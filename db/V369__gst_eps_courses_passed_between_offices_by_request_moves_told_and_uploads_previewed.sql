-- V369: a course passes between the GST and EPS offices only by request; the offices are told of every move someone else made;
--       a programme structure upload shows, before it loads, which courses it would move, and never takes a course off an office.
--
-- 1  By request. Since V367 either office could take the other's course on its own word ("This office's"). Now a course held
--    by one office goes to the other only through catalogue.general_transfer: the office that wants it asks, with a reason;
--    the office that holds it accepts or declines (a decline says why); the Academic Office and the Super Administrator may
--    decide any request. A request lapses when the course moves some other way first. Taking a course no office holds, and
--    giving a course back to its department, work as before.
-- 2  Told. A move that an office makes itself — its claim, its give-back, its family, an accepted request — is confirmed as it
--    is made. A move someone else makes — an upload, the Academic Office giving a course back, an edit — waits for the office
--    to confirm, and the office's holders get one email for the transaction that made it, listing every course (also on each
--    holder's notifications page). The dashboards count what waits.
-- 3  Previewed, and kept. The programme structure upload (catalogue.import_courses, the "Upload or Create Courses" page) wrote
--    each row's status over a course its department owns, so a structure marking an office's course C took it off the office's
--    desk; it now leaves an office's course with the office (as V368 left a course given back with its department), and names
--    its moves as an upload. catalogue.structure_placements reads the same rows without writing and says, course by course,
--    what loading them would do to the GST and EPS offices' courses.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V369: GST/EPS courses passed by request; moves told; structure uploads previewed and kept off the offices', true);

-- ── 1 · words the notices and the pages share ────────────────────────────────────────────────────────────────────

