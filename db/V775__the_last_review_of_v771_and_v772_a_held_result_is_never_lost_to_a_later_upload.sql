-- ═══════════════════════════════════════════════════════════════════════════════
--  V775 · The last review of V771 and V772: a held result is never lost to a later upload, and the rollback's last loose ends
-- ═══════════════════════════════════════════════════════════════════════════════
--  V771 (a past result keeps the course as it was taken) and V772 (Course Registration Correction) went up on 16 November 2026 with a
--  fifth reading of the rewritten rollback still running. It re-ran every earlier failing case and random orders of rollbacks, found
--  the rollback's one rule holding (a change is undone only where it is still the last word on what it changed), and confirmed one
--  loss and a number of smaller faults beside it. This puts them right; nothing here changes what an upload or a rollback is.
--
--  Held results:
--    · A results file loaded for a student who has since been put on the register, without the reconcile having run, posted the row
--      as the new upload's own first result and deleted the older hold outright. The upload that held it kept nothing; rolling the new
--      upload back then took the course and the mark off for good. Now the loader first posts the held results of its batch's students
--      (assessment.reconcile_held, the reconcile for one semester's rows of some students), each under the upload that held it, and
--      the file then replaces or finds the result in its own ledger, exactly as for a student already on the register. The check
--      and the import say so: held_posted_first counts them, and the answer's CGPA list, students and graduates are read against
--      the record as it stood before they posted (what confirming the file does to the record the officer sees).
--    · The reconcile takes the held rows it is about to post before it reads them, so a second reconcile of the same rows (another
--      batch carrying the student, the whole reconcile after a student upload) waits and then finds them posted; the doors that can
--      meet in a circle on those locks are run again by the API (DeadlockRetry).
--    · Holders post in the order they HELD the row (the prior chain, the oldest hold first), not the order their uploads were begun.
--    · A rollback never hands a hold back to the very upload being rolled back (assessment.held_prior_standing takes that upload).
--    · Every row of a rolled-back upload still reading HELD is closed at its rollback, in words that say what happened then; no
--      rolled-back upload's row promises a posting.
--    · A closed upload's stored counts are taken again when something posts under it (assessment.past_upload_counts), and written
--      only where they moved.
--  The rollback (assessment.revert_change):
--    · "One row's corrections" are the same upload, course and snapshot with nothing else done to the course between them in the
--      ledger; a batch sent again after another change is a later change.
--    · A correction asks the Course Registration Correction hook too (the rule was "for every kind").
--    · A class chosen to stand over its duplicate since the upload is left (a person has acted on it); and the Duplicate results
--      decision refuses a pair one of whose marks is only a rolled-back upload's history (DUP_NOT_DUPLICATE).
--    · A first result that stays because its course had to be left is told why, never "it goes with that course when PRU-… is rolled
--      back" of an upload already rolled back.
--    · A class heading stays with the courses of its own upload that were left, while every counted student of the class still
--      carries the course as the heading reads — not because the class happens to read the same again, which left headings "left"
--      on uploads rolled back in full; and where a student reads otherwise the heading is put back.
--  The ledger: a change's "now" code and title are what the course reads after the row (the file's only where the file's were taken),
--  and a course approved again keeps the code and title it had before.
--  Rows V771 and V772 have written since 16 November are brought under these rules at the end (holds under a rolled-back upload,
--  rows still reading HELD under one, stored counts, the ledger's code and title).
-- ═══════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V775: the last review of V771 and V772', true);

-- presence: every function restated or edited here is as V771 and V772 left it (another change since would be overwritten)
DO $$
DECLARE f text; h text; want text;
BEGIN
    FOR f, want IN VALUES
        ('assessment.revert_change(uuid,text,uuid,text)', 'c145eef2e94eaf05155e47c61d46a928'),
        ('assessment.revert_past_upload(uuid,text)', '20fd4c40c71a4a5a3e25dc044e7822bb'),
        ('assessment.reconcile_legacy_holding()', '83dea2d3a4332d896e85fae2390548f5'),
        ('assessment.past_upload_finish(uuid,boolean)', 'ad66fcb7965289ff84479a9ea4b94617'),
        ('assessment.held_prior_standing(jsonb)', 'd639ec2a56e98be729a6dc5759970c5b'),
        ('assessment.legacy_semester_load(text,integer,jsonb,boolean,boolean,uuid,boolean)', '2a38cc36b5428cbc797d58419dc69f44'),
        ('assessment.resolve_duplicate(uuid,uuid,uuid,text)', '5c0659fbe5724ffadca43555b712990a')
    LOOP
        SELECT md5(replace(p.prosrc, E'\r', '')) INTO h FROM pg_proc p WHERE p.oid = to_regprocedure(f);
        IF h IS DISTINCT FROM want THEN
            RAISE EXCEPTION 'V775: % is not as V771 and V772 left it (restate this migration from its live text)', f;
        END IF;
    END LOOP;
END $$;

-- ── held results ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- the hold a hold replaced, nearest first, whose upload still stands — never the upload being rolled back (its own earlier hold, taken
-- over and taken back, would otherwise be handed the row again and keep it under a rolled-back upload for good)
DROP FUNCTION assessment.held_prior_standing(jsonb);
CREATE FUNCTION assessment.held_prior_standing(p_prior jsonb, p_rolling uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
BEGIN
    WHILE p_prior IS NOT NULL AND jsonb_typeof(p_prior) = 'object'
          AND ((p_prior->>'upload_id')::uuid = p_rolling
               OR EXISTS (SELECT 1 FROM assessment.past_upload pu WHERE pu.id = (p_prior->>'upload_id')::uuid AND pu.state = 'REVERTED')) LOOP
        p_prior := p_prior->'prior';
    END LOOP;
    RETURN CASE WHEN jsonb_typeof(p_prior) = 'object' THEN p_prior END;
END $$;
COMMENT ON FUNCTION assessment.held_prior_standing(jsonb, uuid) IS
  'V771, V775: of the holds a held result replaced (assessment.legacy_result_holding.prior, nearest first), the nearest whose upload has not been rolled back and is not the one being rolled back — the hold a rollback hands the row back to; NULL when there is none.';

-- an upload's counts: one reading of its ledger and rows, stored when it is closed and taken again when something posts under it
CREATE FUNCTION assessment.past_upload_counts(p_upload uuid)
RETURNS jsonb
LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('changes', count(*), 'students', count(DISTINCT c.student_id),
                                               'byKind', coalesce((SELECT jsonb_object_agg(k.kind, k.n) FROM (SELECT x.kind, count(*) AS n FROM assessment.past_upload_change x
                                                                                                            WHERE x.upload_id = p_upload GROUP BY x.kind) k), '{}'::jsonb),
                                               'graduates', (SELECT count(*) FROM assessment.past_upload_student s WHERE s.upload_id = p_upload AND s.graduate),
                                               'rows', (SELECT count(*) FROM assessment.past_upload_row w WHERE w.upload_id = p_upload),
                                               'byStatus', coalesce((SELECT jsonb_object_agg(k.status, k.n) FROM (SELECT w.status, count(*) AS n FROM assessment.past_upload_row w
                                                                                                                WHERE w.upload_id = p_upload GROUP BY w.status) k), '{}'::jsonb))
                       FROM assessment.past_upload_change c WHERE c.upload_id = p_upload
$$;
COMMENT ON FUNCTION assessment.past_upload_counts(uuid) IS
  'V775: an upload''s counts as its ledger and rows read now — changes, students, graduates, by kind, rows, by status. Stored on the upload when it is closed (assessment.past_upload_finish), and again when a held result posts under it or it is rolled back.';

CREATE OR REPLACE FUNCTION assessment.past_upload_finish(p_upload uuid, p_complete boolean)
RETURNS assessment.past_upload
LANGUAGE plpgsql AS $$
DECLARE u assessment.past_upload; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    SELECT * INTO u FROM assessment.past_upload WHERE id = p_upload FOR UPDATE;
    IF u.id IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: no upload %', p_upload USING ERRCODE = 'P0002'; END IF;
    IF u.created_by IS DISTINCT FROM v_actor THEN RAISE EXCEPTION 'LEGACY_UPLOAD_OWN: upload % is another officer''s', u.ref USING ERRCODE = '42501'; END IF;
    IF u.state <> 'RUNNING' THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %', u.ref, lower(u.state) USING ERRCODE = '23514'; END IF;
    UPDATE assessment.past_upload
       SET state = CASE WHEN p_complete THEN 'COMPLETE' ELSE 'INCOMPLETE' END, finished_at = now(), finished_by = v_actor,
           counts = assessment.past_upload_counts(p_upload)
     WHERE id = p_upload RETURNING * INTO u;
    RETURN u;
END $$;

-- the reconcile, for all that is held or for one semester's rows of some students (the loader posts the held results of its batch's
-- students before it reads their rows): each upload still standing that held a row posts it, in the order they held it
CREATE FUNCTION assessment.reconcile_held(p_session text, p_semester integer, p_matrics text[])
 RETURNS TABLE(reconciled integer, still_held integer)
 LANGUAGE plpgsql
AS $function$
DECLARE grp record; v_before int; v_after int; v_posted uuid[] := '{}';
BEGIN
    PERFORM set_config('moaum.legacy_reconcile', 'on', true);  -- V627: posting held results is open to every migrating office
    -- V775: the held rows it is about to post are taken first, in one order: a second reconcile of the same rows waits here for the
    -- first, and then reads them as posted (read before the lock, it would post again what a file has since replaced)
    PERFORM 1 FROM assessment.legacy_result_holding h
      WHERE (p_matrics IS NULL OR (h.session = p_session AND h.semester = p_semester AND h.matric = ANY (p_matrics)))
        AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric)
      ORDER BY h.session, h.semester, h.matric, h.course_code
        FOR UPDATE OF h;
    SELECT count(*) INTO v_before FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric) AND NOT assessment.held_row_removed(h)
       AND (p_matrics IS NULL OR (h.session = p_session AND h.semester = p_semester AND h.matric = ANY (p_matrics)));
    FOR grp IN
        -- V771's reading (a row an earlier upload still standing held before is posted first, under that upload), without the removed
        WITH RECURSIVE held AS (
            SELECT h.session, h.semester, h.matric, h.course_code, h.as_taken, h.upload_id, h.raw, h.loaded_at, h.prior, 0 AS depth
              FROM assessment.legacy_result_holding h
             WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric) AND NOT assessment.held_row_removed(h)
       AND (p_matrics IS NULL OR (h.session = p_session AND h.semester = p_semester AND h.matric = ANY (p_matrics)))
            UNION ALL
            SELECT c.session, c.semester, c.matric, c.course_code, coalesce((c.prior->>'as_taken')::boolean, false), (c.prior->>'upload_id')::uuid,
                   c.prior->'raw', (c.prior->>'loaded_at')::timestamptz, c.prior->'prior', c.depth + 1
              FROM held c WHERE jsonb_typeof(c.prior) = 'object')
        SELECT k.session, k.semester, k.as_taken, k.upload_id, jsonb_agg(k.raw ORDER BY k.loaded_at) AS rows
          FROM (SELECT DISTINCT ON (q.session, q.semester, q.matric, q.course_code, q.upload_id) q.*   -- an upload's newest hold of the row only
                  FROM held q ORDER BY q.session, q.semester, q.matric, q.course_code, q.upload_id, q.depth) k
          LEFT JOIN assessment.past_upload pu ON pu.id = k.upload_id
         WHERE k.depth = 0 OR pu.state IS DISTINCT FROM 'REVERTED'
         -- in the order they held the row (the oldest hold first: the prior chain is the only record of who replaced whom), one
         -- loader call for each upload at each depth
         GROUP BY k.depth, k.session, k.semester, k.as_taken, k.upload_id
         ORDER BY k.depth DESC, min(pu.created_at) NULLS FIRST, min(pu.ref) NULLS FIRST
    LOOP
        PERFORM assessment.legacy_semester_load(grp.session, grp.semester, grp.rows, true, false, grp.upload_id, grp.as_taken);
        IF grp.upload_id IS NOT NULL AND NOT (grp.upload_id = ANY (v_posted)) THEN v_posted := v_posted || grp.upload_id; END IF;
    END LOOP;
    -- a closed upload's counts are a stored reading of its ledger and rows: taken again when something posts under it — written
    -- only where they moved (a held row that cannot post is offered at every reconcile; no entry in the audit trail for nothing)
    UPDATE assessment.past_upload pu SET counts = n.counts
      FROM (SELECT u.id, assessment.past_upload_counts(u.id) AS counts FROM assessment.past_upload u
             WHERE u.id = ANY (v_posted) AND u.state <> 'RUNNING' OFFSET 0) n
     WHERE pu.id = n.id AND pu.counts IS DISTINCT FROM n.counts;
    SELECT count(*) INTO v_after FROM assessment.legacy_result_holding h
     WHERE EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric) AND NOT assessment.held_row_removed(h)
       AND (p_matrics IS NULL OR (h.session = p_session AND h.semester = p_semester AND h.matric = ANY (p_matrics)));
    PERFORM set_config('moaum.legacy_reconcile', '', true);
    RETURN QUERY SELECT greatest(v_before - v_after, 0),
                        (SELECT count(*)::int FROM assessment.legacy_result_holding h WHERE NOT assessment.held_row_removed(h)
                           AND (p_matrics IS NULL OR (h.session = p_session AND h.semester = p_semester AND h.matric = ANY (p_matrics))));
