-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V427 — payments classified fast, and each required biodata item counted before it is ticked
--
--   1. reporting.payments (V409) classified every payment by calling three rule functions per row — the category from
--      the purpose or kind (finance.categorise), the programme type from the entry mode and the programme's category
--      (finance.programme_type_for), the owner from the purpose and the programme type (finance.payment_owner). Each
--      call is a separate SQL function run, about 35–60 µs, and on a live-shaped ledger of 314,325 payments the view took
--      48 s to read whole: every Financial analytics screen read it five times. Yet the inputs are few — 80 purposes,
--      a handful of kinds, entry modes and programme categories. So each function's answer is kept per distinct input
--      (finance.category_memo, finance.programme_type_memo, finance.owner_memo), recomputed in full whenever the
--      Bursary's rules change (the categories, programme types, purposes and classification rules, by statement
--      triggers) and extended as new purposes appear on new payment references. The view reads the memo and, for an
--      input it does not hold, still calls the function — so the answer is always the rules' own, never stale. And the
--      applicants' fees found their programme by calling admissions.programme_code_of — a scan of the programmes by name —
--      for every fee (450 µs each, six of the nine seconds the whole view took once the rules were memoised); the view joins
--      one row a programme name instead, chosen the same way (unarchived first, then by code).
--   2. people.biodata_requirement_impact() — for every item that can be required of a student's biodata, how many
--      students on the register lack it, how many complete students ticking it would hold, and how many held students
--      unticking it would free: what the ICT Director sees before changing what is required (V423).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1 · each rule function's answer, per distinct input ──────────────────────────────────────────────────────────────
CREATE TABLE finance.category_memo (
    kind    text NOT NULL,     -- '' when the payment carries a purpose instead
    purpose text NOT NULL,     -- '' when the payment carries a kind instead
    code    text NOT NULL,
    PRIMARY KEY (kind, purpose)
);
SELECT audit.exempt('finance.category_memo', 'finance.categorise''s answer per kind and purpose; derived from finance.payment_category and recomputed whenever it changes');

CREATE TABLE finance.programme_type_memo (
    entry_mode text NOT NULL,  -- '' when none
    category   text NOT NULL,  -- the programme's category, '' when none
    code       text NOT NULL,
    PRIMARY KEY (entry_mode, category)
);
SELECT audit.exempt('finance.programme_type_memo', 'finance.programme_type_for''s answer per entry mode and programme category; derived from finance.programme_type and recomputed whenever it changes');

CREATE TABLE finance.owner_memo (
    purpose            text NOT NULL,
    programme_type     text NOT NULL,
    source_module      text NULL,
    responsible_office text NULL,
    PRIMARY KEY (purpose, programme_type)
);
SELECT audit.exempt('finance.owner_memo', 'finance.payment_owner''s answer per purpose and programme type; derived from finance.payment_classification and recomputed whenever it changes');

