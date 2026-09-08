package ng.edu.moaum.portal.hostel;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** The rules are the database's (V030); this is the shape the screens read. */
@Service
public class HostelService {

    private static final List<String> STATES = List.of("RAISED", "ASSIGNED", "FIXED", "CLOSED");

    private final HostelRepository repo;

    HostelService(HostelRepository repo) {
        this.repo = repo;
    }

    private String session(String asked) {
        String s = asked == null || asked.isBlank() ? repo.currentSession() : asked;
        return s == null ? "2026/2027" : s;
    }

    /* ── the student ── */

    @Transactional(readOnly = true)
    public Map<String, Object> mine(UUID student, String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("view", repo.studentView(student, session).orElse(Map.of()));
        out.put("halls", repo.halls());
        out.put("history", repo.history(student));
        UUID room = repo.roomOf(student, session).orElse(null);
        out.put("maintenance", room == null ? List.of() : repo.maintenanceOfRoom(room));
        return out;
    }

    @Transactional
    public Map<String, Object> apply(UUID student, String sessionAsked, String hall, String category, String note) {
        String session = session(sessionAsked);
        UUID id = repo.apply(student, session, hall == null || hall.isBlank() ? null : hall.trim().toUpperCase(), category, note);
        return Map.of("applicationId", id, "session", session, "state", "APPLIED");
    }

    @Transactional
    public Map<String, Object> feeReference(UUID student, String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> v = repo.studentView(student, session).orElseThrow(() -> new NotFound("hostel application for", session));
        Object app = v.get("application_id");
        if (app == null) {
            throw new DomainRuleViolation("HOSTEL_NO_APPLICATION", "No application stands for " + session + ".",
                    new DomainRuleViolation.Remedy("Apply first; the fee is paid against a bed the draw allocates.", "You"));
        }
        return Map.of("reference", repo.feeReference((UUID) app), "amount", v.get("fee"), "session", session);
    }

    @Transactional
    public Map<String, Object> raise(UUID student, String sessionAsked, String issue) {
        if (issue == null || issue.isBlank()) {
            throw new DomainRuleViolation("HOSTEL_ISSUE_BLANK", "Say what is wrong with the room.",
                    new DomainRuleViolation.Remedy("One line: the fan, the latch, the tap.", "You"));
        }
        UUID room = repo.roomOf(student, session(sessionAsked)).orElseThrow(() -> new DomainRuleViolation("HOSTEL_NO_ROOM",
                "No confirmed room stands against you this session.",
                new DomainRuleViolation.Remedy("A maintenance request is raised from a room you occupy; pay the accommodation fee to confirm the bed first.", "You")));
        return Map.of("id", repo.raise(room, student, issue.trim()), "state", "RAISED");
    }

    /* ── the office ── */

    @Transactional(readOnly = true)
    public Map<String, Object> desk(String sessionAsked) {
        String session = session(sessionAsked);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("setting", repo.setting(session).orElse(null));
        out.put("halls", repo.halls());
        out.put("counts", repo.counts(session));
        out.put("draw", repo.draw(session));
        out.put("maintenance", repo.maintenance());
        return out;
    }

    @Transactional
    public Map<String, Object> putSetting(String sessionAsked, BigDecimal fee, Integer holdHours, LocalDate close) {
        String session = session(sessionAsked);
        if (fee == null || fee.signum() < 0) {
            throw new DomainRuleViolation("HOSTEL_FEE", "State the accommodation fee for the session.", new DomainRuleViolation.Remedy("Zero is a fee; blank is not.", "Student Services"));
        }
        repo.putSetting(session, fee, holdHours == null ? 72 : holdHours, close);
        return Map.of("session", session, "fee", fee, "holdHours", holdHours == null ? 72 : holdHours);
    }

    @Transactional
    public Map<String, Object> putHall(String code, String name, String sex) {
        if (code == null || !code.trim().toUpperCase().matches("[A-Z0-9]{2,8}") || name == null || name.isBlank()) {
            throw new DomainRuleViolation("HOSTEL_HALL", "A hall has a short code and a name.", new DomainRuleViolation.Remedy("Two to eight letters or digits for the code.", "Student Services"));
        }
        repo.putHall(code.trim().toUpperCase(), name.trim(), sex == null || sex.isBlank() ? null : sex.trim().toUpperCase());
        return Map.of("code", code.trim().toUpperCase());
    }

    @Transactional
    public Map<String, Object> putRoom(String hall, String block, String roomNo, Integer beds, Boolean out, String note) {
        if (hall == null || block == null || roomNo == null || beds == null || block.isBlank() || roomNo.isBlank()) {
            throw new DomainRuleViolation("HOSTEL_ROOM", "A room is a hall, a block, a number and its beds.", new DomainRuleViolation.Remedy("All four.", "Student Services"));
        }
        repo.putRoom(hall.trim().toUpperCase(), block.trim().toUpperCase(), roomNo.trim(), beds, out != null && out, note);
        return Map.of("hall", hall.trim().toUpperCase(), "block", block.trim().toUpperCase(), "roomNo", roomNo.trim());
    }

    @Transactional
    public Map<String, Object> draw(String sessionAsked, String seed) {
        return repo.runDraw(session(sessionAsked), seed);
    }

    @Transactional
    public Map<String, Object> lapse(String sessionAsked) {
        return Map.of("lapsed", repo.lapse(session(sessionAsked)));
    }

    @Transactional
    public Map<String, Object> decideMaintenance(UUID id, String state, String note) {
        String st = state == null ? "" : state.trim().toUpperCase();
        if (!STATES.contains(st)) {
            throw new DomainRuleViolation("HOSTEL_MAINT_STATE", "A request is assigned, fixed or closed.", new DomainRuleViolation.Remedy("One of those three.", "Student Services"));
        }
        if (repo.decideMaintenance(id, st, note) == 0) {
            throw new NotFound("maintenance request", id);
        }
        return Map.of("id", id, "state", st);
    }
}
