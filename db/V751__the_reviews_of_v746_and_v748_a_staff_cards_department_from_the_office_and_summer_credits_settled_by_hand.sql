-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V751 · The reviews of V746 and V748 applied
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The review of V746 and V748 (three readers, each finding put to a refuter) confirmed nine; the four in the drawing went with V748.
--  The rest are answered here.
--    · A staff card's department. A member of staff the HR record places nowhere (a Head of Department or the Registrar created in
--      Users & roles, a lecturer imported without a department) printed their office's title — "Head of Department", "Registrar" —
--      as DEPARTMENT. credentials.staff_card_department now reads the office they hold: a department-scoped grant its department, a
--      unit-scoped one the unit's card name, a faculty-scoped one the faculty, a college-scoped one the college, and an office the
--      University holds centrally the unit it belongs to (ref.office.unit_code, seeded: the Registrar's offices the Registry, the
--      Bursar's the Bursary, the Director of ICT's ICT, the Chief Security Officer's the Security Unit, the Librarian's the Library).
--      Nothing resolving, the card prints a dash — never an office's title under DEPARTMENT.
--    · V746 refused to move or archive a payment whose Summer credit the Bursar had settled, wherever the payment stood: a payment
--      moved before V746 after its credit was refunded — the money counted twice, which V746's own notice counts — could then be
--      neither reversed nor archived. The refusal now holds only while the payment stands as that credit's Summer payment.
--    · A Bursar who recorded a whole-payment credit "Applied" before moving the payment (as the page then told them to) froze it for
--      good. A credit that is the whole of its payment is now applied by moving the payment on the payment correction desk (the move
--      records it, V742), never by hand (SUMMER_CREDIT_MOVE_IT); and a credit settled by hand may be reopened by the Bursar, with a
--      reason, while its payment stands as the Summer payment (registration.summer_credit_reopen).
--    · V746's one-off repair of authorisations naming a dead code resolved each code once — any merge alias, else the latest change —
--      without the date the authorisation was granted: a code renamed and the renamed course then merged stayed dead, and a code later
--      reused by another course was sent to that course. registration.summer_code_after(code, since) follows a code forward from the
--      grant, renames and merges in the order they happened (never a later course that took the old code). Authorisations still naming
--      a dead code are put right with it; those V746 rewrote to another course than it gives are counted for the Academic Office (not
--      changed: it decides).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V751: the reviews of V746 and V748 applied', true);

-- ── an office the University holds centrally belongs to a unit ───────────────────────────────────────────────────────────────────
ALTER TABLE ref.office ADD COLUMN unit_code text REFERENCES ref.unit (code) ON UPDATE CASCADE ON DELETE SET NULL;
COMMENT ON COLUMN ref.office.unit_code IS
    'V751: the unit an office belongs to (the Registrar''s office the Registry, the Bursar''s the Bursary): what a staff identity card prints as the department of someone the HR record places nowhere, through the unit''s card name.';
UPDATE ref.office o SET unit_code = m.unit
  FROM (VALUES ('registrar', 'REGISTRY'), ('dregistrar', 'REGISTRY'), ('bursar', 'BURSARY'), ('studentaccounts', 'BURSARY'),
               ('ict', 'ICT'), ('security', 'SECURITY'), ('library', 'LIBRARY')) AS m(office, unit)
 WHERE o.code = m.office AND o.unit_code IS NULL AND EXISTS (SELECT 1 FROM ref.unit u WHERE u.code = m.unit);

-- ── a staff card's department: the HR record, else the office held ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION credentials.staff_card_department(p_person uuid) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT coalesce(
        (SELECT coalesce(d.name, ref.unit_card_name(sr.home_unit), nullif(btrim(sr.unit_as_given), ''))
           FROM hrm.staff_record sr LEFT JOIN ref.department d ON d.code = sr.home_department
          WHERE sr.person_id = p_person),
        -- V751: the office the person holds today, read by its scope; a department first, then a unit, a faculty, a college, a central office
        (SELECT x.v FROM (
            SELECT CASE a.scope_kind
                       WHEN 'department' THEN (SELECT d.name FROM ref.department d WHERE d.code = a.scope_id)
                       WHEN 'unit' THEN ref.unit_card_name(a.scope_id)
                       WHEN 'faculty' THEN (SELECT CASE WHEN f.name ILIKE 'faculty%' THEN f.name ELSE 'Faculty of ' || f.name END FROM ref.faculty f WHERE f.code = a.scope_id)
                       WHEN 'college' THEN (SELECT c.name FROM ref.college c WHERE c.code = a.scope_id)
                   END AS scoped,
                   ref.unit_card_name(o.unit_code) AS central,
                   CASE a.scope_kind WHEN 'department' THEN 1 WHEN 'unit' THEN 2 WHEN 'faculty' THEN 3 WHEN 'college' THEN 4 ELSE 5 END AS rank,
                   a.valid_from
              FROM iam.office_assignment a JOIN ref.office o ON o.code = a.office_code
             WHERE a.person_id = p_person AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
        ) y CROSS JOIN LATERAL (SELECT coalesce(y.scoped, y.central) AS v) x
          WHERE x.v IS NOT NULL
          ORDER BY y.rank, y.valid_from DESC LIMIT 1));
