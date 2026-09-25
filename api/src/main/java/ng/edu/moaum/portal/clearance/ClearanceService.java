package ng.edu.moaum.portal.clearance;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ClearanceService {

    private static final Set<String> ANY_UNIT = Set.of("registrar", "dregistrar", "academic");

    private final ClearanceRepository repo;

    ClearanceService(ClearanceRepository repo) {
        this.repo = repo;
    }

    @Transactional(readOnly = true)
    public List<Clearance.Unit> units() {
        return repo.units();
    }

    @Transactional(readOnly = true)
    public Clearance.Listing listing(String purpose, String fac, String dept, String prog, Integer level, String session) {
        List<Clearance.Unit> units = repo.units();
        List<Clearance.Candidate> out = new ArrayList<>();
        long[] holding = new long[units.size()];
        long cleared = 0;
        long one = 0;
        long more = 0;
        for (ClearanceRepository.StudentRow s : repo.students(fac, dept, prog, level, session)) {
            List<Clearance.Position> pos = repo.position(s.id(), purpose);
            List<String> states = new ArrayList<>();
            int held = 0;
            for (int i = 0; i < units.size(); i++) {
                String st = i < pos.size() ? pos.get(i).state() : "HELD";
                states.add(st);
                if (!"CLEARED".equals(st)) {
                    held++;
                    holding[i]++;
                }
            }
            if (held == 0) {
                cleared++;
            } else if (held == 1) {
                one++;
            } else {
                more++;
            }
            out.add(new Clearance.Candidate(s.id(), s.number(), s.surname(), s.otherNames(), s.programmeName(), s.deptName(),
                    s.facultyCode(), s.level(), states, held == 0));
        }
        List<Clearance.UnitCount> counts = new ArrayList<>();
        for (int i = 0; i < units.size(); i++) {
            Clearance.Unit u = units.get(i);
            int progress = out.isEmpty() ? 0 : (int) Math.round(100.0 * (out.size() - holding[i]) / out.size());
            counts.add(new Clearance.UnitCount(u.code(), u.label(), u.clearsAgainst(), u.holdsFor(), u.typicalReason(), holding[i], progress));
        }
        return new Clearance.Listing(purpose, new Clearance.Totals(out.size(), cleared, one, more), counts, out, repo.total());
    }

    @Transactional(readOnly = true)
    public List<Clearance.Position> position(UUID student, String purpose) {
        if (!repo.studentExists(student)) {
            throw new NotFound("student", student);
        }
        return repo.position(student, purpose);
    }

    private Clearance.Unit unitFor(String code, AuditContext ctx) {
        Clearance.Unit u = repo.unit(code.toUpperCase()).orElseThrow(() -> new NotFound("clearance unit", code));
        // the housing desk signs the hostel unit beside Student Services (V261)
        boolean housingHostel = "housing".equals(ctx.actorOffice()) && "HOSTEL".equals(u.code());
        if (!housingHostel && !ANY_UNIT.contains(ctx.actorOffice()) && (u.officeCode() == null || !u.officeCode().equals(ctx.actorOffice()))) {
            throw new AccessDeniedException("the " + u.label() + " clears against its own record; " + ctx.actorOffice() + " does not sign for it");
        }
        return u;
    }

    @Transactional
    public Map<String, Object> clear(UUID student, String unit, String purpose, String note) {
        AuditContext ctx = AuditContextHolder.required();
        if (!repo.studentExists(student)) {
            throw new NotFound("student", student);
        }
        Clearance.Unit u = unitFor(unit, ctx);
        repo.decide(student, purpose, u.code(), "CLEARED", null, ctx.actorId(), note);
        return Map.of("student", student, "unit", u.code(), "state", "CLEARED");
    }

    @Transactional
    public Map<String, Object> hold(UUID student, String unit, String purpose, String item, String note) {
        AuditContext ctx = AuditContextHolder.required();
        if (!repo.studentExists(student)) {
            throw new NotFound("student", student);
        }
        if (item == null || item.isBlank()) {
            throw new DomainRuleViolation("CLR_HOLD_NAMES_ITEM", "A hold names the specific item outstanding.",
                    new DomainRuleViolation.Remedy("Say what the candidate must return, pay or deposit. A hold with no item against it is leverage.", "The unit holding"));
        }
        Clearance.Unit u = unitFor(unit, ctx);
        repo.decide(student, purpose, u.code(), "HELD", item, ctx.actorId(), note);
        return Map.of("student", student, "unit", u.code(), "state", "HELD");
    }
}
