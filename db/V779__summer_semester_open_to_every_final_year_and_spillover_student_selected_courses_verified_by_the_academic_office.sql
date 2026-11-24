-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V779 · The Summer Semester open to every final-year and spillover student, the courses they select verified by the Academic Office
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompts of 23 November 2026: the Summer Semester must be open to ALL final-year and ALL spillover
--  students, whose category comes from the real academic status and not from matric patterns or level; the student selects the
--  courses they still owe from either semester; the Academic Office verifies each selection (four states: Student selected -
--  pending verification; Academically confirmed outstanding; Not outstanding - result verified; Rejected - incorrect course
--  selection) and the student sees the status and any reason; nothing depends on uploaded results or detected carry-overs, and a
--  missing result is never read as a pass; newly uploaded results are reconciled against selections; the register-and-pay-before-
--  verification workflow is kept; the fee stays the Bursary's (₦50,000 a student and ₦5,000 a course as published), itemised and
--  never charged twice; the student prints the registration confirmation; reports for the Academic Office, Faculty, Department,
--  Bursary and ICT; the course as taken (V771) is respected. The owner's decisions: the Summer first (Rule A, the carry-over
--  clearance, comes after and is not here); a paid selection later found Not outstanding or Rejected becomes a Summer credit the
--  Bursar settles — never an automatic refund.
--
--  What this migration does, in the order of the file:
--    · restates, from their live text and presence-checked, the readers and writers that decided who may take the Summer and which
--      courses: summer_eligibility (the category from the engine's own position: a spillover student, or a final-year one — the
--      record at or past the programme's final level, or the engine says so), summer_course_outstanding (a selection stands until a
--      pass or a decision ends it, so a self-selected course is not taken back at the first draw of a reference), summer_reference,
--      summer_materialize (the entry's type is the selection's state), summer_identify, summer_students, summer_area and the
--      trigger function entry_spillover_carry (a third-semester entry of a Summer student is left as the Summer typed it);
--    · makes a selection a row (registration.summer_selection, with its write-once history and its evidence cache), with the four
--      states and one writer of each (summer_selection_move, summer_selection_flag);
--    · reads set-based: summer_eligibility_of for any number of students at once with no result read, summer_results_of and
--      summer_evidence for the published results of those who select, summer_selectable for the one student's page (plpgsql: a
--      single inlined statement planned for 388 ms);
--    · verification: summer_verify (confirm, not outstanding, reject, reopen; in bulk; the money of a decision as a Summer credit
--      the Bursar settles and the paid entry withdrawn by the removal route of V772), reconciliation against newly published
--      results, the examination gate (a paid Summer course not verified holds the Summer's examinations unless the Academic Office
--      records why), the desk's roster, queue and report, the student's summary and confirmation, the notices in tranches.
--
--  Applied after V777 on a fresh database and, on the live one, after V780 to V782 as well: it restates none of what they restate,
--  so either order gives the same functions. The restated functions are the ones V735 to V756 left, asserted below by the md5 of
--  their text before anything is written.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V779: the Summer Semester open to every final-year and spillover student', true);

-- ── 3.0 · the live text of what is restated, as it was left ────────────────────────────────────────────────────────────────────────
CREATE FUNCTION pg_temp.v779_expect(p regprocedure, p_md5 text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    IF md5(replace((SELECT prosrc FROM pg_proc WHERE oid = p), E'\r', '')) <> p_md5 THEN
        RAISE EXCEPTION 'V779: % is not as it was left', p;
    END IF;
END $f$;
SELECT pg_temp.v779_expect('registration.summer_eligibility(uuid,text)', 'e4675592605295eee31ce5731a11653f');
SELECT pg_temp.v779_expect('registration.summer_course_outstanding(uuid,text,text)', 'c628812b619c04f8386da4db2b19b0f0');
SELECT pg_temp.v779_expect('registration.summer_reference(uuid,text)', '169817c8740501ed9797d33e55bc97d3');
SELECT pg_temp.v779_expect('registration.summer_materialize(uuid,text)', 'c449656a25845d4965a199a30431e421');
SELECT pg_temp.v779_expect('registration.summer_identify(text,timestamptz,integer)', '854ae835003c39cc6dce40d3d7ef7bcf');
SELECT pg_temp.v779_expect('registration.summer_students(text)', 'a369d9158e3eaab5752e8ac654c80e00');
SELECT pg_temp.v779_expect('registration.entry_spillover_carry()', 'daac85581559cdd79c8ef5f7daeca593');
SELECT pg_temp.v779_expect('registration.summer_select(uuid,text,text[])', '1966f8a3b28cdd05032b2a8b5f081ae0');


-- ── 2 · the schema ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- 2.1 · a charge's basis: the third way a course comes in, the student's own selection
DO $$
DECLARE v_con text; v_n int;
BEGIN
    SELECT count(*), min(c.conname) INTO v_n, v_con FROM pg_constraint c
     WHERE c.conrelid = 'registration.summer_charge'::regclass AND c.contype = 'c'
       AND pg_get_constraintdef(c.oid) LIKE '%basis%CARRY_OVER%AUTHORISED%';
    IF v_n <> 1 THEN RAISE EXCEPTION 'V779: the basis check of registration.summer_charge is not as V735 left it (% found)', v_n; END IF;
    EXECUTE format('ALTER TABLE registration.summer_charge DROP CONSTRAINT %I', v_con);
END $$;
ALTER TABLE registration.summer_charge ADD CONSTRAINT ck_summer_charge_basis
    CHECK (basis IS NULL OR basis IN ('CARRY_OVER', 'AUTHORISED', 'STUDENT_SELECTED'));

-- 2.2 · small columns
ALTER TABLE registration.summer_period    ADD COLUMN max_courses integer CHECK (max_courses IS NULL OR max_courses BETWEEN 1 AND 60);
ALTER TABLE registration.summer_candidate ADD COLUMN results integer;
ALTER TABLE registration.summer_credit    ADD COLUMN source text NOT NULL DEFAULT 'PAYMENT' CHECK (source IN ('PAYMENT', 'DECISION')),
                                          ADD COLUMN source_charge_id uuid REFERENCES registration.summer_charge(id) ON DELETE SET NULL,
                                          ADD COLUMN note text;
/* the idempotency key of a decision's money: one credit for the money ONE payment held on ONE charge row. A charge row is paid by a
   given payment at most once in its life (a confirmation runs once for a reference, and the programme fee a student selects back is a NEW
   charge row, never the cancelled one paid again), so the pair names one cancellation: a decision or a call repeated finds its credit, and
   a charge row cancelled again after a later payment revived it gets a credit of its own (keyed on the charge alone that second money vanished) */
CREATE UNIQUE INDEX uq_summer_credit_charge ON registration.summer_credit (source_charge_id, reference_id) WHERE source_charge_id IS NOT NULL;
COMMENT ON INDEX registration.uq_summer_credit_charge IS
  'V779: the idempotency key of the money of a decision — one DECISION credit for the money one payment held on one Summer charge (source_charge_id, reference_id); a charge row is paid by a payment at most once, so the pair is one cancellation.';
COMMENT ON COLUMN registration.summer_period.max_courses IS 'V779: the most Summer courses a student may hold in the session (cumulative); NULL no ceiling; the 30 a call stays.';
COMMENT ON COLUMN registration.summer_candidate.results IS 'V779: published results on the portal when the student was identified (NULL: not read) — the missing-history figure.';
COMMENT ON COLUMN registration.summer_credit.source IS 'V779: PAYMENT (money received beyond the charges, V739) or DECISION (the fee of a paid course the Academic Office found not outstanding or rejected).';
COMMENT ON COLUMN registration.summer_credit.source_charge_id IS 'V779: the cancelled PAID charge a DECISION credit is the money of; with reference_id (the payment that paid it) the idempotency key: one credit for the money one payment held on one charge.';
-- identify moves evaluated_at on every read: that must not write an audit row each time (V374's pattern for a heartbeat column)
DROP TRIGGER trg_audit_registration_summer_candidate ON registration.summer_candidate;
CREATE TRIGGER trg_audit_registration_summer_candidate AFTER INSERT OR DELETE ON registration.summer_candidate FOR EACH ROW EXECUTE FUNCTION audit.record();
CREATE TRIGGER trg_audit_registration_summer_candidate_change AFTER UPDATE ON registration.summer_candidate FOR EACH ROW
    WHEN ((to_jsonb(OLD) - 'evaluated_at') IS DISTINCT FROM (to_jsonb(NEW) - 'evaluated_at')) EXECUTE FUNCTION audit.record();
COMMENT ON TRIGGER trg_audit_registration_summer_candidate_change ON registration.summer_candidate IS
  'V779: every change of a candidate is audited except one that moves only evaluated_at, the heartbeat of the identification.';

-- 2.3 · a selection is a row
CREATE TABLE registration.summer_selection (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id       uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session          text NOT NULL REFERENCES policy.academic_session(name),
    course_code      text NOT NULL REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    basis            text NOT NULL CHECK (basis IN ('CARRY_OVER', 'AUTHORISED', 'STUDENT_SELECTED')),
    state            text NOT NULL DEFAULT 'PENDING_VERIFICATION'
                     CHECK (state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING', 'NOT_OUTSTANDING', 'REJECTED')),
    verified_via     text CHECK (verified_via IN ('RESULTS', 'AUTHORISATION', 'OFFICER')),
    decision_reason  text,
    units            integer NOT NULL CHECK (units BETWEEN 0 AND 12),
    original_session text, original_semester integer CHECK (original_semester IN (1, 2, 3)),
    original_source  text CHECK (original_source IN ('RESULTS', 'STUDENT')),
    needs_review     boolean NOT NULL DEFAULT false,
    review_flag      text CHECK (review_flag IN ('PASSED_ON_RECORD', 'EVIDENCE_CHANGED', 'ENTRY_REMOVED')),
    clarification_open boolean NOT NULL DEFAULT false, clarification_note text, clarification_by uuid, clarification_at timestamptz,
    student_note     text CHECK (student_note IS NULL OR length(student_note) <= 500), student_note_at timestamptz,
    decided_by       uuid, decided_office text, decided_at timestamptz,
    removal_ref      text,
    created_at       timestamptz NOT NULL DEFAULT now(), created_by uuid, updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_summer_selection UNIQUE (student_id, session, course_code),
    CONSTRAINT ck_sel_via      CHECK ((state = 'PENDING_VERIFICATION') = (verified_via IS NULL)),
    CONSTRAINT ck_sel_reason   CHECK (state NOT IN ('NOT_OUTSTANDING', 'REJECTED') OR length(btrim(coalesce(decision_reason, ''))) >= 10),
    CONSTRAINT ck_sel_rejected CHECK (state <> 'REJECTED' OR verified_via = 'OFFICER'),
    CONSTRAINT ck_sel_flag     CHECK (needs_review = (review_flag IS NOT NULL))
);
CREATE INDEX ix_summer_selection_state   ON registration.summer_selection (session, state);
CREATE INDEX ix_summer_selection_student ON registration.summer_selection (student_id, session);
CREATE INDEX ix_summer_selection_flag    ON registration.summer_selection (session) WHERE needs_review;
CREATE INDEX ix_summer_selection_clar    ON registration.summer_selection (session) WHERE clarification_open;
CREATE INDEX ix_summer_selection_course  ON registration.summer_selection (course_code);
COMMENT ON TABLE registration.summer_selection IS
  'V779: one row for each course a student selected for the Summer of a session, for ever — how it came in (basis), the Academic Office''s verification state (Student selected - pending verification; Academically confirmed outstanding; Not outstanding - result verified; Rejected - incorrect course selection) and why, the student''s own words and the Office''s question. Whether it is live follows its COURSE charge (DUE or PAID); the row is never deleted. A missing result is never read as a pass.';
SELECT audit.attach('registration.summer_selection');

CREATE TABLE registration.summer_selection_evidence (
    selection_id uuid PRIMARY KEY REFERENCES registration.summer_selection(id) ON DELETE CASCADE,
    evidence     text NOT NULL CHECK (evidence IN ('RESULT_FAILED', 'RESULT_PASSED', 'RESULT_AWAITED', 'NO_RESULT')),
    evidence_at  timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE INDEX ix_summer_evidence ON registration.summer_selection_evidence (evidence);
COMMENT ON TABLE registration.summer_selection_evidence IS
  'V779: the evidence read from published results for a selection, cached so the verification queue filters on it without reading results for each row; recomputed at every reconcile and verification; decisions and the examination gate act on a live read, never on this.';
SELECT audit.exempt('registration.summer_selection_evidence', 'a cache of the evidence read from published results, recomputed at every reconcile and every verification; every change of a selection that follows from it is on the audited summer_selection and its review history');

-- 2.4 · the write-once history of every verification act
CREATE TABLE registration.summer_selection_review (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    selection_id uuid NOT NULL REFERENCES registration.summer_selection(id) ON DELETE CASCADE,
    batch_ref text NOT NULL,
    action text NOT NULL CHECK (action IN ('CONFIRMED', 'NOT_OUTSTANDING', 'REJECTED', 'REOPENED', 'CLARIFICATION_ASKED', 'CLARIFICATION_ANSWERED', 'FLAGGED', 'FLAG_CLEARED')),
    from_state text, to_state text,
    via text NOT NULL CHECK (via IN ('RESULTS', 'AUTHORISATION', 'OFFICER', 'SYSTEM', 'STUDENT')),
    evidence text, reason text, note text,
    money_effect text NOT NULL DEFAULT 'NONE' CHECK (money_effect IN ('NONE', 'CHARGE_CANCELLED', 'CREDITED')),
    credit_amount numeric(12,2), removal_ref text,
    actor_id uuid, actor_office text, at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_summer_review_selection ON registration.summer_selection_review (selection_id, at);
COMMENT ON TABLE registration.summer_selection_review IS
  'V779: the write-once history of a Summer selection — every confirmation, decision, reopening, flag, question and answer with who, when, the evidence read and what happened to the money. Never changed or deleted (it goes with the selection when the student goes).';
SELECT audit.attach('registration.summer_selection_review');
CREATE FUNCTION registration.summer_review_kept() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' AND (pg_trigger_depth() > 1 OR coalesce(current_setting('moaum.maintenance', true), '') = 'on') THEN RETURN OLD; END IF;   -- a cascade from the selection
    RAISE EXCEPTION 'SUMMER_REVIEW_KEPT: a Summer verification record is history and is not changed or deleted' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_summer_review_kept BEFORE UPDATE OR DELETE ON registration.summer_selection_review FOR EACH ROW EXECUTE FUNCTION registration.summer_review_kept();

-- 2.5 · the examination gate's override
CREATE TABLE registration.summer_exam_override (
    session text NOT NULL REFERENCES policy.academic_session(name), act text NOT NULL CHECK (act IN ('OPEN', 'RELEASE')),
    reason text NOT NULL CHECK (length(btrim(reason)) >= 10), unverified integer NOT NULL,
    set_by uuid NOT NULL, set_office text NOT NULL, set_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY (session, act));
COMMENT ON TABLE registration.summer_exam_override IS
  'V779: the Academic Office''s recorded reason for opening the Summer''s examinations or releasing its score sheets while paid courses are still unverified; it holds only while the unverified count has not grown.';
SELECT audit.attach('registration.summer_exam_override');


-- ── 3.1 · the level the Summer reads ─────────────────────────────────────────────────────────────────────────────────────────────
/* the level a Summer limit, roster and queue read: the recorded level or the engine's, whichever is higher (a spillover student recorded
   at 100 who has reached 400 is a 400 Level student here); never the level of a new Summer registration, which keeps current_level */
CREATE FUNCTION registration.summer_level(p_student uuid) RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT greatest(s.current_level, coalesce(ap.computed_level, 0))
      FROM people.student s LEFT JOIN people.academic_position ap ON ap.student_id = s.id WHERE s.id = p_student;
$$;
COMMENT ON FUNCTION registration.summer_level(uuid) IS
  'V779: the level the Summer reads for a student — the recorded level or the one the academic engine computes, the higher. Serves the period''s level limit, the roster and the queue filters; the Summer registration itself keeps the recorded level.';

-- ── 3.2 · who may take the Summer, for any number of students at once, reading no result ──────────────────────────────────────
CREATE FUNCTION registration.summer_eligibility_of(p_session text, p_students uuid[])
RETURNS TABLE(student_id uuid, eligible boolean, category text, reason text)
LANGUAGE sql STABLE SET jit = off AS $$
    WITH p AS (SELECT pp.* FROM registration.summer_period pp WHERE pp.session = p_session),
    s AS (
        SELECT u.id AS sid, st.id AS st_id, st.entry_mode, st.status, st.programme_code, st.current_level, pr.category AS programme_category,
               ap.spillover_years, ap.spillover_state, ap.computed_level, ap.final_level AS ap_final,
               EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = st.id AND g.senate_state = 'APPROVED') AS graduand,
               EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p_session AND a.student_id = st.id AND a.revoked_at IS NULL) AS authorised
          FROM unnest(p_students) AS u(id)
          LEFT JOIN people.student st ON st.id = u.id
          LEFT JOIN ref.programme pr ON pr.code = st.programme_code
          LEFT JOIN people.academic_position ap ON ap.student_id = st.id),
    n AS (
        SELECT s.*, p.session IS NOT NULL AS has_period, p.categories, p.programmes, p.levels,
               -- the natural categories, from the engine's own position and never from matric patterns: spillover (the engine's years or
               -- state, or the fee rule's own reading) and final year (the record at or past the programme's final level, or the engine says so)
               (s.st_id IS NOT NULL AND (coalesce(s.spillover_years > 0, false) OR coalesce(s.spillover_state LIKE 'SPILLOVER%', false)
                                         OR coalesce(finance.is_spillover(s.st_id), false))) AS is_spill,
               (s.st_id IS NOT NULL AND (s.current_level >= coalesce(finance.final_level(s.programme_code), 400)
                                         OR coalesce(s.computed_level >= s.ap_final, false))) AS is_final
          FROM s LEFT JOIN p ON true),
    c AS (
        SELECT n.*,
               CASE WHEN n.is_spill THEN 'SPILLOVER' WHEN n.is_final THEN 'FINAL_YEAR' END AS nat1,
               CASE WHEN n.is_spill AND ('SPILLOVER' = ANY (n.categories) OR 'BEYOND_DURATION' = ANY (n.categories)) THEN 'SPILLOVER'
                    WHEN n.is_final AND 'FINAL_YEAR' = ANY (n.categories) THEN 'FINAL_YEAR' END AS adm,
               (n.st_id IS NULL OR NOT n.has_period OR n.entry_mode IN ('CCE', 'POSTGRADUATE') OR coalesce(n.programme_category, '') <> 'UNDER GRADUATE'
                OR n.status NOT IN ('ACTIVE', 'PROBATION') OR n.graduand) AS barred,
               (n.authorised AND 'AUTHORISED' = ANY (n.categories)) AS auth_ok,
               (n.programmes IS NOT NULL AND NOT (n.programme_code = ANY (n.programmes))) AS bad_programme,
               (n.levels IS NOT NULL AND NOT (greatest(n.current_level, coalesce(n.computed_level, 0)) = ANY (n.levels))) AS bad_level
          FROM n)
    SELECT c.sid,
           CASE WHEN c.barred THEN false WHEN c.auth_ok THEN true WHEN c.bad_programme OR c.bad_level THEN false
                WHEN c.nat1 IS NULL OR c.adm IS NULL THEN false ELSE true END,
           CASE WHEN c.barred THEN NULL WHEN c.auth_ok THEN coalesce(c.adm, 'AUTHORISED') WHEN c.bad_programme OR c.bad_level THEN c.nat1
                WHEN c.nat1 IS NULL THEN NULL WHEN c.adm IS NULL THEN c.nat1 ELSE c.adm END,
           CASE WHEN c.st_id IS NULL THEN 'NO_STUDENT'
                WHEN NOT c.has_period THEN 'NO_SUMMER'
                WHEN c.entry_mode IN ('CCE', 'POSTGRADUATE') OR coalesce(c.programme_category, '') <> 'UNDER GRADUATE' THEN 'NOT_UNDERGRADUATE'
                WHEN c.status NOT IN ('ACTIVE', 'PROBATION') THEN 'NOT_STUDYING'
                WHEN c.graduand THEN 'GRADUATED'
                WHEN c.auth_ok THEN NULL
                WHEN c.bad_programme THEN 'PROGRAMME_NOT_IN_SUMMER'
                WHEN c.bad_level THEN 'LEVEL_NOT_IN_SUMMER'
                WHEN c.nat1 IS NULL THEN 'NOT_FINAL_OR_SPILLOVER'
                WHEN c.adm IS NULL THEN 'CATEGORY_NOT_IN_SUMMER' END
      FROM c;
$$;
COMMENT ON FUNCTION registration.summer_eligibility_of(text, uuid[]) IS
  'V779: who may take the Summer of a session, for any number of students in one statement and reading no result: NO_STUDENT, NO_SUMMER, NOT_UNDERGRADUATE (CCE, postgraduate), NOT_STUDYING, GRADUATED, an authorisation, PROGRAMME_NOT_IN_SUMMER, LEVEL_NOT_IN_SUMMER (the Summer level), NOT_FINAL_OR_SPILLOVER, CATEGORY_NOT_IN_SUMMER, else eligible as SPILLOVER (the engine''s spillover years or state, or the fee rule) or FINAL_YEAR (the record at or past the programme''s final level, or the engine says so). An outstanding course is no condition: a missing result is never read as nothing owed.';

-- ── 3.3 · the one student's reading, with the courses owed counted for the page ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_eligibility(p_student uuid, p_session text)
RETURNS TABLE(eligible boolean, category text, outstanding integer, reason text) LANGUAGE plpgsql STABLE SET jit = off AS $$
DECLARE r record; v_out int;
BEGIN
    SELECT * INTO r FROM registration.summer_eligibility_of(p_session, ARRAY[p_student]);
    IF r.reason IN ('NO_STUDENT', 'NO_SUMMER', 'NOT_UNDERGRADUATE', 'NOT_STUDYING', 'GRADUATED') THEN
        RETURN QUERY SELECT r.eligible, r.category, 0, r.reason; RETURN;
    END IF;
    v_out := (SELECT count(*) FROM registration.carryovers(p_student))
             + CASE WHEN r.category = 'AUTHORISED'
                    THEN coalesce((SELECT cardinality(a.courses) FROM registration.summer_authorisation a
                                    WHERE a.session = p_session AND a.student_id = p_student AND a.revoked_at IS NULL), 0) ELSE 0 END;
    RETURN QUERY SELECT r.eligible, r.category, v_out, r.reason;
END $$;
COMMENT ON FUNCTION registration.summer_eligibility(uuid, text) IS
  'V779: a Summer candidate — registration.summer_eligibility_of for one student, with the courses detected as owed counted (plus the authorisation''s named courses for an authorised student) for the student''s own page. There is no longer a reason NO_OUTSTANDING_COURSE: a final-year or spillover student is eligible whatever their results show.';

-- ── 3.4 · results: one reading of 'passed', and the published results of many students at once ───────────────────────────────────
/* the one definition of 'passed' on the money path, the selection path and the evidence path: a published pass of the course, or of a live
   twin of it, in any session strictly before this Summer — never the Summer's own class or a later one */
CREATE FUNCTION registration.summer_passed(p_student uuid, p_course text, p_session text) RETURNS boolean LANGUAGE sql STABLE COST 100000 AS $$
    SELECT EXISTS (SELECT 1 FROM assessment.student_results(p_student) r
                    WHERE r.published AND r.outcome = 'GRADED' AND r.points > 0
                      AND (r.session < p_session OR (r.session = p_session AND r.semester < 3))
                      AND (r.course_code = p_course
                           OR r.course_code IN (SELECT CASE WHEN t.bsu_code = p_course THEN t.moau_code ELSE t.bsu_code END
                                                  FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND p_course IN (t.bsu_code, t.moau_code))));
$$;
COMMENT ON FUNCTION registration.summer_passed(uuid, text, text) IS
  'V779: whether the student has a published pass of the course (or of its live twin) in a session before the Summer of p_session. The one definition of passed for the money path, the selection path and the evidence; a result of that Summer''s own class, or a later one, is never evidence for or against its selection.';

/* a course the student sat in the Summer's own class and whose result is published: such a selection is sat, never reconciled again */
CREATE FUNCTION registration.summer_sat(p_student uuid, p_session text, p_course text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM registration.course_registration r
                     JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
                     JOIN catalogue.offering o ON o.id = e.offering_id AND o.course_code = p_course
                     JOIN assessment.score_sheet sh ON sh.offering_id = o.id AND sh.stage = 'PUBLISHED'
                     JOIN assessment.score sc ON sc.sheet_id = sh.id AND sc.student_id = p_student AND sc.outcome IS NOT NULL
                    WHERE r.student_id = p_student AND r.session = p_session AND r.semester = 3 AND r.status IN ('APPROVED', 'LOCKED'));
$$;
COMMENT ON FUNCTION registration.summer_sat(uuid, text, text) IS
  'V779: the student sat the course in the Summer''s own class and a result of it is published. Such a selection is skipped by the evidence and the reconcile: the Summer''s own result is neither evidence for nor against it.';

/* the published results of the students asked for, read as a set (the V573 chain, generalised): each student''s final sitting of each
   class they were registered in before this Summer (a special or re-sit published supersedes the Main), summed for each course on its key —
   how many sittings are published, failed and passed, and when the last of each was. No department, no elective filter: those are the
   evidence''s to apply, on the few rows that need it. */
CREATE FUNCTION registration.summer_results_of(p_session text, p_students uuid[])
RETURNS TABLE(student_id uuid, course_code text, published integer, fails integer, passes integer,
              last_fail_session text, last_fail_semester integer, last_pass_session text, last_pass_semester integer)
LANGUAGE sql STABLE SET jit = off AS $fn$
    WITH ent AS MATERIALIZED (
        SELECT r.student_id, r.session, r.semester, o.id AS offering_id, o.course_code
          FROM registration.course_registration r
          JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
          JOIN catalogue.offering o ON o.id = e.offering_id
         WHERE r.student_id = ANY (p_students) AND r.status IN ('APPROVED', 'LOCKED')
           AND (r.session < p_session OR (r.session = p_session AND r.semester < 3))),
    sheets AS MATERIALIZED (
        SELECT sh.id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
          FROM assessment.score_sheet sh
          LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
         WHERE sh.offering_id IN (SELECT x.offering_id FROM ent x)),
    scores AS MATERIALIZED (
        SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome
          FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls
         WHERE ls.student_id = ANY (p_students)),
    sitting AS (
        SELECT x.student_id, x.session, x.semester, x.offering_id, x.course_code, sh.stage, sh.kind, sc.points, sc.outcome,
               CASE sh.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
          FROM ent x
          JOIN sheets sh ON sh.offering_id = x.offering_id
          LEFT JOIN scores sc ON sc.sheet_id = sh.id AND sc.student_id = x.student_id),
    fin AS (
        SELECT DISTINCT ON (x.student_id, x.offering_id, x.session, x.semester) x.*
          FROM sitting x
         WHERE (x.kind IN ('SPECIAL', 'RESIT') AND x.stage = 'PUBLISHED' AND x.outcome IS NOT NULL) OR x.kind = 'MAIN'
         ORDER BY x.student_id, x.offering_id, x.session, x.semester, x.pr),
    res AS (
        SELECT f.student_id, f.course_code, f.session, f.semester,
               coalesce(f.stage = 'PUBLISHED' AND f.outcome IS NOT NULL, false) AS pub,
               coalesce(f.stage = 'PUBLISHED' AND (f.outcome = 'ABSENT' OR (f.outcome = 'GRADED' AND f.points = 0)), false) AS failed,
               coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points > 0, false) AS passed
          FROM fin f)
    SELECT r.student_id, r.course_code,
           (count(*) FILTER (WHERE r.pub))::int, (count(*) FILTER (WHERE r.failed))::int, (count(*) FILTER (WHERE r.passed))::int,
           (array_agg(r.session ORDER BY r.session DESC, r.semester DESC) FILTER (WHERE r.failed))[1],
           (array_agg(r.semester ORDER BY r.session DESC, r.semester DESC) FILTER (WHERE r.failed))[1],
           (array_agg(r.session ORDER BY r.session DESC, r.semester DESC) FILTER (WHERE r.passed))[1],
           (array_agg(r.semester ORDER BY r.session DESC, r.semester DESC) FILTER (WHERE r.passed))[1]
      FROM res r
     GROUP BY r.student_id, r.course_code
$fn$;
COMMENT ON FUNCTION registration.summer_results_of(text, uuid[]) IS
  'V779: the published results of the students asked for as a set — for each student and course (on the course key) the sittings published, failed and passed, and the session and semester of the last failure and the last pass — from the classes they were registered in before the Summer of p_session (its own class and later ones never count). The V573 reading generalised, read for the few who select, never for the population. Pass the bound ''9999/9999'' for every session.';

-- ── 3.5 · the evidence of a selection ────────────────────────────────────────────────────────────────────────────────────────────
/* what the published results say of each selection of the students asked for: PASSED, AWAITED (registered this session and no result yet),
   FAILED (an owed course as registration.carryover_attempts reads it: published F or absence, not an elective) or NO_RESULT — never a pass
   from a missing result. A selection whose own Summer class has a published result is sat and is not read. */
CREATE FUNCTION registration.summer_evidence(p_session text, p_students uuid[])
RETURNS TABLE(selection_id uuid, student_id uuid, course_code text, evidence text,
              last_fail_session text, last_fail_semester integer, last_pass_session text, last_pass_semester integer, attempts integer)
LANGUAGE plpgsql STABLE SET jit = off AS $$
BEGIN
    RETURN QUERY
    WITH sel AS (
        SELECT x.id, x.student_id AS sid, x.course_code AS code FROM registration.summer_selection x
         WHERE x.session = p_session AND x.student_id = ANY (p_students) AND NOT registration.summer_sat(x.student_id, x.session, x.course_code)),
    res AS MATERIALIZED (SELECT * FROM registration.summer_results_of(p_session, p_students)),
    -- a pass of the live twin of a course counts for it: the pairs both ways, joined to the results once (never a probe of the results for each selection)
    tp AS (SELECT t.bsu_code AS code, t.moau_code AS other FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL
           UNION ALL SELECT t.moau_code, t.bsu_code FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL),
    tw AS (SELECT x.student_id AS sid, tp.code, sum(x.passes) AS passes FROM tp JOIN res x ON x.course_code = tp.other GROUP BY x.student_id, tp.code),
    awaited AS (
        SELECT DISTINCT r.student_id AS sid, o.course_code AS code
          FROM registration.course_registration r
          JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
          JOIN catalogue.offering o ON o.id = e.offering_id
         WHERE r.student_id = ANY (p_students) AND r.session = p_session AND r.semester IN (1, 2) AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
           AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score sc ON sc.sheet_id = sh.id AND sc.student_id = r.student_id
                            WHERE sh.offering_id = o.id AND sh.stage = 'PUBLISHED' AND sc.outcome IS NOT NULL)),
    j AS (
        SELECT s.id, s.sid, s.code, coalesce(o.passes, 0) + coalesce(w.passes, 0) AS passes, o.fails,
               o.last_fail_session AS lfs, o.last_fail_semester AS lfn, o.last_pass_session AS lps, o.last_pass_semester AS lpn,
               EXISTS (SELECT 1 FROM awaited a WHERE a.sid = s.sid AND a.code = s.code) AS is_awaited
          FROM sel s
          LEFT JOIN res o ON o.student_id = s.sid AND o.course_code = s.code
          LEFT JOIN tw w ON w.sid = s.sid AND w.code = s.code)
    SELECT j.id, j.sid, j.code,
           CASE WHEN j.passes > 0 THEN 'RESULT_PASSED'
                WHEN j.is_awaited THEN 'RESULT_AWAITED'
                WHEN coalesce(j.fails, 0) > 0
                     AND NOT registration.is_elective_for(j.sid, j.code)
                     AND EXISTS (SELECT 1 FROM registration.carryover_attempts(j.sid) a
                                  WHERE a.course_code = j.code AND (a.session, a.semester) < (p_session, 3)) THEN 'RESULT_FAILED'
                ELSE 'NO_RESULT' END,
           j.lfs, j.lfn, j.lps, j.lpn, coalesce(j.fails, 0)
      FROM j;
