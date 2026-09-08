package ng.edu.moaum.portal.admissions;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The Central Admissions Committee's guidelines, made into settings the
 * portal applies. A session's settings are a DRAFT until the Committee's
 * minute puts them in force, and every write here is to a draft: settings
 * in force are not edited — a correction is a new version citing a new
 * minute. The checks are the database's ({@code admissions.policy_findings});
 * this service only refuses what the database would.
 */
@Service
public class AdmissionSettingsService {

    static final Set<String> CRITERIA = Set.of("NATIONAL_MERIT", "STATE_MERIT", "ELG", "LOCALITY");

    private final AdmissionSettingsRepository settings;
    private final CapsRepository caps;

    AdmissionSettingsService(AdmissionSettingsRepository settings, CapsRepository caps) {
        this.settings = settings;
        this.caps = caps;
    }

    public record PolicySettings(@NotNull @Min(1) Integer nucQuota,
                                 @NotNull @Min(0) @Max(100) Integer weightUtme, @NotNull @Min(0) @Max(100) Integer weightPutme,
                                 @NotNull @Min(0) @Max(100) Integer ratioUtme, @NotNull @Min(0) @Max(100) Integer ratioDe,
                                 @NotNull @Min(0) @Max(100) Integer ratioScience, @NotNull @Min(0) @Max(100) Integer ratioArts,
                                 @NotNull @Min(0) @Max(100) Integer elgCapPct, @NotNull @Min(0) @Max(100) Integer deptSharePct,
                                 @NotNull @Min(0) Integer indexPrelimPlaces, @NotNull @Min(0) Integer indexPerZone,
                                 @NotNull Boolean mpfOnly, @NotNull Boolean screeningRequired) {
    }

    public record FacultyQuotaIn(@Min(0) Integer quota, @Min(1) @Max(400) Integer cutoff) {
    }

    public record ProgrammeRuleIn(@Min(1) @Max(400) Integer cutoff,
                                  @NotBlank @Size(max = 2000) String olevelText,
                                  @NotBlank @Size(max = 2000) String utmeText,
                                  @NotBlank @Size(max = 2000) String deText,
                                  @Min(1) @Max(9) Integer olevelCredits, @Min(1) @Max(4) Integer olevelSittings,
                                  /** the O'Level subjects relevant to the programme — the ones the screening counts (V020); null leaves them as they are */
                                  List<String> olevelSubjects) {
    }

    public record Instrument(@NotBlank @Size(max = 200) String instrument) {
    }

    @Transactional(readOnly = true)
    public List<AdmissionPolicy.Summary> policies() {
        return settings.policies();
    }

    @Transactional(readOnly = true)
    public AdmissionPolicy policy(String session) {
        AdmissionPolicy.Row r = settings.row(session).orElseThrow(() -> new NotFound("admission settings for", session));
        return new AdmissionPolicy(r.session(), r.state(), "IN_FORCE".equals(r.state()), r.instrument(), r.inForceSince(),
                r.nucQuota(), r.weightUtme(), r.weightPutme(), r.ratioUtme(), r.ratioDe(), r.ratioScience(), r.ratioArts(),
                r.elgCapPct(), r.deptSharePct(), r.indexPrelimPlaces(), r.indexPerZone(), r.mpfOnly(), r.screeningRequired(),
                settings.criteria(session), caps.facultyCutoffs(session), caps.programmeCutoffs(session),
                settings.programmeRules(session), caps.policyFindings(session));
    }

