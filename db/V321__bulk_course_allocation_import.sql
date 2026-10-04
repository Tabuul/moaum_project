-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- V321 — bulk course allocation to lecturers: the record of each import
--
--   Teaching allocation stays what it is (V041): the lead lecturer and the second examiner on the
--   offering, co-lecturers on catalogue.offering_teacher, the 12-unit rule in catalogue.allocate_offering,
--   the score sheet opened in the lead's name. The bulk import reads a spreadsheet of staff numbers and
--   course codes, validates every row against the register — the lecturer, their department, the course,
--   its department, the programme and level it is offered to, the session, the semester, the offering,
--   duplicates in the file and allocations already on record — shows the result, and only then writes
--   the valid rows through the same allocation. Nothing in the spreadsheet creates or changes a lecturer,
--   a course, a department, a programme, a session or a semester.
--
--   catalogue.allocation_import is the record of each import: a reference the office can quote, the file,
--   who uploaded it in which office, the session and semester, the counts, the status, the options chosen,
--   and every finding row by row (the error report). An import key makes a repeated submission of the
--   same file answer with the record it already made rather than allocate twice.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V321: the record of bulk course allocation imports', true);

CREATE TABLE catalogue.allocation_import (
    id              uuid        PRIMARY KEY,
    reference       text        NOT NULL UNIQUE,
    import_key      uuid        NOT NULL UNIQUE,
    file_name       text        NULL,
    session         text        NOT NULL REFERENCES policy.academic_session(name),
    semester        int         NULL,
    scope_dept      text        NULL,
    uploaded_by     uuid        NOT NULL,
    uploader_office text        NOT NULL,
    uploaded_at     timestamptz NOT NULL DEFAULT now(),
    total_rows      int         NOT NULL DEFAULT 0,
    valid_rows      int         NOT NULL DEFAULT 0,
    imported        int         NOT NULL DEFAULT 0,
    existing        int         NOT NULL DEFAULT 0,
    skipped         int         NOT NULL DEFAULT 0,
    errors          int         NOT NULL DEFAULT 0,
    warnings        int         NOT NULL DEFAULT 0,
    status          text        NOT NULL,
    options         jsonb       NULL,
    findings        jsonb       NULL,
    CONSTRAINT ck_allocation_import_status CHECK (status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS', 'NOTHING_TO_IMPORT')),
    CONSTRAINT ck_allocation_import_counts CHECK (total_rows >= 0 AND imported >= 0 AND imported <= total_rows)
);
CREATE INDEX ix_allocation_import_when ON catalogue.allocation_import (uploaded_at DESC);
CREATE INDEX ix_allocation_import_scope ON catalogue.allocation_import (scope_dept, uploaded_at DESC);
COMMENT ON TABLE catalogue.allocation_import IS
  'V321: each bulk course allocation import — its reference, file, uploader and office, session and semester, the counts, the status, the options chosen and every finding row by row. The allocations themselves are on catalogue.offering and catalogue.offering_teacher, as every allocation is.';
SELECT audit.attach('catalogue.allocation_import');

/* the record of an import, numbered in the session: ALLOC/2026-2027/00001. A repeated import key returns the record
   already made — the import that made it is not made again. */
CREATE OR REPLACE FUNCTION catalogue.record_allocation_import(p_key uuid, p_file text, p_session text, p_semester int, p_scope_dept text,
                                                              p_total int, p_valid int, p_imported int, p_existing int, p_skipped int,
                                                              p_errors int, p_warnings int, p_status text, p_options jsonb, p_findings jsonb)
RETURNS catalogue.allocation_import
LANGUAGE plpgsql AS $$
DECLARE r catalogue.allocation_import; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), ''); v_ref text;
BEGIN
    SELECT * INTO r FROM catalogue.allocation_import WHERE import_key = p_key;
    IF FOUND THEN
        RETURN r;
    END IF;
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'an allocation import is made by a person' USING ERRCODE = '23514';
    END IF;
    v_ref := 'ALLOC/' || replace(p_session, '/', '-') || '/' || lpad(platform.next_number('allocation_import', 'UNIVERSITY', p_session)::text, 5, '0');
    INSERT INTO catalogue.allocation_import (id, reference, import_key, file_name, session, semester, scope_dept, uploaded_by, uploader_office,
                                             total_rows, valid_rows, imported, existing, skipped, errors, warnings, status, options, findings)
    VALUES (gen_random_uuid(), v_ref, p_key, nullif(btrim(coalesce(p_file, '')), ''), p_session, p_semester, p_scope_dept, v_actor, coalesce(v_office, '?'),
            p_total, p_valid, p_imported, p_existing, p_skipped, p_errors, p_warnings, p_status, p_options, p_findings)
    RETURNING * INTO r;
    RETURN r;
END $$;
COMMENT ON FUNCTION catalogue.record_allocation_import(uuid, text, text, int, text, int, int, int, int, int, int, int, text, jsonb, jsonb) IS
  'V321: records a bulk allocation import under a reference numbered in the session; the same import key answers with the record already made.';

COMMIT;
