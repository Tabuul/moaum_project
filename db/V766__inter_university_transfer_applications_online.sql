-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- V766 — Inter-university transfer applications online
--
--   The University's request: "a link that students from other universities open to apply themselves". Until now an incoming
--   inter-university transfer existed only once an officer prepared it (V588's file, V763's form). A student of another
--   university now applies on their own at a public link, under the University's decisions of 15 November 2026:
--     · a transfer window the Academic Office opens each session (admissions.iut_window: DRAFT, OPEN or CLOSED, with its dates
--       and the message the public reads while it is not open), listing the programmes and levels that take transfer students
--       (admissions.iut_line, with places if the Office limits them); the public form offers only those. The window opens only
--       with a programme taking transfers and the session's fee published (a fee of nothing is published too), so nothing is
--       charged at a guess and nobody is left registered with no way to pay; while it is open its last programme taking
--       transfers is not closed or removed (the window is closed instead). A line whose programme is archived or merged away,
--       or shortened past its level, after it was added offers nothing, and counts for nothing: an open window left offering no
--       programme and level in use reads closed to the public, the sign-in page and the website. Closing stops new applications
--       only (V312's rule): an application made before may still pay, upload, submit, be corrected and be decided; its programme
--       and level no longer change. Asked for no session, the desks open on the window being run (the open one, else the latest
--       session with applications on their hands — a window closed keeps its desk work, and lines or a fee readied for the next
--       session do not take the desks off it — else one set open but not open today), not the current session;
--     · an application fee the Bursary states (bursar, studentaccounts, super) and the Bursar publishes (bursar, super) for each
--       session, possibly nothing (finance.iut_fee, kept with its history as the SIWES fee is, V752), paid online on a reference of
--       its own (admissions.iut_fee_reference, MOAUM-IUTAPP-YYYY-NNNNNN) before the application is submitted; a fee of nothing is
--       settled at registration, and a fee restated to nothing settles a draft still unpaid without it (its reference is no longer
--       taken, and money paid on it anyway is owed back). A second payment for the same application is owed back (the Bursary's
--       payments report says so until the refund desk has given it back, and the refund desk pays it); the fee is not refunded
--       when an application is declined or withdrawn, as every other application fee — the refund desk refuses a refund of the
--       payment that settled an application (REFUND_IUT_SETTLES). A payment received at the bank is posted by the Bursary's
--       two-person bank credit as any other reference; one confirmed between the proposal and the approval is posted to it as the
--       same money only on the machine's evidence that the credit is that payment — Interswitch's settlement row carrying one of
--       the identifiers the gateway or the collections import gave the payment, as its confirmation kept them (every one: the
--       Payment Log Id, the payment reference, the WebPAY transaction reference asked and the RRN), or the collections
--       statement's line whose bank reference (the bank's own field) is one of them — never by the portal reference itself or any
--       piece of it (the reference written short), which every payment for it quotes, never by a collections line's bank
--       reference that is a bare number shorter than an RRN (a teller's) or that holds the portal reference (WebPAY's
--       '<reference>-A2', which a payer may copy), and never once another bank credit is posted to the reference (one payment is
--       posted once). Free text is never evidence: a reference the Bursar confirmed by hand takes no bank credit at all (a note
--       naming two tellers, another branch or the reference written short posted real second payments as nothing), and a
--       collections line's narration is the payer's own words (a transfer quoting the first payment's Log Id, RRN or card
--       transaction posted a real second payment as nothing). Everything else is refused
--       (IUT_FEE_ALREADY_PAID, worded by how the reference was confirmed: the officer checks the bank's record and rejects the
--       proposal; money received twice is owed back, for the refund desk). So the same money is never told to be refunded, and a
--       second payment is never posted as nothing;
--     · the applicant's own account (admissions.iut_account: an e-mail, a Nigerian phone and a password) holding one application
--       a session (admissions.iut_application, IUT/APP/YYYY/NNNNNN), signed in under the applicant office — never a Post-UTME,
--       postgraduate or JUPEB account, whose tables belong to their own routes. One application in progress under a JAMB number:
--       a draft holds it too, so the Registry may end a draft made under another person's number, its reason told (never for
--       lateness: a started application has no deadline);
--     · uploaded documents (admissions.iut_document: the transcript, a letter of release or of good standing, the JAMB admission
--       letter, the O'Level result and the like — kinds the Academic Office keeps, admissions.iut_document_kind), uploaded once the
--       fee is settled and checked one by one by the Registry before the department sees the application: an explicit exception,
--       by the University's decision, to the rule that applicants never upload;
--     · the Head of Department of the programme applied for (or the College's Dean, V734's rule) recommends — accept at a level the
--       window opens, or decline with a reason — and the Academic Office or the Registry approves: the approval registers the
--       transfer exactly as V763's form does (people.register_university_transfer), a batch of one (source APPLICATION) that
--       another officer decides on the existing Inter-University Transfer page under V588's rule. That decision moves the
--       application: approved, the student is on the register (TRANSFER, ADMITTED, the level recommended, with the account's
--       e-mail and phone as they stand at the decision, an applicant's change after the approval included) and the application
--       ADMITTED; rejected there, the application goes back to the Registry's desk untold, for a fresh approval or a refusal
--       in words meant for the applicant. An applicant is never admitted onto a record already on the register: an application
--       whose JAMB number V763's check would record on an existing student is not approved, nor is such a transfer completed;
--     · the applicant is told (e-mail and SMS) when the application is made, paid, submitted, returned for a correction, with the
--       department, admitted, refused and withdrawn — never at a recommendation or an approval before the second officer decides,
--       and their own page reads those three alike ("with the Registry for a decision": WITH_REGISTRY), the applicant's own
--       withdrawal included (open until the department has assessed it, then asked of the Registry in all three alike);
--       the Head of Department (or the Dean) is told when an application reaches the desk, and reads it without the applicant's
--       contact, the fee, the transfer or the Registry's words to the applicant or the record (the notes of a return, a rejection,
--       a document rejected or the approval), its history included; the applicant never reads the Registry's note to the department;
--     · the payment runs through the gateways every applicant fee uses: the reference is joined wherever the JUPEB store is —
--       its state, Quickteller and PAYDirect, the collections import, the receipts reported, the payers told, the day book, the
--       payments view (and through it the ledger, Financial Analytics, Collections and the master report: source IUT, category
--       IUT_APPLICATION, purpose APPLICATION) — and the go-live data reset clears the applications (the window, programmes,
--       document kinds and fee are configuration and are kept).
--   No letter of admission is printed for an admitted transfer student here (a follow-up for the University); the admission
--   number is in the notice and on the application's page.
--
--   The tables are made first, without their keys onto the portal's tables; the keys, the trigger on the transfers, the changed
--   checks, the payments view and the payment category come last, in a short stretch: a key or a trigger holds every writer of its
--   table until the commit.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V766: inter-university transfer applications online', true);

-- ── 1 · the window, the programmes and levels, the documents asked for: the Academic Office's ─────────────────────────────
CREATE TABLE admissions.iut_window (
    session        text PRIMARY KEY,                         -- policy.academic_session (section 13)
    state          text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'OPEN', 'CLOSED')),
    opens_on       date,
    closes_on      date,
    closed_message text CHECK (closed_message IS NULL OR length(closed_message) <= 2000),
    note           text,
    set_by         uuid NOT NULL,
    set_office     text NOT NULL,
    set_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_iut_window_dated CHECK (state <> 'OPEN' OR (opens_on IS NOT NULL AND closes_on IS NOT NULL)),
    CONSTRAINT ck_iut_window_dates CHECK (opens_on IS NULL OR closes_on IS NULL OR closes_on >= opens_on)
);
COMMENT ON TABLE admissions.iut_window IS
  'V766: the inter-university transfer application window of a session, the Academic Office''s (academic, registrar, dregistrar, super): DRAFT binds nobody; OPEN between its dates (Lagos days) takes new applications, and opens only with a programme taking transfers and the session''s fee published; CLOSED stops new applications only. closed_message is what the public reads while it is not open.';
SELECT audit.attach('admissions.iut_window');

CREATE TABLE admissions.iut_line (
    session        text NOT NULL REFERENCES admissions.iut_window(session) ON DELETE CASCADE,
    programme_code text NOT NULL,                            -- ref.programme (section 13)
    level          integer NOT NULL CHECK (level BETWEEN 100 AND 900 AND level % 100 = 0),
    places         integer CHECK (places IS NULL OR places >= 1),
    accepting      boolean NOT NULL DEFAULT true,
    added_by       uuid NOT NULL,
    added_office   text NOT NULL,
    added_at       timestamptz NOT NULL DEFAULT now(),
    changed_by     uuid,
    changed_office text,
    changed_at     timestamptz,
    PRIMARY KEY (session, programme_code, level)
);
CREATE INDEX ix_iut_line_programme ON admissions.iut_line (programme_code);
COMMENT ON TABLE admissions.iut_line IS
  'V766: a programme and level taking transfer students in a session. places: the most approved and admitted at that level (NULL: no limit), counted at the level the Head of Department recommended; accepting false: closed to new applications and new choices, the applications made on it untouched.';
SELECT audit.attach('admissions.iut_line');

/* the one rule of a programme that takes transfer students: an undergraduate programme in use. A line stays when its programme is
   archived or merged away after it was added, but offers nothing from then on (admissions.iut_line_offered, below, which the public
   list, the door, the window's status — an open window offering none reads CLOSED — and the open window's last line read) */
CREATE FUNCTION admissions.iut_programme_in_use(p_code text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM ref.programme p WHERE p.code = p_code AND p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false));
$$;
COMMENT ON FUNCTION admissions.iut_programme_in_use(text) IS
  'V766: whether a programme takes inter-university transfer students — an undergraduate programme not archived. A line of a programme archived or merged away since it was added offers nothing to the public (admissions.iut_window_status reads an open window offering none CLOSED).';

/* the one rule of a line the public is offered (taking applications aside): its programme in use, and its level still one of the
   programme's. A line stays when its programme is shortened past it (ref.set_programme_length, V598/V634) after it was added, as it
   stays when the programme is archived, but offers nothing from then on: no Head of Department could recommend at that level */
CREATE FUNCTION admissions.iut_line_offered(p_code text, p_level integer) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT admissions.iut_programme_in_use(p_code) AND coalesce(p_level = ANY (people.programme_levels(p_code)), false);
$$;
COMMENT ON FUNCTION admissions.iut_line_offered(text, integer) IS
  'V766: whether a programme and level can be offered to inter-university transfer applicants — the programme in use (admissions.iut_programme_in_use) and the level one of its levels (people.programme_levels). A line whose programme was archived or merged away, or shortened past its level, since it was added offers nothing: the public list, the door, the window''s status and the open window''s last line all read a line through this.';

/* a transfer student comes into an undergraduate programme in use, at one of its levels. A line moved to another programme (a merge,
   V574) that cannot take it is refused as a key the programme does not hold (23503): the merge keeps such a line on the old code,
   as MOVE_UNLESS_HELD keeps any setting the kept programme cannot take, where a 23514 would stop the whole merge */
CREATE FUNCTION admissions.iut_line_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_code text := CASE WHEN TG_OP = 'UPDATE' AND NEW.programme_code IS DISTINCT FROM OLD.programme_code THEN '23503' ELSE '23514' END;
BEGIN
    IF NOT admissions.iut_programme_in_use(NEW.programme_code) THEN
        RAISE EXCEPTION 'IUT_PROGRAMME: % is not an undergraduate programme in use; transfer students come into undergraduate programmes', NEW.programme_code
            USING ERRCODE = v_code;
    END IF;
    IF NOT coalesce(NEW.level = ANY (people.programme_levels(NEW.programme_code)), false) THEN
        RAISE EXCEPTION 'IUT_LEVEL: % Level is not a level of %', NEW.level, (SELECT p.name FROM ref.programme p WHERE p.code = NEW.programme_code)
            USING ERRCODE = v_code;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_iut_line_guard BEFORE INSERT OR UPDATE OF programme_code, level ON admissions.iut_line
    FOR EACH ROW EXECUTE FUNCTION admissions.iut_line_guard();

CREATE TABLE admissions.iut_document_kind (
    code           text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{2,39}$'),
    label          text NOT NULL CHECK (length(btrim(label)) BETWEEN 3 AND 160),
    hint           text CHECK (hint IS NULL OR length(hint) <= 400),
    required       boolean NOT NULL,
    images_allowed boolean NOT NULL DEFAULT true,            -- PDF always; JPEG and PNG only when true
    transfer_code  text CHECK (transfer_code IS NULL OR transfer_code IN ('TRANSCRIPT', 'RELEASE_LETTER', 'JAMB_ADMISSION_LETTER', 'OLEVEL_RESULT')),
    ord            integer NOT NULL,
    active         boolean NOT NULL DEFAULT true,
    changed_by     uuid,
    changed_office text,
    changed_at     timestamptz
);
COMMENT ON TABLE admissions.iut_document_kind IS
  'V766: the documents an inter-university transfer applicant uploads, kept by the Academic Office. transfer_code: the V763 document code an accepted one counts as on the transfer (set by the seed, never edited). A change of required applies to submissions made after it; a submitted application is never held again.';
COMMENT ON COLUMN admissions.iut_document_kind.transfer_code IS 'V766: the V763 people.university_transfer.documents code this kind counts as once the Registry accepts it; set by the seed, never edited';
SELECT audit.attach('admissions.iut_document_kind');

