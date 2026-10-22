package ng.edu.moaum.portal.admissions;

import java.util.ArrayList;
import java.util.LinkedHashMap;
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
        requireUploadingOffice(actor);
        Integer loadCutoff = cutoffFor(request.session(), request.listKind());
        refuseUnknownProgrammes(request.listKind(), request.rows());
        UUID id = UUID.randomUUID();
        int expected = request.rowsExpected() == null || request.rowsExpected() < request.rows().size() ? request.rows().size() : request.rowsExpected();
        caps.insertBatch(id, request.session(), request.source(), blankToNull(request.filename()), request.fileSha256(),
                expected, request.listKind(), request.downloadedOn(), actor.actorId(), actor.actorOffice());
        return insertRows(id, request.session(), request.listKind(), loadCutoff, request.rows());
    }

    /**
     * A large download arrives in several requests. The rows appended join the
     * batch the first request opened, under the same rules, while it is neither
     * committed nor withdrawn.
     */
    @Transactional
    public CapsLoadResult appendRows(UUID batchId, List<CapsRowIn> rows) {
        AuditContext actor = AuditContextHolder.required();
        requireUploadingOffice(actor);
        CapsBatch b = get(batchId);
        if (b.committedAt() != null) {
            throw new DomainRuleViolation("ADM_BATCH_COMMITTED", "The list is committed; nothing is added to it.",
                    new DomainRuleViolation.Remedy("Load the further rows as a new list.", "Academic Office"));
        }
        if (b.withdrawnAt() != null) {
            throw new DomainRuleViolation("ADM_BATCH_WITHDRAWN", "The list was withdrawn; nothing is added to it.",
                    new DomainRuleViolation.Remedy("Load the file again as a new list.", "Academic Office"));
        }
        Integer loadCutoff = cutoffFor(b.session(), b.listKind());
        refuseUnknownProgrammes(b.listKind(), rows);
        return insertRows(batchId, b.session(), b.listKind(), loadCutoff, rows);
    }

    private static void requireUploadingOffice(AuditContext actor) {
        if (!UPLOADING_OFFICES.contains(actor.actorOffice())) {
            throw new DomainRuleViolation("ADM_LIST_OFFICE",
                    "The admission list is loaded by the Academic Office or the Registrar, not by '" + actor.actorOffice() + "'.",
                    new DomainRuleViolation.Remedy("Ask the Academic Office to load the list, or act as that office if you hold it.",
                            "Academic Office"));
        }
    }

    /** the one general cut-off a UTME list loads under (V024); faculty and programme cut-offs are the screening's */
    private Integer cutoffFor(String session, String listKind) {
        if (!"UTME".equals(listKind)) {
            return null;
        }
        return caps.loadCutoff(session).orElseThrow(() -> new DomainRuleViolation("ADM_LOAD_CUTOFF_NOT_STATED",
                "No general UTME cut-off is stated for loading the " + session + " lists, so nothing may be loaded.",
                new DomainRuleViolation.Remedy(
                        "State the general UTME cut-off for loading on the admission settings, then upload the file.",
                        "Academic Office")));
    }

    private void refuseUnknownProgrammes(String listKind, List<CapsRowIn> rows) {
        if (!"UTME".equals(listKind)) {
            return;
        }
        Set<String> codes = rows.stream().map(r -> r.jambCode().trim().toUpperCase()).collect(Collectors.toCollection(LinkedHashSet::new));
        Map<String, String> known = programmeNames();
        List<String> unknown = codes.stream().filter(c -> !known.containsKey(c)).toList();
        if (!unknown.isEmpty()) {
            throw new DomainRuleViolation("ADM_UNKNOWN_PROGRAMME",
                    "Not a programme the University runs: " + String.join(", ", unknown) + ".",
                    new DomainRuleViolation.Remedy("Resolve each JAMB course to a University programme before the list is loaded.",
                            "Academic Office"));
        }
    }

    /**
     * V629: the CAPS download is cumulative — each week's file repeats every candidate already loaded — so each row is read against
     * the session's live list first: the same → skipped; changed by JAMB (the course, the aggregate, the names, sex, state, LGA,
     * the subject scores) → updated in place, the change kept (admissions.caps_row_change); not on it → added under the cut-off.
     */
    private CapsLoadResult insertRows(UUID id, String session, String listKind, Integer loadCutoff, List<CapsRowIn> rows) {
        int loaded = 0, updatedCount = 0, unchanged = 0;
        boolean courseChanged = false;
        List<CapsLoadResult.ExcludedRow> excluded = new ArrayList<>();
        List<CapsLoadResult.UpdatedRow> updated = new ArrayList<>();
        List<String> otherList = new ArrayList<>();
        Map<String, String> names = "UTME".equals(listKind) ? programmeNames() : Map.of();
        AuditContext actor = AuditContextHolder.required();
        Map<String, CapsRepository.LiveRow> live = caps.liveRows(session,
                rows.stream().map(r -> r.jambRegNo().trim().toUpperCase()).collect(Collectors.toCollection(LinkedHashSet::new)));
        Set<String> seen = new java.util.HashSet<>();
        for (CapsRowIn row : rows) {
            Map<String, Object> raw = row.raw() == null ? Map.of() : row.raw();
            String rawJson = json.writeValueAsString(raw);
            String code = row.jambCode().trim().toUpperCase();
            String key = row.jambRegNo().trim().toUpperCase();
            if (!seen.add(key)) {
                unchanged++;   // the same candidate twice in one file: the first stands
                continue;
            }
            CapsRepository.LiveRow was = live.get(key);
            if (was != null) {
                if (!was.entryMode().equals(row.entryMode())) {
                    otherList.add(key);   // on the other list (UTME or Direct Entry): left as it is
                    continue;
                }
                Map<String, Map<String, Object>> changes = changes(was, row, raw);
                if (changes.isEmpty()) {
                    unchanged++;
                    continue;
                }
                caps.updateRow(was.id(), row, rawJson);
                caps.recordChange(was.id(), session, key, id, json.writeValueAsString(changes), actor.actorId(), actor.actorOffice());
                updatedCount++;
                courseChanged |= changes.containsKey("course");
                if (updated.size() < CapsLoadResult.UPDATED_LISTED) {
                    updated.add(new CapsLoadResult.UpdatedRow(key, row.surname().trim(), row.otherNames(), changes));
                }
                continue;
            }
            if (loadCutoff != null && row.aggregate() != null && row.aggregate() < loadCutoff) {
                caps.insertExcluded(id, session, row, loadCutoff, "BELOW_CUTOFF", rawJson);
                excluded.add(new CapsLoadResult.ExcludedRow(row.jambRegNo().trim().toUpperCase(), row.surname(),
                        row.otherNames(), code, names.getOrDefault(code, code), row.aggregate(), loadCutoff, "BELOW_CUTOFF"));
                continue;
            }
            caps.insertRow(id, session, row, rawJson);
            loaded++;
        }
        caps.countMerge(id, updatedCount, unchanged);
        // V636: a candidate on the portal whose course JAMB changed follows it unless an offer stands
        int followed = 0, admittedLeft = 0;
        if (courseChanged) {
            Map<String, Object> f = caps.followCapsCourse(session, false);
            followed = ((Number) f.get("followed")).intValue();
            admittedLeft = ((Number) f.get("admitted_left")).intValue();
        }
        return new CapsLoadResult(caps.find(id).orElseThrow(), loaded, excluded, updatedCount, unchanged, updated, otherList, followed, admittedLeft);
    }

    /**
     * V636: the candidates JAMB moved on the live list, followed where no released offer stands — the programme set to JAMB's, a
     * programme change approved as made, the applicant told — and counted apart where one does; a dry run names them and writes
     * nothing. By the offices that load the list.
     */
    @Transactional
    public Map<String, Object> followCapsCourse(String session, boolean dryRun) {
        requireUploadingOffice(AuditContextHolder.required());
        Map<String, Object> r = caps.followCapsCourse(session, dryRun);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("dryRun", dryRun);
        out.put("followed", r.get("followed"));
        out.put("admittedLeft", r.get("admitted_left"));
        out.put("named", json.readValue(String.valueOf(r.get("named")), List.class));
        return out;
    }

    /**
     * V636: before a list is committed, the candidates of its session whose course JAMB changed follow it where no offer stands —
     * in a transaction of their own, so they stay followed when the commit is then refused for another finding. A list loaded
     * before V636 carried the changes without the follow, and its commit was refused for them.
     */
    @Transactional
    public Map<String, Object> followBeforeCommit(UUID id) {
        return followCapsCourse(get(id).session(), false);
    }

    /** V629: the subject columns of either layout (and JAMB's course name), compared as the file wrote them */
    private static final Set<String> SUBJECT_KEYS = Set.of("coname", "subject1", "rgsub1score", "subject2", "rgsub2score", "subject3",
            "rgsub3score", "engscore", "sub1", "sub1score", "sub2", "sub2score", "sub3", "sub3score", "sub4score");

    private static String norm(String s) {
        return s == null ? "" : s.toLowerCase().replaceAll("[^a-z0-9]", "");
    }

    private static String text(Object v) {
        String t = v == null ? "" : String.valueOf(v).trim();
        return t.isEmpty() ? null : t;
    }

    /** the subjects and scores as "Physics 96 · Biology 85 · …", from whichever columns the file carried */
    private String subjects(Map<String, Object> raw) {
        java.util.TreeMap<String, String> by = new java.util.TreeMap<>();
        raw.forEach((k, v) -> {
            String n = norm(k);
            if (SUBJECT_KEYS.contains(n) && text(v) != null) {
                by.put(n, text(v));
            }
        });
        return String.join(" · ", by.entrySet().stream().map(e -> e.getKey() + " " + e.getValue()).toList());
    }

    private Map<String, Object> rawOf(String rawJson) {
        if (rawJson == null || rawJson.isBlank()) {
            return Map.of();
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> m = json.readValue(rawJson, Map.class);
        return m == null ? Map.of() : m;
    }

    /** V629: what JAMB changed for a candidate already on the list, field by field; nothing when it is the same */
    private Map<String, Map<String, Object>> changes(CapsRepository.LiveRow was, CapsRowIn row, Map<String, Object> raw) {
        Map<String, Map<String, Object>> out = new java.util.LinkedHashMap<>();
        java.util.function.BiConsumer<String, Object[]> put = (field, pair) -> out.put(field, new java.util.LinkedHashMap<>(Map.of(
                "from", pair[0] == null ? "" : pair[0], "to", pair[1] == null ? "" : pair[1])));
        String code = row.jambCode().trim().toUpperCase();
        if (!code.equals(was.jambCode())) put.accept("course", new Object[] {was.jambCode(), code});
        if (!java.util.Objects.equals(was.aggregate(), row.aggregate())) put.accept("aggregate", new Object[] {was.aggregate(), row.aggregate()});
        if (!java.util.Objects.equals(text(was.surname()), text(row.surname()))) put.accept("surname", new Object[] {was.surname(), text(row.surname())});
        if (!java.util.Objects.equals(text(was.otherNames()), text(row.otherNames()))) put.accept("otherNames", new Object[] {was.otherNames(), text(row.otherNames())});
        if (!java.util.Objects.equals(text(was.sex()), text(row.sex()))) put.accept("sex", new Object[] {was.sex(), text(row.sex())});
        if (!java.util.Objects.equals(text(was.stateOfOrigin()), text(row.stateOfOrigin()))) put.accept("state", new Object[] {was.stateOfOrigin(), text(row.stateOfOrigin())});
        if (!java.util.Objects.equals(text(was.lga()), text(row.lga()))) put.accept("lga", new Object[] {was.lga(), text(row.lga())});
        String before = subjects(rawOf(was.raw())), after = subjects(raw);
        if (!before.equals(after)) put.accept("subjects", new Object[] {before, after});
        return out;
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

    /** the applicants on committed admission lists for a session — filterable by faculty, programme
     *  and entry mode — with a per-programme breakdown and how many have registered */
    @Transactional(readOnly = true)
    public Map<String, Object> applicants(String session, String q, String faculty, String programme, String entryMode, int limit) {
        String fac = faculty == null || faculty.isBlank() ? null : faculty.trim();
        String prog = programme == null || programme.isBlank() ? null : programme.trim();
        String em = entryMode == null || entryMode.isBlank() ? null : entryMode.trim();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("counts", caps.applicantCounts(session, fac, prog, em));
        out.put("breakdown", caps.applicantBreakdown(session, fac, prog, em));
        out.put("applicants", caps.applicants(session, q == null || q.isBlank() ? null : q.trim(), fac, prog, em, Math.min(Math.max(limit, 1), 500)));
        return out;
    }

    /** the programmes registered for post-UTME and their score-upload status, so the office knows
     *  which programmes' scores must be uploaded before the admission process proceeds */
    @Transactional(readOnly = true)
    public Map<String, Object> postUtmeProgrammes(String session) {
        java.util.List<java.util.Map<String, Object>> rows = caps.postUtmeProgrammes(session);
        long programmes = rows.size();
        long awaiting = rows.stream().filter(r -> ((Number) r.get("awaiting")).longValue() > 0).count();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("counts", Map.of("programmes", programmes, "awaitingScores", awaiting));
        out.put("programmes", rows);
        return out;
    }

    /** the merit list for a programme: the eligible pool ranked, with the proposed offer that fills the quota */
    @Transactional(readOnly = true)
    public Map<String, Object> meritList(String session, String programme) {
        java.util.List<java.util.Map<String, Object>> rows = caps.meritList(session, programme);
        long eligible = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("eligible"))).count();
        long offered = rows.stream().filter(r -> Boolean.TRUE.equals(r.get("proposed_offer"))).count();
        java.util.Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("programme", programme);
        out.put("counts", Map.of("pool", rows.size(), "eligible", eligible, "proposed", offered));
        out.put("rows", rows);
        return out;
    }

    /** per-programme Direct Entry screening: the DE applicants and the subject gate's verdict (V200).
     *  Screening-only — this reports, it does not gate the offer decision. */
    @Transactional(readOnly = true)
    public Map<String, Object> deScreening(String session, String programme) {
        java.util.List<java.util.Map<String, Object>> rows = caps.deScreening(session, programme);
        long met = rows.stream().filter(r -> "MET".equals(r.get("status"))).count();
        long shortfall = rows.stream().filter(r -> "SHORT".equals(r.get("status"))).count();
        long unverified = rows.stream().filter(r -> "UNVERIFIED".equals(r.get("status"))).count();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("programme", programme);
        out.put("counts", Map.of("pool", rows.size(), "met", met, "shortfall", shortfall, "unverified", unverified));
        out.put("rows", rows);
        return out;
    }

    /** the Direct Entry awards captured for a candidate, each with its subjects (V200) */
    @Transactional(readOnly = true)
    public java.util.List<java.util.Map<String, Object>> deAwards(String session, String jambKey) {
        return caps.deAwards(session, jambKey);
    }

    /** record (replace whole) a candidate's Direct Entry award and its subjects; returns the candidate's awards (V200) */
    @Transactional
    public java.util.List<java.util.Map<String, Object>> recordDeAward(String session, String jambKey, String basis,
            Integer year, String institution, java.util.List<java.util.Map<String, String>> subjects) {
        AuditContext actor = AuditContextHolder.required();
        caps.recordDeAward(session, jambKey, basis == null ? null : basis.trim().toUpperCase(), year, institution,
                subjects == null ? java.util.List.of() : subjects, actor.actorId());
        return caps.deAwards(session, jambKey);
    }

    /** remove one Direct Entry award (V200) */
    @Transactional
    public void deleteDeAward(java.util.UUID id) {
        AuditContextHolder.required();
        caps.deleteDeAward(id);
    }

    /** the Board records the proposed merit list in a batch: an offer (with its basis) for each proposed
     *  candidate, the waiting list for the eligible below the line, and NOT OFFERED — with the reason — for
     *  the ineligible, so every candidate in the pool carries a decision and the JAMB template reconciles;
     *  a released decision is left untouched */
    @Transactional
    public Map<String, Object> recordMerit(String session, String programme) {
        List<Map<String, Object>> rows = caps.meritList(session, programme);
        int offered = 0;
        int waited = 0;
        int notOffered = 0;
        int skipped = 0;
        for (Map<String, Object> r : rows) {
            java.util.UUID app = (java.util.UUID) r.get("app_id");
            if (caps.decisionReleased(app)) {
                skipped++;
                continue;
            }
            if (!Boolean.TRUE.equals(r.get("eligible"))) {
                boolean cut = Boolean.TRUE.equals(r.get("meets_cutoff"));
                boolean comp = Boolean.TRUE.equals(r.get("meets_compulsory"));
                boolean utme = Boolean.TRUE.equals(r.get("meets_utme"));
                List<String> why = new ArrayList<>();
                if (!cut || !comp) {
                    why.add(!cut && !comp ? "Below the cut-off and the O'Level requirement not met"
                            : !cut ? "Below the programme cut-off"
                            : "O'Level requirement not met");
                }
                if (!utme) {
                    why.add("Incorrect UTME subject combination");
                }
                caps.decide(app, "NOT_OFFERED", why.isEmpty() ? "Not qualified on the merit list" : String.join("; ", why), null);
                notOffered++;
                continue;
            }
            if (Boolean.TRUE.equals(r.get("proposed_offer"))) {
                caps.decide(app, "OFFERED", "Recorded from the merit list", (String) r.get("basis"));
                offered++;
            } else {
                caps.decide(app, "WAITING", "Eligible, below the quota line on the merit list", null);
                waited++;
            }
        }
        return Map.of("programme", programme, "offered", offered, "waited", waited,
                "notOffered", notOffered, "skipped", skipped, "pool", rows.size());
    }

    /** record the merit list for several programmes at once (all with a pool when none are named), so the
     *  Board commits the offers across programmes in one action */
    @Transactional
    public Map<String, Object> recordMeritMany(String session, List<String> programmes) {
        List<String> codes = (programmes == null || programmes.isEmpty()) ? caps.programmesWithPool(session) : programmes;
        int offered = 0, waited = 0, notOffered = 0, skipped = 0, done = 0;
        List<Map<String, Object>> each = new ArrayList<>();
        for (String code : codes) {
            Map<String, Object> r = recordMerit(session, code);
            offered += ((Number) r.get("offered")).intValue();
            waited += ((Number) r.get("waited")).intValue();
            notOffered += ((Number) r.get("notOffered")).intValue();
            skipped += ((Number) r.get("skipped")).intValue();
            done++;
            each.add(r);
        }
        return Map.of("programmes", done, "offered", offered, "waited", waited,
                "notOffered", notOffered, "skipped", skipped, "each", each);
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
                    new DomainRuleViolation.Remedy("If " + holder.get()
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

    @Transactional
    public java.util.Map<String, Object> resetIntake(String session) {
        return caps.resetIntake(session);
    }

    /** the JAMB admission-status list uploaded back: match by registration number, offer and release the accepted */
    @Transactional
    public java.util.Map<String, Object> loadJambAdmissions(String session, List<Map<String, Object>> rows) {
        if (rows == null || rows.isEmpty()) {
            throw new DomainRuleViolation("ADM_JAMB_ROWS", "The list is rows: registration number, name, course, admission status.",
                    new DomainRuleViolation.Remedy("Download the admission-status file from JAMB and upload its rows.", "Academic Office"));
        }
        return caps.loadJambAdmissions(session, json.writeValueAsString(rows));
    }

    @Transactional(readOnly = true)
    public Map<String, Object> jambAdmissions(String session) {
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session);
        out.put("tiles", caps.jambAdmissionTiles(session));
        out.put("rows", caps.jambAdmissionList(session));
        return out;
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