END $$;
COMMENT ON FUNCTION registration.summer_evidence(text, uuid[]) IS
  'V779: what the published results say of each Summer selection of the students asked for — RESULT_PASSED (a pass before the Summer, the course or its twin), RESULT_AWAITED (registered this session, no result yet), RESULT_FAILED (owed as registration.carryover_attempts reads it, so a later rule on carry-overs reaches the Summer without a second edit) or NO_RESULT. A missing result is NO_RESULT, never a pass. A selection sat in its own Summer class is not read.';


-- ── 3.6 · the courses a student may select ───────────────────────────────────────────────────────────────────────────────────────
/* the pool of one student's Summer, plpgsql so the plans are cached (one inlined statement planned for 388 ms): the programme's own
   structure up to its final level (both semesters, every level a final-year or spillover student may owe), the courses detected as owed
   (published F or absence) and the courses the Academic Office named — each with the evidence the results give, the units the
   programme gives it, the course as it was taken (V771), the selection and its verification, selectable or why not, and the fee.
   SIWES is registered on its own page (V752, V777), an elective or deficiency course is never offered by the structure (V689). */
CREATE FUNCTION registration.summer_selectable(p_student uuid, p_session text)
RETURNS TABLE(course_code text, title text, units integer, course_semester integer, both_semesters boolean, level integer, programme_basis text,
              is_gst boolean, source text, evidence text, attempts integer, original_session text, original_semester integer, original_source text,
              as_taken_code text, as_taken_title text, as_taken_session text, as_taken_semester integer, as_taken_units integer, basis text,
              status text, selection_id uuid, verification text, verified_via text, decision_reason text, clarification_open boolean,
              clarification_note text, student_note text, selectable boolean, reason text, course_fee numeric)
LANGUAGE plpgsql STABLE SET jit = off AS $$
DECLARE s record; v_pass text[]; v_twin text[]; v_awaited text[]; v_siwes text; v_fee numeric;
BEGIN
    SELECT st.id, st.programme_code, st.entry_level, st.current_level, st.curriculum_track, st.curriculum_version INTO s
      FROM people.student st WHERE st.id = p_student;
    IF s.id IS NULL THEN RETURN; END IF;
    -- what the results say, read once: the passes before this Summer, their live twins, the courses registered this session and awaiting a result
    SELECT coalesce(array_agg(DISTINCT r.course_code), '{}') INTO v_pass FROM assessment.student_results(p_student) r
     WHERE r.published AND r.outcome = 'GRADED' AND r.points > 0 AND (r.session < p_session OR (r.session = p_session AND r.semester < 3));
    SELECT coalesce(array_agg(DISTINCT CASE WHEN t.bsu_code = ANY (v_pass) THEN t.moau_code ELSE t.bsu_code END), '{}') INTO v_twin
      FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND (t.bsu_code = ANY (v_pass) OR t.moau_code = ANY (v_pass));
    SELECT coalesce(array_agg(DISTINCT o.course_code), '{}') INTO v_awaited
      FROM registration.course_registration r
      JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
      JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE r.student_id = p_student AND r.session = p_session AND r.semester IN (1, 2) AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')
       AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh JOIN assessment.score sc ON sc.sheet_id = sh.id AND sc.student_id = p_student
                        WHERE sh.offering_id = o.id AND sh.stage = 'PUBLISHED' AND sc.outcome IS NOT NULL);
    v_siwes := registration.siwes_course_of(s.programme_code, s.curriculum_version);
    SELECT f.course_fee INTO v_fee FROM finance.summer_fee_for(p_student, p_session) f;
    RETURN QUERY
    WITH co AS (SELECT c.course_code, c.attempts FROM registration.carryovers(p_student) c),
    att AS (SELECT a.course_code, a.session, a.semester, row_number() OVER (PARTITION BY a.course_code ORDER BY a.session DESC, a.semester DESC) AS rk
              FROM registration.carryover_attempts(p_student) a),
    auth AS (SELECT DISTINCT upper(btrim(code)) AS course_code
               FROM registration.summer_authorisation sa CROSS JOIN LATERAL unnest(coalesce(sa.courses, ARRAY[]::text[])) code
              WHERE sa.session = p_session AND sa.student_id = p_student AND sa.revoked_at IS NULL AND btrim(code) <> ''),
    sel AS (SELECT x.* FROM registration.summer_selection x WHERE x.student_id = p_student AND x.session = p_session),
    ch AS (SELECT c.course_code, c.state FROM registration.summer_charge c
            WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state <> 'CANCELLED'),
    taken_off AS (SELECT DISTINCT c.course_code FROM registration.summer_credit cr JOIN registration.summer_charge c ON c.id = cr.source_charge_id
                   WHERE c.student_id = p_student AND c.session = p_session),
    -- the programme's structure: the V663 rule of what a programme binds a student to, never bounded by the level they are recorded at
    struct AS (
        SELECT co2.course_code, min(co2.level) AS level, (array_agg(co2.basis ORDER BY co2.level))[1] AS pbasis
          FROM catalogue.course_offer co2
          CROSS JOIN registration.flex_rule() pol
          JOIN catalogue.course k2 ON k2.code = co2.course_code
         WHERE co2.programme_code = s.programme_code AND co2.level >= coalesce(s.entry_level, 100) AND co2.level <= coalesce(finance.final_level(s.programme_code), 400)
           AND coalesce(co2.basis, 'Core') NOT IN ('Elective', 'Deficiency', 'Research')
           AND k2.state <> 'ENDED' AND k2.code NOT LIKE 'DMO %' AND NOT coalesce(k2.industrial_training, false)
           AND (pol.curriculum_open OR co2.track IS NULL OR s.curriculum_track IS NULL OR co2.track = s.curriculum_track)
           AND (NOT EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x WHERE x.course_code = co2.course_code AND x.programme_code = co2.programme_code AND x.level = co2.level)
                OR EXISTS (SELECT 1 FROM catalogue.course_offer_specialisation x JOIN people.student_specialisation ss ON ss.specialisation_id = x.specialisation_id AND ss.student_id = p_student
                            WHERE x.course_code = co2.course_code AND x.programme_code = co2.programme_code AND x.level = co2.level))
         GROUP BY co2.course_code),
    pool AS (
        SELECT DISTINCT ON (z.course_code) z.course_code, z.source
          FROM (SELECT o.course_code, 'CARRY_OVER'::text AS source, 1 AS pr FROM co o
                UNION ALL SELECT a.course_code, 'AUTHORISED', 2 FROM auth a
                UNION ALL SELECT st.course_code, 'STRUCTURE', 3 FROM struct st
                -- a selection that stands or was decided stays on the page whatever became of the source that brought it in
                UNION ALL SELECT sl.course_code, CASE sl.basis WHEN 'CARRY_OVER' THEN 'CARRY_OVER' WHEN 'AUTHORISED' THEN 'AUTHORISED' ELSE 'STRUCTURE' END, 4
                            FROM sel sl WHERE EXISTS (SELECT 1 FROM ch WHERE ch.course_code = sl.course_code)
                                           OR (sl.state IN ('NOT_OUTSTANDING', 'REJECTED') AND (sl.removal_ref IS NOT NULL OR sl.course_code IN (SELECT t.course_code FROM taken_off t)))) z
         ORDER BY z.course_code, z.pr),
    taken AS (
        SELECT DISTINCT ON (o.course_code) o.course_code, at.code_as_taken, at.title, r.session, r.semester, at.units
          FROM registration.entry e
          JOIN registration.course_registration r ON r.id = e.registration_id
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course_as_taken at ON at.id = e.as_taken_id
         WHERE r.student_id = p_student AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
         ORDER BY o.course_code, r.session DESC, r.semester DESC),
    x AS (
        SELECT p.course_code AS code, p.source AS src, k.code AS k_code, k.title AS k_title, k.state AS k_state, k.semester AS k_sem,
               coalesce(k.both_semesters, false) AS k_both, k.kind AS k_kind, k.industrial_training AS k_siwes,
               coalesce(catalogue.units_for(p.course_code, s.programme_code, NULL), k.units) AS u,
               st.level AS st_level, st.pbasis,
               CASE WHEN p.course_code = ANY (v_pass) OR p.course_code = ANY (v_twin) THEN 'RESULT_PASSED'
                    WHEN p.course_code = ANY (v_awaited) THEN 'RESULT_AWAITED'
                    WHEN o.course_code IS NOT NULL THEN 'RESULT_FAILED' ELSE 'NO_RESULT' END AS ev,
               coalesce(o.attempts, 0) AS attempts,
               a.session AS a_session, a.semester AS a_semester,
               sl.id AS sel_id, sl.basis AS sel_basis, sl.state AS sel_state, sl.verified_via, sl.decision_reason, sl.clarification_open, sl.clarification_note,
               sl.student_note, sl.original_session AS sl_os, sl.original_semester AS sl_on, sl.removal_ref,
               c.state AS ch_state,
               EXISTS (SELECT 1 FROM taken_off t WHERE t.course_code = p.course_code) AS was_paid,
               t.code_as_taken, t.title AS t_title, t.session AS t_session, t.semester AS t_semester, t.units AS t_units
          FROM pool p
          LEFT JOIN catalogue.course k ON k.code = p.course_code
          LEFT JOIN struct st ON st.course_code = p.course_code
          LEFT JOIN co o ON o.course_code = p.course_code
          LEFT JOIN att a ON a.course_code = p.course_code AND a.rk = 1
          LEFT JOIN sel sl ON sl.course_code = p.course_code
          LEFT JOIN ch c ON c.course_code = p.course_code
          LEFT JOIN taken t ON t.course_code = p.course_code),
    y AS (
        SELECT x.*,
               CASE WHEN x.k_code IS NULL THEN 'COURSE_UNKNOWN'
                    WHEN x.k_state = 'ENDED' THEN 'COURSE_ENDED'
                    WHEN x.ch_state = 'PAID' THEN 'ALREADY_REGISTERED'
                    WHEN x.ch_state = 'DUE' THEN 'ALREADY_SELECTED'
                    WHEN x.sel_state = 'NOT_OUTSTANDING' THEN 'DECIDED_NOT_OUTSTANDING'
                    WHEN x.sel_state = 'REJECTED' THEN 'DECIDED_REJECTED'
                    WHEN coalesce(x.k_siwes, false) OR x.code = v_siwes THEN 'SIWES_OWN_PAGE'
                    WHEN x.ev = 'RESULT_PASSED' THEN 'PASSED'
                    WHEN x.ev = 'RESULT_AWAITED' THEN 'RESULT_AWAITED' END AS why
          FROM x)
    SELECT y.code, y.k_title, y.u::int, y.k_sem, y.k_both, y.st_level, y.pbasis,
           coalesce(y.k_kind = 'GST' OR y.pbasis = 'GST', false), y.src, y.ev, y.attempts,
           CASE WHEN y.a_session IS NOT NULL THEN y.a_session ELSE y.sl_os END,
           CASE WHEN y.a_session IS NOT NULL THEN y.a_semester ELSE y.sl_on END,
           CASE WHEN y.a_session IS NOT NULL THEN 'RESULTS' WHEN y.sl_os IS NOT NULL THEN 'STUDENT' END,
           y.code_as_taken, y.t_title, y.t_session, y.t_semester, y.t_units,
           coalesce(y.sel_basis, CASE y.src WHEN 'CARRY_OVER' THEN 'CARRY_OVER' WHEN 'AUTHORISED' THEN 'AUTHORISED' ELSE 'STUDENT_SELECTED' END),
           CASE WHEN y.ch_state = 'PAID' THEN 'REGISTERED' WHEN y.ch_state = 'DUE' THEN 'SELECTED'
                WHEN y.sel_state IN ('NOT_OUTSTANDING', 'REJECTED') AND (y.removal_ref IS NOT NULL OR y.was_paid) THEN 'TAKEN_OFF'
                ELSE 'OUTSTANDING' END,
           y.sel_id, y.sel_state, y.verified_via, y.decision_reason, coalesce(y.clarification_open, false), y.clarification_note, y.student_note,
           y.why IS NULL, y.why, v_fee
      FROM y
     ORDER BY y.st_level NULLS LAST, y.k_sem, y.code;
END $$;
COMMENT ON FUNCTION registration.summer_selectable(uuid, text) IS
  'V779: the courses a student may select for the Summer of a session, each with the evidence the results give, the units the programme gives it, the course as it was taken (V771), the selection and its verification, selectable or why not (COURSE_UNKNOWN, COURSE_ENDED, ALREADY_REGISTERED, ALREADY_SELECTED, DECIDED_NOT_OUTSTANDING, DECIDED_REJECTED, SIWES_OWN_PAGE, PASSED, RESULT_AWAITED) and the fee. The pool is the programme''s structure up to its final level (never bounded by the level on record), the courses detected as owed and the courses the Academic Office named. A missing result is never a pass and never proof of nothing owed.';