    /** Creates the session's draft, or changes it while it is one. */
    @Transactional
    public AdmissionPolicy save(String session, PolicySettings s) {
        settings.row(session).ifPresent(r -> assertDraft(r));
        if (s.weightUtme() + s.weightPutme() != 100) {
            throw refused("ADM_WEIGHTS", "The weighting does not total 100%: " + s.weightUtme() + " + " + s.weightPutme() + ".",
                    "Two weights that do not total a hundred produce an aggregate on a scale nobody can state.");
        }
        if (s.ratioUtme() + s.ratioDe() != 100) {
            throw refused("ADM_RATIO_UTME_DE", "UTME to Direct Entry does not total 100: " + s.ratioUtme() + ":" + s.ratioDe() + ".",
                    "State the two shares of the intake.");
        }
        if (s.ratioScience() + s.ratioArts() != 100) {
            throw refused("ADM_RATIO_SCIENCE_ARTS", "Science to Arts does not total 100: " + s.ratioScience() + ":" + s.ratioArts() + ".",
                    "State the two shares of the intake.");
        }
        settings.upsertPolicy(session, s);
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy saveCriteria(String session, Map<String, Integer> percents) {
        UUID id = draftId(session);
        for (Map.Entry<String, Integer> e : percents.entrySet()) {
            if (!CRITERIA.contains(e.getKey())) {
                throw refused("ADM_CRITERION_UNKNOWN", "'" + e.getKey() + "' is not one of the four criteria.",
                        "The criteria are National Merit, State Merit, Equality of Local Government and Locality.");
            }
            if (e.getValue() == null || e.getValue() < 0 || e.getValue() > 100) {
                throw refused("ADM_CRITERION_PERCENT", "A criterion's share must be between 0 and 100%.", "Enter a percentage.");
            }
            settings.upsertCriterion(id, e.getKey(), e.getValue());
        }
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy saveFaculty(String session, String facultyCode, FacultyQuotaIn in) {
        UUID id = draftId(session);
        String code = facultyCode.trim().toUpperCase();
        if (!settings.facultyExists(code)) {
            throw new NotFound("faculty", code);
        }
        settings.upsertFacultyQuota(id, code, in.quota(), in.cutoff());
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy saveProgrammeRule(String session, String programmeCode, ProgrammeRuleIn in) {
        UUID id = draftId(session);
        String code = programmeCode.trim().toUpperCase();
        if (!settings.programmeExists(code)) {
            throw new NotFound("programme", code);
        }
        settings.upsertProgrammeRule(id, code, in);
        return policy(session);
    }

    /** A programme closed for the session (V023): not admitted into, needs no rule; the reason is on the record. */
    @Transactional
    public AdmissionPolicy closeProgramme(String session, String programmeCode, String reason) {
        UUID id = draftId(session);
        String code = programmeCode.trim().toUpperCase();
        if (!settings.programmeExists(code)) {
            throw new NotFound("programme", code);
        }
        if (reason == null || reason.isBlank()) {
            throw new DomainRuleViolation("ADM_CLOSE_REASON", "A programme is closed for a session for a reason.",
                    new DomainRuleViolation.Remedy("Say why it does not admit this session — no accreditation, no intake, suspended by Senate.", "Academic Office"));
        }
        settings.closeProgramme(id, code, reason.trim());
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy reopenProgramme(String session, String programmeCode) {
        UUID id = draftId(session);
        settings.reopenProgramme(id, programmeCode.trim().toUpperCase());
        return policy(session);
    }

    /** The Committee's minute. The database refuses, by name, until every finding is answered. */
    @Transactional
    public AdmissionPolicy putInForce(String session, String instrument) {
        settings.row(session).orElseThrow(() -> new NotFound("admission settings for", session));
        settings.putInForce(session, instrument.trim());
        return policy(session);
    }

    /** A session begins from the last one: everything it states, as a new draft to amend. */
    @Transactional
    public AdmissionPolicy startFrom(String session, String from) {
        if (settings.row(session).isPresent()) {
            throw refused("ADM_SETTINGS_EXIST", "Settings for " + session + " already exist.",
                    "Amend the draft that exists; a session has one set of settings.");
        }
        settings.row(from).orElseThrow(() -> new NotFound("admission settings for", from));
        settings.copy(from, session);
        return policy(session);
    }

    private UUID draftId(String session) {
        AdmissionPolicy.Row r = settings.row(session).orElseThrow(() -> new NotFound("admission settings for", session));
        assertDraft(r);
        return settings.id(session).orElseThrow();
    }

    private static void assertDraft(AdmissionPolicy.Row r) {
        if (!"DRAFT".equals(r.state())) {
            throw new DomainRuleViolation("ADM_SETTINGS_IN_FORCE",
                    "The " + r.session() + " settings are in force under " + r.instrument() + " and are not edited.",
                    new DomainRuleViolation.Remedy("A correction is a new version citing a new minute; this one stays readable for as long as anybody admitted under it is alive.",
                            "Central Admissions Committee"));
        }
    }

    private static DomainRuleViolation refused(String code, String detail, String remedy) {
        return new DomainRuleViolation(code, detail, new DomainRuleViolation.Remedy(remedy, "Central Admissions Committee"));
    }
}
