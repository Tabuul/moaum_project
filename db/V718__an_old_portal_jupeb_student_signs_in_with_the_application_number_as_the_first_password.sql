-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V718 · A JUPEB student uploaded from the old portal signs in with the application number as the first password
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 11 November 2026: "UPLOADED JUPEB STUDENT FROM OLD PORTAL CANNOT LOGIN USING THEIR APPLICATION NUMBER
--  AND PASSWORD".
--
--  Why they could not: V345 gives each student the old portal's upload makes a random temporary password, hashed, shown once to the
--  uploading office on a login sheet and never stored readable; the student knows it only if the office handed it to them. And the
--  one sign-in page sends a number of the old portal's shape (S007202609174486) to the staff door and, since V709, the postgraduate
--  door — never the JUPEB door, which finds the student by it. On the live copy of 21 October 2026, 104 students were so: every one
--  still to change their password, none ever signed in.
--
--  As the University settled it for undergraduate applicants (V706) and postgraduate applicants (V709): while an uploaded student is
--  still to choose their own password (jupeb.account.must_change_password, no temporary password from the desk), the application
--  number — the old portal's, kept as the application's number and its legacy reference — opens the account as the first password,
--  however its letters and spaces are typed; the portal then asks them to choose their own before anything else (V345's gate). The
--  rule is jupeb.first_password_opens(account, typed), read at the door (JupebPublicController) and at the change of password; no
--  number is hashed into the accounts. A temporary password ICT Support issues at the desk (V347) is unchanged: it opens once, until
--  its time, and the number does not open an account that holds one. A student who has chosen their own password is unchanged.
--  The sign-in page's own part — an unknown number tried at the JUPEB door after the staff and postgraduate doors — is in the frontend.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V718: an old-portal JUPEB student signs in with the application number as the first password (the University''s word of 11 November 2026)', true);

CREATE FUNCTION jupeb.first_password_opens(p_account uuid, p_typed text) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (
        SELECT 1 FROM jupeb.account acc
         WHERE acc.id = p_account AND acc.must_change_password AND acc.temp_expires_at IS NULL
           AND nullif(upper(regexp_replace(coalesce(p_typed, ''), '\s+', '', 'g')), '') IS NOT NULL
           AND EXISTS (SELECT 1 FROM jupeb.application x
                        WHERE x.account_id = acc.id
                          AND upper(regexp_replace(coalesce(p_typed, ''), '\s+', '', 'g')) IN (upper(x.application_no), upper(coalesce(x.legacy_ref, '')))))
$fn$;
COMMENT ON FUNCTION jupeb.first_password_opens(uuid, text) IS
  'V718: whether what was typed opens the JUPEB account as its first password — the account is still to choose its own password (must_change_password) and holds no temporary password from the desk, and the text is the application number (this portal''s, or the old portal''s legacy reference) however its letters and spaces are typed. Read at the sign-in and at the change of password; never hashed into the account.';

COMMENT ON COLUMN jupeb.account.must_change_password IS
  'V345, V718: the student chooses their own password at the next sign-in before anything else. Until then — and while no temporary password from the desk is set — the application number opens the account as the first password (jupeb.first_password_opens).';

COMMIT;
