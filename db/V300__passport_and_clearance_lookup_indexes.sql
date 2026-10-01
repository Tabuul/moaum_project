-- Passport import (ResultsRepository.storePassport) looks a candidate up by jamb_key alone, but the only
-- index is (session, jamb_key), whose leading column the query does not supply: a scan per photo.
CREATE INDEX IF NOT EXISTS ix_candidate_jamb_key ON admissions.candidate (jamb_key);

-- ...and a student by upper(btrim(jamb_reg_no)); ix_student_upper_jamb is on upper(jamb_reg_no) only, so
-- the expression the query uses cannot use it.
CREATE INDEX IF NOT EXISTS ix_student_upper_btrim_jamb
    ON people.student (upper(btrim(jamb_reg_no))) WHERE jamb_reg_no IS NOT NULL;

-- Clearance listing (ClearanceRepository.latestStates) reads the standing decision per student and unit
-- for one purpose; ix_clr_student starts with student_id and cannot serve a read by purpose.
CREATE INDEX IF NOT EXISTS ix_clr_purpose_current
    ON clearance.item (purpose, student_id, unit, decided_at DESC) WHERE superseded_by IS NULL;
