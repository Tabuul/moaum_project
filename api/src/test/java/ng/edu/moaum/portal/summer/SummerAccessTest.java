package ng.edu.moaum.portal.summer;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import jakarta.validation.ConstraintViolation;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;

import org.junit.jupiter.api.Test;

/**
 * V779: the words a Summer export is made of. A text cell that begins like a formula is made plain (=, +, - and @), a cell is quoted
 * when it holds a comma, a quote or a line break, a number is left a number (a credit of −5,000 is not a formula), the file begins
 * with the byte order mark a spreadsheet reads UTF-8 by, and a snake-case column is a camel-case key of the JSON the desk reads.
 * And every course code a Summer request carries may be as long as the catalogue allows (20 characters, ck_course_code, V776), so
 * the database, not bean validation, answers for a long code.
 */
class SummerAccessTest {

    @Test
    void aCellThatLooksLikeAFormulaIsMadePlainAndOneThatMustBeQuotedIsQuoted() {
        assertThat(SummerAccess.Csv.cell("=SUM(A1:A9)")).isEqualTo("'=SUM(A1:A9)");
        assertThat(SummerAccess.Csv.cell("+234 803 000 0000")).isEqualTo("'+234 803 000 0000");
        assertThat(SummerAccess.Csv.cell("-1")).isEqualTo("'-1");
        assertThat(SummerAccess.Csv.cell("@cmd")).isEqualTo("'@cmd");
        // the name of a student whose surname begins with = holds a comma too: made plain, then quoted
        assertThat(SummerAccess.Csv.cell("=ZZ, Invented")).isEqualTo("\"'=ZZ, Invented\"");
        assertThat(SummerAccess.Csv.cell("says \"yes\"")).isEqualTo("\"says \"\"yes\"\"\"");
        assertThat(SummerAccess.Csv.cell("two\nlines")).isEqualTo("\"two\nlines\"");
        assertThat(SummerAccess.Csv.cell("Plain text")).isEqualTo("Plain text");
        assertThat(SummerAccess.Csv.cell(null)).isEmpty();
    }

    @Test
    void aNumberIsLeftANumber() {
        assertThat(SummerAccess.Csv.cell(new BigDecimal("-5000.00"))).isEqualTo("-5000.00");
        assertThat(SummerAccess.Csv.cell(30)).isEqualTo("30");
        assertThat(SummerAccess.Csv.cell(true)).isEqualTo("true");
    }

    @Test
    void theFileBeginsWithTheByteOrderMarkAndEndsEachLineWithCrLf() {
        SummerAccess.Csv csv = new SummerAccess.Csv("Name", "Units");
        csv.row("ZZ Student, Invented", 3);
        csv.row("=Evil", 2);
        assertThat(csv.rows()).isEqualTo(2);
        byte[] bytes = csv.bytes();
        assertThat(bytes[0] & 0xFF).isEqualTo(0xEF);
        assertThat(bytes[1] & 0xFF).isEqualTo(0xBB);
        assertThat(bytes[2] & 0xFF).isEqualTo(0xBF);
        assertThat(new String(bytes, StandardCharsets.UTF_8)).isEqualTo("\uFEFFName,Units\r\n\"ZZ Student, Invented\",3\r\n'=Evil,2\r\n");
    }

    @Test
    void aSnakeCaseColumnIsACamelCaseKey() {
        assertThat(SummerAccess.camel("students_selected")).isEqualTo("studentsSelected");
        assertThat(SummerAccess.camel("eligible")).isEqualTo("eligible");
        Map<String, Object> row = new LinkedHashMap<>();
        row.put("group_code", "FACULTY");
        row.put("eligible_final_year", 3L);
        assertThat(SummerAccess.camel(row)).containsEntry("groupCode", "FACULTY").containsEntry("eligibleFinalYear", 3L);
    }

    @Test
    void aPageAndItsSizeAreHeldToTheirBounds() {
        assertThat(SummerAccess.page(null)).isZero();
        assertThat(SummerAccess.page(-4)).isZero();
        assertThat(SummerAccess.page(3)).isEqualTo(3);
        assertThat(SummerAccess.size(null, 50, 200)).isEqualTo(50);
        assertThat(SummerAccess.size(0, 50, 200)).isEqualTo(1);
        assertThat(SummerAccess.size(5000, 50, 200)).isEqualTo(200);
        assertThat(SummerAccess.nz("  ")).isNull();
        assertThat(SummerAccess.nz(" x ")).isEqualTo("x");
    }

