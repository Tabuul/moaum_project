package ng.edu.moaum.portal.admissions;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.ObjectMapper;

/**
 * Loading a CAPS list is one transaction: the batch and every row, or
 * nothing. The rules — list kind declared first, a UTME row must carry an
 * aggregate, a Direct Entry row must not — are the database's, and its
 * refusal is passed through to the caller with its own wording.
 */
@Service
public class CapsIntakeService {

    /** {@code ck_batch_office}: the offices that upload the admission list. */
    static final Set<String> UPLOADING_OFFICES = Set.of("academic", "registrar");

    private final CapsRepository caps;
    private final ObjectMapper json;

    CapsIntakeService(CapsRepository caps, ObjectMapper json) {
        this.caps = caps;
        this.json = json;
    }

    /**
     * Loads a list. For a UTME list the cut-off is read from the session's
     * admission settings — the programme's own, else its faculty's — and a
     * candidate under it is held back, on record, rather than loaded. No
     * settings in force means nothing is loaded: the database fails closed
     * on that, and so does this.
     */
    @Transactional
    public CapsLoadResult load(NewCapsBatch request) {
        AuditContext actor = AuditContextHolder.required();
        if (!UPLOADING_OFFICES.contains(actor.actorOffice())) {
            throw new DomainRuleViolation("ADM_LIST_OFFICE",
                    "The admission list is loaded by the Academic Office or the Registrar, not by '" + actor.actorOffice() + "'.",
                    new DomainRuleViolation.Remedy("Ask the Academic Office to load the list, or act as that office if you hold it.",
                            "Academic Office"));
        }

        /* the one general cut-off a UTME list loads under (V024); faculty and programme cut-offs are the screening's */
        Integer general = null;
        if ("UTME".equals(request.listKind())) {
            general = caps.loadCutoff(request.session()).orElseThrow(() -> new DomainRuleViolation("ADM_LOAD_CUTOFF_NOT_STATED",
                    "No general UTME cut-off is stated for loading the " + request.session() + " lists, so nothing may be loaded.",
                    new DomainRuleViolation.Remedy(
                            "State the general cut-off for loading — the UTME score under which a candidate is not loaded, whatever the programme — on the admission settings, before the file is uploaded.",
                            "Academic Office")));
            Set<String> codes = request.rows().stream()
                    .map(r -> r.jambCode().trim().toUpperCase())
                    .collect(Collectors.toCollection(LinkedHashSet::new));
            Map<String, String> known = programmeNames();
            List<String> unknown = codes.stream().filter(c -> !known.containsKey(c)).toList();
            if (!unknown.isEmpty()) {
                throw new DomainRuleViolation("ADM_UNKNOWN_PROGRAMME",
                        "Not a programme the University runs: " + String.join(", ", unknown) + ".",
                        new DomainRuleViolation.Remedy("Resolve each JAMB course to a University programme before the list is loaded.",
                                "Academic Office"));
            }
        }
        final Integer loadCutoff = general;

        UUID id = UUID.randomUUID();
        caps.insertBatch(id, request.session(), request.source(), blankToNull(request.filename()), request.fileSha256(),
                request.rows().size(), request.listKind(), request.downloadedOn(), actor.actorId(), actor.actorOffice());
        int loaded = 0;
        List<CapsLoadResult.ExcludedRow> excluded = new ArrayList<>();
        Map<String, String> names = "UTME".equals(request.listKind()) ? programmeNames() : Map.of();
        for (CapsRowIn row : request.rows()) {
            Map<String, Object> raw = row.raw() == null ? Map.of() : row.raw();
            String rawJson = json.writeValueAsString(raw);
            String code = row.jambCode().trim().toUpperCase();
            if (loadCutoff != null && row.aggregate() != null && row.aggregate() < loadCutoff) {
                caps.insertExcluded(id, request.session(), row, loadCutoff, "BELOW_CUTOFF", rawJson);
                excluded.add(new CapsLoadResult.ExcludedRow(row.jambRegNo().trim().toUpperCase(), row.surname(),
                        row.otherNames(), code, names.getOrDefault(code, code), row.aggregate(), loadCutoff, "BELOW_CUTOFF"));
                continue;
            }
            caps.insertRow(id, request.session(), row, rawJson);
            loaded++;
        }
        return new CapsLoadResult(caps.find(id).orElseThrow(), loaded, excluded);
    }

    private Map<String, String> programmeNames() {
        return caps.programmes().stream().collect(Collectors.toMap(Programme::code, Programme::name, (a, b) -> a));
    }

    @Transactional(readOnly = true)
    public CapsBatch get(UUID id) {
        return caps.find(id).orElseThrow(() -> new NotFound("CAPS batch", id));
    }

    @Transactional(readOnly = true)
    public List<CapsBatch> bySession(String session) {
        return caps.bySession(session);
    }

