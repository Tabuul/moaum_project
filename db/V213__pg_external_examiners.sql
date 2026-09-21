-- ═══════════════════════════════════════════════════════════════════════════
-- V213 — external examiners of the Postgraduate School (Policy 18)
--
--   The Board approves external examiners on a department's recommendation
--   through the Faculty Postgraduate Committee; the Secretary issues the
--   appointment letters. A Master's examiner normally serves three years; PhD
--   examiners are approved by specialization. This is the roster of those
--   institution-level appointments (distinct from the per-candidate panel of
--   V212). Attached to the audit spine.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE admissions.pg_examiner (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name         text NOT NULL,
    institution  text NOT NULL,
    field        text NULL,
    tenure_from  date NULL,
    tenure_to    date NULL,
    active       boolean NOT NULL DEFAULT true,
    appointed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_pg_examiner_active ON admissions.pg_examiner (name) WHERE active;
SELECT audit.attach('admissions.pg_examiner');

COMMIT;
