-- ═══════════════════════════════════════════════════════════════════════════
-- V342 — JUPEB: admission status checking and acceptance fees, O'Level sittings with their own documents, Non-Science,
--        the guided application, the statement of result, and a reusable attendance engine
--
--   1. ADMISSION STATUS CHECKING. A new window, JUPEB_ADMISSION_STATUS_CHECKING (closed until the Director of ICT opens it),
--      and a status checking fee the Bursary sets (default ₦1,000). A submitted applicant pays it once while the window is
--      open; the decision is then shown — ADMITTED, NOT ADMITTED, PENDING, PROCESSING or REQUIRES REVIEW — and never before.
--      The entitlement is the confirmed fee reference itself (jupeb.fee_reference, kind STATUS_CHECKING), not a flag.
--   2. ACCEPTANCE. An admitted applicant who has seen the decision pays the acceptance fee (Bursary's, default ₦15,000);
--      the acceptance letter is issued only on its confirmed reference, and school fees open only after it.
--   3. O'LEVEL SITTINGS. The applicant declares one or two sittings; each sitting's result is validated on its own (examination
--      body, number and year given; the same result never entered twice) and the combined result must hold five credits with
--      English and Mathematics. Each sitting has its OWN O'Level document (jupeb.document.sitting), all of them required.
--   4. NON-SCIENCE. The JUPEB programme is SCIENCE or NON_SCIENCE; a record written ARTS (V341) is the same thing and is
--      carried over.
--   5. THE GUIDED APPLICATION. jupeb.step_status(app) states, step by step (personal, O'Level, documents, programme,
--      review), what is complete and what still needs correcting, field by field — the dashboard's Save & Continue reads it.
--   6. THE STATEMENT OF RESULT, as the Board's sample: grades A–F with X (absent), Q (cancelled) and W (withheld); the grade
--      point out of 16 with the one point added when all three subjects are passed; the examination month and year; each
--      subject's course units (jupeb.subject_unit) for the note beneath.
--   7. ATTENDANCE. The University's existing register (registration.attendance) records only present/absent for undergraduate
--      offerings and cannot hold a JUPEB student or subject. A reusable engine (schema attendance) is added: registers per
--      session, semester, subject, class and date; PRESENT, ABSENT, LATE and EXCUSED; batch marking; corrections kept with
--      their reason; locking; instructors assigned to what they may take; a configurable minimum percentage (never invented).
--      It serves the JUPEB context now and is shaped for the other programmes later.
--   8. THE BOARD'S COMBINATIONS (SC-001 to SC-046, updated 2026) are seeded with their subjects and areas.
--   9. WHAT IS OFFERED. A combination is offered while it and its three subjects are active. The JUPEB Office disables a
--      subject or a combination the University does not offer and reactivates it later (jupeb.set_offered) — nothing is
--      deleted; a candidate holding a combination that stops being offered, before registering its subjects, is told and
--      chooses another; registered subjects are kept.
--  10. THE APPLICANT'S COMBINATION. On the programme step the applicant chooses Science or Non-Science AND one offered
--      combination of it (jupeb.choose); the application is complete only with one (when any is offered for the programme).
--      The student registers it — or another offered one of the programme — after activation, as before.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V342: JUPEB checking and acceptance, O''Level sittings, Non-Science, the statement of result, attendance', true);

-- ── 1 · the Bursary's two new fees, and the kinds of payment ─────────────────────────────────────
ALTER TABLE jupeb.fee_setting
    ADD COLUMN checking_fee   numeric(12,2) NOT NULL DEFAULT 1000 CHECK (checking_fee >= 0),
    ADD COLUMN acceptance_fee numeric(12,2) NOT NULL DEFAULT 15000 CHECK (acceptance_fee >= 0);
COMMENT ON COLUMN jupeb.fee_setting.checking_fee IS 'V342: the JUPEB admission status checking fee (default ₦1,000), paid once for the admission exercise';
COMMENT ON COLUMN jupeb.fee_setting.acceptance_fee IS 'V342: the JUPEB acceptance fee (default ₦15,000), paid by an admitted applicant before the acceptance letter';

ALTER TABLE jupeb.fee_reference DROP CONSTRAINT fee_reference_kind_check;
ALTER TABLE jupeb.fee_reference ADD CONSTRAINT fee_reference_kind_check
    CHECK (kind IN ('APPLICATION', 'STATUS_CHECKING', 'ACCEPTANCE', 'SCHOOL_FIRST', 'SCHOOL_SECOND', 'SCHOOL_FULL'));

/* when a kind of JUPEB fee was confirmed for a candidate — the payment record is the only authority */
CREATE OR REPLACE FUNCTION jupeb.paid_at(p_app uuid, p_kind text)
RETURNS timestamptz LANGUAGE sql STABLE AS $$
    SELECT min(confirmed_at) FROM jupeb.fee_reference WHERE application_id = p_app AND kind = p_kind AND confirmed_at IS NOT NULL
$$;

-- ── 2 · Non-Science ──────────────────────────────────────────────────────────────────────────────
ALTER TABLE jupeb.application DROP CONSTRAINT ck_jupeb_app_stream;
UPDATE jupeb.application SET stream = 'NON_SCIENCE' WHERE stream = 'ARTS';
ALTER TABLE jupeb.application ADD CONSTRAINT ck_jupeb_app_stream CHECK (stream IS NULL OR stream IN ('SCIENCE', 'NON_SCIENCE'));
COMMENT ON COLUMN jupeb.application.stream IS 'V341/V342: SCIENCE or NON_SCIENCE (V341 wrote ARTS for the latter; V342 carried those over), the applicant''s programme; decides the school fee and the combinations offered at subject registration';

CREATE OR REPLACE FUNCTION jupeb.combination_suits(p_area text, p_stream text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_stream IS NULL OR p_area IS NULL
        OR (p_stream = 'SCIENCE' AND p_area IN ('Science', 'Engineering'))
        OR (p_stream IN ('NON_SCIENCE', 'ARTS') AND p_area NOT IN ('Science', 'Engineering'))
$$;

/* V342: a combination is offered while it and its three subjects are active (the JUPEB Office disables what is not offered) */
CREATE OR REPLACE FUNCTION jupeb.combination_offered(p_combination uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT c.active AND s1.active AND s2.active AND s3.active
                       FROM jupeb.combination c
                       JOIN jupeb.subject s1 ON s1.id = c.subject1 JOIN jupeb.subject s2 ON s2.id = c.subject2 JOIN jupeb.subject s3 ON s3.id = c.subject3
                      WHERE c.id = p_combination), false)
$$;

CREATE OR REPLACE FUNCTION jupeb.school_fees(p_app uuid)
RETURNS TABLE (category text, indigene boolean, total numeric, first_percent numeric, first_amount numeric, second_amount numeric,
               allow_full boolean, first_paid boolean, second_paid boolean, full_paid boolean, paid numeric, outstanding numeric, status text, frozen boolean)
LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT * FROM jupeb.application WHERE id = p_app),
    fs AS (SELECT f.* FROM a CROSS JOIN LATERAL jupeb.fee_setting_of(a.session) f),
    c AS (SELECT coalesce(a.fee_category, CASE WHEN a.stream = 'SCIENCE' THEN 'SCIENCE' WHEN a.stream IN ('NON_SCIENCE', 'ARTS') THEN 'OTHER' END,
                          jupeb.category_of(a.programme_code)) AS category,
                 coalesce(a.indigene, upper(btrim(coalesce(a.state_of_origin, ''))) = upper(btrim(fs.indigene_state))) AS indigene,
                 a.school_fee_total IS NOT NULL AS frozen, coalesce(a.first_percent, fs.first_percent) AS pct, fs.allow_full,
                 a.session, a.school_fee_total
            FROM a, fs),
    t AS (SELECT c.*, coalesce(c.school_fee_total, jupeb.school_fee_amount(c.session, c.category, c.indigene)) AS total FROM c),
    p AS (SELECT coalesce(bool_or(kind = 'SCHOOL_FIRST' AND confirmed_at IS NOT NULL), false) AS f1,
                 coalesce(bool_or(kind = 'SCHOOL_SECOND' AND confirmed_at IS NOT NULL), false) AS f2,
                 coalesce(bool_or(kind = 'SCHOOL_FULL' AND confirmed_at IS NOT NULL), false) AS ff,
                 coalesce(sum(amount) FILTER (WHERE kind LIKE 'SCHOOL_%' AND confirmed_at IS NOT NULL), 0) AS paid
            FROM jupeb.fee_reference WHERE application_id = p_app)
    SELECT t.category, t.indigene, t.total, t.pct,
           round(t.total * t.pct / 100, 2), t.total - round(t.total * t.pct / 100, 2), t.allow_full,
           p.f1 OR p.ff, p.f2 OR p.ff, p.ff, p.paid, greatest(coalesce(t.total, 0) - p.paid, 0),
           CASE WHEN t.total IS NULL THEN 'NOT_SET' WHEN p.paid >= t.total THEN 'PAID' WHEN p.paid > 0 THEN 'PARTIALLY_PAID' ELSE 'NOT_PAID' END,
           t.frozen
      FROM t, p
$$;

