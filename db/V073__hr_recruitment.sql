-- ═══════════════════════════════════════════════════════════════════════════
-- V073 — recruitment
--
--   The University advertises a post, receives applications, scores them against
--   the advertised criteria, shortlists, interviews and makes an offer. The
--   office records each stage; the shortlist is scored, not argued. An applicant
--   who does not meet an advertised minimum cannot be shortlisted past it.
--   Every act is attributed; nothing is deleted, a post is closed or cancelled.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE hrm.vacancy (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title         text NOT NULL,
    department    text NOT NULL,
    requirements  text NOT NULL,
    grade         text NULL,
    category      text NULL,
    opened_on     date NOT NULL DEFAULT current_date,
    closes_on     date NULL,
    state         text NOT NULL DEFAULT 'OPEN',
    note          text NULL,
    CONSTRAINT ck_vac_state CHECK (state IN ('OPEN','SHORTLISTING','INTERVIEW','OFFER','CLOSED','CANCELLED')),
    CONSTRAINT ck_vac_category CHECK (category IS NULL OR category IN ('ACADEMIC','NON_ACADEMIC')),
    CONSTRAINT ck_vac_title CHECK (btrim(title) <> '')
);
CREATE INDEX ix_vac_state ON hrm.vacancy (state, opened_on DESC);
SELECT audit.attach('hrm.vacancy');

CREATE TABLE hrm.applicant (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    vacancy_id     uuid NOT NULL REFERENCES hrm.vacancy(id),
    name           text NOT NULL,
    email          text NULL,
    phone          text NULL,
    qualification  text NULL,
    publications   int NULL,
    teaching_years numeric(4,1) NULL,
    score          int NULL,
    recommendation text NULL,
    state          text NOT NULL DEFAULT 'APPLIED',
    applied_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_app_state CHECK (state IN ('APPLIED','SHORTLISTED','RESERVE','REJECTED','INVITED','OFFERED','DECLINED','APPOINTED')),
    CONSTRAINT ck_app_name CHECK (btrim(name) <> ''),
    CONSTRAINT ck_app_score CHECK (score IS NULL OR score BETWEEN 0 AND 100)
);
CREATE INDEX ix_app_vacancy ON hrm.applicant (vacancy_id, score DESC NULLS LAST);
SELECT audit.attach('hrm.applicant');

COMMIT;
