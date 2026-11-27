#!/usr/bin/env python3
"""One API call as an actor's dev user:  python3 tools/seed/call.py <actor> <METHOD> <path under the actor> [json body]"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import contract_test as ct
actor, method, path = sys.argv[1:4]
body = json.loads(sys.argv[4]) if len(sys.argv) > 4 else None
cache = f"/tmp/run/token-{actor}"
tok = open(cache).read() if os.path.exists(cache) and os.path.getmtime(cache) > __import__("time").time() - 600 else None
if not tok:
    tok = ct.login(ct.USERS[actor]); open(cache, "w").write(tok)
base = next(p for p in ct.ROUTES if p.rstrip("/").endswith("/" + actor))
st, out = ct.http(method, ct.APP + base + path, tok, body=body)
print(st); print(out[:3000])
