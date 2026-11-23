-- V780. An inter-university transfer student registered by staff signs in on the admission number.
--
-- The owner, 23 November 2026: "allow inter university transfer student to login, e.g. MOAUM/ADM/25/000023".
--
-- What was wrong. The student door opens on the matriculation number and, before one is issued, on the admission number
-- (StudentPortalRepository.byMatric): MOAUM/ADM/25/000023 is found. But the door then needs an account (iam.student_account), and a
-- student who came in through the portal as an applicant brings one — the applicant's password carried over at the first sign-in. An
-- incoming transfer registered BY STAFF (the spreadsheet batch of V588, the one-student form of V763) has no applicant and was given
-- no account: people.decide_university_transfer made the record — ADMITTED, entry by TRANSFER, an admission number drawn — and
-- stopped there. The door answered "No portal account has been opened for this number yet. The Registry opens it and gives you a first
-- password", and nothing in the portal opened one (ICT Support's reset and the bulk reset act on an account that exists).
--
-- What V780 does. The account every other registration route gives a student with no password of their own — a sealed hash nobody
-- holds and must_change on (V669's upload, the biography imports): the first password is the number the student signs in with, here
-- the admission number, and the change is forced before anything else; once one is chosen the number opens nothing (V428, V485).
--
--   people.open_transfer_student_account(student, sealed) — opens that account for an incoming transfer student, once: only a record
--     made by TRANSFER, not ended as a duplicate or closed (withdrawn, expelled, transferred out, graduated, deceased), with no
--     account yet and no password of their own to carry over (an applicant's account on their candidate, or an online transfer
--     application — V766 — that admitted them: their application password is carried over at the first sign-in as it always was).
--     Returns whether it opened one; a second call opens nothing.
--   people.decide_university_transfer (V588) — opens it when the record is made by a batch staff prepared (source FILE or FORM); a
--     batch made from an online application (source APPLICATION, V766) keeps its own route.
--   The transfer students already on the register without an account (created by a staff batch, approved and completed) — opened
--     once here, the same way.
--
-- Nothing else changes: the fee gate does not apply to a transfer entrant (finance.portal_fee_gate_applies reads UTME and Direct
-- Entry admits only), so the student reaches the portal on their first sign-in; the biodata gate and the contact prompts take them
-- from there, as for any student.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V780: an inter-university transfer student registered by staff signs in on the admission number', true);

-- ── 1 · the account for a transfer student with none ─────────────────────────────────────────────────────────────────────────
CREATE FUNCTION people.open_transfer_student_account(p_student uuid, p_sealed text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE s people.student; v_sealed text := p_sealed;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND OR s.entry_mode IS DISTINCT FROM 'TRANSFER' OR s.duplicate_of IS NOT NULL
       OR s.status IN ('WITHDRAWN', 'EXPELLED', 'TRANSFERRED_OUT', 'GRADUATED', 'DECEASED', 'VOLUNTARY_WITHDRAWAL') THEN
        RETURN false;
    END IF;
    IF EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id) THEN
        RETURN false;
    END IF;
    -- a password of their own to carry over at the first sign-in: the applicant's account on their candidate, or the online
    -- inter-university transfer application that admitted them (V766) — left as they are
    IF (s.candidate_id IS NOT NULL AND EXISTS (SELECT 1 FROM admissions.applicant_account x WHERE x.candidate_id = s.candidate_id))
       OR EXISTS (SELECT 1 FROM admissions.iut_application ap WHERE ap.student_id = s.id AND ap.state = 'ADMITTED') THEN
        RETURN false;
    END IF;
    -- sealed: a cost-12 hash of a random secret nobody holds (the account table requires cost 12); the student's first sign-in is
    -- their own number (must_change), never this
    IF v_sealed IS NULL THEN
        v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12));
    END IF;
    INSERT INTO iam.student_account (id, student_id, password_hash, must_change)
    VALUES (gen_random_uuid(), s.id, v_sealed, true)
    ON CONFLICT (student_id) DO NOTHING;
    RETURN FOUND;
END $$;
COMMENT ON FUNCTION people.open_transfer_student_account(uuid, text) IS
  'V780: opens the student account of an incoming inter-university transfer student registered by staff — a sealed hash and must_change on, so the first sign-in is the admission number (or the matriculation number once issued) and the change of password is forced. Only a record made by TRANSFER, not a duplicate and not closed, with no account yet and no password of their own to carry over (an applicant account on their candidate; an online transfer application that admitted them, V766). Returns whether it opened one; a second call opens nothing.';

-- ── 2 · the decision opens it (people.decide_university_transfer, V588: restated by anchor) ─────────────────────────────────
CREATE FUNCTION pg_temp.v780_once(p_def text, p_anchor text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    IF p_anchor IS NULL OR length(p_anchor) = 0 OR (length(p_def) - length(replace(p_def, p_anchor, ''))) / length(p_anchor) <> 1 THEN
        RAISE EXCEPTION 'V780: % is not as it was left (an anchor is not there exactly once)', p_what;
    END IF;
END $$;

DO $v780$
DECLARE d text; a text;
BEGIN
    d := pg_get_functiondef('people.decide_university_transfer(uuid,boolean,text)'::regprocedure);
    -- the record made for an incoming transfer: after its contact and nationality, the account it signs in with
    a := E'        PERFORM people.default_nationality(v_student);\n';
    PERFORM pg_temp.v780_once(d, a, 'people.decide_university_transfer');
    d := replace(d, a, a
        || E'        -- V780: the student signs in on the admission number just drawn — a first password and the change forced; a batch made\n'
        || E'        -- from an online application (V766) keeps the application''s own password\n'
        || E'        IF b.source IS DISTINCT FROM ''APPLICATION'' THEN\n'
        || E'            PERFORM people.open_transfer_student_account(v_student);\n'
        || E'        END IF;\n');
    EXECUTE d;
END $v780$;

-- ── 3 · the transfer students already registered without an account ────────────────────────────────────────────────────────
DO $v780$
DECLARE r record; v_sealed text; v_opened int := 0;
BEGIN
    FOR r IN
        SELECT DISTINCT s.id
          FROM people.student s
          JOIN people.university_transfer t ON t.student_id = s.id AND t.direction = 'INCOMING' AND t.status = 'COMPLETED' AND t.created_student
          JOIN people.university_transfer_batch b ON b.id = t.batch_id AND b.source IS DISTINCT FROM 'APPLICATION'
         WHERE s.entry_mode = 'TRANSFER'
           AND NOT EXISTS (SELECT 1 FROM iam.student_account a WHERE a.student_id = s.id)
    LOOP
        IF v_sealed IS NULL THEN
            v_sealed := crypt(gen_random_uuid()::text, gen_salt('bf', 12));
        END IF;
        IF people.open_transfer_student_account(r.id, v_sealed) THEN
            v_opened := v_opened + 1;
        END IF;
    END LOOP;
    RAISE NOTICE 'V780: % inter-university transfer student account(s) opened', v_opened;
END $v780$;

COMMIT;
