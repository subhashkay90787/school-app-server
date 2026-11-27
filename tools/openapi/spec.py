"""Building blocks for the school-app-server OpenAPI specs (see gen_openapi.py).

Entity schemas come from tools/er_v5_school.dsl (same source as the database), so request/response bodies
stay in step with the tables. View models (screens: home cards, registers, boards ...) are declared in
views.py. Every operation carries x-access (feature + permissions) which the generated Java interfaces turn
into an @Access annotation enforced by platform-core.
"""
import re
import sys
from collections import OrderedDict

sys.path.insert(0, __file__.rsplit("/", 2)[0])
from er2sql import parse  # noqa: E402

PROBLEM_RESPONSES = {
    "400": "Validation failed or the request breaks a rule",
    "401": "Missing or invalid access token",
    "403": "No access: wrong role for this module, feature off for the branch, missing permission, or consent pending",
    "404": "Not found in this branch (or not visible to you)",
    "409": "Conflicts with current state (e.g. already approved, ledger rule, duplicate)",
}


def camel(name):
    head, *rest = name.split("_")
    return head + "".join(p[:1].upper() + p[1:] for p in rest)


def pascal(name):
    return "".join(p[:1].upper() + p[1:] for p in name.split("_"))


TYPE_SCHEMA = {
    "i": {"type": "integer", "format": "int32"},
    "b": {"type": "integer", "format": "int64"},
    "s": {"type": "string"},
    "d": {"type": "string", "format": "date"},
    "dt": {"type": "string", "format": "date-time"},
    "tm": {"type": "string", "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$", "example": "08:30"},
    "n": {"type": "number"},
    "f": {"type": "number", "format": "double"},
    "bo": {"type": "boolean"},
    "j": {"type": "object", "additionalProperties": True},
    "a": {"type": "array", "items": {"type": "string"}},
    "u": {"type": "string", "format": "uuid"},
}

SERVER_SET = {"created_at", "status"}


class Registry:
    """All component schemas; specs pull in only what they reference (transitively)."""

    def __init__(self, dsl_path):
        self.tables = parse(dsl_path)
        self.schemas = OrderedDict()
        names = {}
        for t in self.tables.values():
            names.setdefault(pascal(t.short), []).append(t.name)
        self.entity_name = {}
        for base, tabs in names.items():
            for tn in tabs:
                s, short = tn.split(".")
                self.entity_name[tn] = base if len(tabs) == 1 else pascal(s) + pascal(short)
        self._build_common()

    # ---------------------------------------------------------------- entities
    def entity(self, table):
        name = self.entity_name[table]
        if name not in self.schemas:
            t = self.tables[table]
            props = OrderedDict()
            props["schoolId"] = {"type": "integer", "format": "int64", "readOnly": True,
                                 "description": "Branch (auth school_id)"}
            required = []
            for c in t.columns:
                p = self._col_schema(c)
                if c.pk:
                    p["readOnly"] = True
                props[camel(c.name)] = p
                if c.pk or c.pkc or c.nn:
                    required.append(camel(c.name))
            sch = {"type": "object", "description": "Table %s (ER v5)%s" % (t.name, ", addition" if t.added else ""),
                   "properties": props}
            if required:
                sch["required"] = required
            self.schemas[name] = sch
        return ref(name)

    def entity_input(self, table, drop=(), extra=None):
        base = self.entity_name[table]
        name = base + "Input"
        if name not in self.schemas:
            t = self.tables[table]
            props = OrderedDict()
            required = []
            for c in t.columns:
                if c.pk or c.name in SERVER_SET or c.name.endswith("_by_user_id") or c.name in drop:
                    continue
                props[camel(c.name)] = self._col_schema(c)
                if (c.pkc or c.nn) and c.default is None:
                    required.append(camel(c.name))
            for k, v in (extra or {}).items():
                props[k] = v
            sch = {"type": "object", "description": "Create/update body for %s" % t.name, "properties": props}
            if required:
                sch["required"] = required
            self.schemas[name] = sch
        return ref(name)

    @staticmethod
    def _col_schema(c):
        if c.name.endswith("_id") and c.code in ("i", "b"):
            p = dict(TYPE_SCHEMA["b"])
        else:
            p = dict(TYPE_SCHEMA[c.code])
        if c.enum:
            p = {"type": "string", "enum": list(c.enum)}
        if c.fk == "U":
            p["description"] = "Auth user id"
        elif c.fk:
            p["description"] = "-> %s" % c.fk
        return p

    # ---------------------------------------------------------------- view models
    def view(self, name, fields, description=None, required=()):
        if name in self.schemas:
            raise ValueError("duplicate schema " + name)
        props = OrderedDict()
        for k, v in fields.items():
            props[k] = self.field(v)
        sch = {"type": "object", "properties": props}
        if description:
            sch["description"] = description
        if required:
            sch["required"] = list(required)
        self.schemas[name] = sch
        return ref(name)

    def field(self, v):
        """'s' / 'i' / ... | 'Name' (schema ref) | '[x]' array | '{A|B}' enum | 'E:schema.table' entity | dict"""
        if isinstance(v, dict):
            return v
        if v.startswith("[") and v.endswith("]"):
            return {"type": "array", "items": self.field(v[1:-1])}
        if v.startswith("{"):
            return {"type": "string", "enum": v.strip("{}").split("|")}
        if v.startswith("E:"):
            return self.entity(v[2:])
        if v in TYPE_SCHEMA:
            return dict(TYPE_SCHEMA[v])
        if v == "binary":
            return {"type": "string", "format": "binary"}
        return ref(v)

    def page(self, item_ref):
        item = item_ref["$ref"].rsplit("/", 1)[1]
        name = item + "Page"
        if name not in self.schemas:
            self.schemas[name] = {"type": "object", "required": ["items", "page", "size", "total"], "properties": {
                "items": {"type": "array", "items": item_ref},
                "page": {"type": "integer", "format": "int32"},
                "size": {"type": "integer", "format": "int32"},
                "total": {"type": "integer", "format": "int64"}}}
        return ref(name)

    def _build_common(self):
        self.schemas["Problem"] = {"type": "object", "description": "RFC 9457 problem detail", "properties": {
            "type": {"type": "string"}, "title": {"type": "string"}, "status": {"type": "integer", "format": "int32"},
            "detail": {"type": "string"}, "instance": {"type": "string"},
            "code": {"type": "string", "description": "Stable machine code, e.g. FEATURE_OFF, CONSENT_REQUIRED, DUES_HOLD"}}}

    def closure(self, roots):
        """Names of schemas reachable from the given refs."""
        seen, stack = set(), list(roots)
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            for r in re.findall(r"#/components/schemas/([A-Za-z0-9]+)", repr(self.schemas[n])):
                stack.append(r)
        return seen


