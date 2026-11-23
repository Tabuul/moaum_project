-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V777 · every SIWES course carries the ₦4,000 fee, paid before the student registers it, whatever the programme, level or semester
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  LAYERS 1 AND 2 (the money layer and the layer that follows). 
--  The user's word (22 November 2026): "yes charge every siwes course". V752 charged the ₦4,000 SIWES registration fee of a student SIWES
--  binds (300 Level, Second Semester, a configured programme) and V776 recognised the SIWES courses of the catalogue
--  (catalogue.course.industrial_training); every other SIWES course was registered free. From V777 the fee follows the course: one
--  ₦4,000 for the student for the session, covering every SIWES course they register in it, either semester, either level of a carry-over.
--
--  The money layer. A SIWES course on an ordinary registration has no registration.siwes_registration row (that table carries the 300
--  Level Second Semester behaviours: the Head cannot return it, the student cannot drop its course, the SIWES page reads it), so
--  the guards that keep a payment where a registration stands on it could not see it. V777 gives them a narrow link of their own:
--    · registration.siwes_course_entry: one row for each SIWES course entry accepted on a payment, many a student and session, none of
--      the SIWES-semester behaviours (no keys: the guards read it through the live entry, so a row whose entry is gone stands for nothing).
--    · finance.siwes_stands_on(payment): V752's test (a standing SIWES registration) or a standing SIWES course entry on that payment.
--    · The refund desk (raised, approved, and a refund approved read again under the lock), the payment correction desk, the archive desk,
--      the withdrawal of a record as never received and the old fees reset refuse, keep or count a payment a course entry stands on as they do
--      one a SIWES registration stands on (finance.siwes_refund_refusal, siwes_refund_follows, payment_reallocation_check,
--      payment_archive_refusals, not_received_refusal, reset_legacy_payments). finance.siwes_standing reads such a payment as registered, so
--      it is the one that settles the fee (finance.siwes_paid), and a payment that leaves moves the entries standing on it to the payment that
--      settles (finance.siwes_settling_follows_payment, siwes_stand_again), as V752 does a SIWES registration.
--    · catalogue.ix_course_siwes_marked: the marked, not ended, courses (the set that is charged).
--  No payment, credit, refund, reference, registration or entry row is written or changed by this layer; what a student whom SIWES binds
--  sees and pays is exactly V752's.
--
--  The rule. The entry trigger (registration.entry_siwes_only, which every writer of a registration entry ends in) now judges every SIWES
--  course (catalogue.course.industrial_training, not ended) where it returned for a student SIWES does not bind: the student, an
--  undergraduate in study, not CCE, not postgraduate, in the session that is their current one, must have a SIWES payment standing
--  (finance.siwes_paid: the portal's, or the old portal's of either semester) before the course is placed — SIWES_UNPAID; SIWES_FEE_NOT_SET
--  until the Bursar has published the session's fee (V777 states a 4,000 DRAFT for each planned session with none, so the Bursar only
--  presses Publish); SIWES_NOT_IN_REACH for a student whose programme carries no SIWES course at their level, who holds none and owes
--  none. Accepted, the entry is written to registration.siwes_course_entry on the payment that settles the fee, under the SIWES lock
--  taken before the payment is read (V762's lock order). One fee covers every SIWES course of the student in the session. Not judged
--  again: an entry that stands approved or in another class, a proposal whose entry is there already, the old portal's loaders (their
--  override), a student not judged. The student SIWES binds (V752, Second Semester) is judged by V752's text, untouched.
--  The students who registered a SIWES course before the rule and paid nothing are not refused anything and their registrations stand,
--  but they are in reach of the fee (registration.siwes_reach: HELD): their SIWES page asks it and they can pay it; the Bursary's list is
--  registration.siwes_entries_unpaid(session).
--  So that nobody is stranded, who may pay widens with the gate: registration.siwes_eligibility (mode SEMESTER, V752's, or COURSE: pay
--  on the SIWES page, register on Course Registration), finance.siwes_reference and siwes_reference_payable (registration.siwes_may_pay),
--  the SIWES menu item (registration.siwes_area), and a SIWES carry-over waits for the fee instead of failing the draft
--  (registration.student_draft, and the registration form's save, registration.student_choose). registration.siwes_register stays the SIWES
--  semester's alone (SIWES_NOT_BOUND).
--  The SIWES courses the Academic Office marks (V776) are the courses charged: marking one starts charging it, and taking one off stops
--  it, which registration.siwes_mark_course refuses while a student holds it on a registration standing on the fee
--  (SIWES_COURSE_IN_USE, the V776 refusals kept). The notice a student is sent when the fee is confirmed (SIWES_FEE_PAID) no longer says
--  the course is registered "on the SIWES page" (a template the Registry has re-worded is left as it is). The Bursary states a 4,000 DRAFT
--  fee for each planned session with none (decision of 22 November 2026: no fee published, no registration).
--  The link backfill (the last statement). The entries that stand when V777 is deployed were never judged and have no link row, so every
--  money guard would be blind to them: the old fees reset, which runs from time to time, could delete the old-portal SIWES payment a
--  student already paid for a course they hold. For each standing entry of a SIWES course on a registration of a student judged (the
--  session the student's current one) who has a SIWES payment standing, the link is written once, on the payment that settles the fee
--  (finance.siwes_paid: the one the entry trigger would link), under the SIWES lock taken before the payment is read. It writes no money row,
--  no entry and no registration, refuses nothing, and skips what is linked already, an entry V752's registration.siwes_registration holds
--  and a student not judged. The students who hold one and have paid nothing are not linked now (their registrations stand; the Bursary's list
--  is registration.siwes_entries_unpaid): the entry is linked when their payment comes to stand (registration.siwes_link_held, called by
--  finance.siwes_settling_follows_payment: a portal payment confirmed, or an old-portal record loaded), or by the gate if they register it again.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V777: every SIWES course carries the SIWES registration fee', true);

-- presence: every function restated here is as V752, V762 and V776 left it (another change since would be overwritten)
DO $$
DECLARE f text; h text; want text;
BEGIN
    FOR f, want IN VALUES
        ('finance.siwes_standing(uuid,text)', 'cb18223ea4d558a5e7452648eb83cc88'),
        ('finance.siwes_refund_refusal(text,numeric)', '7bf91e9eb2d5779809dfca7ab167e94b'),
        ('finance.siwes_refund_follows()', 'e0fc7cc42b32a27c44aa27b9e028134b'),
        ('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)', '786fe0126cc3c6597aa6644545baf22c'),
        ('finance.payment_archive_refusals(uuid)', '80a875801622a9780efe98a2b72ad9a9'),
        ('finance.reset_legacy_payments(text,text,integer)', '74141d52ff19697edea74c9b5067b677'),
        ('finance.not_received_refusal(uuid)', '74159945f8543b16fde6f0b6c2b91ffa'),
        ('finance.siwes_settling_follows_payment()', '8e0b8091adf3d278c55eb13e48b74f28'),
        ('finance.siwes_stand_again(uuid,text,text[],text)', '0e17c212a9f0f5ed5869a19c0380df13'),
        ('registration.entry_siwes_only()', '7d3d32a91b8d73a89e5f8ef90021c977'),
        ('registration.siwes_eligibility(uuid,text)', '1440dc391b634ea880e634eb658ad168'),
        ('finance.siwes_reference(uuid)', '3b77ef2b41d705f73da0c20d27cc6aee'),
        ('finance.siwes_reference_payable(text)', 'db471e5432fd3eb0f7c091a5adf62e10'),
        ('registration.siwes_area(uuid)', '789b1660b846ebcc06b790c2a609e122'),
        ('registration.siwes_register(uuid)', '641600dec9ee4d78206333dc3e2c2944'),
        ('registration.student_draft(uuid,text,integer)', 'e9c9499c07c06ac0806bda593d9fd378'),
        ('registration.student_choose(uuid,uuid[])', '2ac750e1fd5d1980e6c03f21e57851e9'),
        ('registration.siwes_reason_words(text[])', '29b77aaab6e08798d42c1ad2a2973b7d'),
        ('registration.siwes_mark_course(text,boolean)', 'cb39d10615b3feb0426e1d0462dc8f81'),
        ('registration.support_add_checks(uuid,text,integer,uuid)', 'a91488be1dd6f5a8ca7e91a6fa6cd3de')
    LOOP
        SELECT md5(replace(p.prosrc, E'\r', '')) INTO h FROM pg_proc p WHERE p.oid = to_regprocedure(f);
        IF h IS DISTINCT FROM want THEN
            RAISE EXCEPTION 'V777: % is not as V776 left it (restate this migration from its live text)', f;
        END IF;
    END LOOP;
END $$;

-- one fragment of a live function replaced exactly once, or the migration stops (V762's pg_temp.v762_once)
CREATE FUNCTION pg_temp.v777_once(p_def text, p_anchor text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_anchor IS NULL OR length(p_anchor) = 0 OR (length(p_def) - length(replace(p_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
        RAISE EXCEPTION 'V777: % is not as it was left (an anchor is not there exactly once)', p_what;
    END IF;
END $$;
CREATE FUNCTION pg_temp.v777_swap(p_def text, p_anchor text, p_repl text, p_what text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE d text := replace(p_def, E'\r', '');
BEGIN
    PERFORM pg_temp.v777_once(d, p_anchor, p_what);
    RETURN replace(d, p_anchor, p_repl);
END $$;

-- ── 1 · the marked-course index, and the link a SIWES course entry of an ordinary registration leaves ─────────────────────────────
-- the courses charged: marked industrial_training and not ended (37 rows; a scan of catalogue.course until now)
CREATE INDEX ix_course_siwes_marked ON catalogue.course (code) WHERE industrial_training AND state <> 'ENDED';

/* one row for each SIWES course entry accepted on a payment: the payment the course stands registered on. registration.siwes_registration
   (V752) is the same for the SIWES semester (one a student and session, 300 Level, Second Semester, the page and the behaviours that
   come with it); this is the narrow link for every other SIWES course, and only the money guards read it. No foreign keys: the guards
   join the live entry, so a row whose entry (or registration, or payment) is gone stands for nothing; keys would need V752's lock stretch
   on registration.entry, course_registration and people.student. */
CREATE TABLE registration.siwes_course_entry (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id             uuid NOT NULL,                      -- people.student
    session                text NOT NULL,                      -- policy.academic_session: the session of the registration
    course_registration_id uuid NOT NULL,                      -- registration.course_registration
    offering_id            uuid NOT NULL,                      -- catalogue.offering: the entry is (course_registration_id, offering_id)
    course_code            text NOT NULL,                      -- catalogue.course
    level                  integer NOT NULL,                   -- the registration's level
    semester               integer NOT NULL CHECK (semester IN (1, 2, 3)),
    payment_reference_id   uuid,                               -- finance.payment_reference: the portal's SIWES payment, or
    legacy_payment_id      uuid,                               -- the old portal's, whichever paid
    registered_at          timestamptz NOT NULL DEFAULT now(),
    registered_by          uuid,
    registered_office      text,
    CONSTRAINT uq_siwes_course_entry UNIQUE (course_registration_id, offering_id),
    CONSTRAINT ck_siwes_course_entry_paid CHECK (num_nonnulls(payment_reference_id, legacy_payment_id) = 1)
);
CREATE INDEX ix_siwes_course_entry_student ON registration.siwes_course_entry (student_id, session);
-- the payment an entry stands on is read by the payment desks (moves, archive, refunds, withdrawal, the old fees reset)
CREATE INDEX ix_siwes_course_entry_payment ON registration.siwes_course_entry (payment_reference_id) WHERE payment_reference_id IS NOT NULL;
CREATE INDEX ix_siwes_course_entry_legacy_payment ON registration.siwes_course_entry (legacy_payment_id) WHERE legacy_payment_id IS NOT NULL;
COMMENT ON TABLE registration.siwes_course_entry IS
  'V777: a SIWES course (catalogue.course.industrial_training) registered on an ordinary registration, and the payment its SIWES fee was settled by: written as the entry is accepted, read only by the money guards (finance.siwes_stands_on). One row for each entry; a student has as many as the SIWES courses they register in the session. The SIWES-semester registration of V752 stays registration.siwes_registration.';
SELECT audit.attach('registration.siwes_course_entry');

-- ── 2 · a payment a SIWES registration, or a SIWES course entry, stands on ──────────────────────────────────────────────────────
/* the one test every money guard asks: a registration stands on this payment — V752's SIWES-semester registration, or a SIWES course
   entry of an ordinary registration — and its entry is not dropped or withdrawn (dropping the course frees the payment). The test V752
   wrote inline in the refund desk, the payment correction desk, the archive desk, the withdrawal as never received and the settling of the
   fee, written once. */
CREATE FUNCTION finance.siwes_stands_on(p_payment uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_payment IS NOT NULL AND (
           EXISTS (SELECT 1 FROM registration.siwes_registration x
                     JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                              AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                    WHERE p_payment IN (x.payment_reference_id, x.legacy_payment_id))
        OR EXISTS (SELECT 1 FROM registration.siwes_course_entry x
                     JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                              AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                    WHERE p_payment IN (x.payment_reference_id, x.legacy_payment_id)));
$$;
COMMENT ON FUNCTION finance.siwes_stands_on(uuid) IS
  'V777: whether a registration stands on this SIWES payment — a SIWES-semester registration (registration.siwes_registration, V752) or a SIWES course entry of an ordinary registration (registration.siwes_course_entry) — with its entry not dropped or withdrawn. Read by the refund desk, the payment correction desk, the archive desk, the withdrawal as never received, the old fees reset and finance.siwes_standing.';


-- ── 3 · the money guards read the link: the same restatements V752 and V762 made, by anchor on the live text ────────────────────

-- V777 (1): a payment a SIWES course entry stands on reads as registered (finance.siwes_stands_on), so finance.siwes_paid prefers it as
-- the one that settles the fee, as it prefers the payment a SIWES registration stands on; the credit rules read the same flag
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_standing(uuid,text)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$                    WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id) AND x.student_id = r.student_id AND x.session = r.session)$a$,
                           $r$                    WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id) AND x.student_id = r.student_id AND x.session = r.session)
                OR finance.siwes_stands_on(r.id)$r$, 'finance.siwes_standing');
    EXECUTE d;
END $v777$;

-- V777 (2): the refund desk refuses a refund of a payment a SIWES course entry stands on (REFUND_SIWES_REGISTERED), raised and approved
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_refund_refusal(text,numeric)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$                 JOIN registration.siwes_registration x ON r.id IN (x.payment_reference_id, x.legacy_payment_id)
                 JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                WHERE r.reference = upper(btrim(coalesce(p_reference, '')))) THEN$a$,
                           $r$                WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND finance.siwes_stands_on(r.id)) THEN$r$, 'finance.siwes_refund_refusal');
    EXECUTE d;
END $v777$;

-- V777 (2b): a refund approved on a payment a SIWES course entry stands on is undone (REFUND_SIWES_REGISTERED), a refund written bare on
-- finance.refund as well as one approved on the desk (this trigger carries its own test: it does not call finance.siwes_refund_refusal)
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_refund_follows()'::regprocedure);
    d := pg_temp.v777_swap(d, $a$    IF EXISTS (SELECT 1 FROM registration.siwes_registration x
                 JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                WHERE pr.id IN (x.payment_reference_id, x.legacy_payment_id)) THEN$a$,
                           $r$    IF finance.siwes_stands_on(pr.id) THEN$r$, 'finance.siwes_refund_follows');
    EXECUTE d;
END $v777$;

-- V777 (3): the payment correction desk does not move a payment a SIWES course entry stands on (REALLOC_LINKED)
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$    IF EXISTS (SELECT 1 FROM registration.siwes_registration x   -- V752: the SIWES fee of a SIWES course that stands registered
                JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id)) THEN$a$,
                           $r$    IF finance.siwes_stands_on(r.id) THEN   -- V752: the SIWES fee of a SIWES course that stands registered (V777: on any registration)$r$, 'finance.payment_reallocation_check');
    EXECUTE d;
