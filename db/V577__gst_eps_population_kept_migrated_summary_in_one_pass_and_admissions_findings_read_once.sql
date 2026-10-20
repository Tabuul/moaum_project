-- V577: slow screens of 19 October 2026 (docs/performance-audit.md §S) taken in turn, each answering as before.
--
--   * The GST and EPS lists, dashboards and the Bursary's GST fee standing read the GST/EPS population — the course engine over
--     the whole register, about 1.7 s on the live-shaped copy — on every open. It is now kept (below).
--   * clearance.migrated_summary (the migrated students cleared at every unit; the API works it out when it starts) crossed every
--     migrated student with every gate purpose and unit (44,497 × 64) and asked the latest decision of each: 25–58 s on the copy.
--     It now reads each pair's latest decision once and counts the CLEARED pairs a student holds against the pairs needed, with
--     the memory to sort them (16–18 s on the copy; the 2.85 million decisions are read either way). The same three figures.
--   * admissions.attachment_state (Candidate data's findings) asked admissions.candidate_is_committed for every file and every
--     candidate: the session's committed numbers are read once (1.3 s to 0.3 s on the copy, the same findings).
-- Each function is restated from its current text with only that change.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'ict', true);
SELECT set_config('moaum.reason', 'V577: the GST/EPS population kept; faster reads, the same answers', true);

-- ── the GST/EPS population kept ────────────────────────────────────────────────────────────────────────────────────────────
-- finance.gst_population reads the GST/EPS course engine over the whole register (V468): about 1.7 s on the live-shaped copy, and
-- the GST office's lists, dashboard, filters and the Bursary's fee page each read it again on every open. It is now kept: worked
-- out once, read from finance.gst_population_kept, worked out again behind the screens once five minutes old (the API), at once
-- when asked (Refresh) or after the GST fee, its setting or a payment review changes (a statement trigger marks it out of date).
-- A student's own GST/EPS standing (the permit, registration, the fee gate) still reads the engine live.
CREATE TABLE finance.gst_population_kept AS
SELECT ''::text AS session, 0::integer AS semester, p.* FROM finance.gst_population(NULL::text, NULL::integer) p WITH NO DATA;
ALTER TABLE finance.gst_population_kept ALTER COLUMN session SET NOT NULL, ALTER COLUMN semester SET NOT NULL,
    ADD PRIMARY KEY (session, semester, student_id);
COMMENT ON TABLE finance.gst_population_kept IS
  'V577: finance.gst_population as last worked out, per session and semester (0: the whole session) — read by the GST/EPS lists and the fee page';

CREATE TABLE finance.gst_population_state (
    session        text NOT NULL,
    semester       integer NOT NULL,
    kept_at        timestamptz NOT NULL,
    millis         integer NOT NULL DEFAULT 0,
    rows_kept      integer NOT NULL DEFAULT 0,
    invalid        boolean NOT NULL DEFAULT false,
    invalidated_at timestamptz,
    PRIMARY KEY (session, semester)
);
COMMENT ON TABLE finance.gst_population_state IS
  'V577: when each kept GST/EPS population was worked out, and whether a change to the GST fee, its setting or a review has made it out of date';
SELECT audit.exempt('finance.gst_population_kept', 'a copy of finance.gst_population worked out again from the record it reads; no person writes it, and every change it reflects is audited where it was made');
SELECT audit.exempt('finance.gst_population_state', 'when the kept GST/EPS population was worked out; written by the keeping alone');

