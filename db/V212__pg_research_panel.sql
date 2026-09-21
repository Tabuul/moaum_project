-- ═══════════════════════════════════════════════════════════════════════════
-- V212 — the panel of examiners for a postgraduate viva (Policy 24)
--
--   A candidate's dissertation/thesis is examined by a panel: the Head of
--   Department as chairman, the external examiner, the supervisor(s), a
--   competent internal examiner, the Postgraduate School Representative (PGSR)
--   and the Postgraduate Coordinator — six for a Master's, seven for a PhD. The
--   School records the roster here when it constitutes the panel; the viva score
--   and outcome stay on the research record (V209).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE admissions.pg_research_panel (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    research_id  uuid NOT NULL REFERENCES admissions.pg_research(id) ON DELETE CASCADE,
    name         text NOT NULL,
    role         text NOT NULL,
    is_external  boolean NOT NULL DEFAULT false,
    added_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_pg_panel_role CHECK (role IN
        ('CHAIR','EXTERNAL','SUPERVISOR','CO_SUPERVISOR','INTERNAL','PGSR','COORDINATOR'))
);
CREATE INDEX ix_pg_panel_research ON admissions.pg_research_panel (research_id);
SELECT audit.attach('admissions.pg_research_panel');

COMMIT;
