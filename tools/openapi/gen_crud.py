#!/usr/bin/env python3
"""Generates one CRUD base class per actor: src/main/java/com/school/app/role/<actor>/<Tag>Crud.java.

Run after gen_openapi.py and `mvn generate-sources` (it reads the generated <Tag>Api interfaces for the exact
method signatures):

    python3 tools/openapi/gen_openapi.py && mvn -q generate-sources && python3 tools/openapi/gen_crud.py

Every operation whose request and response map onto one table (tools/openapi/operations.json + the table
metadata in src/main/resources/schema/tables.json) gets a generic implementation through core.data.Crud:

    GET  .../{id}            -> one row (scoped)
    GET  ...                 -> list or page, query parameters as filters (date/from/to on the date column, q search)
    POST ...                 -> insert; path parameters fill their columns
    POST .../{id}/<action>   -> update the row with the body fields (simple state changes such as respond)
    PUT  .../{id}            -> update the row with the non-null body fields
    PUT  .../{studentId}     -> upsert, for one-per-person tables keyed by that id
    DELETE .../{id}          -> delete the row (scoped)

The rest (screen views, flows, bulk and file operations, and the ops in HAND) stay 501 in the base class: the
actor's controller overrides them. tools/openapi/crud-report.md lists both groups per actor.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OPS = json.load(open(os.path.join(ROOT, "tools/openapi/operations.json")))
TABLES = json.load(open(os.path.join(ROOT, "src/main/resources/schema/tables.json")))
GEN = os.path.join(ROOT, "target/generated-sources/openapi/src/gen/java/com/school/app/role")
OUT = os.path.join(ROOT, "src/main/java/com/school/app/role")

# Operations that fit the generic shapes but need their own logic (status machines, derived fields): built by hand.
HAND = {
    "parent": {"bookPtmSlot", "respondReenrollment"},
    "teacher": {"gradeSubmission"},
}
# Actors whose every row operation is self-service ("my" rows).
SELF_ACTORS = {"staff"}

VIEWS = os.path.join(ROOT, "src/main/resources/views")
ANN = re.compile(r'@[\w.]+(\((?:[^()"]|"[^"]*")*\))?\s*')


def camel(s):
    p = s.split("_")
    return p[0] + "".join(x[:1].upper() + x[1:] for x in p[1:])


def parse_api(path):
    """method name -> {ret, params: [{kind, name (wire), type, var}], status, imports}"""
    src = open(path).read()
    imports = [l for l in src.splitlines() if l.startswith("import ")]
    methods = {}
    for m in re.finditer(r"default (ResponseEntity<.*?>) (\w+)\(\n(.*?)\n    \) \{", src, re.S):
        ret, name, body = m.group(1), m.group(2), m.group(3)
        params = []
        for line in [l.strip() for l in body.split("\n") if l.strip()]:
            line = line.rstrip(",")
            kind = ("header" if "@RequestHeader" in line else "path" if "@PathVariable" in line else
                    "query" if "@RequestParam" in line else "body" if "@RequestBody" in line else
                    "part" if "@RequestPart" in line else "other")
            wire = re.search(r'(?:value = |@PathVariable\()"([^"]+)"', line)
            decl = ANN.sub("", line).strip()
            typ, var = decl.rsplit(" ", 1)
            params.append({"kind": kind, "name": wire.group(1) if wire else var, "type": typ, "var": var})
        doc = src[:m.start()].rsplit("/**", 1)[-1]
        st = re.search(r"@return \w[^(]*\(status code (\d+)\)", doc)
        methods[name] = {"ret": ret, "params": params, "status": int(st.group(1)) if st else 200}
    return imports, methods


def view_names(actor):
    """operationId -> True when the block is marked write, from src/main/resources/views/<actor>.sql"""
    path = os.path.join(VIEWS, f"{actor}.sql")
    if not os.path.exists(path):
        return {}
    return {m.group(1): bool(m.group(2)) for m in re.finditer(r"^--\s*name:\s*(\w+)(\s+write)?\s*$", open(path).read(), re.M)}


def view_call(op, sig, write):
    inner = re.match(r"ResponseEntity<(.*)>$", sig["ret"]).group(1)
    st = sig["status"]
    names = [p for p in sig["params"] if p["kind"] in ("path", "query")]
    params = "Crud.keys(" + ", ".join(f'"{p["name"]}", {p["var"]}' for p in names) + ")"
    body = next((p["var"] for p in sig["params"] if p["kind"] == "body"), None)
    if write or op["method"] != "get":
        cls = "Void" if inner == "Void" else re.sub(r"^List<.*>$", "List", inner)
        call = f'views.write(ACTOR, "{op["opId"]}", {cls}.class, {params}, {body or "null"})'
        if inner == "Void":
            return f"{call};\n        return ResponseEntity.status({st}).build();"
        return f"return ResponseEntity.status({st}).body({call});"
    m = re.match(r"^List<(.*)>$", inner)
    if m:
        return f'return ResponseEntity.status({st}).body(views.list(ACTOR, "{op["opId"]}", {m.group(1)}.class, {params}));'
    return f'return ResponseEntity.status({st}).body(views.one(ACTOR, "{op["opId"]}", {inner}.class, {params}));'


def table_by_pk(param):
    """The table whose primary key is this path parameter, when exactly one table has it."""
    found = [name for name, t in TABLES.items() if t["pk"] and camel(t["pk"]) == param]
    return found[0] if len(found) == 1 else None


def plan(actor, op, siblings):
    """Returns (shape, table, keys, fixed) or (None, reason)."""
    if op["opId"] in HAND.get(actor, set()):
        return None, "hand-built (own logic)"
    if op["binary"] or op["multipart"]:
        return None, "file transfer"
    if op["bodyKind"] == "array":
        return None, "bulk body"
    method = op["method"]
    table = op["respTable"]
    if method == "delete" and not table:
        table = next((s["respTable"] for s in siblings if s["path"] == op["path"] and s["respTable"]), None) \
            or (table_by_pk(op["pathParams"][-1]) if op["pathParams"] else None)
    if not table:
        return None, "screen view or flow"
    t = TABLES[table]
    cols = {c["camel"] for c in t["columns"]}
    pk = camel(t["pk"]) if t["pk"] else None
    pkc = [camel(c) for c in t["pkc"]]
    keys = []  # (field, java var source = path param name)
    params = op["pathParams"]
    for i, p in enumerate(params):
        if p in cols:
            keys.append((p, p))
        elif i == len(params) - 1 and pk:
            keys.append((pk, p))
        else:
            return None, f"path parameter {p} is not a column of {table}"
    fields = set(keys and [k for k, _ in keys])
    targets_row = (pk is not None and pk in fields) or (pk is None and pkc and set(pkc) <= fields)
    body_fields = op["bodyFields"] or []
    body_ok = all(f in cols for f in body_fields)

    if method == "get":
        if op["respKind"] == "one":
            return ("one", table, keys), None
        if op["respKind"] == "array":
            return ("list", table, keys), None
        if op["respKind"] == "page":
            return ("page", table, keys), None
        return None, "no response body"
    if method == "delete":
        if not targets_row:
            return None, "delete without the row key"
        return ("delete", table, keys), None
    if op["respKind"] != "one":
        return None, "response is not one row"
    if method == "put":
        if not op["body"]:
            return None, "no body"
        if not body_ok:
            return None, "body fields beyond the table: " + ", ".join(f for f in body_fields if f not in cols)
        if targets_row and pk:
            return ("update", table, keys), None
        if targets_row and pk is None:
            return ("upsert", table, keys), None
        return None, "PUT without the row key"
    # post
    if not op["body"]:
        return None, "action without a body (state change)"
    if not body_ok:
        return None, "body fields beyond the table: " + ", ".join(f for f in body_fields if f not in cols)
    if targets_row:
        return ("update", table, keys), None
    if op["respTable"] and op["bodyTable"] and op["bodyTable"] != op["respTable"]:
        return None, "body is another table"
    return ("create", table, keys), None


def java_call(actor, op, sig, shape, table, keys, mine):
    shape_name = shape
    t = TABLES[table]
    pvars = {p["name"]: p["var"] for p in sig["params"] if p["kind"] == "path"}
    qparams = [p for p in sig["params"] if p["kind"] == "query"]
    body = next((p["var"] for p in sig["params"] if p["kind"] == "body"), "null")
    keyexpr = "Crud.keys(" + ", ".join(f'"{f}", {pvars[src]}' for f, src in keys) + ")"
    inner = re.match(r"ResponseEntity<(.*)>$", sig["ret"]).group(1)
    resp = re.sub(r"^List<(.*)>$", r"\1", inner)
    st = sig["status"]

    def ok(expr):
        return f"return ResponseEntity.status({st}).body({expr});"

    if shape_name in ("list", "page"):
        q = ["Query.create()"]
        for p in qparams:
            n, v = p["name"], p["var"]
            if n in ("page", "size"):
                continue
            if n == "date":
                q.append(f".on({v})")
            elif n == "q":
                q.append(f".search({v})")
            elif n in ("from", "to"):
                continue
            else:
                q.append(f'.eq("{n}", {v})')
        names = {p["name"]: p["var"] for p in qparams}
        if "from" in names or "to" in names:
            q.append(f".between({names.get('from', 'null')}, {names.get('to', 'null')})")
        if "page" in names:
            q.append(f".page({names['page']}, {names.get('size', 'null')})")
        qexpr = "".join(q)
        if shape_name == "list":
            return ok(f'crud.list(ACTOR, "{table}", {resp}.class, {mine}, {keyexpr}, {qexpr})')
        return ok(f'crud.page(ACTOR, "{table}", {resp}.class, {op["resp"]}.class, {mine}, {keyexpr}, {qexpr})')
    if shape_name == "one":
        return ok(f'crud.one(ACTOR, "{table}", {resp}.class, {mine}, {keyexpr})')
    if shape_name == "create":
        return ok(f'crud.create(ACTOR, "{table}", {resp}.class, {mine}, {body}, {keyexpr})')
    if shape_name == "update":
        return ok(f'crud.update(ACTOR, "{table}", {resp}.class, {mine}, {keyexpr}, {body})')
    if shape_name == "upsert":
        return ok(f'crud.upsert(ACTOR, "{table}", {resp}.class, {body}, {keyexpr})')
    if shape_name == "delete":
        return f'crud.delete(ACTOR, "{table}", {mine}, {keyexpr});\n        return ResponseEntity.status({st}).build();'
    raise ValueError(shape_name)


def main():
    report = ["# Generic CRUD coverage", "",
              "Generated by tools/openapi/gen_crud.py. **Generic**: served by <Tag>Crud through core.data.Crud. "
              "**Screen query**: one SQL statement in src/main/resources/views/<actor>.sql. **Custom**: answers 501 in the base class; the actor's controller overrides it.", ""]
    total_g = total_c = total_v = 0
    for actor, spec in OPS.items():
        tag = spec["tag"]
        api_path = os.path.join(GEN, actor, "api", f"{tag}Api.java")
        if not os.path.exists(api_path):
            sys.exit(f"missing {api_path}: run mvn generate-sources first")
        imports, methods = parse_api(api_path)
        body = []
        generic, custom, viewed = [], [], []
        vnames = view_names(actor)
        unknown = set(vnames) - {op["opId"] for op in spec["ops"]}
        if unknown:
            sys.exit(f"views/{actor}.sql has queries for unknown operations: {sorted(unknown)}")
        for op in spec["ops"]:
            sig = methods[op["opId"]]
            if op["opId"] in vnames:
                params = ", ".join(f'{p["type"]} {p["var"]}' for p in sig["params"])
                body.append(f"""    /** {op['method'].upper()} {op['path']}: views/{actor}.sql. */
    @Override
    public {sig['ret']} {op['opId']}({params}) {{
        {view_call(op, sig, vnames[op['opId']])}
    }}