CREATE OR REPLACE FUNCTION finance.refresh_category_memo()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    DELETE FROM finance.category_memo;
    INSERT INTO finance.category_memo (kind, purpose, code)
    SELECT x.k, x.p, finance.categorise(nullif(x.k, ''), nullif(x.p, ''))
      FROM (SELECT ''::text AS k, coalesce(r.purpose, '') AS p FROM finance.payment_reference r GROUP BY 2
            UNION SELECT coalesce(fr.kind, ''), '' FROM admissions.fee_reference fr GROUP BY 1
            UNION SELECT unnest(c.kinds), '' FROM finance.payment_category c WHERE c.kinds IS NOT NULL) x;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION finance.refresh_programme_type_memo()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    DELETE FROM finance.programme_type_memo;
    INSERT INTO finance.programme_type_memo (entry_mode, category, code)
    SELECT e.m, c.cat, finance.programme_type_for(nullif(e.m, ''), nullif(c.cat, ''))
      FROM (SELECT coalesce(s.entry_mode, '') AS m FROM people.student s GROUP BY 1
            UNION SELECT coalesce(ca.entry_mode, '') FROM admissions.candidate ca GROUP BY 1
            UNION SELECT upper(unnest(t.entry_modes)) FROM finance.programme_type t WHERE t.entry_modes IS NOT NULL
            UNION VALUES ('POSTGRADUATE'), ('JUPEB'), ('')) e
     CROSS JOIN (SELECT coalesce(p.category, '') AS cat FROM ref.programme p GROUP BY 1
                 UNION SELECT unnest(t.programme_categories) FROM finance.programme_type t WHERE t.programme_categories IS NOT NULL
                 UNION VALUES ('')) c;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION finance.refresh_owner_memo()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    DELETE FROM finance.owner_memo;
    INSERT INTO finance.owner_memo (purpose, programme_type, source_module, responsible_office)
    SELECT pu.p, ty.t, o.source_module, o.responsible_office
      FROM (SELECT code AS p FROM finance.payment_purpose UNION SELECT purpose FROM finance.payment_category WHERE purpose IS NOT NULL
            UNION VALUES ('OTHER')) pu
     CROSS JOIN (SELECT code AS t FROM finance.programme_type UNION SELECT code FROM finance.programme_type_memo UNION VALUES ('OTHER')) ty
      LEFT JOIN LATERAL finance.payment_owner(pu.p, ty.t) o(source_module, responsible_office) ON true;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- the Bursary's rules change → the answers they give are recomputed, in the same transaction
CREATE OR REPLACE FUNCTION finance.classification_rules_changed()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_TABLE_NAME = 'payment_category' THEN
        PERFORM finance.refresh_category_memo();
    END IF;
    IF TG_TABLE_NAME = 'programme_type' THEN
        PERFORM finance.refresh_programme_type_memo();
    END IF;
    PERFORM finance.refresh_owner_memo();
    RETURN NULL;
END $$;
CREATE TRIGGER trg_classification_memo AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON finance.payment_category
    FOR EACH STATEMENT EXECUTE FUNCTION finance.classification_rules_changed();
CREATE TRIGGER trg_classification_memo AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON finance.programme_type
    FOR EACH STATEMENT EXECUTE FUNCTION finance.classification_rules_changed();
CREATE TRIGGER trg_classification_memo AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON finance.payment_purpose
    FOR EACH STATEMENT EXECUTE FUNCTION finance.classification_rules_changed();
CREATE TRIGGER trg_classification_memo AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON finance.payment_classification
    FOR EACH STATEMENT EXECUTE FUNCTION finance.classification_rules_changed();

-- a payment reference with a purpose the memo has not met yet: its category is worked out once, for the next reads
CREATE OR REPLACE FUNCTION finance.category_memo_new_purposes()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO finance.category_memo (kind, purpose, code)
    SELECT '', x.p, finance.categorise(NULL, nullif(x.p, ''))
      FROM (SELECT DISTINCT coalesce(n.purpose, '') AS p FROM new_rows n) x
     WHERE NOT EXISTS (SELECT 1 FROM finance.category_memo m WHERE m.kind = '' AND m.purpose = x.p)
    ON CONFLICT DO NOTHING;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_category_memo_purposes AFTER INSERT ON finance.payment_reference
    REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION finance.category_memo_new_purposes();

SELECT finance.refresh_category_memo();
SELECT finance.refresh_programme_type_memo();
SELECT finance.refresh_owner_memo();   -- after the programme types, whose codes it reads

