package ng.edu.moaum.portal.transfers;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V766: the desks of the online inter-university transfer applications. The Academic Office (or the Registry) opens a window each
 * session, lists the programmes and levels that take transfer students and keeps the documents asked for; the Registry checks each
 * document of a submitted application, returns it to the applicant or sends it to the Head of Department of the programme applied for
 * (the College's Dean, V734's rule), who recommends it at a level the window opens or declines it with a reason; the Registry then
 * rejects it, sends it back, or approves it — which registers the transfer exactly as V763's form does, a batch of one (source
 * APPLICATION) that another officer decides on the Inter-University Transfer page. The rules are the database's (admissions.iut_*);
 * here the reading offices are held to their own: the active office must be one the endpoint names (SiwesRegistrationController's
 * rule — a person who holds a reading office but acts in another reads nothing), a Head of Department reads only their department's
 * applications that have reached the desk, a Dean only those of their faculty's departments in a College.
 */
@RestController
@RequestMapping("/api/v1/transfer-applications/office")
class TransferApplicationDeskController {

    static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super')";
    static final String KEEPERS = SETTERS;
    static final String DEPARTMENT = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_super')";
    static final String READERS_OR_DEPARTMENT = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_super',"
            + "'OFFICE_hod','OFFICE_dean')";
    static final Set<String> SETTER_OFFICES = Set.of("academic", "registrar", "dregistrar", "super");
    static final Set<String> READER_OFFICES = Set.of("academic", "registrar", "dregistrar", "records", "super");
    static final Set<String> DEPARTMENT_OFFICES = Set.of("hod", "dean", "super");
    static final String SESSION = "^\\d{4}/\\d{4}$";
    static final String NONE = "__none__";
    static final int PAGE_MAX = 500;
    /** the states in which V763's own check of the transfer is shown to the Registry: submitted, short of a decision */
    static final Set<String> CHECKED = Set.of("SUBMITTED", "CORRECTION_REQUIRED", "WITH_HOD", "RECOMMENDED", "NOT_RECOMMENDED");

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final TransferApplicationFiles documents;
    private final tools.jackson.databind.ObjectMapper json;