/* the public application: Non-Science in the place of Arts (an ARTS from an older page is read as Non-Science) */
CREATE OR REPLACE FUNCTION jupeb.apply(p jsonb)
RETURNS TABLE (application_id uuid, application_no text, reference text, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE v_session text := jupeb.current_session(); v_acc uuid; v_app uuid; v_no text; v_ref text; st jupeb.setting;
        v_stream text := replace(replace(upper(btrim(coalesce(p->>'stream', ''))), '-', '_'), ' ', '_');
BEGIN
    IF v_stream = 'ARTS' THEN v_stream := 'NON_SCIENCE'; END IF;
    IF v_session IS NULL THEN RAISE EXCEPTION 'JUPEB_NO_SESSION: no academic session is on the calendar' USING ERRCODE = '23514'; END IF;
    IF v_stream NOT IN ('SCIENCE', 'NON_SCIENCE') THEN RAISE EXCEPTION 'JUPEB_STREAM: choose Science or Non-Science' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM jupeb.account x WHERE lower(x.email) = lower(btrim(p->>'email'))) THEN
        RAISE EXCEPTION 'JUPEB_APP_EXISTS: a JUPEB application already exists for this email' USING ERRCODE = '23514',
            HINT = 'Sign in with this email to continue it; forgotten your password? Reset it from the sign-in page.';
    END IF;
    INSERT INTO jupeb.account (email, password_hash) VALUES (lower(btrim(p->>'email')), p->>'passwordHash') RETURNING id INTO v_acc;
    st := jupeb.setting_of(v_session);
    v_no := st.application_prefix || '/' || substr(v_session, 1, 4) || '/' || lpad(platform.next_number('JUPEB_APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0');
    INSERT INTO jupeb.application (account_id, session, application_no, surname, first_name, middle_name, sex, date_of_birth, nin, email, phone, stream)
    VALUES (v_acc, v_session, v_no, upper(btrim(p->>'surname')), btrim(p->>'firstName'), nullif(btrim(coalesce(p->>'middleName', '')), ''),
            nullif(upper(left(btrim(coalesce(p->>'sex', '')), 1)), ''),
            CASE WHEN coalesce(p->>'dob', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p->>'dob')::date END,
            nullif(btrim(coalesce(p->>'nin', '')), ''), lower(btrim(p->>'email')), nullif(btrim(coalesce(p->>'phone', '')), ''), v_stream)
    RETURNING id INTO v_app;
    v_ref := jupeb.new_fee_reference(v_app, 'APPLICATION');
    RETURN QUERY SELECT v_app, v_no, v_ref, (SELECT fr.amount FROM jupeb.fee_reference fr WHERE fr.reference = v_ref);
END $$;

-- ── 3 · O'Level sittings, each with its own document ─────────────────────────────────────────────
ALTER TABLE jupeb.application ADD COLUMN olevel_sittings int NULL CHECK (olevel_sittings IS NULL OR olevel_sittings IN (1, 2));
COMMENT ON COLUMN jupeb.application.olevel_sittings IS 'V342: the number of O''Level sittings the applicant declares (one or two); each needs its own result and its own document';
UPDATE jupeb.application a SET olevel_sittings = (SELECT count(DISTINCT o.sitting) FROM jupeb.olevel o WHERE o.application_id = a.id)
 WHERE EXISTS (SELECT 1 FROM jupeb.olevel o WHERE o.application_id = a.id);

ALTER TABLE jupeb.document
    ADD COLUMN sitting   int NULL CHECK (sitting IS NULL OR sitting IN (1, 2)),
    ADD COLUMN exam_body text NULL,
    ADD COLUMN exam_year int NULL CHECK (exam_year IS NULL OR exam_year BETWEEN 1970 AND 2100);
UPDATE jupeb.document d SET sitting = 1,
       exam_body = (SELECT o.exam_type FROM jupeb.olevel o WHERE o.application_id = d.application_id AND o.sitting = 1 LIMIT 1),
       exam_year = (SELECT o.exam_year FROM jupeb.olevel o WHERE o.application_id = d.application_id AND o.sitting = 1 LIMIT 1)
 WHERE d.kind = 'OLEVEL_RESULT' AND d.sitting IS NULL;
ALTER TABLE jupeb.document ADD CONSTRAINT ck_jupeb_document_sitting CHECK ((kind = 'OLEVEL_RESULT') = (sitting IS NOT NULL));
ALTER TABLE jupeb.document DROP CONSTRAINT uq_jupeb_document;
CREATE UNIQUE INDEX ux_jupeb_document ON jupeb.document (application_id, kind, (coalesce(sitting, 0)));
COMMENT ON COLUMN jupeb.document.sitting IS 'V342: for an O''Level result, the sitting it belongs to — each sitting its own document, never merged';

/* the documents an application needs: every active required kind, the O'Level result once for each declared sitting */
CREATE OR REPLACE FUNCTION jupeb.required_documents(p_app uuid)
RETURNS TABLE (kind text, sitting int, label text, ord int)
LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT a.id, greatest(coalesce(a.olevel_sittings, (SELECT count(DISTINCT o.sitting) FROM jupeb.olevel o WHERE o.application_id = a.id)::int), 1) AS n
                 FROM jupeb.application a WHERE a.id = p_app)
    SELECT k.code, s.sitting, CASE WHEN k.code = 'OLEVEL_RESULT' THEN k.label || CASE s.sitting WHEN 1 THEN ' — first sitting' ELSE ' — second sitting' END ELSE k.label END, k.ord
      FROM jupeb.document_kind k CROSS JOIN a
      CROSS JOIN LATERAL (SELECT generate_series(1, a.n) AS sitting WHERE k.code = 'OLEVEL_RESULT'
                          UNION ALL SELECT NULL::int WHERE k.code <> 'OLEVEL_RESULT') s
     WHERE k.active AND k.required
$$;

/* five credits including English and Mathematics in the combined result, in the sittings declared (at most two), each
   sitting complete (examination body, number and year) and no result entered twice */
CREATE OR REPLACE FUNCTION jupeb.olevel_check(p_app uuid)
RETURNS TABLE (credits int, english boolean, mathematics boolean, sittings int, ok boolean, reasons text[])
LANGUAGE sql STABLE AS $$
    WITH best AS (
        SELECT upper(btrim(subject)) AS subject, bool_or(grade IN ('A1', 'B2', 'B3', 'C4', 'C5', 'C6')) AS credit
          FROM jupeb.olevel WHERE application_id = p_app GROUP BY upper(btrim(subject))
    ), per AS (
        SELECT sitting, count(DISTINCT exam_type) AS bodies, count(DISTINCT coalesce(exam_number, '')) AS numbers, count(DISTINCT coalesce(exam_year, 0)) AS years,
               bool_or(exam_number IS NULL OR btrim(exam_number) = '') AS no_number, bool_or(exam_year IS NULL) AS no_year,
               max(exam_type) AS body, max(upper(btrim(coalesce(exam_number, '')))) AS number
          FROM jupeb.olevel WHERE application_id = p_app GROUP BY sitting
    ), s AS (SELECT count(*)::int AS n, coalesce(bool_or(no_number), false) AS no_number, coalesce(bool_or(no_year), false) AS no_year,
                    coalesce(bool_or(bodies > 1 OR numbers > 1 OR years > 1), false) AS mixed,
                    count(*) = 2 AND count(DISTINCT body || '|' || number) = 1 AS twice
               FROM per),
    d AS (SELECT a.olevel_sittings AS declared FROM jupeb.application a WHERE a.id = p_app),
    x AS (SELECT count(*) FILTER (WHERE credit)::int AS credits,
                 coalesce(bool_or(credit) FILTER (WHERE subject ~ '^ENGLISH'), false) AS eng,
                 coalesce(bool_or(credit) FILTER (WHERE subject ~ '^(MATHEMATICS|MATHS|GENERAL MATHEMATICS)'), false) AS maths
            FROM best),
    r AS (SELECT array_remove(ARRAY[
                CASE WHEN s.n = 0 THEN 'no O''Level result entered' END,
                CASE WHEN d.declared IS NOT NULL AND s.n > 0 AND s.n <> d.declared
                     THEN 'you declared ' || CASE d.declared WHEN 1 THEN 'one sitting' ELSE 'two sittings' END || ' but entered results for ' || CASE s.n WHEN 1 THEN 'one' ELSE 'two' END END,
                CASE WHEN s.no_number THEN 'each sitting needs its examination number' END,
                CASE WHEN s.no_year THEN 'each sitting needs its examination year' END,
                CASE WHEN s.mixed THEN 'every subject of a sitting has the same examination body, number and year' END,
                CASE WHEN s.twice THEN 'the two sittings are the same result' END,
                CASE WHEN s.n > 0 AND x.credits < 5 THEN 'fewer than five credits (' || x.credits || ')' END,
                CASE WHEN s.n > 0 AND NOT x.eng THEN 'no credit in English Language' END,
                CASE WHEN s.n > 0 AND NOT x.maths THEN 'no credit in Mathematics' END], NULL) AS reasons
            FROM s, x, d)
    SELECT x.credits, x.eng, x.maths, s.n, cardinality(r.reasons) = 0 AND s.n BETWEEN 1 AND 2, r.reasons
      FROM x, s, r
$$;

/* the guided application: each step, whether it is complete, and what to correct, field by field */
CREATE OR REPLACE FUNCTION jupeb.step_status(p_app uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT * FROM jupeb.application WHERE id = p_app),
    personal AS (SELECT coalesce(jsonb_agg(p) FILTER (WHERE p IS NOT NULL), '[]'::jsonb) AS problems FROM a, LATERAL unnest(ARRAY[
        CASE WHEN a.sex IS NULL THEN jsonb_build_object('field', 'sex', 'message', 'Sex is required') END,
        CASE WHEN a.date_of_birth IS NULL THEN jsonb_build_object('field', 'dob', 'message', 'Date of birth is required') END,
        CASE WHEN a.nin IS NULL THEN jsonb_build_object('field', 'nin', 'message', 'NIN is required: the eleven digits on your NIN slip') END,
        CASE WHEN a.phone IS NULL THEN jsonb_build_object('field', 'phone', 'message', 'Phone number is required') END,
        CASE WHEN a.state_of_origin IS NULL THEN jsonb_build_object('field', 'stateOfOrigin', 'message', 'State of origin is required') END,
        CASE WHEN a.lga IS NULL THEN jsonb_build_object('field', 'lga', 'message', 'Local government is required') END,
        CASE WHEN a.contact_address IS NULL THEN jsonb_build_object('field', 'contactAddress', 'message', 'Contact address is required') END,
        CASE WHEN a.next_of_kin_name IS NULL THEN jsonb_build_object('field', 'nextOfKinName', 'message', 'Next of kin''s name is required') END,
        CASE WHEN a.next_of_kin_phone IS NULL THEN jsonb_build_object('field', 'nextOfKinPhone', 'message', 'Next of kin''s phone is required') END]) p),
    olevel AS (SELECT coalesce(jsonb_agg(jsonb_build_object('field', 'olevel', 'message', upper(left(r, 1)) || substr(r, 2))), '[]'::jsonb)
                      || CASE WHEN (SELECT olevel_sittings FROM a) IS NULL THEN jsonb_build_array(jsonb_build_object('field', 'olevelSittings', 'message', 'Say whether you sat once or twice')) ELSE '[]'::jsonb END AS problems
                 FROM jupeb.olevel_check(p_app) k, LATERAL unnest(k.reasons) r),
    docs AS (SELECT coalesce(jsonb_agg(jsonb_build_object('field', 'doc:' || q.kind || coalesce(':' || q.sitting, ''), 'message', q.label || ' is not uploaded') ORDER BY q.ord, q.sitting), '[]'::jsonb) AS problems
               FROM jupeb.required_documents(p_app) q
              WHERE NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = p_app AND d.kind = q.kind AND coalesce(d.sitting, 0) = coalesce(q.sitting, 0)
                                  AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED'))),
    prog AS (SELECT CASE WHEN a.stream IS NULL AND a.programme_code IS NULL THEN jsonb_build_array(jsonb_build_object('field', 'stream', 'message', 'Choose Science or Non-Science')) ELSE '[]'::jsonb END
                    || CASE
                        WHEN c.id IS NOT NULL AND NOT jupeb.combination_offered(c.id)
                            THEN jsonb_build_array(jsonb_build_object('field', 'combination', 'message', c.code || ' is no longer offered: choose another subject combination'))
                        WHEN c.id IS NOT NULL AND a.stream IS NOT NULL AND NOT jupeb.combination_suits(c.area, a.stream)
                            THEN jsonb_build_array(jsonb_build_object('field', 'combination', 'message', c.code || ' is not a ' || CASE a.stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END || ' combination: choose another'))
                        WHEN c.id IS NULL AND a.stream IS NOT NULL AND EXISTS (SELECT 1 FROM jupeb.combination o WHERE jupeb.combination_offered(o.id) AND jupeb.combination_suits(o.area, a.stream))
                            THEN jsonb_build_array(jsonb_build_object('field', 'combination', 'message', 'Choose your subject combination'))
                        ELSE '[]'::jsonb END AS problems
               FROM a LEFT JOIN jupeb.combination c ON c.id = a.combination_id),
    review AS (SELECT CASE WHEN a.fee_confirmed_at IS NULL THEN jsonb_build_array(jsonb_build_object('field', 'fee', 'message', 'The application fee is not yet paid')) ELSE '[]'::jsonb END AS problems FROM a),
    steps AS (SELECT 1 AS n, 'PERSONAL' AS step, problems FROM personal UNION ALL SELECT 2, 'OLEVEL', problems FROM olevel
              UNION ALL SELECT 3, 'DOCUMENTS', problems FROM docs UNION ALL SELECT 4, 'PROGRAMME', problems FROM prog UNION ALL SELECT 5, 'REVIEW', problems FROM review)
    SELECT jsonb_build_object(
        'steps', jsonb_agg(jsonb_build_object('step', step, 'ok', jsonb_array_length(problems) = 0, 'problems', problems) ORDER BY n),
        'current', coalesce((SELECT step FROM steps WHERE jsonb_array_length(problems) > 0 ORDER BY n LIMIT 1), 'REVIEW'),
        'complete', bool_and(jsonb_array_length(problems) = 0))
      FROM steps
$$;

CREATE OR REPLACE FUNCTION jupeb.missing(p_app uuid)
RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(p->>'message' ORDER BY s.n, p->>'field'), '{}')
      FROM jsonb_array_elements(jupeb.step_status(p_app)->'steps') WITH ORDINALITY s(step, n), jsonb_array_elements(s.step->'problems') p