""")
                viewed.append(op)
                continue
            planned, reason = plan(actor, op, spec["ops"])
            if not planned:
                custom.append((op, reason))
                continue
            shape, table, keys = planned
            mine = "true" if (actor in SELF_ACTORS or op["path"].startswith("/me") or
                              re.match(r"(list|get)My", op["opId"])) else "false"
            params = ", ".join(f'{p["type"]} {p["var"]}' for p in sig["params"])
            body.append(f"""    /** {op['method'].upper()} {op['path']}: {shape} {table}. */
    @Override
    public {sig['ret']} {op['opId']}({params}) {{
        {java_call(actor, op, sig, shape, table, keys, mine)}
    }}
""")
            generic.append((op, f"{shape} `{table}`"))
        imp = sorted(set(imports) | {
            "import com.school.app.core.data.Crud;", "import com.school.app.core.data.Query;",
            "import com.school.app.core.data.Views;",
            "import org.springframework.beans.factory.annotation.Autowired;",
            f"import com.school.app.role.{actor}.api.{tag}Api;"})
        src = f"""package com.school.app.role.{actor};

{chr(10).join(imp)}

/**
 * GENERATED by tools/openapi/gen_crud.py from openapi/{actor}.yaml and the ER v5 table metadata: do not edit.
 *
 * <p>Generic CRUD for the {len(generic)} {tag} operations that map onto one table, scoped to what the actor may
 * see (core.data.ScopeService); {len(viewed)} screen operations run their query in views/{actor}.sql
 * (core.data.Views). The other {len(custom)} operations answer 501 here until {tag}Controller overrides them
 * (flows: notifications, reminders, approval routing, payments, files). See tools/openapi/crud-report.md.
 */
