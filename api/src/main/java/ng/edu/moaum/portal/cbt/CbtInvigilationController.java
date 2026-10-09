package ng.edu.moaum.portal.cbt;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.CheckCodes;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;
import ng.edu.moaum.portal.jupeb.JupebDocuments;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The invigilator's door (V374). The office that runs an examination names the staff who invigilate each sitting (one may be the
 * chief) and may set how late a candidate may still start on their own. An invigilator sees their sittings and, for each, the seats:
 * who has not come, who is writing and when they were last heard from, who has submitted. They mark a candidate absent (once the
 * sitting has begun, never one who has started) or admit one who came late, giving back at most the minutes lost. Every mark is the
 * database's to judge and stays on the record; who may make it is judged here, on the server — an invigilator of that sitting, or the
 * office that manages the examination. The board is read from the sitting's seats, never from the whole candidate list.
 * V375: candidates are checked in at the door — the QR on their CBT slip, scanned with the phone's own camera, opens the portal's
 * check-in page, which reads the signed code, shows the candidate's photograph and seat, and checks them in; the office may require it.
 * Incidents are recorded as they happen, and the chief invigilator files the sitting's report once it is over; the office adds to it.
 */
@RestController
@RequestMapping("/api/v1/cbt")
class CbtInvigilationController {

    private static final String MANAGERS = "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_super','OFFICE_jupeb')";
    /** the offices that read examinations (CbtExamController's readers) and so may look at a sitting's board without invigilating it */
    private static final Set<String> READ_OFFICES = Set.of("gst", "eps", "bursar", "financecontroller", "registrar", "dregistrar", "dvc", "vc", "academic", "records",
            "ict", "admin", "super", "exams", "facultyexams", "hod", "dean", "jupeb");
    /** a candidate's own token is never an invigilator's */
    private static final Set<String> CANDIDATES = Set.of("student", "applicant", "jupebstudent");

    private static final String READERS =
            "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dvc','OFFICE_vc','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_exams','OFFICE_facultyexams','OFFICE_hod','OFFICE_dean','OFFICE_jupeb')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final CheckCodes codes;
    private final StudentPortalService portal;
    private final FileObjects files;
    private final tools.jackson.databind.ObjectMapper mapper = new tools.jackson.databind.ObjectMapper();

