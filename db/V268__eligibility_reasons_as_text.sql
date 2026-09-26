-- ═══════════════════════════════════════════════════════════════════════════
-- V268 — the eligibility evaluator's reasons, appended as text
--
--   V266 appended a bare string literal to the text[] of reasons in seven
--   places ("v_reasons := v_reasons || 'No admission rule is stated …'").
--   Postgres reads an untyped literal beside an array as an ARRAY literal, so
--   the first applicant whose programme has no rule this session (or no
--   O'Level result, no UTME subjects, no score, no DE award, no place, an
--   archived programme) stopped the whole evaluation with "malformed array
--   literal". The function is redefined with every such literal cast to text.
--   Nothing else changes.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V268: eligibility reasons appended as text', true);

CREATE OR REPLACE FUNCTION admissions.evaluate_programme(p_session text, p_jamb_key text, p_programme text, p_entry_mode text)
RETURNS TABLE (result text, checks jsonb, reasons text[])
LANGUAGE plpgsql STABLE AS $$
DECLARE pol admissions.session_policy; pr admissions.programme_rule; g ref.programme; v_checks jsonb := '[]'::jsonb; v_best jsonb; v_best_met int := -1; v_met int;
        v_key text := upper(btrim(p_jamb_key)); sit uuid[]; combo uuid[]; i int; j int; n int; allowed int; c jsonb; v_quota int; v_taken int; v_closed text;
        cand text[]; grp record; it record; v_have int; v_agg int; v_req int; v_fac int; v_load int; v_prog_cut int; v_status text; ok boolean; v_res text;
        v_unverified boolean := false; v_failed boolean := false; v_reasons text[] := ARRAY[]::text[]; v_add text;
