#!/bin/bash
# backup_db.sh — Snapshot the RouzMe Supabase database to local disk.
#
# Exports every public table (+ the auth users email↔id map) to timestamped
# JSON files under backups/. Uses the service-role key from .env, so it bypasses
# RLS and captures ALL users' data — run it whenever you want a safety copy.
#
#   ./backup_db.sh              # -> backups/rouzme-YYYYMMDD-HHMMSS/
#
# Restore/inspection: the JSON is one file per table (arrays of row objects).
# Requires: python3 (stdlib only), SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in .env.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f .env ]; then
  echo "❌ .env not found (need SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)"; exit 1
fi
set -a; # shellcheck source=/dev/null
source .env; set +a

: "${SUPABASE_URL:?SUPABASE_URL not set in .env}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY not set in .env}"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUTDIR="backups/rouzme-$STAMP"
mkdir -p "$OUTDIR"

echo "📦 Backing up $SUPABASE_URL"
echo "   -> $OUTDIR"

SUPABASE_URL="$SUPABASE_URL" \
SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" \
OUTDIR="$OUTDIR" \
python3 - <<'PY'
import json, os, urllib.request, urllib.error

BASE = os.environ["SUPABASE_URL"].rstrip("/")
KEY  = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
OUT  = os.environ["OUTDIR"]

# Public base tables to snapshot.
TABLES = [
    "Categories", "Tasks", "Icons", "site_parsing_hints",
    "shared_categories", "share_links", "share_link_categories",
    "share_link_invites", "share_invitations", "allowed_senders",
]

def get(url):
    req = urllib.request.Request(url, headers={
        "apikey": KEY, "Authorization": f"Bearer {KEY}", "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

def dump_table(name):
    rows, offset, page = [], 0, 1000
    while True:
        # PostgREST; paginate by offset (Supabase caps a single response).
        chunk = get(f"{BASE}/rest/v1/{name}?select=*&limit={page}&offset={offset}")
        rows.extend(chunk)
        if len(chunk) < page:
            break
        offset += page
    with open(os.path.join(OUT, f"{name}.json"), "w") as f:
        json.dump(rows, f, indent=2, default=str)
    return len(rows)

def dump_auth_users():
    # Admin API: email <-> id map so a restore can reattach owner_id -> person.
    users, page, per = [], 1, 1000
    while True:
        data = get(f"{BASE}/auth/v1/admin/users?page={page}&per_page={per}")
        batch = data.get("users", data if isinstance(data, list) else [])
        if not batch:
            break
        for u in batch:
            users.append({"id": u.get("id"), "email": u.get("email"),
                          "created_at": u.get("created_at"),
                          "confirmed": bool(u.get("email_confirmed_at"))})
        if len(batch) < per:
            break
        page += 1
    with open(os.path.join(OUT, "auth_users.json"), "w") as f:
        json.dump(users, f, indent=2, default=str)
    return len(users)

manifest = {"created_at": os.path.basename(OUT), "counts": {}}
for t in TABLES:
    try:
        n = dump_table(t)
        manifest["counts"][t] = n
        print(f"   ✓ {t}: {n}")
    except urllib.error.HTTPError as e:
        manifest["counts"][t] = f"ERROR {e.code}"
        print(f"   ✗ {t}: HTTP {e.code}")

try:
    n = dump_auth_users()
    manifest["counts"]["auth.users"] = n
    print(f"   ✓ auth.users: {n}")
except Exception as e:
    manifest["counts"]["auth.users"] = f"ERROR {e}"
    print(f"   ✗ auth.users: {e}")

with open(os.path.join(OUT, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)
PY

echo "✅ Backup complete: $OUTDIR"
du -sh "$OUTDIR" 2>/dev/null | awk '{print "   size: "$1}'