INSERT INTO admissions.iut_document_kind (code, label, hint, required, images_allowed, transfer_code, ord, changed_by, changed_office, changed_at) VALUES
    ('TRANSCRIPT', 'Academic transcript or statement of results from your present university', 'Every semester you have completed, with your CGPA', true, true, 'TRANSCRIPT', 10,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('RELEASE_LETTER', 'Letter of release, or of good standing, from your present university', 'Signed by its Registrar or your Dean', true, true, 'RELEASE_LETTER', 20,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('JAMB_ADMISSION_LETTER', 'JAMB admission letter', 'Printed from JAMB''s portal', true, true, 'JAMB_ADMISSION_LETTER', 30,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('OLEVEL_RESULT', 'O''Level result (WAEC, NECO or NABTEB)', NULL, true, true, 'OLEVEL_RESULT', 40,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('OLEVEL_RESULT_2', 'O''Level result, second sitting (if any)', NULL, false, true, 'OLEVEL_RESULT', 50,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('ADMISSION_LETTER', 'Admission letter from your present university', NULL, false, true, NULL, 60,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('STUDENT_ID_CARD', 'Identity card of your present university', NULL, false, true, NULL, 70,
     '00000000-0000-0000-0000-000000000000', 'academic', now()),
    ('OTHER', 'Any other supporting document', NULL, false, true, NULL, 80,
     '00000000-0000-0000-0000-000000000000', 'academic', now());

-- ── 2 · the fee: the Bursary's, stated and published per session (zero allowed); its history ─────────────────────────────
CREATE TABLE finance.iut_fee (
    session          text PRIMARY KEY,                       -- policy.academic_session (section 13)
    amount           numeric(12,2) NOT NULL CHECK (amount >= 0),   -- the fee in force once PUBLISHED; before that, the draft's
    state            text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'PUBLISHED')),
    note             text,
    stated_by        uuid NOT NULL,
    stated_office    text NOT NULL,
    stated_at        timestamptz NOT NULL DEFAULT now(),
    published_by     uuid,
    published_office text,
    published_at     timestamptz,
    -- a restatement waiting for the Bursar: the published figure stays in force until it is published
    draft_amount     numeric(12,2) CHECK (draft_amount >= 0),
    draft_note       text,
    drafted_by       uuid,
    drafted_office   text,
    drafted_at       timestamptz,
    CONSTRAINT ck_iut_fee_published CHECK (state = 'DRAFT' OR published_at IS NOT NULL),
    CONSTRAINT ck_iut_fee_draft CHECK ((draft_amount IS NULL) = (drafted_at IS NULL) AND (draft_amount IS NULL) = (drafted_by IS NULL))
);
COMMENT ON TABLE finance.iut_fee IS
  'V766: the inter-university transfer application fee of a session — stated by the Bursary (bursar, studentaccounts, super), published by the Bursar (bursar, super), zero allowed; a reference keeps the figure it was drawn at';
SELECT audit.attach('finance.iut_fee');

CREATE TABLE finance.iut_fee_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text NOT NULL,                            -- policy.academic_session (section 13)
    action         text NOT NULL CHECK (action IN ('STATED', 'PUBLISHED')),
    amount         numeric(12,2) NOT NULL,
    was_amount     numeric(12,2),
    was_state      text,
    note           text,
    changed_by     uuid NOT NULL,
    changed_office text NOT NULL,
    changed_at     timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX ix_iut_fee_change_session ON finance.iut_fee_change (session, changed_at);
COMMENT ON TABLE finance.iut_fee_change IS 'V766: every statement and publication of an inter-university transfer application fee, as it was made.';
SELECT audit.attach('finance.iut_fee_change');

/* every statement and publication is kept, whoever writes it (finance.siwes_fee_history's rule) */
CREATE FUNCTION finance.iut_fee_history() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.draft_amount IS NOT NULL
       AND (TG_OP = 'INSERT' OR (NEW.draft_amount, NEW.draft_note, NEW.drafted_by, NEW.drafted_at) IS DISTINCT FROM (OLD.draft_amount, OLD.draft_note, OLD.drafted_by, OLD.drafted_at)) THEN
        INSERT INTO finance.iut_fee_change (session, action, amount, was_amount, was_state, note, changed_by, changed_office)
        VALUES (NEW.session, 'STATED', NEW.draft_amount,
                CASE WHEN TG_OP = 'UPDATE' THEN coalesce(CASE WHEN OLD.state = 'PUBLISHED' THEN OLD.amount END, OLD.draft_amount, OLD.amount) END,
                CASE WHEN TG_OP = 'UPDATE' THEN OLD.state END, NEW.draft_note, NEW.drafted_by, NEW.drafted_office);
    END IF;
    IF NEW.state = 'PUBLISHED' AND (TG_OP = 'INSERT' OR OLD.state <> 'PUBLISHED' OR (OLD.draft_amount IS NOT NULL AND NEW.draft_amount IS NULL)
                                    OR NEW.published_at IS DISTINCT FROM OLD.published_at) THEN
        INSERT INTO finance.iut_fee_change (session, action, amount, was_amount, was_state, note, changed_by, changed_office)
        VALUES (NEW.session, 'PUBLISHED', NEW.amount, CASE WHEN TG_OP = 'UPDATE' AND OLD.state = 'PUBLISHED' THEN OLD.amount END,
                CASE WHEN TG_OP = 'UPDATE' THEN OLD.state END, NEW.note, coalesce(NEW.published_by, NEW.stated_by), coalesce(NEW.published_office, NEW.stated_office));
    END IF;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_iut_fee_history AFTER INSERT OR UPDATE ON finance.iut_fee FOR EACH ROW EXECUTE FUNCTION finance.iut_fee_history();

-- ── 3 · the applicant: the account, the application, its documents, its fee references, its history ──────────────────────
CREATE TABLE admissions.iut_account (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),     -- the token subject
    email               text NOT NULL CONSTRAINT ck_iut_account_email CHECK (email ~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$'),
    phone               text NOT NULL CONSTRAINT ck_iut_account_phone CHECK (phone ~ '^0[0-9]{10}$'),
    password_hash       text NOT NULL CONSTRAINT ck_iut_account_hash CHECK (password_hash LIKE '$2%$12$%'),
    failed_attempts     integer NOT NULL DEFAULT 0,
    locked_until        timestamptz,
    last_signed_in_at   timestamptz,
    password_changed_at timestamptz,
    created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ux_iut_account_email ON admissions.iut_account (lower(email));
COMMENT ON TABLE admissions.iut_account IS
  'V766: an inter-university transfer applicant''s account — the e-mail, the phone and the password (bcrypt, cost 12, hashed by the API) — holding at most one application a session. Signed in under the applicant office; the transfer pages find the account here from the token, so no other applicant''s token reaches them.';
SELECT audit.exempt('admissions.iut_account',
  'V766: carries a password hash, as admissions.applicant_account and admissions.pg_applicant do; every act on the application is on the spine');

CREATE TABLE admissions.iut_application (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_id          uuid NOT NULL REFERENCES admissions.iut_account(id),
    session             text NOT NULL REFERENCES admissions.iut_window(session),
    application_no      text NOT NULL UNIQUE CHECK (application_no ~ '^IUT/APP/[0-9]{4}/[0-9]{6}$'),
    state               text NOT NULL DEFAULT 'DRAFT' CHECK (state IN ('DRAFT', 'SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD', 'RECOMMENDED', 'NOT_RECOMMENDED',
                                                                       'APPROVED', 'ADMITTED', 'REJECTED', 'WITHDRAWN')),
    jamb_reg_no         text NOT NULL CHECK (jamb_reg_no ~ '^[0-9]{12}[A-Z]{2,3}$'),
    surname             text NOT NULL CHECK (surname = upper(surname) AND length(btrim(surname)) BETWEEN 2 AND 60),
    other_names         text NOT NULL CHECK (length(btrim(other_names)) BETWEEN 2 AND 120),
    sex                 text NOT NULL CHECK (sex IN ('M', 'F')),
    date_of_birth       date NOT NULL,                       -- 14 to 70 on the day of applying: the functions' rule
    university_code     text,                                -- ref.university (section 13)
    university_named    text CHECK (university_named IS NULL OR length(university_named) <= 200),
    other_matric_no     text NOT NULL CHECK (other_matric_no ~ '^[A-Z0-9][A-Z0-9/._-]{0,39}$'),
    other_programme     text NOT NULL CHECK (length(btrim(other_programme)) BETWEEN 3 AND 200),
    other_level         integer NOT NULL CHECK (other_level BETWEEN 100 AND 900 AND other_level % 100 = 0),
    other_entry_session text NOT NULL,
    other_cgpa          numeric(3,2) NOT NULL,
    other_cgpa_scale    smallint NOT NULL,
    programme_code      text NOT NULL,                       -- ref.programme (section 13): the programme applied for
    level               integer NOT NULL CHECK (level BETWEEN 100 AND 900 AND level % 100 = 0),
    reason              text NOT NULL CHECK (length(btrim(reason)) BETWEEN 20 AND 2000),
    fee_settled_at      timestamptz,
    fee_basis           text CHECK (fee_basis IN ('PAID', 'NONE_DUE')),
    submitted_at        timestamptz,                         -- the first submission
    last_submitted_at   timestamptz,
    declaration_ip      text,
    hod_decision        text CHECK (hod_decision IN ('ACCEPT', 'DECLINE')),
    hod_level           integer CHECK (hod_level IS NULL OR (hod_level BETWEEN 100 AND 900 AND hod_level % 100 = 0)),
    hod_note            text CHECK (hod_note IS NULL OR length(hod_note) <= 2000),
    hod_by              uuid,
    hod_office          text,
    hod_at              timestamptz,
    registry_by         uuid,                                -- the Registry's latest act: approve, reject or return
    registry_office     text,
    registry_at         timestamptz,
    registry_note       text CHECK (registry_note IS NULL OR length(registry_note) <= 2000),
    approval_ref        text CHECK (approval_ref IS NULL OR length(approval_ref) <= 120),
    transfer_id         uuid,                                -- people.university_transfer (section 13)
    student_id          uuid,                                -- people.student (section 13)
    withdrawn_at        timestamptz,
    withdrawn_reason    text CHECK (withdrawn_reason IS NULL OR length(withdrawn_reason) <= 500),
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_iut_app_account_session UNIQUE (account_id, session),
    CONSTRAINT ck_iut_app_university CHECK (university_code IS NOT NULL OR length(btrim(university_named)) BETWEEN 3 AND 200),
    CONSTRAINT ck_iut_app_entry CHECK (CASE WHEN other_entry_session ~ '^[0-9]{4}/[0-9]{4}$'
                                            THEN substr(other_entry_session, 6, 4)::int = substr(other_entry_session, 1, 4)::int + 1 AND other_entry_session <= session
                                            ELSE false END),
    CONSTRAINT ck_iut_app_cgpa CHECK (other_cgpa_scale IN (4, 5) AND other_cgpa BETWEEN 0 AND other_cgpa_scale),
    CONSTRAINT ck_iut_app_fee CHECK ((fee_settled_at IS NULL) = (fee_basis IS NULL)),
    CONSTRAINT ck_iut_app_hod CHECK ((hod_decision IS NULL) = (hod_at IS NULL)
                                     AND (hod_decision IS DISTINCT FROM 'ACCEPT' OR hod_level IS NOT NULL)
                                     AND (hod_decision IS DISTINCT FROM 'DECLINE' OR length(btrim(hod_note)) >= 10)),
    -- a draft the Registry ended (REJECTED: made under another person's JAMB number) was never submitted
    CONSTRAINT ck_iut_app_submitted CHECK (state IN ('DRAFT', 'WITHDRAWN', 'REJECTED') OR submitted_at IS NOT NULL),
    CONSTRAINT ck_iut_app_paid CHECK (submitted_at IS NULL OR fee_settled_at IS NOT NULL),
    CONSTRAINT ck_iut_app_recommended CHECK (state <> 'RECOMMENDED' OR hod_decision = 'ACCEPT'),
    CONSTRAINT ck_iut_app_not_recommended CHECK (state <> 'NOT_RECOMMENDED' OR hod_decision = 'DECLINE'),
    CONSTRAINT ck_iut_app_approved CHECK (state <> 'APPROVED' OR transfer_id IS NOT NULL),
    CONSTRAINT ck_iut_app_withdrawn CHECK ((state = 'WITHDRAWN') = (withdrawn_at IS NOT NULL)),
    CONSTRAINT ck_iut_app_rejected CHECK (state <> 'REJECTED' OR length(btrim(registry_note)) >= 10)
);
-- one application in progress under a JAMB number; a refused or withdrawn one leaves the number free
CREATE UNIQUE INDEX ux_iut_app_live_jamb ON admissions.iut_application (upper(jamb_reg_no)) WHERE state NOT IN ('REJECTED', 'WITHDRAWN');
CREATE UNIQUE INDEX ux_iut_app_transfer ON admissions.iut_application (transfer_id) WHERE transfer_id IS NOT NULL;
CREATE INDEX ix_iut_app_session_state ON admissions.iut_application (session, state);
CREATE INDEX ix_iut_app_programme ON admissions.iut_application (programme_code);
CREATE INDEX ix_iut_app_student ON admissions.iut_application (student_id) WHERE student_id IS NOT NULL;
COMMENT ON TABLE admissions.iut_application IS
  'V766: an online inter-university transfer application. DRAFT (paid, documents uploaded, then submitted) → SUBMITTED (the Registry checks each document) → CORRECTION_REQUIRED (returned to the applicant) or WITH_HOD → RECOMMENDED (accepted at hod_level) or NOT_RECOMMENDED → APPROVED (registered as the V763 transfer transfer_id, for another officer''s decision) → ADMITTED (student_id); REJECTED by the Registry (registry_note told; a draft too, ended so: one made under another person''s JAMB number holds the number) and WITHDRAWN by the applicant end it. A transfer the second officer rejects returns it to RECOMMENDED.';
COMMENT ON COLUMN admissions.iut_application.university_named IS 'V766: the university the applicant typed when theirs is not on the list (ref.university); kept as typed once the Registry sets the code';
COMMENT ON COLUMN admissions.iut_application.transfer_id IS 'V766: the V588/V763 incoming transfer the approval registered (a batch of one, source APPLICATION), awaiting or given another officer''s decision';
SELECT audit.attach('admissions.iut_application');

CREATE FUNCTION admissions.iut_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END $$;
CREATE TRIGGER trg_iut_application_touch BEFORE UPDATE ON admissions.iut_application FOR EACH ROW EXECUTE FUNCTION admissions.iut_touch();

CREATE TABLE admissions.iut_document (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id  uuid NOT NULL REFERENCES admissions.iut_application(id) ON DELETE CASCADE,
    kind            text NOT NULL REFERENCES admissions.iut_document_kind(code),
    filename        text NOT NULL CHECK (length(filename) BETWEEN 1 AND 200),
    content_type    text NOT NULL CHECK (content_type IN ('application/pdf', 'image/jpeg', 'image/png')),
    bytes           integer NOT NULL CHECK (bytes BETWEEN 1 AND 5242880),
    sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    stored          text NOT NULL CHECK (stored IN ('OBJECT', 'BLOB')),
    object_id       uuid,                                    -- platform.file_object (section 13)
    status          text NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACCEPTED', 'REJECTED')),
    review_note     text CHECK (review_note IS NULL OR length(review_note) <= 1000),
    reviewed_by     uuid,
    reviewed_office text,
    reviewed_at     timestamptz,
    uploaded_at     timestamptz NOT NULL DEFAULT now(),
    superseded_at   timestamptz,                             -- replaced or removed: kept, never deleted
    superseded_by   uuid,                                    -- the document that replaced it
    CONSTRAINT ck_iut_doc_stored CHECK ((stored = 'OBJECT') = (object_id IS NOT NULL)),
    CONSTRAINT ck_iut_doc_reviewed CHECK ((status = 'PENDING') = (reviewed_at IS NULL)),
    CONSTRAINT ck_iut_doc_rejected_note CHECK (status <> 'REJECTED' OR length(btrim(review_note)) >= 10)
);
CREATE UNIQUE INDEX ux_iut_document_current ON admissions.iut_document (application_id, kind) WHERE superseded_at IS NULL;
CREATE INDEX ix_iut_document_application ON admissions.iut_document (application_id);
CREATE INDEX ix_iut_document_object ON admissions.iut_document (object_id) WHERE object_id IS NOT NULL;
COMMENT ON TABLE admissions.iut_document IS
  'V766: a document an inter-university transfer applicant uploaded (PDF, JPEG or PNG, up to 5 MB), held in the file store (OBJECT) or here (BLOB, admissions.iut_document_blob), checked by the Registry (ACCEPTED or REJECTED with its note). One current document a kind; a replaced or removed one is kept as superseded.';
SELECT audit.attach('admissions.iut_document');

CREATE TABLE admissions.iut_document_blob (
    document_id uuid PRIMARY KEY REFERENCES admissions.iut_document(id) ON DELETE CASCADE,
    content     bytea NOT NULL
);
COMMENT ON TABLE admissions.iut_document_blob IS 'V766: the bytes of an inter-university transfer applicant''s document when no file store is configured.';
SELECT audit.exempt('admissions.iut_document_blob',
  'V766: the file itself, up to 5 MB; the fact of it — its name, size, fingerprint, status and who checked it — is on the spine in admissions.iut_document');

CREATE TABLE admissions.iut_fee_reference (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id   uuid NOT NULL REFERENCES admissions.iut_application(id),
    kind             text NOT NULL DEFAULT 'APPLICATION' CHECK (kind = 'APPLICATION'),
    reference        text NOT NULL UNIQUE CHECK (reference ~ '^MOAUM-IUTAPP-[0-9]{4}-[0-9]{6}$'),
    amount           numeric(12,2) NOT NULL CHECK (amount > 0),
    session          text NOT NULL,
    created_at       timestamptz NOT NULL DEFAULT now(),
    expires_at       timestamptz NOT NULL,
    confirmed_at     timestamptz,
    channel          text,
    note             text,
    -- the payment's own identifiers, every one the channel that confirmed it gave (Interswitch's Payment Log Id and payment
    -- reference from PAYDirect's notice, the collections import's Log Id, WebPAY's payment reference, RRN and the transaction
    -- reference asked, a card gateway's transaction id), the first the one the receipt names: what a bank credit is compared with
    gateway_refs     text[] CHECK (gateway_refs IS NULL OR (cardinality(gateway_refs) BETWEEN 1 AND 8 AND array_position(gateway_refs, NULL) IS NULL)),
    receipt_no       text UNIQUE,
    confirmed_by     uuid,
    confirmed_office text,
    settles          boolean NOT NULL DEFAULT false,         -- the one payment that settled the application; any other confirmed one is owed back
    CONSTRAINT ck_iut_fee_receipt CHECK ((confirmed_at IS NULL) = (receipt_no IS NULL)),
    CONSTRAINT ck_iut_fee_settles CHECK (NOT settles OR confirmed_at IS NOT NULL)
);
CREATE UNIQUE INDEX ux_iut_fee_settles ON admissions.iut_fee_reference (application_id) WHERE settles;
CREATE INDEX ix_iut_fee_reference_application ON admissions.iut_fee_reference (application_id);
COMMENT ON TABLE admissions.iut_fee_reference IS
  'V766: a payment reference for an inter-university transfer application fee (MOAUM-IUTAPP-YYYY-NNNNNN), payable for 24 hours through the gateways every applicant fee uses; confirmed with a receipt in the University''s series (RCT-YYYY-NNNNN). settles: the payment that settled the application; a confirmed one that does not is owed back. gateway_refs: every identifier its channel gave the payment (a Payment Log Id, a payment reference, a WebPAY transaction reference, an RRN, a transaction id), the receipt''s first, by which a bank credit is known to be that payment.';
SELECT audit.attach('admissions.iut_fee_reference');

CREATE TABLE admissions.iut_event (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id     uuid NOT NULL REFERENCES admissions.iut_application(id) ON DELETE CASCADE,
    at                 timestamptz NOT NULL DEFAULT clock_timestamp(),
    action             text NOT NULL CHECK (action IN ('CREATED', 'EDITED', 'FEE_NONE_DUE', 'FEE_PAID', 'FEE_PAID_AGAIN', 'DOCUMENT_UPLOADED', 'DOCUMENT_REMOVED',
                                                       'DOCUMENT_ACCEPTED', 'DOCUMENT_REJECTED', 'SUBMITTED', 'RESUBMITTED', 'RETURNED', 'SENT_TO_HOD',
                                                       'RECOMMENDED', 'NOT_RECOMMENDED', 'SENT_BACK_TO_HOD', 'UNIVERSITY_SET', 'APPROVED', 'TRANSFER_REJECTED',
                                                       'ADMITTED', 'REJECTED', 'WITHDRAWN')),
    from_state         text,
    to_state           text,
    note               text,
    transfer_id        uuid,                                 -- history: no key
    actor              uuid,
    office             text,
    shown_to_applicant boolean NOT NULL DEFAULT false
);
CREATE INDEX ix_iut_event_application ON admissions.iut_event (application_id, at);
-- the Inter-University Transfer page finds the application of a transfer the second officer rejected through its history
CREATE INDEX ix_iut_event_transfer ON admissions.iut_event (transfer_id) WHERE transfer_id IS NOT NULL;
COMMENT ON TABLE admissions.iut_event IS
  'V766: the history of an inter-university transfer application, as the desks read it; the applicant reads the rows shown_to_applicant (made, paid, uploaded, submitted, returned, with the department, admitted, refused, withdrawn).';
SELECT audit.attach('admissions.iut_event');

-- ── 4 · who, when and what is open ───────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.iut_office() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL
       OR coalesce(nullif(current_setting('moaum.actor_office', true), ''), '-') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'IUT_OFFICE: the transfer window is set by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
END $$;

/* the Registry's desk: the same offices, said for the desk's acts */
CREATE FUNCTION admissions.iut_keeper() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL
       OR coalesce(nullif(current_setting('moaum.actor_office', true), ''), '-') NOT IN ('academic', 'registrar', 'dregistrar', 'super') THEN
        RAISE EXCEPTION 'IUT_OFFICE: a transfer application is checked and decided by the Academic Office or the Registry' USING ERRCODE = '42501';
    END IF;
END $$;

CREATE FUNCTION admissions.iut_session_ok(p_session text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session s WHERE s.name = p_session AND s.state IN ('PLANNED', 'CURRENT') AND s.merged_into IS NULL) THEN
        RAISE EXCEPTION 'IUT_SESSION: % is not a session that takes new students', coalesce(p_session, '(none)') USING ERRCODE = '23514';
    END IF;
END $$;

CREATE FUNCTION admissions.iut_window_status(p_session text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN w.session IS NULL OR w.state <> 'OPEN' THEN 'CLOSED'
                -- D4 kept when a programme is archived, merged away or shortened past its line while the window is open: offering
                -- nothing, it is not open
                WHEN NOT EXISTS (SELECT 1 FROM admissions.iut_line l WHERE l.session = w.session AND l.accepting
                                    AND admissions.iut_line_offered(l.programme_code, l.level)) THEN 'CLOSED'
                WHEN (now() AT TIME ZONE 'Africa/Lagos')::date < w.opens_on THEN 'SCHEDULED'
                WHEN (now() AT TIME ZONE 'Africa/Lagos')::date > w.closes_on THEN 'EXPIRED'
                ELSE 'OPEN' END
      FROM (SELECT 1) one LEFT JOIN admissions.iut_window w ON w.session = p_session;
$$;
COMMENT ON FUNCTION admissions.iut_window_status(text) IS
  'V766: OPEN (state OPEN and today, the Lagos day, between its dates), SCHEDULED (before the opening), EXPIRED (after the closing) or CLOSED (no window, DRAFT or CLOSED, or OPEN with no line taking applications that can be offered: a programme archived or merged away since, or a level the programme no longer has, offers nothing — admissions.iut_line_offered).';

CREATE FUNCTION admissions.iut_open_session() RETURNS text LANGUAGE sql STABLE AS $$
    SELECT w.session FROM admissions.iut_window w WHERE admissions.iut_window_status(w.session) = 'OPEN' ORDER BY w.session DESC LIMIT 1;
$$;

/* the session the desks open on when none is asked. Most of the desks' work (the Registry's checking, the department, the approvals)
   comes after the window closes (D5), so a session with applications on the desks' hands comes before any window merely set open
   (scheduled, expired, offering nothing) and before the University's current session, which may have no window at all. A window
   being prepared (DRAFT: lines added, a fee stated for the next session) and a draft application are never the desks' work: counting
   them moved the desks off a closed window with applications still waiting */
CREATE FUNCTION admissions.iut_desk_session() RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(admissions.iut_open_session(),
                    (SELECT a.session FROM admissions.iut_application a
                      WHERE a.state IN ('SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD', 'RECOMMENDED', 'NOT_RECOMMENDED', 'APPROVED')
                      ORDER BY a.session DESC LIMIT 1),
                    (SELECT w.session FROM admissions.iut_window w WHERE w.state = 'OPEN' ORDER BY w.session DESC LIMIT 1),
                    policy.university_current_session());
$$;
COMMENT ON FUNCTION admissions.iut_desk_session() IS
  'V766: the session the transfer application desks open on when none is asked — the open window''s; else the latest session with applications on the desks'' hands (submitted, returned for a correction, with the department, recommended or not, approved: a closed window keeps its desk work, a window being prepared for the next session never takes the desks off it); else the latest window set OPEN but not open today (scheduled, expired, or offering nothing); else the University''s current session.';

/* what a refusal at a window that is not open tells the applicant: the window's message, else the latest one's */
CREATE FUNCTION admissions.iut_closed_hint(p_session text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT nullif(btrim(w.closed_message), '') FROM admissions.iut_window w WHERE w.session = p_session),
                    (SELECT nullif(btrim(w.closed_message), '') FROM admissions.iut_window w WHERE nullif(btrim(w.closed_message), '') IS NOT NULL
                      ORDER BY w.session DESC LIMIT 1),
                    'Watch the University''s website for the next window');
$$;

/* an applicant's act is on their own application alone (the account the token names); a missing one is refused alike */
CREATE FUNCTION admissions.iut_mine(p_app uuid) RETURNS admissions.iut_application LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application;
BEGIN
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL OR coalesce(nullif(current_setting('moaum.actor_office', true), ''), '-') <> 'applicant'
       OR a.account_id IS DISTINCT FROM nullif(current_setting('moaum.actor_id', true), '')::uuid THEN
        RAISE EXCEPTION 'IUT_NOT_YOURS: this is not your transfer application' USING ERRCODE = '42501';
    END IF;
    RETURN a;
END $$;

/* a desk act made on the state the officer saw */
CREATE FUNCTION admissions.iut_expect(p_state text, p_expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF nullif(btrim(coalesce(p_expected, '')), '') IS NOT NULL AND upper(btrim(p_expected)) <> p_state THEN
        RAISE EXCEPTION 'IUT_STATE_MOVED: the application is now %', p_state USING ERRCODE = '23514',
            HINT = 'Someone acted on it meanwhile; open it again to see where it stands';
    END IF;
END $$;

/* D11: the state as the applicant reads it. The Head of Department's recommendation, its decline and the Registry's approval all read
   WITH_REGISTRY ("with the Registry for a decision"), in the view, its history and the words of a refusal, so nothing of the outcome
   reaches the applicant before another officer decides the transfer (a transfer rejected there leaves it RECOMMENDED, read alike) */
CREATE FUNCTION admissions.iut_state_shown(p_state text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_state IN ('RECOMMENDED', 'NOT_RECOMMENDED', 'APPROVED') THEN 'WITH_REGISTRY' ELSE p_state END;
$$;
COMMENT ON FUNCTION admissions.iut_state_shown(text) IS
  'V766 (D11): a transfer application''s state as its applicant reads it — RECOMMENDED, NOT_RECOMMENDED and APPROVED are WITH_REGISTRY ("with the Registry for a decision"); every other state as it is.';

/* the state in the words of a refusal the applicant reads ("this one is ...") */
CREATE FUNCTION admissions.iut_state_words(p_state text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE admissions.iut_state_shown(p_state)
               WHEN 'DRAFT' THEN 'a draft' WHEN 'CORRECTION_REQUIRED' THEN 'returned to you for a correction' WHEN 'WITH_HOD' THEN 'with the department'
               WHEN 'WITH_REGISTRY' THEN 'with the Registry for a decision' ELSE lower(p_state) END;
$$;

CREATE FUNCTION admissions.iut_log(p_app uuid, p_action text, p_from text, p_to text, p_note text, p_shown boolean, p_transfer uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v uuid;
BEGIN
    -- the public door acts as nobody: the applicant is the actor of their own application
    IF office = 'applicant' AND (who IS NULL OR who = '00000000-0000-0000-0000-000000000000') THEN
        who := (SELECT a.account_id FROM admissions.iut_application a WHERE a.id = p_app);
    END IF;
    INSERT INTO admissions.iut_event (application_id, action, from_state, to_state, note, transfer_id, actor, office, shown_to_applicant)
    VALUES (p_app, p_action, p_from, p_to, nullif(btrim(coalesce(p_note, '')), ''), p_transfer, who, office, coalesce(p_shown, false))
    RETURNING id INTO v;
    RETURN v;
END $$;

/* the applicant told, by e-mail and SMS, on the account's address */
CREATE FUNCTION admissions.iut_tell(p_app uuid, p_key text, p_variant text, p_vars jsonb, p_event_key text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; acc admissions.iut_account; v jsonb;
BEGIN
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN 0; END IF;
    SELECT * INTO acc FROM admissions.iut_account WHERE id = a.account_id;
    v := jsonb_strip_nulls(jsonb_build_object(
            'FIRST_NAME', coalesce(nullif(split_part(btrim(a.other_names), ' ', 1), ''), a.surname),
            'FULL_NAME', a.surname || ', ' || a.other_names,
            'APPLICATION_NUMBER', a.application_no,
            'SESSION', a.session,
            'PROGRAMME', (SELECT p.name FROM ref.programme p WHERE p.code = a.programme_code),
            'LEVEL', a.level::text,
            'JAMB_NUMBER', a.jamb_reg_no)) || jsonb_strip_nulls(coalesce(p_vars, '{}'::jsonb));
    -- e-mail and SMS only: the applicant has no portal inbox (the application's page is their portal view)
    RETURN platform.notify(p_key, p_variant, v, 'iut_application', p_app, acc.email, acc.phone, p_event_key, ARRAY['EMAIL', 'SMS']);
END $$;

/* the department's desk: the Head of the department of the programme applied for, and the Dean where it is in a College (V734) */
CREATE FUNCTION admissions.iut_desk_people(p_app uuid) RETURNS TABLE(person_id uuid, name text, email text, phone text, office text) LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (a.person_id) a.person_id, h.name, h.email, h.phone, a.office_code
      FROM admissions.iut_application ap
     CROSS JOIN LATERAL people.transfer_unit(ap.programme_code) u
      JOIN iam.office_assignment a ON a.office_code = ANY (CASE WHEN u.college_code IS NOT NULL THEN ARRAY['hod', 'dean'] ELSE ARRAY['hod'] END)
      JOIN iam.person pe ON pe.id = a.person_id AND pe.ended_on IS NULL
     CROSS JOIN LATERAL assessment.staff_reach(a.person_id) h
     WHERE ap.id = p_app
       AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND CASE a.office_code
                WHEN 'hod'  THEN upper(iam.acting_department(a.person_id, 'hod')) = upper(u.dept_code)
                WHEN 'dean' THEN u.college_code IS NOT NULL AND upper(iam.acting_faculty(a.person_id, 'dean')) = upper(u.faculty_code)
                ELSE false
           END
     ORDER BY a.person_id, a.office_code;
$$;

CREATE FUNCTION admissions.iut_tell_desk(p_app uuid, p_event uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; u record; r record; n integer := 0;
BEGIN
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN 0; END IF;
    SELECT * INTO u FROM people.transfer_unit(a.programme_code);
    FOR r IN SELECT * FROM admissions.iut_desk_people(p_app) LOOP
        n := n + platform.notify('IUT_DESK', 'WITH_HOD',
                 jsonb_strip_nulls(jsonb_build_object('NAME', r.name, 'APPLICATION_NUMBER', a.application_no, 'APPLICANT', a.surname || ', ' || a.other_names,
                                                      'PROGRAMME', (SELECT p.name FROM ref.programme p WHERE p.code = a.programme_code),
                                                      'LEVEL', a.level::text, 'DEPARTMENT', u.dept_name)),
                 'iut_application', p_app, r.email, r.phone, 'IUT_DESK:' || p_app || ':' || r.person_id || ':' || p_event);
    END LOOP;
    RETURN n;
END $$;

/* the department's officer of the programme applied for: its Head, the College's Dean (V734), or super */
CREATE FUNCTION admissions.iut_hod_of(p_app uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT CASE nullif(current_setting('moaum.actor_office', true), '')
                    WHEN 'super' THEN true
                    WHEN 'hod' THEN upper(iam.acting_department(nullif(current_setting('moaum.actor_id', true), '')::uuid, 'hod')) = upper(u.dept_code)
                    WHEN 'dean' THEN u.college_code IS NOT NULL
                                     AND upper(iam.acting_faculty(nullif(current_setting('moaum.actor_id', true), '')::uuid, 'dean')) = upper(u.faculty_code)
                    ELSE false END
          FROM admissions.iut_application a CROSS JOIN LATERAL people.transfer_unit(a.programme_code) u
         WHERE a.id = p_app), false);
$$;

CREATE FUNCTION admissions.iut_hod_may(p_app uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM admissions.iut_event e WHERE e.application_id = p_app AND e.action = 'SENT_TO_HOD')
       AND admissions.iut_hod_of(p_app);
$$;
COMMENT ON FUNCTION admissions.iut_hod_may(uuid) IS
  'V766: whether the acting officer reads and recommends this application at the department''s desk — it has reached the desk (sent to the Head of Department once), and the officer is the Head of the department of the programme applied for, the Dean of its faculty where that faculty is in a College (V734), or super.';

/* the documents that keep an application from the department or the approval: any current one not accepted; with p_required, also
   any kind required now without an accepted one. The Registry sends to the department with p_required (a kind made required since
   the submission is asked for by returning the application, still possible then); the approval without it — a submitted application
   is never re-gated on a kind made required after it (SPEC §3.3), and by then nothing would let the applicant upload it */
CREATE FUNCTION admissions.iut_unchecked(p_app uuid, p_required boolean DEFAULT true) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT string_agg(x.label, '; ' ORDER BY x.ord, x.label) FROM (
        SELECT DISTINCT k.label, k.ord
          FROM admissions.iut_document d JOIN admissions.iut_document_kind k ON k.code = d.kind
         WHERE d.application_id = p_app AND d.superseded_at IS NULL AND d.status <> 'ACCEPTED'
        UNION
        SELECT k.label, k.ord FROM admissions.iut_document_kind k
         WHERE coalesce(p_required, true) AND k.active AND k.required
           AND NOT EXISTS (SELECT 1 FROM admissions.iut_document d WHERE d.application_id = p_app AND d.kind = k.code AND d.superseded_at IS NULL AND d.status = 'ACCEPTED')) x;
$$;

/* the particulars as the form gives them, checked in the order the form shows them; the first that fails is refused. p_keys
   names the ones checked (NULL: all); 'university' is the code or the name typed, 'otherCgpa' the CGPA with its scale */
CREATE FUNCTION admissions.iut_particulars(p jsonb, p_session text, p_keys text[] DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE o jsonb := '{}'::jsonb; x text; y text; d date; n integer; c numeric; v_code text; v_named text;
        v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date;
BEGIN
    p := coalesce(p, '{}'::jsonb);
    IF p_keys IS NULL OR 'surname' = ANY (p_keys) THEN
        x := regexp_replace(btrim(coalesce(p->>'surname', '')), '\s+', ' ', 'g');
        IF length(x) NOT BETWEEN 2 AND 60 OR x !~ '^[[:alpha:]][[:alpha:] ''-]*$' THEN
            RAISE EXCEPTION 'IUT_NAME: the surname is 2 to 60 letters (spaces, '' and - allowed)' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('surname', upper(x));
    END IF;
    IF p_keys IS NULL OR 'otherNames' = ANY (p_keys) THEN
        x := regexp_replace(btrim(coalesce(p->>'otherNames', '')), '\s+', ' ', 'g');
        IF length(x) NOT BETWEEN 2 AND 120 OR x !~ '^[[:alpha:]][[:alpha:] ''-]*$' THEN
            RAISE EXCEPTION 'IUT_NAME: the other names are 2 to 120 letters (spaces, '' and - allowed)' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('otherNames', x);
    END IF;
    IF p_keys IS NULL OR 'sex' = ANY (p_keys) THEN
        x := upper(btrim(coalesce(p->>'sex', '')));
        x := CASE x WHEN 'MALE' THEN 'M' WHEN 'FEMALE' THEN 'F' ELSE x END;
        IF x NOT IN ('M', 'F') THEN RAISE EXCEPTION 'IUT_SEX: sex is M or F' USING ERRCODE = '23514'; END IF;
        o := o || jsonb_build_object('sex', x);
    END IF;
    IF p_keys IS NULL OR 'dateOfBirth' = ANY (p_keys) THEN
        x := btrim(coalesce(p->>'dateOfBirth', ''));
        d := NULL;
        IF x ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
            BEGIN
                d := to_date(x, 'YYYY-MM-DD');
                IF to_char(d, 'YYYY-MM-DD') <> x THEN d := NULL; END IF;
            EXCEPTION WHEN OTHERS THEN d := NULL;
            END;
        END IF;
        IF d IS NULL THEN
            RAISE EXCEPTION 'IUT_DATE_OF_BIRTH: the date of birth is a real date, written YYYY-MM-DD' USING ERRCODE = '23514';
        END IF;
        n := extract(year FROM age(v_today, d))::int;
        IF d > v_today OR n NOT BETWEEN 14 AND 70 THEN
            RAISE EXCEPTION 'IUT_DATE_OF_BIRTH: an applicant is 14 to 70 years old today (the date of birth makes % years)', greatest(n, 0) USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('dateOfBirth', x);
    END IF;
    IF p_keys IS NULL OR 'email' = ANY (p_keys) THEN
        x := lower(btrim(coalesce(p->>'email', '')));
        IF length(x) > 200 OR x !~ '^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$' THEN
            RAISE EXCEPTION 'IUT_EMAIL: % is not an e-mail address', coalesce(nullif(x, ''), 'the e-mail given') USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('email', x);
    END IF;
    IF p_keys IS NULL OR 'phone' = ANY (p_keys) THEN
        x := people.contact_phone(p->>'phone');
        IF x IS NULL OR x !~ '^0[0-9]{10}$' THEN
            RAISE EXCEPTION 'IUT_PHONE: the phone number is a Nigerian one, 11 digits from 0 (or +234)' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('phone', x);
    END IF;
    IF p_keys IS NULL OR 'jambRegNo' = ANY (p_keys) THEN
        x := upper(regexp_replace(coalesce(p->>'jambRegNo', ''), '\s', '', 'g'));
        IF x !~ '^[0-9]{12}[A-Z]{2,3}$' THEN
            RAISE EXCEPTION 'IUT_JAMB: the JAMB registration number is 12 digits and two or three letters, as on your JAMB admission letter' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('jambRegNo', x);
    END IF;
    IF p_keys IS NULL OR 'university' = ANY (p_keys) THEN
        v_code := nullif(upper(btrim(coalesce(p->>'universityCode', ''))), '');
        v_named := nullif(regexp_replace(btrim(coalesce(p->>'universityNamed', '')), '\s+', ' ', 'g'), '');
        IF v_code IS NOT NULL THEN
            IF NOT EXISTS (SELECT 1 FROM ref.university u WHERE u.code = v_code AND u.active) THEN
                RAISE EXCEPTION 'IUT_UNIVERSITY: % is not a university on the list', v_code USING ERRCODE = '23514',
                    HINT = 'Choose your university from the list, or choose "My university is not on the list" and name it';
            END IF;
            v_named := NULL;   -- chosen from the list: nothing typed is kept beside it
        ELSIF v_named IS NULL OR length(v_named) NOT BETWEEN 3 AND 200 THEN
            RAISE EXCEPTION 'IUT_UNIVERSITY: choose your present university from the list, or name it (3 to 200 characters)' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('universityCode', v_code, 'universityNamed', v_named);
    END IF;
    IF p_keys IS NULL OR 'otherMatricNo' = ANY (p_keys) THEN
        x := upper(regexp_replace(coalesce(p->>'otherMatricNo', ''), '\s', '', 'g'));
        IF x !~ '^[A-Z0-9][A-Z0-9/._-]{0,39}$' THEN
            RAISE EXCEPTION 'IUT_OTHER_MATRIC: the matriculation number at your present university is up to 40 letters, digits and / . - _' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('otherMatricNo', x);
    END IF;
    IF p_keys IS NULL OR 'otherProgramme' = ANY (p_keys) THEN
        x := regexp_replace(btrim(coalesce(p->>'otherProgramme', '')), '\s+', ' ', 'g');
        IF length(x) NOT BETWEEN 3 AND 200 THEN
            RAISE EXCEPTION 'IUT_OTHER_PROGRAMME: name the programme you study at your present university (3 to 200 characters)' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('otherProgramme', x);
    END IF;
    IF p_keys IS NULL OR 'otherLevel' = ANY (p_keys) THEN
        x := btrim(coalesce(p->>'otherLevel', ''));
        IF x !~ '^[1-9]00$' THEN
            RAISE EXCEPTION 'IUT_OTHER_LEVEL: the level at your present university is 100 to 900' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('otherLevel', x::int);
    END IF;
    IF p_keys IS NULL OR 'otherEntrySession' = ANY (p_keys) THEN
        x := btrim(coalesce(p->>'otherEntrySession', ''));
        IF (CASE WHEN x ~ '^[0-9]{4}/[0-9]{4}$' THEN substr(x, 6, 4)::int <> substr(x, 1, 4)::int + 1 ELSE true END) THEN
            RAISE EXCEPTION 'IUT_ENTRY_SESSION: the session you entered your present university is written like 2022/2023' USING ERRCODE = '23514';
        END IF;
        IF p_session IS NOT NULL AND x > p_session THEN
            RAISE EXCEPTION 'IUT_ENTRY_SESSION: the session you entered your present university (%) is after the session you apply for (%)', x, p_session
                USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('otherEntrySession', x);
    END IF;
    IF p_keys IS NULL OR 'otherCgpa' = ANY (p_keys) THEN
        x := btrim(coalesce(p->>'otherCgpa', ''));
        y := btrim(coalesce(p->>'otherCgpaScale', ''));
        IF x !~ '^[0-9](\.[0-9]{1,2})?$' THEN
            RAISE EXCEPTION 'IUT_CGPA: the CGPA is a number with up to two decimals, such as 3.45' USING ERRCODE = '23514';
        END IF;
        IF y !~ '^[45](\.0+)?$' THEN
            RAISE EXCEPTION 'IUT_CGPA: the CGPA is on a 4-point or a 5-point scale' USING ERRCODE = '23514';
        END IF;
        c := x::numeric;
        n := left(y, 1)::int;
        IF c > n THEN
            RAISE EXCEPTION 'IUT_CGPA: a CGPA of % is above the %-point scale', x, n USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('otherCgpa', c, 'otherCgpaScale', n);
    END IF;
    IF p_keys IS NULL OR 'reason' = ANY (p_keys) THEN
        x := btrim(coalesce(p->>'reason', ''));
        IF length(x) NOT BETWEEN 20 AND 2000 THEN
            RAISE EXCEPTION 'IUT_REASON: say why you want to transfer, in 20 to 2000 characters' USING ERRCODE = '23514';
        END IF;
        o := o || jsonb_build_object('reason', x);
    END IF;
    RETURN o;
END $$;
COMMENT ON FUNCTION admissions.iut_particulars(jsonb, text, text[]) IS
  'V766: an inter-university transfer applicant''s particulars checked and written as kept (the surname in capitals, the numbers in capitals without spaces, the phone from 0, the e-mail in lower case), in the order the form shows them; the first that fails is refused with its code.';

/* the words of a programme and level not taking transfers */
CREATE FUNCTION admissions.iut_line_words(p_session text, p_programme text, p_level integer) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.name FROM ref.programme p WHERE p.code = p_programme), nullif(p_programme, ''), 'The programme chosen')
           || ' at ' || coalesce(p_level::text || ' Level', 'the level chosen') || ' is not taking transfer students in ' || coalesce(p_session, 'this session');
$$;

/* the database's second wall behind the functions at the public door, as policy.application_window_guard is for the other doors: an
   applicant makes an application, or changes its programme and level, only while the window is open and on a line taking them */
CREATE FUNCTION admissions.iut_application_window_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(nullif(current_setting('moaum.actor_office', true), ''), '-') <> 'applicant' THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND NEW.programme_code IS NOT DISTINCT FROM OLD.programme_code AND NEW.level IS NOT DISTINCT FROM OLD.level
       AND NEW.session IS NOT DISTINCT FROM OLD.session THEN
        RETURN NEW;
    END IF;
    IF admissions.iut_window_status(NEW.session) <> 'OPEN' THEN
        RAISE EXCEPTION 'IUT_WINDOW_CLOSED: inter-university transfer applications are not open' USING ERRCODE = '23514',
            HINT = admissions.iut_closed_hint(NEW.session);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM admissions.iut_line l
                    WHERE l.session = NEW.session AND l.programme_code = NEW.programme_code AND l.level = NEW.level AND l.accepting
                      AND admissions.iut_line_offered(l.programme_code, l.level)) THEN
        RAISE EXCEPTION 'IUT_PROGRAMME_NOT_OPEN: %', admissions.iut_line_words(NEW.session, NEW.programme_code, NEW.level) USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_iut_application_window BEFORE INSERT OR UPDATE OF programme_code, level, session ON admissions.iut_application
    FOR EACH ROW EXECUTE FUNCTION admissions.iut_application_window_guard();

-- ── 5 · what the desks, the applicant and the public read ────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.iut_window_view(p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'session', p_session,
        'state', w.state,
        'status', admissions.iut_window_status(p_session),
        'opensOn', w.opens_on, 'closesOn', w.closes_on,
        'message', w.closed_message, 'note', w.note,
        'setByName', people.officer_name(w.set_by), 'setOffice', w.set_office, 'setAt', w.set_at,
        'fee', jsonb_build_object('amount', f.amount, 'state', f.state, 'published', coalesce(f.state = 'PUBLISHED', false), 'draftAmount', f.draft_amount),
        -- the lines the public is offered: taking applications, on a programme in use at one of its levels (a line whose programme was
        -- archived, or shortened past its level, offers nothing; levelInUse says which)
        'offered', (SELECT count(*) FROM admissions.iut_line l WHERE l.session = p_session AND l.accepting AND admissions.iut_line_offered(l.programme_code, l.level)),
        'lines', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                       'programme', l.programme_code, 'programmeName', p.name, 'dept', u.dept_code, 'deptName', u.dept_name,
                       'faculty', u.faculty_code, 'facultyName', u.faculty_name, 'level', l.level, 'places', l.places, 'accepting', l.accepting,
                       'programmeInUse', admissions.iut_programme_in_use(l.programme_code),
                       'levelInUse', coalesce(l.level = ANY (people.programme_levels(l.programme_code)), false),
                       'offered', l.accepting AND admissions.iut_line_offered(l.programme_code, l.level),
                       'applications', (SELECT count(*) FROM admissions.iut_application a
                                         WHERE a.session = l.session AND a.programme_code = l.programme_code AND a.level = l.level),
                       'approved', (SELECT count(*) FROM admissions.iut_application a
                                     WHERE a.session = l.session AND a.programme_code = l.programme_code AND a.hod_level = l.level AND a.state = 'APPROVED'),
                       'admitted', (SELECT count(*) FROM admissions.iut_application a
                                     WHERE a.session = l.session AND a.programme_code = l.programme_code AND a.hod_level = l.level AND a.state = 'ADMITTED'))
                   ORDER BY p.name, l.level)
              FROM admissions.iut_line l JOIN ref.programme p ON p.code = l.programme_code
             CROSS JOIN LATERAL people.transfer_unit(l.programme_code) u
             WHERE l.session = p_session), '[]'::jsonb),
        'counts', CASE WHEN w.session IS NULL THEN '{}'::jsonb ELSE (
            SELECT jsonb_object_agg(s.st, coalesce(c.n, 0))
              FROM unnest(ARRAY['DRAFT', 'SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD', 'RECOMMENDED', 'NOT_RECOMMENDED', 'APPROVED', 'ADMITTED',
                                'REJECTED', 'WITHDRAWN']) s(st)
              LEFT JOIN (SELECT a.state, count(*) AS n FROM admissions.iut_application a WHERE a.session = p_session GROUP BY a.state) c ON c.state = s.st) END)
      FROM (SELECT 1) one
      LEFT JOIN admissions.iut_window w ON w.session = p_session
      LEFT JOIN finance.iut_fee f ON f.session = p_session;
$$;

CREATE FUNCTION admissions.iut_document_kinds() RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT coalesce(jsonb_agg(jsonb_build_object('code', k.code, 'label', k.label, 'hint', k.hint, 'required', k.required, 'imagesAllowed', k.images_allowed,
                                                 'transferCode', k.transfer_code, 'ord', k.ord, 'active', k.active) ORDER BY k.ord, k.code), '[]'::jsonb)
      FROM admissions.iut_document_kind k;
$$;

/* the public's view: nothing personal; the programmes only while the window is open; never the places */
CREATE FUNCTION admissions.iut_public(p_session text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_session text; v_status text; v_fee numeric; w admissions.iut_window;
BEGIN
    v_session := coalesce(nullif(btrim(coalesce(p_session, '')), ''), admissions.iut_open_session(),
                          (SELECT x.session FROM admissions.iut_window x WHERE x.state = 'OPEN' ORDER BY x.session DESC LIMIT 1));
    SELECT * INTO w FROM admissions.iut_window WHERE session = v_session;
    v_status := admissions.iut_window_status(v_session);
    v_fee := finance.iut_fee_for(v_session);
    RETURN jsonb_build_object(
        'session', v_session,
        'window', jsonb_build_object('status', v_status, 'opensOn', w.opens_on, 'closesOn', w.closes_on,
                                     'message', CASE WHEN v_status = 'OPEN' THEN NULL
                                                     WHEN w.session IS NOT NULL THEN nullif(btrim(w.closed_message), '')
                                                     ELSE (SELECT nullif(btrim(x.closed_message), '') FROM admissions.iut_window x
                                                            WHERE nullif(btrim(x.closed_message), '') IS NOT NULL ORDER BY x.session DESC LIMIT 1) END),
        'fee', jsonb_build_object('amount', v_fee, 'published', v_fee IS NOT NULL),
        'programmes', CASE WHEN v_status <> 'OPEN' THEN '[]'::jsonb ELSE coalesce((
            SELECT jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'dept', u.dept_code, 'deptName', u.dept_name,
                                                'faculty', u.faculty_code, 'facultyName', u.faculty_name, 'levels', to_jsonb(x.levels))
                             ORDER BY u.faculty_name, u.dept_name, p.name)
              FROM (SELECT l.programme_code, array_agg(l.level ORDER BY l.level) AS levels FROM admissions.iut_line l
                     WHERE l.session = v_session AND l.accepting AND admissions.iut_line_offered(l.programme_code, l.level) GROUP BY l.programme_code) x
              JOIN ref.programme p ON p.code = x.programme_code
             CROSS JOIN LATERAL people.transfer_unit(p.code) u), '[]'::jsonb) END,
        'universities', coalesce((SELECT jsonb_agg(jsonb_build_object('code', u.code, 'name', u.name, 'country', u.country) ORDER BY u.name)
                                    FROM ref.university u WHERE u.active), '[]'::jsonb),
        'documents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', k.code, 'label', k.label, 'hint', k.hint, 'required', k.required,
                                                                   'imagesAllowed', k.images_allowed) ORDER BY k.ord, k.code)
                                 FROM admissions.iut_document_kind k WHERE k.active), '[]'::jsonb),
        'maxDocumentBytes', 5242880);
END $$;
COMMENT ON FUNCTION admissions.iut_public(text) IS
  'V766: what the public link and the University''s website read — the session (asked, else the open window''s, else the latest window opened but not open today), the window''s status and dates (CLOSED when it offers no programme and level in use), its message while it is not open, the published fee, the programmes and levels taking transfers (only while open, on programmes in use at their own levels; never the places), the universities on the list and the documents asked for. Nothing personal.';

CREATE FUNCTION admissions.iut_view(p_app uuid, p_for text) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE a admissions.iut_application; acc admissions.iut_account; v_for text := upper(coalesce(p_for, 'OFFICE')); u record; pr ref.programme;
        out jsonb; v_hist jsonb; v_docs jsonb; v_notice jsonb; t record; s people.student;
BEGIN
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app;
    IF a.id IS NULL THEN RETURN NULL; END IF;
    IF v_for NOT IN ('APPLICANT', 'OFFICE', 'HOD') THEN v_for := 'APPLICANT'; END IF;
    SELECT * INTO acc FROM admissions.iut_account WHERE id = a.account_id;
    SELECT * INTO pr FROM ref.programme WHERE code = a.programme_code;
    SELECT * INTO u FROM people.transfer_unit(a.programme_code);

    out := jsonb_build_object(
        'id', a.id, 'applicationNo', a.application_no, 'session', a.session,
        -- D11: the applicant reads WITH_REGISTRY for a recommendation, a decline and an approval, and the time of the last step shown
        -- to them (the row's own time moves with every desk act)
        'state', CASE WHEN v_for = 'APPLICANT' THEN admissions.iut_state_shown(a.state) ELSE a.state END,
        'windowStatus', admissions.iut_window_status(a.session),
        'createdAt', a.created_at,
        'updatedAt', CASE WHEN v_for = 'APPLICANT'
                          THEN coalesce((SELECT max(e.at) FROM admissions.iut_event e WHERE e.application_id = a.id AND e.shown_to_applicant), a.created_at)
                          ELSE a.updated_at END,
        'applicant', jsonb_build_object('surname', a.surname, 'otherNames', a.other_names, 'sex', a.sex, 'dateOfBirth', to_char(a.date_of_birth, 'YYYY-MM-DD'),
                                        'jambRegNo', a.jamb_reg_no)
                     || CASE WHEN v_for = 'HOD' THEN '{}'::jsonb ELSE jsonb_build_object('email', acc.email, 'phone', acc.phone) END,
        'previous', jsonb_build_object('universityCode', a.university_code, 'universityName', (SELECT x.name FROM ref.university x WHERE x.code = a.university_code),
                                       'universityNamed', a.university_named, 'matricNo', a.other_matric_no, 'programme', a.other_programme,
                                       'level', a.other_level, 'entrySession', a.other_entry_session, 'cgpa', a.other_cgpa, 'cgpaScale', a.other_cgpa_scale),
        'applied', jsonb_build_object('programme', a.programme_code, 'programmeName', pr.name, 'dept', u.dept_code, 'deptName', u.dept_name,
                                      'faculty', u.faculty_code, 'facultyName', u.faculty_name, 'college', u.college_code, 'collegeName', u.college_name,
                                      'level', a.level,
                                      -- the levels the Head of Department may recommend at: the window's lines of the programme
                                      -- (taking applications or not) at a level the programme still has (iut_recommend's own test)
                                      'levelsOpen', coalesce((SELECT jsonb_agg(l.level ORDER BY l.level) FROM admissions.iut_line l
                                                               WHERE l.session = a.session AND l.programme_code = a.programme_code
                                                                 AND l.level = ANY (people.programme_levels(a.programme_code))), '[]'::jsonb)),
        'reason', a.reason,
        -- a kind no longer asked for is listed while a current document holds it, marked so (no upload of it is taken)
        'kinds', coalesce((SELECT jsonb_agg(jsonb_build_object('code', k.code, 'label', k.label, 'hint', k.hint, 'required', k.required,
                                                              'imagesAllowed', k.images_allowed, 'active', k.active) ORDER BY k.ord, k.code)
                             FROM admissions.iut_document_kind k
                            WHERE k.active OR EXISTS (SELECT 1 FROM admissions.iut_document d WHERE d.application_id = a.id AND d.kind = k.code AND d.superseded_at IS NULL)),
                          '[]'::jsonb),
        'submittedAt', a.submitted_at, 'lastSubmittedAt', a.last_submitted_at, 'withdrawnAt', a.withdrawn_at);

    -- a rejected document's note is the Registry's words to the applicant: the applicant's and the office's, never the department's;
    -- an accepted one's is the Registry's word on the paper, read by the desks
    v_docs := coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'label', k.label, 'required', k.required, 'filename', d.filename,
                                                            'contentType', d.content_type, 'bytes', d.bytes, 'uploadedAt', d.uploaded_at, 'status', d.status,
                                                            'note', CASE WHEN v_for = 'OFFICE' OR (v_for = 'APPLICANT') = (d.status = 'REJECTED') THEN d.review_note END,
                                                            'reviewedAt', d.reviewed_at) ORDER BY k.ord, d.kind)
                          FROM admissions.iut_document d JOIN admissions.iut_document_kind k ON k.code = d.kind
                         WHERE d.application_id = a.id AND d.superseded_at IS NULL), '[]'::jsonb);
    out := out || jsonb_build_object('documents', v_docs);

    -- the notice is the Registry's words to the applicant (a return, a rejection): not the department's to read
    v_notice := CASE WHEN v_for <> 'HOD' THEN CASE a.state
        WHEN 'CORRECTION_REQUIRED' THEN jsonb_build_object('kind', 'CORRECTION',
                    'note', (SELECT e.note FROM admissions.iut_event e WHERE e.application_id = a.id AND e.action = 'RETURNED' ORDER BY e.at DESC LIMIT 1))
        WHEN 'REJECTED' THEN jsonb_build_object('kind', 'REJECTED', 'note', a.registry_note) END END;
    out := out || jsonb_build_object('notice', v_notice);

    IF v_for <> 'HOD' THEN
        -- due: only a draft pays; a draft withdrawn or ended owes nothing (a payment that comes after is owed back). refunded: what the
        -- refund desk gave back on a payment (approved or paid, at most the amount), as the Bursary's report counts it, so neither the
        -- applicant nor the Registry reads a payment given back as still owed
        out := out || jsonb_build_object('fee', jsonb_build_object(
            'settled', a.fee_settled_at IS NOT NULL, 'basis', a.fee_basis, 'settledAt', a.fee_settled_at,
            'due', CASE WHEN a.fee_settled_at IS NULL AND a.state = 'DRAFT' THEN finance.iut_fee_for(a.session) END,
            'references', coalesce((SELECT jsonb_agg(jsonb_build_object('reference', f.reference, 'amount', f.amount, 'expiresAt', f.expires_at,
                                                                        'confirmedAt', f.confirmed_at, 'receiptNo', f.receipt_no, 'channel', f.channel,
                                                                        'settles', f.settles,
                                                                        'refunded', CASE WHEN f.confirmed_at IS NOT NULL THEN least(f.amount, finance.gst_refunded(f.reference)) END)
                                                     ORDER BY f.created_at DESC)
                                      FROM admissions.iut_fee_reference f WHERE f.application_id = a.id), '[]'::jsonb)));
    END IF;

    IF v_for <> 'APPLICANT' THEN
        out := out || jsonb_build_object(
            'superseded', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'label', k.label, 'filename', d.filename, 'uploadedAt', d.uploaded_at,
                                                                        'status', d.status,
                                                                        'note', CASE WHEN v_for = 'OFFICE' OR d.status <> 'REJECTED' THEN d.review_note END,
                                                                        'supersededAt', d.superseded_at)
                                                     ORDER BY d.superseded_at DESC)
                                      FROM admissions.iut_document d JOIN admissions.iut_document_kind k ON k.code = d.kind
                                     WHERE d.application_id = a.id AND d.superseded_at IS NOT NULL), '[]'::jsonb),
            'hod', CASE WHEN a.hod_decision IS NOT NULL THEN
                       jsonb_build_object('decision', a.hod_decision, 'level', a.hod_level, 'note', a.hod_note, 'byName', people.officer_name(a.hod_by),
                                          'office', a.hod_office, 'at', a.hod_at) END);
    END IF;

    IF v_for = 'OFFICE' THEN
        out := out || jsonb_build_object('registry', CASE WHEN a.registry_at IS NOT NULL OR a.approval_ref IS NOT NULL THEN
                          jsonb_build_object('note', a.registry_note, 'byName', people.officer_name(a.registry_by), 'office', a.registry_office,
                                             'at', a.registry_at, 'approvalRef', a.approval_ref) END);
        IF a.transfer_id IS NOT NULL THEN
            SELECT tr.id, tr.batch_id, b.ref, tr.status, tr.prepared_by INTO t
              FROM people.university_transfer tr JOIN people.university_transfer_batch b ON b.id = tr.batch_id WHERE tr.id = a.transfer_id;
            out := out || jsonb_build_object('transfer', jsonb_build_object('id', t.id, 'batchId', t.batch_id, 'batchRef', t.ref, 'status', t.status,
                                                                            'preparedBy', t.prepared_by, 'preparedByName', people.officer_name(t.prepared_by)));
        ELSE
            out := out || jsonb_build_object('transfer', NULL);
        END IF;
    END IF;

    -- the level admitted at: the Head of Department's, the transfer's own (SPEC §6 "Admitted to <programme>, <level> Level").
    -- portalOpened: the student door has been used once (iam.student_account): the application's password was carried over at that
    -- first sign-in (D18), and from then on the student portal keeps its own, so a change here no longer reaches it
    IF a.student_id IS NOT NULL AND (v_for <> 'APPLICANT' OR a.state = 'ADMITTED') THEN
        SELECT * INTO s FROM people.student WHERE id = a.student_id;
        out := out || jsonb_build_object('student', jsonb_build_object('id', s.id, 'admissionNo', s.admission_no, 'matricNo', s.matric_no,
                                                                       'level', coalesce(a.hod_level, s.entry_level),
                                                                       'portalOpened', EXISTS (SELECT 1 FROM iam.student_account sa WHERE sa.student_id = s.id)));
    END IF;

    -- the applicant: the steps shown to them, nameless, the states as they read them (D11), without the Registry's note sent with the
    -- application to the department (written for the Head of Department); the department: no fee step, no transfer and none of the
    -- Registry's own words in the history either (the HOD view leaves out fee, transfer and registry) — the notes of a return, a
    -- rejection or a document rejected (written for the applicant: the document's name is kept), of the approval, of the deciding
    -- officer's rejection and of the university set are left out; the Registry's notes to the department (sent to it, sent back to
    -- it) stay, being written for it
    v_hist := coalesce((SELECT jsonb_agg(CASE WHEN v_for = 'APPLICANT'
                                              THEN jsonb_build_object('at', e.at, 'action', e.action, 'fromState', admissions.iut_state_shown(e.from_state),
                                                                      'toState', admissions.iut_state_shown(e.to_state),
                                                                      'note', CASE WHEN e.action = 'SENT_TO_HOD' THEN NULL ELSE e.note END)
                                              WHEN v_for = 'HOD'
                                              THEN jsonb_build_object('at', e.at, 'action', e.action, 'fromState', e.from_state, 'toState', e.to_state,
                                                                      'note', CASE WHEN e.action IN ('RETURNED', 'REJECTED', 'APPROVED', 'TRANSFER_REJECTED', 'UNIVERSITY_SET')
                                                                                   THEN NULL
                                                                                   -- "<label>: <note>" read as the label alone
                                                                                   WHEN e.action = 'DOCUMENT_REJECTED'
                                                                                   THEN (SELECT k.label FROM admissions.iut_document_kind k
                                                                                          WHERE e.note = k.label OR left(e.note, length(k.label) + 2) = k.label || ': '
                                                                                          ORDER BY length(k.label) DESC LIMIT 1)
                                                                                   ELSE e.note END,
                                                                      'byName', coalesce(people.officer_name(e.actor), CASE WHEN e.office = 'applicant' THEN 'The applicant' END),
                                                                      'office', e.office)
                                              ELSE jsonb_build_object('at', e.at, 'action', e.action, 'fromState', e.from_state, 'toState', e.to_state, 'note', e.note,
                                                                      'byName', coalesce(people.officer_name(e.actor), CASE WHEN e.office = 'applicant' THEN 'The applicant' END),
                                                                      'office', e.office, 'transferId', e.transfer_id) END
                                         ORDER BY e.at, e.id)
                          FROM admissions.iut_event e
                         WHERE e.application_id = a.id AND (v_for <> 'APPLICANT' OR e.shown_to_applicant)
                           AND (v_for <> 'HOD' OR e.action NOT IN ('FEE_NONE_DUE', 'FEE_PAID', 'FEE_PAID_AGAIN'))), '[]'::jsonb);
    RETURN out || jsonb_build_object('history', v_hist);
END $$;
COMMENT ON FUNCTION admissions.iut_view(uuid, text) IS
  'V766: an inter-university transfer application as APPLICANT (no Head of Department, Registry, transfer or superseded documents; RECOMMENDED, NOT_RECOMMENDED and APPROVED read WITH_REGISTRY, in the history too, and updatedAt is the last step shown to them (D11); the history shown to them, nameless, without the Registry''s note sent to the department; a document''s note only when rejected; the fee due only while a draft, and what the refund desk gave back on each payment; the student once admitted, with the level admitted at and whether the student portal has been opened (its own password from then on)), HOD (no contact, fee, transfer, Registry or notice — nor the fee''s steps, the transfer or the Registry''s words to the applicant or the record: the notes of a return, a rejection, a document rejected (its name kept, in the history, the documents and those replaced), the approval, the deciding officer''s rejection and the university set; its notes to the department stay) or OFFICE (everything) reads it.';

CREATE FUNCTION admissions.iut_applications(p_session text, p_state text, p_faculty text, p_dept text, p_programme text, p_q text,
                                            p_department_desk boolean, p_college_only boolean, p_limit integer, p_offset integer)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH base AS (
        SELECT a.*, u.dept_code AS u_dept, u.dept_name AS u_dept_name, u.faculty_code AS u_faculty, u.college_code AS u_college, p.name AS programme_name,
               (SELECT x.name FROM ref.university x WHERE x.code = a.university_code) AS university_name
          FROM admissions.iut_application a
          JOIN ref.programme p ON p.code = a.programme_code
         CROSS JOIN LATERAL people.transfer_unit(a.programme_code) u
         WHERE (p_session IS NULL OR a.session = p_session)
           AND (p_faculty IS NULL OR upper(u.faculty_code) = upper(p_faculty))
           AND (p_dept IS NULL OR upper(u.dept_code) = upper(p_dept))
           AND (p_programme IS NULL OR a.programme_code = upper(btrim(p_programme)))
           AND (NOT coalesce(p_department_desk, false) OR EXISTS (SELECT 1 FROM admissions.iut_event e WHERE e.application_id = a.id AND e.action = 'SENT_TO_HOD'))
           AND (NOT coalesce(p_college_only, false) OR u.college_code IS NOT NULL)
           AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL
                OR a.application_no ILIKE '%' || btrim(p_q) || '%' OR a.jamb_reg_no ILIKE '%' || btrim(p_q) || '%'
                OR (a.surname || ' ' || a.other_names) ILIKE '%' || btrim(p_q) || '%' OR (a.other_names || ' ' || a.surname) ILIKE '%' || btrim(p_q) || '%'
                OR a.other_matric_no ILIKE '%' || btrim(p_q) || '%' OR coalesce(a.university_code, '') ILIKE '%' || btrim(p_q) || '%'
                OR coalesce(a.university_named, '') ILIKE '%' || btrim(p_q) || '%'
                OR coalesce((SELECT x.name FROM ref.university x WHERE x.code = a.university_code), '') ILIKE '%' || btrim(p_q) || '%')),
    listed AS (SELECT * FROM base b WHERE p_state IS NULL OR b.state = upper(btrim(p_state)))
    SELECT jsonb_build_object(
        'total', (SELECT count(*) FROM listed),
        'counts', (SELECT jsonb_object_agg(s.st, coalesce(c.n, 0))
                     FROM unnest(ARRAY['DRAFT', 'SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD', 'RECOMMENDED', 'NOT_RECOMMENDED', 'APPROVED', 'ADMITTED',
                                       'REJECTED', 'WITHDRAWN']) s(st)
                     LEFT JOIN (SELECT b.state, count(*) AS n FROM base b GROUP BY b.state) c ON c.state = s.st),
        'rows', coalesce((SELECT jsonb_agg(jsonb_build_object(
                    'id', l.id, 'applicationNo', l.application_no, 'session', l.session, 'state', l.state, 'surname', l.surname, 'otherNames', l.other_names,
                    'jambRegNo', l.jamb_reg_no, 'universityCode', l.university_code, 'universityName', l.university_name, 'universityNamed', l.university_named,
                    'programme', l.programme_code, 'programmeName', l.programme_name, 'dept', l.u_dept, 'deptName', l.u_dept_name, 'level', l.level,
                    'hodLevel', l.hod_level, 'cgpa', l.other_cgpa, 'cgpaScale', l.other_cgpa_scale, 'submittedAt', l.submitted_at, 'updatedAt', l.updated_at,
                    'feeSettled', l.fee_settled_at IS NOT NULL,
                    'documents', (SELECT jsonb_build_object('pending', count(*) FILTER (WHERE d.status = 'PENDING'),
                                                            'accepted', count(*) FILTER (WHERE d.status = 'ACCEPTED'),
                                                            'rejected', count(*) FILTER (WHERE d.status = 'REJECTED'))
                                    FROM admissions.iut_document d WHERE d.application_id = l.id AND d.superseded_at IS NULL)) ORDER BY l.updated_at DESC, l.application_no)
                            FROM (SELECT * FROM listed ORDER BY updated_at DESC, application_no
                                   LIMIT greatest(1, least(coalesce(p_limit, 50), 500)) OFFSET greatest(coalesce(p_offset, 0), 0)) l), '[]'::jsonb));