-- the view, as V409 left it (restated from the database), reading the memo before the functions
CREATE OR REPLACE VIEW reporting.payments AS
SELECT 'STUDENT'::text AS source,
    r.id AS payment_id,
    r.reference,
    r.receipt_no,
    r.purpose,
    NULL::text AS kind,
    k.code AS category_code,
    r.amount,
    r.generated_at,
    r.confirmed_at,
    r.expires_at,
    r.channel,
    r.session,
    st.id AS student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    st.id::text AS payer_key,
    st.surname,
    st.other_names,
    COALESCE(st.matric_no, st.admission_no) AS number,
    st.sex,
    st.entry_mode,
    st.entry_session,
    st.status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session) AS level,
    st.entry_mode = 'POSTGRADUATE'::text OR p.category = 'POST GRADUATE'::text AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    finance.admission_route_of(st.entry_mode) AS admission_route,
    st.study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
        CASE
            WHEN r.purpose ~* '(first|1st) semester'::text THEN 1
            WHEN r.purpose ~* '(second|2nd) semester'::text THEN 2
            ELSE NULL::integer
        END AS semester,
    st.jamb_reg_no,
    NULL::text AS application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN r.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN r.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM finance.payment_reference r
     JOIN people.student st ON st.id = r.student_id
     JOIN ref.programme p ON p.code = st.programme_code
     JOIN ref.faculty f ON f.code = p.faculty_code
     JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN finance.category_memo km ON km.kind = ''::text AND km.purpose = COALESCE(r.purpose, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(km.code, finance.categorise(NULL::text, r.purpose)) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     LEFT JOIN finance.programme_type_memo ptm ON ptm.entry_mode = COALESCE(st.entry_mode, ''::text) AND ptm.category = COALESCE(p.category, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(ptm.code, finance.programme_type_for(st.entry_mode, p.category)) AS code) pt
     LEFT JOIN finance.owner_memo om ON om.purpose = COALESCE(cat.purpose, 'OTHER'::text) AND om.programme_type = pt.code
     CROSS JOIN LATERAL ( SELECT
                CASE WHEN om.purpose IS NOT NULL THEN om.source_module
                     ELSE (SELECT o.source_module FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office)) END AS source_module,
                CASE WHEN om.purpose IS NOT NULL THEN om.responsible_office
                     ELSE (SELECT o.responsible_office FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office)) END AS responsible_office) own
UNION ALL
 SELECT 'APPLICANT'::text AS source,
    fr.id AS payment_id,
    fr.reference,
    fr.receipt_no,
    NULL::text AS purpose,
    fr.kind,
    k.code AS category_code,
    fr.amount,
    fr.generated_at,
    fr.confirmed_at,
    fr.expires_at,
    fr.channel,
    a.session,
    s.id AS student_id,
    a.id AS application_id,
    NULL::uuid AS pg_application_id,
    COALESCE(s.id::text, a.id::text) AS payer_key,
    c.surname,
    c.other_names,
    COALESCE(s.matric_no, s.admission_no, a.application_no) AS number,
    COALESCE(s.sex, cr.sex) AS sex,
    c.entry_mode,
    a.session AS entry_session,
    COALESCE(s.status, 'APPLICANT'::text) AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    c.entry_level AS level,
    false AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    finance.admission_route_of(c.entry_mode) AS admission_route,
        CASE
            WHEN c.entry_mode = 'CCE'::text THEN 'PART_TIME'::text
            ELSE 'FULL_TIME'::text
        END AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    c.jamb_reg_no,
    a.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN fr.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN fr.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM admissions.fee_reference fr
     JOIN admissions.application a ON a.id = fr.application_id
     JOIN admissions.candidate c ON c.id = a.candidate_id
     LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
     LEFT JOIN people.student s ON s.candidate_id = c.id
     LEFT JOIN ( SELECT DISTINCT ON (pn.name) pn.name, pn.code
                   FROM ref.programme pn
                  ORDER BY pn.name, pn.archived, pn.code) pnm ON pnm.name = c.programme
     LEFT JOIN ref.programme p ON p.code = pnm.code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN finance.category_memo km ON km.kind = COALESCE(fr.kind, ''::text) AND km.purpose = ''::text
     CROSS JOIN LATERAL ( SELECT COALESCE(km.code, finance.categorise(fr.kind, NULL::text)) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     LEFT JOIN finance.programme_type_memo ptm ON ptm.entry_mode = COALESCE(c.entry_mode, ''::text) AND ptm.category = COALESCE(p.category, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(ptm.code, finance.programme_type_for(c.entry_mode, p.category)) AS code) pt
     LEFT JOIN finance.owner_memo om ON om.purpose = COALESCE(cat.purpose, 'OTHER'::text) AND om.programme_type = pt.code
     CROSS JOIN LATERAL ( SELECT
                CASE WHEN om.purpose IS NOT NULL THEN om.source_module
                     ELSE (SELECT o.source_module FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office)) END AS source_module,
                CASE WHEN om.purpose IS NOT NULL THEN om.responsible_office
                     ELSE (SELECT o.responsible_office FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office)) END AS responsible_office) own