/* where a course stands, in words: an office, a general course no office holds, or its department */
CREATE OR REPLACE FUNCTION catalogue.general_place(p_office text, p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_office IS NOT NULL THEN 'the ' || p_office || ' office'
                WHEN p_kind = 'GST' THEN 'general, no office'
                WHEN p_kind IS NULL THEN 'a new course'
                ELSE 'its department' END;
$$;

/* a move the acting office made to its own courses alone: every office it touches is the actor's */
CREATE OR REPLACE FUNCTION catalogue.general_move_is_own(p_before text, p_after text, p_actor text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(coalesce(p_before, p_after) IS NOT NULL
                    AND coalesce(p_before, upper(p_actor)) = upper(p_actor)
                    AND coalesce(p_after, upper(p_actor)) = upper(p_actor), false);
$$;

-- ── 2 · a course passes between the offices by request ───────────────────────────────────────────────────────────

CREATE TABLE catalogue.general_transfer (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_code      text NOT NULL REFERENCES catalogue.course(code) ON DELETE CASCADE ON UPDATE CASCADE,
    from_office      text NOT NULL CHECK (from_office IN ('GST', 'EPS')),
    to_office        text NOT NULL CHECK (to_office IN ('GST', 'EPS')),
    reason           text NOT NULL CHECK (btrim(reason) <> ''),
    state            text NOT NULL DEFAULT 'PENDING' CHECK (state IN ('PENDING', 'ACCEPTED', 'DECLINED', 'WITHDRAWN', 'LAPSED')),
    requested_by     uuid NOT NULL,
    requested_office text NOT NULL,
    requested_at     timestamptz NOT NULL DEFAULT now(),
    decided_by       uuid NULL,
    decided_office   text NULL,
    decided_at       timestamptz NULL,
    decision_note    text NULL,
    CONSTRAINT ck_general_transfer_offices CHECK (from_office <> to_office),
    CONSTRAINT ck_general_transfer_decided CHECK ((state = 'PENDING') = (decided_at IS NULL)),
    CONSTRAINT ck_general_transfer_declined CHECK (state <> 'DECLINED' OR btrim(coalesce(decision_note, '')) <> '')
);
COMMENT ON TABLE catalogue.general_transfer IS
  'V369: a request by the GST or EPS office for a course the other office holds — accepted or declined by the office that holds it, or decided by the Academic Office or the Super Administrator; withdrawn by the office that asked; lapsed when the course moves some other way first.';
CREATE UNIQUE INDEX ux_general_transfer_pending ON catalogue.general_transfer (course_code) WHERE state = 'PENDING';
CREATE INDEX ix_general_transfer_offices ON catalogue.general_transfer (from_office, to_office, requested_at DESC);
SELECT audit.attach('catalogue.general_transfer');
GRANT SELECT ON catalogue.general_transfer TO app_auditor;

/* the holders of an office today who have an email: who a notice to the office reaches */
CREATE OR REPLACE FUNCTION catalogue.general_office_holders(p_office text)
RETURNS TABLE(id uuid, email text) LANGUAGE sql STABLE AS $$
    SELECT DISTINCT p.id, p.email FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id
     WHERE a.office_code = lower(p_office) AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND p.email IS NOT NULL AND btrim(p.email) <> '' AND p.ended_on IS NULL;
$$;

CREATE OR REPLACE FUNCTION catalogue.tell_general_office(p_office text, p_subject text, p_body text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE h record; n int := 0;
BEGIN
    FOR h IN SELECT * FROM catalogue.general_office_holders(p_office) LOOP
        PERFORM platform.queue_notice('EMAIL', h.email, p_subject, p_body, 'person', h.id);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

CREATE OR REPLACE FUNCTION catalogue.request_general_transfer(p_code text, p_to_office text, p_reason text)
RETURNS catalogue.general_transfer
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := lower(coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''));
        v_to text := upper(btrim(coalesce(p_to_office, ''))); c catalogue.course; t catalogue.general_transfer;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is asked for by a person' USING ERRCODE = '23514'; END IF;
    IF v_to NOT IN ('GST', 'EPS') THEN RAISE EXCEPTION 'GEN_OFFICE: a general course is the GST or the EPS office''s' USING ERRCODE = '23514'; END IF;
    IF actor NOT IN (lower(v_to), 'academic', 'super') THEN
        RAISE EXCEPTION 'GEN_TRANSFER_NOT_YOURS: only the % office asks for a course for itself', v_to USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'GEN_REASON: say why the course should come to the % office', v_to USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.kind <> 'GST' OR c.general_office IS NULL THEN
        RAISE EXCEPTION 'GEN_NO_OFFICE: % is no office''s course; take it directly', c.code USING ERRCODE = '23514';
    END IF;
    IF c.general_office = v_to THEN RAISE EXCEPTION 'GEN_ALREADY_YOURS: % is already the % office''s', c.code, v_to USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM catalogue.general_transfer x WHERE x.course_code = c.code AND x.state = 'PENDING') THEN
        RAISE EXCEPTION 'GEN_TRANSFER_PENDING: a request for % is already waiting for an answer', c.code USING ERRCODE = '23514';
    END IF;
    INSERT INTO catalogue.general_transfer (course_code, from_office, to_office, reason, requested_by, requested_office)
    VALUES (c.code, c.general_office, v_to, btrim(p_reason), who, actor)
    RETURNING * INTO t;
    PERFORM catalogue.tell_general_office(t.from_office, 'The ' || t.to_office || ' office asks for ' || c.code,
        'The ' || t.to_office || ' office asks for ' || c.code || ' ' || c.title || ', which is the ' || t.from_office || ' office''s course.' || E'\n\n'
        || 'Its reason: ' || t.reason || E'\n\n'
        || 'Sign in to the portal and open ' || t.from_office || ' Courses. Under "Requests between the GST and EPS offices", accept to pass the course, '
        || 'or decline and say why. The Academic Office may decide the request if the two offices disagree.' || E'\n');
    RETURN t;
END $$;

CREATE OR REPLACE FUNCTION catalogue.decide_general_transfer(p_id uuid, p_accept boolean, p_note text)
RETURNS catalogue.general_transfer
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := lower(coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''));
        t catalogue.general_transfer; c catalogue.course; v_word text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a request is decided by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM catalogue.general_transfer WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GEN_TRANSFER: no request %', p_id USING ERRCODE = '23503'; END IF;
    IF t.state <> 'PENDING' THEN RAISE EXCEPTION 'GEN_TRANSFER_DECIDED: the request for % is already %', t.course_code, lower(t.state) USING ERRCODE = '23514'; END IF;
    IF actor NOT IN (lower(t.from_office), 'academic', 'super') THEN
        RAISE EXCEPTION 'GEN_TRANSFER_NOT_YOURS: the % office, the Academic Office or the Super Administrator decides this request', t.from_office USING ERRCODE = '23514';
    END IF;
    IF NOT coalesce(p_accept, false) AND nullif(btrim(coalesce(p_note, '')), '') IS NULL THEN
        RAISE EXCEPTION 'GEN_REASON: say why the request is declined' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = t.course_code FOR UPDATE;
    IF coalesce(p_accept, false) THEN
        IF c.kind <> 'GST' OR c.general_office IS DISTINCT FROM t.from_office THEN
            RAISE EXCEPTION 'GEN_TRANSFER_STALE: % is no longer the % office''s course', c.code, t.from_office USING ERRCODE = '23514';
        END IF;
        PERFORM set_config('moaum.general_cause', 'TRANSFER', true);
        UPDATE catalogue.course SET general_office = t.to_office WHERE code = c.code;
        PERFORM set_config('moaum.general_cause', '', true);
        UPDATE assessment.cbt_exam SET office = t.to_office WHERE course_code = c.code AND office = t.from_office;
    END IF;
    UPDATE catalogue.general_transfer
       SET state = CASE WHEN coalesce(p_accept, false) THEN 'ACCEPTED' ELSE 'DECLINED' END,
           decided_by = who, decided_office = actor, decided_at = now(), decision_note = nullif(btrim(coalesce(p_note, '')), '')
     WHERE id = t.id
    RETURNING * INTO t;
    v_word := CASE WHEN t.state = 'ACCEPTED' THEN 'accepted' ELSE 'declined' END;
    PERFORM catalogue.tell_general_office(t.to_office, 'Your request for ' || t.course_code || ' is ' || v_word,
        'The request for ' || t.course_code || ' ' || c.title || ' was ' || v_word
        || CASE WHEN actor IN ('academic', 'super') THEN ' by the ' || CASE actor WHEN 'academic' THEN 'Academic Office' ELSE 'Super Administrator' END ELSE ' by the ' || t.from_office || ' office' END || '.'
        || CASE WHEN t.decision_note IS NOT NULL THEN E'\n\nIts note: ' || t.decision_note ELSE '' END
        || CASE WHEN t.state = 'ACCEPTED' THEN E'\n\nThe course is now on your desk, with its offerings, score sheets and CBT examinations.' ELSE '' END || E'\n');
    IF actor IN ('academic', 'super') THEN
        PERFORM catalogue.tell_general_office(t.from_office, 'The request for ' || t.course_code || ' was ' || v_word,
            'The ' || t.to_office || ' office''s request for ' || t.course_code || ' ' || c.title || ' was ' || v_word || ' by the '
            || CASE actor WHEN 'academic' THEN 'Academic Office' ELSE 'Super Administrator' END || '.'
            || CASE WHEN t.decision_note IS NOT NULL THEN E'\n\nIts note: ' || t.decision_note ELSE '' END || E'\n');
    END IF;
    RETURN t;
