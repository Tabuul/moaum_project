-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V734 · College Deans as inter-departmental transfer approving authorities
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's master prompt of 12 November 2026, part B: "allow the appropriate College Deans, who serve as the Heads of
--  Department or approving authorities for their respective Colleges, to view and approve transfer applications … integrate the
--  functionality into the existing Inter-Departmental Transfer module and approval workflow … do not assume that every transfer
--  requires approval from both Colleges unless that is part of the existing institutional approval policy".
--
--  Inspected first (docs/inter-departmental-transfer-fee-and-old-portal-payments.md, V070/V185/V186/V727, TransferController): the
--  chain is the current department (APPLIED → FROM_OK, once anything is paid), the new department (FROM_OK → TO_OK), the Registry
--  (TO_OK → REG_OK) and the Academic Office's final approval (REG_OK → EFFECTED, the whole fee paid and nothing awaiting the bank).
--  The department desks are the HODs' (iam.acting_department), and no Dean or Provost could read or act; the fifteen departments of
--  the College of Health Sciences have no HOD grant on the live copy, so only the Super Administrator could move an application of
--  theirs. The policy is that both the releasing and the receiving department approve; nothing else.
--
--  So no new stage and no second system: at a department desk whose department belongs to a College (ref.faculty.college_code), the
--  Dean of that department's faculty is that department's approving authority, beside an HOD where one is granted. A transfer within
--  the University's faculties moves exactly as before; one out of a College is released by the College's Dean, one into a College
--  received by it; one between two Colleges passes each College at its own desk, in the existing order. The payment rules stand as
--  they are (any verified payment before the current department acts; the whole fee before the final approval). The Java gate
--  (TransferController.mayApprove) holds who may act, as it always has; this migration gives it what it reads:
--    people.transfer_unit(programme)  the department, faculty and College of a programme's side (the department's faculty, else the
--                                     programme's, as the transfer-fee monitor reads it);
--    people.transfer_desk(application) who holds the application now — the desk, its unit, the offices that may act and their words;
--    people.transfer_desk_people(application) the live holders of those offices over that unit, to be told it awaits them;
--    people.transfer_event            the approval history, written once by a trigger on every change of state (who, which office,
--                                     which desk and unit, the decision, the comment or reason, the next desk), backfilled from the
--                                     desks' stamps for the applications already made;
--    people.transfer_list             the desk list, with each side's department, faculty and College named (columns appended).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V734: College Deans as inter-departmental transfer approving authorities', true);

-- ── 1 · a programme's side: its department, faculty and College ─────────────────────────────────────────────────────────────────
CREATE FUNCTION people.transfer_unit(p_programme text)
RETURNS TABLE(dept_code text, dept_name text, faculty_code text, faculty_name text, college_code text, college_name text)
LANGUAGE sql STABLE AS $$
    SELECT p.dept_code, d.name, f.code, f.name, c.code, c.name
      FROM ref.programme p
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
      LEFT JOIN ref.college c ON c.code = f.college_code
     WHERE p.code = p_programme;
$$;
COMMENT ON FUNCTION people.transfer_unit(text) IS
  'V734: a transfer side''s unit — the programme''s department, that department''s faculty (else the programme''s, as the transfer-fee monitor reads it) and the faculty''s College, if it is in one.';

-- ── 2 · the desk holding an application, and who may act at it ──────────────────────────────────────────────────────────────────
CREATE FUNCTION people.transfer_desk(p_app uuid)
RETURNS TABLE(state text, desk text, dept_code text, dept_name text, faculty_code text, faculty_name text, college_code text, college_name text,
              offices text[], label text)