def ref(name):
    return {"$ref": "#/components/schemas/" + name}


class Actor:
    def __init__(self, key, title, base_roles, description, phase=None):
        self.key, self.title, self.base_roles, self.description, self.phase = key, title, base_roles, description, phase
        self.ops = []

    def op(self, method, path, op_id, summary, resp=None, body=None, feature=None, perms=(), query=(), paged=False,
           status=None, description=None, binary=False, multipart=None, header_school=True, x=None):
        self.ops.append(dict(method=method, path=path, op_id=op_id, summary=summary, resp=resp, body=body,
                             feature=feature, perms=list(perms), query=list(query), paged=paged, status=status,
                             description=description, binary=binary, multipart=multipart,
                             header_school=header_school, x=x or {}))
        return self

    def get(self, path, op_id, summary, resp=None, **kw):
        return self.op("get", path, op_id, summary, resp, **kw)

    def post(self, path, op_id, summary, resp=None, body=None, **kw):
        return self.op("post", path, op_id, summary, resp, body=body, **kw)

    def put(self, path, op_id, summary, resp=None, body=None, **kw):
        return self.op("put", path, op_id, summary, resp, body=body, **kw)

    def patch(self, path, op_id, summary, resp=None, body=None, **kw):
        return self.op("patch", path, op_id, summary, resp, body=body, **kw)

    def delete(self, path, op_id, summary, resp=None, **kw):
        return self.op("delete", path, op_id, summary, resp, **kw)


QTYPES = {"s": {"type": "string"}, "i": {"type": "integer", "format": "int32"},
          "b": {"type": "integer", "format": "int64"}, "d": {"type": "string", "format": "date"},
          "dt": {"type": "string", "format": "date-time"}, "bo": {"type": "boolean"}}