END $$;

CREATE OR REPLACE FUNCTION catalogue.withdraw_general_transfer(p_id uuid)
RETURNS catalogue.general_transfer
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; actor text := lower(coalesce(nullif(current_setting('moaum.actor_office', true), ''), ''));
        t catalogue.general_transfer;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a request is withdrawn by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO t FROM catalogue.general_transfer WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'GEN_TRANSFER: no request %', p_id USING ERRCODE = '23503'; END IF;
    IF t.state <> 'PENDING' THEN RAISE EXCEPTION 'GEN_TRANSFER_DECIDED: the request for % is already %', t.course_code, lower(t.state) USING ERRCODE = '23514'; END IF;
    IF actor NOT IN (lower(t.to_office), 'academic', 'super') THEN
        RAISE EXCEPTION 'GEN_TRANSFER_NOT_YOURS: the % office withdraws its own request', t.to_office USING ERRCODE = '23514';
    END IF;
    UPDATE catalogue.general_transfer SET state = 'WITHDRAWN', decided_by = who, decided_office = actor, decided_at = now()
     WHERE id = t.id RETURNING * INTO t;
    PERFORM catalogue.tell_general_office(t.from_office, 'The request for ' || t.course_code || ' is withdrawn',
        'The ' || t.to_office || ' office has withdrawn its request for ' || t.course_code || '. Nothing changes on your desk.' || E'\n');
    RETURN t;