-- ── 3.10 · the writers of verification state ─────────────────────────────────────────────────────────────────────────────────────
/* the number of a verification batch: one for each decision call or system run */
CREATE FUNCTION registration.summer_batch_ref() RETURNS text LANGUAGE sql AS $$
    SELECT 'SVB-' || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('SUMMER_REVIEW', 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0');
$$;
COMMENT ON FUNCTION registration.summer_batch_ref() IS 'V779: the next verification batch reference, SVB-YYYY-NNNNN.';

/* the batch of the act in hand: one a system run (a reconcile) holds for all its rows, else a new one */
CREATE FUNCTION registration.summer_current_batch() RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text := nullif(current_setting('moaum.summer_batch', true), '');
BEGIN
    RETURN coalesce(v, registration.summer_batch_ref());
END $$;

/* one row of a selection's history: a system act (via RESULTS or SYSTEM) is written with no actor and the office 'system' */
CREATE FUNCTION registration.summer_review_row(p_selection uuid, p_batch text, p_action text, p_from text, p_to text, p_via text, p_evidence text,
                                               p_reason text, p_note text, p_money text, p_credit numeric, p_removal text) RETURNS void LANGUAGE sql AS $$
    INSERT INTO registration.summer_selection_review (selection_id, batch_ref, action, from_state, to_state, via, evidence, reason, note,
                                                      money_effect, credit_amount, removal_ref, actor_id, actor_office)
    VALUES (p_selection, p_batch, p_action, p_from, p_to, p_via, p_evidence, p_reason, p_note, coalesce(p_money, 'NONE'), p_credit, p_removal,
            CASE WHEN p_via IN ('RESULTS', 'SYSTEM') THEN NULL ELSE nullif(current_setting('moaum.actor_id', true), '')::uuid END,
            CASE WHEN p_via IN ('RESULTS', 'SYSTEM') THEN 'system' ELSE nullif(current_setting('moaum.actor_office', true), '') END);
$$;

/* the only writer of a selection's state: its target, who and what said so, the entry's type kept in step (CARRYOVER while confirmed,
   CURRENT while pending: the state, not the basis, decides), and one row of history */
CREATE FUNCTION registration.summer_selection_move(p_id uuid, p_to text, p_via text, p_action text, p_reason text, p_note text, p_batch text,
                                                   p_evidence text, p_money text, p_credit numeric, p_removal text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s registration.summer_selection; v_sys boolean := p_via IN ('RESULTS', 'SYSTEM');
        v_actor uuid; v_office text; v_type text;
BEGIN
    -- SYSTEM only sends a selection back to the Office (a revoked authorisation, 3.13 d)
    IF p_to NOT IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING', 'NOT_OUTSTANDING', 'REJECTED')
       OR p_via NOT IN ('RESULTS', 'AUTHORISATION', 'OFFICER', 'SYSTEM')
       OR (p_via = 'SYSTEM' AND p_to <> 'PENDING_VERIFICATION')
       OR (p_to = 'REJECTED' AND p_via <> 'OFFICER')
       OR (p_to = 'CONFIRMED_OUTSTANDING' AND p_via NOT IN ('RESULTS', 'AUTHORISATION', 'OFFICER'))
       OR (p_to = 'NOT_OUTSTANDING' AND p_via = 'AUTHORISATION') THEN
        RAISE EXCEPTION 'SUMMER_MOVE: % by % is not a verification state change', p_to, p_via USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM registration.summer_selection WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_SELECTION_UNKNOWN: no such Summer selection' USING ERRCODE = '23514'; END IF;
    v_actor := CASE WHEN v_sys THEN NULL ELSE nullif(current_setting('moaum.actor_id', true), '')::uuid END;
    v_office := CASE WHEN v_sys THEN 'system' ELSE nullif(current_setting('moaum.actor_office', true), '') END;
    UPDATE registration.summer_selection SET
           state = p_to,
           verified_via = CASE WHEN p_to = 'PENDING_VERIFICATION' THEN NULL ELSE p_via END,
           decision_reason = CASE WHEN p_to IN ('NOT_OUTSTANDING', 'REJECTED') THEN btrim(p_reason) ELSE NULL END,
           decided_by = v_actor, decided_office = v_office, decided_at = now(),
           needs_review = false, review_flag = NULL,
           -- a question the Office asked stays when the results alone send the selection back to pending
           clarification_open = CASE WHEN p_to = 'PENDING_VERIFICATION' AND v_sys THEN clarification_open ELSE false END,
           removal_ref = coalesce(p_removal, removal_ref),
           updated_at = now()
     WHERE id = p_id;
    -- D3: the registered entry's type follows the state
    IF p_to IN ('CONFIRMED_OUTSTANDING', 'PENDING_VERIFICATION') THEN
        v_type := CASE WHEN p_to = 'CONFIRMED_OUTSTANDING' THEN 'CARRYOVER' ELSE 'CURRENT' END;
        UPDATE registration.entry e SET entry_type = v_type
          FROM registration.course_registration r, catalogue.offering o
         WHERE r.student_id = s.student_id AND r.session = s.session AND r.semester = 3 AND e.registration_id = r.id
           AND o.id = e.offering_id AND o.course_code = s.course_code
           AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND e.entry_type IS DISTINCT FROM v_type;
    END IF;
    PERFORM registration.summer_review_row(p_id, coalesce(p_batch, registration.summer_current_batch()), p_action, s.state, p_to, p_via,
                                           p_evidence, p_reason, p_note, p_money, p_credit, p_removal);
END $$;
COMMENT ON FUNCTION registration.summer_selection_move(uuid, text, text, text, text, text, text, text, text, numeric, text) IS
  'V779: the only writer of a Summer selection''s state. p_via RESULTS is the system confirming or taking back by results (no actor, office system), SYSTEM the system sending a selection back to pending (a revoked authorisation), AUTHORISATION or OFFICER a person; a REJECTED is always OFFICER. The entry''s type follows the state (CARRYOVER while confirmed, CURRENT while pending) and one row of history is written. Clears the flag of review on any move.';

/* the only writer of a selection's flag of review when no state changes; NULL clears; setting a flag already set (or clearing none) writes nothing */
CREATE FUNCTION registration.summer_selection_flag(p_id uuid, p_flag text, p_batch text, p_evidence text, p_note text, p_via text DEFAULT 'SYSTEM')
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE s registration.summer_selection;
BEGIN
    IF p_flag IS NOT NULL AND p_flag NOT IN ('PASSED_ON_RECORD', 'EVIDENCE_CHANGED', 'ENTRY_REMOVED') THEN
        RAISE EXCEPTION 'SUMMER_FLAG: % is not a flag of review', p_flag USING ERRCODE = '23514';
    END IF;
    SELECT * INTO s FROM registration.summer_selection WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_SELECTION_UNKNOWN: no such Summer selection' USING ERRCODE = '23514'; END IF;
    IF p_flag IS NULL THEN
        IF NOT s.needs_review THEN RETURN false; END IF;
        UPDATE registration.summer_selection SET needs_review = false, review_flag = NULL, updated_at = now() WHERE id = p_id;
        PERFORM registration.summer_review_row(p_id, coalesce(p_batch, registration.summer_current_batch()), 'FLAG_CLEARED', s.state, s.state,
                                               coalesce(p_via, 'SYSTEM'), p_evidence, s.review_flag, p_note, 'NONE', NULL, NULL);
        RETURN true;
    END IF;
    IF s.review_flag = p_flag THEN RETURN false; END IF;
    UPDATE registration.summer_selection SET needs_review = true, review_flag = p_flag, updated_at = now() WHERE id = p_id;
    PERFORM registration.summer_review_row(p_id, coalesce(p_batch, registration.summer_current_batch()), 'FLAGGED', s.state, s.state,
                                           coalesce(p_via, 'SYSTEM'), p_evidence, p_flag, p_note, 'NONE', NULL, NULL);
    RETURN true;
END $$;
COMMENT ON FUNCTION registration.summer_selection_flag(uuid, text, text, text, text, text) IS
  'V779: sets (PASSED_ON_RECORD, EVIDENCE_CHANGED, ENTRY_REMOVED) or clears (NULL) the flag of review of a Summer selection without changing its state; a flag already set, or none to clear, writes nothing and answers false.';

-- ── 3.12 · the removal of a paid entry, a decision's credit, the two removal triggers ─────────────────────────────────────────────
/* the Summer's own use of the removal route (V772): the entry withdrawn under an APPLIED registration.entry_removal without the ICT office
   gate; a course carrying a mark is refused (the Director of ICT requests it, the Registry confirms); an entry already withdrawn under an
   APPLIED removal (the Director's) is adopted: its ref is returned and nothing is written */
CREATE FUNCTION registration.summer_withdraw_entry(p_student uuid, p_session text, p_course text, p_reason text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        r registration.course_registration; e registration.entry; o catalogue.offering; v_res record; v_ref text; v_at catalogue.course_as_taken;
        v_title text; v_year text := to_char(now(), 'YYYY');
BEGIN
    -- the payment trigger's order: the student, the charges, then the registration and the entry
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = 3 FOR UPDATE;
    IF NOT FOUND THEN RETURN NULL; END IF;
    SELECT e2.* INTO e FROM registration.entry e2 JOIN catalogue.offering o2 ON o2.id = e2.offering_id
     WHERE e2.registration_id = r.id AND o2.course_code = p_course ORDER BY (e2.status NOT IN ('DROPPED', 'WITHDRAWN')) DESC LIMIT 1 FOR UPDATE OF e2;
    IF NOT FOUND THEN RETURN NULL; END IF;
    IF e.status IN ('DROPPED', 'WITHDRAWN') THEN
        SELECT x.ref INTO v_ref FROM registration.entry_removal x
         WHERE x.registration_id = r.id AND x.offering_id = e.offering_id AND x.state = 'APPLIED' LIMIT 1;
        RETURN v_ref;
    END IF;
    SELECT * INTO o FROM catalogue.offering WHERE id = e.offering_id;
    SELECT * INTO v_res FROM registration.entry_result(p_student, e.offering_id);
    IF v_res.has_result THEN
        RAISE EXCEPTION 'SUMMER_HAS_RESULT: a mark is already on record for % ; the Director of ICT requests its removal on Course Registration Correction and the Registrar or Deputy Registrar confirms; then record this decision', p_course
            USING ERRCODE = '23514';
    END IF;
    IF e.as_taken_id IS NOT NULL THEN SELECT * INTO v_at FROM catalogue.course_as_taken WHERE id = e.as_taken_id; END IF;
    SELECT coalesce(v_at.title, o.title, c.title) INTO v_title FROM catalogue.course c WHERE c.code = o.course_code;
    v_ref := 'RCR-' || v_year || '-' || lpad(platform.next_number('ENTRY_REMOVAL', 'UNIVERSITY', v_year)::text, 5, '0');
    INSERT INTO registration.entry_removal (ref, group_ref, student_id, registration_id, offering_id, course_code, code_as_taken, title, session, semester, level,
                                            was_status, was_units, was_entry_type, was_basis, was_as_taken, was_added, had_result, result_words, graduate,
                                            reason, state, requested_by, requested_office, decided_by, decided_office, decided_at, decision_note)
    VALUES (v_ref, v_ref, p_student, r.id, e.offering_id, o.course_code, v_at.code_as_taken, v_title, r.session, r.semester, r.level,
            e.status, e.units, e.entry_type, e.basis, e.as_taken_id, registration.entry_came(r.id, e.offering_id), false, NULL,
            EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED'),
            btrim(p_reason), 'APPLIED', who, v_office, who, v_office, clock_timestamp(), 'Summer Semester course verification');
    UPDATE registration.entry SET status = 'WITHDRAWN' WHERE registration_id = r.id AND offering_id = e.offering_id;
    IF catalogue.class_examined(e.offering_id) THEN
        PERFORM credentials.flag_documents(p_student, ARRAY['TRANSCRIPT', 'SESSIONAL_TRANSCRIPT', 'MINI_TRANSCRIPT', 'ACADEMIC_STATEMENT'],
                                           'A course was taken off the student''s registration (' || v_ref || ')');
    END IF;
    RETURN v_ref;
END $$;
COMMENT ON FUNCTION registration.summer_withdraw_entry(uuid, text, text, text) IS
  'V779: a paid Summer course taken off the semester-3 registration by the Academic Office''s decision, as the Director of ICT''s removal route does it (an APPLIED registration.entry_removal, RCR-YYYY-NNNNN, the entry WITHDRAWN) without its office gate. Answers the removal ref; the Director''s own removal of an already-withdrawn entry is adopted (its ref answered, nothing written); a course carrying a mark is refused SUMMER_HAS_RESULT.';

/* the money of a cancelled PAID charge held as a Summer credit for the Bursar: one credit for the money one payment held on one charge
   (uq_summer_credit_charge), the second attempt for the same charge and payment answers the first's id and writes nothing */
CREATE FUNCTION registration.summer_credit_for_charge(p_charge uuid, p_reference uuid, p_note text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ch registration.summer_charge; v_id uuid;
BEGIN
    SELECT * INTO ch FROM registration.summer_charge WHERE id = p_charge;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_CHARGE_UNKNOWN: no such Summer charge' USING ERRCODE = '23514'; END IF;
    INSERT INTO registration.summer_credit (student_id, session, reference_id, amount, source, source_charge_id, note)
    VALUES (ch.student_id, ch.session, p_reference, ch.amount, 'DECISION', p_charge, p_note)
    ON CONFLICT (source_charge_id, reference_id) WHERE source_charge_id IS NOT NULL DO NOTHING
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN SELECT id INTO v_id FROM registration.summer_credit WHERE source_charge_id = p_charge AND reference_id = p_reference; END IF;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION registration.summer_credit_for_charge(uuid, uuid, text) IS
  'V779: the Summer credit of a cancelled PAID charge — its amount, source DECISION, the payment it was paid by; one credit for the money one payment held on one charge (the key (source_charge_id, reference_id); a second call for the same charge and payment answers the first''s id and writes nothing), never an automatic refund: the Bursar settles it.';

/* the programme fee follows the last course, whatever takes it (owner's O2, D6): when a student's last COURSE charge of a Summer stops being
   DUE or PAID — unselected, the window closed, taken back at a draw, a reconcile or a confirmation, decided against — a DUE programme fee is
   cancelled and a PAID one is cancelled with its money held as ONE open Summer credit for the Bursar (never an automatic refund; the student who
   selects again in the same open window has it reinstated, 3.7). A decision credits the programme fee itself in its own words and figures
   (summer_verify sets moaum.summer_money for the statements of its money). Locks: the course row is held by the statement that cancelled it, then
   the programme fee; the course charges are read again once it is held. */
CREATE FUNCTION registration.summer_programme_follows() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p registration.summer_charge;
BEGIN
    IF coalesce(current_setting('moaum.summer_money', true), '') = 'verify' THEN RETURN NULL; END IF;
    IF EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = NEW.student_id AND c.session = NEW.session
                  AND c.kind = 'COURSE' AND c.state <> 'CANCELLED') THEN
        RETURN NULL;
    END IF;
    SELECT * INTO p FROM registration.summer_charge c WHERE c.student_id = NEW.student_id AND c.session = NEW.session
       AND c.kind = 'PROGRAMME' AND c.state <> 'CANCELLED' FOR UPDATE;
    IF NOT FOUND OR EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = NEW.student_id AND c.session = NEW.session
                               AND c.kind = 'COURSE' AND c.state <> 'CANCELLED') THEN
        RETURN NULL;
    END IF;
    IF p.state = 'DUE' THEN
        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now() WHERE id = p.id;
    ELSIF p.paid_reference_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.source_charge_id = p.id AND x.reference_id = p.paid_reference_id) THEN
            RAISE EXCEPTION 'SUMMER_CREDIT_EXISTS: the money this payment holds on the programme fee is already a Summer credit; the Bursary checks it' USING ERRCODE = '23514';
        END IF;
        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now(), paid_at = NULL WHERE id = p.id;
        PERFORM registration.summer_credit_for_charge(p.id, p.paid_reference_id, 'Programme fee: no Summer course remains after ' || NEW.course_code || ' was taken off');
        UPDATE registration.summer_charge SET paid_reference_id = NULL WHERE id = p.id;
    END IF;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION registration.summer_programme_follows() IS
  'V779: trigger function of trg_summer_programme_follows — when the last COURSE charge of a student''s Summer stops being DUE or PAID by any route, the programme fee follows: DUE cancelled, PAID cancelled and its money held as one open Summer credit (source DECISION, keyed on the charge and its payment) for the Bursar; a decision does this itself (moaum.summer_money = verify). A PAID fee whose payment is no longer on the record is left for the Bursary.';

/* a credit the student's own selection settled by reinstating the programme fee (3.7) IS that paid charge: reopened it would count the same
   money twice (a PAID charge and an open credit) */
CREATE FUNCTION registration.summer_credit_reinstated_kept() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'SUMMER_CREDIT_REINSTATED: this credit paid the programme fee the student selected back; its money is that paid fee and it is not reopened'
        USING ERRCODE = '23514';
END $$;
COMMENT ON FUNCTION registration.summer_credit_reinstated_kept() IS
  'V779: trigger function of trg_summer_credit_reinstated_kept — a DECISION credit applied by reinstating the programme fee (settled_note ''Reinstated as the programme fee: …'') is never reopened (SUMMER_CREDIT_REINSTATED): the same money would be a PAID charge and an open credit.';

/* a removal the Academic Office's decision made or adopted is not undone or cancelled by the Director of ICT */
CREATE FUNCTION registration.summer_removal_held() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM registration.summer_selection s WHERE s.removal_ref = OLD.ref) THEN
        RAISE EXCEPTION 'SUMMER_REMOVAL_HELD: this removal was made by a Summer Semester decision (%); the entry, the charge and the credit stand as that decision left them', OLD.ref
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;

/* a paid Summer course the Director of ICT removed on their own (no mark: applied at once) is flagged for the Academic Office, never dropped silently */
CREATE FUNCTION registration.summer_removal_noted() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s registration.summer_selection;
BEGIN
    IF NEW.decision_note = 'Summer Semester course verification' OR NOT registration.is_summer_for(NEW.student_id, NEW.session, 3) THEN RETURN NULL; END IF;
    SELECT x.* INTO s FROM registration.summer_selection x
     WHERE x.student_id = NEW.student_id AND x.session = NEW.session AND x.course_code = NEW.course_code
       AND x.removal_ref IS NULL AND x.state NOT IN ('NOT_OUTSTANDING', 'REJECTED')
       AND EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = x.student_id AND c.session = x.session
                      AND c.course_code = x.course_code AND c.kind = 'COURSE' AND c.state = 'PAID');
    IF s.id IS NOT NULL THEN
        PERFORM registration.summer_selection_flag(s.id, 'ENTRY_REMOVED', NULL, NULL, 'The Director of ICT took the paid course off the registration (' || NEW.ref || ')', 'SYSTEM');
    END IF;
    RETURN NULL;
END $$;


-- ── 3.8 · a selection stands until a pass or a decision ends it (the take-back trap) ──────────────────────────────────────────────
/* a course still owed for the student's Summer: not decided against, not passed (the one predicate, before this Summer), and either selected
   by the student (any basis: a pending or a confirmed selection stands) or still in the pool the detected failures and the Office's
   authorisation make. A reference holding a course that is no longer outstanding is not payable, and a payment confirmed anyway takes
   the course back rather than pay it. An ended course not passed stays outstanding (the draw cancels it on its own test). */
CREATE OR REPLACE FUNCTION registration.summer_course_outstanding(p_student uuid, p_session text, p_course text) RETURNS boolean
LANGUAGE sql STABLE COST 100000 AS $$
    SELECT NOT EXISTS (SELECT 1 FROM registration.summer_selection x WHERE x.student_id = p_student AND x.session = p_session AND x.course_code = p_course
                        AND x.state IN ('NOT_OUTSTANDING', 'REJECTED'))
       AND NOT registration.summer_passed(p_student, p_course, p_session)
       AND (EXISTS (SELECT 1 FROM registration.summer_selection x WHERE x.student_id = p_student AND x.session = p_session AND x.course_code = p_course
                     AND x.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING'))
            OR EXISTS (SELECT 1 FROM registration.summer_courses(p_student, p_session) sc WHERE sc.course_code = p_course AND coalesce(sc.reason, '') <> 'PASSED'));
$$;
COMMENT ON FUNCTION registration.summer_course_outstanding(uuid, text, text) IS
  'V779 (V742, V743): true while a course is still owed for the student''s Summer — never when the Academic Office decided against it or a pass is on record before the Summer (the course or its twin), and for as long as an undecided selection of it stands, whatever its basis; else while it is in the pool of the detected failures and the authorisation. A reference holding a course no longer outstanding is not payable, and a payment confirmed anyway takes the course back rather than pay it.';

/* a selection ended by a pass: unpaid it is taken back (NOT_OUTSTANDING by the results, its unpaid charges cancelled, the student told);
   paid it is flagged for the Office and nothing is withdrawn. Answers TAKEN_BACK, FLAGGED or NONE; a second call finds the end state. */
CREATE FUNCTION registration.summer_selection_passed(p_student uuid, p_session text, p_course text, p_notify boolean, p_charge_cancelled boolean DEFAULT false)
RETURNS text LANGUAGE plpgsql SET jit = off AS $$
DECLARE s registration.summer_selection; v_ps text; v_pn int; v_reason text; v_batch text; v_cancelled int := 0; v_n int; v_course_title text; v_when text;
BEGIN
    SELECT * INTO s FROM registration.summer_selection x
     WHERE x.student_id = p_student AND x.session = p_session AND x.course_code = p_course AND x.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING') FOR UPDATE;
    IF NOT FOUND OR NOT registration.summer_passed(p_student, p_course, p_session) THEN RETURN 'NONE'; END IF;
    SELECT r.session, r.semester INTO v_ps, v_pn FROM assessment.student_results(p_student) r
     WHERE r.published AND r.outcome = 'GRADED' AND r.points > 0 AND (r.session < p_session OR (r.session = p_session AND r.semester < 3))
       AND (r.course_code = p_course
            OR r.course_code IN (SELECT CASE WHEN t.bsu_code = p_course THEN t.moau_code ELSE t.bsu_code END
                                   FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND p_course IN (t.bsu_code, t.moau_code)))
     ORDER BY r.session DESC, r.semester DESC LIMIT 1;
    v_when := v_ps || ' ' || CASE v_pn WHEN 1 THEN 'first' WHEN 2 THEN 'second' ELSE 'Summer' END || ' semester';
    v_reason := 'A pass is on record: ' || v_when;
    v_batch := registration.summer_current_batch();
    -- a paid course: flagged for the Office, nothing withdrawn, no money moved
    IF EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.course_code = p_course
                  AND c.kind = 'COURSE' AND c.state = 'PAID') THEN
        RETURN CASE WHEN registration.summer_selection_flag(s.id, 'PASSED_ON_RECORD', v_batch, 'RESULT_PASSED', v_reason, 'SYSTEM') THEN 'FLAGGED' ELSE 'NONE' END;
    END IF;
    UPDATE registration.summer_charge c SET state = 'CANCELLED', cancelled_at = now()
     WHERE c.student_id = p_student AND c.session = p_session AND c.course_code = p_course AND c.kind = 'COURSE' AND c.state = 'DUE';
    GET DIAGNOSTICS v_cancelled = ROW_COUNT;
    PERFORM registration.summer_selection_move(s.id, 'NOT_OUTSTANDING', 'RESULTS', 'NOT_OUTSTANDING', v_reason, NULL, v_batch, 'RESULT_PASSED',
                                               CASE WHEN v_cancelled > 0 OR p_charge_cancelled THEN 'CHARGE_CANCELLED' ELSE 'NONE' END, NULL, NULL);
    IF v_cancelled > 0 THEN
        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now()
         WHERE student_id = p_student AND session = p_session AND kind = 'PROGRAMME' AND state = 'DUE'
           AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state IN ('DUE', 'PAID'));
        PERFORM registration.summer_close_stale_references(p_student, p_session);
        IF p_notify THEN
            SELECT k.title INTO v_course_title FROM catalogue.course k WHERE k.code = p_course;
            PERFORM platform.tell_student(p_student, 'SUMMER_COURSE_REVIEWED', NULL,
                jsonb_build_object('SESSION', p_session, 'LINES', p_course || ': taken off because a pass is on record (' || v_when || ')', 'MONEY', ''),
                'SUMMER_COURSE_REVIEWED:' || p_student || ':RECONCILE:' || s.id || ':NOT_OUTSTANDING');
        END IF;
    END IF;
    RETURN 'TAKEN_BACK';
END $$;
COMMENT ON FUNCTION registration.summer_selection_passed(uuid, text, text, boolean, boolean) IS
  'V779: a selection ended by a published pass before the Summer. Unpaid: moved to NOT_OUTSTANDING by the results, its unpaid charges cancelled and the student told (p_notify); paid: flagged PASSED_ON_RECORD for the Office, the entry kept and no money moved. TAKEN_BACK, FLAGGED or NONE; a second call finds the end state and writes nothing.';

-- ── 3.7 · the student selects ────────────────────────────────────────────────────────────────────────────────────────────────────
DROP FUNCTION registration.summer_select(uuid, text, text[]);
/* the student selects courses (adds to what is selected or paid): each must be in the pool the structure, the results and the Office make and
   selectable now; one selection a course, for ever; the programme fee is charged once a Summer (or the money a decision credited of it
   reinstated as a new paid programme charge on its payment, while that credit stands unsettled); a course no result confirms waits for the Academic Office */
