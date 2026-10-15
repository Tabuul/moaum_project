-- ═══════════════════════════════════════
-- V479 — The Post-UTME paid applicants report
--
--   The Academic Office, the Registry and the Directorate of ICT — and a Dean or a Head of Department within their own
--   faculty or department — list and download the candidates whose Post-UTME application fee is paid. The rules are held
--   here once, so the list, the figures above it and every download read the same set:
--
--     · a Post-UTME applicant is an application of the session on the applicant stack that is not the Centre for
--       Continuing Education's (CCE) nor a Preliminary programme's — UTME and Direct Entry candidates alike;
--     · PAID (verified) is an APPLICATION fee reference confirmed by the payment service (admissions.fee_reference.
--       confirmed_at). A Bursary reversal (V420) clears that confirmation, so a reversed payment is not paid; a reference
--       never confirmed is pending; a checking or acceptance fee never makes an applicant paid. One row an application,
--       however many attempts it took: the first confirmed reference is the payment shown, and the attempts are counted;
--     · the programme is the one the candidate applied for (admissions.candidate.programme), matched to its record for the
--       faculty and department exactly as the screening desk matches it (admissions.programme_code_of);
--     · the UTME aggregate is JAMB's, from the CAPS record of the candidate's session, as the merit list reads it (V384), or
--       the aggregate stored on the candidate; nothing is computed. A Direct Entry candidate sat no UTME. The gender is the
--       candidate's, else JAMB's on the same CAPS record;
--     · the contacts are the applicant account's; the placeholders the old portal's applicants came over with (V168:
--       '<jamb>@migrate.moau.local', '00000000000') are not contacts and read as missing;
--     · what is missing is listed on the row (no JAMB number, programme not matched, gender, phone, e-mail, UTME aggregate),
--       never a reason to leave the row out.
--
--   admissions.report_export records each download — who, when, which report and session, the format, the filters and the
--   number of rows — on the audit spine.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'academic', true),
       set_config('moaum.reason', 'V479: the Post-UTME paid applicants report', true);

CREATE FUNCTION admissions.post_utme_paid_applicants(p_session text)
RETURNS TABLE(application_id uuid, application_no text, session text, jamb_reg_no text, surname text, other_names text, full_name text,
              programme text, programme_code text, faculty_code text, faculty text, dept_code text, department text,
              sex text, entry_mode text, utme_aggregate integer, phone text, email text,
              payment_status text, paid_at timestamptz, payment_reference text, receipt_no text, channel text, amount numeric,
              verified_payments integer, missing text[])
