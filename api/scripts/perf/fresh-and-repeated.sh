#!/usr/bin/env bash
# Times one statement N times on fresh connections and N times on one connection, so a slowdown that comes with the connection's
# use (a cached generic plan, or the server process itself) is seen apart from the statement's own cost.
#   bash fresh-and-repeated.sh <database url> "<statement>" [N=4]
# e.g. bash fresh-and-repeated.sh postgres://postgres:postgres@127.0.0.1:54331/copy "SELECT count(*) FROM finance.session_positions('2025/2026', NULL)"
# Read only: the statement runs inside a transaction that is rolled back. Never point it at the live database.
set -u
URL="$1"; Q="$2"; N="${3:-4}"
ms() { grep -oE "^Time: [0-9.]+" | sed 's/Time: //'; }
echo "fresh connections:"
for i in $(seq 1 "$N"); do
  printf 'BEGIN;\n\\timing on\n%s;\nROLLBACK;\n' "$Q" | psql "$URL" -X -q 2>&1 | ms | tail -1 | sed 's/^/  /;s/$/ ms/'
done
echo "one connection, $N times:"
{ printf 'BEGIN;\n\\timing on\n'; for i in $(seq 1 "$N"); do printf '%s;\n' "$Q"; done; printf 'ROLLBACK;\n'; } | psql "$URL" -X -q 2>&1 | ms | sed 's/^/  /;s/$/ ms/'
