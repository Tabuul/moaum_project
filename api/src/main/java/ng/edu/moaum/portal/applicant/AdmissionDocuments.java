package ng.edu.moaum.portal.applicant;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.shared.NotFound;

/**
 * The documents of one admission, in one place (V282): the offer / confirmation letter (V275), the
 * receipts of the admission checking and acceptance fees, the screening forms (V280) and the
 * school-fees receipts once the person is on the register. Each row is read from the table that
 * owns the document — the credential store, the fee references, the payment references — with
 * the state that store gives it: PENDING (not yet available, and after what), AVAILABLE (may be
 * opened; generated on first opening), GENERATED, DOWNLOADED, PRINTED (from the document's own
 * trail), REPLACED, REVOKED, or NOT_ISSUED (a screening that was not successful).
 * <p>
 * The same rows are served to the applicant and, after the register has them, to the student
 * the applicant has become: one account, one set of documents, two doors.
 */
@Component
public class AdmissionDocuments {

    private final JdbcClient jdbc;

    AdmissionDocuments(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the application behind a student, when the student came through the admission lifecycle */
    public UUID applicationOfStudent(UUID student) {
        return jdbc.sql("""
                SELECT ap.id FROM admissions.application ap JOIN people.student s ON s.candidate_id = ap.candidate_id
                 WHERE s.id = :s ORDER BY ap.submitted_at DESC NULLS LAST, ap.id LIMIT 1
                """).param("s", student).query(UUID.class).optional().orElseThrow(() -> new NotFound("admission record for student", student));
    }

    public List<Map<String, Object>> centre(UUID app) {
        Map<String, Object> a = jdbc.sql("""
                SELECT a.id, a.session, a.accepted_at, a.acceptance_confirmed_at, a.decision, a.decision_released_at, a.cleared_at,
                       admissions.screening_required(a.id) AS screening_required,
                       coalesce((SELECT f.checking_fee FROM admissions.applicant_fee_rule(a.session) f), 0) AS checking_fee,
                       coalesce((SELECT k.decision_visible FROM admissions.status_checking(a.id) k), false) AS decision_visible,
                       s.id AS student_id, s.matric_no, sf.state AS screening_state, sf.screening_no
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN people.student s ON s.candidate_id = c.id
                  LEFT JOIN admissions.screening_form sf ON sf.application_id = a.id
                 WHERE a.id = :a
                """).param("a", app).query().singleRow();
        // an offer shows here only once Admission Status Checking lets the applicant read it (V295): the rows say nothing before
        boolean offered = "OFFERED".equals(a.get("decision")) && a.get("decision_released_at") != null && Boolean.TRUE.equals(a.get("decision_visible"));
        boolean accepted = a.get("accepted_at") != null;
        List<Map<String, Object>> rows = new ArrayList<>();

        // 1 · the offer / confirmation letter: a numbered document once the acceptance settles, a version per approved change of programme
        Map<String, Object> letter = issued(app, "ADMISSION_LETTER");
        rows.add(row("OFFER_LETTER", "ADMISSION", "Offer / confirmation letter",
                accepted ? (letter == null ? "AVAILABLE" : stateOf(letter)) : "PENDING",
                accepted ? null : offered ? "after the acceptance fee" : "after an offer of admission",
                letter, null, accepted ? "letter" : null));

        // 2 · the receipts of the fees paid to accept: the admission checking fee where the session charges one, the acceptance fee
        Map<String, Object> checking = feeReference(app, "CHECKING");
        if (checking != null || ((Number) a.get("checking_fee")).doubleValue() > 0) {
            rows.add(row("CHECKING_RECEIPT", "ACCEPTANCE", "Admission checking fee receipt",
                    checking != null ? "AVAILABLE" : "PENDING", checking != null ? null : "after the admission checking fee", null, checking,
                    checking != null ? "receipt:" + checking.get("reference") : null));
        }
        Map<String, Object> acceptance = feeReference(app, "ACCEPTANCE");
        rows.add(row("ACCEPTANCE_RECEIPT", "ACCEPTANCE", "Acceptance fee receipt",
                acceptance != null ? "AVAILABLE" : "PENDING", acceptance != null ? null : "after the acceptance fee", null, acceptance,
                acceptance != null ? "receipt:" + acceptance.get("reference") : null));

        // 3 · the official screening forms: generated from the record when the University's screening is successful
        if (Boolean.TRUE.equals(a.get("screening_required"))) {
            String scr = a.get("screening_state") == null ? null : String.valueOf(a.get("screening_state"));
            Map<String, Object> forms = "SUCCESSFUL".equals(scr) ? issued(app, "SCREENING_FORMS") : null;
            String status = "SUCCESSFUL".equals(scr) ? (forms == null ? "AVAILABLE" : stateOf(forms)) : "UNSUCCESSFUL".equals(scr) ? "NOT_ISSUED" : "PENDING";
            rows.add(row("SCREENING_FORMS", "SCREENING", "Screening forms", status,
                    "SUCCESSFUL".equals(scr) ? null : "UNSUCCESSFUL".equals(scr) ? "not issued: the screening was not successful" : "after successful screening",
                    forms, null, "SUCCESSFUL".equals(scr) ? "forms" : null));
        }

        // 4 · the school-fees receipts, once the person is on the register and has paid
        List<Map<String, Object>> receipts = a.get("student_id") == null ? List.of() : jdbc.sql("""
                SELECT reference, receipt_no, amount, confirmed_at, session, purpose FROM finance.payment_reference
                 WHERE student_id = :s AND confirmed_at IS NOT NULL ORDER BY confirmed_at
                """).param("s", a.get("student_id"), Types.OTHER).query().listOfRows();
        if (receipts.isEmpty()) {
            if (offered) rows.add(row("SCHOOL_FEES_RECEIPT", "FEES", "School fees receipt", "PENDING", "after school fees", null, null, null));
        } else {
            int n = 0;
            for (Map<String, Object> r : receipts) {
                n++;
                rows.add(row("SCHOOL_FEES_RECEIPT" + (n == 1 ? "" : "_" + n), "FEES", "School fees receipt" + (receipts.size() > 1 ? " · " + r.get("session") : ""),
                        "AVAILABLE", null, null, r, "fees-receipt:" + r.get("reference")));
            }
        }
        return rows;
    }

    /** the letter as the applicant's page and the student's library open it: the document, and the application it states */
    public Map<String, Object> letter(UUID app, String event) {
        Map<String, Object> row = jdbc.sql("SELECT id, number, version, verification_code, statement::text AS statement, issued_on, supersedes FROM admissions.issue_admission_letter(:a)").param("a", app).query().singleRow();
        log(row.get("id"), event, "Offer letter");
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.remove("id");
        out.put("verifyPath", "/verify/document?key=" + row.get("verification_code"));
        out.put("application", jdbc.sql("""
                SELECT a.application_no AS "applicationNo", a.session, c.surname || ', ' || c.other_names AS name, c.surname, c.other_names AS "otherNames",
                       c.jamb_reg_no AS "jambKey", c.entry_level AS "entryLevel",
                       coalesce(q.to_programme, c.programme) AS programme, f.name AS faculty, d.name AS department, p.category AS "degreeType",
                       -- the duration in semesters from the programme's final level (100 → 400 is eight); eight when the level is not stated
                       coalesce((finance.final_level(p.code) - c.entry_level) / 100 + 1, 4) * 2 AS "durationSemesters",
                       -- the first semester's registration date for the session, as the calendar states it
                       coalesce((SELECT sm.registration_opens FROM policy.semester sm WHERE sm.session = a.session AND sm.number = 1),
                                (SELECT sm.lectures_from FROM policy.semester sm WHERE sm.session = a.session AND sm.number = 1),
                                (SELECT s.starts_on FROM policy.academic_session s WHERE s.name = a.session)) AS "registrationOpens",
                       a.decision, a.decision_released_at AS "decisionReleasedAt", a.decision_basis AS "decisionBasis", a.accepted_at AS "acceptedAt"
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN LATERAL (SELECT x.to_programme FROM admissions.programme_change_request x WHERE x.application_id = a.id AND x.state = 'APPROVED' ORDER BY x.decided_at DESC LIMIT 1) q ON true
                  LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(coalesce(q.to_programme, c.programme))
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE a.id = :a
                """).param("a", app).query().singleRow());
        // the wording, the signatory and the notes: the active ADMISSION_LETTER template (V283), a new version from Document settings
        out.put("template", jdbc.sql("SELECT title, subtitle, signatory_name, signatory_title, second_name, second_title, footer, remarks FROM credentials.document_template WHERE kind = 'ADMISSION_LETTER' AND active ORDER BY version DESC LIMIT 1")
                .query().listOfRows().stream().findFirst().orElse(null));
        return out;
    }

    /** the screening forms of a successful screening (V280), each opening on the document's trail */
    public Map<String, Object> forms(UUID app, String event) {
        Map<String, Object> row = jdbc.sql("SELECT id, number, version, verification_code, statement::text AS statement, issued_on FROM admissions.issue_screening_forms(:a)").param("a", app).query().singleRow();
        log(row.get("id"), event, "Screening forms");
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.remove("id");
        out.put("verifyPath", "/verify/document?key=" + row.get("verification_code"));
        return out;
    }

    /** the receipt of an admission fee (checking or acceptance), with the payer as the application names them */
    public Map<String, Object> receipt(UUID app, String reference) {
        return jdbc.sql("""
                SELECT fr.reference, fr.kind, fr.amount, fr.confirmed_at, fr.receipt_no, fr.channel, fr.generated_at,
                       a.application_no, a.session, c.surname, c.other_names, c.jamb_reg_no, c.programme
                  FROM admissions.fee_reference fr JOIN admissions.application a ON a.id = fr.application_id JOIN admissions.candidate c ON c.id = a.candidate_id
                 WHERE fr.application_id = :a AND fr.reference = :r AND fr.confirmed_at IS NOT NULL
                """).param("a", app).param("r", reference).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("receipt", reference));
    }

