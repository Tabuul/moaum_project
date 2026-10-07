-- ═══════════════════════════════════════════════════════════════════════════
-- V349 — JUPEB: the office's announcements, practice questions with images and formulas, and the student identity card
--
--   · Announcements: the JUPEB Office publishes a notice to a session's candidates — everyone, those not yet admitted, the
--     admitted, the students, one class, one subject combination or one programme. It shows on each reached candidate's
--     dashboard (read or unread, pinned first, until it expires or is withdrawn with a reason) and, when the office asks, is
--     also emailed and texted through the University's notice queue. A withdrawn notice stops showing; nothing is deleted.
--   · Practice questions: a question may carry one image (a diagram, a graph, a structure), kept private (the object store or
--     the database), shown to the office and to a student only inside an attempt that drew the question. A question is edited
--     in place until someone has answered it; after that an edit makes a new version and the old one stays with the attempts
--     that used it. Formulas are written in the text ($x^2$, $H_2O$, $\frac{1}{2}mv^2$) and drawn by the portal.
--   · The identity card: an active JUPEB student with a passport photograph on file has a card whose QR carries a code issued
--     like the other JUPEB papers (jupeb.issue_paper, kind ID_CARD) and verified at /verify/jupeb/{code}. A lost or damaged card
--     is replaced by revoking the old code with a reason and issuing a new one.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V349: JUPEB announcements, practice images and formulas, identity card', true);

-- ── 1 · announcements ────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.announcement (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session          text NOT NULL CHECK (session ~ '^[0-9]{4}/[0-9]{4}$'),
    audience         text NOT NULL CHECK (audience IN ('ALL', 'APPLICANTS', 'ADMITTED', 'STUDENTS', 'CLASS', 'COMBINATION', 'PROGRAMME')),
    audience_ref     text NULL,
    title            text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 160),
    body             text NOT NULL CHECK (length(btrim(body)) BETWEEN 3 AND 5000),
    pinned           boolean NOT NULL DEFAULT false,
    send_email       boolean NOT NULL DEFAULT false,
    send_sms         boolean NOT NULL DEFAULT false,
    expires_on       date NULL,
    published_at     timestamptz NOT NULL DEFAULT now(),
    created_by       uuid NULL,
    created_office   text NULL,
    notified         int NULL,
    withdrawn_at     timestamptz NULL,
    withdrawn_by     uuid NULL,
    withdrawn_reason text NULL,
    CONSTRAINT ck_jupeb_ann_ref CHECK ((audience IN ('CLASS', 'COMBINATION', 'PROGRAMME')) = (audience_ref IS NOT NULL)),
    CONSTRAINT ck_jupeb_ann_programme CHECK (audience <> 'PROGRAMME' OR audience_ref IN ('SCIENCE', 'NON_SCIENCE')),
    CONSTRAINT ck_jupeb_ann_withdrawn CHECK ((withdrawn_at IS NULL) = (withdrawn_reason IS NULL))
);
CREATE INDEX ix_jupeb_ann_session ON jupeb.announcement (session, published_at DESC) WHERE withdrawn_at IS NULL;
SELECT audit.attach('jupeb.announcement');
COMMENT ON TABLE jupeb.announcement IS 'V349: a notice the JUPEB Office publishes to a session''s candidates (an audience, or one class, combination or programme); shown on the dashboard, optionally emailed and texted; withdrawn with a reason, never deleted.';

CREATE TABLE jupeb.announcement_read (
    announcement_id uuid NOT NULL REFERENCES jupeb.announcement(id),
    application_id  uuid NOT NULL REFERENCES jupeb.application(id),
    read_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (announcement_id, application_id)
);
SELECT audit.exempt('jupeb.announcement_read', 'Which candidate opened which notice, for the unread mark and the office''s read count; it changes nothing on the record.');

-- whom a notice reaches: the session's candidates in its audience; a withdrawn application is reached by nothing
CREATE OR REPLACE FUNCTION jupeb.audience_reaches(p_session text, p_audience text, p_ref text, p_app jupeb.application)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT p_app.session = p_session AND p_app.state <> 'WITHDRAWN' AND CASE p_audience
        WHEN 'ALL' THEN true
        WHEN 'APPLICANTS' THEN p_app.state IN ('DRAFT', 'SUBMITTED', 'RETURNED', 'UNDER_REVIEW', 'ELIGIBLE', 'PENDING')
        WHEN 'ADMITTED' THEN p_app.state IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED')
        WHEN 'STUDENTS' THEN p_app.state IN ('STUDENT', 'COMPLETED')
        WHEN 'CLASS' THEN p_app.class_id::text = p_ref
        WHEN 'COMBINATION' THEN EXISTS (SELECT 1 FROM jupeb.combination c WHERE c.id = p_app.combination_id AND upper(c.code) = upper(p_ref))
        WHEN 'PROGRAMME' THEN (CASE WHEN p_app.stream = 'ARTS' THEN 'NON_SCIENCE' ELSE p_app.stream END) = p_ref
        ELSE false END