$$;
COMMENT ON FUNCTION admissions.iut_applications(text, text, text, text, text, text, boolean, boolean, integer, integer) IS
  'V766: the transfer applications a desk lists — by session, state, faculty, department and programme; the department''s desk only those sent to the Head of Department, the Dean''s only departments of a College; searched by the application and JAMB numbers, the name, the matriculation number at the other university and the university. counts: by state, on the same filters but the state.';

-- ── 6 · the Academic Office's acts: the window, its programmes and levels, the documents asked for ────────────────────────
CREATE FUNCTION admissions.iut_set_window(p_session text, p_state text, p_opens date, p_closes date, p_message text, p_note text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_state text := upper(btrim(coalesce(p_state, ''))); v_msg text := nullif(btrim(coalesce(p_message, '')), ''); v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    PERFORM admissions.iut_office();
    PERFORM admissions.iut_session_ok(p_session);
    -- held while the lines are counted: a line closed at the same moment waits (admissions.iut_lines_left)
    PERFORM 1 FROM admissions.iut_window w WHERE w.session = p_session FOR UPDATE;
    IF v_state NOT IN ('DRAFT', 'OPEN', 'CLOSED') THEN
        RAISE EXCEPTION 'IUT_WINDOW_STATE: a transfer window is DRAFT, OPEN or CLOSED' USING ERRCODE = '23514';
    END IF;
    IF v_state = 'OPEN' THEN
        IF p_opens IS NULL OR p_closes IS NULL THEN
            RAISE EXCEPTION 'IUT_WINDOW_DATES: an open window has its opening and closing dates' USING ERRCODE = '23514', HINT = 'Give the opening and closing dates';
        END IF;
        -- a line on a programme archived or merged away since, or shortened past its level, offers the public nothing, and opens nothing
        IF NOT EXISTS (SELECT 1 FROM admissions.iut_line l WHERE l.session = p_session AND l.accepting AND admissions.iut_line_offered(l.programme_code, l.level)) THEN
            RAISE EXCEPTION 'IUT_WINDOW_NO_PROGRAMMES: the window opens with at least one programme and level taking transfer students' USING ERRCODE = '23514',
                HINT = 'Add the programmes and levels that take transfer students first (a programme archived since its line was added, or a level it no longer has, takes none)';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM finance.iut_fee f WHERE f.session = p_session AND f.state = 'PUBLISHED') THEN
            RAISE EXCEPTION 'IUT_WINDOW_FEE_UNPUBLISHED: the application fee for % is not published', p_session USING ERRCODE = '23514',
                HINT = 'The Bursar states and publishes the session''s application fee on Fee Setup; a fee of nothing is published too';
        END IF;
    END IF;
    IF p_opens IS NOT NULL AND p_closes IS NOT NULL AND p_closes < p_opens THEN
        RAISE EXCEPTION 'IUT_WINDOW_DATES: the closing date (%) is before the opening date (%)', p_closes, p_opens USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(v_msg, '')) > 2000 THEN
        RAISE EXCEPTION 'IUT_WINDOW_MESSAGE: the message the public reads is at most 2000 characters' USING ERRCODE = '23514';
    END IF;
    IF v_state = 'DRAFT' AND EXISTS (SELECT 1 FROM admissions.iut_application a WHERE a.session = p_session) THEN
        RAISE EXCEPTION 'IUT_WINDOW_IN_USE: applications are made in this window; it is closed, not returned to draft' USING ERRCODE = '23514',
            HINT = 'Close the window instead';
    END IF;
    -- closing leaves every reference drawn payable (D5): a started application still pays, uploads and submits
    INSERT INTO admissions.iut_window (session, state, opens_on, closes_on, closed_message, note, set_by, set_office, set_at)
    VALUES (p_session, v_state, p_opens, p_closes, v_msg, v_note, who, office, now())
    ON CONFLICT (session) DO UPDATE
       SET state = EXCLUDED.state, opens_on = EXCLUDED.opens_on, closes_on = EXCLUDED.closes_on, closed_message = EXCLUDED.closed_message,
           note = EXCLUDED.note, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office, set_at = EXCLUDED.set_at;
    RETURN admissions.iut_window_view(p_session);
