-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V749 · Identity information: the blood group confirmed by the student and the member of staff; a member of staff's photograph
--         and e-mail
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's two briefs of 12 November 2026. Every student whose blood group is missing or not confirmed is asked for it on
--  the dashboard ("UPDATE YOUR BLOOD GROUP INFORMATION": one of A+, A-, B+, B-, AB+, AB-, O+, O-, and "I confirm that the blood group
--  information supplied is accurate."), saved to the record with the time and the confirmation; the identity card reads it from the
--  record, never a default. A member of staff is asked the same, and to bring the photograph and the e-mail address up to date
--  ("UPDATE STAFF IDENTITY INFORMATION"): the photograph assessed and enhanced on the server, the original kept, saved as the card
--  photograph only once the member of staff accepts it; the e-mail address verified by a code sent to it, the old address kept until
--  then, never another person's. Done is all three: the photograph enhanced and accepted, the e-mail verified, the blood group
--  confirmed. The administrators see who has and who has not, and every change is on the audit trail.
--  The University's decisions of 12 November 2026: a student's identity card waits until the blood group is confirmed — by the
--  student, or by the card desk, whose entry counts as confirmed (for the blood group alone; V699 stands for the rest); a member of
--  staff's card is not held (it prints "—" without one).
--
--  What stood: a student's blood group was the biodata's free text (any words, read as one of the eight by credentials.blood_group_of)
--  or the health profile's; a member of staff's was the card desk's alone (credentials.staff_card_detail, V622). Nothing said whether
--  either had been confirmed, and the student's card did not read it. A staff e-mail was never verified and could be another
--  person's; a staff photograph was kept as uploaded, replaced whole, with no history and nothing done to it.
--
--  1 · The blood group confirmed. credentials.blood_group_confirmation: one row a student or member of staff — the group confirmed, when,
--      by whom and from where (SELF, or DESK for the card desk). credentials.blood_group_event: every save, with the value before it.
--      credentials.blood_group_confirmed(kind, holder): the group confirmed, only while the record still holds it — a later change of the
--      biodata's free text is not confirmed. credentials.confirm_my_blood_group(value, confirmed): the student (on the biodata) or the
--      member of staff in service (on the card detail) saves their own: one of the eight exactly, the confirmation ticked.
--      credentials.set_blood_group (V622, restated): the card desk's entry now counts as confirmed, and is an event. Entries the card desk
--      made before today count the same (from the card detail, and for students from the audit trail).
--  2 · A student's identity card. credentials.id_card_eligibility (restated from V699): a blood group not yet confirmed is a reason the
--      card is not printed; checks.blood_group and bloodGroup (the confirmed group) are said with it. The print (and the desk's one-act
--      issue, which prints) reads the eligibility as before.
--  3 · A member of staff's e-mail. iam.email_verification: each code sent, kept only as its SHA-256 hash — three an hour, fifteen minutes
--      each, five tries, as V575 for students. iam.person_email_verified: the address verified, which stands while the person's e-mail
--      is still that address. An address is another person's when that person verified it and still holds it
--      (iam.email_verified_elsewhere); one merely typed on someone's record never keeps it from the person it belongs to, and is left
--      as it stands. iam.email_code_issue(address, hash) refuses a malformed address; one another person holds verified uses up one of
--      the hour's three tries and is answered TAKEN (the hour's limit comes first, so whose an address is cannot be asked for nothing);
--      iam.email_code_check(hash) makes the address the person's only when the code is right and no one else holds it verified — the
--      old address stands until then. One address is verified by one person at a time (a lock on the address). No unique index on
--      e-mail: the functions keep the rule. The person's own doors change the e-mail only this way: iam.set_my_contact (the "how do we
--      reach you" banner) refuses an address other than the one on record (STAFF_EMAIL_VERIFY, iam.assert_my_email_unchanged), blank
--      leaving it as it is; the profile (PUT /api/v1/staff/profile) takes none — the API writes the record's address into it, so a page
--      opened before the address changed saves the rest; where the record has none, the profile keeps its own (one no other record
--      holds), which reaches the record as V425 copies it. A profile's address that never reached its record (saved before V425's copy)
--      is put on the record first, where no other record holds it. The office's correction (iam.set_person_contact) is the profile's
--      too, so an address it cleared is not brought back by the profile; it never places an address another person holds verified,
--      and no other door does either: iam.person refuses it on every write (IDENTITY_EMAIL_TAKEN, the trigger
--      trg_person_email_not_taken — the office's lecturers, the uploads, examiners, a person added). An appointment (hrm.appoint and
--      hrm.appointment_check, V510 restated) is made without such an address, the check naming it beforehand and the appointment
--      reporting it left off. The address is locked before the person's record on every path that takes both, so two of them never
--      wait on each other.
--      The code reaches the mailbox alone. Its e-mail is filed against the code (about_kind 'email_verification'), never against the
--      person who asked; its words are kept in the outbox only until the message has gone (or will not go: a code decided first
--      cancels it). A member of staff's own notices (platform.person_notices, GET /api/v1/me/notices) are those filed against them and,
--      by address, those sent to an address they verified — or, of the notices of their work (a course, a score sheet, a transfer, a
--      clearance, a deferment, a Post-UTME export, a report sent, an office's notice), to an address or phone theirs alone on the
--      register — and never a message that carries a code or a link that signs in or opens a form (platform.notice_carries_secret).
--      An office's notice is told from an applicant's own message, both filed 'application', by its mark (admissions.tell_office,
--      restated, marks it OFFICE_TELL); a reply to a sign-in ticket (a request from the sign-in page names no one) is listed only to
--      the address verified. Each way is walked newest first by its own index (ix_notice_about, ix_notice_recipient, and
--      ix_notice_work for the notices of a person's work alone: the key, then the time) and stops at the limit, the secret asked only
--      of the messages walked.
--      A student's notices on the dashboard leave such a message out too (the API), so a contact confirmation code (V575) is read only
--      in its mailbox.
--  4 · A member of staff's photograph. hrm.staff_photo_submission: each upload — the original, kept; the enhanced copy; the assessment and
--      what was done; the verdict (GOOD, FAIR, REPLACE). hrm.staff_photo_event: every upload, enhancement, failure, retry, acceptance and
--      discard. hrm.add_my_staff_photo_submission, update_my_staff_photo_submission (a retry), accept_my_staff_photo and
--      discard_my_staff_photo, each the holder's own. Accepted, the enhanced copy is the card photograph (hrm.staff_photo.submission_id
--      names it) and the photograph it replaced is kept on the submission; a photograph needing replacement is never accepted.
--      Twenty uploads and retries an hour (hrm.staff_photo_upload_allowed, asked before the image is worked and again as it is kept),
--      a file refused as it was read counted among them (REFUSED, hrm.record_my_staff_photo_refusal): reading it was work all the same.
--      hrm.set_my_staff_photo (V310, restated): a photograph uploaded the old way is not an enhanced one.
--  5 · iam.staff_in_service(person) — V698's reading of a member of staff in the University's service — and
--      iam.staff_identity_state(person): in service, the photograph, the e-mail, the blood group, and whether all three are done.
--  6 · The reports: credentials.identity_completion_students and _student_list (students in study, by faculty, department, programme
--      and level), credentials.identity_completion_staff and _staff_list (staff in service, by faculty, unit and category).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V749: identity information — the blood group confirmed, a member of staff''s photograph and e-mail', true);

-- ── 1 · the blood group confirmed ──────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE credentials.blood_group_confirmation (
    kind             text NOT NULL CONSTRAINT ck_bgc_kind CHECK (kind IN ('STUDENT', 'STAFF')),
    holder_id        uuid NOT NULL,
    blood_group      text NOT NULL CONSTRAINT ck_bgc_group CHECK (blood_group IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    source           text NOT NULL CONSTRAINT ck_bgc_source CHECK (source IN ('SELF', 'DESK')),
    confirmed_at     timestamptz NOT NULL DEFAULT now(),
    confirmed_by     uuid NULL,
    confirmed_office text NULL,
    PRIMARY KEY (kind, holder_id)
);
COMMENT ON TABLE credentials.blood_group_confirmation IS
  'V749: the blood group a student (holder: the student) or a member of staff (holder: the person) confirmed, or the card desk recorded (DESK, which counts as confirmed); it counts only while the record still holds that group (credentials.blood_group_confirmed)';
SELECT audit.attach('credentials.blood_group_confirmation');

CREATE TABLE credentials.blood_group_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind           text NOT NULL CONSTRAINT ck_bge_kind CHECK (kind IN ('STUDENT', 'STAFF')),
    holder_id      uuid NOT NULL,
    holder_number  text NULL,
    previous_value text NULL,
    new_value      text NOT NULL CONSTRAINT ck_bge_group CHECK (new_value IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
    confirmed      boolean NOT NULL,
    source         text NOT NULL CONSTRAINT ck_bge_source CHECK (source IN ('SELF', 'DESK')),
    at             timestamptz NOT NULL DEFAULT now(),
    by             uuid NULL,
    office         text NULL
);
CREATE INDEX ix_blood_group_event_holder ON credentials.blood_group_event (kind, holder_id, at DESC);
COMMENT ON TABLE credentials.blood_group_event IS
  'V749: every blood group saved — by the student or member of staff (SELF) or at the card desk (DESK) — with the number the holder bore, the group the card read before it and the group saved';
SELECT audit.attach('credentials.blood_group_event');

-- V698's reading of a member of staff in the University's service: a staff number, not left, an office today or the HR staff register
CREATE FUNCTION iam.staff_in_service(p_person uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.person pe
                    WHERE pe.id = p_person AND pe.staff_number IS NOT NULL AND btrim(pe.staff_number) <> '' AND pe.ended_on IS NULL
                      AND (EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = pe.id AND a.valid_from <= current_date
                                     AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                           OR EXISTS (SELECT 1 FROM hrm.staff_record r WHERE r.person_id = pe.id)))
$$;
COMMENT ON FUNCTION iam.staff_in_service(uuid) IS
  'V749: whether the person is a member of staff in the University''s service as V698 reads it — a staff number, not left, and an office today or a row on the HR staff register';

CREATE FUNCTION credentials.blood_group_confirmed(p_kind text, p_holder uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT c.blood_group FROM credentials.blood_group_confirmation c
     WHERE c.kind = p_kind AND c.holder_id = p_holder
       AND c.blood_group = CASE p_kind WHEN 'STUDENT' THEN credentials.student_blood_group(p_holder)
                                       WHEN 'STAFF' THEN credentials.staff_blood_group(p_holder) END
$$;
COMMENT ON FUNCTION credentials.blood_group_confirmed(text, uuid) IS
  'V749: the blood group confirmed (by the holder or the card desk) while the record still holds it — what the card reads (credentials.student_blood_group / staff_blood_group) equal to what was confirmed; NULL otherwise';

CREATE FUNCTION credentials.confirm_my_blood_group(p_value text, p_confirmed boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        g text := upper(btrim(coalesce(p_value, ''))); v_kind text; v_prev text; v_no text; v_at timestamptz := now();
BEGIN
    IF who IS NULL OR office IS NULL THEN
        RAISE EXCEPTION 'IDENTITY_BLOOD_ACTOR: a blood group is confirmed by the student or the member of staff, signed in' USING ERRCODE = '23514';
    END IF;
    IF office = 'applicant' THEN
        RAISE EXCEPTION 'IDENTITY_BLOOD_OFFICE: an applicant''s blood group is not asked here; it is confirmed on the student''s portal once admitted'
            USING ERRCODE = '42501';
    END IF;
    IF p_confirmed IS NOT TRUE THEN
        RAISE EXCEPTION 'IDENTITY_BLOOD_UNCONFIRMED: tick "I confirm that the blood group information supplied is accurate." to save the blood group'
            USING ERRCODE = '23514';
    END IF;
    IF g NOT IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-') THEN
        RAISE EXCEPTION 'IDENTITY_BLOOD_GROUP: a blood group is one of A+, A-, B+, B-, AB+, AB-, O+ or O-' USING ERRCODE = '23514';
    END IF;
    IF office = 'student' THEN
        -- the student office signs in as the student: the actor is the student's own record
        v_kind := 'STUDENT';
        SELECT coalesce(s.matric_no, s.admission_no) INTO v_no FROM people.student s WHERE s.id = who;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'IDENTITY_NOT_STUDENT: no student record is signed in' USING ERRCODE = '42501';
        END IF;
        v_prev := credentials.student_blood_group(who);
        INSERT INTO people.biodata (student_id, field, value) VALUES (who, 'blood_group', g)
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
    ELSE
        v_kind := 'STAFF';
        IF NOT iam.staff_in_service(who) THEN
            RAISE EXCEPTION 'IDENTITY_NOT_STAFF: the staff identity information is kept for members of staff in the University''s service (a staff number, an office today or the HR staff register)'
                USING ERRCODE = '42501';
        END IF;
        SELECT pe.staff_number INTO v_no FROM iam.person pe WHERE pe.id = who;
        v_prev := credentials.staff_blood_group(who);
        INSERT INTO credentials.staff_card_detail (person_id, blood_group, set_at, set_by, set_office) VALUES (who, g, v_at, who, office)
        ON CONFLICT (person_id) DO UPDATE SET blood_group = EXCLUDED.blood_group, set_at = EXCLUDED.set_at, set_by = EXCLUDED.set_by, set_office = EXCLUDED.set_office;
    END IF;
    INSERT INTO credentials.blood_group_confirmation (kind, holder_id, blood_group, source, confirmed_at, confirmed_by, confirmed_office)
    VALUES (v_kind, who, g, 'SELF', v_at, who, office)
    ON CONFLICT (kind, holder_id) DO UPDATE SET blood_group = EXCLUDED.blood_group, source = EXCLUDED.source, confirmed_at = EXCLUDED.confirmed_at,
                                                confirmed_by = EXCLUDED.confirmed_by, confirmed_office = EXCLUDED.confirmed_office;
    INSERT INTO credentials.blood_group_event (kind, holder_id, holder_number, previous_value, new_value, confirmed, source, at, by, office)
    VALUES (v_kind, who, v_no, v_prev, g, true, 'SELF', v_at, who, office);
    RETURN jsonb_build_object('bloodGroup', g, 'confirmedAt', v_at, 'kind', v_kind, 'previous', v_prev);
END $$;
COMMENT ON FUNCTION credentials.confirm_my_blood_group(text, boolean) IS
  'V749: the signed-in student (office student: on the biodata) or member of staff in service (any other office but applicant: on the card detail) saves and confirms their own blood group — one of the eight exactly, the confirmation ticked; an event with the value before it. Returns {bloodGroup, confirmedAt, kind, previous}.';

-- ── the card desk's entry (V622, restated): it now counts as confirmed, and is an event ──
CREATE OR REPLACE FUNCTION credentials.set_blood_group(p_kind text, p_holder uuid, p_value text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        g text := credentials.blood_group_of(p_value);
        v_prev text; v_no text;
BEGIN
    IF who IS NULL OR coalesce(office, '') NOT IN ('security', 'super') THEN
        RAISE EXCEPTION 'CARD_BLOOD_OFFICE: the blood group on the identity card is set at the card desk (the Security Unit)' USING ERRCODE = '42501';
    END IF;
    IF g IS NULL THEN
        RAISE EXCEPTION 'CARD_BLOOD_GROUP: a blood group is one of A+, A-, B+, B-, AB+, AB-, O+ or O-' USING ERRCODE = '23514';
    END IF;
    IF p_kind = 'STUDENT' THEN
        IF NOT EXISTS (SELECT 1 FROM people.student WHERE id = p_holder) THEN
            RAISE EXCEPTION 'CARD_BLOOD_HOLDER: no such student' USING ERRCODE = 'P0002';
        END IF;
        -- V749: what the card read before, and the number the student bore
        v_prev := credentials.student_blood_group(p_holder);
        v_no := (SELECT coalesce(s.matric_no, s.admission_no) FROM people.student s WHERE s.id = p_holder);
        INSERT INTO people.biodata (student_id, field, value) VALUES (p_holder, 'blood_group', g)
        ON CONFLICT (student_id, field) DO UPDATE SET value = EXCLUDED.value WHERE people.biodata.value IS DISTINCT FROM EXCLUDED.value;
    ELSIF p_kind = 'STAFF' THEN
        IF NOT EXISTS (SELECT 1 FROM iam.person WHERE id = p_holder) THEN
            RAISE EXCEPTION 'CARD_BLOOD_HOLDER: no such member of staff' USING ERRCODE = 'P0002';
        END IF;
        v_prev := credentials.staff_blood_group(p_holder);
        v_no := (SELECT pe.staff_number FROM iam.person pe WHERE pe.id = p_holder);
        INSERT INTO credentials.staff_card_detail (person_id, blood_group, set_at, set_by, set_office) VALUES (p_holder, g, now(), who, office)
        ON CONFLICT (person_id) DO UPDATE SET blood_group = EXCLUDED.blood_group, set_at = now(), set_by = who, set_office = office;
    ELSE
        RAISE EXCEPTION 'CARD_BLOOD_HOLDER: a card is a student''s or a member of staff''s' USING ERRCODE = '23514';
    END IF;
    -- V749: the card desk's entry counts as confirmed (the University's decision of 12 November 2026), and is kept as an event
    INSERT INTO credentials.blood_group_confirmation (kind, holder_id, blood_group, source, confirmed_at, confirmed_by, confirmed_office)
    VALUES (p_kind, p_holder, g, 'DESK', now(), who, office)
    ON CONFLICT (kind, holder_id) DO UPDATE SET blood_group = EXCLUDED.blood_group, source = EXCLUDED.source, confirmed_at = EXCLUDED.confirmed_at,
                                                confirmed_by = EXCLUDED.confirmed_by, confirmed_office = EXCLUDED.confirmed_office;
    INSERT INTO credentials.blood_group_event (kind, holder_id, holder_number, previous_value, new_value, confirmed, source, at, by, office)
    VALUES (p_kind, p_holder, v_no, v_prev, g, true, 'DESK', now(), who, office);
    RETURN g;
END $$;
COMMENT ON FUNCTION credentials.set_blood_group(text, uuid, text) IS
  'V622/V749: the blood group the card prints, set at the card desk (Security Unit, super): a student''s on the biodata (blood_group), a member of staff''s on credentials.staff_card_detail; since V749 the entry counts as confirmed and is kept as an event';

-- the card desk's entries made before today count as confirmed too: a member of staff's from the card detail, a student's where the
-- latest write of the biodata's blood group on the audit trail is the desk's and the record still holds what it wrote
INSERT INTO credentials.blood_group_confirmation (kind, holder_id, blood_group, source, confirmed_at, confirmed_by, confirmed_office)
SELECT 'STAFF', d.person_id, d.blood_group, 'DESK', d.set_at, d.set_by, d.set_office
  FROM credentials.staff_card_detail d
 WHERE d.blood_group IS NOT NULL AND d.set_office IN ('security', 'super')
ON CONFLICT (kind, holder_id) DO NOTHING;

INSERT INTO credentials.blood_group_confirmation (kind, holder_id, blood_group, source, confirmed_at, confirmed_by, confirmed_office)
SELECT 'STUDENT', b.student_id, b.value, 'DESK', l.occurred_at, l.actor_id, l.actor_office
  FROM people.biodata b
  JOIN (SELECT DISTINCT ON (k.student_id) k.student_id, k.value, e.occurred_at, e.actor_id, e.actor_office
          FROM audit.entries e
         CROSS JOIN LATERAL (SELECT (coalesce(e.after_state, e.before_state)->>'student_id')::uuid AS student_id, e.after_state->>'value' AS value) k
         WHERE e.subject_type = 'people.biodata' AND coalesce(e.after_state, e.before_state)->>'field' = 'blood_group'
         ORDER BY k.student_id, e.occurred_at DESC, e.id) l ON l.student_id = b.student_id
 WHERE b.field = 'blood_group' AND b.value IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')
   AND l.actor_office IN ('security', 'super') AND l.value = b.value
ON CONFLICT (kind, holder_id) DO NOTHING;

-- ── 2 · a student's identity card waits on a confirmed blood group (restated from V699) ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.id_card_eligibility(p_student uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; reasons text[] := '{}'; warnings text[] := '{}'; v_repl jsonb; v_ses text; v_rule boolean; v_stated boolean; v_in_study boolean; v_photo boolean;
        v_short jsonb := '[]'::jsonb; r record; v_fees_ok boolean := true; v_sessions jsonb := '[]'::jsonb; v_live record; v_blood text;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('eligible', false, 'reasons', jsonb_build_array('No such student on the register'));
    END IF;
    -- V699: the matriculation number alone decides a card; what follows is said to the desk, never held against the card
    v_in_study := s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DORMANT');
    IF NOT v_in_study THEN
        warnings := array_append(warnings, CASE WHEN s.status = 'GRADUATED' THEN 'The record has graduated: no new card is issued; the cards held stay on the record'
                                   ELSE 'Not in study on the register (' || lower(replace(s.status, '_', ' ')) || '): no new card is issued' END);
    END IF;
    IF s.matric_no IS NULL THEN
        reasons := array_append(reasons, 'Matriculation number not yet issued');
    END IF;
    -- V749: and the blood group the card prints, confirmed by the student or recorded by the card desk (the University's decision of
    -- 12 November 2026) — never a default
    v_blood := credentials.blood_group_confirmed('STUDENT', p_student);
    IF v_blood IS NULL THEN
        reasons := array_append(reasons, 'Blood group not yet confirmed — the student confirms it on their dashboard, or the card desk records it');
    END IF;
    v_photo := credentials.has_photo(p_student);
    IF NOT v_photo THEN
        warnings := array_append(warnings, 'Student photograph is missing: the card prints with a blank frame');
    END IF;
    -- the school fees, as finance records them, over the sessions the record shows the student in (an enrolment, or a submitted
    -- registration): the latest of them released for the card by the scheme the Bursary put in force — the University's
    -- school-fee condition — and every earlier one with stated fees paid in full, "from 100 Level"
    SELECT max(x.session) INTO v_ses
      FROM (SELECT e.session FROM people.enrolment e WHERE e.student_id = p_student
            UNION SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = p_student AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x;
    IF v_ses IS NULL THEN
        v_fees_ok := false;
        warnings := array_append(warnings, 'School fees: the record shows no session in study, so no school fees to read');
    ELSE
        v_stated := finance.fee_stated(p_student, v_ses);
        v_rule := CASE WHEN v_stated THEN finance.clears(p_student, v_ses, 'ID_CARD') ELSE NULL END;
        IF v_stated IS NOT TRUE THEN
            v_fees_ok := false;
            warnings := array_append(warnings, ('School fees: the school fees for ' || v_ses || ' are not yet stated for this programme and level'));
        ELSIF NOT v_rule THEN
            v_fees_ok := false;
            warnings := array_append(warnings, ('School fees: the school fees for ' || v_ses || ' are not paid as the scheme in force requires'));
        END IF;
        FOR r IN
            SELECT x.session, pos.due, pos.paid, pos.balance, pos.paid_in_full
              FROM (SELECT DISTINCT e.session FROM people.enrolment e WHERE e.student_id = p_student
                    UNION SELECT cr.session FROM registration.course_registration cr WHERE cr.student_id = p_student AND cr.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x
              CROSS JOIN LATERAL finance.position(p_student, x.session) pos
             WHERE x.session < v_ses AND finance.fee_stated(p_student, x.session)
             ORDER BY x.session
        LOOP
            v_sessions := v_sessions || jsonb_build_object('session', r.session, 'due', r.due, 'paid', r.paid, 'balance', r.balance, 'paid_in_full', r.paid_in_full);
            IF NOT r.paid_in_full THEN
                v_fees_ok := false;
                v_short := v_short || to_jsonb(r.session);
            END IF;
        END LOOP;
        IF jsonb_array_length(v_short) > 0 THEN
            warnings := array_append(warnings, ('School fees: outstanding for ' ||
                                   (SELECT string_agg(value #>> '{}', ', ') FROM jsonb_array_elements(v_short))));
        END IF;
    END IF;
    SELECT c.card_no, c.state, c.version INTO v_live FROM credentials.identity_card c WHERE c.student_id = p_student AND c.state IN ('PRINTED', 'ISSUED');
    v_repl := credentials.id_card_replacement_state(p_student);
    RETURN jsonb_build_object(
        'eligible', cardinality(reasons) = 0,
        'reasons', to_jsonb(reasons),
        -- V699: said, not held — the photograph, the study, the school fees; and a new card after the first waits on its fee
        'warnings', to_jsonb(warnings),
        'replacement', v_repl,
        'checks', jsonb_build_object('in_study', v_in_study, 'matric', s.matric_no IS NOT NULL, 'photo', v_photo, 'fees', v_fees_ok,
                                     'blood_group', v_blood IS NOT NULL),
        -- V749: the blood group the card prints, as confirmed (NULL until it is)
        'bloodGroup', v_blood,
        'fees', jsonb_build_object('session', v_ses, 'stated', v_stated, 'released', v_rule, 'earlier', v_sessions, 'short', v_short),
        'card', CASE WHEN v_live.card_no IS NULL THEN NULL ELSE jsonb_build_object('card_no', v_live.card_no, 'state', v_live.state, 'version', v_live.version) END);
END $function$;

-- ── 3 · a member of staff's e-mail, verified by a code ─────────────────────────────────────────────────────────────────────────
-- first, a profile's address that never reached its record (saved before V425 copied a profile's contact back to the person) is put on
-- the record, as that copy would have put it: only where the record has none, the address is one the profile can hold, and no other
-- record or profile holds it (case and spaces aside). Done before the rules below, when no address is yet verified; from now on the
-- profile's save keeps such an address where no other record holds it (the API), so it is never lost to an empty record
UPDATE iam.person p
   SET email = btrim(sp.email)
  FROM hrm.staff_profile sp
 WHERE sp.person_id = p.id
   AND nullif(btrim(coalesce(p.email, '')), '') IS NULL
   AND btrim(sp.email) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
   AND NOT EXISTS (SELECT 1 FROM iam.person o WHERE o.id <> p.id AND lower(btrim(o.email)) = lower(btrim(sp.email)))
   AND NOT EXISTS (SELECT 1 FROM hrm.staff_profile o WHERE o.person_id <> sp.person_id AND lower(btrim(o.email)) = lower(btrim(sp.email)));

CREATE TABLE iam.email_verification (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id      uuid NOT NULL REFERENCES iam.person (id) ON DELETE CASCADE,
    email          text NOT NULL CONSTRAINT ck_email_verification_email CHECK (email = lower(btrim(email)) AND email <> ''),
    previous_email text NULL,
    code_hash      text NOT NULL CONSTRAINT ck_email_verification_hash CHECK (code_hash ~ '^[0-9a-f]{64}$'),
    expires_at     timestamptz NOT NULL,
    attempts       integer NOT NULL DEFAULT 0 CONSTRAINT ck_email_verification_attempts CHECK (attempts BETWEEN 0 AND 5),
    -- TAKEN: asked for an address another person holds verified — no code sent, and the try counted among the hour's three
    outcome        text NULL CONSTRAINT ck_email_verification_outcome CHECK (outcome IN ('VERIFIED', 'EXPIRED', 'REPLACED', 'TAKEN')),
    created_at     timestamptz NOT NULL DEFAULT now(),
    decided_at     timestamptz NULL
);
CREATE INDEX ix_email_verification_person ON iam.email_verification (person_id, created_at DESC);
COMMENT ON TABLE iam.email_verification IS
  'V749: each code sent to verify a member of staff''s new e-mail address (kept only as its SHA-256 hash; fifteen minutes, five tries, three an hour), with the address it was for, the address the person held then, and how it ended (VERIFIED, EXPIRED, REPLACED by a later code, TAKEN — the address another person''s, verified: no code sent, the try counted)';
SELECT audit.attach('iam.email_verification');

CREATE TABLE iam.person_email_verified (
    person_id   uuid PRIMARY KEY REFERENCES iam.person (id) ON DELETE CASCADE,
    email       text NOT NULL CONSTRAINT ck_person_email_verified_email CHECK (email = lower(btrim(email)) AND email <> ''),
    verified_at timestamptz NOT NULL
);
CREATE INDEX ix_person_email_verified_email ON iam.person_email_verified (email);
COMMENT ON TABLE iam.person_email_verified IS
  'V749: the e-mail address a person verified by a code, and when; the person''s e-mail (iam.person.email) is verified while it is still this address (case and spaces aside)';
SELECT audit.attach('iam.person_email_verified');

-- whose an address is: another person's only when that person verified it and still holds it (case and spaces aside). An address merely
-- typed on someone's record — unverified — never keeps it from the person it belongs to
CREATE FUNCTION iam.email_verified_elsewhere(p_person uuid, p_email text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM iam.person_email_verified v JOIN iam.person o ON o.id = v.person_id
                    WHERE v.email = lower(btrim(coalesce(p_email, ''))) AND v.person_id IS DISTINCT FROM p_person
                      AND lower(btrim(o.email)) = v.email)
$$;
COMMENT ON FUNCTION iam.email_verified_elsewhere(uuid, text) IS
  'V749: whether the address is another person''s — verified by them with a code and still their e-mail (case and spaces aside); an unverified copy on someone else''s record does not count, so it cannot keep the address from its owner';

-- a code is issued for an address (the API makes it, sends it and keeps only its hash); nothing changes iam.person.email here. The hour's
-- three come before the question whose the address is, and a refused address is one of them: answered TAKEN, not raised, so the try
-- stands once the API commits it — asking whose an address is never comes free
CREATE FUNCTION iam.email_code_issue(p_email text, p_code_hash text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
        v_email text := lower(btrim(coalesce(p_email, ''))); v_prev text; v_id uuid;
BEGIN
    IF who IS NULL OR office IS NULL THEN
        RAISE EXCEPTION 'IDENTITY_EMAIL_ACTOR: an e-mail address is verified by the member of staff, signed in' USING ERRCODE = '23514';
    END IF;
    IF office IN ('student', 'applicant') THEN
        RAISE EXCEPTION 'IDENTITY_EMAIL_OFFICE: a student''s or an applicant''s e-mail is confirmed on their own portal' USING ERRCODE = '42501';
    END IF;
    SELECT pe.email INTO v_prev FROM iam.person pe WHERE pe.id = who;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'IDENTITY_NOT_STAFF: no member of staff is signed in' USING ERRCODE = '42501';
    END IF;
    IF NOT platform.email_valid(v_email) THEN
        RAISE EXCEPTION 'IDENTITY_EMAIL_FORMAT: that is not an e-mail address the portal can write to (name@domain, with a domain such as .com or .edu.ng)'
            USING ERRCODE = '23514';
    END IF;
    IF p_code_hash IS NULL OR lower(p_code_hash) !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'IDENTITY_EMAIL_CODE: the code is kept only as its SHA-256 hash' USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('email_code:' || who::text));   -- two clicks, one count
    -- three tries an hour, a refused address among them
    IF (SELECT count(*) FROM iam.email_verification x WHERE x.person_id = who AND x.created_at > now() - interval '1 hour') >= 3 THEN
        RAISE EXCEPTION 'IDENTITY_EMAIL_CODE_LIMIT: three codes have been asked for in the last hour; use the latest, or ask for another later'
            USING ERRCODE = '23514';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('email_addr:' || v_email));      -- one address verified by one person at a time
    IF iam.email_verified_elsewhere(who, v_email) THEN
        -- no code: the try kept (an open earlier code stands), and the refusal said once the API has committed it
        INSERT INTO iam.email_verification (person_id, email, previous_email, code_hash, expires_at, outcome, decided_at)
        VALUES (who, v_email, v_prev, lower(p_code_hash), now(), 'TAKEN', now());
        RETURN jsonb_build_object('email', v_email, 'outcome', 'TAKEN');
    END IF;
    UPDATE iam.email_verification x SET outcome = 'REPLACED', decided_at = now() WHERE x.person_id = who AND x.outcome IS NULL;
    INSERT INTO iam.email_verification (person_id, email, previous_email, code_hash, expires_at)
    VALUES (who, v_email, v_prev, lower(p_code_hash), now() + interval '15 minutes')
    RETURNING id INTO v_id;
    -- id: the code's e-mail is filed against it (about_kind 'email_verification'), never against the person who asked
    RETURN jsonb_build_object('email', v_email, 'outcome', 'ISSUED', 'id', v_id);
END $$;
COMMENT ON FUNCTION iam.email_code_issue(text, text) IS
  'V749: a code to verify a new e-mail address for the signed-in member of staff (not a student or applicant): refused for a malformed address (IDENTITY_EMAIL_FORMAT) and past three tries an hour (IDENTITY_EMAIL_CODE_LIMIT); an address another person holds verified is answered {email, outcome: TAKEN} — not raised, the try recorded and counted, no code — else an earlier open code is REPLACED and {email, outcome: ISSUED, id} returned, the address as kept (lower case, trimmed) and the code''s row, which its e-mail is filed against (about_kind ''email_verification''). An unverified copy of the address on someone else''s record does not stop it. The person''s e-mail is not changed until the code is checked.';

-- the code entered: VERIFIED, WRONG (a try used), EXPIRED (none open, out of time, or five tries spent), TAKEN (another person holds the
-- address verified now) — answered, never raised, so a try is counted
CREATE FUNCTION iam.email_code_check(p_code_hash text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; x iam.email_verification;
BEGIN
    IF who IS NULL THEN RETURN 'EXPIRED'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('email_code:' || who::text));
    SELECT * INTO x FROM iam.email_verification c WHERE c.person_id = who AND c.outcome IS NULL ORDER BY c.created_at DESC LIMIT 1 FOR UPDATE;
    IF NOT FOUND OR x.expires_at <= now() THEN
        IF FOUND THEN UPDATE iam.email_verification SET outcome = 'EXPIRED', decided_at = now() WHERE id = x.id; END IF;
        RETURN 'EXPIRED';
    END IF;
    IF x.code_hash <> lower(coalesce(p_code_hash, '')) THEN
        UPDATE iam.email_verification SET attempts = attempts + 1,
               outcome = CASE WHEN attempts + 1 >= 5 THEN 'EXPIRED' END, decided_at = CASE WHEN attempts + 1 >= 5 THEN now() END
         WHERE id = x.id;
        RETURN CASE WHEN x.attempts + 1 >= 5 THEN 'EXPIRED' ELSE 'WRONG' END;
    END IF;
    -- the address is still nobody else's, verified: asked under the address's lock, so of two people verifying one address at once the
    -- second waits for the first and is told TAKEN
    PERFORM pg_advisory_xact_lock(hashtext('email_addr:' || x.email));
    IF iam.email_verified_elsewhere(who, x.email) THEN
        UPDATE iam.email_verification SET outcome = 'TAKEN', decided_at = now() WHERE id = x.id;
        RETURN 'TAKEN';
    END IF;
    -- verified: the address is the person's from now (the old one stood until this moment), and the profile says the same, so a later
    -- save of the profile does not bring the old address back. An unverified copy of it on someone else's record is left as it stands
    UPDATE iam.person SET email = x.email WHERE id = who AND email IS DISTINCT FROM x.email;
    UPDATE hrm.staff_profile SET email = x.email
     WHERE person_id = who AND nullif(btrim(coalesce(email, '')), '') IS NOT NULL AND lower(btrim(email)) <> x.email;
    INSERT INTO iam.person_email_verified (person_id, email, verified_at) VALUES (who, x.email, now())
    ON CONFLICT (person_id) DO UPDATE SET email = EXCLUDED.email, verified_at = EXCLUDED.verified_at;
    UPDATE iam.email_verification SET outcome = 'VERIFIED', decided_at = now() WHERE id = x.id;
    RETURN 'VERIFIED';
END $$;
COMMENT ON FUNCTION iam.email_code_check(text) IS
  'V749: the signed-in person''s latest open code checked: VERIFIED (the address becomes iam.person.email, and the profile''s, and is recorded verified; an unverified copy on someone else''s record is left as it stands), WRONG (a try used; five and it is EXPIRED), EXPIRED, or TAKEN (another person holds the address verified now; asked under the address''s lock). Never raised, so a try is counted.';

-- the person's own door to their e-mail — the "how do we reach you" banner (PUT /api/v1/staff/contact): the address changes only by a
-- code sent to the new one (above). An address other than the one on record (case and spaces aside) is refused, and nothing of the
-- request is kept; blank leaves the address as it stands. The profile (PUT /api/v1/staff/profile) does not ask: it takes no address, the
-- API writing the record's own into it
CREATE FUNCTION iam.assert_my_email_unchanged(p_email text) RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_new text := lower(btrim(coalesce(p_email, '')));
BEGIN
    IF v_new <> '' AND v_new IS DISTINCT FROM (SELECT lower(btrim(coalesce(pe.email, ''))) FROM iam.person pe WHERE pe.id = who) THEN
        RAISE EXCEPTION 'STAFF_EMAIL_VERIFY: a new e-mail address is saved only once it is verified — add it at My identity'
            USING ERRCODE = '23514';
    END IF;
END $$;
COMMENT ON FUNCTION iam.assert_my_email_unchanged(text) IS
  'V749: refuses (STAFF_EMAIL_VERIFY) an e-mail address other than the signed-in person''s on record, case and spaces aside; blank or the same passes. Asked by the person''s own contact door (iam.set_my_contact) before it writes, so a new address reaches the record only through the code (iam.email_code_issue / email_code_check); the profile takes no address at all (the API writes the record''s).';

-- the banner's save: the phone as given (blank clears it, as it did), the e-mail only as it stands
CREATE FUNCTION iam.set_my_contact(p_email text, p_phone text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
BEGIN
    PERFORM iam.assert_my_email_unchanged(p_email);
    UPDATE iam.person SET phone = v_phone WHERE id = who AND phone IS DISTINCT FROM v_phone;
END $$;
COMMENT ON FUNCTION iam.set_my_contact(text, text) IS
  'V749: the signed-in member of staff''s own contact (PUT /api/v1/staff/contact): the phone saved; the e-mail never changed here — the one on record or blank passes, any other is refused (STAFF_EMAIL_VERIFY) with nothing saved.';

-- the office's correction of a member of staff's record (PUT /api/v1/iam/persons/{id}/contact: the Registry, HR, ICT): the address and
-- the phone as given, blank clearing either as it did — but never an address another person holds verified. The address is locked
-- before the person's record, as the code's issue and check lock it before they reach the record (the other order could leave an
-- office's correction and the holder's own verification each waiting on the other). The profile follows the correction, as it follows
-- an address verified: its older copy is then neither written back over the record (V425) nor, where the office cleared the record's
-- address, kept and brought back by the next save of the profile
CREATE FUNCTION iam.set_person_contact(p_person uuid, p_email text, p_phone text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_email text := nullif(btrim(coalesce(p_email, '')), ''); v_phone text := nullif(btrim(coalesce(p_phone, '')), ''); v_now text;
BEGIN
    IF v_email IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtext('email_addr:' || lower(v_email)));
    END IF;
    SELECT lower(btrim(coalesce(pe.email, ''))) INTO v_now FROM iam.person pe WHERE pe.id = p_person FOR UPDATE;
    IF v_email IS NOT NULL AND lower(v_email) IS DISTINCT FROM v_now THEN
        IF iam.email_verified_elsewhere(p_person, v_email) THEN
            RAISE EXCEPTION 'IDENTITY_EMAIL_TAKEN: this e-mail address is another person''s, verified on their record; it is not placed on this one'
                USING ERRCODE = '23514';
        END IF;
    END IF;
    UPDATE iam.person SET email = v_email, phone = v_phone WHERE id = p_person;
    -- the profile's copy (an address it cannot hold, to its rule ck_sp_email, left out of it): the record locked first, then the profile,
    -- as the profile's own save takes them
    UPDATE hrm.staff_profile sp
       SET email = CASE WHEN v_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN v_email END, phone = v_phone
     WHERE sp.person_id = p_person
       AND (sp.email IS DISTINCT FROM CASE WHEN v_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN v_email END
            OR sp.phone IS DISTINCT FROM v_phone);
END $$;
COMMENT ON FUNCTION iam.set_person_contact(uuid, text, text) IS
  'V749: an office corrects a member of staff''s e-mail and phone (blank clears): refused (IDENTITY_EMAIL_TAKEN) only for a new address another person holds verified, asked under the address''s lock (taken before the record''s). The staff profile''s copy follows (an address it cannot hold left out), so the profile neither writes its older copy back over the record nor keeps an address the office cleared. An address changed here is not verified until its holder enters a code sent to it.';

-- every other door to iam.person.email — the office's lecturers (iam.update_lecturer), the staff and lecturer uploads, an appointment,
-- an examiner, a person added — under the same rule: no address another person holds verified is placed on a record (an address
-- unchanged, case and spaces aside, stands, so a record already holding a copy can still be edited). Asked as the row is written, so the
-- record is locked by then: the address is NOT locked here (taking it after the record would invert the order the code's issue and
-- check keep, address then record, and two of them could wait on each other). The test only reads, and suffices: every address
-- verified and committed elsewhere is seen. One being verified by another session at the same instant is not yet — the one window
-- left, for the doors other than the office's correction, which takes the address first and so waits for that verification
CREATE FUNCTION iam.person_email_not_taken() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_new text := lower(btrim(coalesce(NEW.email, '')));
BEGIN
    IF v_new <> '' AND (TG_OP = 'INSERT' OR v_new IS DISTINCT FROM lower(btrim(coalesce(OLD.email, ''))))
       AND iam.email_verified_elsewhere(NEW.id, v_new) THEN
        RAISE EXCEPTION 'IDENTITY_EMAIL_TAKEN: this e-mail address is another person''s, verified on their record; it is not placed on this one'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_person_email_not_taken BEFORE INSERT OR UPDATE OF email ON iam.person
    FOR EACH ROW EXECUTE FUNCTION iam.person_email_not_taken();
COMMENT ON FUNCTION iam.person_email_not_taken() IS
  'V749: on every write of iam.person.email (trg_person_email_not_taken), a new non-blank address another person holds verified (iam.email_verified_elsewhere) is refused IDENTITY_EMAIL_TAKEN (23514, answered 422); an unchanged one stands. Read-only: the address is not locked here, the record being locked already.';

-- an appointment (V510, restated): an address another person holds verified is theirs, so the appointment is made without it rather
-- than refused whole at the record — the check says so first (a warning, the e-mail left off: email NULL, email_left_off the address),
-- so Human Resources sees it before submitting, and the appointment and the upload report it. An address another record holds
-- unverified is refused as V510 refused it, now read case and spaces aside, as the record reads it
CREATE OR REPLACE FUNCTION hrm.appointment_check(p jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE v_no text := btrim(coalesce(p->>'staff_no', ''));
        v_sur text := btrim(coalesce(p->>'surname', '')); v_given text := btrim(coalesce(p->>'given_names', ''));
        v_cat text := upper(replace(replace(btrim(coalesce(p->>'category', '')), '-', '_'), ' ', '_'));
        v_grade text := upper(regexp_replace(btrim(coalesce(p->>'grade', '')), '\s+', ' ', 'g'));
        v_step int := CASE WHEN btrim(coalesce(p->>'step', '')) ~ '^\d{1,2}$' THEN btrim(p->>'step')::int END;
        v_date date := hrm.read_day(p->>'appointment_date');
        v_dept_in text := nullif(upper(btrim(coalesce(p->>'department', ''))), ''); v_unit_in text := nullif(upper(btrim(coalesce(p->>'unit', ''))), '');
        v_sex text := upper(btrim(coalesce(p->>'sex', ''))); v_email text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
        v_phone text := nullif(regexp_replace(btrim(coalesce(p->>'phone', '')), '[\s()-]', '', 'g'), '');
        v_acct text := regexp_replace(coalesce(p->>'account_number', p->>'account_last4', ''), '\D', '', 'g');
        v_pin text := nullif(upper(btrim(coalesce(p->>'pension_pin', ''))), '');
        v_dept text; v_unit text; per record; g record; v_emp record; probs text[] := '{}'; warns text[] := '{}'; v_taken boolean := false;
BEGIN
    IF v_no !~ '^[A-Za-z0-9/._-]{2,30}$' THEN probs := probs || 'The staff number is 2 to 30 letters, digits, / . _ or -.'::text; END IF;
    SELECT x.id, x.surname, x.given_names, x.ended_on, x.email INTO per FROM iam.person x WHERE upper(btrim(x.staff_number)) = upper(v_no) LIMIT 1;
    IF per.id IS NOT NULL THEN
        IF per.ended_on IS NOT NULL THEN probs := probs || ('The person with staff number ' || v_no || ' was ended on ' || to_char(per.ended_on, 'DD Mon YYYY') || '; ICT restores the record first.'); END IF;
        SELECT e.staff_no, e.status INTO v_emp FROM hrm.employment e WHERE e.person_id = per.id AND e.status <> 'ENDED' LIMIT 1;
        IF v_emp.staff_no IS NOT NULL THEN probs := probs || (per.surname || ' is already in employment (' || v_emp.staff_no || ', ' || lower(v_emp.status) || ').'); END IF;
        IF v_sur <> '' AND upper(v_sur) <> upper(btrim(per.surname)) THEN
            warns := warns || ('The staff number is ' || per.surname || ', ' || per.given_names || '''s; the row says ' || v_sur || '.');
        END IF;
    ELSE
        IF length(v_sur) < 2 OR length(v_given) < 2 THEN probs := probs || 'A new member of staff needs a surname and given names.'::text; END IF;
    END IF;
    IF v_no <> '' AND EXISTS (SELECT 1 FROM hrm.employment e WHERE upper(e.staff_no) = upper(v_no) AND (per.id IS NULL OR e.person_id <> per.id OR e.status = 'ENDED')) THEN
        probs := probs || ('Staff number ' || v_no || ' is already on an employment record; a return to service is a Movement (reinstatement).');
    END IF;
    IF v_cat NOT IN ('ACADEMIC', 'NON_ACADEMIC') THEN probs := probs || 'The category is ACADEMIC or NON_ACADEMIC.'::text; END IF;
    SELECT x.grade, x.step, x.category INTO g FROM hrm.grade x WHERE upper(x.grade) = v_grade AND x.step = v_step;
    IF g.grade IS NULL THEN
        probs := probs || ('Grade ' || coalesce(nullif(v_grade, ''), '(none)') || ' step ' || coalesce(v_step::text, '(none)') || ' is not set up; set it on Salary grades first.');
    ELSIF v_cat IN ('ACADEMIC', 'NON_ACADEMIC') AND g.category <> v_cat THEN
        probs := probs || (g.grade || CASE g.category WHEN 'ACADEMIC' THEN ' is an academic grade.' ELSE ' is a non-academic grade.' END);
    END IF;
    IF v_date IS NULL THEN probs := probs || 'The date of appointment is a day (YYYY-MM-DD or DD/MM/YYYY).'::text;
    ELSIF v_date < DATE '1960-01-01' OR v_date > current_date + 366 THEN probs := probs || 'The date of appointment is from 1960 and at most a year ahead.'::text;
    END IF;
    IF v_dept_in IS NOT NULL THEN
        SELECT d.code INTO v_dept FROM ref.department d WHERE (upper(d.code) = v_dept_in OR upper(d.name) = v_dept_in) AND d.ended_on IS NULL LIMIT 1;
        IF v_dept IS NULL THEN probs := probs || ('No live department ' || v_dept_in || '.'); END IF;
    END IF;
    IF v_unit_in IS NOT NULL THEN
        SELECT u.code INTO v_unit FROM ref.unit u WHERE (upper(u.code) = v_unit_in OR upper(u.name) = v_unit_in) AND u.ended_on IS NULL LIMIT 1;
        IF v_unit IS NULL THEN probs := probs || ('No live unit ' || v_unit_in || '.'); END IF;
    END IF;
    IF v_cat = 'ACADEMIC' AND v_dept_in IS NULL THEN probs := probs || 'An academic appointment names the department.'::text;
    ELSIF v_dept_in IS NULL AND v_unit_in IS NULL THEN probs := probs || 'Name the department or the unit of the appointment.'::text;
    END IF;
    IF v_sex <> '' AND v_sex NOT IN ('M', 'F', 'MALE', 'FEMALE') THEN probs := probs || 'Sex is M or F.'::text; END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN probs := probs || 'The e-mail address is not one.'::text; END IF;
    -- V749: another person's, verified — left off, the rest made; held by another record unverified — refused, as V510 refused it
    v_taken := v_email IS NOT NULL AND iam.email_verified_elsewhere(per.id, v_email);
    IF v_taken THEN
        warns := warns || ('The e-mail ' || v_email || ' is another person''s, verified on their record: the appointment is made without it, and the member of staff verifies their own at My identity.');
    ELSIF v_email IS NOT NULL AND EXISTS (SELECT 1 FROM iam.person x WHERE lower(btrim(x.email)) = v_email AND x.id IS DISTINCT FROM per.id) THEN
        probs := probs || ('The e-mail ' || v_email || ' belongs to another person.');
    END IF;
    IF v_phone IS NOT NULL AND v_phone !~ '^\+?\d{7,15}$' THEN probs := probs || 'The phone number is 7 to 15 digits.'::text; END IF;
    IF v_acct <> '' AND length(v_acct) < 4 THEN probs := probs || 'The account number has at least four digits (only the last four are kept).'::text; END IF;
    IF v_pin IS NOT NULL AND v_pin !~ '^[A-Z0-9]{6,20}$' THEN probs := probs || 'The pension PIN is 6 to 20 letters and digits.'::text; END IF;
    RETURN jsonb_build_object(
        'ok', cardinality(probs) = 0, 'problems', to_jsonb(probs), 'warnings', to_jsonb(warns),
        'action', CASE WHEN per.id IS NOT NULL THEN 'LINK' ELSE 'CREATE' END, 'person_id', per.id,
        'name', CASE WHEN per.id IS NOT NULL THEN upper(btrim(per.surname)) || ', ' || btrim(per.given_names) ELSE upper(v_sur) || ', ' || v_given END,
        'staff_no', v_no, 'category', v_cat, 'grade', coalesce(g.grade, v_grade), 'step', v_step, 'appointment_date', v_date,
        'department', v_dept, 'unit', v_unit,
        'sex', CASE WHEN v_sex IN ('M', 'MALE') THEN 'M' WHEN v_sex IN ('F', 'FEMALE') THEN 'F' END,
        'email', CASE WHEN NOT v_taken THEN v_email END, 'email_left_off', CASE WHEN v_taken THEN v_email END,
        'phone', v_phone, 'account_last4', CASE WHEN length(v_acct) >= 4 THEN right(v_acct, 4) END, 'pension_pin', v_pin);
END $$;
COMMENT ON FUNCTION hrm.appointment_check(jsonb) IS
  'V510/V749: what an appointment row would do (LINK an existing person by staff number, or CREATE one) and every reason it may not: staff number, person already in employment, staff number on an employment record, category, grade and step set up in the category, date, department or unit, sex, e-mail (one another record holds unverified, case and spaces aside), phone, account and pension; an e-mail another person holds verified (iam.email_verified_elsewhere) is a warning, not a reason — email NULL and email_left_off the address, so the appointment is made without it; writes nothing';
COMMENT ON FUNCTION hrm.appoint(jsonb) IS
  'V510/V749: Human Resources makes an appointment — the person (made, or linked by staff number), the establishment record and the ACTIVE employment record — refused with every reason hrm.appointment_check gives; the e-mail placed (on a new person, or on a linked one with none) only as the check returns it, so never an address another person holds verified (left off: the check''s email_left_off)';

-- an upload of appointments (V510, restated): each appointed row says the address left off, as the check said it
CREATE OR REPLACE FUNCTION hrm.appoint_many(p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); chk jsonb; x jsonb; rowval jsonb; i int := 0; made int := 0; out jsonb := '[]'::jsonb; v_emp uuid;
BEGIN
    IF coalesce(v_office, '') NOT IN ('hrm', 'super') THEN
        RAISE EXCEPTION 'HR_APPOINT_OFFICE: an appointment is made by Human Resources' USING ERRCODE = '42501';
    END IF;
    IF jsonb_array_length(coalesce(p_rows, '[]'::jsonb)) > 2000 THEN
        RAISE EXCEPTION 'HR_APPOINT_TOO_MANY: an upload holds at most 2,000 appointments' USING ERRCODE = '23514';
    END IF;
    chk := hrm.appointments_check(p_rows);
    FOR x IN SELECT value FROM jsonb_array_elements(chk) LOOP
        i := i + 1;
        rowval := p_rows->(i - 1);
        IF (x->>'ok')::boolean THEN
            v_emp := hrm.appoint(rowval);
            made := made + 1;
            out := out || (jsonb_build_object('row', x->>'row', 'staff_no', x->>'staff_no', 'name', x->>'name', 'appointed', true, 'employment_id', v_emp)
                           || CASE WHEN x->>'email_left_off' IS NOT NULL THEN jsonb_build_object('email_left_off', x->>'email_left_off') ELSE '{}'::jsonb END);
        ELSE
            out := out || jsonb_build_object('row', x->>'row', 'staff_no', x->>'staff_no', 'name', x->>'name', 'appointed', false, 'problems', x->'problems');
        END IF;
    END LOOP;
    RETURN jsonb_build_object('appointed', made, 'skipped', i - made, 'rows', out);
END $$;
COMMENT ON FUNCTION hrm.appoint_many(jsonb) IS
  'V510/V749: an upload of appointments: each row that passes hrm.appointments_check (a staff number repeated in the file refused) is appointed — with email_left_off where the row''s e-mail is another person''s, verified, and was left off; the rest are listed with their reasons';

-- ── the code reaches the mailbox alone ──
-- a message that carries what only its mailbox should hold: a code that verifies or confirms an address, a link that resets a password
-- or signs in for the first time (…?token=: the staff, student, applicant and JUPEB resets, an examiner's activation), a referee's form
-- (/pg/referee/…), a partnership's status page (/partnerships/status/…). Read from the template and the words, so the senders that set
-- no template are known too
CREATE FUNCTION platform.notice_carries_secret(p_template_key text, p_body text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(p_template_key, '') = 'STAFF_EMAIL_CODE'
        OR coalesce(p_body, '') ~* '[?&]token=|/pg/referee/|/partnerships/status/|\mcode to (confirm|verify)\M'
$$;
COMMENT ON FUNCTION platform.notice_carries_secret(text, text) IS
  'V749: whether a message carries a secret for its mailbox alone — the staff e-mail code (STAFF_EMAIL_CODE), a student''s contact confirmation code (V575: "your code to confirm"), a password reset or first sign-in link (?token=), a referee''s form, a partnership''s status page; such a message is never listed back on the portal (platform.person_notices; a student''s notices on the dashboard). A public check code ("Verification code:" on a report sent) is not one.';

-- the code's words are kept only until its message has gone, or will not go (sent, failed for good, cancelled): then the outbox holds
-- these words in their place. The audit trail keeps the message as it was queued, as it keeps every message's
CREATE FUNCTION platform.notice_code_scrubbed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.body := 'A code to verify an e-mail address on a MOAUM portal staff record was sent in this message. The code is not kept once the message has gone.';
    RETURN NEW;
END $$;
CREATE TRIGGER trg_notice_code_scrubbed BEFORE INSERT OR UPDATE ON platform.notice
    FOR EACH ROW WHEN (NEW.template_key = 'STAFF_EMAIL_CODE' AND NEW.state <> 'QUEUED'
                       AND NEW.body IS DISTINCT FROM 'A code to verify an e-mail address on a MOAUM portal staff record was sent in this message. The code is not kept once the message has gone.')
    EXECUTE FUNCTION platform.notice_code_scrubbed();
COMMENT ON FUNCTION platform.notice_code_scrubbed() IS
  'V749: the body of a staff e-mail code''s message (STAFF_EMAIL_CODE) is replaced, once the message is no longer queued (sent, failed for good, cancelled), by words that do not carry the code (trg_notice_code_scrubbed)';

-- a code decided before its message went (replaced by a later one, verified, run out, taken): the message still queued is cancelled —
-- its words then scrubbed as above
CREATE FUNCTION iam.email_code_decided() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    UPDATE platform.notice n
       SET state = 'CANCELLED', cancelled_at = now(), cancelled_by = NEW.person_id,
           cancel_reason = 'V749: the code was ' || lower(NEW.outcome) || ' before its message went'
     WHERE n.about_kind = 'email_verification' AND n.about_id = NEW.id AND n.state = 'QUEUED';
    RETURN NULL;
END $$;
CREATE TRIGGER trg_email_code_decided AFTER UPDATE OF outcome ON iam.email_verification
    FOR EACH ROW WHEN (OLD.outcome IS NULL AND NEW.outcome IS NOT NULL) EXECUTE FUNCTION iam.email_code_decided();
COMMENT ON FUNCTION iam.email_code_decided() IS
  'V749: a code decided (REPLACED, VERIFIED, EXPIRED, TAKEN) cancels its message if it is still queued (trg_email_code_decided), so a code no longer good is not sent and its words are not kept';

-- the outbox read by its ways to a person, newest first (then by id, as the list is ordered, so no walk is sorted): by address (the
-- address as the message went, case and spaces aside); by what a message is filed against (V025's ix_notice_about, which had no
-- time, replaced by one that has); and, by address, the notices of a person's work alone (ix_notice_work), so an address not verified
-- is never walked through the rest of its mail — the Head of ICT Support's one notice a ticket, filed against them, among it. The
-- person's own notices below are walked so and stop at the limit, whatever the number a person has been sent
CREATE INDEX ix_notice_recipient ON platform.notice (lower(btrim(recipient)), created_at DESC, id);
DROP INDEX platform.ix_notice_about;
CREATE INDEX ix_notice_about ON platform.notice (about_kind, about_id, created_at DESC, id);
CREATE INDEX ix_notice_work ON platform.notice (lower(btrim(recipient)), created_at DESC, id)
    WHERE about_kind IN ('offering', 'score_sheet', 'transfer', 'clearance_document', 'deferment', 'putme_score_export', 'report_snapshot')
       OR (about_kind = 'application' AND template_key = 'OFFICE_TELL');

-- an office's notice (V266, restated): marked OFFICE_TELL. Filed 'application' as an applicant's own messages are, it is known from
-- them by the mark alone — whoever holds the address now — so a member of staff's own notices list the office's, never an applicant's
CREATE OR REPLACE FUNCTION admissions.tell_office(p_office text, p_subject text, p_body text, p_about uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT DISTINCT pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
              WHERE a.office_code = p_office AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.email IS NOT NULL LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'application', p_about, NULL, 'OFFICE_TELL', NULL);
    END LOOP;
END $$;
COMMENT ON FUNCTION admissions.tell_office(text, text, text, uuid) IS
  'V266/V749: an e-mail to every holder of the office today with an address (the calendar, the session''s turn, the audit chain, Human Resources'' staff reach, the Bursary''s applicant fees, the screening and admission desks), filed ''application'' and marked OFFICE_TELL (template_key), by which a member of staff''s own notices (platform.person_notices) tell it from an applicant''s own message';

-- a member of staff's own notices, as GET /api/v1/me/notices lists them: those filed against them (about the person, or a clearance
-- chase of theirs); by address, those sent to the e-mail they verified (never one filed against another person); and the notices of
-- their work sent to an e-mail or phone on their record that no one else's record holds — a course allocated (offering), a score sheet,
-- a transfer, a clearance document or a deferment at their desk, a Post-UTME export, a report sent from the portal (report_snapshot:
-- the return's title, period and public check code), and an office's notice (admissions.tell_office: 'application' marked
-- OFFICE_TELL). Not by an address unverified: an applicant's own message (filed 'application' with no mark: the address may since have
-- been corrected away from the applicant's account), nor a reply to a sign-in ticket ('ticket': the request from the sign-in page names
-- no one, so its replies go to whoever typed the address) — both are listed only to the address verified. Never a message carrying a
-- code or a link for its mailbox alone (platform.notice_carries_secret): the portal never shows what proves the mailbox, so a person
-- never proves a mailbox from the portal. Each way is walked newest first by its own index (ix_notice_about, ix_notice_recipient, and
-- ix_notice_work for an address not verified: the key, then the time and the id, the order of the list; the person's key a scalar
-- subquery, so the walk stays in order), the secret asked of each message walked, and each stops at the limit; the newest of all of
-- them, up to the limit, are listed. Never a bitmap scan: the planner cannot know how many messages a person's key has (it guesses a
-- couple of dozen), and for a limit above its guess it would now and then read every one of an address's messages, test each and
-- sort them (60,000 for one address took 0.85 s), where the walk in order reads only what it lists
CREATE FUNCTION platform.person_notices(p_person uuid, p_limit int DEFAULT 100)
RETURNS TABLE (id uuid, channel text, subject text, body text, about_kind text, about_id uuid, created_at timestamptz, state text,
               sent_at timestamptz, priority text, template_key text, read_at timestamptz)
LANGUAGE sql STABLE SET enable_bitmapscan = off AS $$
    WITH me AS MATERIALIZED (
        SELECT nullif(lower(btrim(coalesce(p.email, ''))), '') AS email, nullif(btrim(coalesce(p.phone, '')), '') AS phone,
               EXISTS (SELECT 1 FROM iam.person_email_verified v WHERE v.person_id = p.id AND v.email = lower(btrim(p.email))) AS verified,
               NOT EXISTS (SELECT 1 FROM iam.person o WHERE o.id <> p.id AND lower(btrim(o.email)) = lower(btrim(p.email))) AS email_alone,
               NOT EXISTS (SELECT 1 FROM iam.person o WHERE o.id <> p.id AND btrim(o.phone) = btrim(p.phone)) AS phone_alone
          FROM iam.person p WHERE p.id = p_person),
    mine AS (
        (SELECT n.id, n.created_at FROM platform.notice n
          WHERE n.about_kind = 'person' AND n.about_id = p_person
            AND NOT platform.notice_carries_secret(n.template_key, n.body)
          ORDER BY n.created_at DESC, n.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500)))
        UNION
        (SELECT n.id, n.created_at FROM platform.notice n
          WHERE n.about_kind = 'clearance_chase' AND n.about_id = p_person
            AND NOT platform.notice_carries_secret(n.template_key, n.body)
          ORDER BY n.created_at DESC, n.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500)))
        UNION
        -- every message to the address verified, but one filed against another person
        (SELECT n.id, n.created_at FROM platform.notice n
          WHERE lower(btrim(n.recipient)) = (SELECT m.email FROM me m WHERE m.verified) AND n.channel = 'EMAIL'
            AND NOT (coalesce(n.about_kind, '') IN ('person', 'staff', 'clearance_chase') AND n.about_id IS DISTINCT FROM p_person)
            AND NOT platform.notice_carries_secret(n.template_key, n.body)
          ORDER BY n.created_at DESC, n.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500)))
        UNION
        -- an address not verified, theirs alone on the register: the notices of their work (with the address verified, the way above
        -- lists these and more)
        (SELECT n.id, n.created_at FROM platform.notice n
          WHERE lower(btrim(n.recipient)) = (SELECT m.email FROM me m WHERE m.email_alone AND NOT m.verified) AND n.channel = 'EMAIL'
            AND (n.about_kind IN ('offering', 'score_sheet', 'transfer', 'clearance_document', 'deferment', 'putme_score_export', 'report_snapshot')
                 OR (n.about_kind = 'application' AND n.template_key = 'OFFICE_TELL'))
            AND NOT platform.notice_carries_secret(n.template_key, n.body)
          ORDER BY n.created_at DESC, n.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500)))
        UNION
        (SELECT n.id, n.created_at FROM platform.notice n
          WHERE lower(btrim(n.recipient)) = (SELECT lower(m.phone) FROM me m WHERE m.phone_alone) AND btrim(n.recipient) = (SELECT m.phone FROM me m)
            AND n.channel = 'SMS'
            AND n.about_kind IN ('offering', 'score_sheet', 'transfer', 'clearance_document', 'deferment', 'putme_score_export', 'report_snapshot')
            AND NOT platform.notice_carries_secret(n.template_key, n.body)
          ORDER BY n.created_at DESC, n.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500)))),
    newest AS (
        SELECT k.id, k.created_at FROM mine k ORDER BY k.created_at DESC, k.id LIMIT greatest(1, least(coalesce(p_limit, 100), 500)))
    SELECT n.id, n.channel, n.subject, n.body, n.about_kind, n.about_id, n.created_at, n.state, n.sent_at, n.priority, n.template_key, r.read_at
      FROM newest k JOIN platform.notice n ON n.id = k.id LEFT JOIN platform.notice_read r ON r.notice_id = n.id
     ORDER BY k.created_at DESC, k.id
$$;
COMMENT ON FUNCTION platform.person_notices(uuid, int) IS
  'V749: a member of staff''s own notices (GET /api/v1/me/notices): filed against them (person, clearance_chase); sent to the e-mail they verified (not one filed against another person); and, to an e-mail or phone no other record holds, the notices of their work — offering, score_sheet, transfer, clearance_document, deferment, putme_score_export, report_snapshot, and an office''s notice (application marked OFFICE_TELL by admissions.tell_office); an applicant''s own message (application, unmarked) and a sign-in ticket''s reply (ticket) only to the address verified — never a message carrying a code or a link for its mailbox alone (platform.notice_carries_secret). Each way walked newest first by ix_notice_about, ix_notice_recipient or ix_notice_work and stopped at the limit. Newest first (then by id), at most 500.';

-- ── 4 · a member of staff's photograph: each upload kept, enhanced, and accepted before it is the card photograph ─────────────────
CREATE TABLE hrm.staff_photo_submission (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id              uuid NOT NULL REFERENCES iam.person (id) ON DELETE CASCADE,
    state                  text NOT NULL CONSTRAINT ck_sps_state CHECK (state IN ('PROCESSED', 'FAILED', 'ACCEPTED', 'DISCARDED', 'SUPERSEDED')),
    original_type          text NOT NULL CONSTRAINT ck_sps_original_type CHECK (original_type IN ('image/jpeg', 'image/png')),
    original_bytes         integer NOT NULL CONSTRAINT ck_sps_original_bytes CHECK (original_bytes > 0),
    original_content       bytea NULL,
    original_object        uuid NULL REFERENCES platform.file_object (id),
    enhanced_content       bytea NULL,
    enhanced_object        uuid NULL REFERENCES platform.file_object (id),
    enhanced_width         integer NULL CONSTRAINT ck_sps_width CHECK (enhanced_width > 0),
    enhanced_height        integer NULL CONSTRAINT ck_sps_height CHECK (enhanced_height > 0),
    assessment             jsonb NULL,
    enhancement            jsonb NULL,
    quality                text NULL CONSTRAINT ck_sps_quality CHECK (quality IN ('GOOD', 'FAIR', 'REPLACE')),
    error                  text NULL,
    previous_photo_object  uuid NULL REFERENCES platform.file_object (id),
    previous_photo_content bytea NULL,
    previous_photo_type    text NULL CONSTRAINT ck_sps_previous_type CHECK (previous_photo_type IN ('image/jpeg', 'image/png')),
    created_at             timestamptz NOT NULL DEFAULT now(),
    decided_at             timestamptz NULL,
    -- the original is kept, in the row or in the file store, never both; so is the enhanced copy and the photograph it replaced
    CONSTRAINT ck_sps_original_one_place CHECK (num_nonnulls(original_content, original_object) = 1),
    CONSTRAINT ck_sps_enhanced_one_place CHECK (NOT (enhanced_content IS NOT NULL AND enhanced_object IS NOT NULL)),
    CONSTRAINT ck_sps_previous_one_place CHECK (NOT (previous_photo_content IS NOT NULL AND previous_photo_object IS NOT NULL)),
    -- a processed or accepted photograph has its enhanced copy; one waiting for its holder's word is undecided, the rest decided
    CONSTRAINT ck_sps_enhanced_when CHECK (state NOT IN ('PROCESSED', 'ACCEPTED') OR num_nonnulls(enhanced_content, enhanced_object) = 1),
    CONSTRAINT ck_sps_decided CHECK ((state IN ('PROCESSED', 'FAILED')) = (decided_at IS NULL))
);
CREATE INDEX ix_staff_photo_submission_person ON hrm.staff_photo_submission (person_id, created_at DESC);
COMMENT ON TABLE hrm.staff_photo_submission IS
  'V749: each photograph a member of staff uploads on the identity form — the original (kept), the enhanced copy, the assessment, what was done to it and the verdict (GOOD, FAIR, REPLACE); PROCESSED or FAILED until the holder accepts it (it becomes the card photograph, the one it replaced kept here) or sets it aside';
SELECT audit.exempt('hrm.staff_photo_submission',
    'V749: the uploaded staff photographs, original and enhanced, up to several megabytes each — heavy blobs kept off the spine like hrm.staff_photo (V109); every upload, enhancement, retry, acceptance and discard is on the audited hrm.staff_photo_event, and the file objects on the audited platform.file_object.');

CREATE TABLE hrm.staff_photo_event (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id     uuid NOT NULL REFERENCES iam.person (id) ON DELETE CASCADE,
    submission_id uuid NULL REFERENCES hrm.staff_photo_submission (id) ON DELETE CASCADE,
    -- REFUSED: a file refused as it was read (damaged, not a photograph, too large …): nothing of it kept, no submission, but counted
    action        text NOT NULL CONSTRAINT ck_spe_action CHECK (action IN ('UPLOADED', 'ENHANCED', 'FAILED', 'RETRIED', 'ACCEPTED', 'DISCARDED', 'REFUSED')),
    at            timestamptz NOT NULL DEFAULT clock_timestamp(),   -- the upload and its enhancement, in one request, in their order
    by            uuid NULL,
    office        text NULL,
    detail        jsonb NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX ix_staff_photo_event_person ON hrm.staff_photo_event (person_id, at DESC);
CREATE INDEX ix_staff_photo_event_submission ON hrm.staff_photo_event (submission_id) WHERE submission_id IS NOT NULL;
COMMENT ON TABLE hrm.staff_photo_event IS
  'V749: what happened to each staff photograph uploaded on the identity form — uploaded, enhanced or failed, retried, accepted as the card photograph, set aside, or refused as it was read (no submission: nothing of the file kept) — with who, from which office, and the particulars';
SELECT audit.attach('hrm.staff_photo_event');

ALTER TABLE hrm.staff_photo ADD COLUMN submission_id uuid NULL REFERENCES hrm.staff_photo_submission (id) ON DELETE SET NULL;
COMMENT ON COLUMN hrm.staff_photo.submission_id IS
  'V749: the upload this photograph was accepted from (enhanced on the identity form); NULL for a photograph set before V749 or uploaded the old way';

-- the person a photograph act is for: the signed-in member of staff (not a student or applicant), on the register
CREATE FUNCTION hrm.staff_photo_holder() RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid; office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF who IS NULL OR office IS NULL THEN
        RAISE EXCEPTION 'PHOTO_ACTOR: a photograph is uploaded by the member of staff themselves, signed in' USING ERRCODE = '23514';
    END IF;
    IF office IN ('student', 'applicant') OR NOT EXISTS (SELECT 1 FROM iam.person WHERE id = who) THEN
        RAISE EXCEPTION 'PHOTO_NOT_STAFF: the staff photograph is a member of staff''s; a student''s passport is kept on the student''s portal'
            USING ERRCODE = '42501';
    END IF;
    RETURN who;
END $$;

-- every original is kept, and every file is read, so the work is bounded: twenty uploads, retries and refused files an hour. Asked before
-- the image is decoded or enhanced (the API's first short transaction), and again as the upload or the retry is kept, under the holder's
-- lock. A file refused as it was read is counted too (REFUSED, below): a damaged photograph can be read in full before it is refused,
-- and one free to send again and again would keep the two photographs the portal works at once busy for everyone
CREATE FUNCTION hrm.staff_photo_upload_allowed() RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE who uuid := hrm.staff_photo_holder();
BEGIN
    IF (SELECT count(*) FROM hrm.staff_photo_event e
         WHERE e.person_id = who AND e.action IN ('UPLOADED', 'RETRIED', 'REFUSED') AND e.at > now() - interval '1 hour') >= 20 THEN
        RAISE EXCEPTION 'PHOTO_UPLOAD_LIMIT: twenty photographs have been uploaded, enhanced again or refused in the last hour; accept one of them, or try again later'
            USING ERRCODE = '23514';
    END IF;
    RETURN who;
END $$;
COMMENT ON FUNCTION hrm.staff_photo_upload_allowed() IS
  'V749: the signed-in member of staff (hrm.staff_photo_holder), refused PHOTO_UPLOAD_LIMIT past twenty uploads, retries and refused files in the hour (UPLOADED, RETRIED and REFUSED events). The API asks it before any image work; the write functions ask it again as the final guard.';

-- a file refused as it was read — damaged, not a photograph, too large, a print file — recorded so it counts among the hour's twenty:
-- no submission (nothing of the file is kept), the refusal's code and the size; on a retry, the holder's own upload it was
CREATE FUNCTION hrm.record_my_staff_photo_refusal(p_code text, p_bytes integer, p_submission uuid DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE who uuid := hrm.staff_photo_holder(); office text := nullif(current_setting('moaum.actor_office', true), ''); v_id uuid;
BEGIN
    INSERT INTO hrm.staff_photo_event (person_id, submission_id, action, by, office, detail)
    VALUES (who, (SELECT s.id FROM hrm.staff_photo_submission s WHERE s.id = p_submission AND s.person_id = who), 'REFUSED', who, office,
            jsonb_strip_nulls(jsonb_build_object('code', nullif(btrim(coalesce(p_code, '')), ''), 'bytes', p_bytes,
                                                 'retry', CASE WHEN p_submission IS NOT NULL THEN true END)))
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
COMMENT ON FUNCTION hrm.record_my_staff_photo_refusal(text, integer, uuid) IS
  'V749: the signed-in member of staff''s file refused as it was read (the API, in a transaction of its own, after the refusal): event REFUSED with the code and the size, the submission only on a retry of the holder''s own; counted by hrm.staff_photo_upload_allowed among the hour''s twenty';

CREATE FUNCTION hrm.add_my_staff_photo_submission(p_original_type text, p_original_bytes integer, p_original_content bytea, p_original_object uuid,
                                                  p_enhanced_content bytea, p_enhanced_object uuid, p_enhanced_width integer, p_enhanced_height integer,
                                                  p_assessment jsonb, p_enhancement jsonb, p_quality text, p_error text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE who uuid := hrm.staff_photo_holder(); office text := nullif(current_setting('moaum.actor_office', true), '');
        v_id uuid := gen_random_uuid(); v_done boolean := p_enhanced_content IS NOT NULL OR p_enhanced_object IS NOT NULL;
        v_error text := CASE WHEN p_enhanced_content IS NOT NULL OR p_enhanced_object IS NOT NULL THEN nullif(btrim(coalesce(p_error, '')), '')
                             ELSE coalesce(nullif(btrim(coalesce(p_error, '')), ''), 'The photograph could not be enhanced') END;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('staff_photo:' || who::text));
    -- every original is kept, so the uploads are bounded (the API asked before the work; asked again here, under the lock)
    PERFORM hrm.staff_photo_upload_allowed();
    INSERT INTO hrm.staff_photo_submission (id, person_id, state, original_type, original_bytes, original_content, original_object,
                                            enhanced_content, enhanced_object, enhanced_width, enhanced_height, assessment, enhancement, quality, error)
    VALUES (v_id, who, CASE WHEN v_done THEN 'PROCESSED' ELSE 'FAILED' END, p_original_type, p_original_bytes,
            CASE WHEN p_original_object IS NULL THEN p_original_content END, p_original_object,
            CASE WHEN p_enhanced_object IS NULL THEN p_enhanced_content END, p_enhanced_object,
            CASE WHEN v_done THEN p_enhanced_width END, CASE WHEN v_done THEN p_enhanced_height END,
            p_assessment, p_enhancement, p_quality, v_error);
    INSERT INTO hrm.staff_photo_event (person_id, submission_id, action, by, office, detail)
    VALUES (who, v_id, 'UPLOADED', who, office, jsonb_build_object('type', p_original_type, 'bytes', p_original_bytes));
    INSERT INTO hrm.staff_photo_event (person_id, submission_id, action, by, office, detail)
    VALUES (who, v_id, CASE WHEN v_done THEN 'ENHANCED' ELSE 'FAILED' END, who, office,
            CASE WHEN v_done THEN jsonb_build_object('quality', p_quality, 'width', p_enhanced_width, 'height', p_enhanced_height)
                 ELSE jsonb_build_object('error', v_error, 'quality', p_quality) END);
    RETURN v_id;
END $$;
COMMENT ON FUNCTION hrm.add_my_staff_photo_submission(text, integer, bytea, uuid, bytea, uuid, integer, integer, jsonb, jsonb, text, text) IS
  'V749: the signed-in member of staff''s uploaded photograph recorded — the original always (bytes, or its file object), the enhanced copy when the enhancement succeeded (PROCESSED) or the reason it did not (FAILED); events UPLOADED and ENHANCED or FAILED; at most twenty uploads and retries an hour (PHOTO_UPLOAD_LIMIT, hrm.staff_photo_upload_allowed). Returns the submission.';

-- the holder's own submission, locked, in one of the states given — or the refusal that says why not
CREATE FUNCTION hrm.my_staff_photo_submission(p_id uuid, p_states text[]) RETURNS hrm.staff_photo_submission LANGUAGE plpgsql AS $$
DECLARE who uuid := hrm.staff_photo_holder(); x hrm.staff_photo_submission;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('staff_photo:' || who::text));
    SELECT * INTO x FROM hrm.staff_photo_submission s WHERE s.id = p_id FOR UPDATE;
    IF NOT FOUND OR x.person_id <> who THEN
        RAISE EXCEPTION 'PHOTO_NOT_YOURS: this is not a photograph you uploaded' USING ERRCODE = '42501';
    END IF;
    IF NOT (x.state = ANY (p_states)) THEN
        RAISE EXCEPTION 'PHOTO_STATE: %', CASE x.state WHEN 'ACCEPTED' THEN 'this photograph is already your card photograph'
                                                       WHEN 'FAILED' THEN 'this photograph could not be enhanced; retry the enhancement or upload another'
                                                       WHEN 'PROCESSED' THEN 'this photograph is enhanced and waiting for you to accept it or upload another'
                                                       ELSE 'this photograph was set aside; upload another' END
            USING ERRCODE = '23514';
    END IF;
    RETURN x;
END $$;

-- a retry of the enhancement on the original kept (the API reads it again and does the work again)
CREATE FUNCTION hrm.update_my_staff_photo_submission(p_id uuid, p_enhanced_content bytea, p_enhanced_object uuid, p_enhanced_width integer,
                                                     p_enhanced_height integer, p_assessment jsonb, p_enhancement jsonb, p_quality text, p_error text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE x hrm.staff_photo_submission := hrm.my_staff_photo_submission(p_id, ARRAY['PROCESSED', 'FAILED']);
        office text := nullif(current_setting('moaum.actor_office', true), '');
        v_done boolean := p_enhanced_content IS NOT NULL OR p_enhanced_object IS NOT NULL; v_state text;
        v_error text := CASE WHEN p_enhanced_content IS NOT NULL OR p_enhanced_object IS NOT NULL THEN nullif(btrim(coalesce(p_error, '')), '')
                             ELSE coalesce(nullif(btrim(coalesce(p_error, '')), ''), 'The photograph could not be enhanced') END;
BEGIN
    -- a retry is work as an upload is: the same twenty an hour (the API asked before the work; asked again here, under the lock)
    PERFORM hrm.staff_photo_upload_allowed();
    v_state := CASE WHEN v_done THEN 'PROCESSED' ELSE 'FAILED' END;
    UPDATE hrm.staff_photo_submission
       SET state = v_state,
           enhanced_content = CASE WHEN p_enhanced_object IS NULL THEN p_enhanced_content END, enhanced_object = p_enhanced_object,
           enhanced_width = CASE WHEN v_done THEN p_enhanced_width END, enhanced_height = CASE WHEN v_done THEN p_enhanced_height END,
           assessment = p_assessment, enhancement = p_enhancement, quality = p_quality, error = v_error
     WHERE id = x.id;
    INSERT INTO hrm.staff_photo_event (person_id, submission_id, action, by, office, detail)
    VALUES (x.person_id, x.id, 'RETRIED', x.person_id, office,
            jsonb_build_object('before', x.state, 'state', v_state, 'quality', p_quality, 'error', v_error));
    RETURN v_state;
END $$;
COMMENT ON FUNCTION hrm.update_my_staff_photo_submission(uuid, bytea, uuid, integer, integer, jsonb, jsonb, text, text) IS
  'V749: the enhancement of the holder''s own photograph done again (only one PROCESSED or FAILED, never decided): the new enhanced copy, assessment and verdict, or the reason it failed; event RETRIED; counted with the uploads, twenty an hour (PHOTO_UPLOAD_LIMIT). Returns the new state.';

CREATE FUNCTION hrm.accept_my_staff_photo(p_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE x hrm.staff_photo_submission := hrm.my_staff_photo_submission(p_id, ARRAY['PROCESSED']);
        office text := nullif(current_setting('moaum.actor_office', true), '');
        cur hrm.staff_photo; v_bytes bigint; v_superseded int;
BEGIN
    IF x.quality = 'REPLACE' THEN
        RAISE EXCEPTION 'PHOTO_NEEDS_REPLACING: this photograph is not good enough for an identity card (too small or not sharp enough, even enhanced); upload another'
            USING ERRCODE = '23514';
    END IF;
    v_bytes := coalesce(length(x.enhanced_content), (SELECT f.size_bytes FROM platform.file_object f WHERE f.id = x.enhanced_object));
    -- the photograph it replaces is kept on the submission
    SELECT * INTO cur FROM hrm.staff_photo ph WHERE ph.person_id = x.person_id FOR UPDATE;
    UPDATE hrm.staff_photo_submission
       SET state = 'ACCEPTED', decided_at = now(),
           previous_photo_object = cur.object_id, previous_photo_content = cur.content, previous_photo_type = cur.content_type
     WHERE id = x.id;
    INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content, object_id, updated_at, submission_id)
    VALUES (x.person_id, 'image/jpeg', v_bytes, x.enhanced_content, x.enhanced_object, now(), x.id)
    ON CONFLICT (person_id) DO UPDATE SET
        content_type = excluded.content_type, bytes = excluded.bytes,
        content = excluded.content, object_id = excluded.object_id, updated_at = now(), submission_id = excluded.submission_id;
    UPDATE hrm.staff_photo_submission SET state = 'SUPERSEDED', decided_at = now()
     WHERE person_id = x.person_id AND id <> x.id AND state IN ('PROCESSED', 'FAILED');
    GET DIAGNOSTICS v_superseded = ROW_COUNT;
    INSERT INTO hrm.staff_photo_event (person_id, submission_id, action, by, office, detail)
    VALUES (x.person_id, x.id, 'ACCEPTED', x.person_id, office,
            jsonb_build_object('bytes', v_bytes, 'quality', x.quality, 'previous', cur.person_id IS NOT NULL, 'previousType', cur.content_type,
                               'previousSubmission', cur.submission_id, 'superseded', v_superseded));
    RETURN jsonb_build_object('id', x.id, 'state', 'ACCEPTED', 'contentType', 'image/jpeg', 'bytes', v_bytes, 'objectId', x.enhanced_object,
                              'previousKept', cur.person_id IS NOT NULL, 'superseded', v_superseded);
END $$;
COMMENT ON FUNCTION hrm.accept_my_staff_photo(uuid) IS
  'V749: the holder accepts their enhanced photograph (PROCESSED, never one judged REPLACE: PHOTO_NEEDS_REPLACING): it becomes hrm.staff_photo (JPEG, with the submission named), the photograph it replaced kept on the submission, the holder''s other undecided uploads SUPERSEDED; event ACCEPTED.';

CREATE FUNCTION hrm.discard_my_staff_photo(p_id uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE x hrm.staff_photo_submission := hrm.my_staff_photo_submission(p_id, ARRAY['PROCESSED', 'FAILED']);
        office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    UPDATE hrm.staff_photo_submission SET state = 'DISCARDED', decided_at = now() WHERE id = x.id;
    INSERT INTO hrm.staff_photo_event (person_id, submission_id, action, by, office, detail)
    VALUES (x.person_id, x.id, 'DISCARDED', x.person_id, office, jsonb_build_object('before', x.state));
    RETURN 'DISCARDED';
END $$;
COMMENT ON FUNCTION hrm.discard_my_staff_photo(uuid) IS
  'V749: the holder sets an undecided photograph aside (DISCARDED); the original stays kept, as every original is; event DISCARDED.';

-- the old upload (V310, restated): a photograph set this way is not an enhanced one accepted on the identity form
CREATE OR REPLACE FUNCTION hrm.set_my_staff_photo(p_content_type text, p_bytes bigint, p_content bytea, p_object_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a photograph is set by the person themselves' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM iam.person WHERE id = who) THEN
        RAISE EXCEPTION 'no person % on the register', who USING ERRCODE = '23503';
    END IF;
    INSERT INTO hrm.staff_photo (person_id, content_type, bytes, content, object_id, updated_at)
    VALUES (who, p_content_type, p_bytes, CASE WHEN p_object_id IS NULL THEN p_content END, p_object_id, now())
    ON CONFLICT (person_id) DO UPDATE SET
        content_type = excluded.content_type, bytes = excluded.bytes,
        content = excluded.content, object_id = excluded.object_id, updated_at = now(),
        -- V749: no longer the enhanced photograph the holder accepted
        submission_id = NULL;
END $$;

-- ── 5 · where a member of staff stands ─────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION iam.staff_identity_state(p_person uuid) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE pe iam.person; ph record; sub hrm.staff_photo_submission; ver iam.person_email_verified; v_open iam.email_verification;
        v_verified boolean; v_blood text; v_confirmed text; v_conf credentials.blood_group_confirmation;
BEGIN
    SELECT * INTO pe FROM iam.person WHERE id = p_person;
    SELECT p.person_id, p.content_type, p.updated_at, p.submission_id INTO ph FROM hrm.staff_photo p WHERE p.person_id = p_person;
    SELECT * INTO sub FROM hrm.staff_photo_submission s WHERE s.person_id = p_person AND s.state IN ('PROCESSED', 'FAILED')
     ORDER BY s.created_at DESC LIMIT 1;
    SELECT * INTO ver FROM iam.person_email_verified v WHERE v.person_id = p_person;
    SELECT * INTO v_open FROM iam.email_verification x WHERE x.person_id = p_person AND x.outcome IS NULL AND x.expires_at > now()
     ORDER BY x.created_at DESC LIMIT 1;
    v_verified := coalesce(ver.email IS NOT NULL AND lower(btrim(pe.email)) = ver.email, false);
    v_blood := credentials.staff_blood_group(p_person);
    v_confirmed := credentials.blood_group_confirmed('STAFF', p_person);
    SELECT * INTO v_conf FROM credentials.blood_group_confirmation c WHERE c.kind = 'STAFF' AND c.holder_id = p_person;
    RETURN jsonb_build_object(
        'staff', iam.staff_in_service(p_person),
        'photo', jsonb_build_object('present', ph.person_id IS NOT NULL, 'enhanced', ph.submission_id IS NOT NULL,
                                    'contentType', ph.content_type, 'updatedAt', ph.updated_at,
                                    'pendingSubmission', sub.id, 'pendingState', sub.state, 'pendingQuality', sub.quality),
        'email', jsonb_build_object('value', nullif(btrim(coalesce(pe.email, '')), ''), 'verified', v_verified,
                                    'verifiedAt', CASE WHEN v_verified THEN ver.verified_at END,
                                    'pending', v_open.email, 'pendingExpiresAt', v_open.expires_at),
        'bloodGroup', jsonb_build_object('value', v_blood, 'confirmed', v_confirmed IS NOT NULL,
                                         'confirmedAt', CASE WHEN v_confirmed IS NOT NULL THEN v_conf.confirmed_at END,
                                         'source', CASE WHEN v_confirmed IS NOT NULL THEN v_conf.source END),
        'complete', ph.submission_id IS NOT NULL AND v_verified AND v_confirmed IS NOT NULL);
END $$;
COMMENT ON FUNCTION iam.staff_identity_state(uuid) IS
  'V749: a member of staff''s identity information — in service (V698), the photograph (on file; enhanced and accepted; an upload waiting for a decision), the e-mail (verified; an address a code was sent to), the blood group (confirmed) — and complete: all three done.';

-- ── 6 · the reports ────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- the passports the attachment store can serve, and the blood groups on the biodata, each read from a small index of its own rather
-- than from the whole table (the reports read the whole register at once: 52,744 passports among 109,740 attachments, 4 blood groups
-- among 539,575 biodata rows on the copy of 11 November 2026)
CREATE INDEX IF NOT EXISTS ix_attachment_passport_on_file ON admissions.attachment (candidate_id, jamb_key)
    WHERE kind = 'PASSPORT' AND (object_id IS NOT NULL OR jsonb_exists(payload, 'dataUrl'));
CREATE INDEX IF NOT EXISTS ix_biodata_blood_group ON people.biodata (student_id) WHERE field = 'blood_group';

-- each student in study (as the card reads it) with the blood group, whether it is confirmed and whether a photograph is on file —
-- read for the whole register at once: the photograph's four places (credentials.has_photo's) are each hashed once, and the inner
-- reading is kept whole (OFFSET 0) so a report testing the photograph several times reads it once a student
CREATE FUNCTION credentials.identity_student_rows(p_faculty text, p_department text, p_programme text, p_level int)
RETURNS TABLE (student_id uuid, matric_no text, admission_no text, jamb_reg_no text, surname text, other_names text, programme_code text,
               programme text, level int, faculty_code text, faculty text, dept_code text, department text, blood_group text,
               blood_confirmed boolean, blood_confirmed_at timestamptz, has_photo boolean)
LANGUAGE sql STABLE AS $$
    SELECT x.id, x.matric_no, x.admission_no, x.jamb_reg_no, x.surname, x.other_names, x.programme_code, x.programme, x.current_level,
           x.faculty_code, x.faculty, x.dept_code, x.department, x.blood_group, x.blood_confirmed, x.blood_confirmed_at, x.has_photo
      FROM (SELECT s.id, s.matric_no, s.admission_no, s.jamb_reg_no, s.surname, s.other_names, s.programme_code, p.name AS programme, s.current_level,
                   p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, g.value AS blood_group,
                   coalesce(c.blood_group = g.value, false) AS blood_confirmed, CASE WHEN c.blood_group = g.value THEN c.confirmed_at END AS blood_confirmed_at,
                   coalesce(s.id IN (SELECT ph.student_id FROM people.student_photo ph)
                            OR s.candidate_id IN (SELECT a.candidate_id FROM admissions.application a
                                                    JOIN admissions.application_document ad ON ad.application_id = a.id AND ad.kind = 'PASSPORT' AND ad.superseded_at IS NULL)
                            OR s.candidate_id IN (SELECT at.candidate_id FROM admissions.attachment at
                                                   WHERE at.kind = 'PASSPORT' AND (at.object_id IS NOT NULL OR jsonb_exists(at.payload, 'dataUrl')))
                            OR upper(btrim(s.jamb_reg_no)) IN (SELECT at.jamb_key FROM admissions.attachment at
                                                                WHERE at.kind = 'PASSPORT' AND (at.object_id IS NOT NULL OR jsonb_exists(at.payload, 'dataUrl'))),
                            false) AS has_photo
              FROM people.student s
              LEFT JOIN ref.programme p ON p.code = s.programme_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN people.biodata b ON b.student_id = s.id AND b.field = 'blood_group'
              LEFT JOIN health.profile h ON h.student_id = s.id
              LEFT JOIN credentials.blood_group_confirmation c ON c.kind = 'STUDENT' AND c.holder_id = s.id
             CROSS JOIN LATERAL (SELECT coalesce(CASE WHEN b.value IS NOT NULL THEN credentials.blood_group_of(b.value) END,
                                                 CASE WHEN h.blood_group IS NOT NULL THEN credentials.blood_group_of(h.blood_group) END) AS value) g
             WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION', 'DORMANT')
               AND (p_faculty IS NULL OR p.faculty_code = p_faculty)
               AND (p_department IS NULL OR p.dept_code = p_department)
               AND (p_programme IS NULL OR s.programme_code = p_programme)
               AND (p_level IS NULL OR s.current_level = p_level)
            OFFSET 0) x
$$;
COMMENT ON FUNCTION credentials.identity_student_rows(text, text, text, int) IS
  'V749: each student in study (admitted, active, on probation, dormant) with the blood group the card reads (credentials.student_blood_group), whether it is confirmed (credentials.blood_group_confirmed) and whether a photograph is on file (credentials.has_photo) — set-based, for the reports';

CREATE FUNCTION credentials.identity_completion_students(p_faculty text DEFAULT NULL, p_department text DEFAULT NULL, p_programme text DEFAULT NULL,
                                                         p_level int DEFAULT NULL)
RETURNS TABLE (total bigint, blood_confirmed bigint, blood_missing bigint, blood_unconfirmed bigint, with_photo bigint, without_photo bigint,
               without_matric bigint, complete bigint, needs_update bigint)
LANGUAGE sql STABLE AS $$
    SELECT count(*), count(*) FILTER (WHERE r.blood_confirmed), count(*) FILTER (WHERE r.blood_group IS NULL),
           count(*) FILTER (WHERE r.blood_group IS NOT NULL AND NOT r.blood_confirmed),
           count(*) FILTER (WHERE r.has_photo), count(*) FILTER (WHERE NOT r.has_photo), count(*) FILTER (WHERE r.matric_no IS NULL),
           count(*) FILTER (WHERE r.blood_confirmed AND r.has_photo AND r.matric_no IS NOT NULL),
           count(*) FILTER (WHERE NOT (r.blood_confirmed AND r.has_photo AND r.matric_no IS NOT NULL))
      FROM credentials.identity_student_rows(p_faculty, p_department, p_programme, p_level) r
$$;
COMMENT ON FUNCTION credentials.identity_completion_students(text, text, text, int) IS
  'V749: the students in study, by faculty, department, programme and level: how many have the blood group confirmed, none, or one not confirmed; a photograph or none; no matriculation number; complete (blood group confirmed, photograph, matriculation number — what the card asks) and not';

CREATE FUNCTION credentials.identity_completion_student_list(p_faculty text, p_department text, p_programme text, p_level int,
                                                             p_missing text, p_q text, p_limit int, p_offset int)
RETURNS TABLE (student_id uuid, matric_no text, name text, programme text, level int, faculty text, department text, blood_group text,
               blood_confirmed boolean, blood_confirmed_at timestamptz, has_photo boolean, complete boolean, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT r.student_id, r.matric_no, btrim(r.surname || ' ' || coalesce(r.other_names, '')), r.programme, r.level, r.faculty, r.department,
           r.blood_group, r.blood_confirmed, r.blood_confirmed_at, r.has_photo,
           r.blood_confirmed AND r.has_photo AND r.matric_no IS NOT NULL, count(*) OVER ()
      FROM credentials.identity_student_rows(p_faculty, p_department, p_programme, p_level) r
     WHERE (p_missing IS NULL OR btrim(p_missing) = ''
            OR (upper(btrim(p_missing)) = 'BLOOD' AND NOT r.blood_confirmed)
            OR (upper(btrim(p_missing)) = 'PHOTO' AND NOT r.has_photo)
            OR (upper(btrim(p_missing)) = 'MATRIC' AND r.matric_no IS NULL)
            OR (upper(btrim(p_missing)) = 'ANY' AND NOT (r.blood_confirmed AND r.has_photo AND r.matric_no IS NOT NULL)))
       AND (p_q IS NULL OR btrim(p_q) = '' OR r.surname ILIKE '%' || btrim(p_q) || '%' OR coalesce(r.other_names, '') ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(r.matric_no, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(r.admission_no, '') ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(r.jamb_reg_no, '') ILIKE '%' || btrim(p_q) || '%')
     ORDER BY r.surname, r.other_names, r.student_id
     LIMIT greatest(1, coalesce(p_limit, 50)) OFFSET greatest(0, coalesce(p_offset, 0))
$$;
COMMENT ON FUNCTION credentials.identity_completion_student_list(text, text, text, int, text, text, int, int) IS
  'V749: the students behind the counts — filtered as the counts are, by what is missing (BLOOD: not confirmed; PHOTO; MATRIC; ANY: not complete; NULL: all) and searched by name or number; paged, with the total';

-- each member of staff in service (V698's roster) with the photograph, the e-mail and the blood group
CREATE FUNCTION credentials.identity_staff_rows(p_faculty text, p_unit text, p_category text)
RETURNS TABLE (person_id uuid, staff_number text, surname text, given_names text, category text, unit_code text, unit text, faculty_code text,
               faculty text, in_office boolean, can_sign_in boolean, has_photo boolean, photo_enhanced boolean, email text, email_verified boolean,
               blood_group text, blood_confirmed boolean)
LANGUAGE sql STABLE AS $$
    SELECT pe.id, pe.staff_number, pe.surname, pe.given_names, coalesce(e.category, sr.category),
           coalesce(sr.home_department, sr.home_unit), coalesce(dp.name, u.name, sr.unit_as_given),
           coalesce(dp.faculty_code, sr.home_faculty), f.name, off.yes,
           off.yes AND EXISTS (SELECT 1 FROM iam.credential cr WHERE cr.person_id = pe.id),
           ph.person_id IS NOT NULL, coalesce(ph.submission_id IS NOT NULL, false),
           nullif(btrim(coalesce(pe.email, '')), ''), coalesce(lower(btrim(pe.email)) = v.email, false),
           cd.blood_group, coalesce(c.blood_group = cd.blood_group, false)
      FROM iam.person pe
      LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
      LEFT JOIN LATERAL (SELECT x.category FROM hrm.employment x WHERE x.person_id = pe.id AND x.status <> 'ENDED'
                          ORDER BY x.appointment_date DESC NULLS LAST LIMIT 1) e ON true
      LEFT JOIN ref.department dp ON dp.code = sr.home_department
      LEFT JOIN ref.unit u ON u.code = sr.home_unit
      LEFT JOIN ref.faculty f ON f.code = coalesce(dp.faculty_code, sr.home_faculty)
     CROSS JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = pe.id AND a.valid_from <= current_date
                                           AND (a.valid_to IS NULL OR a.valid_to >= current_date)) AS yes) off
      LEFT JOIN hrm.staff_photo ph ON ph.person_id = pe.id
      LEFT JOIN iam.person_email_verified v ON v.person_id = pe.id
      LEFT JOIN credentials.staff_card_detail cd ON cd.person_id = pe.id
      LEFT JOIN credentials.blood_group_confirmation c ON c.kind = 'STAFF' AND c.holder_id = pe.id
     WHERE pe.staff_number IS NOT NULL AND btrim(pe.staff_number) <> '' AND pe.ended_on IS NULL
       AND (off.yes OR sr.person_id IS NOT NULL)
       AND (p_faculty IS NULL OR coalesce(dp.faculty_code, sr.home_faculty) = p_faculty)
       AND (p_unit IS NULL OR coalesce(sr.home_department, sr.home_unit) = p_unit)
       AND (p_category IS NULL OR coalesce(e.category, sr.category) = upper(btrim(p_category)))
$$;
COMMENT ON FUNCTION credentials.identity_staff_rows(text, text, text) IS
  'V749: each member of staff in service (credentials.staff_card_roster''s reading), with whether they can sign in (an office and a sign-in, so the dashboard asks them), the photograph (on file; enhanced and accepted), the e-mail (verified) and the blood group (confirmed) — for the reports';

CREATE FUNCTION credentials.identity_completion_staff(p_faculty text DEFAULT NULL, p_unit text DEFAULT NULL, p_category text DEFAULT NULL)
RETURNS TABLE (total bigint, with_photo bigint, without_photo bigint, photo_enhanced bigint, email_verified bigint, email_unverified bigint,
               email_missing bigint, blood_confirmed bigint, blood_missing bigint, blood_unconfirmed bigint, complete bigint, no_sign_in bigint)
LANGUAGE sql STABLE AS $$
    SELECT count(*), count(*) FILTER (WHERE r.has_photo), count(*) FILTER (WHERE NOT r.has_photo), count(*) FILTER (WHERE r.photo_enhanced),
           count(*) FILTER (WHERE r.email_verified), count(*) FILTER (WHERE r.email IS NOT NULL AND NOT r.email_verified),
           count(*) FILTER (WHERE r.email IS NULL),
           count(*) FILTER (WHERE r.blood_confirmed), count(*) FILTER (WHERE r.blood_group IS NULL),
           count(*) FILTER (WHERE r.blood_group IS NOT NULL AND NOT r.blood_confirmed),
           count(*) FILTER (WHERE r.photo_enhanced AND r.email_verified AND r.blood_confirmed),
           count(*) FILTER (WHERE NOT r.can_sign_in)
      FROM credentials.identity_staff_rows(p_faculty, p_unit, p_category) r
$$;
COMMENT ON FUNCTION credentials.identity_completion_staff(text, text, text) IS
  'V749: the staff in service, by faculty, unit and category: the photograph (on file, not, enhanced and accepted), the e-mail (verified, given but not verified, none), the blood group (confirmed, none, not confirmed), complete (all three done), and how many cannot sign in to be asked';

CREATE FUNCTION credentials.identity_completion_staff_list(p_faculty text, p_unit text, p_category text, p_missing text, p_q text,
                                                           p_limit int, p_offset int)
RETURNS TABLE (person_id uuid, staff_number text, name text, category text, unit text, faculty text, in_office boolean, can_sign_in boolean,
               has_photo boolean, photo_enhanced boolean, email text, email_verified boolean, email_pending text, blood_group text,
               blood_confirmed boolean, complete boolean, total bigint)
LANGUAGE sql STABLE AS $$
    SELECT r.person_id, r.staff_number, btrim(coalesce(r.surname, '') || ' ' || coalesce(r.given_names, '')), r.category, r.unit, r.faculty,
           r.in_office, r.can_sign_in, r.has_photo, r.photo_enhanced, r.email, r.email_verified,
           (SELECT x.email FROM iam.email_verification x WHERE x.person_id = r.person_id AND x.outcome IS NULL AND x.expires_at > now()
             ORDER BY x.created_at DESC LIMIT 1),
           r.blood_group, r.blood_confirmed, r.photo_enhanced AND r.email_verified AND r.blood_confirmed, count(*) OVER ()
      FROM credentials.identity_staff_rows(p_faculty, p_unit, p_category) r
     WHERE (p_missing IS NULL OR btrim(p_missing) = ''
            OR (upper(btrim(p_missing)) = 'PHOTO' AND NOT r.photo_enhanced)
            OR (upper(btrim(p_missing)) = 'EMAIL' AND NOT r.email_verified)
            OR (upper(btrim(p_missing)) = 'BLOOD' AND NOT r.blood_confirmed)
            OR (upper(btrim(p_missing)) = 'ANY' AND NOT (r.photo_enhanced AND r.email_verified AND r.blood_confirmed)))
       AND (p_q IS NULL OR btrim(p_q) = '' OR r.staff_number ILIKE '%' || btrim(p_q) || '%' OR coalesce(r.surname, '') ILIKE '%' || btrim(p_q) || '%'
            OR coalesce(r.given_names, '') ILIKE '%' || btrim(p_q) || '%' OR coalesce(r.email, '') ILIKE '%' || btrim(p_q) || '%')
     ORDER BY r.surname, r.given_names, r.staff_number
     LIMIT greatest(1, coalesce(p_limit, 50)) OFFSET greatest(0, coalesce(p_offset, 0))
$$;
COMMENT ON FUNCTION credentials.identity_completion_staff_list(text, text, text, text, text, int, int) IS
  'V749: the staff behind the counts — filtered as the counts are, by what is missing (PHOTO: not enhanced and accepted; EMAIL: not verified; BLOOD: not confirmed; ANY: not complete; NULL: all) and searched by staff number, name or e-mail; paged, with the total';

DO $$
DECLARE n_students int; n_staff int; n_desk int;
BEGIN
    SELECT count(*) FILTER (WHERE kind = 'STUDENT'), count(*) FILTER (WHERE kind = 'STAFF'), count(*) FILTER (WHERE source = 'DESK')
      INTO n_students, n_staff, n_desk FROM credentials.blood_group_confirmation;
    RAISE NOTICE 'V749: % student(s) and % member(s) of staff hold a confirmed blood group (% recorded at the card desk before today); every other student in study is asked on the dashboard, and the card waits on it',
        n_students, n_staff, n_desk;
END $$;

COMMIT;