LANGUAGE sql STABLE AS $$
    WITH t AS (SELECT * FROM people.transfer_application WHERE id = p_app),
    side AS (
        SELECT t.state,
               CASE t.state WHEN 'APPLIED' THEN 'FROM_DEPARTMENT' WHEN 'FROM_OK' THEN 'TO_DEPARTMENT'
                            WHEN 'TO_OK' THEN 'REGISTRY' WHEN 'REG_OK' THEN 'ACADEMIC' END AS desk,
               CASE t.state WHEN 'APPLIED' THEN t.from_programme_code WHEN 'FROM_OK' THEN t.to_programme_code END AS programme
          FROM t)
    SELECT s.state, s.desk, u.dept_code, u.dept_name, u.faculty_code, u.faculty_name, u.college_code, u.college_name,
           CASE s.desk
                WHEN 'FROM_DEPARTMENT' THEN CASE WHEN u.college_code IS NOT NULL THEN ARRAY['hod', 'dean'] ELSE ARRAY['hod'] END
                WHEN 'TO_DEPARTMENT'   THEN CASE WHEN u.college_code IS NOT NULL THEN ARRAY['hod', 'dean'] ELSE ARRAY['hod'] END
                WHEN 'REGISTRY' THEN ARRAY['registrar', 'dregistrar']
                WHEN 'ACADEMIC' THEN ARRAY['academic']
           END,
           CASE s.desk
                WHEN 'FROM_DEPARTMENT' THEN 'the current department — ' || coalesce(u.dept_name, 'its department')
                     || CASE WHEN u.college_code IS NOT NULL THEN ': the Head of Department or the Dean, ' || coalesce(u.faculty_name, 'the faculty') || ', ' || u.college_name ELSE ': the Head of Department' END
                WHEN 'TO_DEPARTMENT' THEN 'the new department — ' || coalesce(u.dept_name, 'its department')
                     || CASE WHEN u.college_code IS NOT NULL THEN ': the Head of Department or the Dean, ' || coalesce(u.faculty_name, 'the faculty') || ', ' || u.college_name ELSE ': the Head of Department' END
                WHEN 'REGISTRY' THEN 'the Registry'
                WHEN 'ACADEMIC' THEN 'the Academic Office (final approval)'
           END
      FROM side s LEFT JOIN LATERAL people.transfer_unit(s.programme) u ON s.programme IS NOT NULL;
$$;
COMMENT ON FUNCTION people.transfer_desk(uuid) IS
  'V734: the desk holding a transfer application — the releasing department (APPLIED), the receiving department (FROM_OK), the Registry (TO_OK) or the Academic Office (REG_OK) — its unit, and the offices that may act: at a department of a College, its faculty''s Dean beside the HOD. NULL desk when nothing is pending.';

/* the live holders of the desk's offices over its unit: an HOD whose acting department is the department, a Dean whose acting
   faculty is the department's faculty in a College, any Registrar, Deputy Registrar or Academic Office holder at their desks */
CREATE FUNCTION people.transfer_desk_people(p_app uuid)
RETURNS TABLE(person_id uuid, name text, email text, phone text, office text)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (a.person_id) a.person_id, h.name, h.email, h.phone, a.office_code
      FROM people.transfer_desk(p_app) d
      JOIN iam.office_assignment a ON a.office_code = ANY (d.offices)
      JOIN iam.person pe ON pe.id = a.person_id AND pe.ended_on IS NULL
     CROSS JOIN LATERAL assessment.staff_reach(a.person_id) h
     WHERE a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
       AND CASE a.office_code
                WHEN 'hod'  THEN upper(iam.acting_department(a.person_id, 'hod')) = upper(d.dept_code)
                WHEN 'dean' THEN d.college_code IS NOT NULL AND upper(iam.acting_faculty(a.person_id, 'dean')) = upper(d.faculty_code)
                ELSE true
           END
     ORDER BY a.person_id, a.office_code;
$$;
COMMENT ON FUNCTION people.transfer_desk_people(uuid) IS
  'V734: the live holders who may act at a transfer application''s desk — told when it reaches them.';

-- ── 3 · the approval history, written once on every change of state ─────────────────────────────────────────────────────────────
CREATE TABLE people.transfer_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES people.transfer_application(id) ON DELETE CASCADE,
    at             timestamptz NOT NULL DEFAULT clock_timestamp(),   -- the moment, so moves within one act read in their order
    from_state     text,
    to_state       text NOT NULL,
    decision       text NOT NULL CHECK (decision IN ('APPLIED', 'RECORDED', 'APPROVED', 'DECLINED', 'WITHDRAWN', 'RECOMMENDED',
                                                     'NOT_RECOMMENDED', 'EFFECTED', 'CHANGED')),
    desk           text,              -- the desk that acted: FROM_DEPARTMENT, TO_DEPARTMENT, REGISTRY, ACADEMIC, COMMITTEE, SENATE, OFFICE
    dept_code      text,
    faculty_code   text,
    college_code   text,
    office         text,
    actor          uuid,
    note           text,
    next_desk      text,              -- the words of the desk it went to, if it is still live
    source         text NOT NULL DEFAULT 'PORTAL' CHECK (source IN ('PORTAL', 'RECORD'))
);
CREATE INDEX ix_transfer_event_application ON people.transfer_event (application_id, at);
SELECT audit.attach('people.transfer_event');
COMMENT ON TABLE people.transfer_event IS
  'V734: every change of a transfer application''s state — the desk and its unit (department, faculty, College), the office and person, the decision, the comment or reason, the next desk. Written once by trg_transfer_event; RECORD rows backfilled from the desks'' stamps of applications made before V734.';

