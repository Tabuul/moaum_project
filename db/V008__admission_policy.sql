-- ════════════════════════════════════════════════════════════════════════
--  V008  ·  ADMISSION POLICY, PER SESSION
--
--  Built 7 September 2026 from GUIDELINES FOR THE 2025/2026 UNDERGRADUATE
--  ADMISSIONS, Office of the Registrar (Academic Office), issued by the
--  Deputy Registrar, Academic Office, as Secretary of the Central
--  Admissions Committee for the Acting Vice-Chancellor as Chairman.
--
--  ── What this is for ────────────────────────────────────────────────────
--  Every year the Central Admissions Committee issues that document, and
--  every year the numbers in it change: the NUC quota, the faculty
--  distribution, the cut-off marks, sometimes a programme's subject
--  combination. Today those numbers live in a Word file, are read by
--  twelve Deans and some fifty Heads of Department, and are applied by
--  hand. Nothing in the University can state, for a candidate admitted
--  three years ago, which cut-off was in force when she was admitted.
--
--  So the policy is DATA, not code, and it is EFFECTIVE-DATED. A session's
--  settings are made, checked, and then put in force by an instrument --
--  the Committee's own minute. Nothing may be changed once a session is
--  in force; a correction is a new version citing the minute that made it,
--  and the old one remains readable for as long as anybody admitted under
--  it is alive.
--
--  ── It fails closed ─────────────────────────────────────────────────────
--  admissions.policy_in_force() raises when a session has no policy. It
--  does not fall back to last year's numbers. Last year's quota applied to
--  this year's candidates is how a university over-admits by nine hundred
--  and finds out at accreditation.
--
--  ── The checks the document itself demands ──────────────────────────────
--  · the four selection criteria must total 100% (NM 10 + SM 35 +
--    ELG 30 + Locality 25)
--  · the faculty quotas must total the NUC approved quota, exactly. The
--    2024/2025 column in the guidelines totals 9,271, which is the stated
--    total to the unit. The 2025/2026 column is EMPTY against a stated
--    total of 10,198: the Deans had not yet distributed it. A session
--    cannot go in force with 10,198 places and nowhere to put them.
--  · the score weighting must total 100% (UTME 70 + Post-UTME 30)
--  · every programme admitted into must have a rule
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── the session's own settings ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admissions.session_policy (
    id              uuid PRIMARY KEY,
    session         text NOT NULL,
    -- The NUC approved quota, which is the carrying capacity. Everything
    -- else is a distribution of this one number.
    nuc_quota       int  NOT NULL,

    -- 2.6 · the aggregate score. The guidelines say 70/30, and any other
    -- pair of numbers ranks a different set of candidates. Stored, not
    -- assumed, because it is exactly the sort of thing that changes.
    weight_utme     int  NOT NULL,
    weight_putme    int  NOT NULL,

    -- 1.0(v) · UTME:DE. 80:20 for all programmes; the guidelines carry a
    -- parenthesis about Education which is ambiguous on its face and is
    -- recorded as an open question rather than guessed at (see the
    -- finding below).
    ratio_utme      int  NOT NULL DEFAULT 80,
    ratio_de        int  NOT NULL DEFAULT 20,

    -- 1.0(vi) · Science:Arts
    ratio_science   int  NOT NULL DEFAULT 60,
    ratio_arts      int  NOT NULL DEFAULT 40,

    -- 2.11 · "Recommendations on the basis of ELG must not exceed 50%"
    elg_cap_pct     int  NOT NULL DEFAULT 50,
    -- 2.5 · "Departments are to make 80% recommendations for (UTME) merit"
    dept_share_pct  int  NOT NULL DEFAULT 80,
    -- 2.5 · index programmes: six from Preliminary, two per Senatorial Zone
    index_prelim_places  int NOT NULL DEFAULT 6,
    index_per_zone       int NOT NULL DEFAULT 2,

    -- 2.8 · only the Most Preferred First list; 2.7 · only candidates who
    -- passed the University's own screening. Both are switches because
    -- both are the sort of rule that gets quietly relaxed in a bad year,
    -- and a switch leaves a record of who relaxed it.
    mpf_only        boolean NOT NULL DEFAULT true,
    screening_required boolean NOT NULL DEFAULT true,

    -- the Committee's minute. Nothing is in force without one.
    instrument      text NULL,
    in_force        tstzrange NULL,
    state           text NOT NULL DEFAULT 'DRAFT',

    CONSTRAINT uq_policy_session UNIQUE (session),
    CONSTRAINT ck_policy_state CHECK (state IN ('DRAFT','IN_FORCE','SUPERSEDED')),
    CONSTRAINT ck_policy_weights CHECK (weight_utme + weight_putme = 100),
    CONSTRAINT ck_policy_utmede  CHECK (ratio_utme + ratio_de = 100),
    CONSTRAINT ck_policy_sciarts CHECK (ratio_science + ratio_arts = 100),
    CONSTRAINT ck_policy_quota   CHECK (nuc_quota > 0),
    CONSTRAINT ck_policy_pct CHECK (elg_cap_pct BETWEEN 0 AND 100
                                AND dept_share_pct BETWEEN 0 AND 100),
    -- an instrument is what makes it real
    CONSTRAINT ck_policy_force CHECK (
        state <> 'IN_FORCE' OR (instrument IS NOT NULL AND btrim(instrument) <> ''
                                AND in_force IS NOT NULL))
);

