package ng.edu.moaum.portal.iam;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import ng.edu.moaum.portal.auth.AuthService;

import org.springframework.jdbc.core.simple.JdbcClient;
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

/** Users & roles: the people, the offices they hold under instruments, and the credential that signs them in. */
@RestController
@RequestMapping("/api/v1/iam")
class AccountsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_audit')";
    private static final String CREDENTIALS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String GRANTORS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_vc','OFFICE_super','OFFICE_ict','OFFICE_admin')";

    public record PersonRow(UUID id, String staffNumber, String surname, String givenNames, String email, String phone, LocalDate endedOn, String username,
                            boolean mustChange, java.time.OffsetDateTime lastSignInAt, java.time.OffsetDateTime lockedUntil, long liveOffices) {
    }

    /** {@code scopeLive} (V325): the live register entry the scope resolves to, or null when it names nothing live —
     *  the console marks such a grant, since the desk it scopes reads nothing from it */
    public record GrantRow(UUID id, UUID personId, String surname, String givenNames, String staffNumber, String officeCode, String label,
                           String scopeKind, String scopeId, String scopeLive, String instrument, UUID grantedBy, String grantedByName, LocalDate validFrom, LocalDate validTo) {
    }

    public record SetCredential(@NotBlank String username, @NotBlank String password) {
    }

    public record EndGrant(LocalDate on, @NotBlank String reason) {
    }

    /** V319: what an amendment of a live grant changes — never the person — and why */
    public record AmendGrant(@NotBlank String officeCode,
                             @NotBlank @jakarta.validation.constraints.Pattern(regexp = "institution|college|faculty|department|programme|course|unit|platform|level") String scopeKind,
                             String scopeId,
                             @NotBlank @jakarta.validation.constraints.Size(max = 400) String instrument,
                             LocalDate validFrom, LocalDate validTo,
                             @NotBlank @jakarta.validation.constraints.Size(max = 400) String reason) {
    }

    /** V750: the rows of the nominal roll (or the old sheet), each with its {@code sheet_row} when the screen sends it; whether to
     *  check them only (a dry run writes nothing); and the e-mail addresses earlier requests of the same upload gave ({address:
     *  staff number}) — kept from these rows, so a check sent in parts says what the upload in parts will do */
    public record Rows(@jakarta.validation.constraints.NotNull List<Map<String, Object>> rows, Boolean dryRun, Map<String, String> claimed) {
    }

    private final JdbcClient jdbc;
    private final AuthService auth;
    private final tools.jackson.databind.ObjectMapper json;

    AccountsController(JdbcClient jdbc, AuthService auth, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.auth = auth;
        this.json = json;
    }

    /**
     * Bulk-onboard lecturers: each row becomes a person, a sign-in
     * (username/password = staff number, must change) and the lecturer office
     * scoped to the department code — the same three things Users & roles makes
     * one at a time. Resilient and idempotent; see iam.import_lecturers (V135).
     * Chunk the rows client-side: each credential is a bcrypt-12 hash (~¼s),
     * so a large single request would time out.
     * V750: the nominal roll's columns or the old sheet's; someone already on record has only what the record lacks filled (V761:
     * a different value kept and listed under {@code kept}, the posting and the salary scale and step each once), and a dry run
     * says row by row what the upload would do and writes nothing. A new lecturer whose
     * department is not on the portal is not loaded (SKIPPED, the message saying what to add or correct). The function's row
     * comes back as it is, with {@code results} — one entry per row, its {@code sheet_row} as {@code row}. A blank or query name
     * cell never erases a name (reported under {@code unresolved}); a number on record as non-teaching staff is an ERROR that
     * writes nothing; an upload moves no lecturer office (V761: a department it fills beside an office open elsewhere is listed as
     * {@code lecturer_office} {@code OFFICE_KEPT}), while the Add form still moves it (the change {@code lecturer_office}).
     */
    @PostMapping("/lecturers/import")
    @PreAuthorize(CREDENTIALS)
    @Transactional
    Map<String, Object> importLecturers(@Valid @RequestBody Rows body) {
        return upload("iam.import_lecturers", body.rows(), body.dryRun(), body.claimed());
    }

    /** an upload function's one row as JSON — its counts and its {@code results} (jsonb), not the driver's wrapper of them */
    private Map<String, Object> upload(String function, List<Map<String, Object>> rows, Boolean dryRun, Map<String, String> claimed) {
        String row = jdbc.sql("SELECT to_jsonb(r)::text FROM " + function + "(:j::jsonb, :d, :c::jsonb) r")
                .param("j", json.writeValueAsString(rows)).param("d", Boolean.TRUE.equals(dryRun))
                .param("c", json.writeValueAsString(claimed == null ? Map.of() : claimed)).query(String.class).single();
        return json.readValue(row, new tools.jackson.core.type.TypeReference<java.util.LinkedHashMap<String, Object>>() { });
    }

    private static final String STAFF_LOADERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    public record StaffRows(@jakarta.validation.constraints.NotNull List<Map<String, Object>> rows, Boolean dryRun, Map<String, String> claimed) {
    }

    /**
     * Bulk-load non-academic staff from the nominal roll (V253): the same sheet as the teaching staff with
     * CONTISS in place of CONUASS and the unit as written. Each row becomes a person and an establishment
     * record placed in its unit, department or faculty — no sign-in and no office, since a non-academic
     * member of staff has no desk on the portal yet. A dry run resolves every row and writes nothing.
     * V750: the senior roll (PNO, P + digits) or the junior roll (JP-NO, JP + digits — never merged into a P record); someone
     * already on record has only what the record lacks filled (V761; the e-mail and phone likewise, a blank or query name cell
     * erasing no name, their sign-in, password and offices never touched);
     * a number on record as teaching staff is an ERROR that writes nothing; the function's row comes back with {@code results},
     * one entry per row.
     */
    @PostMapping("/staff/import")
    @PreAuthorize(STAFF_LOADERS)
    @Transactional
    Map<String, Object> importStaff(@Valid @RequestBody StaffRows body) {
        return upload("iam.import_staff", body.rows(), body.dryRun(), body.claimed());
    }

    /** V750: a roll uploaded, by kind (ACADEMIC or NON_ACADEMIC) and the staff numbers on it (P123, JP858; a bare number is a P number) */
    public record RollAbsent(@NotBlank @jakarta.validation.constraints.Pattern(regexp = "(?i)\\s*(ACADEMIC|NON_ACADEMIC)\\s*") String kind,
                             @jakarta.validation.constraints.NotNull @jakarta.validation.constraints.Size(max = 5000) List<String> numbers) {
    }

    private static final java.util.Set<String> CREDENTIAL_OFFICES = java.util.Set.of(
            "OFFICE_registrar", "OFFICE_dregistrar", "OFFICE_ict", "OFFICE_admin", "OFFICE_super");

    /**
     * V750: the roll's "on the portal but not on this roll" — the staff in service of that kind (V698) whose number is not among
     * the roll's, within the series the roll holds (P or JP). It reads; nobody is ended by it. The non-academic roll by the offices
     * that load non-academic staff; the teaching staff's by those that load teaching staff (CREDENTIALS — not Human Resources alone).
     */
    @PostMapping("/staff/roll-absent")
    @PreAuthorize(STAFF_LOADERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> rollAbsent(@Valid @RequestBody RollAbsent body, org.springframework.security.core.Authentication caller) {
        String kind = body.kind().trim().toUpperCase();
        if ("ACADEMIC".equals(kind) && caller.getAuthorities().stream().noneMatch(g -> CREDENTIAL_OFFICES.contains(g.getAuthority()))) {
            throw new org.springframework.security.access.AccessDeniedException(
                    "The teaching staff's roll is checked by the offices that load teaching staff: the Registrar, the Deputy Registrar, ICT and the administrators.");
        }
        return jdbc.sql("SELECT a.person_id, a.staff_number, a.name, a.rank, a.posting FROM hrm.roll_absent(:k, :n::text[]) a")
                .param("k", kind).param("n", body.numbers().stream().filter(java.util.Objects::nonNull).toArray(String[]::new))
                .query().listOfRows();
    }

    /** the non-academic staff on record, with where each is placed */
    @GetMapping("/staff")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> staff(@RequestParam(required = false) String q) {
        return jdbc.sql("""
                SELECT p.id, p.staff_number, trim(p.surname || ', ' || p.given_names) AS name, p.surname, p.given_names, p.email, p.phone,
                       sr.present_rank, sr.sex, sr.salary_scale, sr.contiss_step, sr.date_first_appointment, sr.unit_as_given,
                       coalesce(u.name, d.name, f.name) AS placed_in,
                       CASE WHEN u.code IS NOT NULL THEN 'UNIT' WHEN d.code IS NOT NULL THEN 'DEPARTMENT' WHEN f.code IS NOT NULL THEN 'FACULTY' END AS placed_kind,
                       coalesce(u.college_code, 'MAIN') AS campus, pu.name AS parent_unit,
                       (c.person_id IS NOT NULL) AS has_signin
                  FROM iam.person p JOIN hrm.staff_record sr ON sr.person_id = p.id
                  LEFT JOIN ref.unit u ON u.code = sr.home_unit LEFT JOIN ref.unit pu ON pu.code = u.parent_code
                  LEFT JOIN ref.department d ON d.code = sr.home_department LEFT JOIN ref.faculty f ON f.code = sr.home_faculty
                  LEFT JOIN iam.credential c ON c.person_id = p.id
                 WHERE p.ended_on IS NULL AND sr.category = 'NON_ACADEMIC'
                   AND (:q::text IS NULL OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%' OR p.staff_number ILIKE '%' || :q || '%'
                        OR coalesce(u.name, d.name, f.name) ILIKE '%' || :q || '%')
                 ORDER BY p.surname, p.given_names
                """).param("q", q == null || q.isBlank() ? null : q.trim()).query().listOfRows();
    }

    /** the unit register, with how many staff each holds */
    @GetMapping("/units")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> units() {
        return jdbc.sql("""
                SELECT u.code, u.name, u.kind, u.parent_code, pu.name AS parent, u.college_code, u.ended_on,
                       u.card_name, ref.unit_card_name(u.code) AS card_prints,   -- V748: what a staff identity card prints for the unit
                       (SELECT count(*) FROM hrm.staff_record sr JOIN iam.person p ON p.id = sr.person_id WHERE sr.home_unit = u.code AND p.ended_on IS NULL) AS staff,
                       (SELECT count(*) FROM ref.unit_alias a WHERE a.unit_code = u.code) AS spellings
                  FROM ref.unit u LEFT JOIN ref.unit pu ON pu.code = u.parent_code
                 ORDER BY coalesce(u.college_code, ''), coalesce(pu.name, u.name), (u.parent_code IS NOT NULL), u.name
                """).query().listOfRows();
    }

    /** V748: the short name a unit prints on staff identity cards as the department, set (or cleared, with an empty name) by ICT */
    public record UnitCardName(@jakarta.validation.constraints.Size(max = 60) String cardName,
                               @NotBlank @jakarta.validation.constraints.Size(min = 10, max = 500) String reason) {
    }

    @org.springframework.web.bind.annotation.PutMapping("/units/{code}/card-name")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_super')")
    @Transactional
    Map<String, Object> unitCardName(@org.springframework.web.bind.annotation.PathVariable String code, @Valid @RequestBody UnitCardName body) {
        String prints = jdbc.sql("SELECT ref.set_unit_card_name(:c, :n, :r)").param("c", code)
                .param("n", body.cardName(), java.sql.Types.VARCHAR).param("r", body.reason()).query(String.class).single();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("code", code.trim().toUpperCase());
        out.put("cardName", body.cardName() == null || body.cardName().isBlank() ? null : body.cardName().trim());
        out.put("cardPrints", prints);
        return out;
    }

    /* ── V656: staff deleted or deactivated, the database deciding what each person is tied to ─────────────────────────────── */

    public record RemoveStaff(@jakarta.validation.constraints.NotEmpty @jakarta.validation.constraints.Size(max = 500) List<UUID> ids,
                              @jakarta.validation.constraints.Size(max = 12) String mode,
                              @jakarta.validation.constraints.Size(max = 40) String reasonCode,
                              @jakarta.validation.constraints.Size(max = 500) String reason) {
    }

    public record RestoreStaff(@NotBlank @jakarta.validation.constraints.Size(max = 40) String reasonCode,
                               @jakarta.validation.constraints.Size(max = 500) String reason) {
    }

    /** a jsonb column read as text in the query, handed back as JSON */
    private List<Map<String, Object>> parsed(List<Map<String, Object>> rows, String column) {
        List<Map<String, Object>> out = new java.util.ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new java.util.LinkedHashMap<>(r);
            Object v = m.get(column);
            m.put(column, v == null ? List.of() : json.readValue(v.toString(), List.class));
            out.add(m);
        }
        return out;
    }

    private List<Map<String, Object>> removal(RemoveStaff b, boolean apply) {
        return parsed(jdbc.sql("""
                SELECT r.person_id, r.staff_number, r.name, r.category, r.ties::text AS ties, r.outcome, r.detail, r.applied, r.change_id
                  FROM iam.remove_staff(:ids, :mode, :code, :reason, :apply) r
                """).param("ids", b.ids().toArray(UUID[]::new)).param("mode", b.mode(), java.sql.Types.VARCHAR)
                .param("code", b.reasonCode(), java.sql.Types.VARCHAR).param("reason", b.reason(), java.sql.Types.VARCHAR)
                .param("apply", apply).query().listOfRows(), "ties");
    }

    /** what deleting these staff would do — each person, what they are tied to, deleted or deactivated or refused; nothing written */
    @PostMapping("/staff/remove/preview")
    @PreAuthorize(STAFF_LOADERS)
    @Transactional
    List<Map<String, Object>> previewRemoval(@Valid @RequestBody RemoveStaff body) {
        return removal(body, false);
    }

    /** delete the staff tied to nothing, deactivate the rest (or as the mode says), with the reason; each kept on iam.staff_change */
    @PostMapping("/staff/remove")
    @PreAuthorize(STAFF_LOADERS)
    @Transactional
    Map<String, Object> removeStaff(@Valid @RequestBody RemoveStaff body) {
        List<Map<String, Object>> rows = removal(body, true);
        long removed = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("applied")) && "REMOVE".equals(r.get("outcome"))).count();
        long deactivated = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("applied")) && "DEACTIVATE".equals(r.get("outcome"))).count();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("removed", removed);
        out.put("deactivated", deactivated);
        out.put("refused", rows.size() - removed - deactivated);
        out.put("rows", rows);
        return out;
    }

    /** the staff deleted, deactivated and restored, newest first; a deactivation says whether it can be restored */
    @GetMapping("/staff/removed")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> removedStaff(@RequestParam(required = false) String category) {
        String c = category == null ? null : category.trim().toUpperCase();
        if (c != null && !List.of("ACADEMIC", "NON_ACADEMIC").contains(c)) c = null;
        return parsed(jdbc.sql("""
                SELECT s.id, s.person_id, s.staff_number, s.name, s.category, s.action, s.reason_code, s.reason_words, s.reason, s.ties::text AS ties,
                       s.actor_name, s.actor_office, s.at, s.restorable, s.restored_at
                  FROM iam.staff_changes(:c) s
                """).param("c", c, java.sql.Types.VARCHAR).query().listOfRows(), "ties");
    }

    /** a deactivation undone: back on the lists, able to sign in, the grants it ended reopened */
    @PostMapping("/staff/removed/{id}/restore")
    @PreAuthorize(STAFF_LOADERS)
    @Transactional
    Map<String, Object> restoreStaff(@PathVariable UUID id, @Valid @RequestBody RestoreStaff body) {
        return jdbc.sql("SELECT r.person_id, r.name, r.grants_reopened, r.change_id FROM iam.restore_staff(:id, :code, :reason) r")
                .param("id", id).param("code", body.reasonCode()).param("reason", body.reason(), java.sql.Types.VARCHAR).query().singleRow();
    }

    public record EditLecturer(@NotBlank String surname, @NotBlank String givenNames, String email, String phone,
                               String sex, String rank, Integer conuass, @NotBlank String department) {
    }

    /** edit one lecturer: names, contact, sex, rank, CONUASS and home department. See iam.update_lecturer (V140). */
    @PutMapping("/lecturers/{id}")
    @PreAuthorize(CREDENTIALS)
    @Transactional
    Map<String, Object> updateLecturer(@PathVariable UUID id, @Valid @RequestBody EditLecturer b) {
        jdbc.sql("SELECT iam.update_lecturer(:id, :sn, :gn, :em, :ph, :sx, :rk, :cn, :dp)")
                .param("id", id).param("sn", b.surname()).param("gn", b.givenNames())
                .param("em", b.email(), java.sql.Types.VARCHAR).param("ph", b.phone(), java.sql.Types.VARCHAR)
                .param("sx", b.sex(), java.sql.Types.VARCHAR).param("rk", b.rank(), java.sql.Types.VARCHAR)
                .param("cn", b.conuass(), java.sql.Types.INTEGER).param("dp", b.department())
                .query().singleRow();
        return Map.of("id", id, "updated", true);
    }

    /** the teaching staff on record — every person holding the lecturer office, with their home
     *  department, rank and whether a sign-in has been issued. Read after an upload to confirm it. */
    @GetMapping("/lecturers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> lecturers(@RequestParam(required = false) String q) {
        return jdbc.sql("""
                SELECT p.id, p.staff_number, trim(p.surname || ', ' || p.given_names) AS name,
                       p.surname, p.given_names, p.email, p.phone,
                       sr.present_rank, sr.sex, sr.conuass_step, sr.home_department AS home_dept_code,
                       coalesce(hd.name, sr.home_department) AS home_department,
                       (SELECT string_agg(DISTINCT dd.name, ', ' ORDER BY dd.name)
                          FROM iam.office_assignment a LEFT JOIN ref.department dd ON dd.code = a.scope_id
                         WHERE a.person_id = p.id AND a.office_code = 'lecturer' AND a.scope_kind = 'department'
                           AND (a.valid_to IS NULL OR a.valid_to >= current_date)) AS departments,
                       (c.person_id IS NOT NULL) AS has_signin, coalesce(c.must_change, false) AS must_change,
                       c.username, c.last_sign_in_at
                  FROM iam.person p
                  LEFT JOIN hrm.staff_record sr ON sr.person_id = p.id
                  LEFT JOIN ref.department hd ON hd.code = sr.home_department
                  LEFT JOIN iam.credential c ON c.person_id = p.id
                 WHERE p.ended_on IS NULL
                   AND EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = p.id AND a.office_code = 'lecturer'
                                AND a.scope_kind = 'department' AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                   AND (:q::text IS NULL OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%'
                        OR p.staff_number ILIKE '%' || :q || '%')
                 ORDER BY p.surname, p.given_names
                """).param("q", q == null || q.isBlank() ? null : q.trim()).query().listOfRows();
    }

    @GetMapping("/persons")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<PersonRow> persons(@RequestParam(required = false) String q) {
        return jdbc.sql("""
                SELECT p.id, p.staff_number, p.surname, p.given_names, p.email, p.phone, p.ended_on, c.username, coalesce(c.must_change, false) AS must_change,
                       c.last_sign_in_at, c.locked_until, (SELECT count(*) FROM iam.live_offices(p.id)) AS live_offices
                  FROM iam.person p LEFT JOIN iam.credential c ON c.person_id = p.id
                 WHERE :q::text IS NULL OR p.surname ILIKE '%' || :q || '%' OR p.given_names ILIKE '%' || :q || '%'
                       OR p.staff_number ILIKE '%' || :q || '%' OR c.username ILIKE '%' || :q || '%'
                 ORDER BY p.surname, p.given_names
                """).param("q", q == null || q.isBlank() ? null : q.trim()).query(PersonRow.class).list();
    }

    /** every grant, newest first, as the prototype's table shows them */
    @GetMapping("/office-assignments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<GrantRow> grants(@RequestParam(defaultValue = "false") boolean ended) {
        return jdbc.sql("""
                SELECT a.id, a.person_id, p.surname, p.given_names, p.staff_number, a.office_code, o.label, a.scope_kind, a.scope_id,
                       iam.live_scope_code(a.scope_kind, a.scope_id) AS scope_live,
                       a.instrument, a.granted_by,
                       (SELECT g.surname || ', ' || g.given_names FROM iam.person g WHERE g.id = a.granted_by) AS granted_by_name,
                       a.valid_from, a.valid_to
                  FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id JOIN ref.office o ON o.code = a.office_code
                 WHERE :ended OR a.valid_to IS NULL OR a.valid_to >= current_date
                 ORDER BY a.valid_from DESC, p.surname
                """).param("ended", ended).query(GrantRow.class).list();
    }

    @PutMapping("/persons/{id}/credential")
    @PreAuthorize(CREDENTIALS)
    Map<String, Object> credential(@PathVariable UUID id, @Valid @RequestBody SetCredential body) {
        return auth.setCredential(id, body.username(), body.password());
    }

    /** V319: a live grant amended in place — the office, the scope, the instrument, the dates — with the reason on the
     *  record. The person is never changed: a grant to the wrong person is ended and made again. */
    @PutMapping("/persons/{id}/office-assignments/{grant}")
    @PreAuthorize(GRANTORS)
    @Transactional
    GrantRow amend(@PathVariable UUID id, @PathVariable UUID grant, @Valid @RequestBody AmendGrant body) {
        boolean theirs = jdbc.sql("SELECT EXISTS (SELECT 1 FROM iam.office_assignment WHERE id = :g AND person_id = :p)")
                .param("g", grant).param("p", id).query(Boolean.class).single();
        if (!theirs) {
            throw new ng.edu.moaum.portal.shared.NotFound("office assignment", grant);
        }
        jdbc.sql("SELECT iam.amend_grant(:g, :o, :k, :s, :i, :f, :t, :r)")
                .param("g", grant).param("o", body.officeCode().trim()).param("k", body.scopeKind().trim())
                .param("s", body.scopeId() == null || body.scopeId().isBlank() ? null : body.scopeId().trim(), java.sql.Types.VARCHAR)
                .param("i", body.instrument().trim())
                .param("f", body.validFrom(), java.sql.Types.DATE).param("t", body.validTo(), java.sql.Types.DATE)
                .param("r", body.reason().trim()).query().listOfRows();
        return jdbc.sql("""
                SELECT a.id, a.person_id, p.surname, p.given_names, p.staff_number, a.office_code, o.label, a.scope_kind, a.scope_id,
                       iam.live_scope_code(a.scope_kind, a.scope_id) AS scope_live,
                       a.instrument, a.granted_by,
                       (SELECT g.surname || ', ' || g.given_names FROM iam.person g WHERE g.id = a.granted_by) AS granted_by_name,
                       a.valid_from, a.valid_to
                  FROM iam.office_assignment a JOIN iam.person p ON p.id = a.person_id JOIN ref.office o ON o.code = a.office_code
                 WHERE a.id = :g
                """).param("g", grant).query(GrantRow.class).single();
    }

    @PostMapping("/persons/{id}/office-assignments/{grant}/end")
    @PreAuthorize(GRANTORS)
    @Transactional
    Map<String, Object> end(@PathVariable UUID id, @PathVariable UUID grant, @Valid @RequestBody EndGrant body) {
        jdbc.sql("SELECT iam.end_grant(:g, :on, :r)").param("g", grant).param("on", body.on() == null ? LocalDate.now() : body.on())
                .param("r", body.reason()).query().singleRow();
        return Map.of("grant", grant, "endedOn", body.on() == null ? LocalDate.now() : body.on());
    }

    /** the offices; V754: with the unit each belongs to, what a staff card prints for it and how many hold it now */
    @GetMapping("/offices")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> offices() {
        return jdbc.sql("""
                SELECT o.code, o.label, o.scope_kind,
                       o.unit_code, u.name AS unit, ref.unit_card_name(o.unit_code) AS card_prints,
                       (SELECT count(*) FROM iam.office_assignment a
                         WHERE a.office_code = o.code AND a.valid_from <= current_date
                           AND (a.valid_to IS NULL OR a.valid_to >= current_date)) AS holders
                  FROM ref.office o LEFT JOIN ref.unit u ON u.code = o.unit_code
                 ORDER BY o.label
                """).query().listOfRows();
    }

    /** V754: the unit an office belongs to, set (or cleared, with an empty unit) by ICT — a staff card prints it as the department
     *  of someone the HR record places nowhere who holds the office (V751) */
    public record OfficeUnit(@jakarta.validation.constraints.Size(max = 40) String unitCode,
                             @NotBlank @jakarta.validation.constraints.Size(min = 10, max = 500) String reason) {
    }

    @PutMapping("/offices/{code}/unit")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_super')")
    @Transactional
    Map<String, Object> officeUnit(@PathVariable String code, @Valid @RequestBody OfficeUnit body) {
        // V754: read as a row, since a cleared unit prints nothing (null)
        Object prints = jdbc.sql("SELECT ref.set_office_unit(:o, :u, :r) AS prints").param("o", code)
                .param("u", body.unitCode(), java.sql.Types.VARCHAR).param("r", body.reason()).query().singleRow().get("prints");
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("code", code.trim().toLowerCase());
        out.put("unitCode", body.unitCode() == null || body.unitCode().isBlank() ? null : body.unitCode().trim().toUpperCase());
        out.put("cardPrints", prints);
        return out;
    }
}
