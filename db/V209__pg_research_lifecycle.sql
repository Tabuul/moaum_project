-- ═══════════════════════════════════════════════════════════════════════════
-- V209 — the postgraduate research / thesis lifecycle (Phase 2)
--
--   After admission and coursework a postgraduate carries a piece of research to
--   an award: supervision, a proposal, a research seminar, registration of the
--   title, a panel of examiners, an oral defence (viva), corrections, the final
--   bound submission, the Secretary's clearance, and the School Board's
--   recommendation to Senate. This models that pipeline as one record per
--   student with a stage, the milestone dates, the supervisors, and an
--   append-only log of what happened at each step — following the University's
--   Postgraduate Policy (Sections 13–34).
--
--   The final report is a Project Report (PGD and taught Master's), a
--   Dissertation (research Master's) or a Thesis (PhD) — degree_kind, derived
--   from the programme's level and whether it is a research degree.
--
--   New tables in the admissions schema inherit the module's grants by default
--   privilege (V001), exactly as the V202 postgraduate tables do; the records
--   are attached to the audit spine, so every write is attributed.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1 · the research record, one per postgraduate student ────────────────────
CREATE TABLE admissions.pg_research (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id          uuid NOT NULL UNIQUE REFERENCES people.student(id),
    degree_kind         text NOT NULL,                 -- PROJECT · DISSERTATION · THESIS
    stage               text NOT NULL DEFAULT 'REGISTERED',
    topic               text NULL,
    -- proposal (Policy 21)
    proposal_submitted_at timestamptz NULL,
    proposal_approved_at  timestamptz NULL,
    -- research seminar and PGSR (Policy 22)
    seminar_held_at     timestamptz NULL,
    pgsr                text NULL,                      -- the Postgraduate School Representative / their report note
    -- registration of title and plagiarism (Policy 23)
    title_registered_at timestamptz NULL,
    plagiarism_pct      numeric(5,2) NULL,
    -- panel of examiners (Policy 24) and draft (Policy 25/26)
    panel_constituted_at timestamptz NULL,
    draft_submitted_at  timestamptz NULL,
    -- oral defence / viva (Policy 27)
    viva_held_at        timestamptz NULL,
    viva_score          numeric(5,2) NULL,
    viva_grade          text NULL,                      -- A · B · C · F
    viva_outcome        text NULL,                      -- PASS_CLEAN · PASS_MINOR · PASS_MAJOR · SECOND_ORAL · FAIL
    -- corrections (Policy 29) and final submission (Policy 31/32)
    corrections_due     date NULL,
    final_submitted_at  timestamptz NULL,
    cleared_at          timestamptz NULL,               -- the Secretary's clearance before binding
    -- award (Policy 34)
    award_recommended_at timestamptz NULL,              -- School Board → Senate
    awarded_at          timestamptz NULL,               -- Senate approval
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_research_kind CHECK (degree_kind IN ('PROJECT','DISSERTATION','THESIS')),
    CONSTRAINT ck_pg_research_stage CHECK (stage IN (
        'REGISTERED','SUPERVISED','PROPOSAL_SUBMITTED','PROPOSAL_APPROVED','SEMINAR_HELD',
        'TITLE_REGISTERED','PANEL_CONSTITUTED','DRAFT_SUBMITTED','VIVA_HELD','CORRECTIONS',
        'FINAL_SUBMITTED','CLEARED','AWARD_RECOMMENDED','AWARDED','WITHDRAWN')),
    CONSTRAINT ck_pg_research_viva CHECK (viva_outcome IS NULL OR viva_outcome IN
        ('PASS_CLEAN','PASS_MINOR','PASS_MAJOR','SECOND_ORAL','FAIL')),
    CONSTRAINT ck_pg_research_grade CHECK (viva_grade IS NULL OR viva_grade IN ('A','B','C','F')),
    CONSTRAINT ck_pg_research_plag CHECK (plagiarism_pct IS NULL OR plagiarism_pct BETWEEN 0 AND 100)
);
CREATE INDEX ix_pg_research_stage ON admissions.pg_research (stage);
SELECT audit.attach('admissions.pg_research');

-- ── 2 · the supervisors assigned to a candidate (Policy 14) ──────────────────
CREATE TABLE admissions.pg_research_supervisor (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    research_id  uuid NOT NULL REFERENCES admissions.pg_research(id) ON DELETE CASCADE,
    person_id    uuid NULL REFERENCES iam.person(id),      -- an internal supervisor on the register
    name         text NOT NULL,                            -- the name as it should read (internal or external)
    role         text NOT NULL DEFAULT 'FIRST',            -- FIRST · SECOND · CO
    is_external  boolean NOT NULL DEFAULT false,
    assigned_at  timestamptz NOT NULL DEFAULT now(),
    ended_at     timestamptz NULL,                         -- a change of supervisor ends the old assignment (Policy 14.6)
    CONSTRAINT ck_pg_sup_role CHECK (role IN ('FIRST','SECOND','CO'))
);
CREATE INDEX ix_pg_sup_research ON admissions.pg_research_supervisor (research_id) WHERE ended_at IS NULL;
SELECT audit.attach('admissions.pg_research_supervisor');

-- ── 3 · the milestone log: what happened, when, by whom ──────────────────────
CREATE TABLE admissions.pg_research_event (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    research_id  uuid NOT NULL REFERENCES admissions.pg_research(id) ON DELETE CASCADE,
    stage        text NOT NULL,                            -- the stage entered, or the act
    note         text NULL,
    by_person    uuid NULL REFERENCES iam.person(id),
    at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pg_research_event ON admissions.pg_research_event (research_id, at DESC);
SELECT audit.attach('admissions.pg_research_event');

-- ── 4 · ensure a record exists for a postgraduate student, deriving its kind ──
CREATE OR REPLACE FUNCTION admissions.pg_research_ensure(p_student uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v_id uuid; v_level int; v_research boolean; v_kind text;
BEGIN
    SELECT id INTO v_id FROM admissions.pg_research WHERE student_id = p_student;
    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;
    SELECT s.entry_level, coalesce(g.pg_research, false)
      INTO v_level, v_research
      FROM people.student s JOIN ref.programme g ON g.code = s.programme_code
     WHERE s.id = p_student AND s.entry_mode = 'POSTGRADUATE';
    IF v_level IS NULL THEN
        RAISE EXCEPTION 'not a postgraduate student %', p_student USING ERRCODE = '23514';
    END IF;
    v_kind := CASE WHEN v_level >= 900 THEN 'THESIS'
                   WHEN v_level >= 800 AND v_research THEN 'DISSERTATION'
                   ELSE 'PROJECT' END;
    INSERT INTO admissions.pg_research (student_id, degree_kind)
    VALUES (p_student, v_kind)
    ON CONFLICT (student_id) DO NOTHING
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
        SELECT id INTO v_id FROM admissions.pg_research WHERE student_id = p_student;
    END IF;
    RETURN v_id;
END $$;

COMMIT;