CREATE FUNCTION registration.summer_select(p_student uuid, p_session text, p_courses text[], p_origin jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET jit = off AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; e record; fee record; per registration.summer_period;
        v_codes text[]; c text; v_pool jsonb; v_row jsonb; v_live int; v_new int; n int := 0; v_origin jsonb := '{}'::jsonb; o jsonb;
        v_os text; v_on int; v_osrc text; v_sel uuid; v_state text; v_via text; v_src text; v_ev text; v_basis text; v_units int;
        a registration.summer_authorisation; sel registration.summer_selection;
        v_pc uuid; v_cr uuid; v_ref uuid; v_paid_at timestamptz;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a Summer selection is made by a person' USING ERRCODE = '23514'; END IF;
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT registration.summer_open(p_session) THEN
        RAISE EXCEPTION 'SUMMER_CLOSED: the Summer Semester of % is not open for registration', p_session USING ERRCODE = '23514',
            HINT = 'The Academic Office opens the Summer Semester and dates its registration window.';
    END IF;
    SELECT * INTO e FROM registration.summer_eligibility_of(p_session, ARRAY[p_student]);
    IF NOT coalesce(e.eligible, false) THEN
        RAISE EXCEPTION 'SUMMER_NOT_ELIGIBLE: % ', CASE e.reason
            WHEN 'NOT_FINAL_OR_SPILLOVER' THEN 'the Summer Semester is for final-year and spillover students'
            WHEN 'GRADUATED' THEN 'your award is approved'
            ELSE 'you are not eligible for the Summer Semester (' || coalesce(e.reason, '?') || ')' END USING ERRCODE = '23514',
            HINT = 'The Academic Office may authorise a student for an approved academic reason.';
    END IF;
    SELECT * INTO fee FROM finance.summer_fee_for(p_student, p_session);
    IF fee.fee_id IS NULL THEN
        RAISE EXCEPTION 'SUMMER_FEE_NOT_PUBLISHED: the Bursary has not published the Summer Semester fees of %', p_session USING ERRCODE = '23514';
    END IF;
    IF p_courses IS NULL OR cardinality(p_courses) = 0 THEN
        RAISE EXCEPTION 'SUMMER_NO_COURSE: choose at least one course' USING ERRCODE = '23514';
    END IF;
    -- the codes as the catalogue writes them, once each, in the order given
    SELECT array_agg(q.code ORDER BY q.first_at) INTO v_codes
      FROM (SELECT z.code, min(z.ord) AS first_at
              FROM (SELECT upper(btrim(regexp_replace(x, '\s+', ' ', 'g'))) AS code, u.ord FROM unnest(p_courses) WITH ORDINALITY u(x, ord)) z
             WHERE z.code <> '' GROUP BY z.code) q;
    IF v_codes IS NULL THEN RAISE EXCEPTION 'SUMMER_NO_COURSE: choose at least one course' USING ERRCODE = '23514'; END IF;
    IF cardinality(v_codes) > 30 THEN
        RAISE EXCEPTION 'SUMMER_TOO_MANY: select at most 30 courses at a time; select the rest afterwards' USING ERRCODE = '23514';
    END IF;
    -- the Academic Office's optional ceiling on the courses a student holds in the Summer (cumulative)
    SELECT * INTO per FROM registration.summer_period WHERE session = p_session;
    IF per.max_courses IS NOT NULL THEN
        SELECT count(*) INTO v_live FROM registration.summer_charge ch WHERE ch.student_id = p_student AND ch.session = p_session AND ch.kind = 'COURSE' AND ch.state <> 'CANCELLED';
        SELECT count(*) INTO v_new FROM unnest(v_codes) u(code)
         WHERE NOT EXISTS (SELECT 1 FROM registration.summer_charge ch WHERE ch.student_id = p_student AND ch.session = p_session AND ch.kind = 'COURSE'
                              AND ch.course_code = u.code AND ch.state <> 'CANCELLED');
        IF v_live + v_new > per.max_courses THEN
            RAISE EXCEPTION 'SUMMER_CEILING: the Summer allows at most % courses; you hold % and chose % more', per.max_courses, v_live, v_new USING ERRCODE = '23514';
        END IF;
    END IF;
    -- where the student says they owe each course: a session that exists and a semester, the first or the second
    IF p_origin IS NOT NULL THEN
        IF jsonb_typeof(p_origin) <> 'array' THEN RAISE EXCEPTION 'SUMMER_ORIGIN_INVALID: where you owe a course is a list of course, session and semester' USING ERRCODE = '23514'; END IF;
        FOR o IN SELECT * FROM jsonb_array_elements(p_origin) LOOP
            IF jsonb_typeof(o) <> 'object' OR nullif(btrim(o ->> 'course'), '') IS NULL OR nullif(btrim(o ->> 'session'), '') IS NULL
               OR coalesce(o ->> 'semester', '') NOT IN ('1', '2')
               OR NOT EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = btrim(o ->> 'session')) THEN
                RAISE EXCEPTION 'SUMMER_ORIGIN_INVALID: say a session on the calendar and the first or the second semester for %', coalesce(o ->> 'course', '?') USING ERRCODE = '23514';
            END IF;
            v_origin := v_origin || jsonb_build_object(upper(btrim(regexp_replace(o ->> 'course', '\s+', ' ', 'g'))), o);
        END LOOP;
    END IF;
    -- the pool, read once
    SELECT coalesce(jsonb_object_agg(x.course_code, to_jsonb(x)), '{}'::jsonb) INTO v_pool
      FROM registration.summer_selectable(p_student, p_session) x WHERE x.course_code = ANY (v_codes);
    FOREACH c IN ARRAY v_codes LOOP
        v_row := v_pool -> c;
        IF v_row IS NULL THEN
            RAISE EXCEPTION 'SUMMER_COURSE_NOT_AVAILABLE: % is not a course you may register in the Summer Semester (it is not in your programme''s structure, nor among your outstanding or authorised courses)', c
                USING ERRCODE = '23514';
        END IF;
        IF NOT (v_row ->> 'selectable')::boolean THEN
            RAISE EXCEPTION 'SUMMER_COURSE_REFUSED: % cannot be registered (%)', c, lower(replace(v_row ->> 'reason', '_', ' ')) USING ERRCODE = '23514';
        END IF;
    END LOOP;
    SELECT * INTO a FROM registration.summer_authorisation WHERE session = p_session AND student_id = p_student AND revoked_at IS NULL;
    FOREACH c IN ARRAY v_codes LOOP
        v_row := v_pool -> c;
        v_src := v_row ->> 'source'; v_ev := v_row ->> 'evidence'; v_units := (v_row ->> 'units')::int;
        v_os := NULL; v_on := NULL; v_osrc := NULL;
        IF (v_row ->> 'original_source') = 'RESULTS' THEN
            v_os := v_row ->> 'original_session'; v_on := (v_row ->> 'original_semester')::int; v_osrc := 'RESULTS';
        ELSIF v_origin ? c THEN
            v_os := btrim(v_origin -> c ->> 'session'); v_on := (v_origin -> c ->> 'semester')::int; v_osrc := 'STUDENT';
        END IF;
        SELECT * INTO sel FROM registration.summer_selection WHERE student_id = p_student AND session = p_session AND course_code = c FOR UPDATE;
        IF NOT FOUND THEN
            v_basis := CASE v_src WHEN 'CARRY_OVER' THEN 'CARRY_OVER' WHEN 'AUTHORISED' THEN 'AUTHORISED' ELSE 'STUDENT_SELECTED' END;
            -- a course the results confirm, or the Office named, is confirmed at once; every other waits for the Office
            IF v_ev = 'RESULT_FAILED' OR v_src = 'CARRY_OVER' THEN v_state := 'CONFIRMED_OUTSTANDING'; v_via := 'RESULTS';
            ELSIF v_src = 'AUTHORISED' THEN v_state := 'CONFIRMED_OUTSTANDING'; v_via := 'AUTHORISATION';
            ELSE v_state := 'PENDING_VERIFICATION'; v_via := NULL; END IF;
            INSERT INTO registration.summer_selection (student_id, session, course_code, basis, state, verified_via, units, original_session, original_semester,
                                                       original_source, decided_by, decided_office, decided_at, created_by)
            VALUES (p_student, p_session, c, v_basis, v_state, v_via, v_units, v_os, v_on, v_osrc,
                    CASE v_via WHEN 'AUTHORISATION' THEN a.granted_by END, CASE v_via WHEN 'AUTHORISATION' THEN a.granted_office WHEN 'RESULTS' THEN 'system' END,
                    CASE WHEN v_via IS NOT NULL THEN CASE WHEN v_via = 'AUTHORISATION' THEN a.granted_at ELSE now() END END, who)
            RETURNING * INTO sel;
            IF v_via = 'RESULTS' THEN
                PERFORM registration.summer_review_row(sel.id, registration.summer_current_batch(), 'CONFIRMED', 'PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING', 'RESULTS',
                                                       v_ev, 'Confirmed by the results: the course is owed', NULL, 'NONE', NULL, NULL);
            ELSIF v_via = 'AUTHORISATION' THEN
                INSERT INTO registration.summer_selection_review (selection_id, batch_ref, action, from_state, to_state, via, evidence, reason, note, actor_id, actor_office)
                VALUES (sel.id, registration.summer_current_batch(), 'CONFIRMED', 'PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING', 'AUTHORISATION', v_ev,
                        'Named by the Academic Office: ' || a.reason, NULL, a.granted_by, a.granted_office);
            END IF;
        ELSE
            UPDATE registration.summer_selection SET units = v_units,
                   original_session = coalesce(v_os, original_session),
                   original_semester = CASE WHEN v_os IS NOT NULL THEN v_on ELSE original_semester END,
                   original_source = CASE WHEN v_os IS NOT NULL THEN v_osrc ELSE original_source END,
                   updated_at = now()
             WHERE id = sel.id RETURNING * INTO sel;
        END IF;
        INSERT INTO registration.summer_selection_evidence (selection_id, evidence) VALUES (sel.id, v_ev)
        ON CONFLICT (selection_id) DO UPDATE SET evidence = EXCLUDED.evidence, evidence_at = clock_timestamp();
        INSERT INTO registration.summer_charge (student_id, session, kind, course_code, original_session, original_semester, basis, amount, fee_id, created_by)
        VALUES (p_student, p_session, 'COURSE', c, sel.original_session, sel.original_semester, sel.basis, fee.course_fee, fee.fee_id, who);
        n := n + 1;
    END LOOP;
    -- no candidate row is written here: the desk's identifiedAt (the latest evaluated_at) and the missing-history figure move only with an
    -- identification (the review's G4); a student who selects before any identification carries a category on the roster from the next one
    -- a Summer payment of the student confirmed at this moment may revive a cancelled programme fee on its own (the payment trigger, V742): the
    -- student's unconfirmed references are locked first, as a confirmation locks its own, so the two wait for each other and the one that comes
    -- second sees the programme fee the other made live (never two live, never a confirmation refused for it)
    PERFORM 1 FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%' AND r.confirmed_at IS NULL AND r.archived_at IS NULL
       FOR UPDATE;
    -- the programme fee, once a Summer: not again when a course is added after it was paid; the money a decision credited of it is reinstated
    -- while that credit stands — as a NEW paid programme charge on the credit's payment, the cancelled charge left as it is, so that charge and
    -- its credit stay one cancellation for good and a later decision that takes the new charge holds its money in a credit of its own
    IF NOT EXISTS (SELECT 1 FROM registration.summer_charge c2 WHERE c2.student_id = p_student AND c2.session = p_session AND c2.kind = 'PROGRAMME' AND c2.state <> 'CANCELLED') THEN
        SELECT ch.id, cr.id, cr.reference_id, pr.confirmed_at INTO v_pc, v_cr, v_ref, v_paid_at
          FROM registration.summer_charge ch
          JOIN registration.summer_credit cr ON cr.source_charge_id = ch.id AND cr.source = 'DECISION' AND cr.state = 'OPEN'
          JOIN finance.payment_reference pr ON pr.id = cr.reference_id AND pr.confirmed_at IS NOT NULL AND pr.archived_at IS NULL
                                           AND pr.purpose LIKE 'Summer semester fees%' AND pr.student_id = ch.student_id AND pr.session = ch.session
         WHERE ch.student_id = p_student AND ch.session = p_session AND ch.kind = 'PROGRAMME' AND ch.state = 'CANCELLED'
         ORDER BY cr.created_at DESC, cr.id LIMIT 1 FOR UPDATE OF ch, cr;
        IF v_pc IS NOT NULL THEN
            INSERT INTO registration.summer_charge (student_id, session, kind, amount, fee_id, state, paid_at, paid_reference_id, created_by)
            SELECT ch.student_id, ch.session, 'PROGRAMME', cr.amount, ch.fee_id, 'PAID', v_paid_at, v_ref, who
              FROM registration.summer_charge ch, registration.summer_credit cr WHERE ch.id = v_pc AND cr.id = v_cr;
            UPDATE registration.summer_credit SET state = 'APPLIED', settled_at = now(), settled_by = who,
                   settled_note = 'Reinstated as the programme fee: the student selected a course again in the same Summer' WHERE id = v_cr;
        ELSE
            INSERT INTO registration.summer_charge (student_id, session, kind, amount, fee_id, created_by)
            VALUES (p_student, p_session, 'PROGRAMME', fee.programme_fee, fee.fee_id, who);
        END IF;
    END IF;
    PERFORM registration.summer_close_stale_references(p_student, p_session);
    RETURN registration.summer_account(p_student, p_session) || jsonb_build_object('selected', n);
END $$;
COMMENT ON FUNCTION registration.summer_select(uuid, text, text[], jsonb) IS
  'V779: the student selects courses for the Summer: each a course of the programme''s structure, a detected failure or an authorised course, selectable now, at most 30 distinct in a call and within the period''s optional ceiling; one selection for a course for ever (a course the results confirm is confirmed, one the Office named confirmed, every other pending the Academic Office''s verification); a due COURSE charge at the published fee; the programme fee once a Summer, or, while the credit a decision left of it is unsettled, that money reinstated as a new paid programme charge on its payment (the credit APPLIED, the cancelled charge left cancelled). p_origin says where the student owes a course: [{"course","session","semester"}]. Refusals SUMMER_CLOSED, SUMMER_NOT_ELIGIBLE, SUMMER_FEE_NOT_PUBLISHED, SUMMER_NO_COURSE, SUMMER_TOO_MANY, SUMMER_CEILING, SUMMER_ORIGIN_INVALID, SUMMER_COURSE_NOT_AVAILABLE, SUMMER_COURSE_REFUSED.';

-- ── the reference for what is owed: a self-selected course survives the draw ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION registration.summer_reference(p_student uuid, p_session text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_due numeric; v_ref text; v_id uuid; v_courses int; v_prog boolean; v_taken int := 0; n int; v_codes text[]; v_code text;
BEGIN
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT registration.summer_open(p_session) THEN
        RAISE EXCEPTION 'SUMMER_CLOSED: registration for the Summer Semester of % is not open', p_session USING ERRCODE = '23514';
    END IF;
    -- V779: a course chosen and no longer owed (passed since, decided against) or no longer taught is not billed: taken back; a self-selected
    -- course the results do not contradict stays (summer_course_outstanding); one taken back for a pass reads NOT_OUTSTANDING by the results
    WITH u AS (UPDATE registration.summer_charge c SET state = 'CANCELLED', cancelled_at = now()
                WHERE c.student_id = p_student AND c.session = p_session AND c.kind = 'COURSE' AND c.state = 'DUE'
                  AND (EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = c.course_code AND k.state = 'ENDED')
                       OR NOT registration.summer_course_outstanding(p_student, p_session, c.course_code))
                RETURNING c.course_code)
    SELECT coalesce(array_agg(u.course_code), '{}'), count(*) INTO v_codes, v_taken FROM u;
    FOREACH v_code IN ARRAY v_codes LOOP
        IF registration.summer_passed(p_student, v_code, p_session) THEN
            PERFORM registration.summer_selection_passed(p_student, p_session, v_code, false, true);
        END IF;
    END LOOP;
    UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now()
     WHERE student_id = p_student AND session = p_session AND kind = 'PROGRAMME' AND state = 'DUE'
       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session
                         AND c.kind = 'COURSE' AND c.state IN ('DUE', 'PAID'));
    GET DIAGNOSTICS n = ROW_COUNT;
    v_taken := v_taken + n;
    PERFORM registration.summer_close_stale_references(p_student, p_session);
    SELECT coalesce(sum(amount), 0), count(*) FILTER (WHERE kind = 'COURSE'), bool_or(kind = 'PROGRAMME')
      INTO v_due, v_courses, v_prog FROM registration.summer_charge
     WHERE student_id = p_student AND session = p_session AND state = 'DUE';
    IF v_due <= 0 THEN
        IF v_taken > 0 THEN RETURN NULL; END IF;   -- V741: what was chosen is no longer owed; the take-back stands
        RAISE EXCEPTION 'SUMMER_NOTHING_DUE: nothing is owed for the Summer Semester of %', p_session USING ERRCODE = '23514',
            HINT = 'Select your courses first; what is paid stays registered.';
    END IF;
    SELECT r.reference INTO v_ref FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.amount = v_due
     ORDER BY r.generated_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    v_ref := finance.new_purpose_reference(p_student, p_session, v_due,
        'Summer semester fees, ' || p_session || ': ' || concat_ws(' and ',
            CASE WHEN v_prog THEN 'programme fee' END,
            CASE WHEN v_courses > 0 THEN v_courses || ' course' || CASE WHEN v_courses = 1 THEN '' ELSE 's' END END));
    SELECT id INTO v_id FROM finance.payment_reference WHERE reference = v_ref;
    INSERT INTO registration.summer_reference_charge (reference_id, charge_id)
    SELECT v_id, c.id FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state = 'DUE';
    RETURN v_ref;
END $$;

-- ── 3.9 · the registration a paid Summer makes: the entry's type is the selection's state ───────────────────────────────────────────
/* the registration a paid Summer makes: semester 3 of the session, every paid course in its Summer class (the one open, else opened), at the
   programme's own units, approved by the payment itself; a course paid later joins it. The entry is a carry-over while its selection is
   confirmed outstanding and the programme's own course (CURRENT) while it waits for the Academic Office; a course whose selection was decided
   against is never registered. A course the registration cannot take is recorded for the desk and the rest go on. Idempotent. */
CREATE OR REPLACE FUNCTION registration.summer_materialize(p_student uuid, p_session text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r registration.course_registration; c record; v_off uuid; v_new boolean := false; v_units int; v_n int; v_prog text; v_err text; v_u int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM registration.summer_charge WHERE student_id = p_student AND session = p_session AND kind = 'COURSE' AND state = 'PAID') THEN
        RETURN NULL;
    END IF;
    SELECT programme_code INTO v_prog FROM people.student WHERE id = p_student;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = 3 FOR UPDATE;
    IF NOT FOUND THEN
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status)
        SELECT gen_random_uuid(), s.id, p_session, 3, s.current_level, 'DRAFT' FROM people.student s WHERE s.id = p_student
        RETURNING * INTO r;
    END IF;
    FOR c IN SELECT ch.course_code, sl.id AS sel_id, sl.state AS sel_state FROM registration.summer_charge ch
               LEFT JOIN registration.summer_selection sl ON sl.student_id = ch.student_id AND sl.session = ch.session AND sl.course_code = ch.course_code
              WHERE ch.student_id = p_student AND ch.session = p_session AND ch.kind = 'COURSE' AND ch.state = 'PAID'
                AND coalesce(sl.state, '') NOT IN ('NOT_OUTSTANDING', 'REJECTED')
                AND NOT EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                                 WHERE e.registration_id = r.id AND o.course_code = ch.course_code AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
    LOOP
        BEGIN
            v_off := NULL;
            SELECT o.id INTO v_off FROM catalogue.offering o
             WHERE o.course_code = c.course_code AND o.session = p_session AND o.semester = 3 AND o.stream = 'REGULAR' LIMIT 1;
            IF v_off IS NULL THEN v_off := catalogue.open_class(c.course_code, p_session, 3, 'REGULAR'); END IF;
            -- V779: the programme's own units (a spillover student recorded at 100 would otherwise lose them), the selection keeps what it was registered at
            v_u := coalesce(catalogue.units_for(c.course_code, v_prog, NULL), (SELECT k.units FROM catalogue.course k WHERE k.code = c.course_code));
            INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
            VALUES (r.id, v_off, v_u, CASE WHEN c.sel_state = 'PENDING_VERIFICATION' THEN 'CURRENT' ELSE 'CARRYOVER' END,
                    CASE WHEN r.status IN ('APPROVED', 'LOCKED') THEN 'APPROVED' ELSE 'REGISTERED' END)
            ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = EXCLUDED.status;
            IF c.sel_id IS NOT NULL THEN
                UPDATE registration.summer_selection SET units = v_u, updated_at = now() WHERE id = c.sel_id AND units IS DISTINCT FROM v_u;
            END IF;
            v_new := true;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            INSERT INTO registration.summer_issue (student_id, session, course_code, error) VALUES (p_student, p_session, c.course_code, v_err);
        END;
    END LOOP;
    IF r.status IN ('DRAFT', 'RETURNED', 'SUBMITTED')
       AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) THEN
        UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = coalesce(submitted_at, now()), approved_at = now(),
               approved_by = NULL, approval_mode = 'AUTO'
         WHERE id = r.id;
        UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = r.id AND status = 'REGISTERED';
    END IF;
    IF v_new THEN
        SELECT count(*), coalesce(sum(e.units), 0) INTO v_n, v_units FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN');
        PERFORM platform.tell_student(p_student, 'SUMMER_REGISTERED', NULL,
            jsonb_build_object('SESSION', p_session, 'COURSES', v_n, 'UNITS', v_units),
            'SUMMER_REGISTERED:' || r.id || ':' || v_n);
    END IF;
    RETURN r.id;
END $$;

-- ── the trigger function of V674 and V711: the Summer's third-semester entries are left as the Summer typed them ─────────────────
CREATE OR REPLACE FUNCTION registration.entry_spillover_carry() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE v_student uuid; v_session text; v_semester int;
BEGIN
    -- V711: an elective the student chooses is an elective, in spillover too (a failed elective is an F, never a carry-over: V689)
    IF NEW.entry_type IN ('CARRYOVER', 'DEFERRED', 'REPEAT', 'ELECTIVE') THEN RETURN NEW; END IF;
    SELECT cr.student_id, cr.session, cr.semester INTO v_student, v_session, v_semester FROM registration.course_registration cr WHERE cr.id = NEW.registration_id;
    -- V779: the Summer's own registration (semester 3 of a Summer a student takes) is typed by the verification of its selection — CURRENT while
    -- the Academic Office has not verified it, CARRYOVER once it has — whoever the student is
    IF v_semester = 3 AND registration.is_summer_for(v_student, v_session, v_semester) THEN RETURN NEW; END IF;
    IF registration.spillover_registration(v_student, v_session) THEN
        NEW.entry_type := 'CARRYOVER';
        NEW.added_as := 'CARRY_OVER_DECLARED';
    END IF;
    RETURN NEW;
END $fn$;
COMMENT ON FUNCTION registration.entry_spillover_carry() IS
  'V674, V711, V779: a course entered on a spillover student''s registration of their current session (registration.spillover_registration) is a carry-over, declared — whoever enters it; a carry-over, deferred or repeated course is left as it is, and so is an elective (V711) and the Summer''s own third-semester registration (V779: its entries are typed by the verification of their selections).';


-- ── 3.11 · the Academic Office verifies ──────────────────────────────────────────────────────────────────────────────────────────
/* the Academic Office or the Registry decides selections, up to 200 at a time: CONFIRM (academically confirmed outstanding), NOT_OUTSTANDING
   and REJECT (with a reason the student is shown), REOPEN (back to pending). Each in its own subtransaction: a refusal does not stop the
   rest and is answered with its code. A decision against a PAID course cancels its charge, makes the money a Summer credit for the
   Bursar (never an automatic refund) and withdraws the entry by the removal route of V772; one against an unpaid course cancels the due
   charge. Locks in the payment trigger's order: the student, the selection, the student's Summer charges (the programme fee first), then
   the registration and the entry. A decision on a paid course is final here (the credit and the withdrawn entry have moved). */
