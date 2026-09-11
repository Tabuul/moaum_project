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

    public record MigrationIn(@NotBlank String session, @NotNull @Min(1) @Max(3) Integer semester,
                              @NotNull List<Map<String, Object>> rows) {
    }

    public record StudentsIn(@NotNull List<Map<String, Object>> rows) {
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
    public Map<String, Object> importStudents(List<Map<String, Object>> rows) {
        requireRows(rows);
        return repo.importStudents(json.writeValueAsString(rows));
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
                r.session(), r.semester(), r.stage(), Sheets.spine(r.stage()), r.dueOn(), daysLate, r.returnedTimes(),
                r.lecturer(), r.candidates(), failRate, mayAct, blocked);
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
        List<Sheets.Row> rows = repo.sheets(fac, dept, prog, course, session, sem, stage);
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
        long expected = repo.offeringsWithLecturer(fac, dept, session, sem);
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
        for (ScoreIn s : in.scores()) {
            String outcome = s.outcome() == null ? "GRADED" : s.outcome();
            ResultsRepository.Latest was = repo.latest(id, s.studentId()).orElse(null);
            if (was != null && Objects.equals(was.ca(), s.ca()) && Objects.equals(was.exam(), s.exam()) && was.outcome().equals(outcome)) {
                continue;
            }
            int version = was == null ? 1 : was.version() + 1;
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
        UUID id = repo.createExamSession(in);
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
        for (Sheets.Row r : repo.sheets(null, null, null, null, e.session(), e.semester(), "ENTRY")) {
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
            out.add(new Sheets.MySheet(r.id(), r.courseCode(), r.courseTitle(), r.units(), r.session(), r.semester(), r.stage(),
                    Sheets.spine(r.stage()), r.dueOn(), daysLate, r.returnedTimes(), r.candidates(), r.entered(), r.graded(),
                    r.secondExaminer(), me != null && me.equals(r.lecturerId())));
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
        Map<UUID, List<Sheets.BroadsheetCell>> byStudent = new LinkedHashMap<>();
        for (Sheets.BroadsheetCell c : cells) {
            courses.putIfAbsent(c.courseCode(), c.units());
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
            BigDecimal points = BigDecimal.ZERO;
            int pending = 0;
            boolean failed = false;
            Sheets.BroadsheetCell first = e.getValue().getFirst();
            for (String code : courses.keySet()) {
                Sheets.BroadsheetCell c = e.getValue().stream().filter(x -> x.courseCode().equals(code)).findFirst().orElse(null);
                if (c == null) {
                    marks.add(new Sheets.BroadsheetMark(code, "NOT_REGISTERED", null, null, null, null, false));
                    continue;
                }
                boolean counted = COUNTED.contains(c.stage()) && "GRADED".equals(c.outcome()) && c.points() != null;
                if (counted) {
                    units += c.units();
                    points = points.add(c.points().multiply(BigDecimal.valueOf(c.units())));
                    if (c.points().signum() == 0) {
                        failed = true;
                    }
                } else {
                    pending++;
                }
                marks.add(new Sheets.BroadsheetMark(code, c.stage(), counted ? c.total() : null, counted ? c.grade() : null,
                        counted ? c.points() : null, c.outcome(), counted));
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
            rows.add(new Sheets.BroadsheetRow(e.getKey(), first.number(), first.surname() + ", " + first.otherNames(), marks, units,
                    points, gpa, pending, standing));
        }
        BigDecimal mean = withGpa == 0 ? null : gpaSum.divide(BigDecimal.valueOf(withGpa), 2, RoundingMode.HALF_UP);
        List<Sheets.BroadsheetCourse> cs = courses.entrySet().stream().map(x -> new Sheets.BroadsheetCourse(x.getKey(), x.getValue())).toList();
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