    /* ── the parts ── */

    private Map<String, Object> issued(UUID app, String kind) {
        return jdbc.sql("""
                SELECT i.id, i.number, i.version, i.verification_code, i.issued_on, credentials.document_status(i.id) AS status,
                       EXISTS (SELECT 1 FROM credentials.event e WHERE e.issued_id = i.id AND e.action = 'DOWNLOADED') AS downloaded,
                       EXISTS (SELECT 1 FROM credentials.event e WHERE e.issued_id = i.id AND e.action = 'PRINTED') AS printed
                  FROM credentials.issued i WHERE i.application_id = :a AND i.kind = :k ORDER BY i.version DESC, i.issued_at DESC LIMIT 1
                """).param("a", app).param("k", kind).query().listOfRows().stream().findFirst().orElse(null);
    }

    private static String stateOf(Map<String, Object> doc) {
        String status = String.valueOf(doc.get("status"));
        if ("REVOKED".equals(status)) return "REVOKED";
        if ("REPLACED".equals(status)) return "REPLACED";
        if (Boolean.TRUE.equals(doc.get("printed"))) return "PRINTED";
        if (Boolean.TRUE.equals(doc.get("downloaded"))) return "DOWNLOADED";
        return "GENERATED";
    }

    private Map<String, Object> feeReference(UUID app, String kind) {
        return jdbc.sql("SELECT reference, receipt_no, amount, confirmed_at, channel FROM admissions.fee_reference WHERE application_id = :a AND kind = :k AND confirmed_at IS NOT NULL ORDER BY confirmed_at DESC LIMIT 1")
                .param("a", app).param("k", kind).query().listOfRows().stream().findFirst().orElse(null);
    }

