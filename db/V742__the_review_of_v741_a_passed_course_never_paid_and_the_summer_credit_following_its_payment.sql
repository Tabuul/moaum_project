-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V742 · The review of V741 applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  A review of V741 (three readers, each finding put to a refuter) confirmed four; the database's are answered here.
--    · A Summer reference drawn before a pass was published stayed payable for its day, so the take-back never ran and the student
--      paid for, and was registered in, a course the portal reads as passed (V739 finding #7, closed only in part). A reference holding
--      a course no longer outstanding is no longer payable (the student's Pay then takes the course back), and a payment confirmed
--      anyway pays no such course: it is taken back first, the programme fee with it when no course stands, and the money stands as
--      a Summer credit.
--    · V741 refused to move or archive a payment while an open Summer credit named it, so the Bursar had to record the credit applied or
--      refunded before the correction was decided; a correction then rejected, or an archive restored, left a settled credit that had
--      moved nothing. The refusals go; the credit follows its payment instead: a payment moved off the Summer (another purpose, session
--      or student) settles its open credit as applied, with the move as its note, and a move back reopens it; a payment archived keeps
--      its credit open and out of sight until it is restored.
--    · Payment reallocations recorded at a level the first-year count (V738) now reads otherwise are counted for the Bursary, beside the
--      assessments V741 counted (V725 told the Bursary both for its own count).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V742: the review of V741 applied', true);

-- ── a course still outstanding for the student's Summer: in the pool and not passed (an ENDED course stays outstanding: once paid it is
--    the desk's issue, V739) ──
CREATE FUNCTION registration.summer_course_outstanding(p_student uuid, p_session text, p_course text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM registration.summer_courses(p_student, p_session) sc
                    WHERE sc.course_code = p_course AND coalesce(sc.reason, '') <> 'PASSED');
$$;
COMMENT ON FUNCTION registration.summer_course_outstanding(uuid, text, text) IS
    'V742: true while a course is in the student''s Summer pool and not passed. A reference holding a course no longer outstanding is not payable, and a payment confirmed anyway takes the course back rather than pay it.';

-- ── a reference is paid only while every course it holds is still outstanding ──
CREATE OR REPLACE FUNCTION registration.summer_reference_payable(p_reference text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT coalesce((
        SELECT r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.student_id IS NOT NULL
               AND registration.summer_open(r.session)
               AND EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id)
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id AND c.state <> 'DUE')
               AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c
                                WHERE c.student_id = r.student_id AND c.session = r.session AND c.state = 'DUE'
                                  AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc WHERE rc.reference_id = r.id AND rc.charge_id = c.id))
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                 JOIN catalogue.course k ON k.code = c.course_code
                                WHERE rc.reference_id = r.id AND k.state = 'ENDED')   -- V739
               AND NOT EXISTS (SELECT 1 FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id AND c.kind = 'COURSE'
                                  AND NOT registration.summer_course_outstanding(c.student_id, c.session, c.course_code))   -- V742: passed since
               AND r.amount = (SELECT sum(c.amount) FROM registration.summer_reference_charge rc JOIN registration.summer_charge c ON c.id = rc.charge_id
                                WHERE rc.reference_id = r.id)
          FROM finance.payment_reference r
         WHERE r.reference = upper(btrim(coalesce(p_reference, ''))) AND r.purpose LIKE 'Summer semester fees%'), false);
$$;

