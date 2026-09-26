-- ═══════════════════════════════════════════════════════════════════════════
-- V266 · Admission eligibility and the course suggestion engine
--
--   An applicant applies for a programme. Whether they qualify for it, and
--   which other programmes they could legitimately be considered for, is read
--   from the University's own admission settings for the session — the
--   compulsory O'Level credits (V053), the programme's required O'Level
--   subjects (a new group scope here, with a minimum grade), the credits and
--   sittings the programme allows (V008), the UTME subject combination (V189–
--   V192), the Direct Entry subjects (V200), the cut-offs — programme, faculty
--   and the session's load cut-off (V008, V024) — the closures (V023), the
--   places (V054), and the subject equivalences the Committee states (new,
--   here). Nothing is inferred from a programme's name and nothing is invented:
--   a requirement nobody configured is reported as not configured, a result
--   nobody recorded as unverified, and a programme is suggested only when every
--   mandatory requirement is met.
--
--   Every evaluation is kept — the policy version it was read under, every
--   check with the requirement, what the candidate holds and the verdict — and
--   superseded, never edited, when the record or the rules change. A suggested
--   programme is never applied by itself: the applicant asks, the eligibility
--   is read again, and the Academic Office decides on the record.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V266: admission eligibility and course suggestion engine', true);

-- ── 1 · the policy, extended ──────────────────────────────────────────────

-- the version of a session's rules: bumped whenever any rule the evaluator reads changes, so an evaluation names what it was read under
ALTER TABLE admissions.session_policy ADD COLUMN IF NOT EXISTS rules_version int NOT NULL DEFAULT 1;
-- a programme that needs more than the academic requirements: an interview, a portfolio, a practical test, a medical
ALTER TABLE admissions.programme_rule ADD COLUMN IF NOT EXISTS additional_screening text NULL;
-- the required O'Level subjects a candidate is CHECKED against (the OLEVEL scope names the relevant subjects the screening score counts)
ALTER TABLE admissions.rule_subject_group DROP CONSTRAINT IF EXISTS ck_grp_scope;
ALTER TABLE admissions.rule_subject_group ADD CONSTRAINT ck_grp_scope CHECK (scope IN ('UTME', 'OLEVEL', 'DE', 'OLEVEL_REQUIRED'));

-- a subject the Committee accepts in place of another: "Biology or Agricultural Science" — stated, never inferred
CREATE TABLE admissions.subject_equivalence (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id  uuid NOT NULL REFERENCES admissions.session_policy(id),
    subject    text NOT NULL,           -- the subject a rule names
    equivalent text NOT NULL,           -- the subject a candidate may offer in its place
    scope      text NOT NULL DEFAULT 'ANY',
    note       text NULL,
    CONSTRAINT ck_subeq_scope CHECK (scope IN ('OLEVEL', 'UTME', 'ANY')),
    CONSTRAINT ck_subeq_distinct CHECK (lower(btrim(subject)) <> lower(btrim(equivalent))),
    CONSTRAINT uq_subeq UNIQUE (policy_id, subject, equivalent, scope)
);
SELECT audit.attach('admissions.subject_equivalence');
COMMENT ON TABLE admissions.subject_equivalence IS 'A subject accepted in place of another under a session''s admission settings, for O''Level, UTME or both. The evaluator matches only what is stated here.';

-- ── 2 · the rules version, bumped by the tables the evaluator reads ───────

CREATE OR REPLACE FUNCTION admissions.bump_rules_version(p_policy uuid)
RETURNS void LANGUAGE sql AS $$
    UPDATE admissions.session_policy SET rules_version = rules_version + 1 WHERE id = p_policy;
$$;

CREATE OR REPLACE FUNCTION admissions.rules_touched()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r record; v_pol uuid; v_session text;
BEGIN
    r := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    CASE TG_TABLE_NAME
        WHEN 'programme_rule', 'rule_subject_group', 'programme_olevel_allowance', 'faculty_quota', 'programme_closed', 'subject_equivalence' THEN
            v_pol := r.policy_id;
        WHEN 'rule_subject' THEN
            SELECT g.policy_id INTO v_pol FROM admissions.rule_subject_group g WHERE g.id = r.group_id;
        WHEN 'olevel_compulsory', 'screening_exam_programme', 'load_cutoff', 'olevel_grading', 'olevel_grade_point' THEN
            v_session := r.session;
            SELECT p.id INTO v_pol FROM admissions.session_policy p WHERE p.session = v_session;
        ELSE v_pol := NULL;
    END CASE;
    IF v_pol IS NOT NULL THEN PERFORM admissions.bump_rules_version(v_pol); END IF;
    RETURN NULL;
