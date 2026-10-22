-- V629: the JAMB list upload merges with the list already held (the University's word of 22 October 2026: "always skip the ones
-- that are already uploaded, but if there's an update, change the update — the candidate may change a programme/course from
-- the JAMB portal — … then upload the new ones found on the list"). The CAPS download is cumulative: each week's file repeats
-- every candidate already loaded, so loading it failed on uq_caps_row_per_session (a second live row for one JAMB number).
-- Now the loader (CapsIntakeService) reads each candidate against the session's live list first:
--   · on it and the same — the course, aggregate, names, sex, state, LGA and subject scores — skipped (rows_unchanged);
--   · on it and changed by JAMB — updated in place, the row keeping its list and its commitment; what changed is kept here,
--     field by field, with the upload that carried it (rows_updated). The eligibility engine re-reads it (trg_eligibility_touched);
--   · not on it — added to the new list as before, under the load cut-off.
-- The database still refuses a second live row for a candidate (check.sql §29); nothing here relaxes it.
BEGIN;

CREATE TABLE admissions.caps_row_change (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session        text        NOT NULL,
    row_id         uuid        NOT NULL REFERENCES admissions.caps_row (id),
    jamb_key       text        NOT NULL,
    batch_id       uuid        NOT NULL REFERENCES admissions.caps_batch (id),
    changes        jsonb       NOT NULL CHECK (jsonb_typeof(changes) = 'object' AND changes <> '{}'::jsonb),
    changed_at     timestamptz NOT NULL DEFAULT now(),
    changed_by     uuid,
    changed_office text
);
COMMENT ON TABLE admissions.caps_row_change IS
  'V629: a candidate already on the session''s live JAMB list whom a later upload carried changed — each field as it was and as it became ({field: {from, to}}), the upload (batch) that carried it, who and when. The row itself is updated in place.';
CREATE INDEX ix_caps_row_change_row ON admissions.caps_row_change (row_id, changed_at DESC);
CREATE INDEX ix_caps_row_change_session ON admissions.caps_row_change (session, changed_at DESC);
SELECT audit.attach('admissions.caps_row_change');

ALTER TABLE admissions.caps_batch ADD COLUMN IF NOT EXISTS rows_updated int NOT NULL DEFAULT 0;
ALTER TABLE admissions.caps_batch ADD COLUMN IF NOT EXISTS rows_unchanged int NOT NULL DEFAULT 0;
COMMENT ON COLUMN admissions.caps_batch.rows_updated IS 'V629: candidates already on the live list whom this upload carried changed, updated in place';
COMMENT ON COLUMN admissions.caps_batch.rows_unchanged IS 'V629: candidates already on the live list whom this upload carried the same, skipped';

COMMIT;