END $function$;
COMMENT ON FUNCTION assessment.reconcile_held(text, integer, text[]) IS
  'V775: held old-portal results posted for the students now on the register — all of them (NULL scope), or one semester''s rows of the named matriculation numbers. Each upload still standing that held a row posts it under its own upload, in the order they held it (the prior chain, the oldest hold first), so a later one replaces or finds the result in its own ledger as for a student already on the register; a row of a course taken off, or of an upload rolled back, is neither posted nor counted. A closed upload''s counts are taken again.';

CREATE OR REPLACE FUNCTION assessment.reconcile_legacy_holding()
 RETURNS TABLE(reconciled integer, still_held integer)
 LANGUAGE sql
AS $function$ SELECT * FROM assessment.reconcile_held(NULL, NULL, NULL) $function$;

-- ── the loader: edits to its text as V771 left it ───────────────────────────────────────────────────────────────────────────────
--  (1) the held results of the batch's students post first, and the answer says so (held_posted_first, and its CGPA list, students
--  and graduates against the record as it stood before they did); (2) and (3) the ledger's code and title; (4) the version read
DO $$
DECLARE d text; f text := 'assessment.legacy_semester_load(text,integer,jsonb,boolean,boolean,uuid,boolean)'; i int; n int;
    a text[] := ARRAY[
$q1$        PERFORM assessment.ensure_session(p_session);$q1$,
$q2$                                SELECT c.kind INTO v_kind FROM catalogue.course c WHERE c.code = v_code;
                                v_cat_now := registration.entry_category(v_entry_type, v_kind, v_entry_basis);$q2$,
$q3$                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_printed_code END, v_code_as,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_printed_title END, v_title,$q3$,
$q4$                                  LEFT JOIN registration.entry e ON e.registration_id = v_reg AND e.offering_id = v_offering
                                 ORDER BY u.ord;$q4$,
$q5$    v_rolled boolean; v_rc int; v_reg_lvl int; v_differs boolean;$q5$,
$q6$        FOR v_x IN SELECT s.id, upper(s.matric_no) AS matric, s.surname || ', ' || s.other_names AS name FROM people.student s WHERE s.id = ANY (v_moved || v_touched) LOOP
            v_before := v_gpa_before->(v_x.id::text);$q6$,
$q7$                v_affected := v_affected || jsonb_build_object(v_x.matric, true);
            END IF;
            IF v_upload IS NOT NULL THEN
                UPDATE assessment.past_upload_student SET cgpa_after = (v_after->>'cgpa')::numeric, tcr_after = (v_after->>'tcr')::int$q7$,
$q8$        'absent_from_abs', n_absent,$q8$];
    b text[] := ARRAY[
$q1$        PERFORM assessment.ensure_session(p_session);
        -- V775: a result held for a student since put on the register posts first, under the upload that held it (as the reconcile
        -- posts it): this file then replaces it, or finds it, in its own ledger, and a rollback of this upload leaves the earlier
        -- upload's result standing. Inside the load, so a check undoes it too
        IF p_with_results AND NOT v_reconcile THEN
            v_held_of := ARRAY(SELECT DISTINCT h.matric FROM assessment.legacy_result_holding h
                                WHERE h.session = p_session AND h.semester = p_semester
                                  AND h.matric IN (SELECT upper(btrim(coalesce(e.value->>'matric', e.value->>'matricNo', e.value->>'matric_no', e.value->>'regNo', e.value->>'reg_no', '')))
                                                     FROM jsonb_array_elements(p_rows) e)
                                  AND EXISTS (SELECT 1 FROM people.student s WHERE upper(s.matric_no) = h.matric));
            IF cardinality(v_held_of) > 0 THEN
                -- the held rows are taken first, in the reconcile's own order: another reconcile of them (a batch carrying the same
                -- student, the whole reconcile after a student upload) has ended before anything of them is read here
                PERFORM 1 FROM assessment.legacy_result_holding h
                  WHERE h.session = p_session AND h.semester = p_semester AND h.matric = ANY (v_held_of)
                  ORDER BY h.session, h.semester, h.matric, h.course_code
                    FOR UPDATE OF h;
                -- the record as it stands, for the answer only: each of these students' picture before their held results post (the
                -- answer's CGPA list, students and graduates then say what confirming the file does to the record the officer sees)
                SELECT coalesce(jsonb_object_agg(s.id::text, assessment.gpa_snapshot(s.id)), '{}'::jsonb) INTO v_gpa_record
                  FROM people.student s
                 WHERE upper(s.matric_no) = ANY (v_held_of)
                   AND EXISTS (SELECT 1 FROM assessment.legacy_result_holding h
                                WHERE h.session = p_session AND h.semester = p_semester AND h.matric = upper(s.matric_no));
                SELECT h.reconciled INTO n_held_first FROM assessment.reconcile_held(p_session, p_semester, v_held_of) h;
            END IF;
        END IF;$q1$,
