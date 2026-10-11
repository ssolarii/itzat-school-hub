"""Build a non-destructive, transactional seed from the public school document.

Usage: python supabase/generate_seed.py school-data.json
The migration must be installed first. Re-running the seed never replaces live data.
"""
from pathlib import Path
import argparse
import json

parser = argparse.ArgumentParser()
parser.add_argument("document", type=Path)
parser.add_argument("--output", type=Path, default=Path(__file__).with_name("seed.sql"))
args = parser.parse_args()
document = json.loads(args.document.read_text(encoding="utf-8-sig"))
payload = json.dumps(document, ensure_ascii=False, separators=(",", ":"))
delimiter = "$school_seed_document$"
if delimiter in payload:
    raise SystemExit("Reserved SQL seed delimiter occurs in school data")
args.output.write_text(
    "-- Generated from " + args.document.name + "; public school data only.\n"
    "begin;\n"
    "do $seed$\n"
    "declare v_document jsonb := " + delimiter + payload + delimiter + "::jsonb;\n"
    "begin\n"
    "  perform pg_advisory_xact_lock(742617092);\n"
    "  if exists(select 1 from public.school_versions) then\n"
    "    raise notice 'Seed skipped: a published document already exists';\n"
    "    return;\n"
    "  end if;\n"
    "  perform school_private.validate_school_document(v_document);\n"
    "  insert into public.school_versions(document) values(v_document);\n"
    "  insert into public.school_audit_events(action,details) values('school.seed', jsonb_build_object('source','canonical uploaded timetables'));\n"
    "end;\n"
    "$seed$;\ncommit;\n",
    encoding="utf-8",
)
print(f"Wrote {args.output} ({args.output.stat().st_size} bytes)")