END $$;

CREATE FUNCTION admissions.iut_add_lines(p_session text, p_programme text, p_levels integer[], p_places integer) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_prog text := upper(btrim(coalesce(p_programme, '')));
BEGIN
    PERFORM admissions.iut_office();
    PERFORM admissions.iut_session_ok(p_session);
    IF NOT EXISTS (SELECT 1 FROM unnest(coalesce(p_levels, '{}'::integer[])) lv WHERE lv IS NOT NULL) THEN
        RAISE EXCEPTION 'IUT_LEVEL: choose at least one level' USING ERRCODE = '23514';
    END IF;
    IF p_places IS NOT NULL AND p_places < 1 THEN
        RAISE EXCEPTION 'IUT_PLACES: places are 1 or more, or none for no limit' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.iut_window (session, set_by, set_office) VALUES (p_session, who, office) ON CONFLICT (session) DO NOTHING;
    -- a line already there is left as it is; the guard refuses a programme not in use and a level not its own
    INSERT INTO admissions.iut_line (session, programme_code, level, places, added_by, added_office)
    SELECT DISTINCT p_session, v_prog, lv, p_places, who, office FROM unnest(p_levels) lv WHERE lv IS NOT NULL
    ON CONFLICT (session, programme_code, level) DO NOTHING;
    RETURN admissions.iut_window_view(p_session);
END $$;

/* D4 kept while the window is open: its last programme and level offered to the public is not closed or removed, or the public
   link, the sign-in page and the website would announce an open window offering nothing (the window is closed instead). Only the
   lines the public is offered count (taking applications, on a programme in use at one of its levels, as admissions.iut_public lists
   them): a line whose programme was archived or merged away, or shortened past its level, since offers nothing, so it closes or goes
   freely and never stands in for the last one. The caller holds the window's row; p_closing: the line at hand stops taking applications */