$$;

-- ── 4 · admission status checking: the window, the fee once, the status ─────────────────────────
ALTER TABLE policy.portal_window DROP CONSTRAINT IF EXISTS portal_window_window_type_check;
ALTER TABLE policy.portal_window ADD CONSTRAINT portal_window_window_type_check
    CHECK (window_type IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION',
                           'POSTGRADUATE_APPLICATION', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING'));

CREATE OR REPLACE FUNCTION policy.window_state(p_type text, p_session text, p_semester integer)
RETURNS TABLE(configured boolean, state text, phase text, opens_at timestamptz, closes_at timestamptz, late_until timestamptz,
              late_fee_enabled boolean, forced text, reason text, window_id uuid, semester integer)
LANGUAGE sql STABLE AS $fn$
    WITH w AS (
        SELECT * FROM policy.portal_window
         WHERE window_type = p_type AND session = p_session AND superseded_at IS NULL
           AND (semester = p_semester OR semester IS NULL)
         ORDER BY (semester IS NOT NULL) DESC LIMIT 1)
    SELECT w.id IS NOT NULL,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING') THEN 'CLOSED' ELSE 'OPEN' END
                WHEN w.forced = 'CLOSED' THEN 'CLOSED'
                WHEN w.forced = 'OPEN' THEN 'OPEN'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'SCHEDULED'
                WHEN w.closes_at IS NULL OR now() <= w.closes_at THEN 'OPEN'
                WHEN w.late_until IS NOT NULL AND now() <= w.late_until THEN 'OPEN'
                ELSE 'EXPIRED' END,
           CASE WHEN w.id IS NULL THEN CASE WHEN p_type IN ('ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING') THEN 'NONE' ELSE 'NORMAL' END
                WHEN w.forced = 'OPEN' THEN CASE WHEN w.late_fee_enabled THEN 'LATE' ELSE 'NORMAL' END
                WHEN w.forced = 'CLOSED' THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at AND w.late_until IS NOT NULL AND now() <= w.late_until THEN 'LATE'
                WHEN w.opens_at IS NOT NULL AND now() < w.opens_at THEN 'NONE'
                WHEN w.closes_at IS NOT NULL AND now() > w.closes_at THEN 'NONE'
                ELSE 'NORMAL' END,
           w.opens_at, w.closes_at, w.late_until, coalesce(w.late_fee_enabled, false), w.forced, w.reason, w.id, w.semester
      FROM (SELECT 1) one LEFT JOIN w ON true
$fn$;

CREATE OR REPLACE FUNCTION policy.window_act(p_type text, p_session text, p_semester integer, p_action text,
                                             p_opens timestamptz, p_closes timestamptz, p_late_until timestamptz, p_late_fee boolean,
                                             p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE cur policy.portal_window; prev record; v_forced text; v_opens timestamptz; v_closes timestamptz; v_late timestamptz; v_fee boolean; v_id uuid; nxt record;
BEGIN
    IF p_type NOT IN ('SCHOOL_FEES_PAYMENT', 'COURSE_REGISTRATION', 'ADMISSION_STATUS_CHECKING', 'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION',
                      'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_APPLICATION', 'JUPEB_ADMISSION_STATUS_CHECKING') THEN
        RAISE EXCEPTION 'no such portal window %', p_type USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('ADMISSION_STATUS_CHECKING', 'POSTGRADUATE_ADMISSION_STATUS_CHECKING', 'JUPEB_ADMISSION_STATUS_CHECKING') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_CHECKING_SESSION: admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF p_type IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION') AND (p_semester IS NOT NULL OR p_late_until IS NOT NULL OR coalesce(p_late_fee, false)) THEN
        RAISE EXCEPTION 'WINDOW_APPLICATION_SESSION: an application window opens and closes for the whole admission exercise of a session, with no semester and no late period' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN RAISE EXCEPTION 'no academic session % on the calendar', p_session USING ERRCODE = '23503'; END IF;
    IF p_action NOT IN ('OPEN', 'CLOSE', 'REOPEN', 'SCHEDULE', 'EXTEND', 'SHORTEN', 'EDIT') THEN RAISE EXCEPTION 'unknown action %', p_action USING ERRCODE = '23514'; END IF;
    IF p_action IN ('CLOSE', 'REOPEN', 'SHORTEN') AND nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'the reason for % is recorded, and none was given', lower(p_action) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM policy.portal_window WHERE window_type = p_type AND session = p_session AND coalesce(semester, 0) = coalesce(p_semester, 0) AND superseded_at IS NULL FOR UPDATE;
    SELECT * INTO prev FROM policy.window_state(p_type, p_session, p_semester);
    v_opens := coalesce(p_opens, cur.opens_at); v_closes := coalesce(p_closes, cur.closes_at); v_late := coalesce(p_late_until, cur.late_until);
    v_fee := coalesce(p_late_fee, cur.late_fee_enabled, false);
    CASE p_action
        WHEN 'OPEN', 'REOPEN' THEN v_forced := CASE WHEN p_opens IS NULL AND p_closes IS NULL THEN 'OPEN' ELSE NULL END;
                                   IF p_opens IS NULL AND p_closes IS NOT NULL THEN v_opens := now(); END IF;
        WHEN 'CLOSE' THEN v_forced := 'CLOSED';
        WHEN 'SCHEDULE' THEN IF p_opens IS NULL THEN RAISE EXCEPTION 'a schedule names when the window opens' USING ERRCODE = '23514'; END IF; v_forced := NULL;
        WHEN 'EXTEND' THEN IF p_closes IS NULL AND p_late_until IS NULL THEN RAISE EXCEPTION 'an extension names the new closing' USING ERRCODE = '23514'; END IF;
                           IF cur.id IS NOT NULL AND p_closes IS NOT NULL AND cur.closes_at IS NOT NULL AND p_closes < cur.closes_at THEN RAISE EXCEPTION 'that closing is earlier than before; shorten the window instead' USING ERRCODE = '23514'; END IF;
                           v_forced := CASE WHEN cur.forced = 'CLOSED' THEN NULL ELSE cur.forced END;
        WHEN 'SHORTEN' THEN IF p_closes IS NULL THEN RAISE EXCEPTION 'a shortening names the new closing' USING ERRCODE = '23514'; END IF; v_forced := cur.forced;
        WHEN 'EDIT' THEN v_forced := cur.forced;
    END CASE;
    IF v_closes IS NOT NULL AND v_opens IS NOT NULL AND v_closes < v_opens THEN RAISE EXCEPTION 'the window closes before it opens' USING ERRCODE = '23514'; END IF;
    IF v_late IS NOT NULL AND v_closes IS NOT NULL AND v_late < v_closes THEN RAISE EXCEPTION 'the late period ends before the window closes' USING ERRCODE = '23514'; END IF;
    IF cur.id IS NOT NULL THEN UPDATE policy.portal_window SET superseded_at = now() WHERE id = cur.id; END IF;
    INSERT INTO policy.portal_window (window_type, session, semester, opens_at, closes_at, late_until, late_fee_enabled, forced, reason, created_by, created_office)
    VALUES (p_type, p_session, p_semester, v_opens, v_closes, v_late, v_fee, v_forced, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office)
    RETURNING id INTO v_id;
    SELECT * INTO nxt FROM policy.window_state(p_type, p_session, p_semester);
    INSERT INTO policy.portal_window_event (window_id, window_type, session, semester, action, previous_state, new_state, previous_opens_at, previous_closes_at, previous_late_until,
                                            new_opens_at, new_closes_at, new_late_until, late_fee_enabled, reason, actor, office)
    VALUES (v_id, p_type, p_session, p_semester, p_action, CASE WHEN prev.configured THEN prev.state ELSE prev.state || ' (default)' END, nxt.state, cur.opens_at, cur.closes_at, cur.late_until,
            v_opens, v_closes, v_late, v_fee, nullif(btrim(coalesce(p_reason, '')), ''), p_actor, p_office);
    RETURN v_id;
END $fn$;

/* the one evaluation of a JUPEB applicant's status checking: a valid (submitted) application, the window, the fee paid once,
   what may be done, and — only when it may be read — the status */
CREATE OR REPLACE FUNCTION jupeb.status_checking(p_app uuid)
RETURNS TABLE (valid boolean, window_state text, window_open boolean, paid boolean, paid_at timestamptz, may_pay boolean, may_check boolean,
               accepted boolean, status text)
LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT * FROM jupeb.application WHERE id = p_app),
    w AS (SELECT ws.state FROM a CROSS JOIN LATERAL policy.window_state('JUPEB_ADMISSION_STATUS_CHECKING', a.session, NULL) ws),
    v AS (SELECT a.state NOT IN ('DRAFT', 'WITHDRAWN') AND a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL AS valid,
                 jupeb.paid_at(a.id, 'STATUS_CHECKING') AS paid_at, jupeb.paid_at(a.id, 'ACCEPTANCE') IS NOT NULL AS accepted,
                 a.state IN ('STUDENT', 'COMPLETED') AS student, a.state
            FROM a)
    SELECT v.valid, w.state, w.state = 'OPEN', v.paid_at IS NOT NULL, v.paid_at,
           v.valid AND w.state = 'OPEN' AND v.paid_at IS NULL,
           v.valid AND ((v.paid_at IS NOT NULL AND w.state = 'OPEN') OR v.accepted OR v.student),
           v.accepted,
           CASE WHEN v.valid AND ((v.paid_at IS NOT NULL AND w.state = 'OPEN') OR v.accepted OR v.student) THEN
                CASE WHEN v.state IN ('ADMITTED', 'STUDENT', 'COMPLETED') THEN 'ADMITTED'
                     WHEN v.state IN ('NOT_ADMITTED', 'INELIGIBLE') THEN 'NOT_ADMITTED'
                     WHEN v.state = 'PENDING' THEN 'PENDING'
                     WHEN v.state = 'RETURNED' THEN 'REQUIRES_REVIEW'
                     ELSE 'PROCESSING' END END
      FROM v, w
$$;
COMMENT ON FUNCTION jupeb.status_checking(uuid) IS
  'V342: a JUPEB applicant''s admission status checking — a submitted application may pay the checking fee once while the Director of ICT has '
  'JUPEB_ADMISSION_STATUS_CHECKING open, and then reads the status (ADMITTED, NOT_ADMITTED, PENDING, PROCESSING, REQUIRES_REVIEW); an applicant who has '
  'accepted, or is a student, reads it whatever the window. The entitlement is the confirmed STATUS_CHECKING fee reference.';

-- ── 5 · the fees: checking and acceptance join the application and school fees ───────────────────
CREATE OR REPLACE FUNCTION jupeb.new_fee_reference(p_app uuid, p_kind text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; fs jupeb.fee_setting; st jupeb.setting; sf record; ck record; v_amt numeric; v_ref text; v_sem int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    fs := jupeb.fee_setting_of(a.session);
    IF p_kind = 'APPLICATION' THEN
        IF a.fee_confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the application fee is already paid' USING ERRCODE = '23514'; END IF;
        v_amt := fs.application_fee;
    ELSIF p_kind = 'STATUS_CHECKING' THEN
        SELECT * INTO ck FROM jupeb.status_checking(p_app);
        IF ck.paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the status checking fee is already paid; check your status' USING ERRCODE = '23514'; END IF;
        IF NOT ck.valid THEN RAISE EXCEPTION 'JUPEB_CHECKING_NOT_VALID: status checking is for a submitted application' USING ERRCODE = '23514',
            HINT = 'Complete and submit your application first.'; END IF;
        IF NOT ck.window_open THEN RAISE EXCEPTION 'JUPEB_CHECKING_CLOSED: admission status checking is %', lower(ck.window_state) USING ERRCODE = '23514',
            HINT = 'Watch the University''s website and this portal: the Directorate of ICT opens admission status checking.'; END IF;
        v_amt := fs.checking_fee;
    ELSIF p_kind = 'ACCEPTANCE' THEN
        SELECT * INTO ck FROM jupeb.status_checking(p_app);
        IF ck.accepted THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the acceptance fee is already paid' USING ERRCODE = '23514'; END IF;
        IF NOT ck.may_check OR coalesce(ck.status, '') <> 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_ACCEPTANCE_NOT_YET: the acceptance fee is paid once your admission status shows you admitted' USING ERRCODE = '23514',
                HINT = 'Check your admission status first.';
        END IF;
        v_amt := fs.acceptance_fee;
    ELSIF p_kind IN ('SCHOOL_FIRST', 'SCHOOL_SECOND', 'SCHOOL_FULL') THEN
        IF a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED') THEN
            RAISE EXCEPTION 'JUPEB_FEES_NOT_YET: school fees are paid once you are admitted' USING ERRCODE = '23514';
        END IF;
        IF a.state = 'ADMITTED' AND jupeb.paid_at(p_app, 'ACCEPTANCE') IS NULL THEN
            RAISE EXCEPTION 'JUPEB_ACCEPTANCE_FIRST: pay the acceptance fee first; school fees follow it' USING ERRCODE = '23514';
        END IF;
        st := jupeb.setting_of(a.session);
        IF st.screening_required AND coalesce(a.screening_state, '') <> 'CLEARED' AND a.state = 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_SCREENING_FIRST: school fees open once you are cleared at screening' USING ERRCODE = '23514',
                HINT = 'Attend the screening shown on your JUPEB portal.';
        END IF;
        -- the fee is frozen on the candidate the first time it is charged: a later change by the Bursary does not rewrite it
        IF a.school_fee_total IS NULL THEN
            SELECT * INTO sf FROM jupeb.school_fees(p_app);
            IF sf.total IS NULL THEN
                RAISE EXCEPTION 'JUPEB_FEE_NOT_SET: the Bursary has not stated the JUPEB school fee for %', a.session USING ERRCODE = '23514';
            END IF;
            UPDATE jupeb.application SET school_fee_total = sf.total, fee_category = sf.category, indigene = sf.indigene, first_percent = sf.first_percent
             WHERE id = p_app;
        END IF;
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF p_kind = 'SCHOOL_FIRST' THEN
            IF sf.first_paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the first semester''s share is already paid' USING ERRCODE = '23514'; END IF;
            v_amt := sf.first_amount; v_sem := 1;
        ELSIF p_kind = 'SCHOOL_SECOND' THEN
            IF NOT sf.first_paid THEN RAISE EXCEPTION 'JUPEB_FEE_ORDER: the first semester''s share is paid first' USING ERRCODE = '23514'; END IF;
            IF sf.second_paid THEN RAISE EXCEPTION 'JUPEB_FEE_PAID: the second semester''s share is already paid' USING ERRCODE = '23514'; END IF;
            v_amt := sf.second_amount; v_sem := 2;
        ELSE
            IF NOT sf.allow_full THEN RAISE EXCEPTION 'JUPEB_FULL_NOT_ALLOWED: the Bursary takes the school fee in two instalments' USING ERRCODE = '23514'; END IF;
            IF sf.paid > 0 THEN RAISE EXCEPTION 'JUPEB_FEE_ORDER: part of the fee is paid; pay the remaining instalment' USING ERRCODE = '23514'; END IF;
            v_amt := sf.total;
        END IF;
    ELSE
        RAISE EXCEPTION 'JUPEB_FEE_KIND: unknown JUPEB fee %', p_kind USING ERRCODE = '23514';
    END IF;
    IF v_amt IS NULL OR v_amt <= 0 THEN RAISE EXCEPTION 'JUPEB_FEE_NOT_SET: the Bursary has not stated this fee' USING ERRCODE = '23514'; END IF;
    SELECT fr.reference INTO v_ref FROM jupeb.fee_reference fr
     WHERE fr.application_id = p_app AND fr.kind = p_kind AND fr.confirmed_at IS NULL AND fr.expires_at > now() AND fr.amount = v_amt
     ORDER BY fr.created_at DESC LIMIT 1;
    IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    v_ref := 'MOAUM-JUPEB' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'STATUS_CHECKING' THEN 'CHK' WHEN 'ACCEPTANCE' THEN 'ACC'
                                         WHEN 'SCHOOL_FIRST' THEN 'SF1' WHEN 'SCHOOL_SECOND' THEN 'SF2' ELSE 'SFF' END
             /* V342: the session's year is in the reference — the count restarts each session, and V339's references
                (MOAUM-JUPEBAPP-000001) would otherwise collide with the next session's */
             || '-' || substr(a.session, 1, 4) || '-' || lpad(platform.next_number('JUPEB_FEEREF', 'UNIVERSITY', a.session)::text, 6, '0');
    INSERT INTO jupeb.fee_reference (application_id, kind, reference, amount, session, semester, expires_at)
    VALUES (p_app, p_kind, v_ref, v_amt, a.session, v_sem, now() + interval '24 hours');
    RETURN v_ref;
END $$;

CREATE OR REPLACE FUNCTION jupeb.confirm_fee(p_reference text, p_channel text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE fr jupeb.fee_reference;
BEGIN
    UPDATE jupeb.fee_reference SET confirmed_at = now(), channel = coalesce(nullif(btrim(coalesce(p_channel, '')), ''), 'bank')
     WHERE upper(reference) = upper(btrim(coalesce(p_reference, ''))) AND confirmed_at IS NULL
    RETURNING * INTO fr;
    IF fr.id IS NULL THEN RETURN 'already confirmed'; END IF;
    IF fr.kind = 'APPLICATION' THEN
        UPDATE jupeb.application SET fee_confirmed_at = coalesce(fee_confirmed_at, now()) WHERE id = fr.application_id;
    ELSIF fr.kind = 'STATUS_CHECKING' THEN
        PERFORM jupeb.app_event(fr.application_id, 'STATUS_CHECKING_CONFIRMED', 'Admission status checking fee confirmed · ₦' || to_char(fr.amount, 'FM999,999,990.00') || ' · ' || fr.reference);
        PERFORM jupeb.tell(fr.application_id, 'Your JUPEB status checking fee is confirmed', 'Your admission status checking fee is confirmed. Sign in to the JUPEB portal to check your admission status.');
    ELSIF fr.kind = 'ACCEPTANCE' THEN
        PERFORM jupeb.app_event(fr.application_id, 'ACCEPTANCE_CONFIRMED', 'Acceptance fee confirmed · ₦' || to_char(fr.amount, 'FM999,999,990.00') || ' · ' || fr.reference);
        PERFORM jupeb.tell(fr.application_id, 'Your JUPEB admission is accepted', 'Your acceptance fee is confirmed and your acceptance letter is on the JUPEB portal. Your school fees are next.');
    ELSE
        PERFORM jupeb.app_event(fr.application_id, 'SCHOOL_FEE_CONFIRMED', CASE fr.kind WHEN 'SCHOOL_FIRST' THEN 'First semester school fee' WHEN 'SCHOOL_SECOND' THEN 'Second semester school fee' ELSE 'Full school fee' END
            || ' confirmed · ₦' || to_char(fr.amount, 'FM999,999,990.00') || ' · ' || fr.reference);
        PERFORM jupeb.tell(fr.application_id, 'Your JUPEB school fee payment is confirmed', 'We confirm your payment of ₦' || to_char(fr.amount, 'FM999,999,990.00') || ' (' || fr.reference || '). Your receipt is on the JUPEB portal.');
        PERFORM jupeb.activate_if_due(fr.application_id);
    END IF;
    RETURN 'confirmed';
END $$;

/* an admission with an acceptance or a school fee paid against it is not withdrawn here */
CREATE OR REPLACE FUNCTION jupeb.decide_admission(p_app uuid, p_decision text, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v text := upper(btrim(coalesce(p_decision, ''))); sf record; st jupeb.setting;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    IF v NOT IN ('ADMITTED', 'NOT_ADMITTED', 'PENDING') THEN RAISE EXCEPTION 'JUPEB_DECISION: admitted, not admitted or pending' USING ERRCODE = '23514'; END IF;
    IF a.state NOT IN ('ELIGIBLE', 'PENDING', 'NOT_ADMITTED', 'ADMITTED') THEN
        RAISE EXCEPTION 'JUPEB_STATE: admission is decided on an eligible application; this one is %', lower(a.state) USING ERRCODE = '23514',
            HINT = 'Mark the application eligible first.';
    END IF;
    IF a.state = 'ADMITTED' AND v <> 'ADMITTED' THEN
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF sf.paid > 0 OR jupeb.paid_at(p_app, 'ACCEPTANCE') IS NOT NULL THEN
            RAISE EXCEPTION 'JUPEB_ADMISSION_PAID: the admission is accepted or a school fee is paid against it; it is not withdrawn here' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF v = a.state THEN RETURN v; END IF;
    st := jupeb.setting_of(a.session);
    UPDATE jupeb.application
       SET state = v, admission_note = nullif(btrim(coalesce(p_note, '')), ''), admission_decided_at = now(), admission_decided_by = p_actor,
           admission_ref = CASE WHEN v = 'ADMITTED' AND admission_ref IS NULL
                                THEN 'JUPEB/ADM/' || substr(a.session, 1, 4) || '/' || lpad(platform.next_number('JUPEB_ADMISSION', 'UNIVERSITY', a.session)::text, 5, '0')
                                ELSE admission_ref END,
           screening_state = CASE WHEN v = 'ADMITTED' AND st.screening_required AND screening_state IS NULL THEN 'PENDING' ELSE screening_state END,
           screening_venue = CASE WHEN v = 'ADMITTED' AND st.screening_required AND screening_venue IS NULL THEN st.screening_venue ELSE screening_venue END
     WHERE id = p_app;
    RETURN v;
END $$;

CREATE OR REPLACE FUNCTION jupeb.bulk_admission(p_ids uuid[], p_decision text, p_note text, p_actor uuid, p_commit boolean)
RETURNS TABLE (application_id uuid, application_no text, name text, state text, ok boolean, reason text)
LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v text := upper(btrim(coalesce(p_decision, ''))); v_ok boolean; v_reason text;
BEGIN
    IF v NOT IN ('ADMITTED', 'NOT_ADMITTED', 'PENDING') THEN RAISE EXCEPTION 'JUPEB_DECISION: admitted, not admitted or pending' USING ERRCODE = '23514'; END IF;
    IF cardinality(coalesce(p_ids, '{}')) > 2000 THEN RAISE EXCEPTION 'JUPEB_BULK_LIMIT: at most 2,000 applications at once' USING ERRCODE = '23514'; END IF;
    FOR a IN SELECT * FROM jupeb.application x WHERE x.id = ANY(p_ids) ORDER BY x.application_no LOOP
        v_ok := a.state IN ('ELIGIBLE', 'PENDING', 'NOT_ADMITTED', 'ADMITTED') AND a.state <> v;
        v_reason := CASE WHEN a.state = v THEN 'Already ' || lower(replace(v, '_', ' '))
                         WHEN NOT v_ok THEN 'Not eligible for an admission decision (' || lower(a.state) || ')' END;
        IF v_ok AND a.state = 'ADMITTED' AND ((SELECT sf.paid FROM jupeb.school_fees(a.id) sf) > 0 OR jupeb.paid_at(a.id, 'ACCEPTANCE') IS NOT NULL) THEN
            v_ok := false; v_reason := 'The admission is accepted or a school fee is paid against it';
        END IF;
        IF v_ok AND p_commit THEN PERFORM jupeb.decide_admission(a.id, v, p_note, p_actor); END IF;
        application_id := a.id; application_no := a.application_no; name := a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '');
        state := a.state; ok := v_ok; reason := v_reason;
        RETURN NEXT;
    END LOOP;
END $$;

/* the trail: a decision is announced without saying what it is — the applicant reads it by checking their status */
CREATE OR REPLACE FUNCTION jupeb.application_trail()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_fee numeric;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM jupeb.app_event(NEW.id, 'CREATED', 'Application started for ' || NEW.session);
        v_fee := (jupeb.fee_setting_of(NEW.session)).application_fee;
        PERFORM jupeb.tell(NEW.id, 'Your JUPEB application is started',
            'Your JUPEB application for the ' || NEW.session || ' session is started and numbered. Sign in to the JUPEB portal with your email or application number, '
            || 'pay the application fee of ₦' || coalesce(to_char(v_fee, 'FM999,999,990'), '') || ', complete your biodata, enter your O''Level results, upload your documents and submit.');
        RETURN NEW;
    END IF;
    IF NEW.state IS DISTINCT FROM OLD.state THEN
        PERFORM jupeb.app_event(NEW.id, NEW.state, CASE NEW.state
            WHEN 'SUBMITTED'    THEN CASE WHEN OLD.state = 'RETURNED' THEN 'Corrected and resubmitted' ELSE 'Application submitted' END
            WHEN 'RETURNED'     THEN 'Returned for correction — ' || coalesce(NEW.return_note, '')
            WHEN 'ELIGIBLE'     THEN 'Found eligible' || coalesce(' — ' || NEW.eligibility_note, '')
            WHEN 'INELIGIBLE'   THEN 'Found not eligible — ' || coalesce(NEW.eligibility_note, '')
            WHEN 'ADMITTED'     THEN 'Admitted · ' || coalesce(NEW.admission_ref, '') || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'NOT_ADMITTED' THEN 'Not admitted' || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'PENDING'      THEN 'Admission decision pending' || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'STUDENT'      THEN 'Activated as a JUPEB student'
            WHEN 'COMPLETED'    THEN 'Results published'
            ELSE NEW.state END);
        IF NEW.state = 'SUBMITTED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB application is submitted', 'Your application is submitted to the JUPEB Office for review. Follow it on the JUPEB portal.');
        ELSIF NEW.state = 'RETURNED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB application needs a correction', 'The JUPEB Office returned your application for correction: '
                || coalesce(NEW.return_note, '') || ' Sign in, make the correction and submit it again.');
        ELSIF NEW.state IN ('ADMITTED', 'NOT_ADMITTED') THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB admission status is ready to check', 'The JUPEB Office has considered your application. '
                || 'When admission status checking is open, sign in to the JUPEB portal to check your admission status.');
        ELSIF NEW.state = 'STUDENT' THEN
            PERFORM jupeb.tell(NEW.id, 'You are a JUPEB student', 'Your school fee payment is confirmed and your JUPEB studentship is active. Sign in to register your three subjects.');
        ELSIF NEW.state = 'COMPLETED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB results are published', 'Your JUPEB results are published on the JUPEB portal.');
        END IF;
    END IF;
    IF NEW.fee_confirmed_at IS NOT NULL AND OLD.fee_confirmed_at IS NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'APPLICATION_FEE_CONFIRMED', 'Application fee confirmed');
        PERFORM jupeb.tell(NEW.id, 'Your JUPEB application fee is confirmed', 'Your application fee is confirmed. Complete your biodata, O''Level results and documents, then submit.');
    END IF;
    IF NEW.subjects_registered_at IS NOT NULL AND OLD.subjects_registered_at IS NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'SUBJECTS_REGISTERED', 'The three subjects of the combination registered');
    END IF;
    IF NEW.exam_no IS DISTINCT FROM OLD.exam_no AND NEW.exam_no IS NOT NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'EXAM_NO_ASSIGNED', 'JUPEB examination number ' || NEW.exam_no || CASE WHEN OLD.exam_no IS NOT NULL THEN ' (was ' || OLD.exam_no || ')' ELSE '' END);
        PERFORM jupeb.tell(NEW.id, 'Your JUPEB examination number is assigned', 'Your official JUPEB examination number is ' || NEW.exam_no || '. It is on your JUPEB portal.');
    END IF;
    IF NEW.screening_state IS DISTINCT FROM OLD.screening_state AND NEW.screening_state IS NOT NULL THEN
        PERFORM jupeb.app_event(NEW.id, 'SCREENING_' || NEW.screening_state, coalesce(NEW.screening_reason, 'Screening ' || lower(replace(NEW.screening_state, '_', ' '))));
    END IF;
    NEW.updated_at := now();
    RETURN NEW;
