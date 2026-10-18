package ng.edu.moaum.portal.graduation;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class GraduationService {

    public record Exception(UUID studentId, String number, String surname, String otherNames, String programmeName,
                            String unmet, BigDecimal cgpa) {
    }

    public record ClassRow(String clazz, long students, int share, BigDecimal low, BigDecimal high) {
    }

    public record Tiles(long finalists, long auditPassed, long outstanding, long awaitingClearance, long approved) {
    }

    /** V416: a graduand's final clearance — its reference and overall word, NOT_STARTED when none is under way */
    public record Finalist(UUID studentId, String number, String surname, String otherNames, String programmeName, BigDecimal cgpa,
                           String unmet, String senateState, String clearanceRef, UUID clearanceProcess, String clearanceState) {
    }

    public record View(String session, Tiles tiles, List<Exception> exceptions, List<ClassRow> classification, List<Finalist> finalists) {
    }

    private final GraduationRepository repo;

    GraduationService(GraduationRepository repo) {
        this.repo = repo;
    }

    /** Computed, not compiled by hand: every finalist against the published record. */
    @Transactional
    public Map<String, Object> audit(String session) {
        int audited = 0;
        int passed = 0;
        for (GraduationRepository.Finalist f : repo.finalists(session)) {
            GraduationRepository.Standing st = repo.standing(f.studentId());
            String unmet = unmet(f.studentId(), f.postgraduate(), st);
            repo.upsert(f.studentId(), session, st.cgpa(), f.programmeName(), unmet);
            audited++;
            if (unmet == null) {
                passed++;
            }
        }
        return Map.of("session", session, "audited", audited, "passed", passed, "outstanding", audited - passed);
    }

    /** the requirement a graduand has not met, or null: every course graded, then the postgraduate coursework or the CGPA threshold */
    private String unmet(UUID student, boolean postgraduate, GraduationRepository.Standing st) {
        if (st.ungraded() != null) {
            return st.ungraded() + " not graded";
        }
        if (postgraduate) {
            // V493: a postgraduate graduand is judged by the courses the programme requires of them (theirs and their
            // specialisation's), not by the undergraduate CGPA threshold
            List<String> outstanding = repo.pgOutstanding(student);
            return outstanding.isEmpty() ? null : "Required coursework not passed: " + String.join(", ", outstanding);
        }
        if (st.cgpa() == null) {
            return "No published result on the record";
        }
        if (st.cgpa().compareTo(new BigDecimal("1.00")) < 0) {
            return "CGPA " + st.cgpa() + " — below pass threshold";
        }
        return null;
    }

    /** V558: a graduand put on a session's list — the entry and whether it is new, with what the audit found unmet */
    public record Placed(UUID graduandId, boolean added, String unmet) {
    }

    /**
     * V558: one student put on a session's graduation list by the lifecycle reconciliation, audited exactly as {@link #audit} audits a
     * finalist (the same standing, the same unmet requirement); an entry already on the list is audited again, never duplicated. The
     * Senate still approves the award. Runs in the caller's transaction, so a refusal there undoes the student's reconciliation whole.
     */
    public Placed placeOnList(UUID student, String session) {
        GraduationRepository.Programme p = repo.programmeOf(student);
        boolean existed = repo.graduandId(student, session) != null;
        GraduationRepository.Standing st = repo.standing(student);
        String unmet = unmet(student, p.postgraduate(), st);
        repo.upsert(student, session, st.cgpa(), p.name(), unmet);
        return new Placed(repo.graduandId(student, session), !existed, unmet);
    }

    @Transactional(readOnly = true)
    public View view(String session, String fac, String dept, String prog) {
        List<GraduationRepository.Graduand> all = repo.graduands(session, fac, dept, prog);
        List<Exception> exceptions = new ArrayList<>();
        long passed = 0;
        long awaitingClearance = 0;
        long approved = 0;
        for (GraduationRepository.Graduand g : all) {
            if (g.unmet() != null) {
                exceptions.add(new Exception(g.studentId(), g.number(), g.surname(), g.otherNames(), g.programmeName(), g.unmet(), g.cgpa()));
            } else {
                passed++;
                if (!g.cleared()) {
                    awaitingClearance++;
                }
            }
            if ("APPROVED".equals(g.senateState())) {
                approved++;
            }
        }
        List<ClassRow> classes = new ArrayList<>();
        // V493: the classes are the undergraduate degrees'; a postgraduate award is not counted in them
        long classified = all.stream().filter(g -> !g.postgraduate() && g.unmet() == null && g.cgpa() != null).count();
        for (GraduationRepository.Band b : repo.bands()) {
            long n = all.stream().filter(g -> !g.postgraduate() && g.unmet() == null && g.cgpa() != null
                    && g.cgpa().compareTo(b.low()) >= 0 && g.cgpa().compareTo(b.high()) <= 0).count();
            classes.add(new ClassRow(b.clazz(), n, classified == 0 ? 0 : (int) Math.round(100.0 * n / classified), b.low(), b.high()));
        }
        List<Finalist> finalists = all.stream().map(g -> new Finalist(g.studentId(), g.number(), g.surname(), g.otherNames(), g.programmeName(),
                g.cgpa(), g.unmet(), g.senateState(), g.clearanceRef(), g.clearanceProcess(), g.clearanceState())).toList();
        return new View(session, new Tiles(all.size(), passed, exceptions.size(), awaitingClearance, approved), exceptions, classes, finalists);
    }

    @Transactional
    public Map<String, Object> approve(String session, String minute) {
        if (minute == null || minute.isBlank()) {
            throw new DomainRuleViolation("GRAD_MINUTE_REQUIRED", "The graduation list is approved on a Senate minute, and none was cited.",
                    new DomainRuleViolation.Remedy("Cite the minute of the Senate that approved the awards.", "Registrar"));
        }
        int n = repo.approve(session, minute.trim());
        return Map.of("session", session, "approved", n, "senateMinute", minute.trim());
    }
}