$$;
COMMENT ON FUNCTION credentials.staff_card_department(uuid) IS
    'V748, V751: the department a staff identity card prints — the academic department the HR record names, else the unit''s card name, else the unit as the roll spelled it; else the office the person holds (its department, unit, faculty or college scope, or the unit a central office belongs to); NULL when nothing resolves (the card then prints a dash, never an office''s title).';

-- ── a settled Summer credit holds its payment only while the payment stands as that credit's Summer payment ─────────────────────
DO $$
DECLARE d text; fn text;
    old_line text := '    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id   -- V746: a Summer credit the Bursar settled is money spent';
    new_line text := '    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id   -- V746: a Summer credit the Bursar settled is money spent
                  AND r.purpose LIKE ''Summer semester fees%'' AND r.student_id = x.student_id AND r.session = x.session   -- V751: while it stands there';
BEGIN
    FOREACH fn IN ARRAY ARRAY['finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)', 'finance.payment_archive_refusals(uuid)'] LOOP
        d := pg_get_functiondef(fn::regprocedure);
        IF position(old_line IN d) = 0 THEN
            RAISE EXCEPTION 'V751: % is not as V746 left it', fn;
        END IF;
        EXECUTE replace(d, old_line, new_line);
    END LOOP;
END $$;

-- ── a Summer credit settled by the Bursar; reopened when settled by hand in error ───────────────────────────────────────────────
CREATE FUNCTION registration.summer_credit_settle(p_id uuid, p_state text, p_note text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); x registration.summer_credit; pr finance.payment_reference;
BEGIN
    IF coalesce(v_office, '') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_OFFICE: a Summer credit is settled by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF p_state NOT IN ('APPLIED', 'REFUNDED') OR length(btrim(coalesce(p_note, ''))) < 10 THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_NOTE: say applied or refunded, and how, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM registration.summer_credit WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_CREDIT_UNKNOWN: no such Summer credit' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO pr FROM finance.payment_reference WHERE id = x.reference_id;
    IF x.state <> 'OPEN' OR pr.archived_at IS NOT NULL OR pr.purpose NOT LIKE 'Summer semester fees%' OR pr.student_id <> x.student_id OR pr.session <> x.session THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_SETTLED: that credit is already settled, or its payment is archived or no longer a Summer payment' USING ERRCODE = '23514';
    END IF;
    -- V751: a credit that is the whole of its payment is applied by moving the payment (the move records it); by hand it froze the payment
    IF p_state = 'APPLIED' AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.paid_reference_id = pr.id AND c.state = 'PAID') THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_MOVE_IT: the whole of this payment is credit; apply it by moving the payment on the payment correction desk, which records the credit applied'
            USING ERRCODE = '23514';
    END IF;
    UPDATE registration.summer_credit SET state = p_state, settled_at = now(),
           settled_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, settled_note = btrim(p_note)
     WHERE id = x.id;
    RETURN p_state;
END $$;
COMMENT ON FUNCTION registration.summer_credit_settle(uuid, text, text) IS
    'V751: the Bursar records a Summer credit applied or refunded, with how. A credit that is the whole of its payment is applied by moving the payment on the payment correction desk instead (SUMMER_CREDIT_MOVE_IT).';

