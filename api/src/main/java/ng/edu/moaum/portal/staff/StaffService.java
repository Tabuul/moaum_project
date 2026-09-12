package ng.edu.moaum.portal.staff;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import tools.jackson.databind.ObjectMapper;

/**
 * Two reads. Neither writes anything, so neither needs the audit context —
 * but both run in a transaction so that the offices a person holds and the
 * person themselves are read as of one moment.
 */
@Service
public class StaffService {

    private final StaffRepository staff;
    private final ObjectMapper json;

    StaffService(StaffRepository staff, ObjectMapper json) {
        this.staff = staff;
        this.json = json;
    }

    /**
     * The acting person and the offices they hold. An actor with no row in
     * {@code iam.person} is answered with nulls rather than a 404: they are
     * signed in, and the screen is entitled to say what the Registry has not
     * yet recorded.
     */
    @Transactional(readOnly = true)
    public StaffMe me(UUID actor) {
        if (actor == null) {
            return new StaffMe(null, List.of());
        }
        return new StaffMe(staff.person(actor).orElse(null), staff.offices(actor));
    }

    /**
     * The acting person's own academic profile as a JSON object the portal can
     * render straight into a form. A person with no profile yet is answered
     * with an empty one — every scalar null and every list empty — so the
     * screen opens on a blank form rather than a 404.
     */
    @Transactional(readOnly = true)
    public Map<String, Object> profile(UUID actor) {
        if (actor == null) {
            return empty();
        }
        return staff.profileJson(actor)
                .map(s -> json.readValue(s, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { }))
                .orElseGet(this::empty);
    }

    /** Save the acting person's profile and read it back. The DB takes the person from the audit context, never the caller. */
    @Transactional
    public Map<String, Object> saveProfile(UUID actor, Map<String, Object> body) {
        staff.saveProfile(json.writeValueAsString(body == null ? Map.of() : body));
        return profile(actor);
    }

    @Transactional(readOnly = true)
    public StaffMe.Photo photo(UUID actor) {
        if (actor == null) {
            throw new NotFound("staff-photo", "me");
        }
        return staff.photo(actor).orElseThrow(() -> new NotFound("staff-photo", actor.toString()));
    }

    @Transactional
    public void savePhoto(String contentType, byte[] content) {
        staff.savePhoto(contentType, content.length, content);
    }

    private Map<String, Object> empty() {
        Map<String, Object> m = new java.util.LinkedHashMap<>();
        for (String k : List.of("email", "phone", "department", "faculty", "responsibility",
                "scholarUrl", "orcid", "researchInterests")) {
            m.put(k, null);
        }
        m.put("mastersGraduated", 0);
        m.put("phdGraduated", 0);
        for (String k : List.of("publications", "grants", "collaborations", "conferences",
                "assignments", "innovations", "patents", "achievements", "contributions")) {
            m.put(k, List.of());
        }
        m.put("photo", false);
        return m;
    }

    @Transactional(readOnly = true)
    public College college(String code) {
        String wanted = code == null ? "" : code.trim().toUpperCase();
        College.Row row = staff.college(wanted).orElseThrow(() -> new NotFound("college", wanted));
        return new College(row, staff.faculties(wanted), staff.students(wanted), staff.byLevel(wanted));
    }
}
