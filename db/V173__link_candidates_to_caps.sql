-- ═══════════════════════════════════════════════════════════════════════════
-- V173 — make the JAMB CAPS list the authoritative source for every candidate
--
--   Best practice: the uploaded JAMB CAPS admitted list is the main data (name,
--   sex, state, LGA, UTME aggregate and subjects); the old-portal migration only
--   CONFIRMS that an applicant applied and paid. The normal portal registration
--   already does this — register_applicant builds the candidate FROM the CAPS row
--   and sets candidate.admitted_from, so demographics flow from JAMB (the merit
--   list, screening and reports all read them through that link).
--
--   The migration importer (V167–V170) predates the CAPS upload: it created a
--   candidate straight from the old-portal file with admitted_from NULL, so those
--   applicants carry no sex/state/LGA/subjects and the merit list shows them blank.
--
--   link_candidates_to_caps reconciles the two: for a session, every candidate
--   with no CAPS link is matched to its live CAPS row by JAMB registration number
--   and admitted_from is set — so the JAMB data becomes the candidate's data. It
--   only FILLS a missing link; it never overrides one already set, and it changes
--   nothing else. Run it after the CAPS list is uploaded and committed.
--
--   Audit-light bulk (the same office action as opening registration / the
--   backfills): SECURITY DEFINER, the row trigger disabled around the one update.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION admissions.link_candidates_to_caps(p_session text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, admissions, ref
AS $$
DECLARE n int;
BEGIN
    IF nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'the reconciliation is run by a person' USING ERRCODE = '23514';
    END IF;

    ALTER TABLE admissions.candidate DISABLE TRIGGER trg_audit_admissions_candidate;
    UPDATE admissions.candidate c
       SET admitted_from = r.id
      FROM admissions.caps_row_live r
     WHERE c.session = p_session
       AND c.admitted_from IS NULL
       AND r.session = p_session
       AND upper(btrim(r.jamb_reg_no)) = upper(btrim(c.jamb_reg_no));
    GET DIAGNOSTICS n = ROW_COUNT;
    ALTER TABLE admissions.candidate ENABLE TRIGGER trg_audit_admissions_candidate;

    RETURN n;
END $$;

COMMENT ON FUNCTION admissions.link_candidates_to_caps(text) IS
'Fill candidate.admitted_from from the live CAPS row (matched by JAMB registration number) for a '
'session, so the JAMB CAPS data becomes the candidate''s demographics. Only fills a missing link; '
'never overrides. Run after the CAPS list is uploaded and committed.';

COMMIT;