BEGIN
    SELECT * INTO g FROM ref.programme WHERE code = p_programme;
    IF g.code IS NULL THEN
        RETURN QUERY SELECT 'NOT_ELIGIBLE'::text, jsonb_build_array(jsonb_build_object('kind','PROGRAMME','label','Programme','requirement','A programme the University runs','candidate',p_programme,'status','NOT_MET','mandatory',true)), ARRAY['No such programme']::text[]; RETURN;
    END IF;
    SELECT * INTO pol FROM admissions.session_policy p WHERE p.session = p_session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1;
    IF pol.id IS NULL THEN
        RETURN QUERY SELECT 'UNVERIFIED'::text, jsonb_build_array(jsonb_build_object('kind','POLICY','label','Admission settings','requirement','Settings for ' || p_session,'candidate','None exist','status','UNVERIFIED','mandatory',true)), ARRAY['No admission settings exist for ' || p_session]::text[]; RETURN;
    END IF;
    IF pol.state <> 'IN_FORCE' THEN
        v_checks := v_checks || jsonb_build_object('kind','POLICY','label','Admission settings','requirement','In force for ' || p_session,'candidate','Draft settings (provisional reading)','status','INFO','mandatory',false);
    END IF;
    -- the programme: active, stated, open, with a place
    SELECT * INTO pr FROM admissions.programme_rule r WHERE r.policy_id = pol.id AND r.programme_code = p_programme;
    IF g.archived THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Programme active','requirement','An active programme','candidate','Archived','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'The programme is not active'::text;
    END IF;
    IF pr.programme_code IS NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Admission rule stated','requirement','A rule for ' || p_session,'candidate','None stated','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'No admission rule is stated for the programme this session'::text;
        RETURN QUERY SELECT 'NOT_ELIGIBLE'::text, v_checks, v_reasons; RETURN;
    END IF;
    SELECT c1.reason INTO v_closed FROM admissions.programme_closed c1 WHERE c1.policy_id = pol.id AND c1.programme_code = p_programme;
    IF v_closed IS NOT NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Open for admission','requirement','Open this session','candidate','Closed: ' || v_closed,'status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || ('The programme is closed for ' || p_session);
    ELSE
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Open for admission','requirement','Open this session','candidate','Open','status','MET','mandatory',true);
    END IF;
    IF pr.quota IS NOT NULL THEN
        SELECT count(*) INTO v_taken FROM admissions.candidate cc WHERE cc.session = p_session AND cc.offer_state IN ('ADMITTED','ACCEPTED') AND cc.programme = g.name;
        IF v_taken >= pr.quota THEN
            v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Places','requirement',pr.quota || ' place(s)','candidate',v_taken || ' admitted — none remains','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'No place remains on the programme'::text;
        ELSE
            v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Places','requirement',pr.quota || ' place(s)','candidate',(pr.quota - v_taken) || ' remaining','status','MET','mandatory',true);
        END IF;
    END IF;
    -- O'Level: the best combination of sittings the programme allows
    SELECT array_agg(st.id ORDER BY st.exam_year NULLS LAST, st.ord) INTO sit FROM admissions.olevel_sitting st WHERE st.session = p_session AND st.jamb_key = v_key;
    IF sit IS NULL THEN
        v_unverified := true;
        v_checks := v_checks || jsonb_build_object('kind','OLEVEL','label','O''Level result','requirement','A result on record','candidate','No O''Level result on record','status','UNVERIFIED','mandatory',true);
        v_reasons := v_reasons || 'Unverified: no O''Level result is on record'::text;
    ELSE
        n := array_length(sit, 1); allowed := greatest(1, coalesce(pr.olevel_sittings, 2));
        IF n <= allowed OR allowed >= 3 THEN
            v_best := admissions.olevel_checks(p_session, pol.id, p_programme, sit, pr);
            combo := sit;
        ELSIF allowed = 1 THEN
            FOR i IN 1..n LOOP
                c := admissions.olevel_checks(p_session, pol.id, p_programme, ARRAY[sit[i]], pr);
                SELECT count(*) INTO v_met FROM jsonb_array_elements(c) e WHERE e->>'status' = 'MET';
                IF v_met > v_best_met THEN v_best := c; v_best_met := v_met; combo := ARRAY[sit[i]]; END IF;
            END LOOP;
        ELSE
            FOR i IN 1..n LOOP FOR j IN (i+1)..n LOOP
                c := admissions.olevel_checks(p_session, pol.id, p_programme, ARRAY[sit[i], sit[j]], pr);
                SELECT count(*) INTO v_met FROM jsonb_array_elements(c) e WHERE e->>'status' = 'MET';
                IF v_met > v_best_met THEN v_best := c; v_best_met := v_met; combo := ARRAY[sit[i], sit[j]]; END IF;
            END LOOP; END LOOP;
        END IF;
        v_checks := v_checks || jsonb_build_object('kind','OLEVEL_SITTINGS','label','Sittings','requirement',CASE WHEN allowed = 1 THEN 'One sitting only' ELSE 'At most ' || allowed || ' sittings combined' END,
            'candidate', n || ' sitting' || CASE WHEN n = 1 THEN '' ELSE 's' END || ' on record' || CASE WHEN array_length(combo, 1) < n THEN ' — read on the best ' || array_length(combo, 1) ELSE '' END,
            'status','MET','mandatory',true);
        v_checks := v_checks || v_best;
    END IF;
    -- UTME: the subject combination and the score
    IF p_entry_mode = 'UTME' THEN
        SELECT array_agg(lower(btrim(e.value))) INTO cand
          FROM admissions.caps_row_live x CROSS JOIN LATERAL jsonb_each_text(x.raw) AS e(key, value)
         WHERE x.session = p_session AND x.jamb_key = v_key
           AND regexp_replace(lower(btrim(e.key)), '[^a-z0-9]', '', 'g') IN ('subject1','subject2','subject3','subject4','subj1','subj2','subj3','subj4')
           AND nullif(btrim(e.value), '') IS NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'UTME') THEN
            v_checks := v_checks || jsonb_build_object('kind','UTME_COMBINATION','label','UTME subject combination','requirement','None configured','candidate',coalesce(array_to_string(cand, ', '), '—'),'status','INFO','mandatory',false);
        ELSIF cand IS NULL THEN
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no UTME subjects are on the candidate''s record'::text;
            v_checks := v_checks || jsonb_build_object('kind','UTME_COMBINATION','label','UTME subject combination','requirement','As configured','candidate','No UTME subjects on record','status','UNVERIFIED','mandatory',true);
        ELSE
            FOR grp IN SELECT gg.* FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'UTME' LOOP
                FOR it IN SELECT * FROM admissions.rule_items(grp.id) LOOP
                    SELECT count(DISTINCT m.opt) INTO v_have FROM unnest(it.members) AS m(opt)
                     WHERE m.opt LIKE 'english%' OR EXISTS (SELECT 1 FROM unnest(cand) AS cs(subj) WHERE admissions.subject_same(cs.subj, m.opt, pol.id, 'UTME'));
                    v_status := CASE WHEN coalesce(v_have, 0) >= it.need THEN 'MET' ELSE 'NOT_MET' END;
                    IF v_status = 'NOT_MET' THEN v_failed := true; v_reasons := v_reasons || ('Required UTME subject not offered: ' || it.slot); END IF;
                    v_checks := v_checks || jsonb_build_object('kind','UTME_COMBINATION','label',it.slot,
                        'requirement', CASE WHEN it.need > 1 THEN it.need || ' of ' || array_to_string(it.members, ' / ') ELSE array_to_string(it.members, ' or ') END,
                        'candidate', CASE WHEN v_status = 'MET' THEN 'Offered' ELSE 'Not offered (' || array_to_string(cand, ', ') || ')' END, 'status', v_status, 'mandatory', true);
                END LOOP;
            END LOOP;
        END IF;
        SELECT max(x.aggregate) INTO v_agg FROM admissions.caps_row_live x WHERE x.session = p_session AND x.jamb_key = v_key AND x.entry_mode = 'UTME';
        SELECT f.cutoff INTO v_fac FROM admissions.faculty_quota f WHERE f.policy_id = pol.id AND f.faculty_code = g.faculty_code;
        v_load := admissions.load_cutoff_for(p_session);
        v_prog_cut := pr.cutoff;
        v_req := greatest(coalesce(v_prog_cut, v_fac), v_load);
        IF v_req IS NULL THEN
            v_checks := v_checks || jsonb_build_object('kind','UTME_SCORE','label','UTME score','requirement','No minimum configured','candidate',coalesce(v_agg::text, 'Not on record'),'status','INFO','mandatory',false);
        ELSIF v_agg IS NULL THEN
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no UTME score is on record'::text;
            v_checks := v_checks || jsonb_build_object('kind','UTME_SCORE','label','UTME score','requirement','Minimum ' || v_req,'candidate','Not on record','status','UNVERIFIED','mandatory',true);
        ELSE
            v_status := CASE WHEN v_agg >= v_req THEN 'MET' ELSE 'NOT_MET' END;
            IF v_status = 'NOT_MET' THEN v_failed := true; v_reasons := v_reasons || ('UTME score ' || v_agg || ' is below the minimum of ' || v_req); END IF;
            v_checks := v_checks || jsonb_build_object('kind','UTME_SCORE','label','UTME score','requirement','Minimum ' || v_req || ' (programme ' || coalesce(v_prog_cut::text, '—') || ' · faculty ' || coalesce(v_fac::text, '—') || ' · session ' || coalesce(v_load::text, '—') || ')',
                'candidate', v_agg::text, 'status', v_status, 'mandatory', true);
        END IF;
    ELSIF p_entry_mode = 'DIRECT_ENTRY' THEN
        SELECT array_agg(lower(btrim(s.subject))) INTO cand FROM admissions.de_award a JOIN admissions.de_award_subject s ON s.award_id = a.id WHERE a.session = p_session AND a.jamb_key = v_key AND nullif(btrim(s.subject), '') IS NOT NULL;
        IF NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'DE') THEN
            v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement','None configured','candidate',coalesce(array_to_string(cand, ', '), '—'),'status','INFO','mandatory',false);
        ELSIF cand IS NULL THEN
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no Direct Entry award is captured'::text;
            v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement','As configured','candidate','No award captured','status','UNVERIFIED','mandatory',true);
        ELSE
            FOR grp IN SELECT gg.* FROM admissions.rule_subject_group gg WHERE gg.policy_id = pol.id AND gg.programme_code = p_programme AND gg.scope = 'DE' LOOP
                SELECT count(DISTINCT m.opt) INTO v_have
                  FROM admissions.rule_items(grp.id) it2 CROSS JOIN unnest(it2.members) AS m(opt)
                 WHERE EXISTS (SELECT 1 FROM unnest(cand) AS cs(subj) WHERE admissions.subject_same(cs.subj, m.opt, pol.id, 'UTME'));
                v_status := CASE WHEN coalesce(v_have, 0) >= grp.choose THEN 'MET' ELSE 'NOT_MET' END;
                IF v_status = 'NOT_MET' THEN v_failed := true; v_reasons := v_reasons || ('Direct Entry subjects short of ' || grp.choose || ' required'); END IF;
                v_checks := v_checks || jsonb_build_object('kind','DE_COMBINATION','label','Direct Entry subjects','requirement',grp.choose || ' of ' || (SELECT string_agg(rs.subject, ', ') FROM admissions.rule_subject rs WHERE rs.group_id = grp.id),
                    'candidate', array_to_string(cand, ', '), 'status', v_status, 'mandatory', true);
            END LOOP;
        END IF;
    END IF;
    -- any O'Level check that failed
    FOR c IN SELECT e FROM jsonb_array_elements(v_checks) e WHERE e->>'status' = 'NOT_MET' AND (e->>'kind') LIKE 'OLEVEL%' LOOP
        v_failed := true;
        v_reasons := v_reasons || ('Required O''Level ' || (c->>'label') || ' not satisfied (' || (c->>'requirement') || '; candidate: ' || (c->>'candidate') || ')');
    END LOOP;
    -- more than the academic requirements
    v_add := nullif(btrim(coalesce(pr.additional_screening, '')), '');
    IF v_add IS NOT NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','SCREENING','label','Additional screening','requirement',v_add,'candidate','To be scheduled','status','INFO','mandatory',false);
    END IF;
    v_res := CASE WHEN v_failed THEN 'NOT_ELIGIBLE' WHEN v_unverified THEN 'UNVERIFIED' WHEN v_add IS NOT NULL THEN 'ELIGIBLE_SCREENING' ELSE 'ELIGIBLE' END;
    RETURN QUERY SELECT v_res, v_checks, v_reasons;
END $$;


COMMIT;
