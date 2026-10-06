-- ═══════════════════════════════════════════════════════════════════════════
-- V343 — JUPEB: verifiable papers, change requests after submission, and reminders
--
--   1. VERIFIABLE PAPERS. Every statement of result, admission and acceptance letter, admission status slip, registration
--      slip, acknowledgement and receipt the portal prints carries a code (XXXX-XXXX-XXXX, 60 random bits) and a QR to
--      /verify/jupeb/{code}. The code is stored with the facts the paper printed — read from the record by the server, never
--      from the page — and its fingerprint. The public verifier shows the University's record: genuine and current, genuine
--      but superseded (the record has changed since — a corrected grade, a withdrawn admission), or not genuine (unknown or
--      revoked by the JUPEB Office). The same paper printed again for an unchanged record carries the same code.
--   2. CHANGE REQUESTS. After submission a candidate (or the JUPEB Office for them) asks to WITHDRAW, to DEFER an accepted
--      admission to a later session, to CHANGE_COMBINATION (until the Board's examination number is assigned) or to
--      CHANGE_PROGRAMME (until a school fee is charged), always with a reason. One request is open at a time; the JUPEB
--      Office approves or declines it (declining says why). Nothing is deleted: the request keeps what it changed from and
--      to. A new state, DEFERRED, holds a deferred admission until the JUPEB Office resumes it in the later session.
--   3. REMINDERS. Once a day the portal reminds a candidate who has not paid the application fee, has paid but not
--      submitted, has no passport photograph, has not checked an open admission status, has not paid the acceptance fee,
--      or owes school fees — at most one reminder a day, each kind on the JUPEB Office's own rule (when it starts, how
--      often, how many times, whether also by SMS). Every reminder sent is logged.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V343: JUPEB verifiable papers, change requests and reminders', true);

-- ── 0 · the new state and what it records ────────────────────────────────────────────────────────
ALTER TABLE jupeb.application DROP CONSTRAINT ck_jupeb_app_state;
ALTER TABLE jupeb.application ADD CONSTRAINT ck_jupeb_app_state CHECK (state IN ('DRAFT', 'SUBMITTED', 'RETURNED', 'ELIGIBLE', 'INELIGIBLE', 'ADMITTED', 'NOT_ADMITTED',
    'PENDING', 'STUDENT', 'COMPLETED', 'WITHDRAWN', 'DEFERRED'));
ALTER TABLE jupeb.application ADD COLUMN withdrawn_at timestamptz NULL;
ALTER TABLE jupeb.application ADD COLUMN deferred_from text NULL;
ALTER TABLE jupeb.application ADD COLUMN deferred_to text NULL;
ALTER TABLE jupeb.application ADD CONSTRAINT ck_jupeb_app_deferred CHECK ((state = 'DEFERRED') <= (deferred_to IS NOT NULL));
COMMENT ON COLUMN jupeb.application.deferred_to IS 'V343: the session an admission is deferred to (state DEFERRED until the JUPEB Office resumes it there)';

