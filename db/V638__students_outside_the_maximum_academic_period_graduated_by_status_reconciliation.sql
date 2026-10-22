-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V638 — Students outside the maximum academic period graduated by status reconciliation
--
--   The University's brief of 22 October 2026: a student outside the current session who has exceeded the programme's length
--   plus the configured spillover limit, and is still kept as an active student, is identified by the academic lifecycle engine
--   and the enrolment's status changed to GRADUATED — never a student already in a terminal status, never on the matriculation
--   year alone, never with the history touched, and never when the record is incomplete or conflicting.
--
--   What the portal already had (reused, not rebuilt):
--     · people.academic_position (V331, V475, V595, V598, V601, V612, V628): the cohort engine's reading of every record — the
--       effective cohort (the entry session, merged or overridden), the programme's own length and final level (the CCE route's
--       terms where that is the route), the approved deferments, the expected completion (the later of the count and the first
--       final-level record, or the Registry's pin), the sessions elapsed since it (spillover_years), the configured maximum
--       (policy.progression_setting.max_spillover_years), rule R4L and spillover_state SPILLOVER_LIMIT_REACHED beyond it;
--     · people.lifecycle_recommendation (V558): the recommendation MAXIMUM_SPILLOVER_REACHED with the desk's confidence and its
--       reasons, the completion check, the register's own signals (the matriculation number's year, the level on record);
--     · the status with its history (people.change_status, V286), the status guard (records.guard_graduated, V602), the lock a
--       GRADUATED record carries — no fee for a session after the graduation session (finance.closed_for_fees), no registration
--       draft, no carry-over (V602) — the final clearance workflow (V415), the notices (V425), the audit spine, the Student
--       Query and the statistics, which read the status (V469).
--
--   What V638 adds on those pieces:
--     · people.graduation_candidates — the students outside the maximum period: in study, spillover_years beyond the maximum,
--       with the whole timeline (admission session, cohort, programme, length, deferments, expected completion, SP1/SP2, the
--       maximum session, the current session) and a confidence for THIS rule: HIGH when the record is complete and nothing
--       conflicts; MEDIUM where the record was migrated with gaps the engine resolves (no registration on record, the level on
--       record behind the computed level, a length from the University rule); LOW — requires review, never graduated in bulk —
--       where it conflicts (entry session missing or ahead, a duplicate or missing matriculation number, the matriculation
--       number's year disagreeing with an unresolved entry session, a live deferment, a transfer, swap or programme change under
--       way, or a registration or enrolment in the current session: a student genuinely in the current session is not graduated
--       because the cohort is old);
--     · people.graduation_reconciliation_batch / _row / graduation_reconciliation — GRAD-RECON/YYYY/NNNNNN: the Academic Office's
--       (or the Registry's) act, previewed first, confirmed, executed one student at a time, each all or nothing, never twice
--       (a graduated student is skipped), every row kept with its outcome; or the portal's own act, nightly, where the
--       Directorate of ICT or the Registrar has switched automatic reconciliation on (policy.progression_setting.auto_graduation,
--       HIGH confidence only);
--     · people.graduation_reconcile — the one act: the student locked and revalidated (still in study, still outside the maximum,
--       the confidence still allowing it), a cohort decision written (rule GRADUATION_RECONCILIATION), the status changed to
--       GRADUATED on the batch as its instrument with the reason, the whole calculation kept on the reconciliation row (the
--       previous status, the cohort, the programme and its length, the deferments, the expected completion, the maximum, the
--       current session, the confidence), the graduation session recorded as the last session the student was permitted (the
--       University's own session sequence, never the calendar year), the official graduation date left for the Academic Office
--       to confirm (people.confirm_graduation_date), final clearance started where none is under way, the student told on a
--       template (STUDENT_GRADUATED_RECONCILED);
--     · records.graduation_session reads the reconciliation's session where there is no approved award, so the fee lock and the
--       registration lock of V602 close the record from the session after it; the cohort engine reads a status-reconciled
--       graduate as validated (no GRADUATED_WITHOUT_APPROVAL issue); records.correct_graduation (the Registrar's correction on a
--       reason and evidence, V602) marks the reconciliation corrected when it puts such a record back.
--   Nothing is deleted: registrations, results, the CGPA, payments, receipts, the matriculation number, the admission, programme,
--   transfer, deferment and clearance history all stay on the record. Results are never written by this act.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V638: students outside the maximum academic period graduated by status reconciliation', true);

-- ── 1 · the setting: automatic reconciliation, off until the University switches it on ──────────────────────────────────
ALTER TABLE policy.progression_setting ADD COLUMN IF NOT EXISTS auto_graduation boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN policy.progression_setting.auto_graduation IS
  'V638: when true the portal graduates, each night, the students outside the maximum academic period whose record the engine reads with HIGH confidence (GRAD-RECON batches of mode AUTOMATIC); off by default — the Academic Office reconciles by hand';

CREATE FUNCTION policy.set_auto_graduation(p_on boolean) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'GRADRECON_PERSON: the automatic graduation setting is changed by a person' USING ERRCODE = '42501'; END IF;
    IF coalesce(office, '') NOT IN ('ict', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'GRADRECON_SETTING_OFFICE: automatic graduation is switched on or off by the Directorate of ICT or the Registrar' USING ERRCODE = '42501';
    END IF;
    UPDATE policy.progression_setting SET auto_graduation = coalesce(p_on, false), updated_at = now(), updated_by = who WHERE row_no;
END $fn$;
COMMENT ON FUNCTION policy.set_auto_graduation(boolean) IS 'V638: the Directorate of ICT or the Registrar switches the nightly graduation reconciliation on or off';

-- ── 2 · the template ──────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('STUDENT_GRADUATED_RECONCILED', 'Academic status reconciled to graduated',
 'To the student when the academic record reconciliation changes the enrolment''s status to GRADUATED — the maximum academic period (the programme''s length plus the permitted spillover) exceeded',
 'Your academic status has been updated to GRADUATED',
 E'Dear [FIRST_NAME],\n\nYour academic status on the University register has been updated to GRADUATED following academic record reconciliation ([BATCH]).\n\nProgramme: [PROGRAMME]\nAdmission session: [ENTRY_SESSION]\nProgramme length: [DURATION] years\nExpected completion: [EXPECTED]\nMaximum academic period: to [MAXIMUM]\nGraduation session recorded: [SESSION]\n\nYour registrations, results, payments and receipts stay on your record. Final clearance: [CLEARANCE]. Transcripts, certificates and verification are requested on the portal as before.\n\nIf you believe this is in error, write to the Academic Office quoting [BATCH].\n\nAcademic Office, Rev. Fr. Moses Orshio Adasu University, Makurdi',
 'MOAUM: your academic status is now GRADUATED following academic record reconciliation ([BATCH]). Graduation session recorded: [SESSION]. See the portal.',
 'Academic status updated to GRADUATED',
 'Your academic status has been updated to GRADUATED following academic record reconciliation ([BATCH]): [PROGRAMME], admitted [ENTRY_SESSION], maximum academic period to [MAXIMUM]. Final clearance: [CLEARANCE].',
 ARRAY['FIRST_NAME','BATCH','PROGRAMME','ENTRY_SESSION','DURATION','EXPECTED','MAXIMUM','SESSION','MATRIC','CLEARANCE'], true, 'HIGH')
ON CONFLICT (key) DO NOTHING;

-- ── 3 · the batch, its rows, the reconciliation ───────────────────────────────────────────────────────────────────────
CREATE SEQUENCE people.graduation_reconciliation_batch_seq;

CREATE TABLE people.graduation_reconciliation_batch (
    batch_ref         text PRIMARY KEY CHECK (batch_ref ~ '^GRAD-RECON/[0-9]{4}/[0-9]{6}$'),
    description       text NOT NULL,
    mode              text NOT NULL CHECK (mode IN ('MANUAL', 'AUTOMATIC')),
    effective_session text NOT NULL,
    scope             text,
    min_confidence    text NOT NULL CHECK (min_confidence IN ('HIGH', 'MEDIUM')),
    selected          int NOT NULL DEFAULT 0,
    eligible          int NOT NULL DEFAULT 0,
    review            int NOT NULL DEFAULT 0,
    graduated         int NOT NULL DEFAULT 0,
    skipped           int NOT NULL DEFAULT 0,
    refused           int NOT NULL DEFAULT 0,
    corrected         int NOT NULL DEFAULT 0,
    created_by        uuid NOT NULL,
    actor_office      text NOT NULL,
    created_at        timestamptz NOT NULL DEFAULT now(),
    executed_at       timestamptz,
    closed_at         timestamptz
);
COMMENT ON TABLE people.graduation_reconciliation_batch IS
  'V638: a graduation-status reconciliation (GRAD-RECON/YYYY/NNNNNN) — the students chosen (by hand, or every HIGH-confidence candidate when the portal runs it), how many were eligible, requiring review, graduated, skipped, refused; opened by an officer of the Academic Office or the Registry, or by the portal when automatic reconciliation is on';
SELECT audit.attach('people.graduation_reconciliation_batch');

CREATE TABLE people.graduation_reconciliation_row (
    batch_ref      text NOT NULL REFERENCES people.graduation_reconciliation_batch (batch_ref) ON DELETE CASCADE,
    student_id     uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    confidence     text NOT NULL CHECK (confidence IN ('HIGH', 'MEDIUM', 'LOW')),
    verdict        text NOT NULL CHECK (verdict IN ('ELIGIBLE', 'REVIEW')),
    reasons        text,
    outcome        text CHECK (outcome IN ('GRADUATED', 'SKIPPED', 'REFUSED')),
    note           text,
    decided_at     timestamptz,
    PRIMARY KEY (batch_ref, student_id)
);
COMMENT ON TABLE people.graduation_reconciliation_row IS 'V638: a student of a graduation-status reconciliation batch — the confidence and verdict at the preview, the outcome when executed';
SELECT audit.exempt('people.graduation_reconciliation_row', 'The rows of a graduation-status reconciliation batch; the act itself is people.graduation_reconciliation on the spine.');

CREATE TABLE people.graduation_reconciliation (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_ref            text NOT NULL REFERENCES people.graduation_reconciliation_batch (batch_ref),
    student_id           uuid NOT NULL REFERENCES people.student (id) ON DELETE CASCADE,
    previous_status      text NOT NULL,
    new_status           text NOT NULL DEFAULT 'GRADUATED',
    matric_no            text,
    entry_session        text,
    effective_cohort     text,
    cohort_source        text,
    programme_code       text,
    duration_years       int,
    final_level          int,
    current_level        int,
    deferred_sessions    int NOT NULL DEFAULT 0,
    expected_completion  text,
    max_spillover_years  int NOT NULL,
    maximum_session      text,
    current_session      text NOT NULL,
    spillover_years      int NOT NULL,
    spillover_state      text,
    confidence           text NOT NULL CHECK (confidence IN ('HIGH', 'MEDIUM')),
    confidence_reasons   text,
    graduation_session   text,
    graduation_date      date,
    date_confirmed       boolean NOT NULL DEFAULT false,
    date_confirmed_by    uuid,
    date_confirmed_at    timestamptz,
    date_note            text,
    clearance            text,
    reason               text NOT NULL,
    decision_id          uuid REFERENCES people.cohort_decision (id),
    reconciled_by        uuid NOT NULL,
    actor_office         text NOT NULL,
    reconciled_at        timestamptz NOT NULL DEFAULT now(),
    corrected_at         timestamptz,
    corrected_by         uuid,
    correction_reason    text,
    CONSTRAINT ck_gradrecon_corrected CHECK ((corrected_at IS NULL) = (corrected_by IS NULL))
);
CREATE INDEX ix_graduation_reconciliation_student ON people.graduation_reconciliation (student_id, reconciled_at DESC);
CREATE INDEX ix_graduation_reconciliation_batch ON people.graduation_reconciliation (batch_ref);
CREATE UNIQUE INDEX ux_graduation_reconciliation_standing ON people.graduation_reconciliation (student_id) WHERE corrected_at IS NULL;
COMMENT ON TABLE people.graduation_reconciliation IS
  'V638: a student''s enrolment reconciled to GRADUATED for having exceeded the maximum academic period — the whole calculation as it stood (the status before, the cohort, the programme and its length, the deferments, the expected completion, the maximum, the current session, the confidence), the graduation session recorded (the last permitted session), the official date once the Academic Office confirms it, the clearance started, who reconciled it and on which batch; corrected rows stay';
SELECT audit.attach('people.graduation_reconciliation');

-- ── 4 · who acts ──────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.graduation_reconciliation_actor() RETURNS uuid
LANGUAGE plpgsql STABLE AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'GRADRECON_PERSON: a graduation-status reconciliation is the act of a person, or of the portal on the University''s setting' USING ERRCODE = '42501'; END IF;
    IF coalesce(office, '') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'GRADRECON_OFFICE: graduation-status reconciliation is the Academic Office''s and the Registry''s' USING ERRCODE = '42501',
            HINT = 'Deans, Heads of Department, Records and ICT read the list and the history; the Academic Office acts on it.';
    END IF;
    RETURN who;
END $fn$;

-- ── 5 · the candidates: outside the maximum academic period, with the timeline and a confidence for this rule ───────────
CREATE FUNCTION people.graduation_candidates(p_fac text, p_dept text, p_prog text, p_q text, p_confidence text, p_students uuid[], p_limit int)
RETURNS TABLE (
    student_id uuid, matric_no text, jamb_reg_no text, surname text, other_names text, status text,
    programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text,
    entry_session text, matric_year int, effective_cohort text, cohort_source text, entry_level int,
    duration_years int, duration_source text, final_level int, current_level int, computed_level int,
    current_session text, deferred_sessions int, live_deferment boolean, expected_completion text, sp1_session text, sp2_session text,
    max_spillover_years int, maximum_session text, spillover_years int, spillover_state text,
    registered_current boolean, enrolled_current boolean, last_session text, completion text,
    programme_moves int, pending_moves text, issues text[],
    confidence text, confidence_reasons text, recommendation text)
LANGUAGE sql STABLE AS $fn$
    WITH cfg AS (SELECT max_spillover_years FROM policy.progression_setting WHERE row_no),
    cand AS (
        SELECT ap.*, cfg.max_spillover_years AS max_spill
          FROM people.academic_position ap CROSS JOIN cfg
          JOIN people.student s ON s.id = ap.student_id
         WHERE s.status IN ('ACTIVE', 'PROBATION') AND s.duplicate_of IS NULL
           AND ap.current_session IS NOT NULL AND ap.spillover_years > cfg.max_spillover_years
           AND (p_students IS NULL OR ap.student_id = ANY (p_students))),
    full_row AS (
        SELECT c.student_id, s.matric_no, s.jamb_reg_no, s.surname, s.other_names, s.status,
               s.programme_code, p.name AS programme, p.dept_code, d.name AS department, p.faculty_code, f.name AS faculty,
               c.entry_session, c.matric_year, c.effective_cohort, c.cohort_source, c.entry_level,
               c.duration_years, coalesce(r.duration_source, CASE WHEN p.duration_years IS NOT NULL OR p.final_level IS NOT NULL THEN 'PROGRAMME' ELSE 'UNIVERSITY_RULE' END) AS duration_source,
               c.final_level, c.current_level, c.computed_level,
               c.current_session, c.deferred_sessions, coalesce(df.live, false) AS live_deferment, c.expected_completion,
               policy.session_after(c.expected_completion, 1) AS sp1_session,
               policy.session_after(c.expected_completion, 2) AS sp2_session,
               c.max_spill AS max_spillover_years, policy.session_after(c.expected_completion, c.max_spill) AS maximum_session,
               c.spillover_years, c.spillover_state, c.registered_current, c.enrolled_current, c.last_session, lc.completion,
               coalesce(mv.moves, 0) AS programme_moves, pm.pending AS pending_moves, c.issues,
               coalesce(r.matric_year_differs, false) AS matric_year_differs, coalesce(r.level_conflict, false) AS level_conflict,
               r.recommendation AS lifecycle_recommendation
          FROM cand c
          JOIN people.student s ON s.id = c.student_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN people.lifecycle_recommendation r ON r.student_id = c.student_id
          LEFT JOIN people.lifecycle_completion lc ON lc.student_id = c.student_id
          LEFT JOIN LATERAL (SELECT bool_or(x.state = 'ACTIVE') AS live FROM people.deferment x WHERE x.student_id = c.student_id AND x.state IN ('APPROVED', 'ACTIVE')) df ON true
          -- the completed moves of programme (transfers, swaps, record moves), counted on their own tables: people.programme_history also reads
          -- the audit trail, too heavy for every candidate at once
          LEFT JOIN LATERAL (SELECT ((SELECT count(*) FROM people.transfer_application t WHERE t.student_id = c.student_id AND t.state = 'EFFECTED')
                                   + (SELECT count(*) FROM people.programme_swap x WHERE x.student_id = c.student_id AND x.status = 'COMPLETED')
                                   + (SELECT count(*) FROM people.record_move m WHERE m.student_id = c.student_id))::int AS moves) mv ON true
          LEFT JOIN LATERAL (
              SELECT nullif(concat_ws('; ',
                  CASE WHEN EXISTS (SELECT 1 FROM people.transfer_application ta WHERE ta.student_id = c.student_id
                                       AND ta.state IN ('APPLIED', 'FROM_OK', 'TO_OK', 'REG_OK', 'APPROVED', 'RECOMMENDED')) THEN 'an inter-departmental transfer under way' END,
                  CASE WHEN EXISTS (SELECT 1 FROM people.programme_swap w WHERE w.student_id = c.student_id AND w.status = 'PENDING_APPROVAL') THEN 'a programme swap pending' END,
                  CASE WHEN EXISTS (SELECT 1 FROM people.university_transfer u WHERE u.student_id = c.student_id AND u.status = 'PENDING_APPROVAL') THEN 'an inter-university transfer pending' END,
                  CASE WHEN s.candidate_id IS NOT NULL AND EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.candidate_id = s.candidate_id AND q.state = 'REQUESTED')
                       THEN 'a change of programme requested at the admission desk' END), '') AS pending) pm ON true
         WHERE (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
           AND (p_q IS NULL OR btrim(p_q) = '' OR s.matric_no ILIKE '%' || btrim(p_q) || '%' OR s.jamb_reg_no ILIKE '%' || btrim(p_q) || '%'
                OR (s.surname || ' ' || s.other_names) ILIKE '%' || btrim(p_q) || '%' OR (s.other_names || ' ' || s.surname) ILIKE '%' || btrim(p_q) || '%')),
    judged AS (
        SELECT fr.*,
               array_remove(ARRAY[
                   -- LOW: the record conflicts or is incomplete — never graduated in bulk
                   CASE WHEN fr.entry_session IS NULL THEN 'LOW: no entry session on the record' END,
                   CASE WHEN fr.issues && ARRAY['ENTRY_SESSION_INVALID', 'ENTRY_SESSION_AHEAD'] THEN 'LOW: the entry session is not a session of the University, or is ahead of the current one' END,
                   CASE WHEN fr.duration_years IS NULL THEN 'LOW: the programme''s length is not configured' END,
                   CASE WHEN 'DUPLICATE_MATRIC' = ANY (fr.issues) THEN 'LOW: another student holds the same matriculation number' END,
                   CASE WHEN fr.matric_no IS NULL THEN 'LOW: no matriculation number on the record' END,
                   CASE WHEN fr.matric_year_differs AND fr.cohort_source = 'ENTRY' THEN 'LOW: the matriculation number''s year (' || fr.matric_year || ') disagrees with the entry session ' || fr.entry_session || ' and nothing resolves it' END,
                   CASE WHEN fr.live_deferment THEN 'LOW: a deferment is in force' END,
                   CASE WHEN fr.pending_moves IS NOT NULL THEN 'LOW: ' || fr.pending_moves END,
                   CASE WHEN fr.registered_current OR fr.enrolled_current THEN 'LOW: registered or enrolled for ' || fr.current_session || ' — a student in the current session is not graduated for an old cohort' END,
                   CASE WHEN fr.lifecycle_recommendation IN ('DATA_INCOMPLETE', 'REQUIRES_REVIEW') THEN 'LOW: the lifecycle desk reads the record as ' || lower(replace(fr.lifecycle_recommendation, '_', ' ')) END,
                   -- MEDIUM: migrated with gaps the engine resolves — the Academic Office''s review recommended
                   CASE WHEN fr.last_session IS NULL THEN 'MEDIUM: no course registration or enrolment on record' END,
                   CASE WHEN fr.level_conflict THEN 'MEDIUM: the level on record (' || fr.current_level || ') is not the computed level (' || fr.computed_level || ')' END,
                   CASE WHEN fr.duration_source = 'UNIVERSITY_RULE' THEN 'MEDIUM: the programme''s length is the University rule, not set on the programme' END,
                   CASE WHEN fr.matric_year_differs AND fr.cohort_source <> 'ENTRY' THEN 'MEDIUM: the matriculation number''s year differs from the entry session; the cohort is ' || lower(fr.cohort_source) END,
                   CASE WHEN fr.completion = 'OUTSTANDING_COURSES' THEN 'MEDIUM: a carry-over is still on the record (results are never written by the reconciliation)' END
               ]::text[], NULL) AS reasons
          FROM full_row fr),
    rated AS (
        SELECT j.*,
               CASE WHEN EXISTS (SELECT 1 FROM unnest(j.reasons) x WHERE x LIKE 'LOW:%') THEN 'LOW'
                    WHEN cardinality(j.reasons) > 0 THEN 'MEDIUM' ELSE 'HIGH' END AS confidence
          FROM judged j)
    SELECT r.student_id, r.matric_no, r.jamb_reg_no, r.surname, r.other_names, r.status,
           r.programme_code, r.programme, r.dept_code, r.department, r.faculty_code, r.faculty,
           r.entry_session, r.matric_year, r.effective_cohort, r.cohort_source, r.entry_level,
           r.duration_years, r.duration_source, r.final_level, r.current_level, r.computed_level,
           r.current_session, r.deferred_sessions, r.live_deferment, r.expected_completion, r.sp1_session, r.sp2_session,
           r.max_spillover_years, r.maximum_session, r.spillover_years, r.spillover_state,
           r.registered_current, r.enrolled_current, r.last_session, r.completion,
           r.programme_moves, r.pending_moves, r.issues,
           r.confidence, nullif(array_to_string(r.reasons, '; '), ''),
           CASE WHEN r.confidence = 'LOW' THEN 'REQUIRES_REVIEW' ELSE 'GRADUATED' END
      FROM rated r
     WHERE p_confidence IS NULL OR r.confidence = p_confidence
     ORDER BY r.surname, r.other_names
     LIMIT greatest(1, least(coalesce(p_limit, 500), 10000))
$fn$;
COMMENT ON FUNCTION people.graduation_candidates(text, text, text, text, text, uuid[], int) IS
  'V638: the students outside the maximum academic period (in study, the sessions since the expected completion beyond the configured spillover limit) with the timeline the cohort engine computed and a confidence for the graduation-status rule: HIGH (complete, nothing conflicting), MEDIUM (migrated gaps the engine resolves — review recommended), LOW (conflicting or missing: requires review, never graduated in bulk)';

-- ── 6 · the figures for the Academic Office's cards ──────────────────────────────────────────────────────────────────
CREATE FUNCTION people.graduation_reconciliation_figures(p_fac text, p_dept text, p_prog text) RETURNS jsonb
LANGUAGE sql STABLE AS $fn$
    WITH st AS (SELECT s.id, s.status FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
                 WHERE s.duplicate_of IS NULL AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)),
         ap AS (SELECT a.* FROM people.academic_position a JOIN st ON st.id = a.student_id WHERE st.status IN ('ACTIVE', 'PROBATION')),
         lr AS (SELECT r.recommendation FROM people.lifecycle_recommendation r JOIN st ON st.id = r.student_id),
         c AS (SELECT confidence FROM people.graduation_candidates(p_fac, p_dept, p_prog, NULL, NULL, NULL, 10000)),
         g AS (SELECT g.student_id, g.batch_ref, b.mode FROM people.graduation_reconciliation g JOIN people.graduation_reconciliation_batch b ON b.batch_ref = g.batch_ref
                 JOIN st ON st.id = g.student_id WHERE g.corrected_at IS NULL)
    SELECT jsonb_build_object(
        'active', (SELECT count(*) FROM st WHERE status IN ('ACTIVE', 'PROBATION')),
        'current', (SELECT count(*) FROM ap WHERE registered_current OR enrolled_current),
        'sp1', (SELECT count(*) FROM ap WHERE spillover_state = 'SPILLOVER_YEAR_1'),
        'sp2', (SELECT count(*) FROM ap WHERE spillover_state = 'SPILLOVER_YEAR_2'),
        'outsideMaximum', (SELECT count(*) FROM c),
        'eligible', (SELECT count(*) FROM c WHERE confidence IN ('HIGH', 'MEDIUM')),
        'eligibleHigh', (SELECT count(*) FROM c WHERE confidence = 'HIGH'),
        'eligibleMedium', (SELECT count(*) FROM c WHERE confidence = 'MEDIUM'),
        'requiresReview', (SELECT count(*) FROM c WHERE confidence = 'LOW'),
        'graduationCandidates', (SELECT count(*) FROM lr WHERE recommendation = 'GRADUATION_CANDIDATE'),
        'dataIncomplete', (SELECT count(*) FROM lr WHERE recommendation = 'DATA_INCOMPLETE'),
        'graduated', (SELECT count(*) FROM st WHERE status = 'GRADUATED'),
        'graduatedByReconciliation', (SELECT count(*) FROM g),
        'graduatedAutomatically', (SELECT count(*) FROM g WHERE mode = 'AUTOMATIC'),
        'maxSpilloverYears', (SELECT max_spillover_years FROM policy.progression_setting WHERE row_no),
        'autoGraduation', (SELECT auto_graduation FROM policy.progression_setting WHERE row_no),
        'currentSession', (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1),
        'lastAutomaticRun', (SELECT max(executed_at) FROM people.graduation_reconciliation_batch WHERE mode = 'AUTOMATIC'))
$fn$;
COMMENT ON FUNCTION people.graduation_reconciliation_figures(text, text, text) IS 'V638: the Graduation Management cards within a scope — active, current, SP1, SP2, outside the maximum period (eligible by confidence, requiring review), graduation candidates, data incomplete, graduated (by reconciliation, automatically), the setting';

-- ── 7 · a batch opened with its rows ──────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.graduation_reconciliation_open(p_description text, p_mode text, p_include_medium boolean, p_students uuid[], p_fac text, p_dept text, p_prog text, p_q text)
RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := people.graduation_reconciliation_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ref text; v_session text; v_mode text := coalesce(upper(p_mode), 'MANUAL'); v_min text; n_sel int; n_el int; n_rv int;
BEGIN
    IF btrim(coalesce(p_description, '')) = '' THEN
        RAISE EXCEPTION 'GRADRECON_DESCRIPTION: a reconciliation batch says what it is for' USING ERRCODE = '23514';
    END IF;
    IF v_mode NOT IN ('MANUAL', 'AUTOMATIC') THEN RAISE EXCEPTION 'GRADRECON_MODE: a batch is MANUAL or AUTOMATIC' USING ERRCODE = '23514'; END IF;
    SELECT name INTO v_session FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1;
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'GRADRECON_NO_SESSION: no session is current; the maximum academic period is counted to the current session' USING ERRCODE = '23514';
    END IF;
    IF v_mode = 'AUTOMATIC' AND NOT (SELECT auto_graduation FROM policy.progression_setting WHERE row_no) THEN
        RAISE EXCEPTION 'GRADRECON_AUTO_OFF: automatic graduation reconciliation is switched off' USING ERRCODE = '23514';
    END IF;
    -- the portal's own run takes HIGH confidence alone; an officer may include the MEDIUM records after reading them
    v_min := CASE WHEN v_mode = 'AUTOMATIC' OR NOT coalesce(p_include_medium, false) THEN 'HIGH' ELSE 'MEDIUM' END;
    v_ref := 'GRAD-RECON/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('people.graduation_reconciliation_batch_seq')::text, 6, '0');
    INSERT INTO people.graduation_reconciliation_batch (batch_ref, description, mode, effective_session, scope, min_confidence, created_by, actor_office)
    VALUES (v_ref, btrim(p_description), v_mode, v_session,
            nullif(concat_ws(' · ', 'faculty ' || p_fac, 'department ' || p_dept, 'programme ' || p_prog, 'search "' || nullif(btrim(coalesce(p_q, '')), '') || '"',
                             CASE WHEN p_students IS NOT NULL THEN cardinality(p_students) || ' chosen' END), ''),
            v_min, who, office);
    INSERT INTO people.graduation_reconciliation_row (batch_ref, student_id, confidence, verdict, reasons)
    SELECT v_ref, c.student_id, c.confidence,
           CASE WHEN c.confidence = 'HIGH' OR (c.confidence = 'MEDIUM' AND v_min = 'MEDIUM') THEN 'ELIGIBLE' ELSE 'REVIEW' END,
           c.confidence_reasons
      FROM people.graduation_candidates(p_fac, p_dept, p_prog, p_q, NULL, p_students, 10000) c;
    SELECT count(*), count(*) FILTER (WHERE verdict = 'ELIGIBLE'), count(*) FILTER (WHERE verdict = 'REVIEW') INTO n_sel, n_el, n_rv
      FROM people.graduation_reconciliation_row WHERE batch_ref = v_ref;
    IF n_sel = 0 THEN RAISE EXCEPTION 'GRADRECON_NOBODY: no student outside the maximum academic period matches the choice' USING ERRCODE = '23514'; END IF;
    UPDATE people.graduation_reconciliation_batch SET selected = n_sel, eligible = n_el, review = n_rv WHERE batch_ref = v_ref;
    RETURN v_ref;
END $fn$;
COMMENT ON FUNCTION people.graduation_reconciliation_open(text, text, boolean, uuid[], text, text, text, text) IS
  'V638: a graduation-status reconciliation batch opened (GRAD-RECON/YYYY/NNNNNN) with the students chosen — by id, or every candidate of a scope and search — each row with its confidence and verdict (ELIGIBLE: HIGH, or MEDIUM when the officer includes them; REVIEW otherwise); nothing on any student changes here';

-- ── 8 · the one act ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.graduation_reconcile(p_batch text, p_student uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := people.graduation_reconciliation_actor(); office text := nullif(current_setting('moaum.actor_office', true), '');
        b people.graduation_reconciliation_batch; s people.student; c record; v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
        v_dec uuid; v_id uuid; v_proc uuid; v_clear text; v_err text; reach record; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; v_first text;
BEGIN
    SELECT * INTO b FROM people.graduation_reconciliation_batch WHERE batch_ref = p_batch FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRADRECON_BATCH: no reconciliation batch %', p_batch USING ERRCODE = '23514'; END IF;
    IF b.closed_at IS NOT NULL THEN RAISE EXCEPTION 'GRADRECON_BATCH_CLOSED: batch % is closed', p_batch USING ERRCODE = '23514'; END IF;
    IF b.created_by <> who THEN RAISE EXCEPTION 'GRADRECON_BATCH_OWNER: a batch is executed by the officer who opened it' USING ERRCODE = '42501'; END IF;
    v_reason := coalesce(v_reason, 'Student exceeded the maximum academic period (' || b.description || ')');
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRADRECON_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    IF s.status = 'GRADUATED' THEN
        UPDATE people.graduation_reconciliation_row SET outcome = 'SKIPPED', note = 'Already graduated', decided_at = now() WHERE batch_ref = p_batch AND student_id = p_student;
        UPDATE people.graduation_reconciliation_batch SET skipped = skipped + 1 WHERE batch_ref = p_batch;
        RETURN jsonb_build_object('outcome', 'SKIPPED', 'why', 'Already graduated');
    END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION') THEN
        RAISE EXCEPTION 'GRADRECON_STATUS: the record reads % — only an active record is reconciled to graduated', lower(replace(s.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    -- revalidated now, on the record as it stands: still outside the maximum, the confidence still allowing it
    SELECT * INTO c FROM people.graduation_candidates(NULL, NULL, NULL, NULL, NULL, ARRAY[p_student], 1);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GRADRECON_NOT_OUTSIDE: the record no longer reads outside the maximum academic period' USING ERRCODE = '23514',
            HINT = 'The cohort, the length, a deferment or the expected completion changed since the preview.';
    END IF;
    IF c.confidence = 'LOW' THEN
        RAISE EXCEPTION 'GRADRECON_REVIEW: requires review — %', c.confidence_reasons USING ERRCODE = '23514';
    END IF;
    IF b.min_confidence = 'HIGH' AND c.confidence <> 'HIGH' THEN
        RAISE EXCEPTION 'GRADRECON_CONFIDENCE: % confidence — %; the batch takes high confidence alone', lower(c.confidence), c.confidence_reasons USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', left('Graduation reconciliation ' || p_batch || ': ' || v_reason, 2000), true);
    INSERT INTO people.cohort_decision (student_id, previous_status, proposed_status, final_status, classification, previous_cohort, effective_cohort,
                                        previous_level, new_level, rule, reason, officer, actor_office, batch_ref)
    VALUES (p_student, s.status, 'GRADUATED', 'GRADUATED', 'OUTSIDE_MAXIMUM_PERIOD', c.entry_session, c.effective_cohort,
            s.current_level, s.current_level, 'GRADUATION_RECONCILIATION', v_reason, who, office, p_batch)
    RETURNING id INTO v_dec;
    PERFORM people.change_status(p_student, 'GRADUATED', 'Graduation reconciliation ' || p_batch, v_today, v_reason);
    INSERT INTO people.graduation_reconciliation (batch_ref, student_id, previous_status, matric_no, entry_session, effective_cohort, cohort_source, programme_code,
                                                  duration_years, final_level, current_level, deferred_sessions, expected_completion, max_spillover_years, maximum_session,
                                                  current_session, spillover_years, spillover_state, confidence, confidence_reasons, graduation_session, reason, decision_id,
                                                  reconciled_by, actor_office)
    VALUES (p_batch, p_student, s.status, s.matric_no, c.entry_session, c.effective_cohort, c.cohort_source, s.programme_code,
            c.duration_years, c.final_level, s.current_level, c.deferred_sessions, c.expected_completion, c.max_spillover_years, c.maximum_session,
            c.current_session, c.spillover_years, c.spillover_state, c.confidence, c.confidence_reasons, c.maximum_session, v_reason, v_dec, who, office)
    RETURNING id INTO v_id;
    -- final clearance begins where none is under way (an engine refusal is recorded, never fatal — as V602 has it)
    SELECT q.id INTO v_proc FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = p_student AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1;
    IF v_proc IS NOT NULL THEN
        v_clear := 'under way';
    ELSE
        BEGIN
            v_proc := clearance.start('FINAL', p_student, coalesce(c.maximum_session, c.current_session), 'ELIGIBLE', NULL, who, office);
            v_clear := 'started';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_clear := 'not started — ' || left(v_err, 160);
        END;
    END IF;
    UPDATE people.graduation_reconciliation SET clearance = v_clear WHERE id = v_id;
    -- the engine reads the record again now the reconciliation stands (the status change recomputed it a moment before the row existed)
    PERFORM people.refresh_academic_positions(ARRAY[p_student]);
    UPDATE people.graduation_reconciliation_row SET outcome = 'GRADUATED', note = 'Graduated; final clearance ' || v_clear, decided_at = now()
     WHERE batch_ref = p_batch AND student_id = p_student;
    UPDATE people.graduation_reconciliation_batch SET graduated = graduated + 1 WHERE batch_ref = p_batch;
    -- the student told on the template; the status change itself was told by people.change_status
    SELECT * INTO reach FROM people.student_reach(p_student);
    v_first := coalesce(nullif(split_part(coalesce(s.other_names, ''), ' ', 1), ''), s.surname);
    PERFORM platform.notify('STUDENT_GRADUATED_RECONCILED', NULL, jsonb_build_object(
                'FIRST_NAME', v_first, 'BATCH', p_batch, 'PROGRAMME', coalesce(c.programme, s.programme_code), 'ENTRY_SESSION', coalesce(c.entry_session, '—'),
                'DURATION', coalesce(c.duration_years::text, '—'), 'EXPECTED', coalesce(c.expected_completion, '—'), 'MAXIMUM', coalesce(c.maximum_session, '—'),
                'SESSION', coalesce(c.maximum_session, '—'), 'MATRIC', coalesce(s.matric_no, s.admission_no, ''),
                'CLEARANCE', CASE WHEN v_clear IN ('started', 'under way') THEN 'under way; each office clears you against your record' ELSE 'to be started by the Registry' END),
            'student', p_student, reach.email, reach.phone, 'graduation-reconciled:' || p_student);
    RETURN jsonb_build_object('outcome', 'GRADUATED', 'id', v_id, 'session', c.maximum_session, 'clearance', v_clear, 'confidence', c.confidence);
END $fn$;
COMMENT ON FUNCTION people.graduation_reconcile(text, uuid, text) IS
  'V638: one student''s enrolment reconciled to GRADUATED on a batch — revalidated (in study, still outside the maximum, the confidence the batch allows), a cohort decision (GRADUATION_RECONCILIATION), the status changed on the batch as the instrument with its history, the calculation kept, the graduation session the last permitted one, final clearance started, the student told; a graduated student is skipped, never changed twice';

-- ── 9 · a step of the execution, the close, the official date ────────────────────────────────────────────────────────
CREATE FUNCTION people.graduation_reconciliation_run(p_batch text, p_reason text, p_limit int) RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := people.graduation_reconciliation_actor(); b people.graduation_reconciliation_batch; r record; res jsonb;
        n_grad int := 0; n_skip int := 0; n_ref int := 0; v_refused jsonb := '[]'::jsonb; v_msg text; v_left int;
BEGIN
    SELECT * INTO b FROM people.graduation_reconciliation_batch WHERE batch_ref = p_batch;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRADRECON_BATCH: no reconciliation batch %', p_batch USING ERRCODE = '23514'; END IF;
    IF b.closed_at IS NOT NULL THEN RAISE EXCEPTION 'GRADRECON_BATCH_CLOSED: batch % is closed', p_batch USING ERRCODE = '23514'; END IF;
    IF b.created_by <> who THEN RAISE EXCEPTION 'GRADRECON_BATCH_OWNER: a batch is executed by the officer who opened it' USING ERRCODE = '42501'; END IF;
    FOR r IN SELECT x.student_id FROM people.graduation_reconciliation_row x JOIN people.student s ON s.id = x.student_id
              WHERE x.batch_ref = p_batch AND x.verdict = 'ELIGIBLE' AND x.outcome IS NULL
              ORDER BY s.surname, s.other_names LIMIT greatest(1, least(coalesce(p_limit, 200), 1000)) LOOP
        BEGIN
            res := people.graduation_reconcile(p_batch, r.student_id, p_reason);
            IF res->>'outcome' = 'GRADUATED' THEN n_grad := n_grad + 1; ELSE n_skip := n_skip + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
            UPDATE people.graduation_reconciliation_row SET outcome = 'REFUSED', note = left(v_msg, 400), decided_at = now()
             WHERE batch_ref = p_batch AND student_id = r.student_id;
            n_ref := n_ref + 1;
            v_refused := v_refused || jsonb_build_object('student', r.student_id, 'code', split_part(v_msg, ':', 1), 'why', btrim(substr(v_msg, position(':' IN v_msg) + 1)));
        END;
    END LOOP;
    UPDATE people.graduation_reconciliation_batch SET refused = graduation_reconciliation_batch.refused + n_ref WHERE batch_ref = p_batch;
    SELECT count(*) INTO v_left FROM people.graduation_reconciliation_row WHERE batch_ref = p_batch AND verdict = 'ELIGIBLE' AND outcome IS NULL;
    IF v_left = 0 THEN
        UPDATE people.graduation_reconciliation_batch SET executed_at = coalesce(executed_at, now()) WHERE batch_ref = p_batch;
        PERFORM people.tell_graduation_reconciliation(p_batch);
    END IF;
    RETURN jsonb_build_object('batchRef', p_batch, 'graduated', n_grad, 'skipped', n_skip, 'refused', v_refused, 'remaining', v_left, 'done', v_left = 0);
END $fn$;
COMMENT ON FUNCTION people.graduation_reconciliation_run(text, text, int) IS 'V638: one step of a batch — up to the limit of its eligible rows reconciled, each on its own (a refusal is kept on the row and the rest go on); the Bursary and the Students Account Office told once the batch is done';

-- the Bursary and the Students Account Office told once a batch leaves graduates for financial clearance (V602's template)
CREATE FUNCTION people.tell_graduation_reconciliation(p_ref text) RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE b people.graduation_reconciliation_batch; p record; v_told int := 0; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT * INTO b FROM people.graduation_reconciliation_batch WHERE batch_ref = p_ref;
    IF NOT FOUND OR b.graduated = 0 THEN RETURN 0; END IF;
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code IN ('bursar', 'studentaccounts') AND oa.valid_from <= v_today AND (oa.valid_to IS NULL OR oa.valid_to >= v_today) LOOP
        v_told := v_told + platform.tell_person(p.person_id, 'GRADUATION_CLEARANCE_WAITING', NULL,
                      jsonb_build_object('COUNT', b.graduated, 'BATCH', b.batch_ref, 'SESSION', b.effective_session, 'MINUTE', 'academic record reconciliation'),
                      'graduation-clearance:' || b.batch_ref || ':' || b.graduated || ':' || p.person_id);
    END LOOP;
    RETURN v_told;
END $fn$;

CREATE FUNCTION people.graduation_reconciliation_close(p_batch text) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := people.graduation_reconciliation_actor(); b people.graduation_reconciliation_batch;
BEGIN
    SELECT * INTO b FROM people.graduation_reconciliation_batch WHERE batch_ref = p_batch FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRADRECON_BATCH: no reconciliation batch %', p_batch USING ERRCODE = '23514'; END IF;
    IF b.created_by <> who AND coalesce(nullif(current_setting('moaum.actor_office', true), ''), '') NOT IN ('registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'GRADRECON_BATCH_OWNER: a batch is closed by the officer who opened it, or the Registrar' USING ERRCODE = '42501';
    END IF;
    UPDATE people.graduation_reconciliation_batch SET closed_at = coalesce(closed_at, now()) WHERE batch_ref = p_batch;
END $fn$;

CREATE FUNCTION people.confirm_graduation_date(p_student uuid, p_date date, p_session text, p_note text) RETURNS jsonb
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := people.graduation_reconciliation_actor(); g people.graduation_reconciliation;
BEGIN
    SELECT * INTO g FROM people.graduation_reconciliation WHERE student_id = p_student AND corrected_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRADRECON_NOT_RECONCILED: the student was not graduated by status reconciliation' USING ERRCODE = '23514'; END IF;
    IF p_date IS NULL THEN RAISE EXCEPTION 'GRADRECON_DATE: give the official graduation date' USING ERRCODE = '23514'; END IF;
    IF p_session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session AND a.state <> 'CANCELLED') THEN
        RAISE EXCEPTION 'GRADRECON_SESSION: % is not a session of the University', p_session USING ERRCODE = '23514';
    END IF;
    UPDATE people.graduation_reconciliation
       SET graduation_date = p_date, graduation_session = coalesce(p_session, graduation_session), date_confirmed = true,
           date_confirmed_by = who, date_confirmed_at = now(), date_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = g.id;
    RETURN jsonb_build_object('id', g.id, 'graduationDate', p_date, 'graduationSession', coalesce(p_session, g.graduation_session));
END $fn$;
COMMENT ON FUNCTION people.confirm_graduation_date(uuid, date, text, text) IS 'V638: the Academic Office confirms the official graduation date (and session) of a status-reconciled graduate — the reconciliation records the last permitted session until then';

-- the reconciled graduates grouped for the reports
CREATE FUNCTION people.graduation_reconciliation_report(p_by text, p_fac text, p_dept text, p_prog text)
RETURNS TABLE (label text, graduated bigint, automatic bigint, high bigint, medium bigint, date_confirmed bigint, cleared bigint, clearance_pending bigint)
LANGUAGE sql STABLE AS $fn$
    SELECT CASE coalesce(p_by, 'faculty')
             WHEN 'department' THEN coalesce(d.name, p.dept_code, '—')
             WHEN 'programme' THEN coalesce(p.name, g.programme_code, '—')
             WHEN 'entry' THEN coalesce(g.entry_session, '—')
             WHEN 'session' THEN coalesce(g.graduation_session, '—')
             WHEN 'spillover' THEN coalesce(g.spillover_state, '—')
             WHEN 'batch' THEN g.batch_ref
             ELSE coalesce(f.name, p.faculty_code, '—') END AS label,
           count(*), count(*) FILTER (WHERE b.mode = 'AUTOMATIC'), count(*) FILTER (WHERE g.confidence = 'HIGH'), count(*) FILTER (WHERE g.confidence = 'MEDIUM'),
           count(*) FILTER (WHERE g.date_confirmed),
           count(*) FILTER (WHERE q.completed_at IS NOT NULL), count(*) FILTER (WHERE q.id IS NOT NULL AND q.completed_at IS NULL)
      FROM people.graduation_reconciliation g
      JOIN people.graduation_reconciliation_batch b ON b.batch_ref = g.batch_ref
      LEFT JOIN ref.programme p ON p.code = g.programme_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN LATERAL (SELECT q.id, q.completed_at FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = g.student_id AND q.cancelled_at IS NULL
                          ORDER BY q.started_at DESC LIMIT 1) q ON true
     WHERE g.corrected_at IS NULL
       AND (p_fac IS NULL OR p.faculty_code = p_fac) AND (p_dept IS NULL OR p.dept_code = p_dept) AND (p_prog IS NULL OR p.code = p_prog)
     GROUP BY 1 ORDER BY 1
$fn$;

-- ── 10 · the graduation session of a status-reconciled graduate: the lock of V602 reads it ───────────────────────────
CREATE OR REPLACE FUNCTION records.graduation_session(p_student uuid) RETURNS text
LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT max(g.session) FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED'),
                    (SELECT r.graduation_session FROM people.graduation_reconciliation r WHERE r.student_id = p_student AND r.corrected_at IS NULL),
                    (SELECT max(x.session) FROM (SELECT e.session FROM people.enrolment e WHERE e.student_id = p_student
                                                 UNION ALL
                                                 SELECT r.session FROM registration.course_registration r
                                                  WHERE r.student_id = p_student AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x))
$fn$;
COMMENT ON FUNCTION records.graduation_session(uuid) IS
  'V602, V638: the session a student graduated in — the approved award''s, else the status reconciliation''s (the last permitted session, or the official session once confirmed), else the last session on record; finance.closed_for_fees closes every later session';


-- ── 11 · the cohort engine reads a status-reconciled graduate as validated (restated from V628 as it stood, with the one join and the two conditions) ──
CREATE OR REPLACE FUNCTION people.academic_position_rows_of(p_students uuid[])
 RETURNS SETOF people.academic_position
 LANGUAGE sql
 STABLE
AS $function$
    WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' ORDER BY starts_on DESC LIMIT 1),
    -- V381: a CCE student stands in the CCE session, for the CCE duration of the programme (six years unless stated)
    cce AS (SELECT policy.route_session('CCE') AS name),
    cfg AS (SELECT max_spillover_years FROM policy.progression_setting),
    st AS (
        SELECT s.id, s.matric_no, s.jamb_reg_no, s.entry_session, s.entry_level, s.programme_code, s.current_level, s.status, s.candidate_id, s.entry_mode,
               s.duplicate_of IS NOT NULL AS ended_duplicate,
               c.session AS candidate_session,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE p.final_level END AS configured_final,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.duration_years ELSE p.duration_years END AS configured_years,
               CASE WHEN s.entry_mode = 'CCE' THEN rt.final_level ELSE finance.final_level(s.programme_code) END AS final_level,
               co.effective_cohort AS override_cohort, cx.expected_completion AS override_completion, a.name AS entry_on_calendar, a.merged_into,
               -- V638: graduated by status reconciliation (outside the maximum academic period), never corrected since
               EXISTS (SELECT 1 FROM people.graduation_reconciliation gr WHERE gr.student_id = s.id AND gr.corrected_at IS NULL) AS reconciled_graduate
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN LATERAL ref.programme_route_terms(s.programme_code, 'CCE') rt ON s.entry_mode = 'CCE'
          LEFT JOIN people.cohort_override co ON co.student_id = s.id
          LEFT JOIN people.completion_override cx ON cx.student_id = s.id
          LEFT JOIN policy.academic_session a ON a.name = s.entry_session
         WHERE p_students IS NULL OR s.id = ANY (p_students)),
    dups AS (SELECT matric_no FROM people.student WHERE matric_no IS NOT NULL GROUP BY matric_no HAVING count(*) > 1),
    defs AS (
        SELECT d.student_id,
               ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int AS sessions,
               bool_or(d.state = 'ACTIVE') AS live
          FROM people.deferment d
         WHERE d.state IN ('APPROVED','ACTIVE','COMPLETED') AND (p_students IS NULL OR d.student_id = ANY (p_students))
         GROUP BY d.student_id),
    reg AS (
        SELECT r.student_id,
               bool_or(r.session = cur.name AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cur_reg,
               bool_or(r.session = (SELECT name FROM cce) AND r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS cce_reg,
               max(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED')) AS last_reg,
               -- V595: the final year as the register shows it — the first session registered at the programme's final level
               min(r.session) FILTER (WHERE r.status IN ('SUBMITTED','APPROVED','LOCKED') AND r.level >= st.final_level) AS first_final_reg
          FROM registration.course_registration r JOIN st ON st.id = r.student_id LEFT JOIN cur ON true
         GROUP BY r.student_id),
    enr AS (
        SELECT e.student_id, bool_or(e.session = cur.name) AS cur_enr, bool_or(e.session = (SELECT name FROM cce)) AS cce_enr, max(e.session) AS last_enr,
               -- V595: and as the old portal's enrolment history shows it
               min(e.session) FILTER (WHERE e.level >= st.final_level) AS first_final_enr
          FROM people.enrolment e JOIN st ON st.id = e.student_id LEFT JOIN cur ON true
         GROUP BY e.student_id),
    grad AS (
        SELECT DISTINCT ON (g.student_id) g.student_id, g.session, g.senate_state, g.unmet
          FROM records.graduand g
         WHERE p_students IS NULL OR g.student_id = ANY (p_students)
         ORDER BY g.student_id, (g.senate_state = 'APPROVED') DESC, g.session DESC),
    base AS (
        SELECT st.*,
               coalesce(policy.session_year(st.candidate_session),
                        CASE WHEN st.jamb_reg_no ~ '^20[0-9]{2}[0-9]{8}[A-Z]{2}$' THEN left(st.jamb_reg_no, 4)::int END,
                        policy.session_year(st.entry_session)) AS jamb_year,
               CASE WHEN st.matric_no ~ '/[0-9]{2}/' THEN 2000 + (regexp_match(st.matric_no, '/([0-9]{2})/'))[1]::int END AS matric_year,
               coalesce(st.override_cohort, policy.effective_session(st.entry_session)) AS effective_cohort,
               CASE WHEN st.override_cohort IS NOT NULL THEN 'OVERRIDE' WHEN st.merged_into IS NOT NULL THEN 'MERGED' ELSE 'ENTRY' END AS cohort_source,
               coalesce(st.configured_years, CASE WHEN st.configured_final IS NOT NULL THEN greatest((st.configured_final - coalesce(st.entry_level, 100)) / 100 + 1, 1) END) AS duration_years,
               st.configured_final IS NOT NULL AS level_based,
               coalesce(d.sessions, 0) AS deferred_sessions, coalesce(d.live, false) AS live_deferment,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN r.cce_reg ELSE r.cur_reg END, false) AS registered_current, greatest(r.last_reg, e.last_enr) AS last_session,
               coalesce(CASE WHEN st.entry_mode = 'CCE' THEN e.cce_enr ELSE e.cur_enr END, false) AS enrolled_current,
               least(r.first_final_reg, e.first_final_enr) AS first_final,
               g.senate_state AS graduation_state, g.session AS graduation_session, g.unmet AS graduation_unmet, g.student_id IS NOT NULL AS has_graduand,
               st.matric_no IN (SELECT matric_no FROM dups) AS dup_matric,
               CASE WHEN st.entry_mode = 'CCE' THEN (SELECT name FROM cce) ELSE (SELECT name FROM cur) END AS current_session, (SELECT max_spillover_years FROM cfg) AS max_spill
          FROM st LEFT JOIN defs d ON d.student_id = st.id LEFT JOIN reg r ON r.student_id = st.id
               LEFT JOIN enr e ON e.student_id = st.id LEFT JOIN grad g ON g.student_id = st.id),
    -- V595: these three are materialised so the session arithmetic (policy.session_after, policy.sessions_elapsed) runs once a row —
    -- inlined, every later reference to expected_completion and spillover_years (the rule, the issues, the classification, the
    -- confidence) evaluated it again, and a pass over the whole register took ten minutes instead of seconds
    arith AS MATERIALIZED (
        SELECT b.*,
               CASE WHEN b.duration_years IS NOT NULL THEN policy.session_after(b.effective_cohort, b.duration_years - 1 + b.deferred_sessions) END AS counted_completion,
               policy.sessions_elapsed(b.effective_cohort, b.current_session) AS elapsed_sessions
          FROM base b),
    timed AS MATERIALIZED (
        -- V595: the final year is the later of the one the count of sessions gives and the first session the register (a registration,
        -- or the old portal's enrolment) shows the student at the final level — a session repeated or lost before the final level is not
        -- a spillover year; a deferment after that year still pushes the completion on; nothing is counted from before the counted year
        -- V612: an expected completion the Registry pinned on evidence is read before any count — the count of sessions and the
        -- final-year rule are set aside while it stands; deferments are in the pin as the Registry made it
        SELECT a.*,
               coalesce(a.override_completion,
               CASE WHEN a.first_final IS NOT NULL AND (a.counted_completion IS NULL OR policy.session_year(a.first_final) > policy.session_year(a.counted_completion))
                    THEN policy.session_after(a.first_final, coalesce((SELECT ceil(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session)))::numeric / 2)::int
                                                                         FROM people.deferment d
                                                                        WHERE d.student_id = a.id AND d.state IN ('APPROVED','ACTIVE','COMPLETED')
                                                                          AND policy.session_year(d.session) > policy.session_year(a.first_final)), 0))
                    ELSE a.counted_completion END) AS expected_completion
          FROM arith a),
    measured AS MATERIALIZED (
        SELECT t.*,
               greatest(0, coalesce(policy.sessions_elapsed(t.expected_completion, t.current_session), 0)) AS spillover_years,
               CASE WHEN t.elapsed_sessions IS NULL THEN NULL
                    WHEN NOT t.level_based THEN coalesce(t.entry_level, t.current_level)
                    ELSE least(t.configured_final, coalesce(t.entry_level, 100) + 100 * greatest(0, t.elapsed_sessions - t.deferred_sessions)) END AS computed_level
          FROM timed t),
    ruled AS (
        SELECT m.*,
               CASE
                 WHEN m.graduation_state = 'APPROVED' OR m.status = 'GRADUATED' THEN 'R1'
                 WHEN m.status IN ('WITHDRAWN','VOLUNTARY_WITHDRAWAL','EXPELLED','DECEASED','TRANSFERRED_OUT','RUSTICATED','SUSPENDED','DORMANT','DEFERRED','ADMITTED') THEN 'R2'
                 WHEN m.entry_session IS NULL OR policy.session_year(m.effective_cohort) IS NULL OR m.duration_years IS NULL OR m.current_session IS NULL THEN 'R6'
                 WHEN m.has_graduand AND m.graduation_unmet IS NULL AND m.graduation_state <> 'APPROVED' THEN 'R5'
                 WHEN m.spillover_years > m.max_spill THEN 'R4L'
                 WHEN m.spillover_years > 0 THEN 'R4'
                 WHEN m.registered_current OR m.enrolled_current THEN 'R3'
                 WHEN m.last_session IS NULL THEN 'R6'
                 ELSE 'R3L' END AS rule,
               array_remove(ARRAY[
                   CASE WHEN m.entry_session IS NULL THEN 'MISSING_ENTRY_SESSION' END,
                   CASE WHEN m.entry_session IS NOT NULL AND policy.session_year(m.entry_session) IS NULL THEN 'ENTRY_SESSION_INVALID' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.elapsed_sessions < 0 THEN 'ENTRY_SESSION_AHEAD' END,
                   CASE WHEN m.matric_no IS NULL AND m.status <> 'ADMITTED' AND NOT m.ended_duplicate THEN 'MISSING_MATRIC' END,
                   CASE WHEN m.jamb_reg_no IS NULL THEN 'MISSING_JAMB' END,
                   CASE WHEN m.duration_years IS NULL THEN 'DURATION_NOT_CONFIGURED' END,
                   CASE WHEN m.dup_matric THEN 'DUPLICATE_MATRIC' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.computed_level IS NOT NULL AND m.computed_level <> m.current_level THEN 'LEVEL_CONFLICT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND NOT m.registered_current AND NOT m.enrolled_current THEN 'NO_CURRENT_REGISTRATION' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.last_session IS NULL THEN 'NO_REGISTRATION_HISTORY' END,
                   CASE WHEN m.status = 'GRADUATED' AND m.graduation_state IS DISTINCT FROM 'APPROVED' AND NOT m.reconciled_graduate THEN 'GRADUATED_WITHOUT_APPROVAL' END,
                   CASE WHEN m.status <> 'GRADUATED' AND m.graduation_state = 'APPROVED' THEN 'APPROVED_NOT_GRADUATED' END,
                   CASE WHEN m.status = 'DEFERRED' AND NOT m.live_deferment THEN 'DEFERRED_WITHOUT_LIVE_DEFERMENT' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > m.max_spill THEN 'SPILLOVER_LIMIT_REACHED' END,
                   CASE WHEN m.status IN ('ACTIVE','PROBATION') AND m.spillover_years > 0 THEN 'BEYOND_PROGRAMME_LENGTH' END
               ]::text[], NULL) AS issues
          FROM measured m)
    SELECT r.id,
           r.jamb_year, r.matric_year, r.entry_session, r.effective_cohort, r.cohort_source, r.entry_level, r.programme_code, r.final_level, r.duration_years,
           r.current_session, r.current_level, r.computed_level, r.expected_completion, r.deferred_sessions, r.elapsed_sessions, r.spillover_years,
           CASE WHEN r.status NOT IN ('ACTIVE','PROBATION') THEN 'NOT_APPLICABLE'
                WHEN r.spillover_years = 0 THEN 'NORMAL'
                WHEN r.spillover_years > r.max_spill THEN 'SPILLOVER_LIMIT_REACHED'
                ELSE 'SPILLOVER_YEAR_' || least(r.spillover_years, 3) END,
           r.registered_current, r.enrolled_current, r.last_session, r.graduation_state, r.graduation_session,
           r.status,
           CASE r.rule
             WHEN 'R1'  THEN 'GRADUATED'
             WHEN 'R2'  THEN r.status
             WHEN 'R5'  THEN 'GRADUATION_ELIGIBLE'
             WHEN 'R4L' THEN 'SPILLOVER_LIMIT_REACHED'
             WHEN 'R4'  THEN 'SPILLOVER'
             WHEN 'R3'  THEN 'ACTIVE'
             WHEN 'R3L' THEN 'ACTIVE'
             ELSE 'REQUIRES_REVIEW' END,
           CASE r.rule WHEN 'R1' THEN 'GRADUATED' WHEN 'R3' THEN CASE WHEN r.status IN ('ACTIVE','PROBATION') THEN r.status ELSE 'ACTIVE' END
                       WHEN 'R3L' THEN r.status WHEN 'R4' THEN r.status WHEN 'R5' THEN r.status ELSE r.status END,
           r.rule,
           CASE
             WHEN r.rule = 'R1' AND (r.graduation_state = 'APPROVED' OR (r.reconciled_graduate AND r.status = 'GRADUATED')) AND r.status IN ('GRADUATED','ACTIVE','PROBATION') THEN 'VALIDATED'
             WHEN r.rule = 'R1' THEN 'REVIEW'
             WHEN r.rule = 'R2' AND NOT (r.status = 'DEFERRED' AND NOT r.live_deferment) THEN 'VALIDATED'
             WHEN r.rule IN ('R6', 'R4L') THEN 'REVIEW'
             WHEN r.dup_matric OR (r.status IN ('ACTIVE','PROBATION') AND r.computed_level IS NOT NULL AND r.computed_level <> r.current_level AND r.spillover_years = 0) THEN 'REVIEW'
             WHEN r.rule IN ('R3', 'R5') THEN 'VALIDATED'
             WHEN r.rule = 'R4' AND (r.registered_current OR r.enrolled_current) THEN 'VALIDATED'
             ELSE 'LIKELY' END,
           r.issues,
           now()
      FROM ruled r
$function$;
COMMENT ON FUNCTION people.academic_position_rows_of(uuid[]) IS
  'V331 (restated V463, V475, V595, V598, V601, V612, V628, V638): the cohort engine''s reading of each record — rule, proposed status, classification, confidence and issues; a student graduated by status reconciliation (V638) is validated under R1 and carries no GRADUATED_WITHOUT_APPROVAL issue';

-- ── 12 · the Registrar's correction marks the reconciliation corrected (restated from V602 as it stood, with the two updates) ──
CREATE OR REPLACE FUNCTION records.correct_graduation(p_student uuid, p_reason text, p_evidence text, p_actor uuid, p_office text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE s people.student; g records.graduand; v_id uuid := gen_random_uuid(); v_impact jsonb; v_cert record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRAD_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    IF s.status <> 'GRADUATED' THEN RAISE EXCEPTION 'GRAD_CORRECTION_NOT_GRADUATED: the record does not read GRADUATED' USING ERRCODE = '23514'; END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'GRAD_CORRECTION_REASON: a graduation correction is made on a reason of at least ten characters' USING ERRCODE = '23514';
    END IF;
    IF p_evidence IS NULL OR btrim(p_evidence) = '' THEN
        RAISE EXCEPTION 'GRAD_CORRECTION_EVIDENCE: a graduation correction cites its evidence — the minute, the letter or the decision' USING ERRCODE = '23514';
    END IF;
    -- a degree certificate that stands is not undone by a status change: it is revoked first, on its own trail
    SELECT c.number, c.status INTO v_cert FROM credentials.certificate c
     WHERE c.student_id = p_student AND c.status <> 'REVOKED'
       AND NOT EXISTS (SELECT 1 FROM credentials.revocation rv WHERE rv.credential_id = c.issued_id)
     ORDER BY c.printed_on DESC NULLS LAST LIMIT 1;
    IF v_cert.number IS NOT NULL THEN
        RAISE EXCEPTION 'GRAD_CORRECTION_CERTIFICATE: the degree certificate % stands (%); revoke it first', v_cert.number, lower(v_cert.status) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO g FROM records.graduand WHERE student_id = p_student AND senate_state = 'APPROVED' ORDER BY session DESC LIMIT 1 FOR UPDATE;
    v_impact := jsonb_build_object(
        'documents_issued', (SELECT count(*) FROM credentials.issued i WHERE i.student_id = p_student),
        'transcript_requests', (SELECT count(*) FROM credentials.transcript_request t WHERE t.student_id = p_student),
        'final_clearance', (SELECT CASE WHEN q.completed_at IS NOT NULL THEN 'completed' ELSE 'under way' END
                              FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = p_student AND q.cancelled_at IS NULL
                             ORDER BY q.started_at DESC LIMIT 1),
        'graduation_session', g.session, 'batch_ref', g.batch_ref, 'senate_minute', g.senate_minute);
    PERFORM set_config('moaum.graduation_correction', p_student::text, true);
    PERFORM people.change_status(p_student, 'ACTIVE', 'Graduation correction: ' || btrim(p_evidence), (now() AT TIME ZONE 'Africa/Lagos')::date, btrim(p_reason));
    PERFORM set_config('moaum.graduation_correction', '', true);
    INSERT INTO records.graduation_correction (id, student_id, graduand_id, batch_ref, reason, evidence, impact, previous_status, new_status, decided_by, actor_office)
    VALUES (v_id, p_student, g.id, g.batch_ref, btrim(p_reason), btrim(p_evidence), v_impact, 'GRADUATED', 'ACTIVE', p_actor, p_office);
    -- the list entry goes back to awaiting, with the correction as its unmet requirement: it is approved again only after the
    -- degree audit has run again (the audit rewrites unmet from the record) — never by the next batch or whole-list approval blindly
    -- V638: a graduation by status reconciliation is marked corrected on its own row, the batch's count with it
    WITH x AS (UPDATE people.graduation_reconciliation SET corrected_at = now(), corrected_by = p_actor, correction_reason = btrim(p_reason)
                WHERE student_id = p_student AND corrected_at IS NULL RETURNING batch_ref)
    UPDATE people.graduation_reconciliation_batch b SET corrected = b.corrected + 1 WHERE b.batch_ref IN (SELECT x.batch_ref FROM x);
    -- the engine reads the corrected record again
    PERFORM people.refresh_academic_positions(ARRAY[p_student]);
    IF g.id IS NOT NULL THEN
        UPDATE records.graduand SET senate_state = 'AWAITING', correction_id = v_id,
               unmet = 'Graduation corrected — the degree audit must run again (' || left(btrim(p_reason), 120) || ')'
         WHERE id = g.id;
    END IF;
    RETURN v_impact || jsonb_build_object('correction_id', v_id);
END $function$;

-- no record is reconciled yet, so no position changes at this migration: the engine reads the new join from the next recompute on
GRANT SELECT ON people.graduation_reconciliation_batch, people.graduation_reconciliation_row, people.graduation_reconciliation TO app_auditor, app_reporting;

COMMIT;
