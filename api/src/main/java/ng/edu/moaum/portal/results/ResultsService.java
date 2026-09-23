package ng.edu.moaum.portal.results;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ResultsService {

    public record ScoreIn(@NotNull UUID studentId, Integer ca, Integer exam, String outcome, String reason) {
    }

    public record ScoresIn(@NotNull List<ScoreIn> scores) {
    }

    public record ExamSessionIn(@NotBlank String session, @NotNull @Min(1) @Max(3) Integer semester, String kind,
                                @NotNull LocalDate examsFrom, @NotNull LocalDate examsTo, @NotNull LocalDate sheetsDue) {
    }

    public record ExamEditIn(@NotBlank String session, @NotNull @Min(1) @Max(3) Integer semester, String kind,
                             @NotNull LocalDate examsFrom, @NotNull LocalDate examsTo, @NotNull LocalDate sheetsDue) {
    }

    /** the three dates are ordered: begin ≤ end ≤ sheets due. A clear message beats the raw DB constraint. */
    private static void checkExamDates(LocalDate from, LocalDate to, LocalDate due) {
        if (to.isBefore(from)) {
            throw new DomainRuleViolation("EXAM_DATES", "The examinations end before they begin.",
                    new DomainRuleViolation.Remedy("Set the end date on or after the begin date.", "Examinations"));
        }
        if (due.isBefore(to)) {
            throw new DomainRuleViolation("EXAM_DATES", "The score sheets are due before the examinations end.",
                    new DomainRuleViolation.Remedy("Set the sheets-due date on or after the examinations end date.", "Examinations"));
        }
    }

    public record MigrationIn(@NotBlank String session, @NotNull @Min(1) @Max(3) Integer semester,
                              @NotNull List<Map<String, Object>> rows) {
    }

    public record StudentsIn(@NotNull List<Map<String, Object>> rows) {
    }

    /** one migrated passport photo: the file name (the JAMB reg no), its type, and its base64 bytes */
    public record PassportItem(@NotBlank String filename, String contentType, @NotBlank String contentBase64) {
    }

    public record PassportsIn(@NotNull List<PassportItem> items) {
    }

    private final ResultsRepository repo;
    private final TransactionTemplate eachInItsOwn;
    private final tools.jackson.databind.ObjectMapper json;

    ResultsService(ResultsRepository repo, PlatformTransactionManager transactions, tools.jackson.databind.ObjectMapper json) {
        this.repo = repo;
        this.json = json;
        this.eachInItsOwn = new TransactionTemplate(transactions);
        this.eachInItsOwn.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    /* ── migration from the old portal (V082) ── */

    @Transactional
    public Map<String, Object> setDefaultPasswords() {
        return repo.setDefaultPasswords();
    }

    @Transactional
    public Map<String, Object> importStudents(List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importStudents(json.writeValueAsString(rows));
    }

    @Transactional
    public Map<String, Object> importBiography(List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importBiography(json.writeValueAsString(rows));
    }

    @Transactional
    public Map<String, Object> importPostgraduate(List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importPostgraduate(json.writeValueAsString(rows));
    }

    /** post every past result held for a student who has since been loaded (V204) */
    @Transactional
    public Map<String, Object> reconcileHolding() {
        return repo.reconcileHolding();
    }

    @Transactional
    public Map<String, Object> importJambNumbers(List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.setJambNumbers(json.writeValueAsString(rows));
    }

    @Transactional
    public Map<String, Object> importRegistration(String session, int semester, List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importLegacy(session, semester, json.writeValueAsString(rows), false);
    }

    @Transactional
    public Map<String, Object> importResults(String session, int semester, List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importLegacy(session, semester, json.writeValueAsString(rows), true);
    }

    /** the postgraduate course registration of a past session/semester, into the postgraduate module (V214) */
    @Transactional
    public Map<String, Object> importPgRegistration(String session, int semester, List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importLegacyPg(session, semester, json.writeValueAsString(rows), false);
    }

    /** the postgraduate past results of a session/semester, graded on the postgraduate scale (V214) */
    @Transactional
    public Map<String, Object> importPgResults(String session, int semester, List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importLegacyPg(session, semester, json.writeValueAsString(rows), true);
    }

    /** post every held postgraduate result whose student has since been loaded (V214) */
    @Transactional
    public Map<String, Object> reconcilePgHolding() {
        return repo.reconcilePgHolding();
    }

    /** the postgraduate research / thesis record brought over from the old portal (V215) */
    @Transactional
    public Map<String, Object> importPgResearch(List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importPgResearch(json.writeValueAsString(rows));
    }

    /* ── bulk passport photos from the old portal (matched by JAMB reg no in the file name) ── */

    private static final java.util.Set<String> IMG_OK = java.util.Set.of("image/jpeg", "image/png", "application/pdf");
    private static final int DOC_MAX = 2_097_152; // the document store's 2 MB cap
    private static final java.util.regex.Pattern JAMB_TOKEN = java.util.regex.Pattern.compile("(\\d{6,}[A-Za-z]{0,3})");

    /** store many passport photos, each matched to a student by the JAMB reg no in its file name; a file with
     *  no matching candidate is skipped (counted, and its number listed). Each photo is its own transaction, so
     *  one bad image does not lose the batch. */
    public Map<String, Object> importPassports(List<PassportItem> items) {
        if (items == null || items.isEmpty()) {
            throw new DomainRuleViolation("RES_PASSPORT_NONE", "No image was uploaded.",
                    new DomainRuleViolation.Remedy("Select the passport image files exported from the old portal.", "Records"));
        }
        int stored = 0, attached = 0, notFound = 0, skipped = 0;
        List<String> notFoundList = new ArrayList<>();
        for (PassportItem it : items) {
            String status;
            try {
                status = eachInItsOwn.execute(tx -> storeOnePassport(it));
            } catch (RuntimeException e) {
                status = "SKIPPED";
            }
            switch (status == null ? "SKIPPED" : status) {
                case "STORED" -> stored++;
                case "ATTACHED" -> attached++;
                case "NOT_FOUND" -> { notFound++; if (notFoundList.size() < 500) notFoundList.add(jambFromName(it.filename())); }
                default -> skipped++;
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", items.size());
        out.put("stored", stored);
        out.put("attached", attached);
        out.put("notFound", notFound);
        out.put("skipped", skipped);
        out.put("notFoundList", notFoundList);
        return out;
    }

    private String storeOnePassport(PassportItem it) {
        String raw = stripDataUrl(it.contentBase64());
        byte[] content;
        try {
            content = java.util.Base64.getDecoder().decode(raw);
        } catch (RuntimeException e) {
            return "SKIPPED";
        }
        if (content.length == 0) {
            return "SKIPPED";
        }
        String ct = normPassportType(it.contentType(), it.filename());
        String base = passportKey(it.filename());
        String key = jambFromName(it.filename());              // the JAMB number, with " _Face"/"_photo" etc. dropped
        String cleaned = base.replaceAll("(?i)[\\s_\\-]*(face|photo|passport|pix|pic|image)\\s*$", "").trim().toUpperCase();
        String tok = (!cleaned.isEmpty() && !cleaned.equals(key)) ? cleaned : null;  // a lenient fallback
        boolean docOk = IMG_OK.contains(ct) && content.length <= DOC_MAX;
        return repo.storePassport(key, tok, it.filename(), ct, content, raw, docOk);
    }

    /** the file name without any path or extension, trimmed — the JAMB reg no as the old portal named the file */
    private static String passportKey(String filename) {
        String n = filename == null ? "" : filename.trim();
        int slash = Math.max(n.lastIndexOf('/'), n.lastIndexOf('\\'));
        if (slash >= 0) n = n.substring(slash + 1);
        int dot = n.lastIndexOf('.');
        if (dot > 0) n = n.substring(0, dot);
        return n.trim();
    }

    /** the JAMB registration number carried by a photo's file name: the leading run of digits with up to three
     *  trailing letters, upper-cased. This drops a " _Face" / "_photo" suffix and any spaces, so
     *  "202441922663AF _Face.jpg" yields "202441922663AF" — exactly what the register stores. Falls back to the
     *  cleaned base name when the name has no JAMB-shaped token. */
    private static String jambFromName(String filename) {
        String base = passportKey(filename);
        java.util.regex.Matcher m = JAMB_TOKEN.matcher(base);
        if (m.find()) {
            return m.group(1).toUpperCase();
        }
        return base.replaceAll("(?i)[\\s_\\-]*(face|photo|passport|pix|pic|image)\\s*$", "").trim().toUpperCase();
    }

    /** the base64, with any "data:...;base64," prefix removed */
    private static String stripDataUrl(String b64) {
        if (b64 == null) return "";
        int comma = b64.indexOf(',');
        return b64.startsWith("data:") && comma >= 0 ? b64.substring(comma + 1) : b64;
    }

    /** a servable image type for the document store — from the given type, else the file extension, else JPEG */
    private static String normPassportType(String contentType, String filename) {
        String t = contentType == null ? "" : contentType.trim().toLowerCase();
        if (t.equals("image/jpg") || t.equals("image/pjpeg")) return "image/jpeg";
        if (IMG_OK.contains(t)) return t;
        String f = (filename == null ? "" : filename).toLowerCase();
        if (f.endsWith(".png")) return "image/png";
        if (f.endsWith(".pdf")) return "application/pdf";
        return "image/jpeg";
    }

    private static void requireRows(List<Map<String, Object>> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new DomainRuleViolation("RES_MIGRATE_ROWS", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Export the list from the old portal and upload it.", "Examinations Officer"));
        }
    }

    private Sheets.Listed listed(Sheets.Row r, AuditContext ctx) {
        Integer daysLate = null;
        if ("ENTRY".equals(r.stage()) && r.dueOn() != null && r.dueOn().isBefore(LocalDate.now())) {
            daysLate = (int) ChronoUnit.DAYS.between(r.dueOn(), LocalDate.now());
        }
        Integer failRate = r.graded() == 0 ? null : (int) Math.round(100.0 * r.failed() / r.graded());
        boolean mayAct = ctx != null && Sheets.DESK.getOrDefault(r.stage(), List.of()).contains(ctx.actorOffice());
        boolean blocked = ctx != null && r.lastActor() != null && r.lastActor().equals(ctx.actorId());
        return new Sheets.Listed(r.id(), r.courseCode(), r.courseTitle(), r.units(), r.deptName(), r.facultyName(),
                r.session(), r.semester(), r.stage(), Sheets.spine(r.stage()), r.sitting(), r.dueOn(), daysLate, r.returnedTimes(),
                r.lecturer(), r.candidates(), failRate, mayAct, blocked, r.caMax(), r.heldScripts());
    }

    private static String desk(String office) {
        return switch (office == null ? "" : office) {
            case "hod" -> "Departmental board";
            case "dean" -> "Faculty Board";
            case "records" -> "Exams & Records validation";
            case "registrar", "dregistrar" -> "Senate";
            case "exams" -> "Verification";
            case "facultyexams" -> "Faculty scrutiny";
            case "facultyofficer" -> "Faculty compilation";
            default -> "";
        };
    }

    @Transactional(readOnly = true)
    public Sheets.Listing sheets(String fac, String dept, String prog, String course, String session, Integer sem, String stage) {
        AuditContext ctx = AuditContextHolder.current().orElse(null);
        String office = ctx == null ? null : ctx.actorOffice();
        // acting as a lecturer, you see only the sheets of the courses assigned to you — never the whole faculty
        UUID mine = "lecturer".equals(office) ? ctx.actorId() : null;
        // acting as a Head of Department, you see only your own department (and the programmes under it)
        if ("hod".equals(office)) {
            String hodDept = repo.officeDepartment(ctx.actorId(), "hod");
            fac = null;                                    // the department fixes the faculty
            dept = hodDept != null ? hodDept : "__none__"; // no department grant → nothing to show
        }
        List<Sheets.Row> rows = repo.sheets(fac, dept, prog, course, session, sem, stage, mine);
        List<Sheets.Listed> out = new ArrayList<>();
        long approved = 0;
        long entry = 0;
        for (Sheets.Row r : rows) {
            out.add(listed(r, ctx));
            if ("PUBLISHED".equals(r.stage())) {
                approved++;
            } else if ("ENTRY".equals(r.stage())) {
                entry++;
            }
        }
        long expected = repo.offeringsWithLecturer(fac, dept, session, sem, mine);
        return new Sheets.Listing(new Sheets.Tiles(expected, approved, rows.size() - approved - entry, Math.max(entry, expected - rows.size() + entry)),
                out, desk(ctx == null ? null : ctx.actorOffice()));
    }

    @Transactional(readOnly = true)
    public Sheets.Detail sheet(UUID id) {
        Sheets.Row r = repo.sheet(id).orElseThrow(() -> new NotFound("score sheet", id));
        ResultsRepository.Examiner x = repo.examiner(id);
        return new Sheets.Detail(listed(r, AuditContextHolder.current().orElse(null)), x.secondExaminer(), x.senateMinute(),
                x.publishedAt(), x.engineVersion(), repo.chain(id), repo.marks(id));
    }

    /** A mark is never overwritten: a change appends a version with its reason. */
    @Transactional
    public Map<String, Object> scores(UUID id, ScoresIn in) {
        Sheets.Row r = repo.sheet(id).orElseThrow(() -> new NotFound("score sheet", id));
        if (!"ENTRY".equals(r.stage())) {
            throw new DomainRuleViolation("RES_SHEET_NOT_AT_ENTRY", "The sheet is at " + r.stage().toLowerCase().replace('_', ' ')
                    + "; a mark changes by amendment with a reason, not by entry.",
                    new DomainRuleViolation.Remedy("Return the sheet to the lecturer, with the reason on the record.", "The desk holding it"));
        }
        int written = 0;
        Boolean returned = null;
        int caMax = r.caMax(), examMax = 100 - r.caMax();
        for (ScoreIn s : in.scores()) {
            String outcome = s.outcome() == null ? "GRADED" : s.outcome();
            if ((s.ca() != null && (s.ca() < 0 || s.ca() > caMax)) || (s.exam() != null && (s.exam() < 0 || s.exam() > examMax))) {
                throw new DomainRuleViolation("RES_MARK_OUTSIDE_SPLIT",
                        r.courseCode() + " assesses out of " + caMax + " and examines out of " + examMax + "; a mark outside that was entered.",
                        new DomainRuleViolation.Remedy("Enter the CA out of " + caMax + " and the examination out of " + examMax + ". The split is set on the department's catalogue.", "Course lecturer"));
            }
            ResultsRepository.Latest was = repo.latest(id, s.studentId()).orElse(null);
            if (was != null && Objects.equals(was.ca(), s.ca()) && Objects.equals(was.exam(), s.exam()) && was.outcome().equals(outcome)) {
                continue;
            }
            int version = was == null ? 1 : was.version() + 1;
            // a mark once saved is on the record: the lecturer does not change it on their own. It changes,
            // with its reason, only after the Examination Officer or the Head of Department returns the sheet.
            if (version > 1) {
                if (returned == null) returned = repo.returnedToEntry(id);
                if (!returned) {
                    throw new DomainRuleViolation("RES_MARK_ON_RECORD", "A saved mark is on the record; the lecturer does not change it on their own.",
                            new DomainRuleViolation.Remedy("Submit the sheet and ask the Examination Officer or the Head of Department to return it with the reason; the mark can then be amended.", "Course lecturer"));
                }
            }
            if (version > 1 && (s.reason() == null || s.reason().isBlank())) {
                throw new DomainRuleViolation("RES_AMENDMENT_SAYS_WHY", "An amended mark carries its reason.",
                        new DomainRuleViolation.Remedy("Say why the mark changes; the old value stays on the record.", "Course lecturer"));
            }
            repo.score(id, s.studentId(), version, s.ca(), s.exam(), outcome, s.reason());
            written++;
        }
        return Map.of("id", id, "written", written);
    }

    @Transactional
    public Map<String, Object> advance(UUID id, String comment, String minute) {
        repo.sheet(id).orElseThrow(() -> new NotFound("score sheet", id));
        String next = repo.advance(id, comment, minute);
        return Map.of("id", id, "stage", next);
    }

    @Transactional
    public Map<String, Object> giveBack(UUID id, String comment) {
        repo.sheet(id).orElseThrow(() -> new NotFound("score sheet", id));
        if (comment == null || comment.isBlank()) {
            throw new DomainRuleViolation("RES_RETURN_SAYS_WHY", "A sheet is returned with the reason on the record.",
                    new DomainRuleViolation.Remedy("Say what the lecturer must correct.", "The desk returning it"));
        }
        repo.giveBack(id, comment);
        return Map.of("id", id, "stage", "ENTRY");
    }

    @Transactional(readOnly = true)
    public List<Sheets.ExamSession> examSessions(String session) {
        return repo.examSessions(session);
    }

    @Transactional
    public Sheets.ExamSession createExamSession(ExamSessionIn in) {
        checkExamDates(in.examsFrom(), in.examsTo(), in.sheetsDue());
        UUID id = repo.createExamSession(in);
        return repo.examSession(id).orElseThrow();
    }

    /** Edit an examination session. The dates are always editable while it is a draft or open (they are
     *  metadata and do not undo any generated sheet). The academic session, semester and type may be changed
     *  only while NO score sheet has been generated — once sheets exist they belong to that session/semester,
     *  so those are then fixed. A closed session is fixed entirely. */
    @Transactional
    public Sheets.ExamSession editExamSession(UUID id, ExamEditIn in) {
        Sheets.ExamSession cur = repo.examSession(id).orElseThrow(() -> new NotFound("examination session", id));
        if ("CLOSED".equals(cur.state())) {
            throw new DomainRuleViolation("EXAM_CLOSED", "A closed examination session cannot be changed.",
                    new DomainRuleViolation.Remedy("A closed session is a record; open a new session instead.", "Examinations"));
        }
        checkExamDates(in.examsFrom(), in.examsTo(), in.sheetsDue());
        String kind = in.kind() == null || in.kind().isBlank() ? "MAIN" : in.kind();
        boolean identityChanged = !cur.session().equals(in.session()) || cur.semester() != in.semester() || !cur.kind().equalsIgnoreCase(kind);
        if (identityChanged) {
            if (cur.sheets() > 0) {
                throw new DomainRuleViolation("EXAM_HAS_SHEETS",
                        "This session already has " + cur.sheets() + " score sheet(s), so its academic session, semester and type are fixed — only the dates can change.",
                        new DomainRuleViolation.Remedy("Move it before it is opened, or open a new session for the other academic session.", "Examinations"));
            }
            if (repo.examSessionExists(in.session(), in.semester(), kind, id)) {
                throw new DomainRuleViolation("EXAM_DUPLICATE",
                        "An examination session already exists for that academic session, semester and type.",
                        new DomainRuleViolation.Remedy("Edit that one instead, or choose a different type.", "Examinations"));
            }
        }
        repo.updateExamSession(id, in.session(), in.semester(), kind, in.examsFrom(), in.examsTo(), in.sheetsDue());
        return repo.examSession(id).orElseThrow();
    }

    @Transactional
    public Map<String, Object> open(UUID id) {
        repo.examSession(id).orElseThrow(() -> new NotFound("examination session", id));
        ResultsRepository.Opened o = repo.open(id);
        return Map.of("id", id, "sheetsMade", o.sheetsMade(), "offeringsWithoutLecturer", o.offeringsWithoutLecturer());
    }

    @Transactional(readOnly = true)
    public Sheets.Monitor monitor(UUID id) {
        Sheets.ExamSession e = repo.examSession(id).orElseThrow(() -> new NotFound("examination session", id));
        List<Sheets.Outstanding> outstanding = new ArrayList<>();
        for (Sheets.Row r : repo.sheets(null, null, null, null, e.session(), e.semester(), "ENTRY", null)) {
            Integer late = r.dueOn() != null && r.dueOn().isBefore(LocalDate.now())
                    ? (int) ChronoUnit.DAYS.between(r.dueOn(), LocalDate.now()) : null;
            outstanding.add(new Sheets.Outstanding(r.id(), r.courseCode(), r.deptName(), r.facultyCode(), r.lecturer(),
                    r.candidates(), late, late == null ? "—" : late < 6 ? "Head of Department" : "Dean"));
        }
        return new Sheets.Monitor(e, repo.progress(id), outstanding);
    }

    /* ── the lecturer's own sheets, and the roll under one (proto/part5, part28 scoreEntry) ── */

    @Transactional(readOnly = true)
    public List<Sheets.MySheet> mine(String session, Integer sem, boolean all) {
        AuditContext ctx = AuditContextHolder.current().orElse(null);
        UUID me = ctx == null ? null : ctx.actorId();
        List<Sheets.MySheet> out = new ArrayList<>();
        for (ResultsRepository.MineRow r : repo.mine(me, session, sem, all)) {
            Integer daysLate = null;
            if ("ENTRY".equals(r.stage()) && r.dueOn() != null && r.dueOn().isBefore(LocalDate.now())) {
                daysLate = (int) ChronoUnit.DAYS.between(r.dueOn(), LocalDate.now());
            }
            Integer daysToDue = r.dueOn() == null ? null : (int) ChronoUnit.DAYS.between(LocalDate.now(), r.dueOn());
            out.add(new Sheets.MySheet(r.id(), r.courseCode(), r.courseTitle(), r.units(), r.session(), r.semester(), r.stage(),
                    Sheets.spine(r.stage()), r.dueOn(), daysLate, daysToDue, r.returnedTimes(), r.candidates(), r.entered(), r.graded(),
                    r.secondExaminer(), me != null && me.equals(r.lecturerId()), r.openQueries(), r.bankQuestions(), r.caEntered(), r.heldScripts()));
        }
        return out;
    }

    @Transactional(readOnly = true)
    public List<Sheets.RollRow> roll(UUID id) {
        repo.sheet(id).orElseThrow(() -> new NotFound("score sheet", id));
        return repo.roll(id);
    }

    /* ── the broadsheet: computed from the sheets, never typed (proto/part26 tBroadsheet) ── */

    private static final List<String> COUNTED = List.of("RECORDS", "SENATE", "PUBLISHED");

    @Transactional(readOnly = true)
    public Sheets.Broadsheet broadsheet(String prog, int level, String session, int sem) {
        List<Sheets.BroadsheetCell> cells = repo.broadsheet(prog, level, session, sem);
        Map<String, Integer> courses = new LinkedHashMap<>();
        Map<String, String> courseKind = new LinkedHashMap<>();
        Map<String, String> courseTitle = new LinkedHashMap<>();
        Map<UUID, List<Sheets.BroadsheetCell>> byStudent = new LinkedHashMap<>();
        for (Sheets.BroadsheetCell c : cells) {
            courses.putIfAbsent(c.courseCode(), c.units());
            courseKind.putIfAbsent(c.courseCode(), c.kind());
            courseTitle.putIfAbsent(c.courseCode(), c.title());
            byStudent.computeIfAbsent(c.studentId(), k -> new ArrayList<>()).add(c);
        }
        List<Sheets.ClassBand> classes = repo.classBands();
        List<Sheets.BroadsheetRow> rows = new ArrayList<>();
        BigDecimal gpaSum = BigDecimal.ZERO;
        long withGpa = 0;
        long passed = 0;
        long carrying = 0;
        long pendingSets = cells.stream().filter(c -> !COUNTED.contains(c.stage())).map(Sheets.BroadsheetCell::courseCode).distinct().count();
        for (Map.Entry<UUID, List<Sheets.BroadsheetCell>> e : byStudent.entrySet()) {
            List<Sheets.BroadsheetMark> marks = new ArrayList<>();
            int units = 0;
            int cur = 0;   // credit units registered this semester
            int cue = 0;   // credit units earned (passed) this semester
            BigDecimal points = BigDecimal.ZERO;
            int pending = 0;
            boolean failed = false;
            List<String> failedHere = new ArrayList<>();   // this sheet's failures, ABS included, by course code
            Sheets.BroadsheetCell first = e.getValue().getFirst();
            for (String code : courses.keySet()) {
                Sheets.BroadsheetCell c = e.getValue().stream().filter(x -> x.courseCode().equals(code)).findFirst().orElse(null);
                if (c == null) {
                    marks.add(new Sheets.BroadsheetMark(code, "NOT_REGISTERED", null, null, null, null, false));
                    continue;
                }
                cur += c.units();   // registered: the student has a cell for this course
                boolean past = COUNTED.contains(c.stage());
                boolean counted = past && "GRADED".equals(c.outcome()) && c.points() != null;
                // no score at all, or absent, on a set past the Faculty Board: the candidate did not sit — an F, recorded ABS
                boolean absent = past && !counted && (c.outcome() == null || "ABSENT".equals(c.outcome()));
                if (counted) {
                    units += c.units();
                    points = points.add(c.points().multiply(BigDecimal.valueOf(c.units())));
                    if (c.points().signum() == 0) {
                        failed = true;
                        failedHere.add(code);
                    } else {
                        cue += c.units();   // earned: passed with points
                    }
                } else if (absent) {
                    units += c.units();
                    failed = true;
                    failedHere.add(code);
                } else {
                    pending++;
                }
                // a score still in the chain is carried with its figures so the sheet can show it as not yet counted
                marks.add(new Sheets.BroadsheetMark(code, c.stage(), absent ? null : c.total(), absent ? "F" : c.grade(),
                        absent ? BigDecimal.ZERO : c.points(), absent ? "ABSENT" : c.outcome(), counted || absent));
            }
            BigDecimal gpa = units == 0 ? null : points.divide(BigDecimal.valueOf(units), 2, RoundingMode.HALF_UP);
            String standing = gpa == null ? "Pending" : failed ? "Carryover" : "Pass";
            if (gpa != null) {
                gpaSum = gpaSum.add(gpa);
                withGpa++;
                if (failed) {
                    carrying++;
                } else {
                    passed++;
                }
            }
            Sheets.Cumulative cum = repo.cumulative(e.getKey(), session, sem);
            /* the CARRYOVER COLUMN is a carryover the student BROUGHT IN from an earlier period AND is
               re-writing this semester — one they now pass or fail again. Courses owed but not re-taken
               this semester stay in the remark, not the column. (Hidden entirely at 100 level in the UI.) */
            java.util.Set<String> writtenThisSheet = marks.stream()
                    .filter(m -> !"NOT_REGISTERED".equals(m.stage()))
                    .map(Sheets.BroadsheetMark::courseCode).collect(java.util.stream.Collectors.toSet());
            List<String> carry = repo.carryoversAt(e.getKey(), session, sem, false).stream()
                    .filter(writtenThisSheet::contains).toList();
            /* the REMARK is what the student owes AS OF this sheet: prior unpassed carryovers plus this
               semester's failures — scoped to this period, so a level not yet reached never appears. Plus
               any course on a PUBLISHED sheet whose score is still missing (a missing script), shown as
               pending until the score is found and the sheet re-viewed. */
            List<String> owed = new java.util.ArrayList<>(repo.carryoversAt(e.getKey(), session, sem, true));
            for (String f : failedHere) if (!owed.contains(f)) owed.add(f);
            boolean anyUnreleased = marks.stream().anyMatch(m -> !"NOT_REGISTERED".equals(m.stage()) && !COUNTED.contains(m.stage()));
            /* the REMARK reads as the Senate's sheet reads: TO GO ON PROBATION when the CGPA is under 1.0; CO: for
               every core course owed (a prior carryover, or failed or missed on this sheet); Fail: for an elective
               failed; PASS when nothing is owed; PENDING only while a set is still in the chain and nothing is owed */
            List<String> coreOwed = owed.stream().filter(x -> !"Elective".equals(courseKind.get(x))).sorted().toList();
            List<String> electiveOwed = owed.stream().filter(x -> "Elective".equals(courseKind.get(x))).sorted().toList();
            List<String> parts = new ArrayList<>();
            if (!coreOwed.isEmpty()) parts.add("CO: " + String.join(", ", coreOwed));
            if (!electiveOwed.isEmpty()) parts.add("Fail: " + String.join(", ", electiveOwed));
            // probation is judged from 200 level first semester on: a student whose CGPA is still under 1.0 by then is
            // to go on probation — said after the courses owed; a 100 level class has no standing to judge yet
            // a Direct Entry student's first semester (200 level first) has no standing to judge either
            boolean deFirst = "DIRECT_ENTRY".equals(first.entryMode()) && level == 200 && sem == 1;
            if (level >= 200 && !deFirst && cum.cgpa() != null && cum.cgpa().compareTo(BigDecimal.ONE) < 0) parts.add("TO GO ON PROBATION");
            String remarks = !parts.isEmpty() ? String.join(" · ", parts)
                    : anyUnreleased ? "PENDING"
                    : "PASS";
            rows.add(new Sheets.BroadsheetRow(e.getKey(), first.number(), first.surname() + ", " + first.otherNames(), marks, units,
                    cur, cue, points, gpa, pending, standing, cum.tcr(), cum.tce(), cum.twgp(), cum.cgpa(), cum.prevCgpa(), carry, remarks, first.entryMode()));
        }
        BigDecimal mean = withGpa == 0 ? null : gpaSum.divide(BigDecimal.valueOf(withGpa), 2, RoundingMode.HALF_UP);
        List<Sheets.BroadsheetCourse> cs = courses.entrySet().stream().map(x -> new Sheets.BroadsheetCourse(x.getKey(), courseTitle.get(x.getKey()), x.getValue(), courseKind.get(x.getKey()))).toList();
        return new Sheets.Broadsheet(prog, level, session, sem, cs, rows, mean, passed, carrying, pendingSets,
                repo.gradeBands(), classes, repo.gradingInstrument());
    }

    /* ── Senate: the schedule, and the minute that publishes (proto/part26 tSenate, tPublish) ── */

    @Transactional(readOnly = true)
    public Sheets.Senate senate(String session, int sem) {
        List<Sheets.SenateFaculty> f = repo.senateFaculties(session, sem);
        long sets = f.stream().mapToLong(Sheets.SenateFaculty::sets).sum();
        long at = f.stream().mapToLong(Sheets.SenateFaculty::atSenate).sum();
        long pub = f.stream().mapToLong(Sheets.SenateFaculty::published).sum();
        long out = f.stream().mapToLong(Sheets.SenateFaculty::outstanding).sum();
        List<Sheets.SenateMinute> minutes = repo.senateMinutes(session, sem);
        long cands = minutes.stream().mapToLong(Sheets.SenateMinute::candidates).sum();
        return new Sheets.Senate(session, sem, f, minutes, sets, at, pub, out, cands);
    }

    /**
     * The minute publishes every set waiting at Senate in the scope. Each set is
     * its own transaction: one the rules refuse (the same person took the
     * previous stage) is reported by name and does not hold the others.
     */
    public Map<String, Object> recordMinute(String session, int sem, String fac, String minute) {
        if (minute == null || minute.isBlank()) {
            throw new DomainRuleViolation("RES_MINUTE_REQUIRED", "A result reaches a student on the Senate minute that approved it, and none was cited.",
                    new DomainRuleViolation.Remedy("Cite the minute of the sitting that approved the results.", "Registrar"));
        }
        List<UUID> waiting = eachInItsOwn.execute(status -> repo.sheetsAtSenate(session, sem, fac));
        List<Map<String, Object>> published = new ArrayList<>();
        List<Map<String, Object>> refused = new ArrayList<>();
        for (UUID id : waiting == null ? List.<UUID>of() : waiting) {
            try {
                String stage = eachInItsOwn.execute(status -> repo.advance(id, null, minute.trim()));
                published.add(Map.of("id", id, "stage", stage == null ? "" : stage));
            } catch (RuntimeException refusedByTheRules) {
                String why = refusedByTheRules.getMessage() == null ? refusedByTheRules.getClass().getSimpleName() : refusedByTheRules.getMessage();
                refused.add(Map.of("id", id, "why", why.length() > 300 ? why.substring(0, 300) : why));
            }
        }
        return Map.of("session", session, "semester", sem, "minute", minute.trim(), "published", published, "refused", refused);
    }
}