$$;

-- how many a notice of this audience would reach now (the office sees it before publishing)
CREATE OR REPLACE FUNCTION jupeb.announcement_reach(p_session text, p_audience text, p_ref text)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT count(*)::int FROM jupeb.application a WHERE jupeb.audience_reaches(p_session, p_audience, nullif(btrim(coalesce(p_ref, '')), ''), a)
$$;

-- the notice emailed and texted to those it reaches, as the office asked; the count is kept on the notice
CREATE OR REPLACE FUNCTION jupeb.announcement_notify(p_ann uuid)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n jupeb.announcement; a jupeb.application; k int := 0;
BEGIN
    SELECT * INTO n FROM jupeb.announcement WHERE id = p_ann;
    IF n.id IS NULL OR n.withdrawn_at IS NOT NULL OR NOT (n.send_email OR n.send_sms) THEN RETURN 0; END IF;
    IF coalesce(current_setting('moaum.jupeb_quiet', true), '') = 'on' THEN RETURN 0; END IF;
    FOR a IN SELECT * FROM jupeb.application x WHERE jupeb.audience_reaches(n.session, n.audience, n.audience_ref, x) LOOP
        IF n.send_email AND a.email IS NOT NULL THEN
            PERFORM platform.queue_notice('EMAIL', a.email, n.title,
                'Dear ' || a.first_name || ',' || E'\n\n' || n.body || E'\n\n' || 'Application number: ' || a.application_no || E'\n'
                || 'JUPEB Office, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'jupeb_announcement', n.id);
        END IF;
        IF n.send_sms AND a.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', a.phone, n.title, 'MOAUM JUPEB: ' || left(n.title, 100) || '. Sign in to the JUPEB portal to read it.', 'jupeb_announcement', n.id);
        END IF;
        k := k + 1;
    END LOOP;
    UPDATE jupeb.announcement SET notified = k WHERE id = n.id;
    RETURN k;
END $$;

-- ── 2 · practice questions: an image each, and edits that never rewrite an answered question ──────────────────────
CREATE TABLE jupeb.practice_image (
    question_id  uuid PRIMARY KEY REFERENCES jupeb.practice_question(id),
    filename     text NOT NULL,
    content_type text NOT NULL CHECK (content_type IN ('image/png', 'image/jpeg')),
    size_bytes   int NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 1048576),
    object_id    uuid NULL REFERENCES platform.file_object(id),
    uploaded_by  uuid NULL,
    uploaded_at  timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.practice_image');
COMMENT ON TABLE jupeb.practice_image IS 'V349: the one image of a practice question (PNG or JPEG, at most 1 MB): in the object store (object_id) or, without one, in jupeb.practice_image_blob.';
CREATE TABLE jupeb.practice_image_blob (
    question_id uuid PRIMARY KEY REFERENCES jupeb.practice_image(question_id) ON DELETE CASCADE,
    bytes       bytea NOT NULL
);
SELECT audit.exempt('jupeb.practice_image_blob', 'The bytes of a practice question''s image kept in the database when no object store is configured; the image row on the spine records who uploaded it.');

-- one question checked as the upload checks it; the message when it is refused, NULL when it stands
CREATE OR REPLACE FUNCTION jupeb.practice_row_problem(r jsonb)
RETURNS text
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN nullif(btrim(coalesce(r->>'question', '')), '') IS NULL OR nullif(btrim(coalesce(r->>'a', '')), '') IS NULL OR nullif(btrim(coalesce(r->>'b', '')), '') IS NULL
            THEN 'A question needs its text and at least options A and B.'
        WHEN upper(left(btrim(coalesce(r->>'answer', '')), 1)) NOT IN ('A', 'B', 'C', 'D', 'E')
             OR nullif(btrim(coalesce(r->>lower(upper(left(btrim(coalesce(r->>'answer', '')), 1))), '')), '') IS NULL
            THEN 'The answer must be the letter of one of the options given.'
        WHEN length(r->>'question') > 4000 OR length(coalesce(r->>'explanation', '')) > 4000 THEN 'A question and its explanation are at most 4,000 characters each.'
    END
$$;

-- one question added; its id back (the office then attaches an image to it)
CREATE OR REPLACE FUNCTION jupeb.practice_add(p_test uuid, p_row jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_problem text := jupeb.practice_row_problem(p_row); v_id uuid; v_ord int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_test WHERE id = p_test) THEN RAISE EXCEPTION 'JUPEB_PRACTICE_TEST: no such test' USING ERRCODE = '23514'; END IF;
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: %', v_problem USING ERRCODE = '23514'; END IF;
    SELECT coalesce(max(ordinal), 0) + 1 INTO v_ord FROM jupeb.practice_question WHERE test_id = p_test;
    INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, option_c, option_d, option_e, answer, explanation)
    VALUES (p_test, v_ord, btrim(p_row->>'question'), btrim(p_row->>'a'), btrim(p_row->>'b'), nullif(btrim(coalesce(p_row->>'c', '')), ''),
            nullif(btrim(coalesce(p_row->>'d', '')), ''), nullif(btrim(coalesce(p_row->>'e', '')), ''), upper(left(btrim(p_row->>'answer'), 1)),
            nullif(btrim(coalesce(p_row->>'explanation', '')), ''))
    RETURNING id INTO v_id;
    UPDATE jupeb.practice_test SET updated_at = now() WHERE id = p_test;
    RETURN v_id;
