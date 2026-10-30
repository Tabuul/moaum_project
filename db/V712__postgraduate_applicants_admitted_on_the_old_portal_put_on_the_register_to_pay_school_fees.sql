-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V712 · Postgraduate applicants admitted on the old portal are put on the register at once, to pay school fees
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 30 October 2026: "allow all admitted migration pg applicant student to bypass all the process and pay
--  school fee, but we will upload their history of the other payments from the old portal".
--
--  V675 brings an applicant admitted on the old portal (the admitted template: "Admitted", "Admission Offered", "Accepted") in as
--  the School's offer, and leaves them to finish on this portal: the acceptance fee (posted only if the old portal verified it,
--  else held for the Bursary), physical screening (the old portal's decision applied, else opened here), and only then the
--  register (admissions.pg_admit) — the student account, the admission number, school fees. The University takes them as admitted:
--  the payments they made on the old portal are uploaded as history (the Bursary's old-portal payments upload), and nothing more is
--  asked of them here before school fees.
--
--  1 · admissions.pg_mig_admit_direct(application): an application the old portal decided as admitted (pg_legacy_application
--      .decided_on_old_portal; offered or accepted here, not yet on the register) is taken as accepted (accepted_at the old portal's
--      date, else now), screening is taken as cleared where it is required and not already cleared (recorded as the old portal's,
--      source OLD_PORTAL), and the applicant is put on the register (admissions.pg_admit, unchanged: the student, the admission
--      number, the account). A not-cleared or correction-required screening decided on THIS portal by its officers stands: that
--      application is left as it is. Nothing is recorded as paid: the acceptance fee stays unconfirmed unless it was posted.
--  2 · admissions.pg_mig_screening (V675, changed in place) does it for every such application the migration brings in or touches —
--      the import and the Bursary's verification of a held fee both call it — so a later upload admits as it imports.
--  3 · admissions.pg_admitted_on_old_portal(application): such an application. admissions.pg_new_fee_reference (changed in place)
--      refuses it an application or acceptance fee reference (PG_FEE_NOT_NEEDED): those payments are the old portal's, recorded
--      from its history. The applicant portal reads it (oldPortalAdmitted) and asks for no fee; school fees are paid on the
--      student portal, signed in on the admission number (V709: the admission number is the first password while the applicant
--      has not chosen their own; one chosen on the applicant portal is carried to the student account).
--  4 · The applications already migrated so are put on the register now; the migration names how many, and how many a screening
--      decided here keeps back. No notice is sent: the applicant portal shows the admission number on the next sign-in.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V712: postgraduate applicants admitted on the old portal put on the register to pay school fees (the University''s word of 30 October 2026)', true);

CREATE FUNCTION pg_temp.v712_swap(p_text text, p_old text, p_new text, p_times integer) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE n integer := (length(p_text) - length(replace(p_text, p_old, ''))) / length(p_old);
BEGIN
    IF n <> p_times THEN
        RAISE EXCEPTION 'V712: "%" found % time(s), expected %', left(p_old, 90), n, p_times;
    END IF;
    RETURN replace(p_text, p_old, p_new);
END $fn$;

-- ── 1 · admitted on the old portal: on the register at once ──
CREATE OR REPLACE FUNCTION admissions.pg_admitted_on_old_portal(p_application uuid) RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT EXISTS (SELECT 1 FROM admissions.pg_application a JOIN admissions.pg_legacy_application l ON l.application_id = a.id
                    WHERE a.id = p_application AND l.decided_on_old_portal AND a.state IN ('OFFERED', 'ACCEPTED', 'ADMITTED'))
$fn$;
COMMENT ON FUNCTION admissions.pg_admitted_on_old_portal(uuid) IS
  'V712: an application the old portal decided as admitted (offered, accepted or on the register here): put on the register without this portal''s acceptance fee or screening; its application and acceptance fees are the old portal''s, recorded from its payments.';

CREATE OR REPLACE FUNCTION admissions.pg_mig_admit_direct(p_app uuid) RETURNS uuid LANGUAGE plpgsql AS $fn$
DECLARE a admissions.pg_application; lg admissions.pg_legacy_application; sc admissions.pg_screening;
BEGIN
    SELECT * INTO a FROM admissions.pg_application WHERE id = p_app FOR UPDATE;
    SELECT * INTO lg FROM admissions.pg_legacy_application WHERE application_id = p_app;
    IF a.id IS NULL OR lg.application_id IS NULL OR NOT lg.decided_on_old_portal THEN RETURN NULL; END IF;
    IF a.student_id IS NOT NULL THEN RETURN a.student_id; END IF;
    IF a.state NOT IN ('OFFERED', 'ACCEPTED') THEN RETURN NULL; END IF;
    -- a screening this portal's officers decided against the applicant stands
    SELECT * INTO sc FROM admissions.pg_screening WHERE application_id = p_app;
    IF sc.application_id IS NOT NULL AND sc.source IS DISTINCT FROM 'OLD_PORTAL' AND sc.state IN ('NOT_CLEARED', 'CORRECTION_REQUIRED') THEN
        RETURN NULL;
    END IF;
    IF a.state = 'OFFERED' THEN
        UPDATE admissions.pg_application g
           SET state = 'ACCEPTED', accepted_at = coalesce(g.accepted_at, admissions.pg_mig_at(lg.accepted_on), now())
         WHERE g.id = p_app;
    END IF;
    -- the old portal's screening as it decided it, when cleared (as V675 records it); else, where this portal requires one and none has
    -- cleared the applicant, taken as cleared
    IF lg.screening_decision = 'CLEARED' AND NOT EXISTS (SELECT 1 FROM admissions.pg_screening x WHERE x.application_id = p_app AND x.state = 'CLEARED') THEN
        INSERT INTO admissions.pg_screening (application_id, state, remarks, decided_at, source)
        VALUES (p_app, 'CLEARED', concat_ws(' · ', 'Screened on the old portal', 'reference ' || lg.screening_reference, lg.screening_remarks),
                admissions.pg_mig_at(lg.screened_on), 'OLD_PORTAL')
        ON CONFLICT (application_id) DO UPDATE
           SET state = 'CLEARED', remarks = EXCLUDED.remarks, reason = NULL, decided_at = EXCLUDED.decided_at, source = 'OLD_PORTAL', updated_at = now();
        PERFORM admissions.pg_app_event(p_app, 'SCREENING_CLEARED', 'Cleared at physical screening on the old portal' || coalesce(' — ' || lg.screening_remarks, ''));
    ELSIF NOT admissions.pg_screening_ok(p_app) THEN
        INSERT INTO admissions.pg_screening (application_id, state, remarks, decided_at, source)
        VALUES (p_app, 'CLEARED',
                concat_ws(' · ', 'Admitted on the old portal: put on the register without screening here (V712)',
                          'old portal reference ' || lg.screening_reference, lg.screening_remarks),
                now(), 'OLD_PORTAL')
        ON CONFLICT (application_id) DO UPDATE
           SET state = 'CLEARED', remarks = EXCLUDED.remarks, reason = NULL, decided_at = EXCLUDED.decided_at, source = 'OLD_PORTAL', updated_at = now();
    END IF;
    PERFORM admissions.pg_app_event(p_app, 'ADMITTED_ON_OLD_PORTAL',
            'Admitted on the old portal: put on the University register to pay school fees; the fees paid on the old portal are recorded from its payments');
    RETURN admissions.pg_admit(p_app);
END $fn$;
COMMENT ON FUNCTION admissions.pg_mig_admit_direct(uuid) IS
  'V712: an application the old portal decided as admitted put on the register at once — taken as accepted, screening taken as cleared where required (a not-cleared decision made here stands), admissions.pg_admit; nothing recorded as paid. The student id, or NULL where it is not such an application or a screening here keeps it back.';

-- ── 2 · every such application the migration touches ──
DO $do$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('admissions.pg_mig_screening(uuid)'::regprocedure);
    d := pg_temp.v712_swap(d, $o$IF a.state <> 'ACCEPTED' OR lg.screening_decision IS NULL OR lg.screening_decision = 'PENDING' THEN RETURN false; END IF;$o$,
        $n$-- V712: admitted on the old portal: on the register at once, the old portal's payments recorded from its history
    IF lg.decided_on_old_portal AND a.state IN ('OFFERED', 'ACCEPTED') AND a.student_id IS NULL THEN
        RETURN admissions.pg_mig_admit_direct(p_app) IS NOT NULL;
    END IF;
    IF a.state <> 'ACCEPTED' OR lg.screening_decision IS NULL OR lg.screening_decision = 'PENDING' THEN RETURN false; END IF;$n$, 1);
    EXECUTE d;
END $do$;

-- ── 3 · no application or acceptance fee asked of them here ──
DO $do$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('admissions.pg_new_fee_reference(uuid,text)'::regprocedure);
    d := pg_temp.v712_swap(d, $o$    -- V694: the application fee is paid once by a person in a session$o$,
        $n$    -- V712: admitted on the old portal and on the register: the application and acceptance fees are the old portal's, recorded from its payments
    IF p_kind IN ('APPLICATION', 'ACCEPTANCE') AND admissions.pg_admitted_on_old_portal(p_application) THEN
        RAISE EXCEPTION 'PG_FEE_NOT_NEEDED: you were admitted on the old portal; the % fee you paid there is recorded from the old portal''s payments, and your school fees are paid on the student portal', lower(p_kind)
              USING ERRCODE = '23514', HINT = 'Sign in to the student portal with your admission number.';
    END IF;
    -- V694: the application fee is paid once by a person in a session$n$, 1);
    EXECUTE d;
END $do$;

-- ── 4 · those already migrated ──
DO $do$
DECLARE r record; n_admitted int := 0; n_kept int := 0;
BEGIN
    -- the pipeline's own notices are silent, as inside a migration (admissions.pg_tell_applicant)
    PERFORM set_config('moaum.pg_migration', 'V712', true);
    FOR r IN SELECT a.id FROM admissions.pg_application a JOIN admissions.pg_legacy_application l ON l.application_id = a.id
              WHERE l.decided_on_old_portal AND a.state IN ('OFFERED', 'ACCEPTED') AND a.student_id IS NULL
              ORDER BY a.application_no LOOP
        IF admissions.pg_mig_admit_direct(r.id) IS NULL THEN n_kept := n_kept + 1; ELSE n_admitted := n_admitted + 1; END IF;
    END LOOP;
    PERFORM set_config('moaum.pg_migration', '', true);
    RAISE NOTICE 'V712: % postgraduate applicant(s) admitted on the old portal put on the register; % kept back by a screening decided here', n_admitted, n_kept;
END $do$;

COMMIT;
