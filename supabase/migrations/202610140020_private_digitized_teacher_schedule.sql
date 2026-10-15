begin;
-- Digitized teacher duties remain under the existing uploader/leadership RLS.
create function school_private.valid_teacher_schedule(p_schedule jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare v_entry jsonb; v_group jsonb;
begin
 if p_schedule is null then return true; end if;
 if jsonb_typeof(p_schedule) is distinct from 'object' or p_schedule->>'version' is distinct from '1' or jsonb_typeof(p_schedule->'entries') is distinct from 'array' then return false; end if;
 if jsonb_array_length(p_schedule->'entries')>60 then return false; end if;
 for v_entry in select value from jsonb_array_elements(p_schedule->'entries') loop
  if jsonb_typeof(v_entry) is distinct from 'object' or jsonb_typeof(v_entry->'day') is distinct from 'number' or jsonb_typeof(v_entry->'session') is distinct from 'number' or coalesce(v_entry->>'day','') !~ '^[1-7]$' or coalesce(v_entry->>'session','') !~ '^[1-6]$' or coalesce(v_entry->>'span','1') !~ '^[1-6]$' then return false; end if;
  if jsonb_typeof(v_entry->'subject') is distinct from 'string' or (v_entry->>'session')::int+coalesce((v_entry->>'span')::int,1)>7 or length(coalesce(v_entry->>'subject','')) not between 1 and 80 or length(coalesce(v_entry->>'room',''))>40 or length(coalesce(v_entry->>'note',''))>240 then return false; end if;
  if jsonb_typeof(v_entry->'groups') is distinct from 'array' or jsonb_array_length(v_entry->'groups')>20 then return false; end if;
  for v_group in select value from jsonb_array_elements(v_entry->'groups') loop if jsonb_typeof(v_group)<>'string' or length(v_group#>>'{}') not between 1 and 30 then return false; end if; end loop;
 end loop;
 return true;
end; $$;
revoke all on function school_private.valid_teacher_schedule(jsonb) from public,anon,authenticated;
alter table public.teacher_timetable_uploads add column digitized_schedule jsonb check(school_private.valid_teacher_schedule(digitized_schedule));
notify pgrst,'reload schema';
commit;