CREATE FUNCTION registration.summer_verify(p_ids uuid[], p_decision text, p_reason text, p_note text) RETURNS jsonb
LANGUAGE plpgsql SET jit = off AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_batch text; v_ids uuid[]; v_id uuid; v_sid uuid; s registration.summer_selection; ch registration.summer_charge; v_ev text;
        v_target text; v_action text; v_money text; v_credit numeric; v_removal text; v_ref uuid; v_note text; v_word text; v_line text;
        n_decided int := 0; n_unchanged int := 0; n_withdrawn int := 0; v_credited numeric := 0; v_refused jsonb := '[]'::jsonb;
        v_lines jsonb := '{}'::jsonb; v_cred jsonb := '{}'::jsonb; v_sess jsonb := '{}'::jsonb; v_err text; v_code text; n int; nr record;
        v_changed boolean; v_withdrew boolean;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: a Summer course is verified by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF p_decision IS NULL OR p_decision NOT IN ('CONFIRM', 'NOT_OUTSTANDING', 'REJECT', 'REOPEN') THEN
        RAISE EXCEPTION 'SUMMER_DECISION: a Summer course is confirmed, found not outstanding, rejected or reopened' USING ERRCODE = '23514';
    END IF;
    IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
        RAISE EXCEPTION 'SUMMER_NO_SELECTION: choose the courses to decide' USING ERRCODE = '23514';
    END IF;
    IF cardinality(p_ids) > 200 THEN
        RAISE EXCEPTION 'SUMMER_BATCH_TOO_BIG: decide at most 200 courses at a time' USING ERRCODE = '23514';
    END IF;
    IF p_decision IN ('NOT_OUTSTANDING', 'REJECT') AND length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUMMER_REASON: say why, in ten characters or more: the student is shown it' USING ERRCODE = '23514';
    END IF;
    v_batch := registration.summer_batch_ref();
    PERFORM set_config('moaum.summer_batch', v_batch, true);
    SELECT array_agg(DISTINCT x) INTO v_ids FROM unnest(p_ids) x;
    FOREACH v_id IN ARRAY v_ids LOOP
        BEGIN
            v_changed := false; v_withdrew := false; v_money := 'NONE'; v_credit := 0; v_removal := NULL;
            SELECT x.student_id INTO v_sid FROM registration.summer_selection x WHERE x.id = v_id;
            IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_SELECTION_UNKNOWN: no such Summer selection' USING ERRCODE = '23514'; END IF;
            PERFORM 1 FROM people.student WHERE id = v_sid FOR UPDATE;
            SELECT * INTO s FROM registration.summer_selection WHERE id = v_id FOR UPDATE;
            -- the live evidence, stored where it is read
            SELECT e.evidence INTO v_ev FROM registration.summer_evidence(s.session, ARRAY[s.student_id]) e WHERE e.selection_id = s.id;
            IF NOT FOUND THEN v_ev := coalesce((SELECT c.evidence FROM registration.summer_selection_evidence c WHERE c.selection_id = s.id), 'NO_RESULT');
            ELSE
                INSERT INTO registration.summer_selection_evidence (selection_id, evidence) VALUES (s.id, v_ev)
                ON CONFLICT (selection_id) DO UPDATE SET evidence = EXCLUDED.evidence, evidence_at = clock_timestamp();
            END IF;
            IF s.review_flag = 'ENTRY_REMOVED' AND p_decision NOT IN ('NOT_OUTSTANDING', 'REJECT') THEN
                RAISE EXCEPTION 'SUMMER_ENTRY_REMOVED: the course was taken off the registration by the Director of ICT; decide Not outstanding or Rejected, or ask the Director to undo the removal'
                    USING ERRCODE = '23514';
            END IF;
            IF p_decision = 'CONFIRM' AND v_ev = 'RESULT_PASSED' THEN
                RAISE EXCEPTION 'SUMMER_PASSED_CONFIRM: a pass is on record for this course; decide Not outstanding or Rejected, or leave it flagged' USING ERRCODE = '23514';
            END IF;
            -- the table of what each decision does from each state
            v_target := NULL;
            IF s.state = 'PENDING_VERIFICATION' THEN
                v_target := CASE p_decision WHEN 'CONFIRM' THEN 'CONFIRMED_OUTSTANDING' WHEN 'NOT_OUTSTANDING' THEN 'NOT_OUTSTANDING' WHEN 'REJECT' THEN 'REJECTED' END;
            ELSIF s.state = 'CONFIRMED_OUTSTANDING' THEN
                v_target := CASE p_decision WHEN 'NOT_OUTSTANDING' THEN 'NOT_OUTSTANDING' WHEN 'REJECT' THEN 'REJECTED' WHEN 'REOPEN' THEN 'PENDING_VERIFICATION' END;
                IF p_decision = 'CONFIRM' AND s.review_flag = 'EVIDENCE_CHANGED' THEN
                    IF registration.summer_selection_flag(s.id, NULL, v_batch, v_ev, p_note, 'OFFICER') THEN v_changed := true; END IF;
                END IF;
            ELSE
                IF (p_decision = 'NOT_OUTSTANDING' AND s.state = 'NOT_OUTSTANDING') OR (p_decision = 'REJECT' AND s.state = 'REJECTED') THEN
                    v_target := NULL;
                ELSE
                    IF s.removal_ref IS NOT NULL OR EXISTS (SELECT 1 FROM registration.summer_credit cr JOIN registration.summer_charge c ON c.id = cr.source_charge_id
                                                             WHERE c.student_id = s.student_id AND c.session = s.session AND c.course_code = s.course_code) THEN
                        RAISE EXCEPTION 'SUMMER_DECIDED_PAID: the course was paid and has been taken off the registration; its fee is a Summer credit for the Bursar' USING ERRCODE = '23514';
                    END IF;
                    v_target := CASE p_decision WHEN 'CONFIRM' THEN 'CONFIRMED_OUTSTANDING' WHEN 'NOT_OUTSTANDING' THEN 'NOT_OUTSTANDING' WHEN 'REJECT' THEN 'REJECTED'
                                                WHEN 'REOPEN' THEN 'PENDING_VERIFICATION' END;
                END IF;
            END IF;
            IF v_target IS NULL OR v_target = s.state THEN
                IF v_changed THEN n_decided := n_decided + 1; ELSE n_unchanged := n_unchanged + 1; END IF;
                CONTINUE;
            END IF;
            v_action := CASE v_target WHEN 'CONFIRMED_OUTSTANDING' THEN 'CONFIRMED' WHEN 'NOT_OUTSTANDING' THEN 'NOT_OUTSTANDING' WHEN 'REJECTED' THEN 'REJECTED' ELSE 'REOPENED' END;
            -- the money of a decision against the course
            IF v_target IN ('NOT_OUTSTANDING', 'REJECTED') AND s.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING') THEN
                v_word := CASE v_target WHEN 'NOT_OUTSTANDING' THEN 'not outstanding' ELSE 'rejected' END;
                -- the decision moves the programme fee itself, step (3) below (trg_summer_programme_follows stands aside meanwhile)
                PERFORM set_config('moaum.summer_money', 'verify', true);
                PERFORM 1 FROM registration.summer_charge c WHERE c.student_id = s.student_id AND c.session = s.session
                  ORDER BY (c.kind = 'PROGRAMME') DESC, c.created_at FOR UPDATE;
                -- (1) the unpaid course charge goes
                UPDATE registration.summer_charge c SET state = 'CANCELLED', cancelled_at = now()
                 WHERE c.student_id = s.student_id AND c.session = s.session AND c.kind = 'COURSE' AND c.course_code = s.course_code AND c.state = 'DUE';
                GET DIAGNOSTICS n = ROW_COUNT;
                IF n > 0 THEN v_money := 'CHARGE_CANCELLED'; END IF;
                -- (2) the paid one is cancelled, its money held as a Summer credit, its entry withdrawn
                SELECT * INTO ch FROM registration.summer_charge c
                 WHERE c.student_id = s.student_id AND c.session = s.session AND c.kind = 'COURSE' AND c.course_code = s.course_code AND c.state = 'PAID';
                IF FOUND THEN
                    IF ch.paid_reference_id IS NULL THEN
                        RAISE EXCEPTION 'SUMMER_CHARGE_NO_PAYMENT: the payment of this course is not on the record; the Bursary checks it' USING ERRCODE = '23514';
                    END IF;
                    v_ref := ch.paid_reference_id;
                    -- the credit below is the one of this cancellation (uq_summer_credit_charge): money a payment held on a charge is never credited twice,
                    -- and a credit that already stands for it would make the one written here nothing — refused, the Bursary checks it
                    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.source_charge_id = ch.id AND x.reference_id = v_ref) THEN
                        RAISE EXCEPTION 'SUMMER_CREDIT_EXISTS: the money this payment holds on the course is already a Summer credit; the Bursary checks it' USING ERRCODE = '23514';
                    END IF;
                    UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now(), paid_at = NULL WHERE id = ch.id;
                    PERFORM registration.summer_credit_for_charge(ch.id, v_ref, 'Course ' || s.course_code || ' found ' || v_word || ': ' || btrim(p_reason));
                    UPDATE registration.summer_charge SET paid_reference_id = NULL WHERE id = ch.id;
                    v_credit := v_credit + ch.amount; v_money := 'CREDITED';
                    v_withdrew := EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                                            JOIN catalogue.offering o ON o.id = e.offering_id
                                           WHERE r.student_id = s.student_id AND r.session = s.session AND r.semester = 3 AND o.course_code = s.course_code
                                             AND e.status NOT IN ('DROPPED', 'WITHDRAWN'));
                    v_removal := registration.summer_withdraw_entry(s.student_id, s.session, s.course_code, 'Summer Semester: ' || s.course_code || ' ' || v_word || ': ' || btrim(p_reason));
                    v_withdrew := v_withdrew AND v_removal IS NOT NULL;
                END IF;
                -- (3) with no course left, the programme fee goes too: unpaid cancelled, paid credited
                IF NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = s.student_id AND c.session = s.session AND c.kind = 'COURSE' AND c.state IN ('DUE', 'PAID')) THEN
                    UPDATE registration.summer_charge c SET state = 'CANCELLED', cancelled_at = now()
                     WHERE c.student_id = s.student_id AND c.session = s.session AND c.kind = 'PROGRAMME' AND c.state = 'DUE';
                    SELECT * INTO ch FROM registration.summer_charge c WHERE c.student_id = s.student_id AND c.session = s.session AND c.kind = 'PROGRAMME' AND c.state = 'PAID';
                    IF FOUND THEN
                        IF ch.paid_reference_id IS NULL THEN
                            RAISE EXCEPTION 'SUMMER_CHARGE_NO_PAYMENT: the payment of the programme fee is not on the record; the Bursary checks it' USING ERRCODE = '23514';
                        END IF;
                        v_ref := ch.paid_reference_id;
                        IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.source_charge_id = ch.id AND x.reference_id = v_ref) THEN
                            RAISE EXCEPTION 'SUMMER_CREDIT_EXISTS: the money this payment holds on the programme fee is already a Summer credit; the Bursary checks it' USING ERRCODE = '23514';
                        END IF;
                        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now(), paid_at = NULL WHERE id = ch.id;
                        PERFORM registration.summer_credit_for_charge(ch.id, v_ref, 'Programme fee: no Summer course remains after ' || s.course_code || ' was found ' || v_word || ': ' || btrim(p_reason));
                        UPDATE registration.summer_charge SET paid_reference_id = NULL WHERE id = ch.id;
                        v_credit := v_credit + ch.amount; v_money := 'CREDITED';
                    END IF;
                END IF;
                PERFORM set_config('moaum.summer_money', '', true);
                PERFORM registration.summer_close_stale_references(s.student_id, s.session);
            END IF;
            PERFORM registration.summer_selection_move(s.id, v_target, 'OFFICER', v_action, btrim(p_reason), p_note, v_batch, v_ev, v_money,
                                                       CASE WHEN v_credit > 0 THEN v_credit END, v_removal);
            -- the line the student is told, one notice for each student at the end
            IF v_target IN ('CONFIRMED_OUTSTANDING', 'NOT_OUTSTANDING', 'REJECTED') THEN
                v_line := s.course_code || ': ' || CASE v_target WHEN 'CONFIRMED_OUTSTANDING' THEN 'academically confirmed outstanding'
                                                                  WHEN 'NOT_OUTSTANDING' THEN 'not outstanding, ' || btrim(p_reason)
                                                                  ELSE 'rejected, ' || btrim(p_reason) END;
                v_lines := jsonb_set(v_lines, ARRAY[s.student_id::text], coalesce(v_lines -> s.student_id::text, '[]'::jsonb) || to_jsonb(v_line), true);
                v_sess := v_sess || jsonb_build_object(s.student_id::text, s.session);
                IF v_credit > 0 THEN v_cred := v_cred || jsonb_build_object(s.student_id::text, coalesce((v_cred ->> s.student_id::text)::numeric, 0) + v_credit); END IF;
            END IF;
            n_decided := n_decided + 1; v_credited := v_credited + v_credit;
            IF v_withdrew THEN n_withdrawn := n_withdrawn + 1; END IF;
        EXCEPTION WHEN check_violation OR insufficient_privilege THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            v_code := split_part(v_err, ':', 1);
            v_refused := v_refused || jsonb_build_object('id', v_id, 'code', CASE WHEN v_code ~ '^[A-Z_]+$' THEN v_code ELSE 'REFUSED' END,
                                                          'message', CASE WHEN v_err ~ '^[A-Z_]+: ' THEN substr(v_err, length(v_code) + 3) ELSE v_err END);
        END;
    END LOOP;
    -- one notice for each student for the batch
    FOR nr IN SELECT k AS sid, v FROM jsonb_each(v_lines) AS j(k, v) LOOP
        PERFORM platform.tell_student(nr.sid::uuid, 'SUMMER_COURSE_REVIEWED', NULL,
            jsonb_build_object('SESSION', v_sess ->> nr.sid,
                               'LINES', (SELECT string_agg(l, E'\n') FROM jsonb_array_elements_text(nr.v) l),
                               'MONEY', CASE WHEN coalesce((v_cred ->> nr.sid)::numeric, 0) > 0
                                             THEN '₦' || to_char((v_cred ->> nr.sid)::numeric, 'FM999,999,990.00') || ' of what you paid is held as a Summer credit; the Bursary applies it to your next Summer or refunds it. Nothing is refunded automatically.'
                                             ELSE '' END),
            'SUMMER_COURSE_REVIEWED:' || nr.sid || ':' || v_batch);
    END LOOP;
    PERFORM set_config('moaum.summer_batch', '', true);
    RETURN jsonb_build_object('batch', v_batch, 'decided', n_decided, 'unchanged', n_unchanged, 'credited', v_credited, 'withdrawn', n_withdrawn, 'refused', v_refused);
END $$;
COMMENT ON FUNCTION registration.summer_verify(uuid[], text, text, text) IS
  'V779: the Academic Office or the Registry decides Summer selections (at most 200): CONFIRM, NOT_OUTSTANDING and REJECT (a reason of ten characters the student is shown), REOPEN. Each id in its own subtransaction; refusals are answered with their code. A decision against a paid course cancels its charge, holds its money as a Summer credit for the Bursar (one for the money each payment held on each charge, the programme fee''s too when no course remains; SUMMER_CREDIT_EXISTS if that money were already a credit) and withdraws the entry by the removal route; a decision on a paid course is final; credited counts only the credits written. Answers {batch, decided, unchanged, credited, withdrawn, refused[]}.';

-- ── the Academic Office's own words on a selection ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.summer_clarify(p_id uuid, p_note text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), ''); s registration.summer_selection;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: a Summer course is verified by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_note, ''))) NOT BETWEEN 10 AND 500 THEN
        RAISE EXCEPTION 'SUMMER_NOTE: a question to the student is 10 to 500 characters' USING ERRCODE = '23514';
    END IF;
    PERFORM 1 FROM people.student WHERE id = (SELECT x.student_id FROM registration.summer_selection x WHERE x.id = p_id) FOR UPDATE;
    SELECT * INTO s FROM registration.summer_selection WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_SELECTION_UNKNOWN: no such Summer selection' USING ERRCODE = '23514'; END IF;
    IF s.state IN ('NOT_OUTSTANDING', 'REJECTED') THEN
        RAISE EXCEPTION 'SUMMER_DECIDED: this course is already decided; a decided course is not asked about' USING ERRCODE = '23514';
    END IF;
    UPDATE registration.summer_selection SET clarification_open = true, clarification_note = btrim(p_note), clarification_by = who, clarification_at = now(), updated_at = now()
     WHERE id = p_id;
    PERFORM registration.summer_review_row(p_id, registration.summer_current_batch(), 'CLARIFICATION_ASKED', s.state, s.state, 'OFFICER', NULL, NULL, btrim(p_note), 'NONE', NULL, NULL);
    PERFORM platform.tell_student(s.student_id, 'SUMMER_COURSE_REVIEWED', NULL,
        jsonb_build_object('SESSION', s.session, 'LINES', s.course_code || ': the Academic Office asks you: ' || btrim(p_note), 'MONEY', ''),
        'SUMMER_COURSE_REVIEWED:' || s.student_id || ':ASK:' || s.id || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
END $$;
COMMENT ON FUNCTION registration.summer_clarify(uuid, text) IS
  'V779: the Academic Office asks the student about a Summer selection (10 to 500 characters); the question is flagged on the selection and the student told; any decision clears it. Refusals SUMMER_OFFICE, SUMMER_NOTE, SUMMER_DECIDED.';

/* the student's own words on a selection: at most 500 characters, a plain note that changes no state; the answer to a question is on its history */
CREATE FUNCTION registration.summer_student_note(p_student uuid, p_session text, p_course text, p_note text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s registration.summer_selection; v_note text := btrim(coalesce(p_note, ''));
BEGIN
    SELECT * INTO s FROM registration.summer_selection x WHERE x.student_id = p_student AND x.session = p_session AND x.course_code = upper(btrim(p_course)) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_NOT_YOURS: that is not your selection' USING ERRCODE = '23514'; END IF;
    IF length(v_note) > 500 THEN RAISE EXCEPTION 'SUMMER_NOTE_LONG: at most 500 characters' USING ERRCODE = '23514'; END IF;
    UPDATE registration.summer_selection SET student_note = nullif(v_note, ''), student_note_at = CASE WHEN v_note <> '' THEN now() END, updated_at = now() WHERE id = s.id;
    IF s.clarification_open AND v_note <> '' THEN
        PERFORM registration.summer_review_row(s.id, registration.summer_current_batch(), 'CLARIFICATION_ANSWERED', s.state, s.state, 'STUDENT', NULL, NULL, v_note, 'NONE', NULL, NULL);
    END IF;
END $$;
COMMENT ON FUNCTION registration.summer_student_note(uuid, text, text, text) IS
  'V779: the student writes a note (at most 500 characters) on their own Summer selection; with a question open it is also kept on the history as the answer. Changes no state. Refusals SUMMER_NOT_YOURS, SUMMER_NOTE_LONG.';

-- ── the ceiling ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.summer_set_ceiling(p_session text, p_max integer, p_reason text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: the Summer Semester is set by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF p_max IS NOT NULL AND p_max NOT BETWEEN 1 AND 60 THEN
        RAISE EXCEPTION 'SUMMER_CEILING_RANGE: a ceiling is 1 to 60 courses, or none' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUMMER_REASON: say why, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', 'V779 Summer course ceiling: ' || btrim(p_reason), true);
    UPDATE registration.summer_period SET max_courses = p_max, set_by = who, set_office = v_office, set_at = now() WHERE session = p_session;
END $$;
COMMENT ON FUNCTION registration.summer_set_ceiling(text, integer, text) IS
  'V779: the Academic Office''s optional ceiling on the courses a student may hold in the Summer (1 to 60, or none), with its reason. A ceiling below what a student holds removes nothing; it stops further selecting.';


-- ── 3.13 · reconcile: the results published after a selection was made ────────────────────────────────────────────────────────────
/* the work of a reconcile for the students given: each selection pending or confirmed (live or not) is read against the published results
   and the rules applied — a pass takes an unpaid course back (the student told) and flags a paid one for the Office, a failure confirms a
   pending selection by the results, a confirmation that rested on results which are gone goes back to pending and flagged, a live selection
   whose authorisation no longer stands goes back to the Office (pending if it was confirmed by that authorisation, and flagged), the flag of a
   removal clears when the entry is back. Each rule leaves a fixed point: a second run changes nothing and writes no row of history. A selection
   sat in its own Summer class is not read. */
CREATE FUNCTION registration.summer_reconcile_core(p_session text, p_students uuid[]) RETURNS jsonb LANGUAGE plpgsql SET jit = off AS $$
DECLARE r record; s registration.summer_selection; res text; v_batch text := registration.summer_current_batch();
        n_conf int := 0; n_back int := 0; n_flag int := 0; n_rev int := 0; n_clear int := 0; n_unch int := 0; v_touched boolean; v_revoked boolean;
BEGIN
    FOR r IN SELECT * FROM registration.summer_evidence(p_session, p_students) e ORDER BY e.student_id, e.course_code LOOP
        PERFORM 1 FROM people.student WHERE id = r.student_id FOR UPDATE;
        SELECT * INTO s FROM registration.summer_selection WHERE id = r.selection_id FOR UPDATE;
        INSERT INTO registration.summer_selection_evidence (selection_id, evidence) VALUES (r.selection_id, r.evidence)
        ON CONFLICT (selection_id) DO UPDATE SET evidence = EXCLUDED.evidence, evidence_at = clock_timestamp();
        IF s.state NOT IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING') THEN CONTINUE; END IF;
        v_touched := false;
        -- a. a pass is on record
        IF r.evidence = 'RESULT_PASSED' THEN
            res := registration.summer_selection_passed(r.student_id, p_session, r.course_code, true);
            IF res = 'TAKEN_BACK' THEN n_back := n_back + 1; ELSIF res = 'FLAGGED' THEN n_flag := n_flag + 1; ELSE n_unch := n_unch + 1; END IF;
            CONTINUE;
        END IF;
        -- the flag of a pass clears once no pass is on record
        IF s.review_flag = 'PASSED_ON_RECORD' THEN
            IF registration.summer_selection_flag(s.id, NULL, v_batch, r.evidence, 'No pass is on record now', 'SYSTEM') THEN n_clear := n_clear + 1; v_touched := true; END IF;
            SELECT * INTO s FROM registration.summer_selection WHERE id = r.selection_id;
        END IF;
        -- d. a live selection the Office's authorisation brought in whose authorisation no longer stands (revoked, or the course no longer named),
        --    the Office not having acted on it since: back to the Office — a confirmation that rested on the authorisation goes back to pending
        --    (the entry CURRENT), and it is flagged; its charge stays as it is (the Office decides). Nothing else is read for it until the Office acts.
        v_revoked := s.basis = 'AUTHORISED'
            AND EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.student_id = s.student_id AND c.session = s.session AND c.course_code = s.course_code
                           AND c.kind = 'COURSE' AND c.state <> 'CANCELLED')
            AND NOT EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = s.session AND a.student_id = s.student_id
                               AND a.revoked_at IS NULL AND s.course_code = ANY (a.courses))
            AND NOT EXISTS (SELECT 1 FROM registration.summer_selection_review v WHERE v.selection_id = s.id AND v.via = 'OFFICER'
                               AND v.at >= coalesce((SELECT coalesce(a.revoked_at, a.granted_at) FROM registration.summer_authorisation a
                                                      WHERE a.session = s.session AND a.student_id = s.student_id), '-infinity'));
        IF v_revoked AND NOT s.needs_review THEN
            IF s.state = 'CONFIRMED_OUTSTANDING' AND s.verified_via = 'AUTHORISATION' THEN
                PERFORM registration.summer_selection_move(s.id, 'PENDING_VERIFICATION', 'SYSTEM', 'REOPENED', 'The Academic Office''s authorisation of this course no longer stands',
                                                           NULL, v_batch, r.evidence, 'NONE', NULL, NULL);
                n_rev := n_rev + 1;
            ELSE
                n_flag := n_flag + 1;
            END IF;
            PERFORM registration.summer_selection_flag(s.id, 'EVIDENCE_CHANGED', v_batch, r.evidence,
                                                       'The Academic Office''s authorisation of this course was revoked or no longer names it', 'SYSTEM');
            CONTINUE;
        END IF;
        -- b. a failure on the results confirms a pending selection
        IF v_revoked THEN
            NULL;   -- flagged already: the Office decides it
        ELSIF r.evidence = 'RESULT_FAILED' AND s.state = 'PENDING_VERIFICATION' THEN
            PERFORM registration.summer_selection_move(s.id, 'CONFIRMED_OUTSTANDING', 'RESULTS', 'CONFIRMED', 'Confirmed by the results: the course is owed', NULL, v_batch, r.evidence, 'NONE', NULL, NULL);
            n_conf := n_conf + 1; v_touched := true;
        -- c. a confirmation that rested on results the portal no longer holds goes back to the Office
        ELSIF s.state = 'CONFIRMED_OUTSTANDING' AND s.verified_via = 'RESULTS' AND r.evidence = 'NO_RESULT' THEN
            PERFORM registration.summer_selection_move(s.id, 'PENDING_VERIFICATION', 'RESULTS', 'REOPENED', 'The results this rested on are no longer on the portal', NULL, v_batch, r.evidence, 'NONE', NULL, NULL);
            PERFORM registration.summer_selection_flag(s.id, 'EVIDENCE_CHANGED', v_batch, r.evidence, 'The result this confirmation rested on changed', 'SYSTEM');
            n_rev := n_rev + 1; v_touched := true;
        END IF;
        -- e. the Director of ICT put the removed course back
        SELECT * INTO s FROM registration.summer_selection WHERE id = r.selection_id;
        IF s.review_flag = 'ENTRY_REMOVED'
           AND EXISTS (SELECT 1 FROM registration.course_registration cr JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                         JOIN catalogue.offering o ON o.id = e.offering_id AND o.course_code = s.course_code
                        WHERE cr.student_id = s.student_id AND cr.session = s.session AND cr.semester = 3) THEN
            IF registration.summer_selection_flag(s.id, NULL, v_batch, r.evidence, 'The course is on the registration again', 'SYSTEM') THEN n_clear := n_clear + 1; v_touched := true; END IF;
        END IF;
        IF NOT v_touched THEN n_unch := n_unch + 1; END IF;
    END LOOP;
    RETURN jsonb_build_object('confirmed', n_conf, 'takenBack', n_back, 'flagged', n_flag, 'reverted', n_rev, 'cleared', n_clear, 'unchanged', n_unch);
END $$;

/* the student's own reconcile (the Summer page fires it once after it renders): costs one read of the results for the student, none when
   nothing of theirs is pending or confirmed */
CREATE FUNCTION registration.summer_reconcile_student(p_student uuid, p_session text) RETURNS jsonb LANGUAGE plpgsql SET jit = off AS $$
DECLARE c jsonb;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM registration.summer_selection x WHERE x.student_id = p_student AND x.session = p_session
                      AND x.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING')) THEN
        RETURN jsonb_build_object('changed', 0);
    END IF;
    PERFORM set_config('moaum.reason', 'Summer reconcile', true);
    c := registration.summer_reconcile_core(p_session, ARRAY[p_student]);
    RETURN jsonb_build_object('changed', (c ->> 'confirmed')::int + (c ->> 'takenBack')::int + (c ->> 'flagged')::int + (c ->> 'reverted')::int + (c ->> 'cleared')::int);
END $$;
COMMENT ON FUNCTION registration.summer_reconcile_student(uuid, text) IS
  'V779: a student''s Summer selections read against the published results and the rules applied (a pass takes an unpaid course back and flags a paid one; a failure confirms; results that are gone send a confirmation by results back to pending, flagged). Answers {changed}. Nothing calls it on a page read; the Summer page fires it once after it renders.';

/* the desk's tranche: the students who have a pending or confirmed selection (live or not) with no evidence read since p_since, in order,
   at most p_limit; a selection sat in its own class is left out */
CREATE FUNCTION registration.summer_reconcile(p_session text, p_since timestamptz, p_limit integer) RETURNS jsonb LANGUAGE plpgsql SET jit = off AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_students uuid[]; v_left int; c jsonb; v_batch text;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: the Summer is reconciled by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    SELECT array_agg(q.student_id) INTO v_students FROM (
        SELECT DISTINCT x.student_id FROM registration.summer_selection x
          LEFT JOIN registration.summer_selection_evidence ev ON ev.selection_id = x.id
         WHERE x.session = p_session AND x.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING')
           AND (ev.selection_id IS NULL OR ev.evidence_at < p_since)
           AND NOT registration.summer_sat(x.student_id, x.session, x.course_code)
         ORDER BY x.student_id LIMIT greatest(coalesce(p_limit, 400), 1)) q;
    v_batch := registration.summer_batch_ref();
    PERFORM set_config('moaum.summer_batch', v_batch, true);
    PERFORM set_config('moaum.reason', 'Summer reconcile', true);
    c := registration.summer_reconcile_core(p_session, coalesce(v_students, ARRAY[]::uuid[]));
    PERFORM set_config('moaum.summer_batch', '', true);
    SELECT count(DISTINCT x.student_id) INTO v_left FROM registration.summer_selection x
      LEFT JOIN registration.summer_selection_evidence ev ON ev.selection_id = x.id
     WHERE x.session = p_session AND x.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING')
       AND (ev.selection_id IS NULL OR ev.evidence_at < p_since)
       AND NOT registration.summer_sat(x.student_id, x.session, x.course_code);
    RETURN jsonb_build_object('read', coalesce(cardinality(v_students), 0), 'left', v_left) || c || jsonb_build_object('batch', v_batch);
END $$;
COMMENT ON FUNCTION registration.summer_reconcile(text, timestamptz, integer) IS
  'V779: the desk''s reconcile of the Summer''s selections against the published results, in tranches: the students with a pending or confirmed selection not read since p_since, at most p_limit (400 by default), answering {read, left, confirmed, takenBack, flagged, reverted, cleared, unchanged, batch}. Academic Office and Registry only.';

-- ── 3.14 · the examination gate ──────────────────────────────────────────────────────────────────────────────────────────────────
/* the paid Summer courses not yet verified: paid, registered (a live entry in the student's semester-3 registration), and pending, flagged
   for review, or with a published pass on record read now from the results (the cache is never trusted, so the count is right whatever the last
   reconcile did). An unpaid pending selection and a withdrawn entry are never counted. */
CREATE FUNCTION registration.summer_unverified(p_session text) RETURNS integer LANGUAGE plpgsql STABLE SET jit = off AS $$
DECLARE n int;
BEGIN
    WITH live AS (
        SELECT x.id, x.student_id, x.course_code, x.state, x.needs_review, x.verified_via
          FROM registration.summer_selection x
          JOIN registration.summer_charge ch ON ch.student_id = x.student_id AND ch.session = x.session AND ch.course_code = x.course_code
                                            AND ch.kind = 'COURSE' AND ch.state = 'PAID'
          JOIN registration.course_registration r ON r.student_id = x.student_id AND r.session = x.session AND r.semester = 3
          WHERE x.session = p_session AND x.state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING')
            AND EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                         WHERE e.registration_id = r.id AND o.course_code = x.course_code AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))),
    res AS (SELECT * FROM registration.summer_results_of(p_session, (SELECT array_agg(DISTINCT l.student_id) FROM live l WHERE l.state = 'CONFIRMED_OUTSTANDING' AND NOT l.needs_review)))
    SELECT count(*) INTO n FROM live l
     WHERE l.state = 'PENDING_VERIFICATION' OR l.needs_review
        -- a confirmation that rested on an authorisation which no longer stands, read now (before any reconcile sends it back to the Office)
        OR (l.state = 'CONFIRMED_OUTSTANDING' AND l.verified_via = 'AUTHORISATION'
            AND NOT EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p_session AND a.student_id = l.student_id
                               AND a.revoked_at IS NULL AND l.course_code = ANY (a.courses)))
        OR EXISTS (SELECT 1 FROM res WHERE res.student_id = l.student_id AND res.passes > 0
                      AND (res.course_code = l.course_code
                           OR res.course_code IN (SELECT CASE WHEN t.bsu_code = l.course_code THEN t.moau_code ELSE t.bsu_code END
                                                    FROM catalogue.course_twin t WHERE t.unlinked_at IS NULL AND l.course_code IN (t.bsu_code, t.moau_code))));
    RETURN coalesce(n, 0);