END $$;

-- a question edited: in place until someone answered it; after that a new version takes its place (and its image), and the old
-- one stays, inactive, with the attempts that drew it — a past attempt is never re-marked
CREATE OR REPLACE FUNCTION jupeb.practice_edit(p_test uuid, p_question uuid, p_row jsonb)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE q jupeb.practice_question; v_problem text := jupeb.practice_row_problem(p_row); v_id uuid;
BEGIN
    SELECT * INTO q FROM jupeb.practice_question WHERE id = p_question AND test_id = p_test AND active FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: no such question in this test' USING ERRCODE = '23514'; END IF;
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_QUESTION: %', v_problem USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jupeb.practice_answer x WHERE x.question_id = q.id)
       AND NOT EXISTS (SELECT 1 FROM jupeb.practice_attempt t WHERE q.id = ANY (t.question_ids)) THEN
        UPDATE jupeb.practice_question SET stem = btrim(p_row->>'question'), option_a = btrim(p_row->>'a'), option_b = btrim(p_row->>'b'),
               option_c = nullif(btrim(coalesce(p_row->>'c', '')), ''), option_d = nullif(btrim(coalesce(p_row->>'d', '')), ''),
               option_e = nullif(btrim(coalesce(p_row->>'e', '')), ''), answer = upper(left(btrim(p_row->>'answer'), 1)),
               explanation = nullif(btrim(coalesce(p_row->>'explanation', '')), '')
         WHERE id = q.id;
        v_id := q.id;
    ELSE
        UPDATE jupeb.practice_question SET active = false WHERE id = q.id;
        INSERT INTO jupeb.practice_question (test_id, ordinal, stem, option_a, option_b, option_c, option_d, option_e, answer, explanation)
        VALUES (p_test, q.ordinal, btrim(p_row->>'question'), btrim(p_row->>'a'), btrim(p_row->>'b'), nullif(btrim(coalesce(p_row->>'c', '')), ''),
                nullif(btrim(coalesce(p_row->>'d', '')), ''), nullif(btrim(coalesce(p_row->>'e', '')), ''), upper(left(btrim(p_row->>'answer'), 1)),
                nullif(btrim(coalesce(p_row->>'explanation', '')), ''))
        RETURNING id INTO v_id;
        INSERT INTO jupeb.practice_image (question_id, filename, content_type, size_bytes, object_id, uploaded_by, uploaded_at)
        SELECT v_id, i.filename, i.content_type, i.size_bytes, i.object_id, i.uploaded_by, i.uploaded_at FROM jupeb.practice_image i WHERE i.question_id = q.id;
        INSERT INTO jupeb.practice_image_blob (question_id, bytes) SELECT v_id, b.bytes FROM jupeb.practice_image_blob b WHERE b.question_id = q.id;
    END IF;
    UPDATE jupeb.practice_test SET updated_at = now() WHERE id = p_test;
    RETURN v_id;
END $$;

-- a student sees a question's image only inside an attempt of theirs that drew it
CREATE OR REPLACE FUNCTION jupeb.practice_image_visible(p_app uuid, p_attempt uuid, p_question uuid)
RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM jupeb.practice_attempt t WHERE t.id = p_attempt AND t.application_id = p_app AND p_question = ANY (t.question_ids))
$$;

