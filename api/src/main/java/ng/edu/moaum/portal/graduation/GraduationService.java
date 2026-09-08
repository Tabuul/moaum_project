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

    public record View(String session, Tiles tiles, List<Exception> exceptions, List<ClassRow> classification) {
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
            String unmet = null;
            if (st.ungraded() != null) {
                unmet = st.ungraded() + " not graded";
            } else if (st.cgpa() == null) {
                unmet = "No published result on the record";
            } else if (st.cgpa().compareTo(new BigDecimal("1.00")) < 0) {
                unmet = "CGPA " + st.cgpa() + " — below pass threshold";
            }
            repo.upsert(f.studentId(), session, st.cgpa(), f.programmeName(), unmet);
            audited++;
            if (unmet == null) {
                passed++;
            }
        }
        return Map.of("session", session, "audited", audited, "passed", passed, "outstanding", audited - passed);
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
        long classified = all.stream().filter(g -> g.unmet() == null && g.cgpa() != null).count();
        for (GraduationRepository.Band b : repo.bands()) {
            long n = all.stream().filter(g -> g.unmet() == null && g.cgpa() != null
                    && g.cgpa().compareTo(b.low()) >= 0 && g.cgpa().compareTo(b.high()) <= 0).count();
            classes.add(new ClassRow(b.clazz(), n, classified == 0 ? 0 : (int) Math.round(100.0 * n / classified), b.low(), b.high()));
        }
        return new View(session, new Tiles(all.size(), passed, exceptions.size(), awaitingClearance, approved), exceptions, classes);
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
