-- ═══════════════════════════════════════
-- V419 — the Bursary told when an application window opens for a session whose applicant fees are not stated
--
--   V401 gave the Bursary its rule for a session whose applicant fees are not stated (CARRY the last stated session's amounts,
--   or REFUSE a fee reference until stated), and the readiness page named the gap. Nobody was told at the moment it starts to
--   matter: the opening of the session's application window. Now, when the POST_UTME_REGISTRATION window (the applicants' application window) is opened or reopened for a
--   session whose applicant fees are not stated, the Bursary is told once, with what the rule does meanwhile. (The applicant
--   is told on their dashboard by the API, from the same facts.)
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V419: the Bursary told when an application window opens on unstated applicant fees', true);

CREATE OR REPLACE FUNCTION admissions.tell_bursary_of_unstated_fees()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE f record; v_policy text;
BEGIN
    IF NEW.window_type <> 'POST_UTME_REGISTRATION' OR NEW.action NOT IN ('OPEN', 'REOPEN') THEN
        RETURN NULL;
    END IF;
    SELECT * INTO f FROM admissions.applicant_fee_rule(NEW.session);
    IF coalesce(f.stated, false) THEN
        RETURN NULL;
    END IF;
    v_policy := admissions.applicant_fee_policy();
    PERFORM admissions.tell_office('bursar',
        format('Applicant fees for %s are not stated and its application window is open', NEW.session),
        format('The application window for %s has been opened and the session''s applicant fees are not yet stated. %s State them on the fee page (Applicant · Post-UTME fees) so the right amounts apply from the start.',
               NEW.session,
               CASE WHEN v_policy = 'REFUSE' THEN 'Under the Bursary''s rule no fee reference is issued to an applicant until they are stated.'
                    WHEN f.carried_from IS NOT NULL THEN format('Meanwhile applicants are charged the %s amounts, carried forward.', f.carried_from)
                    ELSE 'Meanwhile applicants are charged the built-in amounts.' END),
        NULL);
    RETURN NULL;
END $fn$;
DROP TRIGGER IF EXISTS trg_window_opened_fees_unstated ON policy.portal_window_event;
CREATE TRIGGER trg_window_opened_fees_unstated
    AFTER INSERT ON policy.portal_window_event
    FOR EACH ROW EXECUTE FUNCTION admissions.tell_bursary_of_unstated_fees();
COMMENT ON FUNCTION admissions.tell_bursary_of_unstated_fees() IS
  'V419: on the opening or reopening of a session''s POST_UTME_REGISTRATION window with the session''s applicant fees not stated, the Bursary is told once, with what the rule does meanwhile.';

COMMIT;
