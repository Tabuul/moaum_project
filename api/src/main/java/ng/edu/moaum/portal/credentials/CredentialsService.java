package ng.edu.moaum.portal.credentials;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.Year;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CredentialsService {

    public record TranscriptIn(@NotNull UUID studentId, @NotBlank String destination, String destinationName, String mode,
                               Boolean express, @Min(1) @Max(10) Integer copies, Boolean paid) {
    }

    public record BatchIn(@NotBlank String batch, @NotNull @Min(1) Integer serialFrom, @NotNull @Min(1) Integer serialTo,
                          @NotNull LocalDate receivedOn) {
    }

    public record PrintIn(@NotNull UUID studentId, UUID batchId, String convocation) {
    }

    private final CredentialsRepository repo;

    CredentialsService(CredentialsRepository repo) {
        this.repo = repo;
    }

    static int workingDays(OffsetDateTime from, OffsetDateTime to) {
        LocalDate a = from.toLocalDate();
        LocalDate b = to.toLocalDate();
        int n = 0;
        for (LocalDate d = a; d.isBefore(b); d = d.plusDays(1)) {
            if (d.getDayOfWeek() != DayOfWeek.SATURDAY && d.getDayOfWeek() != DayOfWeek.SUNDAY) {
                n++;
            }
        }
        return n;
    }

    private Credentials.Transcript view(Credentials.TranscriptRow r) {
        OffsetDateTime now = OffsetDateTime.now();
        Integer sla = r.paidAt() == null ? null : workingDays(r.paidAt(), r.releasedAt() == null ? now : r.releasedAt());
        boolean breaching = sla != null && sla > 5 && !"RELEASED".equals(r.stage());
        String action = switch (r.stage()) {
            case "AWAITING_PAYMENT" -> "NOT_PAYABLE";
            case "HELD_AT_CLEARANCE" -> "BLOCKED";
            case "READY" -> r.heldBy() != null ? "BLOCKED" : "PRODUCE";
            case "VERIFIED" -> "RELEASE";
            default -> "VERIFICATION";
        };
        return new Credentials.Transcript(r, sla, breaching, action);
    }

    @Transactional(readOnly = true)
    public Credentials.TranscriptQueue transcripts() {
        List<Credentials.Transcript> out = new ArrayList<>();
        long open = 0;
        long held = 0;
        long breaching = 0;
        double turnaround = 0;
        int released = 0;
        for (Credentials.TranscriptRow r : repo.transcripts()) {
            Credentials.Transcript t = view(r);
            out.add(t);
            if (!"RELEASED".equals(r.stage())) {
                open++;
            } else if (r.paidAt() != null) {
                turnaround += ChronoUnit.HOURS.between(r.paidAt(), r.releasedAt()) / 24.0;
                released++;
            }
            if ("BLOCKED".equals(t.actionStage())) {
                held++;
            }
            if (t.breaching()) {
                breaching++;
            }
        }
        return new Credentials.TranscriptQueue(new Credentials.TranscriptTiles(open, held, breaching,
                released == 0 ? null : Math.round(10.0 * turnaround / released) / 10.0), out);
    }

    private String stageFor(UUID student, boolean paid) {
        if (!paid) {
            return "AWAITING_PAYMENT";
        }
        return repo.isClear(student, "TRANSCRIPT") ? "READY" : "HELD_AT_CLEARANCE";
    }

    @Transactional
    public Credentials.Transcript request(TranscriptIn in) {
        if (!repo.studentExists(in.studentId())) {
            throw new NotFound("student", in.studentId());
        }
        String year = String.valueOf(Year.now().getValue());
        String ref = "TRN-" + year + "-" + String.format("%05d", repo.next("TRANSCRIPT", "UNIVERSITY", year));
        UUID id = repo.createTranscript(ref, in, stageFor(in.studentId(), in.paid() != null && in.paid()));
        return view(repo.transcript(id).orElseThrow());
    }

    @Transactional
    public Credentials.Transcript markPaid(UUID id) {
        Credentials.TranscriptRow r = repo.transcript(id).orElseThrow(() -> new NotFound("transcript request", id));
        if (r.paidAt() != null) {
            throw new DomainRuleViolation("CTP_ALREADY_PAID", "Request " + r.ref() + " is already paid.",
                    new DomainRuleViolation.Remedy("Nothing to do.", "Bursary"));
        }
        repo.markPaid(id, stageFor(r.studentId(), true));
        return view(repo.transcript(id).orElseThrow());
    }

    @Transactional
    public Credentials.Transcript produce(UUID id) {
        Credentials.TranscriptRow r = repo.transcript(id).orElseThrow(() -> new NotFound("transcript request", id));
        if (r.paidAt() != null && "HELD_AT_CLEARANCE".equals(r.stage()) && repo.isClear(r.studentId(), "TRANSCRIPT")) {
            repo.setStage(id, "READY");
        }
        repo.produce(id);
        return view(repo.transcript(id).orElseThrow());
    }

    @Transactional
    public Credentials.Transcript release(UUID id) {
        repo.transcript(id).orElseThrow(() -> new NotFound("transcript request", id));
        repo.release(id);
        return view(repo.transcript(id).orElseThrow());
    }

    @Transactional(readOnly = true)
    public Credentials.CertificateRegister register(String convocation) {
        List<Credentials.Certificate> certs = repo.certificates(convocation);
        long printed = certs.stream().filter(c -> !"REVOKED".equals(c.status())).count();
        long collected = certs.stream().filter(c -> "COLLECTED".equals(c.status())).count();
        List<Credentials.Batch> batches = repo.batches();
        long stock = 0;
        for (Credentials.Batch b : batches) {
            stock += b.issued() - b.used() - b.spoiled() - b.returned();
        }
        String session = convocation == null ? null : convocation.replaceAll("[^0-9/]", "");
        long graduands = repo.approvedGraduands(session != null && session.matches("\\d{4}/\\d{4}") ? session : null);
        return new Credentials.CertificateRegister(convocation, new Credentials.CertificateTiles(graduands, printed, collected, stock),
                certs, batches, repo.awaitingPrint());
    }

    /** Printed only against a Senate-approved award and a cleared candidate; the serial comes off the batch. */
    @Transactional
    public Credentials.Certificate print(PrintIn in) {
        Credentials.Graduand g = repo.approvedGraduand(in.studentId()).orElseThrow(() -> new DomainRuleViolation("CRED_NOT_GRADUATED",
                "No Senate-approved award stands against this student.",
                new DomainRuleViolation.Remedy("A certificate is printed only against a graduand Senate has approved. Run the degree audit and send the list to Senate.", "Academic Office")));
        if (!repo.isClear(in.studentId(), "CONVOCATION")) {
            throw new DomainRuleViolation("CRED_NOT_CLEARED", "The candidate is held by a unit.",
                    new DomainRuleViolation.Remedy("The certificate is printed only against a cleared record; the student's clearance screen names the unit.", "The unit holding"));
        }
        Integer serial = null;
        if (in.batchId() != null) {
            repo.batch(in.batchId()).orElseThrow(() -> new NotFound("stationery batch", in.batchId()));
            serial = repo.nextSerial(in.batchId());
            if (serial == null) {
                throw new DomainRuleViolation("CRED_BATCH_EXHAUSTED", "Every serial of that batch is used.",
                        new DomainRuleViolation.Remedy("Print from another batch, or record the next batch received.", "Academic Office"));
            }
        }
        String year = String.valueOf(Year.now().getValue());
        String number = "MOAUM/C/" + year.substring(2) + "/" + String.format("%05d", repo.next("CERTIFICATE", "UNIVERSITY", year));
        String convocation = in.convocation() == null || in.convocation().isBlank() ? "Convocation " + year : in.convocation();
        UUID id = repo.insertCertificate(number, in.studentId(), g.award(), g.classOfDegree() == null ? "Pass" : g.classOfDegree(),
                convocation, serial, in.batchId(), null);
        return repo.certificate(id).orElseThrow();
    }

    @Transactional
    public Credentials.Certificate collect(UUID id, String note) {
        Credentials.Certificate c = repo.certificate(id).orElseThrow(() -> new NotFound("certificate", id));
        if ("HELD".equals(c.status())) {
            throw new DomainRuleViolation("CRED_HELD", "Certificate " + c.number() + " is held: " + c.heldReason(),
                    new DomainRuleViolation.Remedy("Clear the hold before it is handed over.", "The unit holding"));
        }
        repo.setCertificate(id, "COLLECTED", LocalDate.now(), note == null ? "Identity verified at collection" : note, null);
        return repo.certificate(id).orElseThrow();
    }

    @Transactional
    public Credentials.Certificate hold(UUID id, String reason) {
        repo.certificate(id).orElseThrow(() -> new NotFound("certificate", id));
        if (reason == null || reason.isBlank()) {
            throw new DomainRuleViolation("CRED_HOLD_SAYS_WHY", "A held certificate names the reason.",
                    new DomainRuleViolation.Remedy("Say which clearance is outstanding.", "Academic Office"));
        }
        repo.setCertificate(id, "HELD", null, null, reason);
        return repo.certificate(id).orElseThrow();
    }

    /** A lost certificate is reissued as a duplicate; the original stays on the register as reissued. */
    @Transactional
    public Credentials.Certificate reissue(UUID id, String reason, UUID batchId) {
        Credentials.Certificate old = repo.certificate(id).orElseThrow(() -> new NotFound("certificate", id));
        if (reason == null || reason.isBlank()) {
            throw new DomainRuleViolation("CRED_REISSUE_SAYS_WHY", "A reissue carries the affidavit and police report reference.",
                    new DomainRuleViolation.Remedy("Record the evidence the duplicate is issued on.", "Academic Office"));
        }
        Integer serial = batchId == null ? null : repo.nextSerial(batchId);
        String year = String.valueOf(Year.now().getValue());
        String number = "MOAUM/C/" + year.substring(2) + "/" + String.format("%05d", repo.next("CERTIFICATE", "UNIVERSITY", year));
        UUID dup = repo.insertCertificate(number, old.studentId(), old.award(), old.classOfDegree(), old.convocation(), serial, batchId, id);
        repo.setCertificate(id, "REISSUED", null, null, null);
        return repo.certificate(dup).orElseThrow();
    }

    @Transactional
    public Credentials.Batch batch(BatchIn in) {
        if (in.serialTo() < in.serialFrom()) {
            throw new DomainRuleViolation("CRED_BATCH_RANGE", "The serial range runs backwards.",
                    new DomainRuleViolation.Remedy("The last serial is not below the first.", "Academic Office"));
        }
        UUID id = repo.createBatch(in.batch().trim(), in.serialFrom(), in.serialTo(), in.receivedOn());
        return repo.batch(id).orElseThrow();
    }

    @Transactional
    public Credentials.Batch count(UUID id, String what, int n) {
        repo.batch(id).orElseThrow(() -> new NotFound("stationery batch", id));
        if (n <= 0) {
            throw new DomainRuleViolation("CRED_COUNT", "A count is a positive number.", new DomainRuleViolation.Remedy("How many?", "Academic Office"));
        }
        repo.countBatch(id, "spoil".equals(what) ? "spoiled" : "returned", n);
        return repo.batch(id).orElseThrow();
    }

    Map<String, Object> summary() {
        return Map.of();
    }
}
