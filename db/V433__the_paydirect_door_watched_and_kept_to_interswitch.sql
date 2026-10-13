-- ═══════════════════════════════════════
-- V433 — the PAYDirect door watched, and kept to Interswitch
--
-- 9–13 October 2026: a firewall rule in front of the portal refused Interswitch's payment notifications for four days, and
-- nobody on the portal's side knew until Interswitch wrote. Two things follow.
--
-- 1 · The door is watched. Every call to the PAYDirect door (a customer validation or a payment notification) already leaves a
--     row on finance.gateway_event. finance.watch_paydirect() reads the door's own rhythm — the longest quiet spell among its
--     calls in the fourteen days before the last call — and tells the Directorate of ICT and the Bursary, once per silence,
--     when the door has been quiet for longer than that rhythm allows, and never for less than
--     finance.paydirect_setting.silence_hours. A door never called, or called fewer than twenty times in those fourteen days,
--     has no rhythm to judge by and is not reported. The message names any call the door itself refused in the quiet time,
--     so an address list that shuts Interswitch out is seen for what it is.
--
-- 2 · The door may be kept to Interswitch. The validation door needs no credential (a CustomerInformationRequest carries
--     none), so anyone may ask it the payer and the amount behind a reference. finance.paydirect_allowed_address lists the
--     addresses the door answers while finance.paydirect_setting.restrict_addresses is on. Every call's address is counted
--     on finance.paydirect_door_access, so the Directorate of ICT sees who calls before switching the restriction on, and
--     the switch is refused while no listed address has been seen at the door in the last seven days: it is never switched
--     on blind. The address is the one the API reads for the person at the other end (ClientAddress: X-Forwarded-For as the
--     edge in front of the portal writes it).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V433: the PAYDirect door watched and kept to Interswitch', true);