END $v777$;

-- V777 (4): the archive desk does not archive a payment a SIWES course entry stands on (PAR_LINKED)
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.payment_archive_refusals(uuid)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$    IF EXISTS (SELECT 1 FROM registration.siwes_registration x   -- V752: the SIWES fee of a SIWES course that stands registered
                JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id)) THEN$a$,
                           $r$    IF finance.siwes_stands_on(r.id) THEN   -- V752: the SIWES fee of a SIWES course that stands registered (V777: on any registration)$r$, 'finance.payment_archive_refusals');
    EXECUTE d;
END $v777$;

-- V777 (5): the old fees reset keeps an old-portal SIWES payment a SIWES course entry stands on, and counts it among those kept
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.reset_legacy_payments(text,text,integer)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$                   AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration sx WHERE sx.legacy_payment_id = r.id)$a$,
                           $r$                   AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration sx WHERE sx.legacy_payment_id = r.id)
                   -- V777: ... or a SIWES course entry of an ordinary registration stands on, its entry not dropped or withdrawn
                   AND NOT EXISTS (SELECT 1 FROM registration.siwes_course_entry cx
                                     JOIN registration.entry ce ON ce.registration_id = cx.course_registration_id AND ce.offering_id = cx.offering_id
                                                               AND ce.status NOT IN ('DROPPED', 'WITHDRAWN')
                                    WHERE cx.legacy_payment_id = r.id)$r$, 'finance.reset_legacy_payments');
    d := pg_temp.v777_swap(d, $a$                    OR r.id IN (SELECT sx.legacy_payment_id FROM registration.siwes_registration sx WHERE sx.legacy_payment_id IS NOT NULL)   -- V752$a$,
                           $r$                    OR r.id IN (SELECT sx.legacy_payment_id FROM registration.siwes_registration sx WHERE sx.legacy_payment_id IS NOT NULL)   -- V752
                    OR r.id IN (SELECT cx.legacy_payment_id FROM registration.siwes_course_entry cx
                                  JOIN registration.entry ce ON ce.registration_id = cx.course_registration_id AND ce.offering_id = cx.offering_id
                                                            AND ce.status NOT IN ('DROPPED', 'WITHDRAWN')
                                 WHERE cx.legacy_payment_id IS NOT NULL)   -- V777$r$, 'finance.reset_legacy_payments');
    EXECUTE d;
END $v777$;

-- V777 (6): a SIWES payment a SIWES course entry stands on, the student holding no other, is not withdrawn as never received
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.not_received_refusal(uuid)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$                  AND EXISTS (SELECT 1 FROM registration.siwes_registration x
                                JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                                         AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                               WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id))$a$,
                           $r$                  AND finance.siwes_stands_on(r.id)$r$, 'finance.not_received_refusal');
    EXECUTE d;
END $v777$;