END $$;

-- ── 3 · a move made by the office itself is confirmed; any other is told to the office once a transaction ────────────

ALTER TABLE catalogue.general_reclassification DROP CONSTRAINT general_reclassification_cause_check;
ALTER TABLE catalogue.general_reclassification ADD CONSTRAINT general_reclassification_cause_check
    CHECK (cause IN ('RULE', 'CLAIM', 'RETURN', 'FAMILY', 'UPLOAD', 'EDIT', 'TRANSFER'));
ALTER TABLE catalogue.general_reclassification ADD COLUMN tx xid8 NOT NULL DEFAULT pg_current_xact_id();
ALTER TABLE catalogue.general_reclassification ADD COLUMN noticed_at timestamptz NULL;
COMMENT ON COLUMN catalogue.general_reclassification.tx IS 'V369: the transaction that made the move — one notice to an office covers all the moves of one transaction.';
COMMENT ON COLUMN catalogue.general_reclassification.noticed_at IS 'V369: when the offices the move touches were told of it (moves an office made itself are confirmed instead).';

-- what is already recorded: a move an office made to its own courses is confirmed by its making; none is told again
UPDATE catalogue.general_reclassification
   SET confirmed_by = changed_by, confirmed_office = changed_office, confirmed_at = changed_at
 WHERE confirmed_at IS NULL AND catalogue.general_move_is_own(before_office, after_office, changed_office);
UPDATE catalogue.general_reclassification SET noticed_at = changed_at WHERE noticed_at IS NULL;

CREATE OR REPLACE FUNCTION catalogue.course_reclassified()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_actor text := nullif(current_setting('moaum.actor_office', true), '');
        v_cause text := coalesce(nullif(current_setting('moaum.general_cause', true), ''),
                                 CASE WHEN current_setting('moaum.owner_source', true) = 'IMPORT' THEN 'UPLOAD' ELSE 'EDIT' END);
        v_who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_before_office text; v_before_kind text; v_own boolean;
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- V369: a new course another office or an upload puts on an office's desk is a move too; the office's own new course is not
        IF NEW.general_office IS NULL OR upper(coalesce(v_actor, '')) = NEW.general_office THEN RETURN NULL; END IF;
    ELSIF NOT (NEW.general_office IS DISTINCT FROM OLD.general_office OR (NEW.kind = 'GST') IS DISTINCT FROM (OLD.kind = 'GST')) THEN
        RETURN NULL;
    ELSE
        v_before_office := OLD.general_office;
        v_before_kind := OLD.kind;
    END IF;
    v_own := v_cause = 'TRANSFER' OR catalogue.general_move_is_own(v_before_office, NEW.general_office, v_actor);
    INSERT INTO catalogue.general_reclassification (course_code, before_office, after_office, before_kind, after_kind, cause, reason, changed_by, changed_office,
                                                    confirmed_by, confirmed_office, confirmed_at)
    VALUES (NEW.code, v_before_office, NEW.general_office, v_before_kind, NEW.kind, v_cause,
            nullif(current_setting('moaum.reason', true), ''), v_who, v_actor,
            CASE WHEN v_own THEN v_who END, CASE WHEN v_own THEN v_actor END, CASE WHEN v_own THEN now() END);
    -- a request for the course lapses when the course moves some other way before it is decided
    IF TG_OP = 'UPDATE' AND v_cause <> 'TRANSFER' AND NEW.general_office IS DISTINCT FROM OLD.general_office THEN
        UPDATE catalogue.general_transfer
           SET state = 'LAPSED', decided_by = v_who, decided_office = v_actor, decided_at = now(),
               decision_note = 'The course moved (' || lower(v_cause) || ') before the request was decided'
         WHERE course_code = NEW.code AND state = 'PENDING';
    END IF;
    RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_course_reclassified ON catalogue.course;