-- worked out again for a session and semester, one at a time: behind the screens a second is answered -1 at once; a reader that
-- must have it (p_wait) waits for the first and takes what it kept (0)
CREATE FUNCTION finance.keep_gst_population(p_session text, p_semester integer, p_wait boolean DEFAULT false)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_sem integer := coalesce(p_semester, 0); t0 timestamptz := clock_timestamp(); n integer;
BEGIN
    IF p_session IS NULL THEN
        RAISE EXCEPTION 'GST_KEEP_SESSION: a session is named' USING ERRCODE = '23514';
    END IF;
    IF NOT pg_try_advisory_xact_lock(hashtext('finance.gst_population'), hashtext(p_session || ':' || v_sem)) THEN
        IF NOT p_wait THEN
            RETURN -1;
        END IF;
        PERFORM pg_advisory_xact_lock(hashtext('finance.gst_population'), hashtext(p_session || ':' || v_sem));
        IF EXISTS (SELECT 1 FROM finance.gst_population_state st
                    WHERE st.session = p_session AND st.semester = v_sem AND NOT st.invalid AND st.kept_at >= t0 - interval '1 minute') THEN
            RETURN 0;
        END IF;
        t0 := clock_timestamp();
    END IF;
    DELETE FROM finance.gst_population_kept k WHERE k.session = p_session AND k.semester = v_sem;
    INSERT INTO finance.gst_population_kept SELECT p_session, v_sem, p.* FROM finance.gst_population(p_session, p_semester) p;
    GET DIAGNOSTICS n = ROW_COUNT;
    INSERT INTO finance.gst_population_state AS st (session, semester, kept_at, millis, rows_kept, invalid)
    VALUES (p_session, v_sem, t0, (extract(epoch FROM clock_timestamp() - t0) * 1000)::integer, n, false)
    ON CONFLICT (session, semester) DO UPDATE
       SET kept_at = EXCLUDED.kept_at, millis = EXCLUDED.millis, rows_kept = EXCLUDED.rows_kept,
           -- a change made while it was being worked out keeps it out of date
           invalid = st.invalidated_at IS NOT NULL AND st.invalidated_at > t0;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION finance.keep_gst_population(text, integer, boolean) IS
  'V577: finance.gst_population worked out again and kept for a session and semester; -1 when another is working it out';

-- the kept population, read as finance.gst_population is
CREATE FUNCTION finance.gst_population_kept_of(p_session text, p_semester integer)
RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text, programme_code text, programme text, level integer, status text, entry_mode text, required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamp with time zone, gst_registered boolean, eps_registered boolean, gst_courses integer, eps_courses integer, registered_at timestamp with time zone, pay_source text, gst_required boolean, eps_required boolean, gst_reason text, eps_reason text, gst_carryover boolean, eps_carryover boolean, gst_completed boolean, eps_completed boolean, gst_owed text, eps_owed text, review boolean)
LANGUAGE sql STABLE AS $fn$
    SELECT k.student_id, k.number, k.surname, k.other_names, k.sex, k.faculty_code, k.faculty, k.dept_code, k.department, k.programme_code, k.programme, k.level, k.status, k.entry_mode, k.required, k.fee, k.stated, k.paid, k.entitled, k.pay_state, k.reference, k.paid_at, k.gst_registered, k.eps_registered, k.gst_courses, k.eps_courses, k.registered_at, k.pay_source, k.gst_required, k.eps_required, k.gst_reason, k.eps_reason, k.gst_carryover, k.eps_carryover, k.gst_completed, k.eps_completed, k.gst_owed, k.eps_owed, k.review
      FROM finance.gst_population_kept k
     WHERE k.session = p_session AND k.semester = coalesce(p_semester, 0)
$fn$;
COMMENT ON FUNCTION finance.gst_population_kept_of(text, integer) IS
  'V577: the kept GST/EPS population of a session and semester, with finance.gst_population''s columns';

-- a change to the GST fee, its setting or a payment review: every kept population out of date (worked out at its next read)
CREATE FUNCTION finance.gst_population_invalidate()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE finance.gst_population_state SET invalid = true, invalidated_at = clock_timestamp();
    RETURN NULL;
END $fn$;
CREATE TRIGGER trg_gst_fee_population AFTER INSERT OR UPDATE OR DELETE ON finance.gst_fee
    FOR EACH STATEMENT EXECUTE FUNCTION finance.gst_population_invalidate();
CREATE TRIGGER trg_gst_setting_population AFTER INSERT OR UPDATE OR DELETE ON finance.gst_setting
    FOR EACH STATEMENT EXECUTE FUNCTION finance.gst_population_invalidate();
CREATE TRIGGER trg_gst_review_population AFTER INSERT OR UPDATE OR DELETE ON finance.gst_payment_review
    FOR EACH STATEMENT EXECUTE FUNCTION finance.gst_population_invalidate();

-- ── the migrated students cleared, counted once a student ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION clearance.migrated_summary(p_from integer DEFAULT 100, p_to integer DEFAULT 400)
 RETURNS TABLE(migrated bigint, cleared bigint, uncleared bigint)
 LANGUAGE sql
 STABLE
 SET work_mem TO '256MB'