def build_spec(reg, actors, title, version, description, servers_path, prefix_ids=False):
    paths = OrderedDict()
    roots = {"Problem"}
    tags = []
    for a in actors:
        tags.append({"name": a.title, "description": a.description + (" (%s)" % a.phase if a.phase else ""),
                     "x-base-roles": a.base_roles})
        base = "/api/v1/" + a.key
        for o in a.ops:
            full = base + o["path"]
            item = paths.setdefault(full, OrderedDict())
            if o["method"] in item:
                raise ValueError("duplicate %s %s" % (o["method"], full))
            params = []
            for pp in re.findall(r"\{([A-Za-z]+)\}", o["path"]):
                schema = {"type": "integer", "format": "int64"} if (pp.endswith("Id") or pp == "id") else {"type": "string"}
                params.append({"name": pp, "in": "path", "required": True, "schema": schema})
            if o["header_school"]:
                params.append({"$ref": "#/components/parameters/SchoolId"})
            if o["method"] in ("post", "put", "patch"):
                params.append({"$ref": "#/components/parameters/IdempotencyKey"})
            for qd in o["query"]:
                n, t = qd[0], qd[1]
                p = {"name": n, "in": "query", "required": False}
                if t.startswith("{"):
                    p["schema"] = {"type": "string", "enum": t.strip("{}").split("|")}
                elif t.startswith("["):
                    p["schema"] = {"type": "array", "items": QTYPES[t[1:-1]]}
                    p["explode"] = False
                else:
                    p["schema"] = dict(QTYPES[t])
                if len(qd) > 2:
                    p["description"] = qd[2]
                params.append(p)
            if o["paged"]:
                params += [{"$ref": "#/components/parameters/Page"}, {"$ref": "#/components/parameters/Size"}]
            op = OrderedDict()
            op["tags"] = [a.title]
            op["operationId"] = (a.key + o["op_id"][:1].upper() + o["op_id"][1:]) if prefix_ids else o["op_id"]
            op["summary"] = o["summary"]
            if o["description"]:
                op["description"] = o["description"]
            op["parameters"] = params
            if o["multipart"]:
                op["requestBody"] = {"required": True, "content": {"multipart/form-data": {"schema": o["multipart"]}}}
            elif o["body"] is not None:
                op["requestBody"] = {"required": True, "content": {"application/json": {"schema": o["body"]}}}
                roots |= set(re.findall(r"schemas/([A-Za-z0-9]+)", repr(o["body"])))
            if o["multipart"]:
                roots |= set(re.findall(r"schemas/([A-Za-z0-9]+)", repr(o["multipart"])))
            ok = o["status"] or ("201" if o["method"] == "post" and o["resp"] is not None and o["op_id"].startswith("create") else
                                 "204" if o["resp"] is None and not o["binary"] else "200")
            responses = OrderedDict()
            if o["binary"]:
                responses["200"] = {"description": "File", "content": {"application/pdf": {"schema": {"type": "string", "format": "binary"}},
                                                                       "application/octet-stream": {"schema": {"type": "string", "format": "binary"}}}}
            elif o["resp"] is None:
                responses[ok] = {"description": "Done"}
            else:
                r = o["resp"]
                if o["paged"]:
                    r = reg.page(r)
                responses[ok] = {"description": "OK", "content": {"application/json": {"schema": r}}}
                roots |= set(re.findall(r"schemas/([A-Za-z0-9]+)", repr(r)))
            for code in PROBLEM_RESPONSES:
                responses[code] = {"$ref": "#/components/responses/E%s" % code}
            op["responses"] = responses
            op["security"] = [{"bearerAuth": []}]
            access = {}
            if o["feature"]:
                access["feature"] = o["feature"]
            if o["perms"]:
                access["anyOf"] = o["perms"]
            op["x-access"] = access or {"feature": None, "anyOf": []}
            op["x-base-roles"] = a.base_roles
            ann_parts = []
            if o["feature"]:
                ann_parts.append('feature = "%s"' % o["feature"])
            if o["perms"]:
                ann_parts.append("anyOf = {%s}" % ", ".join('"%s"' % p for p in o["perms"]))
            if ann_parts:
                op["x-operation-extra-annotation"] = "@com.school.app.core.access.Access(%s)" % ", ".join(ann_parts)
            for k, v in o["x"].items():
                op[k] = v
            item[o["method"]] = op

    names = reg.closure(roots)
    schemas = OrderedDict((n, reg.schemas[n]) for n in sorted(names))
    spec = OrderedDict()
    spec["openapi"] = "3.0.3"
    spec["info"] = {"title": title, "version": version, "description": description}
    spec["servers"] = [{"url": servers_path, "description": "School app server (hosted or self-hosted)"}]
    spec["tags"] = tags
    spec["paths"] = paths
    spec["components"] = {
        "securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT",
                                           "description": "Access token from school-auth (OTP or social sign-in). "
                                                          "Claims used: user_id, school_access[].{school_id, roles, base_roles, permissions, enabled_features}."}},
        "parameters": {
            "SchoolId": {"name": "X-School-Id", "in": "header", "required": True,
                         "description": "Branch to act in; must be in the token's school_access",
                         "schema": {"type": "integer", "format": "int64"}},
            "IdempotencyKey": {"name": "Idempotency-Key", "in": "header", "required": False,
                               "description": "Client-generated UUID; repeats within 24 h return the first response (offline queues)",
                               "schema": {"type": "string", "format": "uuid"}},
            "Page": {"name": "page", "in": "query", "required": False, "schema": {"type": "integer", "format": "int32", "default": 0, "minimum": 0}},
            "Size": {"name": "size", "in": "query", "required": False, "schema": {"type": "integer", "format": "int32", "default": 50, "minimum": 1, "maximum": 200}},
        },
        "responses": {"E" + c: {"description": d, "content": {"application/problem+json": {"schema": ref("Problem")}, "application/json": {"schema": ref("Problem")}}}
                      for c, d in PROBLEM_RESPONSES.items()},
        "schemas": schemas,
    }
    return spec