    /** Commits, or reports — by the database's own words — why the list does not yet reconcile. */
    @Transactional
    public String commit(UUID id) {
        get(id);
        return caps.commit(id);
    }

    /**
     * A list loaded in error is withdrawn, never deleted: the batch and its
     * rows stay as evidence, marked, and count for nothing. The database
     * refuses it for a list whose candidates already hold admission numbers.
     */
    @Transactional
    public String withdraw(UUID id, String reason) {
        get(id);
        return caps.withdraw(id, reason);
    }

    @Transactional(readOnly = true)
    public List<Finding> reconcile(String session) {
        return caps.reconcile(session);
    }

    @Transactional(readOnly = true)
    public List<Finding> attachmentState(String session) {
        return caps.attachmentState(session);
    }

    @Transactional(readOnly = true)
    public List<PolicyFinding> policyFindings(String session) {
        return caps.policyFindings(session);
    }

    /** Every programme with the name JAMB uses for it — what a CAPS download is resolved against. */
    @Transactional(readOnly = true)
    public List<Programme> programmes() {
        return caps.programmes();
    }

    /**
     * Records what JAMB calls a programme. The alias is the JOIN a CAPS
     * download is matched on, so it is held per code, one name each, and a
     * name already held by another code is refused: two programmes with the
     * same JAMB name would make every candidate on it ambiguous.
     */
    @Transactional
    public Programme setJambAlias(String code, String jambName) {
        String upper = code.trim().toUpperCase();
        caps.programme(upper).orElseThrow(() -> new NotFound("programme", upper));
        if (jambName == null || jambName.isBlank()) {
            throw new DomainRuleViolation("ADM_ALIAS_BLANK", "JAMB's name for the programme was not given.",
                    new DomainRuleViolation.Remedy("Type the course name exactly as it appears in the CAPS download.", "Academic Office"));
        }
        String name = jambName.trim();
        String normalised = name.toLowerCase().replaceAll("[^a-z0-9]", "");
        Optional<String> holder = caps.codeWithAlias(normalised);
        if (holder.isPresent() && !holder.get().equals(upper)) {
            throw new DomainRuleViolation("ADM_ALIAS_TAKEN",
                    "\"" + name + "\" is already what JAMB calls " + holder.get() + "; one JAMB name cannot mean two programmes.",
                    new DomainRuleViolation.Remedy("Check the CAPS download: JAMB names each programme once. If " + holder.get()
                            + " no longer carries this name, change its alias first.", "Academic Office"));
        }
        if (holder.isPresent()) {
            return caps.programme(upper).orElseThrow();       // already what JAMB calls it
        }
        if (caps.aliasIsOwnName(upper)) {
            caps.upsertAlias(upper, name);                      // the first real JAMB name replaces the seed's fallback
        } else {
            caps.addAliasName(upper, name, normalised);         // a further name, kept beside the first
        }
        return caps.programme(upper).orElseThrow();
    }

    private static final Set<String> CATEGORIES = Set.of("UNDER GRADUATE", "POST GRADUATE");

    /**
     * The University's own words for a programme. The code never changes
     * (BR-007: a retired programme keeps it for every graduate who holds it),
     * the faculty follows the department, and the name JAMB uses is a
     * separate matter, set by {@link #setJambAlias}.
     */
    @Transactional
    public Programme editProgramme(String code, String name, String deptCode, String category, boolean archived) {
        String upper = code.trim().toUpperCase();
        caps.programme(upper).orElseThrow(() -> new NotFound("programme", upper));
        if (name == null || name.isBlank()) {
            throw new DomainRuleViolation("ADM_PROGRAMME_NAME_BLANK", "The programme was given no name.",
                    new DomainRuleViolation.Remedy("Type the name the University awards the degree under.", "Academic Office"));
        }
        String dept = deptCode == null ? "" : deptCode.trim().toUpperCase();
        String faculty = caps.facultyOfDepartment(dept).orElseThrow(() -> new DomainRuleViolation("ADM_DEPARTMENT_UNKNOWN",
                "No department carries the code \"" + dept + "\", or it has ended.",
                new DomainRuleViolation.Remedy("Choose the department from the University's structure.", "Academic Office")));
        String cat = category == null ? "" : category.trim().toUpperCase();
        if (!CATEGORIES.contains(cat)) {
            throw new DomainRuleViolation("ADM_PROGRAMME_CATEGORY", "\"" + category + "\" is not a programme category.",
                    new DomainRuleViolation.Remedy("A programme is UNDER GRADUATE or POST GRADUATE.", "Academic Office"));
        }
        caps.updateProgramme(upper, name.trim(), dept, faculty, cat, archived);
        return caps.programme(upper).orElseThrow();
    }

    /** The registration number inside a filename, by shape — {@code admissions.reg_no_in}. */
    @Transactional(readOnly = true)
    public Optional<String> regNoIn(String text) {
        return caps.regNoIn(text);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
