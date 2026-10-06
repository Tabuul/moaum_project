-- ═══════════════════════════════════════════════════════════════════════════
-- V341 — JUPEB: the applicant chooses Science or Arts; the subject combination is chosen at subject registration
--
--   The University asked for a simpler application. The form no longer asks for a programme of interest or a subject
--   combination: the applicant chooses SCIENCE or ARTS (jupeb.application.stream). That choice decides the school fee
--   directly — Science pays the Bursary's Science fee, Arts the other fee — so the faculty mapping is no longer needed for
--   a new application (it remains only for an application made before this, which named a programme).
--
--   The Board still examines three subjects, so the combination is not dropped: an active student chooses one of the
--   approved combinations of their stream when registering subjects (Science: a combination of the Science or Engineering
--   area; Arts: any other area; a combination with no area is open to both). Examination numbers and results follow as before.
--   Applications already holding a programme or a combination keep them.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V341: JUPEB — Science or Arts on the application', true);

ALTER TABLE jupeb.application ADD COLUMN stream text NULL;
ALTER TABLE jupeb.application ADD CONSTRAINT ck_jupeb_app_stream CHECK (stream IS NULL OR stream IN ('SCIENCE', 'ARTS'));
CREATE INDEX ix_jupeb_app_stream ON jupeb.application (session, stream);
COMMENT ON COLUMN jupeb.application.stream IS 'V341: SCIENCE or ARTS, the applicant''s choice on the application; decides the school fee (Science, or the other fee for Arts) and the combinations offered at subject registration';

/* a combination suits a stream: Science takes the Science and Engineering areas, Arts every other; no area suits both */
CREATE OR REPLACE FUNCTION jupeb.combination_suits(p_area text, p_stream text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT p_stream IS NULL OR p_area IS NULL
        OR (p_stream = 'SCIENCE' AND p_area IN ('Science', 'Engineering'))
        OR (p_stream = 'ARTS' AND p_area NOT IN ('Science', 'Engineering'))
$$;

/* the school fee: the category is the applicant's stream (Arts pays the OTHER fee); an older application falls back to the faculty mapping */
CREATE OR REPLACE FUNCTION jupeb.school_fees(p_app uuid)
RETURNS TABLE (category text, indigene boolean, total numeric, first_percent numeric, first_amount numeric, second_amount numeric,
               allow_full boolean, first_paid boolean, second_paid boolean, full_paid boolean, paid numeric, outstanding numeric, status text, frozen boolean)
LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT * FROM jupeb.application WHERE id = p_app),
    fs AS (SELECT f.* FROM a CROSS JOIN LATERAL jupeb.fee_setting_of(a.session) f),
    c AS (SELECT coalesce(a.fee_category, CASE a.stream WHEN 'SCIENCE' THEN 'SCIENCE' WHEN 'ARTS' THEN 'OTHER' END, jupeb.category_of(a.programme_code)) AS category,
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

/* what still stands between an application and its submission: Science or Arts in place of the programme and combination */
CREATE OR REPLACE FUNCTION jupeb.missing(p_app uuid)
RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT array_remove(ARRAY[
        CASE WHEN a.fee_confirmed_at IS NULL THEN 'The application fee is not yet paid' END,
        CASE WHEN a.sex IS NULL OR a.date_of_birth IS NULL THEN 'Sex and date of birth' END,
        CASE WHEN a.nin IS NULL THEN 'NIN' END,
        CASE WHEN a.phone IS NULL THEN 'Phone number' END,
        CASE WHEN a.state_of_origin IS NULL OR a.lga IS NULL THEN 'State of origin and LGA' END,
        CASE WHEN a.contact_address IS NULL THEN 'Contact address' END,
        CASE WHEN a.next_of_kin_name IS NULL OR a.next_of_kin_phone IS NULL THEN 'Next of kin and their phone' END,
        CASE WHEN a.stream IS NULL AND a.programme_code IS NULL THEN 'Science or Arts' END,
        (SELECT 'O''Level: ' || array_to_string(k.reasons, '; ') FROM jupeb.olevel_check(a.id) k WHERE NOT k.ok),
        (SELECT 'Documents: ' || string_agg(dk.label, ', ' ORDER BY dk.ord) FROM jupeb.document_kind dk
          WHERE dk.active AND dk.required
            AND NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = dk.code AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED')))
    ], NULL)
      FROM jupeb.application a WHERE a.id = p_app
$$;

/* the public application: the account, the application numbered for life with its stream, and the application fee reference */
CREATE OR REPLACE FUNCTION jupeb.apply(p jsonb)
RETURNS TABLE (application_id uuid, application_no text, reference text, amount numeric)
LANGUAGE plpgsql AS $$
DECLARE v_session text := jupeb.current_session(); v_acc uuid; v_app uuid; v_no text; v_ref text; st jupeb.setting;
        v_stream text := upper(btrim(coalesce(p->>'stream', '')));
BEGIN
    IF v_session IS NULL THEN RAISE EXCEPTION 'JUPEB_NO_SESSION: no academic session is on the calendar' USING ERRCODE = '23514'; END IF;
    IF v_stream NOT IN ('SCIENCE', 'ARTS') THEN RAISE EXCEPTION 'JUPEB_STREAM: choose Science or Arts' USING ERRCODE = '23514'; END IF;
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

/* the active student registers the three subjects of a combination of their stream, chosen here (or held from before) */
CREATE OR REPLACE FUNCTION jupeb.register_subjects(p_app uuid, p_actor uuid, p_combination uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.combination; n int;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.state NOT IN ('STUDENT') THEN RAISE EXCEPTION 'JUPEB_NOT_STUDENT: subjects are registered by an active JUPEB student' USING ERRCODE = '23514',
        HINT = 'Pay the school fee the Bursary requires for activation first.'; END IF;
    IF a.subjects_registered_at IS NOT NULL THEN RETURN 0; END IF;
    IF p_combination IS NOT NULL THEN
        SELECT * INTO c FROM jupeb.combination WHERE id = p_combination AND active;
        IF c.id IS NULL THEN RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the approved subject combinations' USING ERRCODE = '23514'; END IF;
        IF NOT jupeb.combination_suits(c.area, a.stream) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a combination for % students', c.code, initcap(a.stream) USING ERRCODE = '23514';
        END IF;
        UPDATE jupeb.application SET combination_id = c.id WHERE id = p_app;
    ELSE
        SELECT * INTO c FROM jupeb.combination WHERE id = a.combination_id;
    END IF;
    IF c.id IS NULL THEN
        RAISE EXCEPTION 'JUPEB_COMBINATION_CHOOSE: choose your subject combination to register' USING ERRCODE = '23514';
    END IF;
    INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
    SELECT p_app, s, a.session, p_actor FROM unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s
    ON CONFLICT (application_id, subject_id) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    UPDATE jupeb.application SET subjects_registered_at = now() WHERE id = p_app;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION jupeb.register_subjects(p_app uuid, p_actor uuid)
RETURNS int LANGUAGE sql AS $$ SELECT jupeb.register_subjects(p_app, p_actor, NULL::uuid) $$;

COMMIT;
