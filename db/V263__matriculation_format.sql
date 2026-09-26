-- ═══════════════════════════════════════════════════════════════════════════
-- V263 — the matriculation number, by configuration
--
--   V064 issued MOAUM/{DEPT}/{YY}/{NNNN} from a counter per department and
--   session. The Registry's rule (the matriculation schedule of September 2026)
--   differs in three ways, and none of them is a special case in code:
--     · the number reads MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}, and the
--       programme segment is a matter of the programme's own configuration —
--       Medicine and Surgery, Pharmacy and Law carry none, and no code is ever
--       invented to fill the gap (no empty separator either);
--     · the sequence comes from a named SERIES the faculty (or the programme)
--       belongs to — Administration, College, Pharmacy, Architecture, General —
--       and the series runs on across years from the last number it issued;
--     · the faculty segment is the faculty's matriculation code, which a
--       programme may override (MBBS carries its own).
--   The format itself is a row: which components appear, the University code,
--   the separator, the padding. The formatter builds from the configuration.
--   A number once issued is permanent (V013's trigger stands), every issue is
--   on its own history, and the student is told.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V263: matriculation number by configuration', true);

-- ── 1 · the series, and the format rule ──────────────────────────────────

CREATE TABLE people.matric_series (
    code        text PRIMARY KEY,
    name        text NOT NULL,
    last_issued bigint NOT NULL DEFAULT 0,
    active      boolean NOT NULL DEFAULT true,
    note        text NULL,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ms_code CHECK (code ~ '^[A-Z][A-Z0-9_]{1,20}$'),
    CONSTRAINT ck_ms_last CHECK (last_issued >= 0)
);
SELECT audit.attach('people.matric_series');
INSERT INTO people.matric_series (code, name, last_issued, note) VALUES
    ('ADMIN', 'Administration and Management series', 13556, 'Faculty of Management Sciences'),
    ('COLLEGE', 'College series', 6093, 'Basic and Applied Medical Sciences, and Medicine and Surgery'),
    ('PHARMACY', 'Pharmacy series', 198, 'Pharmaceutical Sciences'),
    ('ARCHITECTURE', 'Architecture series', 76, 'Architecture'),
    ('GENERAL', 'General series', 85631, 'Every other faculty');

CREATE TABLE people.matric_format (
    id              text PRIMARY KEY DEFAULT 'UNIVERSITY',
    university_code text NOT NULL DEFAULT 'MOAU',
    faculty_code    boolean NOT NULL DEFAULT true,
    programme_code  boolean NOT NULL DEFAULT true,    -- the component exists; each programme says whether it carries one
    year            boolean NOT NULL DEFAULT true,
    sequence        boolean NOT NULL DEFAULT true,
    sequence_digits int NOT NULL DEFAULT 0,           -- 0: no padding; the series' own count
    separator       text NOT NULL DEFAULT '/',
    note            text NULL,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_mf_one CHECK (id = 'UNIVERSITY'),
    CONSTRAINT ck_mf_univ CHECK (university_code ~ '^[A-Z]{2,6}$'),
    CONSTRAINT ck_mf_sep CHECK (separator IN ('/', '-')),
    CONSTRAINT ck_mf_digits CHECK (sequence_digits BETWEEN 0 AND 8),
    CONSTRAINT ck_mf_seq CHECK (sequence)
);
SELECT audit.attach('people.matric_format');
INSERT INTO people.matric_format (id, note) VALUES ('UNIVERSITY', 'MOAU/{FACULTY}/{PROGRAMME}/{YY}/{SEQUENCE}; the programme segment where the programme is configured to carry one');

-- ── 2 · what the faculty and the programme say about their number ───────

ALTER TABLE ref.faculty
    ADD COLUMN IF NOT EXISTS matric_code   text NULL,
    ADD COLUMN IF NOT EXISTS matric_series text NULL REFERENCES people.matric_series(code),
    ADD CONSTRAINT ck_faculty_matric_code CHECK (matric_code IS NULL OR matric_code ~ '^[A-Z0-9]{2,6}$');
ALTER TABLE ref.programme
    ADD COLUMN IF NOT EXISTS matric_code         text NULL,          -- the short code the number carries (ACC), not the programme's reference code (C00019)
    ADD COLUMN IF NOT EXISTS matric_uses_code    boolean NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS matric_faculty_code text NULL,          -- a programme that carries its own faculty segment (MBBS)
    ADD COLUMN IF NOT EXISTS matric_series       text NULL REFERENCES people.matric_series(code),
    ADD CONSTRAINT ck_programme_matric_code CHECK (matric_code IS NULL OR matric_code ~ '^[A-Z0-9]{2,6}$'),
    ADD CONSTRAINT ck_programme_matric_fac CHECK (matric_faculty_code IS NULL OR matric_faculty_code ~ '^[A-Z0-9]{2,6}$');

-- the faculties, as the schedule names them
UPDATE ref.faculty SET matric_code = CASE code WHEN 'MS' THEN 'AD' WHEN 'BAMS' THEN 'BM' WHEN 'PS' THEN 'PHRM' WHEN 'CM' THEN 'CS' WHEN 'LW' THEN 'LAW' WHEN 'TI' THEN 'TS' ELSE code END,
       matric_series = CASE code WHEN 'MS' THEN 'ADMIN' WHEN 'BAMS' THEN 'COLLEGE' WHEN 'PS' THEN 'PHARMACY' WHEN 'AC' THEN 'ARCHITECTURE' ELSE 'GENERAL' END;

-- the programmes on the schedule: the code the number carries (or none), the faculty segment where it differs, the series
WITH sched(programme_code, matric_code, faculty_segment, series_code) AS (VALUES
    ('C00019', 'ACC', 'AD', 'ADMIN'),
    ('C44827', 'FIN', 'AD', 'ADMIN'),
    ('C44829', 'TAX', 'AD', 'ADMIN'),
    ('C00021', 'BUS', 'AD', 'ADMIN'),
    ('C44828', 'MAR', 'AD', 'ADMIN'),
    ('C51691', 'PUB', 'AD', 'ADMIN'),
    ('C29132', 'ANA', 'BM', 'COLLEGE'),
    ('C49412', 'MLS', 'BM', 'COLLEGE'),
    ('C35147', 'NUR', 'BM', 'COLLEGE'),
    ('C18115', 'PHS', 'BM', 'COLLEGE'),
    ('C49411', 'RAD', 'BM', 'COLLEGE'),
    ('C00061', NULL, 'MBBS', 'COLLEGE'),
    ('C73770', NULL, 'PHRM', 'PHARMACY'),
    ('C51900', 'ARC', 'AC', 'ARCHITECTURE'),
    ('C72222', 'LSA', 'AC', 'ARCHITECTURE'),
    ('C40831', 'ITD', 'AC', 'ARCHITECTURE'),
    ('C00002', 'ENG', 'AR', 'GENERAL'),
    ('C00067', 'HIS', 'AR', 'GENERAL'),
    ('C00003', 'FRE', 'AR', 'GENERAL'),
    ('C00005', 'LIN', 'AR', 'GENERAL'),
    ('C00094', 'PHL', 'AR', 'GENERAL'),
    ('C00062', 'REL', 'AR', 'GENERAL'),
    ('C00066', 'THA', 'AR', 'GENERAL'),
    ('C13707', 'ADV', 'CS', 'GENERAL'),
    ('C60514', 'BRO', 'CS', 'GENERAL'),
    ('C62073', 'DEV', 'CS', 'GENERAL'),
    ('C94958', 'JOU', 'CS', 'GENERAL'),
    ('C48372', 'PUB', 'CS', 'GENERAL'),
    ('C98602', 'STR', 'CS', 'GENERAL'),
    ('C00001', 'EEN', 'ED', 'GENERAL'),
    ('C34921', 'REL', 'ED', 'GENERAL'),
    ('C62664', 'SOS', 'ED', 'GENERAL'),
    ('C00219', 'EMG', 'ED', 'GENERAL'),
    ('C00220', 'GDC', 'ED', 'GENERAL'),
    ('C47096', 'GDC', 'ED', 'GENERAL'),
    ('C00065', 'PPE', 'ED', 'GENERAL'),
    ('C00091', 'PPE', 'ED', 'GENERAL'),
    ('C00093', 'PPS', 'ED', 'GENERAL'),
    ('C00090', 'PSS', 'ED', 'GENERAL'),
    ('C00010', 'PHE', 'ED', 'GENERAL'),
    ('C00012', 'EBI', 'ED', 'GENERAL'),
    ('C00014', 'ECH', 'ED', 'GENERAL'),
    ('C67895', 'CED', 'ED', 'GENERAL'),
    ('C44826', 'EIS', 'ED', 'GENERAL'),
    ('C00016', 'EMT', 'ED', 'GENERAL'),
    ('C00017', 'EPH', 'ED', 'GENERAL'),
    ('C00025', 'GEO', 'ES', 'GENERAL'),
    ('C30468', 'URP', 'ES', 'GENERAL'),
    ('C00033', NULL, 'LAW', 'GENERAL'),
    ('C64548', 'BCH', 'SC', 'GENERAL'),
    ('C00060', 'BIO', 'SC', 'GENERAL'),
    ('C52295', 'MCB', 'SC', 'GENERAL'),
    ('C82347', 'PSB', 'SC', 'GENERAL'),
    ('C22229', 'ICH', 'SC', 'GENERAL'),
    ('C00022', 'CHM', 'SC', 'GENERAL'),
    ('C52395', 'EMT', 'SC', 'GENERAL'),
    ('C00023', 'CMP', 'SC', 'GENERAL'),
    ('C00028', 'MTH', 'SC', 'GENERAL'),
    ('C56345', 'STA', 'SC', 'GENERAL'),
    ('C00029', 'PHY', 'SC', 'GENERAL'),
    ('C00024', 'ECO', 'SS', 'GENERAL'),
    ('C00030', 'POL', 'SS', 'GENERAL'),
    ('C00031', 'PSY', 'SS', 'GENERAL'),
    ('C00032', 'SOC', 'SS', 'GENERAL'),
    ('C00063', 'LIS', 'SS', 'GENERAL'),
    ('C78876', 'HED', 'TS', 'GENERAL'),
    ('C67773', 'BED', 'TS', 'GENERAL'),
    ('C27835', 'TEC', 'TS', 'GENERAL')
)
UPDATE ref.programme p SET matric_code = s.matric_code, matric_uses_code = s.matric_code IS NOT NULL,
       matric_faculty_code = CASE WHEN s.faculty_segment <> coalesce((SELECT f.matric_code FROM ref.faculty f WHERE f.code = p.faculty_code), '') THEN s.faculty_segment END,
       matric_series = CASE WHEN s.series_code <> coalesce((SELECT f.matric_series FROM ref.faculty f WHERE f.code = p.faculty_code), '') THEN s.series_code END
  FROM sched s WHERE s.programme_code = p.code;
-- a programme the schedule does not name carries no code until the Registry gives it one
UPDATE ref.programme SET matric_uses_code = false WHERE matric_code IS NULL;

-- ── 3 · the history: every number issued, permanent ──────────────────────

CREATE TABLE people.matric_history (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id   uuid NOT NULL REFERENCES people.student(id),
    matric_no    text NOT NULL UNIQUE,
    series_code  text NOT NULL REFERENCES people.matric_series(code),
    sequence     bigint NOT NULL,
    components   jsonb NOT NULL,
    run_id       uuid NULL REFERENCES people.matriculation_run(id),
    issued_at    timestamptz NOT NULL DEFAULT now(),
    issued_by    uuid NULL,
    actor_office text NULL,
    reason       text NULL,
    UNIQUE (series_code, sequence)
);
CREATE INDEX ix_mh_student ON people.matric_history (student_id);
SELECT audit.attach('people.matric_history');
CREATE OR REPLACE FUNCTION people.matric_history_is_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'the matriculation history is written once; a number issued is never edited or reused' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_matric_history_written_once BEFORE UPDATE ON people.matric_history FOR EACH ROW EXECUTE FUNCTION people.matric_history_is_written_once();

-- the shape: the configured form, the V064 form, and a legacy number kept as issued
ALTER TABLE people.student DROP CONSTRAINT IF EXISTS ck_student_matric_shape;
ALTER TABLE people.student ADD CONSTRAINT ck_student_matric_shape CHECK (
    matric_no IS NULL
    OR matric_no ~ '^[A-Z]{2,6}[/-][A-Z0-9]{2,6}([/-][A-Z0-9]{2,6})?[/-][0-9]{2}[/-][0-9]{1,8}$'   -- MOAU/FAC[/PROG]/YY/SEQ, or MOAUM/DEPT/YY/NNNN
    OR matric_no ~ '^[A-Z]{2,6}(/[A-Z0-9]{2,6}){1,4}/[0-9]{2,7}$'                              -- a legacy old-portal number, kept as issued
);

-- ── 4 · the components, the formatter, the next number ───────────────────

/* what the record and the configuration say a student's number is made of */
CREATE OR REPLACE FUNCTION people.matric_components(p_student uuid)
RETURNS TABLE (university_code text, faculty_segment text, programme_segment text, uses_code boolean, yy text, series_code text, programme_code text, programme text, faculty_code text, faculty text, problem text)
LANGUAGE sql STABLE AS $$
    SELECT mf.university_code,
           CASE WHEN mf.faculty_code THEN coalesce(p.matric_faculty_code, f.matric_code, f.code) END,
           CASE WHEN mf.programme_code AND p.matric_uses_code THEN p.matric_code END,
           mf.programme_code AND p.matric_uses_code,
           CASE WHEN mf.year THEN substr(coalesce(s.entry_session, to_char(now(), 'YYYY')), 3, 2) END,
           coalesce(p.matric_series, f.matric_series, 'GENERAL'),
           p.code, p.name, f.code, f.name,
           CASE WHEN p.code IS NULL THEN 'The student has no programme on the record'
                WHEN mf.programme_code AND p.matric_uses_code AND p.matric_code IS NULL THEN 'Programme ' || p.name || ' is configured to carry a code but has none; give it one or set it to carry none'
                WHEN mf.faculty_code AND coalesce(p.matric_faculty_code, f.matric_code, f.code) IS NULL THEN 'The faculty has no matriculation code'
                WHEN NOT EXISTS (SELECT 1 FROM people.matric_series ms WHERE ms.code = coalesce(p.matric_series, f.matric_series, 'GENERAL') AND ms.active) THEN 'The series ' || coalesce(p.matric_series, f.matric_series, 'GENERAL') || ' is not active' END
      FROM people.student s
      CROSS JOIN people.matric_format mf
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     WHERE s.id = p_student AND mf.id = 'UNIVERSITY';
$$;

/* the number from its parts: only the parts that exist, one separator between them, never an empty segment */
CREATE OR REPLACE FUNCTION people.format_matric(p_university text, p_faculty text, p_programme text, p_yy text, p_sequence bigint)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT array_to_string(array_remove(ARRAY[
               nullif(btrim(coalesce(p_university, '')), ''),
               nullif(btrim(coalesce(p_faculty, '')), ''),
               nullif(btrim(coalesce(p_programme, '')), ''),
               nullif(btrim(coalesce(p_yy, '')), ''),
               CASE WHEN p_sequence IS NULL THEN NULL
                    WHEN mf.sequence_digits > 0 THEN lpad(p_sequence::text, mf.sequence_digits, '0')
                    ELSE p_sequence::text END], NULL), mf.separator)
      FROM people.matric_format mf WHERE mf.id = 'UNIVERSITY';
$$;

/* what the next number would be, without spending it */
CREATE OR REPLACE FUNCTION people.matric_preview(p_student uuid)
RETURNS TABLE (matric_no text, series_code text, sequence bigint, problem text)
LANGUAGE sql STABLE AS $$
    SELECT people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, c.yy, ms.last_issued + 1), c.series_code, ms.last_issued + 1, c.problem
      FROM people.matric_components(p_student) c LEFT JOIN people.matric_series ms ON ms.code = c.series_code;
