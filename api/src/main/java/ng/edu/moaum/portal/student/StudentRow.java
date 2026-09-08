package ng.edu.moaum.portal.student;

import java.time.LocalDate;
import java.util.List;
import java.util.UUID;

/**
 * One line of the register: the student, and the chain above them —
 * programme, department, faculty — because no list of students in this
 * University is a list that does not say which.
 */
record StudentRow(UUID id, String matricNo, String admissionNo, String jambRegNo,
                  String surname, String otherNames, String sex, LocalDate dateOfBirth,
                  String programmeCode, String programmeName, String deptCode, String deptName,
                  String facultyCode, String facultyName,
                  String entryMode, String entrySession, int entryLevel, int currentLevel, String status) {

    /**
     * The register in a scope, and the register entire: {@code rows} is what
     * the scope selects, {@code total} is what the University has, so that
     * the scope bar can say "showing N of M".
     */
    record Register(List<StudentRow> rows, int total) {
    }
}
