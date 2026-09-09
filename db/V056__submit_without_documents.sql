-- ═══════════════════════════════════════════════════════════════════════════
-- V056 — an application submits without uploaded documents
--
--   The University's decision is that the applicant no longer uploads scanned
--   documents at application: originals are seen at Registry clearance, and
--   results are verified directly with the examination bodies. So the submit
--   no longer requires the five documents, nor blocks on a rejected one. The
--   application fee and the next of kin are still required, and everything
--   else in the journey is unchanged. Documents may still be uploaded (the
--   passport photograph is used for the screening slip and the identity card),
--   they are simply not a condition of submitting.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION admissions.submit_application(p_app uuid, p_ip text)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE a admissions.application;
BEGIN
    SELECT * INTO a FROM admissions.application WHERE id = p_app;
    IF NOT FOUND THEN RAISE EXCEPTION 'no such application' USING ERRCODE = '23503'; END IF;
    IF a.submitted_at IS NOT NULL THEN RETURN 'already submitted'; END IF;
    IF a.fee_confirmed_at IS NULL THEN
        RAISE EXCEPTION 'the form opens when the application fee is confirmed' USING ERRCODE = '23514',
            HINT = 'Pay against the reference this portal generated; a gateway payment confirms itself.';
    END IF;
    IF a.next_of_kin IS NULL OR btrim(a.next_of_kin) = '' THEN
        RAISE EXCEPTION 'the next of kin is not given' USING ERRCODE = '23514', HINT = 'Name and phone number of your next of kin, under Biodata.';
    END IF;
    -- documents are no longer a condition of submitting (V056): originals are seen at
    -- clearance and results are verified with the examination bodies.
    UPDATE admissions.application SET submitted_at = now(), declaration_ip = p_ip WHERE id = p_app;
    RETURN 'submitted';
END $$;