CREATE TRIGGER trg_course_reclassified AFTER INSERT OR UPDATE OF kind, general_office ON catalogue.course
    FOR EACH ROW EXECUTE FUNCTION catalogue.course_reclassified();

/* at commit: every office a transaction's unconfirmed moves touch is told once, with every course, by email to its holders */
CREATE OR REPLACE FUNCTION catalogue.notice_general_moves()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o text; v_n int; v_lines text; v_by text; v_reason text; v_ids uuid[];
BEGIN
    SELECT array_agg(m.id) INTO v_ids FROM catalogue.general_reclassification m
     WHERE m.tx = pg_current_xact_id() AND m.noticed_at IS NULL AND m.confirmed_at IS NULL
       AND (m.before_office IS NOT NULL OR m.after_office IS NOT NULL);
    IF v_ids IS NULL THEN RETURN NULL; END IF;
    FOREACH o IN ARRAY ARRAY['GST', 'EPS'] LOOP
        SELECT count(*), string_agg(x.line, E'\n' ORDER BY x.course_code) FILTER (WHERE x.rn <= 40),
               min(x.changed_office), min(x.reason)
          INTO v_n, v_lines, v_by, v_reason
          FROM (SELECT m.course_code, m.changed_office, m.reason, row_number() OVER (ORDER BY m.course_code) AS rn,
                       '- ' || m.course_code || ' ' || c.title || ': '
                       || CASE WHEN m.before_kind IS NULL THEN 'new, to ' ELSE 'from ' || catalogue.general_place(m.before_office, m.before_kind) || ' to ' END
                       || catalogue.general_place(m.after_office, m.after_kind)
                       || ' (' || CASE m.cause WHEN 'UPLOAD' THEN 'a course upload' WHEN 'RETURN' THEN 'given back to its department'
                                               WHEN 'CLAIM' THEN 'taken by an office' WHEN 'FAMILY' THEN 'a code family' ELSE 'an edit' END || ')' AS line
                  FROM catalogue.general_reclassification m JOIN catalogue.course c ON c.code = m.course_code
                 WHERE m.id = ANY(v_ids) AND (m.before_office = o OR m.after_office = o)) x;
        CONTINUE WHEN v_n = 0;
        PERFORM catalogue.tell_general_office(o, v_n || ' course' || CASE WHEN v_n = 1 THEN '' ELSE 's' END || ' moved to or from the ' || o || ' office',
            'These courses were moved to or from the ' || o || ' office:' || E'\n\n'
            || v_lines || CASE WHEN v_n > 40 THEN E'\n- and ' || (v_n - 40) || ' more' ELSE '' END || E'\n'
            || CASE WHEN v_by IS NOT NULL THEN E'\nMoved by: ' || coalesce((SELECT r.label FROM ref.office r WHERE r.code = v_by), v_by) ELSE '' END
            || CASE WHEN v_reason IS NOT NULL THEN E'\nReason recorded: ' || v_reason ELSE '' END || E'\n\n'
            || 'Sign in to the portal and open ' || o || ' Courses. Under "Courses moved to or from this office", confirm each move that is right, '
            || 'take a course this office runs, or give back to its department one it does not.' || E'\n');
    END LOOP;
    UPDATE catalogue.general_reclassification SET noticed_at = now() WHERE id = ANY(v_ids);
    RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER trg_general_moves_noticed AFTER INSERT ON catalogue.general_reclassification
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION catalogue.notice_general_moves();

-- ── 4 · a claim takes only a course no office holds; an upload keeps an office's course ─────────────────────────────

