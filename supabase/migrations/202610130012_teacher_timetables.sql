begin;
create function school_private.chat_audience_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (school_private.community_developer() or
 (not exists(select 1 from public.school_members where user_id=auth.uid() and active and role in ('teacher','principal'))
 and not exists(select 1 from public.community_profiles where user_id=auth.uid() and audience='parent')));
$$;
create or replace function school_private.community_room_access(p_room uuid) returns boolean language sql stable security definer set search_path='' as $$
 select school_private.chat_audience_allowed() and school_private.community_verified() and exists(select 1 from public.community_rooms r where r.id=p_room and r.status='approved' and not r.channel_archived and
 ((r.kind='class' and school_private.community_class_access(r.class_group))
 or (r.kind='school' and school_private.school_space_access())
 or (r.kind in ('dm','group') and exists(select 1 from public.community_room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.consent='accepted'))));
$$;
create or replace function school_private.school_space_access() returns boolean language sql stable security definer set search_path='' as $$
 select school_private.chat_audience_allowed() and school_private.community_verified() and exists(select 1 from public.community_profiles p where p.user_id=auth.uid() and p.space_onboarded)
 and not exists(select 1 from public.school_space_roles s where s.user_id=auth.uid() and s.kicked);
$$;
revoke all on function school_private.chat_audience_allowed() from public,anon,authenticated;
create table public.teacher_timetable_uploads (
 teacher_id uuid primary key references auth.users(id) on delete cascade,
 image_path text not null,
 status text not null default 'pending' check(status in ('pending','digitized','reupload')),
 uploaded_at timestamptz not null default now(),
 reviewed_at timestamptz,
 review_note text not null default '' check(length(review_note)<=1000)
);
alter table public.teacher_timetable_uploads enable row level security;
revoke all on public.teacher_timetable_uploads from public,anon,authenticated;
grant select on public.teacher_timetable_uploads to authenticated;
create policy teacher_timetables_read on public.teacher_timetable_uploads for select to authenticated using(teacher_id=auth.uid() or school_private.is_leadership());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('teacher-timetables','teacher-timetables',false,10485760,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy teacher_timetable_images_insert on storage.objects for insert to authenticated with check(bucket_id='teacher-timetables' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.school_members where user_id=auth.uid() and active));
create policy teacher_timetable_images_read on storage.objects for select to authenticated using(bucket_id='teacher-timetables' and ((storage.foldername(name))[1]=auth.uid()::text or school_private.is_leadership()));
create function public.submit_teacher_timetable(p_path text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
 if not exists(select 1 from public.school_members where user_id=auth.uid() and active) then raise exception 'Approved staff access required' using errcode='42501'; end if;
 if p_path is null or split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='teacher-timetables' and name=p_path) then raise exception 'Upload your timetable image first' using errcode='22023'; end if;
 insert into public.teacher_timetable_uploads(teacher_id,image_path) values(auth.uid(),p_path) on conflict(teacher_id) do update set image_path=excluded.image_path,status='pending',uploaded_at=now(),reviewed_at=null,review_note=''
 returning to_jsonb(teacher_timetable_uploads.*) into v_result;
 insert into public.school_audit_events(actor,action,details) values(auth.uid(),'teacher.timetable.submit','{}');
 return v_result;
end; $$;
revoke all on function public.submit_teacher_timetable(text) from public,anon;
grant execute on function public.submit_teacher_timetable(text) to authenticated;
notify pgrst,'reload schema';
commit;
