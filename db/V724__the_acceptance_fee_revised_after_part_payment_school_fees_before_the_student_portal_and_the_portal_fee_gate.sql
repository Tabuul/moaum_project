-- ═══════════════════════════════════════════════════════════
-- V724 — the acceptance fee revised after part of it was paid; school fees read for an admitted applicant
--         before the student portal opens; the student portal's fee gate for fresh admits; the monitors
--
--   The University's master prompt of 11 November 2026 ("2026/2027 ACCEPTANCE FEE BALANCE RECOVERY, SCHOOL FEES
--   CONFIGURATION AND STUDENT PORTAL ACCESS CONTROL"). The 2026/2027 acceptance fee was stated at ₦25,000 and is revised to
--   ₦35,000: an applicant who paid ₦25,000 owes ₦10,000, never ₦35,000 again; one who paid ₦35,000 owes nothing. Until now
--   "accepted" was a boolean (any confirmed ACCEPTANCE reference) and a second reference was refused outright, so a revised
--   fee could neither be owed nor paid; the admission letter followed the acceptance alone; the Bursary's restatement of a
--   session's applicant fees overwrote the row with no history.
--
--   1 · admissions.applicant_fee_revision keeps every statement of a session's applicant fees (the trigger on
--       admissions.applicant_fee writes it, with who, from which office, and why); a revision of the acceptance fee closes the
--       session's open ACCEPTANCE references drawn at another figure.
--   2 · admissions.acceptance_entitlement says, beside what it said, the fee due (admissions.acceptance_fee_due — the stated
--       acceptance fee of the application's session or route), the total confirmed, the balance, whether the acceptance is
--       settled, and the open reference. admissions.new_fee_reference draws an ACCEPTANCE reference for the balance (the
--       whole fee before anything is confirmed), returns one still open for that amount rather than a second (draws for one
--       application one at a time), closes one drawn for another figure, and refuses once settled (ACCEPTANCE_SETTLED); the
--       stated fee is kept on the reference. UTME and Direct Entry: a CCE or preliminary admission paid once is paid, as before.
--       admissions.fee_reversal_check lets the Bursary reverse a balance reference confirmed in error (V420 held every
--       ACCEPTANCE reference once the offer was accepted, and a balance is always paid after acceptance).
--   3 · admissions.issue_admission_letter waits for the balance (ACCEPTANCE_BALANCE_DUE) — the undertaking, the screening and
--       the register do not; the tracker's letter step follows.
--   4 · finance.school_fee_state(student, session): NOT_CONFIGURED (no fee line reaches the student — nothing is charged at
--       a guess), NOT_OPEN (the payment window), PAYMENT_PENDING (a reference awaiting the bank), AVAILABLE, PART_PAID, PAID,
--       with the figures; admissions.admission_status says SCHOOL_FEES_NOT_AVAILABLE / SCHOOL_FEES_NOT_OPEN /
--       SCHOOL_FEES_PART_PAID and, while the gate stands, sends the applicant to pay on their own dashboard.
--   5 · finance.portal_fee_gate (one row: on, from which entry session, what clears it — the first semester's fees, as the
--       University chose on 11 November 2026, or the session's in full) and finance.portal_fee_gate_exception (the Bursary's,
--       within a term); finance.portal_access_state(student): OPEN (not a fresh admit of a gated session with an applicant
--       account to pay from, or the gate off), EXCEPTION, HELD_ACCEPTANCE_BALANCE (the acceptance balance comes first), CLEARED,
--       HELD_FEES_NOT_AVAILABLE, HELD_FEES_UNPAID — read at the student door and on every student request.
--       Matriculation, the register and the admission number are untouched: the gate only reads them.
--   6 · finance.programme_fee_coverage(session): every undergraduate programme with or without a fee line reaching a fresh
--       UTME (100 Level) or Direct Entry (200 Level) entrant; admissions.acceptance_fee_monitor(session) and
--       finance.intake_fee_monitor(session): the rows the monitors and their drill-downs read.
-- ═══════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V724: acceptance fee revised, school fees before the student portal, the portal fee gate', true);

-- ── 1 · every statement of a session's applicant fees is kept ──────────────────────────────────────────────
CREATE TABLE admissions.applicant_fee_revision (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session                 text NOT NULL,
    application_fee         numeric(12,2) NOT NULL,
    portal_charge           numeric(12,2) NOT NULL,
    acceptance_fee          numeric(12,2) NOT NULL,
    checking_fee            numeric(12,2) NULL,
    previous_acceptance_fee numeric(12,2) NULL,
    stated_at               timestamptz NOT NULL DEFAULT now(),
    stated_by               uuid NULL,
    stated_office           text NULL,
    reason                  text NULL
);
CREATE INDEX ix_applicant_fee_revision_session ON admissions.applicant_fee_revision (session, stated_at);
SELECT audit.attach('admissions.applicant_fee_revision');
COMMENT ON TABLE admissions.applicant_fee_revision IS
  'V724: every statement of a session''s applicant fees (admissions.applicant_fee is one row a session, overwritten): the figures stated, '
  'the acceptance fee before, who stated them, from which office, why. Written by the trigger; never changed or removed.';

CREATE FUNCTION admissions.applicant_fee_revision_kept()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'APPLICANT_FEE_REVISION_KEPT: a statement of the applicant fees is kept as it was made' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_applicant_fee_revision_kept BEFORE UPDATE OR DELETE ON admissions.applicant_fee_revision
    FOR EACH ROW EXECUTE FUNCTION admissions.applicant_fee_revision_kept();

CREATE FUNCTION admissions.applicant_fee_revised()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_before numeric;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.application_fee = OLD.application_fee AND NEW.portal_charge = OLD.portal_charge
       AND NEW.acceptance_fee = OLD.acceptance_fee AND NEW.checking_fee IS NOT DISTINCT FROM OLD.checking_fee THEN
        RETURN NULL;   -- stated again as it was: no revision
    END IF;
    -- the figure before: the session's own, or — the first statement of a session that carried another's forward (V272) — the one carried
    v_before := CASE WHEN TG_OP = 'UPDATE' THEN OLD.acceptance_fee
                     ELSE (SELECT f.acceptance_fee FROM admissions.applicant_fee f WHERE f.session <> NEW.session ORDER BY f.stated_at DESC, f.session DESC LIMIT 1) END;
    INSERT INTO admissions.applicant_fee_revision (session, application_fee, portal_charge, acceptance_fee, checking_fee, previous_acceptance_fee,
                                                   stated_by, stated_office, reason)
    VALUES (NEW.session, NEW.application_fee, NEW.portal_charge, NEW.acceptance_fee, NEW.checking_fee, v_before,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''),
            nullif(btrim(current_setting('moaum.reason', true)), ''));
    -- an ACCEPTANCE reference still open at another figure stops being payable: the applicant draws one for what is owed now
    IF v_before IS NOT NULL AND NEW.acceptance_fee <> v_before THEN
        UPDATE admissions.fee_reference r SET expires_at = least(r.expires_at, now())
          FROM admissions.application a
         WHERE a.id = r.application_id AND a.session = NEW.session AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NULL AND r.expires_at > now()
           AND r.amount <> (SELECT e.balance FROM admissions.acceptance_entitlement(a.id) e);
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_applicant_fee_revised AFTER INSERT OR UPDATE ON admissions.applicant_fee
    FOR EACH ROW EXECUTE FUNCTION admissions.applicant_fee_revised();
-- the history before V724: each session's row as it stands, dated as it was stated
INSERT INTO admissions.applicant_fee_revision (session, application_fee, portal_charge, acceptance_fee, checking_fee, stated_at, reason)
SELECT f.session, f.application_fee, f.portal_charge, f.acceptance_fee, f.checking_fee, f.stated_at, 'As stated before V724'
  FROM admissions.applicant_fee f;

ALTER TABLE admissions.fee_reference ADD COLUMN stated_fee numeric(12,2) NULL;
COMMENT ON COLUMN admissions.fee_reference.stated_fee IS
  'V724: for an ACCEPTANCE reference, the acceptance fee stated when it was drawn; the amount is what was owed then (the whole fee, or the balance after a revision).';

