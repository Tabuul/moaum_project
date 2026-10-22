-- V630: the changes V629 keeps for a candidate on the JAMB list go with the row they describe — the fix for CI on 8110c046, where the
-- property suite's V292 check (the data reset clears every table that hangs on what it clears) found admissions.caps_row_change
-- holding admissions.caps_row and admissions.caps_batch with plain foreign keys, which platform.reset_operational_data (the
-- go-live clean slate) would trip on. A list row is never deleted in the running portal — a wrong list is withdrawn and kept — so
-- the only delete that reaches these rows is that reset, and its changes go with it.
BEGIN;
ALTER TABLE admissions.caps_row_change DROP CONSTRAINT IF EXISTS caps_row_change_row_id_fkey;
ALTER TABLE admissions.caps_row_change DROP CONSTRAINT IF EXISTS caps_row_change_batch_id_fkey;
ALTER TABLE admissions.caps_row_change
    ADD CONSTRAINT caps_row_change_row_id_fkey FOREIGN KEY (row_id) REFERENCES admissions.caps_row (id) ON DELETE CASCADE,
    ADD CONSTRAINT caps_row_change_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES admissions.caps_batch (id) ON DELETE CASCADE;
COMMIT;