-- ── 1 · verifiable papers ────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.paper (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code           text NOT NULL UNIQUE,
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    kind           text NOT NULL,
    subject_ref    text NULL,
    facts          jsonb NOT NULL,
    fingerprint    text NOT NULL,
    issued_at      timestamptz NOT NULL DEFAULT now(),
    issued_by      uuid NULL,
    issued_office  text NULL,
    revoked_at     timestamptz NULL,
    revoked_by     uuid NULL,
    revoked_reason text NULL,
    CONSTRAINT ck_jupeb_paper_code CHECK (code ~ '^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$'),
    CONSTRAINT ck_jupeb_paper_kind CHECK (kind IN ('RESULT', 'ADMISSION_LETTER', 'ACCEPTANCE_LETTER', 'STATUS_SLIP', 'REGISTRATION_SLIP', 'ACKNOWLEDGEMENT', 'RECEIPT')),
    CONSTRAINT ck_jupeb_paper_revoked CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
CREATE INDEX ix_jupeb_paper_app ON jupeb.paper (application_id, issued_at DESC);
CREATE UNIQUE INDEX ux_jupeb_paper_same ON jupeb.paper (application_id, kind, coalesce(subject_ref, ''), fingerprint) WHERE revoked_at IS NULL;
SELECT audit.attach('jupeb.paper');
COMMENT ON TABLE jupeb.paper IS 'V343: a JUPEB paper the portal issued, with the code its QR carries and the facts it printed (read from the record by the server); verified at /verify/jupeb/{code} against the record as it stands.';

/* what a paper of this kind states for this candidate now — NULL when the record does not support the paper. p_office: the
   JUPEB Office (and the verifier) see the decision before the candidate has paid to check it */
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
    ELSIF p_kind = 'RECEIPT' THEN
        SELECT * INTO fr FROM jupeb.fee_reference x WHERE x.application_id = p_app AND upper(x.reference) = upper(btrim(coalesce(p_ref, ''))) AND x.confirmed_at IS NOT NULL;
        IF fr.id IS NULL THEN RETURN NULL; END IF;
        RETURN jsonb_build_object('name', base->'name', 'applicationNo', a.application_no, 'session', fr.session, 'reference', fr.reference, 'fee', fr.kind,
            'amount', fr.amount, 'paidOn', (fr.confirmed_at AT TIME ZONE 'Africa/Lagos')::date);
    END IF;
    RETURN NULL;
END $$;

/* twelve characters from a 32-letter alphabet (no 0/O, 1/I), from the operating system's random source through gen_random_uuid */
CREATE OR REPLACE FUNCTION jupeb.paper_code()
RETURNS text LANGUAGE plpgsql VOLATILE AS $$
DECLARE b bytea := uuid_send(gen_random_uuid()); al text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; s text := ''; i int;
BEGIN
    /* bytes 6 and 8 carry the UUID's version and variant bits; the other fourteen are random */
    FOREACH i IN ARRAY ARRAY[0, 1, 2, 3, 4, 5, 7, 9, 10, 11, 12, 13] LOOP
        s := s || substr(al, (get_byte(b, i) % 32) + 1, 1);
    END LOOP;
    RETURN substr(s, 1, 4) || '-' || substr(s, 5, 4) || '-' || substr(s, 9, 4);
END $$;

/* the code for a paper: the same code while the record it states is unchanged, a new one when it changes */
CREATE OR REPLACE FUNCTION jupeb.issue_paper(p_app uuid, p_kind text, p_ref text, p_office boolean, p_actor uuid, p_actor_office text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_facts jsonb; v_fp text; v_code text; v_ref text := nullif(upper(btrim(coalesce(p_ref, ''))), '');
BEGIN
    v_facts := jupeb.paper_facts(p_app, p_kind, v_ref, p_office);
    IF v_facts IS NULL THEN
        RAISE EXCEPTION 'JUPEB_PAPER_NOT_ISSUABLE: the record does not support this paper as it stands' USING ERRCODE = '23514';
    END IF;
    v_fp := md5(v_facts::text);
    SELECT code INTO v_code FROM jupeb.paper
     WHERE application_id = p_app AND kind = p_kind AND coalesce(subject_ref, '') = coalesce(v_ref, '') AND fingerprint = v_fp AND revoked_at IS NULL;
    IF v_code IS NOT NULL THEN RETURN v_code; END IF;
    LOOP
        v_code := jupeb.paper_code();
        INSERT INTO jupeb.paper (code, application_id, kind, subject_ref, facts, fingerprint, issued_by, issued_office)
        VALUES (v_code, p_app, p_kind, v_ref, v_facts, v_fp, p_actor, p_actor_office)
        ON CONFLICT DO NOTHING;
        EXIT WHEN FOUND;
        /* a concurrent issue of the same paper won the unique index: take its code */
        SELECT code INTO v_code FROM jupeb.paper
         WHERE application_id = p_app AND kind = p_kind AND coalesce(subject_ref, '') = coalesce(v_ref, '') AND fingerprint = v_fp AND revoked_at IS NULL;
        IF v_code IS NOT NULL THEN RETURN v_code; END IF;
    END LOOP;
    RETURN v_code;
END $$;

/* the public verifier: only what the paper itself printed, and whether the record still says it */
CREATE OR REPLACE FUNCTION jupeb.verify_paper(p_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE k text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); p jupeb.paper; cur jsonb; v_state text;
BEGIN
    IF length(k) <> 12 THEN RETURN jsonb_build_object('genuine', false); END IF;
    SELECT * INTO p FROM jupeb.paper WHERE code = substr(k, 1, 4) || '-' || substr(k, 5, 4) || '-' || substr(k, 9, 4);
    IF p.id IS NULL THEN RETURN jsonb_build_object('genuine', false); END IF;
    IF p.revoked_at IS NOT NULL THEN
        RETURN jsonb_build_object('genuine', false, 'revoked', true, 'kind', p.kind, 'revokedOn', (p.revoked_at AT TIME ZONE 'Africa/Lagos')::date);
    END IF;
    cur := jupeb.paper_facts(p.application_id, p.kind, p.subject_ref, true);
    v_state := (SELECT a.state FROM jupeb.application a WHERE a.id = p.application_id);
    RETURN jsonb_build_object('genuine', true, 'code', p.code, 'kind', p.kind, 'issuedOn', (p.issued_at AT TIME ZONE 'Africa/Lagos')::date, 'facts', p.facts,
        'current', cur IS NOT NULL AND md5(cur::text) = p.fingerprint,
        'currentFacts', CASE WHEN cur IS NOT NULL AND md5(cur::text) <> p.fingerprint THEN cur END,
        'withdrawn', v_state = 'WITHDRAWN', 'deferred', v_state = 'DEFERRED');
END $$;

CREATE OR REPLACE FUNCTION jupeb.revoke_paper(p_code text, p_reason text, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'JUPEB_PAPER_REASON: say why the paper is revoked' USING ERRCODE = '23514'; END IF;
    UPDATE jupeb.paper SET revoked_at = now(), revoked_by = p_actor, revoked_reason = btrim(p_reason) WHERE code = upper(btrim(p_code)) AND revoked_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'JUPEB_PAPER_UNKNOWN: no live paper has that code' USING ERRCODE = '23514'; END IF;
    PERFORM jupeb.app_event((SELECT application_id FROM jupeb.paper WHERE code = upper(btrim(p_code))), 'PAPER_REVOKED', upper(btrim(p_code)) || ' — ' || btrim(p_reason));
END $$;

-- ── 2 · change requests after submission ─────────────────────────────────────────────────────────
CREATE TABLE jupeb.change_request (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id   uuid NOT NULL REFERENCES jupeb.application(id),
    kind             text NOT NULL CHECK (kind IN ('WITHDRAW', 'DEFER', 'CHANGE_COMBINATION', 'CHANGE_PROGRAMME')),
    from_state       text NOT NULL,
    from_stream      text NULL,
    from_combination uuid NULL REFERENCES jupeb.combination(id),
    to_stream        text NULL,
    to_combination   uuid NULL REFERENCES jupeb.combination(id),
    from_session     text NULL,
    to_session       text NULL,
    reason           text NOT NULL,
    state            text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'APPROVED', 'DECLINED', 'CANCELLED')),
    requested_at     timestamptz NOT NULL DEFAULT now(),
    requested_by     uuid NULL,
    requested_office text NULL,
    decided_at       timestamptz NULL,
    decided_by       uuid NULL,
    decided_office   text NULL,
    decision_note    text NULL,
    CONSTRAINT ck_jupeb_change_reason CHECK (length(btrim(reason)) >= 10),
    CONSTRAINT ck_jupeb_change_declined CHECK (state <> 'DECLINED' OR length(btrim(coalesce(decision_note, ''))) > 0),
    CONSTRAINT ck_jupeb_change_decided CHECK ((state = 'PENDING') = (decided_at IS NULL))
);
CREATE UNIQUE INDEX ux_jupeb_change_open ON jupeb.change_request (application_id) WHERE state = 'PENDING';
CREATE INDEX ix_jupeb_change_state ON jupeb.change_request (state, requested_at);
SELECT audit.attach('jupeb.change_request');
COMMENT ON TABLE jupeb.change_request IS 'V343: a request, after submission, to withdraw, defer an accepted admission, or change the combination or programme — with its reason, what it would change from and to, and the JUPEB Office''s decision.';

CREATE OR REPLACE FUNCTION jupeb.next_session(p_session text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT (substr(p_session, 1, 4)::int + 1)::text || '/' || (substr(p_session, 6, 4)::int + 1)::text
$$;

/* whether the change can be made to the application as it stands — the same judgement when asked and when approved */
CREATE OR REPLACE FUNCTION jupeb.change_check(p_app uuid, p_kind text, p_stream text, p_combination uuid, p_to_session text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; c jupeb.combination; v_stream text;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'JUPEB_NOT_FOUND: no such application' USING ERRCODE = '23514'; END IF;
    IF a.state IN ('DRAFT', 'RETURNED') THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_EDIT_YOURSELF: an application not yet submitted is changed on the application itself' USING ERRCODE = '23514';
    END IF;
    IF a.state IN ('COMPLETED', 'WITHDRAWN') THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_CLOSED: a % application takes no change request', lower(a.state) USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'WITHDRAW' THEN
        RETURN;
    ELSIF p_kind = 'DEFER' THEN
        IF a.state <> 'ADMITTED' THEN
            RAISE EXCEPTION 'JUPEB_DEFER_STATE: only an admission not yet activated is deferred' USING ERRCODE = '23514';
        END IF;
        IF jupeb.paid_at(p_app, 'ACCEPTANCE') IS NULL THEN
            RAISE EXCEPTION 'JUPEB_DEFER_ACCEPT_FIRST: accept the admission (pay the acceptance fee) before asking to defer it' USING ERRCODE = '23514';
        END IF;
        IF p_to_session IS NULL OR p_to_session !~ '^[0-9]{4}/[0-9]{4}$' OR p_to_session <= a.session
           OR substr(p_to_session, 1, 4)::int > substr(a.session, 1, 4)::int + 2 THEN
            RAISE EXCEPTION 'JUPEB_DEFER_SESSION: an admission is deferred to one of the next two sessions' USING ERRCODE = '23514';
        END IF;
    ELSIF p_kind = 'CHANGE_COMBINATION' THEN
        IF a.state NOT IN ('SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'STUDENT', 'DEFERRED') THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_STATE: the combination is not changed on a % application', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF a.exam_no IS NOT NULL OR EXISTS (SELECT 1 FROM jupeb.result r WHERE r.application_id = p_app) THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_EXAM_NO: the Board already holds this candidate''s subjects (an examination number or a result)' USING ERRCODE = '23514';
        END IF;
        SELECT * INTO c FROM jupeb.combination WHERE id = p_combination;
        IF c.id IS NULL OR NOT jupeb.combination_offered(c.id) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the subject combinations the University offers' USING ERRCODE = '23514';
        END IF;
        IF NOT jupeb.combination_suits(c.area, a.stream) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a % combination', c.code, CASE a.stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
        END IF;
        IF c.id = a.combination_id THEN RAISE EXCEPTION 'JUPEB_CHANGE_SAME: that is already the combination' USING ERRCODE = '23514'; END IF;
    ELSIF p_kind = 'CHANGE_PROGRAMME' THEN
        IF a.state NOT IN ('SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'DEFERRED') THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_STATE: the programme is not changed on a % application', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF a.school_fee_total IS NOT NULL THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_FEES_CHARGED: a school fee is already charged at this programme''s rate' USING ERRCODE = '23514';
        END IF;
        v_stream := CASE upper(regexp_replace(btrim(coalesce(p_stream, '')), '[- ]', '_', 'g')) WHEN 'SCIENCE' THEN 'SCIENCE' WHEN 'NON_SCIENCE' THEN 'NON_SCIENCE' WHEN 'ARTS' THEN 'NON_SCIENCE' END;
        IF v_stream IS NULL THEN RAISE EXCEPTION 'JUPEB_STREAM: choose Science or Non-Science' USING ERRCODE = '23514'; END IF;
        IF v_stream = a.stream THEN RAISE EXCEPTION 'JUPEB_CHANGE_SAME: that is already the programme' USING ERRCODE = '23514'; END IF;
        IF p_combination IS NOT NULL THEN
            SELECT * INTO c FROM jupeb.combination WHERE id = p_combination;
            IF c.id IS NULL OR NOT jupeb.combination_offered(c.id) THEN
                RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the subject combinations the University offers' USING ERRCODE = '23514';
            END IF;
            IF NOT jupeb.combination_suits(c.area, v_stream) THEN
                RAISE EXCEPTION 'JUPEB_COMBINATION_STREAM: % is not a % combination', c.code, CASE v_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END USING ERRCODE = '23514';
            END IF;
        ELSIF EXISTS (SELECT 1 FROM jupeb.combination o WHERE jupeb.combination_offered(o.id) AND jupeb.combination_suits(o.area, v_stream)) THEN
            RAISE EXCEPTION 'JUPEB_COMBINATION_CHOOSE: choose the subject combination of the new programme' USING ERRCODE = '23514';
        END IF;
    ELSE
        RAISE EXCEPTION 'JUPEB_CHANGE_KIND: withdraw, defer, or change the combination or the programme' USING ERRCODE = '23514';
    END IF;
END $$;

CREATE OR REPLACE FUNCTION jupeb.request_change(p_app uuid, p_kind text, p_stream text, p_combination text, p_to_session text, p_reason text, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a jupeb.application; v_comb uuid; v_stream text; v_id uuid; v_kind text := upper(btrim(coalesce(p_kind, ''))); v_to text;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_REASON: give the reason for the request (at least ten characters)' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM jupeb.change_request r WHERE r.application_id = p_app AND r.state = 'PENDING') THEN
        RAISE EXCEPTION 'JUPEB_CHANGE_PENDING: a request is already with the JUPEB Office; cancel it or wait for its decision' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_combination, '')), '') IS NOT NULL THEN
        v_comb := (SELECT c.id FROM jupeb.combination c WHERE c.id::text = btrim(p_combination) OR upper(c.code) = upper(btrim(p_combination)));
        IF v_comb IS NULL THEN RAISE EXCEPTION 'JUPEB_COMBINATION: choose one of the subject combinations the University offers' USING ERRCODE = '23514'; END IF;
    END IF;
    v_to := CASE WHEN v_kind = 'DEFER' THEN coalesce(nullif(btrim(coalesce(p_to_session, '')), ''), jupeb.next_session(a.session)) END;
    PERFORM jupeb.change_check(p_app, v_kind, p_stream, v_comb, v_to);
    v_stream := CASE WHEN v_kind = 'CHANGE_PROGRAMME'
                     THEN CASE upper(regexp_replace(btrim(p_stream), '[- ]', '_', 'g')) WHEN 'SCIENCE' THEN 'SCIENCE' ELSE 'NON_SCIENCE' END END;
    INSERT INTO jupeb.change_request (application_id, kind, from_state, from_stream, from_combination, to_stream, to_combination, from_session, to_session,
                                      reason, requested_by, requested_office)
    VALUES (p_app, v_kind, a.state, a.stream, a.combination_id, v_stream, CASE WHEN v_kind IN ('CHANGE_COMBINATION', 'CHANGE_PROGRAMME') THEN v_comb END,
            a.session, v_to, btrim(p_reason), p_actor, p_office)
    RETURNING id INTO v_id;
    PERFORM jupeb.app_event(p_app, 'CHANGE_REQUESTED', jupeb.change_words(v_id) || ' — ' || btrim(p_reason));
    PERFORM jupeb.tell(p_app, 'Your JUPEB request is received',
        'Your request (' || jupeb.change_words(v_id) || ') is with the JUPEB Office. You will be told of its decision; you can follow it on the JUPEB portal.');
    RETURN v_id;
END $$;

/* "withdraw the application", "change the combination from SC-031 to SC-033" … */
CREATE OR REPLACE FUNCTION jupeb.change_words(p_req uuid)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE r.kind
        WHEN 'WITHDRAW' THEN 'withdraw the application'
        WHEN 'DEFER' THEN 'defer the admission from ' || r.from_session || ' to ' || r.to_session
        WHEN 'CHANGE_COMBINATION' THEN 'change the combination from ' || coalesce(fc.code, 'none') || ' to ' || coalesce(tc.code, '?')
        WHEN 'CHANGE_PROGRAMME' THEN 'change the programme from ' || CASE r.from_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END
                                     || ' to ' || CASE r.to_stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END || coalesce(' (' || tc.code || ')', '') END
      FROM jupeb.change_request r LEFT JOIN jupeb.combination fc ON fc.id = r.from_combination LEFT JOIN jupeb.combination tc ON tc.id = r.to_combination
     WHERE r.id = p_req
$$;

CREATE OR REPLACE FUNCTION jupeb.cancel_change(p_req uuid, p_app uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    UPDATE jupeb.change_request SET state = 'CANCELLED', decided_at = now(), decided_by = p_actor, decided_office = 'applicant', decision_note = 'Cancelled by the candidate'
     WHERE id = p_req AND application_id = p_app AND state = 'PENDING';
    IF NOT FOUND THEN RAISE EXCEPTION 'JUPEB_CHANGE_DECIDED: the request is no longer open' USING ERRCODE = '23514'; END IF;
    PERFORM jupeb.app_event(p_app, 'CHANGE_CANCELLED', 'Request cancelled: ' || jupeb.change_words(p_req));
END $$;

/* the JUPEB Office's decision; an approval is judged again on the application as it now stands, then applied */
CREATE OR REPLACE FUNCTION jupeb.decide_change(p_req uuid, p_approve boolean, p_note text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r jupeb.change_request; a jupeb.application; c jupeb.combination; v_words text;
BEGIN
    SELECT * INTO r FROM jupeb.change_request WHERE id = p_req FOR UPDATE;
    IF r.id IS NULL OR r.state <> 'PENDING' THEN RAISE EXCEPTION 'JUPEB_CHANGE_DECIDED: the request is no longer open' USING ERRCODE = '23514'; END IF;
    v_words := jupeb.change_words(p_req);
    IF NOT p_approve THEN
        IF length(btrim(coalesce(p_note, ''))) = 0 THEN
            RAISE EXCEPTION 'JUPEB_CHANGE_NOTE: say why the request is declined' USING ERRCODE = '23514';
        END IF;
        UPDATE jupeb.change_request SET state = 'DECLINED', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_note = btrim(p_note) WHERE id = p_req;
        PERFORM jupeb.app_event(r.application_id, 'CHANGE_DECLINED', 'Request declined: ' || v_words || ' — ' || btrim(p_note));
        PERFORM jupeb.tell(r.application_id, 'Your JUPEB request is declined', 'The JUPEB Office declined your request to ' || v_words || ': ' || btrim(p_note));
        RETURN;
    END IF;
    PERFORM jupeb.change_check(r.application_id, r.kind, r.to_stream, r.to_combination, r.to_session);
    SELECT * INTO a FROM jupeb.application WHERE id = r.application_id FOR UPDATE;
    IF r.kind = 'WITHDRAW' THEN
        UPDATE jupeb.application SET state = 'WITHDRAWN', withdrawn_at = now() WHERE id = a.id;
    ELSIF r.kind = 'DEFER' THEN
        UPDATE jupeb.application SET state = 'DEFERRED', deferred_from = a.session, deferred_to = r.to_session WHERE id = a.id;
    ELSIF r.kind = 'CHANGE_COMBINATION' THEN
        SELECT * INTO c FROM jupeb.combination WHERE id = r.to_combination;
        UPDATE jupeb.application SET combination_id = c.id WHERE id = a.id;
        IF a.subjects_registered_at IS NOT NULL THEN
            /* no result and no examination number hang on the old subjects (change_check): the registration follows the new combination */
            DELETE FROM jupeb.subject_registration WHERE application_id = a.id;
            INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by)
            SELECT a.id, s, a.session, p_actor FROM unnest(ARRAY[c.subject1, c.subject2, c.subject3]) s;
        END IF;
    ELSIF r.kind = 'CHANGE_PROGRAMME' THEN
        UPDATE jupeb.application SET stream = r.to_stream, combination_id = r.to_combination WHERE id = a.id;
    END IF;
    UPDATE jupeb.change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decided_office = p_office, decision_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = p_req;
    PERFORM jupeb.app_event(r.application_id, 'CHANGE_APPROVED', 'Request approved: ' || v_words || coalesce(' — ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    PERFORM jupeb.tell(r.application_id, 'Your JUPEB request is approved', 'The JUPEB Office approved your request to ' || v_words || '.'
        || coalesce(' ' || nullif(btrim(coalesce(p_note, '')), ''), '')
        || CASE r.kind WHEN 'WITHDRAW' THEN ' Your application is withdrawn. Any refund is the Bursary''s decision under its own rules.'
                       WHEN 'DEFER' THEN ' Your admission is held for ' || r.to_session || '; the JUPEB Office resumes it then.'
                       ELSE ' Sign in to the JUPEB portal to see your record.' END);
END $$;

/* a deferred admission resumed in the session it was deferred to: admitted again there, with what was paid */
CREATE OR REPLACE FUNCTION jupeb.resume_deferment(p_app uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jupeb.application;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL OR a.state <> 'DEFERRED' THEN RAISE EXCEPTION 'JUPEB_NOT_DEFERRED: the admission is not deferred' USING ERRCODE = '23514'; END IF;
    UPDATE jupeb.application SET state = 'ADMITTED', session = a.deferred_to, deferred_to = NULL WHERE id = p_app;
END $$;

/* the trail, V342's, knowing withdrawal, deferment and resumption */
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
            WHEN 'ADMITTED'     THEN CASE WHEN OLD.state = 'DEFERRED' THEN 'Deferred admission resumed for ' || NEW.session
                                          ELSE 'Admitted · ' || coalesce(NEW.admission_ref, '') || coalesce(' — ' || NEW.admission_note, '') END
            WHEN 'NOT_ADMITTED' THEN 'Not admitted' || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'PENDING'      THEN 'Admission decision pending' || coalesce(' — ' || NEW.admission_note, '')
            WHEN 'STUDENT'      THEN 'Activated as a JUPEB student'
            WHEN 'COMPLETED'    THEN 'Results published'
            WHEN 'WITHDRAWN'    THEN 'Application withdrawn'
            WHEN 'DEFERRED'     THEN 'Admission deferred from ' || coalesce(NEW.deferred_from, OLD.session) || ' to ' || coalesce(NEW.deferred_to, '')
            ELSE NEW.state END);
        IF NEW.state = 'SUBMITTED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB application is submitted', 'Your application is submitted to the JUPEB Office for review. Follow it on the JUPEB portal.');
        ELSIF NEW.state = 'RETURNED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your JUPEB application needs a correction', 'The JUPEB Office returned your application for correction: '
                || coalesce(NEW.return_note, '') || ' Sign in, make the correction and submit it again.');
        ELSIF NEW.state = 'ADMITTED' AND OLD.state = 'DEFERRED' THEN
            PERFORM jupeb.tell(NEW.id, 'Your deferred JUPEB admission is resumed', 'Your deferred admission is resumed for the ' || NEW.session
                || ' session. Sign in to the JUPEB portal for your school fees and the next steps.');
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
    IF NEW.combination_id IS DISTINCT FROM OLD.combination_id AND OLD.state NOT IN ('DRAFT', 'RETURNED') THEN
        PERFORM jupeb.app_event(NEW.id, 'COMBINATION_CHANGED', 'Combination ' || coalesce((SELECT code FROM jupeb.combination WHERE id = OLD.combination_id), 'none')
            || ' → ' || coalesce((SELECT code FROM jupeb.combination WHERE id = NEW.combination_id), 'none'));
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

-- ── 3 · reminders ────────────────────────────────────────────────────────────────────────────────
CREATE TABLE jupeb.reminder_rule (
    kind             text PRIMARY KEY CHECK (kind IN ('FEE_UNPAID', 'SUBMIT_PENDING', 'PASSPORT_MISSING', 'CHECKING_OPEN', 'ACCEPTANCE_UNPAID', 'SCHOOL_FEE_UNPAID')),
    enabled          boolean NOT NULL DEFAULT true,
    first_after_days int NOT NULL CHECK (first_after_days BETWEEN 0 AND 60),
    every_days       int NOT NULL CHECK (every_days BETWEEN 1 AND 60),
    max_count        int NOT NULL CHECK (max_count BETWEEN 1 AND 10),
    sms              boolean NOT NULL DEFAULT false,
    ord              int NOT NULL,
    updated_by       uuid NULL,
    updated_at       timestamptz NOT NULL DEFAULT now()
);
SELECT audit.attach('jupeb.reminder_rule');
COMMENT ON TABLE jupeb.reminder_rule IS 'V343: when the portal reminds a JUPEB candidate of each kind of unfinished step — days after it began, every how many days, at most how many times, and whether also by SMS; the JUPEB Office''s to set.';
INSERT INTO jupeb.reminder_rule (kind, first_after_days, every_days, max_count, ord) VALUES
    ('FEE_UNPAID', 2, 3, 3, 1), ('SUBMIT_PENDING', 2, 3, 3, 2), ('PASSPORT_MISSING', 3, 4, 2, 3),
    ('CHECKING_OPEN', 0, 7, 2, 4), ('ACCEPTANCE_UNPAID', 2, 5, 3, 5), ('SCHOOL_FEE_UNPAID', 3, 7, 3, 6);

CREATE TABLE jupeb.reminder_log (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES jupeb.application(id),
    kind           text NOT NULL REFERENCES jupeb.reminder_rule(kind),
    sent_at        timestamptz NOT NULL DEFAULT now(),
    by_sms         boolean NOT NULL DEFAULT false,
    trigger        text NOT NULL DEFAULT 'SCHEDULE' CHECK (trigger IN ('SCHEDULE', 'OFFICE'))
);
CREATE INDEX ix_jupeb_reminder_log ON jupeb.reminder_log (application_id, kind, sent_at DESC);
SELECT audit.attach('jupeb.reminder_log');

/* who is due a reminder now, and of what: at most one kind per candidate (the earliest step first) */
CREATE OR REPLACE FUNCTION jupeb.due_reminders(p_now timestamptz)
RETURNS TABLE (application_id uuid, application_no text, name text, kind text, sent_before int, last_sent timestamptz, detail jsonb)
LANGUAGE sql STABLE AS $$
    WITH a AS (
        SELECT x.id, x.state, x.session, x.created_at, x.fee_confirmed_at, x.returned_at, x.submitted_at, x.activated_at, x.screening_state,
               w.state AS app_window, w.closes_at AS app_closes, ck.valid, ck.window_open AS chk_open, ck.paid AS chk_paid, ck.paid_at AS chk_paid_at,
               ck.may_check, ck.status AS adm_status, jupeb.paid_at(x.id, 'ACCEPTANCE') AS acc_at
          FROM jupeb.application x
          CROSS JOIN LATERAL policy.window_state('JUPEB_APPLICATION', x.session, NULL) w
          CROSS JOIN LATERAL jupeb.status_checking(x.id) ck
         WHERE x.state IN ('DRAFT', 'RETURNED', 'SUBMITTED', 'ELIGIBLE', 'PENDING', 'ADMITTED', 'STUDENT')
    ), cand AS (
        SELECT a.id, 'FEE_UNPAID'::text AS kind, a.created_at AS anchor, jsonb_build_object('closes', a.app_closes) AS detail
          FROM a WHERE a.state = 'DRAFT' AND a.fee_confirmed_at IS NULL AND a.app_window = 'OPEN'
        UNION ALL
        SELECT a.id, 'SUBMIT_PENDING', greatest(a.fee_confirmed_at, coalesce(a.returned_at, a.fee_confirmed_at)), jsonb_build_object('closes', a.app_closes, 'returned', a.state = 'RETURNED')
          FROM a WHERE a.state IN ('DRAFT', 'RETURNED') AND a.fee_confirmed_at IS NOT NULL AND a.app_window = 'OPEN'
        UNION ALL
        SELECT a.id, 'PASSPORT_MISSING', a.created_at, jsonb_build_object('closes', a.app_closes)
          FROM a WHERE a.state IN ('DRAFT', 'RETURNED') AND a.app_window = 'OPEN'
           AND NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = a.id AND d.kind = 'PASSPORT' AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED'))
        UNION ALL
        SELECT a.id, 'CHECKING_OPEN', a.submitted_at, '{}'::jsonb
          FROM a WHERE a.valid AND a.chk_open AND NOT a.chk_paid AND a.state NOT IN ('STUDENT')
        UNION ALL
        SELECT a.id, 'ACCEPTANCE_UNPAID', a.chk_paid_at, '{}'::jsonb
          FROM a WHERE a.state = 'ADMITTED' AND a.may_check AND a.adm_status = 'ADMITTED' AND a.acc_at IS NULL
        UNION ALL
        SELECT a.id, 'SCHOOL_FEE_UNPAID', a.acc_at, jsonb_build_object('first', true)
          FROM a WHERE a.state = 'ADMITTED' AND a.acc_at IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM jupeb.fee_reference f WHERE f.application_id = a.id AND f.kind LIKE 'SCHOOL%' AND f.confirmed_at IS NOT NULL)
           AND (NOT (jupeb.setting_of(a.session)).screening_required OR a.screening_state = 'CLEARED')
        UNION ALL
        SELECT a.id, 'SCHOOL_FEE_UNPAID', a.activated_at, jsonb_build_object('first', false, 'outstanding', sf.outstanding)
          FROM a CROSS JOIN LATERAL jupeb.school_fees(a.id) sf WHERE a.state = 'STUDENT' AND sf.outstanding > 0
    ), due AS (
        SELECT DISTINCT ON (c.id) c.id, c.kind, c.detail, s.n, s.last
          FROM cand c
          JOIN jupeb.reminder_rule r ON r.kind = c.kind AND r.enabled
          CROSS JOIN LATERAL (SELECT count(*)::int AS n, max(l.sent_at) AS last FROM jupeb.reminder_log l WHERE l.application_id = c.id AND l.kind = c.kind) s
         WHERE c.anchor IS NOT NULL AND c.anchor + make_interval(days => r.first_after_days) <= p_now
           AND s.n < r.max_count AND (s.last IS NULL OR s.last + make_interval(days => r.every_days) <= p_now)
           /* never twice in a day, whatever the kind */
           AND NOT EXISTS (SELECT 1 FROM jupeb.reminder_log l WHERE l.application_id = c.id AND l.sent_at > p_now - interval '20 hours')
         ORDER BY c.id, r.ord
    )
    SELECT d.id, x.application_no, x.surname || ', ' || x.first_name || coalesce(' ' || x.middle_name, ''), d.kind, d.n, d.last, d.detail
      FROM due d JOIN jupeb.application x ON x.id = d.id
     ORDER BY x.application_no
$$;

/* the words of a reminder: [subject, email body, SMS] */
CREATE OR REPLACE FUNCTION jupeb.reminder_words(p_app uuid, p_kind text, p_detail jsonb, p_portal text)
RETURNS text[] LANGUAGE plpgsql STABLE AS $$
DECLARE a jupeb.application; fs record; sf record; v_url text := rtrim(coalesce(p_portal, ''), '/') || '/jupeb/portal'; v_closes text;
        naira text; subj text; body text;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    SELECT * INTO fs FROM jupeb.fee_setting_of(a.session);
    v_closes := CASE WHEN p_detail->>'closes' IS NOT NULL
                     THEN ' before the application window closes on ' || to_char(((p_detail->>'closes')::timestamptz AT TIME ZONE 'Africa/Lagos'), 'FMDD Mon YYYY') ELSE '' END;
    IF p_kind = 'FEE_UNPAID' THEN
        subj := 'Your JUPEB application: the application fee is not yet paid';
        body := 'Your JUPEB application is started, but the application fee of ₦' || to_char(fs.application_fee, 'FM999,999,990') || ' is not yet paid. '
             || 'Sign in at ' || v_url || ' to pay it and complete your application' || v_closes || '.';
    ELSIF p_kind = 'SUBMIT_PENDING' THEN
        subj := CASE WHEN (p_detail->>'returned')::boolean THEN 'Your JUPEB application: submit your correction' ELSE 'Your JUPEB application is not yet submitted' END;
        body := CASE WHEN (p_detail->>'returned')::boolean THEN 'The JUPEB Office returned your application for a correction and it is not yet resubmitted. '
                     ELSE 'Your application fee is paid, but your JUPEB application is not yet submitted. ' END
             || 'Sign in at ' || v_url || ', complete the remaining steps and submit' || v_closes || '.';
    ELSIF p_kind = 'PASSPORT_MISSING' THEN
        subj := 'Your JUPEB application: upload your passport photograph';
        body := 'Your JUPEB application has no passport photograph yet. Upload a clear, recent passport photograph (JPEG or PNG) at ' || v_url || v_closes || '.';
    ELSIF p_kind = 'CHECKING_OPEN' THEN
        subj := 'JUPEB admission status checking is open';
        body := 'Admission status checking is open. Sign in at ' || v_url || ' to check your admission status; the status checking fee of ₦'
             || to_char(fs.checking_fee, 'FM999,999,990') || ' is paid once.';
    ELSIF p_kind = 'ACCEPTANCE_UNPAID' THEN
        subj := 'Accept your JUPEB admission';
        body := 'You are offered admission into the JUPEB programme. Accept it by paying the acceptance fee of ₦' || to_char(fs.acceptance_fee, 'FM999,999,990')
             || ' at ' || v_url || '; your acceptance letter and school fees follow.';
    ELSIF p_kind = 'SCHOOL_FEE_UNPAID' THEN
        SELECT * INTO sf FROM jupeb.school_fees(p_app);
        IF coalesce((p_detail->>'first')::boolean, true) THEN
            subj := 'Pay your JUPEB school fee to begin';
            body := 'Your admission is accepted. Pay the first semester''s school fee of ₦' || to_char(sf.first_amount, 'FM999,999,990')
                 || ' at ' || v_url || ' to activate your studentship and register your subjects.';
        ELSE
            subj := 'Your JUPEB school fee balance';
            body := 'You have an outstanding JUPEB school fee balance of ₦' || to_char(sf.outstanding, 'FM999,999,990') || '. Pay it at ' || v_url || '.';
        END IF;
    ELSE
        RETURN NULL;
    END IF;
    RETURN ARRAY[subj, body, subj || '. ' || v_url];
END $$;

/* send what is due: one email each (and an SMS where the rule says), logged; returns how many by kind */
CREATE OR REPLACE FUNCTION jupeb.send_reminders(p_now timestamptz, p_portal text, p_limit int, p_trigger text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE d record; w text[]; r jupeb.reminder_rule; n int := 0; v_by jsonb := '{}'::jsonb; a jupeb.application;
BEGIN
    FOR d IN SELECT * FROM jupeb.due_reminders(p_now) LIMIT greatest(coalesce(p_limit, 500), 0) LOOP
        w := jupeb.reminder_words(d.application_id, d.kind, d.detail, p_portal);
        CONTINUE WHEN w IS NULL;
        SELECT * INTO r FROM jupeb.reminder_rule WHERE kind = d.kind;
        SELECT * INTO a FROM jupeb.application WHERE id = d.application_id;
        PERFORM jupeb.tell(d.application_id, w[1], w[2]);
        IF r.sms AND a.phone IS NOT NULL THEN
            PERFORM platform.queue_notice('SMS', a.phone, w[1], w[3], 'jupeb_application', d.application_id);
        END IF;
        INSERT INTO jupeb.reminder_log (application_id, kind, sent_at, by_sms, trigger)
        VALUES (d.application_id, d.kind, p_now, r.sms AND a.phone IS NOT NULL, coalesce(p_trigger, 'SCHEDULE'));
        n := n + 1;
        v_by := jsonb_set(v_by, ARRAY[d.kind], to_jsonb(coalesce((v_by->>d.kind)::int, 0) + 1));
    END LOOP;
    RETURN jsonb_build_object('sent', n, 'byKind', v_by);
END $$;

-- ── 4 · grants ───────────────────────────────────────────────────────────────────────────────────
GRANT SELECT ON jupeb.paper, jupeb.change_request, jupeb.reminder_rule, jupeb.reminder_log TO app_auditor;
GRANT SELECT, INSERT, UPDATE ON jupeb.paper, jupeb.change_request, jupeb.reminder_rule, jupeb.reminder_log TO app_admissions;

COMMIT;