$$;

/* the next number, spent: the series locked, the sequence moved, the number checked unique, the history written */
CREATE OR REPLACE FUNCTION people.next_matric(p_student uuid, p_run uuid, p_reason text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE c record; ms people.matric_series; v_seq bigint; v_no text; v_try int := 0;
BEGIN
    SELECT * INTO c FROM people.matric_components(p_student);
    IF c.problem IS NOT NULL THEN
        RAISE EXCEPTION 'the matriculation number cannot be built: %', c.problem USING ERRCODE = '23514', HINT = 'The Registry configures the faculty, the programme and the series under Matriculation number format.';
    END IF;
    SELECT * INTO ms FROM people.matric_series WHERE code = c.series_code FOR UPDATE;
    IF ms.code IS NULL THEN RAISE EXCEPTION 'no series %', c.series_code USING ERRCODE = '23503'; END IF;
    LOOP
        v_try := v_try + 1;
        v_seq := ms.last_issued + v_try;
        v_no := people.format_matric(c.university_code, c.faculty_segment, c.programme_segment, c.yy, v_seq);
        -- a number already on the register (a legacy import, say) is passed over: the sequence is spent, never reused
        EXIT WHEN NOT EXISTS (SELECT 1 FROM people.student s WHERE s.matric_no = v_no)
             AND NOT EXISTS (SELECT 1 FROM people.matric_history h WHERE h.matric_no = v_no OR (h.series_code = c.series_code AND h.sequence = v_seq));
        IF v_try > 1000 THEN RAISE EXCEPTION 'no free number in series % after a thousand tries', c.series_code USING ERRCODE = '23514'; END IF;
    END LOOP;
    UPDATE people.matric_series SET last_issued = v_seq, updated_at = now() WHERE code = ms.code;
    INSERT INTO people.matric_history (student_id, matric_no, series_code, sequence, components, run_id, issued_by, actor_office, reason)
    VALUES (p_student, v_no, c.series_code, v_seq,
            jsonb_build_object('university', c.university_code, 'faculty', c.faculty_segment, 'programme', c.programme_segment, 'usesCode', c.uses_code,
                               'year', c.yy, 'sequence', v_seq, 'programmeCode', c.programme_code, 'facultyCode', c.faculty_code),
            p_run, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''), p_reason);
    RETURN v_no;
