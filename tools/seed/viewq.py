#!/usr/bin/env python3
"""Runs screen queries from src/main/resources/views/<actor>.sql the way core.data.Views does (as the API role,
with the request's RLS settings), inside a rolled-back transaction. For checking SQL while writing it.

    python3 tools/seed/viewq.py <actor> <user_id> [opId|all] [name=value ...]

Parameters not given are NULL; :me and :school are filled in (school 1 unless school=...). Prints the JSON.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def blocks(actor):
    text = open(os.path.join(ROOT, "src/main/resources/views", f"{actor}.sql")).read()
    heads = list(re.finditer(r"^--\s*name:\s*(\w+)(\s+write)?\s*$", text, re.M))
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        yield m.group(1), bool(m.group(2)), text[m.end():end].strip().rstrip(";")


def lit(v):
    return "NULL" if v is None else "'" + str(v).replace("'", "''") + "'"


def run(sql, user, school):
    script = (f"BEGIN;\nSELECT set_config('app.school_ids', '{school}', true), set_config('app.user_id', '{user}', true), "
              f"set_config('app.org_ids', '1', true), set_config('app.rls_bypass', '', true), set_config('TimeZone', 'Asia/Kolkata', true) \\g /dev/null\n"
              f"{sql};\nROLLBACK;\n")
    env = dict(os.environ, PGPASSWORD=os.environ.get("APP_DB_PASSWORD", "api"))
    p = subprocess.run(["psql", "-h", "localhost", "-U", "schoolcrm_api", "-d", "school_app_db", "-AtqX", "-v", "ON_ERROR_STOP=1"],
                       input=script, capture_output=True, text=True, env=env)
    return p.returncode, (p.stdout.strip() or p.stderr.strip())


def main():
    actor, user = sys.argv[1], sys.argv[2]
    which = sys.argv[3] if len(sys.argv) > 3 else "all"
    params = dict(a.split("=", 1) for a in sys.argv[4:])
    school = params.pop("school", "1")
    params.setdefault("me", user)
    params.setdefault("school", school.split(",")[0])
    params.setdefault("body", "{}")
    failed = 0
    for name, write, sql in blocks(actor):
        if which != "all" and name != which:
            continue
        parts = re.split(r"\n--\s*then\s*\n", sql, maxsplit=1)
        if len(parts) == 2:
            # same transaction: keep the first result in a psql variable and use it as :result
            first = re.sub(r"(?<![:\w]):(\w+)", lambda m: lit(params.get(m.group(1))), parts[0].strip().rstrip(";"))
            second = re.sub(r"(?<![:\w]):(\w+)", lambda m: ":'result'" if m.group(1) == "result" else lit(params.get(m.group(1))),
                            parts[1].strip().rstrip(";"))
            bound = f"{first} \\gset\n{second}"
        else:
            bound = re.sub(r"(?<![:\w]):(\w+)", lambda m: lit(params.get(m.group(1))), sql)
        code, out = run(bound, user, school)
        ok = code == 0 and out and out != ""
        if ok:
            try:
                json.loads(out.splitlines()[-1])
            except ValueError:
                ok = False
        if not ok:
            failed += 1
        if which == "all":
            print(("OK  " if ok else "ERR ") + name + ("" if ok else "\n    " + out.replace("\n", "\n    ")))
        else:
            print(json.dumps(json.loads(out.splitlines()[-1]), indent=1) if ok else out)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
