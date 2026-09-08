package ng.edu.moaum.portal.results;

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

    private final ResultsRepository repo;

    ResultsService(ResultsRepository repo) {
        this.repo = repo;
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
}
