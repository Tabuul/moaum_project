package ng.edu.moaum.portal.credentials;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

public final class Credentials {

    private Credentials() {
    }

    public record TranscriptRow(UUID id, String ref, UUID studentId, String number, String surname, String otherNames,
                                String destination, String destinationName, String mode, boolean express, int copies,
                                OffsetDateTime requestedAt, OffsetDateTime paidAt, String stage, OffsetDateTime producedAt,
                                UUID producedBy, OffsetDateTime releasedAt, UUID releasedBy, long unitsCleared, String heldBy,
                                String heldReason) {
    }

    public record Transcript(TranscriptRow row, Integer slaDay, boolean breaching, String actionStage) {
    }

    public record TranscriptTiles(long open, long heldAtClearance, long breachingSla, Double averageTurnaroundDays) {
    }

    public record TranscriptQueue(TranscriptTiles tiles, List<Transcript> requests) {
    }

    public record Certificate(UUID id, String number, UUID studentId, String matricNo, String surname, String otherNames,
                              String award, String classOfDegree, String convocation, Integer serial, String batch,
                              String status, LocalDate printedOn, LocalDate collectedOn, String collectedNote,
                              String heldReason, String issuingName, UUID duplicateOf) {
    }

    public record Batch(UUID id, String batch, int serialFrom, int serialTo, LocalDate receivedOn, int issued, long used,
                        int spoiled, int returned) {
    }

    public record Graduand(UUID studentId, String matricNo, String surname, String otherNames, String award, String classOfDegree,
                           String session) {
    }

    public record CertificateTiles(long graduands, long printed, long collected, long stockLeft) {
    }

    public record CertificateRegister(String convocation, CertificateTiles tiles, List<Certificate> certificates,
                                      List<Batch> batches, List<Graduand> awaitingPrint) {
    }
}
