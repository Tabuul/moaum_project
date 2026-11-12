-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V746 · The review findings left open by V742 and V743
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  Two defects the reviews of V742 and V743 found and set aside as older than those migrations, put right here.
--    · A Summer authorisation names its courses as text (registration.summer_authorisation.courses), and neither a code correction
--      (catalogue.correct_course, rename_course: the course's code changed) nor a merge (catalogue.merge_course: the course gone, its code
--      an alias) rewrote it. The student's pool then held the dead code (COURSE_UNKNOWN), the charge — which follows the code by its key —
--      read as no longer outstanding, and a payment confirmed for it was taken back into credit with nothing registered, the course not
--      selectable again. An authorisation now follows its course: a code changed or merged away is replaced in every authorisation
--      naming it, and those already naming a dead code are put right from the merge aliases and the code-change trail.
--    · A Summer credit the Bursar records as refunded, or as applied elsewhere, is money spent; the payment it names could still be moved
--      to another purpose or archived, counting the same money twice. Such a payment is now neither moved nor archived (REALLOC_LINKED,
--      PAR_LINKED), as a payment that paid registered Summer courses is not (V739). A credit still open is not affected: it follows its
--      payment (V742).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V746: a Summer authorisation follows its course; a settled Summer credit holds its payment', true);

-- ── an authorisation follows its course ──────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION registration.summer_authorisation_follow(p_old text, p_new text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
    UPDATE registration.summer_authorisation sa
       SET courses = ARRAY(SELECT DISTINCT CASE WHEN upper(btrim(x)) = upper(btrim(p_old)) THEN p_new ELSE upper(btrim(x)) END
                             FROM unnest(sa.courses) x ORDER BY 1)
     WHERE EXISTS (SELECT 1 FROM unnest(sa.courses) x WHERE upper(btrim(x)) = upper(btrim(p_old)));
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $$;
COMMENT ON FUNCTION registration.summer_authorisation_follow(text, text) IS
    'V746: every Summer authorisation naming a course code names its new code instead (a correction or a merge).';

CREATE FUNCTION registration.summer_authorisation_code_changed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM registration.summer_authorisation_follow(OLD.code, NEW.code);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_summer_authorisation_code_changed AFTER UPDATE OF code ON catalogue.course
    FOR EACH ROW WHEN (OLD.code IS DISTINCT FROM NEW.code) EXECUTE FUNCTION registration.summer_authorisation_code_changed();

CREATE FUNCTION registration.summer_authorisation_course_merged() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM registration.summer_authorisation_follow(NEW.alias_code, NEW.course_code);
    RETURN NULL;
END $$;
CREATE TRIGGER trg_summer_authorisation_course_merged AFTER INSERT ON catalogue.course_alias
    FOR EACH ROW EXECUTE FUNCTION registration.summer_authorisation_course_merged();

-- ── a settled Summer credit holds its payment ────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE d text; fn text; code text; anchor text :=
    '    IF EXISTS (SELECT 1 FROM registration.summer_charge x WHERE x.paid_reference_id = r.id AND x.state = ''PAID'') THEN   -- V739';
BEGIN
    FOREACH fn IN ARRAY ARRAY['finance.payment_reallocation_check(uuid,text,text,integer,uuid,text)', 'finance.payment_archive_refusals(uuid)'] LOOP
        d := pg_get_functiondef(fn::regprocedure);
        IF position(anchor IN d) = 0 THEN
            RAISE EXCEPTION 'V746: % is not as V742 left it', fn;
        END IF;
        code := CASE WHEN fn LIKE 'finance.payment_reallocation_check%' THEN 'REALLOC_LINKED' ELSE 'PAR_LINKED' END;
        d := replace(d, anchor,
            '    IF EXISTS (SELECT 1 FROM registration.summer_credit x WHERE x.reference_id = r.id   -- V746: a Summer credit the Bursar settled is money spent
                  AND (x.state = ''REFUNDED'' OR (x.state = ''APPLIED'' AND x.settled_note NOT LIKE ''Moved by a payment correction: %''))) THEN
        refusals := refusals || ''' || code || ': the Bursar recorded a Summer credit of this payment as refunded or applied; that money is spent''::text;
    END IF;
' || anchor);
        EXECUTE d;
    END LOOP;
END $$;

-- ── what is put right, and what is told ──────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record; v_new text; n_auth int := 0; n_dead int; n_spent int;
BEGIN
    -- authorisations already naming a code merged away or corrected: the merge's alias, else the latest code change of that code
    FOR r IN SELECT DISTINCT upper(btrim(x)) AS code FROM registration.summer_authorisation sa CROSS JOIN LATERAL unnest(sa.courses) x
              WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x))) LOOP
        v_new := coalesce((SELECT a.course_code FROM catalogue.course_alias a WHERE a.alias_code = r.code),
                          (SELECT k.code FROM catalogue.course_change ch JOIN catalogue.course k ON k.id = ch.course_id
                            WHERE ch.field = 'CODE' AND upper(ch.old_value) = r.code ORDER BY ch.changed_at DESC LIMIT 1));
        IF v_new IS NOT NULL AND v_new <> r.code THEN
            n_auth := n_auth + registration.summer_authorisation_follow(r.code, v_new);
        END IF;
    END LOOP;
    SELECT count(*) INTO n_dead FROM registration.summer_authorisation sa CROSS JOIN LATERAL unnest(sa.courses) x
     WHERE NOT EXISTS (SELECT 1 FROM catalogue.course k WHERE k.code = upper(btrim(x)));
    -- payments already moved or archived after the Bursar settled their Summer credit (the money counted twice: for the Bursary)
    SELECT count(DISTINCT pr.id) INTO n_spent FROM registration.summer_credit x JOIN finance.payment_reference pr ON pr.id = x.reference_id
     WHERE (x.state = 'REFUNDED' OR (x.state = 'APPLIED' AND x.settled_note NOT LIKE 'Moved by a payment correction: %'))
       AND (pr.archived_at IS NOT NULL OR pr.purpose NOT LIKE 'Summer semester fees%');
    RAISE NOTICE 'V746: % Summer authorisations put right to the course''s present code (% codes still name no course); % payments whose settled Summer credit was moved or archived since (counted for the Bursary, not changed)',
        n_auth, n_dead, n_spent;
END $$;

COMMIT;