END $$;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['programme_rule','rule_subject_group','rule_subject','programme_olevel_allowance','faculty_quota','programme_closed',
                             'subject_equivalence','olevel_compulsory','screening_exam_programme','load_cutoff','olevel_grading','olevel_grade_point'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_rules_touched ON admissions.%I', t);
        EXECUTE format('CREATE TRIGGER trg_rules_touched AFTER INSERT OR UPDATE OR DELETE ON admissions.%I FOR EACH ROW EXECUTE FUNCTION admissions.rules_touched()', t);
    END LOOP;
END $$;

-- ── 3 · the evaluations, kept ────────────────────────────────────────────

CREATE TABLE admissions.eligibility_run (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id         uuid NOT NULL REFERENCES admissions.application(id),
    candidate_id           uuid NOT NULL REFERENCES admissions.candidate(id),
    session                text NOT NULL,
    jamb_key               text NOT NULL,
    entry_mode             text NOT NULL,
    applied_programme_code text NULL,
    applied_programme      text NULL,
    policy_id              uuid NULL REFERENCES admissions.session_policy(id),
    policy_state           text NULL,
    rules_version          int  NULL,
    applied_result         text NOT NULL,
    alternatives           int  NOT NULL DEFAULT 0,
    evaluated_at           timestamptz NOT NULL DEFAULT now(),
    evaluated_by           uuid NULL,
    trigger_kind           text NOT NULL,
    stale                  boolean NOT NULL DEFAULT false,
    superseded_at          timestamptz NULL,
    CONSTRAINT ck_elrun_result CHECK (applied_result IN ('ELIGIBLE','ELIGIBLE_SCREENING','NOT_ELIGIBLE','UNVERIFIED')),
    CONSTRAINT ck_elrun_trigger CHECK (trigger_kind IN ('SUBMISSION','SYSTEM','OFFICER','APPLICANT','DATA_CHANGE','POLICY_CHANGE','PROGRAMME_CHANGE'))
);
CREATE INDEX ix_elrun_current ON admissions.eligibility_run (application_id) WHERE superseded_at IS NULL;
CREATE INDEX ix_elrun_session ON admissions.eligibility_run (session, applied_result) WHERE superseded_at IS NULL;
SELECT audit.attach('admissions.eligibility_run');
COMMENT ON TABLE admissions.eligibility_run IS 'One evaluation of an application against the session''s admission settings: the policy version read, the verdict on the applied programme, how many alternatives qualified; superseded, never edited.';

CREATE TABLE admissions.eligibility_result (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id         uuid NOT NULL REFERENCES admissions.eligibility_run(id) ON DELETE CASCADE,
    programme_code text NOT NULL,
    programme      text NOT NULL,
    faculty_code   text NULL,
    faculty        text NULL,
    department     text NULL,
    kind           text NOT NULL,
    result         text NOT NULL,
    checks         jsonb NOT NULL,
    reasons        text[] NOT NULL DEFAULT ARRAY[]::text[],
    ord            int NOT NULL DEFAULT 0,
    CONSTRAINT ck_elres_kind CHECK (kind IN ('APPLIED','ALTERNATIVE')),
    CONSTRAINT ck_elres_result CHECK (result IN ('ELIGIBLE','ELIGIBLE_SCREENING','NOT_ELIGIBLE','UNVERIFIED'))
);
CREATE INDEX ix_elres_run ON admissions.eligibility_result (run_id, kind, ord);
SELECT audit.exempt('admissions.eligibility_result', 'Derived from the admission settings and the candidate''s record at the run''s moment; re-derived at will; the run itself is on the spine.');

CREATE TABLE admissions.eligibility_event (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id uuid NOT NULL REFERENCES admissions.application(id),
    run_id         uuid NULL,
    action         text NOT NULL,
    programme_code text NULL,
    result         text NULL,
    detail         text NULL,
    actor_id       uuid NULL,
    actor_office   text NULL,
    at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_elev_app ON admissions.eligibility_event (application_id, at);
SELECT audit.attach('admissions.eligibility_event');
CREATE OR REPLACE FUNCTION admissions.eligibility_event_is_written_once()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF current_setting('moaum.maintenance', true) = 'on' THEN RETURN COALESCE(NEW, OLD); END IF;
    RAISE EXCEPTION 'the eligibility trail is written once' USING ERRCODE = '23514';
END $$;
CREATE TRIGGER trg_elev_written_once BEFORE UPDATE ON admissions.eligibility_event FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_event_is_written_once();

CREATE OR REPLACE FUNCTION admissions.eligibility_log(p_app uuid, p_run uuid, p_action text, p_programme text, p_result text, p_detail text)
RETURNS void LANGUAGE sql AS $$
    INSERT INTO admissions.eligibility_event (application_id, run_id, action, programme_code, result, detail, actor_id, actor_office)
    VALUES (p_app, p_run, p_action, p_programme, p_result, p_detail, nullif(current_setting('moaum.actor_id', true), '')::uuid, nullif(current_setting('moaum.actor_office', true), ''));
$$;

-- the applicant's request to move to a programme the engine found them eligible for; decided by the Academic Office
CREATE TABLE admissions.programme_change_request (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    application_id       uuid NOT NULL REFERENCES admissions.application(id),
    candidate_id         uuid NOT NULL REFERENCES admissions.candidate(id),
    session              text NOT NULL,
    from_programme_code  text NULL,
    from_programme       text NOT NULL,
    to_programme_code    text NOT NULL REFERENCES ref.programme(code),
    to_programme         text NOT NULL,
    run_id               uuid NULL REFERENCES admissions.eligibility_run(id),
    eligibility_at_request  text NOT NULL,
    requested_at         timestamptz NOT NULL DEFAULT now(),
    requested_by_kind    text NOT NULL,
    requested_by         uuid NULL,
    note                 text NULL,
    state                text NOT NULL DEFAULT 'REQUESTED',
    eligibility_at_decision text NULL,
    decided_at           timestamptz NULL,
    decided_by           uuid NULL,
    decision_note        text NULL,
    CONSTRAINT ck_pcr_state CHECK (state IN ('REQUESTED','APPROVED','REJECTED','CANCELLED')),
    CONSTRAINT ck_pcr_by CHECK (requested_by_kind IN ('APPLICANT','OFFICE'))
);
CREATE INDEX ix_pcr_app ON admissions.programme_change_request (application_id, requested_at DESC);
CREATE UNIQUE INDEX uq_pcr_open ON admissions.programme_change_request (application_id) WHERE state = 'REQUESTED';
SELECT audit.attach('admissions.programme_change_request');

-- ── 4 · the matchers: a subject, a grade, a rule item ────────────────────

/* the rank of an O'Level grade: A1 first, F9 last; an unknown grade ranks last */
CREATE OR REPLACE FUNCTION admissions.grade_rank(p_grade text)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE upper(btrim(coalesce(p_grade, ''))) WHEN 'A1' THEN 1 WHEN 'B2' THEN 2 WHEN 'B3' THEN 3 WHEN 'C4' THEN 4 WHEN 'C5' THEN 5 WHEN 'C6' THEN 6 WHEN 'D7' THEN 7 WHEN 'E8' THEN 8 WHEN 'F9' THEN 9 ELSE 99 END;
$$;

/* does the candidate's subject satisfy the subject a rule names — the same name, the Mathematics rule, an English variant, or a stated equivalence */
CREATE OR REPLACE FUNCTION admissions.subject_same(p_cand text, p_req text, p_policy uuid, p_scope text)
RETURNS boolean LANGUAGE sql STABLE AS $$
    WITH n AS (SELECT lower(btrim(p_cand)) AS c, lower(btrim(p_req)) AS r)
    SELECT CASE
        WHEN n.c = '' OR n.r = '' THEN false
        WHEN n.c = n.r THEN true
        WHEN n.r LIKE 'english%' AND n.c LIKE 'english%' THEN true
        WHEN n.r LIKE 'math%' AND n.r NOT LIKE 'further%' AND n.c LIKE 'math%' AND n.c NOT LIKE 'further%' THEN true
        WHEN n.r LIKE 'further math%' AND n.c LIKE 'further math%' THEN true
        WHEN EXISTS (SELECT 1 FROM admissions.subject_equivalence e
                      WHERE e.policy_id = p_policy AND lower(btrim(e.subject)) = n.r AND lower(btrim(e.equivalent)) = n.c
                        AND (e.scope = 'ANY' OR e.scope = p_scope)) THEN true
        ELSE false END
      FROM n;
$$;

/* the items of a rule group under the shared grammar: each item is "at least K distinct members of a slash-set";
   a plain item or "X/Y" is K = 1; "N of A/B/C" (word or digit) is K = N */
CREATE OR REPLACE FUNCTION admissions.rule_items(p_group uuid)
RETURNS TABLE (slot text, need int, members text[])
LANGUAGE sql STABLE AS $$
    WITH raw AS (SELECT btrim(rs.subject) AS slot FROM admissions.rule_subject rs WHERE rs.group_id = p_group),
    norm AS (
        SELECT slot,
               regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                 lower(slot), '\many\M', ' ', 'g'), '\mone\M', '1', 'g'), '\mtwo\M', '2', 'g'), '\mthree\M', '3', 'g'), '\mfour\M', '4', 'g'), '\mfive\M', '5', 'g') AS s
          FROM raw),
    parsed AS (
        SELECT slot,
               CASE WHEN s ~ '\m\d+\s*of\M' THEN ((regexp_match(s, '(\d+)\s*of\M'))[1])::int ELSE 1 END AS need,
               CASE WHEN s ~ '\m\d+\s*of\M' THEN btrim(regexp_replace(s, '^.*?\d+\s*of\M[:\s]*', '')) ELSE s END AS setstr
          FROM norm)
    SELECT p.slot, p.need,
           ARRAY(SELECT btrim(m) FROM regexp_split_to_table(p.setstr, '\s*/\s*|\s+or\s+') AS m WHERE btrim(m) <> '')
      FROM parsed p;
