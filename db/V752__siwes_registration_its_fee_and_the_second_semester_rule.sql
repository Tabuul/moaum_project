-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V752 · SIWES registration, its fee and the Second Semester rule
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompt of 12 November 2026 (SIWES / Industrial Training) and its decisions of the same day:
--    · SIWES registration is at 300 Level, Second Semester only, for the programmes the Academic Office configures for a session. An
--      eligible student registers the programme's SIWES course and nothing else that semester, once a ₦4,000 SIWES registration fee
--      (the Bursary's, published, configurable) is paid through the existing gateways. First-semester and past registrations are left
--      as they are.
--    · V503's rule stays beside it: a programme not configured for the session keeps today's attachment semester exactly
--      (registration.siwes_units, the SIWES basis of the unit rule, REG_SIWES_UNITS, REG_SIWES_SEMESTER).
--    · School fees are still owed: the Second Semester's school fees are cleared as today (the registration's own gates run). The
--      ₦4,000 is a payment of its own: never a school-fee line, never counted with school fees or GST/EPS.
--    · An old-portal SIWES payment ("SIWES (legacy)", ₦4,000) confirmed for the session, of either semester, settles that session's
--      fee; those payments leave the category Other for the SIWES category.
--
--  Measured first on the live-shaped copy (lv571): V503 reads 12 attachment programme-semesters. 7 are at 300/2 (Biochemistry,
--  Computer Science, Biology, Chemistry, Physics, Plant Science, Zoology: 838 students at 300 Level); the four Communication
--  programmes are at 300/1 and Environmental Management & Toxicology at 400/2 (135 students): those five stay V503's, unconfigured.
--  1,606 old-portal SIWES payments stand for 2025/2026 (37 students paid twice). Computer Science and Biochemistry hold a BMAS and a
--  CCMAS SIWES code; Chemistry and Physics hold only a BMAS one while their 300 Level students are CCMAS (left unmapped and told).
--
--  Decided by the lead (said here and in docs/siwes-registration.md):
--    · Students of the Centre for Continuing Education, postgraduates and a student who has passed a SIWES course are not eligible.
--    · The registration is approved as it is made (AUTO): one fixed course, nothing for a Head of Department to choose. It stays an
--      ordinary registration (the V156 supervisors need an approved one) and is recorded in registration.siwes_registration, so the
--      lists label it SIWES.
--    · Paying does not register: the student registers the course once the payment is confirmed.
--    · A drawn reference keeps its amount until it expires or is renewed; a fee changed applies to new references.
--    · The assessment stays V156's (supervisor /40 + coordinator /60); no pass mark, grade or promotion rule is invented.
--    · A programme's SIWES course is a standing mapping (programme, curriculum → catalogue course), never per session; the
--      participation and the period are per session. No session is written in: the seed reads policy.university_current_session().
--
--  The reviews of the build (database and money, API, screens) answered here, before it shipped:
--    · The old fees history started over (finance.reset_legacy_payments) keeps an old-portal payment a SIWES registration was made on,
--      and counts it kept; it deleted it, and the registration with it.
--    · A payment refunded on the refund desk (approved or paid) no longer settles the fee (netted as the GST fee nets refunds); no refund
--      is raised or approved against the payment a standing SIWES registration was made on (REFUND_SIWES_REGISTERED).
--    · SIWES credits follow V742 and V751: settled by the Bursar only while the payment stands as the credit's SIWES payment
--      (SIWES_CREDIT_HELD), never the payment that now settles the fee or a registration stands on (SIWES_CREDIT_SETTLES), applied by
--      moving the payment, never by hand (SIWES_CREDIT_MOVE_IT), and reopened by the Bursar with a reason (finance.siwes_credit_reopen);
--      the move and archive refusals hold a settled credit's payment only while it stands there. When the payment that settled a fee
--      leaves it (moved or archived), the oldest open credit settles it instead and is recorded so; one that comes back where another
--      settles is a credit again.
--    · A cohort no mapping reaches is never held to a course it cannot register: while every curriculum is open (V590) a curriculum with
--      no SIWES course of its own reads the programme's other one, SIWES binds only a student with a live course mapped, and the period
--      does not open while a configured programme has 300 Level students no course reaches (SIWES_COURSE_MISSING).
--    · The published fee stays in force while a restatement waits for the Bursar: a statement is a draft beside it, publishing puts the
--      draft in force; Student Accounts states, never withdraws.
--    · Two SIWES payments confirmed at the same moment are decided one after the other (a lock on the student and session): one settles,
--      the other is a credit.
--    · The student's own doors drop and reset the ordinary Second Semester courses, never the SIWES course a SIWES registration holds
--      (SIWES_COURSE_KEPT, REG_RESET_SIWES); the eligibility says whether SIWES binds (applies); the Bursary's payments report totals what
--      settles apart from the rest.
--
--  The second round of reviews, answered here too:
--    · The refund desk and the SIWES credits never give one payment back twice, in either order: no refund is raised or approved on a
--      payment whose credit the Bursar recorded refunded (REFUND_SIWES_CREDIT_SETTLED), no credit is settled while a refund stands on its
--      payment (SIWES_CREDIT_REFUND_DESK), and a refund approved on a SIWES payment settles its credit itself ('Refunded on the refund
--      desk: …'); when the payment refunded settled the fee, the oldest open credit settles it now, as when it is moved or archived.
--    · The fee is all or nothing: a payment anything was given back on settles nothing.
--    · One test of a SIWES payment (finance.is_siwes_purpose: the portal's, and the old portal's "SIWES … (legacy)") wherever a payment is
--      judged one, so an old-portal credit is refunded or reopened by the Bursar like any other.
--    · A student who has paid or registered is never stranded: the mapping their SIWES course comes from is replaced, never taken away
--      (SIWES_COURSE_IN_USE), and they stay bound to SIWES if their course is ended (registering waits on SIWES_COURSE_MISSING).
--    · A carry-over or deferred course placed before SIWES bound the student waits for a later semester: the student drops it or a reset
--      clears it, an office drops it, while no SIWES registration stands there.
--    · A SIWES registration is never returned by a Head of Department (REG_RETURN_SIWES); the course it was made on stays the student's
--      SIWES course whatever the mapping says since (never listed as an ordinary course in the way).
--    · The payment that settles also follows a payment deleted (the old fees reset) or set back to unconfirmed, and a payment moved to a
--      student already paid is that student's credit, whatever credit it carried before.
--    · The Bursary's report totals what was given back apart (amountRefunded), and the credits list says what the Bursar can do with each.
--
--  The third round, answered here too:
--    · The old fees history started over keeps an old-portal payment whose SIWES credit the Bursar settled by hand (counted among those
--      kept), as it keeps one the refund desk refunded or a payment correction moved: the record that the Bursar gave it back is never
--      deleted with it and given back again. An open credit, or one the database settled itself, goes with its payment and the reload
--      makes it again (a row loaded under the wrong student is taken away by the reset, its credit with it).
--    · An old-portal SIWES payment never binds or locks a configuration by itself: a student whose programme has no live SIWES course
--      stays bound only by a portal payment or a SIWES registration; the old portal's payers are not "in use" (a programme added by mistake
--      is taken out again); a programme is added to a period no longer a draft only once its 300 Level cohort has a SIWES course
--      (SIWES_COURSE_MISSING). The old portal's payment still pays a bound student's fee (decision 4).
--    · An old-portal SIWES payment loaded (inserted confirmed, as the import and its reload do) comes to stand as any: it settles again
--      where a credit settled only in its absence, else it is the student's credit.
--    · SIWES_COURSE_KEPT is the student's own refusal: ICT Support and the Student edit drop the SIWES course of a registration made in
--      error (after which the fee may be refunded), and drop a course in the way of the SIWES course with no override (its words say it waits
--      for a later semester).
--    · The fee is all or nothing on the refund desk too: a SIWES payment is refunded whole or not at all (REFUND_SIWES_PART), and a credit
--      is recorded refunded only once the whole of it is.
--    · A standing SIWES registration stays approved (or locked): no door submits it again, makes it a draft or returns it (REG_STATUS_SIWES,
--      REG_RETURN_SIWES); the office's reset and drop take the SIWES course off first.
--    · The eligibility says whether the Second Semester school fees are cleared (semesterFees), by the tests the registration applies, and
--      canRegister waits on them.
--
--  The fourth round, answered here too:
--    · One rule for a student's second SIWES payment of a session, whenever it came: a SIWES credit (money owed back). The old portal's
--      SIWES payments already on record when V752 lands are credited at the end of this migration by the function the payment triggers
--      use (finance.siwes_comes_to_stand): the first confirmed settles, each later one is a credit — what the old fees history started
--      over and loaded again in date order makes. Measured on the live-shaped copy (lv726r): 20 student-sessions hold two old-portal
--      SIWES payments (11 a first- and a second-semester payment, 4 a whole-session and a first-semester one, 5 two second-semester
--      payments of one day and amount under two payment numbers): without this their second payments would be credits only after an
--      old fees reset and reload. Computed there (read only): 20 credits of ₦80,000 (17 of 2024/2025, 3 of 2025/2026), the 5 of one day
--      held for the Bursary's bank check.
--    · V561's standing rule (docs/old-fees-double-charges.md): an old-portal record that may be a bank double charge — another of the same
--      student, session, item, Lagos day and amount under another payment number, as finance.possible_double_charges lists it — is never
--      refunded until the Bursary has checked it with the bank: not on the refund desk (REFUND_SIWES_CHECK_BANK), not by the Bursar's
--      hand (SIWES_CREDIT_CHECK_BANK; the credits list says so in bank_check). Found received, it is refunded as any; found never
--      received, its withdrawal (V561, approved by a second officer) archives it for good (V670) and its credit with it. A SIWES
--      registration made on a payment that leaves follows the payment that settles the fee now.
--    · A SIWES course entered on a Second Semester registration an office had approved is stamped approved on the fee (AUTO, now, by
--      nobody), the status unchanged: the record never shows a Head of Department's approval of a course the Head never saw.
--
--  The fifth round, answered here too:
--    · V752 lands without holding up the portal. Round 4's file held every write to the payments, registrations, entries, students,
--      courses and classes for 13 to 20 s of its 15 to 21 s on the live-shaped copy (its keys and triggers took their locks at the start,
--      and the seed and the credit of the second payments ran under them). Now everything that only reads the portal, or writes V752's own
--      tables, comes first: the tables (their keys onto the portal's tables left for the end), the functions, the restated functions, the
--      notices and the seed. The locks that hold writers come last, in one short stretch (section 18): the keys onto the portal's tables,
--      the triggers on the payments, entries, registrations and refunds, then the credit of the second SIWES payments on record. Read
--      once those locks are held, the credit sees every payment committed before them; a payment written after them waits for the
--      commit and meets the triggers. None is missed.
--    · V561's test for one record (finance.double_charge_group): whether an old-portal record is a possible bank double charge is read
--      from the student's own payments by index, as finance.possible_double_charges forms its groups (the same exclusions), never from
--      the session's whole list. The Bursar's credits list no longer takes seconds for each credit waiting on the bank.
--    · The bank-check hold covers every way the money leaves or moves, the payment correction desk too (REALLOC_SIWES_CHECK_BANK). A
--      check that found a record never received holds every SIWES payment of its day until that record is withdrawn (archived): the
--      received one is released only then, and the one never received settles no fee meanwhile. A SIWES payment that a standing SIWES
--      registration rests on, the student holding no other for the session, is not withdrawn as never received
--      (PAY_NOT_RECEIVED_SIWES_REGISTERED): the registration is undone first.
--    · How a SIWES credit was settled is a column (finance.siwes_credit.settled_kind: SETTLES, MOVED, DESK_REFUND, HAND_REFUND), written by
--      what settles it and read wherever it matters (the old fees reset keeps a payment only for HAND_REFUND). The note is free text.
--    · SIWES binds only a student in study (ACTIVE or PROBATION), by the test the desk's roster and the eligibility apply.
--    · The seed maps each programme and curriculum to the industrial-training course its 300 Level students register in the attachment
--      semester today (V503), read from their Second Semester registrations: a LIVE course before any other, then the most recent
--      session, then the most students. The structure's course is mapped only where no registration speaks for a curriculum, and a
--      course not LIVE only where the programme has no LIVE SIWES course. On the live-shaped copy, CCMAS Biochemistry and BMAS Biology
--      map to BCH 300 and BIO 314, the LIVE courses their students registered. Round 4 read BCH 399 and BIO 300, still at the Board,
--      which nobody had registered.
--    · A SIWES course passed before is looked for among the SIWES courses the student registered (the published result, the costly read,
--      is asked of those alone): the desk's lists and statistics in under a second.
--
--  The sixth round, answered here too:
--    · A SIWES payment whose credit was refunded, by the Bursar's hand or on the refund desk, is not withdrawn as never received
--      (PAY_NOT_RECEIVED_SIWES_REFUNDED), as V561 refuses a school-fees record whose excess was decided and the archive desk a linked one:
--      the money given back stays on the books with the payment it was given back on.
--    · The Bursary's bank check changes what stands for a SIWES fee (a record found never received does not), so whenever a check is
--      recorded or changed, or a withdrawal as never received is raised, approved or rejected, the one rule is applied again to the
--      student's session (finance.siwes_stand_again): a record found never received that settled the fee leaves it (the oldest open credit
--      settles in its place, as on an archive), a record found received comes to stand again as the student's credit, a standing SIWES
--      registration follows the payment that settles. One payment settles, every other that stands is a credit, and no credit is listed
--      on a record the bank never received.
--    · V752 never makes the portal's writers queue behind it: the locks of the short stretch are taken without waiting, all at once, and
--      tried again a moment later while a write is open on any of them; after the deploy's lock_timeout it stops (V752_LOCKS_BUSY) and
--      the next deploy runs it.
--    · An old-portal SIWES payment written while V752 lands, its item text new, is never left under Other: the category memo is rebuilt
--      once the payments are locked (the seventh round's order, below).
--    · The SIWES page stays in a student's menu only while a SIWES of theirs stands (a registration, or a payment of a session SIWES
--      bound them in) or SIWES binds them now: a SIWES wholly undone leaves no menu item.
--    · The bank check's wait comes as a code beside its words (finance.siwes_bank_hold: PROPOSED, NOT_RECEIVED, NOT_RECEIVED_WAITING,
--      UNCHECKED), on the credits list and the payments report, so the screens follow the code: the record the bank received is never
--      marked as the one it never received.
--
--  The seventh round, answered here too:
--    · A record the bank check found never received stays so whatever day an old fees upload gives it afterwards: the finding is read
--      from the check that names the record (finance.double_charge_check.not_received), not from the check of the record's current Lagos
--      day and amount. An upload without payment numbers puts a record's day right (finance.import_legacy_payments); read by the day, the
--      record left its check, stood again beside the payment that settled in its place (two settling), and was refunded on the desk
--      though the bank never received it (V561).
--    · A SIWES credit the Bursar reopens is put under the one rule again (finance.siwes_stand_again): when the payment that settled the
--      fee was given back meanwhile, the reopened credit settles it (SETTLES) instead of the fee standing paid by an open credit offered
--      for refund.
--    · V752 holds no lock the Bursary's rules need while it waits for the locks of the short stretch: the SIWES payment purpose, category
--      and classification, whose V427 triggers rebuild the category and owner memos (a lock on every memo row until the commit), are
--      written inside the stretch, and the two memos are among the tables locked without waiting. Before, a Bursary change to a payment
--      category waited as long as V752 tried (13 s of a 15 s budget on a copy).
--    · The Bursary's SIWES payments report shows no bank-check hold on a payment given back (its credit refunded, or refunded on the
--      refund desk without a credit), as the credits list shows none on a refunded credit: the hold's "not refunded or moved" stood
--      beside "refunded" on the same row.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V752: SIWES registration, its fee and the Second Semester rule', true);

-- ── 1 · the period and the programmes of a session; the course of a programme ───────────────────────────────────────────────────
-- V752's tables are made here without their keys onto the portal's tables (the sessions, programmes, courses, classes, students,
-- payments and registrations): a key takes a lock on the table it points at that holds its writers until the commit, so the keys are
-- added in section 18, with the triggers, in the short stretch at the end.
CREATE TABLE registration.siwes_period (
    session             text PRIMARY KEY,                   -- policy.academic_session (section 18)
    state               text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'OPEN', 'CLOSED')),
    level               integer NOT NULL DEFAULT 300 CHECK (level = 300),
    semester            integer NOT NULL DEFAULT 2 CHECK (semester = 2),
    registration_opens  date,
    registration_closes date,
    training_starts     date,
    training_ends       date,             -- the expected completion; never assumed the same every session
    duration_months     integer NOT NULL DEFAULT 6 CHECK (duration_months BETWEEN 1 AND 12),
    note                text,
    set_by              uuid NOT NULL,
    set_office          text NOT NULL,
    set_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_siwes_registration_dates CHECK (registration_closes IS NULL OR registration_opens IS NULL OR registration_closes >= registration_opens),
    CONSTRAINT ck_siwes_training_dates CHECK (training_ends IS NULL OR training_starts IS NULL OR training_ends > training_starts),
    CONSTRAINT ck_siwes_open_dated CHECK (state <> 'OPEN' OR (registration_opens IS NOT NULL AND registration_closes IS NOT NULL
                                                              AND training_starts IS NOT NULL AND training_ends IS NOT NULL))
);
COMMENT ON TABLE registration.siwes_period IS
  'V752: SIWES registration of a session — 300 Level, Second Semester — its state (a DRAFT binds nobody), its registration window and its training period. Set by the Academic Office.';
SELECT audit.attach('registration.siwes_period');

CREATE TABLE registration.siwes_programme (
    session        text NOT NULL REFERENCES registration.siwes_period(session) ON DELETE CASCADE,
    programme_code text NOT NULL,                              -- ref.programme (section 18)
    added_by       uuid NOT NULL,
    added_office   text NOT NULL,
    added_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session, programme_code)
);
CREATE INDEX ix_siwes_programme_programme ON registration.siwes_programme (programme_code);
COMMENT ON TABLE registration.siwes_programme IS
  'V752: a programme taking part in SIWES registration in a session, as the Academic Office configures it. A programme not listed keeps V503''s attachment semester.';
SELECT audit.attach('registration.siwes_programme');

CREATE TABLE registration.siwes_course (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    programme_code text NOT NULL,                              -- ref.programme (section 18)
    curriculum     text CHECK (curriculum IS NULL OR curriculum IN ('CCMAS', 'BMAS')),   -- NULL: every curriculum without its own
    course_code    text NOT NULL,                              -- catalogue.course (section 18)
    set_by         uuid NOT NULL,
    set_office     text NOT NULL,
    set_at         timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_siwes_course ON registration.siwes_course (programme_code, (coalesce(curriculum, '')));
CREATE INDEX ix_siwes_course_course ON registration.siwes_course (course_code);
COMMENT ON TABLE registration.siwes_course IS
  'V752: the SIWES course of a programme, for a curriculum (CCMAS, BMAS) or for every curriculum: an existing catalogue course (a correction or a merge of its code follows it), standing across sessions — courses are never tied to sessions.';
SELECT audit.attach('registration.siwes_course');

/* SIWES is for undergraduates: a postgraduate programme is neither configured nor mapped */
CREATE FUNCTION registration.siwes_programme_undergraduate() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = NEW.programme_code AND p.category = 'UNDER GRADUATE') THEN
        RAISE EXCEPTION 'SIWES_NOT_UNDERGRADUATE: % is not an undergraduate programme; SIWES registration is for undergraduates', NEW.programme_code
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_siwes_programme_undergraduate BEFORE INSERT OR UPDATE OF programme_code ON registration.siwes_programme
    FOR EACH ROW EXECUTE FUNCTION registration.siwes_programme_undergraduate();
CREATE TRIGGER trg_siwes_course_undergraduate BEFORE INSERT OR UPDATE OF programme_code ON registration.siwes_course
    FOR EACH ROW EXECUTE FUNCTION registration.siwes_programme_undergraduate();

-- a programme merged into another (V574): its participation and its SIWES course move, unless the kept programme holds its own
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('registration.siwes_programme', 'programme_code', 'MOVE_UNLESS_HELD', 'a programme taking part in SIWES registration in a session (V752)'),
    ('registration.siwes_course', 'programme_code', 'MOVE_UNLESS_HELD', 'the SIWES course of a programme (V752)')
ON CONFLICT (tab, col) DO NOTHING;

-- ── 2 · the fee: the Bursary's, stated and published; its history; money received twice ──────────────────────────────────────────
CREATE TABLE finance.siwes_fee (
    session          text PRIMARY KEY,                         -- policy.academic_session (section 18)
    amount           numeric(12,2) NOT NULL DEFAULT 4000 CHECK (amount > 0),   -- the fee in force once PUBLISHED; before that, the draft's
    state            text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'PUBLISHED')),
    note             text,
    stated_by        uuid NOT NULL,
    stated_office    text NOT NULL,
    stated_at        timestamptz NOT NULL DEFAULT now(),
    published_by     uuid,
    published_office text,
    published_at     timestamptz,
    -- a restatement waiting for the Bursar: the published figure stays in force until it is published (Student Accounts states,
    -- never withdraws)
    draft_amount     numeric(12,2) CHECK (draft_amount > 0),
    draft_note       text,
    drafted_by       uuid,
    drafted_office   text,
    drafted_at       timestamptz,
    CONSTRAINT ck_siwes_fee_published CHECK (state = 'DRAFT' OR published_at IS NOT NULL),
    CONSTRAINT ck_siwes_fee_draft CHECK ((draft_amount IS NULL) = (drafted_at IS NULL) AND (draft_amount IS NULL) = (drafted_by IS NULL))
);
COMMENT ON TABLE finance.siwes_fee IS
  'V752: the SIWES registration fee of a session, as the Bursary states it (bursar, studentaccounts, super) and publishes it (bursar, super). A statement is a draft (draft_*): a fee never published is its draft until published; a published fee stays in force, as published, while a restatement waits, and publishing copies the draft over it. A reference keeps the figure it was drawn at. Never a school-fee line.';
SELECT audit.attach('finance.siwes_fee');

CREATE TABLE finance.siwes_fee_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text NOT NULL,                              -- policy.academic_session (section 18)
    action         text NOT NULL CHECK (action IN ('STATED', 'PUBLISHED')),
    amount         numeric(12,2) NOT NULL,
    was_amount     numeric(12,2),
    was_state      text,
    note           text,
    changed_by     uuid NOT NULL,
    changed_office text NOT NULL,
    changed_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_siwes_fee_change_session ON finance.siwes_fee_change (session, changed_at);
COMMENT ON TABLE finance.siwes_fee_change IS 'V752: every statement and publication of a SIWES registration fee, as it was made.';
SELECT audit.attach('finance.siwes_fee_change');

/* every statement and publication of a SIWES fee is kept, whoever writes it: a statement as the draft it makes (was: the figure then in
   force, or the draft before it), a publication as the figure it puts in force */
CREATE FUNCTION finance.siwes_fee_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.draft_amount IS NOT NULL
       AND (TG_OP = 'INSERT' OR (NEW.draft_amount, NEW.draft_note, NEW.drafted_by, NEW.drafted_at) IS DISTINCT FROM (OLD.draft_amount, OLD.draft_note, OLD.drafted_by, OLD.drafted_at)) THEN
        INSERT INTO finance.siwes_fee_change (session, action, amount, was_amount, was_state, note, changed_by, changed_office)
        VALUES (NEW.session, 'STATED', NEW.draft_amount,
                CASE WHEN TG_OP = 'UPDATE' THEN coalesce(CASE WHEN OLD.state = 'PUBLISHED' THEN OLD.amount END, OLD.draft_amount, OLD.amount) END,
                CASE WHEN TG_OP = 'UPDATE' THEN OLD.state END, NEW.draft_note, NEW.drafted_by, NEW.drafted_office);
    END IF;
    -- published: a draft put in force (published_at alone may not change within one transaction)
    IF NEW.state = 'PUBLISHED' AND (TG_OP = 'INSERT' OR OLD.state <> 'PUBLISHED' OR (OLD.draft_amount IS NOT NULL AND NEW.draft_amount IS NULL)
                                    OR NEW.published_at IS DISTINCT FROM OLD.published_at) THEN
        INSERT INTO finance.siwes_fee_change (session, action, amount, was_amount, was_state, note, changed_by, changed_office)
        VALUES (NEW.session, 'PUBLISHED', NEW.amount, CASE WHEN TG_OP = 'UPDATE' AND OLD.state = 'PUBLISHED' THEN OLD.amount END,
                CASE WHEN TG_OP = 'UPDATE' THEN OLD.state END, NEW.note, coalesce(NEW.published_by, NEW.stated_by), coalesce(NEW.published_office, NEW.stated_office));
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_siwes_fee_history AFTER INSERT OR UPDATE ON finance.siwes_fee FOR EACH ROW EXECUTE FUNCTION finance.siwes_fee_history();

CREATE TABLE finance.siwes_credit (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id    uuid NOT NULL,                               -- people.student (section 18)
    session       text NOT NULL,                               -- policy.academic_session (section 18)
    reference_id  uuid NOT NULL UNIQUE,                        -- finance.payment_reference (section 18)
    amount        numeric(12,2) NOT NULL CHECK (amount > 0),
    reason        text NOT NULL,
    state         text NOT NULL DEFAULT 'OPEN' CHECK (state IN ('OPEN', 'APPLIED', 'REFUNDED')),
    created_at    timestamptz NOT NULL DEFAULT now(),
    settled_at    timestamptz,
    settled_by    uuid,
    settled_note  text,                                        -- free text: what the settling said, never read back
    -- how it was settled, written by what settled it: SETTLES (it settles the fee in another payment's absence), MOVED (a payment
    -- correction moved its payment), DESK_REFUND (a refund approved on the refund desk), HAND_REFUND (the Bursar recorded it refunded)
    settled_kind  text,
    CONSTRAINT ck_siwes_credit_settled CHECK (state = 'OPEN' OR (settled_at IS NOT NULL AND nullif(btrim(settled_note), '') IS NOT NULL)),
    CONSTRAINT ck_siwes_credit_kind CHECK ((state = 'OPEN' AND settled_kind IS NULL)
                                           OR (state = 'APPLIED' AND settled_kind IN ('SETTLES', 'MOVED'))
                                           OR (state = 'REFUNDED' AND settled_kind IN ('DESK_REFUND', 'HAND_REFUND')))
);
CREATE INDEX ix_siwes_credit_session ON finance.siwes_credit (session, state);
COMMENT ON TABLE finance.siwes_credit IS
  'V752: a SIWES payment confirmed for a session whose SIWES fee another payment had already settled — never lost, never applied twice: the Bursary refunds it or moves its payment. settled_kind says how it was settled (SETTLES, MOVED, DESK_REFUND, HAND_REFUND), written by what settled it; settled_note is free text.';
SELECT audit.attach('finance.siwes_credit');

