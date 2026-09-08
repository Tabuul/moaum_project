package ng.edu.moaum.portal.applicant;

/** A document as uploaded: the file the applicant gave, served back as it arrived. */
public record DocumentContent(String filename, String contentType, byte[] content) {
}