CREATE FUNCTION admissions.iut_lines_left(p_session text, p_programme text, p_level integer, p_closing boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF coalesce(p_closing, false)
       AND EXISTS (SELECT 1 FROM admissions.iut_window w WHERE w.session = p_session AND w.state = 'OPEN')
       AND admissions.iut_line_offered(p_programme, p_level)
       AND NOT EXISTS (SELECT 1 FROM admissions.iut_line l WHERE l.session = p_session AND l.accepting AND admissions.iut_line_offered(l.programme_code, l.level)
                          AND (l.programme_code, l.level) IS DISTINCT FROM (p_programme, p_level)) THEN
        RAISE EXCEPTION 'IUT_WINDOW_NO_PROGRAMMES: the window is open and this is its last programme and level taking transfer students' USING ERRCODE = '23514',
            HINT = 'Close the window instead, or open another programme and level first';
    END IF;
END $$;

CREATE FUNCTION admissions.iut_set_line(p_session text, p_programme text, p_level integer, p_places integer, p_accepting boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_prog text := upper(btrim(coalesce(p_programme, ''))); l admissions.iut_line; n integer;
BEGIN
    PERFORM admissions.iut_office();
    -- the window first (as iut_remove_line): two officers closing its last two lines at once are taken one after the other
    PERFORM 1 FROM admissions.iut_window w WHERE w.session = p_session FOR UPDATE;
    SELECT * INTO l FROM admissions.iut_line WHERE session = p_session AND programme_code = v_prog AND level = p_level FOR UPDATE;
    IF l.session IS NULL THEN
        RAISE EXCEPTION 'IUT_LINE_UNKNOWN: % does not take transfer students in % at % Level', v_prog, coalesce(p_session, '(no session)'), p_level USING ERRCODE = '23514';
    END IF;
    IF p_places IS NOT NULL AND p_places < 1 THEN
        RAISE EXCEPTION 'IUT_PLACES: places are 1 or more, or none for no limit' USING ERRCODE = '23514';
    END IF;
    PERFORM admissions.iut_lines_left(l.session, l.programme_code, l.level, NOT coalesce(p_accepting, l.accepting) AND l.accepting);
    n := (SELECT count(*) FROM admissions.iut_application a
           WHERE a.session = l.session AND a.programme_code = l.programme_code AND a.hod_level = l.level AND a.state IN ('APPROVED', 'ADMITTED'));
    IF p_places IS NOT NULL AND p_places < n THEN
        RAISE EXCEPTION 'IUT_PLACES: % already approved on this line', n USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.iut_line SET places = p_places, accepting = coalesce(p_accepting, accepting), changed_by = who, changed_office = office, changed_at = now()
     WHERE session = l.session AND programme_code = l.programme_code AND level = l.level;
    RETURN admissions.iut_window_view(p_session);
END $$;

CREATE FUNCTION admissions.iut_remove_line(p_session text, p_programme text, p_level integer) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_prog text := upper(btrim(coalesce(p_programme, ''))); l admissions.iut_line;
BEGIN
    PERFORM admissions.iut_office();
    PERFORM 1 FROM admissions.iut_window w WHERE w.session = p_session FOR UPDATE;
    SELECT * INTO l FROM admissions.iut_line x WHERE x.session = p_session AND x.programme_code = v_prog AND x.level = p_level FOR UPDATE;
    IF l.session IS NULL THEN
        RAISE EXCEPTION 'IUT_LINE_UNKNOWN: % does not take transfer students in % at % Level', v_prog, coalesce(p_session, '(no session)'), p_level USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM admissions.iut_application a WHERE a.session = p_session AND a.programme_code = v_prog AND (a.level = p_level OR a.hod_level = p_level)) THEN
        RAISE EXCEPTION 'IUT_LINE_IN_USE: applications are made on this programme and level' USING ERRCODE = '23514', HINT = 'Close it to new applications instead';
    END IF;
    PERFORM admissions.iut_lines_left(l.session, l.programme_code, l.level, l.accepting);
    DELETE FROM admissions.iut_line WHERE session = p_session AND programme_code = v_prog AND level = p_level;
    RETURN admissions.iut_window_view(p_session);
END $$;

CREATE FUNCTION admissions.iut_save_document_kind(p_code text, p_label text, p_hint text, p_required boolean, p_images_allowed boolean, p_ord integer, p_active boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_code text := upper(btrim(coalesce(p_code, ''))); v_label text := nullif(regexp_replace(btrim(coalesce(p_label, '')), '\s+', ' ', 'g'), '');
        k admissions.iut_document_kind; v_hint text;
BEGIN
    PERFORM admissions.iut_office();
    IF v_code !~ '^[A-Z][A-Z0-9_]{2,39}$' THEN
        RAISE EXCEPTION 'IUT_KIND: a document''s code is 3 to 40 capital letters, digits or _, beginning with a letter' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO k FROM admissions.iut_document_kind WHERE code = v_code FOR UPDATE;
    v_label := coalesce(v_label, k.label);
    IF v_label IS NULL OR length(v_label) NOT BETWEEN 3 AND 160 THEN
        RAISE EXCEPTION 'IUT_KIND: a document''s label is 3 to 160 characters' USING ERRCODE = '23514';
    END IF;
    -- a hint not given is kept; one given blank is cleared
    v_hint := CASE WHEN p_hint IS NULL THEN k.hint ELSE nullif(btrim(p_hint), '') END;
    IF length(coalesce(v_hint, '')) > 400 THEN
        RAISE EXCEPTION 'IUT_KIND: a document''s hint is at most 400 characters' USING ERRCODE = '23514';
    END IF;
    INSERT INTO admissions.iut_document_kind (code, label, hint, required, images_allowed, ord, active, changed_by, changed_office, changed_at)
    VALUES (v_code, v_label, v_hint, coalesce(p_required, k.required, false), coalesce(p_images_allowed, k.images_allowed, true),
            coalesce(p_ord, k.ord, (SELECT coalesce(max(x.ord), 0) + 10 FROM admissions.iut_document_kind x)), coalesce(p_active, k.active, true), who, office, now())
    ON CONFLICT (code) DO UPDATE
       SET label = EXCLUDED.label, hint = EXCLUDED.hint, required = EXCLUDED.required, images_allowed = EXCLUDED.images_allowed, ord = EXCLUDED.ord,
           active = EXCLUDED.active, changed_by = EXCLUDED.changed_by, changed_office = EXCLUDED.changed_office, changed_at = EXCLUDED.changed_at;
    RETURN admissions.iut_document_kinds();
END $$;

-- ── 7 · the Bursary's acts: the fee stated (bursar, studentaccounts, super) and published (bursar, super) ──────────────────
CREATE FUNCTION finance.iut_fee_for(p_session text) RETURNS numeric LANGUAGE sql STABLE AS $$
    SELECT f.amount FROM finance.iut_fee f WHERE f.session = p_session AND f.state = 'PUBLISHED';
$$;
COMMENT ON FUNCTION finance.iut_fee_for(text) IS 'V766: the inter-university transfer application fee published for the session (0: none charged), or NULL when none is published: a fee never published is never charged.';

CREATE FUNCTION finance.iut_fee_view(p_session text) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'session', p_session,
        'amount', f.amount, 'state', f.state, 'note', f.note,
        'statedAt', f.stated_at, 'statedOffice', f.stated_office,
        'publishedAt', f.published_at, 'publishedOffice', f.published_office, 'publishedBy', f.published_by,
        'publishedByName', people.officer_name(f.published_by),
        'draft', CASE WHEN f.draft_amount IS NULL THEN NULL
                      ELSE jsonb_build_object('amount', f.draft_amount, 'note', f.draft_note, 'by', f.drafted_by, 'byName', people.officer_name(f.drafted_by),
                                              'office', f.drafted_office, 'at', f.drafted_at) END,
        'history', coalesce((SELECT jsonb_agg(jsonb_build_object('action', h.action, 'amount', h.amount, 'wasAmount', h.was_amount, 'wasState', h.was_state,
                                                                'note', h.note, 'by', h.changed_by, 'byName', people.officer_name(h.changed_by),
                                                                'office', h.changed_office, 'at', h.changed_at) ORDER BY h.changed_at DESC, h.id)
                               FROM finance.iut_fee_change h WHERE h.session = p_session), '[]'::jsonb))
      FROM (SELECT 1) one LEFT JOIN finance.iut_fee f ON f.session = p_session;
$$;

CREATE FUNCTION finance.iut_fee_state(p_session text, p_amount numeric, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
        v_amount numeric := round(p_amount, 2); v_note text := nullif(btrim(p_note), '');
BEGIN
    IF who IS NULL OR coalesce(v_office, '-') NOT IN ('bursar', 'studentaccounts', 'super') THEN
        RAISE EXCEPTION 'IUT_FEE_OFFICE: the transfer application fee is stated by the Bursary' USING ERRCODE = '42501';
    END IF;
    PERFORM admissions.iut_session_ok(p_session);
    IF p_amount IS NULL OR p_amount < 0 THEN
        RAISE EXCEPTION 'IUT_FEE_AMOUNT: the fee is an amount of nothing or more' USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.iut_fee (session, amount, state, note, stated_by, stated_office, draft_amount, draft_note, drafted_by, drafted_office, drafted_at)
    VALUES (p_session, v_amount, 'DRAFT', v_note, who, v_office, v_amount, v_note, who, v_office, now())
    ON CONFLICT (session) DO UPDATE
       SET draft_amount = EXCLUDED.draft_amount, draft_note = EXCLUDED.draft_note, drafted_by = EXCLUDED.drafted_by,
           drafted_office = EXCLUDED.drafted_office, drafted_at = EXCLUDED.drafted_at,
           -- never published: the fee is its draft
           amount = CASE WHEN finance.iut_fee.state = 'PUBLISHED' THEN finance.iut_fee.amount ELSE EXCLUDED.amount END,
           note = CASE WHEN finance.iut_fee.state = 'PUBLISHED' THEN finance.iut_fee.note ELSE EXCLUDED.note END,
           stated_by = CASE WHEN finance.iut_fee.state = 'PUBLISHED' THEN finance.iut_fee.stated_by ELSE EXCLUDED.stated_by END,
           stated_office = CASE WHEN finance.iut_fee.state = 'PUBLISHED' THEN finance.iut_fee.stated_office ELSE EXCLUDED.stated_office END,
           stated_at = CASE WHEN finance.iut_fee.state = 'PUBLISHED' THEN finance.iut_fee.stated_at ELSE now() END;
    RETURN finance.iut_fee_view(p_session);
END $$;

CREATE FUNCTION finance.iut_fee_publish(p_session text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR coalesce(v_office, '-') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'IUT_FEE_OFFICE: the transfer application fee is published by the Bursar' USING ERRCODE = '42501';
    END IF;
    UPDATE finance.iut_fee
       SET amount = coalesce(draft_amount, amount), note = CASE WHEN draft_amount IS NOT NULL THEN draft_note ELSE note END,
           stated_by = coalesce(drafted_by, stated_by), stated_office = coalesce(drafted_office, stated_office), stated_at = coalesce(drafted_at, stated_at),
           state = 'PUBLISHED', published_by = who, published_office = v_office, published_at = now(),
           draft_amount = NULL, draft_note = NULL, drafted_by = NULL, drafted_office = NULL, drafted_at = NULL
     WHERE session = p_session AND (state = 'DRAFT' OR draft_amount IS NOT NULL);
    IF NOT FOUND AND NOT EXISTS (SELECT 1 FROM finance.iut_fee WHERE session = p_session) THEN
        RAISE EXCEPTION 'IUT_FEE_NOT_STATED: no transfer application fee is stated for %', p_session USING ERRCODE = '23514';
    END IF;
    RETURN finance.iut_fee_view(p_session);
END $$;

CREATE FUNCTION finance.iut_payments(p_session text, p_state text, p_q text, p_limit integer, p_offset integer) RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH given AS (
        -- given back by the refund desk: its refunds approved or paid against the reference (finance.gst_refunded, as the SIWES report
        -- and the master report count them), never more than was paid
        SELECT f.*, CASE WHEN f.confirmed_at IS NOT NULL THEN least(f.amount, finance.gst_refunded(f.reference)) ELSE 0 END AS refunded
          FROM admissions.iut_fee_reference f
         WHERE p_session IS NULL OR f.session = p_session),
    base AS (
        SELECT f.*, a.application_no, a.surname, a.other_names, a.jamb_reg_no, a.programme_code, a.state AS application_state, p.name AS programme_name,
               CASE WHEN f.confirmed_at IS NOT NULL THEN 'PAID' WHEN f.expires_at <= now() THEN 'EXPIRED' ELSE 'PENDING' END AS pay_state,
               -- owed back: paid, settling nothing, and not yet all given back
               (f.confirmed_at IS NOT NULL AND NOT f.settles AND f.refunded < f.amount) AS owed_back
          FROM given f
          JOIN admissions.iut_application a ON a.id = f.application_id
          LEFT JOIN ref.programme p ON p.code = a.programme_code),
    filtered AS (
        SELECT * FROM base b
         WHERE (nullif(btrim(coalesce(p_state, '')), '') IS NULL
                OR (upper(btrim(p_state)) = 'OWED_BACK' AND b.owed_back) OR b.pay_state = upper(btrim(p_state)))
           AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL
                OR b.reference ILIKE '%' || btrim(p_q) || '%' OR coalesce(b.receipt_no, '') ILIKE '%' || btrim(p_q) || '%'
                OR b.application_no ILIKE '%' || btrim(p_q) || '%' OR b.jamb_reg_no ILIKE '%' || btrim(p_q) || '%'
                OR (b.surname || ', ' || b.other_names) ILIKE '%' || btrim(p_q) || '%' OR (b.other_names || ' ' || b.surname) ILIKE '%' || btrim(p_q) || '%'))
    SELECT jsonb_build_object(
        'session', p_session,
        'totals', (SELECT jsonb_build_object('drawn', count(*), 'paid', count(*) FILTER (WHERE x.pay_state = 'PAID'),
                                             'paidAmount', coalesce(sum(x.amount) FILTER (WHERE x.pay_state = 'PAID'), 0),
                                             'pending', count(*) FILTER (WHERE x.pay_state = 'PENDING'), 'expired', count(*) FILTER (WHERE x.pay_state = 'EXPIRED'),
                                             'owedBack', count(*) FILTER (WHERE x.owed_back), 'owedBackAmount', coalesce(sum(x.amount - x.refunded) FILTER (WHERE x.owed_back), 0),
                                             'refunded', count(*) FILTER (WHERE x.refunded > 0), 'refundedAmount', coalesce(sum(x.refunded), 0))
                     FROM filtered x),
        'rows', coalesce((SELECT jsonb_agg(jsonb_build_object(
                    'reference', r.reference, 'amount', r.amount, 'generatedAt', r.created_at, 'expiresAt', r.expires_at, 'confirmedAt', r.confirmed_at,
                    'channel', r.channel, 'receiptNo', r.receipt_no, 'state', r.pay_state, 'settles', r.settles, 'owedBack', r.owed_back, 'refunded', r.refunded,
                    'applicationId', r.application_id, 'applicationNo', r.application_no, 'name', r.surname || ', ' || r.other_names, 'jambRegNo', r.jamb_reg_no,
                    'programme', r.programme_code, 'programmeName', r.programme_name, 'applicationState', r.application_state) ORDER BY r.created_at DESC, r.reference)
                            FROM (SELECT * FROM filtered ORDER BY created_at DESC, reference
                                   LIMIT greatest(1, least(coalesce(p_limit, 100), 1000)) OFFSET greatest(coalesce(p_offset, 0), 0)) r), '[]'::jsonb));
$$;
COMMENT ON FUNCTION finance.iut_payments(text, text, text, integer, integer) IS
  'V766: the transfer application fee''s references for the Bursary — PAID, PENDING or EXPIRED, and owed back (a payment confirmed that did not settle the application: a second payment, or one after a withdrawal or a refusal, until the refund desk has given it all back: refunded, its refunds approved or paid); searched by the reference, receipt, application and JAMB numbers and the name; the totals over the filtered rows, before paging (owedBackAmount what is still owed, refundedAmount what is given back).';

-- ── 8 · the applicant's acts ─────────────────────────────────────────────────────────────────────────────────────────────
/* a fee of nothing is settled as it stands */
CREATE FUNCTION admissions.iut_settle_none_due(p_app uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application;
BEGIN
    UPDATE admissions.iut_application SET fee_settled_at = now(), fee_basis = 'NONE_DUE' WHERE id = p_app AND fee_settled_at IS NULL RETURNING * INTO a;
    IF a.id IS NULL THEN RETURN NULL; END IF;
    RETURN admissions.iut_log(a.id, 'FEE_NONE_DUE', a.state, a.state, 'No application fee is charged for ' || a.session, true);
END $$;

CREATE FUNCTION admissions.iut_apply(p jsonb, p_hash text, p_account uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_session text := admissions.iut_open_session(); v jsonb; v_prog text; v_level_text text; v_level integer; acc admissions.iut_account;
        v_last admissions.iut_application; v_app uuid; v_no text; v_fee numeric; v_ev uuid; v_con text; v_settled boolean := false;
BEGIN
    p := coalesce(p, '{}'::jsonb);
    -- the particulars, in the order the form shows them (an account applying again keeps its e-mail and phone)
    v := admissions.iut_particulars(p, v_session,
             CASE WHEN p_account IS NULL THEN NULL
                  ELSE ARRAY['surname', 'otherNames', 'sex', 'dateOfBirth', 'jambRegNo', 'university', 'otherMatricNo', 'otherProgramme', 'otherLevel',
                             'otherEntrySession', 'otherCgpa', 'reason'] END);
    IF v_session IS NULL THEN
        RAISE EXCEPTION 'IUT_WINDOW_CLOSED: inter-university transfer applications are not open' USING ERRCODE = '23514', HINT = admissions.iut_closed_hint(NULL);
    END IF;
    v_prog := upper(btrim(coalesce(p->>'programme', '')));
    v_level_text := btrim(coalesce(p->>'level', ''));
    v_level := CASE WHEN v_level_text ~ '^[1-9]00$' THEN v_level_text::int END;
    IF NOT EXISTS (SELECT 1 FROM admissions.iut_line l
                    WHERE l.session = v_session AND l.programme_code = v_prog AND l.level = v_level AND l.accepting
                      AND admissions.iut_line_offered(l.programme_code, l.level)) THEN
        RAISE EXCEPTION 'IUT_PROGRAMME_NOT_OPEN: %', admissions.iut_line_words(v_session, v_prog, v_level) USING ERRCODE = '23514',
            HINT = 'Choose a programme and level from the list';
    END IF;

    IF p_account IS NULL THEN
        IF EXISTS (SELECT 1 FROM admissions.iut_account x WHERE lower(x.email) = v->>'email') THEN
            RAISE EXCEPTION 'IUT_EMAIL_TAKEN: an application account already uses this e-mail' USING ERRCODE = '23514',
                HINT = 'Sign in with it, or choose Forgot password and give your transfer application number (IUT/APP/…)';
        END IF;
        IF p_hash IS NULL OR p_hash NOT LIKE '$2%$12$%' THEN
            RAISE EXCEPTION 'IUT_PASSWORD: the password is kept only as its bcrypt hash (cost 12)' USING ERRCODE = '23514';
        END IF;
        BEGIN
            INSERT INTO admissions.iut_account (email, phone, password_hash) VALUES (v->>'email', v->>'phone', p_hash) RETURNING * INTO acc;
        EXCEPTION WHEN unique_violation THEN
            RAISE EXCEPTION 'IUT_EMAIL_TAKEN: an application account already uses this e-mail' USING ERRCODE = '23514',
                HINT = 'Sign in with it, or choose Forgot password and give your transfer application number (IUT/APP/…)';
        END;
    ELSE
        IF coalesce(office, '-') <> 'applicant' OR who IS DISTINCT FROM p_account THEN
            RAISE EXCEPTION 'IUT_NOT_YOURS: an application account applies again for itself alone' USING ERRCODE = '42501';
        END IF;
        SELECT * INTO acc FROM admissions.iut_account WHERE id = p_account FOR UPDATE;
        IF acc.id IS NULL THEN
            RAISE EXCEPTION 'IUT_NOT_YOURS: no such application account' USING ERRCODE = '42501';
        END IF;
        SELECT * INTO v_last FROM admissions.iut_application x WHERE x.account_id = acc.id ORDER BY x.created_at DESC LIMIT 1;
        IF (v_last.id IS NOT NULL AND v_last.state NOT IN ('REJECTED', 'WITHDRAWN'))
           OR EXISTS (SELECT 1 FROM admissions.iut_application x WHERE x.account_id = acc.id AND x.session = v_session) THEN
            RAISE EXCEPTION 'IUT_ALREADY_APPLIED: this account has an application in progress, or one in %', v_session USING ERRCODE = '23514',
                HINT = 'An account applies again once its last application is refused or withdrawn, in a later window';
        END IF;
    END IF;

    -- one live application under a JAMB number (nothing about the students of the University is read at this door)
    IF EXISTS (SELECT 1 FROM admissions.iut_application x WHERE upper(x.jamb_reg_no) = v->>'jambRegNo' AND x.state NOT IN ('REJECTED', 'WITHDRAWN')) THEN
        RAISE EXCEPTION 'IUT_JAMB_TAKEN: an application under this JAMB number is already in progress' USING ERRCODE = '23514',
            HINT = 'Sign in to it, or ask the Registry';
    END IF;
    v_no := 'IUT/APP/' || left(v_session, 4) || '/' || lpad(platform.next_number('IUT_APPLICATION', 'UNIVERSITY', v_session)::text, 6, '0');
    BEGIN
        INSERT INTO admissions.iut_application (account_id, session, application_no, jamb_reg_no, surname, other_names, sex, date_of_birth,
                                                university_code, university_named, other_matric_no, other_programme, other_level, other_entry_session,
                                                other_cgpa, other_cgpa_scale, programme_code, level, reason)
        VALUES (acc.id, v_session, v_no, v->>'jambRegNo', v->>'surname', v->>'otherNames', v->>'sex', (v->>'dateOfBirth')::date,
                v->>'universityCode', v->>'universityNamed', v->>'otherMatricNo', v->>'otherProgramme', (v->>'otherLevel')::int, v->>'otherEntrySession',
                (v->>'otherCgpa')::numeric, (v->>'otherCgpaScale')::smallint, v_prog, v_level, v->>'reason')
        RETURNING id INTO v_app;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
        IF v_con = 'ux_iut_app_live_jamb' THEN
            RAISE EXCEPTION 'IUT_JAMB_TAKEN: an application under this JAMB number is already in progress' USING ERRCODE = '23514',
                HINT = 'Sign in to it, or ask the Registry';
        ELSIF v_con = 'uq_iut_app_account_session' THEN
            RAISE EXCEPTION 'IUT_ALREADY_APPLIED: this account has an application in %', v_session USING ERRCODE = '23514';
        END IF;
        RAISE;
    END;
    v_ev := admissions.iut_log(v_app, 'CREATED', NULL, 'DRAFT', v_no, true);

    v_fee := finance.iut_fee_for(v_session);
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'IUT_FEE_NOT_PUBLISHED: no application fee is published for %', v_session USING ERRCODE = '23514',
            HINT = 'The Bursar publishes the session''s application fee; try again later';
    ELSIF v_fee = 0 THEN
        PERFORM admissions.iut_settle_none_due(v_app);
        v_settled := true;
    END IF;
    PERFORM admissions.iut_tell(v_app, 'IUT_APPLICATION', 'CREATED', NULL, 'IUT:CREATED:' || v_app || ':' || v_ev);
    RETURN jsonb_build_object('accountId', acc.id, 'applicationId', v_app, 'applicationNo', v_no, 'session', v_session,
                              'feeDue', CASE WHEN v_settled THEN 0 ELSE v_fee END);
END $$;
COMMENT ON FUNCTION admissions.iut_apply(jsonb, text, uuid) IS
  'V766: an inter-university transfer application made at the public door (a new account: p_hash the password''s bcrypt hash) or by a signed-in account applying again (p_account, its last application refused or withdrawn, none in the session): the particulars checked, the window open and the programme and level on its list, one live application under a JAMB number; a fee of nothing settled at once. Returns {accountId, applicationId, applicationNo, session, feeDue}.';

CREATE FUNCTION admissions.iut_update(p_app uuid, p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; acc admissions.iut_account; k text; v_given text[]; v_allowed text[]; v_keys text[] := '{}'; m jsonb; v jsonb;
        v_changed text[] := '{}'; v_prog text; v_level integer; v_level_text text; v_con text; n_email text; n_phone text;
        v_particulars text[] := ARRAY['surname', 'otherNames', 'sex', 'dateOfBirth', 'jambRegNo', 'universityCode', 'universityNamed', 'otherMatricNo',
                                      'otherProgramme', 'otherLevel', 'otherEntrySession', 'otherCgpa', 'otherCgpaScale', 'reason'];
BEGIN
    a := admissions.iut_mine(p_app);
    SELECT * INTO acc FROM admissions.iut_account WHERE id = a.account_id FOR UPDATE;
    p := CASE WHEN jsonb_typeof(p) = 'object' THEN p ELSE '{}'::jsonb END;
    -- a key given as null is not given
    v_given := ARRAY(SELECT e.key FROM jsonb_each(p) e WHERE jsonb_typeof(e.value) <> 'null' ORDER BY e.key);
    v_allowed := CASE WHEN a.state = 'DRAFT' THEN v_particulars || ARRAY['programme', 'level', 'email', 'phone']
                      WHEN a.state = 'CORRECTION_REQUIRED' THEN v_particulars || ARRAY['email', 'phone']
                      WHEN a.state IN ('ADMITTED', 'REJECTED', 'WITHDRAWN') THEN '{}'::text[]
                      ELSE ARRAY['email', 'phone'] END;
    FOREACH k IN ARRAY v_given LOOP
        IF NOT k = ANY (v_allowed) THEN
            RAISE EXCEPTION 'IUT_NOT_EDITABLE: % cannot be changed now', CASE k
                    WHEN 'surname' THEN 'the surname' WHEN 'otherNames' THEN 'the other names' WHEN 'sex' THEN 'the sex' WHEN 'dateOfBirth' THEN 'the date of birth'
                    WHEN 'jambRegNo' THEN 'the JAMB registration number' WHEN 'universityCode' THEN 'the present university' WHEN 'universityNamed' THEN 'the present university'
                    WHEN 'otherMatricNo' THEN 'the matriculation number at the present university' WHEN 'otherProgramme' THEN 'the programme at the present university'
                    WHEN 'otherLevel' THEN 'the level at the present university' WHEN 'otherEntrySession' THEN 'the session entered at the present university'
                    WHEN 'otherCgpa' THEN 'the CGPA' WHEN 'otherCgpaScale' THEN 'the CGPA' WHEN 'reason' THEN 'the reason for transferring'
                    WHEN 'programme' THEN 'the programme applied for' WHEN 'level' THEN 'the level applied for' WHEN 'email' THEN 'the e-mail address'
                    WHEN 'phone' THEN 'the phone number' ELSE k END
                USING ERRCODE = '23514',
                      HINT = CASE WHEN a.state = 'CORRECTION_REQUIRED' THEN 'The particulars are corrected now; the programme and level stay as applied for'
                                  WHEN a.state IN ('ADMITTED', 'REJECTED', 'WITHDRAWN') THEN 'The application is ' || lower(a.state) || '; nothing on it changes'
                                  ELSE 'Only the e-mail address and the phone number change now' END;
        END IF;
    END LOOP;

    -- the particulars given, read beside the ones kept (the university and the CGPA are each a pair)
    m := jsonb_build_object('surname', a.surname, 'otherNames', a.other_names, 'sex', a.sex, 'dateOfBirth', to_char(a.date_of_birth, 'YYYY-MM-DD'),
                            'jambRegNo', a.jamb_reg_no, 'universityCode', a.university_code, 'universityNamed', a.university_named,
                            'otherMatricNo', a.other_matric_no, 'otherProgramme', a.other_programme, 'otherLevel', a.other_level,
                            'otherEntrySession', a.other_entry_session, 'otherCgpa', a.other_cgpa, 'otherCgpaScale', a.other_cgpa_scale, 'reason', a.reason,
                            'email', acc.email, 'phone', acc.phone);
    FOREACH k IN ARRAY v_given LOOP
        IF k IN ('programme', 'level') THEN CONTINUE; END IF;
        m := m || jsonb_build_object(k, p->k);
        v_keys := v_keys || CASE k WHEN 'universityCode' THEN 'university' WHEN 'universityNamed' THEN 'university' WHEN 'otherCgpaScale' THEN 'otherCgpa' ELSE k END;
    END LOOP;
    -- a name typed without a code: the university is not on the list
    IF 'universityNamed' = ANY (v_given) AND NOT 'universityCode' = ANY (v_given) THEN
        m := m || jsonb_build_object('universityCode', NULL);
    END IF;
    -- only the particulars given are checked (none given: none; iut_particulars reads NULL as all)
    v := CASE WHEN cardinality(v_keys) = 0 THEN '{}'::jsonb
              ELSE admissions.iut_particulars(m, a.session, (SELECT array_agg(DISTINCT x) FROM unnest(v_keys) x)) END;

    IF v ? 'jambRegNo' AND v->>'jambRegNo' <> a.jamb_reg_no
       AND EXISTS (SELECT 1 FROM admissions.iut_application x WHERE x.id <> a.id AND upper(x.jamb_reg_no) = v->>'jambRegNo' AND x.state NOT IN ('REJECTED', 'WITHDRAWN')) THEN
        RAISE EXCEPTION 'IUT_JAMB_TAKEN: an application under this JAMB number is already in progress' USING ERRCODE = '23514', HINT = 'Sign in to it, or ask the Registry';
    END IF;

    -- the programme and level applied for: only in DRAFT, only while the window is open, only on a line taking transfers
    v_prog := a.programme_code; v_level := a.level;
    IF 'programme' = ANY (v_given) THEN v_prog := upper(btrim(p->>'programme')); END IF;
    IF 'level' = ANY (v_given) THEN
        v_level_text := btrim(p->>'level');
        v_level := CASE WHEN v_level_text ~ '^[1-9]00$' THEN v_level_text::int END;
    END IF;
    IF v_prog IS DISTINCT FROM a.programme_code OR v_level IS DISTINCT FROM a.level THEN
        IF admissions.iut_window_status(a.session) <> 'OPEN' THEN
            RAISE EXCEPTION 'IUT_WINDOW_CLOSED: the window is closed; the programme and level applied for no longer change' USING ERRCODE = '23514',
                HINT = admissions.iut_closed_hint(a.session);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM admissions.iut_line l
                        WHERE l.session = a.session AND l.programme_code = v_prog AND l.level = v_level AND l.accepting
                          AND admissions.iut_line_offered(l.programme_code, l.level)) THEN
            RAISE EXCEPTION 'IUT_PROGRAMME_NOT_OPEN: %', admissions.iut_line_words(a.session, v_prog, v_level) USING ERRCODE = '23514',
                HINT = 'Choose a programme and level from the list';
        END IF;
    END IF;

    -- what changed
    IF v ? 'surname' AND v->>'surname' <> a.surname THEN v_changed := array_append(v_changed, 'surname'); END IF;
    IF v ? 'otherNames' AND v->>'otherNames' <> a.other_names THEN v_changed := array_append(v_changed, 'other names'); END IF;
    IF v ? 'sex' AND v->>'sex' <> a.sex THEN v_changed := array_append(v_changed, 'sex'); END IF;
    IF v ? 'dateOfBirth' AND (v->>'dateOfBirth')::date <> a.date_of_birth THEN v_changed := array_append(v_changed, 'date of birth'); END IF;
    IF v ? 'jambRegNo' AND v->>'jambRegNo' <> a.jamb_reg_no THEN v_changed := array_append(v_changed, 'JAMB registration number'); END IF;
    IF v ? 'universityCode' AND ((v->>'universityCode') IS DISTINCT FROM a.university_code OR (v->>'universityNamed') IS DISTINCT FROM a.university_named) THEN
        v_changed := array_append(v_changed, 'present university');
    END IF;
    IF v ? 'otherMatricNo' AND v->>'otherMatricNo' <> a.other_matric_no THEN v_changed := array_append(v_changed, 'matriculation number there'); END IF;
    IF v ? 'otherProgramme' AND v->>'otherProgramme' <> a.other_programme THEN v_changed := array_append(v_changed, 'programme there'); END IF;
    IF v ? 'otherLevel' AND (v->>'otherLevel')::int <> a.other_level THEN v_changed := array_append(v_changed, 'level there'); END IF;
    IF v ? 'otherEntrySession' AND v->>'otherEntrySession' <> a.other_entry_session THEN v_changed := array_append(v_changed, 'session entered there'); END IF;
    IF v ? 'otherCgpa' AND ((v->>'otherCgpa')::numeric <> a.other_cgpa OR (v->>'otherCgpaScale')::int <> a.other_cgpa_scale) THEN v_changed := array_append(v_changed, 'CGPA'); END IF;
    IF v ? 'reason' AND v->>'reason' <> a.reason THEN v_changed := array_append(v_changed, 'reason'); END IF;
    IF v_prog IS DISTINCT FROM a.programme_code THEN v_changed := array_append(v_changed, 'programme applied for'); END IF;
    IF v_level IS DISTINCT FROM a.level THEN v_changed := array_append(v_changed, 'level applied for'); END IF;
    n_email := CASE WHEN v ? 'email' AND v->>'email' <> acc.email THEN v->>'email' END;
    n_phone := CASE WHEN v ? 'phone' AND v->>'phone' <> acc.phone THEN v->>'phone' END;
    IF n_email IS NOT NULL THEN v_changed := array_append(v_changed, 'e-mail address'); END IF;
    IF n_phone IS NOT NULL THEN v_changed := array_append(v_changed, 'phone number'); END IF;
    IF cardinality(v_changed) = 0 THEN RETURN admissions.iut_view(a.id, 'APPLICANT'); END IF;

    IF n_email IS NOT NULL OR n_phone IS NOT NULL THEN
        IF n_email IS NOT NULL AND EXISTS (SELECT 1 FROM admissions.iut_account x WHERE x.id <> acc.id AND lower(x.email) = n_email) THEN
            RAISE EXCEPTION 'IUT_EMAIL_TAKEN: an application account already uses this e-mail' USING ERRCODE = '23514';
        END IF;
        BEGIN
            UPDATE admissions.iut_account SET email = coalesce(n_email, email), phone = coalesce(n_phone, phone) WHERE id = acc.id;
        EXCEPTION WHEN unique_violation THEN
            RAISE EXCEPTION 'IUT_EMAIL_TAKEN: an application account already uses this e-mail' USING ERRCODE = '23514';
        END;
    END IF;
    BEGIN
        UPDATE admissions.iut_application
           SET surname = coalesce(v->>'surname', surname), other_names = coalesce(v->>'otherNames', other_names), sex = coalesce(v->>'sex', sex),
               date_of_birth = coalesce((v->>'dateOfBirth')::date, date_of_birth), jamb_reg_no = coalesce(v->>'jambRegNo', jamb_reg_no),
               university_code = CASE WHEN v ? 'universityCode' THEN v->>'universityCode' ELSE university_code END,
               university_named = CASE WHEN v ? 'universityCode' THEN v->>'universityNamed' ELSE university_named END,
               other_matric_no = coalesce(v->>'otherMatricNo', other_matric_no), other_programme = coalesce(v->>'otherProgramme', other_programme),
               other_level = coalesce((v->>'otherLevel')::int, other_level), other_entry_session = coalesce(v->>'otherEntrySession', other_entry_session),
               other_cgpa = coalesce((v->>'otherCgpa')::numeric, other_cgpa), other_cgpa_scale = coalesce((v->>'otherCgpaScale')::smallint, other_cgpa_scale),
               reason = coalesce(v->>'reason', reason)
         WHERE id = a.id;
        IF v_prog IS DISTINCT FROM a.programme_code OR v_level IS DISTINCT FROM a.level THEN
            UPDATE admissions.iut_application SET programme_code = v_prog, level = v_level WHERE id = a.id;
        END IF;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
        IF v_con = 'ux_iut_app_live_jamb' THEN
            RAISE EXCEPTION 'IUT_JAMB_TAKEN: an application under this JAMB number is already in progress' USING ERRCODE = '23514', HINT = 'Sign in to it, or ask the Registry';
        END IF;
        RAISE;
    END;
    PERFORM admissions.iut_log(a.id, 'EDITED', a.state, a.state, 'Changed: ' || array_to_string(v_changed, ', '), true);
    RETURN admissions.iut_view(a.id, 'APPLICANT');
END $$;

CREATE FUNCTION admissions.iut_fee_reference_draw(p_app uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; v_fee numeric; r admissions.iut_fee_reference;
BEGIN
    a := admissions.iut_mine(p_app);
    IF a.state <> 'DRAFT' THEN
        RAISE EXCEPTION 'IUT_STATE: the application fee is paid before the application is submitted; this one is %', admissions.iut_state_words(a.state) USING ERRCODE = '23514';
    END IF;
    IF a.fee_settled_at IS NOT NULL THEN
        -- nothing was due: the page asks, and is answered so
        IF a.fee_basis = 'NONE_DUE' THEN RETURN jsonb_build_object('settled', true, 'due', 0); END IF;
        RAISE EXCEPTION 'IUT_FEE_SETTLED: the application fee is already settled' USING ERRCODE = '23514';
    END IF;
    -- no window check (D5): an application made before the closing still pays
    v_fee := finance.iut_fee_for(a.session);
    IF v_fee IS NULL THEN
        RAISE EXCEPTION 'IUT_FEE_NOT_PUBLISHED: no application fee is published for %', a.session USING ERRCODE = '23514',
            HINT = 'The Bursar publishes the session''s application fee; try again later';
    END IF;
    IF v_fee = 0 THEN
        PERFORM admissions.iut_settle_none_due(a.id);
        RETURN jsonb_build_object('settled', true, 'due', 0);
    END IF;
    -- the reference still open for the fee in force, else a new one for 24 hours
    SELECT * INTO r FROM admissions.iut_fee_reference f
     WHERE f.application_id = a.id AND f.confirmed_at IS NULL AND f.expires_at > now() AND f.amount = v_fee
     ORDER BY f.created_at DESC LIMIT 1;
    IF r.id IS NULL THEN
        INSERT INTO admissions.iut_fee_reference (application_id, reference, amount, session, expires_at)
        VALUES (a.id, 'MOAUM-IUTAPP-' || left(a.session, 4) || '-' || lpad(platform.next_number('IUT_FEEREF', 'UNIVERSITY', a.session)::text, 6, '0'),
                v_fee, a.session, now() + interval '24 hours')
        RETURNING * INTO r;
    END IF;
    RETURN jsonb_build_object('settled', false, 'reference', r.reference, 'amount', r.amount, 'expiresAt', r.expires_at);
END $$;

/* a reference drawn at a figure the Bursar has since restated to nothing is not taken: the draft owes nothing now (the draw settles it
   NONE_DUE), so money paid on it would be a fee the University no longer charges */
CREATE FUNCTION admissions.iut_reference_payable(p_reference text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT f.confirmed_at IS NULL AND f.expires_at > now() AND a.state = 'DRAFT' AND a.fee_settled_at IS NULL
                            AND coalesce(finance.iut_fee_for(a.session) <> 0, true)
                       FROM admissions.iut_fee_reference f JOIN admissions.iut_application a ON a.id = f.application_id
                      WHERE f.reference = upper(btrim(coalesce(p_reference, '')))), false);
$$;
COMMENT ON FUNCTION admissions.iut_reference_payable(text) IS
  'V766: whether a transfer application fee reference may still be paid — unconfirmed and unexpired, its application in DRAFT with the fee not yet settled, and the session''s fee not restated to nothing since it was drawn. The checkout and PAYDirect validation ask it; a payment that comes anyway is owed back.';

/* p_gateway_refs: every identifier the channel gives the payment (a Payment Log Id, a payment reference, the WebPAY transaction
   reference asked and its RRN, a transaction id), the receipt's first, kept so a bank credit for the reference can be told to be that
   payment or another (finance.iut_bank_credit_already_paid): a settlement row may carry any one of them. Blank ones are dropped,
   one written twice is kept once, at most eight */
CREATE FUNCTION admissions.iut_confirm_fee(p_reference text, p_channel text, p_note text DEFAULT NULL, p_gateway_refs text[] DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_ref text := upper(btrim(coalesce(p_reference, ''))); r admissions.iut_fee_reference; a admissions.iut_application; v_ev uuid; v_settles boolean := false;
        v_none boolean := false;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'IUT_FEE_CONFIRM_ACTOR: a payment is confirmed by a person or a gateway on the record' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(coalesce(p_channel, ''))) = 'MANUAL' AND coalesce(office, '-') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'IUT_FEE_CONFIRM_OFFICE: a transfer application fee is confirmed by hand by the Bursar' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO r FROM admissions.iut_fee_reference WHERE reference = v_ref;
    IF r.id IS NULL THEN
        RAISE EXCEPTION 'IUT_REFERENCE_UNKNOWN: no reference % was generated by this portal', v_ref USING ERRCODE = 'P0002',
            HINT = 'Only a reference this portal generated is confirmed; money sent anywhere else did not reach the University';
    END IF;
    -- the application first, then its reference: two payments of one application settle it once
    SELECT * INTO a FROM admissions.iut_application WHERE id = r.application_id FOR UPDATE;
    UPDATE admissions.iut_fee_reference
       SET confirmed_at = now(), channel = nullif(btrim(coalesce(p_channel, '')), ''), note = nullif(btrim(coalesce(p_note, '')), ''),
           gateway_refs = (SELECT array_agg(k.id ORDER BY k.o)
                             FROM (SELECT d.id, d.o FROM (SELECT DISTINCT ON (finance.log_id_key(g.id)) g.id, g.o
                                                            FROM (SELECT left(btrim(regexp_replace(x, '[[:cntrl:]]', ' ', 'g')), 200) AS id, o
                                                                    FROM unnest(p_gateway_refs) WITH ORDINALITY u(x, o)) g
                                                           WHERE finance.log_id_key(g.id) IS NOT NULL
                                                           ORDER BY finance.log_id_key(g.id), g.o) d
                                    ORDER BY d.o LIMIT 8) k),
           receipt_no = 'RCT-' || left(session, 4) || '-' || lpad(platform.next_number('RECEIPT', 'UNIVERSITY', session)::text, 5, '0'),
           confirmed_by = who, confirmed_office = office
     WHERE id = r.id AND confirmed_at IS NULL
    RETURNING * INTO r;
    IF NOT FOUND THEN RETURN 'already confirmed'; END IF;
    -- the fee restated to nothing since the reference was drawn: the draft owes nothing (settled so, as the draw would settle it), and
    -- this money is a fee no longer charged, owed back (D19 refuses a refund only of a payment that settles)
    IF a.fee_settled_at IS NULL AND a.state NOT IN ('WITHDRAWN', 'REJECTED') AND finance.iut_fee_for(a.session) = 0 THEN
        PERFORM admissions.iut_settle_none_due(a.id);
        SELECT * INTO a FROM admissions.iut_application WHERE id = a.id;
        v_none := true;
    END IF;
    IF a.fee_settled_at IS NULL AND a.state NOT IN ('WITHDRAWN', 'REJECTED') THEN
        UPDATE admissions.iut_fee_reference SET settles = true WHERE id = r.id;
        UPDATE admissions.iut_application SET fee_settled_at = now(), fee_basis = 'PAID' WHERE id = a.id;
        v_ev := admissions.iut_log(a.id, 'FEE_PAID', a.state, a.state, r.reference || ' · ' || r.receipt_no, true);
        v_settles := true;
    ELSE
        -- a second payment, one after the application was withdrawn or refused, or one of a fee restated to nothing: owed back (D19)
        v_ev := admissions.iut_log(a.id, 'FEE_PAID_AGAIN', a.state, a.state, r.reference || ' · ' || r.receipt_no || ' · owed back'
                                   || CASE WHEN v_none THEN ' (no application fee is charged for ' || a.session || ')' ELSE '' END, false);
    END IF;
    PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'PAYMENT_RECEIVED',
        jsonb_build_object('RECEIPT_NUMBER', r.receipt_no, 'REFERENCE', r.reference, 'PURPOSE', 'Inter-university transfer application fee',
                           'AMOUNT', 'NGN ' || to_char(r.amount, 'FM999,999,990.00'), 'PAID_ON', to_char(now() AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY'),
                           'CHANNEL', coalesce(r.channel, 'Bank'), 'APPLICATION_NUMBER', a.application_no,
                           'NEXT_STEP', CASE WHEN v_settles THEN 'Your application fee is settled: sign in, upload your documents and submit the application.'
                                             WHEN v_none THEN 'No application fee is charged for ' || a.session || ' now, so this payment is owed back to you: the Bursary refunds it. Sign in, upload your documents and submit the application.'
                                             ELSE 'The application fee was already settled, or the application is closed, so this payment is owed back to you: the Bursary refunds it.' END),
        'IUT:PAYMENT_RECEIVED:' || a.id || ':' || v_ev);
    RETURN 'confirmed';
END $$;
COMMENT ON FUNCTION admissions.iut_confirm_fee(text, text, text, text[]) IS
  'V766: a transfer application fee reference confirmed (admissions.confirm_fee''s contract): a receipt in the University''s series; the first payment of an application in progress settles it (settles), any other is owed back — as is one paid after the session''s fee was restated to nothing, the draft then settled without a fee (NONE_DUE); the payer told with the receipt. MANUAL is the Bursar''s alone. p_gateway_refs keeps every identifier the channel gave the payment (gateway_refs: a Payment Log Id, a payment reference, the WebPAY transaction reference and RRN, a transaction id), by any of which a bank credit is known to be that payment.';

CREATE FUNCTION admissions.iut_add_document(p_app uuid, p_kind text, p_filename text, p_content_type text, p_bytes integer, p_sha256 text, p_object uuid, p_content bytea)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; k admissions.iut_document_kind; cur admissions.iut_document; v_id uuid := gen_random_uuid();
        v_type text := lower(btrim(coalesce(p_content_type, ''))); v_sha text := lower(btrim(coalesce(p_sha256, '')));
        v_name text := left(btrim(regexp_replace(coalesce(p_filename, ''), '[\\/\r\n\t]', '_', 'g')), 200);
BEGIN
    a := admissions.iut_mine(p_app);
    IF a.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN
        RAISE EXCEPTION 'IUT_STATE: documents are uploaded before the application is submitted, or when it is returned to you; this one is %', admissions.iut_state_words(a.state)
            USING ERRCODE = '23514';
    END IF;
    IF a.fee_settled_at IS NULL THEN
        RAISE EXCEPTION 'IUT_FEE_UNPAID: pay the application fee first; documents are uploaded after it' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO k FROM admissions.iut_document_kind WHERE code = upper(btrim(coalesce(p_kind, ''))) AND active;
    IF k.code IS NULL THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_KIND: % is not a document this application asks for', coalesce(nullif(btrim(p_kind), ''), 'the document chosen') USING ERRCODE = '23514';
    END IF;
    IF v_type NOT IN ('application/pdf', 'image/jpeg', 'image/png') OR (v_type <> 'application/pdf' AND NOT k.images_allowed) THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_TYPE: % is uploaded as %', k.label, CASE WHEN k.images_allowed THEN 'a PDF, JPEG or PNG' ELSE 'a PDF' END USING ERRCODE = '23514';
    END IF;
    IF (p_object IS NULL) = (p_content IS NULL) THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_TYPE: the file is kept in the file store or here, one of the two' USING ERRCODE = '23514';
    END IF;
    IF p_bytes IS NULL OR p_bytes NOT BETWEEN 1 AND 5242880 OR (p_content IS NOT NULL AND octet_length(p_content) <> p_bytes) THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_SIZE: a document is at most 5 MB' USING ERRCODE = '23514';
    END IF;
    IF v_sha !~ '^[0-9a-f]{64}$' OR (p_content IS NOT NULL AND encode(sha256(p_content), 'hex') <> v_sha) THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_TYPE: the file''s fingerprint does not match the file' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO cur FROM admissions.iut_document d WHERE d.application_id = a.id AND d.kind = k.code AND d.superseded_at IS NULL;
    IF cur.status = 'ACCEPTED' THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_ACCEPTED: the Registry has accepted this document; it is not replaced' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.iut_document SET superseded_at = now(), superseded_by = v_id WHERE id = cur.id;
    INSERT INTO admissions.iut_document (id, application_id, kind, filename, content_type, bytes, sha256, stored, object_id)
    VALUES (v_id, a.id, k.code, coalesce(nullif(v_name, ''), 'document'), v_type, p_bytes, v_sha, CASE WHEN p_object IS NULL THEN 'BLOB' ELSE 'OBJECT' END, p_object);
    IF p_content IS NOT NULL THEN
        INSERT INTO admissions.iut_document_blob (document_id, content) VALUES (v_id, p_content);
    END IF;
    PERFORM admissions.iut_log(a.id, 'DOCUMENT_UPLOADED', a.state, a.state, k.label, true);
    RETURN v_id;
END $$;

CREATE FUNCTION admissions.iut_remove_document(p_app uuid, p_document uuid) RETURNS void LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; d admissions.iut_document;
BEGIN
    a := admissions.iut_mine(p_app);
    IF a.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN
        RAISE EXCEPTION 'IUT_STATE: documents change before the application is submitted, or when it is returned to you; this one is %', admissions.iut_state_words(a.state) USING ERRCODE = '23514';
    END IF;
    SELECT * INTO d FROM admissions.iut_document x WHERE x.id = p_document AND x.application_id = a.id AND x.superseded_at IS NULL;
    IF d.id IS NULL THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_UNKNOWN: no such document on this application' USING ERRCODE = 'P0002';
    END IF;
    IF d.status = 'ACCEPTED' THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_ACCEPTED: the Registry has accepted this document; it is not removed' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.iut_document SET superseded_at = now() WHERE id = d.id;
    PERFORM admissions.iut_log(a.id, 'DOCUMENT_REMOVED', a.state, a.state, (SELECT k.label FROM admissions.iut_document_kind k WHERE k.code = d.kind), true);
END $$;

CREATE FUNCTION admissions.iut_submit(p_app uuid, p_ip text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; v_missing text; v_rejected text; v_ev uuid;
BEGIN
    a := admissions.iut_mine(p_app);
    IF a.state NOT IN ('DRAFT', 'CORRECTION_REQUIRED') THEN
        RAISE EXCEPTION 'IUT_STATE: the application is %; it is submitted from a draft, or when it is returned to you', admissions.iut_state_words(a.state) USING ERRCODE = '23514';
    END IF;
    IF a.fee_settled_at IS NULL THEN
        RAISE EXCEPTION 'IUT_FEE_UNPAID: pay the application fee first; the application is submitted after it' USING ERRCODE = '23514';
    END IF;
    v_missing := (SELECT string_agg(k.label, '; ' ORDER BY k.ord, k.code) FROM admissions.iut_document_kind k
                   WHERE k.active AND k.required
                     AND NOT EXISTS (SELECT 1 FROM admissions.iut_document d WHERE d.application_id = a.id AND d.kind = k.code AND d.superseded_at IS NULL));
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'IUT_DOCUMENTS_MISSING: %', v_missing USING ERRCODE = '23514', HINT = 'Upload every document marked required, then submit';
    END IF;
    v_rejected := (SELECT string_agg(k.label, '; ' ORDER BY k.ord, k.code) FROM admissions.iut_document d JOIN admissions.iut_document_kind k ON k.code = d.kind
                    WHERE d.application_id = a.id AND d.superseded_at IS NULL AND d.status = 'REJECTED');
    IF v_rejected IS NOT NULL THEN
        RAISE EXCEPTION 'IUT_DOCUMENTS_REJECTED: replace %', v_rejected USING ERRCODE = '23514', HINT = 'The Registry''s note on each says why';
    END IF;
    -- no window check (D5): an application made before the closing is still submitted
    UPDATE admissions.iut_application
       SET state = 'SUBMITTED', submitted_at = coalesce(submitted_at, now()), last_submitted_at = now(), declaration_ip = nullif(btrim(coalesce(p_ip, '')), '')
     WHERE id = a.id;
    v_ev := admissions.iut_log(a.id, CASE WHEN a.submitted_at IS NULL THEN 'SUBMITTED' ELSE 'RESUBMITTED' END, a.state, 'SUBMITTED', NULL, true);
    PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'SUBMITTED', NULL, 'IUT:SUBMITTED:' || a.id || ':' || v_ev);
    RETURN admissions.iut_view(a.id, 'APPLICANT');
END $$;

CREATE FUNCTION admissions.iut_withdraw(p_app uuid, p_reason text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_ev uuid;
BEGIN
    a := admissions.iut_mine(p_app);
    -- the applicant withdraws until the department has assessed it. With the Registry for a decision (a recommendation, a decline or
    -- an approval: WITH_REGISTRY, D11) the withdrawal is asked of the Registry in all three alike, so neither the answer nor its words
    -- tell an approval from a recommendation; the Registry ends it with the applicant's request as its reason
    IF a.state NOT IN ('DRAFT', 'SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD') THEN
        RAISE EXCEPTION 'IUT_STATE: the application is %; it is no longer withdrawn here', admissions.iut_state_words(a.state) USING ERRCODE = '23514',
            HINT = CASE admissions.iut_state_shown(a.state)
                        WHEN 'WITH_REGISTRY' THEN 'Write to the Registry to withdraw it; the Registry decides it now'
                        WHEN 'ADMITTED' THEN 'An admitted application stays as it is: you are a student of the University now'
                        WHEN 'REJECTED' THEN 'A refused application stays as it is'
                        ELSE 'It is withdrawn already' END;
    END IF;
    IF length(coalesce(v_reason, '')) > 500 THEN
        RAISE EXCEPTION 'IUT_REASON: a reason for withdrawing is at most 500 characters' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.iut_application SET state = 'WITHDRAWN', withdrawn_at = now(), withdrawn_reason = v_reason WHERE id = a.id;
    v_ev := admissions.iut_log(a.id, 'WITHDRAWN', a.state, 'WITHDRAWN', v_reason, true);
    PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'WITHDRAWN', NULL, 'IUT:WITHDRAWN:' || a.id || ':' || v_ev);
    RETURN admissions.iut_view(a.id, 'APPLICANT');
END $$;

-- ── 9 · the Registry's desk and the department's ─────────────────────────────────────────────────────────────────────────
CREATE FUNCTION admissions.iut_review_document(p_document uuid, p_verdict text, p_note text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        d admissions.iut_document; a admissions.iut_application; v text := upper(btrim(coalesce(p_verdict, ''))); v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    PERFORM admissions.iut_keeper();
    SELECT * INTO d FROM admissions.iut_document WHERE id = p_document AND superseded_at IS NULL;
    IF d.id IS NULL THEN
        RAISE EXCEPTION 'IUT_DOCUMENT_UNKNOWN: no such current document' USING ERRCODE = 'P0002';
    END IF;
    SELECT * INTO a FROM admissions.iut_application WHERE id = d.application_id FOR UPDATE;
    IF a.state <> 'SUBMITTED' THEN
        RAISE EXCEPTION 'IUT_STATE: documents are checked while the application is submitted; it is %', lower(a.state) USING ERRCODE = '23514';
    END IF;
    IF v NOT IN ('ACCEPTED', 'REJECTED') THEN
        RAISE EXCEPTION 'IUT_REVIEW_VERDICT: a document is ACCEPTED or REJECTED' USING ERRCODE = '23514';
    END IF;
    IF v = 'REJECTED' AND length(coalesce(v_note, '')) < 10 THEN
        RAISE EXCEPTION 'IUT_REVIEW_NOTE: say why the document is rejected, ten characters or more; the applicant reads it' USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(v_note, '')) > 1000 THEN
        RAISE EXCEPTION 'IUT_REVIEW_NOTE: a note on a document is at most 1000 characters' USING ERRCODE = '23514';
    END IF;
    UPDATE admissions.iut_document SET status = v, review_note = v_note, reviewed_by = who, reviewed_office = office, reviewed_at = now() WHERE id = d.id;
    PERFORM admissions.iut_log(a.id, 'DOCUMENT_' || v, a.state, a.state,
        (SELECT k.label FROM admissions.iut_document_kind k WHERE k.code = d.kind) || coalesce(': ' || v_note, ''), false);
    RETURN admissions.iut_view(a.id, 'OFFICE');
END $$;

CREATE FUNCTION admissions.iut_act(p_app uuid, p_action text, p_note text, p_expected text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        a admissions.iut_application; v_action text := upper(btrim(coalesce(p_action, ''))); v_note text := nullif(btrim(coalesce(p_note, '')), '');
        v_ev uuid; v_unchecked text; v_docs text;
BEGIN
    PERFORM admissions.iut_keeper();
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN
        RAISE EXCEPTION 'IUT_APPLICATION_UNKNOWN: no such transfer application' USING ERRCODE = 'P0002';
    END IF;
    IF v_action NOT IN ('SEND_TO_HOD', 'RETURN', 'SEND_BACK_TO_HOD', 'REJECT') THEN
        RAISE EXCEPTION 'IUT_ACTION: the Registry sends an application to the Head of Department, returns it to the applicant, sends it back to the Head of Department or rejects it'
            USING ERRCODE = '23514';
    END IF;
    PERFORM admissions.iut_expect(a.state, p_expected);
    IF length(coalesce(v_note, '')) > 2000 THEN
        RAISE EXCEPTION 'IUT_NOTE: a note is at most 2000 characters' USING ERRCODE = '23514';
    END IF;

    IF v_action = 'SEND_TO_HOD' THEN
        IF a.state <> 'SUBMITTED' THEN
            RAISE EXCEPTION 'IUT_STATE: an application goes to the Head of Department once submitted and checked; it is %', lower(a.state) USING ERRCODE = '23514';
        END IF;
        v_unchecked := admissions.iut_unchecked(a.id);
        IF v_unchecked IS NOT NULL THEN
            RAISE EXCEPTION 'IUT_DOCUMENTS_UNCHECKED: %', v_unchecked USING ERRCODE = '23514',
                HINT = 'Accept each document, or return the application to the applicant for the ones that are not right';
        END IF;
        UPDATE admissions.iut_application SET state = 'WITH_HOD' WHERE id = a.id;
        v_ev := admissions.iut_log(a.id, 'SENT_TO_HOD', a.state, 'WITH_HOD', v_note, true);
        PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'WITH_HOD', NULL, 'IUT:WITH_HOD:' || a.id || ':' || v_ev);
        PERFORM admissions.iut_tell_desk(a.id, v_ev);

    ELSIF v_action = 'RETURN' THEN
        IF a.state <> 'SUBMITTED' THEN
            RAISE EXCEPTION 'IUT_STATE: an application is returned to the applicant while it is submitted; it is %', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF length(coalesce(v_note, '')) < 10 THEN
            RAISE EXCEPTION 'IUT_NOTE: say what the applicant corrects, ten characters or more; they read it' USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.iut_application SET state = 'CORRECTION_REQUIRED', registry_by = who, registry_office = office, registry_at = now(), registry_note = v_note
         WHERE id = a.id;
        v_ev := admissions.iut_log(a.id, 'RETURNED', a.state, 'CORRECTION_REQUIRED', v_note, true);
        v_docs := (SELECT string_agg('- ' || k.label || ': ' || d.review_note, E'\n' ORDER BY k.ord, k.code)
                     FROM admissions.iut_document d JOIN admissions.iut_document_kind k ON k.code = d.kind
                    WHERE d.application_id = a.id AND d.superseded_at IS NULL AND d.status = 'REJECTED');
        PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'CORRECTION_REQUIRED',
            jsonb_build_object('NOTE', v_note, 'DOCUMENTS', coalesce(v_docs, 'None: the note above says what to correct')),
            'IUT:CORRECTION_REQUIRED:' || a.id || ':' || v_ev);

    ELSIF v_action = 'SEND_BACK_TO_HOD' THEN
        IF a.state NOT IN ('RECOMMENDED', 'NOT_RECOMMENDED') THEN
            RAISE EXCEPTION 'IUT_STATE: an application goes back to the Head of Department after a recommendation; it is %', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF length(coalesce(v_note, '')) < 10 THEN
            RAISE EXCEPTION 'IUT_NOTE: say what the Head of Department looks at again, ten characters or more' USING ERRCODE = '23514';
        END IF;
        -- the recommendation sent back is kept in the history
        v_ev := admissions.iut_log(a.id, 'SENT_BACK_TO_HOD', a.state, 'WITH_HOD',
            v_note || ' (was: ' || CASE a.hod_decision WHEN 'ACCEPT' THEN 'recommended at ' || a.hod_level || ' Level' ELSE 'not recommended' END
                   || coalesce(' — ' || a.hod_note, '') || ', ' || coalesce(people.officer_name(a.hod_by), a.hod_office, 'the department') || ')', false);
        UPDATE admissions.iut_application
           SET state = 'WITH_HOD', hod_decision = NULL, hod_level = NULL, hod_note = NULL, hod_by = NULL, hod_office = NULL, hod_at = NULL
         WHERE id = a.id;
        PERFORM admissions.iut_tell_desk(a.id, v_ev);

    ELSE   -- REJECT
        -- a draft too: an application made under another person's JAMB number holds the number (ux_iut_app_live_jamb) in every
        -- session until it ends, and nothing but its maker's own withdrawal ended it; the Registry ends it, its reason told to the
        -- account that made it, and the number is free for its owner (a reference drawn on it is no longer taken; paid, owed back).
        -- Never for lateness: a started application has no deadline (D5), and a fee paid on a draft so ended is not refunded (D19)
        IF a.state NOT IN ('DRAFT', 'SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD', 'RECOMMENDED', 'NOT_RECOMMENDED') THEN
            RAISE EXCEPTION 'IUT_STATE: the application is %; it is not rejected now', lower(a.state) USING ERRCODE = '23514';
        END IF;
        IF length(coalesce(v_note, '')) < 10 THEN
            RAISE EXCEPTION 'IUT_NOTE: say why the application is rejected, ten characters or more; the applicant reads it' USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.iut_application SET state = 'REJECTED', registry_by = who, registry_office = office, registry_at = now(), registry_note = v_note
         WHERE id = a.id;
        v_ev := admissions.iut_log(a.id, 'REJECTED', a.state, 'REJECTED', v_note, true);
        PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'REJECTED', jsonb_build_object('REASON', v_note), 'IUT:REJECTED:' || a.id || ':' || v_ev);
    END IF;
    RETURN admissions.iut_view(a.id, 'OFFICE');
END $$;

CREATE FUNCTION admissions.iut_recommend(p_app uuid, p_accept boolean, p_level integer, p_note text, p_expected text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        a admissions.iut_application; v_note text := nullif(btrim(coalesce(p_note, '')), ''); v_to text;
BEGIN
    IF who IS NULL OR coalesce(office, '-') NOT IN ('hod', 'dean', 'super') THEN
        RAISE EXCEPTION 'IUT_HOD_OFFICE: a transfer application is recommended by the Head of Department' USING ERRCODE = '42501';
    END IF;
    IF NOT admissions.iut_hod_of(p_app) THEN
        RAISE EXCEPTION 'IUT_HOD_OTHER_DEPARTMENT: the programme applied for is in another department; its own Head of Department recommends' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app FOR UPDATE;
    PERFORM admissions.iut_expect(a.state, p_expected);
    IF a.state <> 'WITH_HOD' THEN
        RAISE EXCEPTION 'IUT_STATE: the application is %; the Head of Department recommends while it is with the department', lower(a.state) USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(v_note, '')) > 2000 THEN
        RAISE EXCEPTION 'IUT_NOTE: an assessment note is at most 2000 characters' USING ERRCODE = '23514';
    END IF;
    IF coalesce(p_accept, false) THEN
        IF p_level IS NULL THEN
            RAISE EXCEPTION 'IUT_LEVEL: give the level you recommend the student for' USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM admissions.iut_line l WHERE l.session = a.session AND l.programme_code = a.programme_code AND l.level = p_level) THEN
            RAISE EXCEPTION 'IUT_LEVEL_NOT_OPEN: % Level of this programme is not open to transfer students in %', p_level, a.session USING ERRCODE = '23514',
                HINT = 'Recommend at a level the window lists for the programme';
        END IF;
        IF NOT coalesce(p_level = ANY (people.programme_levels(a.programme_code)), false) THEN
            RAISE EXCEPTION 'IUT_LEVEL: % Level is not a level of the programme', p_level USING ERRCODE = '23514';
        END IF;
        v_to := 'RECOMMENDED';
    ELSE
        IF length(coalesce(v_note, '')) < 10 THEN
            RAISE EXCEPTION 'IUT_REASON: say why the application is not recommended, ten characters or more' USING ERRCODE = '23514';
        END IF;
        v_to := 'NOT_RECOMMENDED';
    END IF;
    UPDATE admissions.iut_application
       SET state = v_to, hod_decision = CASE WHEN v_to = 'RECOMMENDED' THEN 'ACCEPT' ELSE 'DECLINE' END,
           hod_level = CASE WHEN v_to = 'RECOMMENDED' THEN p_level END, hod_note = v_note, hod_by = who, hod_office = office, hod_at = now()
     WHERE id = a.id;
    PERFORM admissions.iut_log(a.id, v_to, a.state, v_to,
        CASE WHEN v_to = 'RECOMMENDED' THEN 'At ' || p_level || ' Level' || coalesce(' — ' || v_note, '') ELSE v_note END, false);
    RETURN admissions.iut_view(a.id, 'HOD');
END $$;

CREATE FUNCTION admissions.iut_set_university(p_app uuid, p_code text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; v_code text := upper(btrim(coalesce(p_code, ''))); v_name text;
BEGIN
    PERFORM admissions.iut_keeper();
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN
        RAISE EXCEPTION 'IUT_APPLICATION_UNKNOWN: no such transfer application' USING ERRCODE = 'P0002';
    END IF;
    IF a.state NOT IN ('SUBMITTED', 'CORRECTION_REQUIRED', 'WITH_HOD', 'RECOMMENDED', 'NOT_RECOMMENDED') THEN
        RAISE EXCEPTION 'IUT_STATE: the university is set on an application being checked or decided; it is %', lower(a.state) USING ERRCODE = '23514';
    END IF;
    SELECT u.name INTO v_name FROM ref.university u WHERE u.code = v_code AND u.active;
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'IUT_UNIVERSITY_UNKNOWN: % is not a university on the list', coalesce(nullif(v_code, ''), 'the code given') USING ERRCODE = '23514',
            HINT = 'Add it under Inter-University Transfer → Universities first';
    END IF;
    UPDATE admissions.iut_application SET university_code = v_code WHERE id = a.id;   -- the name the applicant typed is kept
    PERFORM admissions.iut_log(a.id, 'UNIVERSITY_SET', a.state, a.state, v_code || ' — ' || v_name || coalesce(' (typed: ' || a.university_named || ')', ''), false);
    RETURN admissions.iut_view(a.id, 'OFFICE');
END $$;

/* the V763 form's row for this application, under people.transfer_cell's names; levels and numbers as text, as the form sends them */
CREATE FUNCTION admissions.iut_transfer_row(p_app uuid, p_level integer DEFAULT NULL) RETURNS jsonb LANGUAGE sql STABLE AS $$
    SELECT jsonb_build_object(
        'direction', 'INCOMING', 'jamb_reg_no', a.jamb_reg_no, 'surname', a.surname, 'other_names', a.other_names, 'sex', a.sex,
        'date_of_birth', to_char(a.date_of_birth, 'YYYY-MM-DD'), 'email', acc.email, 'phone', acc.phone,
        'faculty', p.faculty_code, 'dept', p.dept_code, 'programme', a.programme_code,
        'level', coalesce(p_level, a.hod_level, a.level)::text,
        'university_code', coalesce(a.university_code, ''), 'other_programme', a.other_programme, 'other_level', a.other_level::text,
        'other_matric_no', a.other_matric_no, 'other_entry_session', a.other_entry_session, 'other_cgpa', a.other_cgpa::text,
        'other_cgpa_scale', a.other_cgpa_scale::text,
        'documents', coalesce((SELECT jsonb_agg(DISTINCT k.transfer_code ORDER BY k.transfer_code)
                                 FROM admissions.iut_document d JOIN admissions.iut_document_kind k ON k.code = d.kind
                                WHERE d.application_id = a.id AND d.superseded_at IS NULL AND d.status = 'ACCEPTED' AND k.transfer_code IS NOT NULL), '[]'::jsonb),
        'remarks', left('Applied online: ' || a.application_no
                        || CASE WHEN a.hod_decision = 'ACCEPT' THEN '. Head of Department: recommended for ' || a.hod_level || ' Level' || coalesce(' — ' || a.hod_note, '')
                                ELSE '' END, 2000))
      FROM admissions.iut_application a
      JOIN admissions.iut_account acc ON acc.id = a.account_id
      JOIN ref.programme p ON p.code = a.programme_code
     WHERE a.id = p_app;
$$;
COMMENT ON FUNCTION admissions.iut_transfer_row(uuid, integer) IS
  'V766: an online transfer application as the V763 form''s incoming row (people.transfer_cell''s names, levels and numbers as text): the particulars, the account''s e-mail and phone, the placement at the level given (else the Head of Department''s, else the one applied for), the V763 codes of the documents the Registry accepted, and the remarks.';

CREATE FUNCTION admissions.iut_approve(p_app uuid, p_approval_ref text, p_note text, p_expected text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        a admissions.iut_application; l admissions.iut_line; v_unchecked text; v_taken integer; v_ref text := nullif(btrim(coalesce(p_approval_ref, '')), '');
        v_note text := nullif(btrim(coalesce(p_note, '')), ''); r jsonb;
BEGIN
    PERFORM admissions.iut_keeper();
    SELECT * INTO a FROM admissions.iut_application WHERE id = p_app FOR UPDATE;
    IF a.id IS NULL THEN
        RAISE EXCEPTION 'IUT_APPLICATION_UNKNOWN: no such transfer application' USING ERRCODE = 'P0002';
    END IF;
    PERFORM admissions.iut_expect(a.state, p_expected);
    IF a.state <> 'RECOMMENDED' THEN
        RAISE EXCEPTION 'IUT_STATE: an application is approved once the Head of Department recommends it at a level; it is %', lower(a.state) USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(v_ref, '')) > 120 THEN
        RAISE EXCEPTION 'IUT_APPROVAL_REF: the approval reference is at most 120 characters' USING ERRCODE = '23514';
    END IF;
    IF length(coalesce(v_note, '')) > 2000 THEN
        RAISE EXCEPTION 'IUT_NOTE: a note is at most 2000 characters' USING ERRCODE = '23514';
    END IF;
    -- the current documents only (SPEC §3.6 step 2): a kind made required after the submission does not hold the approval
    v_unchecked := admissions.iut_unchecked(a.id, false);
    IF v_unchecked IS NOT NULL THEN
        RAISE EXCEPTION 'IUT_DOCUMENTS_UNCHECKED: %', v_unchecked USING ERRCODE = '23514';
    END IF;
    IF a.university_code IS NULL THEN
        RAISE EXCEPTION 'IUT_UNIVERSITY_NOT_LISTED: % is not on the list of universities', coalesce(a.university_named, 'the university named') USING ERRCODE = '23514',
            HINT = 'Add it under Inter-University Transfer → Universities, then set it on the application';
    END IF;
    -- the places of the line at the level recommended, held while this approval is made
    SELECT * INTO l FROM admissions.iut_line WHERE session = a.session AND programme_code = a.programme_code AND level = a.hod_level FOR UPDATE;
    IF l.session IS NULL THEN
        RAISE EXCEPTION 'IUT_LEVEL_NOT_OPEN: % Level of this programme is not open to transfer students in %', a.hod_level, a.session USING ERRCODE = '23514';
    END IF;
    IF l.places IS NOT NULL THEN
        v_taken := (SELECT count(*) FROM admissions.iut_application x
                     WHERE x.session = a.session AND x.programme_code = a.programme_code AND x.hod_level = a.hod_level AND x.state IN ('APPROVED', 'ADMITTED') AND x.id <> a.id);
        IF v_taken >= l.places THEN
            RAISE EXCEPTION 'IUT_PLACES_FILLED: the % places of %, % Level are taken', l.places, (SELECT p.name FROM ref.programme p WHERE p.code = a.programme_code), a.hod_level
                USING ERRCODE = '23514';
        END IF;
    END IF;
    -- a student of another university is never on the register already: V763's check would record the transfer on the record that
    -- holds the JAMB number at that placement (RECORD_ON_EXISTING, only a warning on its form), and the application would then admit
    -- the applicant onto that student's record — the number, the notice, the password at the student door
    IF people.university_transfer_form_check(admissions.iut_transfer_row(a.id, a.hod_level), a.session)->>'action' = 'RECORD_ON_EXISTING' THEN
        RAISE EXCEPTION 'IUT_STUDENT_EXISTS: the JAMB number % is a student''s of this University already; an online application never admits onto a record on the register',
            a.jamb_reg_no USING ERRCODE = '23514',
            HINT = 'Reject the application, or take the record up with the Registry''s records first';
    END IF;
    -- exactly the V763 form's call; the approving officer prepares it, another decides it (V588)
    r := people.register_university_transfer(admissions.iut_transfer_row(a.id, a.hod_level), a.session,
             'Online inter-university transfer application ' || a.application_no || coalesce(': ' || v_note, ''), v_ref);
    UPDATE people.university_transfer_batch SET source = 'APPLICATION' WHERE id = (r->>'id')::uuid;
    UPDATE admissions.iut_application
       SET state = 'APPROVED', transfer_id = (r->>'transferId')::uuid, registry_by = who, registry_office = office, registry_at = now(), registry_note = v_note,
           approval_ref = v_ref
     WHERE id = a.id;
    PERFORM admissions.iut_log(a.id, 'APPROVED', a.state, 'APPROVED', 'Batch ' || (r->>'ref') || coalesce(' — ' || v_note, ''), false, (r->>'transferId')::uuid);
    RETURN admissions.iut_view(a.id, 'OFFICE') || jsonb_build_object('batchId', r->>'id', 'batchRef', r->>'ref', 'transferId', r->>'transferId');
END $$;
COMMENT ON FUNCTION admissions.iut_approve(uuid, text, text, text) IS
  'V766: the Registry''s approval of a recommended application: the current documents all accepted, the university on the list, a place free at the level recommended, the JAMB number no student''s on the register (IUT_STUDENT_EXISTS); registered exactly as V763''s form registers a transfer (people.register_university_transfer), a batch of one with source APPLICATION, prepared by the approving officer and decided by another (V588).';

/* the second officer's decision on the transfer moves the application: approved, admitted (the applicant told); rejected, back to the
   Registry's desk, untold (the note is written for officers). A transfer completed onto a record already on the register (a student
   given the JAMB number between the approval and the decision: V588 records it on that record, created_student false) is refused here:
   the applicant is never admitted onto another student's record */
CREATE FUNCTION admissions.iut_transfer_decided() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a admissions.iut_application; v_ev uuid; s people.student;
BEGIN
    SELECT * INTO a FROM admissions.iut_application WHERE transfer_id = NEW.id AND state = 'APPROVED' FOR UPDATE;
    IF a.id IS NULL THEN RETURN NULL; END IF;
    IF NEW.status = 'COMPLETED' THEN
        IF NOT NEW.created_student THEN
            RAISE EXCEPTION 'IUT_STUDENT_EXISTS: the transfer of online application % would be recorded on a student already on the register; an online application never admits onto one',
                a.application_no USING ERRCODE = '23514',
                HINT = 'Reject the transfer: the application goes back to the Registry''s desk';
        END IF;
        SELECT * INTO s FROM people.student WHERE id = NEW.student_id;
        -- the record takes the account's e-mail and phone as they stand now: the transfer row was taken at the approval, and the
        -- applicant may change them while the approval waits (iut_update); the student's notices and password resets go there
        INSERT INTO people.student_contact AS sc (student_id, email, phone, updated_at)
        SELECT NEW.student_id, acc.email, acc.phone, now() FROM admissions.iut_account acc WHERE acc.id = a.account_id
        ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone, updated_at = now()
         WHERE (sc.email, sc.phone) IS DISTINCT FROM (EXCLUDED.email, EXCLUDED.phone);
        UPDATE admissions.iut_application SET state = 'ADMITTED', student_id = NEW.student_id WHERE id = a.id;
        v_ev := admissions.iut_log(a.id, 'ADMITTED', 'APPROVED', 'ADMITTED', 'Admission number ' || coalesce(s.matric_no, s.admission_no, '—'), true, NEW.id);
        PERFORM admissions.iut_tell(a.id, 'IUT_APPLICATION', 'ADMITTED',
            jsonb_build_object('ADMISSION_NUMBER', coalesce(s.matric_no, s.admission_no), 'PROGRAMME', (SELECT p.name FROM ref.programme p WHERE p.code = NEW.programme_code),
                               'LEVEL', a.hod_level::text, 'SESSION', a.session),
            'IUT:ADMITTED:' || a.id || ':' || v_ev);
    ELSIF NEW.status = 'REJECTED' THEN
        UPDATE admissions.iut_application SET state = 'RECOMMENDED', transfer_id = NULL WHERE id = a.id;
        PERFORM admissions.iut_log(a.id, 'TRANSFER_REJECTED', 'APPROVED', 'RECOMMENDED', NEW.decision_note, false, NEW.id);
    END IF;
    RETURN NULL;
END $$;

-- ── 10 · the payment, joined wherever the JUPEB store is (D2) ────────────────────────────────────────────────────────────
/* each existing function is changed from its live text (V762's restatements of the refund desk's two included), every piece found
   once or the migration stops; and the function as it then stands must be exactly that text, or it stops too (an edit that left
   the function as it was, or made another beside it, never passes unseen) */
CREATE FUNCTION pg_temp.v766_edit(p_fn regprocedure, p_edits text[]) RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); i integer; n integer;
BEGIN
    IF coalesce(array_length(p_edits, 1), 0) = 0 OR array_length(p_edits, 1) % 2 <> 0 THEN
        RAISE EXCEPTION 'V766: the edits of % come in pairs', p_fn;
    END IF;
    FOR i IN 1 .. array_length(p_edits, 1) / 2 LOOP
        n := (length(d) - length(replace(d, p_edits[2 * i - 1], ''))) / length(p_edits[2 * i - 1]);
        IF n <> 1 THEN
            RAISE EXCEPTION 'V766: % is not as main left it (% found % times)', p_fn, left(p_edits[2 * i - 1], 80), n;
        END IF;
        d := replace(d, p_edits[2 * i - 1], p_edits[2 * i]);
    END LOOP;
    EXECUTE d;
    IF pg_get_functiondef(p_fn) IS DISTINCT FROM d THEN
        RAISE EXCEPTION 'V766: % did not take its edit', p_fn;
    END IF;
END $$;

SELECT pg_temp.v766_edit('finance.reference_state(text)'::regprocedure, ARRAY[
$a$    SELECT 'JUPEB_' || j.kind, j.amount, j.confirmed_at, j.expires_at, j.channel, NULL FROM jupeb.fee_reference j WHERE j.reference = upper(btrim(p_reference))$a$,
$b$    SELECT 'JUPEB_' || j.kind, j.amount, j.confirmed_at, j.expires_at, j.channel, NULL FROM jupeb.fee_reference j WHERE j.reference = upper(btrim(p_reference))
    UNION ALL
    -- V766: an inter-university transfer applicant's fee
    SELECT 'IUT_APPLICATION', f.amount, f.confirmed_at, f.expires_at, f.channel, f.receipt_no FROM admissions.iut_fee_reference f WHERE f.reference = upper(btrim(p_reference))$b$]);

SELECT pg_temp.v766_edit('finance.quickteller_link(text)'::regprocedure, ARRAY[
$a$        UNION ALL SELECT j.reference, j.amount FROM jupeb.fee_reference j WHERE upper(j.reference) = v_ref) x$a$,
$b$        UNION ALL SELECT j.reference, j.amount FROM jupeb.fee_reference j WHERE upper(j.reference) = v_ref
        -- V766: an inter-university transfer applicant's fee
        UNION ALL SELECT i.reference, i.amount FROM admissions.iut_fee_reference i WHERE i.reference = v_ref) x$b$]);

