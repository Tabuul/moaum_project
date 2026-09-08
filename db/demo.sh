#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
#  Put the invented demo accounts on a database (db/demo.sql).
#
#  Not a migration: migrate.sh never runs this. Run it yourself, once, on a
#  database you mean to demonstrate on — from the Railway shell of the API
#  service:   bash db/demo.sh
#
#  It is idempotent: a second run finds everything already there and
#  changes nothing. Every person it makes is invented (surname DEMO); the
#  password for every account is printed at the end.
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is not set — Railway provides it when the Postgres service is attached to this one}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "── MOAUMPP demo accounts ──────────────────────────────────────"
echo "   Invented people go on the register of this database. Do not run"
echo "   this against the University's live data."
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q --no-psqlrc -f "$HERE/demo.sql"
echo "── done. See docs/demo-accounts.md for the table of accounts."
