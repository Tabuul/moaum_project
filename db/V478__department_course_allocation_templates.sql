-- ═══════════════════════════════════════
-- V478 — Department course allocation templates: issued from the register, checked against their own context on upload
--
-- The bulk allocation import (V321, V408) took a generic template — blank rows, and every lecturer, course and programme of
-- the University on reference sheets — so the person filling it typed course codes and staff numbers. A department's
-- template is now issued from the register as it stands: one department, one kind of programme (undergraduate or
-- postgraduate), one session and semester; its classes, their current lecturers, the department's lecturers and programmes
-- written in, the lecturer chosen from a list. Each issue is recorded and numbered, and an upload names the template it
-- came from, so the portal checks the file against the template's own context, whatever the file says:
--
--   · catalogue.allocation_template — each template issued: its reference (CAT-2026-000123), the template format's
--     version, the faculty, department, programme type, session and semester, who issued it and from which office, the
--     classes, lecturers and programmes it carried, and the support ticket it was issued on;
--   · catalogue.issue_allocation_template numbers and records one;
--   · catalogue.allocation_import carries the template it came from, the programme type and the ticket.
--
-- No allocation, class, course or lecturer is changed by this migration.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V478: department course allocation templates', true);

CREATE SEQUENCE catalogue.allocation_template_seq;

CREATE TABLE catalogue.allocation_template (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reference        text NOT NULL UNIQUE,
    version          integer NOT NULL DEFAULT 1,
    faculty_code     text,
    dept_code        text NOT NULL REFERENCES ref.department(code),
    programme_type   text NOT NULL CHECK (programme_type IN ('UNDERGRADUATE', 'POSTGRADUATE')),
    session          text NOT NULL REFERENCES policy.academic_session(name),
    semester         integer NOT NULL CHECK (semester IN (1, 2, 3)),
    issued_by        uuid NOT NULL,
    issued_office    text NOT NULL,
    issued_at        timestamptz NOT NULL DEFAULT now(),
    classes          integer NOT NULL DEFAULT 0,
    lecturers        integer NOT NULL DEFAULT 0,
    programmes       integer NOT NULL DEFAULT 0,
    allocations      integer NOT NULL DEFAULT 0,
    ticket_id        uuid REFERENCES helpdesk.ticket(id) ON DELETE SET NULL
);
CREATE INDEX ix_allocation_template_dept ON catalogue.allocation_template (dept_code, issued_at DESC);
CREATE INDEX ix_allocation_template_ticket ON catalogue.allocation_template (ticket_id) WHERE ticket_id IS NOT NULL;
COMMENT ON TABLE catalogue.allocation_template IS
  'V478: each department course allocation template issued — its reference and version, the department, programme type, session and semester it carries, who issued it, what it held, and the ticket it was issued on. An upload of it is checked against this context, never against what the file says.';
SELECT audit.attach('catalogue.allocation_template');

/* a template issued: numbered in its year (CAT-2026-000123), recorded with what it carried */
CREATE FUNCTION catalogue.issue_allocation_template(p_dept text, p_type text, p_session text, p_semester integer,
                                                    p_classes integer, p_lecturers integer, p_programmes integer, p_allocations integer, p_ticket uuid)
RETURNS TABLE (id uuid, reference text, version integer, issued_at timestamptz)
LANGUAGE plpgsql AS $fn$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        office text := nullif(current_setting('moaum.actor_office', true), '');
        v_id uuid := gen_random_uuid(); v_ref text;
BEGIN
    IF who IS NULL OR office IS NULL THEN
        RAISE EXCEPTION 'ALLOC_TEMPLATE_ACTOR: a template is issued by a person acting in an office' USING ERRCODE = '23514';
    END IF;
    v_ref := 'CAT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('catalogue.allocation_template_seq')::text, 6, '0');
    INSERT INTO catalogue.allocation_template (id, reference, faculty_code, dept_code, programme_type, session, semester, issued_by, issued_office,
                                               classes, lecturers, programmes, allocations, ticket_id)
    SELECT v_id, v_ref, d.faculty_code, d.code, p_type, p_session, p_semester, who, office,
           coalesce(p_classes, 0), coalesce(p_lecturers, 0), coalesce(p_programmes, 0), coalesce(p_allocations, 0), p_ticket
      FROM ref.department d WHERE d.code = upper(btrim(p_dept));
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ALLOC_TEMPLATE_DEPT: no department is coded %', p_dept USING ERRCODE = '23514';
    END IF;
    RETURN QUERY SELECT t.id, t.reference, t.version, t.issued_at FROM catalogue.allocation_template t WHERE t.id = v_id;
END $fn$;
COMMENT ON FUNCTION catalogue.issue_allocation_template(text, text, text, integer, integer, integer, integer, integer, uuid) IS
  'V478: a department course allocation template issued and numbered (CAT-YYYY-NNNNNN), with its context and what it carried.';

ALTER TABLE catalogue.allocation_import
    ADD COLUMN template_id uuid REFERENCES catalogue.allocation_template(id),
    ADD COLUMN programme_type text CHECK (programme_type IS NULL OR programme_type IN ('UNDERGRADUATE', 'POSTGRADUATE')),
    ADD COLUMN ticket_id uuid REFERENCES helpdesk.ticket(id) ON DELETE SET NULL;
CREATE INDEX ix_allocation_import_template ON catalogue.allocation_import (template_id) WHERE template_id IS NOT NULL;
COMMENT ON COLUMN catalogue.allocation_import.template_id IS 'V478: the department template the file came from, when it came from one';
COMMENT ON COLUMN catalogue.allocation_import.ticket_id IS 'V478: the support ticket the import answers';

COMMIT;
