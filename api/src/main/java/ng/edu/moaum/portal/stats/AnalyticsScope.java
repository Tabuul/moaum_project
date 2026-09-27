package ng.edu.moaum.portal.stats;

import java.util.Set;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.stereotype.Component;

/**
 * The one scope every analytics figure is held to (V257, shared since V279): the
 * Postgraduate School sees only postgraduates, the College of Health Sciences only its
 * own students and payers, a Dean or Faculty Officer their faculty, a Head of
 * Department their department; the University's offices see everyone. Amounts are
 * shown to the offices that hold the purse. The bound is read from the acting office
 * and its assignment on the server — never from a request parameter — and the student
 * statistics, the financial analytics and the admission funnel all apply it.
 */
@Component
public class AnalyticsScope {

    public static final Set<String> PG_OFFICES = Set.of("pgschool", "pgsecretary");
    public static final Set<String> CHS_OFFICES = Set.of("provost", "collegesecretary", "financecontroller");
    /** the offices that see amounts and individual transactions */
    public static final Set<String> MONEY = Set.of("bursar", "financecontroller", "registrar", "dregistrar", "super", "admin",
            "pgschool", "pgsecretary", "provost", "collegesecretary", "dvc", "vc", "audit");
    /** the offices that read the financial summary of their scope without the individual transactions */
    public static final Set<String> SUMMARY_ONLY = Set.of("ict", "academic");
    /** the offices bound to a faculty or a department that may read their own scope's money */
    public static final Set<String> SCOPED_MONEY = Set.of("dean", "facultyofficer", "hod");

    /** the scope the acting office is held to, and the predicates that hold it */
    public record Bound(String kind, String label, String faculty, String dept, boolean money) {
        public boolean pg() {
            return "PG_SCHOOL".equals(kind);
        }
        public boolean chs() {
            return "COLLEGE".equals(kind);
        }
    }

    private final OfficeScope scope;

    AnalyticsScope(OfficeScope scope) {
        this.scope = scope;
    }

    public String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    public Bound bound() {
        String office = office();
        boolean money = MONEY.contains(office) || SCOPED_MONEY.contains(office);
        if (PG_OFFICES.contains(office)) return new Bound("PG_SCHOOL", "Postgraduate School", null, null, money);
        if (CHS_OFFICES.contains(office)) return new Bound("COLLEGE", "College of Health Sciences", null, null, money);
        if (scope.actingFacultyOffice()) {
            String f = scope.actingFaculty();
            return new Bound("FACULTY", "Faculty", f == null ? "__none__" : f, null, money);
        }
        if (scope.actingDepartmentOffice()) {
            String d = scope.actingDept();
            return new Bound("DEPARTMENT", "Department", null, d == null ? "__none__" : d, money);
        }
        return new Bound("UNIVERSITY", "University", null, null, money);
    }

    /** whether the acting office may open the individual transactions of its scope (not only the summary) */
    public boolean transactions() {
        String office = office();
        return MONEY.contains(office) || SCOPED_MONEY.contains(office);
    }
}