-- ── 2.4 · the four selection criteria ──────────────────────────────────
CREATE TABLE IF NOT EXISTS admissions.selection_criterion (
    policy_id   uuid NOT NULL REFERENCES admissions.session_policy(id),
    criterion   text NOT NULL,
    percent     int  NOT NULL,
    PRIMARY KEY (policy_id, criterion),
    CONSTRAINT ck_crit_name CHECK (criterion IN
        ('NATIONAL_MERIT','STATE_MERIT','ELG','LOCALITY')),
    CONSTRAINT ck_crit_pct CHECK (percent BETWEEN 0 AND 100)
);

-- ── 2.3 · the faculty quota, and 2.13 · the faculty cut-off ────────────
CREATE TABLE IF NOT EXISTS admissions.faculty_quota (
    policy_id     uuid NOT NULL REFERENCES admissions.session_policy(id),
    faculty_code  text NOT NULL REFERENCES ref.faculty(code),
    quota         int  NULL,          -- NULL means the Dean has not distributed yet
    cutoff        int  NULL,
    PRIMARY KEY (policy_id, faculty_code),
    CONSTRAINT ck_fq_quota  CHECK (quota IS NULL OR quota >= 0),
    -- 400 is the UTME maximum; a cut-off above it admits nobody, and a
    -- cut-off of 0 is not a cut-off
    CONSTRAINT ck_fq_cutoff CHECK (cutoff IS NULL OR cutoff BETWEEN 1 AND 400)
);

-- ── the programme rule ─────────────────────────────────────────────────
-- One row per programme per session. A programme with no row cannot be
-- admitted into: that is the point, not an omission to work around.
CREATE TABLE IF NOT EXISTS admissions.programme_rule (
    policy_id      uuid NOT NULL REFERENCES admissions.session_policy(id),
    programme_code text NOT NULL REFERENCES ref.programme(code),
    -- 2.13 · a programme may carry its own cut-off above its faculty's:
    -- MBBS 220 inside a College whose others are 180, Computer Science
    -- 180 inside a Faculty of Science at 160.
    cutoff         int  NULL,
    olevel_credits int  NOT NULL DEFAULT 5,
    olevel_sittings int NOT NULL DEFAULT 2,
    -- the words as the guidelines print them, kept verbatim beside the
    -- structured form: a Head of Department checks the sentence, and the
    -- selection engine reads the structure
    olevel_text    text NOT NULL,
    utme_text      text NOT NULL,
    de_text        text NOT NULL,
    PRIMARY KEY (policy_id, programme_code),
    CONSTRAINT ck_pr_cutoff CHECK (cutoff IS NULL OR cutoff BETWEEN 1 AND 400),
    CONSTRAINT ck_pr_credits CHECK (olevel_credits BETWEEN 1 AND 9)
);

-- ── the subject combination, structured ────────────────────────────────
-- "Mathematics, Physics and any one of Chemistry, Geography, Fine Arts or
-- Technical Drawing" is not a list. It is two mandatory subjects and a
-- choice of one from four, and a system that stores it as a sentence
-- cannot check a candidate against it.
CREATE TABLE IF NOT EXISTS admissions.rule_subject_group (
    id             uuid PRIMARY KEY,
    policy_id      uuid NOT NULL,
    programme_code text NOT NULL,
    scope          text NOT NULL,      -- UTME | OLEVEL
    choose         int  NOT NULL,      -- how many of this group are needed
    -- a credit for O'Level; for UTME the subject is simply sat
    min_grade      text NULL,
    FOREIGN KEY (policy_id, programme_code)
        REFERENCES admissions.programme_rule(policy_id, programme_code),
    CONSTRAINT ck_grp_scope CHECK (scope IN ('UTME','OLEVEL')),
    CONSTRAINT ck_grp_choose CHECK (choose >= 1)
);