-- ── 2 · the acceptance fee due, what is confirmed, the balance ────────────────────────────────────────────
CREATE FUNCTION admissions.acceptance_fee_due(p_app uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN admissions.applicant_route(a.id) IS NOT NULL
                THEN (SELECT r.acceptance_fee FROM admissions.route_fee_rule(a.session, admissions.applicant_route(a.id)) r)
                ELSE (SELECT r.acceptance_fee FROM admissions.applicant_fee_rule(a.session) r) END
      FROM admissions.application a WHERE a.id = p_app
$$;
COMMENT ON FUNCTION admissions.acceptance_fee_due(uuid) IS
  'V724: the acceptance fee stated for the application''s session — the route''s (CCE, preliminary, proficiency) or the Post-UTME figure, as it stands now.';

DROP FUNCTION IF EXISTS admissions.acceptance_entitlement(uuid);
CREATE FUNCTION admissions.acceptance_entitlement(p_app uuid)
RETURNS TABLE (paid boolean, reference text, confirmed_at timestamptz, amount numeric,
               checking_paid boolean, checking_reference text, checking_confirmed_at timestamptz, checking_amount numeric,
               fee_due numeric, paid_total numeric, balance numeric, settled boolean, payments int, balance_due boolean,
               open_reference text, open_amount numeric, open_expires_at timestamptz)
LANGUAGE sql STABLE AS $$
    SELECT x.paid, x.reference, x.confirmed_at, x.amount, x.checking_paid, x.checking_reference, x.checking_confirmed_at, x.checking_amount,
           x.fee_due, x.paid_total, x.balance, x.paid AND x.balance = 0, x.payments, x.payments > 0 AND x.balance > 0,
           x.open_reference, x.open_amount, x.open_expires_at
      FROM (
    SELECT (a.acceptance_confirmed_at IS NOT NULL OR fr.confirmed_at IS NOT NULL) AS paid, fr.reference, coalesce(a.acceptance_confirmed_at, fr.confirmed_at) AS confirmed_at, fr.amount,
           (a.checking_confirmed_at IS NOT NULL OR ck.confirmed_at IS NOT NULL OR a.acceptance_confirmed_at IS NOT NULL OR fr.confirmed_at IS NOT NULL) AS checking_paid,
           ck.reference AS checking_reference, coalesce(a.checking_confirmed_at, ck.confirmed_at) AS checking_confirmed_at, ck.amount AS checking_amount,
           -- V724: the fee as stated now, the total confirmed (a reversed confirmation has no confirmed_at, V420), the balance — an acceptance
           -- confirmed with no reference behind it (by hand, or carried from the old portal) owes nothing: only a payment made through a
           -- reference, short of the fee as stated now, leaves a balance (balance_due)
           due.fee AS fee_due, sm.total AS paid_total,
           -- a CCE, preliminary or proficiency admission paid once is paid, as before V724: the revision is the Post-UTME acceptance fee's
           CASE WHEN sm.n = 0 AND a.acceptance_confirmed_at IS NOT NULL THEN 0
                WHEN admissions.applicant_route(a.id) IS NOT NULL AND (a.acceptance_confirmed_at IS NOT NULL OR fr.confirmed_at IS NOT NULL) THEN 0
                ELSE greatest(due.fee - sm.total, 0) END AS balance,
           sm.n AS payments, op.reference AS open_reference, op.amount AS open_amount, op.expires_at AS open_expires_at
      FROM admissions.application a
      LEFT JOIN LATERAL (SELECT r.reference, r.confirmed_at, r.amount FROM admissions.fee_reference r
                          WHERE r.application_id = a.id AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NOT NULL ORDER BY r.confirmed_at LIMIT 1) fr ON true
      LEFT JOIN LATERAL (SELECT r.reference, r.confirmed_at, r.amount FROM admissions.fee_reference r
                          WHERE r.application_id = a.id AND r.kind = 'CHECKING' AND r.confirmed_at IS NOT NULL ORDER BY r.confirmed_at LIMIT 1) ck ON true
      CROSS JOIN LATERAL (SELECT coalesce(sum(r.amount), 0) AS total, count(*)::int AS n FROM admissions.fee_reference r
                           WHERE r.application_id = a.id AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NOT NULL) sm
      CROSS JOIN LATERAL (SELECT coalesce(admissions.acceptance_fee_due(a.id), sm.total) AS fee) due
      LEFT JOIN LATERAL (SELECT r.reference, r.amount, r.expires_at FROM admissions.fee_reference r
                          WHERE r.application_id = a.id AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NULL AND r.expires_at > now()
                          ORDER BY r.generated_at DESC LIMIT 1) op ON true
     WHERE a.id = p_app) x;
$$;
COMMENT ON FUNCTION admissions.acceptance_entitlement(uuid) IS
  'The acceptance and the checking fees of an admission (V271) — and, since V724, the acceptance fee due as stated now, the total confirmed through '
  'references, the balance owed, whether the acceptance is settled (paid and nothing owed), how many payments, whether a balance is due (a payment '
  'made through a reference short of the fee as stated now — what the admission letter waits for), and the reference still open. paid is as it was: '
  'any confirmed ACCEPTANCE reference or the confirmation flag (the place is held, the screening and the register follow).';

-- ── 4 · what the school fees say for one student in a session ─────────────────────────────────────────────
CREATE FUNCTION finance.school_fee_state(p_student uuid, p_session text)
RETURNS TABLE (state text, due numeric, paid numeric, balance numeric, paid_in_full boolean, first_semester_cleared boolean, instalments_paid int,
               window_state text, opens_at timestamptz, open_reference text, open_amount numeric, open_expires_at timestamptz, unstated_semesters int[])
LANGUAGE sql STABLE AS $$
    WITH pos AS (SELECT * FROM finance.position(p_student, p_session)),
         win AS (SELECT w.state, w.opens_at FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL) w),
         st AS (SELECT finance.fee_stated(p_student, p_session) AS stated, finance.fee_unstated_semesters(p_student, p_session) AS unstated),
         op AS (SELECT r.reference, r.amount, r.expires_at FROM finance.payment_reference r
                 WHERE r.student_id = p_student AND r.session = p_session AND r.purpose LIKE 'School fees%'
                   AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
                 ORDER BY r.generated_at DESC LIMIT 1)
    SELECT CASE WHEN NOT st.stated OR pos.due <= 0 THEN 'NOT_CONFIGURED'
                WHEN pos.paid_in_full THEN 'PAID'
                WHEN op.reference IS NOT NULL THEN 'PAYMENT_PENDING'
                WHEN win.state <> 'OPEN' THEN 'NOT_OPEN'
                WHEN pos.paid > 0 THEN 'PART_PAID'
                ELSE 'AVAILABLE' END,
           pos.due, pos.paid, pos.balance, pos.paid_in_full,
           -- a first semester with nothing charged in it is not "paid" (a session staged with only a later semester's line)
           finance.due_for_semester(p_student, p_session, 1) > 0 AND finance.semester_cleared(p_student, p_session, 1), pos.instalments_paid,
           win.state, win.opens_at, op.reference, op.amount, op.expires_at, st.unstated
      FROM pos CROSS JOIN win CROSS JOIN st LEFT JOIN op ON true
$$;
COMMENT ON FUNCTION finance.school_fee_state(uuid, text) IS
  'V724: NOT_CONFIGURED (no FEE line in force reaches the student, or nothing is due — nothing is charged at a guess), PAID, PAYMENT_PENDING (a reference '
  'drawn and awaiting the bank), NOT_OPEN (the SCHOOL_FEES_PAYMENT window), PART_PAID, AVAILABLE — with finance.position''s figures, whether the first '
  'semester''s fees are cleared (finance.semester_cleared) and the window; read for the applicant dashboard and the monitors.';

-- ── 5 · the student portal's fee gate for fresh admits ───────────────────────────────────────────────────
CREATE TABLE finance.portal_fee_gate (
    id             int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    enabled        boolean NOT NULL DEFAULT true,
    from_session   text NOT NULL,
    clears_on      text NOT NULL DEFAULT 'FIRST_SEMESTER' CHECK (clears_on IN ('FIRST_SEMESTER', 'PAID_IN_FULL')),
    changed_by     uuid NULL,
    changed_office text NULL,
    changed_at     timestamptz NULL,
    reason         text NULL
);
SELECT audit.attach('finance.portal_fee_gate');
COMMENT ON TABLE finance.portal_fee_gate IS
  'V724: the one-row switch that holds a fresh admit (ADMITTED, no matriculation number, UTME or Direct Entry, entered from from_session on) out of the '
  'student portal until the session''s school fees are stated and paid — the first semester''s (FIRST_SEMESTER) or the session''s in full (PAID_IN_FULL). '
  'ON from the start, as the University asked on 11 November 2026; turned by the Bursar, the Director of ICT or an administrator; every change on the audit spine.';
-- on from the start, from the entry session of the newest cohort of admitted-but-not-matriculated freshers on the register (the intake session where
-- the register holds none yet); never a figure written into the code (the Bursar changes it on Fee Setup)
INSERT INTO finance.portal_fee_gate (id, enabled, from_session, clears_on, changed_at, reason)
VALUES (1, true,
        coalesce((SELECT max(s.entry_session) FROM people.student s
                   WHERE s.status = 'ADMITTED' AND s.matric_no IS NULL AND s.duplicate_of IS NULL AND s.candidate_id IS NOT NULL
                     AND s.entry_mode IN ('UTME', 'DIRECT_ENTRY')),
                 policy.intake_session()),
        'FIRST_SEMESTER', now(), 'V724: on from the start, as the University asked on 11 November 2026');

CREATE TABLE finance.portal_fee_gate_exception (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id     uuid NOT NULL REFERENCES people.student(id) ON DELETE CASCADE,
    basis          text NOT NULL CHECK (basis IN ('INSTALMENT_POLICY', 'WAIVER', 'BURSARY_DECISION')),
    reason         text NOT NULL,
    granted_by     uuid NOT NULL,
    granted_office text NOT NULL,
    granted_at     timestamptz NOT NULL DEFAULT now(),
    starts_at      timestamptz NOT NULL DEFAULT now(),
    expires_at     timestamptz NOT NULL,
    revoked_at     timestamptz NULL,
    revoked_by     uuid NULL,
    revoke_reason  text NULL,
    CONSTRAINT ck_portal_fee_exception_span CHECK (expires_at > starts_at)
);
CREATE INDEX ix_portal_fee_gate_exception_student ON finance.portal_fee_gate_exception (student_id) WHERE revoked_at IS NULL;
SELECT audit.attach('finance.portal_fee_gate_exception');
COMMENT ON TABLE finance.portal_fee_gate_exception IS
  'V724: a named fresh admit let into the student portal while the fee gate would hold them — on an approved instalment arrangement, a waiver, or the '
  'Bursary''s decision — for a stated time (at most 200 days), one at a time; revoked or ended, the gate applies again.';

CREATE FUNCTION finance.set_portal_fee_gate(p_enabled boolean, p_from_session text, p_clears_on text, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE g finance.portal_fee_gate;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('bursar', 'ict', 'admin', 'super') THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_OFFICE: only the Bursar, the Director of ICT or an administrator sets the student portal''s fee gate' USING ERRCODE = '23514';
    END IF;
    IF p_clears_on IS NOT NULL AND p_clears_on NOT IN ('FIRST_SEMESTER', 'PAID_IN_FULL') THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_RULE: the gate clears on FIRST_SEMESTER or PAID_IN_FULL' USING ERRCODE = '23514';
    END IF;
    IF p_from_session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = p_from_session) THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_SESSION: % is not a session', p_from_session USING ERRCODE = '23514';
    END IF;
    SELECT * INTO g FROM finance.portal_fee_gate WHERE id = 1 FOR UPDATE;
    IF coalesce(p_enabled, g.enabled) = g.enabled AND coalesce(p_from_session, g.from_session) = g.from_session AND coalesce(p_clears_on, g.clears_on) = g.clears_on THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_UNCHANGED: the student portal''s fee gate is already so' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.portal_fee_gate
       SET enabled = coalesce(p_enabled, enabled), from_session = coalesce(p_from_session, from_session), clears_on = coalesce(p_clears_on, clears_on),
           changed_by = p_actor, changed_office = p_office, changed_at = now(),
           reason = coalesce(nullif(btrim(coalesce(p_reason, '')), ''), CASE WHEN coalesce(p_enabled, enabled) THEN 'Set' ELSE 'Turned OFF' END)
     WHERE id = 1;
END $$;

CREATE FUNCTION finance.grant_portal_fee_exception(p_student uuid, p_basis text, p_reason text, p_starts timestamptz, p_expires timestamptz, p_actor uuid, p_office text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('bursar', 'studentaccounts', 'admin', 'super') THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_OFFICE: only the Bursary or an administrator lets a student through the fee gate' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_student) THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_STUDENT: no such student' USING ERRCODE = '23503';
    END IF;
    IF p_basis IS NULL OR p_basis NOT IN ('INSTALMENT_POLICY', 'WAIVER', 'BURSARY_DECISION') THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_BASIS: an exception rests on an INSTALMENT_POLICY, a WAIVER or a BURSARY_DECISION' USING ERRCODE = '23514';
    END IF;
    IF nullif(btrim(coalesce(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_REASON: an exception is granted for a reason' USING ERRCODE = '23514';
    END IF;
    IF p_expires IS NULL OR p_expires <= coalesce(p_starts, now()) OR p_expires > coalesce(p_starts, now()) + interval '200 days' THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_SPAN: an exception runs for a stated time of at most 200 days' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM finance.portal_fee_gate_exception e WHERE e.student_id = p_student AND e.revoked_at IS NULL AND e.expires_at > now()) THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_EXCEPTION_ACTIVE: the student already has an exception that stands; revoke it first' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.portal_fee_gate_exception (student_id, basis, reason, granted_by, granted_office, starts_at, expires_at)
    VALUES (p_student, p_basis, btrim(p_reason), p_actor, p_office, coalesce(p_starts, now()), p_expires) RETURNING id INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION finance.revoke_portal_fee_exception(p_id uuid, p_reason text, p_actor uuid, p_office text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_office IS NULL OR p_office NOT IN ('bursar', 'studentaccounts', 'admin', 'super') THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_OFFICE: only the Bursary or an administrator revokes an exception' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.portal_fee_gate_exception
       SET revoked_at = now(), revoked_by = p_actor, revoke_reason = nullif(btrim(coalesce(p_reason, '')), '')
     WHERE id = p_id AND revoked_at IS NULL AND expires_at > now();
    IF NOT FOUND THEN
        RAISE EXCEPTION 'PORTAL_FEE_GATE_EXCEPTION_ENDED: that exception has already ended or been revoked' USING ERRCODE = '23514';
    END IF;
END $$;

-- whether the gate applies to a record at all: a fresh admit of a gated entry session — on the register from an admission, not yet
-- matriculated, UTME or Direct Entry, with an applicant account to pay from. Every matriculated or returning student
-- (ck_student_active_has_matric), every earlier cohort, every record without a candidate or without an applicant account (brought
-- onto the register from a list, with no applicant dashboard to pay on), postgraduate and CCE are outside it.
CREATE FUNCTION finance.portal_fee_gate_applies(p_student uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM people.student s CROSS JOIN finance.portal_fee_gate g
                    WHERE s.id = p_student AND g.enabled
                      AND s.status = 'ADMITTED' AND s.matric_no IS NULL AND s.duplicate_of IS NULL AND s.candidate_id IS NOT NULL
                      AND s.entry_mode IN ('UTME', 'DIRECT_ENTRY') AND s.entry_session >= g.from_session
                      AND EXISTS (SELECT 1 FROM admissions.applicant_account acc WHERE acc.candidate_id = s.candidate_id))
$$;

-- V724: the acceptance fee balance a fresh admit still owes (a fee revised after part of it was paid), over the candidate's applications
CREATE FUNCTION admissions.acceptance_balance_of_student(p_student uuid)
RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT coalesce(sum(e.balance) FILTER (WHERE e.balance_due), 0)
      FROM people.student s
      JOIN admissions.application a ON a.candidate_id = s.candidate_id
      CROSS JOIN LATERAL admissions.acceptance_entitlement(a.id) e
     WHERE s.id = p_student AND a.decision = 'OFFERED' AND a.declined_at IS NULL
$$;

CREATE FUNCTION finance.portal_access_state(p_student uuid)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE s people.student; g finance.portal_fee_gate; pos record; cleared boolean;
BEGIN
    IF NOT finance.portal_fee_gate_applies(p_student) THEN RETURN 'OPEN'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student;
    SELECT * INTO g FROM finance.portal_fee_gate WHERE id = 1;
    IF EXISTS (SELECT 1 FROM finance.portal_fee_gate_exception e
                WHERE e.student_id = p_student AND e.revoked_at IS NULL AND now() >= e.starts_at AND now() < e.expires_at) THEN
        RETURN 'EXCEPTION';
    END IF;
    -- the acceptance fee first: a fee revised after part of it was paid holds the student until the balance is paid (the brief's
    -- "acceptance fee partially paid: pay the outstanding balance; no access")
    IF admissions.acceptance_balance_of_student(s.id) > 0 THEN RETURN 'HELD_ACCEPTANCE_BALANCE'; END IF;
    SELECT * INTO pos FROM finance.position(s.id, s.entry_session);
    -- nothing stated reaches the student: the Bursary has not published the fees, and nothing is charged at a guess (read before
    -- the position, which reads nothing due as paid in full)
    IF pos.due <= 0 OR NOT finance.fee_stated(s.id, s.entry_session) THEN RETURN 'HELD_FEES_NOT_AVAILABLE'; END IF;
    -- a first semester with nothing charged in it does not clear the gate (a session staged with only a later semester's line)
    cleared := CASE g.clears_on WHEN 'PAID_IN_FULL' THEN pos.paid_in_full
                    ELSE finance.due_for_semester(s.id, s.entry_session, 1) > 0 AND finance.semester_cleared(s.id, s.entry_session, 1) END;
    IF cleared THEN
        RETURN 'CLEARED';
    END IF;
    RETURN 'HELD_FEES_UNPAID';
END $$;
COMMENT ON FUNCTION finance.portal_access_state(uuid) IS
  'V724: OPEN (the gate is off, or the record is not a fresh admit of a gated session), EXCEPTION (a live exception from the Bursary), '
  'HELD_ACCEPTANCE_BALANCE (the acceptance fee, revised after part of it was paid, still owed), CLEARED (the '
  'session''s school fees paid as the gate requires: the first semester''s, or in full), HELD_FEES_NOT_AVAILABLE (no fee stated for the student: '
  'the applicant dashboard says so), HELD_FEES_UNPAID (stated, payable on the applicant dashboard). Read at the student door and on every request '
  'to the student portal while held — never cached.';

-- ── 3 · the reference for the balance, the letter after the balance, the status and the tracker ──────────────────────
-- admissions.new_fee_reference (V701's text): the ACCEPTANCE reference is for the balance, one open reference, the stated fee kept
CREATE OR REPLACE FUNCTION admissions.new_fee_reference(p_app uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE a admissions.application; fee record; v_ref text; v_amount numeric; c record; v_cce boolean; v_try int; v_route text; v_prelim boolean;
        ent record; v_stated numeric;   -- V724
BEGIN
    -- V724: draws for one application one at a time, so two at once never mint two references for the same balance
    SELECT * INTO a FROM admissions.application WHERE id = p_app FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    v_route := admissions.applicant_route(p_app);
    v_prelim := v_route IS NOT NULL AND NOT v_cce;
    IF p_kind = 'APPLICATION' AND a.fee_confirmed_at IS NOT NULL THEN
        RAISE EXCEPTION 'the application fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed for the application.';
    END IF;
    -- V446: a Preliminary Science applicant pays the application fee; the University has stated no checking or acceptance fee for it
    IF v_prelim AND p_kind <> 'APPLICATION' THEN
        SELECT r.checking_fee, r.acceptance_fee INTO fee FROM admissions.route_fee_rule(a.session, v_route) r;
        IF (p_kind = 'CHECKING' AND fee.checking_fee IS NULL) OR (p_kind = 'ACCEPTANCE' AND fee.acceptance_fee IS NULL) THEN
            RAISE EXCEPTION 'PRELIM_FEE_NOT_CONFIGURED: the University has not stated a % fee of % for %', lower(p_kind), coalesce((SELECT pp.name FROM admissions.prelim_programme pp WHERE pp.route = v_route), 'the programme'), a.session USING ERRCODE = '23514';
        END IF;
    END IF;
    IF p_kind = 'CHECKING' AND NOT v_prelim THEN
        -- V295: the checking fee is open to every applicant with a valid Post-UTME application while the Director of ICT has
        -- admission status checking open — admitted, not admitted or not yet decided alike; the decision is what the check reveals
        SELECT * INTO c FROM admissions.status_checking(p_app);
        IF c.paid THEN
            RAISE EXCEPTION 'ADMISSION_CHECKING_PAID: the admission checking fee is already paid; nothing more is owed' USING ERRCODE = '23514';
        END IF;
        IF NOT c.application_valid THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking follows a CCE application paid for and submitted'
                ELSE 'ADMISSION_CHECKING_NOT_ELIGIBLE: admission status checking is for applicants whose Post-UTME application is paid for and submitted' END USING ERRCODE = '23514';
        END IF;
        IF NOT c.window_open THEN
            -- V404: for CCE, checking opens when the Centre publishes the outcome of the application
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN 'ADMISSION_CHECKING_CLOSED: the Centre for Continuing Education has not yet published the outcome of your application'
                ELSE 'ADMISSION_CHECKING_CLOSED: admission status checking is closed' END USING ERRCODE = '23514';
        END IF;
        -- a reference still open is the one to pay: the same service is never charged twice
        IF c.open_reference IS NOT NULL THEN RETURN c.open_reference; END IF;
    END IF;
    IF p_kind = 'ACCEPTANCE' AND NOT v_prelim THEN
        -- V295: the acceptance fee follows an offer the applicant has read through Admission Status Checking; before that the
        -- answer is the same whatever the decision, so no path here says whether there is an offer
        IF NOT (SELECT k.past FROM admissions.status_checking(p_app) k) THEN
            RAISE EXCEPTION 'ADMISSION_STATUS_NOT_CHECKED: check your admission status before paying for, accepting or declining the offer' USING ERRCODE = '23514';
        END IF;
        IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN
            RAISE EXCEPTION 'there is no offer to accept' USING ERRCODE = '23514', HINT = 'The acceptance fee follows an offer of admission.';
        END IF;
        -- V724: what is owed is the fee as stated now less what is confirmed — a fee revised after a part payment leaves a balance,
        -- paid on a reference of its own (UTME and Direct Entry; a CCE admission as before)
        SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
        IF NOT v_cce AND ent.balance <= 0 THEN
            RAISE EXCEPTION 'ACCEPTANCE_SETTLED: the acceptance fee is paid in full' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
        IF v_cce AND a.acceptance_confirmed_at IS NOT NULL THEN
            RAISE EXCEPTION 'the acceptance fee is already confirmed' USING ERRCODE = '23514', HINT = 'Nothing more is owed to accept.';
        END IF;
    END IF;
    IF v_cce OR v_prelim THEN
        -- V379: the route's fees, as the Bursary stated them for the session (or last stated); never the Post-UTME figures.
        -- V404: the CCE admission checking fee among them; V446: a preliminary programme's fees, read the same way
        SELECT r.application_fee, r.portal_charge, r.acceptance_fee, r.checking_fee INTO fee FROM admissions.route_fee_rule(a.session, v_route) r;
        v_amount := CASE p_kind WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge WHEN 'CHECKING' THEN fee.checking_fee ELSE fee.acceptance_fee END;
        IF v_amount IS NULL THEN
            RAISE EXCEPTION '%', CASE WHEN v_cce THEN format('CCE_FEE_NOT_STATED: the Bursary has not stated the CCE %s fee for %s', lower(p_kind), a.session)
                                      ELSE format('PRELIM_FEE_NOT_CONFIGURED: the Bursary has not stated the %s fee of %s for %s', lower(p_kind), coalesce((SELECT pp.name FROM admissions.prelim_programme pp WHERE pp.route = v_route), 'the programme'), a.session) END
                USING ERRCODE = '23514';
        END IF;
    ELSE
    SELECT * INTO fee FROM admissions.applicant_fee_rule(a.session);
    -- V401: where the Bursary refuses to carry a session's applicant fees forward, nothing is paid until they are stated
    IF NOT fee.stated AND admissions.applicant_fee_policy() = 'REFUSE' THEN
        RAISE EXCEPTION 'APPLICANT_FEE_NOT_STATED: the % fee for % is not stated yet', lower(p_kind), a.session USING ERRCODE = '23514',
            HINT = 'The Bursary states the applicant fees for the session on Fee Setup.';
    END IF;
    -- each fee on its own reference (V271): the checking fee is never folded into the acceptance fee
    v_amount := CASE p_kind
                    WHEN 'APPLICATION' THEN fee.application_fee + fee.portal_charge
                    WHEN 'CHECKING' THEN coalesce(fee.checking_fee, 0)
                    ELSE fee.acceptance_fee END;
    END IF;
    -- V724: the acceptance fee is paid up to the figure stated now: the balance, which is the whole fee before anything is confirmed
    IF p_kind = 'ACCEPTANCE' AND NOT v_cce AND NOT v_prelim THEN
        v_stated := ent.fee_due;
        v_amount := ent.balance;
    END IF;
    IF v_amount <= 0 THEN RAISE EXCEPTION 'no % fee is stated for %', lower(p_kind), a.session USING ERRCODE = '23514', HINT = 'The Bursary states the applicant fees on Fee Setup.'; END IF;
    -- a reference still open for the application fee is the one to pay (V446: never two at once for the same fee)
    IF v_prelim AND p_kind = 'APPLICATION' THEN
        SELECT r.reference INTO v_ref FROM admissions.fee_reference r
         WHERE r.application_id = p_app AND r.kind = 'APPLICATION' AND r.confirmed_at IS NULL AND r.expires_at > now() AND r.amount = v_amount
         ORDER BY r.generated_at DESC LIMIT 1;
        IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
    END IF;
    -- V724: an acceptance reference still open for what is owed is the one to pay, never a second; one drawn for another figure
    -- (the fee since revised) is closed, so that it cannot be paid at the old amount
    IF p_kind = 'ACCEPTANCE' AND NOT v_cce AND NOT v_prelim THEN
        SELECT r.reference INTO v_ref FROM admissions.fee_reference r
         WHERE r.application_id = p_app AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NULL AND r.expires_at > now() AND r.amount = v_amount
         ORDER BY r.generated_at DESC LIMIT 1;
        IF v_ref IS NOT NULL THEN RETURN v_ref; END IF;
        UPDATE admissions.fee_reference r SET expires_at = least(r.expires_at, now())
         WHERE r.application_id = p_app AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NULL AND r.expires_at > now();
    END IF;
    -- V390: the four random digits may repeat a reference another application drew (the last six digits of an application
    -- number are the session's running number, shared across sessions); a taken reference is drawn again, never answered as a clash
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-' || CASE p_kind WHEN 'APPLICATION' THEN 'APP' WHEN 'CHECKING' THEN 'CHK' ELSE 'ACC' END || '-' || right(a.application_no, 6) || '-'
                 || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at, stated_fee)
        VALUES (gen_random_uuid(), p_app, p_kind, v_ref, v_amount, now() + interval '24 hours', v_stated)
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free % reference was found for % in fifty draws', lower(p_kind), a.application_no USING ERRCODE = '23514',
        HINT = 'Try again; if it persists, the Directorate of ICT widens the reference.';
END $function$;

-- admissions.issue_admission_letter (V701's text): the balance read before the letter already issued is returned
CREATE OR REPLACE FUNCTION admissions.issue_admission_letter(p_app uuid)
 RETURNS credentials.issued
 LANGUAGE plpgsql
AS $function$
DECLARE pr admissions.prelim_review; pp admissions.prelim_programme; tg record; a admissions.application; c admissions.candidate; cur credentials.issued; v_stmt jsonb; v_hash text; v_number text; v_version int := 1; v_id uuid := gen_random_uuid();
        v_actor uuid; v_office text; ent record; v_prog record; v_changed record; v_student people.student;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NULL OR a.decision <> 'OFFERED' THEN RAISE EXCEPTION 'there is no offer to issue a letter for' USING ERRCODE = '23514'; END IF;
    SELECT * INTO pr FROM admissions.prelim_review WHERE application_id = p_app;
    -- V446: a Preliminary Science offer has no acceptance fee the University has stated; its letter follows the published offer
    IF a.accepted_at IS NULL AND pr.application_id IS NULL THEN RAISE EXCEPTION 'the admission letter is issued once the offer is accepted and the acceptance fee confirmed' USING ERRCODE = '23514', HINT = 'Sign the undertaking and pay the acceptance fee, then print the letter.'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    -- V724: the letter waits for the acceptance fee in full — a fee revised after a part payment leaves a balance; the undertaking,
    -- the screening and the register do not wait for it (UTME and Direct Entry; a CCE or preliminary admission as before). Read
    -- before the letter already issued is returned, so that a letter printed before the revision is not printed again on a balance.
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    IF pr.application_id IS NULL AND c.entry_mode <> 'CCE' AND coalesce(ent.balance_due, false) THEN
        RAISE EXCEPTION 'ACCEPTANCE_BALANCE_DUE: the admission letter is issued once the acceptance fee of ₦% is paid in full; ₦% remains',
            to_char(ent.fee_due, 'FM999,999,990'), to_char(ent.balance, 'FM999,999,990') USING ERRCODE = '23514';
    END IF;
    SELECT p.code, p.name, p.category, f.name AS faculty, d.name AS department INTO v_prog
      FROM ref.programme p LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = admissions.programme_code_of(c.programme);
    SELECT * INTO cur FROM credentials.issued i WHERE i.application_id = p_app AND i.kind = 'ADMISSION_LETTER' AND NOT EXISTS (SELECT 1 FROM credentials.issued x WHERE x.supersedes = i.id) ORDER BY i.version DESC LIMIT 1;
    -- the letter stands while it names the programme the admission is for
    IF cur.id IS NOT NULL AND cur.statement->>'programme' = c.programme THEN RETURN cur; END IF;
    SELECT * INTO v_student FROM people.student WHERE candidate_id = c.id LIMIT 1;
    SELECT q.from_programme, q.to_programme, q.decided_at INTO v_changed FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1;
    v_actor := coalesce(nullif(current_setting('moaum.actor_id', true), '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid);
    v_office := nullif(current_setting('moaum.actor_office', true), '');
    IF v_office IS NULL OR NOT EXISTS (SELECT 1 FROM ref.office WHERE code = v_office) THEN v_office := 'registrar'; END IF;
    IF cur.id IS NOT NULL THEN v_version := cur.version + 1; v_number := cur.number; ELSE v_number := credentials.next_document_number('ADMISSION_LETTER'); END IF;
    v_stmt := jsonb_build_object(
        'kind', 'ADMISSION_LETTER', 'number', v_number, 'version', v_version,
        'holder', c.surname || ', ' || c.other_names, 'surname', c.surname, 'otherNames', c.other_names, 'jambRegNo', c.jamb_reg_no, 'applicationNo', a.application_no,
        'session', a.session, 'programme', c.programme, 'programmeCode', v_prog.code, 'degreeType', v_prog.category, 'faculty', v_prog.faculty, 'department', v_prog.department,
        'admissionType', c.entry_mode || ' · ' || c.entry_level || ' Level', 'entryMode', c.entry_mode, 'entryLevel', c.entry_level, 'basis', a.decision_basis,
        'decisionReleasedOn', a.decision_released_at::date, 'acceptedOn', a.accepted_at::date, 'acceptanceReference', ent.reference, 'acceptanceConfirmedOn', ent.confirmed_at::date,
        'admissionNo', v_student.admission_no,
        'changedFrom', v_changed.from_programme, 'changedTo', v_changed.to_programme, 'changedOn', v_changed.decided_at::date,
        'issuedOn', current_date, 'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi');
    -- V379: a CCE admission names the route, the study mode, the Centre and the programme's duration on the route
    IF c.entry_mode = 'CCE' THEN
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', 'CCE', 'studyMode', 'PART-TIME', 'centre', 'Centre for Continuing Education',
                    'admissionType', 'CCE · Part-time · ' || c.entry_level || ' Level',
                    'durationYears', (SELECT t.duration_years FROM ref.programme_route_terms(v_prog.code, 'CCE') t),
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for the Centre for Continuing Education');
    END IF;
    -- V446/V701: a preliminary or proficiency letter names the programme, its type and campus, and the target programme (an intended
    -- progression only) with the option chosen, or the certificate course
    IF pr.application_id IS NOT NULL THEN
        SELECT * INTO pp FROM admissions.prelim_programme WHERE route = pr.route;
        SELECT p.code, p.name, f.name AS faculty, d.name AS department, t.kind, t.requested_name, t.group_name, sp.name AS specialisation,
               coalesce(t.duration_months, pp.duration_months) AS months
          INTO tg
          FROM admissions.prelim_target t
          LEFT JOIN ref.programme p ON p.code = t.programme_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
          LEFT JOIN admissions.prelim_specialisation sp ON sp.id = pr.specialisation_id
         WHERE t.id = pr.target_id;
        v_stmt := v_stmt || jsonb_build_object('admissionRoute', pr.route, 'programme', pp.name, 'programmeCode', NULL,
                    'degreeType', CASE pp.programme_type WHEN 'PROFICIENCY_CERTIFICATE' THEN 'PROFICIENCY CERTIFICATE' ELSE 'PRELIMINARY / REMEDIAL' END,
                    'faculty', NULL, 'department', NULL, 'studyMode', 'FULL-TIME', 'admissionType', pp.name || ' · Full-time', 'entryLevel', NULL,
                    'campus', (SELECT cm.name FROM ref.campus cm WHERE cm.code = pp.campus_code),
                    'durationMonths', tg.months, 'area', tg.group_name,
                    'targetProgramme', CASE WHEN tg.kind = 'PROGRAMME' THEN tg.name END, 'targetProgrammeCode', CASE WHEN tg.kind = 'PROGRAMME' THEN tg.code END,
                    'targetFaculty', tg.faculty, 'targetDepartment', tg.department, 'specialisation', tg.specialisation,
                    'certificateCourse', CASE WHEN tg.kind = 'COURSE' THEN tg.requested_name END,
                    'targetNote', pp.target_note,
                    'remediationRequired', pr.remediation_status = 'REQUIRED',
                    'remediationSubjects', to_jsonb(pr.remediation_subjects), 'remediationCreditsShort', pr.remediation_credits_short,
                    'completionNote', pp.completion_note,
                    'issuingAuthority', 'The Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi, for ' || pp.name);
    END IF;
    v_hash := encode(sha256(convert_to(v_stmt::text, 'UTF8')), 'hex');
    INSERT INTO credentials.issued (id, kind, student_id, application_id, verification_code, statement, signature, signed_with, issuing_name, issued_on, issued_by, issued_office, supersedes, number, version, template_version, content_hash, note)
    VALUES (v_id, 'ADMISSION_LETTER', v_student.id, p_app, credentials.new_code(), v_stmt, decode(v_hash, 'hex'), NULL, 'Rev. Fr. Moses Orshio Adasu University, Makurdi', current_date, v_actor, v_office, cur.id,
            v_number, v_version, NULL, v_hash, CASE WHEN cur.id IS NULL THEN 'Letter of provisional admission' ELSE 'Reissued: the programme changed to ' || c.programme END);
    PERFORM credentials.log(NULL, v_id, v_student.id, 'ISSUED', NULL, 'ACTIVE', 'ADMISSION_LETTER ' || v_number || ' v' || v_version || ' · ' || c.programme);
    SELECT * INTO cur FROM credentials.issued WHERE id = v_id;
    RETURN cur;
END $function$;

-- admissions.admission_status (V446's text): the school fees as they stand, on the applicant's own dashboard while the gate stands
CREATE OR REPLACE FUNCTION admissions.admission_status(p_app uuid)
 RETURNS TABLE(status text, label text, next_action text, next_href text, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; req boolean; ent record; reg boolean; paid boolean; c record; v_cce boolean;
        sf record; gate record; v_state text;   -- V724
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN QUERY SELECT 'NOT_FOUND', 'Not found', NULL, NULL, NULL; RETURN; END IF;
    v_cce := EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE');
    -- V446: a Preliminary Science applicant is told in the programme's own terms (admissions.prelim_status)
    IF EXISTS (SELECT 1 FROM admissions.prelim_review x WHERE x.application_id = p_app) THEN
        RETURN QUERY SELECT * FROM admissions.prelim_status(p_app); RETURN;
    END IF;
    -- V295: the status is read through Admission Status Checking — a valid Post-UTME application (paid for and submitted), checking
    -- open (the Director of ICT's window) and the checking fee paid; never through the decision, which is what the check reveals.
    -- An applicant who has read an offer and whose admission is under way continues whatever the window.
    SELECT * INTO c FROM admissions.status_checking(p_app);
    IF NOT c.decision_visible THEN
        IF NOT c.application_valid THEN
            RETURN QUERY SELECT 'APPLICATION_INCOMPLETE', 'Application not complete',
                CASE WHEN a.fee_confirmed_at IS NULL THEN 'Pay the application fee' ELSE 'Complete and submit your application' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE') THEN '/applicant/cce'
                     WHEN a.fee_confirmed_at IS NULL THEN '/applicant/fee' ELSE '/applicant/apply' END,
                CASE WHEN EXISTS (SELECT 1 FROM admissions.candidate x WHERE x.id = a.candidate_id AND x.entry_mode = 'CCE')
                     THEN 'The Centre for Continuing Education reviews your application once it is complete and submitted.'
                     ELSE 'Admission status checking is open to every applicant whose Post-UTME application is paid for and submitted.' END; RETURN;
        END IF;
        IF NOT c.window_open THEN
            RETURN QUERY SELECT 'CHECKING_CLOSED', 'Admission status checking closed', NULL::text, '/applicant/admission',
                -- V404: a CCE applicant's checking opens when the Centre publishes the outcome of the application
                CASE WHEN v_cce THEN 'The Centre for Continuing Education has not yet published the outcome of your application. You are told by email and SMS when it does; then pay the admission checking fee and read it here.'
                     WHEN c.window_state = 'SCHEDULED' AND c.opens_at IS NOT NULL
                     THEN 'Admission status checking opens on ' || to_char(c.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI') || '.'
                     ELSE 'Admission status checking is currently unavailable. Please check back when the University opens the admission checking portal.' END; RETURN;
        END IF;
        RETURN QUERY SELECT 'CHECKING_FEE_PENDING', 'Admission checking fee not paid', 'Pay the admission checking fee', '/applicant/admission',
            CASE WHEN v_cce AND c.fee IS NULL
                 THEN 'The Centre for Continuing Education has published the outcome of your application. The Bursary has not yet stated the CCE admission checking fee for ' || a.session || '; pay it and read the outcome here once it does.'
                 WHEN v_cce
                 THEN 'The Centre for Continuing Education has published the outcome of your application. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then read it here as often as you need.'
                 ELSE 'Admission status checking is open. Pay the admission checking fee of ₦' || to_char(c.fee, 'FM999,999,990') || ' once, then check your admission status as often as you need while checking is open.' END; RETURN;
    END IF;
    IF a.decision_released_at IS NULL OR a.decision IS NULL THEN
        RETURN QUERY SELECT 'PENDING', 'Admission pending', NULL::text, '/applicant/admission',
            'Your admission has not yet been finalised. Please check again when further admission processing has been completed; the checking fee is not charged again.'; RETURN;
    END IF;
    IF a.decision <> 'OFFERED' THEN
        RETURN QUERY SELECT 'NOT_ADMITTED', CASE WHEN a.decision = 'WAITING' THEN 'Waiting list' ELSE 'Not admitted' END, NULL::text, '/applicant/admission',
            coalesce(a.decision_note, CASE WHEN a.decision = 'WAITING'
                THEN 'You are above the cut-off, but the approved quota is full. You are offered a place only if an offered candidate fails to accept in time.'
                ELSE 'Your admission status for the ' || a.session || ' admission exercise is: not admitted. You may continue to monitor the University''s official admission updates.' END); RETURN;
    END IF;
    IF a.declined_at IS NOT NULL THEN RETURN QUERY SELECT 'DECLINED', 'Offer declined', NULL, '/applicant/status', 'A declined offer is not reinstated.'; RETURN; END IF;
    -- V358: an offer not accepted by its deadline, lapsed by the Admissions Office
    IF a.lapsed_at IS NOT NULL THEN
        RETURN QUERY SELECT 'LAPSED', 'Offer lapsed', NULL::text, '/applicant/admission',
            'Your offer was not accepted by ' || coalesce(to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY'), 'its deadline')
            || ' and has lapsed. A lapsed offer is not reinstated; write to the Admissions Office quoting your application number if you believe this is in error.'; RETURN;
    END IF;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    -- the applicant reads the admission status — the offer, its programme, faculty and session — before anything is accepted (V271)
    IF a.accepted_at IS NULL AND a.status_checked_at IS NULL AND NOT ent.paid AND a.undertaking_at IS NULL THEN
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — check your admission status', 'Check your admission status', '/applicant/admission', 'Congratulations: read the offer and its details, then accept it and pay the acceptance fee.'; RETURN;
    END IF;
    IF a.accepted_at IS NULL THEN
        IF ent.paid OR a.undertaking_at IS NOT NULL THEN RETURN QUERY SELECT 'ACCEPTANCE_PENDING', 'Acceptance in progress', CASE WHEN ent.paid THEN 'Sign the undertaking' ELSE 'Pay the acceptance fee' END, '/applicant/accept', 'The undertaking and the acceptance fee together accept the offer.'; RETURN; END IF;
        RETURN QUERY SELECT 'ADMITTED', 'Admitted — offer to accept', 'Pay the acceptance fee', '/applicant/accept', 'Accept the offer and pay the acceptance fee; the acceptance letter follows.' || coalesce(' Accept it by ' || to_char(admissions.offer_deadline_of(p_app), 'FMDD Month YYYY') || '; an offer neither accepted nor paid for by then lapses.', ''); RETURN;
    END IF;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app ORDER BY x.requested_at DESC LIMIT 1;
    IF req AND NOT admissions.screening_ok(p_app) THEN
        -- the University screens on the record it holds (V280): the applicant waits (entering only the schools attended), or provides the one correction asked for
        -- V284: a change the Academic Office recommended during the screening awaits approval
        IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND f.application_id IS NOT NULL AND f.state IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Programme change under review', 'Wait for the Academic Office', '/applicant/admission',
                'During the screening the Academic Office recommended ' || q.to_programme || ' in place of ' || q.from_programme || '; the change takes effect when it is approved, and you will be told. Your acceptance fee is not paid again.';
            RETURN;
        END IF;
        IF f.application_id IS NULL OR f.state = 'PENDING' THEN RETURN QUERY SELECT 'SCREENING_PENDING', 'Accepted - awaiting screening', 'Wait for the University''s screening', '/applicant/clearance', 'Your information has been received. The University screens your admission on the information JAMB and your application already gave; the schools you attended are the only thing you enter. You will be told the outcome here and by email.'; RETURN; END IF;
        IF f.state = 'IN_REVIEW' THEN RETURN QUERY SELECT 'SCREENING_IN_REVIEW', 'Screening in progress', 'Wait for the screening officers', '/applicant/clearance', 'A screening officer opened your record' || coalesce(' on ' || to_char(f.review_started_at, 'DD Mon YYYY'), '') || '.'; RETURN; END IF;
        IF f.state = 'CORRECTION_REQUIRED' THEN RETURN QUERY SELECT 'SCREENING_CORRECTION', 'Screening: one correction required', 'Provide the correction', '/applicant/clearance', f.returned_note; RETURN; END IF;
        IF f.state = 'UNSUCCESSFUL' THEN
            IF q.id IS NOT NULL AND q.state = 'REQUESTED' AND q.requested_at >= f.decided_at THEN RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_PENDING', 'Change of programme requested', 'Wait for the Admissions Office', '/applicant/clearance', 'Requested ' || q.to_programme || ' on ' || to_char(q.requested_at, 'DD Mon YYYY') || '.'; RETURN; END IF;
            RETURN QUERY SELECT 'CHANGE_OF_PROGRAMME_REQUIRED', 'Screening unsuccessful', 'Apply for a change of programme', '/applicant/clearance', f.decision_reason; RETURN;
        END IF;
    END IF;
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    -- V724: the acceptance fee revised after part of it was paid: the balance before the steps that follow (the place is held; the
    -- letter, the school fees and the student portal wait for it) — UTME and Direct Entry (admissions.acceptance_entitlement)
    IF coalesce(ent.balance_due, false) AND s.matric_no IS NULL THEN
        RETURN QUERY SELECT 'ACCEPTANCE_BALANCE_PENDING', 'Acceptance fee balance to pay', 'Pay the acceptance fee balance', '/applicant/accept',
            'The acceptance fee for ' || a.session || ' was revised to ₦' || to_char(ent.fee_due, 'FM999,999,990') || ' after you paid ₦'
            || to_char(ent.paid_total, 'FM999,999,990') || '. The balance of ₦' || to_char(ent.balance, 'FM999,999,990')
            || ' is to be paid; you are not charged the full fee again. Your place is held; the acceptance letter, your school fees and the Student Portal follow the balance.';
        RETURN;
    END IF;
    IF s.id IS NULL THEN RETURN QUERY SELECT 'REGISTER_PENDING', CASE WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Wait for the Registry to bring you onto the register', '/applicant/matric', 'School fees open once you are on the register under your admission number.'; RETURN; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN QUERY SELECT 'MATRICULATED', 'Matriculated', NULL, '/applicant/matric', 'Matriculation number ' || s.matric_no || ', issued ' || to_char(s.matriculated_at, 'DD Mon YYYY') || '. It is now your sign-in.'; RETURN; END IF;
    paid := coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    IF NOT paid THEN
        -- V724: where the student stands at the student portal's fee gate decides what is said (finance.portal_access_state, read now).
        -- A record the gate does not hold (the gate off, CCE, an earlier cohort, no applicant account) is told as before V724.
        v_state := finance.portal_access_state(s.id);
        IF v_state = 'OPEN' THEN
            RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END, 'Pay school fees', '/student/fees', 'Sign in to the student portal with your admission number ' || coalesce(s.admission_no, '') || ' to pay.'; RETURN;
        END IF;
        SELECT * INTO sf FROM finance.school_fee_state(s.id, s.entry_session);
        SELECT * INTO gate FROM finance.portal_fee_gate WHERE id = 1;
        IF v_state = 'EXCEPTION' THEN
            RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', 'Student portal opened by the Bursary', 'Pay school fees', '/student/fees',
                'The Bursary has let you into the Student Portal before your ' || s.entry_session || ' school fees are paid'
                || coalesce(' (until ' || (SELECT to_char(e.expires_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY') FROM finance.portal_fee_gate_exception e
                                          WHERE e.student_id = s.id AND e.revoked_at IS NULL AND now() >= e.starts_at AND now() < e.expires_at ORDER BY e.expires_at DESC LIMIT 1) || ')', '')
                || '. ₦' || to_char(coalesce(sf.paid, 0), 'FM999,999,990') || ' of ₦' || to_char(coalesce(sf.due, 0), 'FM999,999,990') || ' is paid; pay the rest here or on the student portal.';
            RETURN;
        END IF;
        IF v_state = 'CLEARED' THEN
            RETURN QUERY SELECT 'SCHOOL_FEES_PART_PAID', CASE WHEN coalesce(gate.clears_on, 'FIRST_SEMESTER') = 'FIRST_SEMESTER' THEN 'School fees: first semester paid' ELSE 'School fees: paid as required' END,
                'Pay the balance of the school fees', '/applicant/admission#fees',
                'The Student Portal is open to you. ₦' || to_char(sf.paid, 'FM999,999,990') || ' of ₦' || to_char(sf.due, 'FM999,999,990') || ' is paid; the balance of ₦'
                || to_char(sf.balance, 'FM999,999,990') || ' is paid here or on the student portal.';
            RETURN;
        END IF;
        -- held: the school fees are paid here, on the applicant dashboard; nothing is charged at a guess
        IF sf.state = 'NOT_CONFIGURED' THEN
            RETURN QUERY SELECT 'SCHOOL_FEES_NOT_AVAILABLE', s.entry_session || ' school fees not yet available', NULL::text, '/applicant/admission',
                'Your acceptance fee payment has been completed successfully. However, the University has not yet published the approved school fees for the '
                || s.entry_session || ' academic session. Please check your Applicant Dashboard for updates. You will be able to complete your school fee payment here before gaining access to the Student Portal.';
            RETURN;
        END IF;
        IF sf.state = 'NOT_OPEN' THEN
            RETURN QUERY SELECT 'SCHOOL_FEES_NOT_OPEN', CASE WHEN sf.window_state = 'SCHEDULED' THEN 'School fees payment not yet open' ELSE 'School fees payment closed' END, NULL::text, '/applicant/admission',
                'The school fees for ' || s.entry_session || ' are stated; payment '
                || CASE WHEN sf.window_state = 'SCHEDULED' AND sf.opens_at IS NOT NULL THEN 'opens on ' || to_char(sf.opens_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY "at" HH24:MI')
                        WHEN sf.window_state = 'SCHEDULED' THEN 'is not yet open'
                        ELSE 'is closed for now; the Directorate of ICT reopens it' END
                || '. You will pay here, on your Applicant Dashboard; the Student Portal opens when the payment is verified.';
            RETURN;
        END IF;
        RETURN QUERY SELECT 'SCHOOL_FEES_PENDING', CASE WHEN q.id IS NOT NULL AND q.state = 'APPROVED' THEN 'Change of programme approved' WHEN req THEN 'Screening successful' ELSE 'Accepted' END,
            'Pay school fees', '/applicant/admission#fees',
            'Pay your ' || s.entry_session || ' school fees here, on your Applicant Dashboard'
            || CASE WHEN sf.state = 'PAYMENT_PENDING' THEN ' — a payment reference is awaiting the bank''s confirmation' WHEN sf.paid > 0 THEN ' (₦' || to_char(sf.paid, 'FM999,999,990') || ' paid, ₦' || to_char(sf.balance, 'FM999,999,990') || ' outstanding)' ELSE '' END
            || '. The Student Portal opens once ' || CASE WHEN coalesce(gate.clears_on, 'FIRST_SEMESTER') = 'FIRST_SEMESTER' THEN 'the first semester''s fees are' ELSE 'the session''s fees are' END || ' paid and verified.';
        RETURN;
    END IF;
    IF NOT reg THEN RETURN QUERY SELECT 'COURSE_REGISTRATION_PENDING', 'School fees paid', 'Register your courses', '/student/registration', 'Registration is on the student portal.'; RETURN; END IF;
    RETURN QUERY SELECT 'MATRICULATION_PENDING', 'Ready for matriculation', 'Wait for the Academic Office to issue your number', '/applicant/matric', 'Your number is issued over the list of students who paid and registered.';
END $function$;

-- admissions.admission_tracker (V295's text): the letter step after the balance; the portal step as the gate reads it
CREATE OR REPLACE FUNCTION admissions.admission_tracker(p_app uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE a admissions.application; f admissions.screening_form; s people.student; q admissions.programme_change_request; st record; req boolean; ent record; steps jsonb := '[]'::jsonb;
        paid boolean; reg boolean; offered boolean; accepted boolean; scr_done boolean; scr_failed boolean; chg_approved boolean; vis boolean; checked_any boolean;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    SELECT * INTO st FROM admissions.admission_status(p_app);
    -- V295: the decision shows in the tracker only where the applicant may read it (checked, or the admission under way)
    vis := coalesce((SELECT c.decision_visible FROM admissions.status_checking(p_app) c), false);
    checked_any := EXISTS (SELECT 1 FROM admissions.status_check k WHERE k.application_id = p_app);
    offered := a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL;
    SELECT * INTO ent FROM admissions.acceptance_entitlement(p_app);
    accepted := a.accepted_at IS NOT NULL;
    req := admissions.screening_required(p_app);
    SELECT * INTO f FROM admissions.screening_form WHERE application_id = p_app;
    SELECT * INTO q FROM admissions.programme_change_request x WHERE x.application_id = p_app AND x.state IN ('REQUESTED', 'APPROVED') ORDER BY x.requested_at DESC LIMIT 1;
    scr_done := coalesce(f.state = 'SUCCESSFUL', false); scr_failed := coalesce(f.state = 'UNSUCCESSFUL', false);
    chg_approved := scr_failed AND coalesce(q.state = 'APPROVED' AND q.decided_at >= f.decided_at, false);
    SELECT * INTO s FROM people.student WHERE candidate_id = a.candidate_id LIMIT 1;
    paid := s.id IS NOT NULL AND coalesce((SELECT fp.paid_in_full AND fp.due > 0 FROM finance.position(s.id, a.session) fp), false);
    reg := s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = a.session AND r.status IN ('APPROVED', 'LOCKED'));
    steps := steps || admissions.tracker_step('ADMISSION', 'JAMB admission', CASE WHEN NOT vis THEN 'now' WHEN offered THEN 'done' WHEN a.decision_released_at IS NULL THEN 'now' ELSE 'failed' END);
    steps := steps || admissions.tracker_step('ADMISSION_STATUS', 'Admission status checked', CASE WHEN checked_any OR a.status_checked_at IS NOT NULL OR accepted OR ent.paid OR a.undertaking_at IS NOT NULL THEN 'done' WHEN a.fee_confirmed_at IS NOT NULL AND a.submitted_at IS NOT NULL THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_PAYMENT', 'Acceptance payment', CASE WHEN ent.paid THEN 'done' WHEN offered AND NOT admissions.checking_due(p_app) AND (a.status_checked_at IS NOT NULL OR a.undertaking_at IS NOT NULL) THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('ACCEPTANCE_LETTER', 'Acceptance letter', CASE WHEN accepted AND NOT coalesce(ent.balance_due, false) THEN 'done' WHEN accepted OR ent.paid THEN 'now' ELSE 'todo' END);   -- V724: after the balance
    IF req THEN
        steps := steps || admissions.tracker_step('SCREENING', 'University screening', CASE WHEN coalesce(f.state, '') IN ('SUCCESSFUL', 'UNSUCCESSFUL') THEN 'done' WHEN accepted THEN 'now' ELSE 'todo' END);
        IF scr_failed THEN
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening unsuccessful', 'failed');
            steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme', CASE WHEN q.id IS NOT NULL AND q.requested_at >= f.decided_at THEN 'done' ELSE 'now' END);
            steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN chg_approved THEN 'done' WHEN q.id IS NOT NULL AND q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
        ELSE
            -- V284: a change recommended during the screening is a step of it, approved or awaiting approval
            IF q.id IS NOT NULL AND f.application_id IS NOT NULL AND q.requested_at >= f.opened_at THEN
                steps := steps || admissions.tracker_step('CHANGE_OF_PROGRAMME', 'Change of programme' || CASE WHEN q.state = 'APPROVED' THEN ' · ' || q.to_programme ELSE '' END, CASE WHEN q.state = 'APPROVED' THEN 'done' ELSE 'now' END);
                steps := steps || admissions.tracker_step('CHANGE_APPROVAL', 'Approval', CASE WHEN q.state = 'APPROVED' THEN 'done' WHEN q.state = 'REQUESTED' THEN 'now' ELSE 'todo' END);
            END IF;
            steps := steps || admissions.tracker_step('SCREENING_DECISION', 'Screening successful', CASE WHEN scr_done THEN 'done' WHEN coalesce(f.state, '') IN ('PENDING', 'IN_REVIEW', 'CORRECTION_REQUIRED') THEN 'now' ELSE 'todo' END);
            steps := steps || admissions.tracker_step('SCREENING_FORMS', 'Screening forms generated', CASE WHEN scr_done THEN 'done' ELSE 'todo' END);
        END IF;
    END IF;
    steps := steps || admissions.tracker_step('SCHOOL_FEES', 'School fees', CASE WHEN paid THEN 'done' WHEN st.status IN ('SCHOOL_FEES_PENDING', 'REGISTER_PENDING', 'SCHOOL_FEES_NOT_AVAILABLE', 'SCHOOL_FEES_NOT_OPEN', 'SCHOOL_FEES_PART_PAID') THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('STUDENT_ACCOUNT', 'Student portal active', CASE WHEN s.id IS NOT NULL AND finance.portal_access_state(s.id) IN ('OPEN', 'CLEARED', 'EXCEPTION') THEN 'done' ELSE 'todo' END);   -- V724: as the gate reads it
    steps := steps || admissions.tracker_step('COURSE_REGISTRATION', 'Course registration', CASE WHEN reg THEN 'done' WHEN st.status = 'COURSE_REGISTRATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('MATRICULATION', 'Matriculation', CASE WHEN s.matric_no IS NOT NULL THEN 'done' WHEN st.status = 'MATRICULATION_PENDING' THEN 'now' ELSE 'todo' END);
    steps := steps || admissions.tracker_step('USERNAME', 'Sign-in changed to the matriculation number', CASE WHEN s.matric_no IS NOT NULL THEN 'done' ELSE 'todo' END);
    RETURN steps;
END $function$;

-- admissions.fee_reversal_check (V420's text): a balance reference confirmed in error is reversible; the payment the acceptance rests on is not
CREATE OR REPLACE FUNCTION admissions.fee_reversal_check(p_reference text)
 RETURNS TABLE(reference text, kind text, amount numeric, application_no text, applicant text, route text, session text, confirmed_at timestamp with time zone, channel text, receipt_no text, reversible boolean, why_not text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH r AS (SELECT f.* FROM admissions.fee_reference f WHERE f.reference = upper(btrim(p_reference))),
         a AS (SELECT ap.*, c.surname || ', ' || c.other_names AS applicant, c.entry_mode
                 FROM admissions.application ap JOIN admissions.candidate c ON c.id = ap.candidate_id JOIN r ON r.application_id = ap.id),
         x AS (
            SELECT r.reference, r.kind, r.amount, a.application_no, a.applicant, a.entry_mode, a.session, r.confirmed_at, r.channel, r.receipt_no,
                   CASE WHEN r.confirmed_at IS NULL THEN 'The reference is not confirmed: there is nothing to reverse'
                        WHEN EXISTS (SELECT 1 FROM finance.gateway_event g WHERE g.reference = r.reference AND g.outcome IN ('SETTLED', 'ALREADY_SETTLED'))
                            THEN 'The payment gateway settled it: the money reached the University on this reference. Refund it instead'
                        WHEN r.kind = 'APPLICATION' AND (a.submitted_at IS NOT NULL
                                 OR EXISTS (SELECT 1 FROM admissions.cce_review v WHERE v.application_id = a.id AND v.state <> 'DRAFT'))
                            THEN 'The application was submitted on this payment'
                        WHEN r.kind = 'CHECKING' AND (a.status_checked_at IS NOT NULL
                                 OR EXISTS (SELECT 1 FROM admissions.status_check k WHERE k.application_id = a.id AND k.checked_at >= r.confirmed_at))
                            THEN 'The admission status was read on this payment'
                        -- V724: only the payment the acceptance rests on is held; a balance drawn after a revision (for less than the fee stated
                        -- when it was drawn) stays reversible — the letter it released is withheld again
                        WHEN r.kind = 'ACCEPTANCE' AND (a.accepted_at IS NOT NULL
                                 OR EXISTS (SELECT 1 FROM people.student s WHERE s.candidate_id = a.candidate_id))
                             AND NOT (r.stated_fee IS NOT NULL AND r.amount < r.stated_fee)
                            THEN 'The offer was accepted on this payment'
                   END AS why_not
              FROM r JOIN a ON true)
    SELECT x.reference, x.kind, x.amount, x.application_no, x.applicant, x.entry_mode, x.session, x.confirmed_at, x.channel, x.receipt_no,
           x.why_not IS NULL, x.why_not
      FROM x;
$function$;

-- ── 6 · the monitors ─────────────────────────────────────────────────────────────────────────────────
-- every undergraduate programme, with or without a fee line reaching a fresh UTME (100 Level) or Direct Entry (200 Level) entrant of the
-- session — the Bursary's census of what is published, independent of who is on the register (the matching of finance.fee_gaps, V637)
CREATE FUNCTION finance.programme_fee_coverage(p_session text)
RETURNS TABLE (faculty_code text, faculty text, programme_code text, programme text, entry_mode text, level int, covered boolean, lines int, admitted int)
LANGUAGE sql STABLE AS $$
    WITH src AS (SELECT x.faculty_code, x.source_code FROM finance.fee_sources(p_session) x),
    prog AS (
        SELECT p.code, p.name, p.faculty_code, p.category, fs.source_code AS src
          FROM ref.programme p LEFT JOIN src fs ON fs.faculty_code = p.faculty_code
         WHERE NOT coalesce(p.archived, false) AND p.faculty_code IS NOT NULL AND coalesce(p.category, '') <> 'POST GRADUATE'),
    lv AS (SELECT 'UTME' AS entry_mode, 100 AS level UNION ALL SELECT 'DIRECT_ENTRY', 200),
    matched AS (
        -- covered when a line reaches every fresher of the entry: one naming no indigene state, or one for each (INDIGENE and NON_INDIGENE)
        SELECT pr.code, l.entry_mode, l.level, count(*)::int AS lines,
               bool_or(f.indigene IS NULL) OR (bool_or(f.indigene = 'INDIGENE') AND bool_or(f.indigene = 'NON_INDIGENE')) AS everyone
          FROM prog pr CROSS JOIN lv l
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE' AND NOT f.spillover
          LEFT JOIN ref.fee_group fg ON fg.code = f.fee_group
         WHERE (f.level IS NULL OR f.level = l.level)
           AND (f.entry_mode IS NULL OR f.entry_mode = l.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.code)
           AND (f.fee_group IS NULL OR fg.applies_category IS NULL OR fg.applies_category = pr.category)
           AND finance.pg_line(false, f.entry_mode, f.level, f.programme_code, fg.applies_category)
         GROUP BY pr.code, l.entry_mode, l.level),
    adm AS (
        SELECT s.programme_code, s.entry_mode, count(*)::int AS n
          FROM people.student s
         WHERE s.entry_session = p_session AND s.duplicate_of IS NULL AND s.entry_mode IN ('UTME', 'DIRECT_ENTRY')
         GROUP BY s.programme_code, s.entry_mode)
    SELECT pr.faculty_code, fa.name, pr.code, pr.name, l.entry_mode, l.level,
           coalesce(m.everyone, false), coalesce(m.lines, 0), coalesce(adm.n, 0)
      FROM prog pr CROSS JOIN lv l
      LEFT JOIN ref.faculty fa ON fa.code = pr.faculty_code
      LEFT JOIN matched m ON m.code = pr.code AND m.entry_mode = l.entry_mode AND m.level = l.level
      LEFT JOIN adm ON adm.programme_code = pr.code AND adm.entry_mode = l.entry_mode
     ORDER BY pr.faculty_code, pr.code, l.level
$$;
COMMENT ON FUNCTION finance.programme_fee_coverage(text) IS
  'V724: every undergraduate programme with or without a full-time FEE line in force reaching a fresh UTME (100 Level) or Direct Entry (200 Level) '
  'entrant of the session, the lines that reach it and the freshers of the session on the register — the school-fee readiness monitor''s census.';

-- the acceptance fee monitor: one row per released Post-UTME offer of the session (UTME and Direct Entry; not declined, not lapsed)
CREATE FUNCTION admissions.acceptance_fee_monitor(p_session text)
RETURNS TABLE (application_id uuid, application_no text, jamb_reg_no text, surname text, other_names text, programme text, programme_code text,
               faculty_code text, entry_mode text, fee_due numeric, paid_total numeric, balance numeric, excess numeric, payments int, first_amount numeric,
               first_paid_at timestamptz, last_paid_at timestamptz, open_reference text, open_amount numeric, band text, accepted_at timestamptz,
               student_id uuid, admission_no text, letters_issued int)
LANGUAGE sql STABLE AS $$
    WITH fee AS (SELECT r.acceptance_fee FROM admissions.applicant_fee_rule(p_session) r),
    offers AS (
        SELECT a.id, a.application_no, a.accepted_at, a.acceptance_confirmed_at, c.jamb_reg_no, c.surname, c.other_names, c.programme, c.entry_mode, c.id AS candidate_id
          FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
         WHERE a.session = p_session AND a.decision = 'OFFERED' AND a.decision_released_at IS NOT NULL
           AND a.declined_at IS NULL AND a.lapsed_at IS NULL AND c.entry_mode IN ('UTME', 'DIRECT_ENTRY')),
    paid AS (
        SELECT r.application_id, sum(r.amount) AS total, count(*)::int AS n, min(r.confirmed_at) AS first_at, max(r.confirmed_at) AS last_at,
               (array_agg(r.amount ORDER BY r.confirmed_at))[1] AS first_amount
          FROM admissions.fee_reference r
         WHERE r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NOT NULL AND r.application_id IN (SELECT o.id FROM offers o)
         GROUP BY r.application_id),
    open_ref AS (
        SELECT DISTINCT ON (r.application_id) r.application_id, r.reference, r.amount
          FROM admissions.fee_reference r
         WHERE r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NULL AND r.expires_at > now() AND r.application_id IN (SELECT o.id FROM offers o)
         ORDER BY r.application_id, r.generated_at DESC),
    letters AS (
        SELECT i.application_id, count(*)::int AS n FROM credentials.issued i
         WHERE i.kind = 'ADMISSION_LETTER' AND i.application_id IN (SELECT o.id FROM offers o) GROUP BY i.application_id),
    x AS (
        SELECT o.*, fee.acceptance_fee AS fee_due, coalesce(p.total, 0) AS paid_total, coalesce(p.n, 0) AS n, p.first_amount, p.first_at, p.last_at,
               orf.reference AS open_reference, orf.amount AS open_amount,
               -- as admissions.acceptance_entitlement reads it: an acceptance confirmed with no reference behind it (by hand, or carried
               -- from the old portal) owes nothing
               (coalesce(p.n, 0) = 0 AND o.acceptance_confirmed_at IS NOT NULL) AS by_hand
          FROM offers o CROSS JOIN fee
          LEFT JOIN paid p ON p.application_id = o.id
          LEFT JOIN open_ref orf ON orf.application_id = o.id)
    SELECT x.id, x.application_no, x.jamb_reg_no, x.surname, x.other_names, x.programme, pr.code, pr.faculty_code, x.entry_mode,
           x.fee_due, x.paid_total,
           CASE WHEN x.by_hand THEN 0 ELSE greatest(x.fee_due - x.paid_total, 0) END,
           greatest(x.paid_total - x.fee_due, 0),
           x.n, x.first_amount, x.first_at, x.last_at, x.open_reference, x.open_amount,
           CASE WHEN x.by_hand THEN 'CONFIRMED_WITHOUT_REFERENCE'
                WHEN x.paid_total = 0 AND x.open_reference IS NOT NULL THEN 'PENDING'
                WHEN x.paid_total = 0 THEN 'NOT_PAID'
                WHEN x.paid_total < x.fee_due THEN 'PART_PAID'
                WHEN x.paid_total > x.fee_due THEN 'OVERPAID'
                WHEN x.n > 1 THEN 'SETTLED_IN_PARTS'
                ELSE 'PAID_IN_FULL' END,
           x.accepted_at, s.id, s.admission_no, coalesce(l.n, 0)
      FROM x
      LEFT JOIN ref.programme pr ON pr.code = admissions.programme_code_of(x.programme)
      LEFT JOIN letters l ON l.application_id = x.id
      LEFT JOIN people.student s ON s.candidate_id = x.candidate_id AND s.duplicate_of IS NULL
$$;
COMMENT ON FUNCTION admissions.acceptance_fee_monitor(text) IS
  'V724: every released Post-UTME offer of the session (not declined or lapsed) with the acceptance fee as stated now, what is confirmed, the balance, '
  'any excess, the first amount paid, the reference awaiting the bank and a band — NOT_PAID, PENDING, PART_PAID (owing a balance), SETTLED_IN_PARTS '
  '(the revised fee met in more than one payment), PAID_IN_FULL (met in one), OVERPAID (more confirmed than the fee as stated now — for the refund desk), '
  'CONFIRMED_WITHOUT_REFERENCE (confirmed by hand or carried over; owes nothing). The acceptance fee monitor and its drill-down read it.';

-- the school-fee readiness monitor: one row per fresher of the session on the register (UTME and Direct Entry), set-based, reading the freshers
-- alone (their profiles' charges and their own payments; no arrears pass over the whole register)
CREATE FUNCTION finance.intake_fee_monitor(p_session text)
RETURNS TABLE (student_id uuid, admission_no text, matric_no text, surname text, other_names text, programme_code text, programme text, faculty_code text,
               entry_mode text, current_level int, status text, fee_stated boolean, due numeric, due_first_semester numeric, paid numeric, balance numeric,
               paid_in_full boolean, first_semester_cleared boolean, open_reference text, fee_state text, acceptance_balance numeric, has_applicant_account boolean,
               portal_state text, account_opened boolean, last_signed_in_at timestamptz)
LANGUAGE sql STABLE AS $$
    WITH g AS (SELECT * FROM finance.portal_fee_gate WHERE id = 1),
    win AS (SELECT w.state FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL) w),
    acc_fee AS (SELECT r.acceptance_fee FROM admissions.applicant_fee_rule(p_session) r),
    fresh AS MATERIALIZED (
        SELECT s.id, s.admission_no, s.matric_no, s.surname, s.other_names, s.programme_code, s.entry_mode, s.current_level, s.status, s.candidate_id
          FROM people.student s
         WHERE s.entry_session = p_session AND s.duplicate_of IS NULL AND s.entry_mode IN ('UTME', 'DIRECT_ENTRY')),
    prof AS (SELECT fp.student_id, fp.profile_key FROM finance.fee_profiles(p_session) fp WHERE fp.student_id IN (SELECT f.id FROM fresh f)),
    whole AS (SELECT x.profile_key, x.fee FROM finance.fee_sums(p_session, NULL) x),
    first AS (SELECT x.profile_key, x.due_upto FROM finance.fee_sums(p_session, 1) x),
    pay AS (
        SELECT r.student_id, sum(r.amount) AS total
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND r.student_id IN (SELECT f.id FROM fresh f)
         GROUP BY r.student_id),
    open_ref AS (
        SELECT DISTINCT ON (r.student_id) r.student_id, r.reference
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.purpose LIKE 'School fees%' AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
           AND r.student_id IN (SELECT f.id FROM fresh f)
         ORDER BY r.student_id, r.generated_at DESC),
    -- the acceptance balance as admissions.acceptance_entitlement reads it for UTME and Direct Entry: the fee as stated now less the confirmed
    -- references, owed only when a reference was paid (an acceptance confirmed with none behind it owes nothing)
    acc AS (
        SELECT f.id AS student_id,
               bool_or(acct.id IS NOT NULL) AS has_account,
               coalesce(sum(greatest((SELECT acc_fee.acceptance_fee FROM acc_fee) - refs.total, 0)) FILTER (WHERE refs.n > 0), 0) AS balance
          FROM fresh f
          LEFT JOIN admissions.applicant_account acct ON acct.candidate_id = f.candidate_id
          LEFT JOIN admissions.application a ON a.candidate_id = f.candidate_id AND a.session = p_session AND a.decision = 'OFFERED' AND a.declined_at IS NULL
          LEFT JOIN LATERAL (SELECT coalesce(sum(r.amount), 0) AS total, count(*) AS n FROM admissions.fee_reference r
                              WHERE r.application_id = a.id AND r.kind = 'ACCEPTANCE' AND r.confirmed_at IS NOT NULL) refs ON a.id IS NOT NULL
         GROUP BY f.id),
    exc AS (SELECT DISTINCT e.student_id FROM finance.portal_fee_gate_exception e WHERE e.revoked_at IS NULL AND now() >= e.starts_at AND now() < e.expires_at),
    y AS (
        SELECT f.*, coalesce(w.fee, 0) AS due, coalesce(fs.due_upto, 0) AS due1, coalesce(p.total, 0) AS paid, orf.reference AS open_reference,
               coalesce(ac.balance, 0) AS acc_balance, coalesce(ac.has_account, false) AS has_account, exc.student_id IS NOT NULL AS excepted
          FROM fresh f
          LEFT JOIN prof ON prof.student_id = f.id
          LEFT JOIN whole w ON w.profile_key = prof.profile_key
          LEFT JOIN first fs ON fs.profile_key = prof.profile_key
          LEFT JOIN pay p ON p.student_id = f.id
          LEFT JOIN open_ref orf ON orf.student_id = f.id
          LEFT JOIN acc ac ON ac.student_id = f.id
          LEFT JOIN exc ON exc.student_id = f.id)
    SELECT y.id, y.admission_no, y.matric_no, y.surname, y.other_names, y.programme_code, pr.name, pr.faculty_code, y.entry_mode, y.current_level, y.status,
           y.due > 0, y.due, y.due1, y.paid, finance.fee_owed(y.due, y.paid),
           y.due > 0 AND NOT finance.fee_short(y.due, y.paid),
           y.due1 > 0 AND NOT finance.fee_short(y.due1, y.paid),
           y.open_reference,
           CASE WHEN y.due <= 0 THEN 'NOT_CONFIGURED'
                WHEN NOT finance.fee_short(y.due, y.paid) THEN 'PAID'
                WHEN y.open_reference IS NOT NULL THEN 'PAYMENT_PENDING'
                WHEN (SELECT win.state FROM win) <> 'OPEN' THEN 'NOT_OPEN'
                WHEN y.paid > 0 THEN 'PART_PAID'
                ELSE 'AVAILABLE' END,
           y.acc_balance, y.has_account,
           -- as finance.portal_access_state reads it, set-based
           CASE WHEN NOT g.enabled OR y.status <> 'ADMITTED' OR y.matric_no IS NOT NULL OR y.candidate_id IS NULL OR NOT y.has_account
                     OR p_session < g.from_session THEN 'OPEN'
                WHEN y.excepted THEN 'EXCEPTION'
                WHEN y.acc_balance > 0 THEN 'HELD_ACCEPTANCE_BALANCE'
                WHEN y.due <= 0 THEN 'HELD_FEES_NOT_AVAILABLE'
                WHEN CASE g.clears_on WHEN 'PAID_IN_FULL' THEN NOT finance.fee_short(y.due, y.paid)
                     ELSE y.due1 > 0 AND NOT finance.fee_short(y.due1, y.paid) END THEN 'CLEARED'
                ELSE 'HELD_FEES_UNPAID' END,
           sa.student_id IS NOT NULL, sa.last_signed_in_at
      FROM y
      CROSS JOIN g
      LEFT JOIN ref.programme pr ON pr.code = y.programme_code
      LEFT JOIN iam.student_account sa ON sa.student_id = y.id
$$;
COMMENT ON FUNCTION finance.intake_fee_monitor(text) IS
  'V724: every fresher of the session on the register (UTME and Direct Entry) with what the school fees say — stated or not, due, the first semester''s '
  'due, paid, the balance, a reference awaiting the bank, the state (NOT_CONFIGURED, PAID, PAYMENT_PENDING, NOT_OPEN, PART_PAID, AVAILABLE) — the '
  'acceptance balance still owed, whether an applicant account exists, and where they stand at the student portal''s fee gate (OPEN, EXCEPTION, '
  'HELD_ACCEPTANCE_BALANCE, CLEARED, HELD_FEES_NOT_AVAILABLE, HELD_FEES_UNPAID), set-based over the freshers alone for the monitor.';

COMMIT;
