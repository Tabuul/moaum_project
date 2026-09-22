-- ═══════════════════════════════════════════════════════════════════════════
-- V215 — the postgraduate research / thesis migration from the old portal
--
--   A postgraduate brought over from the old portal may already carry a research
--   record: a topic, supervisors, a viva result, an award. This imports that into
--   the research lifecycle (V209: admissions.pg_research), so a migrated candidate
--   sits on the research desk and the register exactly like one carried through
--   here — rather than starting again at REGISTERED.
--
--     • the student is matched by matriculation number and must be a POSTGRADUATE
--       on the register (loaded first by people.import_postgraduate, V203);
--     • a research record is ensured (its degree kind derived from the programme),
--       then the topic, milestone dates, viva result and award are set from the row;
--     • the stage is taken as stated, else inferred from the furthest milestone the
--       row carries (an award date ⇒ AWARDED, a clearance ⇒ CLEARED, and so on);
--     • supervisors named on the row replace the record's current supervisors, so a
--       re-upload updates rather than duplicates;
--     • a milestone-log line records that the record was migrated.
--
--   Every write is to audit-attached tables (V209), so it is attributed to the
--   officer running the migration, like the rest of the import desk.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- a legacy date/timestamp cell → timestamptz, or NULL when it cannot be read
CREATE OR REPLACE FUNCTION admissions.pg_legacy_ts(p text)
RETURNS timestamptz
LANGUAGE plpgsql STABLE AS $$
DECLARE v timestamptz;
BEGIN
    IF p IS NULL OR btrim(p) = '' THEN RETURN NULL; END IF;
    BEGIN v := btrim(p)::timestamptz; RETURN v;
    EXCEPTION WHEN OTHERS THEN
        BEGIN v := btrim(p)::date; RETURN v;
        EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
    END;
END $$;

CREATE OR REPLACE FUNCTION admissions.import_legacy_pg_research(p_rows jsonb)
RETURNS TABLE (rows int, matched int, created int, updated int, supervisors int,
               no_student int, skipped int, first_error text)