CREATE FUNCTION registration.summer_credit_reopen(p_id uuid, p_reason text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_office text := nullif(current_setting('moaum.actor_office', true), ''); x registration.summer_credit; pr finance.payment_reference;
BEGIN
    IF coalesce(v_office, '') NOT IN ('bursar', 'super') THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_OFFICE: a Summer credit is reopened by the Bursar' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_REASON: say why the credit is reopened, in ten characters or more' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO x FROM registration.summer_credit WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'SUMMER_CREDIT_UNKNOWN: no such Summer credit' USING ERRCODE = 'P0002'; END IF;
    SELECT * INTO pr FROM finance.payment_reference WHERE id = x.reference_id;
    IF x.state = 'OPEN' OR x.settled_note LIKE 'Moved by a payment correction: %' THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_NOT_REOPENED: only a credit the Bursar settled by hand is reopened (a move reopens its own when moved back)' USING ERRCODE = '23514';
    END IF;
    IF pr.archived_at IS NOT NULL OR pr.purpose NOT LIKE 'Summer semester fees%' OR pr.student_id <> x.student_id OR pr.session <> x.session THEN
        RAISE EXCEPTION 'SUMMER_CREDIT_NOT_REOPENED: its payment no longer stands as the Summer payment' USING ERRCODE = '23514';
    END IF;
    PERFORM set_config('moaum.reason', btrim(p_reason), true);
    UPDATE registration.summer_credit SET state = 'OPEN', settled_at = NULL, settled_by = NULL, settled_note = NULL WHERE id = x.id;
    RETURN 'OPEN';
END $$;
COMMENT ON FUNCTION registration.summer_credit_reopen(uuid, text) IS
    'V751: the Bursar reopens a Summer credit settled by hand in error (applied or refunded), with a reason on the audit trail, while its payment stands as the Summer payment; the payment may then be moved or archived.';

-- ── a course code followed forward from a date: renames and merges in the order they happened ──────────────────────────────────
CREATE FUNCTION registration.summer_code_after(p_code text, p_since timestamptz) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE v_code text := upper(btrim(coalesce(p_code, ''))); v_at timestamptz := coalesce(p_since, '-infinity'); v_next text; hop int := 0;
        ch record; al record;
BEGIN
    LOOP
        IF EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = v_code) AND hop > 0 THEN RETURN v_code; END IF;
        hop := hop + 1;
        EXIT WHEN hop > 12;
        -- the first rename of the code after v_at, and the first merge of it after v_at; whichever came first
        SELECT c.course_id, c.new_value, c.changed_at INTO ch FROM catalogue.course_change c
         WHERE c.field = 'CODE' AND upper(c.old_value) = v_code AND c.changed_at >= v_at ORDER BY c.changed_at LIMIT 1;
        SELECT a.course_code, a.merged_at INTO al FROM catalogue.course_alias a WHERE a.alias_code = v_code AND a.merged_at >= v_at;
        IF ch.course_id IS NULL AND al.course_code IS NULL THEN
            RETURN CASE WHEN EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = v_code) THEN v_code END;
        END IF;
        IF ch.course_id IS NOT NULL AND (al.course_code IS NULL OR ch.changed_at <= al.merged_at) THEN
            -- renamed: the course renamed is followed by its new code from the rename on (it may have been renamed or merged again)
            v_next := upper(ch.new_value); v_at := ch.changed_at;
        ELSE
            v_next := upper(al.course_code); v_at := al.merged_at;
        END IF;
        v_code := v_next;
    END LOOP;
    RETURN NULL;
END $$;
COMMENT ON FUNCTION registration.summer_code_after(text, timestamptz) IS
    'V751: the code a course named by p_code at p_since bears now — its renames and merges followed in the order they happened (never a later course that took the old code); NULL when nothing names a course now.';

-- ── what is put right, and what is told ──────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record; v_new text; n_auth int := 0; n_dead int; n_v746 int; n_moved_trapped int; n_central int;
BEGIN
    -- authorisations still naming a dead code: followed from the date each was granted
    FOR r IN SELECT sa.session, sa.student_id, upper(btrim(x)) AS code, sa.granted_at
               FROM registration.summer_authorisation sa CROSS JOIN LATERAL unnest(sa.courses) x
              WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x))) LOOP
        v_new := registration.summer_code_after(r.code, r.granted_at);
        IF v_new IS NOT NULL AND v_new <> r.code THEN
            UPDATE registration.summer_authorisation sa
               SET courses = ARRAY(SELECT DISTINCT CASE WHEN upper(btrim(y)) = r.code THEN v_new ELSE upper(btrim(y)) END FROM unnest(sa.courses) y ORDER BY 1)
             WHERE sa.session = r.session AND sa.student_id = r.student_id;
            n_auth := n_auth + 1;
        END IF;
    END LOOP;
    SELECT count(*) INTO n_dead FROM registration.summer_authorisation sa CROSS JOIN LATERAL unnest(sa.courses) x
     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)));
    -- authorisations V746's repair rewrote to a code other than the one followed from the grant (for the Academic Office; not changed)
    SELECT count(*) INTO n_v746
      FROM audit.entries e
      CROSS JOIN LATERAL (SELECT upper(btrim(b)) AS old_code FROM jsonb_array_elements_text(e.before_state -> 'courses') b
                           WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a WHERE upper(btrim(a)) = upper(btrim(b)))) o
     WHERE e.subject_type = 'registration.summer_authorisation' AND e.reason LIKE 'V746:%'
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(e.after_state -> 'courses') a
                        WHERE upper(btrim(a)) = registration.summer_code_after(o.old_code, (e.before_state ->> 'granted_at')::timestamptz));
    -- whole-payment credits recorded applied by hand while the payment still stands on the Summer (the Bursar may reopen them)
    SELECT count(*) INTO n_moved_trapped FROM registration.summer_credit x JOIN finance.payment_reference pr ON pr.id = x.reference_id
     WHERE x.state = 'APPLIED' AND x.settled_note NOT LIKE 'Moved by a payment correction: %'
       AND pr.archived_at IS NULL AND pr.purpose LIKE 'Summer semester fees%'
       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.paid_reference_id = pr.id AND c.state = 'PAID');
    SELECT count(*) INTO n_central FROM ref.office WHERE unit_code IS NOT NULL;
    RAISE NOTICE 'V751: % Summer authorisations put right from the date they were granted (% codes still name no course); % codes V746 rewrote otherwise than the trail from the grant gives (for the Academic Office, not changed); % whole-payment Summer credits recorded applied by hand while the payment stands (the Bursar may reopen them); % offices carry the unit they belong to',
        n_auth, n_dead, n_v746, n_moved_trapped, n_central;
END $$;

COMMIT;
