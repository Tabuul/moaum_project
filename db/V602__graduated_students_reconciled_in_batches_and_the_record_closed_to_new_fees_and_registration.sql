-- ═══════════════════════════════════════
-- V602 — graduated students reconciled in batches, and the graduated record closed to new fees and registration
--
--   What the portal already had (kept, not rebuilt): the register's status GRADUATED with its history (people.change_status, V286);
--   the graduation list per session — the degree audit from the published record, records.graduand, Senate's approval on a
--   minute, which marks every audited graduand GRADUATED at once (V029, V493); the cohort engine and the lifecycle
--   reconciliation (V331, V558, V595, V598): recommendation, confidence, completion (every course passed and published, a
--   carry-over owed, a result awaited, the final level not reached, nothing published), review, RECON batches, graduation
--   candidates placed on the list; final clearance as a workflow on the one clearance engine (V013, V415): eight offices
--   (Bursary first), each clearing against the record, the student's own view, certificates with a QR; the Student Query and
--   the statistics, which already keep GRADUATED out of the current population (V469); the student's full record.
--
--   What was missing, and is added here on those pieces:
--     · records.graduation_batch / graduation_batch_row — GRAD/YYYY/NNNNNN: the Academic Office's act of confirming awards for
--       chosen students on the Senate's minute, previewed first (records.graduation_verdict: already graduated, deferred,
--       suspended, withdrawn, discontinued, a carry-over owed, a result awaited, the final level not reached, no published
--       result, a requirement unmet, data incomplete, requires review (a low-confidence record never graduated in bulk unless
--       the Registry verified it on the lifecycle desk), or eligible), then executed one student at a time, each all or
--       nothing, never twice (a graduated student is skipped, not graduated again);
--     · records.graduate_one — the single act both paths share: revalidated in the database (status, the list entry, nothing
--       owed, no result awaited, the minute), the list entry approved with the batch, the moment, the final level and the
--       spillover state the student graduated from, the status changed on the minute with its history, final clearance
--       started where none is under way, the student told on a template (STUDENT_GRADUATED); records.approve_awards (the
--       session's whole-list approval) now calls it for each graduand;
--     · the lock: finance.closed_for_fees — a graduated record owes nothing for a session after its graduation session
--       (finance.charges_as, which every fee figure reads, and finance.new_reference, which every school-fee payment starts
--       from, both answer by it; sessions up to graduation keep their history and may still be settled); registration.
--       student_draft refuses a student not in study, so no path registers a course or a carry-over for a graduated record;
--       transcript, certificate and other purpose payments are untouched;
--     · the correction: GRADUATED is permanent on the register (records.guard_graduated) except through
--       records.correct_graduation — the Registrar's act on a reason and evidence, refused while a degree certificate stands
--       unrevoked, with the downstream impact (documents issued, transcript requests, the final clearance) recorded, the list entry awaiting a fresh degree audit;
--     · the Bursary and the Students Account Office told when a batch leaves graduates for financial clearance
--       (GRADUATION_CLEARANCE_WAITING).
--   Nothing is deleted: registrations, results, payments, receipts, clearance and level history stay on the record.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V602: graduated students reconciled in batches, the graduated record closed to new fees and registration', true);

-- ── the two templates ──────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('STUDENT_GRADUATED', 'Graduation confirmed',
 'To the student when the award is confirmed on the Senate''s minute — a graduation batch of the Academic Office, or the session''s list approved',
 'Your graduation is confirmed — [AWARD], [SESSION]',
 E'Dear [FIRST_NAME],\n\nYour award of [AWARD] in [PROGRAMME] ([DEPARTMENT], [FACULTY]) is confirmed under Senate minute [MINUTE], graduation session [SESSION]. Your record on the University register (matriculation number [MATRIC]) now reads GRADUATED.\n\nYour course registrations, results, payments and receipts stay on your record and remain open to you. Course registration and school fees for later sessions are closed on this record; transcripts, the certificate and other services remain open. Final clearance: [CLEARANCE].\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi',
 'MOAUM: your award of [AWARD] ([PROGRAMME]) is confirmed under [MINUTE], session [SESSION]. Final clearance: [CLEARANCE]. See the portal.',
 'Graduation confirmed',
 'Your award of [AWARD] in [PROGRAMME] is confirmed under Senate minute [MINUTE] (graduation session [SESSION]). Final clearance: [CLEARANCE].',
 ARRAY['FIRST_NAME','AWARD','PROGRAMME','DEPARTMENT','FACULTY','MINUTE','SESSION','MATRIC','CLEARANCE'], true, 'HIGH'),
('GRADUATION_CLEARANCE_WAITING', 'Graduates waiting for financial clearance',
 'To the Bursary and the Students Account Office when a graduation batch marks students GRADUATED and their final clearance begins',
 '[COUNT] graduates of [SESSION] await financial clearance ([BATCH])',
 E'Dear [FIRST_NAME],\n\nThe Academic Office has confirmed the award of [COUNT] student(s) under graduation batch [BATCH] (session [SESSION], Senate minute [MINUTE]). Their final clearance is under way, and the Bursary''s stage awaits the office''s verification of their school fees, payments and balances. Nothing is deleted: the office verifies the record and marks the student cleared, or not cleared with the reason.\n\nOpen Financial Clearance on the portal.',
 NULL,
 'Graduates await financial clearance',
 '[COUNT] graduate(s) of [SESSION] under batch [BATCH] await the Bursary''s clearance.',
 ARRAY['FIRST_NAME','COUNT','BATCH','SESSION','MINUTE'], false, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── the batch and its rows ─────────────────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS records.graduation_batch_seq;

CREATE TABLE records.graduation_batch (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    batch_ref     text NOT NULL UNIQUE CHECK (batch_ref ~ '^GRAD/[0-9]{4}/[0-9]{6}$'),
    session       text NOT NULL REFERENCES policy.academic_session(name),     -- the graduation session the awards are confirmed for
    senate_minute text NOT NULL CHECK (btrim(senate_minute) <> ''),
    reason        text NOT NULL CHECK (length(btrim(reason)) >= 10),
    scope         jsonb NOT NULL DEFAULT '{}'::jsonb,                          -- the filters the students were chosen by, as words
    selected      integer NOT NULL DEFAULT 0,
    eligible      integer NOT NULL DEFAULT 0,
    graduated     integer NOT NULL DEFAULT 0,
    rejected      integer NOT NULL DEFAULT 0,
    review        integer NOT NULL DEFAULT 0,
    created_by    uuid NOT NULL,
    actor_office  text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    executed_at   timestamptz,
    closed_at     timestamptz,
    closed_by     uuid
);
COMMENT ON TABLE records.graduation_batch IS
  'V602: a graduation batch (GRAD/YYYY/NNNNNN) — the Academic Office''s act of confirming the awards of chosen students on a Senate minute, previewed, then executed one student at a time';

CREATE TABLE records.graduation_batch_row (
    batch_id      uuid NOT NULL REFERENCES records.graduation_batch(id) ON DELETE CASCADE,
    student_id    uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,        -- the go-live reset clears students: their rows go with them
    verdict       text NOT NULL,
    confidence    text,
    reason        text,
    graduand_id   uuid REFERENCES records.graduand(id) ON DELETE SET NULL,
    graduated_at  timestamptz,
    outcome       text,
    PRIMARY KEY (batch_id, student_id)
);
CREATE INDEX graduation_batch_row_student_idx ON records.graduation_batch_row (student_id);
COMMENT ON TABLE records.graduation_batch_row IS
  'V602: a student in a graduation batch: the verdict and confidence of the preview, and what the execution did (GRADUATED, ALREADY_GRADUATED, SKIPPED, REFUSED with the reason)';

CREATE TABLE records.graduation_correction (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    graduand_id     uuid REFERENCES records.graduand(id) ON DELETE SET NULL,
    batch_ref       text,
    reason          text NOT NULL CHECK (length(btrim(reason)) >= 10),
    evidence        text NOT NULL CHECK (btrim(evidence) <> ''),
    impact          jsonb NOT NULL DEFAULT '{}'::jsonb,
    previous_status text NOT NULL,
    new_status      text NOT NULL,
    decided_by      uuid NOT NULL,
    actor_office    text NOT NULL,
    decided_at      timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE records.graduation_correction IS
  'V602: an erroneous graduation put right by the Registrar on a reason and evidence, with the downstream impact recorded; the only way a GRADUATED record leaves that status';

SELECT audit.attach('records.graduation_batch');
SELECT audit.attach('records.graduation_batch_row');
SELECT audit.attach('records.graduation_correction');

ALTER TABLE records.graduand
    ADD COLUMN batch_ref       text REFERENCES records.graduation_batch(batch_ref),
    ADD COLUMN graduated_at    timestamptz,
    ADD COLUMN graduated_by    uuid,
    ADD COLUMN actor_office    text,
    ADD COLUMN final_level     integer,
    ADD COLUMN duration_years  integer,
    ADD COLUMN spillover_state text,
    ADD COLUMN entry_session   text,
    ADD COLUMN correction_id   uuid REFERENCES records.graduation_correction(id);
CREATE INDEX graduand_approved_session_idx ON records.graduand (session) WHERE senate_state = 'APPROVED';
CREATE INDEX graduand_batch_idx ON records.graduand (batch_ref) WHERE batch_ref IS NOT NULL;
COMMENT ON COLUMN records.graduand.batch_ref IS 'V602: the graduation batch that confirmed the award (null for a session''s whole-list approval)';
COMMENT ON COLUMN records.graduand.graduated_at IS 'V602: the moment the award was confirmed and the status changed';
COMMENT ON COLUMN records.graduand.spillover_state IS 'V602: the cohort engine''s spillover state at graduation (NORMAL, SPILLOVER_YEAR_1 …): the SP1 → graduated and SP2 → graduated figures';

-- ── the graduation session, and the lock ───────────────────────────────────────────────────────────────────────
CREATE FUNCTION records.graduation_session(p_student uuid) RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce((SELECT max(g.session) FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED'),
                    (SELECT max(x.session) FROM (SELECT e.session FROM people.enrolment e WHERE e.student_id = p_student
                                                 UNION ALL
                                                 SELECT r.session FROM registration.course_registration r
                                                  WHERE r.student_id = p_student AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x))
$fn$;
COMMENT ON FUNCTION records.graduation_session(uuid) IS
  'V602: the session a student graduated in — the approved list entry''s, else the last session the record shows them in study';

CREATE FUNCTION finance.closed_for_fees(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT s.status = 'GRADUATED' AND (gs.name IS NULL OR p_session > gs.name)
      FROM people.student s
      LEFT JOIN LATERAL (SELECT records.graduation_session(s.id) AS name) gs ON true
     WHERE s.id = p_student
$fn$;
COMMENT ON FUNCTION finance.closed_for_fees(uuid, text) IS
  'V602: whether a session''s school fees are closed on the record — a graduated record owes nothing for a session after its graduation session; sessions up to it keep their history and may be settled';

CREATE OR REPLACE FUNCTION finance.charges_as(p_student uuid, p_session text, p_programme text)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $function$
    -- V602: no charge of any kind for a session a graduated record is closed to
    SELECT x.id, x.item, x.amount, x.ord
      FROM (SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], p_programme) c
            UNION ALL
            SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of_as(p_student, p_session, ARRAY['LATE_PAYMENT'], p_programme) c WHERE finance.late_payment_applies(p_student, p_session)
            UNION ALL
            SELECT c.id, c.item, c.amount, c.ord FROM finance.charges_of_as(p_student, p_session, ARRAY['LATE_REGISTRATION'], p_programme) c WHERE finance.late_registration_applies(p_student, p_session)) x
     WHERE NOT finance.closed_for_fees(p_student, p_session)
     ORDER BY x.ord, x.item
$function$;

CREATE OR REPLACE FUNCTION finance.new_reference(p_student uuid, p_session text, p_amount numeric, p_purpose text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE pos record; v_ref text; v_matric text; win record;
BEGIN
    -- V602: a graduated academic record takes no new school-fee obligation: no reference for a session after the graduation session
    IF finance.closed_for_fees(p_student, p_session) THEN
        RAISE EXCEPTION 'SCHOOL_FEES_CLOSED_GRADUATED: This academic record has been marked as graduated. New school-fee payments are not available for this academic enrollment.'
            USING ERRCODE = '23514',
                  HINT = 'Transcript, certificate and other services are paid for from Documents; a balance of a session up to graduation is settled with the Bursary, which verifies it in financial clearance.';
    END IF;
    -- school fees wait for a successful online screening where the session requires one (V269)
    PERFORM admissions.screening_refuse_student(p_student, 'SCHOOL FEES');
    -- the portal's school-fees window (V288): a new reference is generated only while it is open; one already generated is paid and verified as before
    SELECT * INTO win FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL);
    IF win.state <> 'OPEN' THEN
        RAISE EXCEPTION 'SCHOOL_FEES_PAYMENT_CLOSED: school fees payment is currently % for %', lower(win.state), p_session USING ERRCODE = '23514',
            HINT = CASE WHEN win.state = 'SCHEDULED' THEN 'It opens on ' || to_char(win.opens_at AT TIME ZONE 'Africa/Lagos', 'DD Month YYYY HH24:MI') || '.' ELSE 'The Directorate of ICT opens the payment window.' END;
    END IF;
    SELECT * INTO pos FROM finance.position(p_student, p_session);
    IF pos.due = 0 THEN
        RAISE EXCEPTION 'no charge is stated for % yet', p_session USING ERRCODE = '23514',
            HINT = 'The Bursar states the session''s fee schedule before anything is paid against it.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'a payment is for an amount' USING ERRCODE = '23514';
    END IF;
    IF p_amount > pos.balance THEN
        RAISE EXCEPTION 'the amount % is more than the balance of %', p_amount, pos.balance USING ERRCODE = '23514',
            HINT = 'Pay the balance, or part of it; nothing is taken beyond what is owed.';
    END IF;
    SELECT coalesce(matric_no, admission_no, 'X') INTO v_matric FROM people.student WHERE id = p_student;
    -- V395: the four random digits may repeat a reference another student drew (students whose numbers end alike share the
    -- first part); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
        VALUES (p_student, p_session, v_ref, coalesce(p_purpose, 'School fees ' || p_session), p_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free payment reference was found for % in fifty draws', v_matric USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

CREATE OR REPLACE FUNCTION registration.student_draft(p_student uuid, p_session text, p_semester integer)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE v uuid; s people.student; m record;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    -- V602: only a student in study registers; a graduated record is closed to course registration (and so to carry-overs) on every path
    IF s.status NOT IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN
        RAISE EXCEPTION 'REG_STUDENT_NOT_ELIGIBLE: %',
            CASE WHEN s.status = 'GRADUATED' THEN 'Course registration is unavailable because this academic record has been graduated.'
                 ELSE 'A student who is ' || lower(replace(s.status, '_', ' ')) || ' does not register.' END
            USING ERRCODE = '23514';
    END IF;
    SELECT id INTO v FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF v IS NOT NULL THEN RETURN v; END IF;
    v := gen_random_uuid();
    INSERT INTO registration.course_registration (id, student_id, session, semester, level)
    VALUES (v, p_student, p_session, p_semester, s.current_level);
    FOR m IN SELECT * FROM registration.student_menu(p_student, p_session, p_semester) WHERE carryover LOOP
        -- V512: a GST/EPS carry-over waits for the GST fee: being a carry-over does not pass it
        IF registration.gst_course_hold(p_student, p_session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type)
        VALUES (v, m.offering_id, m.units, CASE WHEN m.deferred THEN 'DEFERRED' ELSE 'CARRYOVER' END)
        ON CONFLICT (registration_id, offering_id) DO NOTHING;
        IF FOUND THEN PERFORM registration.gst_course_registered(v, m.offering_id); END IF;
    END LOOP;
    RETURN v;
END $function$;

-- ── the verdict: what the preview says of a student, before anything is written ────────────────────────────────
CREATE FUNCTION records.graduation_verdict(p_student uuid, p_session text)
RETURNS TABLE(verdict text, confidence text, reason text, status text, completion text, outstanding_courses text, awaiting_courses text,
              graduand_state text, unmet text, recommendation text, review_state text, spillover_state text, current_level integer,
              final_level integer, entry_session text)
LANGUAGE sql STABLE AS $fn$
    WITH s AS (SELECT st.id, st.status, st.current_level, st.entry_session, st.programme_code FROM people.student st WHERE st.id = p_student),
         ap AS (SELECT a.* FROM people.academic_position a WHERE a.student_id = p_student),
         lr AS (SELECT r.recommendation, r.confidence, r.review_state FROM people.lifecycle_recommendation r WHERE r.student_id = p_student),
         g AS (SELECT gr.senate_state, gr.unmet, gr.cgpa FROM records.graduand gr WHERE gr.student_id = p_student AND gr.session = p_session),
         c AS (SELECT * FROM people.lifecycle_completion_rows(ARRAY[p_student])),
         fl AS (SELECT records.final_level_of(p_student) AS lvl),
         x AS (
             SELECT CASE
                      WHEN s.status = 'GRADUATED' THEN 'ALREADY_GRADUATED'
                      WHEN s.status = 'DEFERRED' THEN 'DEFERRED'
                      WHEN s.status IN ('SUSPENDED', 'RUSTICATED') THEN 'SUSPENDED'
                      WHEN s.status IN ('WITHDRAWN', 'VOLUNTARY_WITHDRAWAL', 'TRANSFERRED_OUT') THEN 'WITHDRAWN'
                      WHEN s.status IN ('EXPELLED', 'DORMANT') THEN 'DISCONTINUED'
                      WHEN s.status NOT IN ('ACTIVE', 'PROBATION') THEN 'NOT_ELIGIBLE_STATUS'
                      WHEN g.senate_state = 'REFERRED' THEN 'REFERRED_BY_SENATE'
                      WHEN c.completion = 'OUTSTANDING_COURSES' THEN 'CARRY_OVER'
                      WHEN c.completion = 'AWAITING_RESULT' THEN 'OUTSTANDING_RESULT'
                      WHEN c.completion = 'FINAL_LEVEL_NOT_REACHED' THEN 'NOT_FINAL_LEVEL'
                      WHEN c.completion = 'NO_PUBLISHED_RESULT' THEN 'NO_RESULT'
                      WHEN g.unmet IS NOT NULL THEN 'REQUIREMENT_UNMET'
                      WHEN s.entry_session IS NULL OR fl.lvl IS NULL THEN 'DATA_INCOMPLETE'
                      WHEN lr.recommendation = 'REQUIRES_REVIEW' AND coalesce(lr.review_state, '') <> 'VERIFIED' THEN 'REQUIRES_REVIEW'
                      ELSE 'ELIGIBLE' END AS verdict,
                    -- the lifecycle desk's confidence where it judged the student (its DATA_INCOMPLETE is the University's — no current
                    -- session, say — not the student's: the verdict reads the student's own record then)
                    CASE WHEN lr.confidence IS NOT NULL AND lr.recommendation <> 'DATA_INCOMPLETE' THEN lr.confidence
                         WHEN s.entry_session IS NULL OR fl.lvl IS NULL THEN 'LOW'
                         WHEN c.completion = 'COMPLETED' AND ap.student_id IS NOT NULL THEN 'HIGH'
                         ELSE 'MEDIUM' END AS confidence,
                    s.status, c.completion, c.outstanding_courses, c.awaiting_courses, g.senate_state, g.unmet, lr.recommendation, lr.review_state,
                    ap.spillover_state, s.current_level, fl.lvl AS final_level, s.entry_session
               FROM s LEFT JOIN ap ON true LEFT JOIN lr ON true LEFT JOIN g ON true LEFT JOIN c ON true CROSS JOIN fl)
    SELECT CASE WHEN x.verdict = 'ELIGIBLE' AND x.confidence = 'LOW' AND coalesce(x.review_state, '') <> 'VERIFIED' THEN 'REQUIRES_REVIEW' ELSE x.verdict END,
           x.confidence,
           CASE x.verdict
             WHEN 'ALREADY_GRADUATED' THEN 'Already graduated'
             WHEN 'DEFERRED' THEN 'Studies deferred: not graduated'
             WHEN 'SUSPENDED' THEN 'Suspended or rusticated: not graduated'
             WHEN 'WITHDRAWN' THEN 'Withdrawn or transferred out: not graduated'
             WHEN 'DISCONTINUED' THEN 'Discontinued (' || lower(replace(x.status, '_', ' ')) || '): not graduated'
             WHEN 'NOT_ELIGIBLE_STATUS' THEN 'Status ' || lower(replace(x.status, '_', ' ')) || ': not graduated'
             WHEN 'REFERRED_BY_SENATE' THEN 'Referred by Senate on the graduation list'
             WHEN 'CARRY_OVER' THEN 'Carry-over owed: ' || coalesce(x.outstanding_courses, '')
             WHEN 'OUTSTANDING_RESULT' THEN 'Result awaited: ' || coalesce(x.awaiting_courses, '')
             WHEN 'NOT_FINAL_LEVEL' THEN 'Registered only below the final level (' || coalesce(x.final_level::text, '?') || ')'
             WHEN 'NO_RESULT' THEN 'No published result on the record'
             WHEN 'REQUIREMENT_UNMET' THEN coalesce(x.unmet, 'A requirement is unmet')
             WHEN 'DATA_INCOMPLETE' THEN CASE WHEN x.entry_session IS NULL THEN 'No entry session on the record'
                                              ELSE 'The programme''s final level is not recorded' END
             WHEN 'REQUIRES_REVIEW' THEN 'Requires review on the lifecycle desk'
             ELSE CASE WHEN x.confidence = 'LOW' THEN 'Low confidence: verify on the lifecycle desk before graduating in bulk'
                       ELSE 'Every requirement met' END END,
           x.status, x.completion, x.outstanding_courses, x.awaiting_courses, x.senate_state, x.unmet, x.recommendation, x.review_state,
           x.spillover_state, x.current_level, x.final_level, x.entry_session
      FROM x
$fn$;
COMMENT ON FUNCTION records.graduation_verdict(uuid, text) IS
  'V602: a student''s verdict for a graduation batch of the session, read from the register, the cohort engine''s position and recommendation, the lifecycle completion check (fresh) and the session''s list entry — nothing written; the degree audit''s CGPA judgement is the API''s (GraduationService)';

-- ── the one act of graduating a student ────────────────────────────────────────────────────────────────────────
CREATE FUNCTION records.graduate_one(p_student uuid, p_session text, p_minute text, p_batch_ref text, p_reason text, p_actor uuid, p_office text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE s people.student; g records.graduand; c record; ap record; pr record; reach record; v_clear text; v_minute text; v_proc uuid; v_err text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRAD_NO_STUDENT: no such student' USING ERRCODE = '23503'; END IF;
    IF s.status = 'GRADUATED' THEN
        RETURN jsonb_build_object('outcome', 'ALREADY_GRADUATED', 'graduand_id', (SELECT id FROM records.graduand WHERE student_id = p_student AND senate_state = 'APPROVED' ORDER BY session DESC LIMIT 1));
    END IF;
    IF s.status NOT IN ('ACTIVE', 'PROBATION') THEN
        RAISE EXCEPTION 'GRAD_STATUS: a student who is % is not graduated', lower(replace(s.status, '_', ' ')) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO g FROM records.graduand WHERE student_id = p_student AND session = p_session FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GRAD_NOT_ON_LIST: not on the graduation list of %', p_session USING ERRCODE = '23514'; END IF;
    IF g.senate_state = 'REFERRED' THEN RAISE EXCEPTION 'GRAD_REFERRED: referred by Senate on the graduation list of %', p_session USING ERRCODE = '23514'; END IF;
    IF g.senate_state <> 'APPROVED' AND (g.unmet IS NOT NULL OR g.cgpa IS NULL) THEN
        RAISE EXCEPTION 'GRAD_NOT_ELIGIBLE: %', coalesce(g.unmet, 'no published result on the record') USING ERRCODE = '23514';
    END IF;
    v_minute := coalesce(nullif(btrim(coalesce(g.senate_minute, '')), ''), nullif(btrim(coalesce(p_minute, '')), ''));
    IF v_minute IS NULL THEN
        RAISE EXCEPTION 'GRAD_MINUTE_REQUIRED: an award is confirmed on a Senate minute, and none was cited' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM people.lifecycle_completion_rows(ARRAY[p_student]);
    IF c.completion = 'OUTSTANDING_COURSES' THEN
        RAISE EXCEPTION 'GRAD_CARRY_OVER: a carry-over is still owed: %', coalesce(c.outstanding_courses, '') USING ERRCODE = '23514';
    END IF;
    IF c.completion = 'AWAITING_RESULT' THEN
        RAISE EXCEPTION 'GRAD_RESULT_AWAITED: a result is still awaited: %', coalesce(c.awaiting_courses, '') USING ERRCODE = '23514';
    END IF;
    SELECT a.spillover_state INTO ap FROM people.academic_position a WHERE a.student_id = p_student;
    SELECT p.duration_years, p.name, p.dept_code, d.name AS dept_name, f.name AS faculty_name INTO pr
      FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE p.code = s.programme_code;
    UPDATE records.graduand
       SET senate_state = 'APPROVED', senate_minute = v_minute, batch_ref = coalesce(p_batch_ref, batch_ref), graduated_at = now(),
           graduated_by = p_actor, actor_office = p_office, final_level = records.final_level_of(p_student), duration_years = pr.duration_years,
           spillover_state = ap.spillover_state, entry_session = s.entry_session
     WHERE id = g.id;
    PERFORM people.change_status(p_student, 'GRADUATED', v_minute, (now() AT TIME ZONE 'Africa/Lagos')::date, coalesce(nullif(btrim(coalesce(p_reason, '')), ''), 'Award approved by Senate'));
    -- final clearance begins where none is under way: the Bursary's stage is first (an engine refusal is recorded, never fatal)
    SELECT q.id INTO v_proc FROM clearance.process q WHERE q.workflow = 'FINAL' AND q.student_id = p_student AND q.cancelled_at IS NULL ORDER BY q.started_at DESC LIMIT 1;
    IF v_proc IS NOT NULL THEN
        v_clear := 'under way';
    ELSE
        BEGIN
            v_proc := clearance.start('FINAL', p_student, p_session, 'ELIGIBLE', NULL, p_actor, p_office);
            v_clear := 'started';
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_clear := 'not started — ' || left(v_err, 160);
        END;
    END IF;
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.notify('STUDENT_GRADUATED', NULL, jsonb_build_object(
                'FIRST_NAME', coalesce(nullif(split_part(coalesce(s.other_names, ''), ' ', 1), ''), s.surname),
                'AWARD', g.award, 'PROGRAMME', coalesce(pr.name, s.programme_code), 'DEPARTMENT', coalesce(pr.dept_name, ''), 'FACULTY', coalesce(pr.faculty_name, ''),
                'MINUTE', v_minute, 'SESSION', p_session, 'MATRIC', coalesce(s.matric_no, s.admission_no, ''),
                'CLEARANCE', CASE WHEN v_clear IN ('started', 'under way') THEN 'under way; each office clears you against your record' ELSE 'to be started by the Registry' END),
            'student', p_student, reach.email, reach.phone, 'graduated:' || p_student);
    RETURN jsonb_build_object('outcome', 'GRADUATED', 'graduand_id', g.id, 'clearance', v_clear, 'process', v_proc, 'minute', v_minute);
END $fn$;
COMMENT ON FUNCTION records.graduate_one(uuid, text, text, text, text, uuid, text) IS
  'V602: one student graduated, all or nothing — revalidated (in study, on the session''s list with nothing unmet or Senate-approved, no carry-over owed, no result awaited, a minute cited), the list entry approved with the batch and the moment, the status changed on the minute, final clearance started, the student told; a graduated student is returned ALREADY_GRADUATED, never graduated twice';

CREATE OR REPLACE FUNCTION records.approve_awards(p_session text, p_minute text) RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE n int := 0; g record; v_actor uuid; v_office text; r jsonb;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'the graduation list is approved on a Senate minute, and none was cited'
        USING ERRCODE = '23514', HINT = 'Cite the minute of the Senate that approved the awards.';
    END IF;
    v_actor := nullif(current_setting('moaum.actor_id', true), '')::uuid;
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    -- V602: every audited graduand with nothing unmet is graduated by the one act, and one approved earlier but still ACTIVE on the register likewise
    FOR g IN
        SELECT gr.student_id
          FROM records.graduand gr JOIN people.student s ON s.id = gr.student_id
         WHERE gr.session = p_session AND gr.unmet IS NULL AND gr.cgpa IS NOT NULL
           AND (gr.senate_state = 'AWAITING' OR (gr.senate_state = 'APPROVED' AND s.status <> 'GRADUATED'))
         ORDER BY s.surname, s.other_names
    LOOP
        r := records.graduate_one(g.student_id, p_session, btrim(p_minute), NULL, 'Award approved by Senate', v_actor, v_office);
        IF r->>'outcome' = 'GRADUATED' THEN n := n + 1; END IF;
    END LOOP;
    RETURN n;
END $function$;
COMMENT ON FUNCTION records.approve_awards(text, text) IS
  'V029/V602: the session''s graduation list approved on a Senate minute — each audited graduand with nothing unmet graduated by records.graduate_one (status, clearance, the student told)';

-- ── batches ────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION records.open_graduation_batch(p_session text, p_minute text, p_reason text, p_scope jsonb, p_actor uuid, p_office text)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE v_ref text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RAISE EXCEPTION 'GRAD_BATCH_SESSION: no session % on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'GRAD_MINUTE_REQUIRED: a graduation batch confirms awards on a Senate minute, and none was cited' USING ERRCODE = '23514';
    END IF;
    IF p_reason IS NULL OR length(btrim(p_reason)) < 10 THEN
        RAISE EXCEPTION 'GRAD_BATCH_REASON: a graduation batch says what it is for (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('records.graduation_batch'));
    v_ref := 'GRAD/' || to_char(now() AT TIME ZONE 'Africa/Lagos', 'YYYY') || '/' || lpad(nextval('records.graduation_batch_seq')::text, 6, '0');
    INSERT INTO records.graduation_batch (batch_ref, session, senate_minute, reason, scope, created_by, actor_office)
    VALUES (v_ref, p_session, btrim(p_minute), btrim(p_reason), coalesce(p_scope, '{}'::jsonb), p_actor, p_office);
    RETURN v_ref;
END $fn$;

CREATE FUNCTION records.graduation_batch_tally(p_ref text) RETURNS void LANGUAGE sql AS $fn$
    UPDATE records.graduation_batch b
       SET selected = t.selected, eligible = t.eligible, graduated = t.graduated, rejected = t.rejected, review = t.review
      FROM (SELECT count(*)::int AS selected,
                   count(*) FILTER (WHERE r.verdict = 'ELIGIBLE')::int AS eligible,
                   count(*) FILTER (WHERE r.outcome = 'GRADUATED')::int AS graduated,
                   count(*) FILTER (WHERE r.verdict NOT IN ('ELIGIBLE', 'REQUIRES_REVIEW', 'ALREADY_GRADUATED') OR r.outcome = 'REFUSED')::int AS rejected,
                   count(*) FILTER (WHERE r.verdict = 'REQUIRES_REVIEW')::int AS review
              FROM records.graduation_batch_row r JOIN records.graduation_batch bb ON bb.id = r.batch_id WHERE bb.batch_ref = p_ref) t
     WHERE b.batch_ref = p_ref
$fn$;

-- ── GRADUATED is permanent except through a correction ─────────────────────────────────────────────────────────
CREATE FUNCTION records.guard_graduated() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    IF OLD.status = 'GRADUATED' AND NEW.status IS DISTINCT FROM 'GRADUATED'
       AND coalesce(current_setting('moaum.graduation_correction', true), '') <> OLD.id::text THEN
        RAISE EXCEPTION 'GRAD_PERMANENT: a graduated record leaves that status only through a graduation correction by the Registrar, on a reason and evidence'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;
CREATE TRIGGER trg_guard_graduated BEFORE UPDATE OF status ON people.student
    FOR EACH ROW WHEN (OLD.status = 'GRADUATED' AND NEW.status IS DISTINCT FROM OLD.status) EXECUTE FUNCTION records.guard_graduated();

CREATE FUNCTION records.correct_graduation(p_student uuid, p_reason text, p_evidence text, p_actor uuid, p_office text)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
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
    IF g.id IS NOT NULL THEN
        UPDATE records.graduand SET senate_state = 'AWAITING', correction_id = v_id,
               unmet = 'Graduation corrected — the degree audit must run again (' || left(btrim(p_reason), 120) || ')'
         WHERE id = g.id;
    END IF;
    RETURN v_impact || jsonb_build_object('correction_id', v_id);
END $fn$;
COMMENT ON FUNCTION records.correct_graduation(uuid, text, text, uuid, text) IS
  'V602: an erroneous graduation put right — the status back to ACTIVE on the evidence cited (the only way past records.guard_graduated), the list entry back to awaiting with the correction as its unmet requirement until the degree audit runs again, the impact recorded; refused while a degree certificate stands unrevoked';

-- ── the Bursary and the Students Account Office told of a batch ────────────────────────────────────────────────
CREATE FUNCTION records.tell_graduation_clearance(p_ref text) RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE b records.graduation_batch; p record; v_told int := 0; v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    SELECT * INTO b FROM records.graduation_batch WHERE batch_ref = p_ref;
    IF NOT FOUND OR b.graduated = 0 THEN RETURN 0; END IF;
    FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
              WHERE oa.office_code IN ('bursar', 'studentaccounts') AND oa.valid_from <= v_today AND (oa.valid_to IS NULL OR oa.valid_to >= v_today) LOOP
        v_told := v_told + platform.tell_person(p.person_id, 'GRADUATION_CLEARANCE_WAITING', NULL,
                      jsonb_build_object('COUNT', b.graduated, 'BATCH', b.batch_ref, 'SESSION', b.session, 'MINUTE', b.senate_minute),
                      'graduation-clearance:' || b.batch_ref || ':' || b.graduated || ':' || p.person_id);
    END LOOP;
    RETURN v_told;
END $fn$;

COMMIT;