END $$;
COMMENT ON FUNCTION registration.summer_unverified(text) IS
  'V779: the paid Summer courses of a session not yet verified — registered, and pending the Academic Office, flagged for its review, confirmed by an authorisation that no longer stands, or with a published pass on record read now (never from the cache). The number the examination gate counts.';

/* the Summer's examination session (semester 3, MAIN, REGULAR: one row by its unique key) is not opened, nor its score sheets released,
   while paid courses are unverified, unless the Academic Office has recorded why; and not opened while registration is still open */
CREATE FUNCTION registration.summer_exam_gate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_act text; n int; o registration.summer_exam_override; v_new boolean; v_old boolean;
BEGIN
    v_new := NEW.semester = 3 AND NEW.kind = 'MAIN' AND NEW.stream = 'REGULAR' AND registration.is_summer(NEW.session, 3);
    -- the gate is not stepped round by the row's identity: the Summer's examination session, once opened or released, keeps its session,
    -- semester, kind and stream, and no row opened or released elsewhere becomes it
    IF (OLD.session, OLD.semester, OLD.kind, OLD.stream) IS DISTINCT FROM (NEW.session, NEW.semester, NEW.kind, NEW.stream) THEN
        v_old := OLD.semester = 3 AND OLD.kind = 'MAIN' AND OLD.stream = 'REGULAR' AND registration.is_summer(OLD.session, 3);
        IF (v_old AND (OLD.state <> 'DRAFT' OR OLD.sheets_released_at IS NOT NULL)) OR (v_new AND (NEW.state <> 'DRAFT' OR NEW.sheets_released_at IS NOT NULL)) THEN
            RAISE EXCEPTION 'SUMMER_EXAM_IDENTITY: the Summer Semester''s examination session is opened or its score sheets released; its session, semester, kind and stream are not changed, nor another opened sitting made it'
                USING ERRCODE = '23514', HINT = 'Edit only the dates of an opened Summer examination session.';
        END IF;
    END IF;
    IF NOT v_new THEN RETURN NEW; END IF;
    IF OLD.state = 'DRAFT' AND NEW.state = 'OPEN' THEN v_act := 'OPEN';
    ELSIF OLD.sheets_released_at IS NULL AND NEW.sheets_released_at IS NOT NULL THEN v_act := 'RELEASE';
    ELSE RETURN NEW; END IF;
    IF v_act = 'OPEN' AND registration.summer_open(NEW.session) THEN
        RAISE EXCEPTION 'SUMMER_REGISTRATION_OPEN: the Summer registration is still open; a payment after the examinations open would put an unverified course on the score sheets'
            USING ERRCODE = '23514', HINT = 'Close the Summer registration, or wait for its closing date, first.';
    END IF;
    n := registration.summer_unverified(NEW.session);
    IF n = 0 THEN RETURN NEW; END IF;
    SELECT * INTO o FROM registration.summer_exam_override WHERE session = NEW.session AND act = v_act;
    IF FOUND AND n <= o.unverified THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'SUMMER_VERIFICATION_PENDING: % paid Summer course(s) are not verified yet%; a student who sits a course they already passed gets a lower new attempt, and every attempt counts in the CGPA',
        n, CASE WHEN FOUND THEN ' (' || o.unverified || ' when the override was recorded)' ELSE '' END
        USING ERRCODE = '23514', HINT = 'Verify them on the Summer desk, or record why the examinations may go ahead.';
END $$;
COMMENT ON FUNCTION registration.summer_exam_gate() IS
  'V779: the gate on the Summer''s examination session (semester 3, MAIN, REGULAR of a session with a Summer): opening it, or releasing its score sheets, is refused while paid Summer courses are unverified (SUMMER_VERIFICATION_PENDING) unless an override with a reason holds for that act and the count has not grown since; opening is also refused while registration is open (SUMMER_REGISTRATION_OPEN). Binds whichever desk starts the act: the row''s session, semester, kind and stream are not changed once it is opened or released, nor another opened or released row moved into the Summer''s (SUMMER_EXAM_IDENTITY).';

/* the Academic Office records why the Summer's examinations may go ahead with courses still unverified: one reason for each act, holding while the count has not grown */
CREATE FUNCTION registration.summer_exam_override_set(p_session text, p_act text, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), ''); n int;
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: the Summer''s examinations are overridden by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF p_act IS NULL OR p_act NOT IN ('OPEN', 'RELEASE') THEN
        RAISE EXCEPTION 'SUMMER_ACT: the act is OPEN or RELEASE' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUMMER_REASON: say why, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    n := registration.summer_unverified(p_session);
    INSERT INTO registration.summer_exam_override (session, act, reason, unverified, set_by, set_office)
    VALUES (p_session, p_act, btrim(p_reason), n, who, v_office)
    ON CONFLICT (session, act) DO UPDATE SET reason = EXCLUDED.reason, unverified = EXCLUDED.unverified, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = now();
    RETURN jsonb_build_object('unverified', n);
END $$;
COMMENT ON FUNCTION registration.summer_exam_override_set(text, text, text) IS
  'V779: records why the Summer''s examinations (act OPEN) or score sheets (act RELEASE) may go ahead with paid courses unverified: the reason, the count then, who. It holds only while the count has not grown. Academic Office and Registry only.';


-- ── 3.15 · identification, roster, queue, report: set-based, no per-student call ──────────────────────────────────────────────────
/* one tranche of the identification: the regular undergraduates who may be candidates — at or past the final level (the record or the
   engine), in spillover, or authorised — and every student identified before, not read since p_since, at most p_limit, read through one
   set-based eligibility and one count of the published results; answers how many are left. The pool is built once a call. */
CREATE OR REPLACE FUNCTION registration.summer_identify(p_session text, p_since timestamptz, p_limit integer) RETURNS jsonb LANGUAGE plpgsql SET jit = off AS $$
DECLARE v_done int := 0; v_ids uuid[]; v_pool int;
        who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: the Summer''s students are identified by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.summer_period WHERE session = p_session) THEN
        RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514';
    END IF;
    CREATE TEMP TABLE IF NOT EXISTS summer_pool (student_id uuid PRIMARY KEY) ON COMMIT DROP;
    TRUNCATE summer_pool;
    INSERT INTO summer_pool (student_id)
    SELECT st.id FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
     WHERE st.status IN ('ACTIVE', 'PROBATION') AND st.entry_mode NOT IN ('CCE', 'POSTGRADUATE') AND pr.category = 'UNDER GRADUATE'
       AND (st.current_level >= coalesce(finance.final_level(st.programme_code), 400)
            OR EXISTS (SELECT 1 FROM people.academic_position ap WHERE ap.student_id = st.id
                          AND (ap.spillover_years > 0 OR ap.spillover_state LIKE 'SPILLOVER%' OR ap.computed_level >= ap.final_level))
            OR EXISTS (SELECT 1 FROM registration.summer_authorisation a WHERE a.session = p_session AND a.student_id = st.id AND a.revoked_at IS NULL))
    UNION
    SELECT c.student_id FROM registration.summer_candidate c WHERE c.session = p_session;
    -- read since p_since by an identification (results written): a row another door wrote with no results read (an authorisation) is read here
    DELETE FROM summer_pool sp WHERE EXISTS (SELECT 1 FROM registration.summer_candidate c WHERE c.session = p_session AND c.student_id = sp.student_id
                                                AND c.evaluated_at >= p_since AND c.results IS NOT NULL);
    SELECT array_agg(q.student_id), count(*) INTO v_ids, v_done FROM (SELECT sp.student_id FROM summer_pool sp ORDER BY sp.student_id LIMIT greatest(coalesce(p_limit, 500), 1)) q;
    SELECT count(*) INTO v_pool FROM summer_pool;
    IF v_ids IS NOT NULL THEN
        WITH res AS MATERIALIZED (SELECT x.student_id, sum(x.published)::int AS n FROM registration.summer_results_of('9999/9999', v_ids) x GROUP BY x.student_id)
        INSERT INTO registration.summer_candidate (session, student_id, eligible, category, outstanding, reason, results, evaluated_at)
        SELECT p_session, e.student_id, e.eligible, e.category, 0, e.reason, coalesce(r.n, 0), clock_timestamp()
          FROM registration.summer_eligibility_of(p_session, v_ids) e LEFT JOIN res r ON r.student_id = e.student_id
         WHERE e.reason IS DISTINCT FROM 'NO_STUDENT'
        ON CONFLICT (session, student_id) DO UPDATE SET eligible = EXCLUDED.eligible, category = EXCLUDED.category, outstanding = EXCLUDED.outstanding,
               reason = EXCLUDED.reason, results = EXCLUDED.results, evaluated_at = EXCLUDED.evaluated_at;
    END IF;
    RETURN jsonb_build_object('read', v_done, 'left', greatest(v_pool - v_done, 0),
                              'eligible', (SELECT count(*) FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible));
END $$;
COMMENT ON FUNCTION registration.summer_identify(text, timestamptz, integer) IS
  'V779: one tranche of the Summer''s identification (V739''s protocol: students not read since p_since, at most p_limit, how many are left): the pool is the undergraduates at or past their programme''s final level (the record or the engine), in spillover, or authorised, with every student identified before; each tranche is read through one set-based eligibility and one count of the published results (the missing-history figure; a candidate another door wrote with no results read is read in the walk whatever its time). Only an identification writes a candidate''s results. A repeat identify writes no audit row. Academic Office and Registry only (SUMMER_OFFICE, 42501). Answers {read, left, eligible}.';

/* the students who still hold a course owed on the published results (the last failure no pass follows; an elective is never owed), for
   the students given, at once */
CREATE FUNCTION registration.summer_carry_students(p_students uuid[]) RETURNS TABLE(student_id uuid) LANGUAGE sql STABLE SET jit = off AS $$
    SELECT DISTINCT x.student_id
      FROM registration.summer_results_of('9999/9999', p_students) x
     WHERE x.fails > 0 AND (x.passes = 0 OR (x.last_pass_session, x.last_pass_semester) <= (x.last_fail_session, x.last_fail_semester))
       AND NOT registration.is_elective_for(x.student_id, x.course_code);
$$;
COMMENT ON FUNCTION registration.summer_carry_students(uuid[]) IS
  'V779: of the students given, those who hold a course owed on the published results — its last failure not followed by a pass, never an elective — read as a set (summer_results_of).';

/* every student of the Summer the older desk read: the eligible (as last identified) and everyone with a charge or a registration; V779 reads
   whether a student is cleared of every owed course for the registered students as a set (not a carry-over read a student) */

CREATE OR REPLACE FUNCTION registration.summer_students(p_session text)
 RETURNS TABLE(student_id uuid, matric_no text, name text, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text, level integer, eligible boolean, category text, outstanding integer, reason text, courses_selected integer, courses_paid integer, programme_fee_due numeric, programme_fee_paid numeric, course_fees_due numeric, course_fees_paid numeric, payment_state text, registration_status text, courses_registered integer, results_published integer, results_passed integer, results_failed integer, cleared_all boolean)
 LANGUAGE sql
 STABLE
 SET jit TO 'off'
AS $function$
    WITH ppl AS (
        SELECT c.student_id FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible
        UNION SELECT ch.student_id FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED'),
    ch AS (SELECT ch.student_id,
                  count(*) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'DUE')::int AS sel,
                  count(*) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'PAID')::int AS paid_n,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'PROGRAMME' AND ch.state = 'DUE'), 0) AS pf_due,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'PROGRAMME' AND ch.state = 'PAID'), 0) AS pf_paid,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'DUE'), 0) AS cf_due,
                  coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'PAID'), 0) AS cf_paid
             FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED' GROUP BY ch.student_id),
    reg AS (SELECT r.student_id, r.status, r.id,
                   (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))::int AS n
              FROM registration.course_registration r WHERE r.session = p_session AND r.semester = 3),
    res AS (SELECT r.student_id,
                   count(*) FILTER (WHERE m.published)::int AS pub,
                   count(*) FILTER (WHERE m.published AND m.outcome = 'GRADED' AND m.points > 0)::int AS pass,
                   count(*) FILTER (WHERE m.published AND ((m.outcome = 'GRADED' AND m.points = 0) OR m.outcome = 'ABSENT'))::int AS fail
              FROM reg r CROSS JOIN LATERAL assessment.student_results(r.student_id) m
             WHERE m.session = p_session AND m.semester = 3
             GROUP BY r.student_id)
    SELECT s.id, s.matric_no, s.surname || ', ' || s.other_names, s.programme_code, pr.name, d.code, d.name, f.code, f.name, s.current_level,
           coalesce(c.eligible, false), c.category, coalesce(c.outstanding, 0), c.reason,
           coalesce(ch.sel, 0), coalesce(ch.paid_n, 0), coalesce(ch.pf_due, 0), coalesce(ch.pf_paid, 0), coalesce(ch.cf_due, 0), coalesce(ch.cf_paid, 0),
           CASE WHEN ch.student_id IS NULL THEN 'NOT_STARTED'
                WHEN ch.pf_due + ch.cf_due > 0 AND ch.pf_paid + ch.cf_paid > 0 THEN 'PART_PAID'
                WHEN ch.pf_due + ch.cf_due > 0 THEN 'UNPAID' ELSE 'PAID' END,
           reg.status, coalesce(reg.n, 0), coalesce(res.pub, 0), coalesce(res.pass, 0), coalesce(res.fail, 0),
           -- V779: cleared of every owed course, read for the registered students at once (never one carry-over read a student)
           reg.id IS NOT NULL AND coalesce(res.pub, 0) > 0
              AND NOT EXISTS (SELECT 1 FROM registration.summer_carry_students((SELECT array_agg(r2.student_id) FROM reg r2)) cs WHERE cs.student_id = s.id)
      FROM ppl
      JOIN people.student s ON s.id = ppl.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = pr.dept_code
      LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, pr.faculty_code)
      LEFT JOIN registration.summer_candidate c ON c.session = p_session AND c.student_id = s.id
      LEFT JOIN ch ON ch.student_id = s.id
      LEFT JOIN reg ON reg.student_id = s.id
      LEFT JOIN res ON res.student_id = s.id
     ORDER BY f.name, d.name, pr.name, s.current_level, s.surname;
$function$;


-- ── 3.16 · the student's summary and printable confirmation ────────────────────────────────────────────────────────────────────
/* what the student's Summer stands at, itemised: the selections by state, the charges, what is owed and paid, the registration, and the
   server's own formula (the programme fee + the course fees = the total of the non-cancelled charges) */
CREATE FUNCTION registration.summer_summary(p_student uuid, p_session text) RETURNS jsonb LANGUAGE sql STABLE SET jit = off AS $$
    WITH ch AS (SELECT c.* FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state <> 'CANCELLED'),
    ent AS (SELECT DISTINCT o.course_code FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                  AND e.status NOT IN ('DROPPED', 'WITHDRAWN') JOIN catalogue.offering o ON o.id = e.offering_id
             WHERE r.student_id = p_student AND r.session = p_session AND r.semester = 3),
    sl AS (SELECT s.*, c.state AS cstate, (c.id IS NOT NULL) AS live, (c.state = 'PAID' AND s.course_code IN (SELECT course_code FROM ent)) AS reg
             FROM registration.summer_selection s
             LEFT JOIN ch c ON c.course_code = s.course_code AND c.kind = 'COURSE'
            WHERE s.student_id = p_student AND s.session = p_session),
    fee AS (SELECT f.programme_fee, f.course_fee FROM finance.summer_fee_for(p_student, p_session) f),
    t AS (SELECT coalesce(sum(amount) FILTER (WHERE state = 'DUE'), 0) AS due, coalesce(sum(amount) FILTER (WHERE state = 'PAID'), 0) AS paid,
                 coalesce(sum(amount), 0) AS total, count(*) AS n,
                 coalesce(sum(amount) FILTER (WHERE kind = 'PROGRAMME'), 0) AS prog,
                 count(*) FILTER (WHERE kind = 'COURSE') AS courses
            FROM ch)
    SELECT jsonb_build_object(
        'selected', (SELECT count(*) FROM sl WHERE live),
        'pending', (SELECT count(*) FROM sl WHERE live AND state = 'PENDING_VERIFICATION'),
        'confirmed', (SELECT count(*) FROM sl WHERE live AND state = 'CONFIRMED_OUTSTANDING'),
        'notOutstanding', (SELECT count(*) FROM sl WHERE state = 'NOT_OUTSTANDING'),
        'rejected', (SELECT count(*) FROM sl WHERE state = 'REJECTED'),
        'clarifications', (SELECT count(*) FROM sl WHERE clarification_open),
        'registered', (SELECT count(*) FROM sl WHERE reg),
        'units', (SELECT coalesce(sum(units), 0) FROM sl WHERE live),
        'unitsRegistered', (SELECT coalesce(sum(units), 0) FROM sl WHERE reg),
        'due', (SELECT due FROM t), 'paid', (SELECT paid FROM t),
        'paymentStatus', (SELECT CASE WHEN n = 0 THEN 'NOT_STARTED' WHEN due > 0 AND paid > 0 THEN 'PART_PAID' WHEN due > 0 THEN 'UNPAID' ELSE 'PAID' END FROM t),
        'registrationStatus', CASE WHEN EXISTS (SELECT 1 FROM ent) THEN 'REGISTERED' WHEN EXISTS (SELECT 1 FROM ch) THEN 'SELECTED' ELSE 'NOT_STARTED' END,
        'reconcilable', EXISTS (SELECT 1 FROM sl WHERE state IN ('PENDING_VERIFICATION', 'CONFIRMED_OUTSTANDING')),
        'lines', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', z.kind, 'code', z.course_code, 'title', z.title, 'amount', z.amount, 'state', z.state, 'verification', z.verification)
                                            ORDER BY (z.kind = 'PROGRAMME') DESC, z.course_code)
                             FROM (SELECT c.kind, c.course_code, k.title, c.amount, c.state, s.state AS verification
                                     FROM ch c LEFT JOIN catalogue.course k ON k.code = c.course_code
                                     LEFT JOIN sl s ON s.course_code = c.course_code) z), '[]'::jsonb),
        'formula', jsonb_build_object('programme', (SELECT prog FROM t), 'perCourse', (SELECT course_fee FROM fee), 'courses', (SELECT courses FROM t), 'total', (SELECT total FROM t)));