END $$;

-- ── 6 · the statement of result: X, Q and W; the grade point out of 16; the examination month; the course units ─────
ALTER TABLE jupeb.result DROP CONSTRAINT result_grade_check;
ALTER TABLE jupeb.result ADD CONSTRAINT result_grade_check CHECK (grade IN ('A', 'B', 'C', 'D', 'E', 'F', 'X', 'Q', 'W'));
COMMENT ON COLUMN jupeb.result.grade IS 'V339/V342: A (70–100, 5 points), B (60–69, 4), C (50–59, 3), D (45–49, 2), E (40–44, 1), F (0–39, 0); X absent, Q cancelled, W withheld (0 points, not a pass)';

CREATE OR REPLACE FUNCTION jupeb.grade_points(p_grade text)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(btrim(p_grade)) WHEN 'A' THEN 5 WHEN 'B' THEN 4 WHEN 'C' THEN 3 WHEN 'D' THEN 2 WHEN 'E' THEN 1
                                       WHEN 'F' THEN 0 WHEN 'X' THEN 0 WHEN 'Q' THEN 0 WHEN 'W' THEN 0 END::numeric
$$;

/* the grade point as the statement prints it: the points of the registered subjects, one point more when all are passed (A–E), out of 5 a subject and the one */
CREATE OR REPLACE FUNCTION jupeb.grade_point(p_app uuid)
RETURNS TABLE (points numeric, bonus int, total numeric, out_of int, graded int, registered int, passed_all boolean)
LANGUAGE sql STABLE AS $$
    WITH r AS (SELECT sr.subject_id, x.grade, x.points FROM jupeb.subject_registration sr
                 LEFT JOIN jupeb.result x ON x.application_id = sr.application_id AND x.subject_id = sr.subject_id
                WHERE sr.application_id = p_app)
    SELECT coalesce(sum(points), 0), CASE WHEN count(*) > 0 AND bool_and(grade IN ('A', 'B', 'C', 'D', 'E')) THEN 1 ELSE 0 END,
           coalesce(sum(points), 0) + CASE WHEN count(*) > 0 AND bool_and(grade IN ('A', 'B', 'C', 'D', 'E')) THEN 1 ELSE 0 END,
           (count(*) * 5 + 1)::int, count(grade)::int, count(*)::int, count(*) > 0 AND coalesce(bool_and(grade IN ('A', 'B', 'C', 'D', 'E')), false)
      FROM r