$$;

/* the best grade the candidate holds per subject over a set of sittings */
CREATE OR REPLACE FUNCTION admissions.olevel_best_of(p_sittings uuid[])
RETURNS TABLE (subject text, grade text, rank int, credit boolean, pass boolean)
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (lower(btrim(g.subject))) btrim(g.subject), upper(btrim(g.grade)), admissions.grade_rank(g.grade),
           admissions.grade_rank(g.grade) <= 6, admissions.grade_rank(g.grade) <= 8
      FROM admissions.olevel_grade g
     WHERE g.sitting_id = ANY (p_sittings)
     ORDER BY lower(btrim(g.subject)), admissions.grade_rank(g.grade);
$$;

-- ── 5 · the evaluator: one programme, one candidate, every check explained ─

/* the O'Level checks over one combination of sittings: compulsory credits, the required subjects, the credit count */
CREATE OR REPLACE FUNCTION admissions.olevel_checks(p_session text, p_policy uuid, p_programme text, p_sittings uuid[], p_rule admissions.programme_rule)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE checks jsonb := '[]'::jsonb; cs record; b record; it record; grp record; v_have int; v_names text; v_credits int; v_min int; v_min_grade text;
        v_found text; v_status text; v_all text; v_matches text;
BEGIN
    -- the compulsory credits (English and Mathematics unless the session states otherwise), a pass accepted only where the programme allows it
    FOR cs IN SELECT * FROM admissions.olevel_compulsory_subjects(p_session) LOOP
        SELECT x.grade, x.rank INTO b FROM admissions.olevel_best_of(p_sittings) x WHERE x.subject ~ cs.pattern ORDER BY x.rank LIMIT 1;
        IF EXISTS (SELECT 1 FROM admissions.programme_olevel_allowance a WHERE a.policy_id = p_policy AND a.programme_code = p_programme AND a.subject = cs.subject) THEN
            v_status := CASE WHEN b.rank IS NOT NULL AND b.rank <= 8 THEN 'MET' ELSE 'NOT_MET' END;
            checks := checks || jsonb_build_object('kind', 'OLEVEL_COMPULSORY', 'label', cs.subject, 'requirement', 'Pass (this programme accepts a pass)', 'candidate', coalesce(b.grade, 'Not available'), 'status', v_status, 'mandatory', true);
        ELSE
            v_status := CASE WHEN b.rank IS NOT NULL AND b.rank <= 6 THEN 'MET' ELSE 'NOT_MET' END;
            checks := checks || jsonb_build_object('kind', 'OLEVEL_COMPULSORY', 'label', cs.subject, 'requirement', 'Credit (C6 or better)', 'candidate', coalesce(b.grade, 'Not available'), 'status', v_status, 'mandatory', true);
        END IF;
    END LOOP;
    -- the programme's required subjects, each item "at least K of a set" at the group's minimum grade
    FOR grp IN SELECT g.* FROM admissions.rule_subject_group g WHERE g.policy_id = p_policy AND g.programme_code = p_programme AND g.scope = 'OLEVEL_REQUIRED' LOOP
        v_min_grade := coalesce(upper(grp.min_grade), 'C6');
        v_min := admissions.grade_rank(v_min_grade);
        FOR it IN SELECT * FROM admissions.rule_items(grp.id) LOOP
            SELECT count(DISTINCT m.opt), string_agg(DISTINCT x.subject || ' — ' || x.grade, ', ')
              INTO v_have, v_matches
              FROM unnest(it.members) AS m(opt)
              JOIN admissions.olevel_best_of(p_sittings) x ON admissions.subject_same(x.subject, m.opt, p_policy, 'OLEVEL') AND x.rank <= v_min;
            v_status := CASE WHEN coalesce(v_have, 0) >= it.need THEN 'MET' ELSE 'NOT_MET' END;
            -- what the candidate holds in those subjects at any grade, for the explanation
            SELECT string_agg(DISTINCT x.subject || ' — ' || x.grade, ', ') INTO v_all
              FROM unnest(it.members) AS m(opt) JOIN admissions.olevel_best_of(p_sittings) x ON admissions.subject_same(x.subject, m.opt, p_policy, 'OLEVEL');
            checks := checks || jsonb_build_object('kind', 'OLEVEL_REQUIRED', 'label', it.slot,
                'requirement', CASE WHEN it.need > 1 THEN it.need || ' of ' || array_to_string(it.members, ' / ') ELSE array_to_string(it.members, ' or ') END || ' — ' || v_min_grade || ' or better',
                'candidate', coalesce(v_matches, coalesce(v_all, 'Not available')), 'status', v_status, 'mandatory', true);
        END LOOP;
    END LOOP;
    IF NOT EXISTS (SELECT 1 FROM admissions.rule_subject_group g WHERE g.policy_id = p_policy AND g.programme_code = p_programme AND g.scope = 'OLEVEL_REQUIRED') THEN
        checks := checks || jsonb_build_object('kind', 'OLEVEL_REQUIRED', 'label', 'Required O''Level subjects', 'requirement', 'None configured beyond the compulsory credits', 'candidate', '—', 'status', 'INFO', 'mandatory', false);
    END IF;
    -- the number of credits
    SELECT count(*) INTO v_credits FROM admissions.olevel_best_of(p_sittings) x WHERE x.credit;
    checks := checks || jsonb_build_object('kind', 'OLEVEL_CREDITS', 'label', 'Credits in all', 'requirement', coalesce(p_rule.olevel_credits, 5) || ' credit passes',
        'candidate', v_credits || ' credit' || CASE WHEN v_credits = 1 THEN '' ELSE 's' END, 'status', CASE WHEN v_credits >= coalesce(p_rule.olevel_credits, 5) THEN 'MET' ELSE 'NOT_MET' END, 'mandatory', true);
    RETURN checks;