-- V777 (7): a payment that leaves (set back, archived, moved, deleted) moves the SIWES course entries standing on it to the payment that settles
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_settling_follows_payment()'::regprocedure);
    d := pg_temp.v777_swap(d, $a$               AND registration.siwes_registered(x.student_id, x.session);
        END IF;$a$,
                           $r$               AND registration.siwes_registered(x.student_id, x.session);
        END IF;
        -- V777: the SIWES course entries of ordinary registrations standing on it follow it too (also a payment deleted: this link has no key
        -- to take it away with the payment)
        UPDATE registration.siwes_course_entry sc
           SET payment_reference_id = CASE WHEN p.source = 'PORTAL' THEN p.reference_id END,
               legacy_payment_id = CASE WHEN p.source = 'OLD_PORTAL' THEN p.reference_id END
          FROM finance.siwes_paid(OLD.student_id, OLD.session) p
         WHERE sc.student_id = OLD.student_id AND sc.session = OLD.session AND OLD.id IN (sc.payment_reference_id, sc.legacy_payment_id)
           AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = sc.course_registration_id AND e.offering_id = sc.offering_id
                                                            AND e.status NOT IN ('DROPPED', 'WITHDRAWN'));$r$, 'finance.siwes_settling_follows_payment');
    d := pg_temp.v777_swap(d, $a$        PERFORM finance.siwes_comes_to_stand(NEW.id);$a$,
                           $r$        PERFORM finance.siwes_comes_to_stand(NEW.id);
        -- V777: the SIWES course entries the student holds on a registration of the session (registered before the fee was asked, or placed under the
        -- old portal's override) stand on the payment that settles now: the money guards see them. Under the student's SIWES lock, as comes_to_stand
        IF NEW.session IS NOT NULL THEN
            PERFORM finance.siwes_lock(NEW.student_id, NEW.session);
            PERFORM registration.siwes_link_held(NEW.student_id, NEW.session);
        END IF;$r$, 'finance.siwes_settling_follows_payment');
    EXECUTE d;
END $v777$;

-- V777 (8): a standing SIWES course entry follows the payment that settles now, where the one it stood on no longer stands
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_stand_again(uuid,text,text[],text)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$                        WHERE s.reference_id IN (sr.payment_reference_id, sr.legacy_payment_id));$a$,
                           $r$                        WHERE s.reference_id IN (sr.payment_reference_id, sr.legacy_payment_id));
    -- V777: a standing SIWES course entry of an ordinary registration follows it too
    UPDATE registration.siwes_course_entry sc
       SET payment_reference_id = CASE WHEN p.source = 'PORTAL' THEN p.reference_id END,
           legacy_payment_id = CASE WHEN p.source = 'OLD_PORTAL' THEN p.reference_id END
      FROM finance.siwes_paid(p_student, p_session) p
     WHERE sc.student_id = p_student AND sc.session = p_session
       AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = sc.course_registration_id AND e.offering_id = sc.offering_id
                                                        AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
       AND NOT EXISTS (SELECT 1 FROM finance.siwes_standing(p_student, p_session) s
                        WHERE s.reference_id IN (sc.payment_reference_id, sc.legacy_payment_id));$r$, 'finance.siwes_stand_again');
    EXECUTE d;
END $v777$;
-- ── 4 · who is charged, who may pay, and what the fee covers: the new readers ─────────────────────────────────────────────────────
/* the students a SIWES course can charge: an undergraduate in study (ACTIVE or PROBATION), not of the Centre for Continuing Education,
   not postgraduate — the tests V752's reasons (registration.siwes_reasons_of) open with, written once. Whether SIWES BINDS the student's
   Second Semester (registration.siwes_applies) is another question: the fee does not ask it */
CREATE FUNCTION registration.siwes_fee_subject(p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM people.student s JOIN ref.programme pr ON pr.code = s.programme_code
                    WHERE s.id = p_student AND s.status IN ('ACTIVE', 'PROBATION')
                      AND pr.category = 'UNDER GRADUATE' AND NOT people.is_postgraduate(s.entry_mode, pr.category)
                      AND s.entry_mode IS DISTINCT FROM 'CCE');
$$;
COMMENT ON FUNCTION registration.siwes_fee_subject(uuid) IS
  'V777: whether a SIWES course can charge the student — an undergraduate in study (ACTIVE or PROBATION), not of the Centre for Continuing Education, not postgraduate (the first tests of registration.siwes_reasons_of, once).';

/* judged: a fee subject, in the session that is the student's current one — the one session a SIWES fee can be paid in
   (finance.siwes_reference draws for it). A session already closed, or one not yet current, is never judged */
