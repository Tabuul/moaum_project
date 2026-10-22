-- V636: the JAMB list merge followed through, and awaiting O'Level results replaced — the University's word of 22 October 2026, on
-- the first cumulative list loaded under V629 ("see what am seeing when attempting to commit"; "all AR should update with their
-- new O'Level results").
--   · The merge (V629) updated 6,774 candidates on the live list to JAMB's changed courses, and 741 of them already had a
--     candidate record on the portal carrying the old course, so the list no longer reconciled ("Matched, programme differs from
--     CAPS") and the commit was refused. Now a candidate whose course JAMB changed follows it unless an offer stands
--     (admissions.follow_caps_course): the candidate's programme becomes JAMB's, a programme change is written on the register
--     (reason JAMB_CAPS, approved as made, the applicant told), and the eligibility engine reads the candidate again. The loader
--     runs it after every upload that changed a course, and the screen offers it for the candidates already changed. A candidate
--     with a released offer is left as offered and counted apart: the admission is corrected on Programme Changes, or the row
--     withdrawn. admissions.reconcile tells the two apart.
--   · An O'Level sitting on record as awaiting result (every grade A/R) is replaced outright by the grades a later upload carries
--     under the same exam number — the finding is kept as REPLACED, never held; an upload that says A/R where the record holds
--     grades changes nothing (AWAITING, skipped). Two sets of real grades under one exam number are still held for the Office (V298).
-- The three functions are restated exactly as they stand, with those additions.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V636: the JAMB list merge followed through, awaiting O''Level results replaced (the University, 22 October 2026)', true);

-- ── an offer that stands: the Board's decision released as OFFERED and not declined ──
CREATE OR REPLACE FUNCTION admissions.offer_stands(p_app uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce((SELECT a.decision_released_at IS NOT NULL AND coalesce(a.decision, '') = 'OFFERED' AND a.declined_at IS NULL
                       FROM admissions.application a WHERE a.id = p_app), false)
$$;
COMMENT ON FUNCTION admissions.offer_stands(uuid) IS 'V636: true when the application''s released decision is OFFERED and the offer was not declined; false for no application.';

INSERT INTO admissions.programme_change_reason (code, label, ord, requires_note)
VALUES ('JAMB_CAPS', 'Course changed by JAMB on the CAPS list', 9, false)
ON CONFLICT (code) DO NOTHING;

-- ── the candidates JAMB moved: followed where no offer stands ──
CREATE OR REPLACE FUNCTION admissions.follow_caps_course(p_session text, p_dry_run boolean DEFAULT false)
RETURNS TABLE (followed integer, admitted_left integer, named jsonb)
LANGUAGE plpgsql
AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
        r record; n_follow int := 0; n_left int := 0; v_named jsonb := '[]'::jsonb;
BEGIN
    FOR r IN
        SELECT c.id AS candidate_id, c.programme AS from_programme, admissions.programme_code_of(c.programme) AS from_code,
               j.code AS to_code, j.name AS to_programme, c.jamb_reg_no, c.surname, c.other_names, a.id AS application_id,
               admissions.offer_stands(a.id) AS admitted, b.filename AS list_file
          FROM admissions.candidate c
          JOIN admissions.caps_row_live rr ON rr.session = c.session AND rr.jamb_reg_no = c.jamb_reg_no
          JOIN ref.programme j ON j.code = rr.jamb_code
          LEFT JOIN admissions.application a ON a.candidate_id = c.id
          LEFT JOIN admissions.caps_batch b ON b.id = rr.batch_id
         WHERE c.session = p_session AND c.programme <> j.name
         ORDER BY c.surname, c.other_names, c.jamb_reg_no
    LOOP
        IF r.admitted THEN
            n_left := n_left + 1;
            IF jsonb_array_length(v_named) < 300 THEN
                v_named := v_named || jsonb_build_object('jambRegNo', r.jamb_reg_no, 'name', r.surname || ', ' || r.other_names,
                                                         'from', r.from_programme, 'to', r.to_programme, 'admitted', true);
            END IF;
            CONTINUE;
        END IF;
        n_follow := n_follow + 1;
        IF jsonb_array_length(v_named) < 300 THEN
            v_named := v_named || jsonb_build_object('jambRegNo', r.jamb_reg_no, 'name', r.surname || ', ' || r.other_names,
                                                     'from', r.from_programme, 'to', r.to_programme, 'admitted', false);
        END IF;
        IF p_dry_run THEN CONTINUE; END IF;
        UPDATE admissions.candidate SET programme = r.to_programme WHERE id = r.candidate_id;
        IF r.application_id IS NOT NULL THEN
            INSERT INTO admissions.programme_change_request
                   (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme,
                    eligibility_at_request, requested_by_kind, requested_by, note, state, decided_at, decided_by, decision_note,
                    reason_code, recommended_office, kind, decided_office)
            VALUES (r.application_id, r.candidate_id, p_session, r.from_code, r.from_programme, r.to_code, r.to_programme,
                    'NOT_READ', 'OFFICE', v_actor, 'JAMB changed the course on the CAPS list' || coalesce(' (' || r.list_file || ')', ''),
                    'APPROVED', now(), v_actor, 'Followed JAMB''s course: no offer stood for the candidate (V636)',
                    'JAMB_CAPS', v_office, 'CHANGE', v_office);
            PERFORM admissions.notify_applicant(r.application_id, 'Your course on the JAMB list has changed',
                'JAMB''s admission list now gives your course as ' || r.to_programme || ' (it was ' || r.from_programme
                || '). Your application here follows it; your eligibility is read again on the new course.',
                'MOAUM: JAMB now lists your course as ' || r.to_programme || '; your application follows it.');
        END IF;
    END LOOP;
    RETURN QUERY SELECT n_follow, n_left, v_named;
END $$;
COMMENT ON FUNCTION admissions.follow_caps_course(text, boolean) IS
  'V636: every candidate of the session whose programme differs from the JAMB course on the live CAPS list — followed (the programme set to JAMB''s, a JAMB_CAPS programme change approved as made, the applicant told) where no released offer stands; counted apart, untouched, where one does. Dry run names them without writing. At most 300 are named.';

CREATE OR REPLACE FUNCTION admissions.reconcile(p_session text)
 RETURNS TABLE(finding text, n bigint, owner text, what_it_means text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT 'On the CAPS list, no candidate record'::text, count(*)::bigint,
           'Academic Office'::text,
           'JAMB admitted them and the University has no record. They arrive '
           'at registration with a CAPS printout and nobody can find them.'::text
      FROM admissions.caps_row_live r
     WHERE r.session = p_session
       AND NOT EXISTS (SELECT 1 FROM admissions.candidate c
                        WHERE c.session = r.session AND c.jamb_reg_no = r.jamb_reg_no)
    UNION ALL
    SELECT 'Admitted here, not on the CAPS list', count(*)::bigint,
           'Registrar',
           'An admission JAMB did not approve. Left alone it becomes a '
           'matriculation number issued to somebody who was never admitted, '
           'and that number is permanent.'
      FROM admissions.candidate c
     WHERE c.session = p_session
       AND c.offer_state IN ('ADMITTED','ACCEPTED')
       AND NOT EXISTS (SELECT 1 FROM admissions.caps_row_live r
                        WHERE r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no)
    UNION ALL
    SELECT 'Matched, programme differs from CAPS — not yet decided', count(*)::bigint,
           'Academic Office',
           'JAMB changed the course after the candidate registered here, and no offer '
           'stands. The candidate follows JAMB''s course on the next list upload, or now '
           'with Apply JAMB''s course changes (V636).'
      FROM admissions.candidate c
      JOIN admissions.caps_row_live r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
      JOIN ref.programme j ON j.code = r.jamb_code
      LEFT JOIN admissions.application a ON a.candidate_id = c.id
     WHERE c.session = p_session AND c.programme <> j.name
       AND NOT admissions.offer_stands(a.id)
    UNION ALL
    SELECT 'Matched, programme differs from CAPS — admitted', count(*)::bigint,
           'Academic Office',
           'The Board offered a programme JAMB no longer says. A student taught for a '
           'year under the wrong programme graduates under a degree JAMB has no record '
           'of: correct the admission on Programme Changes, or withdraw the row.'
      FROM admissions.candidate c
      JOIN admissions.caps_row_live r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
      JOIN ref.programme j ON j.code = r.jamb_code
      LEFT JOIN admissions.application a ON a.candidate_id = c.id
     WHERE c.session = p_session AND c.programme <> j.name
       AND admissions.offer_stands(a.id)
    UNION ALL
    SELECT 'JAMB course code the University does not run', count(DISTINCT r.jamb_code)::bigint,
           'Academic Office',
           'The code is on the CAPS list and not in the University programme '
           'table, or is archived, or is not an undergraduate programme. '
           'It is refused rather than guessed: the candidate would otherwise '
           'be taught for a year under a programme nobody chose for them.'
      FROM admissions.caps_row_live r
     WHERE r.session = p_session
       AND NOT EXISTS (SELECT 1 FROM ref.programme p
                        WHERE p.code = r.jamb_code
                          AND NOT p.archived
                          AND p.category = 'UNDER GRADUATE')
    UNION ALL
    SELECT 'Direct Entry candidate entered at the wrong level', count(*)::bigint,
           'Academic Office',
           'A Direct Entry candidate at 100 Level repeats a year the University '
           'admitted them past, and it surfaces at the end of the session.'
      FROM admissions.candidate c
      JOIN admissions.caps_row_live r
        ON r.session = c.session AND r.jamb_reg_no = c.jamb_reg_no
     WHERE c.session = p_session
       AND r.entry_mode <> 'UTME' AND c.entry_level = 100;
$function$;
COMMENT ON FUNCTION admissions.reconcile(text) IS
  'V006, V019, V636: what the database finds both ways between the live CAPS list and the candidate records; a programme that differs from CAPS is told apart by whether a released offer stands (not yet decided: follows JAMB; admitted: corrected on Programme Changes).';

-- ── the O'Level duplicate findings: a new kind and a new state ──
ALTER TABLE admissions.olevel_duplicate DROP CONSTRAINT IF EXISTS ck_old_kind;
ALTER TABLE admissions.olevel_duplicate DROP CONSTRAINT IF EXISTS ck_old_state;
ALTER TABLE admissions.olevel_duplicate DROP CONSTRAINT IF EXISTS ck_old_state_kind;
ALTER TABLE admissions.olevel_duplicate
    ADD CONSTRAINT ck_old_kind CHECK (kind IN ('SAME_RESULT', 'SAME_SITTING', 'NUMBER_ELSEWHERE', 'AWAITING')),
    ADD CONSTRAINT ck_old_state CHECK (state IN ('SKIPPED', 'HELD', 'KEPT', 'USED', 'OPEN', 'VERIFIED', 'REPLACED')),
    ADD CONSTRAINT ck_old_state_kind CHECK ((kind = 'SAME_RESULT' AND state = 'SKIPPED')
                                         OR (kind = 'AWAITING' AND state = 'SKIPPED')
                                         OR (kind = 'SAME_SITTING' AND state IN ('HELD', 'KEPT', 'USED', 'REPLACED'))
                                         OR (kind = 'NUMBER_ELSEWHERE' AND state IN ('OPEN', 'VERIFIED')));
COMMENT ON TABLE admissions.olevel_duplicate IS
  'V298/V315/V636: what an O''Level upload carried that was already on record (SAME_RESULT, not recorded again), the same exam number with other grades (SAME_SITTING: held for the Office, or REPLACED when the record held an awaiting result), an awaiting result where the record holds the grades (AWAITING, skipped), or an exam number on another applicant''s record (NUMBER_ELSEWHERE, open until verified).';

-- ── awaiting result: A/R and its spellings, a sitting of nothing else, an uploaded sitting of nothing else ──
CREATE OR REPLACE FUNCTION admissions.olevel_awaiting_grade(p text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT upper(regexp_replace(coalesce(p, ''), '[^A-Za-z]', '', 'g')) IN ('', 'AR', 'AWR', 'AWAITING', 'AWAITINGRESULT', 'AWAITINGRESULTS')
$$;
COMMENT ON FUNCTION admissions.olevel_awaiting_grade(text) IS 'V636: a grade that is no grade — A/R, AR, awaiting result, or blank.';

CREATE OR REPLACE FUNCTION admissions.olevel_awaiting(p_sitting uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(bool_and(admissions.olevel_awaiting_grade(g.grade)), false) FROM admissions.olevel_grade g WHERE g.sitting_id = p_sitting
$$;
COMMENT ON FUNCTION admissions.olevel_awaiting(uuid) IS 'V636: a sitting on record whose every grade is an awaiting result.';

CREATE OR REPLACE FUNCTION admissions.olevel_payload_awaiting(s jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT coalesce(bool_and(admissions.olevel_awaiting_grade(x ->> 'grade')), false)
      FROM jsonb_array_elements(coalesce(s -> 'subjects', '[]'::jsonb)) x
     WHERE nullif(btrim(x ->> 'subject'), '') IS NOT NULL
$$;
COMMENT ON FUNCTION admissions.olevel_payload_awaiting(jsonb) IS 'V636: a sitting as an upload carries it whose every grade is an awaiting result.';

CREATE OR REPLACE FUNCTION admissions.olevel_duplicate_note(a admissions.attachment, p_no integer, p_kind text, s jsonb, hit admissions.olevel_sitting)
 RETURNS void
 LANGUAGE sql
AS $function$
    INSERT INTO admissions.olevel_duplicate (session, jamb_key, attachment_id, sitting_no, kind, state, exam_body, exam_type_raw, exam_year, exam_series, exam_number, subjects,
                                             other_sitting_id, other_jamb_key, other_exam_year, other_exam_number, other_subjects)
    VALUES (a.session, a.jamb_key, a.id, p_no, p_kind,
            CASE p_kind WHEN 'SAME_RESULT' THEN 'SKIPPED' WHEN 'AWAITING' THEN 'SKIPPED' WHEN 'SAME_SITTING' THEN 'HELD' ELSE 'OPEN' END,
            admissions.exam_body(s ->> 'type'), nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''), nullif(btrim(s ->> 'series'), ''),
            nullif(btrim(s ->> 'examNumber'), ''), coalesce(s -> 'subjects', '[]'::jsonb),
            hit.id, hit.jamb_key, hit.exam_year, hit.exam_number, CASE WHEN hit.id IS NULL THEN NULL ELSE admissions.olevel_grades_sig(hit.id) END)
    ON CONFLICT (attachment_id, sitting_no, kind) DO UPDATE
        SET detected_at = now(), other_sitting_id = EXCLUDED.other_sitting_id, other_jamb_key = EXCLUDED.other_jamb_key,
            other_exam_year = EXCLUDED.other_exam_year, other_exam_number = EXCLUDED.other_exam_number, other_subjects = EXCLUDED.other_subjects;
$function$;

CREATE OR REPLACE FUNCTION admissions.olevel_from_attachment(p_attachment uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    a admissions.attachment;
    sittings jsonb;
    s jsonb;
    sub jsonb;
    hit admissions.olevel_sitting;
    v_sitting uuid;
    v_ord int := 0;
    v_no int := 0;
    v_body text; v_key text; v_kind text; v_hit uuid;
    v_replaced boolean; v_old_sig text; v_old_key text; v_old_year text; v_old_number text;  -- V636
BEGIN
    SELECT * INTO a FROM admissions.attachment WHERE id = p_attachment;
    IF NOT FOUND OR a.kind <> 'OLEVEL' OR a.jamb_key IS NULL THEN
        RETURN 0;
    END IF;
    -- read again from the file as it arrived: this attachment's own sittings go first
    DELETE FROM admissions.olevel_grade g USING admissions.olevel_sitting st
     WHERE g.sitting_id = st.id AND st.attachment_id = p_attachment;
    DELETE FROM admissions.olevel_sitting WHERE attachment_id = p_attachment;

    IF jsonb_typeof(a.payload -> 'sittings') = 'array' THEN
        sittings := a.payload -> 'sittings';
    ELSE
        sittings := jsonb_build_array(a.payload);
    END IF;

    FOR s IN SELECT * FROM jsonb_array_elements(sittings) LOOP
        v_no := v_no + 1;
        v_body := admissions.exam_body(s ->> 'type');
        v_key := admissions.olevel_exam_key(s ->> 'examNumber');
        -- 1–3 · the same result already on record (not recorded again), or a second result for the same examination (held)
        v_kind := NULL; v_hit := NULL; v_replaced := false;
        SELECT m.kind, m.sitting_id INTO v_kind, v_hit FROM admissions.olevel_match(a.session, a.jamb_key, s) m;
        IF v_kind IS NOT NULL THEN
            SELECT st.* INTO hit FROM admissions.olevel_sitting st WHERE st.id = v_hit;
            IF v_kind = 'SAME_SITTING' AND admissions.olevel_payload_awaiting(s) THEN
                -- V636: the upload says awaiting result where the record holds the grades — the grades stand
                PERFORM admissions.olevel_duplicate_note(a, v_no, 'AWAITING', s, hit);
                CONTINUE;
            ELSIF v_kind = 'SAME_SITTING' AND admissions.olevel_awaiting(v_hit) THEN
                -- V636: the record holds awaiting result (A/R) — the grades the upload carries replace it, and the finding says so
                v_old_sig := admissions.olevel_grades_sig(v_hit); v_old_key := hit.jamb_key; v_old_year := hit.exam_year; v_old_number := hit.exam_number;
                DELETE FROM admissions.olevel_grade WHERE sitting_id = v_hit;
                DELETE FROM admissions.olevel_sitting WHERE id = v_hit;
                v_replaced := true;
            ELSE
                PERFORM admissions.olevel_duplicate_note(a, v_no, v_kind, s, hit);
                CONTINUE;
            END IF;
        END IF;

        v_ord := v_ord + 1;
        v_sitting := gen_random_uuid();
        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_type_raw, exam_year, exam_number, ord, exam_series)
        VALUES (v_sitting, a.id, a.session, a.jamb_key, v_body,
                nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''), nullif(btrim(s ->> 'examNumber'), ''), v_ord, nullif(btrim(s ->> 'series'), ''));
        FOR sub IN SELECT * FROM jsonb_array_elements(coalesce(s -> 'subjects', '[]'::jsonb)) LOOP
            IF nullif(btrim(sub ->> 'subject'), '') IS NOT NULL THEN
                INSERT INTO admissions.olevel_grade AS og (sitting_id, subject, grade, raw_subject)
                VALUES (v_sitting, btrim(sub ->> 'subject'), upper(btrim(coalesce(sub ->> 'grade', ''))), sub ->> 'raw')
                ON CONFLICT (sitting_id, subject) DO UPDATE
                    SET grade = CASE WHEN admissions.olevel_points(a.session, EXCLUDED.grade)
                                          > admissions.olevel_points(a.session, og.grade)
                                     THEN EXCLUDED.grade ELSE og.grade END;
            END IF;
        END LOOP;
        IF v_replaced THEN
            INSERT INTO admissions.olevel_duplicate (session, jamb_key, attachment_id, sitting_no, kind, state, exam_body, exam_type_raw, exam_year, exam_series, exam_number, subjects,
                                                     other_sitting_id, other_jamb_key, other_exam_year, other_exam_number, other_subjects, decided_at, note, used_sitting_id)
            VALUES (a.session, a.jamb_key, a.id, v_no, 'SAME_SITTING', 'REPLACED', v_body, nullif(btrim(s ->> 'type'), ''), nullif(btrim(s ->> 'year'), ''),
                    nullif(btrim(s ->> 'series'), ''), nullif(btrim(s ->> 'examNumber'), ''), coalesce(s -> 'subjects', '[]'::jsonb),
                    NULL, v_old_key, v_old_year, v_old_number, v_old_sig, now(),
                    'Awaiting result (A/R) on record replaced by the grades the upload carried', v_sitting)
            ON CONFLICT (attachment_id, sitting_no, kind) DO UPDATE
                SET state = 'REPLACED', detected_at = now(), decided_at = now(), decided_by = NULL, decided_office = NULL,
                    note = EXCLUDED.note, other_sitting_id = NULL, other_jamb_key = EXCLUDED.other_jamb_key, other_exam_year = EXCLUDED.other_exam_year,
                    other_exam_number = EXCLUDED.other_exam_number, other_subjects = EXCLUDED.other_subjects, used_sitting_id = EXCLUDED.used_sitting_id;
        END IF;
        -- 4 · the same exam number on another applicant's record in the session: recorded, and flagged for verification
        IF v_key IS NOT NULL THEN
            hit := NULL;
            SELECT st.* INTO hit FROM admissions.olevel_sitting st
             WHERE st.session = a.session AND st.exam_body = v_body AND st.exam_key = v_key AND st.jamb_key <> a.jamb_key
             ORDER BY st.jamb_key, st.ord LIMIT 1;
            IF hit.id IS NOT NULL THEN
                PERFORM admissions.olevel_duplicate_note(a, v_no, 'NUMBER_ELSEWHERE', s, hit);
            END IF;
        END IF;
    END LOOP;
    RETURN v_ord;
END $function$;
COMMENT ON FUNCTION admissions.olevel_from_attachment(uuid) IS
  'The sittings an O''Level upload carries (V020), each checked before it is recorded (V298, V315, V636): the same result is not recorded again; an awaiting result (A/R) on record is replaced by the grades the upload carries under the same exam number (REPLACED); an uploaded A/R never replaces grades (AWAITING); the same exam number with other grades is held; another exam number is a sitting of its own; an exam number on another applicant''s record is recorded and flagged.';

COMMIT;
