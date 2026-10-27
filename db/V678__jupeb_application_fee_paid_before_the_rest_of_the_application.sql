-- ════════════════════════════════════════════════════════════════════════
--  V678 · The JUPEB application fee is paid before the rest of the application
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 27 October 2026: "JUPEB application is by-passing application fee … all pending applicants who
--  started their applications but yet to pay application fee should pay before proceeding for other registration."
--
--  Until now the guided application (V342) asked for the fee last, on the review step: a candidate signed in after applying
--  and filled the personal details, the O'Level, the documents and the programme without paying; only the submission waited
--  for the fee. Now the fee is the first step, and nothing else of the application is taken until it is confirmed:
--
--  · jupeb.step_status restated: a step FEE before PERSONAL ("The application fee is not yet paid"), the review step no
--    longer carrying it; the guided application opens on the fee while it is unpaid (current = FEE). Everything else as V342.
--  · jupeb.require_fee_first(app): JUPEB_FEE_FIRST while a draft (or an application returned for correction) has no
--    confirmed application fee. The candidate's portal calls it before saving the biodata, the O'Level, the programme and
--    combination, or a document (JupebPortalController.requireEditable). The office's and ICT Support's own acts, the
--    reading of the record, the payment itself, the password and support tickets are not held.
--  · A candidate who started before this and has not paid keeps what they entered: the portal opens on the fee step, and
--    the rest opens again the moment the fee is confirmed. Submission already needed the fee (jupeb.submit, V339).
--  Nothing on record is changed.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION jupeb.step_status(p_app uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
    WITH a AS (SELECT * FROM jupeb.application WHERE id = p_app),
    -- V678: the application fee first — the rest of the application is taken once it is confirmed
    fee AS (SELECT CASE WHEN a.fee_confirmed_at IS NULL THEN jsonb_build_array(jsonb_build_object('field', 'fee', 'message', 'The application fee is not yet paid')) ELSE '[]'::jsonb END AS problems FROM a),
    personal AS (SELECT coalesce(jsonb_agg(p) FILTER (WHERE p IS NOT NULL), '[]'::jsonb) AS problems FROM a, LATERAL unnest(ARRAY[
        CASE WHEN a.sex IS NULL THEN jsonb_build_object('field', 'sex', 'message', 'Sex is required') END,
        CASE WHEN a.date_of_birth IS NULL THEN jsonb_build_object('field', 'dob', 'message', 'Date of birth is required') END,
        CASE WHEN a.nin IS NULL THEN jsonb_build_object('field', 'nin', 'message', 'NIN is required: the eleven digits on your NIN slip') END,
        CASE WHEN a.phone IS NULL THEN jsonb_build_object('field', 'phone', 'message', 'Phone number is required') END,
        CASE WHEN a.state_of_origin IS NULL THEN jsonb_build_object('field', 'stateOfOrigin', 'message', 'State of origin is required') END,
        CASE WHEN a.lga IS NULL THEN jsonb_build_object('field', 'lga', 'message', 'Local government is required') END,
        CASE WHEN a.contact_address IS NULL THEN jsonb_build_object('field', 'contactAddress', 'message', 'Contact address is required') END,
        CASE WHEN a.next_of_kin_name IS NULL THEN jsonb_build_object('field', 'nextOfKinName', 'message', 'Next of kin''s name is required') END,
        CASE WHEN a.next_of_kin_phone IS NULL THEN jsonb_build_object('field', 'nextOfKinPhone', 'message', 'Next of kin''s phone is required') END]) p),
    olevel AS (SELECT coalesce(jsonb_agg(jsonb_build_object('field', 'olevel', 'message', upper(left(r, 1)) || substr(r, 2))), '[]'::jsonb)
                      || CASE WHEN (SELECT olevel_sittings FROM a) IS NULL THEN jsonb_build_array(jsonb_build_object('field', 'olevelSittings', 'message', 'Say whether you sat once or twice')) ELSE '[]'::jsonb END AS problems
                 FROM jupeb.olevel_check(p_app) k, LATERAL unnest(k.reasons) r),
    docs AS (SELECT coalesce(jsonb_agg(jsonb_build_object('field', 'doc:' || q.kind || coalesce(':' || q.sitting, ''), 'message', q.label || ' is not uploaded') ORDER BY q.ord, q.sitting), '[]'::jsonb) AS problems
               FROM jupeb.required_documents(p_app) q
              WHERE NOT EXISTS (SELECT 1 FROM jupeb.document d WHERE d.application_id = p_app AND d.kind = q.kind AND coalesce(d.sitting, 0) = coalesce(q.sitting, 0)
                                  AND d.status NOT IN ('REJECTED', 'REPLACEMENT_REQUIRED'))),
    prog AS (SELECT CASE WHEN a.stream IS NULL AND a.programme_code IS NULL THEN jsonb_build_array(jsonb_build_object('field', 'stream', 'message', 'Choose Science or Non-Science')) ELSE '[]'::jsonb END
                    || CASE
                        WHEN c.id IS NOT NULL AND NOT jupeb.combination_offered(c.id)
                            THEN jsonb_build_array(jsonb_build_object('field', 'combination', 'message', c.code || ' is no longer offered: choose another subject combination'))
                        WHEN c.id IS NOT NULL AND a.stream IS NOT NULL AND NOT jupeb.combination_suits(c.area, a.stream)
                            THEN jsonb_build_array(jsonb_build_object('field', 'combination', 'message', c.code || ' is not a ' || CASE a.stream WHEN 'SCIENCE' THEN 'Science' ELSE 'Non-Science' END || ' combination: choose another'))
                        WHEN c.id IS NULL AND a.stream IS NOT NULL AND EXISTS (SELECT 1 FROM jupeb.combination o WHERE jupeb.combination_offered(o.id) AND jupeb.combination_suits(o.area, a.stream))
                            THEN jsonb_build_array(jsonb_build_object('field', 'combination', 'message', 'Choose your subject combination'))
                        ELSE '[]'::jsonb END AS problems
               FROM a LEFT JOIN jupeb.combination c ON c.id = a.combination_id),
    review AS (SELECT '[]'::jsonb AS problems),
    steps AS (SELECT 0 AS n, 'FEE' AS step, problems FROM fee
              UNION ALL SELECT 1, 'PERSONAL', problems FROM personal UNION ALL SELECT 2, 'OLEVEL', problems FROM olevel
              UNION ALL SELECT 3, 'DOCUMENTS', problems FROM docs UNION ALL SELECT 4, 'PROGRAMME', problems FROM prog UNION ALL SELECT 5, 'REVIEW', problems FROM review)
    SELECT jsonb_build_object(
        'steps', jsonb_agg(jsonb_build_object('step', step, 'ok', jsonb_array_length(problems) = 0, 'problems', problems) ORDER BY n),
        'current', coalesce((SELECT step FROM steps WHERE jsonb_array_length(problems) > 0 ORDER BY n LIMIT 1), 'REVIEW'),
        'complete', bool_and(jsonb_array_length(problems) = 0))
      FROM steps
$$;
COMMENT ON FUNCTION jupeb.step_status(uuid) IS
  'V342, V678: the guided application''s steps — FEE (the application fee confirmed, first: nothing else is taken before it), PERSONAL, OLEVEL, DOCUMENTS, PROGRAMME, REVIEW — each with what is missing; current is the first incomplete step.';

CREATE OR REPLACE FUNCTION jupeb.require_fee_first(p_app uuid)
RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE a jupeb.application;
BEGIN
    SELECT * INTO a FROM jupeb.application WHERE id = p_app;
    IF a.id IS NULL THEN RAISE EXCEPTION 'no such JUPEB application' USING ERRCODE = '23503'; END IF;
    IF a.state IN ('DRAFT', 'RETURNED') AND a.fee_confirmed_at IS NULL THEN
        RAISE EXCEPTION 'JUPEB_FEE_FIRST: Pay the JUPEB application fee first. The rest of your application opens once the University confirms it.'
            USING ERRCODE = '23514',
                  HINT = 'Pay the application fee on the first step of your JUPEB application. Anything you entered before is kept. If you have paid, the portal confirms it when the payment reaches the University.';
    END IF;
END $$;
COMMENT ON FUNCTION jupeb.require_fee_first(uuid) IS
  'V678: JUPEB_FEE_FIRST while a draft (or a returned application) has no confirmed application fee — the candidate''s portal asks it before saving any step of the application.';

COMMIT;