CREATE FUNCTION registration.siwes_fee_judged(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_session IS NOT NULL AND registration.siwes_fee_subject(p_student)
       AND p_session IS NOT DISTINCT FROM people.student_current_session(p_student);
$$;
COMMENT ON FUNCTION registration.siwes_fee_judged(uuid, text) IS
  'V777: whether a SIWES course placed on the student''s registration of the session is judged against the fee — a fee subject (registration.siwes_fee_subject) and the session the student''s current one.';

/* the fee in force: the Bursar has published it for the session */
CREATE FUNCTION registration.siwes_fee_open(p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT finance.siwes_fee_for(p_session) IS NOT NULL;
$$;
COMMENT ON FUNCTION registration.siwes_fee_open(text) IS
  'V777: whether the SIWES registration fee of the session is published (finance.siwes_fee_for): without it no SIWES course is registered (SIWES_FEE_NOT_SET).';

/* the SIWES courses that are the student's, for the page, the payable test and the refusals (a judged student only; none otherwise):
     HELD       a SIWES course the student holds on a registration of the session (an entry that stands) — asked for the fee whatever else is
                true: registered before the fee was asked, it is not taken away, and the fee is asked of the student who holds it
     CARRYOVER  a SIWES course the student failed and owes (registration.carryovers), at any level
     STRUCTURE  the SIWES courses of the programme's structure at the student's level (catalogue.course_offer), the curriculum rule of
                V776's siwes_course_candidates
   one row for each course, the first of those that names it; passed: a course the student passed in an earlier session (a published
   pass), which is neither owed nor asked for (never true of a held one). Costly (the carry-overs read the results): the page and the
   payable test only, never a registration screen — registration.siwes_at_level is that one's */
CREATE FUNCTION registration.siwes_reach(p_student uuid, p_session text)
RETURNS TABLE(course_code text, title text, units integer, level integer, semester integer, basis text, state text, why text, held boolean, passed boolean)
LANGUAGE sql STABLE AS $$
    WITH s AS (
        SELECT st.id, st.programme_code, st.curriculum_version, st.current_level
          FROM people.student st
         WHERE st.id = p_student AND registration.siwes_fee_judged(st.id, p_session)),
    h AS (
        SELECT c.code, e.units, cr.level, cr.semester
          FROM s
          JOIN registration.course_registration cr ON cr.student_id = s.id AND cr.session = p_session
          JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training AND c.state <> 'ENDED'),
    owed AS (
        SELECT c.code, k.units, c.level, c.semester
          FROM s
         CROSS JOIN LATERAL registration.carryovers(s.id) k
          JOIN catalogue.course c ON c.code = k.course_code AND c.industrial_training AND c.state <> 'ENDED'),
    str AS (
        SELECT c.code, coalesce(co.units, c.units) AS units, co.level, c.semester
          FROM s
          JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
          JOIN catalogue.course c ON c.code = co.course_code AND c.industrial_training AND c.state <> 'ENDED'
         WHERE c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version OR registration.curriculum_open()),
    u AS (
        SELECT h.code, h.units, h.level, h.semester, 'HELD'::text AS why, 1 AS rk FROM h
        UNION ALL SELECT owed.code, owed.units, owed.level, owed.semester, 'CARRYOVER', 2 FROM owed
        UNION ALL SELECT str.code, str.units, str.level, str.semester, 'STRUCTURE', 3 FROM str),
    d AS (SELECT DISTINCT ON (u.code) u.* FROM u ORDER BY u.code, u.rk)
    SELECT c.code, c.title, d.units, coalesce(d.level, c.level), coalesce(d.semester, c.semester),
           (SELECT o2.basis FROM catalogue.course_offer o2, s WHERE o2.course_code = c.code AND o2.programme_code = s.programme_code ORDER BY o2.level LIMIT 1),
           c.state, d.why, d.why = 'HELD',
           d.why = 'STRUCTURE' AND EXISTS (
               SELECT 1 FROM registration.course_registration r2
                 JOIN registration.entry e2 ON e2.registration_id = r2.id AND e2.status IN ('REGISTERED', 'APPROVED')
                 JOIN catalogue.offering o3 ON o3.id = e2.offering_id AND o3.course_code = c.code
                WHERE r2.student_id = p_student AND r2.status IN ('APPROVED', 'LOCKED') AND r2.session < p_session
                  AND EXISTS (SELECT 1 FROM assessment.course_final(r2.student_id, o3.id) cf
                               WHERE cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' AND cf.points > 0))
      FROM d JOIN catalogue.course c ON c.code = d.code
     ORDER BY coalesce(d.semester, c.semester), coalesce(d.level, c.level), c.code;
$$;
COMMENT ON FUNCTION registration.siwes_reach(uuid, text) IS
  'V777: the SIWES courses that are the judged student''s in the session — HELD (an entry of the session that stands), CARRYOVER (failed and owed), STRUCTURE (the programme''s structure at the student''s level) — one row each, with whether a pass of an earlier session makes it neither owed nor asked for. Read by the SIWES page and the payable test; costly, never by a registration screen.';

/* the student is in reach of the fee: judged, and holds or owes or is set a SIWES course not already passed */
CREATE FUNCTION registration.siwes_in_reach(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT registration.siwes_fee_judged(p_student, p_session)
       AND EXISTS (SELECT 1 FROM registration.siwes_reach(p_student, p_session) r WHERE NOT r.passed);
$$;
COMMENT ON FUNCTION registration.siwes_in_reach(uuid, text) IS
  'V777: whether the student can be asked the SIWES fee in the session — a fee subject in the student''s current session who holds, owes or is set a SIWES course not already passed (registration.siwes_reach). Without one the fee has nothing to cover and cannot be paid.';

/* the cheap, structural half, for the menu: the programme's structure carries a SIWES course at the student's own level (an index
   probe on catalogue.course_offer by programme and level); a subject only. A student whose only SIWES course is a carry-over is not
   told by this: the registration page's own lock leads them to the SIWES page */
CREATE FUNCTION registration.siwes_at_level(p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT registration.siwes_fee_subject(p_student)
       AND EXISTS (SELECT 1 FROM people.student s
                     JOIN catalogue.course_offer co ON co.programme_code = s.programme_code AND co.level = s.current_level
                     JOIN catalogue.course c ON c.code = co.course_code AND c.industrial_training AND c.state <> 'ENDED'
                    WHERE s.id = p_student
                      AND (c.curriculum IS NULL OR s.curriculum_version IS NULL OR c.curriculum = s.curriculum_version OR registration.curriculum_open()));
$$;
COMMENT ON FUNCTION registration.siwes_at_level(uuid) IS
  'V777: whether the fee subject''s programme carries a SIWES course at their own level — the cheap test the SIWES menu item reads (registration.siwes_area), not the page''s (registration.siwes_reach).';

/* may the student pay the SIWES fee of the session now: one SIWES semester the programme binds keeps V752's window (the Academic Office
   opens and dates it); every other student in reach pays when the Bursar has published the fee. Read by the reference, the payable
   test the gateway, Quickteller and PayDirect ask, and the page */
CREATE FUNCTION registration.siwes_may_pay(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN registration.siwes_eligible(p_student, p_session) THEN registration.siwes_registration_open(p_session)
                ELSE registration.siwes_in_reach(p_student, p_session) AND registration.siwes_fee_open(p_session) END;
$$;
COMMENT ON FUNCTION registration.siwes_may_pay(uuid, text) IS
  'V777: whether the student may pay the SIWES registration fee of the session — a student SIWES binds (V752: registration.siwes_eligible) within the Academic Office''s window, else a student in reach (registration.siwes_in_reach) once the fee is published (registration.siwes_fee_open).';

/* the refusal a SIWES course placed on the student's registration meets when nothing pays for it, by its cause: the fee not published, the
   student with no SIWES course to pay for, else the fee unpaid. One text for the entry trigger and the registration pages */
CREATE FUNCTION registration.siwes_fee_refusal(p_student uuid, p_session text, p_course text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN NOT registration.siwes_fee_open(p_session)
            THEN 'SIWES_FEE_NOT_SET: the Bursary has not published the SIWES registration fee for ' || p_session
                 || '; ' || p_course || ' is registered once it is published and paid'
        WHEN NOT (registration.siwes_eligible(p_student, p_session) OR registration.siwes_in_reach(p_student, p_session))
            THEN 'SIWES_NOT_IN_REACH: ' || p_course || ' is a SIWES course and carries the SIWES registration fee for ' || p_session
                 || ', but your programme carries no SIWES course at your level, so the fee cannot be paid for it'
        ELSE 'SIWES_UNPAID: the SIWES registration fee for ' || p_session || ' is not paid; ' || p_course || ' is registered once it is'
    END;
$$;
COMMENT ON FUNCTION registration.siwes_fee_refusal(uuid, text, text) IS
  'V777: the words a SIWES course meets when no SIWES payment stands, by cause — SIWES_FEE_NOT_SET, SIWES_NOT_IN_REACH, else SIWES_UNPAID (V752''s words). Asked only once nothing is paid.';

/* the friendly refusal of a list of courses, as registration.gst_gate_many: one row for each distinct course, its message when it is a
   SIWES course of a judged student with nothing paid (the words the entry trigger raises), else NULL */
CREATE FUNCTION registration.siwes_fee_gate_many(p_student uuid, p_session text, p_courses text[])
RETURNS TABLE(course_code text, message text) LANGUAGE sql STABLE AS $$
    WITH want AS (SELECT DISTINCT u AS code FROM unnest(p_courses) u WHERE u IS NOT NULL),
         marked AS (SELECT w.code FROM want w JOIN catalogue.course c ON c.code = w.code AND c.industrial_training AND c.state <> 'ENDED'),
         unpaid AS (SELECT true AS yes WHERE EXISTS (SELECT 1 FROM marked)
                                          AND registration.siwes_fee_judged(p_student, p_session)
                                          AND NOT EXISTS (SELECT 1 FROM finance.siwes_paid(p_student, p_session)))
    SELECT w.code,
           CASE WHEN EXISTS (SELECT 1 FROM unpaid) AND EXISTS (SELECT 1 FROM marked m WHERE m.code = w.code)
                THEN registration.siwes_fee_refusal(p_student, p_session, w.code) END
      FROM want w;
$$;
COMMENT ON FUNCTION registration.siwes_fee_gate_many(uuid, text, text[]) IS
  'V777: for each course of a list, the refusal its SIWES fee would meet (the entry trigger''s words) or NULL: a SIWES course (catalogue.course.industrial_training), a student judged (registration.siwes_fee_judged), nothing paid (finance.siwes_paid). The registration page locks the course on it.';

CREATE FUNCTION registration.siwes_fee_gate(p_student uuid, p_session text, p_course text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = p_course AND c.industrial_training AND c.state <> 'ENDED')
                 AND registration.siwes_fee_judged(p_student, p_session)
                 AND NOT EXISTS (SELECT 1 FROM finance.siwes_paid(p_student, p_session))
                THEN registration.siwes_fee_refusal(p_student, p_session, p_course) END;
$$;
COMMENT ON FUNCTION registration.siwes_fee_gate(uuid, text, text) IS
  'V777: the refusal the course''s SIWES fee would meet (registration.siwes_fee_gate_many for one course; the cheap test first), or NULL.';

/* the Bursary's list: the students holding a SIWES course on a registration of the session (an entry that stands) with no SIWES payment
   standing — those who registered one before the fee was asked (the University's decision of 22 November 2026: they are asked to pay;
   their registrations stand and are not judged again), and any other entry placed without a payment (the old portal's loaders keep
   their override). payable: the session is the student's current one, so the SIWES page asks the fee of them */
CREATE FUNCTION registration.siwes_entries_unpaid(p_session text)
RETURNS TABLE(student_id uuid, matric_no text, name text, programme_code text, programme text, current_level integer,
              course_code text, course_title text, level integer, semester integer, registration_status text, payable boolean)
LANGUAGE sql STABLE AS $$
    SELECT s.id, s.matric_no, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), s.programme_code, pr.name,
           s.current_level, c.code, c.title, cr.level, cr.semester, cr.status, registration.siwes_fee_judged(s.id, p_session)
      FROM catalogue.course c
      JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session
      JOIN registration.entry e ON e.offering_id = o.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
      JOIN registration.course_registration cr ON cr.id = e.registration_id AND cr.session = p_session
      JOIN people.student s ON s.id = cr.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
     WHERE c.industrial_training AND c.state <> 'ENDED' AND registration.siwes_fee_subject(s.id)
       AND NOT EXISTS (SELECT 1 FROM finance.siwes_paid(s.id, p_session))
     ORDER BY s.programme_code, s.matric_no, cr.semester, c.code;
$$;
COMMENT ON FUNCTION registration.siwes_entries_unpaid(text) IS
  'V777: the Bursary''s list — the fee subjects holding a SIWES course on a registration of the session with no SIWES payment standing (those registered before the fee was asked, and any entry placed under the old portal''s override), with programme, level, course and semester; payable says the SIWES page asks them the fee (the session is their current one).';

/* the link of the SIWES course entries a student already holds, written when a payment comes to stand under them. The entry trigger links an entry
   it ACCEPTS; an entry that stands without a link — one registered before the fee was asked (the students asked to pay), or placed under the old portal's
   override — has none, so the money guards (refund, correction, archive, never received, the old fees reset) would not see that a registered course
   stands on the payment the student pays later. For each standing, not dropped or withdrawn, entry of a SIWES course (marked, not ended) on a registration
   of the student in the session, none of it V752's registration.siwes_registration, with no link, the student judged (registration.siwes_fee_judged) and a
   SIWES payment standing (finance.siwes_paid: the one that settles the fee), the link is written on that payment: the row the entry trigger writes (the
   registration's level and semester; registered when the student added the entry, where the entry records it, else now; by whoever's transaction it is).
   Writes nothing else, refuses nothing, never touches a link there already; written again changes nothing. TAKES NO LOCK: it is called under the
   student's SIWES lock (finance.siwes_lock) — by finance.siwes_settling_follows_payment, after the payment comes to stand, and by the backfill of this
   migration, one student at a time. Costs one index probe for a student with no such entry (the payment of a student of no SIWES course). */
-- V777 link held: begin
CREATE FUNCTION registration.siwes_link_held(p_student uuid, p_session text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE pd record; k integer := 0;
BEGIN
    IF p_student IS NULL OR p_session IS NULL THEN RETURN 0; END IF;
    -- nothing to link: no standing SIWES entry of the session without a link
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration cr
                     JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                     JOIN catalogue.offering o ON o.id = e.offering_id
                     JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training AND c.state <> 'ENDED'
                    WHERE cr.student_id = p_student AND cr.session = p_session
                      AND NOT EXISTS (SELECT 1 FROM registration.siwes_course_entry x WHERE x.course_registration_id = e.registration_id AND x.offering_id = e.offering_id)
                      AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.course_registration_id = e.registration_id AND x.offering_id = e.offering_id)) THEN
        RETURN 0;
    END IF;
    IF NOT registration.siwes_fee_judged(p_student, p_session) THEN RETURN 0; END IF;
    SELECT * INTO pd FROM finance.siwes_paid(p_student, p_session);
    IF pd.reference_id IS NULL THEN RETURN 0; END IF;
    INSERT INTO registration.siwes_course_entry (student_id, session, course_registration_id, offering_id, course_code, level, semester,
                                                 payment_reference_id, legacy_payment_id, registered_at, registered_by, registered_office)
    SELECT cr.student_id, cr.session, e.registration_id, e.offering_id, c.code, cr.level, cr.semester,
           CASE WHEN pd.source = 'PORTAL' THEN pd.reference_id END, CASE WHEN pd.source = 'OLD_PORTAL' THEN pd.reference_id END,
           coalesce(e.student_added_at, now()), nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), '')
      FROM registration.course_registration cr
      JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
      JOIN catalogue.offering o ON o.id = e.offering_id
      JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training AND c.state <> 'ENDED'
     WHERE cr.student_id = p_student AND cr.session = p_session
       AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.course_registration_id = e.registration_id AND x.offering_id = e.offering_id)
    ON CONFLICT (course_registration_id, offering_id) DO NOTHING;
    GET DIAGNOSTICS k = ROW_COUNT;
    RETURN k;
END $$;
-- V777 link held: end
COMMENT ON FUNCTION registration.siwes_link_held(uuid, text) IS
  'V777: links the SIWES course entries a student already holds in the session (registered before the fee was asked, or placed under the old portal''s override) to the SIWES payment that settles the fee, so the money guards see them; called under the student''s SIWES lock when a SIWES payment comes to stand and by the V777 backfill. Judged students only; writes nothing else, never touches a link there already; returns the rows written.';

/* the SIWES course entries the students hold of a course that has just come to be charged (marked a SIWES course on the desk, or by its title as it is
   retitled): for each student who holds it on a registration of a session still to come or running, under the student's SIWES lock,
   registration.siwes_link_held links the entry to the SIWES payment that settles the fee where one stands. A student who has paid nothing is asked as
   the gate asks: the entry stands, on the Bursary's list, linked when the payment comes to stand. Never refuses; written again changes nothing */
CREATE FUNCTION registration.siwes_link_held_course(p_course text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE s record; n integer := 0;
BEGIN
    FOR s IN SELECT DISTINCT cr.student_id, cr.session
               FROM catalogue.offering o
               JOIN registration.entry e ON e.offering_id = o.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
               JOIN registration.course_registration cr ON cr.id = e.registration_id
               JOIN policy.academic_session a ON a.name = cr.session AND a.state IN ('PLANNED', 'CURRENT')
              WHERE o.course_code = p_course
              ORDER BY cr.student_id, cr.session
    LOOP
        PERFORM finance.siwes_lock(s.student_id, s.session);
        n := n + registration.siwes_link_held(s.student_id, s.session);
    END LOOP;
    RETURN n;
END $$;
COMMENT ON FUNCTION registration.siwes_link_held_course(text) IS
  'V777: links the SIWES course entries of the students who hold a course that has just come to be charged (registration.siwes_link_held for each student holding it in a session still to come or running, under the student''s SIWES lock). Called by the trigger on the flag; returns the rows written.';

CREATE FUNCTION catalogue.course_links_siwes() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM registration.siwes_link_held_course(NEW.code);
    RETURN NULL;
END $$;
COMMENT ON FUNCTION catalogue.course_links_siwes() IS
  'V777: a course that comes to be a SIWES course (the flag turned on: the Academic Office''s Mark, a retitle V776 reads as SIWES, any other way) charges the students who already hold it in a session still to come or running: those who have paid are linked to their payment (registration.siwes_link_held_course).';
-- not UPDATE OF industrial_training: a retitle marks the course in V776's BEFORE trigger, and a column-specific trigger does not see a change a BEFORE trigger made
CREATE TRIGGER trg_course_links_siwes AFTER UPDATE ON catalogue.course
    FOR EACH ROW WHEN (NEW.industrial_training AND NOT OLD.industrial_training) EXECUTE FUNCTION catalogue.course_links_siwes();



-- ── 5 · the pay chain: who may pay, what the reference and the gateway ask, where the fee is read ──────────────────────────────────

-- V777 (10): the words of the new reason NO_SIWES_COURSE (a fee subject with no SIWES course to pay for)
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.siwes_reason_words(text[])'::regprocedure);
    d := pg_temp.v777_swap(d, $a$               WHEN 'ALREADY_PASSED' THEN 'a SIWES course is already passed'$a$,
                           $r$               WHEN 'ALREADY_PASSED' THEN 'a SIWES course is already passed'
               WHEN 'NO_SIWES_COURSE' THEN 'the programme carries no SIWES course at the student''s level, and none is held or owed'$r$, 'registration.siwes_reason_words');
    EXECUTE d;
END $v777$;

-- V777 (10): the SIWES page reads the fee for every SIWES course, not only the SIWES semester — mode SEMESTER (a student SIWES binds: V752, every key
-- as it was), COURSE (a student not bound who holds, owes or is set a SIWES course: pays here, registers the course on Course Registration), else none;
-- eligible is bound or in reach (bound says V752's), the courses the fee covers, where they are registered, and the reason NO_SIWES_COURSE for a fee
-- subject with none to pay for. canPay follows registration.siwes_may_pay; canRegister stays the SIWES page's
CREATE OR REPLACE FUNCTION registration.siwes_eligibility(p_student uuid, p_session text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s record; v_session text; v_reasons text[]; v_code text; v_course jsonb; f finance.siwes_fee; pd record; v_open boolean;
        v_ref record; v_reg_id uuid; v_reg jsonb; v_other jsonb; v_eligible boolean; v_fees_stated boolean; v_fees_cleared boolean; v_owed numeric;
        v_bound boolean; v_judged boolean; v_in_reach boolean; v_mode text; v_courses jsonb;
BEGIN
    SELECT st.*, pr.name AS programme_name, d.code AS d_code, d.name AS d_name, fa.code AS f_code, fa.name AS f_name INTO s
      FROM people.student st
      LEFT JOIN ref.programme pr ON pr.code = st.programme_code
      LEFT JOIN ref.department d ON d.code = pr.dept_code
      LEFT JOIN ref.faculty fa ON fa.code = coalesce(d.faculty_code, pr.faculty_code)
     WHERE st.id = p_student;
    IF s.id IS NULL THEN RAISE EXCEPTION 'SIWES_NO_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    v_session := coalesce(nullif(btrim(coalesce(p_session, '')), ''), people.student_current_session(p_student));
    v_reasons := registration.siwes_reasons(p_student, v_session);
    v_eligible := cardinality(v_reasons) = 0;
    -- V777: V752's eligible is the SIWES semester (bound). A fee subject it does not bind who holds, owes or is set a SIWES course is in reach of
    -- the fee for it (COURSE: pay here, register the course on Course Registration); one with none is told so, beside V752's reasons
    v_bound := v_eligible;
    v_judged := registration.siwes_fee_judged(p_student, v_session);
    v_in_reach := NOT v_bound AND v_judged AND registration.siwes_in_reach(p_student, v_session);
    v_mode := CASE WHEN v_bound THEN 'SEMESTER' WHEN v_in_reach THEN 'COURSE' END;
    v_eligible := v_bound OR v_in_reach;
    -- eligible, bound or in reach, means no reasons: what keeps SIWES from binding a student in reach is not said to them; one not eligible has V752's
    -- reasons, and NO_SIWES_COURSE beside them when they are a fee subject with nothing to pay for (a pass of SIWES says only that)
    IF v_in_reach THEN v_reasons := '{}'::text[]; END IF;
    IF NOT v_eligible AND v_judged AND NOT ('ALREADY_PASSED' = ANY (v_reasons)) THEN v_reasons := v_reasons || 'NO_SIWES_COURSE'::text; END IF;
    v_courses := coalesce((SELECT jsonb_agg(jsonb_build_object('code', x.course_code, 'title', x.title, 'units', x.units, 'level', x.level,
                                                               'semester', x.semester, 'basis', x.basis, 'state', x.state, 'why', x.why,
                                                               'held', x.held, 'passed', x.passed,
                                                               -- the status of the registration that holds the course (DRAFT, RETURNED, SUBMITTED, APPROVED, LOCKED), else null
                                                               'registrationStatus', CASE WHEN x.held THEN (SELECT cr.status FROM registration.course_registration cr
                                                                                                             JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                                                                                                             JOIN catalogue.offering o ON o.id = e.offering_id AND o.course_code = x.course_code
                                                                                                            WHERE cr.student_id = p_student AND cr.session = v_session
                                                                                                            ORDER BY (cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) DESC, cr.semester LIMIT 1) END)
                                                      ORDER BY x.semester, x.level, x.course_code)
                             FROM registration.siwes_reach(p_student, v_session) x), '[]'::jsonb);
    v_code := registration.siwes_course_of(s.programme_code, s.curriculum_version);
    v_course := registration.siwes_course_json(v_code, s.programme_code);
    SELECT * INTO f FROM finance.siwes_fee WHERE session = v_session;
    v_open := registration.siwes_registration_open(v_session);
    SELECT * INTO pd FROM finance.siwes_paid(p_student, v_session);
    SELECT r.reference, r.amount, r.expires_at INTO v_ref FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = v_session AND r.purpose LIKE 'SIWES registration fee%'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
       AND finance.siwes_reference_payable(r.reference)
     ORDER BY r.generated_at DESC LIMIT 1;
    SELECT x.id INTO v_reg_id FROM registration.siwes_registration x WHERE x.student_id = p_student AND x.session = v_session;
    -- a SIWES course dropped since (by an office) is no registration: the student registers again
    v_reg := registration.siwes_registration_json(v_reg_id);
    IF v_reg ->> 'status' = 'DROPPED' THEN v_reg := NULL; END IF;
    -- the ordinary courses in the way: never the SIWES course — today's mapping, nor the course the SIWES registration was made on,
    -- whatever the mapping says since (registration.courseCode names it)
    SELECT coalesce(jsonb_agg(DISTINCT o.course_code), '[]'::jsonb) INTO v_other
      FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id JOIN catalogue.offering o ON o.id = e.offering_id
     WHERE r.student_id = p_student AND r.session = v_session AND r.semester = 2 AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
       AND o.course_code IS DISTINCT FROM v_code
       AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.student_id = p_student AND x.session = v_session
                          AND (x.offering_id = e.offering_id OR x.course_code = o.course_code));
    -- the Second Semester school fees, by the very tests the registration's own gates apply when the SIWES course is registered
    -- (registration.submit_checks: REG_FEES_NOT_STATED, REG_SEMESTER_FEES_NOT_STATED, REG_SEMESTER_FEES_DUE): still owed (decision 3)
    v_fees_stated := finance.fee_stated(p_student, v_session) AND NOT (2 = ANY (coalesce(finance.fee_unstated_semesters(p_student, v_session), '{}'::integer[])));
    v_fees_cleared := finance.semester_cleared(p_student, v_session, 2);
    IF NOT v_fees_cleared THEN
        SELECT fp.outstanding INTO v_owed FROM finance.semester_position(p_student, v_session, 2, false) fp;
    END IF;
    RETURN jsonb_build_object(
        'studentId', s.id,
        'eligible', v_eligible,
        -- V777: bound = V752's eligible (the SIWES semester, registered on the SIWES page); mode SEMESTER / COURSE / none; the SIWES courses the fee
        -- covers; where the course is registered
        'bound', v_bound, 'mode', v_mode, 'courses', v_courses,
        'registerOn', CASE v_mode WHEN 'SEMESTER' THEN 'SIWES_PAGE' WHEN 'COURSE' THEN 'COURSE_REGISTRATION' END,
        -- whether SIWES binds the student's Second Semester of the session (registration.siwes_applies), as every registration reader reads it
        'applies', registration.siwes_applies(p_student, v_session),
        'reasons', to_jsonb(v_reasons),
        'session', v_session,
        'level', CASE WHEN v_mode = 'COURSE' THEN NULL::integer ELSE registration.siwes_level(p_student, v_session) END,
        'semester', CASE WHEN v_mode = 'COURSE' THEN NULL::integer ELSE 2 END,
        'programme', jsonb_build_object('code', s.programme_code, 'name', s.programme_name),
        'curriculum', s.curriculum_version,
        'departmentCode', s.d_code, 'department', s.d_name, 'facultyCode', s.f_code, 'faculty', s.f_name,
        'course', CASE WHEN v_mode = 'COURSE' THEN NULL::jsonb ELSE v_course END,
        'period', registration.siwes_period_json(v_session),
        'registrationOpen', CASE WHEN v_mode = 'COURSE' THEN registration.siwes_fee_open(v_session) ELSE v_open END,
        'fee', CASE WHEN f.session IS NULL THEN NULL ELSE jsonb_build_object('amount', f.amount, 'state', f.state) END,
        'paid', CASE WHEN pd.reference_id IS NULL THEN NULL
                     ELSE jsonb_build_object('reference', pd.reference, 'amount', pd.amount, 'receiptNo', pd.receipt_no, 'at', pd.confirmed_at,
                                             'channel', pd.channel, 'source', pd.source) END,
        'openReference', CASE WHEN v_ref.reference IS NULL THEN NULL
                              ELSE jsonb_build_object('reference', v_ref.reference, 'amount', v_ref.amount, 'expiresAt', v_ref.expires_at) END,
        'registration', v_reg,
        'otherCourses', CASE WHEN v_mode = 'COURSE' THEN '[]'::jsonb ELSE v_other END,
        -- cleared: the semester's school fees paid (REG_SEMESTER_FEES_DUE); outstanding: what is left when not (else null); stated: the
        -- session's and the semester's school fees stated (REG_FEES_NOT_STATED, REG_SEMESTER_FEES_NOT_STATED)
        'semesterFees', CASE WHEN v_mode = 'COURSE' THEN NULL::jsonb
                             ELSE jsonb_build_object('cleared', v_fees_cleared, 'outstanding', v_owed, 'stated', v_fees_stated) END,
        'canPay', CASE WHEN v_bound THEN v_open WHEN v_in_reach THEN registration.siwes_fee_open(v_session) ELSE false END
                  AND pd.reference_id IS NULL AND f.state IS NOT DISTINCT FROM 'PUBLISHED',
        'canRegister', v_bound AND v_open AND pd.reference_id IS NOT NULL AND jsonb_array_length(v_other) = 0 AND v_reg IS NULL
                       AND v_fees_cleared AND v_fees_stated);
END $function$;

-- V777 (11): the reference of a student SIWES does not bind (a COURSE student in reach) is drawn when the Bursar has published the fee: the
-- Academic Office's window is the SIWES semester's alone; the refusals stay SIWES_NOT_ELIGIBLE, SIWES_PAID, SIWES_CLOSED (a bound student), SIWES_FEE_NOT_SET
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_reference(uuid)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$HINT = 'SIWES registration is for 300 Level undergraduates of the programmes the Academic Office configures for the session.'$a$,
                           $r$HINT = 'SIWES registration fee is paid by an undergraduate whose programme carries a SIWES course at their level, or who holds or owes one.'$r$, 'finance.siwes_reference');
    d := pg_temp.v777_swap(d, $a$HINT = 'Register your SIWES course on the SIWES page.'$a$,
                           $r$HINT = CASE WHEN (e ->> 'bound')::boolean THEN 'Register your SIWES course on the SIWES page.' ELSE 'Register your SIWES course on Course Registration.' END$r$, 'finance.siwes_reference');
    d := pg_temp.v777_swap(d, $a$IF NOT registration.siwes_registration_open(v_session) THEN$a$,
                           $r$IF (e ->> 'bound')::boolean AND NOT registration.siwes_registration_open(v_session) THEN$r$, 'finance.siwes_reference');
    EXECUTE d;
END $v777$;

-- V777 (12): a SIWES reference is payable when the student may pay (registration.siwes_may_pay): V752's window and eligibility for a student SIWES
-- binds, the fee published and a SIWES course in reach for any other. The checkout, Quickteller and PayDirect validation all read this
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('finance.siwes_reference_payable(text)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$               AND registration.siwes_registration_open(r.session)
               AND registration.siwes_eligible(r.student_id, r.session)$a$,
                           $r$               AND registration.siwes_may_pay(r.student_id, r.session)$r$, 'finance.siwes_reference_payable');
    EXECUTE d;
END $v777$;

-- V777 (13): the SIWES menu item is the student's too when their programme carries a SIWES course at their level (the cheap test,
-- registration.siwes_at_level) or they hold one on a registration of the current session (asked the fee): last in the test, so a student with none is
-- read as before
CREATE OR REPLACE FUNCTION registration.siwes_area(p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT registration.siwes_applies(p_student, people.student_current_session(p_student))
        OR EXISTS (SELECT 1 FROM registration.siwes_registration sr WHERE sr.student_id = p_student
                      AND registration.siwes_registered(p_student, sr.session))
        OR EXISTS (SELECT 1 FROM (SELECT DISTINCT r.session FROM finance.payment_reference r
                                   WHERE r.student_id = p_student AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                                     AND finance.is_siwes_purpose(r.purpose)) k
                    WHERE EXISTS (SELECT 1 FROM finance.siwes_standing(p_student, k.session))
                      AND (EXISTS (SELECT 1 FROM registration.siwes_registration sr WHERE sr.student_id = p_student AND sr.session = k.session)
                           OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = p_student AND p.session = k.session
                                         AND p.purpose LIKE 'SIWES registration fee%' AND p.confirmed_at IS NOT NULL)
                           OR (EXISTS (SELECT 1 FROM registration.siwes_period pd JOIN registration.siwes_programme sp ON sp.session = pd.session
                                         JOIN people.student s ON s.id = p_student AND s.programme_code = sp.programme_code
                                        WHERE pd.session = k.session AND pd.state <> 'DRAFT')   -- cheap first: configured for them there
                               AND registration.siwes_applies(p_student, k.session))))
        -- V777: every SIWES course carries the fee: the page where it is paid is the student's whose programme carries one at their level,
        OR registration.siwes_at_level(p_student)
        -- or who holds one on a registration of the current session (registered before the fee was asked, or since)
        OR (registration.siwes_fee_subject(p_student)
            AND EXISTS (SELECT 1 FROM registration.course_registration cr
                          JOIN registration.entry e ON e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                          JOIN catalogue.offering o ON o.id = e.offering_id
                          JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training AND c.state <> 'ENDED'
                         WHERE cr.student_id = p_student AND cr.session = people.student_current_session(p_student)));
$function$;

-- V777 (14): the SIWES page registers the SIWES semester of a student SIWES binds only. A student not bound who is in reach of the fee has the course to
-- register on Course Registration (SIWES_NOT_BOUND), not a Second Semester registration with no course; a student not in reach keeps V752's refusal
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.siwes_register(uuid)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$    IF NOT (e ->> 'eligible')::boolean THEN
        RAISE EXCEPTION 'SIWES_NOT_ELIGIBLE: you are not eligible for SIWES registration in %: %', v_session,
            registration.siwes_reason_words(ARRAY(SELECT jsonb_array_elements_text(e -> 'reasons'))) USING ERRCODE = '23514';
    END IF;$a$,
                           $r$    IF NOT (e ->> 'bound')::boolean THEN
        IF (e ->> 'eligible')::boolean THEN
            RAISE EXCEPTION 'SIWES_NOT_BOUND: SIWES does not bind your Second Semester of %; your SIWES course is registered on Course Registration, not here', v_session
                USING ERRCODE = '23514', HINT = 'Pay the SIWES registration fee on the SIWES page, then register the course on Course Registration.';
        END IF;
        RAISE EXCEPTION 'SIWES_NOT_ELIGIBLE: you are not eligible for SIWES registration in %: %', v_session,
            registration.siwes_reason_words(ARRAY(SELECT jsonb_array_elements_text(e -> 'reasons'))) USING ERRCODE = '23514';
    END IF;$r$, 'registration.siwes_register');
    EXECUTE d;
END $v777$;

-- V777 (15): a SIWES carry-over waits for the SIWES fee as a GST carry-over waits for the GST fee (V512): the draft is made without it and the student adds it once the
-- fee is paid, instead of one unpaid carry-over failing the whole draft at the entry trigger
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.student_draft(uuid,text,integer)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$        IF registration.registered_elsewhere(p_student, p_session, p_semester, m.course_code) THEN CONTINUE; END IF;$a$,
                           $r$        IF registration.registered_elsewhere(p_student, p_session, p_semester, m.course_code) THEN CONTINUE; END IF;
        -- V777: nor an unpaid SIWES carry-over: every SIWES course carries the fee, asked when the student adds it
        IF registration.siwes_fee_gate(p_student, p_session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;$r$, 'registration.student_draft');
    EXECUTE d;
END $v777$;

-- V777 (15b): the registration form's save adds the carry-overs that have become due to a draft, and an unpaid SIWES carry-over waits for the SIWES fee as a GST carry-over waits
-- for the GST fee (V512): the form is saved without it and the student adds it once the fee is paid, instead of one unpaid carry-over refusing every save
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.student_choose(uuid,uuid[])'::regprocedure);
    d := pg_temp.v777_swap(d, $a$        IF registration.registered_elsewhere(r.student_id, r.session, r.semester, m.course_code) THEN CONTINUE; END IF;$a$,
                           $r$        IF registration.registered_elsewhere(r.student_id, r.session, r.semester, m.course_code) THEN CONTINUE; END IF;
        -- V777: nor an unpaid SIWES carry-over: every SIWES course carries the fee, asked when the student adds it
        IF registration.siwes_fee_gate(r.student_id, r.session, m.course_code) IS NOT NULL THEN CONTINUE; END IF;$r$, 'registration.student_choose');
    EXECUTE d;
END $v777$;

-- V777 (9): taking a course off the SIWES courses (which stops charging it) is refused while a student holds it on a registration that stands on the SIWES fee
-- (registration.siwes_course_entry, the entry not dropped or withdrawn): SIWES_COURSE_IN_USE, as V776 refuses it while students have paid or registered the
-- SIWES semester; accepted once the entries are dropped. Marking a course on starts charging it: the courses students hold already are not judged again
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.siwes_mark_course(text,boolean)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) of % are registered in the attachment semester % makes; it stays a SIWES course', n, v_who, c.code
                USING ERRCODE = '23514';
        END IF;$a$,
                           $r$            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) of % are registered in the attachment semester % makes; it stays a SIWES course', n, v_who, c.code
                USING ERRCODE = '23514';
        END IF;
        -- V777: every SIWES course carries the SIWES registration fee, so taking one off stops charging it. The students who hold it on an ordinary
        -- registration (a SIWES course entry, whatever their programme) hold it on a payment the money guards protect while the entry stands: it stays
        -- a SIWES course until they have dropped it
        SELECT count(DISTINCT x.student_id) INTO n
          FROM registration.siwes_course_entry x
          JOIN policy.academic_session a ON a.name = x.session AND a.state IN ('PLANNED', 'CURRENT')
          JOIN catalogue.offering o ON o.id = x.offering_id AND o.course_code = c.code
          JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                   AND e.status NOT IN ('DROPPED', 'WITHDRAWN');
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) hold % in a session still to come or running on a registration that stands on the SIWES registration fee; taking it off the SIWES courses would stop charging it, and it stays a SIWES course', n, c.code
                USING ERRCODE = '23514', HINT = 'They drop the course on Course Registration first, or ICT Support drops it for them.';
        END IF;$r$, 'registration.siwes_mark_course');
    EXECUTE d;
