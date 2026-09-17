-- ===========================================================================
-- V162 - name the semester a fee payment covers (First / Second / Full session)
--
--   A payment is made against the session's balance, not tagged to a semester,
--   so a receipt could only say "Full session". But a student may pay in two
--   instalments — first semester, then second — and each receipt should say
--   which. Infer it from the per-semester due and where this payment falls in
--   the run of the student's confirmed school-fees payments:
--
--     · a legacy label that already names the semester wins;
--     · a single payment that clears the whole session at once  -> Full session;
--     · a payment whose cumulative range sits within semester 1  -> First Semester;
--     · one that sits within semester 2                          -> Second Semester;
--     · one that spans both                                      -> Full session.
--
--   Read-only; nothing is stored on the payment.
-- ===========================================================================

BEGIN;

CREATE OR REPLACE FUNCTION finance.payment_term(p_ref uuid)
RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE r record; sem1 numeric; total numeric; prior numeric; tol numeric := 1;
BEGIN
    SELECT pr.student_id, pr.session, pr.amount, pr.purpose, pr.confirmed_at, pr.generated_at
      INTO r FROM finance.payment_reference pr WHERE pr.id = p_ref;
    IF r.student_id IS NULL OR coalesce(r.purpose, '') NOT ILIKE 'School fees%' THEN
        RETURN NULL;                                  -- not a school-fees payment (e.g. acceptance)
    END IF;

    -- a legacy purpose that already names the semester is authoritative
    IF r.purpose ~* 'semester\s*1' THEN RETURN 'First Semester'; END IF;
    IF r.purpose ~* 'semester\s*2' THEN RETURN 'Second Semester'; END IF;
    IF r.purpose ~* 'semester\s*3' THEN RETURN 'Third Semester'; END IF;

    sem1  := coalesce(finance.due_for_semester(r.student_id, r.session, 1), 0);
    total := coalesce((SELECT due FROM finance.position(r.student_id, r.session)), 0);

    -- confirmed school-fees paid before this one (ordered by when it confirmed, then minted)
    SELECT coalesce(sum(pr2.amount), 0) INTO prior
      FROM finance.payment_reference pr2
     WHERE pr2.student_id = r.student_id AND pr2.session = r.session
       AND pr2.purpose ILIKE 'School fees%' AND pr2.confirmed_at IS NOT NULL AND pr2.id <> p_ref
       AND (pr2.confirmed_at, pr2.generated_at, pr2.id)
           < (coalesce(r.confirmed_at, r.generated_at), r.generated_at, p_ref);

    IF prior <= tol AND r.amount >= total - tol THEN RETURN 'Full session'; END IF;
    IF prior + r.amount <= sem1 + tol THEN RETURN 'First Semester'; END IF;
    IF prior >= sem1 - tol THEN RETURN 'Second Semester'; END IF;
    RETURN 'Full session';                            -- one payment spanning both semesters
END $$;

COMMENT ON FUNCTION finance.payment_term(uuid) IS
'The semester a fee payment covers, for the receipt: First/Second/Third Semester, or Full session '
'(a single payment that clears the whole session). Inferred from the per-semester due and the run '
'of confirmed school-fees payments; a legacy purpose that names the semester wins. Read-only.';

COMMIT;
