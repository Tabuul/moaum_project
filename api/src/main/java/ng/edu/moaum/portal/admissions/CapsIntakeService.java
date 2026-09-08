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

        Map<String, Integer> cutoffs = Map.of();
        if ("UTME".equals(request.listKind())) {
            if (!caps.policyInForce(request.session())) {
                throw new DomainRuleViolation("ADM_SETTINGS_NOT_IN_FORCE",
                        "No admission settings are in force for " + request.session()
                                + ", so no cut-off can be applied and nothing may be loaded.",
                        new DomainRuleViolation.Remedy(
                                "Complete the session's admission settings and put them in force, citing the Central Admissions Committee minute that approved them.",
                                "Academic Office"));
            }
            Set<String> codes = request.rows().stream()
                    .map(r -> r.jambCode().trim().toUpperCase())
                    .collect(Collectors.toCollection(LinkedHashSet::new));
            cutoffs = caps.cutoffsFor(request.session(), codes);
            Map<String, Integer> known = cutoffs;
            List<String> unknown = codes.stream().filter(c -> !known.containsKey(c)).toList();
            if (!unknown.isEmpty()) {
                throw new DomainRuleViolation("ADM_UNKNOWN_PROGRAMME",
                        "Not a programme the University runs: " + String.join(", ", unknown) + ".",
                        new DomainRuleViolation.Remedy("Resolve each JAMB course to a University programme before the list is loaded.",
                                "Academic Office"));
            }
        }

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
            Integer cutoff = cutoffs.get(code);
            if (cutoff != null && row.aggregate() != null && row.aggregate() < cutoff) {
                caps.insertExcluded(id, request.session(), row, cutoff, "BELOW_CUTOFF", rawJson);
                excluded.add(new CapsLoadResult.ExcludedRow(row.jambRegNo().trim().toUpperCase(), row.surname(),
                        row.otherNames(), code, names.getOrDefault(code, code), row.aggregate(), cutoff, "BELOW_CUTOFF"));
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

    /** The session's admission settings, with the cut-offs and whatever keeps them a draft. */
    @Transactional(readOnly = true)
    public AdmissionPolicy policy(String session) {
        AdmissionPolicy.Row row = caps.policy(session).orElseThrow(() -> new NotFound("admission settings for", session));
        return new AdmissionPolicy(row.session(), row.state(), "IN_FORCE".equals(row.state()), row.instrument(),
                row.nucQuota(), row.weightUtme(), row.weightPutme(), row.ratioUtme(), row.ratioDe(),
                caps.facultyCutoffs(session), caps.programmeCutoffs(session), caps.policyFindings(session));
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
        caps.upsertAlias(upper, name);
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