    private void log(Object issuedId, String event, String what) {
        String action = "PRINTED".equalsIgnoreCase(event) ? "PRINTED" : "DOWNLOADED";
        jdbc.sql("SELECT credentials.log(NULL, :i, NULL, :act, 'AVAILABLE', :act, :n)").param("i", issuedId, Types.OTHER).param("act", action)
                .param("n", what + (action.equals("PRINTED") ? " printed" : " opened") + " by the holder").query().listOfRows();
    }

    private static Map<String, Object> row(String key, String group, String title, String status, String availableAfter,
                                           Map<String, Object> doc, Map<String, Object> payment, String action) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("key", key);
        r.put("group", group);
        r.put("title", title);
        r.put("status", status);
        r.put("availableAfter", availableAfter);
        r.put("number", doc == null ? null : doc.get("number"));
        r.put("version", doc == null ? null : doc.get("version"));
        r.put("code", doc == null ? null : doc.get("verification_code"));
        r.put("issuedOn", doc == null ? null : doc.get("issued_on"));
        r.put("reference", payment == null ? null : payment.get("reference"));
        r.put("receiptNo", payment == null ? null : payment.get("receipt_no"));
        r.put("amount", payment == null ? null : payment.get("amount"));
        r.put("confirmedAt", payment == null ? null : payment.get("confirmed_at"));
        r.put("action", action);
        return r;
    }
}
