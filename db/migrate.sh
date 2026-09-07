#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════
#  Apply the MOAUMPP migrations, once each, in order.
#
#  ── Why a ledger and not "just run them all" ───────────────────────────
#  Most of these files are re-runnable and some are not, and which is
#  which is not something anybody should have to remember at three in the
#  morning. Every file that has been applied is recorded with the SHA-256
#  of its contents, and:
#
#    · a file already applied unchanged is SKIPPED
#    · a file never applied is applied, in its own transaction
#    · a file applied before whose CONTENTS HAVE CHANGED stops the
#      deployment, by name
#
#  That last one is the point. A migration edited after it has been
#  applied leaves production and the repository describing two different
#  databases, and nothing anywhere says so. Correct it with a NEW file.
#
#  ── It does not run check.sql ──────────────────────────────────────────
#  check.sql creates people, policies and credentials and deliberately
#  tampers with an audit row. It belongs in CI, against a throwaway
#  database, and never against the University's data. What runs here
#  afterwards is verify.sql, which only reads.
# ════════════════════════════════════════════════════════════════════════
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is not set — Railway provides it when the Postgres service is attached to this one}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q --no-psqlrc)

echo "── MOAUMPP migrations ─────────────────────────────────────────"

"${PSQL[@]}" <<'SQL'
CREATE TABLE IF NOT EXISTS public.schema_migration (
    filename    text PRIMARY KEY,
    sha256      text NOT NULL,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    applied_by  text NOT NULL DEFAULT current_user
);
COMMENT ON TABLE public.schema_migration IS
'What has been applied to this database, and the checksum of the file that '
'was applied. A migration edited after the fact is caught here rather than '
'discovered as a column that does not exist.';
SQL

applied=0
skipped=0

for f in "$HERE"/V*.sql; do
    name="$(basename "$f")"
    sha="$(sha256sum "$f" | cut -d' ' -f1)"
    seen="$("${PSQL[@]}" -tAc "SELECT sha256 FROM public.schema_migration WHERE filename = '$name'")"

    if [ -n "$seen" ]; then
        if [ "$seen" != "$sha" ]; then
            echo
            echo "!! $name has been applied to this database already, and the file has"
            echo "   since CHANGED."
            echo "     applied: $seen"
            echo "     on disk: $sha"
            echo
            echo "   The deployment is stopped. Applying it again would run different"
            echo "   statements from the ones this database was built with, and nothing"
            echo "   afterwards would say so. Put the correction in a NEW migration file."
            exit 1
        fi
        skipped=$((skipped + 1))
        continue
    fi

    echo "   applying $name"
    "${PSQL[@]}" -f "$f"
    "${PSQL[@]}" -c "INSERT INTO public.schema_migration (filename, sha256) VALUES ('$name', '$sha')"
    applied=$((applied + 1))
done

echo "   $applied applied, $skipped already in place"

if [ -f "$HERE/verify.sql" ]; then
    echo "── verifying ──────────────────────────────────────────────────"
    "${PSQL[@]}" -f "$HERE/verify.sql"
fi

echo "── done ───────────────────────────────────────────────────────"
