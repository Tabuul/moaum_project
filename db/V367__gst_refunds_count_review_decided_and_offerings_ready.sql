-- V367: GST refunds that count, payments no course requires decided by the Bursary, the GST and EPS offices' own courses, and the session's offerings checked.
--
-- 1  A refund that counts. finance.refund.reference is the refund's own number (RF-2026-0001); the payment it refunds is
--    source_reference (V067). Since V314 the GST entitlement, the offices' population and the CBT candidate list asked
--    "is there an approved or paid refund whose reference is this payment's?" — never true — so a GST payment refunded
--    through the Bursary still entitled the student. From V367 a payment counts net of the refunds approved or paid
--    against it (finance.gst_refunded); refunded in full, it entitles no more.
-- 2  A payment no course requires, decided. V366 flags a GST payment no GST/EPS course requires of the student (review).
--    The Bursary now decides each: KEEP (with a note — a programme change pending, the student owes next session) or
--    REFUND, which raises a refund against the payment through the existing maker–checker workflow (finance.propose_refund
--    with the payment as its source; another officer approves it on the refunds desk; nothing is approved or paid here).
--    A decided payment leaves the review list; a refund the checker rejects puts it back.
-- 3  Only the GST office's courses are GST courses. The uploads marked departmental courses (status G) and EPS courses as kind
--    GST, and V314 filed every one under the GST office by default — on its dashboard, its courses, its CBT examinations, and
--    from V366 in its students' fee. A course is now the GST office's when its subject is a General Studies family (GST, GNS,
--    GES), the EPS office's for an Entrepreneurship family (EPS, ENT) or an entrepreneurship title, and no office's otherwise:
--    it stays with its department, owes no GST fee, and its CBT examinations are the examinations office's. The families are
--    data the offices keep (catalogue.general_family); an office claims a course its families miss; a course no office runs can
--    be given back to its department as Core.
-- 4  The session's offerings checked. A GST/EPS course is owed only when it runs in the session (V366), so a course
--    bound to programmes but not opened for the session leaves its students owing nothing. catalogue.gst_offering_gaps
--    names them; catalogue.open_gst_offerings opens them in their own semester, refusing a closed session.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V367: GST refunds that count, review decided, offerings checked', true);

-- ── 1 · what has been refunded against a payment ────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS ix_refund_source ON finance.refund (source_reference) WHERE source_reference IS NOT NULL;

CREATE OR REPLACE FUNCTION finance.gst_refunded(p_reference text)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(rf.amount), 0) FROM finance.refund rf WHERE rf.source_reference = p_reference AND rf.state IN ('APPROVED', 'PAID')
$$;
COMMENT ON FUNCTION finance.gst_refunded(text) IS
  'V367: what the refunds approved or paid against a payment (finance.refund.source_reference) take back from it. A refund''s own reference is its RF- number, never the payment''s.';

-- ── 2 · the Bursary's decision on a payment no course requires ──────────────────────────────────────────────────

CREATE TABLE finance.gst_payment_review (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference      text NOT NULL UNIQUE REFERENCES finance.payment_reference(reference) ON DELETE CASCADE,
    student_id     uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    session        text NOT NULL,
    decision       text NOT NULL CHECK (decision IN ('KEEP', 'REFUND')),
    note           text NOT NULL CHECK (btrim(note) <> ''),
    refund_id      uuid NULL REFERENCES finance.refund(id) ON DELETE CASCADE,
    decided_by     uuid NOT NULL,
    decided_office text NULL,
    decided_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_gst_review_refund CHECK ((decision = 'REFUND') = (refund_id IS NOT NULL))
);
COMMENT ON TABLE finance.gst_payment_review IS
  'V367: the Bursary''s decision on a GST payment no GST/EPS course requires of the student (finance.gst_entitlement.review): KEEP with its reason, or REFUND through the maker–checker refund workflow (refund_id). One standing decision per payment; a rejected refund puts the payment back in review. The payment itself is never touched.';
CREATE INDEX ix_gst_review_student ON finance.gst_payment_review (student_id, session);
SELECT audit.attach('finance.gst_payment_review');
GRANT SELECT ON finance.gst_payment_review TO app_auditor;