END $v777$;

-- V777 (review): the preview of an add by ICT Support or a record editor tells the SIWES fee as the entry trigger will: a SIWES course (catalogue.course.industrial_training,
-- not ended) of a student not bound by V752's SIWES semester is a failing, not overridable rule while the fee is unpaid, not published, or the student is not in reach
DO $v777$
DECLARE d text;
BEGIN
    d := pg_get_functiondef('registration.support_add_checks(uuid,text,integer,uuid)'::regprocedure);
    d := pg_temp.v777_swap(d, $a$
    END IF;
END $function$$a$,
                           $r$
    ELSIF coalesce(c.industrial_training AND c.state <> 'ENDED', false) THEN
        ord := 17; rule := 'SIWES_FEE'; label := 'SIWES registration fee'; advisory := false; overridable := false;
        v_gate := registration.siwes_fee_gate(p_student, p_session, c.code);
        passed := v_gate IS NULL;
        message := coalesce(v_gate, 'The SIWES registration fee is paid, or is not asked of the student in this session.');
        RETURN NEXT;
    END IF;
END $function$$r$, 'registration.support_add_checks');
    EXECUTE d;
END $v777$;

-- ── the SIWES registration fee of every session still to come: stated, for the Bursar to publish ────────────────────────────────────
/* no fee published, no registration (SIWES_FEE_NOT_SET): the Bursary states and publishes the fee on Fee Setup. So that the Bursar only presses
   Publish, a ₦4,000 DRAFT is stated now for each PLANNED session that has no fee row (a published or drafted one is left exactly as it is) */