END $$;

/* the student told: email and SMS where the record reaches them */
CREATE OR REPLACE FUNCTION people.matric_tell(p_student uuid, p_no text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE reach record;
BEGIN
    SELECT * INTO reach FROM people.student_reach(p_student);
    PERFORM platform.queue_notice('EMAIL', reach.email, 'Your matriculation number',
        'Your matriculation number is ' || p_no || '. It is permanent, it opens the portal in place of your admission number, and it appears on every document the University issues to you.'
        || E'\n\nOffice of the Registrar, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', p_student);
    PERFORM platform.queue_notice('SMS', reach.phone, 'Your matriculation number', 'MOAUM: your matriculation number is ' || p_no || '. It opens the portal from now.', 'student', p_student);
END $$;

-- ── 5 · the run and the single issue, on the new generator ──────────────

CREATE OR REPLACE FUNCTION people.matriculate(p_session text)
RETURNS TABLE (run_ref text, issued int)
LANGUAGE plpgsql AS $$
DECLARE v_missing text; v_run uuid := gen_random_uuid(); v_ref text; v_n int := 0; r record; v_no text;
BEGIN
    SELECT string_agg(f.name, ', ' ORDER BY f.name) INTO v_missing
      FROM ref.faculty f
     WHERE EXISTS (SELECT 1 FROM people.faculty_list_rows(p_session, f.code))
       AND NOT EXISTS (SELECT 1 FROM people.faculty_list l WHERE l.session = p_session AND l.faculty_code = f.code AND l.state = 'CONFIRMED');
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION 'the run cannot start: % has not confirmed its list', v_missing USING ERRCODE = 'check_violation',
              HINT = 'A run with a faculty outstanding would leave its students unmatriculated after their classmates, or force a second run whose numbers sit at the end of the sequence. Confirm every list first.';
    END IF;
    v_ref := 'MAT/' || substr(p_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', p_session)::text, 3, '0');
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (v_run, v_ref, p_session, 0);
    FOR r IN
        SELECT x.student_id, x.dept_code
          FROM ref.faculty f
          CROSS JOIN LATERAL people.faculty_list_rows(p_session, f.code) x
         WHERE x.query_reason IS NULL
           AND (SELECT fp.paid_in_full FROM finance.position(x.student_id, p_session) fp)
         ORDER BY x.dept_code, x.surname, x.other_names
    LOOP
        v_no := people.next_matric(r.student_id, v_run, 'Matriculation run ' || v_ref);
        UPDATE people.student SET matric_no = v_no, matriculated_at = now(), matriculation_run = v_run, status = 'ACTIVE' WHERE id = r.student_id;
        INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
        VALUES (gen_random_uuid(), r.student_id, 'ADMITTED', 'ACTIVE', v_ref, current_date, 'Matriculated');
        PERFORM people.matric_tell(r.student_id, v_no);
        v_n := v_n + 1;
    END LOOP;
    IF v_n = 0 THEN
        RAISE EXCEPTION 'nobody on a confirmed list has both paid the fees and registered for %; there is nothing to matriculate', p_session USING ERRCODE = 'no_data_found';
    END IF;
    UPDATE people.matriculation_run SET issued = v_n WHERE id = v_run;
    RETURN QUERY SELECT v_ref, v_n;
END $$;

CREATE OR REPLACE FUNCTION people.matriculate_student(p_student uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s people.student; v_run uuid; v_ref text; v_no text; v_paid boolean;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    IF s.matric_no IS NOT NULL THEN RETURN s.matric_no; END IF;
    IF s.status <> 'ADMITTED' THEN RAISE EXCEPTION 'only an admitted student is matriculated; this one is %', lower(s.status) USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = s.entry_session AND r.status IN ('APPROVED','LOCKED')) THEN
        RAISE EXCEPTION 'the student has not registered courses for %', s.entry_session USING ERRCODE = '23514', HINT = 'A matriculation number is issued once the school fees are paid and the courses are registered.';
    END IF;
    SELECT fp.paid_in_full INTO v_paid FROM finance.position(p_student, s.entry_session) fp;
    IF NOT coalesce(v_paid, false) THEN
        RAISE EXCEPTION 'the school fees for % are not settled', s.entry_session USING ERRCODE = '23514', HINT = 'A matriculation number is issued once the school fees are paid and the courses are registered.';
    END IF;
    v_run := gen_random_uuid();
    v_ref := 'MAT/' || substr(s.entry_session, 1, 4) || '/' || lpad(platform.next_number('MATRIC_RUN', 'UNIVERSITY', s.entry_session)::text, 3, '0');
    INSERT INTO people.matriculation_run (id, ref, session, issued) VALUES (v_run, v_ref, s.entry_session, 1);
    v_no := people.next_matric(p_student, v_run, 'Matriculated on fees and registration');
    UPDATE people.student SET matric_no = v_no, matriculated_at = now(), matriculation_run = v_run, status = 'ACTIVE' WHERE id = p_student;
    INSERT INTO people.status_change (id, student_id, from_status, to_status, instrument, effective_on, reason)
    VALUES (gen_random_uuid(), p_student, 'ADMITTED', 'ACTIVE', v_ref, current_date, 'Matriculated on fees and registration');
    PERFORM people.matric_tell(p_student, v_no);
    RETURN v_no;
END $$;

-- ── 6 · what the desk reads: every programme, its segments, the number it would give ──

CREATE OR REPLACE FUNCTION people.matric_config_rows()
RETURNS TABLE (programme_code text, programme text, faculty_code text, faculty text, faculty_matric_code text, faculty_series text, matric_code text, matric_uses_code boolean,
               matric_faculty_code text, matric_series text, series_effective text, sample text, problem text, students_admitted bigint, archived boolean, category text)
LANGUAGE sql STABLE AS $$
    SELECT p.code, p.name, f.code, f.name, f.matric_code, f.matric_series, p.matric_code, p.matric_uses_code, p.matric_faculty_code, p.matric_series,
           coalesce(p.matric_series, f.matric_series, 'GENERAL'),
           people.format_matric(mf.university_code, CASE WHEN mf.faculty_code THEN coalesce(p.matric_faculty_code, f.matric_code, f.code) END,
                                CASE WHEN mf.programme_code AND p.matric_uses_code THEN p.matric_code END, CASE WHEN mf.year THEN to_char(now(), 'YY') END,
                                (SELECT ms.last_issued + 1 FROM people.matric_series ms WHERE ms.code = coalesce(p.matric_series, f.matric_series, 'GENERAL'))),
           CASE WHEN mf.programme_code AND p.matric_uses_code AND p.matric_code IS NULL THEN 'Configured to carry a code but has none' END,
           (SELECT count(*) FROM people.student s WHERE s.programme_code = p.code AND s.status = 'ADMITTED'),
           p.archived, p.category
      FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code CROSS JOIN people.matric_format mf
     WHERE mf.id = 'UNIVERSITY'
     ORDER BY f.name, p.name;
$$;

GRANT SELECT, INSERT, UPDATE ON people.matric_series, people.matric_format, people.matric_history TO app_student;
GRANT SELECT ON people.matric_series, people.matric_format, people.matric_history TO app_auditor;

COMMIT;