-- the attempt's paper says which questions carry an image
CREATE OR REPLACE FUNCTION jupeb.practice_paper(p_app uuid, p_attempt uuid)
RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE at jupeb.practice_attempt; t jupeb.practice_test; v_over boolean;
BEGIN
    SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt AND application_id = p_app;
    IF at.id IS NULL THEN RAISE EXCEPTION 'JUPEB_PRACTICE_ATTEMPT: no such attempt' USING ERRCODE = '23514'; END IF;
    IF at.submitted_at IS NULL AND at.ends_at < now() THEN
        PERFORM jupeb.practice_submit(p_app, p_attempt);
        SELECT * INTO at FROM jupeb.practice_attempt WHERE id = p_attempt;
    END IF;
    SELECT * INTO t FROM jupeb.practice_test WHERE id = at.test_id;
    v_over := at.submitted_at IS NOT NULL;
    RETURN jsonb_build_object(
        'attempt', jsonb_build_object('id', at.id, 'number', at.number, 'startedAt', at.started_at, 'endsAt', at.ends_at, 'submittedAt', at.submitted_at,
                                      'score', at.score, 'total', at.total, 'percentage', at.percentage, 'answered', at.answered, 'secondsLeft',
                                      greatest(0, floor(extract(epoch FROM at.ends_at - now())))::int),
        'test', jsonb_build_object('id', t.id, 'title', t.title, 'instructions', t.instructions, 'durationMinutes', t.duration_minutes, 'showAnswers', t.show_answers),
        'questions', (SELECT coalesce(jsonb_agg(
                         jsonb_build_object('id', q.id, 'n', o.n, 'stem', q.stem,
                                            'options', jsonb_strip_nulls(jsonb_build_object('A', q.option_a, 'B', q.option_b, 'C', q.option_c, 'D', q.option_d, 'E', q.option_e)),
                                            'chosen', x.chosen,
                                            'image', EXISTS (SELECT 1 FROM jupeb.practice_image i WHERE i.question_id = q.id))
                         || CASE WHEN v_over AND t.show_answers THEN jsonb_build_object('answer', q.answer, 'correct', coalesce(x.correct, false), 'explanation', q.explanation)
                                 WHEN v_over THEN jsonb_build_object('correct', coalesce(x.correct, false)) ELSE '{}'::jsonb END
                         ORDER BY o.n), '[]'::jsonb)
                        FROM unnest(at.question_ids) WITH ORDINALITY o(qid, n)
                        JOIN jupeb.practice_question q ON q.id = o.qid
                        LEFT JOIN jupeb.practice_answer x ON x.attempt_id = at.id AND x.question_id = q.id));
END $$;
COMMENT ON FUNCTION jupeb.practice_paper(uuid, uuid) IS 'V347, V349: an attempt''s questions for the student — the options, their own choices and whether each has an image; the answer key and the explanations only after the attempt is submitted (and only where the test shows answers).';

-- ── 3 · the identity card, a verifiable JUPEB paper ──────────────────────────────────────────────────────────────
ALTER TABLE jupeb.paper DROP CONSTRAINT ck_jupeb_paper_kind;
ALTER TABLE jupeb.paper ADD CONSTRAINT ck_jupeb_paper_kind
    CHECK (kind IN ('RESULT', 'ADMISSION_LETTER', 'ACCEPTANCE_LETTER', 'STATUS_SLIP', 'REGISTRATION_SLIP', 'ACKNOWLEDGEMENT', 'RECEIPT', 'ID_CARD'));