SELECT pg_temp.v766_edit('finance.paydirect_customer(text)'::regprocedure, ARRAY[
$a$b finance.paydirect_biller; v_why text; jf jupeb.fee_reference; ja jupeb.application;$a$,
$b$b finance.paydirect_biller; v_why text; jf jupeb.fee_reference; ja jupeb.application; ir admissions.iut_fee_reference; ia admissions.iut_application;$b$,
$a$    RETURN QUERY SELECT false, 'No reference like this was generated by the portal', v_ref,$a$,
$b$    -- V766: an inter-university transfer applicant's fee — payable only while the application is a draft with the fee unsettled
    SELECT * INTO ir FROM admissions.iut_fee_reference x WHERE x.reference = v_ref;
    IF FOUND THEN
        SELECT * INTO ia FROM admissions.iut_application x WHERE x.id = ir.application_id;
        v_why := CASE WHEN ir.confirmed_at IS NOT NULL THEN 'Already paid'
                      WHEN ir.expires_at < now() THEN 'Expired: a new reference is generated on the portal, free of charge'
                      WHEN NOT admissions.iut_reference_payable(ir.reference) THEN 'The application fee is already settled or no longer charged, or the application was withdrawn or decided' END;
        RETURN QUERY SELECT v_why IS NULL, v_why, ir.reference, ia.surname, ia.other_names, ia.application_no, ir.amount,
            'Inter-university transfer application fee ' || ia.session, b.scope, b.biller_code;
        RETURN;
    END IF;

    RETURN QUERY SELECT false, 'No reference like this was generated by the portal', v_ref,$b$]);

