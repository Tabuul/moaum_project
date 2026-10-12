-- V403 — The Board's result sheet, uploaded once: each candidate's JUPEB number, subject combination, subjects and grades.
--
--   The JUPEB Office receives the Board's sheet as the Board prints it: S/N, JUPEB NUMBER, SURNAME, OTHER Names, then one
--   column per subject in the Board's own codes (ACC AGR BIO BUS CHM CRS ECN FRE GRY GOV HST IGB ISS LIT MAT MUS PHY VSA
--   YOR) with the grade in the subjects the candidate sat and the rest blank. Those codes are already on record as the
--   prefix of each of the Board's subjects (jupeb.board_subject, V353), so a column names the Board's subject exactly —
--   the either/or ones included: CRS or ISS for Christian / Islamic Religious Studies, IGB or YOR for Igbo / Yoruba.
--
--   jupeb.import_board_results(rows, commit, file, actor), previewed and then committed like the other JUPEB imports:
--     · the candidate is found by the application number when the office adds one to the row, else by the JUPEB number
--       already on record, else by name — the surname and the other names, as words in any order, against the active and
--       completed students; a name that matches no one, or more than one, is held for review with the candidates it might
--       be, and the office adds the application number to the row and uploads again;
--     · the subjects the sheet grades make the candidate's combination (one of the Board's combinations, or the row is
--       invalid); the Board's word stands: a registered subject the Board did not examine is turned into the one it did
--       (the registration row re-pointed, never deleted; continuous assessment and attendance stay as history) and the
--       option taken — CRS or ISS, IGB or YOR — is the column graded. A subject that already carries a recorded result is
--       not turned into another: the row is held for review;
--     · the JUPEB number is assigned (jupeb.set_exam_no); a candidate who holds a different one is held for review, or
--       corrected when the row gives the reason;
--     · the grades are recorded as the candidate's results (jupeb.result), unpublished until the office publishes them; a
--       grade already recorded and different changes only with the row's reason (jupeb.result_change).
--   Nothing is written while any row is invalid; rows held for review are left as they are and listed on the batch.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'jupeb', true),
       set_config('moaum.reason', 'V403: the Board''s result sheet uploaded — numbers, combination, subjects and grades', true);

ALTER TABLE jupeb.import_batch DROP CONSTRAINT IF EXISTS import_batch_kind_check;
ALTER TABLE jupeb.import_batch ADD CONSTRAINT import_batch_kind_check
  CHECK (kind = ANY (ARRAY['EXAM_NUMBERS', 'RESULTS', 'COMBINATIONS', 'OLD_PORTAL_STUDENTS', 'OLD_PORTAL_PAYMENTS', 'BOARD_RESULTS']));

/* the reference of an import batch: the Board's result sheet gets its own word, not the combinations' */
CREATE OR REPLACE FUNCTION jupeb.batch_ref(p_kind text)
 RETURNS text
 LANGUAGE sql
AS $function$
    SELECT 'JUPEB-' || CASE p_kind WHEN 'EXAM_NUMBERS' THEN 'EXAMNO' WHEN 'RESULTS' THEN 'RESULT' WHEN 'OLD_PORTAL_STUDENTS' THEN 'OLDPORTAL'
                                   WHEN 'OLD_PORTAL_PAYMENTS' THEN 'OLDPAY' WHEN 'BOARD_RESULTS' THEN 'BOARD' ELSE 'COMB' END || '-'
           || to_char(now(), 'YYYY') || '-' || lpad(platform.next_number('JUPEB_' || p_kind, 'UNIVERSITY', to_char(now(), 'YYYY'))::text, 5, '0')
$function$;

/* a name as words: upper case, letters and digits only, each word once, in order — so "St. Mark  Achia" and "ST MARK ACHIA"
   are the same words, whatever the order the sheet writes them in */
