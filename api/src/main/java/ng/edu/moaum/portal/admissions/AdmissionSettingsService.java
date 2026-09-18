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

    public record FacultyQuotaIn(@Min(0) Integer quota, @Min(1) @Max(400) Integer cutoff,
                                 @Min(0) @Max(100) Integer ratioUtme, @Min(0) @Max(100) Integer ratioDe) {
    }

    public record ProgrammeRuleIn(@Min(1) @Max(400) Integer cutoff,
                                  @NotBlank @Size(max = 2000) String olevelText,
                                  @NotBlank @Size(max = 2000) String utmeText,
                                  @NotBlank @Size(max = 2000) String deText,
                                  @Min(1) @Max(9) Integer olevelCredits, @Min(1) @Max(4) Integer olevelSittings,
                                  /** the O'Level subjects relevant to the programme — the ones the screening counts (V020); null leaves them as they are */
                                  List<String> olevelSubjects,
                                  /** the programme's own carrying capacity (V054); null leaves it unset */
                                  @Min(0) Integer quota,
                                  /** compulsory O'Level subjects this programme accepts a pass in (V053); null leaves them as they are */
                                  List<String> olevelAllowances) {
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
                settings.programmeRules(session), caps.policyFindings(session), settings.catchmentLgas(session));
    }

    /** The catchment local governments, stated for the Locality basis; replaces the set. This is the
     *  operational list the merit engine reads live for the Locality basis, so it may be set (and
     *  corrected) even while the settings are in force — unlike the weights and quotas the Committee fixed. */
    @Transactional
    public AdmissionPolicy saveCatchment(String session, List<String> lgas) {
        UUID id = settings.id(session).orElseThrow(() -> new NotFound("admission settings for", session));
        List<String> clean = (lgas == null ? List.<String>of() : lgas).stream()
                .map(s -> s == null ? "" : s.trim()).filter(s -> !s.isEmpty()).distinct().toList();
        settings.saveCatchment(id, clean);
        return policy(session);
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
        Integer ru = in.ratioUtme();
        Integer rd = in.ratioDe();
        if ((ru == null) != (rd == null)) {
            throw new DomainRuleViolation("ADM_RATIO_PAIR", "A faculty's UTME:Direct-Entry split is stated as both shares or neither.",
                    new DomainRuleViolation.Remedy("Leave both blank to inherit the session default (e.g. 80:20).", "Central Admissions Committee"));
        }
        if (ru != null && ru + rd != 100) {
            throw new DomainRuleViolation("ADM_RATIO_SUM", "A UTME:Direct-Entry split totals 100.",
                    new DomainRuleViolation.Remedy("Education is 60:40; every other faculty is the session's 80:20.", "Central Admissions Committee"));
        }
        settings.upsertFacultyQuota(id, code, in.quota(), in.cutoff(), ru, rd);
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

    /* ── capacity, editable in force ──
       A quota is the number of places, not a rule of qualification. The NUC can raise the approved
       quota mid-cycle and the Deans redistribute it, so these three are edited whether the policy is a
       draft or in force — unlike everything else, they do not assert DRAFT. Every change is still an
       attributed act on the audit spine, and the cut-offs, weightings, criteria and subject
       combinations a candidate is admitted against stay frozen once the policy is in force. */

    @Transactional
    public AdmissionPolicy setNucQuota(String session, Integer quota) {
        UUID id = settings.id(session).orElseThrow(() -> new NotFound("admission settings for", session));
        if (quota == null || quota <= 0) {
            throw refused("ADM_QUOTA", "The NUC approved quota is a positive number of places.", "State the quota the NUC approved.");
        }
        settings.setNucQuota(id, quota);
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy setFacultyQuota(String session, String facultyCode, Integer quota) {
        UUID id = settings.id(session).orElseThrow(() -> new NotFound("admission settings for", session));
        String code = facultyCode.trim().toUpperCase();
        if (!settings.facultyExists(code)) {
            throw new NotFound("faculty", code);
        }
        if (quota != null && quota < 0) {
            throw refused("ADM_QUOTA", "A faculty quota is a number of places, or blank.", "Enter the places distributed to the faculty, or leave it blank.");
        }
        settings.setFacultyQuota(id, code, quota);
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy setProgrammeQuota(String session, String programmeCode, Integer quota) {
        UUID id = settings.id(session).orElseThrow(() -> new NotFound("admission settings for", session));
        String code = programmeCode.trim().toUpperCase();
        if (!settings.programmeExists(code)) {
            throw new NotFound("programme", code);
        }
        if (quota != null && quota < 0) {
            throw refused("ADM_QUOTA", "A programme quota is a number of places, or blank.", "Enter the places the programme carries, or leave it blank.");
        }
        settings.setProgrammeQuota(id, code, quota);
        return policy(session);
    }

    /** the relevant O'Level subjects a programme's screening counts — editable in force like a quota:
     *  it corrects which subjects the score reads, a data correction, not the cut-off or weighting a
     *  candidate is ranked by. */
    @Transactional
    public AdmissionPolicy setProgrammeOlevelSubjects(String session, String programmeCode, List<String> subjects) {
        UUID id = settings.id(session).orElseThrow(() -> new NotFound("admission settings for", session));
        String code = programmeCode.trim().toUpperCase();
        if (!settings.programmeExists(code)) {
            throw new NotFound("programme", code);
        }
        settings.setProgrammeOlevelSubjects(id, code, subjects);
        return policy(session);
    }

    @Transactional
    public AdmissionPolicy setProgrammeCutoff(String session, String programmeCode, Integer cutoff) {
        UUID id = settings.id(session).orElseThrow(() -> new NotFound("admission settings for", session));
        String code = programmeCode.trim().toUpperCase();
        if (!settings.programmeExists(code)) {
            throw new NotFound("programme", code);
        }
        if (cutoff != null && (cutoff < 1 || cutoff > 400)) {
            throw refused("ADM_CUTOFF", "A cut-off is a UTME aggregate from 1 to 400, or blank to inherit the faculty's.", "Enter the programme's own cut-off, or leave it blank.");
        }
        if (settings.setProgrammeCutoff(id, code, cutoff) == 0) {
            throw refused("ADM_NO_RULE", "This programme has no rule for the session yet.", "State the programme's rule on the Programme requirements tab first, then set its cut-off.");
        }
        return policy(session);
    }

    /** The general UTME cut-off a session loads its JAMB lists under (V024): stated before the file is uploaded, whatever the programme. */
    @Transactional(readOnly = true)
    public Map<String, Object> loadCutoff(String session) {
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("cutoff", settings.loadCutoff(session).orElse(null));
        return out;
    }

    @Transactional
    public Map<String, Object> stateLoadCutoff(String session, Integer cutoff) {
        if (cutoff == null || cutoff < 0 || cutoff > 400) {
            throw new DomainRuleViolation("ADM_LOAD_CUTOFF", "A UTME cut-off is a score between 0 and 400.",
                    new DomainRuleViolation.Remedy("State the score under which a candidate on the JAMB list is not loaded.", "Academic Office"));
        }
        settings.stateLoadCutoff(session, cutoff);
        return loadCutoff(session);
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