$q2$                                SELECT c.kind INTO v_kind FROM catalogue.course c WHERE c.code = v_code;
                                v_cat_now := registration.entry_category(v_entry_type, v_kind, v_entry_basis);
                                -- V775: the code and title the course had before, for the ledger
                                v_old := NULL;
                                IF v_entry_at IS NOT NULL THEN SELECT * INTO v_old FROM catalogue.course_as_taken WHERE id = v_entry_at; END IF;
                                SELECT coalesce(v_old.code_as_taken, catalogue.code_as_written(o.course_code)),
                                       coalesce(v_old.title, catalogue.title_as_written(coalesce(o.title, c.title)))
                                  INTO v_printed_code, v_printed_title
                                  FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.id = v_entry;$q2$,
$q3$                                       -- V775: "now" is what the course reads after the row — the file's only where the file's were taken
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_printed_code END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN v_code_as ELSE coalesce(na.code_as_taken, v_printed_code, v_code_as) END,
                                       CASE WHEN k IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN NULL ELSE v_printed_title END,
                                       CASE WHEN k IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') THEN v_title ELSE coalesce(na.title, v_printed_title, v_title) END,$q3$,
$q4$                                  LEFT JOIN registration.entry e ON e.registration_id = v_reg AND e.offering_id = v_offering
                                  LEFT JOIN catalogue.course_as_taken na ON na.id = e.as_taken_id
                                 ORDER BY u.ord;$q4$,
$q5$    v_rolled boolean; v_rc int; v_reg_lvl int; v_differs boolean;
    n_held_first int := 0; v_gpa_record jsonb := '{}'::jsonb; v_held_of text[] := '{}';   -- V775$q5$,
$q6$        -- V775: and each student whose held results posted first — for the answer, against the record as it stood before they did
        FOR v_x IN SELECT s.id, upper(s.matric_no) AS matric, s.surname || ', ' || s.other_names AS name FROM people.student s
                    WHERE s.id = ANY (v_moved || v_touched || ARRAY(SELECT k::uuid FROM jsonb_object_keys(v_gpa_record) k)) LOOP
            v_before := coalesce(v_gpa_record->(v_x.id::text), v_gpa_before->(v_x.id::text));$q6$,
$q7$                v_affected := v_affected || jsonb_build_object(v_x.matric, true);
                -- V775: a Senate-approved graduate whose record the held posting moved is listed for the Registry as any other
                IF v_gpa_record ? v_x.id::text
                   AND EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = v_x.id AND g.senate_state = 'APPROVED') THEN
                    v_graduates := v_graduates || jsonb_build_object(v_x.matric, true);
                END IF;
            END IF;
            IF v_upload IS NOT NULL AND v_x.id = ANY (v_moved || v_touched) THEN   -- V775: the upload's own students only — its ledger's
                                                                                 -- before and after stay its own (the holder's has the rest)
                UPDATE assessment.past_upload_student SET cgpa_after = (v_after->>'cgpa')::numeric, tcr_after = (v_after->>'tcr')::int$q7$,
$q8$        'absent_from_abs', n_absent, 'held_posted_first', n_held_first,   -- V775: results held for these students, posted first$q8$];
BEGIN
    d := replace(pg_get_functiondef(f::regprocedure), E'\r', '');
    FOR i IN 1 .. cardinality(a) LOOP
        n := (length(d) - length(replace(d, a[i], ''))) / length(a[i]);
        IF n <> 1 THEN RAISE EXCEPTION 'V775: the loader is not as V771 left it (edit % found % times)', i, n; END IF;
        d := replace(d, a[i], b[i]);
    END LOOP;
    EXECUTE d;
END $$;