END $$;

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
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Programme active','requirement','An active programme','candidate','Archived','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'The programme is not active';
    END IF;
    IF pr.programme_code IS NULL THEN
        v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Admission rule stated','requirement','A rule for ' || p_session,'candidate','None stated','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'No admission rule is stated for the programme this session';
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
            v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Places','requirement',pr.quota || ' place(s)','candidate',v_taken || ' admitted — none remains','status','NOT_MET','mandatory',true); v_failed := true; v_reasons := v_reasons || 'No place remains on the programme';
        ELSE
            v_checks := v_checks || jsonb_build_object('kind','PROGRAMME','label','Places','requirement',pr.quota || ' place(s)','candidate',(pr.quota - v_taken) || ' remaining','status','MET','mandatory',true);
        END IF;
    END IF;
    -- O'Level: the best combination of sittings the programme allows
    SELECT array_agg(st.id ORDER BY st.exam_year NULLS LAST, st.ord) INTO sit FROM admissions.olevel_sitting st WHERE st.session = p_session AND st.jamb_key = v_key;
    IF sit IS NULL THEN
        v_unverified := true;
        v_checks := v_checks || jsonb_build_object('kind','OLEVEL','label','O''Level result','requirement','A result on record','candidate','No O''Level result on record','status','UNVERIFIED','mandatory',true);
        v_reasons := v_reasons || 'Unverified: no O''Level result is on record';
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
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no UTME subjects are on the candidate''s record';
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
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no UTME score is on record';
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
            v_unverified := true; v_reasons := v_reasons || 'Unverified: no Direct Entry award is captured';
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

