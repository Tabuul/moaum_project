package ng.edu.moaum.portal.staff;

import java.util.List;
import java.util.UUID;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Two reads. Neither writes anything, so neither needs the audit context —
 * but both run in a transaction so that the offices a person holds and the
 * person themselves are read as of one moment.
 */
@Service
public class StaffService {

    private final StaffRepository staff;

    StaffService(StaffRepository staff) {
        this.staff = staff;
    }

    /**
     * The acting person and the offices they hold. An actor with no row in
     * {@code iam.person} is answered with nulls rather than a 404: they are
     * signed in, and the screen is entitled to say what the Registry has not
     * yet recorded.
     */
    @Transactional(readOnly = true)
    public StaffMe me(UUID actor) {
        if (actor == null) {
            return new StaffMe(null, List.of());
        }
        return new StaffMe(staff.person(actor).orElse(null), staff.offices(actor));
    }

    @Transactional(readOnly = true)
    public College college(String code) {
        String wanted = code == null ? "" : code.trim().toUpperCase();
        College.Row row = staff.college(wanted).orElseThrow(() -> new NotFound("college", wanted));
        return new College(row, staff.faculties(wanted), staff.students(wanted), staff.byLevel(wanted));
    }
}