-- ── a payment confirmed: what is no longer outstanding is taken back before anything is paid ──
CREATE OR REPLACE FUNCTION registration.summer_reference_confirmed() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_applied numeric := 0; c registration.summer_charge; v_err text; v_prog uuid; v_prog_amount numeric;
BEGIN
    IF NEW.student_id IS NULL THEN RETURN NULL; END IF;
    -- V742: a course passed since it was chosen (or no longer in the pool) is taken back, not paid; the programme fee goes with it when
    -- no course stands beside it; their money stands as credit below
    UPDATE registration.summer_charge t SET state = 'CANCELLED', cancelled_at = now()
     WHERE t.student_id = NEW.student_id AND t.session = NEW.session AND t.kind = 'COURSE' AND t.state = 'DUE'
       AND NOT registration.summer_course_outstanding(t.student_id, t.session, t.course_code);
    UPDATE registration.summer_charge t SET state = 'CANCELLED', cancelled_at = now()
     WHERE t.student_id = NEW.student_id AND t.session = NEW.session AND t.kind = 'PROGRAMME' AND t.state = 'DUE'
       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = NEW.student_id AND y.session = NEW.session
                         AND y.kind = 'COURSE' AND y.state IN ('DUE', 'PAID'));
    -- 1. the charges it was drawn for, still owed
    WITH u AS (UPDATE registration.summer_charge ch SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id
                 FROM registration.summer_reference_charge rc
                WHERE rc.reference_id = NEW.id AND rc.charge_id = ch.id AND ch.state = 'DUE'
               RETURNING ch.amount)
    SELECT coalesce(sum(u.amount), 0) INTO v_applied FROM u;
    -- 2. those it was drawn for and taken back since, where nothing stands in their place and the course is still outstanding
    FOR c IN SELECT ch.* FROM registration.summer_reference_charge rc JOIN registration.summer_charge ch ON ch.id = rc.charge_id
              WHERE rc.reference_id = NEW.id AND ch.state = 'CANCELLED' ORDER BY (ch.kind = 'PROGRAMME') DESC, ch.created_at
    LOOP
        CONTINUE WHEN NEW.amount - v_applied < c.amount;
        CONTINUE WHEN EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.student_id = c.student_id AND x.session = c.session AND x.kind = c.kind
                                 AND x.course_code IS NOT DISTINCT FROM c.course_code AND x.state <> 'CANCELLED');
        -- V741: a course passed since (an authorised one too) is never revived
        CONTINUE WHEN c.kind = 'COURSE' AND NOT registration.summer_course_outstanding(c.student_id, c.session, c.course_code);
        CONTINUE WHEN c.kind = 'COURSE' AND NOT EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = c.student_id AND y.session = c.session
                                                           AND y.kind = 'PROGRAMME' AND y.state = 'PAID');
        UPDATE registration.summer_charge SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id, cancelled_at = NULL WHERE id = c.id;
        IF c.kind = 'PROGRAMME' THEN v_prog := c.id; v_prog_amount := c.amount; END IF;
        v_applied := v_applied + c.amount;
    END LOOP;
    -- 3. the student's other charges still owed, the programme fee first and never a course before it (all still outstanding: taken
    --    back above otherwise)
    FOR c IN SELECT x.* FROM registration.summer_charge x WHERE x.student_id = NEW.student_id AND x.session = NEW.session AND x.state = 'DUE'
              ORDER BY (x.kind = 'PROGRAMME') DESC, x.created_at
    LOOP
        EXIT WHEN c.kind = 'COURSE' AND EXISTS (SELECT 1 FROM registration.summer_charge y WHERE y.student_id = NEW.student_id AND y.session = NEW.session
                                                   AND y.kind = 'PROGRAMME' AND y.state = 'DUE');
        CONTINUE WHEN NEW.amount - v_applied < c.amount;
        UPDATE registration.summer_charge SET state = 'PAID', paid_at = NEW.confirmed_at, paid_reference_id = NEW.id WHERE id = c.id;
        v_applied := v_applied + c.amount;
    END LOOP;
    -- V741: the programme fee revived with no course of the Summer standing beside it goes back: its money stands as credit
    IF v_prog IS NOT NULL AND NOT EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.student_id = NEW.student_id AND x.session = NEW.session
                                             AND x.kind = 'COURSE' AND x.state IN ('DUE', 'PAID')) THEN
        UPDATE registration.summer_charge SET state = 'CANCELLED', cancelled_at = now(), paid_at = NULL, paid_reference_id = NULL WHERE id = v_prog;
        v_applied := v_applied - v_prog_amount;
    END IF;
    IF NEW.amount - v_applied >= 1 THEN
        INSERT INTO registration.summer_credit (student_id, session, reference_id, amount) VALUES (NEW.student_id, NEW.session, NEW.id, NEW.amount - v_applied);
    END IF;
    PERFORM registration.summer_close_stale_references(NEW.student_id, NEW.session);
    BEGIN
        PERFORM registration.summer_materialize(NEW.student_id, NEW.session);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
        INSERT INTO registration.summer_issue (student_id, session, reference_id, error) VALUES (NEW.student_id, NEW.session, NEW.id, v_err);
    END;
    RETURN NULL;
END $$;