LANGUAGE sql STABLE AS $$
    SELECT a.id, a.application_no, a.session, nullif(btrim(c.jamb_reg_no), ''), c.surname, c.other_names,
           upper(btrim(c.surname)) || coalesce(', ' || nullif(btrim(c.other_names), ''), ''),
           c.programme, p.code, f.code, f.name, d.code, d.name,
           coalesce(c.sex, x.sex), c.entry_mode, coalesce(x.aggregate, c.utme_aggregate),
           ct.phone, ct.email,
           CASE WHEN pay.first_id IS NOT NULL THEN 'VERIFIED'
                WHEN EXISTS (SELECT 1 FROM admissions.fee_reversal v WHERE v.application_id = a.id AND v.kind = 'APPLICATION') THEN 'REVERSED'
                WHEN EXISTS (SELECT 1 FROM admissions.fee_reference r WHERE r.application_id = a.id AND r.kind = 'APPLICATION') THEN 'PENDING'
                ELSE 'NOT_STARTED' END,
           pay.paid_at, pay.reference, pay.receipt_no, pay.channel, pay.amount, coalesce(pay.n, 0),
           array_remove(ARRAY[
               CASE WHEN nullif(btrim(c.jamb_reg_no), '') IS NULL THEN 'JAMB_NUMBER' END,
               CASE WHEN p.code IS NULL THEN 'PROGRAMME_NOT_MATCHED' END,
               CASE WHEN coalesce(c.sex, x.sex) IS NULL THEN 'GENDER' END,
               CASE WHEN ct.phone IS NULL THEN 'PHONE' END,
               CASE WHEN ct.email IS NULL THEN 'EMAIL' END,
               CASE WHEN c.entry_mode = 'UTME' AND coalesce(x.aggregate, c.utme_aggregate) IS NULL THEN 'UTME_AGGREGATE' END], NULL)
      FROM admissions.application a
      JOIN admissions.candidate c ON c.id = a.candidate_id
      JOIN admissions.applicant_account acc ON acc.id = a.account_id
      -- the programme the candidate applied for, matched by name as admissions.programme_code_of matches it (one map, joined once)
      LEFT JOIN (SELECT DISTINCT ON (g.name) g.name, g.code FROM ref.programme g ORDER BY g.name, g.archived, g.code) pm ON pm.name = c.programme
      LEFT JOIN ref.programme p ON p.code = pm.code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      LEFT JOIN ref.department d ON d.code = p.dept_code
      LEFT JOIN admissions.caps_row_live x ON x.session = a.session AND x.jamb_reg_no = c.jamb_reg_no
      -- the old portal's applicants came over with placeholder contacts where it had none (V168): they are not contacts
      CROSS JOIN LATERAL (SELECT CASE WHEN btrim(coalesce(acc.phone, '')) IN ('', '00000000000') THEN NULL ELSE btrim(acc.phone) END AS phone,
                                 CASE WHEN btrim(coalesce(acc.email, '')) = '' OR acc.email ILIKE '%@migrate.moau.local' THEN NULL ELSE btrim(acc.email) END AS email) ct
      LEFT JOIN LATERAL (
          SELECT (array_agg(r.id ORDER BY r.confirmed_at, r.id))[1] AS first_id, min(r.confirmed_at) AS paid_at,
                 (array_agg(r.reference ORDER BY r.confirmed_at, r.id))[1] AS reference,
                 (array_agg(r.receipt_no ORDER BY r.confirmed_at, r.id))[1] AS receipt_no,
                 (array_agg(r.channel ORDER BY r.confirmed_at, r.id))[1] AS channel,
                 (array_agg(r.amount ORDER BY r.confirmed_at, r.id))[1] AS amount,
                 count(*)::int AS n
            FROM admissions.fee_reference r
           WHERE r.application_id = a.id AND r.kind = 'APPLICATION' AND r.confirmed_at IS NOT NULL
          HAVING count(*) > 0) pay ON true
     WHERE a.session = p_session
       AND c.entry_mode NOT IN ('CCE', 'PRELIMINARY');
$$;
COMMENT ON FUNCTION admissions.post_utme_paid_applicants(text) IS
  'V479: every Post-UTME application of a session (UTME and Direct Entry; not CCE, not Preliminary), one row each, with its payment status — VERIFIED (an APPLICATION fee reference confirmed by the payment service), REVERSED (reversed by the Bursary), PENDING (references, none confirmed) or NOT_STARTED — the first confirmed payment, JAMB''s UTME aggregate as the merit list reads it, and what is missing';

CREATE TABLE admissions.report_export (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report      text NOT NULL CHECK (report ~ '^[A-Z][A-Z0-9_]{2,60}$'),
    session     text NULL,
    format      text NOT NULL CHECK (format IN ('XLSX', 'PDF')),
    filters     jsonb NOT NULL DEFAULT '{}'::jsonb,
    row_count   integer NOT NULL CHECK (row_count >= 0),
    exported_by uuid NULL,
    office      text NULL REFERENCES ref.office (code),
    exported_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_report_export_report ON admissions.report_export (report, exported_at DESC);
COMMENT ON TABLE admissions.report_export IS
  'V479: each download of an admissions report — the report, the session, the format, the filters, the rows and who took it — kept on the audit spine';
SELECT audit.attach('admissions.report_export');

COMMIT;