UNION ALL
 SELECT 'PG'::text AS source,
    fr.id AS payment_id,
    fr.reference,
    NULL::text AS receipt_no,
    NULL::text AS purpose,
    'PG_'::text || fr.kind AS kind,
    k.code AS category_code,
    fr.amount,
    fr.generated_at,
    fr.confirmed_at,
    fr.expires_at,
    fr.channel,
    pa.session,
    pa.student_id,
    NULL::uuid AS application_id,
    pa.id AS pg_application_id,
    COALESCE(pa.student_id::text, pa.id::text) AS payer_key,
    ap.surname,
    ap.other_names,
    COALESCE(s.matric_no, s.admission_no, pa.application_no) AS number,
    COALESCE(s.sex, ap.sex) AS sex,
    'POSTGRADUATE'::text AS entry_mode,
    pa.session AS entry_session,
    COALESCE(s.status, pa.state) AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    COALESCE(s.current_level, pa.entry_level) AS level,
    true AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'POSTGRADUATE'::text AS admission_route,
    s.study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    NULL::text AS jamb_reg_no,
    pa.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN fr.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN fr.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM admissions.pg_fee_reference fr
     JOIN admissions.pg_application pa ON pa.id = fr.application_id
     JOIN admissions.pg_applicant ap ON ap.id = pa.applicant_id
     LEFT JOIN people.student s ON s.id = pa.student_id
     LEFT JOIN ref.programme p ON p.code = pa.programme_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('PG_'::text || fr.kind, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('POSTGRADUATE'::text, 'POST GRADUATE'::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true
UNION ALL
 SELECT 'JUPEB'::text AS source,
    jf.id AS payment_id,
    jf.reference,
    NULL::text AS receipt_no,
    NULL::text AS purpose,
    'JUPEB_'::text || jf.kind AS kind,
    k.code AS category_code,
    jf.amount,
    jf.created_at AS generated_at,
    jf.confirmed_at,
    jf.expires_at,
    jf.channel,
    jf.session,
    NULL::uuid AS student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    ja.id::text AS payer_key,
    ja.surname,
    concat_ws(' '::text, NULLIF(btrim(ja.first_name), ''::text), NULLIF(btrim(ja.middle_name), ''::text)) AS other_names,
    ja.application_no AS number,
    ja.sex,
    'JUPEB'::text AS entry_mode,
    ja.session AS entry_session,
    ja.state AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    NULL::integer AS level,
    false AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'JUPEB'::text AS admission_route,
    'FULL_TIME'::text AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    jf.semester,
    NULL::text AS jamb_reg_no,
    ja.application_no,
    ja.exam_no,
    ja.id AS jupeb_application_id,
        CASE
            WHEN jf.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN jf.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM jupeb.fee_reference jf
     JOIN jupeb.application ja ON ja.id = jf.application_id
     LEFT JOIN ref.programme p ON p.code = ja.programme_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('JUPEB_'::text || jf.kind, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('JUPEB'::text, NULL::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true;
COMMENT ON VIEW reporting.payments IS
  'V409, read fast since V427: every payment from every source, classified — category, programme type, purpose, source module, responsible office — by the Bursary''s rules, through the memo tables of each rule''s answer (finance.category_memo, programme_type_memo, owner_memo) and the rule functions themselves for any input the memo does not hold.';

-- ── 2 · each item that can be required, counted before it is ticked ──────────────────────────────────────────────────
-- For the students on the register (people.biodata_applicable): how many lack the item; how many of those whose required
-- biodata is complete now would be held if it were required; and, for a required item, how many held students it alone
-- holds (unticking it would free them). "Given" means what people.biodata_completion means by it: a value other than
-- blanks in the biodata, the contact the student gave for the mobile, e-mail and address, the register line's state of
-- origin, and a passport photograph wherever the portal finds one.
CREATE OR REPLACE FUNCTION people.biodata_requirement_impact()
RETURNS TABLE (item text, required boolean, students int, missing int, newly_held int, freed int)
LANGUAGE sql STABLE AS $$
    WITH app AS (
        SELECT s.id, s.candidate_id, s.jamb_reg_no, s.state_of_origin FROM people.student s WHERE people.biodata_applicable(s.status)
    ),
    comp AS MATERIALIZED (
        SELECT c.student_id, c.complete, c.missing FROM people.biodata_completion((SELECT coalesce(array_agg(id), '{}'::uuid[]) FROM app)) c
    ),
    items AS (
        SELECT 'PASSPORT'::text AS item
        UNION ALL
        SELECT f.field FROM ref.biodata_field f WHERE f.tier <> 'locked' AND f.section <> 'health'
    ),
    has AS (
        SELECT b.field AS item, b.student_id FROM people.biodata b WHERE b.student_id IN (SELECT id FROM app) AND btrim(b.value) <> ''
        UNION
        SELECT x.item, c.student_id FROM people.student_contact c
         CROSS JOIN LATERAL (VALUES ('mobile', c.phone), ('personal_email', c.email), ('home_address', c.address), ('term_address', c.address)) x(item, v)
         WHERE c.student_id IN (SELECT id FROM app) AND nullif(btrim(x.v), '') IS NOT NULL
        UNION
        SELECT 'state_of_origin', app.id FROM app WHERE nullif(btrim(app.state_of_origin), '') IS NOT NULL
        UNION
        SELECT 'PASSPORT', app.id FROM app
         WHERE EXISTS (SELECT 1 FROM people.student_photo ph WHERE ph.student_id = app.id)
            OR EXISTS (SELECT 1 FROM admissions.application a
                         JOIN admissions.application_document d ON d.application_id = a.id AND d.kind = 'PASSPORT' AND d.superseded_at IS NULL
                        WHERE a.candidate_id = app.candidate_id)
            OR EXISTS (SELECT 1 FROM admissions.attachment at
                        WHERE at.kind = 'PASSPORT' AND at.candidate_id = app.candidate_id AND (at.object_id IS NOT NULL OR jsonb_exists(at.payload, 'dataUrl')))
            OR EXISTS (SELECT 1 FROM admissions.attachment at
                        WHERE at.kind = 'PASSPORT' AND app.jamb_reg_no IS NOT NULL AND at.jamb_key = upper(btrim(app.jamb_reg_no))
                          AND (at.object_id IS NOT NULL OR jsonb_exists(at.payload, 'dataUrl')))
    ),
    counts AS (
        SELECT h.item, count(*) AS has_all, count(*) FILTER (WHERE c.complete) AS has_complete
          FROM has h JOIN comp c ON c.student_id = h.student_id GROUP BY h.item
    ),
    totals AS (SELECT count(*) AS n, count(*) FILTER (WHERE complete) AS complete FROM comp),
    alone AS (SELECT c.missing[1] AS item, count(*) AS n FROM comp c WHERE cardinality(c.missing) = 1 GROUP BY 1)
    SELECT i.item, coalesce(r.required, false),
           t.n::int,
           (t.n - coalesce(k.has_all, 0))::int,
           CASE WHEN coalesce(r.required, false) THEN 0 ELSE (t.complete - coalesce(k.has_complete, 0)) END::int,
           CASE WHEN coalesce(r.required, false) THEN coalesce(a.n, 0) ELSE 0 END::int
      FROM items i
     CROSS JOIN totals t
      LEFT JOIN counts k ON k.item = i.item
      LEFT JOIN alone a ON a.item = i.item
      LEFT JOIN people.biodata_requirement r ON r.item = i.item
$$;
COMMENT ON FUNCTION people.biodata_requirement_impact() IS
  'V427: for each item that can be required (the passport and every open, non-health biodata field), over the students on the register: how many there are, how many lack it, how many complete students requiring it would hold, and how many held students it alone holds — read by Biodata compliance before an item is ticked or unticked.';