CREATE TABLE IF NOT EXISTS admissions.rule_subject (
    group_id  uuid NOT NULL REFERENCES admissions.rule_subject_group(id),
    subject   text NOT NULL,
    PRIMARY KEY (group_id, subject)
);

-- ── the checks, stated in words ────────────────────────────────────────
-- Returns one row per thing wrong with a session's settings. Empty means
-- the session may be put in force. The screen shows this list; nothing is
-- reported as "invalid" without saying which rule and by how much.
CREATE OR REPLACE FUNCTION admissions.policy_findings(p_session text)
RETURNS TABLE (finding text, detail text, owner text)
LANGUAGE sql
STABLE
AS $$
    WITH pol AS (SELECT * FROM admissions.session_policy WHERE session = p_session)
    -- the four criteria
    SELECT 'The selection criteria do not total 100%'::text,
           'National Merit, State Merit, Equality of Local Government and '
           'Locality total ' || coalesce(sum(c.percent), 0) || '%. The guidelines '
           'set 10 + 35 + 30 + 25.',
           'Central Admissions Committee'::text
      FROM pol p LEFT JOIN admissions.selection_criterion c ON c.policy_id = p.id
     GROUP BY p.id
    HAVING coalesce(sum(c.percent), 0) <> 100
  UNION ALL
    -- the quota distribution, to the unit
    SELECT 'The faculty quotas do not total the NUC approved quota'::text,
           'Distributed ' || coalesce(sum(f.quota), 0) || ' of ' || p.nuc_quota ||
           '. ' || abs(p.nuc_quota - coalesce(sum(f.quota), 0))::text ||
           CASE WHEN coalesce(sum(f.quota), 0) < p.nuc_quota
                THEN ' places are unallocated.' ELSE ' places over the capacity.' END,
           'Deans of Faculties'::text
      FROM pol p LEFT JOIN admissions.faculty_quota f ON f.policy_id = p.id
     GROUP BY p.id, p.nuc_quota
    HAVING coalesce(sum(f.quota), 0) <> p.nuc_quota
  UNION ALL
    -- a faculty with no cut-off admits on no rule at all
    SELECT 'A faculty has no UTME cut-off'::text,
           string_agg(f.faculty_code, ', ' ORDER BY f.faculty_code) ||
           ' — a faculty with no cut-off admits on no rule at all.',
           'Central Admissions Committee'::text
      FROM pol p JOIN admissions.faculty_quota f ON f.policy_id = p.id
     WHERE f.cutoff IS NULL
     GROUP BY p.id
  UNION ALL
    -- a programme the University runs with nothing said about it
    SELECT 'Programmes with no admission rule for this session'::text,
           count(*)::text || ' of ' ||
           (SELECT count(*) FROM ref.programme)::text ||
           ' programmes have no O''Level requirement, no UTME subject '
           'combination and no Direct Entry rule. Nobody may be admitted '
           'into them until Senate states one.',
           'Deans and Heads of Department'::text
      FROM pol p, ref.programme g
     WHERE NOT EXISTS (SELECT 1 FROM admissions.programme_rule r
                        WHERE r.policy_id = p.id AND r.programme_code = g.code)
     GROUP BY p.id
    HAVING count(*) > 0
  UNION ALL
    -- a programme cut-off below its own faculty's is not a cut-off
    SELECT 'A programme cut-off is below its faculty''s'::text,
           string_agg(r.programme_code || ' at ' || r.cutoff || ' under ' ||
                      g.faculty_code || ' at ' || f.cutoff, '; '),
           'Central Admissions Committee'::text
      FROM pol p
      JOIN admissions.programme_rule r ON r.policy_id = p.id
      JOIN ref.programme g ON g.code = r.programme_code
      JOIN admissions.faculty_quota f ON f.policy_id = p.id
                                     AND f.faculty_code = g.faculty_code
     WHERE r.cutoff IS NOT NULL AND f.cutoff IS NOT NULL AND r.cutoff < f.cutoff
     GROUP BY p.id
$$;

