-- ═══════════════════════════════════════════════════════════════════════════
-- V226 — the faculty vets a postgraduate application after the department
--
--   The postgraduate admission flow gains a faculty stage. An application is
--   recommended by the department (the HOD's committee), then vetted by the
--   faculty (the Dean), and only then decided by the School of Postgraduate
--   Studies. So: SUBMITTED → DEPT_RECOMMENDED → FAC_RECOMMENDED → OFFERED. This
--   adds the faculty decision columns and act, and makes the School decide after
--   the faculty rather than straight after the department.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'academic', true);
SELECT set_config('moaum.reason', 'PG faculty vetting stage (V226)', true);

-- ── 1 · the faculty decision columns, and the two new states ─────────────────
ALTER TABLE admissions.pg_application ADD COLUMN IF NOT EXISTS fac_decided_at timestamptz NULL;
ALTER TABLE admissions.pg_application ADD COLUMN IF NOT EXISTS fac_decided_by uuid NULL REFERENCES iam.person(id);
ALTER TABLE admissions.pg_application ADD COLUMN IF NOT EXISTS fac_note text NULL;

ALTER TABLE admissions.pg_application DROP CONSTRAINT IF EXISTS ck_pg_app_state;
ALTER TABLE admissions.pg_application ADD  CONSTRAINT ck_pg_app_state CHECK (state IN
    ('DRAFT','SUBMITTED','DEPT_RECOMMENDED','DEPT_DECLINED','FAC_RECOMMENDED','FAC_DECLINED',
     'OFFERED','NOT_OFFERED','ACCEPTED','ADMITTED'));

-- ── 2 · the faculty recommends (or declines) an application the department recommended ──
CREATE OR REPLACE FUNCTION admissions.pg_faculty_decide(p_application uuid, p_recommend boolean, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    SELECT state INTO v_state FROM admissions.pg_application WHERE id = p_application;
    IF v_state IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF v_state <> 'DEPT_RECOMMENDED' THEN
        RAISE EXCEPTION 'the faculty decides after the department recommends, not on an application at %', v_state;
    END IF;
    UPDATE admissions.pg_application
       SET state = CASE WHEN p_recommend THEN 'FAC_RECOMMENDED' ELSE 'FAC_DECLINED' END,
           fac_decided_at = now(), fac_decided_by = p_actor, fac_note = nullif(btrim(p_note), '')
     WHERE id = p_application;
END;
$$;

-- ── 3 · the School decides after the faculty has recommended ─────────────────
CREATE OR REPLACE FUNCTION admissions.pg_spgs_decide(p_application uuid, p_offer boolean, p_note text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text;
BEGIN
    SELECT state INTO v_state FROM admissions.pg_application WHERE id = p_application;
    IF v_state IS NULL THEN RAISE EXCEPTION 'no such postgraduate application'; END IF;
    IF v_state <> 'FAC_RECOMMENDED' THEN
        RAISE EXCEPTION 'the School decides after the faculty, not on an application at %', v_state;
    END IF;
    UPDATE admissions.pg_application
       SET state = CASE WHEN p_offer THEN 'OFFERED' ELSE 'NOT_OFFERED' END,
           spgs_decided_at = now(), spgs_decided_by = p_actor, spgs_note = nullif(btrim(p_note), '')
     WHERE id = p_application;
END;
$$;

COMMIT;
