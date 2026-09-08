package ng.edu.moaum.portal.ref;

import java.time.LocalDate;

/** A course of the catalogue: owned by one department, live by Senate's approval, ended with a date. */
public record Course(String code, String title, int units, int semester, int level, String deptCode, String deptName,
                     String kind, String state, LocalDate endedOn) {
}