-- ── putting it in force ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.put_in_force(p_session text, p_instrument text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE v_n int; v_first text;
BEGIN
    IF p_instrument IS NULL OR btrim(p_instrument) = '' THEN
        RAISE EXCEPTION 'admission settings for % cannot be put in force without '
                        'citing the Central Admissions Committee minute that '
                        'approved them', p_session
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT count(*), min(finding) INTO v_n, v_first
      FROM admissions.policy_findings(p_session);

    IF v_n > 0 THEN
        RAISE EXCEPTION 'admission settings for % are not complete: % finding(s), '
                        'the first being "%"', p_session, v_n, v_first
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE admissions.session_policy
       SET state = 'IN_FORCE', instrument = p_instrument,
           in_force = tstzrange(now(), NULL)
     WHERE session = p_session;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'no admission settings exist for %', p_session
            USING ERRCODE = 'no_data_found';
    END IF;
END;
$$;

-- ── reading it back · FAILS CLOSED ─────────────────────────────────────
CREATE OR REPLACE FUNCTION admissions.policy_in_force(p_session text)
RETURNS admissions.session_policy
LANGUAGE plpgsql
STABLE
AS $$
DECLARE r admissions.session_policy;
BEGIN
    SELECT * INTO r FROM admissions.session_policy
     WHERE session = p_session AND state = 'IN_FORCE';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no admission settings are in force for % — nothing may be '
                        'admitted, ranked or cut off until the Central Admissions '
                        'Committee''s settings for this session are in force',
                        p_session
            USING ERRCODE = 'no_data_found';
    END IF;
    RETURN r;
END;
$$;

-- ── 2.6 · the aggregate, computed from the session's own weighting ─────
-- UTME is out of 400 and Post-UTME out of 100, so the UTME score is
-- scaled before it is weighted. Adding 247 to 68.5 is not an aggregate.
CREATE OR REPLACE FUNCTION admissions.aggregate_score(
    p_session text, p_utme int, p_putme numeric)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE p admissions.session_policy;
BEGIN
    p := admissions.policy_in_force(p_session);
    IF p_utme IS NULL OR p_putme IS NULL THEN
        RETURN NULL;                     -- absent is not zero
    END IF;
    RETURN round((p_utme / 400.0 * 100.0) * p.weight_utme / 100.0
               + p_putme * p.weight_putme / 100.0, 2);
END;
$$;

-- ── the cut-off that actually applies to a candidate ───────────────────
-- The programme's own if it has one, otherwise the faculty's. Resolved
-- here rather than in each of the twenty-nine modules that will ask.
CREATE OR REPLACE FUNCTION admissions.cutoff_for(p_session text, p_programme text)
RETURNS int
LANGUAGE plpgsql
STABLE
AS $$
DECLARE v int; p admissions.session_policy;
BEGIN
    p := admissions.policy_in_force(p_session);
    SELECT coalesce(r.cutoff, f.cutoff) INTO v
      FROM ref.programme g
      LEFT JOIN admissions.programme_rule r
             ON r.policy_id = p.id AND r.programme_code = g.code
      LEFT JOIN admissions.faculty_quota f
             ON f.policy_id = p.id AND f.faculty_code = g.faculty_code
     WHERE g.code = p_programme;

    IF v IS NULL THEN
        RAISE EXCEPTION 'no UTME cut-off is set for % in % — neither the programme '
                        'nor its faculty carries one', p_programme, p_session
            USING ERRCODE = 'no_data_found';
    END IF;
    RETURN v;
END;
$$;

SELECT audit.attach('admissions.session_policy');
SELECT audit.attach('admissions.faculty_quota');
SELECT audit.attach('admissions.programme_rule');

SELECT audit.exempt('admissions.selection_criterion',
    'Four rows written with the policy row they belong to and audited as part '
    'of it; the policy is the act.');
SELECT audit.exempt('admissions.rule_subject_group',
    'The structured form of the sentence in programme_rule.utme_text, which is '
    'audited. The sentence is the decision; this is its parse.');
SELECT audit.exempt('admissions.rule_subject',
    'Subject names inside a group. See rule_subject_group.');

GRANT SELECT, INSERT, UPDATE ON admissions.session_policy,
      admissions.selection_criterion, admissions.faculty_quota,
      admissions.programme_rule, admissions.rule_subject_group,
      admissions.rule_subject TO app_admissions;
GRANT SELECT ON admissions.session_policy, admissions.selection_criterion,
      admissions.faculty_quota, admissions.programme_rule,
      admissions.rule_subject_group, admissions.rule_subject TO app_auditor;

COMMIT;