@SuppressWarnings("unused")
public abstract class {tag}Crud implements {tag}Api {{

    protected static final String ACTOR = "{actor}";

    @Autowired
    protected Crud crud;

    @Autowired
    protected Views views;

{chr(10).join(body)}}}
"""
        open(os.path.join(OUT, actor, f"{tag}Crud.java"), "w").write(src)
        report += [f"## {tag} ({actor}) — {len(generic)} generic, {len(viewed)} screen queries, {len(custom)} custom", "",
                   "| Method | Path | Operation | Served by |", "|---|---|---|---|"]
        for op, how in generic:
            report.append(f"| {op['method'].upper()} | `{op['path']}` | {op['opId']} | generic: {how} |")
        for op in viewed:
            report.append(f"| {op['method'].upper()} | `{op['path']}` | {op['opId']} | screen query: views/{actor}.sql |")
        for op, why in custom:
            report.append(f"| {op['method'].upper()} | `{op['path']}` | {op['opId']} | custom: {why} |")
        report.append("")
        total_v += len(viewed)
        total_g += len(generic)
        total_c += len(custom)
    report.insert(4, f"Totals: {total_g} generic, {total_v} screen queries, {total_c} custom.\n")
    open(os.path.join(ROOT, "tools/openapi/crud-report.md"), "w").write("\n".join(report))
    print(f"generic {total_g}, screen queries {total_v}, custom {total_c}")


if __name__ == "__main__":
    main()
