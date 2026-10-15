-- ═══════════════════════════════════════
-- V485 — A student's password reset to the matriculation number at the ICT Support Desk
--
--   ICT Support already resets a student's password two ways (V346): a one-hour link to the address on record, or a random
--   temporary password handed over at the desk on the student's ticket. Most migrated students have no address on record,
--   and the University asks for the reset it uses at the counter: the matriculation number is the username and, until the
--   student chooses their own, the password — forced to change at the first sign-in.
--
--   No new password store and no plaintext: the portal already has that state. An account that must change its password and
--   holds no temporary password is on its "first password" (V178, V122, restored 13 Oct 2026): the sign-in door accepts the
--   number the student signs in with, and nothing else, and the change is forced before anything else; once the student
--   chooses a password the number opens nothing (V428). A reset to the default credential puts the student's one account in
--   that state: a fresh bcrypt hash of a random secret nobody holds (so the old password stops working), must-change on, any
--   temporary password withdrawn — the matriculation number is never written anywhere, not even as a hash.
--
--     · iam.student_reset_check(student) says, from the record, whether the reset may be made: the student found and not a
--       record merged into another, a matriculation number on the record (the register holds it in its shape and once:
--       ck_student_matric_shape, student_matric_no_key), a status the desk's policy allows (never a withdrawn, expelled,
--       transferred-out or deceased student, nor one still ADMITTED without a number), and the policy switched on;
--     · iam.student_account.support_reset_at — when ICT Support last reset the account, so the student's change page says
--       so; cleared when the student chooses a password;
--     · the support ledger takes the method DEFAULT_CREDENTIAL for PASSWORD_RESET, and ACCOUNT_UNLOCKED for a lockout cleared
--       with the reset — both in the Authentication module, neither ever carrying a value (ck_hd_sa_no_password);
--     · the desk's own settings row carries the policy: on or off, whether the reset clears a lockout unless the agent says
--       otherwise, whether a ticket is required, the most resets one agent makes in an hour, and the statuses it may reach.
--       The forced change is not a setting: the default credential never opens the portal without it.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V485: a student''s password reset to the matriculation number at the ICT Support Desk', true);

-- ── the ledger ──
ALTER TABLE helpdesk.support_action DROP CONSTRAINT ck_hd_sa_action;
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_action CHECK (action IN (
    'CONTACT_EDITED', 'PERSONAL_EDITED', 'FAMILY_EDITED', 'PHOTO_REPLACED', 'CHANGE_REQUESTED', 'REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED',
    'COURSE_RESTORED', 'REGISTRATION_SUBMITTED', 'RECORD_EXPORTED', 'PASSWORD_RESET', 'ACCOUNT_UNLOCKED', 'PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED',
    'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED', 'ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED'));
ALTER TABLE helpdesk.support_action DROP CONSTRAINT ck_hd_sa_no_password;
ALTER TABLE helpdesk.support_action ADD CONSTRAINT ck_hd_sa_no_password CHECK (
    action NOT IN ('PASSWORD_RESET', 'ACCOUNT_UNLOCKED')
    OR (old_value IS NULL AND new_value IS NULL
        AND (action <> 'PASSWORD_RESET' OR method IN ('RESET_LINK', 'TEMPORARY_PASSWORD', 'DEFAULT_CREDENTIAL'))));