$$;

ALTER TABLE jupeb.setting ADD COLUMN exam_month text NULL CHECK (exam_month IS NULL OR length(btrim(exam_month)) BETWEEN 4 AND 40);
COMMENT ON COLUMN jupeb.setting.exam_month IS 'V342: the JUPEB examination''s month and year as the statement of result prints it (e.g. AUGUST 2026)';

CREATE TABLE jupeb.subject_unit (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    subject_id uuid NOT NULL REFERENCES jupeb.subject(id),
    code       text NOT NULL CHECK (code ~ '^[A-Z]{2,5} ?[0-9]{3}$'),
    title      text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 160),
    ord        int NOT NULL DEFAULT 1,
    CONSTRAINT uq_jupeb_subject_unit UNIQUE (subject_id, code)
);
SELECT audit.attach('jupeb.subject_unit');
COMMENT ON TABLE jupeb.subject_unit IS 'V342: the course units a JUPEB subject is taught in (BIO 001: General Biology …), printed in the note of the statement of result';
GRANT SELECT ON jupeb.subject_unit TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.subject_unit TO app_admissions;

/* results: X, Q and W are grades too */
CREATE OR REPLACE FUNCTION jupeb.import_results(p_rows jsonb, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; a jupeb.application; s jupeb.subject; v_key text; v_grade text; v_old text; v_status text; v_msg text; v_pair text;
        n_invalid int := 0; n_new int := 0; n_fix int := 0; n_same int := 0; v_ref text; seen text[] := '{}'; applied int := 0;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('jupeb.results'));
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_key := upper(regexp_replace(btrim(coalesce(nullif(r->>'examNo', ''), r->>'applicationNo', '')), '\s+', '', 'g'));
        v_grade := upper(btrim(coalesce(r->>'grade', '')));
        v_status := NULL; v_msg := NULL; v_old := NULL;
        SELECT * INTO a FROM jupeb.application x WHERE upper(x.exam_no) = v_key OR upper(x.application_no) = v_key ORDER BY (upper(x.exam_no) = v_key) DESC NULLS LAST LIMIT 1;
        SELECT * INTO s FROM jupeb.subject x WHERE upper(x.code) = upper(btrim(coalesce(r->>'subject', ''))) OR upper(x.title) = upper(btrim(coalesce(r->>'subject', ''))) LIMIT 1;
        v_pair := coalesce(a.id::text, v_key) || '|' || coalesce(s.id::text, upper(btrim(coalesce(r->>'subject', ''))));
        IF v_key = '' THEN v_status := 'INVALID'; v_msg := 'No examination or application number';
        ELSIF a.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No JUPEB candidate ' || v_key;
        ELSIF s.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No JUPEB subject ' || coalesce(r->>'subject', '');
        ELSIF NOT EXISTS (SELECT 1 FROM jupeb.subject_registration sr WHERE sr.application_id = a.id AND sr.subject_id = s.id) THEN
            v_status := 'INVALID'; v_msg := s.title || ' is not one of the candidate''s registered subjects';
        ELSIF v_grade NOT IN ('A', 'B', 'C', 'D', 'E', 'F', 'X', 'Q', 'W') THEN v_status := 'INVALID'; v_msg := 'The grade is A to F, X (absent), Q (cancelled) or W (withheld), not ' || coalesce(nullif(v_grade, ''), 'blank');
        ELSIF v_pair = ANY(seen) THEN v_status := 'INVALID'; v_msg := 'The candidate''s ' || s.title || ' appears twice in the file';
        ELSE
            SELECT grade INTO v_old FROM jupeb.result WHERE application_id = a.id AND subject_id = s.id;
            IF v_old IS NULL THEN v_status := 'NEW'; v_msg := s.title || ': ' || v_grade;
            ELSIF v_old = v_grade THEN v_status := 'UNCHANGED'; v_msg := s.title || ' already ' || v_grade;
            ELSIF nullif(btrim(coalesce(r->>'reason', '')), '') IS NULL THEN v_status := 'INVALID'; v_msg := s.title || ' is already ' || v_old || '; a correction states its reason';
            ELSE v_status := 'CORRECTION'; v_msg := s.title || ': ' || v_old || ' → ' || v_grade;
            END IF;
        END IF;
        seen := seen || v_pair;
        CASE v_status WHEN 'INVALID' THEN n_invalid := n_invalid + 1; WHEN 'NEW' THEN n_new := n_new + 1; WHEN 'CORRECTION' THEN n_fix := n_fix + 1; ELSE n_same := n_same + 1; END CASE;
        v_out := v_out || jsonb_build_object('row', r->'row', 'key', v_key, 'subject', coalesce(s.code, r->>'subject'), 'grade', v_grade, 'status', v_status, 'message', v_msg,
                                         'applicationId', a.id, 'subjectId', s.id, 'applicationNo', a.application_no, 'examNo', a.exam_no,
                                         'name', CASE WHEN a.id IS NOT NULL THEN a.surname || ', ' || a.first_name END, 'reason', nullif(btrim(coalesce(r->>'reason', '')), ''));
    END LOOP;
    IF p_commit THEN
        IF jsonb_array_length(v_out) = 0 THEN RAISE EXCEPTION 'JUPEB_IMPORT_EMPTY: the file has no rows' USING ERRCODE = '23514'; END IF;
        IF n_invalid > 0 THEN
            RAISE EXCEPTION 'JUPEB_IMPORT_INVALID: % row(s) are invalid; nothing was written', n_invalid USING ERRCODE = '23514', HINT = 'Correct the rows the preview lists and upload again.';
        END IF;
        v_ref := jupeb.batch_ref('RESULTS');
        FOR r IN SELECT * FROM jsonb_array_elements(v_out) LOOP
            IF r->>'status' = 'NEW' THEN
                INSERT INTO jupeb.result (application_id, subject_id, grade, points, batch_ref, recorded_by)
                VALUES ((r->>'applicationId')::uuid, (r->>'subjectId')::uuid, r->>'grade', jupeb.grade_points(r->>'grade'), v_ref, p_actor);
                applied := applied + 1;
            ELSIF r->>'status' = 'CORRECTION' THEN
                INSERT INTO jupeb.result_change (application_id, subject_id, old_grade, new_grade, reason, batch_ref, changed_by)
                SELECT application_id, subject_id, grade, r->>'grade', r->>'reason', v_ref, p_actor FROM jupeb.result
                 WHERE application_id = (r->>'applicationId')::uuid AND subject_id = (r->>'subjectId')::uuid;
                UPDATE jupeb.result SET grade = r->>'grade', points = jupeb.grade_points(r->>'grade'), batch_ref = v_ref, recorded_by = p_actor, recorded_at = now()
                 WHERE application_id = (r->>'applicationId')::uuid AND subject_id = (r->>'subjectId')::uuid;
                PERFORM jupeb.app_event((r->>'applicationId')::uuid, 'RESULT_CORRECTED', (r->>'message') || ' — ' || (r->>'reason'));
                applied := applied + 1;
            END IF;
        END LOOP;
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'RESULTS', p_file, jsonb_array_length(v_out), applied, jsonb_build_object('new', n_new, 'corrections', n_fix, 'unchanged', n_same),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'invalid', n_invalid, 'new', n_new, 'corrections', n_fix, 'unchanged', n_same, 'committed', p_commit, 'ref', v_ref, 'applied', applied);
END $$;