CREATE OR REPLACE FUNCTION catalogue.course_general_office()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- V368: a course given back to its department stays its department's: an upload's status G or GST classification does not make it general again
    IF TG_OP = 'UPDATE' AND OLD.general_released_at IS NOT NULL AND NEW.general_released_at IS NOT NULL AND NEW.kind = 'GST' AND OLD.kind <> 'GST' THEN
        NEW.kind := OLD.kind;
    END IF;
    -- V369: an office's course stays the office's through an upload: a structure's status C, R or E does not take it off the desk —
    -- the office gives it back, or passes it to the other office, itself
    IF TG_OP = 'UPDATE' AND OLD.kind = 'GST' AND OLD.general_office IS NOT NULL AND NEW.kind <> 'GST'
       AND coalesce(nullif(current_setting('moaum.general_cause', true), ''),
                    CASE WHEN current_setting('moaum.owner_source', true) = 'IMPORT' THEN 'UPLOAD' END) = 'UPLOAD' THEN
        NEW.kind := OLD.kind;
    END IF;
    IF NEW.kind <> 'GST' THEN
        NEW.general_office := NULL;
    ELSIF NEW.general_office IS NULL THEN
        NEW.general_office := catalogue.general_office_of(NEW.code, NEW.title, NEW.kind);
    END IF;
    RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION catalogue.claim_general_course(p_code text, p_office text)
RETURNS catalogue.course
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := upper(btrim(coalesce(p_office, ''))); c catalogue.course;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a course is classified by a person' USING ERRCODE = '23514'; END IF;
    IF v_office NOT IN ('GST', 'EPS') THEN RAISE EXCEPTION 'GEN_OFFICE: a general course is the GST or the EPS office''s' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = upper(btrim(coalesce(p_code, ''))) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no course is coded %', p_code USING ERRCODE = '23503'; END IF;
    IF c.kind <> 'GST' AND c.general_released_at IS NULL THEN
        RAISE EXCEPTION 'GEN_NOT_GENERAL: % is a departmental course (%); its department classifies it', c.code, c.kind USING ERRCODE = '23514',
            HINT = 'A course is offered as GST/EPS through the programmes that take it (basis GST) on the catalogue.';
    END IF;
    -- V369: the other office's course comes only by its answer to a request
    IF c.kind = 'GST' AND c.general_office IS NOT NULL AND c.general_office <> v_office THEN
        RAISE EXCEPTION 'GEN_OTHER_OFFICE: % is the % office''s course; ask that office for it', c.code, c.general_office USING ERRCODE = '23514',
            HINT = 'Ask for it on the courses page: the ' || c.general_office || ' office accepts or declines, and the Academic Office may decide.';
    END IF;
    PERFORM set_config('moaum.general_cause', 'CLAIM', true);
    UPDATE catalogue.course SET kind = 'GST', general_office = v_office, general_released_at = NULL WHERE code = c.code RETURNING * INTO c;
    PERFORM set_config('moaum.general_cause', '', true);
    UPDATE assessment.cbt_exam SET office = v_office WHERE course_code = c.code AND office IN ('GST', 'EPS', 'EXAMS') AND office <> v_office;
    RETURN c;
END $$;

