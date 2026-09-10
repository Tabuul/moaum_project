-- ═══════════════════════════════════════════════════════════════════════════
-- V074 — appraisal and promotion eligibility
--
--   Promotion eligibility is computed, not argued. Years on the current grade
--   are derived from the last promotion the record holds (or the appointment),
--   so the committee sees the same figure every candidate sees. The appraisal
--   record (APER grade, publications, the self and supervisor scores) is captured
--   per cycle; the minimum-years rule is checked from the record, not asserted.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE hrm.appraisal (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    employment_id    uuid NOT NULL REFERENCES hrm.employment(id),
    person_id        uuid NOT NULL REFERENCES iam.person(id),
    cycle            text NOT NULL,
    self_score       int NULL,
    supervisor_score int NULL,
    aper_grade       text NULL,
    publications     int NULL,
    note             text NULL,
    state            text NOT NULL DEFAULT 'SELF',
    updated_at       timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_ap_state CHECK (state IN ('SELF','SUPERVISOR','MODERATED')),
    CONSTRAINT ck_ap_grade CHECK (aper_grade IS NULL OR aper_grade IN ('A','B','C','D','E')),
    CONSTRAINT ck_ap_scores CHECK ((self_score IS NULL OR self_score BETWEEN 0 AND 100) AND (supervisor_score IS NULL OR supervisor_score BETWEEN 0 AND 100)),
    CONSTRAINT uq_ap_person_cycle UNIQUE (person_id, cycle)
);
CREATE INDEX ix_ap_cycle ON hrm.appraisal (cycle);
SELECT audit.attach('hrm.appraisal');

-- the promotion picture for a cycle: years on grade computed from the record,
-- the appraisal captured beside it, and the minimum-years rule checked
CREATE OR REPLACE FUNCTION hrm.promotion_view(p_cycle text)
RETURNS TABLE (person_id uuid, name text, staff_no text, grade text, step int, category text,
               on_grade_since date, years_on_grade numeric, aper_grade text, publications int,
               self_score int, supervisor_score int, appraisal_state text, eligible_years boolean)
LANGUAGE sql STABLE AS $$
    SELECT em.person_id, p.surname || ', ' || p.given_names, em.staff_no, em.grade, em.step, em.category,
           since.d,
           round((current_date - since.d) / 365.25, 1),
           ap.aper_grade, ap.publications, ap.self_score, ap.supervisor_score,
           coalesce(ap.state, 'SELF'),
           (current_date - since.d) >= 3 * 365
      FROM hrm.employment em
      JOIN iam.person p ON p.id = em.person_id
      LEFT JOIN hrm.appraisal ap ON ap.person_id = em.person_id AND ap.cycle = p_cycle
      CROSS JOIN LATERAL (
          SELECT coalesce(
              (SELECT max(m.effective_date) FROM hrm.movement m
                WHERE m.employment_id = em.id AND m.state = 'IMPLEMENTED' AND m.kind IN ('PROMOTION','UPGRADING','CONVERSION')),
              em.appointment_date) AS d
      ) since
     WHERE em.status = 'ACTIVE'
     ORDER BY em.category, em.grade DESC, p.surname
$$;

COMMIT;