DO $v777$
DECLARE n int;
BEGIN
    INSERT INTO finance.siwes_fee (session, amount, state, note, stated_by, stated_office, draft_amount, draft_note, drafted_by, drafted_office, drafted_at)
    SELECT a.name, 4000, 'DRAFT', 'V777: stated for the Bursar to publish — every SIWES course carries the SIWES registration fee',
           '00000000-0000-0000-0000-000000000000', 'bursar', 4000, 'V777: stated for the Bursar to publish — every SIWES course carries the SIWES registration fee',
           '00000000-0000-0000-0000-000000000000', 'bursar', now()
      FROM policy.academic_session a
     WHERE a.state = 'PLANNED' AND NOT EXISTS (SELECT 1 FROM finance.siwes_fee f WHERE f.session = a.name);
    GET DIAGNOSTICS n = ROW_COUNT;
    RAISE NOTICE 'V777: a DRAFT SIWES registration fee of 4,000 stated for % planned session(s) with none; the Bursar publishes it on Fee Setup', n;
END $v777$;


-- ── the notice a student is sent when the SIWES fee is confirmed: it no longer says where the course is registered ──────────────────
/* V752's words send every student to "the SIWES page" to register the course; a student SIWES does not bind registers it on Course Registration,
   and the notice cannot tell which. Neutral words, each field changed only where it still reads exactly as V752 wrote it (a template the Registry
   has re-worded since is left as it is) */