    TransferApplicationDeskController(JdbcClient jdbc, OfficeScope scope, TransferApplicationFiles documents, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.documents = documents;
        this.json = json;
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parse(String text) {
        return text == null ? new LinkedHashMap<>() : new LinkedHashMap<>(json.readValue(text, Map.class));
    }

    private Object parseAny(String text) {
        return text == null ? null : json.readValue(text, Object.class);
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    /** the active office, one the endpoint names: authority is checked against every office the token carries, so a person who holds a
     *  reading office but acts in another would otherwise read with it */
    private static String acting(Set<String> offices, String what) {
        String o = office();
        if (o == null || !offices.contains(o)) {
            throw new AccessDeniedException(what + " is read and changed in an office that holds it.");
        }
        return o;
    }

    private static Set<String> union(Set<String> a, Set<String> b) {
        java.util.HashSet<String> u = new java.util.HashSet<>(a);
        u.addAll(b);
        return u;
    }

    /** the session asked, else the desks' own (admissions.iut_desk_session): the open window's, else the latest session with
     *  applications on the desks' hands — a closed window keeps its desk work, a window being prepared for the next session does not
     *  take the desks off it — else the latest window set open but not open today, else the University's current session */
    private String sessionOr(String asked) {
        String s = blank(asked);
        return s != null ? s : jdbc.sql("SELECT admissions.iut_desk_session()").query(String.class).optional().orElse(null);
    }

    /* ── the window, its programmes and levels, the documents asked for: the Academic Office's ── */

    /** a session's window: its state and dates, its fee as the Bursary left it, its lines with the applications, approvals and
     *  admissions on each, and the applications by state (admissions.iut_window_view) */
    @GetMapping("/window")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> window(@RequestParam(required = false) String session) {
        acting(READER_OFFICES, "The transfer window");
        return parse(jdbc.sql("SELECT admissions.iut_window_view(:s)::text").param("s", sessionOr(session), Types.VARCHAR).query(String.class).single());
    }

    public record WindowIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Pattern(regexp = "(?i)DRAFT|OPEN|CLOSED") String state,
                           LocalDate opensOn, LocalDate closesOn, @Size(max = 2000) String message, @Size(max = 2000) String note) {
    }

    /** the window set: OPEN with its dates, a programme taking transfers and the fee published; CLOSED stops new applications only;
     *  back to DRAFT while no application is made (admissions.iut_set_window) */
    @PutMapping("/window")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> setWindow(@Valid @RequestBody WindowIn body) {
        acting(SETTER_OFFICES, "The transfer window");
        return parse(jdbc.sql("SELECT admissions.iut_set_window(:s, :st, :o, :c, :m, :n)::text").param("s", body.session()).param("st", body.state().toUpperCase())
                .param("o", body.opensOn(), Types.DATE).param("c", body.closesOn(), Types.DATE).param("m", blank(body.message()), Types.VARCHAR)
                .param("n", blank(body.note()), Types.VARCHAR).query(String.class).single());
    }

    public record LinesIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 20) String programme,
                          @NotNull @Size(min = 1, max = 9) List<@NotNull @Min(100) @Max(900) Integer> levels, @Min(1) @Max(100000) Integer places) {
    }

    /** a programme's levels added to the window (one line each; a line already there is left as it is) */
    @PostMapping("/lines")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> addLines(@Valid @RequestBody LinesIn body) {
        acting(SETTER_OFFICES, "The transfer window");
        return parse(jdbc.sql("SELECT admissions.iut_add_lines(:s, :p, CAST(:l AS integer[]), :n)::text").param("s", body.session()).param("p", body.programme().trim())
                .param("l", body.levels().stream().map(String::valueOf).collect(java.util.stream.Collectors.joining(",", "{", "}")))
                .param("n", body.places(), Types.INTEGER).query(String.class).single());
    }

    public record LineIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 20) String programme,
                         @NotNull @Min(100) @Max(900) Integer level, @Min(1) @Max(100000) Integer places, Boolean accepting) {
    }

    /** a line's places (none: no limit) and whether it takes new applications (none: as it is) */
    @PutMapping("/lines")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> setLine(@Valid @RequestBody LineIn body) {
        acting(SETTER_OFFICES, "The transfer window");
        return parse(jdbc.sql("SELECT admissions.iut_set_line(:s, :p, :l, :n, :a)::text").param("s", body.session()).param("p", body.programme().trim())
                .param("l", body.level()).param("n", body.places(), Types.INTEGER).param("a", body.accepting(), Types.BOOLEAN).query(String.class).single());
    }

    /** a line taken off the window while no application names it */
    @DeleteMapping("/lines")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> removeLine(@RequestParam String session, @RequestParam String programme, @RequestParam int level) {
        acting(SETTER_OFFICES, "The transfer window");
        return parse(jdbc.sql("SELECT admissions.iut_remove_line(:s, :p, :l)::text").param("s", session.trim()).param("p", programme.trim()).param("l", level)
                .query(String.class).single());
    }

    /** the undergraduate programmes in use a line may name, each with its department, faculty and levels — the picker for lines */
    @GetMapping("/programmes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> programmes() {
        acting(READER_OFFICES, "The transfer window");
        return jdbc.sql("""
                SELECT p.code, p.name, u.dept_code AS dept, u.dept_name AS "deptName", u.faculty_code AS faculty, u.faculty_name AS "facultyName",
                       u.college_code AS college, to_jsonb(people.programme_levels(p.code))::text AS levels
                  FROM ref.programme p CROSS JOIN LATERAL people.transfer_unit(p.code) u
                 WHERE p.category = 'UNDER GRADUATE' AND NOT coalesce(p.archived, false)
                 ORDER BY u.faculty_name, u.dept_name, p.name
                """).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("levels", parseAny((String) r.get("levels")));
                    return m;
                }).toList();
    }

    /** the documents an applicant is asked for, with the V763 code each counts as (admissions.iut_document_kinds) */
    @GetMapping("/document-kinds")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Object documentKinds() {
        acting(READER_OFFICES, "The documents asked for");
        return parseAny(jdbc.sql("SELECT admissions.iut_document_kinds()::text").query(String.class).single());
    }

    public record KindIn(@NotBlank @Size(max = 40) String code, @Size(max = 160) String label, @Size(max = 400) String hint, Boolean required,
                         Boolean imagesAllowed, @Min(0) @Max(100000) Integer ord, Boolean active) {
    }

    /** a document kind added or changed (a value not sent is kept; a hint sent blank is cleared; the V763 code is never written) */
    @PutMapping("/document-kinds")
    @PreAuthorize(SETTERS)
    @Transactional
    Object saveDocumentKind(@Valid @RequestBody KindIn body) {
        acting(SETTER_OFFICES, "The documents asked for");
        return parseAny(jdbc.sql("SELECT admissions.iut_save_document_kind(:c, :l, :h, :r, :i, :o, :a)::text").param("c", body.code().trim())
                .param("l", blank(body.label()), Types.VARCHAR).param("h", body.hint(), Types.VARCHAR).param("r", body.required(), Types.BOOLEAN)
                .param("i", body.imagesAllowed(), Types.BOOLEAN).param("o", body.ord(), Types.INTEGER).param("a", body.active(), Types.BOOLEAN)
                .query(String.class).single());
    }

    /* ── the applications ── */

    /** whom the active office lists: a reading office the filters it sends; the Head of Department their department's applications
     *  that have reached the desk (none when no department resolves, as the HOD's desk answers); the Dean their faculty's, where its
     *  departments are in a College; super everything */
    private record Scope(String faculty, String dept, boolean desk, boolean college) {
    }

    private Scope scopeOf(String office, String department) {
        return switch (office) {
            case "hod" -> new Scope(null, coalesce(scope.actingDept(), NONE), true, false);
            case "dean" -> new Scope(coalesce(scope.actingFaculty(), NONE), null, true, true);
            default -> new Scope(null, blank(department), false, false);
        };
    }

    private static String coalesce(String a, String b) {
        return a == null || a.isBlank() ? b : a;
    }

    /** the applications of a session (every session when none is named), by state, programme, department and a search — the
     *  application and JAMB numbers, the name, the matriculation number at the other university, the university — a page at a time,
     *  with the total and the counts by state on the same filters but the state (admissions.iut_applications) */
    @GetMapping("/applications")
    @PreAuthorize(READERS_OR_DEPARTMENT)
    @Transactional(readOnly = true)
    Map<String, Object> applications(@RequestParam(required = false) String session, @RequestParam(required = false) String state,
                                     @RequestParam(required = false) String programme, @RequestParam(required = false) String department,
                                     @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                                     @RequestParam(defaultValue = "50") int size) {
        String o = acting(union(READER_OFFICES, DEPARTMENT_OFFICES), "The transfer applications");
        Scope s = scopeOf(o, department);
        int sz = Math.max(1, Math.min(size, PAGE_MAX));
        int pg = Math.max(0, page);
        Map<String, Object> out = parse(jdbc.sql("SELECT admissions.iut_applications(:s, :st, :f, :d, :p, :q, :desk, :college, :n, :off)::text")
                .param("s", blank(session), Types.VARCHAR).param("st", blank(state), Types.VARCHAR).param("f", s.faculty(), Types.VARCHAR)
                .param("d", s.dept(), Types.VARCHAR).param("p", blank(programme), Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("desk", s.desk()).param("college", s.college()).param("n", sz).param("off", pg * sz).query(String.class).single());
        out.put("page", pg);
        out.put("size", sz);
        return out;
    }

    /** the applications by state, scoped as the list is */
    @GetMapping("/summary")
    @PreAuthorize(READERS_OR_DEPARTMENT)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session) {
        String o = acting(union(READER_OFFICES, DEPARTMENT_OFFICES), "The transfer applications");
        Scope s = scopeOf(o, null);
        Map<String, Object> all = parse(jdbc.sql("SELECT admissions.iut_applications(:s, NULL, :f, :d, NULL, NULL, :desk, :college, 1, 0)::text")
                .param("s", blank(session), Types.VARCHAR).param("f", s.faculty(), Types.VARCHAR).param("d", s.dept(), Types.VARCHAR)
                .param("desk", s.desk()).param("college", s.college()).query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", blank(session));
        out.put("counts", all.get("counts"));
        return out;
    }

    private Map<String, Object> row(UUID id) {
        return jdbc.sql("SELECT application_no, session, state FROM admissions.iut_application WHERE id = :id").param("id", id).query().listOfRows().stream()
                .findFirst().orElseThrow(() -> new NotFound("transfer application", id));
    }

    /** whether the department's officer reads this application: it reached the desk, and it is their department's (admissions.iut_hod_may) */
    private void departmentMay(UUID id) {
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT admissions.iut_hod_may(:id)").param("id", id).query(Boolean.class).single())) {
            throw new AccessDeniedException("IUT_HOD_OTHER_DEPARTMENT: the application is not at your department's desk.");
        }
    }

    /** the office reading it: a reading office (super among them) reads it whole; the Head of Department or the Dean only one that
     *  reached their desk */
    private String readable(UUID id) {
        String o = acting(union(READER_OFFICES, DEPARTMENT_OFFICES), "The transfer application");
        row(id);
        if (!READER_OFFICES.contains(o)) {
            departmentMay(id);
        }
        return o;
    }

    /** one application: a reading office reads it whole (admissions.iut_view OFFICE) with what V763's own check of the transfer it would
     *  register says (people.university_transfer_form_check — STUDENT_EXISTS, TRANSFER_PENDING, UNIVERSITY_UNKNOWN, NAME_DIFFERS and the
     *  rest) while it is submitted and short of a decision; the Head of Department or the Dean reads it without the contact, the fee, the
     *  transfer or the Registry's acts (HOD) */
    @GetMapping("/applications/{id}")
    @PreAuthorize(READERS_OR_DEPARTMENT)
    @Transactional(readOnly = true)
    Map<String, Object> application(@PathVariable UUID id) {
        String o = readable(id);
        if (!READER_OFFICES.contains(o)) {
            return parse(jdbc.sql("SELECT admissions.iut_view(:id, 'HOD')::text").param("id", id).query(String.class).single());
        }
        Map<String, Object> out = parse(jdbc.sql("SELECT admissions.iut_view(:id, 'OFFICE')::text").param("id", id).query(String.class).single());
        if (CHECKED.contains(String.valueOf(out.get("state")))) {
            out.put("transferCheck", parse(jdbc.sql("SELECT people.university_transfer_form_check(admissions.iut_transfer_row(a.id), a.session)::text FROM admissions.iut_application a WHERE a.id = :id")
                    .param("id", id).query(String.class).single()));
        }
        return out;
    }

    /** a document of the application, current or superseded */
    @GetMapping("/applications/{id}/documents/{docId}")
    @PreAuthorize(READERS_OR_DEPARTMENT)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> document(@PathVariable UUID id, @PathVariable UUID docId) {
        readable(id);
        return documents.stream(id, docId);
    }

    /** the application's current documents as one PDF, for the Head of Department */
    @GetMapping("/applications/{id}/documents.pdf")
    @PreAuthorize(READERS_OR_DEPARTMENT)
    @Transactional(readOnly = true)
    ResponseEntity<byte[]> merged(@PathVariable UUID id) {
        readable(id);
        return documents.merged(id, String.valueOf(row(id).get("application_no")));
    }

    public record ReviewIn(@NotBlank @Pattern(regexp = "(?i)ACCEPTED|REJECTED") String verdict, @Size(max = 1000) String note) {
    }

    /** a document accepted, or rejected with a note the applicant reads, while the application is submitted */
    @PostMapping("/applications/{id}/documents/{docId}/review")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> review(@PathVariable UUID id, @PathVariable UUID docId, @Valid @RequestBody ReviewIn body) {
        acting(SETTER_OFFICES, "The transfer application");
        if (!Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.iut_document WHERE id = :d AND application_id = :a)")
                .param("d", docId).param("a", id).query(Boolean.class).single())) {
            throw new NotFound("document of the transfer application", docId);
        }
        return parse(jdbc.sql("SELECT admissions.iut_review_document(:d, :v, :n)::text").param("d", docId).param("v", body.verdict().toUpperCase())
                .param("n", blank(body.note()), Types.VARCHAR).query(String.class).single());
    }

    public record ActIn(@NotBlank @Pattern(regexp = "(?i)SEND_TO_HOD|RETURN|SEND_BACK_TO_HOD|REJECT") String action, @Size(max = 2000) String note,
                        @Size(max = 40) String expectedState) {
    }

    /** the Registry's act: send to the Head of Department, return to the applicant, send back to the Head of Department, or reject — a
     *  draft too, to end one made under another person's JAMB number (it holds the number until it ends) */
    @PostMapping("/applications/{id}/act")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> act(@PathVariable UUID id, @Valid @RequestBody ActIn body) {
        acting(SETTER_OFFICES, "The transfer application");
        return parse(jdbc.sql("SELECT admissions.iut_act(:a, :x, :n, :e)::text").param("a", id).param("x", body.action().toUpperCase())
                .param("n", blank(body.note()), Types.VARCHAR).param("e", blank(body.expectedState()), Types.VARCHAR).query(String.class).single());
    }

    public record RecommendIn(@NotNull Boolean accept, @Min(100) @Max(900) Integer level, @Size(max = 2000) String note, @Size(max = 40) String expectedState) {
    }

    /** the Head of Department's recommendation: accept at a level the window lists for the programme, or decline with a reason */
    @PostMapping("/applications/{id}/recommend")
    @PreAuthorize(DEPARTMENT)
    @Transactional
    Map<String, Object> recommend(@PathVariable UUID id, @Valid @RequestBody RecommendIn body) {
        acting(DEPARTMENT_OFFICES, "The recommendation");
        row(id);
        return parse(jdbc.sql("SELECT admissions.iut_recommend(:a, :ok, :l, :n, :e)::text").param("a", id).param("ok", body.accept())
                .param("l", body.level(), Types.INTEGER).param("n", blank(body.note()), Types.VARCHAR).param("e", blank(body.expectedState()), Types.VARCHAR)
                .query(String.class).single());
    }

    public record UniversityIn(@NotBlank @Size(max = 16) String code) {
    }

    /** the university on the list set on an application whose applicant named one not on it (the name typed is kept) */
    @PostMapping("/applications/{id}/university")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> university(@PathVariable UUID id, @Valid @RequestBody UniversityIn body) {
        acting(SETTER_OFFICES, "The transfer application");
        return parse(jdbc.sql("SELECT admissions.iut_set_university(:a, :c)::text").param("a", id).param("c", body.code().trim()).query(String.class).single());
    }

    public record ApproveIn(@Size(max = 120) String approvalRef, @Size(max = 2000) String note, @Size(max = 40) String expectedState) {
    }

    /** the Registry's approval: the transfer registered as V763's form registers it, a batch of one (source APPLICATION) for another
     *  officer's decision on the Inter-University Transfer page; the answer carries batchId, batchRef and transferId */
    @PostMapping("/applications/{id}/approve")
    @PreAuthorize(KEEPERS)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id, @Valid @RequestBody ApproveIn body) {
        acting(SETTER_OFFICES, "The transfer application");
        return parse(jdbc.sql("SELECT admissions.iut_approve(:a, :r, :n, :e)::text").param("a", id).param("r", blank(body.approvalRef()), Types.VARCHAR)
                .param("n", blank(body.note()), Types.VARCHAR).param("e", blank(body.expectedState()), Types.VARCHAR).query(String.class).single());
    }
}