SELECT pg_temp.v766_edit('finance.paydirect_biller_of_reference(text)'::regprocedure, ARRAY[
$a$         WHERE upper(fr.reference) = v_ref) x$a$,
$b$         WHERE upper(fr.reference) = v_ref
        UNION ALL
        -- V766: the programme an inter-university transfer applicant applies for (a College of Health Sciences one pays the CHS biller)
        SELECT ia.programme_code FROM admissions.iut_fee_reference ir JOIN admissions.iut_application ia ON ia.id = ir.application_id
         WHERE ir.reference = v_ref) x$b$]);

SELECT pg_temp.v766_edit('finance.import_paydirect(jsonb)'::regprocedure, ARRAY[
$a$            UNION ALL SELECT j.amount, 'JUPEB' FROM jupeb.fee_reference j WHERE upper(j.reference) = v_prn) x$a$,
$b$            UNION ALL SELECT j.amount, 'JUPEB' FROM jupeb.fee_reference j WHERE upper(j.reference) = v_prn
            -- V766: an inter-university transfer applicant's fee
            UNION ALL SELECT i.amount, 'IUT' FROM admissions.iut_fee_reference i WHERE i.reference = v_prn) x$b$,
$a$                PERFORM jupeb.confirm_fee(v_prn, coalesce(v_chan, 'Quickteller PayDirect'));$a$,
$b$                PERFORM jupeb.confirm_fee(v_prn, coalesce(v_chan, 'Quickteller PayDirect'));
            ELSIF v_where = 'IUT' THEN
                -- V766: the settlement's own Log Id kept, so a bank credit for the reference is told to be this payment or another
                PERFORM admissions.iut_confirm_fee(v_prn, 'PAYDIRECT', v_note, ARRAY[v_rrn]);$b$]);

SELECT pg_temp.v766_edit('finance.paydirect_claims(integer,text)'::regprocedure, ARRAY[
$a$ja.surname || ', ' || concat_ws(' ', ja.first_name, ja.middle_name)),$a$,
$b$ja.surname || ', ' || concat_ws(' ', ja.first_name, ja.middle_name), ia.surname || ', ' || ia.other_names),$b$,
$a$coalesce(s.matric_no, s.admission_no, ap.application_no, ja.application_no),$a$,
$b$coalesce(s.matric_no, s.admission_no, ap.application_no, ja.application_no, ia.application_no),$b$,
$a$          LEFT JOIN jupeb.application ja ON ja.id = jf.application_id$a$,
$b$          LEFT JOIN jupeb.application ja ON ja.id = jf.application_id
          -- V766: an inter-university transfer applicant's fee
          LEFT JOIN admissions.iut_fee_reference ifr ON ifr.reference = cl.reference
          LEFT JOIN admissions.iut_application ia ON ia.id = ifr.application_id$b$]);

SELECT pg_temp.v766_edit('finance.paydirect_claim_mark(text,boolean,text)'::regprocedure, ARRAY[
$a$vars jsonb; v_student uuid; v_app uuid; v_jupeb uuid;$a$,
$b$vars jsonb; v_student uuid; v_app uuid; v_jupeb uuid; v_iut uuid;$b$,
$a$    SELECT application_id INTO v_jupeb FROM jupeb.fee_reference WHERE upper(reference) = c.reference;$a$,
$b$    SELECT application_id INTO v_jupeb FROM jupeb.fee_reference WHERE upper(reference) = c.reference;
    SELECT application_id INTO v_iut FROM admissions.iut_fee_reference WHERE reference = c.reference;   -- V766$b$,
$a$                   c.reference, c.payment_log_id, to_char(c.paid_on, 'FMDD Mon YYYY'), c.not_found_note));
    END IF;$a$,
$b$                   c.reference, c.payment_log_id, to_char(c.paid_on, 'FMDD Mon YYYY'), c.not_found_note));
    ELSIF v_iut IS NOT NULL THEN
        PERFORM admissions.iut_tell(v_iut, 'PAYDIRECT_RECEIPT_NOT_FOUND', NULL, vars, v_event);   -- V766
    END IF;$b$]);

SELECT pg_temp.v766_edit('finance.tell_payers(text)'::regprocedure, ARRAY[
$a$v_jupeb uuid; v_kind text;$a$,
$b$v_jupeb uuid; v_iut uuid; v_kind text;$b$,
$a$v_student := NULL; v_app := NULL; v_pg := NULL; v_jupeb := NULL; n := 0;$a$,
$b$v_student := NULL; v_app := NULL; v_pg := NULL; v_jupeb := NULL; v_iut := NULL; n := 0;$b$,
$a$        IF v_student IS NULL AND v_app IS NULL AND v_pg IS NULL THEN SELECT application_id INTO v_jupeb FROM jupeb.fee_reference WHERE upper(reference) = w.reference; END IF;$a$,
$b$        IF v_student IS NULL AND v_app IS NULL AND v_pg IS NULL THEN SELECT application_id INTO v_jupeb FROM jupeb.fee_reference WHERE upper(reference) = w.reference; END IF;
        -- V766: an inter-university transfer applicant's fee
        IF v_student IS NULL AND v_app IS NULL AND v_pg IS NULL AND v_jupeb IS NULL THEN
            SELECT application_id INTO v_iut FROM admissions.iut_fee_reference WHERE reference = w.reference;
        END IF;$b$,
$a$WHEN v_jupeb IS NOT NULL THEN 'JUPEB' END;$a$,
$b$WHEN v_jupeb IS NOT NULL THEN 'JUPEB' WHEN v_iut IS NOT NULL THEN 'IUT_APPLICANT' END;$b$,
$a$        ELSIF v_app IS NOT NULL THEN
            n := platform.tell_applicant(v_app, v_key, NULL, vars, 'payer-told:' || w.case_code || ':' || w.reference);$a$,
$b$        ELSIF v_app IS NOT NULL THEN
            n := platform.tell_applicant(v_app, v_key, NULL, vars, 'payer-told:' || w.case_code || ':' || w.reference);
        ELSIF v_iut IS NOT NULL THEN
            n := admissions.iut_tell(v_iut, v_key, NULL, vars, 'payer-told:' || w.case_code || ':' || w.reference);   -- V766$b$]);

SELECT pg_temp.v766_edit('finance.day_book(date,date)'::regprocedure, ARRAY[
$a$     WHERE j.confirmed_at IS NOT NULL AND j.confirmed_at::date BETWEEN p_from AND p_to
    ORDER BY 2 DESC$a$,
$b$     WHERE j.confirmed_at IS NOT NULL AND j.confirmed_at::date BETWEEN p_from AND p_to
    UNION ALL
    -- V766: an inter-university transfer applicant's fee
    SELECT f.reference, f.confirmed_at, a.surname || ', ' || a.other_names, a.application_no, 'Inter-university transfer application fee',
           f.amount, f.channel, f.receipt_no, f.note, f.session
      FROM admissions.iut_fee_reference f JOIN admissions.iut_application a ON a.id = f.application_id
     WHERE f.confirmed_at IS NOT NULL AND f.confirmed_at::date BETWEEN p_from AND p_to
    ORDER BY 2 DESC$b$]);

/* whether an identifier can be one payment's own: it holds a digit, and its letters and digits are neither the portal reference's
   nor any run of them — the reference itself, the reference written short ('IUTAPP-2026-000017', '2026/000017') or a piece of it
   (its prefix, its year). Every payment made for a reference may quote it, so it never tells one payment from another */