DO $v777$
DECLARE n int := 0; k int;
BEGIN
    UPDATE platform.notice_template
       SET portal_body = 'Your SIWES registration fee for [SESSION] is paid. Sign in and register your SIWES course: paying does not register it.',
           updated_by = '00000000-0000-0000-0000-000000000000', updated_office = 'bursar', updated_at = now()
     WHERE key = 'SIWES_FEE_PAID'
       AND portal_body = 'Your SIWES registration fee for [SESSION] is paid. Register your SIWES course on the SIWES page.';
    GET DIAGNOSTICS k = ROW_COUNT; n := n + k;
    UPDATE platform.notice_template
       SET email_body = replace(email_body, 'Sign in, open SIWES and register your SIWES course: paying does not register it.',
                                            'Sign in and register your SIWES course: paying does not register it.'),
           updated_by = '00000000-0000-0000-0000-000000000000', updated_office = 'bursar', updated_at = now()
     WHERE key = 'SIWES_FEE_PAID' AND email_body LIKE '%Sign in, open SIWES and register your SIWES course: paying does not register it.%';
    GET DIAGNOSTICS k = ROW_COUNT; n := n + k;
    RAISE NOTICE 'V777: the SIWES_FEE_PAID notice reworded in % place(s) (a template the Registry has re-worded is left as it is)', n;
END $v777$;


-- ── 6 · the gate, last: nothing is refused before the student can pay, and no money guard is blind to the link ──────────────────────