-- ── 7 · the attendance engine ────────────────────────────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS attendance;
COMMENT ON SCHEMA attendance IS 'V342: the University''s attendance engine — registers by session, semester, subject, class and date; PRESENT, ABSENT, LATE, EXCUSED; corrections kept with their reason; locking; instructors; a configurable minimum. The JUPEB context first; shaped for the other programmes.';
GRANT USAGE ON SCHEMA attendance TO app_admissions, app_auditor, app_registration, app_results;

/* who takes a context's registers for a subject (and a class, or every class) in a session */
CREATE TABLE attendance.instructor (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    context     text NOT NULL CHECK (context IN ('JUPEB')),
    session     text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    subject_ref uuid NOT NULL,
    class_ref   uuid NULL,
    person_id   uuid NOT NULL REFERENCES iam.person(id),
    assigned_by uuid NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    ended_at    timestamptz NULL,
    ended_by    uuid NULL
);
CREATE UNIQUE INDEX ux_attendance_instructor ON attendance.instructor (context, session, subject_ref, coalesce(class_ref, '00000000-0000-0000-0000-000000000000'::uuid), person_id) WHERE ended_at IS NULL;
CREATE INDEX ix_attendance_instructor_person ON attendance.instructor (person_id) WHERE ended_at IS NULL;
SELECT audit.attach('attendance.instructor');

CREATE TABLE attendance.register (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    context     text NOT NULL CHECK (context IN ('JUPEB')),
    session     text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    semester    int NOT NULL CHECK (semester BETWEEN 1 AND 3),
    subject_ref uuid NOT NULL,
    class_ref   uuid NULL,
    held_on     date NOT NULL,
    topic       text NULL CHECK (topic IS NULL OR length(topic) <= 300),
    opened_by   uuid NOT NULL,
    opened_at   timestamptz NOT NULL DEFAULT now(),
    saved_at    timestamptz NULL,
    locked_at   timestamptz NULL,
    locked_by   uuid NULL
);
CREATE UNIQUE INDEX ux_attendance_register ON attendance.register (context, session, semester, subject_ref, coalesce(class_ref, '00000000-0000-0000-0000-000000000000'::uuid), held_on);
CREATE INDEX ix_attendance_register_lookup ON attendance.register (context, session, subject_ref, held_on DESC);
SELECT audit.attach('attendance.register');

CREATE TABLE attendance.mark (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    register_id uuid NOT NULL REFERENCES attendance.register(id),
    member_ref  uuid NOT NULL,
    status      text NOT NULL CHECK (status IN ('PRESENT', 'ABSENT', 'LATE', 'EXCUSED')),
    marked_time time NULL,
    remarks     text NULL CHECK (remarks IS NULL OR length(remarks) <= 300),
    marked_by   uuid NOT NULL,
    marked_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_attendance_mark UNIQUE (register_id, member_ref)
);
CREATE INDEX ix_attendance_mark_member ON attendance.mark (member_ref);
SELECT audit.attach('attendance.mark');

CREATE TABLE attendance.mark_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    mark_id        uuid NOT NULL REFERENCES attendance.mark(id),
    register_id    uuid NOT NULL REFERENCES attendance.register(id),
    member_ref     uuid NOT NULL,
    old_status     text NOT NULL,
    new_status     text NOT NULL,
    old_remarks    text NULL,
    new_remarks    text NULL,
    reason         text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 600),
    changed_by     uuid NOT NULL,
    changed_office text NULL,
    changed_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_attendance_change ON attendance.mark_change (register_id, changed_at);
SELECT audit.attach('attendance.mark_change');

/* the minimum attendance a context requires in a session ('*' for every session without its own) — never assumed */
CREATE TABLE attendance.policy (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    context     text NOT NULL CHECK (context IN ('JUPEB')),
    session     text NOT NULL CHECK (session = '*' OR session ~ '^[0-9]{4}/[0-9]{4}$'),
    min_percent numeric(5,2) NULL CHECK (min_percent IS NULL OR min_percent BETWEEN 0 AND 100),
    updated_by  uuid NULL,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_attendance_policy UNIQUE (context, session)
);
SELECT audit.attach('attendance.policy');

/* the references a JUPEB register and its instructors name: a JUPEB subject, and a JUPEB class of the same session */
CREATE OR REPLACE FUNCTION attendance.check_refs()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.context = 'JUPEB' THEN
        IF NOT EXISTS (SELECT 1 FROM jupeb.subject WHERE id = NEW.subject_ref) THEN
            RAISE EXCEPTION 'ATT_SUBJECT: no such JUPEB subject' USING ERRCODE = '23514';
        END IF;
        IF NEW.class_ref IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jupeb.class WHERE id = NEW.class_ref AND session = NEW.session) THEN
            RAISE EXCEPTION 'ATT_CLASS: no such JUPEB class in %', NEW.session USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_attendance_instructor_refs BEFORE INSERT OR UPDATE ON attendance.instructor FOR EACH ROW EXECUTE FUNCTION attendance.check_refs();
CREATE TRIGGER trg_attendance_register_refs BEFORE INSERT OR UPDATE ON attendance.register FOR EACH ROW EXECUTE FUNCTION attendance.check_refs();

/* the class list of a register: in the JUPEB context, the active students of the session registered for the subject, of the class when one is named */
CREATE OR REPLACE FUNCTION attendance.roster(p_register uuid)
RETURNS TABLE (member_ref uuid, name text, application_no text, exam_no text, combination_code text, class_name text, stream text)
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, ''), a.application_no, a.exam_no, c.code, cl.name, a.stream
      FROM attendance.register r
      JOIN jupeb.application a ON a.session = r.session AND a.state IN ('STUDENT', 'COMPLETED')
      JOIN jupeb.subject_registration sr ON sr.application_id = a.id AND sr.subject_id = r.subject_ref
      LEFT JOIN jupeb.combination c ON c.id = a.combination_id
      LEFT JOIN jupeb.class cl ON cl.id = a.class_id
     WHERE r.id = p_register AND r.context = 'JUPEB' AND (r.class_ref IS NULL OR a.class_id = r.class_ref)
     ORDER BY a.surname, a.first_name
$$;

/* whether a person may take (and correct, before it is locked) a register of this subject and class */
CREATE OR REPLACE FUNCTION attendance.may_take(p_person uuid, p_context text, p_session text, p_subject uuid, p_class uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM attendance.instructor i
                    WHERE i.person_id = p_person AND i.context = p_context AND i.session = p_session AND i.subject_ref = p_subject
                      AND i.ended_at IS NULL AND (i.class_ref IS NULL OR i.class_ref = p_class))
$$;