-- ── Duplicate results: a rolled-back upload's mark is no second result; the decision's time is clock time ────────────────────────
DO $$
DECLARE d text; f text := 'assessment.resolve_duplicate(uuid,uuid,uuid,text)'; i int; n int;
    a text[] := ARRAY[
$q1$        RAISE EXCEPTION 'DUP_REMOVAL: one of these classes is being taken off the registration by the Director of ICT; settle that first' USING ERRCODE = '23514';
    END IF;$q1$,
$q2$dropped_entry_was, reason, decided_by, decided_office)
    VALUES (p_student, k.session, k.semester, assessment.base_course_code(k.course_code), p_keep, p_drop, v_was, btrim(p_reason), v_actor, v_office)$q2$];
    b text[] := ARRAY[
$q1$        RAISE EXCEPTION 'DUP_REMOVAL: one of these classes is being taken off the registration by the Director of ICT; settle that first' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM assessment.score_sheet sh
                WHERE sh.offering_id IN (p_keep, p_drop) AND assessment.result_rolled_back(sh.id, p_student)) THEN   -- V775
        RAISE EXCEPTION 'DUP_NOT_DUPLICATE: one of these marks is only the history of an upload since rolled back; there is nothing to decide' USING ERRCODE = '23514';
    END IF;$q1$,
$q2$dropped_entry_was, reason, decided_by, decided_office, decided_at)
    VALUES (p_student, k.session, k.semester, assessment.base_course_code(k.course_code), p_keep, p_drop, v_was, btrim(p_reason), v_actor, v_office,
            clock_timestamp())$q2$];
BEGIN
    d := replace(pg_get_functiondef(f::regprocedure), E'\r', '');
    FOR i IN 1 .. cardinality(a) LOOP
        n := (length(d) - length(replace(d, a[i], ''))) / length(a[i]);
        IF n <> 1 THEN RAISE EXCEPTION 'V775: assessment.resolve_duplicate is not as V772 left it (edit % found % times)', i, n; END IF;
        d := replace(d, a[i], b[i]);
    END LOOP;
    EXECUTE d;
END $$;

-- ── the rollback ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION assessment.revert_change(p_change uuid, p_reason text, p_rolling uuid, p_by text)
RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE c assessment.past_upload_change; u assessment.past_upload; e registration.entry; o catalogue.offering;
        v_last assessment.score; v_was assessment.score; v_note text; v_done boolean := false; v_senate text; v_reason text;
        v_rolling text; v_later boolean := false; v_course text; v_row uuid[] := '{}';
        v_when text := CASE WHEN p_by IS NOT NULL THEN 'undone when ' || p_by || ' was rolled back' END;