LANGUAGE plpgsql AS $$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_student uuid; v_pg boolean; v_res uuid; v_existed boolean;
        v_topic text; v_stage text; v_file_stage text;
        v_score numeric; v_grade text; v_outcome text; v_plag numeric;
        t_prop timestamptz; t_sem timestamptz; t_title timestamptz; t_panel timestamptz;
        t_draft timestamptz; t_viva timestamptz; t_final timestamptz; t_cleared timestamptz; t_award timestamptz;
        v_sup1 text; v_sup2 text; v_co text; v_have_sup boolean;
        n int := 0; n_match int := 0; n_new int := 0; n_upd int := 0; n_sup int := 0;
        nns int := 0; ns int := 0; v_firsterr text := NULL;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a migration is loaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the file is rows: matriculation number, topic, supervisor and the award' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', r->>'reg_no', '')));
        IF v_matric = '' THEN CONTINUE; END IF;
        n := n + 1;

        BEGIN
            SELECT s.id, (s.entry_mode = 'POSTGRADUATE') INTO v_student, v_pg
              FROM people.student s WHERE upper(s.matric_no) = v_matric;
            IF v_student IS NULL OR NOT coalesce(v_pg, false) THEN nns := nns + 1; CONTINUE; END IF;

            v_existed := EXISTS (SELECT 1 FROM admissions.pg_research WHERE student_id = v_student);
            v_res := admissions.pg_research_ensure(v_student);

            v_topic := nullif(btrim(coalesce(r->>'topic', r->>'title', r->>'researchTitle', r->>'research_title',
                                             r->>'thesisTitle', r->>'thesis_title', r->>'projectTitle',
                                             r->>'dissertationTitle', '')), '');

            t_prop   := admissions.pg_legacy_ts(coalesce(r->>'proposalApproved', r->>'proposal_approved', r->>'proposalDate'));
            t_sem    := admissions.pg_legacy_ts(coalesce(r->>'seminarHeld', r->>'seminar_held', r->>'seminarDate'));
            t_title  := admissions.pg_legacy_ts(coalesce(r->>'titleRegistered', r->>'title_registered'));
            t_panel  := admissions.pg_legacy_ts(coalesce(r->>'panelConstituted', r->>'panel_constituted'));
            t_draft  := admissions.pg_legacy_ts(coalesce(r->>'draftSubmitted', r->>'draft_submitted'));
            t_viva   := admissions.pg_legacy_ts(coalesce(r->>'vivaHeld', r->>'viva_held', r->>'vivaDate', r->>'defenceDate'));
            t_final  := admissions.pg_legacy_ts(coalesce(r->>'finalSubmitted', r->>'final_submitted'));
            t_cleared:= admissions.pg_legacy_ts(coalesce(r->>'cleared', r->>'clearedAt', r->>'cleared_at'));
            t_award  := admissions.pg_legacy_ts(coalesce(r->>'awardDate', r->>'awarded', r->>'awardedAt', r->>'awarded_at', r->>'award_date'));

            v_score := nullif(regexp_replace(coalesce(r->>'vivaScore', r->>'viva_score', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_score IS NOT NULL AND (v_score < 0 OR v_score > 100) THEN v_score := NULL; END IF;
            v_grade := upper(btrim(coalesce(r->>'vivaGrade', r->>'viva_grade', '')));
            IF v_grade NOT IN ('A','B','C','F') THEN v_grade := NULL; END IF;
            v_outcome := upper(replace(btrim(coalesce(r->>'vivaOutcome', r->>'viva_outcome', r->>'outcome', '')), ' ', '_'));
            IF v_outcome NOT IN ('PASS_CLEAN','PASS_MINOR','PASS_MAJOR','SECOND_ORAL','FAIL') THEN v_outcome := NULL; END IF;
            v_plag := nullif(regexp_replace(coalesce(r->>'plagiarism', r->>'plagiarismPct', r->>'plagiarism_pct', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_plag IS NOT NULL AND (v_plag < 0 OR v_plag > 100) THEN v_plag := NULL; END IF;

            -- the stage: as stated when valid, else the furthest milestone the row carries
            v_file_stage := upper(replace(btrim(coalesce(r->>'stage', '')), ' ', '_'));
            IF v_file_stage NOT IN ('REGISTERED','SUPERVISED','PROPOSAL_SUBMITTED','PROPOSAL_APPROVED','SEMINAR_HELD',
                'TITLE_REGISTERED','PANEL_CONSTITUTED','DRAFT_SUBMITTED','VIVA_HELD','CORRECTIONS',
                'FINAL_SUBMITTED','CLEARED','AWARD_RECOMMENDED','AWARDED','WITHDRAWN') THEN
                v_file_stage := NULL;
            END IF;
            v_stage := coalesce(
                CASE WHEN t_award   IS NOT NULL THEN 'AWARDED' END,
                v_file_stage,
                CASE WHEN t_cleared IS NOT NULL THEN 'CLEARED' END,
                CASE WHEN t_final   IS NOT NULL THEN 'FINAL_SUBMITTED' END,
                CASE WHEN t_viva    IS NOT NULL OR v_outcome IS NOT NULL THEN 'VIVA_HELD' END,
                CASE WHEN t_panel   IS NOT NULL THEN 'PANEL_CONSTITUTED' END,
                CASE WHEN t_title   IS NOT NULL THEN 'TITLE_REGISTERED' END,
                CASE WHEN t_sem     IS NOT NULL THEN 'SEMINAR_HELD' END,
                CASE WHEN t_prop    IS NOT NULL THEN 'PROPOSAL_APPROVED' END);

            UPDATE admissions.pg_research SET
                topic                = coalesce(v_topic, topic),
                stage                = coalesce(v_stage, stage),
                proposal_approved_at = coalesce(t_prop, proposal_approved_at),
                seminar_held_at      = coalesce(t_sem, seminar_held_at),
                title_registered_at  = coalesce(t_title, title_registered_at),
                panel_constituted_at = coalesce(t_panel, panel_constituted_at),
                draft_submitted_at   = coalesce(t_draft, draft_submitted_at),
                viva_held_at         = coalesce(t_viva, viva_held_at),
                viva_score           = coalesce(v_score, viva_score),
                viva_grade           = coalesce(v_grade, viva_grade),
                viva_outcome         = coalesce(v_outcome, viva_outcome),
                plagiarism_pct       = coalesce(v_plag, plagiarism_pct),
                final_submitted_at   = coalesce(t_final, final_submitted_at),
                cleared_at           = coalesce(t_cleared, cleared_at),
                awarded_at           = coalesce(t_award, awarded_at),
                pgsr                 = coalesce(nullif(btrim(coalesce(r->>'pgsr', '')), ''), pgsr),
                updated_at           = now()
              WHERE id = v_res;

            -- supervisors: when the row names any, they replace the record's current ones
            v_sup1 := nullif(btrim(coalesce(r->>'supervisor', r->>'supervisor1', r->>'mainSupervisor', r->>'first_supervisor', r->>'firstSupervisor', '')), '');
            v_sup2 := nullif(btrim(coalesce(r->>'supervisor2', r->>'secondSupervisor', r->>'second_supervisor', '')), '');
            v_co   := nullif(btrim(coalesce(r->>'coSupervisor', r->>'co_supervisor', '')), '');
            v_have_sup := (v_sup1 IS NOT NULL OR v_sup2 IS NOT NULL OR v_co IS NOT NULL);
            IF v_have_sup THEN
                DELETE FROM admissions.pg_research_supervisor WHERE research_id = v_res AND ended_at IS NULL;
                IF v_sup1 IS NOT NULL THEN
                    INSERT INTO admissions.pg_research_supervisor (research_id, name, role, is_external)
                    VALUES (v_res, v_sup1, 'FIRST', false); n_sup := n_sup + 1;
                END IF;
                IF v_sup2 IS NOT NULL THEN
                    INSERT INTO admissions.pg_research_supervisor (research_id, name, role, is_external)
                    VALUES (v_res, v_sup2, 'SECOND', false); n_sup := n_sup + 1;
                END IF;
                IF v_co IS NOT NULL THEN
                    INSERT INTO admissions.pg_research_supervisor (research_id, name, role, is_external)
                    VALUES (v_res, v_co, 'CO', false); n_sup := n_sup + 1;
                END IF;
            END IF;

            INSERT INTO admissions.pg_research_event (research_id, stage, note, by_person)
            VALUES (v_res, coalesce(v_stage, 'REGISTERED'), 'Migrated from the legacy portal', v_actor);

            n_match := n_match + 1;
            IF v_existed THEN n_upd := n_upd + 1; ELSE n_new := n_new + 1; END IF;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_firsterr IS NULL THEN v_firsterr := left(v_matric || ': ' || SQLSTATE || ' ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, n_match, n_new, n_upd, n_sup, nns, ns, v_firsterr;
END $$;

COMMIT;
