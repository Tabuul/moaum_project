package ng.edu.moaum.portal.library;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class LibraryService {

    private static final List<String> KINDS = List.of("BOOK", "JOURNAL", "THESIS", "AUDIOVISUAL", "REFERENCE");

    private final LibraryRepository repo;

    LibraryService(LibraryRepository repo) {
        this.repo = repo;
    }

    /* ── the student ── */

    @Transactional(readOnly = true)
    public Map<String, Object> mine(UUID student, String q) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("setting", repo.setting());
        out.put("standing", repo.standing(student));
        out.put("loans", repo.loansOf(student));
        out.put("reservations", repo.reservationsOf(student));
        out.put("catalogue", q == null || q.isBlank() ? List.of() : repo.search(q.trim()));
        return out;
    }

    @Transactional
    public Map<String, Object> renew(UUID student, UUID loan) {
        UUID owner = repo.loanOwner(loan).orElseThrow(() -> new NotFound("loan", loan));
        if (!student.equals(owner)) {
            throw new NotFound("loan", loan);
        }
        return Map.of("loanId", loan, "dueOn", repo.renew(loan));
    }

    @Transactional
    public Map<String, Object> reserve(UUID student, UUID item) {
        return Map.of("reservationId", repo.reserve(item, student), "state", "WAITING");
    }

    @Transactional
    public Map<String, Object> fineReference(UUID student, UUID loan) {
        UUID owner = repo.loanOwner(loan).orElseThrow(() -> new NotFound("loan", loan));
        if (!student.equals(owner)) {
            throw new NotFound("loan", loan);
        }
        return Map.of("loanId", loan, "reference", repo.fineReference(loan));
    }

    /* ── the desk ── */

    @Transactional(readOnly = true)
    public Map<String, Object> desk(String patronNumber, String q) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("setting", repo.setting());
        out.put("tiles", repo.tiles());
        out.put("today", repo.today());
        out.put("overdue", repo.overdue());
        out.put("fines", repo.finesUnpaid());
        out.put("catalogue", q == null || q.isBlank() ? List.of() : repo.search(q.trim()));
        if (patronNumber != null && !patronNumber.isBlank()) {
            Map<String, Object> p = repo.patron(patronNumber.trim()).orElse(null);
            out.put("patron", p);
            if (p != null && p.get("student_id") != null) {
                UUID sid = (UUID) p.get("student_id");
                out.put("patronStanding", repo.standing(sid));
                out.put("patronLoans", repo.loansOf(sid));
            }
        }
        return out;
    }

    @Transactional
    public Map<String, Object> issue(String accession, String patronNumber) {
        Map<String, Object> p = repo.patron(patronNumber == null ? "" : patronNumber.trim()).orElseThrow(() -> new DomainRuleViolation("LIB_NO_PATRON",
                "No student or member of staff carries the number " + patronNumber + ".",
                new DomainRuleViolation.Remedy("The matriculation number, the admission number or the staff number, as issued.", "Library")));
        UUID loan = repo.issue(accession == null ? "" : accession.trim().toUpperCase(), (UUID) p.get("student_id"), (UUID) p.get("person_id"));
        return Map.of("loanId", loan, "patron", p.get("name"), "accession", accession.trim().toUpperCase());
    }

    @Transactional
    public Map<String, Object> giveBack(String accession) {
        return repo.giveBack(accession == null ? "" : accession.trim().toUpperCase());
    }

    @Transactional
    public Map<String, Object> renewAtDesk(UUID loan) {
        repo.loanOwner(loan).orElseThrow(() -> new NotFound("loan", loan));
        return Map.of("loanId", loan, "dueOn", repo.renew(loan));
    }

    @Transactional
    public Map<String, Object> waive(UUID loan, String why) {
        repo.waive(loan, why);
        return Map.of("loanId", loan, "waived", true);
    }

    @Transactional
    public Map<String, Object> putSetting(Integer loanDays, BigDecimal finePerDay, Integer maxLoans, Integer maxRenewals) {
        Map<String, Object> was = repo.setting();
        repo.putSetting(loanDays == null ? ((Number) was.get("loan_days")).intValue() : loanDays,
                finePerDay == null ? (BigDecimal) was.get("fine_per_day") : finePerDay,
                maxLoans == null ? ((Number) was.get("max_loans")).intValue() : maxLoans,
                maxRenewals == null ? ((Number) was.get("max_renewals")).intValue() : maxRenewals);
        return repo.setting();
    }

    @Transactional
    public Map<String, Object> putItem(UUID id, String title, String author, String edition, Integer year, String isbn, String subject, String kind, List<String> accessions, String location) {
        if (title == null || title.isBlank()) {
            throw new DomainRuleViolation("LIB_TITLE", "An item has a title.", new DomainRuleViolation.Remedy("As it is on the title page.", "Library"));
        }
        String k = kind == null || kind.isBlank() ? "BOOK" : kind.trim().toUpperCase();
        if (!KINDS.contains(k)) {
            throw new DomainRuleViolation("LIB_KIND", "The kind is one the catalogue knows.", new DomainRuleViolation.Remedy(String.join(", ", KINDS), "Library"));
        }
        UUID v = repo.putItem(id, title.trim(), author, edition, year, isbn, subject, k);
        int copies = 0;
        for (String a : accessions == null ? List.<String>of() : accessions) {
            if (a != null && !a.isBlank()) {
                repo.putCopy(a.trim().toUpperCase(), v, location);
                copies++;
            }
        }
        return Map.of("itemId", v, "copies", copies);
    }
}