CREATE FUNCTION people.transfer_event_kept() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- an application removed (the operational-data reset, a test's own cleanup) takes its history with it: the cascade's delete runs
    -- inside the foreign key's trigger; a history row is never changed or removed on its own
    IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'TRANSFER_EVENT_KEPT: a transfer''s approval history is written once and kept' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_transfer_event_kept BEFORE UPDATE OR DELETE ON people.transfer_event
    FOR EACH ROW EXECUTE FUNCTION people.transfer_event_kept();

CREATE FUNCTION people.transfer_event_record() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_prog text; v_desk text; u record; v_next text; v_decision text; v_note text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_decision := CASE WHEN NEW.state = 'APPLIED' THEN 'APPLIED' ELSE 'RECORDED' END;
        v_desk := CASE WHEN nullif(current_setting('moaum.actor_office', true), '') = 'student' THEN 'STUDENT' ELSE 'OFFICE' END;
        v_prog := NEW.from_programme_code;
    ELSE
        IF OLD.state IS NOT DISTINCT FROM NEW.state THEN RETURN NULL; END IF;
        v_decision := CASE
            WHEN NEW.state = 'DECLINED' THEN 'DECLINED'
            WHEN NEW.state = 'WITHDRAWN' THEN 'WITHDRAWN'
            WHEN NEW.state IN ('RECOMMENDED', 'NOT_RECOMMENDED') THEN NEW.state
            WHEN NEW.state = 'EFFECTED' AND OLD.state = 'APPROVED' THEN 'EFFECTED'
            WHEN NEW.state IN ('FROM_OK', 'TO_OK', 'REG_OK', 'EFFECTED', 'APPROVED') THEN 'APPROVED'
            ELSE 'CHANGED' END;
        v_desk := CASE OLD.state WHEN 'APPLIED' THEN 'FROM_DEPARTMENT' WHEN 'FROM_OK' THEN 'TO_DEPARTMENT' WHEN 'TO_OK' THEN 'REGISTRY'
                                 WHEN 'REG_OK' THEN 'ACADEMIC' WHEN 'RECOMMENDED' THEN 'SENATE' ELSE 'OFFICE' END;
        IF NEW.state IN ('RECOMMENDED', 'NOT_RECOMMENDED') THEN v_desk := 'COMMITTEE'; END IF;
        v_prog := CASE v_desk WHEN 'FROM_DEPARTMENT' THEN NEW.from_programme_code WHEN 'TO_DEPARTMENT' THEN NEW.to_programme_code END;
        v_note := coalesce(nullif(btrim(current_setting('moaum.transfer_note', true)), ''),
                           CASE NEW.state WHEN 'DECLINED' THEN NEW.decline_note WHEN 'WITHDRAWN' THEN NEW.withdrawn_why
                                          WHEN 'RECOMMENDED' THEN NEW.committee_note WHEN 'NOT_RECOMMENDED' THEN NEW.committee_note END,
                           CASE WHEN OLD.state = 'RECOMMENDED' THEN NEW.senate_note END);
    END IF;
    SELECT * INTO u FROM people.transfer_unit(v_prog) WHERE v_prog IS NOT NULL;
    -- the next desk, in words, while the application is still live (read after this change: the trigger runs AFTER)
    SELECT d.label INTO v_next FROM people.transfer_desk(NEW.id) d WHERE d.desk IS NOT NULL;
    INSERT INTO people.transfer_event (application_id, from_state, to_state, decision, desk, dept_code, faculty_code, college_code,
                                       office, actor, note, next_desk)
    VALUES (NEW.id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.state END, NEW.state, v_decision,
            v_desk,
            u.dept_code, u.faculty_code, u.college_code,
            nullif(current_setting('moaum.actor_office', true), ''), nullif(current_setting('moaum.actor_id', true), '')::uuid,
            CASE WHEN TG_OP = 'INSERT' THEN NEW.reason ELSE v_note END, v_next);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_transfer_event AFTER INSERT OR UPDATE OF state ON people.transfer_application
    FOR EACH ROW EXECUTE FUNCTION people.transfer_event_record();

-- the applications already made: their history from the desks' stamps (who and when; the office is not known)
INSERT INTO people.transfer_event (application_id, at, from_state, to_state, decision, desk, dept_code, faculty_code, college_code, actor, note, source)
SELECT t.id, x.at, x.from_state, x.to_state, x.decision, x.desk, u.dept_code, u.faculty_code, u.college_code, x.actor, x.note, 'RECORD'
  FROM people.transfer_application t
 CROSS JOIN LATERAL (VALUES
        (t.applied_at,  NULL::text, 'APPLIED',  'APPLIED',  'STUDENT',         t.applied_by,   NULL::text,       t.reason),
        (t.from_dept_at, 'APPLIED', 'FROM_OK',  'APPROVED', 'FROM_DEPARTMENT', t.from_dept_by, t.from_programme_code, NULL),
        (t.to_dept_at,  'FROM_OK',  'TO_OK',    'APPROVED', 'TO_DEPARTMENT',   t.to_dept_by,   t.to_programme_code,   NULL),
        (t.reg_at,      'TO_OK',    'REG_OK',   'APPROVED', 'REGISTRY',        t.reg_by,       NULL,             NULL),
        (t.acad_at,     'REG_OK',   'EFFECTED', 'APPROVED', 'ACADEMIC',        t.acad_by,      NULL,             NULL)
     ) AS x(at, from_state, to_state, decision, desk, actor, programme, note)
  LEFT JOIN LATERAL people.transfer_unit(x.programme) u ON x.programme IS NOT NULL
 WHERE x.at IS NOT NULL;

-- ── 4 · the desk list, each side's unit named (appended columns: DROP and CREATE, the return type grows) ─────────────────────────
DROP FUNCTION people.transfer_list(text, text);
CREATE FUNCTION people.transfer_list(p_session text, p_state text)
 RETURNS TABLE(id uuid, student_id uuid, name text, matric_no text, from_programme text, from_dept text, from_level integer, to_programme text, to_dept text, mode_of_entry text, utme_score integer, cgpa numeric, reason text, state text, recommended_level integer, committee_note text, senate_note text, decline_note text, withdrawn_why text, applied_at timestamp with time zone, from_dept_at timestamp with time zone, to_dept_at timestamp with time zone, reg_at timestamp with time zone, acad_at timestamp with time zone, effected_at timestamp with time zone, fee_reference text, fee_confirmed_at timestamp with time zone, session text, fee_due numeric, paid_total numeric, old_portal_paid numeric, balance numeric, pending boolean, band text, legacy_ref text, legacy_applied_on date, legacy_stage text, legacy_approvals text, legacy_documents text,
               from_programme_code text, from_dept_name text, from_faculty text, from_faculty_name text, from_college text, from_college_name text,
               to_programme_code text, to_dept_name text, to_faculty text, to_faculty_name text, to_college text, to_college_name text,
               desk text, desk_label text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT t.id, t.student_id, s.surname || ', ' || s.other_names, s.matric_no,
           fp.name, fp.dept_code, t.from_level, tp.name, tp.dept_code,
           t.mode_of_entry, t.utme_score, t.cgpa, t.reason, t.state,
           t.recommended_level, t.committee_note, t.senate_note, t.decline_note, t.withdrawn_why,
           t.applied_at, t.from_dept_at, t.to_dept_at, t.reg_at, t.acad_at, t.effected_at,
           t.fee_reference, fs.confirmed_at, t.session,
           e.fee_due, e.paid_total, e.old_portal_paid, e.balance, e.pending, e.band, lg.legacy_ref,
           lg.applied_on, lg.stage, lg.approvals, lg.documents,
           t.from_programme_code, fu.dept_name, fu.faculty_code, fu.faculty_name, fu.college_code, fu.college_name,
           t.to_programme_code, tu.dept_name, tu.faculty_code, tu.faculty_name, tu.college_code, tu.college_name,
           dk.desk, dk.label
      FROM people.transfer_application t
      JOIN people.student s ON s.id = t.student_id
      LEFT JOIN ref.programme fp ON fp.code = t.from_programme_code
      LEFT JOIN ref.programme tp ON tp.code = t.to_programme_code
      LEFT JOIN LATERAL finance.reference_state(t.fee_reference) fs ON t.fee_reference IS NOT NULL
      LEFT JOIN LATERAL people.transfer_entitlement(t.id) e ON true
      LEFT JOIN people.transfer_legacy lg ON lg.application_id = t.id
      LEFT JOIN LATERAL people.transfer_unit(t.from_programme_code) fu ON true
      LEFT JOIN LATERAL people.transfer_unit(t.to_programme_code) tu ON true
      LEFT JOIN LATERAL people.transfer_desk(t.id) dk ON true
     WHERE (p_session IS NULL OR t.session = p_session)
       AND (p_state IS NULL OR t.state = p_state)
     ORDER BY t.applied_at
$function$;
COMMENT ON FUNCTION people.transfer_list(text, text) IS
  'The inter-departmental transfer desk list (V185, V727: what is paid). V734: each side''s department, faculty and College named, and the desk holding the application with its words.';

COMMIT;