    CbtInvigilationController(JdbcClient jdbc, OfficeScope scope, CheckCodes codes, StudentPortalService portal, FileObjects files) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.codes = codes;
        this.portal = portal;
        this.files = files;
    }

    /* ── V375: what the check-in, the incidents and the report take ── */

    public record CheckInRequiredIn(@NotNull Boolean required) {
    }

    public record CheckInIn(@Size(max = 10) String method, @Size(max = 200) String token) {
    }

    public record IncidentIn(UUID candidateId, @NotBlank @Size(max = 20) String kind, @NotBlank @Size(max = 2000) String detail, Integer minutesLost, OffsetDateTime occurredAt) {
    }

    public record ReportIn(@NotNull OffsetDateTime began, @NotNull OffsetDateTime ended, @NotNull @Size(min = 1, max = 50) List<@NotNull UUID> invigilators,
                           @Size(max = 4000) String remarks) {
    }

    public record AddendumIn(@NotBlank @Size(max = 2000) String text) {
    }

    /** who may see a sitting, and whether they mark it: one of its invigilators, the office managing it, or an office that reads examinations */
    private record Access(boolean invigilator, boolean office, boolean canMark) {
    }

    public record LateEntryIn(Integer minutes) {
    }

    public record InvigilatorIn(@NotNull UUID personId, Boolean chief) {
    }

    public record MarkIn(@Size(max = 500) String note) {
    }

    public record LateIn(@NotNull Integer minutes, @Size(max = 500) String note) {
    }

    private static AuditContext ctx() {
        return AuditContextHolder.current().orElseThrow(() -> new AccessDeniedException("Sign in first."));
    }

    private Map<String, Object> exam(UUID id) {
        return jdbc.sql("SELECT id, office, course_code, reference, title, state, late_entry_minutes FROM assessment.cbt_exam WHERE id = :e").param("e", id)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("examination", id.toString()));
    }

    /** the examination, for the office that manages it (CbtExamController's rule), within its scope */
    private Map<String, Object> managed(UUID id) {
        Map<String, Object> e = exam(id);
        CbtExamController.manage(CbtExamController.office((String) e.get("office")));
        if ("EXAMS".equals(e.get("office"))) scope.assertCourseInScope((String) e.get("course_code"));
        return e;
    }

    private Map<String, Object> sitting(UUID sitting) {
        return jdbc.sql("SELECT id, exam_id, label, venue, starts_at, ends_at, capacity FROM assessment.cbt_sitting WHERE id = :s").param("s", sitting)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("sitting", sitting.toString()));
    }

    private boolean invigilates(UUID sitting) {
        return jdbc.sql("SELECT EXISTS (SELECT 1 FROM assessment.cbt_invigilator WHERE sitting_id = :s AND person_id = :p)")
                .param("s", sitting).param("p", ctx().actorId()).query(Boolean.class).single();
    }

    /** who may mark a sitting: one of its invigilators, or the office managing its examination */
    private Map<String, Object> markable(UUID sitting) {
        Map<String, Object> s = sitting(sitting);
        if (!invigilates(sitting)) managed((UUID) s.get("exam_id"));
        return s;
    }

    /** whether the acting office manages the examination (never thrown: answered) */
    private boolean office(UUID exam) {
        try {
            managed(exam);
            return true;
        } catch (AccessDeniedException | DomainRuleViolation no) {
            return false;
        }
    }

    /** the sitting read: an invigilator of it, the office managing it, or (read only) an office that reads examinations */
    private Access access(UUID sitting, UUID examId) {
        if (invigilates(sitting)) return new Access(true, office(examId), true);
        String acting = ctx().actorOffice();
        if (!READ_OFFICES.contains(acting)) throw new AccessDeniedException("A sitting's board is for its invigilators and the office running the examination.");
        Map<String, Object> e = exam(examId);
        String o = CbtExamController.office((String) e.get("office"));
        if ("EXAMS".equals(e.get("office"))) scope.assertCourseInScope((String) e.get("course_code"));
        try {
            CbtExamController.manage(o);
            return new Access(false, true, true);
        } catch (AccessDeniedException readOnly) {
            return new Access(false, false, false);
        }
    }

    /** a slip's code read: the examination and the candidate it names, and the code the API signed for them */
    private UUID[] slip(String token) {
        String[] p = token == null ? new String[0] : token.trim().split("\\.");
        UUID exam = null;
        UUID candidate = null;
        if (p.length == 3) {
            try {
                exam = UUID.fromString(p[0]);
                candidate = UUID.fromString(p[1]);
            } catch (IllegalArgumentException unreadable) {
                exam = null;
            }
        }
        if (exam == null || candidate == null) {
            throw new DomainRuleViolation("CBT_SLIP_UNREADABLE", "That is not the code of a CBT slip.",
                    new DomainRuleViolation.Remedy("Scan the QR on the candidate's CBT slip, or find them on the sitting's board.", "You"));
        }
        if (!codes.signed(p[2], CheckCodes.Kind.CBT_SLIP, exam.toString(), candidate.toString())) {
            throw new DomainRuleViolation("CBT_SLIP_NOT_GENUINE", "The slip's code does not match: the portal did not issue it for this candidate.",
                    new DomainRuleViolation.Remedy("Check the candidate's identity another way and find them on the board; report the slip to the examining office.", "You"));
        }
        return new UUID[] {exam, candidate};
    }

    /* ── the office: late entry, the invigilators, the staff to choose from ── */

    /** how many minutes after a sitting begins a candidate may still start on their own; null = no limit (none is assumed) */
    @PutMapping("/exams/{id}/late-entry")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> lateEntry(@PathVariable UUID id, @RequestBody LateEntryIn in) {
        managed(id);
        Integer m = jdbc.sql("SELECT late_entry_minutes FROM assessment.cbt_set_late_entry(:e, :m)").param("e", id).param("m", in.minutes(), Types.INTEGER)
                .query(Integer.class).optional().orElse(null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("exam", id);
        out.put("late_entry_minutes", m);
        return out;
    }

    /** members of staff holding an office today, found by name or staff number, to name as invigilators */
    @GetMapping("/staff")
    @PreAuthorize(MANAGERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> staff(@RequestParam String q) {
        String t = q == null ? "" : q.trim().toLowerCase();
        if (t.length() < 2) return List.of();
        return jdbc.sql("""
                SELECT p.id, p.staff_number, p.surname, p.given_names, string_agg(DISTINCT o.office_code, ', ' ORDER BY o.office_code) AS offices
                  FROM iam.person p
                  JOIN iam.office_assignment o ON o.person_id = p.id AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)
                 WHERE p.ended_on IS NULL
                   AND (lower(p.surname || ' ' || p.given_names) LIKE :q OR lower(p.given_names || ' ' || p.surname) LIKE :q OR lower(coalesce(p.staff_number, '')) LIKE :q)
                 GROUP BY p.id ORDER BY p.surname, p.given_names LIMIT 20
                """).param("q", "%" + t + "%").query().listOfRows();
    }

    @PostMapping("/exams/{id}/sittings/{sitting}/invigilators")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> assign(@PathVariable UUID id, @PathVariable UUID sitting, @Valid @RequestBody InvigilatorIn in) {
        managed(id);
        if (!id.equals(sitting(sitting).get("exam_id"))) throw new NotFound("sitting", sitting.toString());
        return jdbc.sql("SELECT sitting_id, person_id, chief FROM assessment.cbt_assign_invigilator(:s, :p, :c)")
                .param("s", sitting).param("p", in.personId()).param("c", Boolean.TRUE.equals(in.chief())).query().singleRow();
    }

    @PostMapping("/exams/{id}/sittings/{sitting}/invigilators/{person}/remove")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> unassign(@PathVariable UUID id, @PathVariable UUID sitting, @PathVariable UUID person) {
        managed(id);
        if (!id.equals(sitting(sitting).get("exam_id"))) throw new NotFound("sitting", sitting.toString());
        int n = jdbc.sql("SELECT assessment.cbt_unassign_invigilator(:s, :p)").param("s", sitting).param("p", person).query(Integer.class).single();
        return Map.of("removed", n);
    }

    /* ── the invigilator ── */

    /** the sittings the signed-in member of staff invigilates: those to come, and those of the last fortnight */
    @GetMapping("/invigilation")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine() {
        AuditContext c = ctx();
        if (CANDIDATES.contains(c.actorOffice())) throw new AccessDeniedException("Invigilation is for members of staff.");
        return jdbc.sql("""
                SELECT s.id AS sitting_id, s.label, s.venue, s.starts_at, s.ends_at, s.capacity, i.chief,
                       e.id AS exam_id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, e.state, assessment.cbt_live_state(e) AS live_state,
                       e.duration_minutes, e.late_entry_minutes,
                       (SELECT count(*) FROM assessment.cbt_seat x WHERE x.sitting_id = s.id) AS seated,
                       CASE WHEN s.ends_at <= now() THEN 'ENDED' WHEN s.starts_at <= now() THEN 'NOW' ELSE 'TO_COME' END AS phase
                  FROM assessment.cbt_invigilator i
                  JOIN assessment.cbt_sitting s ON s.id = i.sitting_id
                  JOIN assessment.cbt_exam e ON e.id = s.exam_id
                  LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                 WHERE i.person_id = :me AND e.state <> 'CANCELLED' AND s.ends_at > now() - interval '14 days'
                 ORDER BY s.starts_at, s.label
                """).param("me", c.actorId()).query().listOfRows();
    }

    /** the sitting's seats as they stand: for its invigilators, the office managing it, and the offices that read examinations */
    @GetMapping("/sittings/{sitting}/board")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> board(@PathVariable UUID sitting) {
        Map<String, Object> s = sitting(sitting);
        UUID examId = (UUID) s.get("exam_id");
        Access a = access(sitting, examId);
        boolean invigilator = a.invigilator();
        boolean canMark = a.canMark();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sitting", s);
        out.put("exam", jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, e.office, e.state, assessment.cbt_live_state(e) AS live_state,
                       e.duration_minutes, e.late_entry_minutes, e.require_check_in
                  FROM assessment.cbt_exam e LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id WHERE e.id = :e
                """).param("e", examId).query().singleRow());
        out.put("now", jdbc.sql("SELECT now()").query(java.time.OffsetDateTime.class).single());
        out.put("role", invigilator ? "INVIGILATOR" : canMark ? "OFFICE" : "READER");
        out.put("canMark", canMark);
        out.put("invigilators", jdbc.sql("""
                SELECT p.id AS person_id, p.surname || ', ' || p.given_names AS name, p.staff_number, i.chief
                  FROM assessment.cbt_invigilator i JOIN iam.person p ON p.id = i.person_id WHERE i.sitting_id = :s ORDER BY i.chief DESC, p.surname
                """).param("s", sitting).query().listOfRows());
        out.put("rows", jdbc.sql("SELECT * FROM assessment.cbt_sitting_board(:s)").param("s", sitting).query().listOfRows());
        // V375: what has happened in the sitting, and whether its report is filed
        out.put("incidents", incidents(sitting));
        out.put("reportFiledAt", jdbc.sql("SELECT filed_at FROM assessment.cbt_sitting_report WHERE sitting_id = :s").param("s", sitting).query(OffsetDateTime.class).optional().orElse(null));
        return out;
    }

    private List<Map<String, Object>> incidents(UUID sitting) {
        return jdbc.sql("""
                SELECT i.id, i.kind, i.occurred_at, i.minutes_lost, i.detail, i.after_filing, i.candidate_id, i.attempt_id, i.recorded_at, i.recorded_office,
                       x.seat_no, coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no) AS number,
                       coalesce(st.surname, upper(ja.surname)) AS surname, coalesce(st.other_names, ja.first_name) AS other_names,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS recorded_by
                  FROM assessment.cbt_sitting_incident i
                  LEFT JOIN assessment.cbt_seat x ON x.sitting_id = i.sitting_id AND x.candidate_id = i.candidate_id
                  LEFT JOIN people.student st ON st.id = i.candidate_id
                  LEFT JOIN jupeb.application ja ON st.id IS NULL AND ja.id = i.candidate_id
                  LEFT JOIN iam.person p ON p.id = i.recorded_by
                 WHERE i.sitting_id = :s ORDER BY i.occurred_at, i.recorded_at
                """).param("s", sitting).query().listOfRows();
    }

    /* ── V375: check-in at the door ── */

    /** whether the office's sittings need a check-in before a candidate starts */
    @PutMapping("/exams/{id}/check-in")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> checkInRequired(@PathVariable UUID id, @Valid @RequestBody CheckInRequiredIn in) {
        managed(id);
        boolean on = jdbc.sql("SELECT require_check_in FROM assessment.cbt_set_check_in_required(:e, :r)").param("e", id).param("r", in.required()).query(Boolean.class).single();
        return Map.of("exam", id, "require_check_in", on);
    }

    /** a slip scanned at the door: the candidate it names, their seat and where they stand — for the examination's invigilators and its office */
    @GetMapping("/check-in")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> lookUp(@RequestParam String t) {
        AuditContext c = ctx();
        if (CANDIDATES.contains(c.actorOffice())) throw new AccessDeniedException("A slip is checked by the invigilator.");
        UUID[] x = slip(t);
        Map<String, Object> e = exam(x[0]);
        boolean anySitting = jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM assessment.cbt_invigilator i JOIN assessment.cbt_sitting s ON s.id = i.sitting_id WHERE s.exam_id = :e AND i.person_id = :p)
                """).param("e", x[0]).param("p", c.actorId()).query(Boolean.class).single();
        boolean office = office(x[0]);
        if (!anySitting && !office) throw new AccessDeniedException("A slip is checked by an invigilator of the examination or by the office running it.");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("exam", jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, e.require_check_in, e.late_entry_minutes
                  FROM assessment.cbt_exam e LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id WHERE e.id = :e
                """).param("e", x[0]).query().singleRow());
        out.put("candidateId", x[1]);
        out.put("token", t.trim());
        Map<String, Object> seat = jdbc.sql("""
                SELECT s.id, s.label, s.venue, s.starts_at, s.ends_at, x.seat_no
                  FROM assessment.cbt_seat x JOIN assessment.cbt_sitting s ON s.id = x.sitting_id WHERE x.exam_id = :e AND x.candidate_id = :c
                """).param("e", x[0]).param("c", x[1]).query().listOfRows().stream().findFirst().orElse(null);
        if (seat == null) {
            out.put("seated", false);
            out.put("canCheckIn", false);
            out.put("candidate", jdbc.sql("""
                    SELECT coalesce(st.matric_no, st.admission_no, ja.exam_no, ja.application_no) AS number, coalesce(st.surname, upper(ja.surname)) AS surname,
                           coalesce(st.other_names, ja.first_name || coalesce(' ' || ja.middle_name, '')) AS other_names, st.current_level AS level
                      FROM (SELECT :c::uuid AS id) k LEFT JOIN people.student st ON st.id = k.id LEFT JOIN jupeb.application ja ON st.id IS NULL AND ja.id = k.id
                    """).param("c", x[1]).query().singleRow());
            return out;
        }
        UUID sittingId = (UUID) seat.get("id");
        boolean mine = invigilates(sittingId);
        out.put("seated", true);
        out.put("sitting", seat);
        out.put("mine", mine);
        out.put("canCheckIn", mine || office);
        out.put("candidate", jdbc.sql("SELECT * FROM assessment.cbt_sitting_board(:s) b WHERE b.candidate_id = :c").param("s", sittingId).param("c", x[1]).query().singleRow());
        return out;
    }

    /** a candidate checked in: by their slip's code (SCAN, which must be theirs) or found on the board (MANUAL) */
    @PostMapping("/sittings/{sitting}/candidates/{candidate}/check-in")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> checkIn(@PathVariable UUID sitting, @PathVariable UUID candidate, @Valid @RequestBody CheckInIn in) {
        Map<String, Object> s = markable(sitting);
        String method = in.method() == null || in.method().isBlank() ? "MANUAL" : in.method().trim().toUpperCase();
        if ("SCAN".equals(method)) {
            UUID[] x = slip(in.token());
            if (!x[0].equals(s.get("exam_id")) || !x[1].equals(candidate)) {
                throw new DomainRuleViolation("CBT_SLIP_MISMATCH", "The slip scanned is not this candidate's for this examination.",
                        new DomainRuleViolation.Remedy("Check the candidate's identity; scan their own slip, or check them in by hand.", "You"));
            }
        }
        jdbc.sql("SELECT status FROM assessment.cbt_check_in(:s, :c, :m)").param("s", sitting).param("c", candidate).param("m", method).query(String.class).single();
        return board(sitting);
    }

    /** the candidate's photograph, to check the face at the door — for whoever may read the sitting, of a candidate seated in it */
    @GetMapping("/sittings/{sitting}/candidates/{candidate}/photo")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> photo(@PathVariable UUID sitting, @PathVariable UUID candidate) {
        Map<String, Object> s = sitting(sitting);
        access(sitting, (UUID) s.get("exam_id"));
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM assessment.cbt_seat WHERE sitting_id = :s AND candidate_id = :c)").param("s", sitting).param("c", candidate).query(Boolean.class).single()) {
            throw new NotFound("candidate", candidate.toString());
        }
        boolean student = jdbc.sql("SELECT EXISTS (SELECT 1 FROM people.student WHERE id = :c)").param("c", candidate).query(Boolean.class).single();
        if (student) {
            byte[] img = portal.passportImage(candidate).orElseThrow(() -> new NotFound("photograph", candidate.toString()));
            return ResponseEntity.ok().contentType(MediaType.IMAGE_JPEG).cacheControl(CacheControl.noStore()).header("X-Content-Type-Options", "nosniff").body(img);
        }
        return JupebDocuments.stream(jdbc, files, candidate, "PASSPORT", null, true);
    }

    /** every candidate of a sitting with the code their slip carries, for the office to print the slips */
    @GetMapping("/exams/{id}/sittings/{sitting}/slips")
    @PreAuthorize(MANAGERS)
    @Transactional(readOnly = true)
    Map<String, Object> slips(@PathVariable UUID id, @PathVariable UUID sitting) {
        managed(id);
        Map<String, Object> s = sitting(sitting);
        if (!id.equals(s.get("exam_id"))) throw new NotFound("sitting", sitting.toString());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("exam", jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, coalesce(c.title, js.title) AS course_title, e.session, e.semester,
                       e.duration_minutes, e.late_entry_minutes
                  FROM assessment.cbt_exam e LEFT JOIN catalogue.course c ON c.code = e.course_code LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id WHERE e.id = :e
                """).param("e", id).query().singleRow());
        out.put("sitting", s);
        out.put("rows", jdbc.sql("SELECT seat_no, candidate_id, number, surname, other_names, level, programme FROM assessment.cbt_sitting_board(:s)")
                .param("s", sitting).query().listOfRows().stream().map(r -> {
                    Map<String, Object> row = new LinkedHashMap<>(r);
                    row.put("token", CbtCandidateDoor.slipToken(codes, id, (UUID) r.get("candidate_id")));
                    return row;
                }).toList());
        return out;
    }

    /* ── V375: incidents and the sitting report ── */

    /** an incident recorded as it happens; once the report is filed, only the office adds one */
    @PostMapping("/sittings/{sitting}/incidents")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> incident(@PathVariable UUID sitting, @Valid @RequestBody IncidentIn in) {
        Map<String, Object> s = markable(sitting);
        boolean filed = jdbc.sql("SELECT EXISTS (SELECT 1 FROM assessment.cbt_sitting_report WHERE sitting_id = :s)").param("s", sitting).query(Boolean.class).single();
        if (filed && !office((UUID) s.get("exam_id"))) {
            throw new AccessDeniedException("The sitting's report is filed; the office running the examination records anything further.");
        }
        jdbc.sql("SELECT id FROM assessment.cbt_record_incident(:s, :c, :k, :d, :m, :at)").param("s", sitting).param("c", in.candidateId(), Types.OTHER)
                .param("k", in.kind()).param("d", in.detail()).param("m", in.minutesLost(), Types.INTEGER).param("at", in.occurredAt(), Types.TIMESTAMP_WITH_TIMEZONE)
                .query(UUID.class).single();
        return board(sitting);
    }

    /** the chief invigilator, else any invigilator where none is named chief, or the office running the examination */
    private boolean mayFile(UUID sitting, UUID exam) {
        if (office(exam)) return true;
        UUID chief = jdbc.sql("SELECT person_id FROM assessment.cbt_invigilator WHERE sitting_id = :s AND chief").param("s", sitting).query(UUID.class).optional().orElse(null);
        return chief != null ? chief.equals(ctx().actorId()) : invigilates(sitting);
    }

    @GetMapping("/sittings/{sitting}/report")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    Map<String, Object> report(@PathVariable UUID sitting) {
        Map<String, Object> s = sitting(sitting);
        UUID examId = (UUID) s.get("exam_id");
        Access a = access(sitting, examId);
        Map<String, Object> r = jdbc.sql("""
                SELECT r.began_at, r.ended_at, r.remarks, r.counts::text AS counts, r.filed_at, r.filed_office, r.addendum, r.addendum_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS filed_by,
                       (SELECT coalesce(json_agg(json_build_object('person_id', q.id, 'name', q.surname || ', ' || q.given_names, 'staff_number', q.staff_number) ORDER BY q.surname), '[]'::json)::text
                          FROM iam.person q WHERE q.id = ANY (r.invigilators)) AS present
                  FROM assessment.cbt_sitting_report r LEFT JOIN iam.person p ON p.id = r.filed_by WHERE r.sitting_id = :s
                """).param("s", sitting).query().listOfRows().stream().findFirst().map(LinkedHashMap::new).orElse(null);
        if (r != null) {
            r.put("counts", mapper.readValue(String.valueOf(r.get("counts")), new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
            r.put("present", mapper.readValue(String.valueOf(r.get("present")), new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sitting", s);
        out.put("exam", jdbc.sql("""
                SELECT e.id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code, e.session, e.duration_minutes
                  FROM assessment.cbt_exam e LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id WHERE e.id = :e
                """).param("e", examId).query().singleRow());
        out.put("report", r);
        out.put("counts", mapper.readValue(jdbc.sql("SELECT assessment.cbt_sitting_counts(:s)::text").param("s", sitting).query(String.class).single(),
                new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
        out.put("incidents", incidents(sitting));
        out.put("invigilators", jdbc.sql("""
                SELECT p.id AS person_id, p.surname || ', ' || p.given_names AS name, p.staff_number, i.chief
                  FROM assessment.cbt_invigilator i JOIN iam.person p ON p.id = i.person_id WHERE i.sitting_id = :s ORDER BY i.chief DESC, p.surname
                """).param("s", sitting).query().listOfRows());
        out.put("canFile", r == null && a.canMark() && mayFile(sitting, examId));
        out.put("canAdd", r != null && a.office());
        out.put("now", jdbc.sql("SELECT now()").query(OffsetDateTime.class).single());
        return out;
    }

    @PostMapping("/sittings/{sitting}/report")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> file(@PathVariable UUID sitting, @Valid @RequestBody ReportIn in) {
        Map<String, Object> s = markable(sitting);
        if (!mayFile(sitting, (UUID) s.get("exam_id"))) throw new AccessDeniedException("The chief invigilator files the sitting's report.");
        jdbc.sql("SELECT filed_at FROM assessment.cbt_file_sitting_report(:s, :b, :e, :i, :r)").param("s", sitting).param("b", in.began()).param("e", in.ended())
                .param("i", in.invigilators().toArray(new UUID[0])).param("r", in.remarks(), Types.VARCHAR).query(OffsetDateTime.class).single();
        return report(sitting);
    }

    @PostMapping("/sittings/{sitting}/report/addendum")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> addendum(@PathVariable UUID sitting, @Valid @RequestBody AddendumIn in) {
        Map<String, Object> s = sitting(sitting);
        managed((UUID) s.get("exam_id"));
        jdbc.sql("SELECT addendum_at FROM assessment.cbt_sitting_report_addendum(:s, :t)").param("s", sitting).param("t", in.text()).query(OffsetDateTime.class).single();
        return report(sitting);
    }

    /** the office's sittings in one place — each filed, due (over and not filed), running or to come — within the acting office's scope */
    @GetMapping("/sitting-reports")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> reports(@RequestParam String office, @RequestParam(required = false) String session) {
        String o = CbtExamController.office(office);
        OfficeScope.Bound b = "EXAMS".equals(o) ? scope.bound(null, null, null) : new OfficeScope.Bound(null, null, null);
        return jdbc.sql("""
                SELECT s.id AS sitting_id, s.label, s.venue, s.starts_at, s.ends_at, e.id AS exam_id, e.reference, e.title, coalesce(e.course_code, js.code) AS course_code,
                       e.session, (SELECT count(*) FROM assessment.cbt_seat x WHERE x.sitting_id = s.id) AS seated,
                       (SELECT count(*) FROM assessment.cbt_sitting_incident i WHERE i.sitting_id = s.id) AS incidents,
                       r.filed_at, r.counts::text AS counts, CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END AS filed_by,
                       CASE WHEN r.sitting_id IS NOT NULL THEN 'FILED' WHEN s.ends_at <= now() THEN 'DUE' WHEN s.starts_at <= now() THEN 'RUNNING' ELSE 'TO_COME' END AS phase
                  FROM assessment.cbt_sitting s
                  JOIN assessment.cbt_exam e ON e.id = s.exam_id
                  LEFT JOIN jupeb.subject js ON js.id = e.jupeb_subject_id
                  LEFT JOIN catalogue.course c ON c.code = e.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN assessment.cbt_sitting_report r ON r.sitting_id = s.id
                  LEFT JOIN iam.person p ON p.id = r.filed_by
                 WHERE e.office = :o AND e.state <> 'CANCELLED' AND (:ses::text IS NULL OR e.session = :ses)
                   AND (:dept::text IS NULL OR c.dept_code = :dept) AND (:fac::text IS NULL OR d.faculty_code = :fac)
                 ORDER BY s.starts_at DESC, s.label LIMIT 500
                """).param("o", o).param("ses", session == null || session.isBlank() ? null : session.trim(), Types.VARCHAR)
                .param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).query().listOfRows().stream().map(r -> {
                    Map<String, Object> row = new LinkedHashMap<>(r);
                    row.put("counts", r.get("counts") == null ? null : mapper.readValue(String.valueOf(r.get("counts")), new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }));
                    return row;
                }).toList();
    }

    @PostMapping("/sittings/{sitting}/candidates/{candidate}/absent")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> absent(@PathVariable UUID sitting, @PathVariable UUID candidate, @Valid @RequestBody MarkIn in) {
        markable(sitting);
        jdbc.sql("SELECT status FROM assessment.cbt_mark_absent(:s, :c, :n)").param("s", sitting).param("c", candidate).param("n", in.note(), Types.VARCHAR).query(String.class).single();
        return board(sitting);
    }

    @PostMapping("/sittings/{sitting}/candidates/{candidate}/late")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> late(@PathVariable UUID sitting, @PathVariable UUID candidate, @Valid @RequestBody LateIn in) {
        markable(sitting);
        jdbc.sql("SELECT status FROM assessment.cbt_admit_late(:s, :c, :m, :n)").param("s", sitting).param("c", candidate).param("m", in.minutes())
                .param("n", in.note(), Types.VARCHAR).query(String.class).single();
        return board(sitting);
    }

    @PostMapping("/sittings/{sitting}/candidates/{candidate}/clear")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> clear(@PathVariable UUID sitting, @PathVariable UUID candidate) {
        markable(sitting);
        jdbc.sql("SELECT assessment.cbt_clear_mark(:s, :c)").param("s", sitting).param("c", candidate).query(Integer.class).single();
        return board(sitting);
    }

    /** everyone seated who has neither come nor been marked, marked absent — once the sitting has begun */
    @PostMapping("/sittings/{sitting}/rest-absent")
    @PreAuthorize("isAuthenticated()")
    @Transactional
    Map<String, Object> restAbsent(@PathVariable UUID sitting, @Valid @RequestBody MarkIn in) {
        markable(sitting);
        int n = jdbc.sql("SELECT assessment.cbt_mark_rest_absent(:s, :n)").param("s", sitting).param("n", in.note(), Types.VARCHAR).query(Integer.class).single();
        Map<String, Object> out = board(sitting);
        out.put("marked", n);
        return out;
    }
}