COMMENT ON FUNCTION admissions.evaluate_programme(text, text, text, text) IS
  'One candidate against one programme under the session''s admission settings: the programme''s standing, the O''Level compulsory credits, required subjects (OLEVEL_REQUIRED groups, min grade), credits and sittings, the UTME combination and the effective cut-off (programme, faculty, session), or the Direct Entry subjects. Every check explained; ELIGIBLE, ELIGIBLE_SCREENING, NOT_ELIGIBLE or UNVERIFIED.';

-- ── 6 · the run: the applied programme, then every other, kept ────────────

CREATE OR REPLACE FUNCTION admissions.programme_code_of(p_name text)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT p.code FROM ref.programme p WHERE p.name = p_name ORDER BY p.archived, p.code LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION admissions.evaluate_application(p_app uuid, p_trigger text, p_actor uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; pol admissions.session_policy; v_run uuid; v_code text; r record; g record; n int := 0; ord int := 0;
        v_prev text; v_prev_alts int; v_fac text; e record;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    v_code := admissions.programme_code_of(c.programme);
    SELECT * INTO pol FROM admissions.session_policy p WHERE p.session = a.session ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1;
    SELECT x.applied_result, x.alternatives INTO v_prev, v_prev_alts FROM admissions.eligibility_run x WHERE x.application_id = p_app AND x.superseded_at IS NULL ORDER BY x.evaluated_at DESC LIMIT 1;
    UPDATE admissions.eligibility_run SET superseded_at = now() WHERE application_id = p_app AND superseded_at IS NULL;
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, v_code, c.entry_mode);
    INSERT INTO admissions.eligibility_run (application_id, candidate_id, session, jamb_key, entry_mode, applied_programme_code, applied_programme, policy_id, policy_state, rules_version, applied_result, evaluated_by, trigger_kind)
    VALUES (p_app, c.id, a.session, c.jamb_key, c.entry_mode, v_code, c.programme, pol.id, pol.state, pol.rules_version, r.result, p_actor, p_trigger)
    RETURNING id INTO v_run;
    SELECT p.faculty_code INTO v_fac FROM ref.programme p WHERE p.code = v_code;
    INSERT INTO admissions.eligibility_result (run_id, programme_code, programme, faculty_code, faculty, department, kind, result, checks, reasons, ord)
    SELECT v_run, coalesce(v_code, '?'), c.programme, p.faculty_code, f.name, d.name, 'APPLIED', r.result, r.checks, r.reasons, 0
      FROM (SELECT 1) one LEFT JOIN ref.programme p ON p.code = v_code LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code;
    -- alternatives are searched only when the applied programme is refused on the rules
    IF r.result = 'NOT_ELIGIBLE' AND pol.id IS NOT NULL THEN
        FOR g IN
            SELECT p.code, p.name, p.faculty_code, f.name AS faculty, d.name AS department
              FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
             WHERE NOT p.archived AND p.code <> coalesce(v_code, '')
               AND EXISTS (SELECT 1 FROM admissions.programme_rule pr WHERE pr.policy_id = pol.id AND pr.programme_code = p.code)
               AND NOT EXISTS (SELECT 1 FROM admissions.programme_closed cl WHERE cl.policy_id = pol.id AND cl.programme_code = p.code)
             ORDER BY p.name
        LOOP
            SELECT * INTO e FROM admissions.evaluate_programme(a.session, c.jamb_key, g.code, c.entry_mode);
            INSERT INTO admissions.eligibility_result (run_id, programme_code, programme, faculty_code, faculty, department, kind, result, checks, reasons, ord)
            VALUES (v_run, g.code, g.name, g.faculty_code, g.faculty, g.department, 'ALTERNATIVE', e.result, e.checks, e.reasons,
                    CASE e.result WHEN 'ELIGIBLE' THEN 0 WHEN 'ELIGIBLE_SCREENING' THEN 100 WHEN 'UNVERIFIED' THEN 200 ELSE 300 END + CASE WHEN g.faculty_code = v_fac THEN 0 ELSE 50 END);
            IF e.result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN n := n + 1; END IF;
        END LOOP;
    END IF;
    UPDATE admissions.eligibility_run SET alternatives = n WHERE id = v_run;
    PERFORM admissions.eligibility_log(p_app, v_run, 'EVALUATED', v_code, r.result,
        'Applied programme ' || coalesce(c.programme, '?') || ': ' || r.result || CASE WHEN r.result = 'NOT_ELIGIBLE' THEN ' · ' || n || ' eligible alternative(s)' ELSE '' END
        || ' · policy ' || coalesce(a.session, '') || '-V' || coalesce(pol.rules_version::text, '?') || ' (' || coalesce(pol.state, 'none') || ') · ' || p_trigger);
    IF n > 0 OR r.result = 'NOT_ELIGIBLE' THEN
        PERFORM admissions.eligibility_log(p_app, v_run, 'RECOMMENDATION_GENERATED', v_code, r.result, n || ' eligible alternative programme(s) found');
    END IF;
    -- the applicant told once per change of verdict, never that admission is guaranteed
    IF r.result = 'NOT_ELIGIBLE' AND (v_prev IS DISTINCT FROM r.result OR coalesce(v_prev_alts, -1) <> n) AND p_trigger IN ('SUBMISSION', 'SYSTEM', 'DATA_CHANGE', 'POLICY_CHANGE', 'PROGRAMME_CHANGE') THEN
        PERFORM admissions.notify_applicant(p_app, 'Your ' || a.session || ' application — programme eligibility',
            'Your selected programme, ' || c.programme || ', does not meet the current admission requirements based on the information on your record. '
            || CASE WHEN n > 0 THEN 'Based on your submitted qualifications, ' || n || ' alternative programme(s) may be available to you. Please review Programme eligibility on your admission portal; nothing changes unless you ask and the Admissions Office approves.'
                    ELSE 'No eligible alternative programme was found on the current admission policy. Please review the reasons on your admission portal.' END,
            'MOAUM: your selected programme does not meet the admission requirements on record. ' || CASE WHEN n > 0 THEN n || ' alternative programme(s) may be available — see the portal.' ELSE 'See the reasons on the portal.' END);
    ELSIF r.result IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') AND v_prev = 'NOT_ELIGIBLE' THEN
        PERFORM admissions.notify_applicant(p_app, 'Your ' || a.session || ' application — programme eligibility',
            'On the information now on your record, your selected programme, ' || c.programme || ', meets the current admission requirements. This is not an offer of admission; the Admissions Board decides in the normal way.', NULL);
    END IF;
    RETURN v_run;