-- ── 1 · the door's settings, its address list, and who calls it ──────────────────────────────────────────────────────────────
CREATE TABLE finance.paydirect_setting (
    id                 boolean PRIMARY KEY DEFAULT true CHECK (id),
    restrict_addresses boolean NOT NULL DEFAULT false,
    watch_enabled      boolean NOT NULL DEFAULT true,
    silence_hours      int NOT NULL DEFAULT 6 CHECK (silence_hours BETWEEN 1 AND 168),
    last_alert_at      timestamptz NULL,
    last_alert_seen_at timestamptz NULL,
    updated_at         timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.paydirect_setting IS 'The PAYDirect door: whether it answers only the listed addresses, whether its silence is watched, the least silence worth reporting, and the last silence reported (one report per silence).';
INSERT INTO finance.paydirect_setting (id) VALUES (true);
SELECT audit.attach('finance.paydirect_setting');

CREATE TABLE finance.paydirect_allowed_address (
    address   inet PRIMARY KEY,
    label     text NULL,
    added_at  timestamptz NOT NULL DEFAULT now(),
    added_by  uuid NULL
);
COMMENT ON TABLE finance.paydirect_allowed_address IS 'The addresses (or ranges) the PAYDirect door answers while finance.paydirect_setting.restrict_addresses is on: Interswitch''s live addresses.';
SELECT audit.attach('finance.paydirect_allowed_address');

CREATE TABLE finance.paydirect_door_access (
    address   text NOT NULL,
    day       date NOT NULL,
    calls     int NOT NULL DEFAULT 0,
    refused   int NOT NULL DEFAULT 0,
    first_at  timestamptz NOT NULL DEFAULT now(),
    last_at   timestamptz NOT NULL DEFAULT now(),
    last_kind text NULL,
    PRIMARY KEY (address, day)
);
COMMENT ON TABLE finance.paydirect_door_access IS 'How often each address called the PAYDirect door, by day, and how many of its calls the address list refused.';
SELECT audit.exempt('finance.paydirect_door_access', 'how often each address called the PAYDirect door, by day — operational counting written on every call; the calls themselves are on finance.gateway_event');

-- the door's rhythm is read from its log by gateway and source
CREATE INDEX IF NOT EXISTS ix_ge_gateway_source_received ON finance.gateway_event (gateway, source, received_at);

-- ── 2 · the address list ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- whether an address is on the list (an address inside a listed range is); what is not an address is not
CREATE FUNCTION finance.paydirect_address_listed(p_address text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF nullif(btrim(coalesce(p_address, '')), '') IS NULL THEN RETURN false; END IF;
    RETURN EXISTS (SELECT 1 FROM finance.paydirect_allowed_address x WHERE btrim(p_address)::inet <<= x.address);
EXCEPTION WHEN data_exception THEN
    RETURN false;
END $$;

CREATE FUNCTION finance.add_paydirect_address(p_address text, p_label text)
RETURNS finance.paydirect_allowed_address LANGUAGE plpgsql AS $$
DECLARE a inet; r finance.paydirect_allowed_address;
BEGIN
    BEGIN
        a := btrim(coalesce(p_address, ''))::inet;
    EXCEPTION WHEN data_exception THEN
        RAISE EXCEPTION 'PAYDIRECT_ADDRESS_INVALID: "%" is not an address — an IPv4 or IPv6 address, or a range such as 41.223.145.0/24', coalesce(p_address, '') USING ERRCODE = '23514';
    END;
    INSERT INTO finance.paydirect_allowed_address AS x (address, label, added_by)
    VALUES (a, nullif(btrim(coalesce(p_label, '')), ''), nullif(current_setting('moaum.actor_id', true), '')::uuid)
    ON CONFLICT (address) DO UPDATE SET label = coalesce(EXCLUDED.label, x.label)
    RETURNING * INTO r;
    RETURN r;
END $$;

-- the last listed address stays while the door is kept to the list: removed, the door would answer nobody
CREATE FUNCTION finance.remove_paydirect_address(p_address text)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE s finance.paydirect_setting; n int;
BEGIN
    SELECT * INTO s FROM finance.paydirect_setting WHERE id;
    IF s.restrict_addresses AND (SELECT count(*) FROM finance.paydirect_allowed_address) <= 1 THEN
        RAISE EXCEPTION 'PAYDIRECT_LAST_ADDRESS: the last listed address is not removed while the door is kept to the list; switch the restriction off first' USING ERRCODE = '23514';
    END IF;
    DELETE FROM finance.paydirect_allowed_address WHERE address = btrim(coalesce(p_address, ''))::inet;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;

-- every call counted by its address; admitted unless the door is kept to the list and the address is not on it
CREATE FUNCTION finance.paydirect_door_admit(p_address text, p_kind text)
RETURNS boolean LANGUAGE plpgsql AS $$
DECLARE s finance.paydirect_setting; a text := nullif(btrim(coalesce(p_address, '')), ''); ok boolean;
BEGIN
    SELECT * INTO s FROM finance.paydirect_setting WHERE id;
    ok := NOT coalesce(s.restrict_addresses, false) OR finance.paydirect_address_listed(a);
    INSERT INTO finance.paydirect_door_access AS d (address, day, calls, refused, last_kind)
    VALUES (coalesce(a, '(no address)'), (now() AT TIME ZONE 'Africa/Lagos')::date, 1, CASE WHEN ok THEN 0 ELSE 1 END, p_kind)
    ON CONFLICT (address, day) DO UPDATE
       SET calls = d.calls + 1, refused = d.refused + CASE WHEN ok THEN 0 ELSE 1 END, last_at = now(), last_kind = EXCLUDED.last_kind;
    RETURN ok;
END $$;

-- who called the door in the last p_days days, and whether each is on the list
CREATE FUNCTION finance.paydirect_addresses_seen(p_days int DEFAULT 7)
RETURNS TABLE (address text, calls bigint, refused bigint, first_at timestamptz, last_at timestamptz, last_kind text, listed boolean)
LANGUAGE sql STABLE AS $$
    SELECT d.address, sum(d.calls), sum(d.refused), min(d.first_at), max(d.last_at),
           (array_agg(d.last_kind ORDER BY d.last_at DESC))[1], finance.paydirect_address_listed(d.address)
      FROM finance.paydirect_door_access d
     WHERE d.last_at >= now() - make_interval(days => greatest(1, coalesce(p_days, 7)))
     GROUP BY d.address
     ORDER BY max(d.last_at) DESC
$$;

-- the settings, written by the Directorate of ICT; the restriction is never switched on blind
CREATE FUNCTION finance.set_paydirect_door(p_restrict boolean, p_watch boolean, p_silence_hours int)
RETURNS finance.paydirect_setting LANGUAGE plpgsql AS $$
DECLARE s finance.paydirect_setting;
BEGIN
    SELECT * INTO s FROM finance.paydirect_setting WHERE id FOR UPDATE;
    IF coalesce(p_restrict, false) AND NOT s.restrict_addresses THEN
        IF NOT EXISTS (SELECT 1 FROM finance.paydirect_allowed_address) THEN
            RAISE EXCEPTION 'PAYDIRECT_NO_ADDRESS: list the addresses the door answers before keeping it to them' USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM finance.paydirect_door_access d WHERE d.last_at >= now() - interval '7 days' AND finance.paydirect_address_listed(d.address)) THEN
            RAISE EXCEPTION 'PAYDIRECT_ADDRESS_UNSEEN: no listed address has called the door in the last seven days; kept to the list now, the door would answer nobody. Compare the addresses seen at the door with the list first' USING ERRCODE = '23514';
        END IF;
    END IF;
    UPDATE finance.paydirect_setting
       SET restrict_addresses = coalesce(p_restrict, restrict_addresses),
           watch_enabled      = coalesce(p_watch, watch_enabled),
           silence_hours      = coalesce(p_silence_hours, silence_hours),
           updated_at         = now()
     WHERE id
    RETURNING * INTO s;
    RETURN s;
END $$;

-- ── 3 · the door's state, and the watch ──────────────────────────────────────────────────────────────────────────────────────
-- NEVER: never called. OK: within its rhythm. QUIET: longer than its rhythm, but too few calls to judge by. SILENT: reported.
CREATE FUNCTION finance.paydirect_door_status()
RETURNS TABLE (restrict_addresses boolean, watch_enabled boolean, silence_hours int, last_alert_at timestamptz,
               last_validation_at timestamptz, last_notification_at timestamptz, last_call_at timestamptz,
               calls_today bigint, calls_7d bigint, refused_7d bigint, calls_14d bigint,
               longest_gap_hours numeric, quiet_hours numeric, threshold_hours numeric, state text)
LANGUAGE plpgsql STABLE AS $$
DECLARE s finance.paydirect_setting; v_val timestamptz; v_not timestamptz; v_last timestamptz; n14 bigint; longest interval;
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; thr interval; quiet interval;
BEGIN
    SELECT * INTO s FROM finance.paydirect_setting WHERE id;
    SELECT max(e.received_at) FILTER (WHERE e.source = 'VALIDATE'), max(e.received_at) FILTER (WHERE e.source = 'WEBHOOK'), max(e.received_at)
      INTO v_val, v_not, v_last
      FROM finance.gateway_event e WHERE e.gateway = 'paydirect' AND e.source IN ('VALIDATE', 'WEBHOOK');
    IF v_last IS NOT NULL THEN
        SELECT count(*), max(g.received_at - g.prev) INTO n14, longest
          FROM (SELECT e.received_at, lag(e.received_at) OVER (ORDER BY e.received_at) AS prev
                  FROM finance.gateway_event e
                 WHERE e.gateway = 'paydirect' AND e.source IN ('VALIDATE', 'WEBHOOK')
                   AND e.received_at > v_last - interval '14 days' AND e.received_at <= v_last) g;
        quiet := now() - v_last;
        thr := greatest(make_interval(hours => s.silence_hours), coalesce(longest, interval '0') * 1.5);
    END IF;
    RETURN QUERY
    SELECT s.restrict_addresses, s.watch_enabled, s.silence_hours, s.last_alert_at, v_val, v_not, v_last,
           (SELECT coalesce(sum(d.calls), 0) FROM finance.paydirect_door_access d WHERE d.day = v_today),
           (SELECT coalesce(sum(d.calls), 0) FROM finance.paydirect_door_access d WHERE d.last_at >= now() - interval '7 days'),
           (SELECT coalesce(sum(d.refused), 0) FROM finance.paydirect_door_access d WHERE d.last_at >= now() - interval '7 days'),
           coalesce(n14, 0),
           round((extract(epoch FROM coalesce(longest, interval '0')) / 3600)::numeric, 1),
           round((extract(epoch FROM coalesce(quiet, interval '0')) / 3600)::numeric, 1),
           round((extract(epoch FROM coalesce(thr, interval '0')) / 3600)::numeric, 1),
           CASE WHEN v_last IS NULL THEN 'NEVER'
                WHEN quiet < thr THEN 'OK'
                WHEN coalesce(n14, 0) < 20 THEN 'QUIET'
                ELSE 'SILENT' END;
END $$;

-- the Directorate of ICT and the Bursary told once per silence; returns the messages queued
CREATE FUNCTION finance.watch_paydirect()
RETURNS int LANGUAGE plpgsql AS $$
DECLARE s finance.paydirect_setting; st record; r record; told int := 0; v_refused bigint; v_from text; vars jsonb; quiet_for text;
BEGIN
    SELECT * INTO s FROM finance.paydirect_setting WHERE id FOR UPDATE;
    IF NOT s.watch_enabled THEN RETURN 0; END IF;
    SELECT * INTO st FROM finance.paydirect_door_status();
    IF st.state <> 'SILENT' THEN RETURN 0; END IF;
    IF s.last_alert_seen_at IS NOT DISTINCT FROM st.last_call_at THEN RETURN 0; END IF;   -- this silence has been told
    SELECT coalesce(sum(d.refused), 0), string_agg(DISTINCT d.address, ', ') FILTER (WHERE d.refused > 0)
      INTO v_refused, v_from
      FROM finance.paydirect_door_access d WHERE d.last_at > st.last_call_at;
    quiet_for := CASE WHEN st.quiet_hours >= 48 THEN format('%s days', round(st.quiet_hours / 24)) ELSE format('%s hours', round(st.quiet_hours)) END;
    vars := jsonb_build_object(
        'SINCE', to_char(st.last_call_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY, HH24:MI'),
        'QUIET_FOR', quiet_for,
        'CALLS_14D', st.calls_14d,
        'USUAL_HOURS', st.longest_gap_hours,
        'REFUSED_NOTE', CASE WHEN v_refused > 0
                             THEN format(' In that time the door itself refused %s call(s) from %s by its address list: check the list on the Gateways screen.', v_refused, v_from)
                             ELSE '' END,
        'DOOR', coalesce(platform.portal_url(), '') || '/api/v1/payments/paydirect/interswitch');
    FOR r IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
              WHERE a.office_code IN ('ict', 'bursar') AND p.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        told := told + platform.tell_person(r.person_id, 'PAYDIRECT_SILENT', NULL, vars,
                                            'paydirect-silent:' || to_char(st.last_call_at AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS'));
    END LOOP;
    UPDATE finance.paydirect_setting SET last_alert_at = now(), last_alert_seen_at = st.last_call_at WHERE id;
    RETURN told;
END $$;

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('PAYDIRECT_SILENT', 'Quickteller door quiet',
 'To the Directorate of ICT and the Bursary when the PAYDirect door (Quickteller customer validations and payment notifications) has been quiet for longer than its own rhythm allows; once per silence',
 'The Quickteller payment door has gone quiet',
 E'Dear [FIRST_NAME],\n\nThe portal''s Quickteller (Interswitch PAYDirect) door has received nothing since [SINCE] — [QUIET_FOR]. In the fourteen days before that it took [CALLS_14D] calls, with no quiet spell longer than [USUAL_HOURS] hours.[REFUSED_NOTE]\n\nStudents may be paying on Quickteller without the portal hearing of it. Check with Interswitch that their messages reach [DOOR], and the firewall in front of the portal. Payments already made are brought in with the collections import on the Gateways screen once the door is open again.\n\nMOAUM Portal',
 '[UNIVERSITY_SHORT] portal: the Quickteller payment door has received nothing since [SINCE] ([QUIET_FOR]). Check with Interswitch and the firewall; see the Gateways screen.',
 'Quickteller door quiet',
 'Nothing has reached the Quickteller payment door since [SINCE] ([QUIET_FOR]); it usually goes no longer than [USUAL_HOURS] hours between calls.[REFUSED_NOTE]',
 ARRAY['FIRST_NAME','SINCE','QUIET_FOR','CALLS_14D','USUAL_HOURS','REFUSED_NOTE','DOOR','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH');

COMMIT;
