# Inventory tools

These scripts regenerate the mechanical parts of the documentation package from the code and a database with every migration applied. They write to `tools/out/`. Run them from anywhere with Python 3.11+; no third-party packages.

1. Dump the database catalogue into `tools/out/` with `psql` against a database that has all migrations applied (any name; `moaumpp` below), one file per query:

```bash
OUT=docs/manual/tools/out; mkdir -p "$OUT"; DB=postgres://postgres@localhost:5433/moaumpp
psql "$DB" -AtF'|' -c "SELECT n.nspname, c.relname, obj_description(c.oid,'pg_class'), (SELECT string_agg(a.attname, ', ' ORDER BY k.n) FROM pg_constraint pk JOIN LATERAL unnest(pk.conkey) WITH ORDINALITY k(attnum,n) ON true JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=k.attnum WHERE pk.conrelid=c.oid AND pk.contype='p'), (SELECT string_agg(DISTINCT confrelid::regclass::text, ', ') FROM pg_constraint f WHERE f.conrelid=c.oid AND f.contype='f'), (SELECT count(*) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped), (SELECT count(*) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal), c.reltuples::bigint FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND n.nspname NOT IN ('pg_catalog','information_schema','public') ORDER BY 1,2" > "$OUT/tables.psv"
psql "$DB" -AtF'|' -c "SELECT table_schema, table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog','information_schema','public') ORDER BY 1,2,ordinal_position" > "$OUT/columns.psv"
psql "$DB" -AtF'|' -c "SELECT n.nspname, p.proname, pg_get_function_arguments(p.oid), pg_get_function_result(p.oid), obj_description(p.oid,'pg_proc') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema','public') ORDER BY 1,2" > "$OUT/functions.psv"
psql "$DB" -AtF'|' -c "SELECT tgrelid::regclass, tgname, pg_get_triggerdef(oid) FROM pg_trigger WHERE NOT tgisinternal ORDER BY 1,2" > "$OUT/triggers.psv"
psql "$DB" -AtF'|' -c "SELECT conrelid::regclass, conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE contype IN ('u','c') AND connamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname IN ('pg_catalog','information_schema','public')) ORDER BY 1,2" > "$OUT/constraints.psv"
psql "$DB" -AtF'|' -c "SELECT schemaname||'.'||tablename, indexname, indexdef FROM pg_indexes WHERE schemaname NOT IN ('pg_catalog','information_schema','public') ORDER BY 1,2" > "$OUT/indexes.psv"
psql "$DB" -AtF'|' -c "SELECT * FROM ref.office ORDER BY 1" > "$OUT/offices.psv"
```

2. `python docs/manual/tools/parse_api.py` — every HTTP endpoint with its guard (`out/api.md`, `out/api.json`).
3. `python docs/manual/tools/parse_front.py` — menus, routes, pages and the API calls each page makes (`out/menus.md`, `out/routes.md`, `out/routes.json`).
4. `python docs/manual/tools/gen_refs.py` — the permission matrix, the API catalogue and the database catalogue (`out/generated/*.md`), which volumes 04, 07 and 08 embed.

The narrative volumes were written from module audits (`docs/manual/audit/`) that cite the code by file and line; when the code changes, re-run the tools, diff the generated files against the embedded copies, and revise the affected sections.
