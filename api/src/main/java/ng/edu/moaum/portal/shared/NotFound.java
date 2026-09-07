package ng.edu.moaum.portal.shared;

/** The resource named in the request does not exist (or is not visible to the caller). */
public class NotFound extends RuntimeException {

    public NotFound(String what, Object id) {
        super(what + " " + id + " not found");
    }
}
