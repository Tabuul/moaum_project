-- V522: the hanging-payment and fee-gap alerts reach the Students Account Officer too.
--
-- V520 made the Students Account Officer (office studentaccounts) the Bursary's desk for hanging payments and for stating the
-- session's school-fee lines, but the two alerts of those duties still went to the Bursar's office holders alone:
--   * PAYDIRECT_UNREPORTED (V477, V490) — once a day, the Pay on Quickteller payments Interswitch has not reported after a day,
--     with the Ask Interswitch list and the hanging payments screen, which the officer works;
--   * FEE_GAPS (V451, V457) — while a semester is open, the students of the session with no school fee stated, which the officer
--     may now state on the Fee Schedule screen.
-- Both are restated from their current definitions (V490's and V457's) with the officer among the recipients; nothing else in them
-- changes, and each event is still told once per person (the event key is unchanged). The gateway alerts (PAYDIRECT_SILENT,
-- PAYDIRECT_UNSETTLED) stay with the Bursary and ICT: the gateway screen is not the officer's.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V522: the hanging-payment and fee-gap alerts reach the Students Account Officer too', true);

CREATE OR REPLACE FUNCTION finance.watch_paydirect_unreported(p_at timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int; v_total numeric; v_oldest timestamptz; v_list text; v_receipts text; v_with int; v_elsewhere int; vars jsonb; r record; told int := 0;
BEGIN
    IF NOT coalesce((SELECT s.watch_enabled FROM finance.paydirect_setting s LIMIT 1), true) THEN RETURN 0; END IF;
    IF extract(hour FROM p_at AT TIME ZONE 'Africa/Lagos') < 8 THEN RETURN 0; END IF;   -- told in the working day, not overnight
    SELECT count(*), coalesce(sum(w.amount), 0), min(w.since), count(w.log_id), count(*) FILTER (WHERE w.state = 'ELSEWHERE')
      INTO n, v_total, v_oldest, v_with, v_elsewhere FROM finance.paydirect_waiting(p_at) w;
    IF n = 0 THEN RETURN 0; END IF;
    SELECT string_agg(format('%s — %s%s — ₦%s — since %s%s', w.reference, coalesce(w.payer, 'payer unknown'), coalesce(' (' || w.number || ')', ''),
                             to_char(coalesce(w.amount, 0), 'FM999,999,999,990.00'), to_char(w.since AT TIME ZONE 'Africa/Lagos', 'DD Mon, HH24:MI'),
                             CASE WHEN w.log_id IS NULL THEN ''
                                  ELSE format(' — receipt %s, paid %s%s', w.log_id, to_char(w.paid_on, 'FMDD Mon'),
                                              CASE WHEN w.state = 'ELSEWHERE' THEN ', reported by Interswitch against ' || w.seen_reference
                                                   WHEN w.state = 'SEEN' THEN ', reported by Interswitch for it and not settled' ELSE '' END) END),
                      E'\n' ORDER BY w.since)
      INTO v_list FROM (SELECT * FROM finance.paydirect_waiting(p_at) z ORDER BY z.since LIMIT 10) w;
    v_receipts := CASE WHEN v_with = 0 THEN 'No payer has reported a receipt for them.'
                       ELSE format('Payers reported the receipt (its Payment Log Id) for %s of them%s.', v_with,
                                   CASE WHEN v_elsewhere > 0 THEN format('; Interswitch reported %s of those against another reference — the Bursary''s to settle, not Interswitch''s to re-send', v_elsewhere) ELSE '' END) END;
    vars := jsonb_build_object(
        'COUNT', n,
        'TOTAL', '₦' || to_char(v_total, 'FM999,999,999,990.00'),
        'OLDEST', to_char(v_oldest AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'),
        'RECEIPTS', v_receipts,
        'LIST', v_list || CASE WHEN n > 10 THEN format(E'\n… and %s more', n - 10) ELSE '' END,
        'SCREEN', coalesce(platform.portal_url(), '') || '/finance/hanging');
    FOR r IN SELECT DISTINCT a.person_id
               FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id
              WHERE a.office_code IN ('bursar', 'studentaccounts') AND p.ended_on IS NULL
                AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
        told := told + platform.tell_person(r.person_id, 'PAYDIRECT_UNREPORTED', NULL, vars,
                                            'paydirect-unreported:' || to_char(p_at AT TIME ZONE 'Africa/Lagos', 'YYYYMMDD'));
    END LOOP;
    RETURN told;
END $function$;

CREATE OR REPLACE FUNCTION finance.watch_fee_gaps(p_session text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_ses text := coalesce(p_session, policy.university_current_session()); v_keys text[]; v_new text[]; v_students bigint; v_groups int; v_list text;
        v_prev text[]; v_vars jsonb; v_at text; p record; told int := 0;
BEGIN
    -- only while a semester of the session (the current one, unless named) is open: a session not yet running is still being stated
    IF v_ses IS NULL OR NOT EXISTS (SELECT 1 FROM policy.semester WHERE session = v_ses AND state = 'OPEN') THEN
        RETURN 0;
    END IF;
    WITH g AS (SELECT * FROM finance.fee_gaps(v_ses)),
    fac AS (SELECT coalesce(g.faculty, g.faculty_code) AS f, sum(g.students) AS n FROM g GROUP BY 1)
    SELECT (SELECT coalesce(array_agg(x.k ORDER BY x.k), '{}'::text[])
              FROM (SELECT concat_ws('|', g.programme_code, g.level, g.entry_mode, g.indigene, g.spillover, coalesce(g.missing::text, 'none')) AS k FROM g) x),
           (SELECT coalesce(sum(g.students), 0) FROM g),
           (SELECT count(*) FROM g),
           (SELECT string_agg(replace(replace(replace(initcap(lower(fac.f)), ' And ', ' and '), ' Of ', ' of '), ' For ', ' for ')
                              || ' ' || to_char(fac.n, 'FM999,999,999'), '; ' ORDER BY fac.n DESC, fac.f) FROM fac)
      INTO v_keys, v_students, v_groups, v_list;
    SELECT w.told_keys INTO v_prev FROM finance.fee_gap_watch w WHERE w.session = v_ses FOR UPDATE;
    v_new := ARRAY(SELECT k FROM unnest(v_keys) k WHERE NOT k = ANY (coalesce(v_prev, '{}'::text[])));
    IF cardinality(v_new) > 0 THEN
        v_at := to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS');   -- each telling its own event
        v_vars := jsonb_build_object('SESSION', v_ses, 'STUDENTS', to_char(v_students, 'FM999,999,999'), 'GROUPS', v_groups,
                                     'NEW_GROUPS', cardinality(v_new), 'FACULTIES', coalesce(v_list, ''));
        FOR p IN SELECT DISTINCT a.person_id
                   FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
                  WHERE a.office_code IN ('bursar', 'studentaccounts') AND pe.ended_on IS NULL
                    AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
            told := told + platform.tell_person(p.person_id, 'FEE_GAPS', NULL, v_vars,
                                                'fee-gaps:' || v_ses || ':' || md5(array_to_string(v_new, ',')) || ':' || v_at, ARRAY['EMAIL', 'PORTAL', 'SMS']);
        END LOOP;
    END IF;
    -- the groups seen now are the ones told: a gap put right and opened again is told again
    INSERT INTO finance.fee_gap_watch AS w (session, told_keys, told_at, told, students, groups, checked_at)
    VALUES (v_ses, v_keys, CASE WHEN cardinality(v_new) > 0 THEN now() END, told, v_students, v_groups, now())
    ON CONFLICT (session) DO UPDATE
       SET told_keys = excluded.told_keys,
           told_at = coalesce(excluded.told_at, w.told_at),
           told = CASE WHEN excluded.told_at IS NOT NULL THEN excluded.told ELSE w.told END,
           students = excluded.students, groups = excluded.groups, checked_at = excluded.checked_at;
    RETURN told;
END $function$;

UPDATE platform.notice_template
   SET purpose = replace(purpose, 'To the Bursary ', 'To the Bursary and the Students Account Officer '), updated_at = now()
 WHERE key IN ('PAYDIRECT_UNREPORTED', 'FEE_GAPS') AND purpose LIKE 'To the Bursary %';

COMMIT;