-- the programme structure upload names its moves as an upload (V332's text otherwise)
CREATE OR REPLACE FUNCTION catalogue.import_courses(p_programme text, p_rows jsonb, p_curriculum text DEFAULT NULL::text)
RETURNS TABLE(rows integer, courses integer, offers integer, no_dept integer, bad_code integer, skipped integer, first_error text, existing integer)
LANGUAGE plpgsql AS $$
DECLARE r record; v_in text := upper(nullif(btrim(coalesce(p_curriculum, '')), '')); v_track text; v_framework text; v_prog text;
BEGIN
    PERFORM set_config('moaum.general_cause', 'UPLOAD', true);
    IF v_in IN ('CCMAS_BSU', 'CCMAS_MOAU', 'BMAS') THEN
        v_track := v_in; v_framework := (SELECT framework FROM policy.curriculum_track WHERE code = v_in);
    ELSIF v_in = 'CCMAS' THEN
        v_track := NULL; v_framework := 'CCMAS';       -- CCMAS for any cohort
    ELSE
        v_track := NULL; v_framework := v_in;
    END IF;
    FOR r IN SELECT * FROM catalogue.import_courses_rows(p_programme, p_rows, v_framework) LOOP
        rows := r.rows; courses := r.courses; offers := r.offers; no_dept := r.no_dept; bad_code := r.bad_code;
        skipped := r.skipped; first_error := r.first_error; existing := r.existing;
        SELECT code INTO v_prog FROM ref.programme
         WHERE upper(code) = upper(btrim(p_programme)) OR upper(name) = upper(btrim(p_programme)) ORDER BY archived, code LIMIT 1;
        IF v_prog IS NOT NULL THEN
            UPDATE catalogue.course_offer co SET track = v_track
             WHERE co.programme_code = v_prog
               AND upper(co.course_code) IN (
                   SELECT regexp_replace(upper(btrim(coalesce(x->>'code', x->>'courseCode', x->>'course_code', ''))), '\s+', ' ', 'g')
                     FROM jsonb_array_elements(p_rows) x)
               AND co.track IS DISTINCT FROM v_track;
        END IF;
        RETURN NEXT;
    END LOOP;
    PERFORM set_config('moaum.general_cause', '', true);
END $$;

-- ── 5 · what a structure upload would do to the offices' courses, read before it loads ───────────────────────────────

/* p_groups: [{programme, rows: [{code, title, status, ...}]}] as the upload page posts them, one group per programme. The same
   reading as catalogue.import_courses_rows — the kind from the code and the status, the owner from the catalogue or the first
   programme that loads a new code, the last row of the owning department's programmes — and the same rules as the course's
   trigger: an office's course and a course given back keep their kind, and a general course is filed by its code family. */
CREATE OR REPLACE FUNCTION catalogue.structure_placements(p_groups jsonb)
RETURNS jsonb LANGUAGE sql STABLE AS $$
WITH g AS (
    SELECT gn::int AS gn, x AS j FROM jsonb_array_elements(coalesce(p_groups, '[]'::jsonb)) WITH ORDINALITY AS t(x, gn)
), gp AS (
    SELECT g.gn, g.j, p.code AS prog, p.dept_code AS dept
      FROM g LEFT JOIN LATERAL (SELECT x.code, x.dept_code FROM ref.programme x
                                 WHERE upper(x.code) = upper(btrim(coalesce(g.j->>'programme', ''))) OR upper(x.name) = upper(btrim(coalesce(g.j->>'programme', '')))
                                 ORDER BY x.archived, x.code LIMIT 1) p ON true
), r AS (
    SELECT gp.gn, rn::int AS rn, gp.prog, gp.dept,
           regexp_replace(upper(btrim(coalesce(x->>'code', x->>'courseCode', x->>'course_code', ''))), '\s+', ' ', 'g') AS code,
           nullif(btrim(coalesce(x->>'title', x->>'courseTitle', '')), '') AS title,
           upper(left(btrim(coalesce(x->>'status', 'C')), 1)) AS status
      FROM gp CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN jsonb_typeof(gp.j->'rows') = 'array' THEN gp.j->'rows' ELSE '[]'::jsonb END) WITH ORDINALITY AS t(x, rn)
     WHERE gp.prog IS NOT NULL AND gp.dept IS NOT NULL
), k AS (
    SELECT r.*, CASE WHEN r.code LIKE 'GST%' THEN 'GST' WHEN r.status = 'G' THEN 'GST' WHEN r.status = 'R' THEN 'Required'
                     WHEN r.status = 'E' THEN 'Elective' ELSE 'Core' END AS kind
      FROM r WHERE r.code ~ '^[A-Z][A-Z0-9 /-]{2,19}$' AND r.code !~* '^course\s*code$'
), owner AS (
    SELECT DISTINCT ON (k.code) k.code, coalesce(c.dept_code, k.dept) AS dept
      FROM k LEFT JOIN catalogue.course c ON c.code = k.code ORDER BY k.code, k.gn, k.rn
), last AS (
    SELECT DISTINCT ON (k.code) k.code, k.kind, coalesce(k.title, k.code) AS title, k.status, k.prog, k.dept
      FROM k JOIN owner o ON o.code = k.code AND o.dept = k.dept ORDER BY k.code, k.gn DESC, k.rn DESC
), p AS (
    SELECT l.code, l.title, l.status, l.prog, l.dept, c.code IS NOT NULL AS existing, c.kind AS before_kind, c.general_office AS before_office,
           c.general_released_at IS NOT NULL AS released, c.title AS before_title, l.kind AS file_kind,
           CASE WHEN c.code IS NOT NULL AND c.kind = 'GST' AND c.general_office IS NOT NULL AND l.kind <> 'GST' THEN c.kind
                WHEN c.code IS NOT NULL AND c.general_released_at IS NOT NULL AND l.kind = 'GST' AND c.kind <> 'GST' THEN c.kind
                ELSE l.kind END AS after_kind
      FROM last l LEFT JOIN catalogue.course c ON c.code = l.code
), q AS (
    SELECT p.*, CASE WHEN p.after_kind = 'GST' THEN coalesce(p.before_office, catalogue.general_office_of(p.code, p.title, 'GST')) END AS after_office
      FROM p
), z AS (
    SELECT q.*, d.name AS department,
           CASE WHEN NOT q.existing AND q.after_office IS NOT NULL THEN 'NEW_TO_OFFICE'
                WHEN NOT q.existing AND q.after_kind = 'GST' THEN 'NEW_NO_OFFICE'
                WHEN q.existing AND q.before_office IS NOT NULL AND q.before_kind = 'GST' AND q.file_kind <> 'GST' THEN 'KEPT_WITH_OFFICE'
                WHEN q.existing AND q.released AND q.file_kind = 'GST' AND q.before_kind <> 'GST' THEN 'KEPT_WITH_DEPARTMENT'
                WHEN q.existing AND q.before_office IS NULL AND q.after_office IS NOT NULL THEN 'TO_OFFICE'
                WHEN q.existing AND q.before_kind <> 'GST' AND q.after_kind = 'GST' THEN 'MARKED_GENERAL_NO_OFFICE'
                WHEN q.existing AND q.before_kind = 'GST' AND q.after_kind <> 'GST' THEN 'BACK_TO_DEPARTMENT' END AS change
      FROM q LEFT JOIN ref.department d ON d.code = q.dept
)
SELECT jsonb_build_object(
    'placements', coalesce(jsonb_agg(jsonb_build_object(
        'code', z.code, 'title', coalesce(z.before_title, z.title), 'programme', z.prog, 'status', z.status, 'department', z.department,
        'beforeOffice', z.before_office, 'beforeKind', z.before_kind, 'afterOffice', z.after_office, 'afterKind', z.after_kind, 'change', z.change)
        ORDER BY z.change, z.code) FILTER (WHERE z.change IS NOT NULL), '[]'::jsonb),
    'counts', jsonb_build_object(
        'toGst', count(*) FILTER (WHERE z.change IN ('NEW_TO_OFFICE', 'TO_OFFICE') AND z.after_office = 'GST'),
        'toEps', count(*) FILTER (WHERE z.change IN ('NEW_TO_OFFICE', 'TO_OFFICE') AND z.after_office = 'EPS'),
        'noOffice', count(*) FILTER (WHERE z.change IN ('NEW_NO_OFFICE', 'MARKED_GENERAL_NO_OFFICE')),
        'backToDepartment', count(*) FILTER (WHERE z.change = 'BACK_TO_DEPARTMENT'),
        'keptWithOffice', count(*) FILTER (WHERE z.change = 'KEPT_WITH_OFFICE'),
        'keptWithDepartment', count(*) FILTER (WHERE z.change = 'KEPT_WITH_DEPARTMENT')))
  FROM z;
$$;
COMMENT ON FUNCTION catalogue.structure_placements(jsonb) IS
  'V369: what a programme structure upload would do to the GST and EPS offices'' courses, course by course, without writing — read by the upload page before it loads.';

COMMIT;