-- ── 3 · the registration made ────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE registration.siwes_registration (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id             uuid NOT NULL,                      -- people.student (section 18, as every key below)
    session                text NOT NULL,                      -- policy.academic_session
    level                  integer NOT NULL DEFAULT 300,
    semester               integer NOT NULL DEFAULT 2 CHECK (semester = 2),
    course_registration_id uuid NOT NULL,                      -- registration.course_registration
    offering_id            uuid NOT NULL,                      -- catalogue.offering: the entry is (course_registration_id, offering_id)
    course_code            text NOT NULL,                      -- catalogue.course
    payment_reference_id   uuid,                               -- finance.payment_reference: the portal's SIWES payment, or
    legacy_payment_id      uuid,                               -- the old portal's, whichever paid
    registered_at          timestamptz NOT NULL DEFAULT now(),
    registered_by          uuid,
    registered_office      text,
    CONSTRAINT uq_siwes_registration UNIQUE (student_id, session),
    CONSTRAINT ck_siwes_registration_paid CHECK (num_nonnulls(payment_reference_id, legacy_payment_id) = 1)
);
CREATE INDEX ix_siwes_registration_registration ON registration.siwes_registration (course_registration_id);
CREATE INDEX ix_siwes_registration_session ON registration.siwes_registration (session);
-- the payment a registration stands on is read by the payment desks (moves, archive, refunds, the old fees reset)
CREATE INDEX ix_siwes_registration_payment ON registration.siwes_registration (payment_reference_id) WHERE payment_reference_id IS NOT NULL;
CREATE INDEX ix_siwes_registration_legacy_payment ON registration.siwes_registration (legacy_payment_id) WHERE legacy_payment_id IS NOT NULL;
COMMENT ON TABLE registration.siwes_registration IS
  'V752: a student''s SIWES registration of a session: the Second Semester registration and the SIWES course entry it made, and the payment that settled the fee. The registration itself stays an ordinary one (history, results, supervisors); this row labels it SIWES.';
SELECT audit.attach('registration.siwes_registration');

-- ── 4 · who SIWES applies to ─────────────────────────────────────────────────────────────────────────────────────────────────────
/* the SIWES course a student of a programme and curriculum registers: the programme's course for that curriculum, else the one for
   every curriculum; a student whose curriculum is not recorded reads the one for every curriculum, else CCMAS's, else BMAS's. While
   every curriculum's courses are open (registration.curriculum_open(), on since V590) a curriculum with no mapping of its own reads the
   programme's other one too — as V503's attachment semester offers it (Chemistry's and Physics's CCMAS students hold a BMAS code) */
