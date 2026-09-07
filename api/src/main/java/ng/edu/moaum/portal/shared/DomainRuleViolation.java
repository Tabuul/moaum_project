package ng.edu.moaum.portal.shared;

/**
 * A domain rule refused the request. Rendered as an RFC 9457 problem with
 * status 422, a stable {@code code}, and — because NFR-USA-005 requires every
 * blocking condition to state its remedy and the responsible office — a
 * {@link Remedy} the frontend cannot forget to show.
 */
public class DomainRuleViolation extends RuntimeException {

    private final String code;
    private final Remedy remedy;

    public DomainRuleViolation(String code, String detail, Remedy remedy) {
        super(detail);
        this.code = code;
        this.remedy = remedy;
    }

    public DomainRuleViolation(String code, String detail) {
        this(code, detail, null);
    }

    public String code() {
        return code;
    }

    public Remedy remedy() {
        return remedy;
    }

    /** What the person can do about it, and whose desk it is. */
    public record Remedy(String message, String office) {
    }
}