-- ── the Summer credit follows its payment: V741's refusals go ──
DO $$
DECLARE d text; fn text;
BEGIN
    FOREACH fn IN ARRAY ARRAY['finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)', 'finance.payment_archive_refusals(uuid)'] LOOP
        d := pg_get_functiondef(fn::regprocedure);
        IF position('    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id AND x.state = ''OPEN'') THEN   -- V741' IN d) = 0 THEN
            RAISE EXCEPTION 'V742: % is not as V741 left it', fn;
        END IF;
        d := regexp_replace(d, '    IF EXISTS \(SELECT 1 FROM registration\.summer_credit x WHERE x\.reference_id = r\.id AND x\.state = ''OPEN''\) THEN   -- V741\n'
                               '        refusals := refusals \|\| ''(REALLOC|PAR)_LINKED: an unapplied Summer credit names this payment; the Bursar settles it on Summer Semester Fees first''::text;\n'
                               '    END IF;\n', '');
        IF position('registration.summer_credit' IN d) > 0 THEN
            RAISE EXCEPTION 'V742: the V741 refusal in % was not taken out', fn;
        END IF;
        EXECUTE d;
    END LOOP;
END $$;

CREATE FUNCTION registration.summer_credit_follows_payment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- moved off the Summer (by a payment correction, a swap to its true owner, a change of session): the open credit is settled as applied
    UPDATE registration.summer_credit x
       SET state = 'APPLIED', settled_at = now(), settled_by = nullif(current_setting('moaum.actor_id', true), '')::uuid,
           settled_note = 'Moved by a payment correction: the payment now counts as ' || NEW.purpose || ' (' || coalesce(NEW.session, '-') || ')'
     WHERE x.reference_id = NEW.id AND x.state = 'OPEN'
       AND (NEW.purpose NOT LIKE 'Summer semester fees%' OR NEW.student_id IS DISTINCT FROM x.student_id OR NEW.session IS DISTINCT FROM x.session);
    -- moved back: the credit that move settled is open again
    UPDATE registration.summer_credit x
       SET state = 'OPEN', settled_at = NULL, settled_by = NULL, settled_note = NULL
     WHERE x.reference_id = NEW.id AND x.state = 'APPLIED' AND x.settled_note LIKE 'Moved by a payment correction: %'
       AND NEW.purpose LIKE 'Summer semester fees%' AND NEW.student_id = x.student_id AND NEW.session = x.session;
    RETURN NULL;
END $$;
CREATE TRIGGER trg_summer_credit_follows_payment AFTER UPDATE OF purpose, session, student_id ON finance.payment_reference
    FOR EACH ROW WHEN (OLD.purpose IS DISTINCT FROM NEW.purpose OR OLD.session IS DISTINCT FROM NEW.session OR OLD.student_id IS DISTINCT FROM NEW.student_id)
    EXECUTE FUNCTION registration.summer_credit_follows_payment();
COMMENT ON FUNCTION registration.summer_credit_follows_payment() IS
    'V742: a Summer credit follows its payment. Moved off the Summer (another purpose, session or student) it is settled as applied, the move its note; moved back it is open again. An archived payment keeps its credit open and out of sight (summer_account and the Bursary''s list read only payments that stand) until it is restored.';

-- ── what the Bursary is told ──────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_ids uuid[]; n_moves int; n_open int;
BEGIN
    SELECT array_agg(st.id) INTO v_ids FROM people.student st
     WHERE st.entry_mode NOT IN ('CCE', 'POSTGRADUATE')
       AND EXISTS (SELECT 1 FROM policy.cohort_start cs WHERE cs.admission_session = policy.session_normal(st.entry_session));
    -- payment reallocations recorded at a level the first-year count now reads otherwise (listed for the Bursary, not changed)
    SELECT count(*) INTO n_moves FROM finance.payment_reallocation r
     WHERE r.student_id = ANY (coalesce(v_ids, '{}')) AND r.to_level IS DISTINCT FROM people.level_in(r.student_id, r.to_session);
    -- open Summer credits whose payment was moved off the Summer before this: settled as the trigger now settles them
    UPDATE registration.summer_credit x
       SET state = 'APPLIED', settled_at = now(), settled_by = '00000000-0000-0000-0000-000000000000'::uuid,
           settled_note = 'Moved by a payment correction: the payment now counts as ' || pr.purpose || ' (' || coalesce(pr.session, '-') || ')'
      FROM finance.payment_reference pr
     WHERE pr.id = x.reference_id AND x.state = 'OPEN'
       AND (pr.purpose NOT LIKE 'Summer semester fees%' OR pr.student_id IS DISTINCT FROM x.student_id OR pr.session IS DISTINCT FROM x.session);
    GET DIAGNOSTICS n_open = ROW_COUNT;
    RAISE NOTICE 'V742: % payment reallocations of first-year-count students name a level other than the session''s count now (listed for the Bursary, not changed); % open Summer credits whose payment had already been moved settled as applied',
        n_moves, n_open;
END $$;

COMMIT;
