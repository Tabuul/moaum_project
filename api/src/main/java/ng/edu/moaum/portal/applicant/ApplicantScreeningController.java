package ng.edu.moaum.portal.applicant;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * The applicant's admission lifecycle (V269): the status and the tracker after the offer, and the online screening form —
 * the Registry's screening of fresh students done on the portal: personal data on the biodata catalogue, the institutions
 * attended, the O'Level results as declared beside JAMB's, the documents, the declaration; saved as a draft, submitted once
 * complete, read-only until an officer returns it. Everything under {@code /me} is the signed-in applicant's own.
 */
@RestController
class ApplicantScreeningController {

    private static final String APPLICANT = "hasAuthority('OFFICE_applicant')";
    private final JdbcClient jdbc;

    ApplicantScreeningController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private UUID myApplication(Authentication a) {
        UUID account;
        try {
            account = UUID.fromString(a.getName());
        } catch (IllegalArgumentException e) {
            throw new NotFound("application", a.getName());
        }
        return jdbc.sql("SELECT id FROM admissions.application WHERE account_id = :acc").param("acc", account).query(UUID.class).optional()
                .orElseThrow(() -> new NotFound("application for account", account));
    }

    /* ── the lifecycle: where the applicant stands and what comes next ── */

    @GetMapping("/api/v1/applicant/me/admission")
    @PreAuthorize(APPLICANT)
    @Transactional(readOnly = true)
    Map<String, Object> admission(Authentication a) {
        UUID app = myApplication(a);
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("SELECT * FROM admissions.admission_status(:a)").param("a", app).query().singleRow());
        out.put("tracker", jdbc.sql("SELECT admissions.admission_tracker(:a)::text").param("a", app).query(String.class).single());
        out.put("entitlement", jdbc.sql("SELECT * FROM admissions.acceptance_entitlement(:a)").param("a", app).query().singleRow());
        out.put("screeningRequired", jdbc.sql("SELECT admissions.screening_required(:a)").param("a", app).query(Boolean.class).single());
        boolean checkingDue = jdbc.sql("SELECT admissions.checking_due(:a)").param("a", app).query(Boolean.class).single();
        out.put("checkingDue", checkingDue);
        out.put("checkingFee", jdbc.sql("SELECT coalesce((SELECT f.checking_fee FROM admissions.application a JOIN admissions.applicant_fee_rule(a.session) f ON true WHERE a.id = :a), 0)").param("a", app).query(java.math.BigDecimal.class).single());
        out.put("checkingReference", jdbc.sql("SELECT reference FROM admissions.fee_reference WHERE application_id = :a AND kind = 'CHECKING' AND confirmed_at IS NULL AND expires_at > now() ORDER BY generated_at DESC LIMIT 1").param("a", app).query(String.class).optional().orElse(null));
        Map<String, Object> offer = jdbc.sql("""
                SELECT a.application_no, a.session, a.decision, a.decision_released_at, a.decision_basis, a.accepted_at, a.undertaking_at, a.acceptance_confirmed_at, a.cleared_at,
                       c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode, c.entry_level,
                       p.code AS programme_code, p.category AS degree_type, f.name AS faculty, d.name AS department,
                       s.id AS student_id, s.admission_no, s.matric_no, s.matriculated_at, s.status AS student_status, s.current_level,
                       (SELECT q.to_programme FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1) AS changed_to,
                       (SELECT q.from_programme FROM admissions.programme_change_request q WHERE q.application_id = a.id AND q.state = 'APPROVED' ORDER BY q.decided_at DESC LIMIT 1) AS changed_from
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme) LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN people.student s ON s.candidate_id = c.id
                 WHERE a.id = :a
                """).param("a", app).query().singleRow();
        if (checkingDue) {
            // the decision and what it names stay closed until the checking fee is confirmed
            for (String k : List.of("decision", "decision_basis", "programme", "programme_code", "degree_type", "faculty", "department", "changed_to", "changed_from")) offer.put(k, null);
        }
        out.put("offer", offer);
        return out;
    }

    /** the applicant's own reading of the released status, stamped once (V271): the step before the acceptance */
    @PostMapping("/api/v1/applicant/me/admission/checked")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> checked(Authentication a) {
        UUID app = myApplication(a);
        jdbc.sql("SELECT admissions.admission_status_checked(:a)").param("a", app).query().listOfRows();
        return admission(a);
    }

    /* ── the screening form ── */

    private Map<String, Object> form(UUID app) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("required", jdbc.sql("SELECT admissions.screening_required(:a)").param("a", app).query(Boolean.class).single());
        out.put("form", jdbc.sql("SELECT * FROM admissions.screening_form WHERE application_id = :a").param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("policy", jdbc.sql("SELECT sp.* FROM admissions.screening_policy sp JOIN admissions.application a ON a.session = sp.session WHERE a.id = :a").param("a", app).query().listOfRows().stream().findFirst().orElse(null));
        out.put("fields", jdbc.sql("SELECT field, section, label, tier, hint, wide, ord FROM ref.biodata_field ORDER BY CASE section WHEN 'personal' THEN 1 WHEN 'origin' THEN 2 WHEN 'contact' THEN 3 WHEN 'family' THEN 4 WHEN 'kin' THEN 5 WHEN 'education' THEN 6 WHEN 'health' THEN 7 ELSE 8 END, ord, label").query().listOfRows());
        out.put("answers", jdbc.sql("SELECT field, value FROM admissions.screening_answer WHERE application_id = :a").param("a", app).query().listOfRows());
        out.put("institutions", jdbc.sql("SELECT ord, name, from_year, to_year, certificate, award_year FROM admissions.screening_institution WHERE application_id = :a AND active ORDER BY ord").param("a", app).query().listOfRows());
        out.put("olevel", jdbc.sql("SELECT ord, exam_body, exam_number, exam_year, subject, grade FROM admissions.screening_olevel WHERE application_id = :a AND active ORDER BY ord").param("a", app).query().listOfRows());
        out.put("jambOlevel", jdbc.sql("""
                SELECT st.exam_body, st.exam_year, st.exam_number, g.subject, g.grade FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id
                  JOIN admissions.olevel_sitting st ON st.session = c.session AND st.jamb_key = c.jamb_key JOIN admissions.olevel_grade g ON g.sitting_id = st.id WHERE a.id = :a ORDER BY st.ord, g.subject
                """).param("a", app).query().listOfRows());
        out.put("documents", jdbc.sql("SELECT id, kind, filename, content_type, bytes, uploaded_at, status, review_note, reviewed_at FROM admissions.application_document WHERE application_id = :a ORDER BY uploaded_at DESC").param("a", app).query().listOfRows());
        out.put("missing", jdbc.sql("SELECT * FROM admissions.screening_missing(:a)").param("a", app).query().listOfRows());
        out.put("prefill", jdbc.sql("""
                SELECT c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode, a.session, a.application_no, r.sex, r.state_of_origin, r.lga, f.name AS faculty, d.name AS department,
                       (SELECT x.payload ->> 'dob' FROM admissions.attachment x WHERE x.candidate_id = c.id AND x.kind = 'DATE_OF_BIRTH' ORDER BY x.arrived_at DESC LIMIT 1) AS date_of_birth,
                       acc.email, acc.phone, a.next_of_kin
                  FROM admissions.application a JOIN admissions.candidate c ON c.id = a.candidate_id JOIN admissions.applicant_account acc ON acc.id = a.account_id
                  LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
                  LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme) LEFT JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE a.id = :a
                """).param("a", app).query().singleRow());
        out.put("events", jdbc.sql("SELECT action, detail, actor_office, at FROM admissions.screening_event WHERE application_id = :a ORDER BY at DESC").param("a", app).query().listOfRows());
        out.put("changes", jdbc.sql("SELECT id, from_programme, to_programme, state, requested_at, decided_at, decision_note FROM admissions.programme_change_request WHERE application_id = :a ORDER BY requested_at DESC").param("a", app).query().listOfRows());
        out.put("status", jdbc.sql("SELECT * FROM admissions.admission_status(:a)").param("a", app).query().singleRow());
        return out;
    }

    @GetMapping("/api/v1/applicant/me/screening")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> screening(Authentication a) {
        UUID app = myApplication(a);
        // the form opens on first sight once the offer is accepted; before that the page says so without a form
        boolean accepted = jdbc.sql("SELECT accepted_at IS NOT NULL FROM admissions.application WHERE id = :a").param("a", app).query(Boolean.class).single();
        if (accepted) {
            jdbc.sql("SELECT admissions.screening_open(:a)").param("a", app).query().singleRow();
        }
        return form(app);
    }

    public record SaveIn(Map<String, String> answers, List<Map<String, Object>> institutions, List<Map<String, Object>> olevel, String membership) {
    }

    @PutMapping("/api/v1/applicant/me/screening")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> save(Authentication a, @RequestBody SaveIn body) {
        UUID app = myApplication(a);
        String answers = body.answers() == null ? null : Json.write(body.answers());
        String institutions = body.institutions() == null ? null : Json.write(body.institutions());
        String olevel = body.olevel() == null ? null : Json.write(body.olevel());
        jdbc.sql("SELECT admissions.screening_save(:a, :ans::jsonb, :inst::jsonb, :ol::jsonb, :m)").param("a", app)
                .param("ans", answers, Types.VARCHAR).param("inst", institutions, Types.VARCHAR).param("ol", olevel, Types.VARCHAR).param("m", body.membership(), Types.VARCHAR).query().singleRow();
        return form(app);
    }

    public record SubmitIn(boolean declaration) {
    }

    @PostMapping("/api/v1/applicant/me/screening/submit")
    @PreAuthorize(APPLICANT)
    @Transactional
    Map<String, Object> submit(Authentication a, @RequestBody SubmitIn body, HttpServletRequest request) {
        UUID app = myApplication(a);
        if (!body.declaration()) {
            throw new DomainRuleViolation("SCR_DECLARATION", "The declaration was not accepted.", new DomainRuleViolation.Remedy("Read the declaration and tick that you accept it.", "You"));
        }
        jdbc.sql("SELECT admissions.screening_submit(:a, true, :ip)").param("a", app).param("ip", request.getRemoteAddr(), Types.VARCHAR).query().singleRow();
        return form(app);
    }

    /** a tiny JSON writer for the save body: strings, numbers, booleans, nulls, maps and lists — nothing else arrives */
    static final class Json {
        static String write(Object o) {
            StringBuilder b = new StringBuilder();
            write(o, b);
            return b.toString();
        }

        @SuppressWarnings("unchecked")
        private static void write(Object o, StringBuilder b) {
            if (o == null) b.append("null");
            else if (o instanceof String s) b.append('"').append(s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")).append('"');
            else if (o instanceof Number || o instanceof Boolean) b.append(o);
            else if (o instanceof Map<?, ?> m) {
                b.append('{');
                boolean first = true;
                for (Map.Entry<Object, Object> e : ((Map<Object, Object>) m).entrySet()) {
                    if (!first) b.append(',');
                    first = false;
                    write(String.valueOf(e.getKey()), b);
                    b.append(':');
                    write(e.getValue(), b);
                }
                b.append('}');
            } else if (o instanceof List<?> l) {
                b.append('[');
                boolean first = true;
                for (Object x : l) {
                    if (!first) b.append(',');
                    first = false;
                    write(x, b);
                }
                b.append(']');
            } else write(String.valueOf(o), b);
        }
    }
}