END $$;

/* the current evaluation of an application, made or refreshed when none stands, the record changed or the rules moved on */
CREATE OR REPLACE FUNCTION admissions.eligibility_current(p_app uuid, p_actor uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE run admissions.eligibility_run; pol_ver int; pol_id uuid;
BEGIN
    SELECT * INTO run FROM admissions.eligibility_run x WHERE x.application_id = p_app AND x.superseded_at IS NULL ORDER BY x.evaluated_at DESC LIMIT 1;
    SELECT p.id, p.rules_version INTO pol_id, pol_ver FROM admissions.application a JOIN admissions.session_policy p ON p.session = a.session WHERE a.id = p_app ORDER BY (p.state = 'IN_FORCE') DESC LIMIT 1;
    IF run.id IS NULL THEN RETURN admissions.evaluate_application(p_app, 'SYSTEM', p_actor); END IF;
    IF run.stale THEN RETURN admissions.evaluate_application(p_app, 'DATA_CHANGE', p_actor); END IF;
    IF pol_id IS DISTINCT FROM run.policy_id OR pol_ver IS DISTINCT FROM run.rules_version THEN RETURN admissions.evaluate_application(p_app, 'POLICY_CHANGE', p_actor); END IF;
    RETURN run.id;
END $$;

-- ── 7 · the record changing marks the evaluation stale; a re-read refreshes it ─

CREATE OR REPLACE FUNCTION admissions.eligibility_touched()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r record; v_session text; v_key text; v_cand uuid;
BEGIN
    r := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    CASE TG_TABLE_NAME
        WHEN 'olevel_sitting' THEN v_session := r.session; v_key := r.jamb_key;
        WHEN 'olevel_grade' THEN SELECT st.session, st.jamb_key INTO v_session, v_key FROM admissions.olevel_sitting st WHERE st.id = r.sitting_id;
        WHEN 'caps_row' THEN v_session := r.session; v_key := r.jamb_key;
        WHEN 'de_award' THEN v_session := r.session; v_key := r.jamb_key;
        WHEN 'de_award_subject' THEN SELECT a.session, a.jamb_key INTO v_session, v_key FROM admissions.de_award a WHERE a.id = r.award_id;
        WHEN 'candidate' THEN v_cand := r.id;
        ELSE RETURN NULL;
    END CASE;
    IF v_cand IS NOT NULL THEN
        UPDATE admissions.eligibility_run SET stale = true WHERE candidate_id = v_cand AND superseded_at IS NULL AND NOT stale;
    ELSIF v_session IS NOT NULL AND v_key IS NOT NULL THEN
        UPDATE admissions.eligibility_run SET stale = true WHERE session = v_session AND jamb_key = upper(btrim(v_key)) AND superseded_at IS NULL AND NOT stale;
    END IF;
    RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_eligibility_touched ON admissions.olevel_sitting;
CREATE TRIGGER trg_eligibility_touched AFTER INSERT OR UPDATE OR DELETE ON admissions.olevel_sitting FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_touched();
DROP TRIGGER IF EXISTS trg_eligibility_touched ON admissions.olevel_grade;
CREATE TRIGGER trg_eligibility_touched AFTER INSERT OR UPDATE OR DELETE ON admissions.olevel_grade FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_touched();
DROP TRIGGER IF EXISTS trg_eligibility_touched ON admissions.caps_row;
CREATE TRIGGER trg_eligibility_touched AFTER UPDATE OF raw, aggregate, withdrawn ON admissions.caps_row FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_touched();
DROP TRIGGER IF EXISTS trg_eligibility_touched ON admissions.de_award;
CREATE TRIGGER trg_eligibility_touched AFTER INSERT OR UPDATE OR DELETE ON admissions.de_award FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_touched();
DROP TRIGGER IF EXISTS trg_eligibility_touched ON admissions.de_award_subject;
CREATE TRIGGER trg_eligibility_touched AFTER INSERT OR UPDATE OR DELETE ON admissions.de_award_subject FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_touched();
DROP TRIGGER IF EXISTS trg_eligibility_touched ON admissions.candidate;
CREATE TRIGGER trg_eligibility_touched AFTER UPDATE OF programme, entry_mode ON admissions.candidate FOR EACH ROW EXECUTE FUNCTION admissions.eligibility_touched();

-- ── 8 · the programme change: asked for, read again, decided on the record ─

CREATE OR REPLACE FUNCTION admissions.tell_office(p_office text, p_subject text, p_body text, p_about uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT DISTINCT pe.email FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
              WHERE a.office_code = p_office AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) AND pe.email IS NOT NULL LOOP
        PERFORM platform.queue_notice('EMAIL', r.email, p_subject, p_body, 'application', p_about);
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION admissions.request_programme_change(p_app uuid, p_to text, p_note text, p_by_kind text, p_by uuid)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a admissions.application; c admissions.candidate; g ref.programme; r record; v_run uuid; v_id uuid; v_from text;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.decision_released_at IS NOT NULL THEN RAISE EXCEPTION 'the Board''s decision on this application has been released; a change of programme is a new decision of the Board' USING ERRCODE = '23514'; END IF;
    SELECT * INTO c FROM admissions.candidate WHERE id = a.candidate_id;
    SELECT * INTO g FROM ref.programme WHERE code = p_to;
    IF g.code IS NULL OR g.archived THEN RAISE EXCEPTION 'no such active programme %', p_to USING ERRCODE = '23514'; END IF;
    v_from := admissions.programme_code_of(c.programme);
    IF v_from = p_to THEN RAISE EXCEPTION 'that is the programme applied for' USING ERRCODE = '23514'; END IF;
    IF EXISTS (SELECT 1 FROM admissions.programme_change_request q WHERE q.application_id = p_app AND q.state = 'REQUESTED') THEN
        RAISE EXCEPTION 'a change of programme is already requested and awaits the Admissions Office' USING ERRCODE = '23514';
    END IF;
    -- read again now, never from a stale screen
    v_run := admissions.eligibility_current(p_app, p_by);
    SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, p_to, c.entry_mode);
    IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
        RAISE EXCEPTION 'the candidate is not eligible for %: %', g.name, array_to_string(r.reasons, '; ') USING ERRCODE = '23514',
              HINT = 'A programme is requested only when every mandatory requirement is met on the current admission policy.';
    END IF;
    INSERT INTO admissions.programme_change_request (application_id, candidate_id, session, from_programme_code, from_programme, to_programme_code, to_programme, run_id, eligibility_at_request, requested_by_kind, requested_by, note)
    VALUES (p_app, c.id, a.session, v_from, c.programme, p_to, g.name, v_run, r.result, p_by_kind, p_by, nullif(btrim(coalesce(p_note, '')), ''))
    RETURNING id INTO v_id;
    PERFORM admissions.eligibility_log(p_app, v_run, 'PROGRAMME_CHANGE_REQUESTED', p_to, r.result, 'From ' || c.programme || ' to ' || g.name || coalesce(' · ' || nullif(btrim(coalesce(p_note, '')), ''), ''));
    PERFORM admissions.notify_applicant(p_app, 'Your request to change programme has been received',
        'Your request to be considered for ' || g.name || ' in place of ' || c.programme || ' has been received and is with the Admissions Office. Your programme changes only when the Office approves; you will be told.',
        'MOAUM: your request to change to ' || g.name || ' is with the Admissions Office.');
    PERFORM admissions.tell_office('academic', 'A programme change request awaits the Admissions Office',
        'Applicant ' || c.surname || ', ' || c.other_names || ' (' || c.jamb_reg_no || ') asks to move from ' || c.programme || ' to ' || g.name || '; the engine finds them ' || lower(replace(r.result, '_', ' ')) || '. Open Programme eligibility on the admissions desk to decide.', p_app);
    RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION admissions.decide_programme_change(p_req uuid, p_decision text, p_note text, p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE q admissions.programme_change_request; a admissions.application; c admissions.candidate; r record; v_note text := nullif(btrim(coalesce(p_note, '')), '');
BEGIN
    SELECT * INTO q FROM admissions.programme_change_request WHERE id = p_req FOR UPDATE;
    IF q.id IS NULL THEN RAISE EXCEPTION 'no such request' USING ERRCODE = '23503'; END IF;
    IF q.state <> 'REQUESTED' THEN RAISE EXCEPTION 'the request is already %', lower(q.state) USING ERRCODE = '23514'; END IF;
    SELECT * INTO a FROM admissions.application WHERE id = q.application_id;
    SELECT * INTO c FROM admissions.candidate WHERE id = q.candidate_id;
    IF p_decision = 'REJECT' THEN
        IF v_note IS NULL THEN RAISE EXCEPTION 'a rejection carries its reason' USING ERRCODE = '23514'; END IF;
        UPDATE admissions.programme_change_request SET state = 'REJECTED', decided_at = now(), decided_by = p_actor, decision_note = v_note WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_REJECTED', q.to_programme_code, NULL, v_note);
        PERFORM admissions.notify_applicant(q.application_id, 'Your request to change programme was not approved', 'Your request to move to ' || q.to_programme || ' was not approved by the Admissions Office. Reason: ' || v_note || ' Your application for ' || q.from_programme || ' stands as it was.', NULL);
        RETURN 'REJECTED';
    ELSIF p_decision = 'APPROVE' THEN
        IF a.decision_released_at IS NOT NULL THEN RAISE EXCEPTION 'the Board''s decision has been released; the programme is not changed under it' USING ERRCODE = '23514'; END IF;
        -- eligibility read again at the moment of decision
        SELECT * INTO r FROM admissions.evaluate_programme(a.session, c.jamb_key, q.to_programme_code, c.entry_mode);
        IF r.result NOT IN ('ELIGIBLE', 'ELIGIBLE_SCREENING') THEN
            RAISE EXCEPTION 'on the current settings the candidate is no longer eligible for %: %', q.to_programme, array_to_string(r.reasons, '; ') USING ERRCODE = '23514';
        END IF;
        UPDATE admissions.candidate SET programme = q.to_programme WHERE id = c.id;
        UPDATE admissions.programme_change_request SET state = 'APPROVED', decided_at = now(), decided_by = p_actor, decision_note = v_note, eligibility_at_decision = r.result WHERE id = q.id;
        PERFORM admissions.eligibility_log(q.application_id, q.run_id, 'PROGRAMME_CHANGE_APPROVED', q.to_programme_code, r.result, 'From ' || q.from_programme || ' to ' || q.to_programme || coalesce(' · ' || v_note, ''));
        PERFORM admissions.evaluate_application(q.application_id, 'PROGRAMME_CHANGE', p_actor);
        PERFORM admissions.notify_applicant(q.application_id, 'Your programme has been changed to ' || q.to_programme,
            'The Admissions Office has approved your request: your application is now for ' || q.to_programme || ' (' || r.result || ' on the current admission policy). This is not an offer of admission; the Admissions Board decides in the normal way.' || coalesce(' Note: ' || v_note, ''),
            'MOAUM: your application is now for ' || q.to_programme || '. This is not yet an offer of admission.');
        RETURN 'APPROVED';
    ELSE
        RAISE EXCEPTION 'unknown decision %', p_decision USING ERRCODE = '23514';
    END IF;
END $$;

-- ── 9 · what the desk reads ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admissions.eligibility_stats(p_session text)
RETURNS TABLE (evaluated bigint, eligible bigint, eligible_screening bigint, not_eligible bigint, unverified bigint, with_alternatives bigint, without_alternatives bigint, change_requests_open bigint)
LANGUAGE sql STABLE AS $$
    SELECT count(*), count(*) FILTER (WHERE applied_result = 'ELIGIBLE'), count(*) FILTER (WHERE applied_result = 'ELIGIBLE_SCREENING'),
           count(*) FILTER (WHERE applied_result = 'NOT_ELIGIBLE'), count(*) FILTER (WHERE applied_result = 'UNVERIFIED'),
           count(*) FILTER (WHERE applied_result = 'NOT_ELIGIBLE' AND alternatives > 0), count(*) FILTER (WHERE applied_result = 'NOT_ELIGIBLE' AND alternatives = 0),
           (SELECT count(*) FROM admissions.programme_change_request q WHERE q.session = p_session AND q.state = 'REQUESTED')
      FROM admissions.eligibility_run r WHERE r.session = p_session AND r.superseded_at IS NULL;
$$;

-- ── grants ────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON admissions.subject_equivalence, admissions.eligibility_run, admissions.eligibility_result, admissions.eligibility_event, admissions.programme_change_request TO app_admissions;
GRANT SELECT ON admissions.subject_equivalence, admissions.eligibility_run, admissions.eligibility_result, admissions.eligibility_event, admissions.programme_change_request TO app_auditor;

COMMIT;