$$;
COMMENT ON FUNCTION registration.summer_summary(uuid, text) IS
  'V779: the student''s Summer itemised — selections by verification state, registered courses, units, what is owed and paid, the payment and registration status, whether a reconcile has anything to read, the charges as lines, and the server''s own formula (the programme fee + the course fees = the total of the non-cancelled charges).';

/* the printable confirmation of the student's Summer: the selections as they stand (decided ones with their reason), the fees, the payments */
CREATE FUNCTION registration.summer_confirmation(p_student uuid, p_session text) RETURNS jsonb LANGUAGE sql STABLE SET jit = off AS $$
    WITH st AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname || ', ' || s.other_names AS name, pr.name AS programme, d.name AS department,
               f.name AS faculty, s.current_level AS level
          FROM people.student s LEFT JOIN ref.programme pr ON pr.code = s.programme_code LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, pr.faculty_code)
         WHERE s.id = p_student),
    ch AS (SELECT c.* FROM registration.summer_charge c WHERE c.student_id = p_student AND c.session = p_session AND c.state <> 'CANCELLED'),
    ent AS (SELECT DISTINCT o.course_code FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                  AND e.status NOT IN ('DROPPED', 'WITHDRAWN') JOIN catalogue.offering o ON o.id = e.offering_id
             WHERE r.student_id = p_student AND r.session = p_session AND r.semester = 3 AND r.status IN ('APPROVED', 'LOCKED')),
    rows AS (
        SELECT s.course_code, k.title, s.units, k.semester AS course_semester, s.original_session, s.original_semester,
               CASE s.basis WHEN 'CARRY_OVER' THEN 'Carry-over' WHEN 'AUTHORISED' THEN 'Authorised course' ELSE 'Student-selected course' END AS category_label,
               CASE WHEN s.state IN ('NOT_OUTSTANDING', 'REJECTED') THEN 'TAKEN_OFF' WHEN c.state = 'PAID' THEN 'REGISTERED' ELSE 'SELECTED' END AS registration_status,
               s.state AS verification, s.verified_via, s.decision_reason, s.clarification_note,
               c.state AS cstate, (c.state = 'PAID' AND s.course_code IN (SELECT course_code FROM ent)) AS reg, (c.id IS NOT NULL) AS live
          FROM registration.summer_selection s
          LEFT JOIN catalogue.course k ON k.code = s.course_code
          LEFT JOIN ch c ON c.course_code = s.course_code AND c.kind = 'COURSE'
         WHERE s.student_id = p_student AND s.session = p_session AND (c.id IS NOT NULL OR s.state IN ('NOT_OUTSTANDING', 'REJECTED'))),
    pay AS (SELECT r.reference, r.amount, r.receipt_no, r.confirmed_at FROM finance.payment_reference r
             WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'Summer semester fees%' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL)
    SELECT jsonb_build_object(
        'session', p_session, 'generatedAt', now(),
        'status', CASE WHEN EXISTS (SELECT 1 FROM rows WHERE reg) THEN 'REGISTERED' WHEN EXISTS (SELECT 1 FROM rows WHERE live) THEN 'SELECTED_UNPAID' ELSE 'NONE' END,
        'student', (SELECT jsonb_build_object('name', st.name, 'number', st.number, 'programme', st.programme, 'department', st.department, 'faculty', st.faculty, 'level', st.level,
                                              -- as identified, else read now (a selection writes no candidate row: G4)
                                              'category', coalesce((SELECT c.category FROM registration.summer_candidate c WHERE c.session = p_session AND c.student_id = p_student),
                                                                   (SELECT e.category FROM registration.summer_eligibility_of(p_session, ARRAY[p_student]) e))) FROM st),
        'period', (SELECT jsonb_build_object('registration_opens', p.registration_opens, 'registration_closes', p.registration_closes, 'exams_from', p.exams_from,
                                             'exams_to', p.exams_to, 'results_due', p.results_due, 'state', p.state)
                     FROM registration.summer_period p WHERE p.session = p_session),
        'rows', coalesce((SELECT jsonb_agg(jsonb_build_object('course_code', r.course_code, 'title', r.title, 'units', r.units, 'course_semester', r.course_semester,
                                                               'original_session', r.original_session, 'original_semester', r.original_semester,
                                                               'category_label', r.category_label, 'registration_status', r.registration_status,
                                                               'verification', r.verification, 'verified_via', r.verified_via, 'decision_reason', r.decision_reason,
                                                               'clarification_note', r.clarification_note) ORDER BY r.course_semester, r.course_code) FROM rows r), '[]'::jsonb),
        'totals', (SELECT jsonb_build_object('courses', (SELECT count(*) FROM rows WHERE live), 'units', (SELECT coalesce(sum(units), 0) FROM rows WHERE live),
                                             'unitsRegistered', (SELECT coalesce(sum(units), 0) FROM rows WHERE reg),
                                             'programmeFee', (SELECT coalesce(sum(amount), 0) FROM ch WHERE kind = 'PROGRAMME'),
                                             'courseFees', (SELECT coalesce(sum(amount), 0) FROM ch WHERE kind = 'COURSE'),
                                             'total', (SELECT coalesce(sum(amount), 0) FROM ch),
                                             'paid', (SELECT coalesce(sum(amount), 0) FROM ch WHERE state = 'PAID'),
                                             'due', (SELECT coalesce(sum(amount), 0) FROM ch WHERE state = 'DUE'))),
        'payments', coalesce((SELECT jsonb_agg(jsonb_build_object('reference', x.reference, 'amount', x.amount, 'receipt_no', x.receipt_no, 'confirmed_at', x.confirmed_at)
                                               ORDER BY x.confirmed_at) FROM pay x), '[]'::jsonb),
        'notice', 'Courses marked Pending verification are registered at your request and are not confirmed carry-overs until the Academic Office verifies them against your record. A course found not outstanding or rejected is taken off your registration and its fee is held for you as a Summer credit.');
$$;
COMMENT ON FUNCTION registration.summer_confirmation(uuid, text) IS
  'V779: the printable Summer registration confirmation of a student: the selections as they stand (a course the student chose is never captioned a carry-over; decided ones are listed with their reason), the fees and totals, the payments with receipt numbers, and the notice. Status REGISTERED, SELECTED_UNPAID or NONE.';

-- ── 3.16 · the notices, in tranches walked by a cursor ───────────────────────────────────────────────────────────────────────────
/* tells the audience of a kind in tranches of up to p_limit students in student order after p_after; the cursor, not the absence of a notice
   row, walks the audience (a student with no usable address gets no row and would be taken again by every tranche); the event key makes a
   repeat send nothing */
CREATE FUNCTION registration.summer_tell(p_session text, p_kind text, p_limit integer, p_after uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SET jit = off AS $$
DECLARE p registration.summer_period; v_limit int := least(greatest(coalesce(p_limit, 500), 1), 2000); v_ids uuid[]; v_told int := 0; v_id uuid; v_rem bigint := 0; v_last uuid;
        who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR v_office IS NULL OR v_office NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_OFFICE: the Summer''s students are told by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO p FROM registration.summer_period WHERE session = p_session;
    IF NOT FOUND THEN RAISE EXCEPTION 'NO_SUMMER: the Summer Semester of % is not set', p_session USING ERRCODE = '23514'; END IF;
    IF p_kind = 'OPEN' THEN
        SELECT array_agg(q.student_id) INTO v_ids FROM (SELECT c.student_id FROM registration.summer_candidate c
              WHERE c.session = p_session AND c.eligible AND (p_after IS NULL OR c.student_id > p_after) ORDER BY c.student_id LIMIT v_limit) q;
    ELSIF p_kind = 'CLOSING' THEN
        SELECT array_agg(q.student_id) INTO v_ids FROM (SELECT c.student_id FROM registration.summer_candidate c
              WHERE c.session = p_session AND c.eligible AND (p_after IS NULL OR c.student_id > p_after)
                AND NOT EXISTS (SELECT 1 FROM registration.summer_charge ch WHERE ch.student_id = c.student_id AND ch.session = p_session AND ch.state = 'PAID')
              ORDER BY c.student_id LIMIT v_limit) q;
    ELSIF p_kind = 'TIMETABLE' THEN
        SELECT array_agg(q.student_id) INTO v_ids FROM (SELECT r.student_id FROM registration.course_registration r
              WHERE r.session = p_session AND r.semester = 3 AND r.status IN ('APPROVED', 'LOCKED') AND p.exams_from IS NOT NULL
                AND (p_after IS NULL OR r.student_id > p_after) AND registration.is_summer_for(r.student_id, r.session, r.semester)
              ORDER BY r.student_id LIMIT v_limit) q;
    ELSE
        RAISE EXCEPTION 'SUMMER_KIND: the notice is OPEN, CLOSING or TIMETABLE' USING ERRCODE = '23514';
    END IF;
    IF v_ids IS NOT NULL THEN
        FOREACH v_id IN ARRAY v_ids LOOP
            IF platform.tell_student(v_id,
                   CASE p_kind WHEN 'OPEN' THEN 'SUMMER_OPEN' WHEN 'CLOSING' THEN 'SUMMER_CLOSING' ELSE 'SUMMER_TIMETABLE' END, NULL,
                   CASE p_kind
                       WHEN 'OPEN' THEN jsonb_build_object('SESSION', p_session, 'OPENS', to_char(p.registration_opens, 'DD Mon YYYY'), 'CLOSES', to_char(p.registration_closes, 'DD Mon YYYY'))
                       WHEN 'CLOSING' THEN jsonb_build_object('SESSION', p_session, 'CLOSES', to_char(p.registration_closes, 'DD Mon YYYY'))
                       ELSE jsonb_build_object('SESSION', p_session, 'EXAMS_FROM', to_char(p.exams_from, 'DD Mon YYYY'), 'EXAMS_TO', to_char(p.exams_to, 'DD Mon YYYY')) END,
                   CASE p_kind
                       WHEN 'OPEN' THEN 'SUMMER_OPEN:' || p_session || ':' || p.registration_opens || ':' || p.registration_closes
                       WHEN 'CLOSING' THEN 'SUMMER_CLOSING:' || p_session || ':' || p.registration_closes
                       ELSE 'SUMMER_TIMETABLE:' || p_session || ':' || p.exams_from || ':' || p.exams_to END) > 0 THEN
                v_told := v_told + 1;
            END IF;
            v_last := v_id;
        END LOOP;
        -- the audience left after the last one taken
        IF p_kind = 'OPEN' THEN
            SELECT count(*) INTO v_rem FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible AND c.student_id > v_last;
        ELSIF p_kind = 'CLOSING' THEN
            SELECT count(*) INTO v_rem FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible AND c.student_id > v_last
               AND NOT EXISTS (SELECT 1 FROM registration.summer_charge ch WHERE ch.student_id = c.student_id AND ch.session = p_session AND ch.state = 'PAID');
        ELSE
            SELECT count(*) INTO v_rem FROM registration.course_registration r WHERE r.session = p_session AND r.semester = 3 AND r.status IN ('APPROVED', 'LOCKED')
               AND p.exams_from IS NOT NULL AND r.student_id > v_last AND registration.is_summer_for(r.student_id, r.session, r.semester);
        END IF;
    END IF;
    RETURN jsonb_build_object('told', v_told, 'visited', coalesce(cardinality(v_ids), 0), 'next', CASE WHEN v_rem > 0 THEN v_last END, 'remaining', v_rem);
END $$;
COMMENT ON FUNCTION registration.summer_tell(text, text, integer, uuid) IS
  'V779: tells the students of a Summer in tranches walked by a cursor: OPEN (the eligible), CLOSING (the eligible who have paid nothing), TIMETABLE (the registered). Answers {told, visited, next, remaining}; repeat with after = next until next is null. The event key makes a repeat send nothing. A broadcast of about 19,000 goes at the template''s priority LOW. Academic Office and Registry only (SUMMER_OFFICE, 42501).';


-- ── the desk: roster, queue and report, set-based and paged, the scope passed in by the server ───────────────────────────────────────
/* the students of the Summer a desk reads, a page at a time: p_scope SELECTED (default: a selection or a charge), ELIGIBLE (identified eligible) or
   ALL; the filters faculty, department, programme, the Summer level, category (SPILLOVER includes the old BEYOND_DURATION), payment state,
   registration status and a search over matric number, name and programme. The results of the Summer's own class are read only for the page. */
CREATE FUNCTION registration.summer_roster(p_session text, p_faculty text, p_dept text, p_programme text, p_level integer, p_category text, p_pay text,
                                           p_reg text, p_scope text, p_q text, p_limit integer, p_offset integer)
RETURNS TABLE(total bigint, student_id uuid, matric_no text, name text, programme_code text, programme text, dept_code text, department text,
              faculty_code text, faculty text, level integer, summer_level integer, eligible boolean, category text, reason text, results integer,
              selected integer, pending integer, confirmed integer, not_outstanding integer, rejected integer, flagged integer, clarifications integer,
              courses_paid integer, units integer, programme_fee_due numeric, programme_fee_paid numeric, course_fees_due numeric, course_fees_paid numeric,
              payment_state text, registration_status text, courses_registered integer, results_published integer, results_passed integer, results_failed integer)
LANGUAGE sql STABLE SET jit = off SET plan_cache_mode = force_custom_plan AS $$
    WITH ppl AS (
        SELECT c.student_id FROM registration.summer_candidate c WHERE c.session = p_session AND (coalesce(p_scope, 'SELECTED') = 'ALL' OR (p_scope = 'ELIGIBLE' AND c.eligible))
        UNION SELECT ch.student_id FROM registration.summer_charge ch WHERE ch.session = p_session AND coalesce(p_scope, 'SELECTED') IN ('SELECTED', 'ALL')
        UNION SELECT sl.student_id FROM registration.summer_selection sl WHERE sl.session = p_session AND coalesce(p_scope, 'SELECTED') IN ('SELECTED', 'ALL')),
    chg AS (SELECT ch.student_id,
                   (count(*) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'PAID'))::int AS paid_n,
                   coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'PROGRAMME' AND ch.state = 'DUE'), 0) AS pf_due,
                   coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'PROGRAMME' AND ch.state = 'PAID'), 0) AS pf_paid,
                   coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'DUE'), 0) AS cf_due,
                   coalesce(sum(ch.amount) FILTER (WHERE ch.kind = 'COURSE' AND ch.state = 'PAID'), 0) AS cf_paid
              FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED' AND ch.student_id IN (SELECT student_id FROM ppl) GROUP BY ch.student_id),
    sel AS (SELECT x.student_id,
                   (count(*) FILTER (WHERE c.id IS NOT NULL))::int AS selected,
                   (count(*) FILTER (WHERE c.id IS NOT NULL AND x.state = 'PENDING_VERIFICATION'))::int AS pending,
                   (count(*) FILTER (WHERE c.id IS NOT NULL AND x.state = 'CONFIRMED_OUTSTANDING'))::int AS confirmed,
                   (count(*) FILTER (WHERE x.state = 'NOT_OUTSTANDING'))::int AS not_outstanding,
                   (count(*) FILTER (WHERE x.state = 'REJECTED'))::int AS rejected,
                   (count(*) FILTER (WHERE x.needs_review))::int AS flagged,
                   (count(*) FILTER (WHERE x.clarification_open))::int AS clarifications,
                   coalesce(sum(x.units) FILTER (WHERE c.id IS NOT NULL), 0)::int AS units
              FROM registration.summer_selection x
              LEFT JOIN registration.summer_charge c ON c.student_id = x.student_id AND c.session = x.session AND c.course_code = x.course_code AND c.kind = 'COURSE' AND c.state <> 'CANCELLED'
             WHERE x.session = p_session AND x.student_id IN (SELECT student_id FROM ppl) GROUP BY x.student_id),
    reg AS (SELECT r.student_id, r.status, r.id,
                   (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))::int AS n
              FROM registration.course_registration r WHERE r.session = p_session AND r.semester = 3 AND r.student_id IN (SELECT student_id FROM ppl)),
    base AS (
        SELECT s.id, s.matric_no, s.surname || ', ' || s.other_names AS name, s.programme_code, pr.name AS programme, d.code AS dept_code, d.name AS department,
               f.code AS faculty_code, f.name AS faculty, s.current_level AS level, greatest(s.current_level, coalesce(ap.computed_level, 0)) AS slevel,
               coalesce(c.eligible, false) AS eligible, c.category, c.reason, c.results,
               coalesce(se.selected, 0) AS selected, coalesce(se.pending, 0) AS pending, coalesce(se.confirmed, 0) AS confirmed,
               coalesce(se.not_outstanding, 0) AS not_outstanding, coalesce(se.rejected, 0) AS rejected, coalesce(se.flagged, 0) AS flagged,
               coalesce(se.clarifications, 0) AS clarifications, coalesce(ch.paid_n, 0) AS paid_n, coalesce(se.units, 0) AS units,
               coalesce(ch.pf_due, 0) AS pf_due, coalesce(ch.pf_paid, 0) AS pf_paid, coalesce(ch.cf_due, 0) AS cf_due, coalesce(ch.cf_paid, 0) AS cf_paid,
               CASE WHEN ch.student_id IS NULL THEN 'NOT_STARTED'
                    WHEN ch.pf_due + ch.cf_due > 0 AND ch.pf_paid + ch.cf_paid > 0 THEN 'PART_PAID'
                    WHEN ch.pf_due + ch.cf_due > 0 THEN 'UNPAID' ELSE 'PAID' END AS pay_state,
               reg.status AS reg_status, coalesce(reg.n, 0) AS reg_n, reg.id AS reg_id
          FROM ppl
          JOIN people.student s ON s.id = ppl.student_id
          LEFT JOIN people.academic_position ap ON ap.student_id = s.id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, pr.faculty_code)
          LEFT JOIN registration.summer_candidate c ON c.session = p_session AND c.student_id = s.id
          LEFT JOIN chg ch ON ch.student_id = s.id
          LEFT JOIN sel se ON se.student_id = s.id
          LEFT JOIN reg ON reg.student_id = s.id),
    flt AS (
        SELECT b.*, count(*) OVER () AS total FROM base b
         WHERE (p_faculty IS NULL OR b.faculty_code = p_faculty) AND (p_dept IS NULL OR b.dept_code = p_dept) AND (p_programme IS NULL OR b.programme_code = p_programme)
           AND (p_level IS NULL OR b.slevel = p_level)
           AND (p_category IS NULL OR b.category = p_category OR (p_category = 'SPILLOVER' AND b.category = 'BEYOND_DURATION'))
           AND (p_pay IS NULL OR b.pay_state = p_pay)
           AND (p_reg IS NULL OR (p_reg = 'REGISTERED' AND b.reg_n > 0) OR (p_reg = 'NOT_REGISTERED' AND b.reg_n = 0))
           AND (nullif(btrim(p_q), '') IS NULL OR b.matric_no ILIKE '%' || btrim(p_q) || '%' OR b.name ILIKE '%' || btrim(p_q) || '%' OR b.programme ILIKE '%' || btrim(p_q) || '%')),
    pg AS (SELECT * FROM flt ORDER BY faculty, department, programme, level, name LIMIT greatest(coalesce(p_limit, 50), 1) OFFSET greatest(coalesce(p_offset, 0), 0)),
    res AS (SELECT p.id AS sid,
                   (count(*) FILTER (WHERE m.published))::int AS pub,
                   (count(*) FILTER (WHERE m.published AND m.outcome = 'GRADED' AND m.points > 0))::int AS pass,
                   (count(*) FILTER (WHERE m.published AND ((m.outcome = 'GRADED' AND m.points = 0) OR m.outcome = 'ABSENT')))::int AS fail
              FROM pg p CROSS JOIN LATERAL assessment.student_results(p.id) m
             WHERE p.reg_id IS NOT NULL AND m.session = p_session AND m.semester = 3
             GROUP BY p.id)
    SELECT p.total, p.id, p.matric_no, p.name, p.programme_code, p.programme, p.dept_code, p.department, p.faculty_code, p.faculty, p.level, p.slevel,
           p.eligible, p.category, p.reason, p.results, p.selected, p.pending, p.confirmed, p.not_outstanding, p.rejected, p.flagged, p.clarifications,
           p.paid_n, p.units, p.pf_due, p.pf_paid, p.cf_due, p.cf_paid, p.pay_state, p.reg_status, p.reg_n,
           coalesce(r.pub, 0), coalesce(r.pass, 0), coalesce(r.fail, 0)
      FROM pg p LEFT JOIN res r ON r.sid = p.id
     ORDER BY p.faculty, p.department, p.programme, p.level, p.name;
$$;
COMMENT ON FUNCTION registration.summer_roster(text, text, text, text, integer, text, text, text, text, text, integer, integer) IS
  'V779: the students of a Summer a desk reads, a page at a time (total counts the whole filtered set): each with their category, the selections by verification state, what is owed and paid by kind, the payment state, the registration and the results of the Summer''s own class (read for the page only). Scope SELECTED, ELIGIBLE or ALL; filters faculty, department, programme, Summer level, category, payment state, registration status, search. The scope arguments are the server''s, never the client''s.';

/* the verification queue, a page at a time: the selections with a live charge or a decision, filterable on cached evidence */
CREATE FUNCTION registration.summer_queue(p_session text, p_faculty text, p_dept text, p_programme text, p_level integer, p_state text, p_evidence text,
                                          p_flag text, p_basis text, p_paid text, p_q text, p_limit integer, p_offset integer)
RETURNS TABLE(total bigint, selection_id uuid, student_id uuid, matric_no text, name text, programme text, dept_code text, faculty_code text, level integer,
              summer_level integer, category text, course_code text, title text, units integer, course_semester integer, original_session text,
              original_semester integer, original_source text, basis text, state text, verified_via text, decision_reason text, evidence text,
              evidence_at timestamptz, needs_review boolean, review_flag text, clarification_open boolean, clarification_note text, student_note text,
              charge_state text, entry_live boolean, selected_at timestamptz, decided_office text, decided_at timestamptz,
              charge_amount numeric, programme_fee_paid numeric, courses_standing integer)
