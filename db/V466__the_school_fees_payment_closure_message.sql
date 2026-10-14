-- ═══════════════════════════════════════
-- V466 — The school-fees payment closure message, the Directorate of ICT's to write
--
--   While school fees payment is closed or on hold, the student's Fees page said the same fixed words to everyone ("The University
--   has not currently opened the payment portal…"). The application windows have had a closure message the Director writes
--   (V312, policy.portal_window_message); the school-fees payment window now has one too: SCHOOL_FEES_PAYMENT among the message's
--   window types, set by policy.window_message_set (restated from V446, the one change marked), each change on the window's
--   history. It starts as the portal's present words, so nothing a student reads changes until the Director writes another.
--   It is the window's message whatever calendar the student follows (a CCE student's window reads the same words).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V466: the school-fees payment closure message', true);

ALTER TABLE policy.portal_window_message DROP CONSTRAINT IF EXISTS portal_window_message_window_type_check;
ALTER TABLE policy.portal_window_message ADD CONSTRAINT portal_window_message_window_type_check CHECK (window_type IN (
    'POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'POST_UTME_CBT', 'POST_UTME_RESULT_CHECKING',
    'PRELIMINARY_SCIENCE_APPLICATION', 'SCHOOL_FEES_PAYMENT'));

-- V466: SCHOOL_FEES_PAYMENT carries a closure message too
CREATE OR REPLACE FUNCTION policy.window_message_set(p_type text, p_message text, p_actor uuid, p_office text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v_old text; v_new text;
BEGIN
    IF p_type NOT IN ('POST_UTME_REGISTRATION', 'POSTGRADUATE_APPLICATION', 'JUPEB_APPLICATION', 'CCE_APPLICATION', 'PRELIMINARY_SCIENCE_APPLICATION',
                      'SCHOOL_FEES_PAYMENT') THEN RAISE EXCEPTION 'no closure message for %', p_type USING ERRCODE = '23514'; END IF;
    v_new := btrim(regexp_replace(regexp_replace(coalesce(p_message, ''), '<[^>]*>', '', 'g'), '[\u0001-\u0008\u000B-\u001F\u007F]', '', 'g'));
    IF length(v_new) = 0 THEN RAISE EXCEPTION 'the closure message cannot be blank' USING ERRCODE = '23514'; END IF;
    IF length(v_new) > 2000 THEN RAISE EXCEPTION 'the closure message is at most 2000 characters' USING ERRCODE = '23514'; END IF;
    SELECT message INTO v_old FROM policy.portal_window_message WHERE window_type = p_type;
    INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office, updated_at)
    VALUES (p_type, v_new, p_actor, p_office, now())
    ON CONFLICT (window_type) DO UPDATE SET message = EXCLUDED.message, updated_by = EXCLUDED.updated_by, updated_office = EXCLUDED.updated_office, updated_at = now();
    INSERT INTO policy.portal_window_event (window_type, session, action, previous_state, new_state, reason, actor, office)
    SELECT p_type, coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1), (SELECT max(name) FROM policy.academic_session)),
           'MESSAGE', left(v_old, 120), left(v_new, 120), 'closure message updated', p_actor, p_office
     WHERE EXISTS (SELECT 1 FROM policy.academic_session);
END $function$;

INSERT INTO policy.portal_window_message (window_type, message, updated_by, updated_office)
VALUES ('SCHOOL_FEES_PAYMENT', 'The University has not currently opened the payment portal; please check again when it is reopened. A reference already generated is still paid and confirmed.', NULL, 'ict')
ON CONFLICT (window_type) DO NOTHING;

COMMIT;
