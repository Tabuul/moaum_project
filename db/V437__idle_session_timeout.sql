-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V437 — the idle session timeout
--
--   A session the person has left alone ends. The portal already holds every session on the server (platform.session,
--   V003: issued, last seen, an absolute end, ended with a reason) and refuses a token whose session has ended
--   (SessionGuard); this adds the one rule the Directorate of ICT sets — after how long a session with no activity ends,
--   and how long before that the person is warned — and the server's own enforcement of it:
--
--   1. platform.session_policy — one row (scope GLOBAL; a scope per office can be added later without a second table):
--      enabled (ON by default), the idle timeout (120 s; at least 30 s, at most eight hours), the warning before it
--      (30 s; shorter than the timeout) and whether the person may continue the session from the warning. Set only by
--      the Directorate of ICT or an administrator, every change on the audit spine with who and why.
--   2. platform.session_policy_for(office) — the policy a session is held to: its office's scope when one is stated,
--      else GLOBAL.
--   3. platform.session_expire_idle(id) — the session ended with the reason 'expired: idle', and the sign-in record told
--      (iam.sign_in_event outcome EXPIRED_IDLE, apart from a sign-out or a session ended by hand).
--   4. platform.session_monitor() and platform.open_sessions(limit) — for the ICT Director's security screen: how many
--      sessions are open and active, open but idle, expired for inactivity today, signed out today; and who holds each
--      open session, acting as what, since when and last seen when. Names and offices only.
--
--   The browser's countdown is for the person; the server's clock and this policy decide. A request the browser sends on
--   its own (a poll, a refresh of a board) carries X-Background and never counts as activity — only what the person does does.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1 · the policy ───────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE platform.session_policy (
    scope           text PRIMARY KEY,
    idle_enabled    boolean NOT NULL DEFAULT true,
    idle_seconds    int NOT NULL DEFAULT 120,
    warning_seconds int NOT NULL DEFAULT 30,
    allow_continue  boolean NOT NULL DEFAULT true,
    updated_by      uuid NULL,
    updated_office  text NULL,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    reason          text NULL,
    CONSTRAINT ck_session_policy_idle CHECK (idle_seconds BETWEEN 30 AND 28800),
    CONSTRAINT ck_session_policy_warning CHECK (warning_seconds BETWEEN 5 AND idle_seconds - 1)
);
INSERT INTO platform.session_policy (scope) VALUES ('GLOBAL');
SELECT audit.attach('platform.session_policy');
COMMENT ON TABLE platform.session_policy IS
  'V437: after how long without activity a session ends (idle_seconds), how long before that the person is warned (warning_seconds), whether they may continue from the warning; GLOBAL now, a scope per office later. Set by ICT or an administrator; every change on the audit spine.';

CREATE OR REPLACE FUNCTION platform.session_policy_for(p_office text)
RETURNS platform.session_policy LANGUAGE sql STABLE AS $$
    SELECT * FROM platform.session_policy WHERE scope = coalesce(p_office, 'GLOBAL')
    UNION ALL
    SELECT * FROM platform.session_policy WHERE scope = 'GLOBAL'
    LIMIT 1
$$;

CREATE OR REPLACE FUNCTION platform.set_session_policy(p_enabled boolean, p_idle int, p_warning int, p_allow boolean, p_reason text,
                                                       p_actor uuid, p_office text)
RETURNS platform.session_policy LANGUAGE plpgsql AS $$
DECLARE r platform.session_policy;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'SESSION_POLICY_OFFICE: the session timeout is set by the Directorate of ICT or an administrator' USING ERRCODE = '23514';
    END IF;
    IF p_idle IS NULL OR p_idle < 30 THEN
        RAISE EXCEPTION 'SESSION_POLICY_IDLE_MIN: the idle timeout is at least 30 seconds' USING ERRCODE = '23514';
    END IF;
    IF p_idle > 28800 THEN
        RAISE EXCEPTION 'SESSION_POLICY_IDLE_MAX: the idle timeout is at most eight hours (28,800 seconds)' USING ERRCODE = '23514';
    END IF;
    IF p_warning IS NULL OR p_warning < 5 THEN
        RAISE EXCEPTION 'SESSION_POLICY_WARNING_MIN: the warning comes at least 5 seconds before the timeout' USING ERRCODE = '23514';
    END IF;
    IF p_warning >= p_idle THEN
        RAISE EXCEPTION 'SESSION_POLICY_WARNING: Warning time must be shorter than the idle timeout.' USING ERRCODE = '23514';
    END IF;
    UPDATE platform.session_policy
       SET idle_enabled = coalesce(p_enabled, idle_enabled), idle_seconds = p_idle, warning_seconds = p_warning,
           allow_continue = coalesce(p_allow, allow_continue), updated_by = p_actor, updated_office = p_office, updated_at = now(),
           reason = nullif(btrim(coalesce(p_reason, '')), '')
     WHERE scope = 'GLOBAL'
    RETURNING * INTO r;
    RETURN r;
