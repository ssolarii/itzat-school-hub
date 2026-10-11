-- Trusted Dashboard operation: import verified official 2026 government holidays.
-- Adds an atomic public version; preserves every existing calendar entry.
-- Contains no account creation, membership grant, or credential.
begin;
do $holiday_import$
declare
  v_old jsonb;
  v_document jsonb;
  v_revision bigint;
  v_government jsonb := $government_calendar${"2026-01-01":{"type":"holiday","label":"New Year's Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-01-15":{"type":"holiday","label":"George Price Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-03-09":{"type":"holiday","label":"National Heroes and Benefactor Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-04-03":{"type":"holiday","label":"Good Friday","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-04-04":{"type":"holiday","label":"Holy Saturday","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-04-06":{"type":"holiday","label":"Easter Monday","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-05-01":{"type":"holiday","label":"Labour Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-08-01":{"type":"holiday","label":"Emancipation Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-09-10":{"type":"holiday","label":"St. George's Caye Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-09-21":{"type":"holiday","label":"Independence Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-10-12":{"type":"holiday","label":"Indigenous People's Resistance Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-11-19":{"type":"holiday","label":"Garifuna Settlement Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-12-25":{"type":"holiday","label":"Christmas Day","description":"Government of Belize public and bank holiday (2026 official notice)."},"2026-12-26":{"type":"holiday","label":"Boxing Day","description":"Government of Belize public and bank holiday (2026 official notice)."}}$government_calendar$::jsonb;
begin
  perform pg_advisory_xact_lock(742617092);
  select s.document,s.revision into v_old,v_revision from public.school_versions s order by s.revision desc limit 1;
  if v_old is null then raise exception 'Seed school document before importing holidays'; end if;
  v_document := jsonb_set(v_old,'{calendar}',v_government || (v_old->'calendar'));
  if v_document->'calendar' = v_old->'calendar' then
    raise notice 'Government holiday import skipped: all entries already present';
    return;
  end if;
  perform school_private.validate_school_document(v_document);
  insert into public.school_versions(document) values(v_document);
  insert into public.school_audit_events(action,details) values('calendar.govimport',jsonb_build_object(
    'previousRevision',v_revision,'year',2026,'source','https://www.pressoffice.gov.bz/wp-content/uploads/2025/11/Nov-6-PR218-25-Public-and-Bank-Holidays-2026.pdf',
    'release','PR#218-25','verifiedAt','2026-10-10','candidateCount',14));
end;
$holiday_import$;
commit;
select revision,document->'calendar' as imported_calendar from public.school_versions order by revision desc limit 1;