CREATE FUNCTION registration.siwes_course_of(p_programme text, p_curriculum text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT sc.course_code
      FROM registration.siwes_course sc
     WHERE sc.programme_code = p_programme
       AND (sc.curriculum IS NULL OR p_curriculum IS NULL OR sc.curriculum = p_curriculum OR registration.curriculum_open())
     ORDER BY (sc.curriculum IS NOT DISTINCT FROM p_curriculum) DESC, (sc.curriculum IS NULL) DESC, sc.curriculum DESC
     LIMIT 1;
$$;

CREATE FUNCTION registration.siwes_course_for(p_student uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT registration.siwes_course_of(s.programme_code, s.curriculum_version) FROM people.student s WHERE s.id = p_student;
$$;
COMMENT ON FUNCTION registration.siwes_course_for(uuid) IS
  'V752: the code of the SIWES course of the student''s programme and curriculum (registration.siwes_course), or NULL when the Academic Office has set none.';

/* a student's level in a session, as SIWES reads it: the operational level in the student's current session, the session's own level
   (people.level_in, its Second Semester first) in any other */
CREATE FUNCTION registration.siwes_level(p_student uuid, p_session text) RETURNS integer LANGUAGE sql STABLE COST 1000 AS $$
    SELECT CASE WHEN p_session IS NOT DISTINCT FROM people.student_current_session(s.id) THEN s.current_level
                ELSE people.level_in(s.id, p_session, 2) END
      FROM people.student s WHERE s.id = p_student;
$$;

/* the students, of those named, who passed a SIWES course before the session: the programme's SIWES course (of any curriculum) or any
   industrial-training course, with a published pass. Such a student is not held to SIWES again. The one rule, for one student
   (registration.siwes_passed) or for the desk's whole roster at once. The SIWES courses the students registered are found first (OFFSET
   0 keeps them apart): the published result (assessment.course_final), the costly read, is asked of those alone, never of every course
   a student ever registered */
CREATE FUNCTION registration.siwes_passed_among(p_session text, p_students uuid[]) RETURNS TABLE(student_id uuid) LANGUAGE sql STABLE AS $$
    SELECT DISTINCT k.student_id
      FROM (SELECT s.id AS student_id, o.id AS offering_id
              FROM people.student s
              JOIN registration.course_registration r ON r.student_id = s.id AND r.status IN ('APPROVED', 'LOCKED') AND r.session < p_session
              JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED', 'APPROVED')
              JOIN catalogue.offering o ON o.id = e.offering_id
              JOIN catalogue.course c ON c.code = o.course_code
             WHERE s.id = ANY (p_students)
               AND (c.industrial_training OR EXISTS (SELECT 1 FROM registration.siwes_course sc WHERE sc.programme_code = s.programme_code AND sc.course_code = c.code))
            OFFSET 0) k
     WHERE EXISTS (SELECT 1 FROM assessment.course_final(k.student_id, k.offering_id) cf WHERE cf.stage = 'PUBLISHED' AND cf.outcome = 'GRADED' AND cf.points > 0);
$$;

/* a SIWES course passed before the session, for one student (registration.siwes_passed_among) */
CREATE FUNCTION registration.siwes_passed(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE COST 10000 AS $$
    SELECT EXISTS (SELECT 1 FROM registration.siwes_passed_among(p_session, ARRAY[p_student]));
$$;

/* one test of a SIWES payment, wherever a payment is judged one: the portal's SIWES registration fee, or the old portal's SIWES payment as
   its import names it (finance.import_legacy_payments: '<the old portal's item> (legacy)[ · semester n]', the item starting "SIWES") */
CREATE FUNCTION finance.is_siwes_purpose(p_purpose text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(p_purpose LIKE 'SIWES registration fee%' OR (p_purpose ~* '^siwes' AND p_purpose LIKE '%(legacy)%'), false);
$$;
COMMENT ON FUNCTION finance.is_siwes_purpose(text) IS
  'V752: whether a payment''s purpose is a SIWES payment — the portal''s ''SIWES registration fee <session>'' or the old portal''s ''SIWES… (legacy)[ · semester n]''. The one test every SIWES reader, refusal and trigger applies.';

/* an old-portal record the Bursary's bank check found never received (V561): a NOT_RECEIVED check names it (finance.double_charge_check
   .not_received holds the references the bank never received). It waits to be withdrawn; meanwhile it does not stand for the SIWES fee
   (finance.siwes_standing) and its credit, if any, waits off the credits list. Read from the check that NAMES the record, never from the
   check of the record's current Lagos day and amount: an old fees upload without payment numbers puts a record's day right
   (finance.import_legacy_payments), and the finding follows the record wherever its day goes (by the student, the check's key leading
   with it). The one test, wherever asked */
CREATE FUNCTION finance.siwes_found_not_received(p_payment uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM finance.payment_reference r
                     JOIN finance.double_charge_check k ON k.student_id = r.student_id AND r.reference = ANY (k.not_received)
                    WHERE r.id = p_payment AND r.channel = 'Legacy' AND k.verdict = 'NOT_RECEIVED');
$$;

/* every SIWES payment of a student's session that stands: confirmed, a SIWES purpose (the portal's, or the old portal's "SIWES
   (legacy)" of either semester), not archived, nothing given back on it — the fee is all or nothing, so a payment the refund desk
   refunded any of (approved or paid, finance.gst_refunded) settles nothing, nor one whose SIWES credit was refunded — and not an
   old-portal record the Bursary's bank check found never received (finance.siwes_found_not_received: it waits to be withdrawn and
   settles no fee meanwhile), with whether it is an open credit and whether a SIWES registration that stands (its course not dropped)
   was made on it */
CREATE FUNCTION finance.siwes_standing(p_student uuid, p_session text)
RETURNS TABLE(reference_id uuid, reference text, amount numeric, receipt_no text, confirmed_at timestamptz, channel text, source text,
              open_credit boolean, registered boolean)
LANGUAGE sql STABLE AS $$
    SELECT r.id, r.reference, r.amount, r.receipt_no, r.confirmed_at, r.channel,
           CASE WHEN r.purpose LIKE 'SIWES registration fee%' THEN 'PORTAL' ELSE 'OLD_PORTAL' END,
           EXISTS (SELECT 1 FROM finance.siwes_credit c WHERE c.reference_id = r.id AND c.state = 'OPEN'),
           EXISTS (SELECT 1 FROM registration.siwes_registration x
                     JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                              AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                    WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id) AND x.student_id = r.student_id AND x.session = r.session)
      FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
       AND finance.is_siwes_purpose(r.purpose)
       AND finance.gst_refunded(r.reference) = 0
       AND NOT EXISTS (SELECT 1 FROM finance.siwes_credit c WHERE c.reference_id = r.id AND c.state = 'REFUNDED')
       AND NOT (r.channel = 'Legacy' AND finance.siwes_found_not_received(r.id));
$$;
COMMENT ON FUNCTION finance.siwes_standing(uuid, text) IS
  'V752: the SIWES payments of a student''s session that stand — confirmed, not archived, nothing refunded on the refund desk (approved or paid: the fee is all or nothing), no SIWES credit of it refunded, not an old-portal record the bank check found never received — each marked an open credit or not, and whether a standing SIWES registration was made on it.';

/* a SIWES registration stands for the student's session: made, and its SIWES course not dropped */
CREATE FUNCTION registration.siwes_registered(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM registration.siwes_registration x
                     JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                              AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                    WHERE x.student_id = p_student AND x.session = p_session);
$$;

/* THE predicate every registration reader and the entry trigger read: SIWES binds the student's Second Semester of the session — a
   period set for the session and no longer a draft, the student's programme configured for it, a SIWES course the student can
   register (mapped and not ended), the student at 300 Level in the session, an undergraduate, not of the Centre for Continuing
   Education, not one who has passed SIWES. False for everyone else: V503's attachment semester then stands as before — a cohort no
   mapping reaches is never held to a course it cannot register. A student who has paid on the portal (a portal SIWES payment that
   stands) or registered SIWES for the session stays bound whatever became of the course since (ended, its mapping changed): money paid
   under this configuration is never stranded in V503's semester; registering waits for a live course (SIWES_COURSE_MISSING). An
   old-portal payment does not hold a student bound with no course: it was paid before the programme was configured (a programme added
   by mistake would bind its old-portal payers to a course none can register); it still pays a bound student's fee (finance.siwes_paid).
   Only a student in study (ACTIVE or PROBATION) is bound, by the test the desk's roster and the eligibility (NOT_IN_STUDY) apply: a
   deferred, withdrawn or graduated student is not. */
CREATE FUNCTION registration.siwes_applies(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1
          FROM people.student s
          JOIN registration.siwes_programme sp ON sp.session = p_session AND sp.programme_code = s.programme_code
          JOIN registration.siwes_period p ON p.session = sp.session AND p.state <> 'DRAFT'
          JOIN ref.programme pr ON pr.code = s.programme_code
         WHERE s.id = p_student AND s.status IN ('ACTIVE', 'PROBATION')
           AND pr.category = 'UNDER GRADUATE' AND NOT people.is_postgraduate(s.entry_mode, pr.category) AND s.entry_mode <> 'CCE'
           AND registration.siwes_level(s.id, p_session) = p.level
           AND NOT registration.siwes_passed(s.id, p_session)
           AND (EXISTS (SELECT 1 FROM catalogue.course c
                         WHERE c.code = registration.siwes_course_of(s.programme_code, s.curriculum_version) AND c.state <> 'ENDED')
                OR registration.siwes_registered(s.id, p_session)
                OR EXISTS (SELECT 1 FROM finance.siwes_standing(s.id, p_session) x WHERE x.source = 'PORTAL')));
$$;
COMMENT ON FUNCTION registration.siwes_applies(uuid, text) IS
  'V752: SIWES binds the student''s Second Semester of the session — a student in study (ACTIVE or PROBATION), a period not in draft, the programme configured for the session, a live SIWES course mapped for the student''s programme and curriculum (or a portal SIWES payment that stands or a SIWES registration made: a student who paid on the portal or registered stays bound; an old-portal payment alone does not), 300 Level in the session (the operational level in the current session, people.level_in otherwise), an undergraduate, not CCE, no SIWES course passed before. The menu, the course check, the unit rule, the submission, the gate, the support checks and the entry trigger read it first; a student it does not bind keeps V503''s attachment semester.';

/* a Second Semester SIWES binds, with no SIWES registration made in it yet: the carry-overs and deferred courses placed on it before SIWES
   bound the student (a draft saved while the period was a draft, a level corrected, a programme added) wait for a later semester — the
   student drops them or a reset clears them, an office drops them — so the SIWES course can be registered alone */
CREATE FUNCTION registration.siwes_sheds(p_student uuid, p_session text, p_semester integer) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN p_semester = 2 THEN registration.siwes_applies(p_student, p_session) AND NOT registration.siwes_registered(p_student, p_session)
                ELSE false END;
$$;
COMMENT ON FUNCTION registration.siwes_sheds(uuid, text, integer) IS
  'V752: the semester is a Second Semester SIWES binds with no SIWES registration standing in it: its carry-over and deferred entries wait for a later semester (registration.student_drop, student_reset and support_drop_checks let them go).';

/* the cohorts of a session's configured programmes that no SIWES course reaches: their 300 Level students in study (undergraduates,
   not CCE, SIWES not passed) whose programme and curriculum map to no live course. SIWES does not bind them (V503 stands); the period is
   not opened while any remain (registration.siwes_set_period) */
CREATE FUNCTION registration.siwes_unmapped(p_session text)
RETURNS TABLE(programme_code text, programme text, curriculum text, students bigint) LANGUAGE sql STABLE AS $$
    SELECT p.code, p.name, s.curriculum_version, count(*)
      FROM registration.siwes_programme sp
      JOIN ref.programme p ON p.code = sp.programme_code
      JOIN people.student s ON s.programme_code = sp.programme_code
     WHERE sp.session = p_session AND s.status IN ('ACTIVE', 'PROBATION') AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND NOT people.is_postgraduate(s.entry_mode, p.category)
       AND NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = registration.siwes_course_of(s.programme_code, s.curriculum_version) AND c.state <> 'ENDED')
       AND registration.siwes_level(s.id, p_session) = 300
       AND NOT registration.siwes_passed(s.id, p_session)
     GROUP BY p.code, p.name, s.curriculum_version;
$$;

/* the session's registration window is open today (Lagos) */
CREATE FUNCTION registration.siwes_registration_open(p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.state = 'OPEN' AND (now() AT TIME ZONE 'Africa/Lagos')::date BETWEEN p.registration_opens AND p.registration_closes
                       FROM registration.siwes_period p WHERE p.session = p_session), false);
$$;

/* why a student is not eligible for SIWES registration of a session (empty: eligible), the student's level in the session and whether
   a SIWES course was passed before given (the desk's roster reads them for its whole population at once) */
CREATE FUNCTION registration.siwes_reasons_of(p_student uuid, p_session text, p_level integer, p_passed boolean) RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT array_remove(ARRAY[
               CASE WHEN pr.category IS DISTINCT FROM 'UNDER GRADUATE' OR people.is_postgraduate(s.entry_mode, pr.category) THEN 'NOT_UNDERGRADUATE' END,
               CASE WHEN s.entry_mode = 'CCE' THEN 'CCE' END,
               CASE WHEN s.status NOT IN ('ACTIVE', 'PROBATION') THEN 'NOT_IN_STUDY' END,
               CASE WHEN p_level IS DISTINCT FROM 300 THEN 'NOT_300_LEVEL' END,
               CASE WHEN NOT EXISTS (SELECT 1 FROM registration.siwes_programme sp WHERE sp.session = p_session AND sp.programme_code = s.programme_code)
                    THEN 'NOT_CONFIGURED' END,
               CASE WHEN NOT EXISTS (SELECT 1 FROM registration.siwes_period p WHERE p.session = p_session AND p.state <> 'DRAFT') THEN 'NO_PERIOD' END,
               CASE WHEN NOT EXISTS (SELECT 1 FROM catalogue.course c WHERE c.code = registration.siwes_course_of(s.programme_code, s.curriculum_version)
                                        AND c.state <> 'ENDED') THEN 'NO_COURSE' END,
               CASE WHEN p_passed THEN 'ALREADY_PASSED' END], NULL)
      FROM people.student s LEFT JOIN ref.programme pr ON pr.code = s.programme_code
     WHERE s.id = p_student;
$$;

/* why a student is not eligible for SIWES registration of a session (empty: eligible) */
CREATE FUNCTION registration.siwes_reasons(p_student uuid, p_session text) RETURNS text[] LANGUAGE sql STABLE AS $$
    SELECT registration.siwes_reasons_of(p_student, p_session, registration.siwes_level(p_student, p_session), registration.siwes_passed(p_student, p_session));
$$;

CREATE FUNCTION registration.siwes_eligible(p_student uuid, p_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce(cardinality(registration.siwes_reasons(p_student, p_session)) = 0, false);
$$;

/* the reasons in words, for a refusal */
CREATE FUNCTION registration.siwes_reason_words(p_reasons text[]) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(string_agg(CASE x
               WHEN 'NOT_UNDERGRADUATE' THEN 'SIWES registration is for undergraduates'
               WHEN 'CCE' THEN 'students of the Centre for Continuing Education do not register SIWES here'
               WHEN 'NOT_IN_STUDY' THEN 'the student is not in study'
               WHEN 'NOT_300_LEVEL' THEN 'SIWES is registered at 300 Level'
               WHEN 'NOT_CONFIGURED' THEN 'the programme does not take part in SIWES registration this session'
               WHEN 'NO_PERIOD' THEN 'SIWES registration is not set for the session'
               WHEN 'NO_COURSE' THEN 'the programme''s SIWES course is not set'
               WHEN 'ALREADY_PASSED' THEN 'a SIWES course is already passed'
               ELSE lower(replace(x, '_', ' ')) END, '; ' ORDER BY i), 'not eligible')
      FROM unnest(p_reasons) WITH ORDINALITY u(x, i);
$$;

-- ── 5 · the money: the fee in force, the payment that settles it ────────────────────────────────────────────────────────────────
/* the published SIWES fee of a session, or NULL */
CREATE FUNCTION finance.siwes_fee_for(p_session text) RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT f.amount FROM finance.siwes_fee f WHERE f.session = p_session AND f.state = 'PUBLISHED';
$$;

/* the payment that settles a student's SIWES fee of a session: of the payments that stand, the one a standing registration was made
   on, else one that is not an open credit (the portal's before the old portal's, the first confirmed — by its reference when two share
   a moment, as the old portal's of one day do); an open credit settles only when nothing else stands; none: not paid */
CREATE FUNCTION finance.siwes_paid(p_student uuid, p_session text)
RETURNS TABLE(reference_id uuid, reference text, amount numeric, receipt_no text, confirmed_at timestamptz, channel text, source text)
LANGUAGE sql STABLE AS $$
    SELECT x.reference_id, x.reference, x.amount, x.receipt_no, x.confirmed_at, x.channel, x.source
      FROM finance.siwes_standing(p_student, p_session) x
     ORDER BY x.registered DESC, x.open_credit, (x.source = 'PORTAL') DESC, x.confirmed_at, x.reference
     LIMIT 1;
$$;
COMMENT ON FUNCTION finance.siwes_paid(uuid, text) IS
  'V752: the payment settling a student''s SIWES fee of a session — of the SIWES payments that stand (finance.siwes_standing: archived and refunded payments do not count), the one a standing SIWES registration was made on, else a confirmed SIWES registration fee reference of the session, else a confirmed old-portal SIWES payment of the session (either semester), an open credit last; none when not paid.';

/* V561's group of one old-portal record (docs/old-fees-double-charges.md), read for that record alone: the old portal's records of the
   student, session, item, Lagos day and amount (to the naira), confirmed and not archived, as finance.possible_double_charges forms its
   groups — a record holding several school-fees payments left out, and each record under at most one payment number — when there are
   two or more of them under two or more payment numbers; NULL otherwise (the record is then not a possible bank double charge). The
   very rule of V561's list, read through the student's own payments by index (ix_pref_student, ix_legacy_payref_reference) instead of
   the session's whole list: the credits list, the refund desk and the payment correction desk ask it of one payment at a time. */
CREATE FUNCTION finance.double_charge_group(p_payment uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
    WITH me AS (
        SELECT r.student_id, r.session, r.purpose, round(r.amount) AS amt, (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date AS day, r.reference
          FROM finance.payment_reference r
         WHERE r.id = p_payment AND r.channel = 'Legacy' AND r.reference LIKE 'MOAUM-LEG-%' AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND coalesce(r.note, '') !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'),
    grp AS (
        SELECT x.reference, k.payref
          FROM me
          JOIN finance.payment_reference x ON x.student_id = me.student_id AND x.session = me.session AND x.purpose = me.purpose
          LEFT JOIN LATERAL (SELECT min(p.payref) AS payref, count(*) AS n FROM finance.legacy_payref p WHERE p.reference = x.reference) k ON true
         WHERE x.channel = 'Legacy' AND x.reference LIKE 'MOAUM-LEG-%' AND x.confirmed_at IS NOT NULL AND x.archived_at IS NULL
           AND coalesce(x.note, '') !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'
           AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = me.day AND round(x.amount) = me.amt
           AND coalesce(k.n, 0) <= 1)
    SELECT array_agg(grp.reference ORDER BY grp.reference)
      FROM grp
    HAVING count(*) >= 2 AND count(DISTINCT grp.payref) >= 2 AND (SELECT me.reference FROM me) = ANY (array_agg(grp.reference));
$$;
COMMENT ON FUNCTION finance.double_charge_group(uuid) IS
  'V752: the references of V561''s possible bank double charge an old-portal record belongs to (finance.possible_double_charges'' rule — the same student, session, item, Lagos day and amount, two or more records under two or more payment numbers, the same exclusions), read for that record alone by index; NULL when it is not one.';

/* V561's standing rule for the old portal's records: one that may be a bank double charge is never carried or refunded until the
   Bursary has checked it with the bank (finance.check_double_charge). Whether an old-portal SIWES payment waits on the bank, in words
   (NULL: it does not), for every way its money would leave or move — the refund desk (REFUND_SIWES_CHECK_BANK), the Bursar's refund of
   a credit by hand (SIWES_CREDIT_CHECK_BANK, the credits list's bank_check) and the payment correction desk (REALLOC_SIWES_CHECK_BANK):
     · a withdrawal of it, or of another old-portal record of its day and amount, as never received waits for the second officer;
     · the bank check of its day found a record never received that is not yet withdrawn (archived): every SIWES payment of that day
       waits — the one never received settles nothing meanwhile (finance.siwes_standing), and the one received is released only once
       the other is withdrawn (a withdrawal rejected or never raised leaves them waiting);
     · not checked, and V561 lists it (finance.double_charge_group).
   Checked RECEIVED, or every record found never received withdrawn: it waits no more. A record the bank check found never received is
   found by the check that names it (finance.siwes_found_not_received's test), whatever day an old fees upload has given it since; the
   other records of its day by the check of their day, read by the key V561 joins it on (the record's student, session, item, Lagos day
   and amount). Which wait it is comes as a code beside the words, so a screen follows the code, never the words: PROPOSED (a withdrawal
   of a record of its day waits for the second officer), NOT_RECEIVED (the bank check found this very record never received: it waits
   to be withdrawn), NOT_RECEIVED_WAITING (the bank check found another record of its day never received: this one, received, waits
   until that is withdrawn), UNCHECKED (a possible bank double charge not yet checked); both NULL when it does not wait. */
CREATE FUNCTION finance.siwes_bank_hold(p_payment uuid, OUT state text, OUT words text) LANGUAGE plpgsql STABLE AS $$
DECLARE r finance.payment_reference; v_day date; v_wait text; v_left text[]; v_grp text[]; c finance.double_charge_check;
BEGIN
    SELECT * INTO r FROM finance.payment_reference WHERE id = p_payment;
    IF r.id IS NULL OR r.student_id IS NULL OR r.confirmed_at IS NULL OR r.archived_at IS NOT NULL OR NOT finance.is_siwes_purpose(r.purpose)
       OR r.channel IS DISTINCT FROM 'Legacy' OR r.reference NOT LIKE 'MOAUM-LEG-%' THEN
        RETURN;
    END IF;
    v_day := (r.confirmed_at AT TIME ZONE 'Africa/Lagos')::date;
    -- a withdrawal as never received waiting for the second officer, of this record or another old-portal record of its day and amount
    SELECT string_agg(w.reference, ', ' ORDER BY w.reference) INTO v_wait
      FROM finance.payment_not_received w JOIN finance.payment_reference x ON x.reference = w.reference
     WHERE w.state = 'PROPOSED' AND x.student_id = r.student_id AND x.session = r.session AND x.purpose = r.purpose
       AND x.channel = 'Legacy' AND x.archived_at IS NULL AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = v_day AND round(x.amount) = round(r.amount);
    IF v_wait IS NOT NULL THEN
        state := 'PROPOSED';
        words := format('the withdrawal of %s as never received by the bank waits for a second Bursary officer (Payments not received); payment %s is not refunded or moved until it is decided',
                        v_wait, r.reference);
        RETURN;
    END IF;
    -- the bank check that names this very record never received, whatever its day now (the newest, should two name it); else the
    -- check of its day
    SELECT * INTO c FROM finance.double_charge_check k
     WHERE k.student_id = r.student_id AND k.verdict = 'NOT_RECEIVED' AND r.reference = ANY (k.not_received)
     ORDER BY k.checked_at DESC LIMIT 1;
    IF c.id IS NULL THEN
        SELECT * INTO c FROM finance.double_charge_check k
         WHERE k.student_id = r.student_id AND k.session = r.session AND k.purpose = r.purpose AND k.paid_on = v_day AND k.amount = round(r.amount);
    END IF;
    IF c.id IS NOT NULL THEN
        IF c.verdict = 'NOT_RECEIVED' THEN
            -- the records the bank never received that still stand (not withdrawn): the whole day waits on them
            SELECT array_agg(x.reference ORDER BY x.reference) INTO v_left FROM finance.payment_reference x
             WHERE x.reference = ANY (c.not_received) AND x.archived_at IS NULL;
            IF v_left IS NOT NULL THEN
                state := CASE WHEN r.reference = ANY (v_left) THEN 'NOT_RECEIVED' ELSE 'NOT_RECEIVED_WAITING' END;
                words := format('the bank check of %s (Old Fees History, possible double charges) found payment %s never received; until it is withdrawn (Payments not received), payment %s is not refunded or moved',
                                to_char(c.checked_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY'), array_to_string(v_left, ', '), r.reference);
            END IF;
        END IF;
        RETURN;
    END IF;
    -- not checked: a possible double charge as V561 lists it
    v_grp := finance.double_charge_group(r.id);
    IF v_grp IS NULL THEN RETURN; END IF;
    state := 'UNCHECKED';
    words := format('payment %s may be a bank double charge: %s, of the same day (%s) and amount, is under another payment number; check them with the bank first (Old Fees History, possible double charges)',
                    r.reference, array_to_string(array_remove(v_grp, r.reference), ', '), to_char(v_day, 'DD Mon YYYY'));
END $$;
COMMENT ON FUNCTION finance.siwes_bank_hold(uuid) IS
  'V752: whether an old-portal SIWES payment waits on the Bursary''s bank check (V561), as a code — PROPOSED, NOT_RECEIVED (this record found never received), NOT_RECEIVED_WAITING (another record of its day found never received), UNCHECKED — and in words; both NULL when it does not wait.';

/* the words alone, as every refusal gives them (REFUND_SIWES_CHECK_BANK, SIWES_CREDIT_CHECK_BANK, REALLOC_SIWES_CHECK_BANK) */
CREATE FUNCTION finance.siwes_bank_check(p_payment uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT h.words FROM finance.siwes_bank_hold(p_payment) h;
$$;
COMMENT ON FUNCTION finance.siwes_bank_check(uuid) IS
  'V752: why an old-portal SIWES payment is neither refunded nor moved until the Bursary checks it with the bank (V561), in words (finance.siwes_bank_hold: its code beside them): a withdrawal of a record of its day waiting for the second officer; the bank check of its day found a record never received that is not yet withdrawn; or a possible bank double charge (finance.double_charge_group) not yet checked. NULL when it does not wait.';

/* the refund desk's refusal (finance.propose_refund, finance.approve_refund): nothing is refunded on the payment a standing SIWES
   registration was made on — the student would stay registered on money given back; the registration is undone first — nor on a payment
   whose SIWES credit the Bursar recorded refunded (or applied) by hand: that money is spent already. The settling of credits takes the
   other side (finance.siwes_credit_refusal: SIWES_CREDIT_REFUND_DESK), and a refund approved settles the credit itself
   (finance.siwes_refund_follows), so one payment is never given back twice, whichever desk comes first. The fee is all or nothing, so a
   SIWES payment is refunded whole — what is left on it, nothing being refunded on it already but a part approved before V752 — never in
   part (REFUND_SIWES_PART): a part refunded would leave the rest held with nothing to settle or give it back. An old-portal SIWES payment
   that waits on the Bursary's bank check (finance.siwes_bank_check: a possible double charge not checked, a record of its day found
   never received and not yet withdrawn, a withdrawal waiting) is not refunded (REFUND_SIWES_CHECK_BANK, V561): the settling one as much
   as the credit, since a refund of either leaves the other settling the fee. */
CREATE FUNCTION finance.siwes_refund_refusal(p_reference text, p_amount numeric) RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE pr finance.payment_reference; v_bank text;
BEGIN
    IF EXISTS (SELECT 1 FROM finance.payment_reference r
                 JOIN registration.siwes_registration x ON r.id IN (x.payment_reference_id, x.legacy_payment_id)
                 JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                WHERE r.reference = upper(btrim(coalesce(p_reference, '')))) THEN
        RAISE EXCEPTION 'REFUND_SIWES_REGISTERED: payment % is the SIWES registration fee a SIWES course stands registered on; nothing is refunded on it while that registration stands',
            upper(btrim(p_reference)) USING ERRCODE = '23514', HINT = 'The Academic Office or ICT Support undoes the SIWES registration first.';
    END IF;
    IF EXISTS (SELECT 1 FROM finance.payment_reference r JOIN finance.siwes_credit c ON c.reference_id = r.id
                WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND c.settled_kind = 'HAND_REFUND') THEN
        RAISE EXCEPTION 'REFUND_SIWES_CREDIT_SETTLED: the Bursar recorded the SIWES credit of payment % as refunded; that money is spent and is not refunded again',
            upper(btrim(p_reference)) USING ERRCODE = '23514', HINT = 'The Bursar reopens the credit first if it was recorded in error.';
    END IF;
    SELECT * INTO pr FROM finance.payment_reference r WHERE r.reference = upper(btrim(coalesce(p_reference, '')));
    IF pr.id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) THEN
        v_bank := finance.siwes_bank_check(pr.id);
        IF v_bank IS NOT NULL THEN
            RAISE EXCEPTION 'REFUND_SIWES_CHECK_BANK: %', v_bank USING ERRCODE = '23514',
                HINT = 'The Bursary records the bank''s answer on Old Fees History (possible double charges) first.';
        END IF;
    END IF;
    IF pr.id IS NOT NULL AND finance.is_siwes_purpose(pr.purpose) AND p_amount < pr.amount - finance.gst_refunded(pr.reference) THEN
        RAISE EXCEPTION 'REFUND_SIWES_PART: payment % is a SIWES registration fee; the fee is all or nothing, so it is refunded whole (NGN %), never in part (NGN % proposed)',
            pr.reference, pr.amount - finance.gst_refunded(pr.reference), p_amount USING ERRCODE = '23514',
            HINT = 'Raise the refund for the whole payment.';
    END IF;
END $$;

/* whether a SIWES reference may be taken to a gateway or paid at the bank now: unpaid, unexpired, of the student's current session,
   the window open, the student eligible, the session's fee not already paid. Its amount is its own: a reference keeps its figure. */
CREATE FUNCTION finance.siwes_reference_payable(p_reference text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
               AND r.session IS NOT DISTINCT FROM people.student_current_session(r.student_id)
               AND registration.siwes_registration_open(r.session)
               AND registration.siwes_eligible(r.student_id, r.session)
               AND NOT EXISTS (SELECT 1 FROM finance.siwes_paid(r.student_id, r.session))
          FROM finance.payment_reference r
         WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND r.purpose LIKE 'SIWES registration fee%'), false);
$$;
COMMENT ON FUNCTION finance.siwes_reference_payable(text) IS
  'V752: a SIWES reference is paid (checkout, Quickteller, PayDirect validation) only while it is unpaid and unexpired, the session''s SIWES window open, the student eligible and the fee not already paid.';

-- ── 6 · what the student, the desk and the API read ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.siwes_period_json(p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('session', p.session, 'state', p.state, 'level', p.level, 'semester', p.semester,
                              'registrationOpens', p.registration_opens, 'registrationCloses', p.registration_closes,
                              'trainingStarts', p.training_starts, 'trainingEnds', p.training_ends, 'durationMonths', p.duration_months,
                              'note', p.note, 'setAt', p.set_at, 'setOffice', p.set_office)
      FROM registration.siwes_period p WHERE p.session = p_session;
$$;

CREATE FUNCTION registration.siwes_course_json(p_code text, p_programme text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('id', c.id, 'code', c.code, 'title', c.title, 'state', c.state,
                              'units', coalesce(catalogue.units_for(c.code, p_programme, 300), c.units))
      FROM catalogue.course c WHERE c.code = p_code;
$$;

/* a SIWES registration as the API returns it: id and at (the record), registrationId (the Second Semester course registration), the
   status (DROPPED when the SIWES course no longer stands on it), the course */
CREATE FUNCTION registration.siwes_registration_json(p_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object('id', x.id, 'at', x.registered_at, 'siwesRegistrationId', x.id, 'registrationId', x.course_registration_id,
                              'status', CASE WHEN EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = x.course_registration_id
                                                            AND e.offering_id = x.offering_id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
                                             THEN cr.status ELSE 'DROPPED' END,
                              'courseCode', x.course_code, 'registeredAt', x.registered_at, 'session', x.session, 'semester', x.semester, 'level', x.level)
      FROM registration.siwes_registration x JOIN registration.course_registration cr ON cr.id = x.course_registration_id
     WHERE x.id = p_id;
$$;

/* a student's SIWES of a session (the student's current session when none is named): eligibility and why not, the course, the
   period, the fee, the payment, the open reference, the registration, the ordinary Second Semester courses in the way, and the Second
   Semester school fees */
CREATE FUNCTION registration.siwes_eligibility(p_student uuid, p_session text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE s record; v_session text; v_reasons text[]; v_code text; v_course jsonb; f finance.siwes_fee; pd record; v_open boolean;
        v_ref record; v_reg_id uuid; v_reg jsonb; v_other jsonb; v_eligible boolean; v_fees_stated boolean; v_fees_cleared boolean; v_owed numeric;
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
        -- whether SIWES binds the student's Second Semester of the session (registration.siwes_applies), as every registration reader reads it
        'applies', registration.siwes_applies(p_student, v_session),
        'reasons', to_jsonb(v_reasons),
        'session', v_session,
        'level', registration.siwes_level(p_student, v_session),
        'semester', 2,
        'programme', jsonb_build_object('code', s.programme_code, 'name', s.programme_name),
        'curriculum', s.curriculum_version,
        'departmentCode', s.d_code, 'department', s.d_name, 'facultyCode', s.f_code, 'faculty', s.f_name,
        'course', v_course,
        'period', registration.siwes_period_json(v_session),
        'registrationOpen', v_open,
        'fee', CASE WHEN f.session IS NULL THEN NULL ELSE jsonb_build_object('amount', f.amount, 'state', f.state) END,
        'paid', CASE WHEN pd.reference_id IS NULL THEN NULL
                     ELSE jsonb_build_object('reference', pd.reference, 'amount', pd.amount, 'receiptNo', pd.receipt_no, 'at', pd.confirmed_at,
                                             'channel', pd.channel, 'source', pd.source) END,
        'openReference', CASE WHEN v_ref.reference IS NULL THEN NULL
                              ELSE jsonb_build_object('reference', v_ref.reference, 'amount', v_ref.amount, 'expiresAt', v_ref.expires_at) END,
        'registration', v_reg,
        'otherCourses', v_other,
        -- cleared: the semester's school fees paid (REG_SEMESTER_FEES_DUE); outstanding: what is left when not (else null); stated: the
        -- session's and the semester's school fees stated (REG_FEES_NOT_STATED, REG_SEMESTER_FEES_NOT_STATED)
        'semesterFees', jsonb_build_object('cleared', v_fees_cleared, 'outstanding', v_owed, 'stated', v_fees_stated),
        'canPay', v_eligible AND v_open AND pd.reference_id IS NULL AND f.state IS NOT DISTINCT FROM 'PUBLISHED',
        'canRegister', v_eligible AND v_open AND pd.reference_id IS NOT NULL AND jsonb_array_length(v_other) = 0 AND v_reg IS NULL
                       AND v_fees_cleared AND v_fees_stated);
END $$;
COMMENT ON FUNCTION registration.siwes_eligibility(uuid, text) IS
  'V752: a student''s SIWES of a session (the current one when none is named), as the student page and the desk read it: eligible, applies (registration.siwes_applies: SIWES binds the Second Semester), reasons (NOT_UNDERGRADUATE, CCE, NOT_IN_STUDY, NOT_300_LEVEL, NOT_CONFIGURED, NO_PERIOD, NO_COURSE, ALREADY_PASSED), the course (today''s mapping), the period, registrationOpen, the fee, the payment (PORTAL or OLD_PORTAL), the open reference, the registration (its courseCode the course it was made on), the ordinary Second Semester courses already on the registration (never the SIWES course, by today''s mapping or as registered) and the Second Semester school fees (semesterFees: cleared, outstanding, stated — the tests registering applies; canRegister waits on them).';

/* whether the SIWES page is in a student's menu (read on every screen, so cheap): SIWES binds the student's current session; or a SIWES
   of the student's still stands somewhere — a SIWES registration that stands (its course not dropped), or a SIWES payment that stands
   for a session SIWES bound the student in (they registered SIWES there, paid on the portal there, or it binds them there still). The
   test the SIWES page's own history reads (a session with a payment that stands or a registration not undone): a student whose SIWES
   was wholly undone (the course dropped, the payment withdrawn or refunded) does not keep the page; one who paid the old portal's SIWES
   fee before SIWES was configured for them is never given it */
CREATE FUNCTION registration.siwes_area(p_student uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
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
                               AND registration.siwes_applies(p_student, k.session))));
$$;
COMMENT ON FUNCTION registration.siwes_area(uuid) IS
  'V752: the SIWES page is in the student''s menu — SIWES binds the current session, or a SIWES registration of the student stands, or a SIWES payment stands for a session SIWES bound them in (registered there, paid on the portal there, or bound there still). A SIWES wholly undone keeps no menu item.';

-- ── 7 · the reference, its confirmation and money received twice ────────────────────────────────────────────────────────────────
/* the reference for the SIWES fee of the student's current session: the open one (at the figure it was drawn for), else a new one at
   the published fee. The amount comes only from finance.siwes_fee; the purpose never reads as school fees or the GST fee. */
CREATE FUNCTION finance.siwes_reference(p_student uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_session text; e jsonb; v_fee numeric; o finance.payment_reference; v_ref text; p registration.siwes_period;
BEGIN
    PERFORM 1 FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SIWES_NO_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    v_session := people.student_current_session(p_student);
    e := registration.siwes_eligibility(p_student, v_session);
    IF NOT (e ->> 'eligible')::boolean THEN
        RAISE EXCEPTION 'SIWES_NOT_ELIGIBLE: you are not eligible for SIWES registration in %: %', v_session,
            registration.siwes_reason_words(ARRAY(SELECT jsonb_array_elements_text(e -> 'reasons'))) USING ERRCODE = '23514',
            HINT = 'SIWES registration is for 300 Level undergraduates of the programmes the Academic Office configures for the session.';
    END IF;
    IF jsonb_typeof(e -> 'paid') = 'object' THEN
        RAISE EXCEPTION 'SIWES_PAID: the SIWES registration fee for % is paid (receipt %); it is never paid twice', v_session,
            coalesce(e -> 'paid' ->> 'receiptNo', e -> 'paid' ->> 'reference') USING ERRCODE = '23514',
            HINT = 'Register your SIWES course on the SIWES page.';
    END IF;
    IF NOT registration.siwes_registration_open(v_session) THEN
        SELECT * INTO p FROM registration.siwes_period WHERE session = v_session;
        RAISE EXCEPTION 'SIWES_CLOSED: SIWES registration for % is not open%', v_session,
            CASE WHEN p.state = 'OPEN' AND p.registration_opens > (now() AT TIME ZONE 'Africa/Lagos')::date THEN '; it opens on ' || to_char(p.registration_opens, 'DD Month YYYY')
                 WHEN p.state = 'OPEN' THEN '; it closed on ' || to_char(p.registration_closes, 'DD Month YYYY')
                 ELSE '' END USING ERRCODE = '23514',
            HINT = 'The Academic Office opens SIWES registration and dates its window.';
    END IF;
    v_fee := finance.siwes_fee_for(v_session);
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'SIWES_FEE_NOT_SET: the Bursary has not published the SIWES registration fee for %', v_session USING ERRCODE = '23514',
            HINT = 'The Bursary states and publishes the fee on Fee Setup.';
    END IF;
    SELECT * INTO o FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = v_session AND r.purpose LIKE 'SIWES registration fee%'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now()
     ORDER BY r.generated_at DESC LIMIT 1;
    IF o.id IS NULL THEN
        v_ref := finance.new_purpose_reference(p_student, v_session, v_fee, 'SIWES registration fee ' || v_session);
        SELECT * INTO o FROM finance.payment_reference WHERE reference = v_ref;
    END IF;
    RETURN jsonb_build_object('reference', o.reference, 'amount', o.amount, 'purpose', o.purpose, 'expiresAt', o.expires_at, 'session', o.session);
END $$;
COMMENT ON FUNCTION finance.siwes_reference(uuid) IS
  'V752: the reference for the SIWES fee of the student''s current session — the open one, else one drawn at the published fee (finance.new_purpose_reference, purpose ''SIWES registration fee <session>''). Refuses SIWES_NOT_ELIGIBLE, SIWES_PAID, SIWES_CLOSED, SIWES_FEE_NOT_SET.';

/* a SIWES reference confirmed (any lane — the gateways, PayDirect, a Bursary confirmation — all end in finance.confirm_payment): the
   student is told to register the course, and the other open SIWES references of the session close. Paying does not register: the
   student registers. A payment for a session already paid (a reference paid at the bank after another was paid by card, or after the
   old portal's) is never applied twice: it stands as a SIWES credit for the Bursary to apply or refund. Nothing here undoes the payment.
   The portal's references only (the old portal's payments come in confirmed, followed by trg_siwes_settling_follows_insert; one confirmed
   again after it was set back by trg_siwes_settling_follows_payment, as any SIWES payment that comes to stand). */
/* one SIWES fee of a student's session decided at a time: two payments confirmed at the same moment (a PayDirect notification and a
   card webhook) are taken one after the other, so the second sees the first and stands as a credit; the moves and the Bursar's
   settling of credits wait on the same lock (a transaction lock: nothing to release) */
CREATE FUNCTION finance.siwes_lock(p_student uuid, p_session text) RETURNS void LANGUAGE sql AS $$
    SELECT pg_advisory_xact_lock(hashtextextended('V752 SIWES ' || p_student::text || ' ' || coalesce(p_session, ''), 0));
$$;

CREATE FUNCTION finance.siwes_reference_confirmed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_other record; v_err text;
BEGIN
    IF NEW.student_id IS NULL THEN RETURN NULL; END IF;
    PERFORM finance.siwes_lock(NEW.student_id, NEW.session);
    -- an earlier payment that settles the fee (not an open credit itself; refunded ones do not count)
    SELECT x.reference, x.receipt_no INTO v_other FROM finance.siwes_standing(NEW.student_id, NEW.session) x
     WHERE x.reference_id <> NEW.id AND NOT x.open_credit
     ORDER BY x.registered DESC, x.confirmed_at, x.reference LIMIT 1;
    IF v_other.reference IS NOT NULL THEN
        INSERT INTO finance.siwes_credit (student_id, session, reference_id, amount, reason)
        VALUES (NEW.student_id, NEW.session, NEW.id, NEW.amount,
                'The SIWES registration fee of ' || NEW.session || ' was already paid by ' || v_other.reference || coalesce(' (receipt ' || v_other.receipt_no || ')', ''))
        ON CONFLICT (reference_id) DO NOTHING;
    ELSE
        BEGIN
            PERFORM platform.tell_student(NEW.student_id, 'SIWES_FEE_PAID', NULL,
                jsonb_build_object('SESSION', NEW.session, 'AMOUNT', finance.naira(NEW.amount), 'RECEIPT', coalesce(NEW.receipt_no, NEW.reference)),
                'SIWES_FEE_PAID:' || NEW.id);
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
            RAISE WARNING 'V752: the SIWES payment notice to % was not sent (%)', NEW.student_id, v_err;
        END;
    END IF;
    UPDATE finance.payment_reference SET expires_at = now()
     WHERE student_id = NEW.student_id AND session = NEW.session AND id <> NEW.id AND purpose LIKE 'SIWES registration fee%'
       AND confirmed_at IS NULL AND archived_at IS NULL AND expires_at > now();
    RETURN NULL;
END $$;
-- (trg_siwes_reference_confirmed on finance.payment_reference: section 18)

/* a SIWES credit follows its payment (as the Summer's, V742): moved off SIWES by a payment correction (another purpose, session or
   student) it is settled as applied (MOVED), the move its note; moved back it is open again */
CREATE FUNCTION finance.siwes_credit_follows_payment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE finance.siwes_credit x
       SET state = 'APPLIED', settled_kind = 'MOVED', settled_at = now(), settled_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           settled_note = 'Moved by a payment correction: the payment now counts as ' || NEW.purpose || ' (' || coalesce(NEW.session, '-') || ')'
     WHERE x.reference_id = NEW.id AND x.state = 'OPEN'
       AND (NOT finance.is_siwes_purpose(NEW.purpose) OR NEW.student_id IS DISTINCT FROM x.student_id OR NEW.session IS DISTINCT FROM x.session);
    UPDATE finance.siwes_credit x
       SET state = 'OPEN', settled_kind = NULL, settled_at = NULL, settled_by = NULL, settled_note = NULL
     WHERE x.reference_id = NEW.id AND x.settled_kind = 'MOVED'
       AND finance.is_siwes_purpose(NEW.purpose) AND NEW.student_id = x.student_id AND NEW.session = x.session;
    RETURN NULL;
END $$;
-- (trg_siwes_credit_follows_payment on finance.payment_reference: section 18)

/* the payment that settled a student's SIWES fee of a session no longer does (moved, archived, deleted, set back to unconfirmed, or
   refunded on the refund desk) and only open credits stand: the oldest settles it now, recorded on the credit (APPLIED, 'Settles the
   SIWES fee: …'), so the Bursar is never offered it to refund. Nothing while another payment still settles. No payment named (NULL):
   whatever left, the fee stands on open credits alone (p_why says why). The caller holds finance.siwes_lock for the student and session. */
CREATE FUNCTION finance.siwes_settles_instead(p_student uuid, p_session text, p_reference text, p_why text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_student IS NULL OR EXISTS (SELECT 1 FROM finance.siwes_standing(p_student, p_session) x WHERE NOT x.open_credit) THEN RETURN; END IF;
    UPDATE finance.siwes_credit c
       SET state = 'APPLIED', settled_kind = 'SETTLES', settled_at = now(), settled_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           settled_note = CASE WHEN p_reference IS NULL
                               THEN 'Settles the SIWES fee: no other SIWES payment of ' || p_session || ' settles it (' || coalesce(p_why, '-') || '); this payment settles it now'
                               ELSE 'Settles the SIWES fee: ' || p_reference || ', which settled the SIWES registration fee of ' || p_session
                                    || ', was ' || p_why || '; this payment settles it now' END
     WHERE c.id = (SELECT c2.id FROM finance.siwes_credit c2 JOIN finance.siwes_standing(p_student, p_session) x ON x.reference_id = c2.reference_id
                    WHERE c2.state = 'OPEN' AND c2.student_id = p_student AND c2.session = p_session
                    ORDER BY x.confirmed_at, x.reference LIMIT 1);
END $$;

/* the one rule for a SIWES payment that comes to stand for its student's session — moved back, restored from the archive, confirmed
   again, moved to its true owner, inserted confirmed (the old portal's, loaded by the import or loaded again after the old fees reset),
   or found on record beside another when V752 landed (finance.siwes_credit_second_payments): where another payment already settles the
   fee, it is that student's credit for the Bursary — one it carried before (one row a payment: applied by the move under the student it
   left, or settling in another's absence) is made this student's and open again; where only credits that settled in its absence stand,
   those are open again (it settles once more). Never applied twice, never lost. A session not on the calendar holds no SIWES fee and
   records no credit. The payment named as the one that settles is the first confirmed (by its reference when two share a moment, as
   the import names the first of a day by the plain key). */
CREATE FUNCTION finance.siwes_comes_to_stand(p_payment uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE p finance.payment_reference; v_other record;
BEGIN
    SELECT * INTO p FROM finance.payment_reference WHERE id = p_payment;
    IF p.id IS NULL OR p.student_id IS NULL OR p.confirmed_at IS NULL OR p.archived_at IS NOT NULL OR NOT finance.is_siwes_purpose(p.purpose)
       OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p.session) THEN
        RETURN;
    END IF;
    PERFORM finance.siwes_lock(p.student_id, p.session);
    -- not an open credit itself (a refunded one never stands here: finance.siwes_standing)
    IF NOT EXISTS (SELECT 1 FROM finance.siwes_standing(p.student_id, p.session) x WHERE x.reference_id = p.id AND NOT x.open_credit) THEN
        RETURN;
    END IF;
    SELECT x.reference, x.receipt_no INTO v_other FROM finance.siwes_standing(p.student_id, p.session) x
      LEFT JOIN finance.siwes_credit c ON c.reference_id = x.reference_id
     WHERE x.reference_id <> p.id AND NOT x.open_credit
       AND (x.registered OR c.settled_kind IS DISTINCT FROM 'SETTLES')
     ORDER BY x.registered DESC, x.confirmed_at, x.reference LIMIT 1;
    IF v_other.reference IS NULL THEN
        -- only credits that settled in its absence: open again
        UPDATE finance.siwes_credit c SET state = 'OPEN', settled_kind = NULL, settled_at = NULL, settled_by = NULL, settled_note = NULL
         WHERE c.student_id = p.student_id AND c.session = p.session AND c.reference_id <> p.id AND c.settled_kind = 'SETTLES';
    ELSE
        -- another settles already: this payment is the student's credit
        INSERT INTO finance.siwes_credit (student_id, session, reference_id, amount, reason)
        VALUES (p.student_id, p.session, p.id, p.amount,
                'The SIWES registration fee of ' || p.session || ' was already paid by ' || v_other.reference
                || coalesce(' (receipt ' || v_other.receipt_no || ')', '') || ' when this payment came to stand for it')
        ON CONFLICT (reference_id) DO UPDATE
           SET student_id = EXCLUDED.student_id, session = EXCLUDED.session, amount = EXCLUDED.amount,
               reason = CASE WHEN finance.siwes_credit.student_id = EXCLUDED.student_id AND finance.siwes_credit.session = EXCLUDED.session
                             THEN finance.siwes_credit.reason ELSE EXCLUDED.reason END,
               state = 'OPEN', settled_kind = NULL, settled_at = NULL, settled_by = NULL, settled_note = NULL
         WHERE finance.siwes_credit.settled_kind IN ('SETTLES', 'MOVED');
    END IF;
END $$;
COMMENT ON FUNCTION finance.siwes_comes_to_stand(uuid) IS
  'V752: the one rule for a SIWES payment that comes to stand for its student''s session (the payment triggers and V752''s credit of the second payments already on record call it): another settles the fee — it is the student''s credit; only credits that settled in its absence — they are open again.';

/* the payment that settles follows the payments (fires after trg_siwes_reference_confirmed and trg_siwes_credit_follows_payment, by
   name). The payment that settled a student's SIWES fee leaves it (moved to another purpose, student or session, archived — the old
   portal's withdrawals archive whatever stands on a record — set back to unconfirmed, or deleted, as the old fees reset deletes an
   old-portal payment nothing holds): the oldest open credit settles it now (finance.siwes_settles_instead), and a standing SIWES
   registration made on it follows the payment that settles now (it would otherwise name money withdrawn, and leave the payment that
   settles open to a refund or a move). A SIWES payment that comes to stand: finance.siwes_comes_to_stand. */
CREATE FUNCTION finance.siwes_settling_follows_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE old_stood boolean := false; new_stands boolean := false; same_key boolean := false; v_why text;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        old_stood := OLD.student_id IS NOT NULL AND OLD.confirmed_at IS NOT NULL AND OLD.archived_at IS NULL AND finance.is_siwes_purpose(OLD.purpose);
    END IF;
    IF TG_OP <> 'DELETE' THEN
        new_stands := NEW.student_id IS NOT NULL AND NEW.confirmed_at IS NOT NULL AND NEW.archived_at IS NULL AND finance.is_siwes_purpose(NEW.purpose);
    END IF;
    IF TG_OP = 'UPDATE' THEN
        same_key := OLD.student_id IS NOT DISTINCT FROM NEW.student_id AND OLD.session IS NOT DISTINCT FROM NEW.session;
    END IF;
    -- left: nothing but open credits stands for the session it left — the oldest settles now
    IF old_stood AND NOT (new_stands AND same_key) THEN
        PERFORM finance.siwes_lock(OLD.student_id, OLD.session);
        IF TG_OP = 'DELETE' THEN v_why := 'deleted';
        ELSIF NEW.confirmed_at IS NULL THEN v_why := 'set back to unconfirmed';
        ELSIF NEW.archived_at IS NOT NULL THEN v_why := 'archived for review';
        ELSIF NEW.student_id IS DISTINCT FROM OLD.student_id THEN v_why := 'moved to another student';
        ELSIF NEW.session IS DISTINCT FROM OLD.session THEN v_why := 'moved to ' || coalesce(NEW.session, 'no session');
        ELSE v_why := 'now counted as ' || coalesce(NEW.purpose, '-');
        END IF;
        PERFORM finance.siwes_settles_instead(OLD.student_id, OLD.session, OLD.reference, v_why);
        IF TG_OP = 'UPDATE' THEN   -- deleted, a registration made on it goes with it (the old fees reset keeps such a payment)
            UPDATE registration.siwes_registration x
               SET payment_reference_id = CASE WHEN p.source = 'PORTAL' THEN p.reference_id END,
                   legacy_payment_id = CASE WHEN p.source = 'OLD_PORTAL' THEN p.reference_id END
              FROM finance.siwes_paid(OLD.student_id, OLD.session) p
             WHERE x.student_id = OLD.student_id AND x.session = OLD.session AND OLD.id IN (x.payment_reference_id, x.legacy_payment_id)
               AND registration.siwes_registered(x.student_id, x.session);
        END IF;
    END IF;
    IF new_stands AND NOT (old_stood AND same_key) THEN
        PERFORM finance.siwes_comes_to_stand(NEW.id);
    END IF;
    RETURN NULL;
END $$;
-- (trg_siwes_settling_follows_payment, _delete and _insert on finance.payment_reference: section 18)

/* a refund approved (or paid) on the refund desk against a SIWES payment (taken after the student's SIWES lock, as every settling is):
   an open SIWES credit on it — or the record that it settled the fee in another's absence — is the refund's (REFUNDED, 'Refunded on the
   refund desk: <refund>'), so the Bursar is never offered it to refund again nor to reopen — once the whole of it is refunded (the desk
   refunds a SIWES payment whole; a part approved before V752 leaves the credit open, the desk holding it, until the rest is); and when
   the payment refunded settled the fee, the oldest open credit settles it now (finance.siwes_settles_instead) */
CREATE FUNCTION finance.siwes_refund_follows() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pr finance.payment_reference;
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.state IN ('APPROVED', 'PAID') THEN RETURN NULL; END IF;   -- paid after approval: followed already
    SELECT * INTO pr FROM finance.payment_reference r WHERE r.reference = NEW.source_reference;
    IF pr.id IS NULL OR pr.student_id IS NULL OR NOT finance.is_siwes_purpose(pr.purpose) THEN RETURN NULL; END IF;
    PERFORM finance.siwes_lock(pr.student_id, pr.session);
    UPDATE finance.siwes_credit c
       SET state = 'REFUNDED', settled_kind = 'DESK_REFUND', settled_at = now(),
           settled_by = coalesce(NEW.approved_by, nullif(current_setting('moaum.actor_id', true), '')::uuid),
           settled_note = 'Refunded on the refund desk: ' || NEW.reference
     WHERE c.reference_id = pr.id AND c.student_id = pr.student_id AND c.session = pr.session
       AND (c.state = 'OPEN' OR c.settled_kind = 'SETTLES')
       AND finance.gst_refunded(pr.reference) >= c.amount;
    PERFORM finance.siwes_settles_instead(pr.student_id, pr.session, pr.reference, 'refunded on the refund desk (' || NEW.reference || ')');
    RETURN NULL;
END $$;
-- (trg_siwes_refund_follows on finance.refund: section 18)

/* the one rule applied again to a student's session when what stands for the fee changes with no payment written: the Bursary's bank
   check of a day recorded or changed (a record found never received no longer stands, finance.siwes_standing; found received, or no
   longer named, it stands again), a withdrawal as never received raised, approved or rejected. So the payments that stand and the
   credits always agree — one payment settles the fee, every other that stands is an open credit, and no credit is listed on a payment
   that does not stand (finance.siwes_credits):
     · a record found never received that settled the fee has left it: the oldest open credit settles it instead (SETTLES), as when a
       payment is archived;
     · a record released comes to stand again (finance.siwes_comes_to_stand): the student's credit where another payment settles, the
       one that settles again where only credits that settled in its absence stand;
     · two payments settling (a state an earlier order of events could leave): the one rule again, newest first, the payment a SIWES
       registration stands on last, so the surplus is a credit;
     · nothing but open credits standing: the oldest settles;
     · a standing SIWES registration made on a payment that no longer stands follows the payment that settles now (a registration never
       rests on money the bank never received).
   p_released: the references the check named never received before and names no more. p_why: the event, for the settled notes. Under
   the student's SIWES lock, as every settling. */
CREATE FUNCTION finance.siwes_stand_again(p_student uuid, p_session text, p_released text[], p_why text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE x record; n int;
BEGIN
    IF p_student IS NULL OR NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student)
       OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = p_session) THEN
        RETURN;
    END IF;
    PERFORM finance.siwes_lock(p_student, p_session);
    -- a record found never received that settled the fee (no open credit of its own) has left it
    FOR x IN SELECT r.reference FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                AND finance.is_siwes_purpose(r.purpose) AND finance.siwes_found_not_received(r.id)
                AND NOT EXISTS (SELECT 1 FROM finance.siwes_credit c WHERE c.reference_id = r.id AND c.state = 'OPEN')
              ORDER BY r.confirmed_at, r.reference LOOP
        PERFORM finance.siwes_settles_instead(p_student, p_session, x.reference, 'found never received by the bank (' || p_why || ')');
    END LOOP;
    -- a record released comes to stand again
    FOR x IN SELECT r.id FROM finance.payment_reference r
              WHERE r.student_id = p_student AND r.session = p_session AND r.reference = ANY (coalesce(p_released, '{}'::text[]))
              ORDER BY r.confirmed_at DESC, r.reference DESC LOOP
        PERFORM finance.siwes_comes_to_stand(x.id);
    END LOOP;
    -- two settling: the one rule again, the one a registration stands on last
    SELECT count(*) INTO n FROM finance.siwes_standing(p_student, p_session) s WHERE NOT s.open_credit;
    IF n > 1 THEN
        FOR x IN SELECT s.reference_id FROM finance.siwes_standing(p_student, p_session) s WHERE NOT s.open_credit
                  ORDER BY s.registered, s.confirmed_at DESC, s.reference DESC LOOP
            PERFORM finance.siwes_comes_to_stand(x.reference_id);
        END LOOP;
    END IF;
    -- none settling while open credits stand: the oldest settles
    PERFORM finance.siwes_settles_instead(p_student, p_session, NULL, p_why);
    -- a standing SIWES registration follows the payment that settles now
    UPDATE registration.siwes_registration sr
       SET payment_reference_id = CASE WHEN p.source = 'PORTAL' THEN p.reference_id END,
           legacy_payment_id = CASE WHEN p.source = 'OLD_PORTAL' THEN p.reference_id END
      FROM finance.siwes_paid(p_student, p_session) p
     WHERE sr.student_id = p_student AND sr.session = p_session AND registration.siwes_registered(p_student, p_session)
       AND NOT EXISTS (SELECT 1 FROM finance.siwes_standing(p_student, p_session) s
                        WHERE s.reference_id IN (sr.payment_reference_id, sr.legacy_payment_id));
END $$;
COMMENT ON FUNCTION finance.siwes_stand_again(uuid, text, text[], text) IS
  'V752: the one rule applied again to a student''s session when the Bursary''s bank check or a withdrawal as never received changes what stands: a record found never received leaves the fee (the oldest open credit settles in its place), a record released comes to stand again (finance.siwes_comes_to_stand), two settling become one and a credit, none settling makes the oldest open credit settle, and a standing SIWES registration follows the payment that settles.';

/* the bank check of a day (finance.double_charge_check: recorded, changed or removed) and the withdrawal of a record as never received
   (finance.payment_not_received: raised, approved, rejected or cancelled), for a SIWES item: the one rule again for the student's session
   (finance.siwes_stand_again), with the records the check no longer names never received */
CREATE FUNCTION finance.siwes_bank_check_follows() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_released text[] := '{}'; k record;
BEGIN
    IF TG_TABLE_NAME = 'double_charge_check' THEN
        IF TG_OP IN ('UPDATE', 'DELETE') AND OLD.verdict = 'NOT_RECEIVED' THEN
            v_released := ARRAY(SELECT y FROM unnest(OLD.not_received) y
                                 WHERE TG_OP = 'DELETE' OR NEW.verdict IS DISTINCT FROM 'NOT_RECEIVED' OR NOT (y = ANY (NEW.not_received)));
        END IF;
        IF TG_OP = 'DELETE' THEN k := OLD; ELSE k := NEW; END IF;
        PERFORM finance.siwes_stand_again(k.student_id, k.session, v_released,
            'the bank check of ' || to_char(k.checked_at AT TIME ZONE 'Africa/Lagos', 'DD Mon YYYY') || CASE WHEN TG_OP = 'DELETE' THEN ', removed' ELSE '' END);
    ELSE
        PERFORM finance.siwes_stand_again(NEW.student_id, NEW.session, '{}'::text[], 'withdrawal ' || NEW.request_ref || ' ' || lower(NEW.state));
    END IF;
    RETURN NULL;
END $$;
-- (trg_siwes_bank_check_follows and _removed on finance.double_charge_check, trg_siwes_withdrawal_follows on finance.payment_not_received:
-- section 18)

-- ── 8 · the registration: the student registers once the fee is paid ────────────────────────────────────────────────────────────
/* the SIWES course registered for the student's current session: SIWES binds the student and they are eligible, the window is open,
   the fee is paid, and no ordinary Second Semester course stands on the registration (SIWES_OTHER_COURSES names them: they are dropped
   first). The session's Second Semester registration is made or reused (level 300), the SIWES class opened if needed, the course
   entered, the registration's own gates run as for any submission (the Second Semester school fees stated and paid, the GST hold, the
   SIWES units) and the registration approved as it is made (AUTO) — one an office approved before is stamped approved on the fee
   (AUTO, now), its status unchanged. Idempotent: a second call returns the same. */
CREATE FUNCTION registration.siwes_register(p_student uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        s people.student; v_session text; e jsonb; pd record; v_code text; r registration.course_registration; v_off uuid; v_units int;
        v_other text; sr registration.siwes_registration; v_was text;
BEGIN
    IF who IS NULL THEN RAISE EXCEPTION 'a SIWES registration is made by a person' USING ERRCODE = '23514'; END IF;
    SELECT * INTO s FROM people.student WHERE id = p_student FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SIWES_NO_STUDENT: no such student' USING ERRCODE = 'P0002'; END IF;
    v_session := people.student_current_session(p_student);
    PERFORM finance.siwes_lock(p_student, v_session);   -- the payment it stands on is not settled as a credit meanwhile
    -- made already, its course standing: the same again
    SELECT * INTO sr FROM registration.siwes_registration WHERE student_id = p_student AND session = v_session;
    IF sr.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.entry x WHERE x.registration_id = sr.course_registration_id AND x.offering_id = sr.offering_id
                                       AND x.status NOT IN ('DROPPED', 'WITHDRAWN')) THEN
        RETURN registration.siwes_registration_json(sr.id);
    END IF;
    -- bound by a payment (or a registration) while no live SIWES course reaches the student (ended, or its mapping changed): said plainly
    v_code := registration.siwes_course_for(p_student);
    IF registration.siwes_applies(p_student, v_session)
       AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = v_code AND k.state <> 'ENDED') THEN
        RAISE EXCEPTION 'SIWES_COURSE_MISSING: no SIWES course your programme registers is set for % now (%); your SIWES payment stands and the course is registered once the Academic Office sets it',
            v_session, coalesce(v_code || ' has ended', 'none is mapped') USING ERRCODE = '23514',
            HINT = 'The Academic Office sets the programme''s SIWES course on the SIWES desk.';
    END IF;
    e := registration.siwes_eligibility(p_student, v_session);
    IF NOT (e ->> 'eligible')::boolean THEN
        RAISE EXCEPTION 'SIWES_NOT_ELIGIBLE: you are not eligible for SIWES registration in %: %', v_session,
            registration.siwes_reason_words(ARRAY(SELECT jsonb_array_elements_text(e -> 'reasons'))) USING ERRCODE = '23514';
    END IF;
    IF NOT registration.siwes_registration_open(v_session) THEN
        RAISE EXCEPTION 'SIWES_CLOSED: SIWES registration for % is not open', v_session USING ERRCODE = '23514',
            HINT = 'The Academic Office opens SIWES registration and dates its window.';
    END IF;
    SELECT * INTO pd FROM finance.siwes_paid(p_student, v_session);
    IF pd.reference_id IS NULL THEN
        RAISE EXCEPTION 'SIWES_UNPAID: the SIWES registration fee for % is not paid; the SIWES course is registered once it is', v_session
            USING ERRCODE = '23514', HINT = 'Pay the SIWES registration fee on the SIWES page; a payment at a bank shows here once it is confirmed.';
    END IF;
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = v_session AND semester = 2 FOR UPDATE;
    IF FOUND THEN
        SELECT string_agg(DISTINCT o.course_code, ', ') INTO v_other
          FROM registration.entry x JOIN catalogue.offering o ON o.id = x.offering_id
         WHERE x.registration_id = r.id AND x.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code <> v_code;
        IF v_other IS NOT NULL THEN
            RAISE EXCEPTION 'SIWES_OTHER_COURSES: your Second Semester registration for % holds %; the SIWES semester holds the SIWES course (%) alone', v_session, v_other, v_code
                USING ERRCODE = '23514',
                HINT = 'Drop those courses on Course Registration, or reset it (a carry-over or deferred course waits for a later semester); ICT Support drops them for you too. Then register SIWES again.';
        END IF;
        IF r.status = 'LOCKED' THEN
            RAISE EXCEPTION 'SIWES_REGISTRATION_LOCKED: your Second Semester registration for % is locked', v_session USING ERRCODE = '23514';
        END IF;
    ELSE
        INSERT INTO registration.course_registration (id, student_id, session, semester, level, status)
        VALUES (gen_random_uuid(), p_student, v_session, 2, 300, 'DRAFT')
        RETURNING * INTO r;
    END IF;
    v_was := r.status;
    -- the SIWES class of the session's Second Semester: the one open, else opened now
    SELECT o.id INTO v_off FROM catalogue.offering o
     WHERE o.course_code = v_code AND o.session = v_session AND o.semester = 2 AND o.stream = 'REGULAR' LIMIT 1;
    IF v_off IS NULL THEN v_off := catalogue.open_class(v_code, v_session, 2, 'REGULAR'); END IF;
    v_units := coalesce(catalogue.units_for(v_code, s.programme_code, 300), (SELECT k.units FROM catalogue.course k WHERE k.code = v_code));
    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
    VALUES (r.id, v_off, v_units, 'CURRENT', CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END)
    ON CONFLICT (registration_id, offering_id) DO UPDATE SET status = EXCLUDED.status, units = EXCLUDED.units;
    -- the registration's own gates, as for any submission: the Second Semester school fees stated and paid, the GST hold, the units
    PERFORM registration.submit_checks(r.id);
    IF v_was IN ('DRAFT', 'RETURNED', 'SUBMITTED') THEN
        UPDATE registration.course_registration SET status = 'APPROVED', submitted_at = coalesce(submitted_at, now()), approved_at = now(),
               approved_by = NULL, approval_mode = 'AUTO'
         WHERE id = r.id;
        UPDATE registration.entry SET status = 'APPROVED' WHERE registration_id = r.id AND status = 'REGISTERED';
        UPDATE registration.approval_review SET cleared_at = now() WHERE registration_id = r.id AND cleared_at IS NULL;
    ELSIF v_was = 'APPROVED' THEN
        -- approved by an office before (its ordinary courses dropped since): the SIWES course is approved on the fee, and the record says
        -- so (AUTO, now, by nobody), the status as it is — never a Head of Department's approval of a course the Head never saw
        UPDATE registration.course_registration SET approved_at = now(), approved_by = NULL, approval_mode = 'AUTO' WHERE id = r.id;
    END IF;
    INSERT INTO registration.siwes_registration (student_id, session, level, semester, course_registration_id, offering_id, course_code,
                                                 payment_reference_id, legacy_payment_id, registered_by, registered_office)
    VALUES (p_student, v_session, 300, 2, r.id, v_off, v_code,
            CASE WHEN pd.source = 'PORTAL' THEN pd.reference_id END, CASE WHEN pd.source = 'OLD_PORTAL' THEN pd.reference_id END, who, v_office)
    ON CONFLICT (student_id, session) DO UPDATE SET course_registration_id = EXCLUDED.course_registration_id, offering_id = EXCLUDED.offering_id,
           course_code = EXCLUDED.course_code, payment_reference_id = EXCLUDED.payment_reference_id, legacy_payment_id = EXCLUDED.legacy_payment_id,
           registered_at = now(), registered_by = EXCLUDED.registered_by, registered_office = EXCLUDED.registered_office
    RETURNING * INTO sr;
    PERFORM platform.tell_student(p_student, 'SIWES_REGISTERED', NULL,
        jsonb_build_object('SESSION', v_session, 'COURSE', v_code, 'UNITS', v_units), 'SIWES_REGISTERED:' || sr.id || ':' || floor(extract(epoch FROM sr.registered_at))::bigint);
    RETURN registration.siwes_registration_json(sr.id);
END $$;
COMMENT ON FUNCTION registration.siwes_register(uuid) IS
  'V752: the student registers the SIWES course of their current session once the fee is paid: a live SIWES course (SIWES_COURSE_MISSING for a student bound by a payment whose course has ended or is unmapped), eligible, window open, paid, no ordinary Second Semester course on the registration (SIWES_OTHER_COURSES); the registration made or reused at 300 Level, the class opened, the course entered, the registration''s own gates run (school fees, GST, units) and the registration approved (AUTO). Idempotent.';

-- ── 9 · the database's own word: the Second Semester of a SIWES student holds the SIWES course alone, paid ─────────────────────
/* every path that writes a course onto a registration ends in registration.entry: the student's doors, add and drop, ICT Support and
   the Student edit (with or without the override), the Registry's late registration, the office create, the old-portal uploads. For a
   Second Semester registration that SIWES binds (registration.siwes_applies), only the student's SIWES course is taken, and that only
   once its fee is paid. A first-semester row, another session, a programme not configured: untouched (V503 stands). An approval is
   judged too (a course placed before the period opened is not approved after it: the Head of Department's approval runs no submission
   checks); a return to REGISTERED, or a row left as it is, is not. The old portal's history loader sets moaum.siwes_override, which is
   honoured for a closed (past) session only. */
CREATE FUNCTION registration.entry_siwes_only() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r record; v_code text; v_siwes text;
BEGIN
    IF NEW.status NOT IN ('REGISTERED', 'APPROVED') THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND OLD.status IN ('REGISTERED', 'APPROVED') AND NEW.offering_id = OLD.offering_id
       AND NOT (OLD.status = 'REGISTERED' AND NEW.status = 'APPROVED') THEN
        RETURN NEW;
    END IF;
    SELECT cr.student_id, cr.session, cr.semester INTO r FROM registration.course_registration cr WHERE cr.id = NEW.registration_id;
    IF r.semester IS DISTINCT FROM 2 OR NOT registration.siwes_applies(r.student_id, r.session) THEN RETURN NEW; END IF;
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
END $$;
-- (trg_entry_siwes_only on registration.entry: section 18)

/* a SIWES registration is approved on the SIWES fee, one fixed course and nothing for a Head of Department to choose: while it stands
   (its SIWES course not dropped) its course registration never leaves APPROVED or LOCKED but to be LOCKED, whichever door tries. Every
   writer of the status: the Head of Department's return (RegistrationRepository.returnWithComment) and the Academic Office's
   below-minimum return (never meets one, the SIWES course being its own minimum) and an admission correction's return: REG_RETURN_SIWES;
   the office submit (RegistrationService.submit, which sets SUBMITTED on any status) and a status written by hand: REG_STATUS_SIWES.
   Returned or submitted again, the student could neither submit it (the gate sends a SIWES semester to the SIWES page) nor register again
   (it stands). The doors that undo one take the SIWES course off first, then set the status: the office reset (registration.student_reset
   deletes the entries, then makes the draft) and the office drop (registration.support_drop marks the entry DROPPED; the status stays).
   The student's submit, the automatic approval and the SIWES registration itself never move an approved registration. */
CREATE FUNCTION registration.siwes_registration_not_returned() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM registration.siwes_registration x
                 JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                          AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                WHERE x.course_registration_id = NEW.id) THEN
        IF NEW.status = 'RETURNED' THEN
            RAISE EXCEPTION 'REG_RETURN_SIWES: a SIWES registration is approved on the SIWES fee; it is not returned' USING ERRCODE = '23514',
                HINT = 'The Academic Office or ICT Support drops the SIWES course when the registration must be made again.';
        END IF;
        RAISE EXCEPTION 'REG_STATUS_SIWES: a SIWES registration is approved on the SIWES fee; it stays % (% refused)', lower(OLD.status), lower(NEW.status)
            USING ERRCODE = '23514', HINT = 'The Academic Office or ICT Support drops the SIWES course, or resets the registration, when it must be made again.';
    END IF;
    RETURN NEW;
END $$;
-- (trg_registration_siwes_not_returned on registration.course_registration: section 18)

-- ── 10 · the registration engine reads SIWES first; V503 stands behind it for every programme not configured ──────────────────────
DO $$
DECLARE d text; a text;
BEGIN
    -- the gate: a SIWES student's Second Semester is registered on the SIWES page (as the Summer's semester 3 is on its own)
    d := pg_get_functiondef('registration.registration_gate(uuid,text,integer)'::regprocedure);
    a := '             WHEN st.entry_mode = ''CCE'' THEN registration.cce_gate(p_student, p_session, p_semester)';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.registration_gate is not as V735 left it'; END IF;
    d := replace(d, a, '             -- V752: a SIWES student''s Second Semester (registration.siwes_applies) is registered on the SIWES page: the SIWES course
             -- alone, once its fee is paid
             WHEN p_semester = 2 AND registration.siwes_applies(p_student, p_session)
                  THEN ''The Second Semester of '' || p_session || '' is your SIWES (industrial training) semester: it is registered on the SIWES page.''
' || a);
    EXECUTE d;

    -- the menu: the SIWES course alone (no other course of the level, no carry-over, no deferred course — so nothing is placed by the
    -- draft or the save either)
    d := pg_get_functiondef('registration.student_menu(uuid,text,integer)'::regprocedure);
    IF position('                      -- V483: the student''s specialisation within their programme' IN d) = 0
       OR position('           AND NOT (c.kind = ''GST'' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))' IN d) = 0
       OR position('         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL' IN d) = 0
       OR position('           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))' IN d) = 0
       OR position('            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x' IN d) = 0 THEN
        RAISE EXCEPTION 'V752: registration.student_menu is not as V590 left it';
    END IF;
    d := replace(d, '                      -- V483: the student''s specialisation within their programme',
                    '                      -- V752: a SIWES student''s Second Semester (registration.siwes_applies) holds their SIWES course alone
                      (p_semester = 2 AND registration.siwes_applies(st.id, p_session)) AS siwes_on, registration.siwes_course_for(st.id) AS siwes_code,
                      -- V483: the student''s specialisation within their programme');
    d := replace(d, '           AND NOT (c.kind = ''GST'' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))',
                    '           AND NOT s.siwes_on   -- V752
           AND NOT (c.kind = ''GST'' AND c.code IN (SELECT gp.course_code FROM gst_passed gp))');
    d := replace(d, '         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL',
                    '         WHERE o.stream = s.stream AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL AND NOT s.siwes_on   -- V752');
    d := replace(d, '           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code))',
                    '           AND registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NULL AND NOT s.siwes_on   -- V752
           AND NOT EXISTS (SELECT 1 FROM carry cv WHERE cv.code = c.code)),
    -- V752: the SIWES student''s SIWES course, at the programme''s units, once its class of the semester is open
    siwes AS (
        SELECT o.id AS offering_id, c.code, c.title, coalesce(catalogue.units_for(c.code, s.programme_code, s.current_level), c.units) AS units, c.kind,
               coalesce((SELECT co.basis FROM catalogue.course_offer co WHERE co.course_code = c.code AND co.programme_code = s.programme_code
                            AND co.level = s.current_level), ''Core'') AS basis, c.dept_code
          FROM s
          JOIN catalogue.course c ON c.code = s.siwes_code AND c.state <> ''ENDED''
          JOIN catalogue.offering o ON o.course_code = c.code AND o.session = p_session AND o.semester = p_semester AND o.stream = s.stream
         WHERE s.siwes_on)');
    d := replace(d, '            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df) x',
                    '            UNION ALL SELECT df.offering_id, df.code, df.title, df.units, df.kind, df.basis, df.dept_code, NULL::text, df.deferred_from FROM deferred df
            UNION ALL SELECT sw.offering_id, sw.code, sw.title, sw.units, sw.kind, sw.basis, sw.dept_code, NULL::text, NULL::text FROM siwes sw) x');
    EXECUTE d;

    -- a course beside the menu (Add Other Course, the carry-over picker, add/drop, the automatic approval's re-check)
    d := pg_get_functiondef('registration.course_check(uuid,text,integer,text,text[],text[],text[],text[])'::regprocedure);
    a := '    IF registration.siwes_units(s.programme_code, s.current_level, p_semester) IS NOT NULL THEN';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.course_check is not as V663 left it'; END IF;
    d := replace(d, a, '    -- V752: a SIWES student''s Second Semester holds the SIWES course alone, registered on the SIWES page
    IF p_semester = 2 AND registration.siwes_applies(p_student, p_session) THEN
        refusal := ''REG_SIWES_SEMESTER: your Second Semester is your SIWES (industrial training) semester; only your SIWES course is registered in it, on the SIWES page''; RETURN NEXT; RETURN;
    END IF;
' || a);
    EXECUTE d;

    -- the unit rule: the SIWES course''s units alone (the screen meter, the submission and the approval agree)
    d := pg_get_functiondef('registration.unit_rule_base(uuid,integer,text,integer)'::regprocedure);
    a := '    siw AS (SELECT registration.siwes_units(st.programme_code, p_level, p_semester) AS units FROM st WHERE p_semester IS NOT NULL),';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.unit_rule_base is not as V508 left it'; END IF;
    d := replace(d, a, '    -- V752: a SIWES student''s Second Semester (registration.siwes_applies) carries their SIWES course''s units alone, read first;
    -- a programme the Academic Office has not configured keeps V503''s attachment semester
    siw AS (SELECT coalesce(CASE WHEN p_semester = 2 AND registration.siwes_applies(p_student, p_session)
                                 THEN (SELECT coalesce(catalogue.units_for(k.code, st.programme_code, 300), k.units)
                                         FROM catalogue.course k WHERE k.code = registration.siwes_course_for(p_student)) END,
                            registration.siwes_units(st.programme_code, p_level, p_semester)) AS units FROM st WHERE p_semester IS NOT NULL),');
    EXECUTE d;

    -- the submission (the student's, ICT Support''s, the automatic re-validation): the SIWES course alone, paid; the school fees as before
    d := pg_get_functiondef('registration.submit_checks(uuid)'::regprocedure);
    a := '    -- V361: the school fees the student owes for the session must be stated before they can be paid, or cleared';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.submit_checks is not as V664 left it'; END IF;
    d := replace(d, a, '    -- V752: a SIWES student''s Second Semester holds the SIWES course alone, its fee paid; the school fees below still bind
    IF r.semester = 2 AND registration.siwes_applies(r.student_id, r.session) THEN
        SELECT string_agg(DISTINCT o.course_code, '', '') INTO v_gate
          FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
         WHERE e.registration_id = p_registration AND e.status NOT IN (''DROPPED'', ''WITHDRAWN'')
           AND o.course_code IS DISTINCT FROM registration.siwes_course_for(r.student_id)
           AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.course_registration_id = p_registration AND x.offering_id = e.offering_id);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION ''SIWES_COURSE_ONLY: the Second Semester of % is your SIWES (industrial training) semester; it holds the SIWES course (%) alone, not %'',
                r.session, coalesce(registration.siwes_course_for(r.student_id), ''not yet set''), v_gate
            USING ERRCODE = ''23514'', HINT = ''Drop the other courses; the SIWES course is registered on the SIWES page.'';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM finance.siwes_paid(r.student_id, r.session)) THEN
            RAISE EXCEPTION ''SIWES_UNPAID: the SIWES registration fee for % is not paid'', r.session
            USING ERRCODE = ''23514'', HINT = ''Pay the SIWES registration fee on the SIWES page.'';
        END IF;
    END IF;
' || a);
    EXECUTE d;

    -- ICT Support, the Student edit and the Registry preview the refusal: a rule no override sets aside, shown only where SIWES binds
    -- (every other student's checks stay the sixteen they were)
    d := pg_get_functiondef('registration.support_add_checks(uuid,text,integer,uuid)'::regprocedure);
    a := '    message := CASE WHEN c.code IS NULL THEN ''—'' ELSE coalesce(m.basis, c.kind) || CASE WHEN c.kind = ''Elective'' THEN '' — counts within the elective allowance.'' ELSE ''.'' END END;
    RETURN NEXT;
';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.support_add_checks is not as V664 left it'; END IF;
    d := replace(d, a, a || '
    -- V752: a SIWES student''s Second Semester is registered on the SIWES page — the SIWES course alone, once its fee is paid; never set aside
    IF p_semester = 2 AND registration.siwes_applies(p_student, p_session) THEN
        ord := 17; rule := ''SIWES''; label := ''SIWES semester''; advisory := false; overridable := false; passed := false;
        message := CASE WHEN c.code IS NOT NULL AND c.code = registration.siwes_course_for(p_student)
                        THEN c.code || '' is the student''''s SIWES course: the student registers it on the SIWES page once the SIWES registration fee is paid.''
                        ELSE ''The '' || w || '' semester of '' || p_session || '' is the student''''s SIWES (industrial training) semester: it holds the SIWES course''
                             || coalesce('' ('' || registration.siwes_course_for(p_student) || '')'', '''') || '' alone, registered on the SIWES page; no other course is added.'' END;
        RETURN NEXT;
    END IF;
');
    EXECUTE d;

    -- the course registration report: a SIWES registration is labelled SIWES, never an ordinary second-semester registrant
    d := pg_get_functiondef('reporting.course_registration_rows(text,integer,jsonb)'::regprocedure);
    a := '               CASE WHEN c.kind = ''GST'' AND c.general_office = ''GST'' THEN ''GST''';
    IF position(a IN d) = 0 OR position('                WHEN ''OTHER_COURSES'' THEN x.category NOT IN (''GST'', ''EPS'')' IN d) = 0 THEN
        RAISE EXCEPTION 'V752: reporting.course_registration_rows is not as V663 left it';
    END IF;
    d := replace(d, a, '               CASE WHEN EXISTS (SELECT 1 FROM registration.siwes_registration sr WHERE sr.course_registration_id = r.id AND sr.course_code = c.code)
                    THEN ''SIWES''   -- V752: a SIWES registration
                    WHEN c.kind = ''GST'' AND c.general_office = ''GST'' THEN ''GST''');
    d := replace(d, '                WHEN ''OTHER_COURSES'' THEN x.category NOT IN (''GST'', ''EPS'')',
                    '                WHEN ''OTHER_COURSES'' THEN x.category NOT IN (''GST'', ''EPS'', ''SIWES'')');
    EXECUTE d;

    -- the old portal's history loader: a past (closed) session's SIWES semester loads as the old portal held it
    d := pg_get_functiondef('assessment.legacy_semester_load(text,integer,jsonb,boolean,boolean)'::regprocedure);
    IF position('    seen_students uuid[] := ''{}''; seen_codes text[] := ''{}''; seen_keys text[] := ''{}'';' IN d) = 0
       OR position('        PERFORM assessment.ensure_session(p_session);' IN d) = 0
       OR position('    RETURN jsonb_build_object(' IN d) = 0 THEN
        RAISE EXCEPTION 'V752: assessment.legacy_semester_load is not as V672 left it';
    END IF;
    d := replace(d, '    seen_students uuid[] := ''{}''; seen_codes text[] := ''{}''; seen_keys text[] := ''{}'';',
                    '    seen_students uuid[] := ''{}''; seen_codes text[] := ''{}''; seen_keys text[] := ''{}'';
    v_siwes_override text := current_setting(''moaum.siwes_override'', true);   -- V752');
    d := replace(d, '        PERFORM assessment.ensure_session(p_session);',
                    '        PERFORM assessment.ensure_session(p_session);
        -- V752: history: the SIWES rule is set aside for a closed session''s rows only (registration.entry_siwes_only)
        PERFORM set_config(''moaum.siwes_override'', ''on'', true);');
    d := replace(d, '    RETURN jsonb_build_object(',
                    '    PERFORM set_config(''moaum.siwes_override'', coalesce(v_siwes_override, ''''), true);   -- V752
    RETURN jsonb_build_object(');
    EXECUTE d;

    -- an expired SIWES reference regenerated (Fees & payments): the open one, or one at the published fee; paid, closed or not eligible
    -- is said so (finance.siwes_reference refuses each)
    d := pg_get_functiondef('finance.renew_reference(uuid,text)'::regprocedure);
    a := '    ELSIF r.purpose LIKE ''Inter-departmental transfer%'' THEN';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: finance.renew_reference is not as V735 left it'; END IF;
    d := replace(d, a, '    ELSIF r.purpose LIKE ''SIWES registration fee%'' THEN
        -- V752: the SIWES fee of the student''s current session; a reference of another session is not renewed
        IF r.session IS DISTINCT FROM people.student_current_session(p_student) THEN
            RAISE EXCEPTION ''SIWES_CLOSED: SIWES registration for % is over; reference % is not renewed'', r.session, r.reference USING ERRCODE = ''23514'';
        END IF;
        BEGIN
            v_new := finance.siwes_reference(p_student) ->> ''reference'';
        EXCEPTION WHEN check_violation THEN
            IF SQLERRM LIKE ''SIWES_PAID%'' THEN
                RAISE EXCEPTION ''REFERENCE_NOTHING_OWED: the SIWES registration fee for % is paid; reference % is not needed'', r.session, r.reference USING ERRCODE = ''23514'';
            END IF;
            RAISE;
        END;
        RETURN QUERY SELECT x.reference, x.amount, x.expires_at, x.purpose, CASE WHEN x.reference = r.reference THEN ''OPEN'' ELSE ''NEW'' END
          FROM finance.payment_reference x WHERE x.reference = v_new;
        RETURN;
' || a);
    EXECUTE d;

    -- a SIWES payment that registered the course is neither moved by a correction nor archived; nor one whose SIWES credit was refunded
    -- (money spent: settled_kind DESK_REFUND or HAND_REFUND) while it stands there as that credit's SIWES payment (as V751 holds the
    -- Summer's). An open credit follows its payment (finance.siwes_credit_follows_payment); a credit that settles the fee is the fee's
    -- payment, moved as any. The correction desk does not move an old-portal SIWES payment that waits on the Bursary's bank check (V561,
    -- finance.siwes_bank_check): the hold covers the move as it covers the refunds; the archive is not held, since V561's withdrawal of a
    -- record never received archives it. The anchor is V746's line, which V751 extends below it: the SIWES lines go above, whichever of
    -- the two came first.
    a := '    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id   -- V746: a Summer credit the Bursar settled is money spent';
    d := pg_get_functiondef('finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)'::regprocedure);
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: finance.payment_reallocation_check is not as V746 left it'; END IF;
    d := replace(d, a, '    IF EXISTS (SELECT 1 FROM registration.siwes_registration x   -- V752: the SIWES fee of a SIWES course that stands registered
                JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN (''DROPPED'', ''WITHDRAWN'')
               WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id)) THEN
        refusals := refusals || ''REALLOC_LINKED: the payment is the SIWES registration fee of a SIWES course that stands registered; it is not moved''::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.siwes_credit x WHERE x.reference_id = r.id   -- V752: a SIWES credit refunded is money spent
                  AND finance.is_siwes_purpose(r.purpose) AND r.student_id = x.student_id AND r.session = x.session   -- while it stands there
                  AND x.settled_kind IN (''DESK_REFUND'', ''HAND_REFUND'')) THEN
        refusals := refusals || ''REALLOC_LINKED: the Bursar recorded the SIWES credit of this payment as refunded or applied; that money is spent''::text;
    END IF;
    IF finance.siwes_bank_check(r.id) IS NOT NULL THEN   -- V752 (V561): a possible bank double charge is not moved until the bank is asked
        refusals := refusals || (''REALLOC_SIWES_CHECK_BANK: '' || finance.siwes_bank_check(r.id));
    END IF;
' || a);
    EXECUTE d;
    d := pg_get_functiondef('finance.payment_archive_refusals(uuid)'::regprocedure);
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: finance.payment_archive_refusals is not as V746 left it'; END IF;
    d := replace(d, a, '    IF EXISTS (SELECT 1 FROM registration.siwes_registration x   -- V752: the SIWES fee of a SIWES course that stands registered
                JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id AND e.status NOT IN (''DROPPED'', ''WITHDRAWN'')
               WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id)) THEN
        refusals := refusals || ''PAR_LINKED: the payment is the SIWES registration fee of a SIWES course that stands registered; the registration is settled first''::text;
    END IF;
    IF EXISTS (SELECT 1 FROM finance.siwes_credit x WHERE x.reference_id = r.id   -- V752: a SIWES credit refunded is money spent
                  AND finance.is_siwes_purpose(r.purpose) AND r.student_id = x.student_id AND r.session = x.session   -- while it stands there
                  AND x.settled_kind IN (''DESK_REFUND'', ''HAND_REFUND'')) THEN
        refusals := refusals || ''PAR_LINKED: the Bursar recorded the SIWES credit of this payment as refunded or applied; that money is spent''::text;
    END IF;
' || a);
    EXECUTE d;

    -- the old fees history started over (V499's reset): an old-portal payment a SIWES registration was made on stays, as the payments
    -- other desks hold do (counted among those kept); otherwise the registration would go with it (ON DELETE CASCADE). So does one whose
    -- SIWES credit the Bursar settled by hand (settled_kind HAND_REFUND, whatever its note says: applying one by hand is refused,
    -- SIWES_CREDIT_MOVE_IT): the credit is the record that the money was given back, and the reload would bring the payment back with
    -- nothing given back on it. A refund-desk refund and a move are kept by their own rows (finance.refund, finance.payment_reallocation).
    -- An open credit, or one the database settled itself (SETTLES: settling the fee in another's absence), records nothing the Bursar
    -- did: it goes with its payment (ON DELETE CASCADE) and the reload makes it again (trg_siwes_settling_follows_insert) — a row loaded
    -- under the wrong student is taken away
    d := pg_get_functiondef('finance.reset_legacy_payments(text,text,integer)'::regprocedure);
    a := '                   AND r.archived_at IS NULL AND NOT EXISTS (SELECT 1 FROM finance.payment_archive pa WHERE pa.payment_id = r.id)';
    IF position(a IN d) = 0
       OR position('                    OR r.id IN (SELECT pa.payment_id FROM finance.payment_archive pa)) AS linked' IN d) = 0 THEN
        RAISE EXCEPTION 'V752: finance.reset_legacy_payments is not as V670 left it';
    END IF;
    d := replace(d, a, a || '
                   -- V752: an old-portal SIWES payment a SIWES registration was made on, or whose SIWES credit the Bursar settled by hand, stays
                   AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration sx WHERE sx.legacy_payment_id = r.id)
                   AND NOT EXISTS (SELECT 1 FROM finance.siwes_credit sc WHERE sc.reference_id = r.id AND sc.settled_kind = ''HAND_REFUND'')');
    d := replace(d, '                    OR r.id IN (SELECT pa.payment_id FROM finance.payment_archive pa)) AS linked',
                    '                    OR r.id IN (SELECT pa.payment_id FROM finance.payment_archive pa)
                    OR r.id IN (SELECT sx.legacy_payment_id FROM registration.siwes_registration sx WHERE sx.legacy_payment_id IS NOT NULL)   -- V752
                    OR r.id IN (SELECT sc.reference_id FROM finance.siwes_credit sc WHERE sc.settled_kind = ''HAND_REFUND'')) AS linked   -- V752');
    EXECUTE d;

    -- the refund desk: no refund is raised, nor approved, against the payment a standing SIWES registration was made on (the
    -- registration is undone first) or whose SIWES credit the Bursar recorded refunded, nor for a part of a SIWES payment (the fee is all
    -- or nothing: REFUND_SIWES_PART); a refund approved or paid on a SIWES payment takes it out of the fee (finance.siwes_standing) and
    -- settles its credit (trg_siwes_refund_follows)
    d := pg_get_functiondef('finance.propose_refund(uuid,text,text,numeric,text,text,text,text)'::regprocedure);
    a := '        -- V350: with the refunds already raised against it and not rejected';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: finance.propose_refund is not as V670 left it'; END IF;
    d := replace(d, a, '        -- V752: the SIWES fee a standing SIWES registration was made on; a SIWES payment refunded whole
        PERFORM finance.siwes_refund_refusal(v_src, p_amount);
' || a);
    EXECUTE d;
    -- approved: the same again (a SIWES registration made on it, or a part raised, before)
    d := pg_get_functiondef('finance.approve_refund(uuid)'::regprocedure);
    a := '    UPDATE finance.refund SET state = ''APPROVED'', approved_by = who, approved_at = now() WHERE id = p_id;';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: finance.approve_refund is not as V043 left it'; END IF;
    d := replace(d, a, '    PERFORM finance.siwes_refund_refusal(r.source_reference, r.amount);   -- V752: a SIWES registration made on it since it was raised; a part
' || a);
    EXECUTE d;

    -- the student's own doors (K5): a SIWES student's Second Semester sheds its ordinary courses on Course Registration, never the
    -- SIWES course a standing SIWES registration holds (an office drops that: registration.support_drop calls this function for an
    -- office, its actor's office not the student's). While no SIWES registration stands there, a carry-over or deferred course placed
    -- before SIWES bound the student is dropped too (registration.siwes_sheds): it waits for a later semester
    d := pg_get_functiondef('registration.student_drop(uuid,text,integer,uuid)'::regprocedure);
    a := '    -- V611: one the student declared (its result not on the portal) is dropped as it was added';
    IF position(a IN d) = 0
       OR position('    IF e.entry_type = ''CARRYOVER'' AND e.added_as IS DISTINCT FROM ''CARRY_OVER_DECLARED'' THEN' IN d) = 0
       OR position('    IF e.entry_type = ''DEFERRED'' THEN' IN d) = 0 THEN
        RAISE EXCEPTION 'V752: registration.student_drop is not as V611 left it';
    END IF;
    d := replace(d, a, '    -- V752: the SIWES course of a standing SIWES registration is the semester''s registration; the student does not drop it. An
    -- office does (ICT Support, the Student edit: registration.support_drop, through its own checks), a SIWES registration made in error
    IF coalesce(nullif(current_setting(''moaum.actor_office'', true), ''''), ''student'') = ''student''
       AND EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.course_registration_id = r.id AND x.offering_id = p_offering) THEN
        RAISE EXCEPTION ''SIWES_COURSE_KEPT: % is your SIWES course, registered on the SIWES page; it is not dropped here'', (SELECT o.course_code FROM catalogue.offering o WHERE o.id = p_offering)
            USING ERRCODE = ''23514'', HINT = ''The Academic Office or ICT Support undoes a SIWES registration.'';
    END IF;
' || a);
    d := replace(d, '    IF e.entry_type = ''CARRYOVER'' AND e.added_as IS DISTINCT FROM ''CARRY_OVER_DECLARED'' THEN',
                    '    -- V752: in a Second Semester SIWES binds, no SIWES registration made, a carry-over or deferred course waits for a later semester
    IF e.entry_type = ''CARRYOVER'' AND e.added_as IS DISTINCT FROM ''CARRY_OVER_DECLARED'' AND NOT registration.siwes_sheds(p_student, p_session, p_semester) THEN');
    d := replace(d, '    IF e.entry_type = ''DEFERRED'' THEN',
                    '    IF e.entry_type = ''DEFERRED'' AND NOT registration.siwes_sheds(p_student, p_session, p_semester) THEN');
    EXECUTE d;
    -- the reset clears them with the chosen courses (as V682 clears a spillover registration's), the student's or an office's
    d := pg_get_functiondef('registration.student_reset(uuid,text,integer,text,text)'::regprocedure);
    a := '    v_spill := registration.spillover_registration(p_student, p_session);';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.student_reset is not as V682 left it'; END IF;
    d := replace(d, a, '    v_spill := registration.spillover_registration(p_student, p_session)
               -- V752: a Second Semester SIWES binds, no SIWES registration made: its carry-overs and deferred courses wait for a later semester
               OR registration.siwes_sheds(p_student, p_session, p_semester);');
    EXECUTE d;
    -- ICT Support and the Student edit drop them too (support_drop_checks' NOT_CARRYOVER passes for that semester), and any course in the
    -- way of the SIWES course with no override: the SIWES gate (REGISTRATION_WINDOW) holds the SIWES course's drop, never theirs
    d := pg_get_functiondef('registration.support_drop_checks(uuid,text,integer,uuid)'::regprocedure);
    a := '    passed := e.offering_id IS NULL OR e.entry_type NOT IN (''CARRYOVER'', ''DEFERRED'') OR coalesce(e.added_as = ''CARRY_OVER_DECLARED'', false);   -- V674: as registration.student_drop (V611)';
    IF position(a IN d) = 0 OR position('                    WHEN passed THEN ''A '' || lower(coalesce(e.entry_type, ''current'')) || '' course.''' IN d) = 0
       OR (length(d) - length(replace(d, '    passed := v_gate IS NULL; message := coalesce(v_gate, ''Open.'');', ''))) / length('    passed := v_gate IS NULL; message := coalesce(v_gate, ''Open.'');') <> 1 THEN
        RAISE EXCEPTION 'V752: registration.support_drop_checks is not as V674 left it';
    END IF;
    d := replace(d, '    passed := v_gate IS NULL; message := coalesce(v_gate, ''Open.'');',
                    '    passed := v_gate IS NULL; message := coalesce(v_gate, ''Open.'');
    -- V752: a course in the way of the SIWES course (registration.siwes_sheds: a Second Semester SIWES binds, no SIWES registration made)
    -- waits for a later semester; the SIWES gate holds only the SIWES course
    IF NOT passed AND registration.siwes_sheds(p_student, p_session, p_semester) AND v_code IS DISTINCT FROM registration.siwes_course_for(p_student)
       AND NOT EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.student_id = p_student AND x.session = p_session AND x.offering_id = p_offering) THEN
        passed := true;
        message := coalesce(v_code, ''The course'') || '' waits for a later semester: the SIWES semester holds the SIWES course alone.'';
    END IF;');
    d := replace(d, a, '    passed := e.offering_id IS NULL OR e.entry_type NOT IN (''CARRYOVER'', ''DEFERRED'') OR coalesce(e.added_as = ''CARRY_OVER_DECLARED'', false)   -- V674: as registration.student_drop (V611)
              OR registration.siwes_sheds(p_student, p_session, p_semester);   -- V752: it waits for a later semester');
    d := replace(d, '                    WHEN passed THEN ''A '' || lower(coalesce(e.entry_type, ''current'')) || '' course.''',
                    '                    WHEN passed AND e.entry_type IN (''CARRYOVER'', ''DEFERRED'') THEN coalesce(v_code, ''The course'') || '' waits for a later semester: the SIWES semester holds the SIWES course alone.''   -- V752
                    WHEN passed THEN ''A '' || lower(coalesce(e.entry_type, ''current'')) || '' course.''');
    EXECUTE d;
    d := pg_get_functiondef('registration.reset_refusal(uuid,text,integer,text)'::regprocedure);
    a := '    IF r.status = ''LOCKED'' THEN
        RETURN ''REG_RESET_LOCKED: the '' || r.session || '' semester '' || r.semester || '' registration is locked; it is the examined record'';
    END IF;';
    IF position(a IN d) = 0 THEN RAISE EXCEPTION 'V752: registration.reset_refusal is not as V491 left it'; END IF;
    d := replace(d, a, a || '
    -- V752: the student''s reset would take the SIWES course a standing SIWES registration holds (it holds nothing else)
    IF p_source = ''STUDENT_PORTAL'' AND EXISTS (SELECT 1 FROM registration.siwes_registration x
                                                  JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                                                           AND e.status NOT IN (''DROPPED'', ''WITHDRAWN'')
                                                 WHERE x.course_registration_id = r.id) THEN
        RETURN ''REG_RESET_SIWES: the '' || r.session || '' Second Semester registration is your SIWES registration, made on the SIWES page; it is not reset'';
    END IF;');
    EXECUTE d;

    -- V561's withdrawal of an old-portal record as never received (Payments not received, and the bank check's NOT_RECEIVED, which
    -- raises one for each record it names): never of a SIWES payment a standing SIWES registration rests on while the student holds no
    -- other SIWES payment for the session — the registration would stand on money the bank never received. With another standing, the
    -- registration follows the payment that settles once the record is withdrawn (trg_siwes_settling_follows_payment). Nor of a SIWES
    -- payment whose SIWES credit was refunded, by the Bursar's hand or on the refund desk (settled_kind HAND_REFUND, DESK_REFUND): the
    -- money given back would stand on a payment the bank never received, and drop out of the SIWES payments report and the credits
    -- list — as V561 refuses a school-fees record whose excess was decided (PAY_NOT_RECEIVED_DECIDED) and the archive desk a linked one
    -- (PAR_LINKED). Read before V502's link test, so a refund-desk refund that settled the credit is named for what it is; a refund
    -- that stands on the desk unsettled is V502's link (PAY_NOT_RECEIVED_LINKED)
    d := pg_get_functiondef('finance.not_received_refusal(uuid)'::regprocedure);
    a := '             WHEN r.purpose LIKE ''School fees%'' AND EXISTS (SELECT 1 FROM finance.overpayment_settled(r.student_id, r.session)) THEN ''PAY_NOT_RECEIVED_DECIDED''';
    IF position(a IN d) = 0
       OR position('             WHEN finance.payment_reference_linked(r.reference, r.id) THEN ''PAY_NOT_RECEIVED_LINKED''' IN d) = 0 THEN
        RAISE EXCEPTION 'V752: finance.not_received_refusal is not as V670 left it';
    END IF;
    d := replace(d, '             WHEN finance.payment_reference_linked(r.reference, r.id) THEN ''PAY_NOT_RECEIVED_LINKED''',
                    '             -- V752: a SIWES payment whose SIWES credit was refunded (by hand or on the refund desk)
             WHEN finance.is_siwes_purpose(r.purpose)
                  AND EXISTS (SELECT 1 FROM finance.siwes_credit c WHERE c.reference_id = r.id AND c.settled_kind IN (''DESK_REFUND'', ''HAND_REFUND''))
                  THEN ''PAY_NOT_RECEIVED_SIWES_REFUNDED''
             WHEN finance.payment_reference_linked(r.reference, r.id) THEN ''PAY_NOT_RECEIVED_LINKED''');
    d := replace(d, a, a || '
             -- V752: a SIWES payment a standing SIWES registration rests on, the student holding no other SIWES payment for the session
             WHEN finance.is_siwes_purpose(r.purpose)
                  AND EXISTS (SELECT 1 FROM registration.siwes_registration x
                                JOIN registration.entry e ON e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                                         AND e.status NOT IN (''DROPPED'', ''WITHDRAWN'')
                               WHERE r.id IN (x.payment_reference_id, x.legacy_payment_id))
                  AND NOT EXISTS (SELECT 1 FROM finance.siwes_standing(r.student_id, r.session) o WHERE o.reference_id <> r.id)
                  THEN ''PAY_NOT_RECEIVED_SIWES_REGISTERED''');
    EXECUTE d;
    d := pg_get_functiondef('finance.raise_not_received(text)'::regprocedure);
    a := '      ELSE NULL;
    END CASE;';
    IF position(a IN d) = 0 OR position('PAY_NOT_RECEIVED_DECIDED' IN d) = 0 THEN RAISE EXCEPTION 'V752: finance.raise_not_received is not as V670 left it'; END IF;
    d := replace(d, a, '      WHEN ''PAY_NOT_RECEIVED_SIWES_REGISTERED'' THEN   -- V752
        RAISE EXCEPTION ''PAY_NOT_RECEIVED_SIWES_REGISTERED: a SIWES course stands registered on this payment and the student holds no other SIWES payment for the session; withdrawn, it would leave that registration standing on money the bank never received'' USING ERRCODE = ''23514'',
            HINT = ''The Academic Office or ICT Support undoes the SIWES registration first.'';
      WHEN ''PAY_NOT_RECEIVED_SIWES_REFUNDED'' THEN   -- V752
        RAISE EXCEPTION ''PAY_NOT_RECEIVED_SIWES_REFUNDED: the SIWES credit of this payment is recorded refunded (by the Bursar, or on the refund desk); withdrawn as never received, it would leave money given back on a payment the bank never received'' USING ERRCODE = ''23514'',
            HINT = ''The Bursar reopens the credit first if its refund was recorded in error; a refund made stays, and the payment with it.'';
' || a);
    EXECUTE d;
END $$;

-- ── 11 · the Academic Office's acts (academic, registrar, dregistrar, super — re-checked here) ──────────────────────────────────
CREATE FUNCTION registration.siwes_office() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL
       OR coalesce(nullif(current_setting('moaum.actor_office', true), ''), '-') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'SIWES_OFFICE: SIWES registration is set by the Academic Office or the Registry' USING ERRCODE = '23514';
    END IF;
END $$;

CREATE FUNCTION registration.siwes_session_ok(p_session text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s policy.academic_session;
BEGIN
    SELECT * INTO s FROM policy.academic_session WHERE name = p_session;
    IF s.id IS NULL OR s.state = 'CANCELLED' OR s.merged_into IS NOT NULL THEN
        RAISE EXCEPTION 'SIWES_SESSION: % is not a session on the calendar that holds classes', coalesce(p_session, '(none)') USING ERRCODE = '23514';
    END IF;
END $$;

/* the students a session's SIWES has begun for: a SIWES registration made, or a portal SIWES payment that stands (paid under this
   configuration: registration.siwes_applies keeps them bound). An old-portal payment does not count: it was paid before the programme was
   configured, binds nobody by itself, and never holds the configuration (a programme added by mistake is taken out again) */
CREATE FUNCTION registration.siwes_in_use_students(p_session text, p_programme text DEFAULT NULL)
RETURNS TABLE(student_id uuid, programme_code text, curriculum text) LANGUAGE sql STABLE AS $$
    SELECT s.id, s.programme_code, s.curriculum_version
      FROM people.student s
     WHERE (p_programme IS NULL OR s.programme_code = p_programme)
       AND (EXISTS (SELECT 1 FROM registration.siwes_registration x WHERE x.student_id = s.id AND x.session = p_session)
            OR EXISTS (SELECT 1 FROM finance.siwes_standing(s.id, p_session) x WHERE x.source = 'PORTAL'));
$$;

/* whether a session's SIWES has begun: how many students have paid or registered (registration.siwes_in_use_students) */
CREATE FUNCTION registration.siwes_in_use(p_session text, p_programme text DEFAULT NULL) RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT count(*)::int FROM registration.siwes_in_use_students(p_session, p_programme);
$$;

/* the period stated or changed. OPEN needs both registration dates and both training dates, and every 300 Level student of a configured
   programme reached by a SIWES course (SIWES_COURSE_MISSING names the programmes: the Academic Office maps their course first); a
   period no longer open closes its open references; a period in use is never put back to a draft */
CREATE FUNCTION registration.siwes_set_period(p_session text, p_state text, p_registration_opens date, p_registration_closes date,
                                              p_training_starts date, p_training_ends date, p_duration_months integer, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_state text := upper(coalesce(nullif(btrim(p_state), ''), 'DRAFT')); n int; v_missing text;
BEGIN
    PERFORM registration.siwes_office();
    PERFORM registration.siwes_session_ok(p_session);
    IF v_state NOT IN ('DRAFT', 'OPEN', 'CLOSED') THEN
        RAISE EXCEPTION 'SIWES_PERIOD_STATE: a SIWES period is DRAFT, OPEN or CLOSED' USING ERRCODE = '23514';
    END IF;
    IF v_state = 'OPEN' AND (p_registration_opens IS NULL OR p_registration_closes IS NULL OR p_training_starts IS NULL OR p_training_ends IS NULL) THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DATES: SIWES registration opens with its registration window and its training period dated' USING ERRCODE = '23514',
            HINT = 'Give the registration opening and closing dates and the training commencement and expected completion dates.';
    END IF;
    IF p_registration_opens IS NOT NULL AND p_registration_closes IS NOT NULL AND p_registration_closes < p_registration_opens THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DATES: registration closes (%) before it opens (%)', p_registration_closes, p_registration_opens USING ERRCODE = '23514';
    END IF;
    IF p_training_starts IS NOT NULL AND p_training_ends IS NOT NULL AND p_training_ends <= p_training_starts THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DATES: the training ends (%) on or before it starts (%)', p_training_ends, p_training_starts USING ERRCODE = '23514';
    END IF;
    IF p_duration_months IS NOT NULL AND p_duration_months NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'SIWES_PERIOD_DURATION: the duration is 1 to 12 months' USING ERRCODE = '23514';
    END IF;
    IF v_state = 'OPEN' THEN
        SELECT string_agg(u.programme || ' (' || u.programme_code || ', ' || coalesce(u.curriculum, 'no curriculum') || ': ' || u.students || ')', '; '
                          ORDER BY u.programme, u.curriculum) INTO v_missing
          FROM registration.siwes_unmapped(p_session) u;
        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION 'SIWES_COURSE_MISSING: no SIWES course reaches the 300 Level students of %; SIWES registration does not open until each is mapped', v_missing
                USING ERRCODE = '23514', HINT = 'Set the SIWES course of each programme (for its curriculum, or for every curriculum), or take the programme out of the session.';
        END IF;
    END IF;
    IF v_state = 'DRAFT' AND EXISTS (SELECT 1 FROM registration.siwes_period WHERE session = p_session AND state <> 'DRAFT') THEN
        n := registration.siwes_in_use(p_session);
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_PERIOD_IN_USE: % student(s) have paid or registered for SIWES in %; the period is closed, never put back to a draft', n, p_session
                USING ERRCODE = '23514';
        END IF;
    END IF;
    INSERT INTO registration.siwes_period (session, state, registration_opens, registration_closes, training_starts, training_ends,
                                           duration_months, note, set_by, set_office)
    VALUES (p_session, v_state, p_registration_opens, p_registration_closes, p_training_starts, p_training_ends,
            coalesce(p_duration_months, 6), nullif(btrim(p_note), ''), who, v_office)
    ON CONFLICT (session) DO UPDATE SET state = EXCLUDED.state, registration_opens = EXCLUDED.registration_opens,
           registration_closes = EXCLUDED.registration_closes, training_starts = EXCLUDED.training_starts, training_ends = EXCLUDED.training_ends,
           duration_months = EXCLUDED.duration_months, note = EXCLUDED.note, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = now();
    -- no longer open: the open references of the session close (one already on its way to a bank still pays: a payment is never lost)
    IF v_state <> 'OPEN' THEN
        UPDATE finance.payment_reference SET expires_at = now()
         WHERE session = p_session AND purpose LIKE 'SIWES registration fee%' AND confirmed_at IS NULL AND archived_at IS NULL AND expires_at > now();
    END IF;
    RETURN registration.siwes_period_json(p_session);
END $$;

/* a programme taking part in a session (its period made a draft when there is none yet). A period no longer a draft binds the
   programme's students as it is added: added only while each of its 300 Level students is reached by a live SIWES course
   (SIWES_COURSE_MISSING, as registration.siwes_set_period opens a period) — never a cohort held to a course it cannot register */
CREATE FUNCTION registration.siwes_add_programme(p_session text, p_programme text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_code text := upper(btrim(coalesce(p_programme, ''))); p ref.programme; n int; v_missing text;
BEGIN
    PERFORM registration.siwes_office();
    PERFORM registration.siwes_session_ok(p_session);
    SELECT * INTO p FROM ref.programme WHERE code = v_code;
    IF p.code IS NULL OR p.archived THEN
        RAISE EXCEPTION 'SIWES_PROGRAMME: % is not a programme on the register', v_code USING ERRCODE = '23514';
    END IF;
    IF p.category <> 'UNDER GRADUATE' THEN
        RAISE EXCEPTION 'SIWES_NOT_UNDERGRADUATE: % is a postgraduate programme; SIWES registration is for undergraduates', p.name USING ERRCODE = '23514';
    END IF;
    INSERT INTO registration.siwes_period (session, state, set_by, set_office) VALUES (p_session, 'DRAFT', who, v_office) ON CONFLICT (session) DO NOTHING;
    INSERT INTO registration.siwes_programme (session, programme_code, added_by, added_office) VALUES (p_session, v_code, who, v_office)
    ON CONFLICT (session, programme_code) DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 AND EXISTS (SELECT 1 FROM registration.siwes_period WHERE session = p_session AND state <> 'DRAFT') THEN
        SELECT string_agg(u.programme || ' (' || u.programme_code || ', ' || coalesce(u.curriculum, 'no curriculum') || ': ' || u.students || ')', '; '
                          ORDER BY u.curriculum) INTO v_missing
          FROM registration.siwes_unmapped(p_session) u WHERE u.programme_code = v_code;
        IF v_missing IS NOT NULL THEN
            RAISE EXCEPTION 'SIWES_COURSE_MISSING: no SIWES course reaches the 300 Level students of %; the programme takes part in % only once each is mapped', v_missing, p_session
                USING ERRCODE = '23514', HINT = 'Set the programme''s SIWES course (for its curriculum, or for every curriculum) first, then add the programme.';
        END IF;
    END IF;
    RETURN registration.siwes_config(p_session);
END $$;

/* a programme taken out of a session: never once a student of it has paid or registered for that session */
CREATE FUNCTION registration.siwes_remove_programme(p_session text, p_programme text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_code text := upper(btrim(coalesce(p_programme, ''))); n int;
BEGIN
    PERFORM registration.siwes_office();
    n := registration.siwes_in_use(p_session, v_code);
    IF n > 0 THEN
        RAISE EXCEPTION 'SIWES_PROGRAMME_IN_USE: % student(s) of % have paid or registered for SIWES in %; the programme stays', n, v_code, p_session
            USING ERRCODE = '23514', HINT = 'Close the period instead; a payment is never lost and a registration made stands.';
    END IF;
    DELETE FROM registration.siwes_programme WHERE session = p_session AND programme_code = v_code;
    RETURN registration.siwes_config(p_session);
END $$;

/* the SIWES course of a programme, for a curriculum or for every curriculum (NULL): an existing course of the catalogue, taught in
   the Second Semester and not ended — never a course made here. No course: the mapping is taken away — never while students of the
   programme who have paid or registered SIWES in a session it takes part in would be left with no live SIWES course (SIWES_COURSE_IN_USE:
   they stay bound to SIWES; the mapping is replaced by another course instead). */
CREATE FUNCTION registration.siwes_set_course(p_programme text, p_curriculum text, p_course text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_prog text := upper(btrim(coalesce(p_programme, ''))); v_cur text := upper(nullif(btrim(coalesce(p_curriculum, '')), ''));
        v_raw text := regexp_replace(upper(btrim(coalesce(p_course, ''))), '\s+', ' ', 'g'); c catalogue.course; p ref.programme;
        n int; v_sessions text;
BEGIN
    PERFORM registration.siwes_office();
    SELECT * INTO p FROM ref.programme WHERE code = v_prog;
    IF p.code IS NULL THEN RAISE EXCEPTION 'SIWES_PROGRAMME: % is not a programme on the register', v_prog USING ERRCODE = '23514'; END IF;
    IF p.category <> 'UNDER GRADUATE' THEN
        RAISE EXCEPTION 'SIWES_NOT_UNDERGRADUATE: % is a postgraduate programme; SIWES registration is for undergraduates', p.name USING ERRCODE = '23514';
    END IF;
    IF v_cur IS NOT NULL AND v_cur NOT IN ('CCMAS', 'BMAS') THEN
        RAISE EXCEPTION 'SIWES_CURRICULUM: a curriculum is CCMAS or BMAS (or none, for every curriculum)' USING ERRCODE = '23514';
    END IF;
    IF v_raw = '' THEN
        DELETE FROM registration.siwes_course WHERE programme_code = v_prog AND curriculum IS NOT DISTINCT FROM v_cur;
        -- the students who paid or registered, in any session the programme takes part in, whom no live course would reach now
        SELECT count(DISTINCT u.student_id), string_agg(DISTINCT sp.session, ', ') INTO n, v_sessions
          FROM registration.siwes_programme sp
          CROSS JOIN LATERAL registration.siwes_in_use_students(sp.session, v_prog) u
         WHERE sp.programme_code = v_prog
           AND NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = registration.siwes_course_of(v_prog, u.curriculum) AND k.state <> 'ENDED');
        IF n > 0 THEN
            RAISE EXCEPTION 'SIWES_COURSE_IN_USE: % student(s) of % have paid or registered for SIWES (%) and would be left with no SIWES course; the mapping is replaced by another course, never taken away',
                n, v_prog, v_sessions USING ERRCODE = '23514', HINT = 'Set another live Second Semester course for the programme instead.';
        END IF;
        RETURN jsonb_build_object('programmeCode', v_prog, 'curriculum', v_cur, 'course', NULL);
    END IF;
    SELECT * INTO c FROM catalogue.course WHERE code = coalesce(catalogue.resolve_course_code(v_raw), v_raw);
    IF c.code IS NULL THEN
        RAISE EXCEPTION 'SIWES_COURSE_UNKNOWN: there is no course % in the catalogue; a SIWES course is an existing course, never one made here', v_raw
            USING ERRCODE = '23514', HINT = 'The department adds the course to the catalogue first.';
    END IF;
    IF c.state = 'ENDED' THEN
        RAISE EXCEPTION 'SIWES_COURSE_ENDED: % has ended and is not taught', c.code USING ERRCODE = '23514';
    END IF;
    IF NOT catalogue.runs_in(c.semester, c.both_semesters, 2) THEN
        RAISE EXCEPTION 'SIWES_COURSE_SEMESTER: % is taught in the first semester; the SIWES course is a Second Semester course', c.code USING ERRCODE = '23514';
    END IF;
    INSERT INTO registration.siwes_course (programme_code, curriculum, course_code, set_by, set_office) VALUES (v_prog, v_cur, c.code, who, v_office)
    ON CONFLICT (programme_code, (coalesce(curriculum, ''))) DO UPDATE SET course_code = EXCLUDED.course_code, set_by = EXCLUDED.set_by,
           set_office = EXCLUDED.set_office, set_at = now();
    RETURN jsonb_build_object('programmeCode', v_prog, 'curriculum', v_cur, 'course', registration.siwes_course_json(c.code, v_prog));
END $$;

-- ── 12 · the Bursary's acts: the fee stated (bursar, studentaccounts, super) and published (bursar, super); a credit settled ────
/* a person's name as the Bursary's pages print it */
CREATE FUNCTION finance.siwes_person_name(p_person uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT nullif(concat_ws(', ', nullif(btrim(pp.surname), ''), nullif(btrim(pp.given_names), '')), '') FROM iam.person pp WHERE pp.id = p_person;
$$;

/* the SIWES fee of a session as the Fee Setup page reads it: the amount and state (the figure in force once published), who published
   it, the draft waiting for the Bursar (null when none) and every statement and publication */
CREATE FUNCTION finance.siwes_fee_view(p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'session', p_session,
        'amount', f.amount, 'state', f.state, 'note', f.note,
        'statedAt', f.stated_at, 'statedOffice', f.stated_office,
        'publishedAt', f.published_at, 'publishedOffice', f.published_office, 'publishedBy', f.published_by,
        'publishedByName', finance.siwes_person_name(f.published_by),
        'draft', CASE WHEN f.draft_amount IS NULL THEN NULL
                      ELSE jsonb_build_object('amount', f.draft_amount, 'note', f.draft_note, 'by', f.drafted_by, 'byName', finance.siwes_person_name(f.drafted_by),
                                              'office', f.drafted_office, 'at', f.drafted_at) END,
        'history', coalesce((SELECT jsonb_agg(jsonb_build_object('action', h.action, 'amount', h.amount, 'wasAmount', h.was_amount, 'wasState', h.was_state,
                                                                'note', h.note, 'by', h.changed_by, 'byName', finance.siwes_person_name(h.changed_by),
                                                                'office', h.changed_office, 'at', h.changed_at) ORDER BY h.changed_at DESC, h.id)
                               FROM finance.siwes_fee_change h WHERE h.session = p_session), '[]'::jsonb))
      FROM (SELECT 1) one LEFT JOIN finance.siwes_fee f ON f.session = p_session;
$$;

/* the fee stated (bursar, studentaccounts, super): a draft. A fee never published is its draft (amount and draft alike) until published;
   a published fee stays in force as it is while the restatement waits for the Bursar — Student Accounts never withdraws it */
CREATE FUNCTION finance.siwes_fee_state(p_session text, p_amount numeric, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_amount numeric := round(p_amount, 2); v_note text := nullif(btrim(p_note), '');
BEGIN
    IF who IS NULL OR coalesce(v_office, '-') NOT IN ('bursar', 'studentaccounts', 'super') THEN
        RAISE EXCEPTION 'SIWES_FEE_OFFICE: the SIWES registration fee is stated by the Bursary' USING ERRCODE = '23514';
    END IF;
    PERFORM registration.siwes_session_ok(p_session);
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'SIWES_FEE_AMOUNT: the SIWES registration fee is an amount above nothing' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.siwes_fee (session, amount, state, note, stated_by, stated_office, draft_amount, draft_note, drafted_by, drafted_office, drafted_at)
    VALUES (p_session, v_amount, 'DRAFT', v_note, who, v_office, v_amount, v_note, who, v_office, now())
    ON CONFLICT (session) DO UPDATE
       SET draft_amount = EXCLUDED.draft_amount, draft_note = EXCLUDED.draft_note, drafted_by = EXCLUDED.drafted_by,
           drafted_office = EXCLUDED.drafted_office, drafted_at = EXCLUDED.drafted_at,
           -- never published: the fee is its draft
           amount = CASE WHEN finance.siwes_fee.state = 'PUBLISHED' THEN finance.siwes_fee.amount ELSE EXCLUDED.amount END,
           note = CASE WHEN finance.siwes_fee.state = 'PUBLISHED' THEN finance.siwes_fee.note ELSE EXCLUDED.note END,
           stated_by = CASE WHEN finance.siwes_fee.state = 'PUBLISHED' THEN finance.siwes_fee.stated_by ELSE EXCLUDED.stated_by END,
           stated_office = CASE WHEN finance.siwes_fee.state = 'PUBLISHED' THEN finance.siwes_fee.stated_office ELSE EXCLUDED.stated_office END,
           stated_at = CASE WHEN finance.siwes_fee.state = 'PUBLISHED' THEN finance.siwes_fee.stated_at ELSE now() END;
    RETURN finance.siwes_fee_view(p_session);
END $$;

/* the draft published (bursar, super): it becomes the fee in force — the published figure it replaces is in the history — and the draft
   is cleared. Nothing waiting: the fee as it is */
CREATE FUNCTION finance.siwes_fee_publish(p_session text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR coalesce(v_office, '-') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'SIWES_FEE_OFFICE: the SIWES registration fee is published by the Bursar' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.siwes_fee
       SET amount = coalesce(draft_amount, amount), note = CASE WHEN draft_amount IS NOT NULL THEN draft_note ELSE note END,
           stated_by = coalesce(drafted_by, stated_by), stated_office = coalesce(drafted_office, stated_office), stated_at = coalesce(drafted_at, stated_at),
           state = 'PUBLISHED', published_by = who, published_office = v_office, published_at = now(),
           draft_amount = NULL, draft_note = NULL, drafted_by = NULL, drafted_office = NULL, drafted_at = NULL
     WHERE session = p_session AND (state = 'DRAFT' OR draft_amount IS NOT NULL);
    IF NOT FOUND AND NOT EXISTS (SELECT 1 FROM finance.siwes_fee WHERE session = p_session) THEN
        RAISE EXCEPTION 'SIWES_FEE_NOT_STATED: no SIWES registration fee is stated for %', p_session USING ERRCODE = '23514';
    END IF;
    RETURN finance.siwes_fee_view(p_session);
END $$;

/* why the Bursar may not settle a SIWES credit as stated (NULL: it may) — the tests finance.siwes_credit_settle applies, and that the
   credits list's can_refund reads (as the Summer's since V742 and V751): the credit open (SIWES_CREDIT_UNKNOWN); its payment confirmed,
   not archived for review and still the credit's SIWES payment (SIWES_CREDIT_HELD); a SIWES credit is the whole of its payment, so it is
   applied by moving the payment on the payment correction desk, which records it (SIWES_CREDIT_MOVE_IT) — by hand it would freeze the
   payment; no refund raised on the refund desk against the payment and not rejected (SIWES_CREDIT_REFUND_DESK: the desk gives it back,
   and its approval settles the credit); never an old-portal payment that waits on the Bursary's bank check (SIWES_CREDIT_CHECK_BANK,
   V561: finance.siwes_bank_check — read before the next test, so that a credit of a day the bank check holds says what it waits on even
   where it settles the fee meanwhile); never the payment that now settles the fee or that a standing SIWES registration was made on
   (SIWES_CREDIT_SETTLES: refunding it would leave the student unpaid). What is left to record by hand is a refund. */
CREATE FUNCTION finance.siwes_credit_refusal(p_credit uuid, p_state text) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE x finance.siwes_credit; pr finance.payment_reference; v_state text := upper(btrim(coalesce(p_state, ''))); v_bank text;
BEGIN
    SELECT * INTO x FROM finance.siwes_credit WHERE id = p_credit;
    IF x.id IS NULL OR x.state <> 'OPEN' THEN RETURN 'SIWES_CREDIT_UNKNOWN: no open SIWES credit ' || coalesce(p_credit::text, '-'); END IF;
    SELECT * INTO pr FROM finance.payment_reference WHERE id = x.reference_id;
    IF pr.confirmed_at IS NULL OR pr.archived_at IS NOT NULL OR NOT finance.is_siwes_purpose(pr.purpose)
       OR pr.student_id IS DISTINCT FROM x.student_id OR pr.session IS DISTINCT FROM x.session THEN
        RETURN format('SIWES_CREDIT_HELD: the payment of that credit (%s) is archived for review, not confirmed, or no longer stands as the SIWES payment of %s for %s; it is settled where it stands',
                      pr.reference, x.session, (SELECT s.matric_no FROM people.student s WHERE s.id = x.student_id));
    END IF;
    IF v_state = 'APPLIED' THEN
        RETURN format('SIWES_CREDIT_MOVE_IT: the whole of payment %s is credit; apply it by moving the payment on the payment correction desk, which records the credit applied', pr.reference);
    END IF;
    IF EXISTS (SELECT 1 FROM finance.refund rf WHERE rf.source_reference = pr.reference AND rf.state <> 'REJECTED') THEN
        RETURN format('SIWES_CREDIT_REFUND_DESK: refund %s on the refund desk stands against payment %s; the refund desk gives it back, and its approval settles the credit',
                      (SELECT string_agg(rf.reference, ', ' ORDER BY rf.proposed_at) FROM finance.refund rf WHERE rf.source_reference = pr.reference AND rf.state <> 'REJECTED'),
                      pr.reference);
    END IF;
    v_bank := finance.siwes_bank_check(pr.id);
    IF v_bank IS NOT NULL THEN RETURN 'SIWES_CREDIT_CHECK_BANK: ' || v_bank; END IF;
    IF EXISTS (SELECT 1 FROM finance.siwes_standing(x.student_id, x.session) s WHERE s.reference_id = x.reference_id AND s.registered)
       OR x.reference_id = (SELECT p.reference_id FROM finance.siwes_paid(x.student_id, x.session) p) THEN
        RETURN format('SIWES_CREDIT_SETTLES: payment %s is now the payment that settles the SIWES registration fee of %s (or a SIWES registration stands on it); it is not refunded as a credit',
                      pr.reference, x.session);
    END IF;
    RETURN NULL;
END $$;

/* a SIWES credit settled by the Bursar, with its note: refused for each reason finance.siwes_credit_refusal gives */
CREATE FUNCTION finance.siwes_credit_settle(p_credit uuid, p_state text, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        x finance.siwes_credit; v_state text := upper(btrim(coalesce(p_state, ''))); v_why text;
BEGIN
    IF who IS NULL OR coalesce(v_office, '-') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'SIWES_FEE_OFFICE: a SIWES credit is settled by the Bursar' USING ERRCODE = '23514';
    END IF;
    IF v_state NOT IN ('APPLIED', 'REFUNDED') OR length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'SIWES_CREDIT_SETTLE: a credit is APPLIED or REFUNDED, with a note of ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM finance.siwes_credit WHERE id = p_credit;
    IF x.id IS NULL THEN RAISE EXCEPTION 'SIWES_CREDIT_UNKNOWN: no open SIWES credit %', p_credit USING ERRCODE = '23514'; END IF;
    PERFORM finance.siwes_lock(x.student_id, x.session);
    PERFORM 1 FROM finance.siwes_credit WHERE id = p_credit FOR UPDATE;
    v_why := finance.siwes_credit_refusal(p_credit, v_state);
    IF v_why IS NOT NULL THEN
        RAISE EXCEPTION '%', v_why USING ERRCODE = '23514',
            HINT = CASE WHEN v_why LIKE 'SIWES_CREDIT_SETTLES:%' THEN 'Nothing else settles the fee now: the student would be left unpaid.'
                        WHEN v_why LIKE 'SIWES_CREDIT_REFUND_DESK:%' THEN 'Approve or reject the refund on the refund desk.'
                        WHEN v_why LIKE 'SIWES_CREDIT_CHECK_BANK:%' THEN 'Record the bank''s answer on Old Fees History (possible double charges) first.'
                        ELSE 'A credit is settled where its payment stands.' END;
    END IF;
    -- the Bursar's settlement by hand: a refund (applying one by hand is refused above, SIWES_CREDIT_MOVE_IT)
    UPDATE finance.siwes_credit SET state = v_state, settled_kind = 'HAND_REFUND', settled_at = now(), settled_by = who, settled_note = btrim(p_note)
     WHERE id = p_credit RETURNING * INTO x;
    RETURN to_jsonb(x);
END $$;

/* why a SIWES credit may not be reopened by the Bursar (NULL: it may) — the tests finance.siwes_credit_reopen applies, and that the
   credits list's can_reopen reads: only a credit the Bursar settled by hand (HAND_REFUND; one a move, the fee or the refund desk settled
   follows its payment), and only while its payment stands, confirmed and not archived, as the credit's SIWES payment */
CREATE FUNCTION finance.siwes_credit_reopen_refusal(p_credit uuid) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE x finance.siwes_credit; pr finance.payment_reference;
BEGIN
    SELECT * INTO x FROM finance.siwes_credit WHERE id = p_credit;
    IF x.id IS NULL THEN RETURN 'SIWES_CREDIT_UNKNOWN: no SIWES credit ' || coalesce(p_credit::text, '-'); END IF;
    IF x.settled_kind IS DISTINCT FROM 'HAND_REFUND' THEN
        RETURN 'SIWES_CREDIT_NOT_REOPENED: only a credit the Bursar settled by hand is reopened (one a move, the fee or the refund desk settled follows its payment)';
    END IF;
    SELECT * INTO pr FROM finance.payment_reference WHERE id = x.reference_id;
    IF pr.confirmed_at IS NULL OR pr.archived_at IS NOT NULL OR NOT finance.is_siwes_purpose(pr.purpose)
       OR pr.student_id IS DISTINCT FROM x.student_id OR pr.session IS DISTINCT FROM x.session THEN
        RETURN format('SIWES_CREDIT_NOT_REOPENED: its payment %s no longer stands as the SIWES payment of %s for the student', pr.reference, x.session);
    END IF;
    RETURN NULL;
END $$;

/* a SIWES credit the Bursar settled by hand in error reopened, with a reason on the audit trail (as the Summer's, V751), while its
   payment stands as the credit's SIWES payment: the payment may then be moved or archived again (finance.siwes_credit_reopen_refusal).
   Its payment stands again, so the one rule is applied again to the student's session (finance.siwes_stand_again): where nothing else
   settles the fee meanwhile (the payment that settled it was refunded on the desk, moved or archived while the credit was settled),
   the oldest open credit settles it (SETTLES) — never a fee paid by an open credit the Bursar is offered to refund. The credit is
   returned as it stands after that. */
CREATE FUNCTION finance.siwes_credit_reopen(p_credit uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        x finance.siwes_credit; v_why text;
BEGIN
    IF who IS NULL OR coalesce(v_office, '-') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'SIWES_FEE_OFFICE: a SIWES credit is reopened by the Bursar' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SIWES_CREDIT_REASON: say why the credit is reopened, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM finance.siwes_credit WHERE id = p_credit;
    IF x.id IS NULL THEN RAISE EXCEPTION 'SIWES_CREDIT_UNKNOWN: no SIWES credit %', p_credit USING ERRCODE = '23514'; END IF;
    PERFORM finance.siwes_lock(x.student_id, x.session);
    PERFORM 1 FROM finance.siwes_credit WHERE id = p_credit FOR UPDATE;
    v_why := finance.siwes_credit_reopen_refusal(p_credit);
    IF v_why IS NOT NULL THEN RAISE EXCEPTION '%', v_why USING ERRCODE = '23514'; END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    UPDATE finance.siwes_credit SET state = 'OPEN', settled_kind = NULL, settled_at = NULL, settled_by = NULL, settled_note = NULL WHERE id = x.id;
    PERFORM finance.siwes_stand_again(x.student_id, x.session, '{}'::text[],
        'the refund of ' || (SELECT r.reference FROM finance.payment_reference r WHERE r.id = x.reference_id) || ' recorded by hand was reopened');
    SELECT * INTO x FROM finance.siwes_credit WHERE id = p_credit;
    RETURN to_jsonb(x);
END $$;
COMMENT ON FUNCTION finance.siwes_credit_reopen(uuid, text) IS
  'V752: the Bursar (or super) reopens a SIWES credit settled by hand in error, with a reason of ten characters or more on the audit trail, while its payment stands as that credit''s SIWES payment; the one rule is then applied again to the student''s session (finance.siwes_stand_again), so where nothing else settles the fee the reopened credit settles it (SETTLES). Returns the credit as it then stands.';

-- ── 13 · the desk's lists and statistics; the Bursary's reconciliation ──────────────────────────────────────────────────────────
/* every student of a session's SIWES the desk reads: the students of the configured programmes at 300 Level in the session (in study,
   undergraduate, not CCE) and everyone who registered SIWES in it — with the unit, eligibility and why not, the payment and the
   registration. Each student's level is read once, and the SIWES courses passed are found for the whole roster at once
   (registration.siwes_passed_among): the desk's lists and statistics in under a second on the live-shaped copy */
CREATE FUNCTION registration.siwes_roster(p_session text)
RETURNS TABLE(student_id uuid, matric_no text, name text, programme_code text, programme text, dept_code text, department text,
              faculty_code text, faculty text, level integer, curriculum text, eligible boolean, reasons text[], course_code text,
              paid boolean, payment_source text, payment_reference text, receipt_no text, paid_at timestamptz, amount numeric,
              registered boolean, registered_at timestamptz, registered_course text, registration_status text)
LANGUAGE sql STABLE AS $$
    WITH cand AS MATERIALIZED (
        SELECT s.id, registration.siwes_level(s.id, p_session) AS level
          FROM registration.siwes_programme sp JOIN people.student s ON s.programme_code = sp.programme_code
         WHERE sp.session = p_session AND s.status IN ('ACTIVE', 'PROBATION') AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE')),
    pop AS MATERIALIZED (
        SELECT c.id, c.level FROM cand c WHERE c.level = 300
        UNION
        SELECT sr.student_id, registration.siwes_level(sr.student_id, p_session) FROM registration.siwes_registration sr WHERE sr.session = p_session),
    passed AS MATERIALIZED (SELECT x.student_id FROM registration.siwes_passed_among(p_session, ARRAY(SELECT pop.id FROM pop)) x)
    SELECT s.id, s.matric_no, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
           s.programme_code, pr.name, d.code, d.name, fa.code, fa.name,
           pop.level, s.curriculum_version,
           cardinality(rs.reasons) = 0, rs.reasons, registration.siwes_course_of(s.programme_code, s.curriculum_version),
           pd.reference_id IS NOT NULL, pd.source, pd.reference, pd.receipt_no, pd.confirmed_at, pd.amount,
           coalesce(sr.live, false), sr.registered_at, sr.course_code, CASE WHEN sr.id IS NULL THEN NULL WHEN sr.live THEN sr.status ELSE 'DROPPED' END
      FROM pop
      JOIN people.student s ON s.id = pop.id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ref.department d ON d.code = pr.dept_code
      LEFT JOIN ref.faculty fa ON fa.code = coalesce(d.faculty_code, pr.faculty_code)
      CROSS JOIN LATERAL (SELECT registration.siwes_reasons_of(s.id, p_session, pop.level, EXISTS (SELECT 1 FROM passed WHERE passed.student_id = s.id)) AS reasons) rs
      LEFT JOIN LATERAL (SELECT * FROM finance.siwes_paid(s.id, p_session)) pd ON true
      LEFT JOIN LATERAL (SELECT x.id, x.registered_at, x.course_code, cr.status,
                                EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = x.course_registration_id AND e.offering_id = x.offering_id
                                          AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) AS live
                           FROM registration.siwes_registration x JOIN registration.course_registration cr ON cr.id = x.course_registration_id
                          WHERE x.student_id = s.id AND x.session = p_session) sr ON true;
$$;

/* the desk's list: filtered by unit, status (ELIGIBLE, PAID, UNPAID, REGISTERED, NOT_REGISTERED) and a search, a page at a time, with
   the count of every row that matches */
CREATE FUNCTION registration.siwes_students(p_session text, p_faculty text, p_department text, p_programme text, p_status text, p_q text,
                                            p_limit integer, p_offset integer)
RETURNS TABLE(student_id uuid, matric_no text, name text, programme_code text, programme text, dept_code text, department text,
              faculty_code text, faculty text, level integer, curriculum text, eligible boolean, reasons text[], course_code text,
              paid boolean, payment_source text, payment_reference text, receipt_no text, paid_at timestamptz, amount numeric,
              registered boolean, registered_at timestamptz, registered_course text, registration_status text, total bigint)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_status text := upper(nullif(btrim(coalesce(p_status, '')), ''));
BEGIN
    IF v_status IS NOT NULL AND v_status NOT IN ('ELIGIBLE', 'PAID', 'UNPAID', 'REGISTERED', 'NOT_REGISTERED') THEN
        RAISE EXCEPTION 'SIWES_STATUS: the status is ELIGIBLE, PAID, UNPAID, REGISTERED or NOT_REGISTERED' USING ERRCODE = '23514';
    END IF;
    RETURN QUERY
    SELECT x.*, count(*) OVER ()
      FROM registration.siwes_roster(p_session) x
     WHERE (nullif(btrim(coalesce(p_faculty, '')), '') IS NULL OR x.faculty_code = btrim(p_faculty))
       AND (nullif(btrim(coalesce(p_department, '')), '') IS NULL OR x.dept_code = btrim(p_department))
       AND (nullif(btrim(coalesce(p_programme, '')), '') IS NULL OR x.programme_code = upper(btrim(p_programme)))
       AND (v_status IS NULL
            OR (v_status = 'ELIGIBLE' AND x.eligible)
            OR (v_status = 'PAID' AND x.paid)
            OR (v_status = 'UNPAID' AND x.eligible AND NOT x.paid)
            OR (v_status = 'REGISTERED' AND x.registered)
            OR (v_status = 'NOT_REGISTERED' AND x.eligible AND NOT x.registered))
       AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL OR x.name ILIKE '%' || btrim(p_q) || '%' OR coalesce(x.matric_no, '') ILIKE '%' || btrim(p_q) || '%')
     ORDER BY x.faculty, x.department, x.programme, x.name, x.student_id
     LIMIT greatest(coalesce(p_limit, 50), 1) OFFSET greatest(coalesce(p_offset, 0), 0);
END $$;

/* the desk's statistics: eligible, paid, registered, yet to pay, yet to register, the money paid and outstanding (at the published fee),
   by faculty, department and programme */
CREATE FUNCTION registration.siwes_stats(p_session text, p_faculty text, p_department text, p_programme text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH x AS MATERIALIZED (
        SELECT r.* FROM registration.siwes_roster(p_session) r
         WHERE (nullif(btrim(coalesce(p_faculty, '')), '') IS NULL OR r.faculty_code = btrim(p_faculty))
           AND (nullif(btrim(coalesce(p_department, '')), '') IS NULL OR r.dept_code = btrim(p_department))
           AND (nullif(btrim(coalesce(p_programme, '')), '') IS NULL OR r.programme_code = upper(btrim(p_programme)))),
    fee AS (SELECT coalesce(finance.siwes_fee_for(p_session), 0) AS amount)
    SELECT jsonb_build_object(
        'session', p_session,
        'fee', (SELECT nullif(fee.amount, 0) FROM fee),
        'eligible', (SELECT count(*) FILTER (WHERE x.eligible) FROM x),
        'paid', (SELECT count(*) FILTER (WHERE x.paid) FROM x),
        'registered', (SELECT count(*) FILTER (WHERE x.registered) FROM x),
        'unpaid', (SELECT count(*) FILTER (WHERE x.eligible AND NOT x.paid) FROM x),
        'notRegistered', (SELECT count(*) FILTER (WHERE x.eligible AND NOT x.registered) FROM x),
        'amountPaid', (SELECT coalesce(sum(x.amount) FILTER (WHERE x.paid), 0) FROM x),
        'amountOutstanding', (SELECT count(*) FILTER (WHERE x.eligible AND NOT x.paid) FROM x) * (SELECT fee.amount FROM fee),
        'byFaculty', coalesce((SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'eligible', g.eligible, 'paid', g.paid, 'registered', g.registered,
                                                                  'unpaid', g.unpaid, 'notRegistered', g.not_registered) ORDER BY g.name)
                                 FROM (SELECT x.faculty_code AS code, x.faculty AS name, count(*) FILTER (WHERE x.eligible) AS eligible, count(*) FILTER (WHERE x.paid) AS paid,
                                              count(*) FILTER (WHERE x.registered) AS registered, count(*) FILTER (WHERE x.eligible AND NOT x.paid) AS unpaid,
                                              count(*) FILTER (WHERE x.eligible AND NOT x.registered) AS not_registered
                                         FROM x GROUP BY x.faculty_code, x.faculty) g), '[]'::jsonb),
        'byDepartment', coalesce((SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'facultyCode', g.faculty_code, 'eligible', g.eligible, 'paid', g.paid,
                                                                     'registered', g.registered, 'unpaid', g.unpaid, 'notRegistered', g.not_registered) ORDER BY g.name)
                                    FROM (SELECT x.dept_code AS code, x.department AS name, x.faculty_code, count(*) FILTER (WHERE x.eligible) AS eligible,
                                                 count(*) FILTER (WHERE x.paid) AS paid, count(*) FILTER (WHERE x.registered) AS registered,
                                                 count(*) FILTER (WHERE x.eligible AND NOT x.paid) AS unpaid, count(*) FILTER (WHERE x.eligible AND NOT x.registered) AS not_registered
                                            FROM x GROUP BY x.dept_code, x.department, x.faculty_code) g), '[]'::jsonb),
        'byProgramme', coalesce((SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'departmentCode', g.dept_code, 'facultyCode', g.faculty_code,
                                                                    'eligible', g.eligible, 'paid', g.paid, 'registered', g.registered, 'unpaid', g.unpaid,
                                                                    'notRegistered', g.not_registered) ORDER BY g.name)
                                   FROM (SELECT x.programme_code AS code, x.programme AS name, x.dept_code, x.faculty_code, count(*) FILTER (WHERE x.eligible) AS eligible,
                                                count(*) FILTER (WHERE x.paid) AS paid, count(*) FILTER (WHERE x.registered) AS registered,
                                                count(*) FILTER (WHERE x.eligible AND NOT x.paid) AS unpaid, count(*) FILTER (WHERE x.eligible AND NOT x.registered) AS not_registered
                                           FROM x GROUP BY x.programme_code, x.programme, x.dept_code, x.faculty_code) g), '[]'::jsonb));
$$;

/* one student on the desk: their SIWES of the session, and every session's SIWES payment and registration */
CREATE FUNCTION registration.siwes_student_detail(p_student uuid, p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT registration.siwes_eligibility(p_student, p_session)
           || jsonb_build_object(
                'matricNo', s.matric_no,
                'name', upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''),
                'history', coalesce((
                    SELECT jsonb_agg(jsonb_build_object(
                               'session', h.session,
                               'paid', (SELECT jsonb_build_object('reference', p.reference, 'amount', p.amount, 'receiptNo', p.receipt_no, 'at', p.confirmed_at, 'source', p.source)
                                          FROM finance.siwes_paid(p_student, h.session) p),
                               'registration', (SELECT registration.siwes_registration_json(x.id) FROM registration.siwes_registration x
                                                 WHERE x.student_id = p_student AND x.session = h.session)) ORDER BY h.session DESC)
                      FROM (SELECT x.session FROM registration.siwes_registration x WHERE x.student_id = p_student
                            UNION SELECT r.session FROM finance.payment_reference r
                             WHERE r.student_id = p_student AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                               AND finance.is_siwes_purpose(r.purpose)) h), '[]'::jsonb))
      FROM people.student s WHERE s.id = p_student;
$$;

/* the Academic Office's configuration of a session: the period, the programmes with their SIWES course (for each curriculum the
   programme's 300 Level students hold, and each mapped), the programmes not yet configured, the fee, the sessions */
CREATE FUNCTION registration.siwes_config(p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH v AS (SELECT coalesce(nullif(btrim(coalesce(p_session, '')), ''), policy.university_current_session()) AS session),
    ros AS MATERIALIZED (SELECT x.programme_code, count(*) FILTER (WHERE x.eligible) AS eligible
                           FROM v CROSS JOIN LATERAL registration.siwes_roster(v.session) x GROUP BY x.programme_code),
    keys AS (SELECT sc.programme_code, sc.curriculum FROM registration.siwes_course sc
             UNION
             SELECT s.programme_code, s.curriculum_version FROM v
               JOIN registration.siwes_programme sp ON sp.session = v.session
               JOIN people.student s ON s.programme_code = sp.programme_code AND s.status IN ('ACTIVE', 'PROBATION') AND s.current_level = 300
                                    AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE'))
    SELECT jsonb_build_object(
        'session', v.session,
        'period', registration.siwes_period_json(v.session),
        'programmes', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'code', p.code, 'name', p.name, 'departmentCode', d.code, 'department', d.name, 'facultyCode', fa.code, 'faculty', fa.name,
                       'eligible', coalesce(ros.eligible, 0),
                       'course', registration.siwes_course_json(registration.siwes_course_of(p.code, NULL), p.code),
                       'curricula', coalesce((SELECT jsonb_agg(jsonb_build_object('curriculum', k.curriculum,
                                                                                  'mapped', EXISTS (SELECT 1 FROM registration.siwes_course sc WHERE sc.programme_code = p.code
                                                                                                       AND sc.curriculum IS NOT DISTINCT FROM k.curriculum),
                                                                                  'course', registration.siwes_course_json(registration.siwes_course_of(p.code, k.curriculum), p.code))
                                                         ORDER BY k.curriculum NULLS FIRST)
                                                FROM keys k WHERE k.programme_code = p.code), '[]'::jsonb)) ORDER BY p.name)
              FROM registration.siwes_programme sp
              JOIN ref.programme p ON p.code = sp.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty fa ON fa.code = coalesce(d.faculty_code, p.faculty_code)
              LEFT JOIN ros ON ros.programme_code = p.code
             WHERE sp.session = v.session), '[]'::jsonb),
        'candidates', coalesce((
            SELECT jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name,
                                                'attachment', registration.siwes_units(p.code, 300, 2) IS NOT NULL) ORDER BY p.name)
              FROM ref.programme p
             WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived
               AND NOT EXISTS (SELECT 1 FROM registration.siwes_programme sp WHERE sp.session = v.session AND sp.programme_code = p.code)), '[]'::jsonb),
        'fee', (SELECT jsonb_build_object('amount', f.amount, 'state', f.state) FROM finance.siwes_fee f WHERE f.session = v.session),
        'sessions', coalesce((SELECT jsonb_agg(a.name ORDER BY a.name DESC) FROM policy.academic_session a
                               WHERE a.state <> 'CANCELLED' AND a.merged_into IS NULL), '[]'::jsonb))
      FROM v;
$$;

/* the Bursary's reconciliation: the confirmed SIWES payments (the portal's and the old portal's), with the gateway's own reference, the
   receipt, the source, whether it settles the student's fee (finance.siwes_paid), its credit's state when it has one and what was given
   back on it (refunded: the refund desk's refunds approved or paid, or the whole payment when the Bursar recorded its credit refunded) —
   never a school-fee or GST payment. The totals, each row counted once: every payment listed (total_amount), the ones that settle a fee
   (total_settling), what was given back (total_refunded), and the money held that settles nothing (total_credits = total_amount -
   total_settling - total_refunded: open or applied credits, old-portal payments made twice). Each row of the page says whether the
   payment waits on the Bursary's bank check (V561), as the credits list says it: bank_check (the words) and bank_check_state (the code:
   PROPOSED, NOT_RECEIVED — this record found never received, NOT_RECEIVED_WAITING — another record of its day found never received,
   UNCHECKED), read for the page's rows alone. A payment given back waits on nothing, by the credits list's rule (a refunded credit
   carries no hold): its credit REFUNDED, or, with no credit, refunded on the refund desk — the hold's words ("not refunded or moved")
   would contradict the money already given back on the same row */
CREATE FUNCTION finance.siwes_payments(p_session text, p_faculty text, p_department text, p_programme text, p_source text, p_limit integer, p_offset integer)
RETURNS TABLE(reference text, student_id uuid, matric_no text, name text, programme_code text, programme text, dept_code text, department text,
              faculty_code text, faculty text, session text, amount numeric, gateway text, gateway_reference text, receipt_no text,
              confirmed_at timestamptz, source text, settles boolean, credit_state text, refunded numeric, total bigint, total_amount numeric,
              total_settling numeric, total_refunded numeric, total_credits numeric, bank_check text, bank_check_state text)
LANGUAGE sql STABLE AS $$
    WITH x0 AS (
        SELECT r.reference, r.student_id, s.matric_no, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS name,
               s.programme_code, pr.name AS programme, d.code AS dept_code, d.name AS department, fa.code AS faculty_code, fa.name AS faculty,
               r.session, r.amount, r.channel AS gateway,
               (SELECT e.gateway_ref FROM finance.gateway_event e WHERE e.reference = r.reference AND e.outcome IN ('SETTLED', 'ALREADY_SETTLED')
                   AND e.gateway_ref IS NOT NULL ORDER BY e.received_at DESC LIMIT 1) AS gateway_reference,
               r.receipt_no, r.confirmed_at,
               CASE WHEN r.purpose LIKE 'SIWES registration fee%' THEN 'PORTAL' ELSE 'OLD_PORTAL' END AS source,
               coalesce(r.id = (SELECT p.reference_id FROM finance.siwes_paid(r.student_id, r.session) p), false) AS settles,
               (SELECT c.state FROM finance.siwes_credit c WHERE c.reference_id = r.id) AS credit_state,
               -- given back: the refund desk's refunds, or the whole credit the Bursar recorded refunded (never both: each refuses the other)
               least(r.amount, finance.gst_refunded(r.reference)
                               + coalesce((SELECT c.amount FROM finance.siwes_credit c WHERE c.reference_id = r.id AND c.settled_kind = 'HAND_REFUND'), 0)) AS refunded,
               r.id AS payment_id
          FROM finance.payment_reference r
          JOIN people.student s ON s.id = r.student_id
          LEFT JOIN ref.programme pr ON pr.code = s.programme_code
          LEFT JOIN ref.department d ON d.code = pr.dept_code
          LEFT JOIN ref.faculty fa ON fa.code = coalesce(d.faculty_code, pr.faculty_code)
         WHERE r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
           AND finance.is_siwes_purpose(r.purpose)
           AND (nullif(btrim(coalesce(p_session, '')), '') IS NULL OR r.session = btrim(p_session))
           AND (nullif(btrim(coalesce(p_faculty, '')), '') IS NULL OR fa.code = btrim(p_faculty))
           AND (nullif(btrim(coalesce(p_department, '')), '') IS NULL OR d.code = btrim(p_department))
           AND (nullif(btrim(coalesce(p_programme, '')), '') IS NULL OR s.programme_code = upper(btrim(p_programme)))),
    x AS (SELECT * FROM x0 WHERE nullif(upper(btrim(coalesce(p_source, ''))), '') IS NULL OR x0.source = upper(btrim(p_source))),
    -- a settling payment has nothing given back (finance.siwes_standing), so the three parts never overlap
    t AS (SELECT count(*) AS n, coalesce(sum(x.amount), 0) AS amount, coalesce(sum(x.amount) FILTER (WHERE x.settles), 0) AS settling,
                 coalesce(sum(x.refunded), 0) AS refunded FROM x),
    pg AS (SELECT x.* FROM x ORDER BY x.confirmed_at DESC, x.reference
            LIMIT greatest(coalesce(p_limit, 50), 1) OFFSET greatest(coalesce(p_offset, 0), 0))
    SELECT pg.reference, pg.student_id, pg.matric_no, pg.name, pg.programme_code, pg.programme, pg.dept_code, pg.department, pg.faculty_code,
           pg.faculty, pg.session, pg.amount, pg.gateway, pg.gateway_reference, pg.receipt_no, pg.confirmed_at, pg.source, pg.settles,
           pg.credit_state, pg.refunded, t.n, t.amount, t.settling, t.refunded, t.amount - t.settling - t.refunded, h.words, h.state
      FROM pg CROSS JOIN t
      LEFT JOIN LATERAL (SELECT b.state, b.words FROM finance.siwes_bank_hold(pg.payment_id) b   -- the page's rows alone; none given back
                          WHERE pg.credit_state IS DISTINCT FROM 'REFUNDED' AND (pg.credit_state IS NOT NULL OR pg.refunded = 0)) h ON true
     ORDER BY pg.confirmed_at DESC, pg.reference;
$$;

/* the Bursary's open and settled SIWES credits of a session, with when the payment was confirmed and who settled the credit; how it was
   settled (settled_kind) and whether the database settled it itself (automatic: SETTLES, MOVED, DESK_REFUND), whether its payment now
   settles the fee, and what the Bursar can do — can_refund and can_reopen are the very tests finance.siwes_credit_settle (REFUNDED) and
   finance.siwes_credit_reopen apply; bank_check, the words, and bank_check_state, the code (finance.siwes_bank_hold: PROPOSED,
   NOT_RECEIVED, NOT_RECEIVED_WAITING, UNCHECKED), when the credit's payment waits on the Bursary's bank check — an open credit, or one
   that settles the fee meanwhile (a refunded one waits on nothing). A credit whose payment is archived for review (or withdrawn as never
   received), found never received by the bank check and not yet withdrawn (it does not stand: no credit is listed on a payment that does
   not stand), or no longer confirmed, waits off the list. */
CREATE FUNCTION finance.siwes_credits(p_session text)
RETURNS TABLE(id uuid, student_id uuid, matric_no text, name text, session text, reference text, amount numeric, reason text, state text,
              created_at timestamptz, settled_at timestamptz, settled_note text, paid_at timestamptz, settled_by_name text,
              automatic boolean, settles boolean, can_refund boolean, can_reopen boolean, bank_check text, settled_kind text,
              bank_check_state text)
LANGUAGE sql STABLE AS $$
    SELECT c.id, c.student_id, s.matric_no, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), ''), c.session, r.reference,
           c.amount, c.reason, c.state, c.created_at, c.settled_at, c.settled_note, r.confirmed_at, finance.siwes_person_name(c.settled_by),
           c.state <> 'OPEN' AND c.settled_kind <> 'HAND_REFUND',
           coalesce(c.reference_id = (SELECT p.reference_id FROM finance.siwes_paid(c.student_id, c.session) p), false),
           f.why IS NULL,
           finance.siwes_credit_reopen_refusal(c.id) IS NULL,
           h.words,
           c.settled_kind,
           h.state
      FROM finance.siwes_credit c JOIN people.student s ON s.id = c.student_id JOIN finance.payment_reference r ON r.id = c.reference_id
      CROSS JOIN LATERAL (SELECT finance.siwes_credit_refusal(c.id, 'REFUNDED') AS why OFFSET 0) f   -- once a credit (OFFSET 0: not inlined)
      LEFT JOIN LATERAL (SELECT b.state, b.words FROM finance.siwes_bank_hold(c.reference_id) b WHERE c.state <> 'REFUNDED') h ON true
     WHERE (nullif(btrim(coalesce(p_session, '')), '') IS NULL OR c.session = btrim(p_session)) AND r.archived_at IS NULL AND r.confirmed_at IS NOT NULL
       AND NOT finance.siwes_found_not_received(r.id)
     ORDER BY c.created_at DESC;
$$;

-- ── 14 · the payments' purpose and category: SIWES, not Other (the old portal's SIWES payments read under it too) ───────────────
-- Written in the short stretch (section 18), once its locks are held: each insert's V427 statement trigger rebuilds the category and
-- owner memos (finance.category_memo, finance.owner_memo) by DELETE and INSERT, a row lock on every memo row until the commit, and
-- written here they held every Bursary change to a payment category, purpose or classification for as long as section 18 waits for its
-- locks (up to the deploy's lock_timeout). Rebuilt there, the memo also reads every payment committed before the locks: an old-portal
-- SIWES payment with an item text new to the memo, written while V752 lands, is memoised SIWES.

-- ── 15 · the notices ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority)
VALUES
 ('SIWES_FEE_PAID', 'SIWES fee paid', 'To the student when the SIWES registration fee is confirmed: register the SIWES course (V752)',
  'Your SIWES registration fee for [SESSION] is paid',
  E'Dear [FIRST_NAME],\n\nYour SIWES registration fee of [AMOUNT] for [SESSION] is confirmed (receipt [RECEIPT]).\n\nSign in, open SIWES and register your SIWES course: paying does not register it.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
  'MOAUM: your SIWES fee for [SESSION] is paid. Register your SIWES course on the portal.',
  'SIWES fee paid', 'Your SIWES registration fee for [SESSION] is paid. Register your SIWES course on the SIWES page.',
  ARRAY['FIRST_NAME', 'SESSION', 'AMOUNT', 'RECEIPT', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL'),
 ('SIWES_REGISTERED', 'SIWES course registered', 'To the student when the SIWES course is registered (V752)',
  'Your SIWES registration for [SESSION]',
  E'Dear [FIRST_NAME],\n\nYour SIWES course [COURSE] ([UNITS] credit units) is registered for the Second Semester of [SESSION]. Print your SIWES course registration from the SIWES page.\n\n[PORTAL_URL]\n\n[UNIVERSITY_NAME]',
  'MOAUM: your SIWES course [COURSE] is registered for [SESSION]. Print it on the portal.',
  'SIWES registered', 'Your SIWES course [COURSE] is registered for the Second Semester of [SESSION].',
  ARRAY['FIRST_NAME', 'SESSION', 'COURSE', 'UNITS', 'PORTAL_URL', 'UNIVERSITY_NAME'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 16 · the seed: the current session's SIWES, as the students register it today ───────────────────────────────────────────────
/* the SIWES course of each programme taking part in a session, for each curriculum, as V503's attachment semester has its 300 Level
   students register it today: the industrial-training course on their Second Semester registrations at 300 Level (submitted, approved
   or locked; the course not dropped; a course not ended, taught in the Second Semester), by the student's curriculum — a LIVE course
   before any other, then the most recent session, then the most students. A curriculum no registration speaks for takes the structure's
   industrial-training course bound at 300 Level and taught in the Second Semester, for the curriculum the course names (none: every
   curriculum): a LIVE one, or one in another state only where the programme has no LIVE SIWES course at all. Never over a mapping the
   Academic Office has set (ON CONFLICT DO NOTHING). Returns what it mapped and why. V752 runs it for the current session; the
   Academic Office changes any of it on the SIWES desk. */
CREATE FUNCTION registration.siwes_seed_courses(p_session text)
RETURNS TABLE(programme_code text, curriculum text, course_code text, course_state text, chosen_by text, students bigint)
LANGUAGE plpgsql AS $$
DECLARE v_who uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
    RETURN QUERY
    WITH reg AS (
        SELECT s.programme_code AS prog, s.curriculum_version AS cur, r.session, c.code, c.state, count(DISTINCT r.student_id) AS n
          FROM registration.siwes_programme sp
          JOIN people.student s ON s.programme_code = sp.programme_code AND (s.curriculum_version IS NULL OR s.curriculum_version IN ('CCMAS', 'BMAS'))
          JOIN registration.course_registration r ON r.student_id = s.id AND r.semester = 2 AND r.level = 300
                                                 AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED') AND r.session <= p_session
          JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
          JOIN catalogue.offering o ON o.id = e.offering_id
          JOIN catalogue.course c ON c.code = o.course_code AND c.industrial_training AND c.state <> 'ENDED'
                                 AND catalogue.runs_in(c.semester, c.both_semesters, 2)
         WHERE sp.session = p_session
         GROUP BY 1, 2, 3, 4, 5),
    pick AS (
        SELECT DISTINCT ON (reg.prog, coalesce(reg.cur, '')) reg.prog, reg.cur, reg.code, reg.n
          FROM reg
         ORDER BY reg.prog, coalesce(reg.cur, ''), (reg.state = 'LIVE') DESC, reg.session DESC, reg.n DESC, reg.code),
    ins AS (
        INSERT INTO registration.siwes_course (programme_code, curriculum, course_code, set_by, set_office)
        SELECT pick.prog, pick.cur, pick.code, v_who, 'academic' FROM pick
        ON CONFLICT DO NOTHING
        RETURNING siwes_course.programme_code, siwes_course.curriculum, siwes_course.course_code)
    SELECT ins.programme_code, ins.curriculum, ins.course_code, c.state, 'REGISTRATIONS'::text, pick.n
      FROM ins JOIN pick ON pick.prog = ins.programme_code AND pick.cur IS NOT DISTINCT FROM ins.curriculum
      JOIN catalogue.course c ON c.code = ins.course_code;
    -- the structure's, where no registration spoke (it sees the mappings just made)
    RETURN QUERY
    WITH st AS (
        SELECT DISTINCT ON (co.programme_code, coalesce(c.curriculum, '')) co.programme_code AS prog, c.curriculum AS cur, c.code, c.state
          FROM registration.siwes_programme sp
          JOIN catalogue.course_offer co ON co.programme_code = sp.programme_code AND co.level = 300
          JOIN catalogue.course c ON c.code = co.course_code AND c.industrial_training AND c.state <> 'ENDED' AND catalogue.runs_in(c.semester, c.both_semesters, 2)
         WHERE sp.session = p_session
         ORDER BY co.programme_code, coalesce(c.curriculum, ''), (c.state = 'LIVE') DESC, c.code),
    ins AS (
        INSERT INTO registration.siwes_course (programme_code, curriculum, course_code, set_by, set_office)
        SELECT st.prog, st.cur, st.code, v_who, 'academic' FROM st
         WHERE st.state = 'LIVE'
            OR (NOT EXISTS (SELECT 1 FROM registration.siwes_course x JOIN catalogue.course k ON k.code = x.course_code AND k.state = 'LIVE'
                             WHERE x.programme_code = st.prog)
                AND NOT EXISTS (SELECT 1 FROM st s2 WHERE s2.prog = st.prog AND s2.state = 'LIVE'))
        ON CONFLICT DO NOTHING
        RETURNING siwes_course.programme_code, siwes_course.curriculum, siwes_course.course_code)
    SELECT ins.programme_code, ins.curriculum, ins.course_code, c.state, 'STRUCTURE'::text, NULL::bigint
      FROM ins JOIN catalogue.course c ON c.code = ins.course_code;
END $$;
COMMENT ON FUNCTION registration.siwes_seed_courses(text) IS
  'V752: maps the SIWES course of each programme taking part in the session, for each curriculum, as its 300 Level students register it under V503 today (their Second Semester registrations: a LIVE course first, then the most recent session, then the most students), else the structure''s (a course not LIVE only where the programme has no LIVE one); never over a mapping set. Returns what it mapped and why.';

DO $$
DECLARE v_session text := policy.university_current_session(); v_who uuid := '00000000-0000-0000-0000-000000000000';
        n_prog int := 0; n_course int := 0; v_progs text; v_unmapped text; n_students int := 0; n_legacy int; v_left text; v_map text;
BEGIN
    IF v_session IS NOT NULL THEN
        -- a draft: it binds nobody until the Academic Office dates it and opens it
        INSERT INTO registration.siwes_period (session, state, set_by, set_office, note)
        VALUES (v_session, 'DRAFT', v_who, 'academic', 'Seeded by V752 from the programmes whose 300 Level Second Semester is an attachment semester')
        ON CONFLICT (session) DO NOTHING;
        -- the programmes whose 300 Level Second Semester is the attachment semester today (V503), undergraduate
        INSERT INTO registration.siwes_programme (session, programme_code, added_by, added_office)
        SELECT v_session, p.code, v_who, 'academic' FROM ref.programme p
         WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND registration.siwes_units(p.code, 300, 2) > 0
        ON CONFLICT DO NOTHING;
        GET DIAGNOSTICS n_prog = ROW_COUNT;
        -- each one's SIWES course for each curriculum, as its 300 Level students register it today (registration.siwes_seed_courses)
        SELECT count(*), string_agg(m.programme_code || ' ' || coalesce(m.curriculum, 'every curriculum') || ' ' || m.course_code || ' (' || m.course_state
                                    || ', ' || CASE WHEN m.chosen_by = 'REGISTRATIONS' THEN m.students || ' registered' ELSE 'the structure' END || ')',
                                    ', ' ORDER BY m.programme_code, m.curriculum NULLS FIRST)
          INTO n_course, v_map
          FROM registration.siwes_seed_courses(v_session) m;
        SELECT string_agg(p.name || ' (' || sp.programme_code || ')', ', ' ORDER BY p.name) INTO v_progs
          FROM registration.siwes_programme sp JOIN ref.programme p ON p.code = sp.programme_code WHERE sp.session = v_session;
        -- the configured programmes whose 300 Level students no SIWES course reaches (each curriculum, with its count): SIWES binds them
        -- not (V503 stands for them) and the period is not opened until the Academic Office maps their course
        SELECT string_agg(u.programme || ' (' || u.programme_code || ', ' || coalesce(u.curriculum, 'no curriculum') || ': ' || u.students || ')', '; '
                          ORDER BY u.programme, u.curriculum) INTO v_unmapped
          FROM registration.siwes_unmapped(v_session) u;
        SELECT count(*) INTO n_students
          FROM registration.siwes_programme sp JOIN people.student s ON s.programme_code = sp.programme_code
         WHERE sp.session = v_session AND s.status IN ('ACTIVE', 'PROBATION') AND s.current_level = 300 AND s.entry_mode NOT IN ('CCE', 'POSTGRADUATE');
        -- the fee: ₦4,000, published
        INSERT INTO finance.siwes_fee (session, amount, state, note, stated_by, stated_office, published_by, published_office, published_at)
        VALUES (v_session, 4000, 'PUBLISHED', 'the University''s master prompt of 12 November 2026', v_who, 'bursar', v_who, 'bursar', now())
        ON CONFLICT (session) DO NOTHING;
    END IF;
    -- the old portal's SIWES payments, read under the SIWES category once section 18 adds it (counted here, outside the locks; section 18
    -- says if any SIWES item text reads under another category then)
    SELECT count(*) INTO n_legacy FROM finance.payment_reference r
     WHERE r.confirmed_at IS NOT NULL AND r.purpose ~* '^siwes' AND r.purpose LIKE '%(legacy)%';
    -- V503's attachment semesters no configuration reaches: kept exactly as they are
    SELECT string_agg(p.code || ' ' || l || '/' || m, ', ' ORDER BY p.code, l, m) INTO v_left
      FROM ref.programme p CROSS JOIN unnest(ARRAY[100, 200, 300, 400, 500, 600]) l CROSS JOIN unnest(ARRAY[1, 2]) m
     WHERE p.category = 'UNDER GRADUATE' AND NOT p.archived AND registration.siwes_units(p.code, l, m) IS NOT NULL
       AND NOT (l = 300 AND m = 2 AND EXISTS (SELECT 1 FROM registration.siwes_programme sp WHERE sp.session = v_session AND sp.programme_code = p.code));
    RAISE NOTICE 'V752: SIWES of % seeded as a DRAFT (binds nobody until the Academic Office opens it): % programme(s) configured (%), % SIWES course mapping(s) (%), % active student(s) at 300 Level in them; configured programmes whose 300 Level students no SIWES course reaches (the period opens only once mapped): %; the fee ₦4,000 published; % old-portal SIWES payment(s) now under the SIWES category; V503 attachment semesters left as they are: %',
        coalesce(v_session, '(no session on the calendar: nothing seeded)'), n_prog, coalesce(v_progs, 'none'), n_course, coalesce(v_map, 'none'), n_students,
        coalesce(v_unmapped, 'none'), n_legacy, coalesce(v_left, 'none');
END $$;

-- ── 17 · the second SIWES payments already on record: credits, as the triggers make one that comes later ───────────────────────
/* one rule for a student's second SIWES payment of a session, whenever it came: a SIWES credit. One that comes after V752 is credited as
   it comes (finance.siwes_comes_to_stand, from trg_siwes_settling_follows_insert and _payment; the portal's reference through
   trg_siwes_reference_confirmed); the old portal's already on record when V752 lands are credited here by the same function: every
   student's session holding more than one standing SIWES payment, the newest first, so each finds those confirmed before it there — the
   first confirmed settles, every later one is a credit naming it, as the old fees history started over and loaded again in date order
   makes them. Run again, it makes nothing more. Returns what it made: the student-sessions, the credits, their amount and how many wait
   on the Bursary's bank check of a possible bank double charge (finance.siwes_bank_check). */
CREATE FUNCTION finance.siwes_credit_second_payments()
RETURNS TABLE(students bigint, credits bigint, amount numeric, held bigint) LANGUAGE plpgsql AS $$
DECLARE k record; p record; v_before uuid[] := ARRAY(SELECT c.id FROM finance.siwes_credit c);
BEGIN
    FOR k IN SELECT r.student_id, r.session FROM finance.payment_reference r
              WHERE r.student_id IS NOT NULL AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND finance.is_siwes_purpose(r.purpose)
              GROUP BY r.student_id, r.session HAVING count(*) > 1
              ORDER BY r.session, r.student_id LOOP
        FOR p IN SELECT x.reference_id FROM finance.siwes_standing(k.student_id, k.session) x ORDER BY x.confirmed_at DESC, x.reference DESC LOOP
            PERFORM finance.siwes_comes_to_stand(p.reference_id);
        END LOOP;
    END LOOP;
    RETURN QUERY
        SELECT count(DISTINCT (c.student_id, c.session)), count(*), coalesce(sum(c.amount), 0),
               count(*) FILTER (WHERE finance.siwes_bank_check(c.reference_id) IS NOT NULL)
          FROM finance.siwes_credit c WHERE NOT (c.id = ANY (v_before));
END $$;
COMMENT ON FUNCTION finance.siwes_credit_second_payments() IS
  'V752: the second (and later) SIWES payments of a student''s session already on record credited by finance.siwes_comes_to_stand, the one rule the payment triggers apply — the first confirmed settles, every later one is a credit; run by V752 as it lands; idempotent.';

-- ── 18 · the short stretch: the locks that hold the portal's writers, taken last ────────────────────────────────────────────────
/* Everything above reads the portal or writes V752's own tables, and no writer of the portal waits on it. A foreign key, and a trigger,
   take a lock on their table that every writer of it waits on until the commit; the payment purpose, category and classification
   (section 14) rebuild the category and owner memos, a lock on every memo row until the commit: they come here, at the end, once those
   locks are all held. Then the SIWES purpose, category and classification (the memos rebuilt), the credit of the second SIWES payments
   on record, the keys onto the portal's tables and the triggers on the payments, refunds, entries, registrations, bank checks and
   withdrawals, each quick, and the commit. On a copy of the live data (db-test r5, r6, r7) the writers waited under a second, where
   round 4's order held them for 13 to 20 s. The memos and the credit of the second payments are made once the payments are locked, so
   they see every payment committed before, and none can change under them; a payment written after waits for the commit and then meets
   the triggers (trg_siwes_settling_follows_insert and _payment) and the SIWES category. None is missed and none is counted twice. The
   credit is run once before the locks too, and undone at once: what it reads and the plans it makes are then at hand, and the stretch
   is shorter (on the live-shaped copy it took 0.66 s cold, inside a lock every writer waits on).
   The locks are taken without waiting (NOWAIT), all thirteen in one attempt, each attempt in a subtransaction: a write still open on any
   of them fails the attempt at once and gives back the locks it took, so no writer ever queues behind V752 while it waits for another
   writer to finish (a waiting LOCK TABLE keeps the locks it has while it waits for the next, and every writer of those tables waits with
   it), and V752 holds nothing a writer needs while it tries again (no memo row: a Bursary change to a payment category, purpose or
   classification goes through meanwhile). The two memos are among the thirteen, so a Bursary change still open on them fails the
   attempt rather than holding the stretch. The attempts are a tenth to a fifth of a second apart, for as long as the deploy's
   lock_timeout (migrate.sh: 90 s, or MIGRATE_LOCK_TIMEOUT; 90 s when none is set); then V752 stops with V752_LOCKS_BUSY, naming what
   held the tables, its transaction undone and the deploy failed, and the next deploy runs it again. */
DO $$
DECLARE v_err text;
BEGIN
    BEGIN
        PERFORM finance.siwes_credit_second_payments();
        RAISE EXCEPTION 'V752: the credit of the second payments, rehearsed and undone';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
        IF v_err <> 'V752: the credit of the second payments, rehearsed and undone' THEN RAISE; END IF;
    END;
END $$;

DO $$
DECLARE v_budget interval; v_until timestamptz; n int := 0; v_held text;
BEGIN
    v_budget := CASE WHEN current_setting('lock_timeout') IN ('0', '') THEN interval '90 seconds' ELSE current_setting('lock_timeout')::interval END;
    v_until := clock_timestamp() + v_budget;
    LOOP
        n := n + 1;
        BEGIN
            LOCK TABLE policy.academic_session, ref.programme, catalogue.course, catalogue.offering, people.student, finance.payment_reference,
                       finance.refund, registration.course_registration, registration.entry, finance.double_charge_check,
                       finance.payment_not_received, finance.category_memo, finance.owner_memo IN SHARE ROW EXCLUSIVE MODE NOWAIT;
            EXIT;
        EXCEPTION WHEN lock_not_available THEN
            IF clock_timestamp() >= v_until THEN
                -- what held them: the other sessions holding a lock that bars V752's on any of the thirteen (never their statements)
                SELECT string_agg(DISTINCT format('pid %s (%s%s, %s, transaction open %s s) on %s', l.pid, coalesce(nullif(a.backend_type, 'client backend'), 'client'),
                                                  coalesce(', ' || nullif(a.application_name, ''), ''), coalesce(a.state, '-'),
                                                  coalesce(round(extract(epoch FROM clock_timestamp() - a.xact_start))::text, '-'), l.relation::regclass), '; ')
                  INTO v_held
                  FROM pg_locks l LEFT JOIN pg_stat_activity a ON a.pid = l.pid
                 WHERE l.locktype = 'relation' AND l.granted AND l.pid <> pg_backend_pid() AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
                   AND l.mode NOT IN ('AccessShareLock', 'RowShareLock')
                   AND l.relation IN ('policy.academic_session'::regclass, 'ref.programme'::regclass, 'catalogue.course'::regclass, 'catalogue.offering'::regclass,
                                      'people.student'::regclass, 'finance.payment_reference'::regclass, 'finance.refund'::regclass,
                                      'registration.course_registration'::regclass, 'registration.entry'::regclass, 'finance.double_charge_check'::regclass,
                                      'finance.payment_not_received'::regclass, 'finance.category_memo'::regclass, 'finance.owner_memo'::regclass);
                RAISE EXCEPTION 'V752_LOCKS_BUSY: the portal''s tables V752 adds its keys and triggers to (and the payment memos it rebuilds) were never free of writes all at once in % s (% attempts, none waited on); V752 is not applied and runs again on the next deploy. Held by: %',
                    round(extract(epoch FROM v_budget)), n, coalesce(v_held, 'short writes, one after another')
                    USING HINT = 'Deploy again when no long write (an old fees upload, a bulk job) is running; MIGRATE_LOCK_TIMEOUT sets how long V752 keeps trying.';
            END IF;
            PERFORM pg_sleep(0.1 + random() * 0.1);
        END;
    END LOOP;
    RAISE NOTICE 'V752: the locks of the short stretch taken at attempt %', n;
END $$;

-- section 14: the SIWES payment purpose, category and classification, now that no payment and no memo can be written. Their V427
-- triggers rebuild the category memo from every payment committed before the locks (an old-portal SIWES payment written while V752
-- waited, its item text new, reads SIWES) and the owner memo
INSERT INTO finance.payment_purpose (code, label, ord, gl_account) VALUES ('SIWES_FEE', 'SIWES registration fee', 96, '4090')
ON CONFLICT (code) DO NOTHING;
INSERT INTO finance.payment_category (code, label, pattern, ord, purpose) VALUES ('SIWES', 'SIWES registration fee', '^siwes', 93, 'SIWES_FEE')
ON CONFLICT (code) DO NOTHING;
INSERT INTO finance.payment_classification (purpose, programme_type, source_module, responsible_office, note)
VALUES ('SIWES_FEE', NULL, 'SIWES', 'academic', 'The SIWES registration fee (V752): the Academic Office runs SIWES registration; the Bursary states the fee and reconciles it')
ON CONFLICT ON CONSTRAINT uq_payment_classification DO NOTHING;
DO $$
DECLARE v_other text;
BEGIN
    -- the old portal's SIWES item texts as the memo now reads them (a few rows): any under another category is said, never hidden
    SELECT string_agg(m.purpose || ' → ' || m.code, '; ' ORDER BY m.purpose) INTO v_other
      FROM finance.category_memo m WHERE m.kind = '' AND finance.is_siwes_purpose(m.purpose) AND m.code <> 'SIWES';
    RAISE NOTICE 'V752: the SIWES payment category added and the memos rebuilt; SIWES item texts read under another category: %', coalesce(v_other, 'none');
END $$;

-- the second SIWES payments on record, credited by the one rule (section 17), while no payment can be written
DO $$
DECLARE b record;
BEGIN
    SELECT * INTO b FROM finance.siwes_credit_second_payments();
    RAISE NOTICE 'V752: the second SIWES payments on record credited by the one rule: % student-session(s), % credit(s) of ₦% for the Bursary to refund or move, % of them waiting on the bank check of a possible double charge (V561: Old Fees History, possible double charges)',
        b.students, b.credits, b.amount, b.held;
END $$;

ALTER TABLE registration.siwes_period ADD FOREIGN KEY (session) REFERENCES policy.academic_session(name);
ALTER TABLE registration.siwes_programme ADD FOREIGN KEY (programme_code) REFERENCES ref.programme(code) ON UPDATE CASCADE;
ALTER TABLE registration.siwes_course ADD FOREIGN KEY (programme_code) REFERENCES ref.programme(code) ON UPDATE CASCADE,
                                      ADD FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE finance.siwes_fee ADD FOREIGN KEY (session) REFERENCES policy.academic_session(name);
ALTER TABLE finance.siwes_fee_change ADD FOREIGN KEY (session) REFERENCES policy.academic_session(name);
ALTER TABLE finance.siwes_credit ADD FOREIGN KEY (student_id) REFERENCES people.student(id) ON DELETE CASCADE,
                                 ADD FOREIGN KEY (session) REFERENCES policy.academic_session(name),
                                 ADD FOREIGN KEY (reference_id) REFERENCES finance.payment_reference(id) ON DELETE CASCADE;
ALTER TABLE registration.siwes_registration
    ADD FOREIGN KEY (student_id) REFERENCES people.student(id) ON DELETE CASCADE,
    ADD FOREIGN KEY (session) REFERENCES policy.academic_session(name),
    ADD FOREIGN KEY (course_registration_id) REFERENCES registration.course_registration(id) ON DELETE CASCADE,
    ADD FOREIGN KEY (offering_id) REFERENCES catalogue.offering(id) ON DELETE CASCADE,
    ADD FOREIGN KEY (course_code) REFERENCES catalogue.course(code) ON UPDATE CASCADE ON DELETE CASCADE,
    ADD FOREIGN KEY (payment_reference_id) REFERENCES finance.payment_reference(id) ON DELETE CASCADE,
    ADD FOREIGN KEY (legacy_payment_id) REFERENCES finance.payment_reference(id) ON DELETE CASCADE;

CREATE TRIGGER trg_siwes_reference_confirmed AFTER UPDATE OF confirmed_at ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.confirmed_at IS NULL AND NEW.confirmed_at IS NOT NULL AND NEW.purpose LIKE 'SIWES registration fee%')
    EXECUTE FUNCTION finance.siwes_reference_confirmed();

CREATE TRIGGER trg_siwes_credit_follows_payment AFTER UPDATE OF purpose, session, student_id ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.purpose IS DISTINCT FROM NEW.purpose OR OLD.session IS DISTINCT FROM NEW.session OR OLD.student_id IS DISTINCT FROM NEW.student_id)
    EXECUTE FUNCTION finance.siwes_credit_follows_payment();

CREATE TRIGGER trg_siwes_settling_follows_payment AFTER UPDATE OF purpose, session, student_id, archived_at, confirmed_at ON finance.payment_reference
    FOR EACH ROW WHEN ((OLD.purpose IS DISTINCT FROM NEW.purpose OR OLD.session IS DISTINCT FROM NEW.session OR OLD.student_id IS DISTINCT FROM NEW.student_id
                        OR OLD.archived_at IS DISTINCT FROM NEW.archived_at OR OLD.confirmed_at IS DISTINCT FROM NEW.confirmed_at)
                       AND (OLD.confirmed_at IS NOT NULL OR NEW.confirmed_at IS NOT NULL)
                       AND (finance.is_siwes_purpose(OLD.purpose) OR finance.is_siwes_purpose(NEW.purpose)))
    EXECUTE FUNCTION finance.siwes_settling_follows_payment();

CREATE TRIGGER trg_siwes_settling_follows_delete AFTER DELETE ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.confirmed_at IS NOT NULL AND OLD.student_id IS NOT NULL AND finance.is_siwes_purpose(OLD.purpose))
    EXECUTE FUNCTION finance.siwes_settling_follows_payment();

-- the old portal's payments are inserted confirmed (the import, and its reload after the old fees reset deleted them)
CREATE TRIGGER trg_siwes_settling_follows_insert AFTER INSERT ON finance.payment_reference
    FOR EACH ROW WHEN (NEW.confirmed_at IS NOT NULL AND NEW.student_id IS NOT NULL AND NEW.archived_at IS NULL AND finance.is_siwes_purpose(NEW.purpose))
    EXECUTE FUNCTION finance.siwes_settling_follows_payment();

CREATE TRIGGER trg_siwes_refund_follows AFTER INSERT OR UPDATE OF state ON finance.refund
    FOR EACH ROW WHEN (NEW.state IN ('APPROVED', 'PAID') AND NEW.source_reference IS NOT NULL)
    EXECUTE FUNCTION finance.siwes_refund_follows();

-- named to fire after trg_entry_once_a_session and before trg_entry_spillover_carry and trg_entry_stream (row triggers fire by name)
CREATE TRIGGER trg_entry_siwes_only BEFORE INSERT OR UPDATE OF offering_id, status ON registration.entry
    FOR EACH ROW EXECUTE FUNCTION registration.entry_siwes_only();

CREATE TRIGGER trg_registration_siwes_not_returned BEFORE UPDATE OF status ON registration.course_registration
    FOR EACH ROW WHEN ((NEW.status = 'RETURNED' AND OLD.status IS DISTINCT FROM 'RETURNED')
                       OR (OLD.status IN ('APPROVED', 'LOCKED') AND NEW.status IS DISTINCT FROM OLD.status AND NEW.status IS DISTINCT FROM 'LOCKED'))
    EXECUTE FUNCTION registration.siwes_registration_not_returned();

-- the Bursary's bank check of a SIWES day, and a withdrawal of a SIWES record as never received: the one rule again (finance.siwes_stand_again)
CREATE TRIGGER trg_siwes_bank_check_follows AFTER INSERT OR UPDATE OF verdict, not_received ON finance.double_charge_check
    FOR EACH ROW WHEN (finance.is_siwes_purpose(NEW.purpose))
    EXECUTE FUNCTION finance.siwes_bank_check_follows();
CREATE TRIGGER trg_siwes_bank_check_removed AFTER DELETE ON finance.double_charge_check
    FOR EACH ROW WHEN (finance.is_siwes_purpose(OLD.purpose))
    EXECUTE FUNCTION finance.siwes_bank_check_follows();
CREATE TRIGGER trg_siwes_withdrawal_follows AFTER INSERT OR UPDATE OF state ON finance.payment_not_received
    FOR EACH ROW WHEN (finance.is_siwes_purpose(NEW.purpose))
    EXECUTE FUNCTION finance.siwes_bank_check_follows();


COMMIT;