/* whether every GST payment of the student's session that still counts carries a standing decision */
CREATE OR REPLACE FUNCTION finance.gst_review_settled(p_student uuid, p_session text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
        SELECT 1 FROM finance.payment_reference r
         WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
           AND r.amount > finance.gst_refunded(r.reference)
           AND NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                            WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED')))
$$;

CREATE OR REPLACE FUNCTION finance.decide_gst_payment(p_reference text, p_decision text, p_note text,
                                                      p_payer text DEFAULT NULL, p_bank text DEFAULT NULL,
                                                      p_account_name text DEFAULT NULL, p_account_last4 text DEFAULT NULL)
RETURNS finance.gst_payment_review
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        v_dec text := upper(btrim(coalesce(p_decision, '')));
        v_note text := nullif(btrim(coalesce(p_note, '')), '');
        r finance.payment_reference; e record; v_net numeric; v_payer text; v_rf text; v_refund uuid; d finance.gst_payment_review;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a GST payment is decided by a person' USING ERRCODE = '23514'; END IF;
    IF v_dec NOT IN ('KEEP', 'REFUND') THEN
        RAISE EXCEPTION 'GST_REVIEW_DECISION: a payment no course requires is kept or refunded' USING ERRCODE = '23514';
    END IF;
    IF v_note IS NULL THEN RAISE EXCEPTION 'GST_REVIEW_NOTE: the decision carries its reason' USING ERRCODE = '23514'; END IF;
    SELECT * INTO r FROM finance.payment_reference WHERE reference = upper(btrim(coalesce(p_reference, ''))) FOR UPDATE;
    IF NOT FOUND OR r.purpose NOT LIKE 'GST fee %' OR r.confirmed_at IS NULL THEN
        RAISE EXCEPTION 'GST_REVIEW_NOT_A_PAYMENT: % is not a confirmed GST payment', p_reference USING ERRCODE = '23503';
    END IF;
    SELECT * INTO e FROM finance.gst_entitlement(r.student_id, r.session);
    IF NOT coalesce(e.review, false)
       OR EXISTS (SELECT 1 FROM finance.gst_payment_review d2 LEFT JOIN finance.refund rf ON rf.id = d2.refund_id
                   WHERE d2.reference = r.reference AND (d2.decision = 'KEEP' OR rf.state <> 'REJECTED')) THEN
        RAISE EXCEPTION 'GST_REVIEW_NOT_PENDING: the GST payment % is not awaiting a decision: a GST/EPS course requires it, or it is decided already', r.reference
            USING ERRCODE = '23514';
    END IF;
    v_net := r.amount - finance.gst_refunded(r.reference);
    IF v_dec = 'REFUND' THEN
        SELECT s.surname || ', ' || s.other_names INTO v_payer FROM people.student s WHERE s.id = r.student_id;
        -- the existing maker–checker workflow: proposed here, approved by another officer on the refunds desk, paid there
        v_rf := finance.propose_refund(r.student_id, coalesce(nullif(btrim(coalesce(p_payer, '')), ''), v_payer),
                                       'GST fee paid for ' || r.session || ' though no GST/EPS course requires it: ' || v_note,
                                       v_net, p_bank, p_account_name, p_account_last4, r.reference);
        SELECT id INTO v_refund FROM finance.refund WHERE reference = v_rf;
    END IF;
    INSERT INTO finance.gst_payment_review (reference, student_id, session, decision, note, refund_id, decided_by, decided_office)
    VALUES (r.reference, r.student_id, r.session, v_dec, v_note, v_refund, who, office)
    ON CONFLICT (reference) DO UPDATE SET decision = EXCLUDED.decision, note = EXCLUDED.note, refund_id = EXCLUDED.refund_id,
                                           decided_by = EXCLUDED.decided_by, decided_office = EXCLUDED.decided_office, decided_at = now()
    RETURNING * INTO d;
    RETURN d;
END $$;
COMMENT ON FUNCTION finance.decide_gst_payment(text, text, text, text, text, text, text) IS
  'V367: the Bursary decides a GST payment no course requires — KEEP with a note, or REFUND, which proposes a refund of what is left of it against the payment through finance.propose_refund (maker); another officer approves it. Refused unless the payment is awaiting a decision.';

-- ── 3 · which office a general course is: by the subject's code family, kept as data; never by default ─────────
-- The course uploads mark a course of kind GST whenever a programme's structure gives it status G or a GST/EPS classification
-- (V119, V338), and V314 then filed every such course under the GST office unless its code or title said EPS. So departmental
-- courses a structure marked G, and EPS courses without an EPS code, sat on the GST office's dashboard, its course list and its
-- CBT examinations — and, from V366, made their students owe the GST fee. From V367 a course is the GST office's when its
-- subject is a General Studies family (GST, GNS, GES), the EPS office's when an Entrepreneurship family (EPS, ENT) or its title
-- is entrepreneurship, and nobody's otherwise: such a course stays with its department, is examined by the examinations office,
-- and owes no GST fee. The families are rows the offices keep; an office claims a course its family does not reach.

CREATE TABLE catalogue.general_family (
    prefix     text PRIMARY KEY CHECK (prefix ~ '^[A-Z]{2,5}$'),
    office     text NOT NULL CHECK (office IN ('GST', 'EPS')),
    added_by   uuid NULL,
    added_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE catalogue.general_family IS
  'V367: the subject codes of the General Studies (GST) and Entrepreneurship Studies (EPS) courses — the letters of a course code, "MOAU-" set aside. A course of kind GST is the office''s whose family its subject is; with none, it is no office''s.';
INSERT INTO catalogue.general_family (prefix, office) VALUES ('GST', 'GST'), ('GNS', 'GST'), ('GES', 'GST'), ('EPS', 'EPS'), ('ENT', 'EPS');
SELECT audit.attach('catalogue.general_family');
GRANT SELECT ON catalogue.general_family TO app_auditor;

/* the subject of a course code: its leading letters, the University's "MOAU-" prefix set aside */
CREATE OR REPLACE FUNCTION catalogue.course_subject(p_code text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT substring(regexp_replace(upper(btrim(coalesce(p_code, ''))), '^MOAU-?', '') FROM '^[A-Z]+')
$$;

CREATE OR REPLACE FUNCTION catalogue.general_office_of(p_code text, p_title text, p_kind text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN coalesce(p_kind, '') <> 'GST' THEN NULL
                WHEN EXISTS (SELECT 1 FROM catalogue.general_family f WHERE f.office = 'EPS' AND f.prefix = catalogue.course_subject(p_code)) THEN 'EPS'
                WHEN coalesce(p_title, '') ~* '(entrepreneur|enterprise|venture)' THEN 'EPS'
                WHEN EXISTS (SELECT 1 FROM catalogue.general_family f WHERE f.office = 'GST' AND f.prefix = catalogue.course_subject(p_code)) THEN 'GST'
                ELSE NULL END
$$;
COMMENT ON FUNCTION catalogue.general_office_of(text, text, text) IS
  'The office a general course belongs to (V314; V367: by the families on catalogue.general_family, never by default): EPS for an EPS-family subject or an entrepreneurship title, GST for a GST-family subject, NULL otherwise — a course no office runs.';

-- every course of kind GST classified again by the rule; what changed is told here and kept on the audit record
DO $$
DECLARE r record; n_gst_none int := 0; n_gst_eps int := 0; n_eps_gst int := 0; n_eps_none int := 0; n_none_set int := 0;
BEGIN
    FOR r IN SELECT c.code, c.general_office AS before, catalogue.general_office_of(c.code, c.title, c.kind) AS after
               FROM catalogue.course c WHERE c.kind = 'GST' AND c.general_office IS DISTINCT FROM catalogue.general_office_of(c.code, c.title, c.kind) LOOP
        UPDATE catalogue.course SET general_office = r.after WHERE code = r.code;
        IF r.before = 'GST' AND r.after IS NULL THEN n_gst_none := n_gst_none + 1;
        ELSIF r.before = 'GST' AND r.after = 'EPS' THEN n_gst_eps := n_gst_eps + 1;
        ELSIF r.before = 'EPS' AND r.after = 'GST' THEN n_eps_gst := n_eps_gst + 1;
        ELSIF r.before = 'EPS' AND r.after IS NULL THEN n_eps_none := n_eps_none + 1;
        ELSE n_none_set := n_none_set + 1; END IF;
    END LOOP;
    RAISE NOTICE 'V367 reclassified general courses: % GST to no office, % GST to EPS, % EPS to GST, % EPS to no office, % newly assigned',
        n_gst_none, n_gst_eps, n_eps_gst, n_eps_none, n_none_set;
END $$;

-- an examination follows its course: the office that now has the course, or the examinations office for a course no general office runs
UPDATE assessment.cbt_exam e SET office = coalesce(c.general_office, 'EXAMS')
  FROM catalogue.course c
 WHERE c.code = e.course_code AND e.office IN ('GST', 'EPS') AND coalesce(c.general_office, 'EXAMS') <> e.office;

/* an office takes a course its families do not reach (or the other office's): kind GST, filed under the office; its examinations follow */
CREATE OR REPLACE FUNCTION catalogue.claim_general_course(p_code text, p_office text)
RETURNS catalogue.course
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := upper(btrim(coalesce(p_office, ''))); c catalogue.course;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is classified by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('GST', 'EPS') THEN RAISE EXCEPTION 'GEN_OFFICE: a general course is the GST or the EPS office''s' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.kind <> 'GST' THEN
        RAISE EXCEPTION 'GEN_NOT_GENERAL: % is a departmental course (%); its department classifies it', c.code, c.kind USING ERRCODE = '23514',
            HINT = 'A course is offered as GST/EPS through the programmes that take it (basis GST) on the catalogue.';
    END IF;
    UPDATE catalogue.course SET general_office = v_office WHERE code = c.code RETURNING * INTO c;
    UPDATE assessment.cbt_exam SET office = v_office WHERE course_code = c.code AND office IN ('GST', 'EPS', 'EXAMS') AND office <> v_office;
    RETURN c;
END $$;

/* a course an upload marked general that no office runs, given back to its department: a departmental course, its programme bindings Core */
CREATE OR REPLACE FUNCTION catalogue.return_general_course(p_code text, p_reason text)
RETURNS catalogue.course
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; c catalogue.course;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is classified by a person' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'GEN_REASON: say why the course goes back to its department' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.kind <> 'GST' THEN RAISE EXCEPTION 'GEN_NOT_GENERAL: % is already a departmental course', c.code USING ERRCODE = '23514'; END IF;
    UPDATE catalogue.course SET kind = 'Core' WHERE code = c.code RETURNING * INTO c;
    UPDATE catalogue.course_offer SET basis = 'Core' WHERE course_code = c.code AND basis = 'GST';
    UPDATE assessment.cbt_exam SET office = 'EXAMS' WHERE course_code = c.code AND office IN ('GST', 'EPS');
    RETURN c;
END $$;
COMMENT ON FUNCTION catalogue.return_general_course(text, text) IS
  'V367: a course an upload marked general (kind GST) given back to its department as a Core course, its GST bindings made Core and its examinations the examinations office''s. Registrations, results and history stay as they are.';

/* a family added (with its office) or removed; courses of kind GST no office runs that the new family reaches are filed under it */
CREATE OR REPLACE FUNCTION catalogue.set_general_family(p_prefix text, p_office text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_prefix text := upper(btrim(coalesce(p_prefix, ''))); v_office text := upper(nullif(btrim(coalesce(p_office, '')), '')); n int := 0;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a family is set by a person' USING ERRCODE = '23514'; END IF;
    IF v_prefix !~ '^[A-Z]{2,5}$' THEN RAISE EXCEPTION 'GEN_FAMILY: a family is the two to five letters of a course code' USING ERRCODE = '23514'; END IF;
    IF v_office IS NULL THEN
        DELETE FROM catalogue.general_family WHERE prefix = v_prefix;
        RETURN 0;
    END IF;
    IF v_office NOT IN ('GST', 'EPS') THEN RAISE EXCEPTION 'GEN_OFFICE: a family is the GST or the EPS office''s' USING ERRCODE = '23514'; END IF;
    INSERT INTO catalogue.general_family (prefix, office, added_by) VALUES (v_prefix, v_office, who)
    ON CONFLICT (prefix) DO UPDATE SET office = EXCLUDED.office, added_by = EXCLUDED.added_by, added_at = now();
    UPDATE catalogue.course SET general_office = v_office
     WHERE kind = 'GST' AND general_office IS NULL AND catalogue.course_subject(code) = v_prefix;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE assessment.cbt_exam e SET office = v_office FROM catalogue.course c
     WHERE c.code = e.course_code AND c.general_office = v_office AND catalogue.course_subject(c.code) = v_prefix AND e.office = 'EXAMS';
    RETURN n;
END $$;

-- ── 4 · the engine, the gate and the examination: only a course an office runs is a GST/EPS course ───────────────

CREATE OR REPLACE FUNCTION finance.gst_eps_rows(p_session text, p_student uuid DEFAULT NULL)
RETURNS TABLE (student_id uuid, course_code text, title text, units int, office text, level int, semesters int[], offering_id uuid,
               source text, counts boolean, status text, registered boolean, failed_in text, last_grade text, passed_in text)
LANGUAGE sql STABLE AS $$
    WITH cur AS (SELECT coalesce(max(name), '') AS name FROM policy.academic_session WHERE state = 'CURRENT'),
    -- the undergraduates in good standing it may concern, at the level the session reads them at
    base AS (
        SELECT s.id, s.programme_code, s.curriculum_track, s.curriculum_version,
               CASE WHEN p_session >= cur.name THEN s.current_level
                    ELSE (SELECT max(cr.level) FROM registration.course_registration cr WHERE cr.student_id = s.id AND cr.session = p_session) END AS level
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          CROSS JOIN cur
         WHERE (p_student IS NULL OR s.id = p_student) AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    gc AS (SELECT c.code, c.title, c.units, c.level, c.general_office, c.curriculum, c.state
             FROM catalogue.course c WHERE c.kind = 'GST' AND c.general_office IS NOT NULL AND c.code NOT LIKE 'DMO %'),
    -- the GST/EPS courses the session runs, in which semesters
    offered AS (SELECT o.course_code, array_agg(o.semester ORDER BY o.semester) AS semesters, (array_agg(o.id ORDER BY o.semester))[1] AS offering_id
                  FROM catalogue.offering o JOIN gc ON gc.code = o.course_code
                 WHERE o.session = p_session
                 GROUP BY o.course_code),
    -- every GST/EPS registration entry of these students up to the session
    ent AS (SELECT cr.student_id, cr.session, cr.semester, cr.status AS reg_status, e.status AS entry_status, o.id AS offering_id, o.course_code
              FROM base b
              JOIN registration.course_registration cr ON cr.student_id = b.id AND cr.session <= p_session
              JOIN registration.entry e ON e.registration_id = cr.id
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN gc ON gc.code = o.course_code),
    -- the record's results: the entries of approved registrations, as assessment.student_results reads them
    rec AS (SELECT DISTINCT x.student_id, x.session, x.semester, x.offering_id, x.course_code FROM ent x
             WHERE x.reg_status IN ('APPROVED', 'LOCKED') AND x.entry_status IN ('REGISTERED', 'APPROVED')),
    sheets AS (SELECT sh.id, sh.offering_id, sh.stage, coalesce(es.kind, 'MAIN') AS kind
                 FROM assessment.score_sheet sh
                 LEFT JOIN assessment.exam_session es ON es.id = sh.exam_session_id
                WHERE sh.offering_id IN (SELECT r.offering_id FROM rec r)),
    -- each sheet's latest scores read once, not once per student
    scores AS MATERIALIZED (SELECT sh.id AS sheet_id, ls.student_id, ls.points, ls.outcome, ls.grade
                              FROM sheets sh CROSS JOIN LATERAL assessment.latest_scores(sh.id) ls),
    sitting AS (SELECT r.student_id, r.session, r.semester, r.offering_id, r.course_code, sh.stage, sh.kind, sc.points, sc.outcome, sc.grade,
                       CASE sh.kind WHEN 'SPECIAL' THEN 1 WHEN 'RESIT' THEN 2 ELSE 3 END AS pr
                  FROM rec r JOIN sheets sh ON sh.offering_id = r.offering_id
                  LEFT JOIN scores sc ON sc.sheet_id = sh.id AND sc.student_id = r.student_id),
    -- assessment.course_final's resolution: a published special or re-sit the student sat supersedes the main sitting
    fin AS (SELECT DISTINCT ON (x.student_id, x.offering_id) x.*
                FROM sitting x
               WHERE (x.kind IN ('SPECIAL', 'RESIT') AND x.stage = 'PUBLISHED' AND x.outcome IS NOT NULL) OR x.kind = 'MAIN'
               ORDER BY x.student_id, x.offering_id, x.pr),
    res AS (SELECT f.student_id, f.course_code, f.session, f.semester, f.grade,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points > 0, false) AS passed,
                   coalesce(f.stage = 'PUBLISHED' AND f.outcome = 'GRADED' AND f.points = 0, false) AS failed
              FROM fin f),
    -- registration.carryovers_at's rule as of the session's start: failed, not passed since, never an elective
    carry AS (SELECT DISTINCT ON (f.student_id, f.course_code) f.student_id, f.course_code, f.session || ' semester ' || f.semester AS failed_in, f.grade
                FROM res f JOIN base b ON b.id = f.student_id
               WHERE f.failed AND f.session < p_session
                 AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer co
                                  WHERE co.course_code = f.course_code AND co.programme_code = b.programme_code AND co.basis = 'Elective')
                 AND NOT EXISTS (SELECT 1 FROM res g
                                  WHERE g.student_id = f.student_id AND g.course_code = f.course_code AND g.passed
                                    AND (g.session, g.semester) > (f.session, f.semester) AND g.session < p_session)
               ORDER BY f.student_id, f.course_code, f.session, f.semester),
    pass AS (SELECT r.student_id, r.course_code, bool_or(r.session < p_session) AS before, bool_or(r.session = p_session) AS now,
                    max(r.session || ' semester ' || r.semester) AS passed_in
               FROM res r WHERE r.passed GROUP BY r.student_id, r.course_code),
    fail_now AS (SELECT DISTINCT r.student_id, r.course_code FROM res r WHERE r.failed AND r.session = p_session),
    reg AS (SELECT x.student_id, x.course_code FROM ent x WHERE x.session = p_session AND x.entry_status <> 'DROPPED' GROUP BY x.student_id, x.course_code),
    -- the programme's own GST/EPS courses at the student's level, read as the registration menu reads them
    curric AS (SELECT b.id AS student_id, co.course_code, co.level
                 FROM base b
                 JOIN catalogue.course_offer co ON co.programme_code = b.programme_code AND co.level = b.level
                                               AND (co.track IS NULL OR b.curriculum_track IS NULL OR co.track = b.curriculum_track)
                 JOIN gc ON gc.code = co.course_code AND gc.state <> 'ENDED'
                WHERE gc.curriculum IS NULL OR b.curriculum_version IS NULL OR gc.curriculum = b.curriculum_version),
    src AS (SELECT c.student_id, c.course_code, 'CARRYOVER'::text AS source, 1 AS pr, NULL::int AS level FROM carry c
            UNION ALL SELECT c.student_id, c.course_code, 'COURSE_OFFERING', 2, c.level FROM curric c
            UNION ALL SELECT r.student_id, r.course_code, 'REGISTERED', 3, NULL FROM reg r),
    one AS (SELECT DISTINCT ON (s.student_id, s.course_code) s.* FROM src s ORDER BY s.student_id, s.course_code, s.pr)
    SELECT o.student_id, o.course_code, gc.title, gc.units, coalesce(gc.general_office, 'GST'), coalesce(o.level, gc.level), off.semesters, off.offering_id, o.source,
           -- owed this session: being taken; or run this session and still owed (a carryover, or the programme's course not yet passed)
           (rg.course_code IS NOT NULL OR (off.course_code IS NOT NULL AND (o.source = 'CARRYOVER' OR NOT coalesce(ps.before, false)))),
           CASE WHEN coalesce(ps.now, false) THEN 'COMPLETED'
                WHEN fn.course_code IS NOT NULL THEN 'FAILED'
                WHEN rg.course_code IS NOT NULL THEN 'REGISTERED'
                WHEN o.source = 'COURSE_OFFERING' AND coalesce(ps.before, false) THEN 'ALREADY_PASSED'
                WHEN off.course_code IS NULL THEN 'NOT_OFFERED'
                ELSE 'OUTSTANDING' END,
           rg.course_code IS NOT NULL, ca.failed_in, ca.grade, ps.passed_in
      FROM one o
      JOIN gc ON gc.code = o.course_code
      LEFT JOIN offered off ON off.course_code = o.course_code
      LEFT JOIN reg rg ON rg.student_id = o.student_id AND rg.course_code = o.course_code
      LEFT JOIN pass ps ON ps.student_id = o.student_id AND ps.course_code = o.course_code
      LEFT JOIN fail_now fn ON fn.student_id = o.student_id AND fn.course_code = o.course_code
      LEFT JOIN carry ca ON ca.student_id = o.student_id AND ca.course_code = o.course_code
$$;
COMMENT ON FUNCTION finance.gst_eps_rows(text, uuid) IS
  'V366 (V367: only courses the GST or the EPS office runs): the GST/EPS courses that concern each undergraduate in good standing in a session — source COURSE_OFFERING, CARRYOVER or REGISTERED; counts = owed this session; status OUTSTANDING, REGISTERED, COMPLETED, FAILED, ALREADY_PASSED or NOT_OFFERED. The one source of every GST/EPS obligation.';

CREATE OR REPLACE FUNCTION registration.gst_gate(p_student uuid, p_session text, p_course text)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH c AS (SELECT kind, general_office FROM catalogue.course WHERE code = p_course),
         g AS (SELECT * FROM finance.gst_setting WHERE id = 1),
         e AS (SELECT * FROM finance.gst_entitlement(p_student, p_session))
    SELECT CASE WHEN e.required AND e.stated AND e.fee > 0 AND NOT e.entitled
                     AND ((g.required_for_gst_eps AND c.kind = 'GST' AND c.general_office IS NOT NULL AND (c.general_office = 'GST' OR g.covers_eps))
                          OR g.required_for_all)
                THEN 'GST_PAYMENT_REQUIRED: you are required to pay the GST fee of NGN ' || to_char(e.fee, 'FM999,999,999,990.00') || ' for ' || p_session
                     || ' before you can register ' || CASE WHEN c.general_office IS NOT NULL THEN c.general_office || ' courses' ELSE 'your courses' END
                     || '. GST payment covers both GST and EPS requirements.'
                ELSE NULL END
      FROM g CROSS JOIN e LEFT JOIN c ON true
$$;

CREATE OR REPLACE FUNCTION assessment.cbt_new_exam(p_office text, p_offering uuid, p_title text, p_instructions text, p_duration integer, p_total integer,
                                                   p_selection text, p_random_q boolean, p_random_o boolean, p_pass numeric, p_attempts integer, p_security text,
                                                   p_venue text, p_violation_limit integer, p_violation_action text, p_second_session text,
                                                   p_starts timestamp with time zone, p_ends timestamp with time zone)
RETURNS assessment.cbt_exam
LANGUAGE plpgsql AS $$
DECLARE o record; e assessment.cbt_exam; v_office text := upper(btrim(coalesce(p_office, '')));
BEGIN
    SELECT ofr.id, ofr.course_code, ofr.session, ofr.semester, c.kind, c.general_office, c.title AS course_title, c.cbt_enabled, c.state AS course_state
      INTO o FROM catalogue.offering ofr JOIN catalogue.course c ON c.code = ofr.course_code WHERE ofr.id = p_offering;
    IF NOT FOUND THEN RAISE EXCEPTION 'CBT_OFFERING_NOT_FOUND: no such course offering' USING ERRCODE = '23503'; END IF;
    -- a course the GST or the EPS office runs is that office's; every other course is examined by the University's examinations office (V367: never GST by default)
    IF coalesce(o.general_office, 'EXAMS') <> v_office THEN
        RAISE EXCEPTION 'CBT_NOT_OFFICE_COURSE: % is not a course of the % office', o.course_code, v_office USING ERRCODE = '23514',
            HINT = 'An office examines its own courses: GST and EPS their General Studies courses, the examinations office every other course.';
    END IF;
    IF NOT o.cbt_enabled THEN
        RAISE EXCEPTION 'CBT_COURSE_NOT_ENABLED: % is not a CBT course', o.course_code USING ERRCODE = '23514',
            HINT = 'The Academic Office, the Registry or Examinations and Records allows a course to be examined by CBT on the catalogue.';
    END IF;
    INSERT INTO assessment.cbt_exam (reference, office, course_code, offering_id, session, semester, title, instructions, duration_minutes, total_questions,
                                     selection, randomize_questions, randomize_options, pass_mark, attempt_limit, security_mode, venue, violation_limit,
                                     violation_action, second_session, starts_at, ends_at, created_by, created_office)
    VALUES ('CBT/' || replace(o.session, '/', '-') || '/' || lpad(platform.next_number('cbt_exam', 'UNIVERSITY', o.session)::text, 5, '0'),
            v_office, o.course_code, o.id, o.session, o.semester, btrim(p_title), nullif(btrim(coalesce(p_instructions, '')), ''),
            coalesce(p_duration, 60), coalesce(p_total, 0), coalesce(upper(p_selection), 'FIXED'), coalesce(p_random_q, true), coalesce(p_random_o, false),
            coalesce(p_pass, 40), coalesce(p_attempts, 1), coalesce(upper(p_security), 'STANDARD'), coalesce(upper(p_venue), 'REMOTE'),
            coalesce(p_violation_limit, 2), coalesce(upper(p_violation_action), 'WARN'), coalesce(upper(p_second_session), 'CONTINUE'),
            p_starts, p_ends, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    RETURNING * INTO e;
    RETURN e;
END $$;

-- ── 5 · the entitlement, the population and the CBT candidates: net of refunds; review until decided ─────────────

CREATE OR REPLACE FUNCTION finance.gst_entitlement(p_student uuid, p_session text)
RETURNS TABLE (required boolean, stated boolean, fee numeric, covers_eps boolean, paid numeric, entitled boolean, state text,
               reference text, receipt_no text, paid_at timestamptz, open_reference text, open_amount numeric, open_expires_at timestamptz,
               source text, channel text, legacy_reference text,
               gst_required boolean, eps_required boolean, reason text, gst_reason text, eps_reason text, review boolean)
LANGUAGE sql STABLE AS $$
    WITH f AS (SELECT * FROM finance.gst_fee_for(p_student, p_session)),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    -- V367: a payment counts net of the refunds approved or paid against it (finance.refund.source_reference); refunded in full, it entitles no more
    pays AS (SELECT r.id, r.reference, r.receipt_no, r.amount - x.refunded AS amount, r.confirmed_at, r.channel
               FROM finance.payment_reference r
               CROSS JOIN LATERAL (SELECT finance.gst_refunded(r.reference) AS refunded) x
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                AND r.amount > x.refunded),
    agg AS (SELECT coalesce(sum(amount), 0) AS paid, max(confirmed_at) AS paid_at, count(*) AS n FROM pays),
    last AS (SELECT p.id, p.reference, p.receipt_no, p.channel FROM pays p ORDER BY p.confirmed_at DESC LIMIT 1),
    open AS (SELECT r.reference, r.amount, r.expires_at
               FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()
              ORDER BY r.generated_at DESC LIMIT 1),
    el AS (SELECT * FROM finance.gst_eps_eligibility(p_student, p_session)),
    -- whether this portal runs GST/EPS in the session at all: a payment no course requires is only questioned where it does
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session) AS gst_run)
    SELECT el.required, f.stated, f.amount, cfg.covers_eps, agg.paid,
           -- a confirmed reference was generated for the fee as it stood: a later change of the fee does not unmake the payment
           (agg.n > 0 OR (f.stated AND f.amount = 0)) AS entitled,
           CASE WHEN agg.n > 0 THEN 'PAID'
                WHEN NOT el.required THEN 'NOT_REQUIRED'
                WHEN f.stated AND f.amount = 0 THEN 'EXEMPT'
                WHEN NOT f.stated THEN 'NOT_STATED'
                WHEN open.reference IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           last.reference, last.receipt_no, agg.paid_at, open.reference, open.amount, open.expires_at,
           CASE WHEN last.id IS NULL THEN NULL WHEN last.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           last.channel,
           (SELECT coalesce(lp.source_reference, lp.source_transaction_id) FROM finance.legacy_gst_reconciliation rc JOIN finance.legacy_gst_payment lp ON lp.id = rc.payment_id WHERE rc.payment_reference_id = last.id),
           el.gst_required, el.eps_required, el.reason, el.gst_reason, el.eps_reason,
           -- V367: until the Bursary decides it — kept, or refunded through the refund workflow
           (agg.n > 0 AND NOT el.required AND run.gst_run AND NOT finance.gst_review_settled(p_student, p_session))
      FROM f CROSS JOIN cfg CROSS JOIN agg CROSS JOIN el CROSS JOIN run LEFT JOIN last ON true LEFT JOIN open ON true
$$;
COMMENT ON FUNCTION finance.gst_entitlement(uuid, text) IS
  'The authoritative answer (V314; source V323; V366: required from the student''s GST/EPS courses; V367: net of refunds against the payment): entitled when a CONFIRMED reference of purpose ''GST fee <session>'' stands for the student and is not refunded in full. '
  'state PAID, NOT_REQUIRED, EXEMPT, NOT_STATED, PENDING or NOT_PAID. review: paid, yet no GST/EPS course requires it in a session this portal runs, and the Bursary has not decided it (finance.decide_gst_payment).';

CREATE OR REPLACE FUNCTION finance.gst_population(p_session text, p_semester int)
RETURNS TABLE (student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
               programme_code text, programme text, level int, status text, entry_mode text,
               required boolean, fee numeric, stated boolean, paid numeric, entitled boolean, pay_state text, reference text, paid_at timestamptz,
               gst_registered boolean, eps_registered boolean, gst_courses int, eps_courses int, registered_at timestamptz, pay_source text,
               gst_required boolean, eps_required boolean, gst_reason text, eps_reason text,
               gst_carryover boolean, eps_carryover boolean, gst_completed boolean, eps_completed boolean,
               gst_owed text, eps_owed text, review boolean)
LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex,
               p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.programme_code, p.name AS programme,
               s.current_level AS level, s.status, s.entry_mode
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code AND p.category = 'UNDER GRADUATE'
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = d.faculty_code
         WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    cfg AS (SELECT covers_eps FROM finance.gst_setting WHERE id = 1),
    run AS (SELECT EXISTS (SELECT 1 FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' WHERE o.session = p_session) AS gst_run),
    -- the engine over the whole register at once; a semester asked for narrows what is owed to the courses run in it
    eng AS (SELECT r.student_id, r.office, r.source, r.status, r.course_code,
                   (r.counts AND (p_semester IS NULL OR p_semester = ANY (r.semesters))) AS due
              FROM finance.gst_eps_rows(p_session, NULL) r),
    req AS (SELECT x.student_id,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'GST'), false) AS g_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'GST'), false) AS g_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'GST'), false) AS g_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'GST'), false) AS g_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'GST'), false) AS g_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'GST'), false) AS g_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'GST' AND x.due), false) AS g_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'GST' AND x.due) AS g_owed,
                   coalesce(bool_or(x.due) FILTER (WHERE x.office = 'EPS'), false) AS e_req,
                   coalesce(bool_or(x.due AND x.source = 'COURSE_OFFERING') FILTER (WHERE x.office = 'EPS'), false) AS e_off,
                   coalesce(bool_or(x.due AND x.source = 'CARRYOVER') FILTER (WHERE x.office = 'EPS'), false) AS e_carry,
                   coalesce(bool_or(x.due AND x.source = 'REGISTERED') FILTER (WHERE x.office = 'EPS'), false) AS e_reg,
                   coalesce(bool_or(x.status = 'ALREADY_PASSED') FILTER (WHERE x.office = 'EPS'), false) AS e_done,
                   coalesce(bool_or(x.status = 'NOT_OFFERED') FILTER (WHERE x.office = 'EPS'), false) AS e_none,
                   coalesce(bool_and(x.status = 'COMPLETED') FILTER (WHERE x.office = 'EPS' AND x.due), false) AS e_complete,
                   string_agg(x.course_code, ', ' ORDER BY x.course_code) FILTER (WHERE x.office = 'EPS' AND x.due) AS e_owed
              FROM eng x GROUP BY x.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM finance.gst_fee f WHERE f.session = p_session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    -- V367: net of the refunds approved or paid against each payment; a payment refunded in full no longer counts
    refunded AS (SELECT rf.source_reference AS reference, sum(rf.amount) AS amount FROM finance.refund rf
                  WHERE rf.state IN ('APPROVED', 'PAID') AND rf.source_reference IS NOT NULL GROUP BY rf.source_reference),
    net AS (SELECT r.student_id, r.reference, r.channel, r.confirmed_at, r.amount - coalesce(x.amount, 0) AS amount
              FROM finance.payment_reference r LEFT JOIN refunded x ON x.reference = r.reference
             WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.amount > coalesce(x.amount, 0)),
    pays AS (SELECT r.student_id, sum(r.amount) AS paid, max(r.confirmed_at) AS paid_at, count(*) AS n,
                    (array_agg(r.reference ORDER BY r.confirmed_at DESC))[1] AS reference,
                    (array_agg(r.channel ORDER BY r.confirmed_at DESC))[1] AS channel
               FROM net r
              GROUP BY r.student_id),
    -- V367: a payment no course requires stays in review until the Bursary decides it
    undecided AS (SELECT DISTINCT r.student_id FROM net r
                   WHERE NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                                      WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED'))),
    pend AS (SELECT DISTINCT r.student_id FROM finance.payment_reference r
              WHERE r.session = p_session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NULL AND r.expires_at > now()),
    regs AS (SELECT cr.student_id,
                    count(*) FILTER (WHERE c.general_office = 'GST') AS gst_courses,
                    count(*) FILTER (WHERE c.general_office = 'EPS') AS eps_courses,
                    min(cr.submitted_at) AS registered_at
               FROM registration.course_registration cr
               JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
               JOIN catalogue.offering o ON o.id = e.offering_id
               JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST'
              WHERE cr.session = p_session AND (p_semester IS NULL OR cr.semester = p_semester)
              GROUP BY cr.student_id),
    j AS (SELECT b.*, coalesce(q.g_req, false) AS g_req, coalesce(q.e_req, false) AS e_req,
                 (coalesce(q.g_req, false) OR (coalesce(q.e_req, false) AND cfg.covers_eps)) AS req,
                 q.g_off, q.g_carry, q.g_reg, q.g_done, q.g_none, q.g_complete, q.g_owed,
                 q.e_off, q.e_carry, q.e_reg, q.e_done, q.e_none, q.e_complete, q.e_owed,
                 fr.id AS fee_id, fr.amount AS fee_amount, py.paid, py.paid_at, py.n, py.reference, py.channel, pd.student_id AS pending,
                 rg.gst_courses, rg.eps_courses, rg.registered_at, run.gst_run AS run_on, (ud.student_id IS NOT NULL) AS undecided
            FROM base b
            CROSS JOIN cfg CROSS JOIN run
            LEFT JOIN req q ON q.student_id = b.id
            LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                  AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                LIMIT 1) fr ON true
            LEFT JOIN pays py ON py.student_id = b.id
            LEFT JOIN pend pd ON pd.student_id = b.id
            LEFT JOIN regs rg ON rg.student_id = b.id
            LEFT JOIN undecided ud ON ud.student_id = b.id)
    SELECT j.id, j.number, j.surname, j.other_names, j.sex, j.faculty_code, j.faculty, j.dept_code, j.department, j.programme_code, j.programme,
           j.level, j.status, j.entry_mode,
           j.req,
           coalesce(j.fee_amount, 0), (j.fee_id IS NOT NULL),
           coalesce(j.paid, 0),
           (coalesce(j.n, 0) > 0 OR (j.fee_id IS NOT NULL AND j.fee_amount = 0)),
           CASE WHEN coalesce(j.n, 0) > 0 THEN 'PAID'
                WHEN NOT j.req THEN 'NOT_REQUIRED'
                WHEN j.fee_id IS NOT NULL AND j.fee_amount = 0 THEN 'EXEMPT'
                WHEN j.fee_id IS NULL THEN 'NOT_STATED'
                WHEN j.pending IS NOT NULL THEN 'PENDING'
                ELSE 'NOT_PAID' END,
           j.reference, j.paid_at,
           coalesce(j.gst_courses, 0) > 0, coalesce(j.eps_courses, 0) > 0, coalesce(j.gst_courses, 0)::int, coalesce(j.eps_courses, 0)::int, j.registered_at,
           CASE WHEN j.n IS NULL THEN NULL WHEN j.channel = 'Legacy' THEN 'LEGACY_PORTAL' ELSE 'CURRENT_PORTAL' END,
           j.g_req, j.e_req,
           finance.gst_eps_reason('GST', coalesce(j.g_off, false), coalesce(j.g_carry, false), coalesce(j.g_reg, false), coalesce(j.g_done, false), coalesce(j.g_none, false)),
           finance.gst_eps_reason('EPS', coalesce(j.e_off, false), coalesce(j.e_carry, false), coalesce(j.e_reg, false), coalesce(j.e_done, false), coalesce(j.e_none, false)),
           coalesce(j.g_carry, false), coalesce(j.e_carry, false), coalesce(j.g_complete, false), coalesce(j.e_complete, false),
           j.g_owed, j.e_owed,
           (coalesce(j.n, 0) > 0 AND NOT j.req AND j.run_on AND j.undecided)
      FROM j