/* the register of a subject (and class) on a day: opened once, found again after */
CREATE OR REPLACE FUNCTION attendance.open_register(p_context text, p_session text, p_semester int, p_subject uuid, p_class uuid, p_held_on date, p_topic text, p_actor uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
    IF p_held_on > current_date THEN RAISE EXCEPTION 'ATT_FUTURE: a register is not taken for a day still to come' USING ERRCODE = '23514'; END IF;
    SELECT id INTO v FROM attendance.register
     WHERE context = p_context AND session = p_session AND semester = p_semester AND subject_ref = p_subject
       AND coalesce(class_ref, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_class, '00000000-0000-0000-0000-000000000000'::uuid) AND held_on = p_held_on;
    IF v IS NOT NULL THEN RETURN v; END IF;
    INSERT INTO attendance.register (context, session, semester, subject_ref, class_ref, held_on, topic, opened_by)
    VALUES (p_context, p_session, p_semester, p_subject, p_class, p_held_on, nullif(btrim(coalesce(p_topic, '')), ''), p_actor)
    RETURNING id INTO v;
    RETURN v;
END $$;

/* the marks of a register, in one batch: new marks written; a mark already saved changes only with a reason, kept on its history;
   a locked register changes only for an office that may (p_override) */
CREATE OR REPLACE FUNCTION attendance.save_marks(p_register uuid, p_marks jsonb, p_reason text, p_actor uuid, p_override boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r attendance.register; m jsonb; v_member uuid; v_status text; v_time time; v_remarks text; cur attendance.mark;
        n_new int := 0; n_changed int := 0; n_same int := 0; v_roster uuid[];
BEGIN
    SELECT * INTO r FROM attendance.register WHERE id = p_register FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such register' USING ERRCODE = '23503'; END IF;
    IF r.locked_at IS NOT NULL AND NOT p_override THEN
        RAISE EXCEPTION 'ATT_LOCKED: the register of % is locked', r.held_on USING ERRCODE = '23514', HINT = 'The JUPEB Office corrects a locked register.';
    END IF;
    SELECT coalesce(array_agg(x.member_ref), '{}') INTO v_roster FROM attendance.roster(p_register) x;
    FOR m IN SELECT * FROM jsonb_array_elements(coalesce(p_marks, '[]'::jsonb)) LOOP
        v_member := (m->>'member')::uuid;
        v_status := upper(btrim(coalesce(m->>'status', '')));
        v_time := CASE WHEN coalesce(m->>'time', '') ~ '^\d{2}:\d{2}(:\d{2})?$' THEN (m->>'time')::time END;
        v_remarks := nullif(btrim(coalesce(m->>'remarks', '')), '');
        IF NOT (v_member = ANY(v_roster)) THEN RAISE EXCEPTION 'ATT_NOT_ON_LIST: a student marked is not on this register''s class list' USING ERRCODE = '23514'; END IF;
        IF v_status NOT IN ('PRESENT', 'ABSENT', 'LATE', 'EXCUSED') THEN RAISE EXCEPTION 'ATT_STATUS: present, absent, late or excused' USING ERRCODE = '23514'; END IF;
        SELECT * INTO cur FROM attendance.mark WHERE register_id = p_register AND member_ref = v_member;
        IF cur.id IS NULL THEN
            INSERT INTO attendance.mark (register_id, member_ref, status, marked_time, remarks, marked_by)
            VALUES (p_register, v_member, v_status, coalesce(v_time, CASE WHEN v_status IN ('PRESENT', 'LATE') THEN (now() AT TIME ZONE 'Africa/Lagos')::time(0) END), v_remarks, p_actor);
            n_new := n_new + 1;
        ELSIF cur.status IS DISTINCT FROM v_status OR cur.remarks IS DISTINCT FROM v_remarks THEN
            IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
                RAISE EXCEPTION 'ATT_REASON: a saved mark is corrected with a reason' USING ERRCODE = '23514', HINT = 'Say why the attendance is corrected.';
            END IF;
            INSERT INTO attendance.mark_change (mark_id, register_id, member_ref, old_status, new_status, old_remarks, new_remarks, reason, changed_by, changed_office)
            VALUES (cur.id, p_register, v_member, cur.status, v_status, cur.remarks, v_remarks, btrim(p_reason), p_actor, nullif(current_setting('moaum.actor_office', true), ''));
            UPDATE attendance.mark SET status = v_status, remarks = v_remarks, marked_time = coalesce(v_time, marked_time), marked_by = p_actor, marked_at = now() WHERE id = cur.id;
            n_changed := n_changed + 1;
        ELSE
            n_same := n_same + 1;
        END IF;
    END LOOP;
    UPDATE attendance.register SET saved_at = now() WHERE id = p_register;
    RETURN jsonb_build_object('marked', n_new, 'corrected', n_changed, 'unchanged', n_same);
END $$;

CREATE OR REPLACE FUNCTION attendance.lock_register(p_register uuid, p_actor uuid, p_lock boolean, p_reason text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r attendance.register;
BEGIN
    SELECT * INTO r FROM attendance.register WHERE id = p_register FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'no such register' USING ERRCODE = '23503'; END IF;
    IF p_lock THEN
        IF r.locked_at IS NOT NULL THEN RETURN; END IF;
        IF NOT EXISTS (SELECT 1 FROM attendance.mark WHERE register_id = p_register) THEN
            RAISE EXCEPTION 'ATT_EMPTY: an unmarked register is not locked' USING ERRCODE = '23514';
        END IF;
        UPDATE attendance.register SET locked_at = now(), locked_by = p_actor WHERE id = p_register;
    ELSE
        IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'ATT_REASON: a register is unlocked with a reason' USING ERRCODE = '23514'; END IF;
        PERFORM set_config('moaum.reason', 'Attendance register unlocked: ' || btrim(p_reason), true);
        UPDATE attendance.register SET locked_at = NULL, locked_by = NULL WHERE id = p_register;
    END IF;
END $$;

/* a member's attendance, subject by subject: the counts, the rate (present and late over every class not excused) and, where a
   minimum is configured, the verdict */
CREATE OR REPLACE FUNCTION attendance.member_summary(p_context text, p_member uuid, p_session text)
RETURNS TABLE (session text, semester int, subject_ref uuid, total int, present int, absent int, late int, excused int, rate numeric, min_percent numeric, verdict text)
LANGUAGE sql STABLE AS $$
    WITH m AS (SELECT r.session, r.semester, r.subject_ref, k.status
                 FROM attendance.mark k JOIN attendance.register r ON r.id = k.register_id
                WHERE r.context = p_context AND k.member_ref = p_member AND (p_session IS NULL OR r.session = p_session)),
    g AS (SELECT m.session, m.semester, m.subject_ref, count(*)::int AS total,
                 count(*) FILTER (WHERE status = 'PRESENT')::int AS present, count(*) FILTER (WHERE status = 'ABSENT')::int AS absent,
                 count(*) FILTER (WHERE status = 'LATE')::int AS late, count(*) FILTER (WHERE status = 'EXCUSED')::int AS excused
            FROM m GROUP BY m.session, m.semester, m.subject_ref)
    SELECT g.session, g.semester, g.subject_ref, g.total, g.present, g.absent, g.late, g.excused,
           CASE WHEN g.total - g.excused > 0 THEN round(100.0 * (g.present + g.late) / (g.total - g.excused), 2) END,
           pol.min_percent,
           CASE WHEN pol.min_percent IS NULL THEN NULL
                WHEN g.total - g.excused = 0 THEN 'REQUIRES_REVIEW'
                WHEN 100.0 * (g.present + g.late) / (g.total - g.excused) >= pol.min_percent THEN 'ELIGIBLE' ELSE 'NOT_ELIGIBLE' END
      FROM g
      LEFT JOIN LATERAL (SELECT p.min_percent FROM attendance.policy p WHERE p.context = p_context AND p.session IN (g.session, '*')
                          ORDER BY (p.session = '*') LIMIT 1) pol ON true
$$;

-- ── 8 · the Board's subject combinations (JUPEB SUBJECT COMBINATIONS, updated 2026: SC-001 to SC-046) ──────────────
--   As the Board publishes them. "Yoruba/Igbo" is one subject (the candidate offers one of the two); CRS/ISS and the CRS/IRS
--   of SC-025 are the same subject. The area follows the Board's list: SC-031–043 and SC-046 are offered to Science
--   candidates, the rest to Non-Science; the JUPEB Office may change an area, add a combination or retire one.
INSERT INTO jupeb.subject (code, title) VALUES
    ('ACC', 'Accounting'), ('AGR', 'Agricultural Science'), ('BIO', 'Biology'), ('BUS', 'Business Studies'), ('CHM', 'Chemistry'),
    ('CRS/ISS', 'Christian / Islamic Religious Studies'), ('ECO', 'Economics'), ('FRE', 'French'), ('GEO', 'Geography'), ('GOV', 'Government'),
    ('HIS', 'History'), ('IGB/YOR', 'Igbo / Yoruba'), ('LIT', 'Literature in English'), ('MTH', 'Mathematics'), ('MUS', 'Music'),
    ('PHY', 'Physics'), ('VAR', 'Visual Art')
ON CONFLICT (code) DO NOTHING;

INSERT INTO jupeb.combination (code, name, subject1, subject2, subject3, area, description)
SELECT v.code, s1.title || ', ' || s2.title || ', ' || s3.title, s1.id, s2.id, s3.id, v.area, 'JUPEB ' || v.code
  FROM (VALUES
    ('SC-001', 'CRS/ISS', 'GOV', 'LIT', 'Arts'),     ('SC-002', 'CRS/ISS', 'GOV', 'IGB/YOR', 'Arts'), ('SC-003', 'CRS/ISS', 'GOV', 'MUS', 'Arts'),
    ('SC-004', 'CRS/ISS', 'GOV', 'VAR', 'Arts'),     ('SC-005', 'CRS/ISS', 'FRE', 'GOV', 'Arts'),     ('SC-006', 'CRS/ISS', 'FRE', 'LIT', 'Arts'),
    ('SC-007', 'CRS/ISS', 'LIT', 'MUS', 'Arts'),     ('SC-008', 'CRS/ISS', 'HIS', 'LIT', 'Arts'),     ('SC-009', 'CRS/ISS', 'HIS', 'VAR', 'Arts'),
    ('SC-010', 'CRS/ISS', 'IGB/YOR', 'LIT', 'Arts'), ('SC-011', 'CRS/ISS', 'IGB/YOR', 'VAR', 'Arts'), ('SC-012', 'CRS/ISS', 'MUS', 'VAR', 'Arts'),
    ('SC-013', 'ECO', 'HIS', 'LIT', 'Arts'),         ('SC-014', 'FRE', 'IGB/YOR', 'LIT', 'Arts'),     ('SC-015', 'GOV', 'MUS', 'LIT', 'Arts'),
    ('SC-016', 'GOV', 'MUS', 'VAR', 'Arts'),         ('SC-017', 'LIT', 'GOV', 'FRE', 'Arts'),         ('SC-018', 'LIT', 'MUS', 'VAR', 'Arts'),
    ('SC-019', 'ACC', 'BUS', 'ECO', 'Management Sciences'), ('SC-020', 'ACC', 'ECO', 'GEO', 'Management Sciences'),
    ('SC-021', 'ACC', 'ECO', 'GOV', 'Management Sciences'), ('SC-022', 'BUS', 'ECO', 'GEO', 'Management Sciences'),
    ('SC-023', 'BUS', 'ECO', 'GOV', 'Management Sciences'), ('SC-024', 'BUS', 'ECO', 'MTH', 'Management Sciences'),
    ('SC-025', 'ECO', 'GOV', 'CRS/ISS', 'Social Sciences'), ('SC-026', 'ECO', 'GOV', 'LIT', 'Social Sciences'),
    ('SC-027', 'ECO', 'GOV', 'MTH', 'Social Sciences'),     ('SC-028', 'ECO', 'GOV', 'BIO', 'Social Sciences'),
    ('SC-029', 'ECO', 'GEO', 'GOV', 'Social Sciences'),     ('SC-030', 'ECO', 'GEO', 'MTH', 'Social Sciences'),
    ('SC-031', 'BIO', 'CHM', 'PHY', 'Science'),      ('SC-032', 'BIO', 'CHM', 'ECO', 'Science'),      ('SC-033', 'BIO', 'CHM', 'MTH', 'Science'),
    ('SC-034', 'BIO', 'CHM', 'AGR', 'Science'),      ('SC-035', 'BIO', 'MTH', 'PHY', 'Science'),      ('SC-036', 'CHM', 'MTH', 'ECO', 'Science'),
    ('SC-037', 'CHM', 'PHY', 'GEO', 'Science'),      ('SC-038', 'CHM', 'PHY', 'MTH', 'Science'),      ('SC-039', 'CHM', 'PHY', 'AGR', 'Science'),
    ('SC-040', 'MTH', 'PHY', 'AGR', 'Science'),      ('SC-041', 'MTH', 'PHY', 'ECO', 'Science'),      ('SC-042', 'MTH', 'PHY', 'GEO', 'Science'),
    ('SC-043', 'MTH', 'PHY', 'VAR', 'Science'),      ('SC-044', 'ACC', 'ECO', 'MTH', 'Management Sciences'),
    ('SC-045', 'CRS/ISS', 'ECO', 'LIT', 'Arts'),     ('SC-046', 'MTH', 'ECO', 'BIO', 'Science')
  ) AS v(code, a, b, c, area)
  JOIN jupeb.subject s1 ON s1.code = v.a JOIN jupeb.subject s2 ON s2.code = v.b JOIN jupeb.subject s3 ON s3.code = v.c
ON CONFLICT (code) DO NOTHING;

/* the course units of the sample statement of result */
INSERT INTO jupeb.subject_unit (subject_id, code, title, ord)
SELECT s.id, v.code, v.title, v.ord FROM (VALUES
    ('BIO', 'BIO 001', 'General Biology', 1), ('BIO', 'BIO 002', 'Microbiology', 2), ('BIO', 'BIO 003', 'Botany', 3), ('BIO', 'BIO 004', 'Zoology', 4),
    ('CHM', 'CHM 001', 'General Chemistry', 1), ('CHM', 'CHM 002', 'Physical Chemistry', 2), ('CHM', 'CHM 003', 'Inorganic Chemistry', 3), ('CHM', 'CHM 004', 'Organic Chemistry', 4),
    ('PHY', 'PHY 001', 'Mechanics and Properties of Matter', 1), ('PHY', 'PHY 002', 'Heat, Waves and Optics', 2), ('PHY', 'PHY 003', 'Electricity and Magnetism', 3),
    ('PHY', 'PHY 004', 'Modern Physics', 4)
  ) AS v(subject, code, title, ord)
  JOIN jupeb.subject s ON s.code = v.subject
ON CONFLICT (subject_id, code) DO NOTHING;

-- ── 9 · what is offered: the JUPEB Office disables and reactivates subjects and combinations ───────────────────
/* p_kind SUBJECT or COMBINATION; p_codes the codes; nothing is deleted. A candidate holding a combination that this stops
   offering, before their subjects are registered, is told to choose another. Returns how many changed and how many were told. */
CREATE OR REPLACE FUNCTION jupeb.set_offered(p_kind text, p_codes text[], p_offered boolean, p_actor uuid)
RETURNS TABLE (changed int, told int) LANGUAGE plpgsql AS $$
DECLARE v_codes text[]; v_unknown text; v_changed text[]; v_told int := 0; r record;
BEGIN
    SELECT coalesce(array_agg(DISTINCT upper(btrim(x))) FILTER (WHERE btrim(x) <> ''), '{}') INTO v_codes FROM unnest(coalesce(p_codes, '{}')) x;
    IF cardinality(v_codes) = 0 THEN RAISE EXCEPTION 'JUPEB_OFFERED_NONE: name at least one code' USING ERRCODE = '23514'; END IF;
    IF p_kind = 'SUBJECT' THEN
        SELECT string_agg(x, ', ') INTO v_unknown FROM unnest(v_codes) x WHERE NOT EXISTS (SELECT 1 FROM jupeb.subject s WHERE upper(s.code) = x);
        IF v_unknown IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_UNKNOWN_SUBJECT: no JUPEB subject %', v_unknown USING ERRCODE = '23514'; END IF;
        WITH u AS (UPDATE jupeb.subject SET active = p_offered, updated_by = p_actor, updated_at = now()
                    WHERE upper(code) = ANY (v_codes) AND active IS DISTINCT FROM p_offered RETURNING code)
        SELECT coalesce(array_agg(upper(code)), '{}') INTO v_changed FROM u;
    ELSIF p_kind = 'COMBINATION' THEN
        SELECT string_agg(x, ', ') INTO v_unknown FROM unnest(v_codes) x WHERE NOT EXISTS (SELECT 1 FROM jupeb.combination c WHERE upper(c.code) = x);
        IF v_unknown IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_UNKNOWN_COMBINATION: no JUPEB combination %', v_unknown USING ERRCODE = '23514'; END IF;
        WITH u AS (UPDATE jupeb.combination SET active = p_offered, updated_by = p_actor, updated_at = now()
                    WHERE upper(code) = ANY (v_codes) AND active IS DISTINCT FROM p_offered RETURNING code)
        SELECT coalesce(array_agg(upper(code)), '{}') INTO v_changed FROM u;
    ELSE
        RAISE EXCEPTION 'JUPEB_OFFERED_KIND: a subject or a combination' USING ERRCODE = '23514';
    END IF;
    IF NOT p_offered AND cardinality(v_changed) > 0 THEN
        FOR r IN SELECT a.id, a.state, c.code FROM jupeb.application a JOIN jupeb.combination c ON c.id = a.combination_id
                  WHERE a.subjects_registered_at IS NULL AND a.state NOT IN ('INELIGIBLE', 'NOT_ADMITTED', 'WITHDRAWN', 'COMPLETED')
                    AND NOT jupeb.combination_offered(c.id)
                    AND CASE WHEN p_kind = 'COMBINATION' THEN upper(c.code) = ANY (v_changed)
                             ELSE EXISTS (SELECT 1 FROM jupeb.subject s WHERE s.id IN (c.subject1, c.subject2, c.subject3) AND upper(s.code) = ANY (v_changed)) END
        LOOP
            PERFORM jupeb.tell(r.id, 'Choose another JUPEB subject combination',
                'The subject combination you chose, ' || r.code || ', is no longer offered by the University. '
                || CASE WHEN r.state IN ('DRAFT', 'RETURNED') THEN 'Sign in and choose another combination of your programme before you submit.'
                        ELSE 'You will choose another combination of your programme when you register your subjects.' END);
            v_told := v_told + 1;
        END LOOP;
    END IF;
    RETURN QUERY SELECT cardinality(v_changed), v_told;
END $$;

-- ── 10 · the applicant's programme and combination ──────────────────────────────────────────────────────────────
/* while the application is a draft or returned: the programme, and (when named) an offered combination of it; a held
   combination that does not suit a changed programme is let go */
CREATE OR REPLACE FUNCTION jupeb.choose(p_app uuid, p_stream text, p_combination text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v_stream text; c jupeb.combination;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN RAISE EXCEPTION 'JUPEB_NOT_FOUND: no such application' USING ERRCODE = '23514'; END IF;
    IF a.state NOT IN ('DRAFT', 'RETURNED') THEN
        RAISE EXCEPTION 'JUPEB_NOT_EDITABLE: the application is submitted and can no longer be changed' USING ERRCODE = '23514';
    END IF;
    v_stream := CASE upper(regexp_replace(btrim(coalesce(p_stream, '')), '[- ]', '_', 'g'))
                    WHEN 'SCIENCE' THEN 'SCIENCE' WHEN 'NON_SCIENCE' THEN 'NON_SCIENCE' WHEN 'ARTS' THEN 'NON_SCIENCE' END;
    IF v_stream IS NULL THEN RAISE EXCEPTION 'JUPEB_STREAM: choose Science or Non-Science' USING ERRCODE = '23514'; END IF;
    IF nullif(btrim(coalesce(p_combination, '')), '') IS NOT NULL THEN
        SELECT * INTO c FROM jupeb.combination x WHERE x.id::text = btrim(p_combination) OR upper(x.code) = upper(btrim(p_combination));
        IF c.id IS NULL OR NOT jupeb.combination_offered(c.id) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the subject combinations the University offers' USING ERRCODE = '23514';
        END IF;
        IF NOT jupeb.combination_suits(c.area, v_stream) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a % combination', c.code, CASE v_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
        END IF;
        UPDATE jupeb.application SET stream = v_stream, combination_id = c.id WHERE id = p_app;
    ELSE
        UPDATE jupeb.application x SET stream = v_stream,
               combination_id = CASE WHEN x.combination_id IS NOT NULL
                                      AND jupeb.combination_suits((SELECT k.area FROM jupeb.combination k WHERE k.id = x.combination_id), v_stream)
                                     THEN x.combination_id END
         WHERE x.id = p_app;
    END IF;
END $$;

/* the active student registers the three subjects of an OFFERED combination of their stream — the one held from the
   application, or another chosen here (V341, V342) */
CREATE OR REPLACE FUNCTION jupeb.register_subjects(p_app uuid, p_actor uuid, p_combination uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.combination; n int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('STUDENT') THEN RAISE EXCEPTION 'JUPEB_NOT_STUDENT: subjects are registered by an active JUPEB student' USING ERRCODE = '23514',
        HINT = 'Pay the school fee the Bursary requires for activation first.'; END IF;
    IF a.subjects_registered_at IS NOT NULL THEN RETURN 0; END IF;
    SELECT * INTO c FROM jupeb.combination WHERE id = coalesce(p_combination, a.combination_id);
    IF c.id IS NULL THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION_CHOOSE: choose your subject combination to register' USING ERRCODE = '23514';
    END IF;
    IF NOT jupeb.combination_offered(c.id) THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION: % is not offered: choose one of the subject combinations the University offers', c.code USING ERRCODE = '23514';
    END IF;
    IF NOT jupeb.combination_suits(c.area, a.stream) THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a combination for % students', c.code, CASE a.stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
    END IF;
    UPDATE jupeb.application SET combination_id = c.id WHERE id = p_app AND combination_id IS DISTINCT FROM c.id;
    INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
    SELECT p_app, s, a.session, p_actor FROM unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s
    ON CONFLICT (application_id, subject_id) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE jupeb.application SET subjects_registered_at = now() WHERE id = p_app;
    RETURN n;
END $$;

-- ── 11 · grants ───────────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON ALL TABLES IN SCHEMA attendance TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA attendance TO app_admissions;

COMMIT;