AS $function$
    -- V577: a student stands cleared when every gate purpose at every unit reads CLEARED at its latest decision — counted once a
    -- student (the CLEARED pairs against the pairs needed), not by crossing every student with every purpose and unit
    WITH m AS MATERIALIZED (
        SELECT s.id FROM people.student s
         WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
           AND s.current_level BETWEEN p_from AND p_to
           AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
    ),
    need AS MATERIALIZED (
        SELECT pu.code AS purpose, u.code AS unit FROM ref.clearance_purpose pu CROSS JOIN clearance.unit u WHERE pu.gate
    ),
    latest AS (
        SELECT DISTINCT ON (c.student_id, c.purpose, c.unit) c.student_id, c.state
          FROM clearance.item c
          JOIN m ON m.id = c.student_id
          JOIN need n ON n.purpose = c.purpose AND n.unit = c.unit
         WHERE c.superseded_by IS NULL
         ORDER BY c.student_id, c.purpose, c.unit, c.decided_at DESC
    ),
    ok AS (
        SELECT l.student_id, count(*) AS pairs FROM latest l WHERE l.state = 'CLEARED' GROUP BY l.student_id
    )
    SELECT count(*), count(*) FILTER (WHERE coalesce(ok.pairs, 0) >= (SELECT count(*) FROM need)),
           count(*) FILTER (WHERE coalesce(ok.pairs, 0) < (SELECT count(*) FROM need))
      FROM m LEFT JOIN ok ON ok.student_id = m.id
$function$;

-- ── Candidate data's findings, the committed numbers read once ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.attachment_state(p_session text)
 RETURNS TABLE(finding text, n bigint, owner text, what_it_means text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V577: the numbers whose admission list is committed read once for the session (admissions.candidate_is_committed's rule),
    -- the session's files and candidates once — not the commitment asked again for every file and every candidate
    WITH committed AS MATERIALIZED (
        SELECT DISTINCT r.jamb_key FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id
         WHERE r.session = p_session AND NOT r.withdrawn AND b.committed_at IS NOT NULL),
    listed AS MATERIALIZED (SELECT DISTINCT c.jamb_key FROM admissions.candidate c WHERE c.session = p_session AND c.jamb_key IS NOT NULL),
    att AS MATERIALIZED (
        SELECT a.read_as, a.candidate_id, a.jamb_key FROM admissions.attachment a WHERE a.session = p_session)
    SELECT 'Files with no readable registration number'::text,
           count(*)::bigint, 'Academic Office'::text,
           'Nothing in the filename has the shape of a JAMB number. Not '
           'guessed at, not discarded, not matched on a name.'::text
      FROM att a
     WHERE a.read_as = 'UNREADABLE'
  UNION ALL
    SELECT 'Held for a candidate not yet committed'::text,
           count(*)::bigint, 'Academic Office'::text,
           'The number is on a candidate record, but that candidate''s '
           'admission list has not been committed. Nothing attaches, and '
           'nothing is uploaded onto the record, until the list is committed.'::text
      FROM att a
     WHERE a.candidate_id IS NULL AND a.jamb_key IS NOT NULL
       AND EXISTS (SELECT 1 FROM listed l WHERE l.jamb_key = a.jamb_key)
       AND NOT EXISTS (SELECT 1 FROM committed k WHERE k.jamb_key = a.jamb_key)
  UNION ALL
    SELECT 'Arrived for nobody on any list'::text,
           count(*)::bigint, 'Academic Office'::text,
           'A readable number that is on no admission list yet. Held: the '
           'next tranche usually claims them.'::text
      FROM att a
     WHERE a.candidate_id IS NULL AND a.jamb_key IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM listed l WHERE l.jamb_key = a.jamb_key)
  UNION ALL
    SELECT 'Candidates with no photograph'::text,
           count(*)::bigint, 'Academic Office'::text,
           'Committed, and nothing to show at screening.'::text
      FROM admissions.candidate c
     WHERE c.session = p_session
       AND EXISTS (SELECT 1 FROM committed k WHERE k.jamb_key = c.jamb_key)
       AND NOT EXISTS (SELECT 1 FROM admissions.attachment a
                        WHERE a.candidate_id = c.id AND a.kind = 'PASSPORT')
  UNION ALL
    SELECT 'Numbers that only matched after trimming or extraction'::text,
           count(*)::bigint, 'ICT'::text,
           'Would have matched nothing had the raw value been joined. Kept '
           'as a count so the day it jumps, somebody asks why.'::text
      FROM att a
     WHERE a.read_as IN ('EMBEDDED','COLUMN')
       AND a.candidate_id IS NOT NULL
$function$;

COMMIT;
