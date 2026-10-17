-- ═══════════════════════════════════════
-- V511 — API keys checked on the integration door, with its first read: the student status lookup
--
--   The Directorate of ICT registered consumers and issued keys (V047), but no request ever read a key, so a key granted nothing
--   (PRD FR-PLT-08). Now:
--   · apimgmt.scope — the scopes a consumer may hold, each with what it reads; a consumer is registered only with scopes on the
--     list (the first: students:status). A consumer registered earlier keeps what it had; a scope off the list grants nothing.
--   · apimgmt.student_status(key, matric, ip) — the integration door's one read so far (GET /api/integration/v1/students/status):
--     the key checked (its hash among the live keys — not revoked, not expired — of an ACTIVE consumer), the scope, and the
--     consumer's daily quota (Lagos day); then the student by matriculation number, told minimally: the matriculation number, the
--     name with initials, the programme, faculty and level, and whether in study, deferred, suspended, graduated or not in study
--     (no contact, no result, no payment, never why a student left). Every call — refused or answered — is on apimgmt.request_log.
--   · apimgmt.request_log is the trail of those calls, append-only and off the audit spine (an outside caller has no actor; the
--     log is itself the record of who asked what, and when).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V511: API keys checked on the integration door, with the student status lookup', true);

CREATE TABLE apimgmt.scope (
    code        text PRIMARY KEY CHECK (code ~ '^[a-z][a-z0-9_.-]*:[a-z][a-z0-9_.-]*$'),
    label       text NOT NULL,
    reads       text NOT NULL,
    path        text NOT NULL
);
COMMENT ON TABLE apimgmt.scope IS 'V511: the scopes an API consumer may hold, what each reads, and the integration path it opens';
SELECT audit.attach('apimgmt.scope');
INSERT INTO apimgmt.scope (code, label, reads, path) VALUES
('students:status', 'Student status lookup',
 'Whether a matriculation number is a student of the University: the name with initials, the programme, faculty and level, and in study, deferred, suspended, graduated or not in study. No contact details, results or payments.',
 'GET /api/integration/v1/students/status?matric=…');

-- a consumer is registered with scopes on the list (separated by spaces or commas)
CREATE OR REPLACE FUNCTION apimgmt.register_consumer(p_name text, p_owner text, p_scopes text, p_quota int)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_id uuid; v_scopes text[]; v_unknown text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a consumer is registered by a person' USING ERRCODE = '23514'; END IF;
    IF coalesce(btrim(p_name), '') = '' OR coalesce(btrim(p_owner), '') = '' OR coalesce(btrim(p_scopes), '') = '' THEN
        RAISE EXCEPTION 'a consumer is named, owned and scoped' USING ERRCODE = '23514';
    END IF;
    v_scopes := ARRAY(SELECT DISTINCT lower(x) FROM regexp_split_to_table(btrim(p_scopes), '[\s,]+') x WHERE x <> '' ORDER BY 1);
    SELECT string_agg(s, ', ') INTO v_unknown FROM unnest(v_scopes) s WHERE NOT EXISTS (SELECT 1 FROM apimgmt.scope c WHERE c.code = s);
    IF v_unknown IS NOT NULL THEN
        RAISE EXCEPTION 'API_SCOPE_UNKNOWN: % is not a scope the API grants; the scopes are: %', v_unknown,
            (SELECT string_agg(code, ', ' ORDER BY code) FROM apimgmt.scope) USING ERRCODE = '23514';
    END IF;
    IF p_quota IS NOT NULL AND p_quota NOT BETWEEN 1 AND 1000000 THEN
        RAISE EXCEPTION 'API_QUOTA: a daily quota is 1 to 1,000,000 calls, or none' USING ERRCODE = '23514';
    END IF;
    INSERT INTO apimgmt.consumer (name, owner, scopes, quota_day, created_by)
    VALUES (btrim(p_name), btrim(p_owner), array_to_string(v_scopes, ' '), p_quota, who) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

-- a key is found by its hash on every call
CREATE UNIQUE INDEX ux_api_key_hash ON apimgmt.key (key_hash);

-- ── the trail of the integration door's calls ──
CREATE TABLE apimgmt.request_log (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    at          timestamptz NOT NULL DEFAULT now(),
    consumer_id uuid NULL REFERENCES apimgmt.consumer(id),
    key_id      uuid NULL REFERENCES apimgmt.key(id),
    scope       text NOT NULL,
    subject     text NULL,
    outcome     text NOT NULL CHECK (outcome IN ('OK', 'NOT_FOUND', 'BAD_KEY', 'NO_SCOPE', 'OVER_QUOTA', 'BAD_REQUEST')),
    ip          text NULL
);
COMMENT ON TABLE apimgmt.request_log IS 'V511: every call on the integration door, refused or answered: the consumer and key (none for a key that is not one), the scope, what was asked, the outcome and the caller''s address';
CREATE INDEX ix_api_log_consumer ON apimgmt.request_log (consumer_id, at DESC);
SELECT audit.exempt('apimgmt.request_log', 'the append-only trail of calls from outside the University on the integration door: an outside caller has no actor for the spine, and the log is itself the record of which consumer asked what and when');

