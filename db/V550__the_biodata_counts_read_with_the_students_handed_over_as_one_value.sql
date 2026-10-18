-- V550: the biodata counts read with the students handed over as one value.
--
-- PostgreSQL inlines a SQL function that returns rows into the query that calls it only when its arguments hold no subquery;
-- otherwise the function's own statement is planned apart, without the argument's value (PostgreSQL 17 always; 18 from the sixth
-- call on a connection). Every call of a SQL function in the API's statements and in the database's own functions was scanned
-- for a subquery among its arguments (api/scripts/perf/scan-calls.py): 47 calls of 22 functions, 17 of them calls of the 7 that
-- return rows. Each was measured on the live-shaped copy on fresh connections with the students handed over as a value instead
-- (docs/performance-audit.md §Q). Only people.biodata_status_counts (Notification Templates' biodata counts) was faster, 2.1 s
-- → 1.5 s, and it is restated here: the students read first, people.biodata_statuses given them as one value by a one-off
-- plan. For the others the value made no difference (clearance.unit_states, cleared_many — the functions' own reading is the
-- cost) or less than a tenth of a second (clearance.stage_rows, finance.fee_positions_of), and for people.biodata_requirement_impact
-- and people.refresh_biodata_snapshot it was slower (1.3 → 2.3 s, 4.0 → 4.8 s), so they are left as they are. The figures are
-- the same: compared row by row on the copy.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V550: the biodata counts read with the students handed over as one value', true);

CREATE OR REPLACE FUNCTION people.biodata_status_counts()
 RETURNS TABLE(total integer, up_to_date integer, incomplete integer, review_required integer, outdated integer, no_email integer, no_phone integer, migrated integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_ids uuid[];
BEGIN
    -- V550: the students read first and handed to people.biodata_statuses as one value, by a one-off plan: given as a subquery,
    -- the function was not planned with the query that calls it
    v_ids := ARRAY(SELECT s.id FROM people.student s WHERE people.biodata_applicable(s.status));
    RETURN QUERY EXECUTE $q$
    WITH x AS (SELECT * FROM people.biodata_statuses($1))
    SELECT coalesce(cardinality($1), 0),
           count(*) FILTER (WHERE x.status = 'UP_TO_DATE')::int,
           count(*) FILTER (WHERE x.status = 'INCOMPLETE')::int,
           count(*) FILTER (WHERE x.status = 'REVIEW_REQUIRED')::int,
           count(*) FILTER (WHERE x.status = 'OUTDATED')::int,
           (SELECT count(*)::int FROM people.student s CROSS JOIN LATERAL people.student_reach(s.id) r WHERE people.biodata_applicable(s.status) AND nullif(btrim(coalesce(r.email, '')), '') IS NULL),
           (SELECT count(*)::int FROM people.student s CROSS JOIN LATERAL people.student_reach(s.id) r WHERE people.biodata_applicable(s.status) AND nullif(btrim(coalesce(r.phone, '')), '') IS NULL),
           count(*) FILTER (WHERE x.migrated)::int
      FROM x
    $q$ USING v_ids;
END $function$;

COMMENT ON FUNCTION people.biodata_status_counts() IS
  'V426/V550: the live students'' biodata status counts (and those with no e-mail or phone), people.biodata_statuses given the students as one value';

COMMIT;