$$;
COMMENT ON FUNCTION finance.gst_population(text, int) IS
  'One row per undergraduate in good standing for a session (V314; V323; V366: required from finance.gst_eps_rows; V367: payments net of refunds, review until the Bursary decides): the GST fee owed or not, each office''s requirement with its reason code, carryover, completed, the courses owed, the fee, what was paid and from which portal, the registrations, review.';

CREATE OR REPLACE FUNCTION assessment.cbt_candidates(p_exam uuid)
RETURNS TABLE(student_id uuid, number text, surname text, other_names text, sex text, faculty_code text, faculty text, dept_code text, department text,
              programme_code text, programme text, level integer, student_status text, entitled boolean, eligible boolean, attempts integer, attempt_id uuid,
              attempt_status text, connection text, started_at timestamp with time zone, ends_at timestamp with time zone, submitted_at timestamp with time zone,
              time_left integer, last_activity_at timestamp with time zone, violations integer, answered integer, score numeric, max_marks integer, percentage numeric,
              grade text, passed boolean, outcome text, updated_at timestamp with time zone)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT x.*, c.general_office, c.kind FROM assessment.cbt_exam x LEFT JOIN catalogue.course c ON c.code = x.course_code WHERE x.id = p_exam),
    cfg AS (SELECT * FROM finance.gst_setting WHERE id = 1),
    reg AS (SELECT DISTINCT cr.student_id FROM e, registration.course_registration cr JOIN registration.entry en ON en.registration_id = cr.id
             WHERE e.office <> 'JUPEB' AND en.offering_id = e.offering_id AND en.status IN ('REGISTERED', 'APPROVED') AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    base AS (SELECT s.id, coalesce(s.matric_no, s.admission_no) AS number, s.surname, s.other_names, s.sex, s.status, s.current_level AS level, s.entry_mode,
                    p.code AS programme_code, p.name AS programme, p.dept_code, d.name AS department, d.faculty_code, f.name AS faculty
               FROM reg JOIN people.student s ON s.id = reg.student_id
               JOIN ref.programme p ON p.code = s.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code),
    pays AS (SELECT r.student_id, count(*) AS n FROM e, finance.payment_reference r
              WHERE e.office IN ('GST', 'EPS') AND r.session = e.session AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL AND r.student_id IN (SELECT id FROM base)
                AND r.amount > finance.gst_refunded(r.reference)
              GROUP BY r.student_id),
    fees AS (SELECT f.id, f.amount, f.level, f.entry_mode, f.faculty_code, f.programme_code, f.stated_at
               FROM e, finance.gst_fee f WHERE e.office IN ('GST', 'EPS') AND f.session = e.session AND f.superseded_at IS NULL AND f.effective_from <= current_date),
    att AS (SELECT DISTINCT ON (a.candidate_id) a.* FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam ORDER BY a.candidate_id, a.number DESC),
    cnt AS (SELECT a.candidate_id, count(*)::int AS attempts FROM assessment.cbt_attempt a WHERE a.exam_id = p_exam GROUP BY a.candidate_id),
    ent AS (SELECT b.id,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN (coalesce(py.n, 0) > 0 OR (fr.id IS NOT NULL AND fr.amount = 0))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS entitled,
                   CASE WHEN e.office IN ('GST', 'EPS')
                        THEN NOT (fr.id IS NOT NULL AND fr.amount > 0 AND NOT (coalesce(py.n, 0) > 0)
                                  AND ((cfg.required_for_gst_eps AND e.kind = 'GST' AND e.general_office IS NOT NULL AND (e.general_office = 'GST' OR cfg.covers_eps))
                                       OR (cfg.required_for_all AND finance.gst_required(b.id, e.session))))
                        ELSE coalesce(finance.clears(b.id, e.session, 'EXAMINATION'), false) END AS paid_up
              FROM e CROSS JOIN cfg CROSS JOIN base b
              LEFT JOIN pays py ON py.student_id = b.id
              LEFT JOIN LATERAL (SELECT f.id, f.amount FROM fees f
                                  WHERE (f.programme_code IS NULL OR f.programme_code = b.programme_code) AND (f.faculty_code IS NULL OR f.faculty_code = b.faculty_code)
                                    AND (f.level IS NULL OR f.level = b.level) AND (f.entry_mode IS NULL OR f.entry_mode = b.entry_mode)
                                  ORDER BY (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, (f.level IS NOT NULL) DESC, (f.entry_mode IS NOT NULL) DESC, f.stated_at DESC
                                  LIMIT 1) fr ON true),
    -- V365: a JUPEB examination's candidates — the JUPEB students registered for the subject in the session
    jreg AS (SELECT a.id, coalesce(a.exam_no, a.application_no) AS number, upper(a.surname) AS surname,
                    a.first_name || coalesce(' ' || a.middle_name, '') AS other_names, a.sex, a.state, cb.code AS combination, cb.name AS combination_name,
                    assessment.cbt_jupeb_fees_paid(a.id, e.semester) AS paid_up
               FROM e JOIN jupeb.subject_registration r ON r.subject_id = e.jupeb_subject_id AND r.session = e.session
               JOIN jupeb.application a ON a.id = r.application_id
               LEFT JOIN jupeb.combination cb ON cb.id = a.combination_id
              WHERE e.office = 'JUPEB'),
    everyone AS (
        SELECT b.id, b.number, b.surname, b.other_names, b.sex, b.faculty_code, b.faculty, b.dept_code, b.department, b.programme_code, b.programme, b.level, b.status,
               en.entitled, en.paid_up AND b.status IN ('ACTIVE', 'ADMITTED', 'PROBATION') AS eligible
          FROM base b JOIN ent en ON en.id = b.id
        UNION ALL
        SELECT j.id, j.number, j.surname, j.other_names, j.sex, 'JUPEB', 'JUPEB programme', NULL, NULL, j.combination, j.combination_name, NULL::int, j.state,
               j.paid_up, j.paid_up AND j.state = 'STUDENT'
          FROM jreg j)
    SELECT v.id, v.number, v.surname, v.other_names, v.sex, v.faculty_code, v.faculty, v.dept_code, v.department, v.programme_code, v.programme, v.level, v.status,
           v.entitled, v.eligible,
           coalesce(cn.attempts, 0), a.id,
           coalesce(a.status, 'NOT_STARTED'),
           CASE WHEN a.status = 'IN_PROGRESS' AND a.last_activity_at < now() - interval '60 seconds' THEN 'DISCONNECTED' WHEN a.status = 'IN_PROGRESS' THEN 'ONLINE' ELSE NULL END,
           a.started_at, a.ends_at, a.submitted_at,
           CASE WHEN a.status = 'IN_PROGRESS' THEN greatest(0, extract(epoch FROM a.ends_at - now()))::int ELSE NULL END,
           a.last_activity_at, coalesce(a.violations, 0), coalesce(a.answered, 0), a.score, a.max_marks, a.percentage, a.grade, a.passed, a.outcome, a.updated_at
      FROM everyone v
      LEFT JOIN att a ON a.candidate_id = v.id
      LEFT JOIN cnt cn ON cn.candidate_id = v.id
$$;

-- ── 6 · the session's GST/EPS offerings: which bound courses are not opened, and opening them ─────────────────────

CREATE OR REPLACE FUNCTION catalogue.gst_offering_gaps(p_session text, p_office text)
RETURNS TABLE (course_code text, title text, level int, semester int, office text, programmes bigint, levels text)
LANGUAGE sql STABLE AS $$
    SELECT c.code, c.title, c.level, c.semester, c.general_office, count(DISTINCT co.programme_code),
           string_agg(DISTINCT co.level::text, ', ')
      FROM catalogue.course c
      JOIN catalogue.course_offer co ON co.course_code = c.code
      JOIN ref.programme p ON p.code = co.programme_code AND NOT coalesce(p.archived, false) AND p.category = 'UNDER GRADUATE'
     WHERE c.kind = 'GST' AND c.general_office IS NOT NULL AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
       AND (p_office IS NULL OR c.general_office = p_office)
       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = p_session)
     GROUP BY c.code, c.title, c.level, c.semester, c.general_office
     ORDER BY c.general_office, c.level, c.code
$$;
COMMENT ON FUNCTION catalogue.gst_offering_gaps(text, text) IS
  'V367: the live GST/EPS courses bound to an undergraduate programme that are not opened in the session — the courses whose students owe nothing that session until they are (V366).';

CREATE OR REPLACE FUNCTION catalogue.open_gst_offerings(p_session text, p_office text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_state text; n int;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'an offering is opened by a person' USING ERRCODE = '23514'; END IF;
    SELECT state INTO v_state FROM policy.academic_session WHERE name = p_session;
    IF NOT FOUND THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF v_state IN ('CLOSED', 'ARCHIVED', 'CANCELLED') THEN
        RAISE EXCEPTION 'GST_SESSION_CLOSED: % is %; its offerings are not opened now', p_session, lower(v_state) USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.offering (id, course_code, session, semester)
    SELECT gen_random_uuid(), g.course_code, p_session, g.semester FROM catalogue.gst_offering_gaps(p_session, p_office) g
    ON CONFLICT (course_code, session, semester) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION catalogue.open_gst_offerings(text, text) IS
  'V367: opens in the session, each in its own semester, every live GST/EPS course of the office bound to a programme and not yet opened; refused for a closed, archived or cancelled session. Returns how many were opened.';

COMMIT;