    /** a course code of 17 to 20 characters is one the catalogue takes (^[A-Z][A-Z0-9 /-]{2,19}$): every Summer request that names a
     *  course lets it through to the database's own answer; 21 characters is no course code and is refused before it */
    @Test
    void everyCourseCodeASummerRequestCarriesMayBeAsLongAsTheCatalogueAllowsAndNoLonger() {
        String twenty = "ZZV 40123456789ABCDE";
        String seventeen = twenty.substring(0, 17);
        String twentyOne = twenty + "F";
        assertThat(twenty).hasSize(20).matches("^[A-Z][A-Z0-9 /-]{2,19}$");
        assertThat(twentyOne).doesNotMatch("^[A-Z][A-Z0-9 /-]{2,19}$");
        try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
            Validator v = factory.getValidator();
            for (String code : List.of(seventeen, twenty)) {
                assertThat(v.validate(new SummerController.Select("2025/2026", List.of(code), List.of(new SummerController.Origin(code, "2024/2025", 1))))).isEmpty();
                assertThat(v.validate(new SummerController.Unselect("2025/2026", code))).isEmpty();
                assertThat(v.validate(new SummerController.StudentNote("2025/2026", code, "I failed it in my second year"))).isEmpty();
                assertThat(v.validate(new SummerController.Origin(code, "2024/2025", 2))).isEmpty();
                assertThat(v.validate(new SummerController.Authorise("MOAU/ZZ/25/0001", List.of(code), "Named by the Board", false))).isEmpty();
            }
            assertThat(paths(v.validate(new SummerController.Select("2025/2026", List.of(twentyOne), null)))).singleElement().asString().startsWith("courses[0]");
            assertThat(paths(v.validate(new SummerController.Select("2025/2026", List.of(twenty), List.of(new SummerController.Origin(twentyOne, null, null))))))
                    .singleElement().asString().startsWith("origins[0].course");
            assertThat(paths(v.validate(new SummerController.Unselect("2025/2026", twentyOne)))).containsExactly("course");
            assertThat(paths(v.validate(new SummerController.StudentNote("2025/2026", twentyOne, "A note")))).containsExactly("course");
            assertThat(paths(v.validate(new SummerController.Authorise("MOAU/ZZ/25/0001", List.of(twentyOne), null, false)))).singleElement().asString().startsWith("courses[0]");
        }
    }

    /** G1: a paid course the Academic Office then rejected or found not outstanding has its charge cancelled and its fee held as a
     *  Summer credit, so the queue's charge_state is not PAID; the CSV says what became of the money (the credit's state), never
     *  "Not paid", which stays for a course nobody paid for */
    @Test
    void thePaymentCellSaysWhatBecameOfTheMoneyOfACourseADecisionTookOff() {
        assertThat(SummerAccess.paymentWord("PAID", true, null)).isEqualTo("Paid");
        assertThat(SummerAccess.paymentWord("PAID", false, null)).isEqualTo("Paid, not registered");
        assertThat(SummerAccess.paymentWord("DUE", false, null)).isEqualTo("Unpaid");
        assertThat(SummerAccess.paymentWord(null, false, "OPEN")).isEqualTo("Paid, held as Summer credit");
        assertThat(SummerAccess.paymentWord("CANCELLED", false, "OPEN")).isEqualTo("Paid, held as Summer credit");
        assertThat(SummerAccess.paymentWord(null, false, "APPLIED")).isEqualTo("Paid, Summer credit applied");
        assertThat(SummerAccess.paymentWord(null, false, "REFUNDED")).isEqualTo("Paid, Summer credit refunded");
        assertThat(SummerAccess.paymentWord(null, false, null)).isEqualTo("Not paid");
        assertThat(SummerAccess.paymentWord("CANCELLED", false, null)).isEqualTo("Not paid");
    }

    /** G6: "Verified by" carries the words the desk's screen shows beneath the status (lib/summer.ts VIA_WORD), never an office code */
    @Test
    void verifiedBySaysTheScreensWordsNotAnOfficeCode() {
        assertThat(SummerAccess.verifiedByWord("RESULTS")).isEqualTo("Confirmed by your results");
        assertThat(SummerAccess.verifiedByWord("AUTHORISATION")).isEqualTo("Named by the Academic Office");
        assertThat(SummerAccess.verifiedByWord("OFFICER")).isEqualTo("Confirmed by the Academic Office");
        assertThat(SummerAccess.verifiedByWord(null)).isEmpty();
    }

    private static List<String> paths(Set<? extends ConstraintViolation<?>> violations) {
        return violations.stream().map(c -> c.getPropertyPath().toString()).toList();
    }
}