CREATE OR REPLACE FUNCTION helpdesk.support_module(p_action text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_action IN ('REGISTRATION_CHOSEN', 'COURSE_ADDED', 'COURSE_DROPPED', 'COURSE_RESTORED', 'REGISTRATION_SUBMITTED') THEN 'COURSE_REGISTRATION'
                WHEN p_action IN ('PASSWORD_RESET', 'ACCOUNT_UNLOCKED') THEN 'AUTHENTICATION'
                WHEN p_action IN ('PAYMENT_INVESTIGATED', 'PAYMENT_VERIFIED', 'ENTITLEMENT_REFRESHED', 'RECEIPT_REGENERATED') THEN 'PAYMENT'
                WHEN p_action IN ('ESCALATED', 'TICKET_CREATED', 'TICKET_RESOLVED') THEN 'TICKET'
                WHEN p_action = 'RECORD_EXPORTED' THEN 'REPORTS'
                ELSE 'STUDENT_RECORD' END
$$;

-- ── the account ──
ALTER TABLE iam.student_account ADD COLUMN support_reset_at timestamptz NULL;
COMMENT ON COLUMN iam.student_account.support_reset_at IS
  'V485: when ICT Support last reset the password (to the default credential or a temporary one); cleared when the student chooses a password';

-- ── the policy, on the desk's settings row ──
ALTER TABLE helpdesk.setting
    ADD COLUMN student_reset_enabled  boolean NOT NULL DEFAULT true,
    ADD COLUMN student_reset_unlock   boolean NOT NULL DEFAULT true,
    ADD COLUMN student_reset_ticket   text    NOT NULL DEFAULT 'OPTIONAL',
    ADD COLUMN student_reset_hourly   integer NOT NULL DEFAULT 30,
    ADD COLUMN student_reset_statuses text[]  NOT NULL DEFAULT ARRAY['ACTIVE', 'PROBATION', 'DEFERRED', 'DORMANT', 'GRADUATED'],
    ADD CONSTRAINT ck_hd_setting_reset_ticket CHECK (student_reset_ticket IN ('OPTIONAL', 'REQUIRED')),
    ADD CONSTRAINT ck_hd_setting_reset_hourly CHECK (student_reset_hourly BETWEEN 1 AND 500),
    ADD CONSTRAINT ck_hd_setting_reset_statuses CHECK (cardinality(student_reset_statuses) >= 1
        AND student_reset_statuses <@ ARRAY['ACTIVE', 'PROBATION', 'DEFERRED', 'DORMANT', 'GRADUATED', 'SUSPENDED']);
-- the desk's one settings row, as V251 seeded it, where a database has lost it (the live-shaped copy of 13 Oct 2026 holds none,
-- so ICT Support Settings could not be read there)
INSERT INTO helpdesk.setting (row_no, auto_close_days, notify_agents_on_new) VALUES (true, NULL, true) ON CONFLICT (row_no) DO NOTHING;
COMMENT ON COLUMN helpdesk.setting.student_reset_statuses IS
  'V485: the student statuses the desk may reset to the default credential; a withdrawn, expelled, transferred-out, deceased or rusticated student, or one not yet matriculated, never';

-- ── may the reset be made: one answer for the desk's screen and the act ──
CREATE FUNCTION iam.student_reset_check(p_student uuid)
RETURNS TABLE(student_id uuid, full_name text, matric_no text, admission_no text, jamb_reg_no text, faculty text, department text, programme text,
              current_level integer, status text, has_account boolean, must_change boolean, temporary boolean, locked_until timestamptz,
              last_signed_in_at timestamptz, support_reset_at timestamptz, eligible boolean, refusal text)
LANGUAGE sql STABLE AS $$
    SELECT s.id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
           nullif(btrim(s.matric_no), ''), s.admission_no, s.jamb_reg_no, f.name, d.name, p.name, s.current_level, s.status,
           a.id IS NOT NULL, coalesce(a.must_change, false), a.temp_expires_at IS NOT NULL, a.locked_until, a.last_signed_in_at, a.support_reset_at,
           r.refusal IS NULL, r.refusal
      FROM people.student s
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN iam.student_account a ON a.student_id = s.id
      -- the policy, or its defaults should the settings row ever be missing
      LEFT JOIN helpdesk.setting g ON g.row_no
      CROSS JOIN LATERAL (SELECT CASE
               WHEN NOT coalesce(g.student_reset_enabled, true) THEN 'RESET_DISABLED'
               WHEN s.duplicate_of IS NOT NULL THEN 'RESET_MERGED_RECORD'
               WHEN nullif(btrim(s.matric_no), '') IS NULL THEN 'RESET_NO_MATRIC'
               WHEN NOT s.status = ANY (coalesce(g.student_reset_statuses, ARRAY['ACTIVE', 'PROBATION', 'DEFERRED', 'DORMANT', 'GRADUATED'])) THEN 'RESET_STATUS'
               END AS refusal) r
     WHERE s.id = p_student;
$$;
COMMENT ON FUNCTION iam.student_reset_check(uuid) IS
  'V485: the student as the ICT Support Desk sees them before a reset to the default credential — the record, the account''s state (never its hash) and whether the reset may be made, with the one reason when it may not';

COMMIT;