CREATE OR REPLACE FUNCTION jupeb.paper_facts(p_app uuid, p_kind text, p_ref text, p_office boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE a jupeb.application; v_comb text; ck record; base jsonb; gp record; v_acc timestamptz; fr jupeb.fee_reference;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN NULL; END IF;
    v_comb := (SELECT c.code FROM jupeb.combination c WHERE c.id = a.combination_id);
    SELECT * INTO ck FROM jupeb.status_checking(p_app);
    v_acc := jupeb.paid_at(p_app, 'ACCEPTANCE');
    base := jsonb_build_object('name', upper(a.surname) || ' ' || a.first_name || coalesce(' ' || a.middle_name, ''), 'applicationNo', a.application_no,
        'session', a.session, 'programme', CASE a.stream WHEN 'SCIENCE' THEN 'Science' WHEN 'NON_SCIENCE' THEN 'Non-Science' END, 'combination', v_comb);
    IF p_kind = 'ACKNOWLEDGEMENT' THEN
        IF a.submitted_at IS NULL OR a.state IN ('DRAFT', 'WITHDRAWN') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('submittedOn', (a.submitted_at AT TIME ZONE 'Africa/Lagos')::date);
    ELSIF p_kind = 'STATUS_SLIP' THEN
        IF NOT (p_office OR ck.may_check) OR ck.status IS NULL OR a.state = 'WITHDRAWN' THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('admissionStatus', ck.status, 'admissionRef', a.admission_ref);
    ELSIF p_kind = 'ADMISSION_LETTER' THEN
        IF NOT (p_office OR ck.may_check) OR a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('admissionRef', a.admission_ref, 'admittedOn', (a.admission_decided_at AT TIME ZONE 'Africa/Lagos')::date);
    ELSIF p_kind = 'ACCEPTANCE_LETTER' THEN
        IF v_acc IS NULL OR a.state NOT IN ('ADMITTED', 'STUDENT', 'COMPLETED', 'DEFERRED') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('admissionRef', a.admission_ref, 'acceptedOn', (v_acc AT TIME ZONE 'Africa/Lagos')::date);
    ELSIF p_kind = 'REGISTRATION_SLIP' THEN
        IF a.subjects_registered_at IS NULL OR a.state = 'WITHDRAWN' THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('examNo', a.exam_no, 'registeredOn', (a.subjects_registered_at AT TIME ZONE 'Africa/Lagos')::date,
            'subjects', (SELECT coalesce(jsonb_agg(s.title ORDER BY s.title), '[]') FROM jupeb.subject_registration r JOIN jupeb.subject s ON s.id = r.subject_id WHERE r.application_id = p_app));
    ELSIF p_kind = 'RESULT' THEN
        /* only a published result is verifiable: an unpublished statement printed by the office carries no code */
        IF NOT jupeb.results_published(a.session) OR NOT EXISTS (SELECT 1 FROM jupeb.result r WHERE r.application_id = p_app) OR a.state = 'WITHDRAWN' THEN RETURN NULL; END IF;
        SELECT * INTO gp FROM jupeb.grade_point(p_app);
        RETURN base || jsonb_build_object('examNo', a.exam_no, 'examination', (jupeb.setting_of(a.session)).exam_month,
            'grades', (SELECT coalesce(jsonb_agg(jsonb_build_object('subject', s.title, 'grade', r.grade) ORDER BY s.title), '[]')
                         FROM jupeb.result r JOIN jupeb.subject s ON s.id = r.subject_id WHERE r.application_id = p_app),
            'gradePoint', trim(to_char(gp.total, 'FM990.##')) || '/' || gp.out_of);
    ELSIF p_kind = 'ID_CARD' THEN
        /* V349: the identity card of an active student with a passport photograph on file; it states who they are in which session,
           never the NIN, the date of birth or a contact — the examination number is left off, so its arrival does not void the card */
        IF a.state NOT IN ('STUDENT', 'COMPLETED')
           OR NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = p_app AND d.kind = 'PASSPORT') THEN RETURN NULL; END IF;
        RETURN base || jsonb_build_object('validFor', a.session);
    ELSIF p_kind = 'RECEIPT' THEN
        SELECT * INTO fr FROM jupeb.fee_reference x WHERE x.application_id = p_app AND upper(x.reference) = upper(btrim(coalesce(p_ref, ''))) AND x.confirmed_at IS NOT NULL;
        IF fr.id IS NULL THEN RETURN NULL; END IF;
        RETURN jsonb_build_object('name', base->'name', 'applicationNo', a.application_no, 'session', fr.session, 'reference', fr.reference, 'fee', fr.kind,
            'amount', fr.amount, 'paidOn', (fr.confirmed_at AT TIME ZONE 'Africa/Lagos')::date);
    END IF;
    RETURN NULL;
END $$;

-- ── 4 · the read-only and admissions roles reach the JUPEB tables of V347 and V349, as they reach the earlier ones ──
GRANT SELECT ON jupeb.legacy_payment, jupeb.timetable_slot, jupeb.practice_test, jupeb.practice_question, jupeb.practice_attempt, jupeb.practice_answer,
                jupeb.announcement, jupeb.announcement_read, jupeb.practice_image, jupeb.practice_image_blob TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.legacy_payment, jupeb.timetable_slot, jupeb.practice_test, jupeb.practice_question, jupeb.practice_attempt,
                jupeb.practice_answer, jupeb.announcement, jupeb.announcement_read, jupeb.practice_image, jupeb.practice_image_blob TO app_admissions;

COMMIT;