CREATE FUNCTION jupeb.name_words(p text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $fn$
    SELECT coalesce(array_agg(DISTINCT w ORDER BY w), '{}')
      FROM regexp_split_to_table(upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]+', ' ', 'g')), ' ') w
     WHERE w <> ''
$fn$;

CREATE FUNCTION jupeb.import_board_results(p_rows jsonb, p_commit boolean, p_file text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE r jsonb; v_out jsonb := '[]'::jsonb; a jupeb.application; c jupeb.combination; g record; bs jupeb.board_subject;
        v_no text; v_appno text; v_reason text; v_how text; v_status text; v_msg text; v_ids uuid[]; v_maybe text;
        v_subjects uuid[]; v_boards uuid[]; v_grades text[]; v_codes text[]; v_bad text; v_held_by text; v_old_comb text;
        v_reg uuid[]; v_drop uuid[]; v_add uuid[]; v_num text; v_comb_change boolean; v_opt_change boolean; v_new_g int; v_fix_g int;
        v_review text[]; v_old text; i int; k int;
        n_invalid int := 0; n_review int := 0; n_new int := 0; n_fix int := 0; n_upd int := 0; n_same int := 0;
        seen_no text[] := '{}'; seen_app uuid[] := '{}'; v_ref text; applied int := 0; x jsonb; v_sid uuid; v_bid uuid; v_grade text;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('jupeb.board_results'));
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) LOOP
        v_no := upper(regexp_replace(btrim(coalesce(r->>'examNo', '')), '\s+', '', 'g'));
        v_appno := upper(btrim(coalesce(r->>'applicationNo', '')));
        v_reason := nullif(btrim(coalesce(r->>'reason', '')), '');
        v_status := NULL; v_msg := NULL; v_how := NULL; a := NULL; c := NULL; v_maybe := NULL; v_review := '{}';
        v_subjects := '{}'; v_boards := '{}'; v_grades := '{}'; v_codes := '{}'; v_bad := NULL; v_old_comb := NULL;
        v_num := NULL; v_comb_change := false; v_opt_change := false; v_new_g := 0; v_fix_g := 0;

        -- the grades the sheet gives, column by column (g_<Board code>), each a subject of the Board
        FOR g IN SELECT upper(substr(e.key, 3)) AS code, upper(btrim(e.value)) AS grade
                   FROM jsonb_each_text(r) e WHERE e.key LIKE 'g\_%' AND btrim(coalesce(e.value, '')) <> '' ORDER BY 1 LOOP
            SELECT b.* INTO bs FROM jupeb.board_subject b JOIN jupeb.syllabus y ON y.id = b.syllabus_id
             WHERE upper(b.prefix) = g.code ORDER BY y.loaded_at DESC LIMIT 1;
            IF bs.id IS NULL THEN v_bad := coalesce(v_bad || '; ', '') || g.code || ' is not one of the Board''s subjects';
            ELSIF g.grade NOT IN ('A', 'B', 'C', 'D', 'E', 'F', 'X', 'Q', 'W') THEN
                v_bad := coalesce(v_bad || '; ', '') || g.code || ' grade ' || g.grade || ' is not A to F, X, Q or W';
            ELSIF bs.subject_id = ANY(v_subjects) THEN v_bad := coalesce(v_bad || '; ', '') || g.code || ' is the same subject as another graded in the row';
            ELSE v_subjects := v_subjects || bs.subject_id; v_boards := v_boards || bs.id; v_grades := v_grades || g.grade; v_codes := v_codes || g.code;
            END IF;
        END LOOP;
        IF v_bad IS NULL AND cardinality(v_subjects) = 3 THEN
            SELECT * INTO c FROM jupeb.combination x
             WHERE ARRAY[x.subject1, x.subject2, x.subject3] @> v_subjects AND ARRAY[x.subject1, x.subject2, x.subject3] <@ v_subjects
             ORDER BY x.active DESC, x.code LIMIT 1;
        END IF;

        -- the candidate: by the application number the office adds, else the JUPEB number on record, else the name
        IF v_appno <> '' THEN
            SELECT * INTO a FROM jupeb.application x WHERE upper(x.application_no) = v_appno; v_how := 'APPLICATION';
        ELSIF v_no <> '' AND EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.exam_no) = v_no) THEN
            SELECT * INTO a FROM jupeb.application x WHERE upper(x.exam_no) = v_no; v_how := 'JUPEB_NUMBER';
        ELSE
            v_ids := ARRAY(SELECT x.id FROM jupeb.application x
                            WHERE x.state IN ('STUDENT', 'COMPLETED') AND (x.exam_no IS NULL OR upper(x.exam_no) = v_no)
                              AND jupeb.name_words(x.surname) = jupeb.name_words(r->>'surname')
                              AND jupeb.name_words(coalesce(x.first_name, '') || ' ' || coalesce(x.middle_name, '')) = jupeb.name_words(r->>'otherNames'));
            IF cardinality(v_ids) = 1 THEN SELECT * INTO a FROM jupeb.application WHERE id = v_ids[1]; v_how := 'NAME';
            ELSE
                SELECT string_agg(x.application_no || ' ' || x.surname || ', ' || x.first_name || coalesce(' ' || x.middle_name, '') || ' (' || x.session || ')', '; ' ORDER BY x.session DESC, x.application_no)
                  INTO v_maybe
                  FROM (SELECT * FROM jupeb.application y
                         WHERE y.state IN ('STUDENT', 'COMPLETED') AND (y.exam_no IS NULL OR upper(y.exam_no) = v_no)
                           AND (y.id = ANY(v_ids) OR jupeb.name_words(y.surname) = jupeb.name_words(r->>'surname'))
                         LIMIT 4) x;
            END IF;
        END IF;

        IF v_no = '' THEN v_status := 'INVALID'; v_msg := 'No JUPEB number';
        ELSIF v_no !~ '^[A-Z0-9][A-Z0-9/-]{3,29}$' THEN v_status := 'INVALID'; v_msg := v_no || ' is not a JUPEB number';
        ELSIF v_no = ANY(seen_no) THEN v_status := 'INVALID'; v_msg := v_no || ' appears twice in the file';
        ELSIF v_bad IS NOT NULL THEN v_status := 'INVALID'; v_msg := v_bad;
        ELSIF cardinality(v_subjects) = 0 THEN v_status := 'INVALID'; v_msg := 'No subject is graded';
        ELSIF cardinality(v_subjects) <> 3 THEN v_status := 'INVALID'; v_msg := cardinality(v_subjects) || ' subjects are graded (' || array_to_string(v_codes, ', ') || '); a combination is three';
        ELSIF c.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No combination of the Board is ' || array_to_string(v_codes, ', ');
        ELSIF v_appno <> '' AND a.id IS NULL THEN v_status := 'INVALID'; v_msg := 'No JUPEB application ' || v_appno;
        ELSIF a.id IS NULL THEN
            v_status := 'REQUIRES_REVIEW';
            v_msg := CASE WHEN v_maybe IS NULL THEN 'No active or completed JUPEB student is named ' || btrim(coalesce(r->>'surname', '')) || ' ' || btrim(coalesce(r->>'otherNames', ''))
                          ELSE 'Not one name match; it may be: ' || v_maybe END || '. Add the application number to the row and upload again.';
        ELSIF a.id = ANY(seen_app) THEN v_status := 'INVALID'; v_msg := a.application_no || ' is matched by two rows of the file';
        ELSIF EXISTS (SELECT 1 FROM jupeb.application x WHERE upper(x.exam_no) = v_no AND x.id <> a.id) THEN
            SELECT application_no INTO v_held_by FROM jupeb.application x WHERE upper(x.exam_no) = v_no AND x.id <> a.id;
            v_status := 'INVALID'; v_msg := v_no || ' is already ' || v_held_by || '''s JUPEB number';
        ELSIF a.state NOT IN ('STUDENT', 'COMPLETED') THEN
            v_status := 'REQUIRES_REVIEW'; v_msg := a.application_no || ' is ' || lower(a.state) || ', not an active or completed JUPEB student';
        ELSE
            -- the JUPEB number
            IF a.exam_no IS NULL THEN v_num := 'NEW';
            ELSIF upper(a.exam_no) = v_no THEN v_num := 'SAME';
            ELSIF v_how = 'NAME' THEN v_review := v_review || ('matched by name but holds ' || a.exam_no || '; add the application number and a reason to correct it');
            ELSIF v_reason IS NULL THEN v_review := v_review || ('holds ' || a.exam_no || '; a correction states its reason');
            ELSE v_num := 'CORRECTION';
            END IF;
            -- the combination and subjects the Board examined
            v_old_comb := (SELECT code FROM jupeb.combination WHERE id = a.combination_id);
            v_reg := ARRAY(SELECT subject_id FROM jupeb.subject_registration WHERE application_id = a.id);
            v_drop := ARRAY(SELECT s FROM unnest(v_reg) s WHERE s <> ALL(v_subjects));
            v_add := ARRAY(SELECT s FROM unnest(v_subjects) s WHERE s <> ALL(v_reg));
            v_comb_change := a.combination_id IS DISTINCT FROM c.id OR cardinality(v_drop) > 0 OR cardinality(v_add) > 0 OR a.subjects_registered_at IS NULL;
            IF cardinality(v_drop) > cardinality(v_add) THEN
                v_review := v_review || ('registered on ' || cardinality(v_reg) || ' subjects; the Board examined three');
            END IF;
            IF EXISTS (SELECT 1 FROM jupeb.result x WHERE x.application_id = a.id AND x.subject_id = ANY(v_drop)) THEN
                v_review := v_review || ('a result is recorded in ' || (SELECT string_agg(s.title, ', ') FROM jupeb.subject s WHERE s.id = ANY(v_drop)) || ', which the Board did not examine');
            END IF;
            FOR i IN 1 .. 3 LOOP
                IF EXISTS (SELECT 1 FROM jupeb.subject_registration x WHERE x.application_id = a.id AND x.subject_id = v_subjects[i] AND x.board_subject_id IS DISTINCT FROM v_boards[i])
                   AND EXISTS (SELECT 1 FROM jupeb.board_subject b2 WHERE b2.subject_id = v_subjects[i] AND b2.id <> v_boards[i]) THEN
                    v_opt_change := true;
                END IF;
                SELECT grade INTO v_old FROM jupeb.result WHERE application_id = a.id AND subject_id = v_subjects[i];
                IF v_old IS NULL THEN v_new_g := v_new_g + 1;
                ELSIF v_old <> v_grades[i] THEN
                    IF v_reason IS NULL THEN v_review := v_review || (v_codes[i] || ' is already ' || v_old || '; a changed grade states its reason');
                    ELSE v_fix_g := v_fix_g + 1; END IF;
                END IF;
            END LOOP;
            IF cardinality(v_review) > 0 THEN v_status := 'REQUIRES_REVIEW'; v_msg := array_to_string(v_review, '; ');
            ELSIF v_num = 'SAME' AND NOT v_comb_change AND NOT v_opt_change AND v_new_g = 0 AND v_fix_g = 0 THEN
                v_status := 'UNCHANGED'; v_msg := 'Already as the Board''s sheet has it';
            ELSE
                v_status := CASE v_num WHEN 'NEW' THEN 'NEW' WHEN 'CORRECTION' THEN 'CORRECTION' ELSE 'UPDATED' END;
                v_msg := concat_ws('; ',
                    CASE v_num WHEN 'NEW' THEN 'JUPEB number ' || v_no WHEN 'CORRECTION' THEN 'JUPEB number ' || a.exam_no || ' → ' || v_no END,
                    CASE WHEN v_comb_change THEN c.code || coalesce(' (was ' || nullif(v_old_comb, c.code) || ')', '') END,
                    CASE WHEN v_opt_change AND NOT v_comb_change THEN 'the option the Board examined' END,
                    CASE WHEN v_new_g > 0 THEN v_new_g || ' grade(s)' END,
                    CASE WHEN v_fix_g > 0 THEN v_fix_g || ' grade(s) corrected' END);
            END IF;
        END IF;
        IF v_no <> '' THEN seen_no := seen_no || v_no; END IF;
        IF a.id IS NOT NULL THEN seen_app := seen_app || a.id; END IF;
        CASE v_status WHEN 'INVALID' THEN n_invalid := n_invalid + 1; WHEN 'REQUIRES_REVIEW' THEN n_review := n_review + 1;
                      WHEN 'NEW' THEN n_new := n_new + 1; WHEN 'CORRECTION' THEN n_fix := n_fix + 1; WHEN 'UPDATED' THEN n_upd := n_upd + 1;
                      ELSE n_same := n_same + 1; END CASE;
        v_out := v_out || jsonb_build_object('row', r->'row', 'examNo', v_no, 'status', v_status, 'message', v_msg, 'how', v_how,
                     'applicationId', a.id, 'applicationNo', a.application_no, 'name', CASE WHEN a.id IS NOT NULL THEN a.surname || ', ' || a.first_name || coalesce(' ' || a.middle_name, '') END,
                     'sheetName', btrim(coalesce(r->>'surname', '') || ' ' || coalesce(r->>'otherNames', '')),
                     'combination', c.code, 'combinationId', c.id, 'was', v_old_comb, 'subjects', to_jsonb(v_subjects), 'boards', to_jsonb(v_boards),
                     'grades', to_jsonb(v_grades), 'codes', to_jsonb(v_codes),
                     'gradesText', (SELECT string_agg(v_codes[j] || ' ' || v_grades[j], ' · ' ORDER BY j) FROM generate_subscripts(v_codes, 1) j),
                     'reason', v_reason);
    END LOOP;

    IF p_commit THEN
        IF jsonb_array_length(v_out) = 0 THEN RAISE EXCEPTION 'JUPEB_IMPORT_EMPTY: the file has no rows' USING ERRCODE = '23514'; END IF;
        IF n_invalid > 0 THEN
            RAISE EXCEPTION 'JUPEB_IMPORT_INVALID: % row(s) are invalid; nothing was written', n_invalid USING ERRCODE = '23514',
                  HINT = 'Correct the rows the preview lists and upload again.';
        END IF;
        v_ref := jupeb.batch_ref('BOARD_RESULTS');
        FOR x IN SELECT * FROM jsonb_array_elements(v_out) LOOP
            CONTINUE WHEN x->>'status' NOT IN ('NEW', 'CORRECTION', 'UPDATED');
            SELECT * INTO a FROM jupeb.application WHERE id = (x->>'applicationId')::uuid FOR UPDATE;
            SELECT * INTO c FROM jupeb.combination WHERE id = (x->>'combinationId')::uuid;
            v_subjects := ARRAY(SELECT (e)::uuid FROM jsonb_array_elements_text(x->'subjects') e);
            v_boards := ARRAY(SELECT (e)::uuid FROM jsonb_array_elements_text(x->'boards') e);
            v_grades := ARRAY(SELECT e FROM jsonb_array_elements_text(x->'grades') e);
            v_codes := ARRAY(SELECT e FROM jsonb_array_elements_text(x->'codes') e);
            -- 1 · the combination and the subjects: a registered subject the Board did not examine becomes the one it did
            v_reg := ARRAY(SELECT subject_id FROM jupeb.subject_registration WHERE application_id = a.id ORDER BY registered_at, id);
            v_drop := ARRAY(SELECT s FROM unnest(v_reg) s WHERE s <> ALL(v_subjects));
            v_add := ARRAY(SELECT s FROM unnest(v_subjects) s WHERE s <> ALL(v_reg));
            k := 0;
            FOREACH v_sid IN ARRAY v_add LOOP
                k := k + 1;
                v_bid := v_boards[array_position(v_subjects, v_sid)];
                IF k <= cardinality(v_drop) THEN
                    UPDATE jupeb.subject_registration SET subject_id = v_sid, board_subject_id = v_bid, registered_by = p_actor
                     WHERE application_id = a.id AND subject_id = v_drop[k];
                ELSE
                    INSERT INTO jupeb.subject_registration (application_id, subject_id, session, registered_by, board_subject_id)
                    VALUES (a.id, v_sid, a.session, p_actor, v_bid);
                END IF;
            END LOOP;
            FOR i IN 1 .. 3 LOOP   -- the option the Board examined: CRS or ISS, IGB or YOR
                UPDATE jupeb.subject_registration SET board_subject_id = v_boards[i]
                 WHERE application_id = a.id AND subject_id = v_subjects[i] AND board_subject_id IS DISTINCT FROM v_boards[i];
            END LOOP;
            IF a.combination_id IS DISTINCT FROM c.id OR a.subjects_registered_at IS NULL OR cardinality(v_add) > 0 THEN
                UPDATE jupeb.application
                   SET combination_id = c.id, subjects_registered_at = coalesce(subjects_registered_at, now()),
                       stream = CASE WHEN c.area IN ('Science', 'Engineering') THEN 'SCIENCE' WHEN c.area IS NOT NULL THEN 'NON_SCIENCE' ELSE stream END
                 WHERE id = a.id;
                PERFORM jupeb.app_event(a.id, 'BOARD_COMBINATION', 'The Board''s result: ' || c.code || ' (' || array_to_string(v_codes, ', ') || ')'
                                                                 || coalesce(' — was ' || nullif(x->>'was', c.code), '') || ' [' || v_ref || ']');
            END IF;
            -- 2 · the JUPEB number
            PERFORM jupeb.set_exam_no(a.id, x->>'examNo', coalesce(x->>'reason', 'The Board''s result sheet'), 'IMPORT', v_ref);
            -- 3 · the grades, unpublished until the office publishes them
            FOR i IN 1 .. 3 LOOP
                v_grade := v_grades[i];
                SELECT grade INTO v_old FROM jupeb.result WHERE application_id = a.id AND subject_id = v_subjects[i];
                IF v_old IS NULL THEN
                    INSERT INTO jupeb.result (application_id, subject_id, grade, points, batch_ref, recorded_by)
                    VALUES (a.id, v_subjects[i], v_grade, jupeb.grade_points(v_grade), v_ref, p_actor);
                ELSIF v_old <> v_grade THEN
                    INSERT INTO jupeb.result_change (application_id, subject_id, old_grade, new_grade, reason, batch_ref, changed_by)
                    VALUES (a.id, v_subjects[i], v_old, v_grade, x->>'reason', v_ref, p_actor);
                    UPDATE jupeb.result SET grade = v_grade, points = jupeb.grade_points(v_grade), batch_ref = v_ref, recorded_by = p_actor, recorded_at = now()
                     WHERE application_id = a.id AND subject_id = v_subjects[i];
                    PERFORM jupeb.app_event(a.id, 'RESULT_CORRECTED', v_codes[i] || ': ' || v_old || ' → ' || v_grade || ' — ' || (x->>'reason'));
                END IF;
            END LOOP;
            applied := applied + 1;
        END LOOP;
        INSERT INTO jupeb.import_batch (ref, kind, file_name, rows, applied, result, imported_by, imported_office)
        VALUES (v_ref, 'BOARD_RESULTS', p_file, jsonb_array_length(v_out), applied,
                jsonb_build_object('new', n_new, 'corrections', n_fix, 'updated', n_upd, 'unchanged', n_same, 'review', n_review,
                                   'reviewRows', (SELECT coalesce(jsonb_agg(jsonb_build_object('row', y->'row', 'examNo', y->'examNo', 'sheetName', y->'sheetName', 'message', y->'message')), '[]'::jsonb)
                                                    FROM jsonb_array_elements(v_out) y WHERE y->>'status' = 'REQUIRES_REVIEW')),
                p_actor, nullif(current_setting('moaum.actor_office', true), ''));
    END IF;
    RETURN jsonb_build_object('rows', v_out, 'invalid', n_invalid, 'review', n_review, 'new', n_new, 'corrections', n_fix, 'updated', n_upd,
                              'unchanged', n_same, 'committed', p_commit, 'ref', v_ref, 'applied', applied);
END $fn$;
COMMENT ON FUNCTION jupeb.import_board_results(jsonb, boolean, text, uuid) IS
  'V403: the Board''s result sheet (JUPEB NUMBER, SURNAME, OTHER Names, a grade column per Board subject) — each candidate found by application number, JUPEB number or name; the JUPEB number assigned, the combination and subjects (with the CRS/ISS, IGB/YOR option) set from the subjects the Board graded (registration rows re-pointed, never deleted), and the grades recorded unpublished. Previewed, then committed; nothing is written while a row is invalid; rows held for review are left alone.';

COMMIT;