END $$;

-- ── 2 · a session that expired for inactivity, on the sign-in record ─────────────────────────────────────────────────
ALTER TABLE iam.sign_in_event DROP CONSTRAINT ck_sign_in_outcome;
ALTER TABLE iam.sign_in_event ADD CONSTRAINT ck_sign_in_outcome
    CHECK (outcome IN ('SIGNED_IN','BAD_PASSWORD','UNKNOWN','LOCKED','MUST_CHANGE','SIGNED_OUT','ENDED','EXPIRED_IDLE'));

CREATE OR REPLACE FUNCTION platform.session_expire_idle(p_id bytea)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE v_person uuid; v_user text;
BEGIN
    UPDATE platform.session SET ended_at = now(), ended_reason = 'expired: idle'
     WHERE id = p_id AND ended_at IS NULL
    RETURNING person_id INTO v_person;
    IF v_person IS NULL THEN
        RETURN false;
    END IF;
    SELECT coalesce((SELECT c.username FROM iam.credential c WHERE c.person_id = v_person),
                    (SELECT coalesce(s.matric_no, s.admission_no, s.jamb_reg_no) FROM people.student s WHERE s.id = v_person), '')
      INTO v_user;
    INSERT INTO iam.sign_in_event (id, username, person_id, outcome, session_id) VALUES (gen_random_uuid(), v_user, v_person, 'EXPIRED_IDLE', p_id);
    RETURN true;
END $$;
COMMENT ON FUNCTION platform.session_expire_idle(bytea) IS
  'V437: ends a session left alone past the idle timeout (ended_reason ''expired: idle'') and records EXPIRED_IDLE on the sign-in log; false when it had already ended.';

-- ── 3 · for the security screen ──────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION platform.session_monitor()
RETURNS TABLE (open_sessions int, active int, idle int, expired_idle_today int, signed_out_today int, ended_today int)
LANGUAGE sql STABLE AS $$
    WITH p AS (SELECT * FROM platform.session_policy WHERE scope = 'GLOBAL'),
         o AS (SELECT s.*, s.last_seen_at >= now() - make_interval(secs => (SELECT idle_seconds FROM p)) AS is_active
                 FROM platform.session s WHERE s.ended_at IS NULL AND s.absolute_end > now())
    SELECT (SELECT count(*) FROM o)::int,
           (SELECT count(*) FROM o WHERE is_active)::int,
           (SELECT count(*) FROM o WHERE NOT is_active)::int,
           (SELECT count(*) FROM platform.session s WHERE s.ended_reason = 'expired: idle' AND s.ended_at >= date_trunc('day', now()))::int,
           (SELECT count(*) FROM platform.session s WHERE s.ended_reason = 'signed out' AND s.ended_at >= date_trunc('day', now()))::int,
           (SELECT count(*) FROM platform.session s WHERE s.ended_at >= date_trunc('day', now()))::int
$$;

CREATE OR REPLACE FUNCTION platform.open_sessions(p_limit int DEFAULT 200)
RETURNS TABLE (session_id text, person_id uuid, name text, office text, issued_at timestamptz, last_seen_at timestamptz, status text)
LANGUAGE sql STABLE AS $$
    SELECT encode(s.id, 'hex'), s.person_id,
           coalesce((SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = s.person_id),
                    (SELECT st.surname || ', ' || st.other_names FROM people.student st WHERE st.id = s.person_id),
                    'Unknown'),
           s.active_office, s.issued_at, s.last_seen_at,
           CASE WHEN s.last_seen_at >= now() - make_interval(secs => (SELECT idle_seconds FROM platform.session_policy WHERE scope = 'GLOBAL'))
                THEN 'ACTIVE' ELSE 'IDLE' END
      FROM platform.session s
     WHERE s.ended_at IS NULL AND s.absolute_end > now()
     ORDER BY s.last_seen_at DESC
     LIMIT greatest(1, p_limit)
$$;
COMMENT ON FUNCTION platform.open_sessions(int) IS
  'V437: the sessions open now — who, acting as what, since when, last seen when, active or idle by the GLOBAL policy — for the ICT Director''s security screen; names and offices only.';
