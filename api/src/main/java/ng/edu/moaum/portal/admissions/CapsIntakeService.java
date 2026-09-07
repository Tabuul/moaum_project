package ng.edu.moaum.portal.admissions;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

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

    @Transactional
    public CapsBatch load(NewCapsBatch request) {
        AuditContext actor = AuditContextHolder.required();
        if (!UPLOADING_OFFICES.contains(actor.actorOffice())) {
            throw new DomainRuleViolation("ADM_LIST_OFFICE",
                    "The admission list is loaded by the Academic Office or the Registrar, not by '" + actor.actorOffice() + "'.",
                    new DomainRuleViolation.Remedy("Ask the Academic Office to load the list, or act as that office if you hold it.",
                            "Academic Office"));
        }
        UUID id = UUID.randomUUID();
        caps.insertBatch(id, request.session(), request.source(), blankToNull(request.filename()), request.fileSha256(),
                request.rows().size(), request.listKind(), request.downloadedOn(), actor.actorId(), actor.actorOffice());
        for (CapsRowIn row : request.rows()) {
            Map<String, Object> raw = row.raw() == null ? Map.of() : row.raw();
            caps.insertRow(id, request.session(), row, json.writeValueAsString(raw));
        }
        return caps.find(id).orElseThrow();
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

    /** The registration number inside a filename, by shape — {@code admissions.reg_no_in}. */
    @Transactional(readOnly = true)
    public Optional<String> regNoIn(String text) {
        return caps.regNoIn(text);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