BEGIN
    IF coalesce(current_setting('moaum.upload_rollback', true), '') <> 'on' THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: an upload''s changes are undone by its rollback (assessment.revert_past_upload), never on their own'
              USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM assessment.past_upload_change WHERE id = p_change FOR UPDATE;
    IF c.id IS NULL OR c.reverted_at IS NOT NULL THEN RETURN false; END IF;   -- undone already (with its course, or with its row's other corrections)
    SELECT * INTO u FROM assessment.past_upload WHERE id = c.upload_id;
    SELECT pu.ref INTO v_rolling FROM assessment.past_upload pu WHERE pu.id = p_rolling;
    v_reason := 'Upload ' || u.ref || ' rolled back: ' || btrim(p_reason);
    IF c.registration_id IS NOT NULL AND c.offering_id IS NOT NULL THEN
        SELECT * INTO e FROM registration.entry WHERE registration_id = c.registration_id AND offering_id = c.offering_id FOR UPDATE;
        -- one row's corrections are one change: the same upload, course and snapshot, with nothing else done to the course between
        -- them in the ledger (a batch sent again after another change is a later change, not the same row)
        IF c.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED') THEN
            SELECT coalesce(array_agg(p.id), '{}') INTO v_row
              FROM assessment.past_upload_change p
             WHERE p.upload_id = c.upload_id AND p.id <> c.id AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
               AND p.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
               AND p.was_units IS NOT DISTINCT FROM c.was_units AND p.now_units IS NOT DISTINCT FROM c.now_units
               AND p.was_as_taken IS NOT DISTINCT FROM c.was_as_taken AND p.now_as_taken IS NOT DISTINCT FROM c.now_as_taken
               AND p.was_entry_type IS NOT DISTINCT FROM c.was_entry_type AND p.now_entry_type IS NOT DISTINCT FROM c.now_entry_type
               AND p.was_basis IS NOT DISTINCT FROM c.was_basis AND p.now_basis IS NOT DISTINCT FROM c.now_basis
               AND NOT EXISTS (SELECT 1 FROM assessment.past_upload_change x
                                WHERE x.registration_id = c.registration_id AND x.offering_id = c.offering_id
                                  AND x.seq > least(p.seq, c.seq) AND x.seq < greatest(p.seq, c.seq)
                                  AND NOT (x.upload_id = c.upload_id AND x.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                                           AND x.was_units IS NOT DISTINCT FROM c.was_units AND x.now_units IS NOT DISTINCT FROM c.now_units
                                           AND x.was_as_taken IS NOT DISTINCT FROM c.was_as_taken AND x.now_as_taken IS NOT DISTINCT FROM c.now_as_taken
                                           AND x.was_entry_type IS NOT DISTINCT FROM c.was_entry_type AND x.now_entry_type IS NOT DISTINCT FROM c.now_entry_type
                                           AND x.was_basis IS NOT DISTINCT FROM c.was_basis AND x.now_basis IS NOT DISTINCT FROM c.now_basis));
        END IF;
        -- a later change to the course that is not undone stands on it
        v_later := EXISTS (SELECT 1 FROM assessment.past_upload_change p
                            WHERE p.registration_id = c.registration_id AND p.offering_id = c.offering_id AND p.seq > c.seq AND p.reverted_at IS NULL
                              AND p.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                              AND NOT (p.id = ANY (v_row)));
        -- the Senate's units stand on the course: an amendment applied at the units the upload had put moves nothing on the entry, so
        -- it is asked for as the loader asks (never written over, by a file or by a rollback)
        v_senate := CASE WHEN e.registration_id IS NOT NULL AND e.units = c.now_units AND c.was_units IS DISTINCT FROM c.now_units
                          AND c.kind IN ('ENTRY_REAPPROVED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')
                         THEN assessment.entry_units_by_senate(c.offering_id, (SELECT st.programme_code FROM people.student st WHERE st.id = c.student_id),
                                                               e.units, e.as_taken_id, c.student_id) END;
    END IF;

    IF c.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') THEN
        IF e.registration_id IS NULL THEN
            v_note := 'the course is no longer on the registration; left as it is';
        ELSIF v_later THEN
            v_note := 'a later upload has changed this course since and its change has not been undone; left as it is';
        ELSIF e.status IS DISTINCT FROM c.now_status OR e.units IS DISTINCT FROM c.now_units OR e.as_taken_id IS DISTINCT FROM c.now_as_taken
              OR e.entry_type IS DISTINCT FROM c.now_entry_type OR e.basis IS DISTINCT FROM c.now_basis THEN
            v_note := 'the course has changed on the registration since the upload; left as it is';
        ELSIF registration.entry_corrected_since(c.registration_id, c.offering_id, c.changed_at) THEN
            v_note := 'a Course Registration Correction has been recorded on this course since the upload; left as it is';
        ELSIF EXISTS (SELECT 1 FROM assessment.duplicate_resolution dr
                       WHERE dr.student_id = c.student_id AND dr.kept_offering = c.offering_id AND dr.undone_at IS NULL
                         AND dr.decided_at > c.changed_at) THEN
            v_note := 'this class was chosen to stand over its duplicate since the upload (Duplicate results); left as it is';
        ELSIF EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score s ON s.sheet_id = sh.id
                       WHERE sh.offering_id = c.offering_id AND s.student_id = c.student_id
                         AND s.version > coalesce(c.was_score_version, 0)   -- newer than the newest on the class when the course was added
                         AND NOT assessment.score_undone(s.sheet_id, s.student_id, s.version)
                         -- the first result of this upload, or of an upload that is rolled back, goes with the course
                         AND NOT EXISTS (SELECT 1 FROM assessment.past_upload_change p JOIN assessment.past_upload pu ON pu.id = p.upload_id
                                          WHERE p.kind = 'RESULT_POSTED' AND p.sheet_id = s.sheet_id AND p.student_id = s.student_id
                                            AND p.now_score_version = s.version AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
                                            AND (p.upload_id = c.upload_id OR pu.state = 'REVERTED' OR pu.id = p_rolling))) THEN
            v_note := 'a result has been entered or changed on this course since the upload; left as it is';
        ELSIF c.kind = 'ENTRY_ADDED' THEN
            -- as if it had never been added: a mark an upload posted on it stays on its sheet as history, the ledger says why it has no
            -- registration (the result monitor passes over it), and a corrected file adds the course afresh
            DELETE FROM registration.entry WHERE registration_id = c.registration_id AND offering_id = c.offering_id;
            v_done := true;
        ELSE
            -- dropped again as it was; the Senate's units, where they are the Senate's, stay with their version
            UPDATE registration.entry SET status = c.was_status,
                   units = CASE WHEN v_senate IS NOT NULL THEN units ELSE coalesce(c.was_units, units) END,
                   as_taken_id = CASE WHEN v_senate IS NOT NULL THEN as_taken_id ELSE c.was_as_taken END,
                   entry_type = coalesce(c.was_entry_type, entry_type), basis = c.was_basis
             WHERE registration_id = c.registration_id AND offering_id = c.offering_id;
            v_done := true;
        END IF;
        IF v_done THEN
            -- the first results on it go with it (each kept on its sheet as history): this upload's, and those of uploads rolled back
            -- (or being rolled back) that were posted after the course was put there
            UPDATE assessment.past_upload_change p
               SET reverted_at = clock_timestamp(),
                   revert_note = CASE WHEN p.upload_id = c.upload_id THEN v_when
                                      ELSE 'taken back with its course when ' || coalesce(v_rolling, u.ref) || ' was rolled back' END
              FROM assessment.past_upload pu
             WHERE pu.id = p.upload_id AND p.kind = 'RESULT_POSTED' AND p.reverted_at IS NULL
               AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
               AND (p.upload_id = c.upload_id
                    OR ((pu.state = 'REVERTED' OR pu.id = p_rolling) AND p.now_score_version > coalesce(c.was_score_version, 0)));
        ELSE
            -- the first results that would have gone with it stay with it and are told why: this upload's, and those of uploads rolled
            -- back (or being rolled back) posted after the course was put there — the course as THIS change put it (no adding or
            -- re-approval of any upload, the result's own included, stands between the two: such a result is that re-approval's
            -- and was told its reason when it was left)
            UPDATE assessment.past_upload_change p
               SET revert_note = CASE WHEN p.upload_id = c.upload_id THEN v_note
                                      ELSE 'a first result on a course ' || u.ref || ' put on the registration: ' || u.ref
                                           || ' is rolled back and had to leave the course (' || replace(v_note, '; left as it is', '')
                                           || '), so the result stays with it; amend it through Result amendments' END
              FROM assessment.past_upload pu
             WHERE pu.id = p.upload_id AND p.kind = 'RESULT_POSTED' AND p.reverted_at IS NULL
               AND p.registration_id = c.registration_id AND p.offering_id = c.offering_id
               AND (p.upload_id = c.upload_id
                    OR ((pu.state = 'REVERTED' OR pu.id = p_rolling) AND p.now_score_version > coalesce(c.was_score_version, 0)
                        AND (u.state = 'REVERTED' OR u.id = p_rolling)
                        AND NOT EXISTS (SELECT 1 FROM assessment.past_upload_change a
                                         WHERE a.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND a.reverted_at IS NULL
                                           AND a.registration_id = c.registration_id AND a.offering_id = c.offering_id
                                           AND a.seq > c.seq AND a.seq < p.seq)));
        END IF;
    ELSIF c.kind = 'RESULT_POSTED' THEN
        -- on a course this upload added or approved again it is decided with that course (the ledger is walked newest first)
        IF EXISTS (SELECT 1 FROM assessment.past_upload_change a
                    WHERE a.upload_id = c.upload_id AND a.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND a.reverted_at IS NULL
                      AND a.registration_id = c.registration_id AND a.offering_id = c.offering_id) THEN
            RETURN false;
        END IF;
        -- a first result on a course already on the registration cannot be taken off without the course
        SELECT pu.ref INTO v_course FROM assessment.past_upload_change a JOIN assessment.past_upload pu ON pu.id = a.upload_id
         WHERE a.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND a.reverted_at IS NULL AND a.upload_id <> c.upload_id
           AND a.registration_id = c.registration_id AND a.offering_id = c.offering_id AND a.seq < c.seq
         ORDER BY a.seq DESC LIMIT 1;
        v_note := CASE WHEN v_course IS NOT NULL
                       THEN 'a first result on a course ' || v_course || ' put on the registration: it goes with that course when ' || v_course
                            || ' is rolled back; until then amend it through Result amendments'
                       ELSE 'a first result on a course already on record is not taken back here; amend it through Result amendments' END;
    ELSIF c.kind = 'RESULT_REPLACED' THEN
        SELECT * INTO v_last FROM assessment.score WHERE sheet_id = c.sheet_id AND student_id = c.student_id ORDER BY version DESC LIMIT 1;
        SELECT * INTO v_was FROM assessment.score WHERE sheet_id = c.sheet_id AND student_id = c.student_id AND version = c.was_score_version;
        -- still this upload's result: its mark is the newest, or every later one is a rolled-back upload's or a rollback's restoration
        IF v_last.version IS NOT NULL AND v_was.version IS NOT NULL
           AND (v_last.version = c.now_score_version
                OR NOT EXISTS (SELECT 1 FROM assessment.score s WHERE s.sheet_id = c.sheet_id AND s.student_id = c.student_id
                                  AND s.version > c.now_score_version AND NOT assessment.score_undone(s.sheet_id, s.student_id, s.version))) THEN
            INSERT INTO assessment.score (sheet_id, student_id, version, ca, exam, total, outcome, imported, reason)
            VALUES (c.sheet_id, c.student_id, v_last.version + 1, v_was.ca, v_was.exam, v_was.total, v_was.outcome, v_was.imported, v_reason);
            UPDATE assessment.past_upload_change SET undo_score_version = v_last.version + 1 WHERE id = c.id;
            v_done := true;
        ELSE
            v_note := 'the result has changed since; left as it is';
        END IF;
    ELSIF c.kind IN ('UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED') THEN
        IF e.registration_id IS NULL THEN
            v_note := 'the course is no longer on the registration; left as it is';
        ELSIF v_later THEN
            v_note := 'a later upload has changed this course since and its change has not been undone; left as it is';
        ELSIF NOT (e.units = c.now_units AND e.as_taken_id IS NOT DISTINCT FROM c.now_as_taken
                   AND e.entry_type IS NOT DISTINCT FROM c.now_entry_type AND e.basis IS NOT DISTINCT FROM c.now_basis) THEN
            v_note := 'the course has changed on the registration since; left as it is';
        ELSIF registration.entry_corrected_since(c.registration_id, c.offering_id, c.changed_at) THEN
            v_note := 'a Course Registration Correction has been recorded on this course since the upload; left as it is';
        ELSIF v_senate IS NOT NULL THEN
            v_note := 'the Senate set these units (' || v_senate || '); left as it is';
        ELSE
            UPDATE registration.entry SET units = c.was_units, as_taken_id = c.was_as_taken, entry_type = c.was_entry_type, basis = c.was_basis
             WHERE registration_id = c.registration_id AND offering_id = c.offering_id;
            v_done := true;
            -- the row's other corrections were written from the same snapshot: undone with this one
            UPDATE assessment.past_upload_change p SET reverted_at = clock_timestamp(), revert_note = v_when
             WHERE p.id = ANY (v_row) AND p.reverted_at IS NULL;
        END IF;
    ELSIF c.kind = 'CLASS_HEADER_CORRECTED' THEN
        SELECT * INTO o FROM catalogue.offering WHERE id = c.offering_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM assessment.past_upload_change p
                    WHERE p.kind = 'CLASS_HEADER_CORRECTED' AND p.offering_id = c.offering_id AND p.seq > c.seq AND p.reverted_at IS NULL) THEN
            v_note := 'a later upload has set this class''s heading since and its change has not been undone; left as it is';
        ELSIF o.id IS NULL OR o.title IS DISTINCT FROM c.now_title OR o.units IS DISTINCT FROM c.now_units THEN
            v_note := 'the class has changed since; left as it is';
        ELSIF EXISTS (SELECT 1 FROM assessment.past_upload_change p
                       WHERE p.upload_id = c.upload_id AND p.offering_id = c.offering_id AND p.reverted_at IS NULL
                         AND p.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED', 'UNITS_CORRECTED', 'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED'))
              AND NOT EXISTS (SELECT 1 FROM registration.entry en LEFT JOIN catalogue.course_as_taken a ON a.id = en.as_taken_id
                               WHERE en.offering_id = c.offering_id AND en.status IN ('APPROVED', 'REGISTERED')
                                 AND (a.id IS NULL OR a.title IS DISTINCT FROM c.now_title OR a.units IS DISTINCT FROM c.now_units)) THEN
            -- the heading reads what this upload made its students' courses read; some of those were left as the upload put them
            -- (the walk undoes the courses first) and every counted student of the class still carries the course so: the heading
            -- stays with them. Where a student reads otherwise — put back to no version of their own, or on a later upload's — the
            -- heading is put back (a student without a version reads the heading), and the left courses keep their own version
            v_note := 'courses of this class that the upload put as the heading reads were left, and every student of the class still carries the course so; the heading stays with them';
        ELSE
            UPDATE catalogue.offering SET title = c.was_title, units = c.was_units WHERE id = c.offering_id;
            v_done := true;
        END IF;
    ELSIF c.kind = 'REGISTRATION_ADDED' THEN
        -- the registration the upload made goes when nothing is left on it and nothing has been done to it since
        v_note := assessment.revert_registration_added(c);
        v_done := v_note IS NULL;
    ELSIF c.kind = 'ENROLMENT_ADDED' THEN
        v_note := assessment.revert_enrolment_added(c);
        v_done := v_note IS NULL;
    END IF;
    UPDATE assessment.past_upload_change SET reverted_at = CASE WHEN v_done THEN clock_timestamp() END,
           revert_note = CASE WHEN v_done THEN v_when ELSE v_note END WHERE id = c.id;
    RETURN v_done;
END $$;
COMMENT ON FUNCTION assessment.revert_change(uuid, text, uuid, text) IS
  'V771, V775: one change of an upload''s ledger undone where it is still the last word on what it changed — no later change in the ledger stands on it, the record still reads what it left, and no one has acted on it since (the Senate''s units, a Course Registration Correction, a class chosen to stand over its duplicate, a registration reset or decided); one row''s corrections (the same upload, course and snapshot, nothing between them in the ledger) are one change; a first result of a rolled-back upload goes with its course, or stays with it and is told why; a class heading stays with the courses of its own upload that were left. Called by assessment.revert_past_upload, never on its own (LEGACY_UPLOAD_STATE without its moaum.upload_rollback handshake).';

CREATE OR REPLACE FUNCTION assessment.revert_past_upload(p_upload uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        u assessment.past_upload; k record; n_held int := 0; n_round int; v_counts jsonb; v_left jsonb;
        v_started timestamptz;
BEGIN
    IF v_office IS NULL OR NOT assessment.past_results_may() THEN
        RAISE EXCEPTION 'LEGACY_REVERT_OFFICE: an upload is rolled back by the Directorate of ICT or a Database Operator granted over the University' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_REASON: say why the upload is rolled back (ten characters or more); it goes on the record with your name' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO u FROM assessment.past_upload WHERE id = p_upload FOR UPDATE;
    IF u.id IS NULL THEN RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: no upload %', p_upload USING ERRCODE = 'P0002'; END IF;
    IF u.state NOT IN ('COMPLETE', 'INCOMPLETE') THEN
        RAISE EXCEPTION 'LEGACY_UPLOAD_STATE: upload % is %; %', u.ref, lower(u.state),
              CASE WHEN u.state = 'RUNNING' THEN 'close it first' ELSE 'it is rolled back already' END USING ERRCODE = '23514';
    END IF;
    -- results it still holds for students not yet on the register never post under a rolled-back upload: each hold goes back to the
    -- nearest earlier upload still standing that held the row before it (the same file loaded twice; never to this upload's own
    -- earlier hold), or is dropped. A row a later upload holds now, or has posted, is that upload's and stays as it is
    WITH mine AS MATERIALIZED (SELECT hx.session, hx.semester, hx.matric, hx.course_code, hx.raw->>'line' AS line,
                                      assessment.held_prior_standing(hx.prior, p_upload) AS j
                                 FROM assessment.legacy_result_holding hx WHERE hx.upload_id = p_upload),
         back AS (UPDATE assessment.legacy_result_holding h
                     SET upload_id = (SELECT pu.id FROM assessment.past_upload pu WHERE pu.id = (m.j->>'upload_id')::uuid),
                         raw = m.j->'raw', as_taken = coalesce((m.j->>'as_taken')::boolean, false), loaded_at = (m.j->>'loaded_at')::timestamptz,
                         prior = CASE WHEN jsonb_typeof(m.j->'prior') = 'object' THEN m.j->'prior' END
                    FROM mine m
                   WHERE m.j IS NOT NULL AND h.session = m.session AND h.semester = m.semester AND h.matric = m.matric AND h.course_code = m.course_code
                  RETURNING 1),
         gone AS (DELETE FROM assessment.legacy_result_holding h USING mine m
                   WHERE m.j IS NULL AND h.session = m.session AND h.semester = m.semester AND h.matric = m.matric AND h.course_code = m.course_code
                  RETURNING 1),
         -- every row of the upload still reading HELD is closed, in words that say what happened then: a row promises a posting only
         -- while its upload stands
         marked AS (UPDATE assessment.past_upload_row pr SET status = 'HELD_ROLLED_BACK',
                           detail = 'Held for a student not yet on the register; '
                                    || coalesce((SELECT CASE WHEN m.j IS NULL THEN 'dropped when the upload was rolled back'
                                                             ELSE 'dropped when the upload was rolled back; the row went back to '
                                                                  || coalesce((SELECT pu.ref FROM assessment.past_upload pu WHERE pu.id = (m.j->>'upload_id')::uuid),
                                                                              'an earlier hold')
                                                                  || ', which held it before' END
                                                   FROM mine m
                                                  WHERE m.session = pr.session AND m.semester = pr.semester AND m.matric = pr.matric
                                                    AND (m.course_code = pr.course OR (pr.line IS NOT NULL AND pr.line = m.line))
                                                  ORDER BY (m.course_code = pr.course) DESC LIMIT 1),
                                                'not posted before the upload was rolled back'
                                                || coalesce((SELECT '; ' || pu.ref || ' had taken the row over'
                                                               FROM assessment.legacy_result_holding h JOIN assessment.past_upload pu ON pu.id = h.upload_id
                                                              WHERE h.session = pr.session AND h.semester = pr.semester AND h.matric = pr.matric
                                                                AND h.course_code = pr.course AND h.upload_id <> p_upload), ''))
                     WHERE pr.upload_id = p_upload AND pr.status = 'HELD'
                    RETURNING 1)
    SELECT count(*) INTO n_held FROM mine;

    v_started := clock_timestamp();
    PERFORM set_config('moaum.upload_rollback', 'on', true);   -- the changes are undone only from here
    -- its own ledger, newest change first; the class headings after the courses, since a heading follows what its students carry
    FOR k IN SELECT ch.id FROM assessment.past_upload_change ch WHERE ch.upload_id = p_upload AND ch.reverted_at IS NULL
              ORDER BY (ch.kind = 'CLASS_HEADER_CORRECTED'), ch.seq DESC LOOP
        PERFORM assessment.revert_change(k.id, p_reason, p_upload, NULL);
    END LOOP;
    -- then what this rollback has freed: a change a rollback had to leave (an earlier rolled-back upload's, or this one's) is tried
    -- again only when a LATER change on the very same thing was undone just now, or was this upload's first result on that course —
    -- never because the record happens to read the same again. Repeated until a round undoes nothing, so uploads rolled back in any
    -- order end the same
    LOOP
        n_round := 0;
        FOR k IN
            SELECT c.id, c.upload_id, pu.revert_reason
              FROM assessment.past_upload_change c JOIN assessment.past_upload pu ON pu.id = c.upload_id
             WHERE c.reverted_at IS NULL AND c.kind <> 'RESULT_POSTED' AND (pu.state = 'REVERTED' OR pu.id = p_upload)
               AND CASE c.kind
                     WHEN 'CLASS_HEADER_CORRECTED' THEN EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                                                  WHERE f.offering_id = c.offering_id AND f.reverted_at >= v_started
                                                                    AND ((f.kind = 'CLASS_HEADER_CORRECTED' AND f.seq > c.seq)
                                                                         OR f.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED', 'UNITS_CORRECTED',
                                                                                       'AS_TAKEN_CORRECTED', 'AS_TAKEN_LINKED', 'CATEGORY_CORRECTED')))
                     WHEN 'REGISTRATION_ADDED' THEN EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                                              WHERE f.kind = 'ENTRY_ADDED' AND f.registration_id = c.registration_id
                                                                AND f.reverted_at >= v_started)
                     WHEN 'ENROLMENT_ADDED' THEN EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                                           WHERE f.kind = 'REGISTRATION_ADDED' AND f.student_id = c.student_id AND f.session = c.session
                                                             AND f.reverted_at >= v_started)
                     ELSE EXISTS (SELECT 1 FROM assessment.past_upload_change f
                                   WHERE f.registration_id = c.registration_id AND f.offering_id = c.offering_id AND f.seq > c.seq
                                     AND (f.reverted_at >= v_started OR (f.upload_id = p_upload AND f.kind = 'RESULT_POSTED')))
                   END
             ORDER BY (c.kind = 'CLASS_HEADER_CORRECTED'), c.seq DESC
        LOOP
            IF assessment.revert_change(k.id, CASE WHEN k.upload_id = p_upload THEN p_reason ELSE k.revert_reason END, p_upload,
                                        CASE WHEN k.upload_id = p_upload THEN NULL ELSE u.ref END) THEN
                n_round := n_round + 1;
            END IF;
        END LOOP;
        EXIT WHEN n_round = 0;
    END LOOP;
    PERFORM set_config('moaum.upload_rollback', '', true);

    -- an issued transcript that showed a course taken off (or dropped again) is flagged for review, once a student
    PERFORM credentials.flag_documents(z.student_id, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                       'A course an old-portal upload put on the record was taken off when ' || u.ref || ' was rolled back')
       FROM (SELECT DISTINCT ch.student_id FROM assessment.past_upload_change ch
              WHERE ch.reverted_at >= v_started AND ch.kind IN ('ENTRY_ADDED', 'ENTRY_REAPPROVED') AND ch.student_id IS NOT NULL
                AND catalogue.class_examined(ch.offering_id)) z;
    -- the cached academic position: nothing refreshes it when a registration or an enrolment is deleted
    PERFORM people.refresh_academic_positions(ARRAY(SELECT DISTINCT ch.student_id FROM assessment.past_upload_change ch
                                                     WHERE ch.reverted_at >= v_started AND ch.kind IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED')
                                                       AND ch.student_id IS NOT NULL))
     WHERE EXISTS (SELECT 1 FROM assessment.past_upload_change ch
                    WHERE ch.reverted_at >= v_started AND ch.kind IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED') AND ch.student_id IS NOT NULL);
    -- every answer is read from the ledger: this upload's, and each earlier rolled-back upload a change of which was undone just now
    UPDATE assessment.past_upload pu
       SET revert_counts = coalesce(pu.revert_counts, '{}'::jsonb)
                           || (SELECT jsonb_build_object('undone', count(*) FILTER (WHERE ch.reverted_at IS NOT NULL),
                                                         'left', count(*) FILTER (WHERE ch.reverted_at IS NULL))
                                 FROM assessment.past_upload_change ch WHERE ch.upload_id = pu.id)
     WHERE pu.id <> p_upload AND pu.state = 'REVERTED'
       AND EXISTS (SELECT 1 FROM assessment.past_upload_change ch WHERE ch.upload_id = pu.id AND ch.reverted_at >= v_started);
    SELECT jsonb_build_object('undone', count(*) FILTER (WHERE ch.upload_id = p_upload AND ch.reverted_at IS NOT NULL),
                              'left', count(*) FILTER (WHERE ch.upload_id = p_upload AND ch.reverted_at IS NULL),
                              'heldDropped', n_held,
                              'earlierUndone', count(*) FILTER (WHERE ch.upload_id <> p_upload AND ch.reverted_at >= v_started))
      INTO v_counts
      FROM assessment.past_upload_change ch
     WHERE ch.upload_id = p_upload OR ch.reverted_at >= v_started;
    SELECT coalesce(jsonb_agg(jsonb_build_object('kind', ch.kind, 'courseCode', ch.course_code, 'session', ch.session, 'semester', ch.semester,
                                                 'matric', (SELECT s.matric_no FROM people.student s WHERE s.id = ch.student_id), 'note', ch.revert_note)
                              ORDER BY ch.seq DESC), '[]'::jsonb)
      INTO v_left
      FROM assessment.past_upload_change ch WHERE ch.upload_id = p_upload AND ch.reverted_at IS NULL;
    UPDATE assessment.past_upload SET state = 'REVERTED', reverted_at = now(), reverted_by = v_actor, reverted_office = v_office,
           revert_reason = btrim(p_reason), revert_counts = v_counts,
           counts = assessment.past_upload_counts(p_upload)   -- its rows' statuses moved (held rows closed)
     WHERE id = p_upload;
    RETURN jsonb_build_object('ref', u.ref, 'state', 'REVERTED') || v_counts || jsonb_build_object('leftChanges', v_left);
END $$;

COMMENT ON FUNCTION assessment.revert_past_upload(uuid, text) IS
  'V771, V775: a confirmed upload rolled back from its ledger, newest change first. Each change is undone only where it is still the last word on what it changed (assessment.revert_change): an entry it added is deleted (a mark posted on it stays on its sheet as history), one it approved again goes back as it was, a correction is put back, a replaced result is restored as a new version, a class header is put back, the registration and session enrolment it made go when nothing is left on them and nothing has been done to them, the cached academic position refreshed. A later change of another upload that still stands, a result amendment, a mark entered on the portal, the Senate''s units, a Course Registration Correction, a class chosen to stand over its duplicate or a registration acted on leaves the change as it is, listed with why. A first result on a course already on record is listed for Result amendments — unless the course is itself an upload''s and that upload is rolled back too: then the result goes with the course. What an earlier rollback had to leave because of this upload is settled now (earlierUndone) — only what this rollback freed, never an unrelated change — so uploads rolled back in any order end the same. Held results go back to the nearest earlier upload still standing that held them (never to this upload''s own earlier hold), or are dropped (heldDropped); every row of the upload still reading HELD is closed. Issued transcripts are flagged. Refusals LEGACY_REVERT_OFFICE, LEGACY_UPLOAD_REASON, LEGACY_UPLOAD_STATE.';
COMMENT ON FUNCTION assessment.reconcile_legacy_holding() IS
  'V204, V771, V772, V775: every held old-portal result of a student now on the register posted (assessment.reconcile_held with no scope).';

-- ── what V771 and V772 have written since 16 November 2026, brought under the rules above ───────────────────────────────────────
--  The functions above assume their own rules of every row. Uploads made or rolled back between V771 and this migration were written
--  under V771's: these five statements put them where the new code would have left them. Each is a no-op on a database with no
--  such row.
-- (a) a hold standing under an upload already rolled back goes back to the nearest earlier holder still standing, or is dropped: the
--     reconcile never posts it and the monitor would list it as held for ever (the rollback's own rule, for rollbacks already made)
WITH dead AS MATERIALIZED (SELECT h.session, h.semester, h.matric, h.course_code, assessment.held_prior_standing(h.prior, NULL::uuid) AS j
                             FROM assessment.legacy_result_holding h JOIN assessment.past_upload pu ON pu.id = h.upload_id
                            WHERE pu.state = 'REVERTED'),
     back AS (UPDATE assessment.legacy_result_holding h
                 SET upload_id = (SELECT pu.id FROM assessment.past_upload pu WHERE pu.id = (m.j->>'upload_id')::uuid),
                     raw = m.j->'raw', as_taken = coalesce((m.j->>'as_taken')::boolean, false), loaded_at = (m.j->>'loaded_at')::timestamptz,
                     prior = CASE WHEN jsonb_typeof(m.j->'prior') = 'object' THEN m.j->'prior' END
                FROM dead m
               WHERE m.j IS NOT NULL AND h.session = m.session AND h.semester = m.semester AND h.matric = m.matric AND h.course_code = m.course_code
              RETURNING 1),
     gone AS (DELETE FROM assessment.legacy_result_holding h USING dead m
               WHERE m.j IS NULL AND h.session = m.session AND h.semester = m.semester AND h.matric = m.matric AND h.course_code = m.course_code
              RETURNING 1)
SELECT (SELECT count(*) FROM back) AS holds_handed_back, (SELECT count(*) FROM gone) AS holds_dropped;
-- (b) every row of a rolled-back upload still reading HELD is closed: V771 closed such a row only when a later holder was rolled back
UPDATE assessment.past_upload_row pr
   SET status = 'HELD_ROLLED_BACK', detail = 'Held for a student not yet on the register; not posted before the upload was rolled back'
  FROM assessment.past_upload pu
 WHERE pu.id = pr.upload_id AND pu.state = 'REVERTED' AND pr.status = 'HELD';
-- (c) a row V771's rollback closed with "the result PRU-… held before it is held again" says what happened then, as the rollback
--     words it now: the present tense stops being true when that upload is rolled back in its turn, and V771 could name the upload
--     being rolled back itself (the hold (a) has just dropped or moved)
UPDATE assessment.past_upload_row pr
   SET detail = 'Held for a student not yet on the register; dropped when the upload was rolled back'
                || CASE WHEN substring(pr.detail FROM '; the result (.*) held before it is held again$') = pu.ref THEN ''
                        ELSE '; the row went back to '
                             || CASE substring(pr.detail FROM '; the result (.*) held before it is held again$') WHEN 'an earlier upload' THEN 'an earlier hold'
                                     ELSE substring(pr.detail FROM '; the result (.*) held before it is held again$') END
                             || ', which held it before' END
  FROM assessment.past_upload pu
 WHERE pu.id = pr.upload_id AND pr.status = 'HELD_ROLLED_BACK' AND pr.detail ~ '; the result .* held before it is held again$';
-- (d) the ledger's code and title of changes already written, from the version each change names (a version is never changed; a
--     change naming none keeps what was written). A rollback reads neither: only the report and its Excel do
UPDATE assessment.past_upload_change c SET now_code = a.code_as_taken, now_title = a.title
  FROM catalogue.course_as_taken a
 WHERE a.id = c.now_as_taken AND c.kind NOT IN ('REGISTRATION_ADDED', 'ENROLMENT_ADDED', 'CLASS_HEADER_CORRECTED')
   AND (c.now_code, c.now_title) IS DISTINCT FROM (a.code_as_taken, a.title);
UPDATE assessment.past_upload_change c SET was_code = a.code_as_taken, was_title = a.title
  FROM catalogue.course_as_taken a
 WHERE a.id = c.was_as_taken AND c.kind NOT IN ('ENTRY_ADDED', 'REGISTRATION_ADDED', 'ENROLMENT_ADDED', 'CLASS_HEADER_CORRECTED')
   AND (c.was_code, c.was_title) IS DISTINCT FROM (a.code_as_taken, a.title);
-- (e) the stored counts of every closed upload, taken once more — last, after the rows' statuses have moved: an upload whose held
--     results posted before this migration read "0 changes, 0 students" on the Uploads list for good
UPDATE assessment.past_upload pu SET counts = n.counts
  FROM (SELECT u.id, assessment.past_upload_counts(u.id) AS counts FROM assessment.past_upload u WHERE u.state <> 'RUNNING' OFFSET 0) n
 WHERE pu.id = n.id AND pu.counts IS DISTINCT FROM n.counts;

COMMIT;
