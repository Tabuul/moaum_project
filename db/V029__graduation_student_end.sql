-- ═══════════════════════════════════════════════════════════════════════════
-- V029 — the graduation loop, closed at the student's end
--
--   The Academic Office runs the degree audit (records.graduand, V013) and
--   Senate approves the list on a minute; the student's status becomes
--   GRADUATED. What the student could not yet see was any of it. Now:
--
--   · records.approve_awards(session, minute) is the one act that approves
--     the list: it marks the graduands, changes each status on the minute,
--     and queues a notice to each graduand — in the same transaction, as
--     every fact written is (V025).
--   · records.student_graduation(student) is what the student sees: whether
--     they are a finalist this session, the audit's finding, Senate's word,
--     the class of degree, the clearance position for convocation unit by
--     unit, the certificate and its collection, and the verification code
--     of the degree once one is issued.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION records.approve_awards(p_session text, p_minute text)
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE n int; g record; reach record;
BEGIN
    IF p_minute IS NULL OR btrim(p_minute) = '' THEN
        RAISE EXCEPTION 'the graduation list is approved on a Senate minute, and none was cited'
        USING ERRCODE = '23514', HINT = 'Cite the minute of the Senate that approved the awards.';
    END IF;
    UPDATE records.graduand SET senate_state = 'APPROVED', senate_minute = btrim(p_minute)
     WHERE session = p_session AND senate_state = 'AWAITING' AND unmet IS NULL AND cgpa IS NOT NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    FOR g IN
        SELECT gr.student_id, gr.award, gr.cgpa, s.status, s.surname, s.other_names, s.matric_no
          FROM records.graduand gr JOIN people.student s ON s.id = gr.student_id
         WHERE gr.session = p_session AND gr.senate_state = 'APPROVED' AND gr.senate_minute = btrim(p_minute)
    LOOP
        IF g.status <> 'GRADUATED' THEN
            PERFORM people.change_status(g.student_id, 'GRADUATED', btrim(p_minute), current_date, 'Award approved by Senate');
        END IF;
        SELECT * INTO reach FROM people.student_reach(g.student_id);
        PERFORM platform.queue_notice('EMAIL', reach.email, 'Senate has approved your award',
            'Senate approved the award of ' || g.award || ' to ' || g.surname || ', ' || g.other_names || ' (' || coalesce(g.matric_no, '') ||
            ') under minute ' || btrim(p_minute) || ', with a CGPA of ' || g.cgpa || ' — ' || coalesce(policy.class_of(g.cgpa), 'Pass') ||
            '. Your certificate is printed once every unit has cleared you for convocation; the Graduation screen on the portal names any unit still holding.',
            'student', g.student_id);
        PERFORM platform.queue_notice('SMS', reach.phone, 'Senate has approved your award',
            'MOAUM: Senate approved your award of ' || g.award || ' (' || coalesce(policy.class_of(g.cgpa), 'Pass') || ') under ' || btrim(p_minute) ||
            '. See the Graduation screen on the portal for clearance and your certificate.',
            'student', g.student_id);
    END LOOP;
    RETURN n;
END $$;

COMMENT ON FUNCTION records.approve_awards(text, text) IS
  'Senate''s approval of the graduation list: the graduands marked, each status changed on the minute, each graduand told. One act, one transaction.';

-- what the student sees of their own graduation, computed from the record
CREATE OR REPLACE FUNCTION records.student_graduation(p_student uuid)
RETURNS TABLE (
    finalist        boolean,
    final_level     int,
    session         text,
    audited         boolean,
    cgpa            numeric,
    award           text,
    unmet           text,
    senate_state    text,
    senate_minute   text,
    class_of_degree text,
    status          text,
    cleared         boolean,
    units_holding   int,
    certificate_no  text,
    certificate_status text,
    convocation     text,
    printed_on      date,
    collected_on    date,
    held_reason     text,
    verification_code text,
    issued_on       date)
LANGUAGE sql STABLE AS $$
    WITH st AS (
        SELECT s.id, s.status, s.programme_code, s.current_level, p.name AS programme_name,
               CASE WHEN p.code = 'C00061' THEN 600
                    WHEN upper(p.name) LIKE 'LL.B%' OR upper(p.name) LIKE '%PHARMACY%' THEN 500
                    ELSE 400 END AS final_level
          FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
         WHERE s.id = p_student),
    cur AS (SELECT a.name FROM policy.academic_session a WHERE a.state = 'CURRENT'),
    g AS (SELECT gg.* FROM records.graduand gg WHERE gg.student_id = p_student ORDER BY gg.session DESC LIMIT 1),
    c AS (SELECT cc.* FROM credentials.certificate cc WHERE cc.student_id = p_student AND cc.status <> 'REISSUED' ORDER BY cc.printed_on DESC LIMIT 1),
    i AS (SELECT ii.* FROM credentials.issued ii WHERE ii.student_id = p_student AND ii.kind = 'DEGREE_CERTIFICATE' ORDER BY ii.issued_on DESC LIMIT 1),
    clr AS (SELECT count(*) FILTER (WHERE cp.state <> 'CLEARED')::int AS holding FROM clearance.position(p_student, 'CONVOCATION') cp)
    SELECT st.status = 'GRADUATED' OR g.student_id IS NOT NULL
               OR EXISTS (SELECT 1 FROM people.enrolment e, cur WHERE e.student_id = st.id AND e.session = cur.name AND e.level = st.final_level)
               OR st.current_level = st.final_level,
           st.final_level,
           coalesce(g.session, (SELECT name FROM cur)),
           g.student_id IS NOT NULL,
           g.cgpa, g.award, g.unmet, g.senate_state, g.senate_minute,
           CASE WHEN g.cgpa IS NULL THEN NULL ELSE coalesce(policy.class_of(g.cgpa), 'Pass') END,
           st.status,
           clr.holding = 0, clr.holding,
           c.number, c.status, c.convocation, c.printed_on, c.collected_on, c.held_reason,
           i.verification_code, i.issued_on
      FROM st LEFT JOIN g ON true LEFT JOIN c ON true LEFT JOIN i ON true, clr;
$$;

COMMENT ON FUNCTION records.student_graduation(uuid) IS
  'The student''s own graduation, computed: finalist or not, the audit, Senate, the class, the convocation clearance, the certificate, the verification code.';

GRANT EXECUTE ON FUNCTION records.approve_awards(text, text) TO app_acrecords;
GRANT EXECUTE ON FUNCTION records.student_graduation(uuid) TO app_student, app_acrecords, app_credentials;

COMMIT;