LANGUAGE sql STABLE SET jit = off SET plan_cache_mode = force_custom_plan AS $$
    WITH q AS (
        SELECT x.id AS sid, x.student_id AS stid, s.matric_no, s.surname || ', ' || s.other_names AS name, pr.name AS programme, d.code AS dept_code,
               f.code AS faculty_code, s.programme_code, s.current_level AS level, greatest(s.current_level, coalesce(ap.computed_level, 0)) AS slevel,
               cd.category, x.course_code, k.title, x.units, k.semester AS course_semester, x.original_session, x.original_semester, x.original_source,
               x.basis, x.state, x.verified_via, x.decision_reason, ev.evidence, ev.evidence_at, x.needs_review, x.review_flag, x.clarification_open,
               x.clarification_note, x.student_note, c.state AS charge_state, c.amount AS charge_amount,
               x.created_at AS selected_at, x.decided_office, x.decided_at
          FROM registration.summer_selection x
          JOIN people.student s ON s.id = x.student_id
          LEFT JOIN people.academic_position ap ON ap.student_id = s.id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, pr.faculty_code)
          LEFT JOIN catalogue.course k ON k.code = x.course_code
          LEFT JOIN registration.summer_candidate cd ON cd.session = x.session AND cd.student_id = x.student_id
          LEFT JOIN registration.summer_selection_evidence ev ON ev.selection_id = x.id
          LEFT JOIN registration.summer_charge c ON c.student_id = x.student_id AND c.session = x.session AND c.course_code = x.course_code AND c.kind = 'COURSE' AND c.state <> 'CANCELLED'
         WHERE x.session = p_session AND (c.id IS NOT NULL OR x.state IN ('NOT_OUTSTANDING', 'REJECTED'))
           AND (p_state IS NULL OR p_state = 'ANY' OR x.state = p_state)
           AND (p_evidence IS NULL OR ev.evidence = p_evidence)
           AND (p_flag IS NULL OR (p_flag = 'REVIEW' AND x.needs_review) OR (p_flag = 'CLARIFICATION' AND x.clarification_open))
           AND (p_basis IS NULL OR x.basis = p_basis)
           AND (p_paid IS NULL OR (p_paid = 'PAID' AND c.state = 'PAID') OR (p_paid = 'UNPAID' AND c.state = 'DUE'))
           AND (p_faculty IS NULL OR f.code = p_faculty) AND (p_dept IS NULL OR d.code = p_dept) AND (p_programme IS NULL OR s.programme_code = p_programme)
           AND (p_level IS NULL OR greatest(s.current_level, coalesce(ap.computed_level, 0)) = p_level)
           AND (nullif(btrim(p_q), '') IS NULL OR s.matric_no ILIKE '%' || btrim(p_q) || '%' OR (s.surname || ', ' || s.other_names) ILIKE '%' || btrim(p_q) || '%'
                OR x.course_code ILIKE '%' || btrim(p_q) || '%' OR pr.name ILIKE '%' || btrim(p_q) || '%')),
    -- the page first, then what costs a probe for each row (whether the entry is live) for the rows of the page alone
    pg AS (
        SELECT count(*) OVER () AS total, q.* FROM q
         ORDER BY q.needs_review DESC, (q.state = 'PENDING_VERIFICATION') DESC, q.selected_at, q.sid
         LIMIT greatest(coalesce(p_limit, 50), 1) OFFSET greatest(coalesce(p_offset, 0), 0)),
    -- the money a decision would hold, for the students of the page in one read: the paid programme fee and how many selections hold a live
    -- course charge (a decision that takes the last of them credits the programme fee too)
    pm AS (
        SELECT c.student_id AS stid,
               sum(c.amount) FILTER (WHERE c.kind = 'PROGRAMME' AND c.state = 'PAID') AS programme_fee_paid,
               (count(*) FILTER (WHERE c.kind = 'COURSE' AND y.id IS NOT NULL))::int AS courses_standing
          FROM registration.summer_charge c
          LEFT JOIN registration.summer_selection y ON y.student_id = c.student_id AND y.session = c.session AND y.course_code = c.course_code
         WHERE c.session = p_session AND c.state IN ('DUE', 'PAID') AND c.student_id IN (SELECT pg.stid FROM pg)
         GROUP BY c.student_id)
    SELECT pg.total, pg.sid, pg.stid, pg.matric_no, pg.name, pg.programme, pg.dept_code, pg.faculty_code, pg.level, pg.slevel, pg.category, pg.course_code, pg.title,
           pg.units, pg.course_semester, pg.original_session, pg.original_semester, pg.original_source, pg.basis, pg.state, pg.verified_via, pg.decision_reason,
           pg.evidence, pg.evidence_at, pg.needs_review, pg.review_flag, pg.clarification_open, pg.clarification_note, pg.student_note, pg.charge_state,
           (pg.charge_state = 'PAID' AND EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                                                    AND e.status NOT IN ('DROPPED', 'WITHDRAWN') JOIN catalogue.offering o ON o.id = e.offering_id AND o.course_code = pg.course_code
                                                  WHERE r.student_id = pg.stid AND r.session = p_session AND r.semester = 3)) AS entry_live,
           pg.selected_at, pg.decided_office, pg.decided_at,
           pg.charge_amount, pm.programme_fee_paid, coalesce(pm.courses_standing, 0)
      FROM pg LEFT JOIN pm ON pm.stid = pg.stid
     ORDER BY pg.needs_review DESC, (pg.state = 'PENDING_VERIFICATION') DESC, pg.selected_at, pg.sid;
$$;
COMMENT ON FUNCTION registration.summer_queue(text, text, text, text, integer, text, text, text, text, text, text, integer, integer) IS
  'V779: the verification queue, a page at a time (total counts every match): the Summer selections with a live charge or a decision, each with the student, the course, the evidence cached from the results, the flag of review, the charge and whether the entry is live, and the money a decision would hold (charge_amount: the live course charge, DUE or PAID; programme_fee_paid: the student''s PAID programme fee; courses_standing: the student''s selections holding a live course charge — a decision taking the last of them credits the programme fee too); filters faculty, department, programme, Summer level, state, evidence, flag (REVIEW, CLARIFICATION), basis, payment, search. Needs-review first, pending next, oldest first.';

/* the ids of the first 5,000 selections of a queue filter, for "select all matching"; total is the full count */
CREATE FUNCTION registration.summer_queue_ids(p_session text, p_faculty text, p_dept text, p_programme text, p_level integer, p_state text, p_evidence text,
                                              p_flag text, p_basis text, p_paid text, p_q text)
RETURNS TABLE(total bigint, selection_id uuid) LANGUAGE sql STABLE SET jit = off SET plan_cache_mode = force_custom_plan AS $$
    SELECT q.total, q.selection_id FROM registration.summer_queue(p_session, p_faculty, p_dept, p_programme, p_level, p_state, p_evidence, p_flag, p_basis, p_paid, p_q, 5000, 0) q;
$$;
COMMENT ON FUNCTION registration.summer_queue_ids(text, text, text, text, integer, text, text, text, text, text, text) IS
  'V779: the ids of the first 5,000 selections the queue filter matches in the queue''s order (total is the full count): what a bulk decision acts on.';

/* the figures of the Summer by group, the scope passed in by the server: eligible, missing history, selections by state, registered, payment states, fees */
CREATE FUNCTION registration.summer_report(p_session text, p_group text, p_faculty text, p_dept text, p_programme text, p_level integer, p_category text,
                                           p_state text, p_pay text, p_reg text)
RETURNS TABLE(group_code text, group_name text, eligible bigint, eligible_final_year bigint, eligible_spillover bigint, eligible_authorised bigint,
              missing_history_students bigint, students_selected bigint, courses_selected bigint, pending bigint, confirmed bigint, not_outstanding bigint,
              rejected bigint, clarifications bigint, flagged bigint, registered_students bigint, registered_courses bigint, units_selected bigint,
              students_not_started bigint, students_unpaid bigint, students_part_paid bigint, students_paid bigint, fees_paid numeric, fees_due numeric,
              credits_open numeric, selections_no_result bigint)
LANGUAGE sql STABLE SET jit = off SET plan_cache_mode = force_custom_plan AS $$
    WITH ppl AS (
        SELECT c.student_id FROM registration.summer_candidate c WHERE c.session = p_session AND c.eligible
        UNION SELECT ch.student_id FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED'
        UNION SELECT sl.student_id FROM registration.summer_selection sl WHERE sl.session = p_session),
    ent AS (SELECT DISTINCT r.student_id, o.course_code FROM registration.course_registration r
              JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') JOIN catalogue.offering o ON o.id = e.offering_id
             WHERE r.session = p_session AND r.semester = 3 AND r.student_id IN (SELECT student_id FROM ppl)),
    chg AS (SELECT ch.student_id,
                   coalesce(sum(ch.amount) FILTER (WHERE ch.state = 'DUE'), 0) AS due, coalesce(sum(ch.amount) FILTER (WHERE ch.state = 'PAID'), 0) AS paid, count(*) AS n
              FROM registration.summer_charge ch WHERE ch.session = p_session AND ch.state <> 'CANCELLED' AND ch.student_id IN (SELECT student_id FROM ppl) GROUP BY ch.student_id),
    sel AS (SELECT x.student_id,
                   (count(*) FILTER (WHERE c.id IS NOT NULL))::bigint AS selected,
                   (count(*) FILTER (WHERE c.id IS NOT NULL AND x.state = 'PENDING_VERIFICATION'))::bigint AS pending,
                   (count(*) FILTER (WHERE c.id IS NOT NULL AND x.state = 'CONFIRMED_OUTSTANDING'))::bigint AS confirmed,
                   (count(*) FILTER (WHERE x.state = 'NOT_OUTSTANDING'))::bigint AS not_outstanding,
                   (count(*) FILTER (WHERE x.state = 'REJECTED'))::bigint AS rejected,
                   (count(*) FILTER (WHERE x.clarification_open))::bigint AS clarifications,
                   (count(*) FILTER (WHERE x.needs_review))::bigint AS flagged,
                   (count(*) FILTER (WHERE c.state = 'PAID' AND (x.student_id, x.course_code) IN (SELECT e.student_id, e.course_code FROM ent e)))::bigint AS reg_courses,
                   coalesce(sum(x.units) FILTER (WHERE c.id IS NOT NULL), 0)::bigint AS units,
                   (count(*) FILTER (WHERE c.id IS NOT NULL AND ev.evidence = 'NO_RESULT'))::bigint AS no_result
              FROM registration.summer_selection x
              LEFT JOIN registration.summer_charge c ON c.student_id = x.student_id AND c.session = x.session AND c.course_code = x.course_code AND c.kind = 'COURSE' AND c.state <> 'CANCELLED'
              LEFT JOIN registration.summer_selection_evidence ev ON ev.selection_id = x.id
             WHERE x.session = p_session AND (p_state IS NULL OR p_state = 'ANY' OR x.state = p_state) AND x.student_id IN (SELECT student_id FROM ppl) GROUP BY x.student_id),
    cr AS (SELECT x.student_id, sum(x.amount) AS open FROM registration.summer_credit x JOIN finance.payment_reference pr ON pr.id = x.reference_id AND pr.archived_at IS NULL
            WHERE x.session = p_session AND x.state = 'OPEN' GROUP BY x.student_id),
    b AS (
        SELECT s.id, f.code AS fcode, f.name AS fname, d.code AS dcode, d.name AS dname, s.programme_code AS pcode, pr.name AS pname,
               greatest(s.current_level, coalesce(ap.computed_level, 0)) AS slevel,
               coalesce(c.eligible, false) AS eligible, CASE WHEN c.category = 'BEYOND_DURATION' THEN 'SPILLOVER' ELSE c.category END AS category, c.results,
               coalesce(se.selected, 0) AS selected, coalesce(se.pending, 0) AS pending, coalesce(se.confirmed, 0) AS confirmed, coalesce(se.not_outstanding, 0) AS not_outstanding,
               coalesce(se.rejected, 0) AS rejected, coalesce(se.clarifications, 0) AS clarifications, coalesce(se.flagged, 0) AS flagged,
               coalesce(se.reg_courses, 0) AS reg_courses, coalesce(se.units, 0) AS units, coalesce(se.no_result, 0) AS no_result,
               coalesce(ch.paid, 0) AS paid, coalesce(ch.due, 0) AS due, coalesce(cr.open, 0) AS credit_open,
               CASE WHEN ch.student_id IS NULL THEN 'NOT_STARTED' WHEN ch.due > 0 AND ch.paid > 0 THEN 'PART_PAID' WHEN ch.due > 0 THEN 'UNPAID' ELSE 'PAID' END AS pay_state
          FROM ppl
          JOIN people.student s ON s.id = ppl.student_id
          LEFT JOIN people.academic_position ap ON ap.student_id = s.id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, pr.faculty_code)
          LEFT JOIN registration.summer_candidate c ON c.session = p_session AND c.student_id = s.id
          LEFT JOIN chg ch ON ch.student_id = s.id
          LEFT JOIN sel se ON se.student_id = s.id
          LEFT JOIN cr ON cr.student_id = s.id),
    g AS (
        SELECT b.*,
               CASE coalesce(p_group, 'ALL') WHEN 'FACULTY' THEN coalesce(b.fcode, '-') WHEN 'DEPARTMENT' THEN coalesce(b.dcode, '-') WHEN 'PROGRAMME' THEN coalesce(b.pcode, '-')
                    WHEN 'LEVEL' THEN coalesce(b.slevel::text, '-') WHEN 'CATEGORY' THEN coalesce(b.category, '-') ELSE 'ALL' END AS gcode,
               CASE coalesce(p_group, 'ALL') WHEN 'FACULTY' THEN coalesce(b.fname, 'No faculty') WHEN 'DEPARTMENT' THEN coalesce(b.dname, 'No department') WHEN 'PROGRAMME' THEN coalesce(b.pname, 'No programme')
                    WHEN 'LEVEL' THEN coalesce(b.slevel::text || ' Level', 'No level') WHEN 'CATEGORY' THEN coalesce(b.category, 'No category') ELSE 'Every student' END AS gname
          FROM b
         WHERE (p_faculty IS NULL OR b.fcode = p_faculty) AND (p_dept IS NULL OR b.dcode = p_dept) AND (p_programme IS NULL OR b.pcode = p_programme)
           AND (p_level IS NULL OR b.slevel = p_level) AND (p_category IS NULL OR b.category = CASE WHEN p_category = 'BEYOND_DURATION' THEN 'SPILLOVER' ELSE p_category END)
           AND (p_pay IS NULL OR b.pay_state = p_pay)
           AND (p_reg IS NULL OR (p_reg = 'REGISTERED' AND b.reg_courses > 0) OR (p_reg = 'NOT_REGISTERED' AND b.reg_courses = 0)))
    SELECT g.gcode, min(g.gname),
           (count(*) FILTER (WHERE g.eligible))::bigint,
           (count(*) FILTER (WHERE g.eligible AND g.category = 'FINAL_YEAR'))::bigint,
           (count(*) FILTER (WHERE g.eligible AND g.category = 'SPILLOVER'))::bigint,
           (count(*) FILTER (WHERE g.eligible AND g.category = 'AUTHORISED'))::bigint,
           (count(*) FILTER (WHERE (g.eligible OR g.selected > 0) AND g.results = 0))::bigint,
           (count(*) FILTER (WHERE g.selected > 0))::bigint, coalesce(sum(g.selected), 0)::bigint, coalesce(sum(g.pending), 0)::bigint, coalesce(sum(g.confirmed), 0)::bigint,
           coalesce(sum(g.not_outstanding), 0)::bigint, coalesce(sum(g.rejected), 0)::bigint, coalesce(sum(g.clarifications), 0)::bigint, coalesce(sum(g.flagged), 0)::bigint,
           (count(*) FILTER (WHERE g.reg_courses > 0))::bigint, coalesce(sum(g.reg_courses), 0)::bigint, coalesce(sum(g.units), 0)::bigint,
           (count(*) FILTER (WHERE g.pay_state = 'NOT_STARTED'))::bigint, (count(*) FILTER (WHERE g.pay_state = 'UNPAID'))::bigint,
           (count(*) FILTER (WHERE g.pay_state = 'PART_PAID'))::bigint, (count(*) FILTER (WHERE g.pay_state = 'PAID'))::bigint,
           coalesce(sum(g.paid), 0), coalesce(sum(g.due), 0), coalesce(sum(g.credit_open), 0), coalesce(sum(g.no_result), 0)::bigint
      FROM g GROUP BY g.gcode ORDER BY g.gcode;
$$;
COMMENT ON FUNCTION registration.summer_report(text, text, text, text, text, integer, text, text, text, text) IS
  'V779: the Summer''s figures by group (ALL, FACULTY, DEPARTMENT, PROGRAMME, LEVEL, CATEGORY) in scope: students eligible (and by category), with missing history (no published result on the portal), selecting, the courses selected by verification state, those registered, the students by payment state, fees paid and due, credits open, and selections no result bears on. Set-based; the scope arguments are the server''s. p_state limits the selection columns; p_pay and p_reg the students counted.';


-- ── 3.18 · the Summer Semester's menu entry: a student the engine places at or past the final level too ─────────────────────────────
DO $$
DECLARE d text; v_anchor text := 'ap.spillover_state LIKE ''SPILLOVER%''))'; n int;
BEGIN
    d := pg_get_functiondef('registration.summer_area(uuid)'::regprocedure);
    n := (length(d) - length(replace(d, v_anchor, ''))) / length(v_anchor);
    IF n <> 1 THEN RAISE EXCEPTION 'V779: registration.summer_area is not as V756 left it (% anchors, 1 expected)', n; END IF;
    EXECUTE replace(d, v_anchor, v_anchor || E'\n                                       OR EXISTS (SELECT 1 FROM people.academic_position ap2 WHERE ap2.student_id = st.id AND ap2.computed_level >= ap2.final_level)');
END $$;

-- ── 2.6 · the triggers ───────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TRIGGER trg_summer_exam_gate BEFORE UPDATE OF state, sheets_released_at, session, semester, kind, stream ON assessment.exam_session
    FOR EACH ROW EXECUTE FUNCTION registration.summer_exam_gate();
CREATE TRIGGER trg_summer_programme_follows AFTER UPDATE OF state ON registration.summer_charge
    FOR EACH ROW WHEN (OLD.kind = 'COURSE' AND OLD.state IN ('DUE', 'PAID') AND NEW.state = 'CANCELLED') EXECUTE FUNCTION registration.summer_programme_follows();
CREATE TRIGGER trg_summer_credit_reinstated_kept BEFORE UPDATE OF state ON registration.summer_credit
    FOR EACH ROW WHEN (OLD.state <> 'OPEN' AND NEW.state = 'OPEN' AND OLD.source = 'DECISION' AND OLD.settled_note LIKE 'Reinstated as the programme fee: %')
    EXECUTE FUNCTION registration.summer_credit_reinstated_kept();
COMMENT ON TRIGGER trg_summer_programme_follows ON registration.summer_charge IS
  'V779: the programme fee follows the student''s last Summer course, whatever takes it: DUE cancelled, PAID cancelled and held as one open Summer credit for the Bursar.';
COMMENT ON TRIGGER trg_summer_credit_reinstated_kept ON registration.summer_credit IS
  'V779: a credit that paid the programme fee the student selected back is not reopened (SUMMER_CREDIT_REINSTATED): the same money would be a PAID charge and an open credit.';
CREATE TRIGGER trg_summer_removal_noted AFTER INSERT OR UPDATE OF state ON registration.entry_removal
    FOR EACH ROW WHEN (NEW.state = 'APPLIED' AND NEW.semester = 3) EXECUTE FUNCTION registration.summer_removal_noted();
CREATE TRIGGER trg_summer_removal_held BEFORE UPDATE OF state ON registration.entry_removal
    FOR EACH ROW WHEN (NEW.state IN ('UNDONE', 'CANCELLED') AND OLD.state IN ('APPLIED', 'PENDING')) EXECUTE FUNCTION registration.summer_removal_held();
COMMENT ON TRIGGER trg_summer_exam_gate ON assessment.exam_session IS
  'V779: the Summer''s examination session is not opened, nor its score sheets released, while paid Summer courses are unverified unless the Academic Office recorded why; and not opened while its registration is open; its identity is not changed once opened or released, nor another opened row moved into it.';
COMMENT ON TRIGGER trg_summer_removal_noted ON registration.entry_removal IS
  'V779: a paid Summer course the Director of ICT removed on their own is flagged for the Academic Office (ENTRY_REMOVED), never dropped silently.';
COMMENT ON TRIGGER trg_summer_removal_held ON registration.entry_removal IS
  'V779: a removal a Summer decision made or adopted is not undone or cancelled by the Director of ICT: the entry, the charge and the credit stand as that decision left them.';

-- ── 2.8 · the backfill: every course the Summer already charged is a confirmed selection ───────────────────────────────────────────
INSERT INTO registration.summer_selection (student_id, session, course_code, basis, state, verified_via, units, original_session, original_semester, original_source, created_at, created_by)
SELECT DISTINCT ON (c.student_id, c.session, c.course_code) c.student_id, c.session, c.course_code, coalesce(c.basis, 'CARRY_OVER'), 'CONFIRMED_OUTSTANDING',
       CASE WHEN c.basis = 'AUTHORISED' THEN 'AUTHORISATION' ELSE 'RESULTS' END,
       coalesce(catalogue.units_for(c.course_code, s.programme_code, NULL), k.units), c.original_session, c.original_semester,
       CASE WHEN c.original_session IS NOT NULL THEN 'RESULTS' END, c.created_at, c.created_by
  FROM registration.summer_charge c JOIN people.student s ON s.id = c.student_id JOIN catalogue.course k ON k.code = c.course_code
 WHERE c.kind = 'COURSE' AND c.state <> 'CANCELLED'
 ORDER BY c.student_id, c.session, c.course_code, c.created_at DESC
ON CONFLICT (student_id, session, course_code) DO NOTHING;

-- ── 3.17 · the notices ────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE t platform.notice_template; v_email boolean; v_sms boolean; v_portal boolean;
    o_email text := E'Dear [FIRST_NAME],\n\nThe Summer Semester of [SESSION] is open for registration from [OPENS] to [CLOSES]. You have [OUTSTANDING] outstanding course(s) you may register in it, from the first and the second semester together.\n\nSign in, open Summer Semester, select your courses and pay the Summer fees; your registration stands once they are paid.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]';
    o_sms text := 'MOAUM: the Summer Semester of [SESSION] is open, [OPENS] to [CLOSES]. You may register your outstanding courses on the portal.';
    o_portal text := 'The Summer Semester of [SESSION] is open from [OPENS] to [CLOSES]: register your outstanding courses on the Summer Semester page.';
BEGIN
    SELECT * INTO t FROM platform.notice_template WHERE key = 'SUMMER_OPEN';
    IF FOUND THEN
        v_email := replace(coalesce(t.email_body, ''), E'\r', '') = o_email AND t.updated_by IS NULL;
        v_sms := coalesce(t.sms_body, '') = o_sms AND t.updated_by IS NULL;
        v_portal := coalesce(t.portal_body, '') = o_portal AND t.updated_by IS NULL;
        UPDATE platform.notice_template SET
               email_body = CASE WHEN v_email THEN E'Dear [FIRST_NAME],\n\nThe Summer Semester of [SESSION] is open for registration from [OPENS] to [CLOSES]. If you are in your final year or in spillover, you may select the courses you still owe, from the first and the second semester together, even where your earlier results are not yet on the portal. The Academic Office verifies each course against your record.\n\nSign in, open Summer Semester, select your courses and pay the Summer fees; your registration stands once they are paid.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]' ELSE email_body END,
               sms_body = CASE WHEN v_sms THEN 'MOAUM: the Summer Semester of [SESSION] is open, [OPENS] to [CLOSES]. You may register the courses you owe on the portal.' ELSE sms_body END,
               portal_body = CASE WHEN v_portal THEN 'The Summer Semester of [SESSION] is open from [OPENS] to [CLOSES]: register the courses you owe on the Summer Semester page.' ELSE portal_body END,
               variables = CASE WHEN v_email AND v_sms AND v_portal THEN array_remove(variables, 'OUTSTANDING') ELSE variables END,
               priority = CASE WHEN priority = 'NORMAL' THEN 'LOW' ELSE priority END
         WHERE key = 'SUMMER_OPEN';
        IF NOT (v_email AND v_sms AND v_portal) THEN
            RAISE NOTICE 'V779: the SUMMER_OPEN notice was edited by hand (email %, sms %, portal % left as they were)', NOT v_email, NOT v_sms, NOT v_portal;
        END IF;
    END IF;
    -- a broadcast of about 19,000 must not queue ahead of receipts and password resets: the dispatcher orders by priority, then age
    UPDATE platform.notice_template SET priority = 'LOW' WHERE key = 'SUMMER_CLOSING' AND priority = 'NORMAL';
END $$;
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority)
VALUES ('SUMMER_COURSE_REVIEWED', 'Summer Semester course reviewed',
        'To the student when the Academic Office decides, or the results settle, courses of their Summer selection, or asks them something (V779)',
        'Your Summer Semester courses of [SESSION] were reviewed',
        E'Dear [FIRST_NAME],\n\n[LINES]\n\n[MONEY]\n\nOpen Summer Semester on the portal to see each course and its reason.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
        'MOAUM: your Summer Semester courses of [SESSION] were reviewed. Open the portal to see the result.',
        'Summer courses reviewed', '[LINES]',
        ARRAY['FIRST_NAME', 'SESSION', 'LINES', 'MONEY', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

COMMIT;

