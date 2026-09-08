-- ═══════════════════════════════════════════════════════════════════════════
-- V024 — the general UTME cut-off for loading the JAMB lists
--
-- The Academic Office asked for the loading of a CAPS list to be gated on
-- one general cut-off — say 150 — stated in the settings before the file
-- is uploaded, irrespective of faculty or programme. A candidate under it
-- is read, held back on record beside the batch (V011), and not loaded.
-- The faculty's and the programme's own cut-offs (V008) are not applied at
-- loading any more: they are the screening's, and stay there.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE admissions.load_cutoff (
    session   text PRIMARY KEY,
    cutoff    int  NOT NULL,
    stated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_load_cutoff CHECK (cutoff BETWEEN 0 AND 400)
);
SELECT audit.attach('admissions.load_cutoff');

COMMENT ON TABLE admissions.load_cutoff IS
  'The one UTME cut-off a session loads its JAMB lists under, stated before '
  'the file is uploaded. Faculty and programme cut-offs are the screening''s.';

-- the cut-off a session loads under, or nothing while none is stated
CREATE OR REPLACE FUNCTION admissions.load_cutoff_for(p_session text)
RETURNS int
LANGUAGE sql STABLE AS $$
    SELECT c.cutoff FROM admissions.load_cutoff c WHERE c.session = p_session;
$$;

COMMIT;