CREATE FUNCTION finance.iut_payment_id(p_id text, p_reference text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(finance.log_id_key(p_id) ~ '[0-9]'
                    AND strpos(coalesce(finance.log_id_key(p_reference), ''), finance.log_id_key(p_id)) = 0, false);
$$;
COMMENT ON FUNCTION finance.iut_payment_id(text, text) IS
  'V766: whether an identifier can be one payment''s own: it holds a digit and is neither the portal reference nor any run of its letters and digits (the reference written short, or a piece of it), which every payment for the reference may quote. Read by finance.iut_gateway_names_credit.';

/* whether one of the identifiers the gateway or the collections import gave the confirmed payment (its gateway_refs) is on the
   settlement row or the collections line a bank credit came from, each compared by finance.log_id_key, never the portal reference or
   a piece of it (finance.iut_payment_id):
   · a settlement row: its Log Id, payment reference or transaction reference — Interswitch's own fields (WebPAY's
     '<reference>-A<n>' there is the transaction reference Interswitch settled);
   · a collections line: only its bank reference, the bank's own field, equal to the identifier. Never its narration: that is the
     payer's own free text, and a payer who pays again by transfer may quote the first payment's receipt (its Log Id, its RRN, the
     card's '<reference>-A2'), which would post the second payment as nothing. Never a bank reference that is a bare number shorter
     than an RRN's twelve digits (a teller's number, which another bank may give another payment), nor one that holds the portal
     reference (WebPAY's '<reference>-A<n>', which a payer may copy from the card's receipt). A line carrying the identifier among
     other words is not equal to it, and is checked by the Bursary first like any other */
CREATE FUNCTION finance.iut_gateway_names_credit(p_ids text[], p_reference text, p_credit uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM unnest(p_ids) g(id)
         WHERE finance.iut_payment_id(g.id, p_reference)
           AND (EXISTS (SELECT 1 FROM finance.settlement_item s WHERE s.bank_credit_id = p_credit
                           AND finance.log_id_key(g.id) IN (finance.log_id_key(s.log_id), finance.log_id_key(s.payment_ref), finance.log_id_key(s.txn_ref)))
                OR EXISTS (SELECT 1 FROM finance.bank_statement_line l WHERE l.bank_credit_id = p_credit
                              AND finance.log_id_key(l.reference) = finance.log_id_key(g.id)
                              AND finance.log_id_key(l.reference) !~ '^[0-9]{1,11}$'
                              AND strpos(finance.log_id_key(l.reference), finance.log_id_key(p_reference)) = 0)));
$$;
COMMENT ON FUNCTION finance.iut_gateway_names_credit(text[], text, uuid) IS
  'V766: whether any identifier the gateway or the collections import gave the confirmed payment (admissions.iut_fee_reference.gateway_refs) is on the settlement row a bank credit came from (its Log Id, payment reference or transaction reference) or is the bank reference of the collections line it came from (equal by finance.log_id_key) — never the portal reference or a piece of it; on a collections line never the narration (the payer''s own free text), never a bank reference that is a bare number shorter than an RRN (a teller''s) or that holds the portal reference (WebPAY''s <reference>-A<n>). Read by finance.iut_bank_credit_already_paid.';

/* a bank credit proposed for a transfer applicant's reference that was confirmed between the proposal and its approval. The Bursary's
   own tools see one payment more than once (Interswitch's settlement report and the collections statement send a payment the portal
   had not yet confirmed to the bank credits; PAYDirect's notice or import, or a gateway, then confirm the same money), but money may
   also come twice: two tellers proposed against one reference, a teller and then a payment at another branch or by card, a settlement
   row of one payment and the import of another. How the reference was confirmed does not tell them apart; only the identifiers the
   machine gave the payment do. So the credit is posted as the same money ('already confirmed', as the house posts any reference's)
   only when it came from a settlement row carrying one of the identifiers the gateway or the collections import gave the confirmed
   payment, or from a collections line whose bank reference is one of them, and no other bank credit is posted to the reference (one
   payment is posted once). Free text is never evidence: a reference the Bursar confirmed by hand takes no bank credit at all, for no
   reading of the note tells one payment from another (round 6's verification posted real second payments as nothing through notes
   naming two tellers, another branch of the bank, or the reference written short), and a collections line's narration is the payer's
   own words (round 7's verification posted real second payments as nothing through transfers quoting the first payment's receipt).
   Everything else is refused, worded by how the reference was confirmed, the officer told to check the bank's record before anything
   is refunded: the same money is never told to be refunded, and a second payment is never posted as nothing */
CREATE FUNCTION finance.iut_bank_credit_already_paid(c finance.bank_credit) RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE f admissions.iut_fee_reference; v_how text; v_chan text; v_posted text; v_why text; v_on text;
BEGIN
    SELECT * INTO f FROM admissions.iut_fee_reference x WHERE x.reference = upper(btrim(c.proposed_reference));
    v_chan := upper(btrim(coalesce(f.channel, '')));
    v_on := to_char(f.confirmed_at AT TIME ZONE 'Africa/Lagos', 'FMDD FMMonth YYYY');
    IF v_chan = 'MANUAL' THEN
        -- confirmed by hand: whatever the note says, it is not evidence that this credit is that payment; the bank's record decides
        RAISE EXCEPTION 'IUT_FEE_ALREADY_PAID: reference % was confirmed by hand by the Bursar on % (receipt %); a reference confirmed by hand takes no bank credit, so this bank credit (% · %) is not posted to it',
            f.reference, v_on, f.receipt_no || coalesce(', "' || f.note || '"', ''), c.bank, c.instrument USING ERRCODE = '23514',
            HINT = 'Reject this proposal once the bank''s record is checked. The money is owed back only if the record shows it twice: then '
                || 'refund this credit on the refund desk, naming the applicant, without a transaction reference (the reference holds the payment '
                || 'confirmed by hand). If the record shows it once, nothing is owed back';
    END IF;
    -- one confirmed payment takes one bank credit: another posted to the reference (it confirmed it, or was posted as it) has taken it.
    -- Read under the application's lock iut_confirm_fee took, so two approvals at one moment see each other
    SELECT string_agg(d.bank || ' · ' || d.instrument, '; ' ORDER BY d.approved_at, d.id) INTO v_posted
      FROM finance.bank_credit d
     WHERE d.id <> c.id AND d.state = 'POSTED' AND upper(btrim(coalesce(d.posted_reference, ''))) = f.reference;
    -- the machine's evidence: an identifier the gateway or the collections import gave the payment, on the row or line this credit came from
    IF v_posted IS NULL AND finance.iut_gateway_names_credit(f.gateway_refs, f.reference, c.id) THEN
        RETURN;
    END IF;
    v_how := CASE
        WHEN v_chan = 'PAYDIRECT' THEN 'confirmed by PAYDirect''s collections import' || coalesce(' (Payment Log Id ' || f.gateway_refs[1] || ')', '')
        WHEN v_chan = 'BANK BRANCH' THEN 'confirmed by another bank credit (' || coalesce(split_part(f.note, ' · proposed: ', 1), 'not named') || ')'
        WHEN f.channel ~* '^card|paystack|flutterwave' THEN 'paid by card online (' || f.channel || coalesce(', transaction ' || array_to_string(f.gateway_refs, ' / '), '') || ')'
        -- PAYDirect's notice from Interswitch ('Quickteller', or 'Quickteller · <its channel>': a branch, the web, a POS)
        WHEN f.channel ~* '^quickteller' THEN 'confirmed by PAYDirect''s notice from Interswitch (' || f.channel || coalesce(', Payment Log Id ' || f.gateway_refs[1], '') || ')'
        ELSE 'confirmed by ' || coalesce(f.channel, 'a channel not recorded') END;
    v_why := CASE
        -- the credit that confirmed it is named in v_how already
        WHEN v_posted IS NOT NULL AND v_chan <> 'BANK BRANCH' THEN
             'bank credit ' || v_posted || ' is posted to it already as that payment, and one payment is posted once: this bank credit ('
             || c.bank || ' · ' || c.instrument || ') is not posted to it'
        ELSE 'nothing shows that this bank credit (' || c.bank || ' · ' || c.instrument || ') is that payment, so it is not posted to it' END;
    RAISE EXCEPTION 'IUT_FEE_ALREADY_PAID: reference % was % on %, receipt %; %',
        f.reference, v_how, v_on, f.receipt_no, v_why USING ERRCODE = '23514',
        HINT = 'Reject the proposal either way, once the bank''s record is checked. If it shows the money twice, this credit is owed back to the applicant: '
            || 'refund it on the refund desk, naming them, without a transaction reference (the reference holds the payment confirmed first). If this '
            || 'credit is that same payment, nothing is owed back';
END $$;
COMMENT ON FUNCTION finance.iut_bank_credit_already_paid(finance.bank_credit) IS
  'V766: called by finance.approve_bank_credit when a transfer applicant''s reference was confirmed after the credit was proposed. The credit is the same money only on the machine''s evidence: it came from Interswitch''s settlement row carrying one of the identifiers the gateway or the collections import gave the confirmed payment (admissions.iut_fee_reference.gateway_refs, finance.iut_gateway_names_credit), or from a collections statement line whose bank reference is one of them (never its narration, the payer''s own words), and no other bank credit is posted to the reference (one payment is posted once); then nothing is raised and the credit is posted ''already confirmed''. A reference confirmed by hand (MANUAL) takes no bank credit: refused IUT_FEE_ALREADY_PAID, the note quoted, whatever it says. Otherwise, however the reference was confirmed (PAYDirect, another bank credit, a card), IUT_FEE_ALREADY_PAID, worded by the channel and why. Either way the officer checks the bank''s record and rejects the proposal; the credit is owed back only if the record shows the money twice.';

-- money received at the bank for a transfer applicant's reference: the Bursary's two-person bank credit posts it as it posts any
-- other (finance.reference_state names the store, so the proposal takes it; the approval confirmed it as a Post-UTME fee and failed)
SELECT pg_temp.v766_edit('finance.approve_bank_credit(uuid)'::regprocedure, ARRAY[
$a$    ELSE
        v_out := admissions.confirm_fee($a$,
$b$    ELSIF st.kind = 'IUT_APPLICATION' THEN
        -- V766: a transfer applicant's fee: it settles the application, or is owed back (admissions.iut_confirm_fee). Confirmed
        -- meanwhile: posted as the same money only when the evidence says this credit is that payment, refused otherwise
        v_out := admissions.iut_confirm_fee(c.proposed_reference, 'Bank branch', c.bank || ' ' || c.instrument || ' · proposed: ' || c.proposed_why);
        IF v_out = 'already confirmed' THEN
            PERFORM finance.iut_bank_credit_already_paid(c);
        END IF;
    ELSE
        v_out := admissions.confirm_fee($b$]);

/* D19: the application fee is not refunded — only a payment owed back is. The refund desk refuses a refund of the payment that
   settled a transfer application, raised or approved (as V752 refuses the SIWES fee a registration stands on) */
CREATE FUNCTION finance.iut_refund_refusal(p_reference text) RETURNS void LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM admissions.iut_fee_reference f WHERE f.reference = upper(btrim(coalesce(p_reference, ''))) AND f.settles) THEN
        RAISE EXCEPTION 'REFUND_IUT_SETTLES: payment % settled an inter-university transfer application; the application fee is not refunded, only a payment owed back is',
            upper(btrim(p_reference)) USING ERRCODE = '23514',
            HINT = 'Refund the payment owed back instead: Transfer Application Payments lists it under Owed back';
    END IF;
END $$;
COMMENT ON FUNCTION finance.iut_refund_refusal(text) IS
  'V766 (D19): refuses a refund of the payment that settled an inter-university transfer application — the application fee is not refunded on a decline or a withdrawal; a second payment (owed back) is. Called by finance.propose_refund and finance.approve_refund.';

SELECT pg_temp.v766_edit('finance.propose_refund(uuid,text,text,numeric,text,text,text,text)'::regprocedure, ARRAY[
$a$        PERFORM finance.siwes_refund_refusal(v_src, p_amount);$a$,
$b$        PERFORM finance.siwes_refund_refusal(v_src, p_amount);
        -- V766: the payment that settled a transfer application (only a payment owed back is refunded)
        PERFORM finance.iut_refund_refusal(v_src);$b$]);

SELECT pg_temp.v766_edit('finance.approve_refund(uuid)'::regprocedure, ARRAY[
$a$    PERFORM finance.siwes_refund_refusal(r.source_reference, r.amount);   -- V752: a SIWES registration made on it since it was raised; a part$a$,
$b$    PERFORM finance.siwes_refund_refusal(r.source_reference, r.amount);   -- V752: a SIWES registration made on it since it was raised; a part
    PERFORM finance.iut_refund_refusal(r.source_reference);   -- V766: the payment that settled a transfer application$b$]);

-- the go-live data reset clears the applications; the window, programmes, document kinds and fee are configuration and are kept
SELECT pg_temp.v766_edit('platform.reset_operational_data(text,text)'::regprocedure, ARRAY[
$a$        'deferments', (SELECT count(*) FROM people.deferment)$a$,
$b$        'deferments', (SELECT count(*) FROM people.deferment),
        'transfer_applications', (SELECT count(*) FROM admissions.iut_application)$b$,
$a$    DELETE FROM admissions.pg_registration;$a$,
$b$    DELETE FROM admissions.pg_registration;
    -- V766: the online inter-university transfer applications (their window, programmes, document kinds and fee are kept)
    DELETE FROM admissions.iut_event;
    DELETE FROM admissions.iut_document_blob;
    DELETE FROM admissions.iut_document;
    DELETE FROM admissions.iut_fee_reference;
    DELETE FROM admissions.iut_application;
    DELETE FROM admissions.iut_account;$b$]);

-- ── 11 · the notices ─────────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, variables, mandatory, priority) VALUES
('IUT_APPLICATION', 'Inter-university transfer application', 'Sent to an inter-university transfer applicant when there is news on the application.',
 'Your inter-university transfer application',
 E'Dear [FIRST_NAME],\n\nThere is news on your inter-university transfer application [APPLICATION_NUMBER]. Sign in to read it: [PORTAL_URL]\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: there is news on your transfer application [APPLICATION_NUMBER]. Sign in at [PORTAL_URL]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:CREATED', 'Transfer application started', 'Sent when a student of another university registers an inter-university transfer application.',
 'Your transfer application [APPLICATION_NUMBER] is started',
 E'Dear [FIRST_NAME],\n\nYour application for an inter-university transfer to [PROGRAMME], [LEVEL] Level, for the [SESSION] session is started. Your application number is [APPLICATION_NUMBER].\n\nSign in at [PORTAL_URL] with the application number or this e-mail address and the password you chose. Next: pay the application fee (if one is due), upload your documents, then submit the application.\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: transfer application [APPLICATION_NUMBER] started. Sign in at [PORTAL_URL] to pay the fee (if due), upload your documents and submit.',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','PROGRAMME','LEVEL','SESSION','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:PAYMENT_RECEIVED', 'Transfer application fee received', 'Sent with the receipt when an inter-university transfer application fee is confirmed.',
 'Your payment receipt · [RECEIPT_NUMBER]',
 E'Dear [FIRST_NAME],\n\nThis is your official receipt from [UNIVERSITY_NAME].\n\nReceipt no:  [RECEIPT_NUMBER]\nReference:   [REFERENCE]\nPurpose:     [PURPOSE]\nApplication: [APPLICATION_NUMBER]\nSession:     [SESSION]\nAmount:      [AMOUNT]\nVerified:    [PAID_ON]\nChannel:     [CHANNEL]\n\n[NEXT_STEP] [PORTAL_URL]\n\nKeep this receipt. It is verified against the University''s record by its receipt number, not by its appearance.',
 '[UNIVERSITY_SHORT] receipt [RECEIPT_NUMBER]: [AMOUNT] for the transfer application fee ([APPLICATION_NUMBER]) received. Sign in for your receipt.',
 ARRAY['FIRST_NAME','RECEIPT_NUMBER','REFERENCE','PURPOSE','APPLICATION_NUMBER','SESSION','AMOUNT','PAID_ON','CHANNEL','NEXT_STEP','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:SUBMITTED', 'Transfer application submitted', 'Sent when an inter-university transfer applicant submits the application (and each time it is submitted again).',
 'Transfer application [APPLICATION_NUMBER] submitted',
 E'Dear [FIRST_NAME],\n\nYour inter-university transfer application [APPLICATION_NUMBER] is submitted. The Registry checks your documents next; you are told when it has.\n\nPrint your acknowledgement from the portal: [PORTAL_URL]\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: transfer application [APPLICATION_NUMBER] submitted. The Registry checks your documents next. Print your acknowledgement at [PORTAL_URL]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:CORRECTION_REQUIRED', 'Transfer application returned for a correction', 'Sent when the Registry returns an inter-university transfer application to the applicant.',
 'Your transfer application needs a correction',
 E'Dear [FIRST_NAME],\n\nThe Registry has returned your transfer application [APPLICATION_NUMBER] to you:\n\n[NOTE]\n\nDocuments to replace:\n[DOCUMENTS]\n\nSign in at [PORTAL_URL], replace them and submit the application again.\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: transfer application [APPLICATION_NUMBER] is returned to you for a correction. Sign in at [PORTAL_URL], correct it and submit again.',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','NOTE','DOCUMENTS','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:WITH_HOD', 'Transfer application with the department', 'Sent when the Registry has checked the documents and sends the application to the Head of Department.',
 'Your transfer application is with the department',
 E'Dear [FIRST_NAME],\n\nYour documents are checked. The Head of Department of [PROGRAMME] is assessing your transfer application [APPLICATION_NUMBER]; you are told when the University decides.\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: your documents are checked; transfer application [APPLICATION_NUMBER] is with the Head of Department of [PROGRAMME].',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','PROGRAMME','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:ADMITTED', 'Admitted by inter-university transfer', 'Sent when another officer approves the transfer the Registry registered: the student is on the register.',
 'Admitted by inter-university transfer',
 E'Dear [FIRST_NAME],\n\nCongratulations: you are admitted by inter-university transfer to [PROGRAMME], [LEVEL] Level, for the [SESSION] session. Your admission number is [ADMISSION_NUMBER].\n\nSign in at [PORTAL_URL] with your admission number and the password of your application; pay your school fees and register your courses in the student portal.\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: you are admitted by transfer to [PROGRAMME], [LEVEL] Level, [SESSION]. Admission number [ADMISSION_NUMBER]. Sign in at [PORTAL_URL] with it and your application password.',
 ARRAY['FIRST_NAME','PROGRAMME','LEVEL','SESSION','ADMISSION_NUMBER','APPLICATION_NUMBER','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:REJECTED', 'Transfer application not successful', 'Sent when the Registry rejects an inter-university transfer application, with its reason.',
 'Your transfer application',
 E'Dear [FIRST_NAME],\n\nYour inter-university transfer application [APPLICATION_NUMBER] is not successful: you are not admitted.\n\nReason: [REASON]\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: transfer application [APPLICATION_NUMBER]: not admitted. Reason: [REASON]',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','REASON','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_APPLICATION:WITHDRAWN', 'Transfer application withdrawn', 'Sent when an inter-university transfer applicant withdraws the application.',
 'Transfer application withdrawn',
 E'Dear [FIRST_NAME],\n\nYour inter-university transfer application [APPLICATION_NUMBER] is withdrawn at your request.\n\nThe Registry, [UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: transfer application [APPLICATION_NUMBER] is withdrawn at your request.',
 ARRAY['FIRST_NAME','APPLICATION_NUMBER','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL'),
('IUT_DESK:WITH_HOD', 'Transfer applicant awaiting a recommendation', 'Sent to the Head of Department (or the College''s Dean) when an inter-university transfer application reaches the department.',
 'Transfer applicant awaiting your recommendation',
 E'Dear [NAME],\n\n[APPLICANT] ([APPLICATION_NUMBER]) applies by inter-university transfer for [PROGRAMME], [LEVEL] Level, in [DEPARTMENT]. The Registry has checked the documents.\n\nRecommend at [PORTAL_URL]/hod/transfer-applications\n\n[UNIVERSITY_NAME]',
 '[UNIVERSITY_SHORT]: transfer applicant [APPLICATION_NUMBER] ([PROGRAMME], [LEVEL] Level) awaits your recommendation. Sign in at [PORTAL_URL]',
 ARRAY['NAME','APPLICANT','APPLICATION_NUMBER','PROGRAMME','LEVEL','DEPARTMENT','PORTAL_URL','UNIVERSITY_NAME','UNIVERSITY_SHORT'], true, 'NORMAL')
ON CONFLICT (key) DO NOTHING;

-- ── 12 · merges, grants, comments ────────────────────────────────────────────────────────────────────────────────────────
-- a programme merged into another (V574): the lines move unless the kept programme holds its own; the applications move
INSERT INTO ref.programme_reference (tab, col, policy, note) VALUES
    ('admissions.iut_line', 'programme_code', 'MOVE_UNLESS_HELD', 'a programme taking inter-university transfer applicants in a session (V766)'),
    ('admissions.iut_application', 'programme_code', 'MOVE', 'the programme an inter-university transfer applicant applies for (V766)')
ON CONFLICT (tab, col) DO NOTHING;

GRANT SELECT ON admissions.iut_window, admissions.iut_line, admissions.iut_document_kind, admissions.iut_application, admissions.iut_document,
                admissions.iut_fee_reference, admissions.iut_event, finance.iut_fee, finance.iut_fee_change TO app_auditor, app_reporting;

COMMENT ON FUNCTION admissions.iut_set_window(text, text, date, date, text, text) IS
  'V766: the Academic Office sets a session''s transfer window (academic, registrar, dregistrar, super): OPEN with its dates, a programme in use taking transfers and the fee published; CLOSED stops new applications only; back to DRAFT only while no application is made.';
COMMENT ON FUNCTION admissions.iut_act(uuid, text, text, text) IS
  'V766: the Registry''s acts on a transfer application (academic, registrar, dregistrar, super): SEND_TO_HOD once submitted and every document checked; RETURN to the applicant with a note; SEND_BACK_TO_HOD after a recommendation or a decline; REJECT with a reason told to the applicant, from a draft (one made under another person''s JAMB number holds the number until it ends) to a recommendation. p_expected: the state the officer saw (IUT_STATE_MOVED).';
COMMENT ON FUNCTION admissions.iut_recommend(uuid, boolean, integer, text, text) IS
  'V766: the Head of Department of the programme applied for (the Dean of its faculty where it is in a College; super) recommends an application with the department: accept at a level the window lists for the programme, or decline with a reason.';

-- ── 13 · the short stretch: the keys, checks, trigger and view on the portal's tables, taken last ─────────────────────────
ALTER TABLE admissions.iut_window ADD CONSTRAINT iut_window_session_fkey FOREIGN KEY (session) REFERENCES policy.academic_session(name);
ALTER TABLE admissions.iut_line ADD CONSTRAINT iut_line_programme_code_fkey FOREIGN KEY (programme_code) REFERENCES ref.programme(code) ON UPDATE CASCADE;
ALTER TABLE finance.iut_fee ADD CONSTRAINT iut_fee_session_fkey FOREIGN KEY (session) REFERENCES policy.academic_session(name);
ALTER TABLE finance.iut_fee_change ADD CONSTRAINT iut_fee_change_session_fkey FOREIGN KEY (session) REFERENCES policy.academic_session(name);
ALTER TABLE admissions.iut_application
    ADD CONSTRAINT iut_application_programme_code_fkey FOREIGN KEY (programme_code) REFERENCES ref.programme(code),
    ADD CONSTRAINT iut_application_university_code_fkey FOREIGN KEY (university_code) REFERENCES ref.university(code),
    ADD CONSTRAINT iut_application_transfer_id_fkey FOREIGN KEY (transfer_id) REFERENCES people.university_transfer(id) ON DELETE SET NULL,
    ADD CONSTRAINT iut_application_student_id_fkey FOREIGN KEY (student_id) REFERENCES people.student(id) ON DELETE SET NULL;
ALTER TABLE admissions.iut_document ADD CONSTRAINT iut_document_object_id_fkey FOREIGN KEY (object_id) REFERENCES platform.file_object(id);

-- an online application approved by the Registry is a batch of its own kind
ALTER TABLE people.university_transfer_batch DROP CONSTRAINT university_transfer_batch_source_check,
    ADD CONSTRAINT university_transfer_batch_source_check CHECK (source IN ('FILE', 'FORM', 'APPLICATION'));
COMMENT ON COLUMN people.university_transfer_batch.source IS
  'V763/V766: FILE (a spreadsheet), FORM (one student on the form), APPLICATION (an online application approved by the Registry: admissions.iut_application.transfer_id)';
-- the transfer applicant resets a forgotten password like every other applicant
ALTER TABLE iam.password_reset DROP CONSTRAINT ck_pwreset_kind,
    ADD CONSTRAINT ck_pwreset_kind CHECK (subject_kind IN ('STAFF', 'STUDENT', 'APPLICANT', 'PGAPPLICANT', 'IUTAPPLICANT'));
-- a transfer applicant told of a short, reversed or hanging payment is recorded as such
ALTER TABLE finance.payer_told DROP CONSTRAINT payer_told_payer_kind_check,
    ADD CONSTRAINT payer_told_payer_kind_check CHECK (payer_kind IN ('STUDENT', 'APPLICANT', 'PG_APPLICANT', 'JUPEB', 'IUT_APPLICANT'));

CREATE TRIGGER trg_iut_transfer_decided AFTER UPDATE OF status ON people.university_transfer
    FOR EACH ROW WHEN (OLD.status = 'PENDING_APPROVAL' AND NEW.status <> 'PENDING_APPROVAL')
    EXECUTE FUNCTION admissions.iut_transfer_decided();

-- the payments view: a branch for the transfer applicant's fee (source IUT); a last column for its application on every branch
-- (CREATE OR REPLACE VIEW adds columns only at the end). Through it the ledger, Financial Analytics, Collections and the master
-- report take the payments in.
DO $do$
DECLARE d text := pg_get_viewdef('reporting.payments'::regclass, true); n integer;
        a text := E'        END AS ledger_status\n   FROM ';
BEGIN
    n := (length(d) - length(replace(d, a, ''))) / length(a);
    IF n <> 4 THEN
        RAISE EXCEPTION 'V766: reporting.payments is not as V741 left it (% branches end with ledger_status)', n;
    END IF;
    d := replace(d, a, E'        END AS ledger_status,\n    NULL::uuid AS iut_application_id\n   FROM ');
    d := rtrim(d, E'; \n') || $branch$
UNION ALL
 SELECT 'IUT'::text AS source,
    f.id AS payment_id,
    f.reference,
    f.receipt_no,
    NULL::text AS purpose,
    'IUT_APPLICATION'::text AS kind,
    k.code AS category_code,
    f.amount,
    f.created_at AS generated_at,
    f.confirmed_at,
    f.expires_at,
    f.channel,
    f.session,
    a.student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    COALESCE(a.student_id::text, a.id::text) AS payer_key,
    a.surname,
    a.other_names,
    COALESCE(s.matric_no, s.admission_no, a.application_no) AS number,
    a.sex,
    'TRANSFER'::text AS entry_mode,
    a.session AS entry_session,
    a.state AS status,
    fa.code AS faculty_code,
    fa.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    a.level,
    false AS is_pg,
    COALESCE(fa.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'TRANSFER'::text AS admission_route,
    'FULL_TIME'::text AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    a.jamb_reg_no,
    a.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN f.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN f.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status,
    a.id AS iut_application_id
   FROM admissions.iut_fee_reference f
     JOIN admissions.iut_application a ON a.id = f.application_id
     LEFT JOIN people.student s ON s.id = a.student_id
     LEFT JOIN ref.programme p ON p.code = a.programme_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('IUT_APPLICATION'::text, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('TRANSFER'::text, 'UNDER GRADUATE'::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true$branch$;
    EXECUTE 'CREATE OR REPLACE VIEW reporting.payments AS ' || d;
    -- the view as it now stands: the column on the four branches and the transfer applicant's own, or the migration stops
    IF (SELECT count(*) FROM regexp_matches(pg_get_viewdef('reporting.payments'::regclass, true), 'AS iut_application_id', 'g')) <> 5
       OR position('''IUT''::text AS source' IN pg_get_viewdef('reporting.payments'::regclass, true)) = 0 THEN
        RAISE EXCEPTION 'V766: reporting.payments did not take its edit';
    END IF;
END $do$;
COMMENT ON COLUMN reporting.payments.iut_application_id IS 'V766: the online inter-university transfer application a payment of source IUT is for';

-- the category last: adding it rebuilds the category and owner memos, a lock on every memo row until the commit
INSERT INTO finance.payment_category (code, label, kinds, ord, revenue, purpose)
VALUES ('IUT_APPLICATION', 'Inter-university transfer application fee', ARRAY['IUT_APPLICATION'], 22, true, 'APPLICATION')
ON CONFLICT (code) DO NOTHING;
SELECT finance.refresh_category_memo();

COMMIT;
