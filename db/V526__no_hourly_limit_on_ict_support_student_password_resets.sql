-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V526 — No hourly limit on ICT Support's student password resets
--
--   V485 limited each ICT Support agent to 30 resets to the default student credential in an hour (helpdesk.setting
--   .student_reset_hourly, 1 to 500, NOT NULL, default 30). At the desk, 17 Oct 2026, the Head of the ICT Support Desk was
--   refused the 31st ("You have reset 30 student passwords in the last hour, the desk's limit"); the University asked for no
--   limit for every ICT support agent. The setting is now optional: NULL — the default, and the desk's value from now — is no
--   limit; the Director of ICT may still state one (1 to 500) in ICT Support Settings. Every reset stays a person's act with a
--   reason, on the support ledger and in the password reset history, the student told each time.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V526: no hourly limit on ICT Support''s student password resets, at the University''s word', true);

ALTER TABLE helpdesk.setting ALTER COLUMN student_reset_hourly DROP NOT NULL, ALTER COLUMN student_reset_hourly SET DEFAULT NULL;
COMMENT ON COLUMN helpdesk.setting.student_reset_hourly IS
  'V485, V526: the resets to the default student credential an ICT Support agent may make in an hour — NULL (the default since V526) is no limit; when stated, 1 to 500';
UPDATE helpdesk.setting SET student_reset_hourly = NULL WHERE row_no AND student_reset_hourly IS NOT NULL;

COMMIT;
