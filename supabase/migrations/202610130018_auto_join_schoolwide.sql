begin;

update public.school_space_server set join_policy='verified' where id;

-- Schoolwide Chat no longer has a separate admission step. A verified, admitted
-- community profile is a member unless the Developer has removed that account.
create or replace function school_private.school_space_access() returns boolean language sql stable security definer set search_path='' as $$
 select school_private.chat_audience_allowed() and school_private.community_verified()
 and exists(select 1 from public.community_profiles p where p.user_id=auth.uid())
 and not exists(select 1 from public.school_space_roles s where s.user_id=auth.uid() and s.kicked);
$$;

-- Membership is automatic, while posting waits for the first-entry interests.
create or replace function school_private.channel_can_speak(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_room_access(p_room) and exists(select 1 from public.community_rooms r where r.id=p_room and
 (r.kind<>'school' or (
  exists(select 1 from public.community_profiles p where p.user_id=auth.uid() and p.space_onboarded and cardinality(p.cosmetic_roles)>0)
  and (school_private.community_developer() or
   case when r.speaking_roles is not null then school_private.school_space_role(auth.uid())=any(r.speaking_roles)
   else r.posting_policy='members' or school_private.school_space_permission('manage_messages') end))));
$$;

create or replace function public.school_space_members() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not school_private.school_space_access() then raise exception 'Schoolwide Chat is unavailable for this account' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(school_private.community_visible_identity(p.user_id)||jsonb_build_object('authority_role',school_private.school_space_role(p.user_id),'online',coalesce(pr.last_seen>now()-interval '90 seconds',false)) order by p.user_id)
 from public.community_profiles p left join public.school_space_presence pr on pr.user_id=p.user_id
 where school_private.community_admitted(p.user_id)
 and (p.audience='student' and not exists(select 1 from public.school_members m where m.user_id=p.user_id and m.active and m.role in ('teacher','principal'))
      or exists(select 1 from public.school_members m where m.user_id=p.user_id and m.active and m.role='developer'))
 and not exists(select 1 from public.school_space_roles s where s.user_id=p.user_id and s.kicked)
 and not school_private.community_pair_blocked(auth.uid(),p.user_id)),'[]');
end; $$;

-- New accounts open this channel on their first visit. The unique channel key
-- keeps reruns safe while leaving an existing Developer-edited channel intact.
insert into public.community_rooms(kind,title,status,school_channel,channel_category,description,channel_archived)
values('school','welcome','approved','welcome','Start here','Introduce yourself and find your way around Schoolwide Chat.',false)
on conflict (school_channel) where kind='school' do nothing;

create or replace function school_private.community_profile_access(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.community_verified() and school_private.community_admitted(p_user) and (p_user=auth.uid() or school_private.is_leadership()
 or exists(select 1 from public.community_profiles p where p.user_id=p_user and p.audience='student' and school_private.community_class_access(p.class_group))
 or (not school_private.community_pair_blocked(auth.uid(),p_user) and (
 school_private.community_friend_access(p_user)
 or (school_private.school_space_access() and exists(select 1 from public.community_profiles p where p.user_id=p_user and (p.audience='student' and not exists(select 1 from public.school_members m where m.user_id=p_user and m.active and m.role in ('teacher','principal')) or exists(select 1 from public.school_members m where m.user_id=p_user and m.active and m.role='developer'))) and not exists(select 1 from public.school_space_roles s where s.user_id=p_user and s.kicked))
 or exists(select 1 from public.community_room_members m where m.user_id=p_user and m.consent='accepted' and school_private.community_room_access(m.room_id)))));
$$;

-- Anyone in Schoolwide Chat may submit an emoji. The existing upload checks,
-- rate limit and pending status still apply; only a Developer may approve it.
create or replace function public.school_space_submit_emoji(p_name text,p_media_path text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 if not school_private.school_space_access() then raise exception 'Schoolwide Chat is unavailable for this account' using errcode='42501'; end if;
 if not exists(select 1 from public.community_profiles p where p.user_id=auth.uid() and p.space_onboarded and cardinality(p.cosmetic_roles)>0) then raise exception 'Choose your interests before submitting an emoji' using errcode='42501'; end if;
 v_id:=public.community_submit_emoji(p_name,p_media_path);
 return jsonb_build_object('id',v_id,'pending_review',true);
end; $$;

revoke all on function school_private.school_space_access(),school_private.channel_can_speak(uuid),school_private.community_profile_access(uuid) from public,anon,authenticated;
revoke all on function public.school_space_members() from public,anon;
revoke all on function public.school_space_submit_emoji(text,text) from public,anon;
grant execute on function school_private.school_space_access(),school_private.community_profile_access(uuid),public.school_space_members(),public.school_space_submit_emoji(text,text) to authenticated;

notify pgrst,'reload schema';
commit;
