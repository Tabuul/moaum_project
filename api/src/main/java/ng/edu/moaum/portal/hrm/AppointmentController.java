package ng.edu.moaum.portal.hrm;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * V510: a new appointment in HR. Human Resources sets the salary grades (the Bursary may too), checks an appointment — one from the
 * form or an upload's rows — and makes it: the person (made, or linked by staff number), the establishment record and the ACTIVE
 * employment record that payroll, identity cards, the Head of Department's screen and the staff registers read. The database holds
 * every rule (hrm.set_grade, appointment_check, appointments_check, appoint, appoint_many); nothing is written by a check.
 */
@RestController
@RequestMapping("/api/v1/hr")
class AppointmentController {

    static final String READERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_super')";
    static final String APPOINTERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_super')";
    static final String GRADE_SETTERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_bursar','OFFICE_super')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    AppointmentController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    @SuppressWarnings("unchecked")
    private Object parse(String s) {
        return s == null ? null : json.readValue(s, Object.class);
    }

    /** the grades, the latest appointments, the counts and the departments and units an appointment may name */
    @GetMapping("/appointments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> overview() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("grades", jdbc.sql("""
                SELECT grade, step, category, basic, housing, transport, other_allowances, basic + housing + transport + other_allowances AS monthly,
                       (SELECT count(*) FROM hrm.employment e WHERE e.grade = g.grade AND e.step = g.step AND e.status <> 'ENDED') AS staff
                  FROM hrm.grade g ORDER BY category, grade, step
                """).query().listOfRows());
        out.put("counts", jdbc.sql("""
                SELECT count(*) FILTER (WHERE status = 'ACTIVE') AS active, count(*) FILTER (WHERE status = 'SUSPENDED') AS suspended,
                       count(*) FILTER (WHERE status = 'ENDED') AS ended,
                       (SELECT count(*) FROM iam.person p WHERE p.staff_number IS NOT NULL AND p.ended_on IS NULL
                          AND NOT EXISTS (SELECT 1 FROM hrm.employment x WHERE x.person_id = p.id AND x.status <> 'ENDED')) AS without_employment
                  FROM hrm.employment
                """).query().singleRow());
        out.put("recent", jdbc.sql("""
                SELECT e.id, e.staff_no, upper(btrim(p.surname)) || ', ' || btrim(p.given_names) AS name, e.category, e.grade, e.step, e.appointment_date, e.status,
                       sr.home_department, d.name AS department, sr.home_unit, u.name AS unit, sr.present_rank
                  FROM hrm.employment e JOIN iam.person p ON p.id = e.person_id
                  LEFT JOIN hrm.staff_record sr ON sr.person_id = p.id
                  LEFT JOIN ref.department d ON d.code = sr.home_department
                  LEFT JOIN ref.unit u ON u.code = sr.home_unit
                 ORDER BY e.appointment_date DESC, e.staff_no LIMIT 50
                """).query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        out.put("units", jdbc.sql("SELECT code, name FROM ref.unit WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        return out;
    }

    public record Rows(@NotNull @Size(min = 1, max = 2000) List<Map<String, Object>> rows) {
    }

    /** what each row would do and every reason it may not (a staff number repeated among the rows refused); writes nothing */
    @PostMapping("/appointments/check")
    @PreAuthorize(APPOINTERS)
    @Transactional(readOnly = true)
    Object check(@Valid @RequestBody Rows body) {
        return parse(jdbc.sql("SELECT hrm.appointments_check(CAST(:j AS jsonb))::text").param("j", json.writeValueAsString(body.rows())).query(String.class).single());
    }

    /** one appointment, from the form */
    @PostMapping("/appointments")
    @PreAuthorize(APPOINTERS)
    @Transactional
    Map<String, Object> appoint(@NotNull @RequestBody Map<String, Object> row) {
        UUID id = jdbc.sql("SELECT hrm.appoint(CAST(:j AS jsonb))").param("j", json.writeValueAsString(row)).query(UUID.class).single();
        return Map.of("employmentId", id);
    }

    /** an upload: the rows that pass are appointed, the rest listed with their reasons */
    @PostMapping("/appointments/upload")
    @PreAuthorize(APPOINTERS)
    @Transactional
    Object upload(@Valid @RequestBody Rows body) {
        return parse(jdbc.sql("SELECT hrm.appoint_many(CAST(:j AS jsonb))::text").param("j", json.writeValueAsString(body.rows())).query(String.class).single());
    }

    public record GradeIn(@NotBlank @Size(max = 30) String grade, @Min(1) @Max(30) int step, @NotBlank String category,
                          @NotNull @DecimalMin("0") BigDecimal basic, @DecimalMin("0") BigDecimal housing, @DecimalMin("0") BigDecimal transport,
                          @DecimalMin("0") BigDecimal other, @NotBlank @Size(min = 10, max = 500) String reason) {
    }

    /** a salary grade and step (monthly amounts), set with a reason */
    @PutMapping("/grades")
    @PreAuthorize(GRADE_SETTERS)
    @Transactional
    Map<String, Object> grade(@Valid @RequestBody GradeIn body) {
        String g = jdbc.sql("SELECT hrm.set_grade(:g, :s, :c, :b, :h, :t, :o, :r)").param("g", body.grade()).param("s", body.step()).param("c", body.category())
                .param("b", body.basic()).param("h", body.housing(), java.sql.Types.NUMERIC).param("t", body.transport(), java.sql.Types.NUMERIC).param("o", body.other(), java.sql.Types.NUMERIC).param("r", body.reason().trim())
                .query(String.class).single();
        return Map.of("grade", g);
    }
}