-- the key, the scope and the quota: the consumer, or why not (and the log row it wrote when refused)
CREATE FUNCTION apimgmt.check_key(p_key text, p_scope text, p_subject text, p_ip text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE k record; v_used int;
BEGIN
    SELECT kk.id AS key_id, c.id AS consumer_id, c.name, c.scopes, c.quota_day INTO k
      FROM apimgmt.key kk JOIN apimgmt.consumer c ON c.id = kk.consumer_id
     WHERE kk.key_hash = digest(coalesce(p_key, ''), 'sha256') AND kk.revoked_at IS NULL AND kk.expires_at > now() AND c.status = 'ACTIVE';
    IF k.key_id IS NULL THEN
        INSERT INTO apimgmt.request_log (scope, subject, outcome, ip) VALUES (p_scope, left(p_subject, 60), 'BAD_KEY', left(p_ip, 60));
        RETURN jsonb_build_object('ok', false, 'outcome', 'BAD_KEY');
    END IF;
    IF NOT (p_scope = ANY (regexp_split_to_array(lower(btrim(k.scopes)), '[\s,]+'))) OR NOT EXISTS (SELECT 1 FROM apimgmt.scope s WHERE s.code = p_scope) THEN
        INSERT INTO apimgmt.request_log (consumer_id, key_id, scope, subject, outcome, ip) VALUES (k.consumer_id, k.key_id, p_scope, left(p_subject, 60), 'NO_SCOPE', left(p_ip, 60));
        RETURN jsonb_build_object('ok', false, 'outcome', 'NO_SCOPE', 'consumer', k.name);
    END IF;
    IF k.quota_day IS NOT NULL THEN
        SELECT count(*) INTO v_used FROM apimgmt.request_log l
         WHERE l.consumer_id = k.consumer_id AND l.outcome IN ('OK', 'NOT_FOUND')
           AND l.at >= ((now() AT TIME ZONE 'Africa/Lagos')::date::timestamp AT TIME ZONE 'Africa/Lagos');
        IF v_used >= k.quota_day THEN
            INSERT INTO apimgmt.request_log (consumer_id, key_id, scope, subject, outcome, ip) VALUES (k.consumer_id, k.key_id, p_scope, left(p_subject, 60), 'OVER_QUOTA', left(p_ip, 60));
            RETURN jsonb_build_object('ok', false, 'outcome', 'OVER_QUOTA', 'consumer', k.name, 'quota', k.quota_day);
        END IF;
    END IF;
    RETURN jsonb_build_object('ok', true, 'consumer_id', k.consumer_id, 'key_id', k.key_id, 'consumer', k.name);
END $$;
COMMENT ON FUNCTION apimgmt.check_key(text, text, text, text) IS
  'V511: an integration call''s key (by its hash: a live key of an ACTIVE consumer), its scope and the consumer''s daily quota (calls answered today, Lagos time); logs and returns the refusal, or returns the consumer';

-- ── the first read: a student's status, minimally ──
CREATE FUNCTION apimgmt.student_status(p_key text, p_matric text, p_ip text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_no text := upper(btrim(coalesce(p_matric, ''))); c jsonb; s record;
BEGIN
    c := apimgmt.check_key(p_key, 'students:status', v_no, p_ip);
    IF NOT (c->>'ok')::boolean THEN RETURN c; END IF;
    IF v_no !~ '^[A-Z0-9/._-]{4,40}$' THEN
        INSERT INTO apimgmt.request_log (consumer_id, key_id, scope, subject, outcome, ip)
        VALUES ((c->>'consumer_id')::uuid, (c->>'key_id')::uuid, 'students:status', left(v_no, 60), 'BAD_REQUEST', left(p_ip, 60));
        RETURN jsonb_build_object('ok', false, 'outcome', 'BAD_REQUEST');
    END IF;
    SELECT x.matric_no, x.surname, x.other_names, x.status, x.current_level, p.name AS programme, f.name AS faculty INTO s
      FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE upper(btrim(x.matric_no)) = v_no LIMIT 1;
    INSERT INTO apimgmt.request_log (consumer_id, key_id, scope, subject, outcome, ip)
    VALUES ((c->>'consumer_id')::uuid, (c->>'key_id')::uuid, 'students:status', v_no, CASE WHEN s.matric_no IS NULL THEN 'NOT_FOUND' ELSE 'OK' END, left(p_ip, 60));
    IF s.matric_no IS NULL THEN RETURN jsonb_build_object('ok', false, 'outcome', 'NOT_FOUND'); END IF;
    RETURN jsonb_build_object('ok', true, 'outcome', 'OK', 'student', jsonb_build_object(
        'matric_no', s.matric_no,
        'name', upper(btrim(s.surname)) || coalesce(', ' || nullif((SELECT string_agg(left(w, 1) || '.', ' ') FROM regexp_split_to_table(btrim(coalesce(s.other_names, '')), '\s+') w WHERE w <> ''), ''), ''),
        'programme', s.programme, 'faculty', s.faculty, 'level', s.current_level,
        'status', CASE WHEN s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION') THEN 'IN_STUDY' WHEN s.status = 'DEFERRED' THEN 'DEFERRED'
                       WHEN s.status IN ('SUSPENDED', 'RUSTICATED') THEN 'SUSPENDED' WHEN s.status = 'GRADUATED' THEN 'GRADUATED' ELSE 'NOT_IN_STUDY' END,
        'session', policy.university_current_session(), 'as_at', now()));
END $$;
COMMENT ON FUNCTION apimgmt.student_status(text, text, text) IS
  'V511: the integration door''s student status lookup: the key, scope (students:status) and quota checked, then the student by matriculation number told minimally (name with initials, programme, faculty, level, IN_STUDY / DEFERRED / SUSPENDED / GRADUATED / NOT_IN_STUDY); every call logged';

COMMIT;