-- V777 (16): every SIWES course carries the SIWES registration fee — the entry trigger judges it where it returned for a student SIWES does not bind:
-- a SIWES course (catalogue.course.industrial_training, not ended) placed on the registration of a fee subject (undergraduate, in study, not CCE, not
-- postgraduate) in the session that is their current one is refused unless a SIWES payment stands (SIWES_UNPAID; SIWES_FEE_NOT_SET while the Bursary has
-- not published the fee; SIWES_NOT_IN_REACH where the programme carries none at the student's level), and, accepted, is written to
-- registration.siwes_course_entry on the payment that settles it, under the SIWES lock taken BEFORE the payment is read (V762's order: the student's row,
-- the advisory lock, then the rows). Not judged again: an entry that stands approved or moved to another class, and a proposal that finds its entry already
-- there; the old portal's loaders keep their override. The student SIWES binds (Second Semester, V752) is judged by V752's text, which is kept as it was
CREATE OR REPLACE FUNCTION registration.entry_siwes_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE r record; v_code text; v_siwes text; pd record; v_msg text; v_was boolean;
BEGIN
    IF NEW.status NOT IN ('REGISTERED', 'APPROVED') THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND OLD.status IN ('REGISTERED', 'APPROVED') AND NEW.offering_id = OLD.offering_id
       AND NOT (OLD.status = 'REGISTERED' AND NEW.status = 'APPROVED') THEN
        RETURN NEW;
    END IF;
    -- V777: the one SELECT also names the course and whether it is a SIWES course (a marked, not ended course of the catalogue)
    SELECT cr.student_id, cr.session, cr.semester, cr.level, o.course_code,
           coalesce(c.industrial_training AND c.state <> 'ENDED', false) AS siwes INTO r
      FROM registration.course_registration cr
      LEFT JOIN catalogue.offering o ON o.id = NEW.offering_id
      LEFT JOIN catalogue.course c ON c.code = o.course_code
     WHERE cr.id = NEW.registration_id;
    -- the student SIWES binds (a configured programme, the period not a draft, 300 Level, Second Semester): V752's rule, as it was, below
    IF r.semester IS NOT DISTINCT FROM 2 AND registration.siwes_applies(r.student_id, r.session) THEN
        IF current_setting('moaum.siwes_override', true) = 'on'
           AND EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = r.session AND a.state IN ('CLOSED', 'ARCHIVED')) THEN
            RETURN NEW;
        END IF;
        SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = NEW.offering_id;
        v_siwes := registration.siwes_course_for(r.student_id);
        -- the course a SIWES registration was made on stays the student's SIWES course, whatever the mapping says since
        IF (v_siwes IS NULL OR v_code IS DISTINCT FROM v_siwes)
           AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.student_id = r.student_id AND x.session = r.session AND x.offering_id = NEW.offering_id) THEN
            RAISE EXCEPTION 'SIWES_COURSE_ONLY: the Second Semester of % is the student''s SIWES (industrial training) semester; it holds %, nothing else (% refused)',
                r.session, coalesce('the SIWES course ' || v_siwes, 'the SIWES course alone, which the Academic Office has not yet set for the programme'), v_code
                USING ERRCODE = '23514', HINT = 'The SIWES course is registered on the SIWES page once its fee is paid; other courses wait for a later semester.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM finance.siwes_paid(r.student_id, r.session)) THEN
            RAISE EXCEPTION 'SIWES_UNPAID: the SIWES registration fee for % is not paid; % is registered once it is', r.session, v_code
                USING ERRCODE = '23514', HINT = 'Pay the SIWES registration fee on the SIWES page, then register the course.';
        END IF;
        RETURN NEW;
    END IF;
    -- ─ V777: every other SIWES course carries the same fee: one ₦4,000 for the session, covering every SIWES course the student registers in it —
    -- ─ either semester, either level of a carry-over. The student must pay before the course is placed, whatever the programme, level or semester
    IF NOT r.siwes THEN RETURN NEW; END IF;
    -- not judged again: an entry that stands and is approved, or its class moved (the link follows the class); a proposal (ON CONFLICT DO NOTHING
    -- fires this trigger too) whose entry is there already. An entry standing for a course that was not a SIWES course, now one, is judged as new
    IF TG_OP = 'UPDATE' AND OLD.status IN ('REGISTERED', 'APPROVED') THEN
        IF NEW.offering_id = OLD.offering_id THEN RETURN NEW; END IF;
        SELECT coalesce(k.industrial_training AND k.state <> 'ENDED', false) INTO v_was
          FROM catalogue.offering p JOIN catalogue.course k ON k.code = p.course_code WHERE p.id = OLD.offering_id;
        IF v_was THEN
            DELETE FROM registration.siwes_course_entry WHERE course_registration_id = NEW.registration_id AND offering_id = NEW.offering_id;
            UPDATE registration.siwes_course_entry SET offering_id = NEW.offering_id, course_code = r.course_code
             WHERE course_registration_id = NEW.registration_id AND offering_id = OLD.offering_id;
            RETURN NEW;
        END IF;
    END IF;
    IF TG_OP = 'INSERT' AND EXISTS (SELECT 1 FROM registration.entry x WHERE x.registration_id = NEW.registration_id AND x.offering_id = NEW.offering_id) THEN
        RETURN NEW;
    END IF;
    -- a student not judged (not a subject, or not this session the student's current one): nothing is asked
    IF NOT registration.siwes_fee_judged(r.student_id, r.session) THEN RETURN NEW; END IF;
    -- the registration's row first: the foreign key check of this very insert takes it (FOR KEY SHARE) at the end of the statement, and a door that
    -- holds it FOR UPDATE (student_add_other, student_reset, summer_materialize) would otherwise wait for it holding the SIWES lock another entry of the
    -- same registration took first, while that one waits here for the lock: a deadlock of two doors. Taken here, before any SIWES lock, every door
    -- takes the registration's row, then the student's, then the advisory lock
    PERFORM 1 FROM registration.course_registration WHERE id = NEW.registration_id FOR KEY SHARE;
    -- the SIWES lock first (the student's row, then the advisory lock, held to the end of the transaction), THEN the payment is read: a refund or
    -- a move of the payment approved at this instant waits for this registration, or this one sees it refused (V762's order)
    PERFORM finance.siwes_lock(r.student_id, r.session);
    SELECT * INTO pd FROM finance.siwes_paid(r.student_id, r.session);
    IF pd.reference_id IS NULL THEN
        -- the old portal's loaders (a result or a registration history is never refused) keep their override: the entry they place stands unlinked, on
        -- registration.siwes_entries_unpaid, and the fee is asked of the student; where the student HAS paid, the entry is accepted below and linked as any
        IF current_setting('moaum.siwes_override', true) = 'on' THEN RETURN NEW; END IF;
        v_msg := registration.siwes_fee_refusal(r.student_id, r.session, r.course_code);
        RAISE EXCEPTION '%', v_msg USING ERRCODE = '23514',
            HINT = CASE split_part(v_msg, ':', 1) WHEN 'SIWES_FEE_NOT_SET' THEN 'The Bursary states and publishes the fee on Fee Setup.'
                              WHEN 'SIWES_NOT_IN_REACH' THEN 'Your programme carries no SIWES course at your level; the Academic Office adds the course to the programme, then the SIWES registration fee is paid and the course registered.'
                              ELSE 'Pay the SIWES registration fee on the SIWES page, then register the course.' END;
    END IF;
    -- accepted: the registration stands on the payment that settles the fee (the money guards read it: finance.siwes_stands_on)
    INSERT INTO registration.siwes_course_entry (student_id, session, course_registration_id, offering_id, course_code, level, semester,
                                                 payment_reference_id, legacy_payment_id, registered_by, registered_office)
    VALUES (r.student_id, r.session, NEW.registration_id, NEW.offering_id, r.course_code, r.level, r.semester,
            CASE WHEN pd.source = 'PORTAL' THEN pd.reference_id END, CASE WHEN pd.source = 'OLD_PORTAL' THEN pd.reference_id END,
            nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''))
    ON CONFLICT (course_registration_id, offering_id) DO UPDATE
       SET student_id = EXCLUDED.student_id, session = EXCLUDED.session, course_code = EXCLUDED.course_code, level = EXCLUDED.level,
           semester = EXCLUDED.semester, payment_reference_id = EXCLUDED.payment_reference_id, legacy_payment_id = EXCLUDED.legacy_payment_id,
           registered_at = now(), registered_by = EXCLUDED.registered_by, registered_office = EXCLUDED.registered_office;
    RETURN NEW;
END $function$;

-- ── 7 · the link backfill: the entries that stand now are linked to the payment they stand on, once ────────────────────────────────────
/* The gate (section 6) writes a link row for every SIWES course entry it ACCEPTS. The entries that stand when this migration is deployed were
   never judged, so they have no row, and the money guards read only the link: the old fees reset (finance.reset_legacy_payments, which is run
   from time to time) would delete the old-portal SIWES payment a student paid for a course they hold, and the refund, correction, archive and
   never-received doors would not see it either. So, for every STANDING entry (not dropped or withdrawn) of a SIWES course (marked, not ended)
   on a registration of a student the gate judges (registration.siwes_fee_judged: an undergraduate in study, not CCE, the session being the
   student's current one) who has a SIWES payment standing for that session (finance.siwes_paid: the portal's or the old portal's, either
   semester), the link is written on the payment that settles the fee: the row the entry trigger would have written (the registration's level and
   semester, the migration as the actor), registered at the time the student added the entry where the entry records it, else now.
   · It writes no money row, no entry and no registration, and refuses nothing: a student not judged (CCE, postgraduate, not in study, another
     session) is skipped by the gate's own predicate; a payment that cannot be read is no payment.
   · Skipped too: an entry already linked (ON CONFLICT DO NOTHING: run again it changes nothing, and a link the gate wrote is never touched) and
     an entry V752's registration.siwes_registration holds (the SIWES semester has its link already; two would count the course twice).
   · Under the SIWES lock, the student's row then the advisory lock, taken BEFORE the payment is read (V762's order, the gate's): a refund
     approved at this instant waits for this migration or is seen by it. Students in ascending order; held to the end of the migration.
   · The students who hold an entry and have paid nothing are not linked now: their registrations stand, the SIWES page asks them the fee, the
     Bursary's list is registration.siwes_entries_unpaid; the entry is linked when their payment comes to stand (registration.siwes_link_held,
     called by finance.siwes_settling_follows_payment), or by the gate if they register the course again.
   · The per-student statement is registration.siwes_link_held (section 4), the one the payment trigger calls: the same predicates, one place. */
-- V777 link backfill: begin
DO $v777$
DECLARE s record; n int := 0; k int; v_students int := 0; v_unpaid int := 0;
BEGIN
    FOR s IN
        WITH held AS MATERIALIZED (
            SELECT DISTINCT cr.student_id, cr.session
              FROM registration.entry e
              JOIN registration.course_registration cr ON cr.id = e.registration_id
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training AND c.state <> 'ENDED'
             WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')
               AND NOT EXISTS (SELECT 1 FROM registration.siwes_course_entry x WHERE x.course_registration_id = e.registration_id AND x.offering_id = e.offering_id)
               AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.course_registration_id = e.registration_id AND x.offering_id = e.offering_id))
        SELECT h.student_id, h.session, EXISTS (SELECT 1 FROM finance.siwes_paid(h.student_id, h.session)) AS paid
          FROM held h
         WHERE registration.siwes_fee_judged(h.student_id, h.session)
         ORDER BY h.student_id, h.session
    LOOP
        IF NOT s.paid THEN v_unpaid := v_unpaid + 1; CONTINUE; END IF;
        PERFORM finance.siwes_lock(s.student_id, s.session);
        k := registration.siwes_link_held(s.student_id, s.session);
        n := n + k;
        IF k > 0 THEN v_students := v_students + 1; END IF;
    END LOOP;
    RAISE NOTICE 'V777: % SIWES course entr(y/ies) of % student(s) that stood before the fee was asked linked to the SIWES payment they stand on; % student(s) hold one with no SIWES payment (registration.siwes_entries_unpaid) and are not linked until they pay', n, v_students, v_unpaid;
END $v777$;
-- V777 link backfill: end

COMMIT;
