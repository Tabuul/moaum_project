package ng.edu.moaum.portal.library;

import java.sql.Types;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class LibraryRepository {

    private static final String LOAN = """
            SELECT l.id, l.accession, l.issued_at, l.due_on, l.renewals, l.returned_at, l.fine, l.fine_reference, l.fine_settled_at, l.fine_waived_at,
                   i.id AS item_id, i.title, i.author, i.edition, i.year,
                   greatest(0, current_date - l.due_on) AS days_overdue,
                   CASE WHEN l.returned_at IS NULL THEN (l.due_on - current_date) END AS days_left,
                   st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number,
                   coalesce(st.surname || ', ' || st.other_names, p.surname || ', ' || p.given_names) AS patron,
                   p.staff_number
              FROM library.loan l
              JOIN library.copy c ON c.accession = l.accession
              JOIN library.item i ON i.id = c.item_id
              LEFT JOIN people.student st ON st.id = l.student_id
              LEFT JOIN iam.person p ON p.id = l.person_id
            """;

    private final JdbcClient jdbc;

    LibraryRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Map<String, Object> setting() {
        return jdbc.sql("SELECT loan_days, fine_per_day, max_loans, max_renewals FROM library.setting WHERE id = 1").query().singleRow();
    }

    void putSetting(int loanDays, java.math.BigDecimal finePerDay, int maxLoans, int maxRenewals) {
        jdbc.sql("UPDATE library.setting SET loan_days = :d, fine_per_day = :f, max_loans = :l, max_renewals = :r WHERE id = 1")
                .param("d", loanDays).param("f", finePerDay).param("l", maxLoans).param("r", maxRenewals).update();
    }

    Map<String, Object> standing(UUID student) {
        return jdbc.sql("SELECT * FROM library.standing(:s)").param("s", student).query().singleRow();
    }

    List<Map<String, Object>> loansOf(UUID student) {
        return jdbc.sql(LOAN + " WHERE l.student_id = :s ORDER BY (l.returned_at IS NULL) DESC, l.due_on, l.issued_at DESC LIMIT 100")
                .param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> reservationsOf(UUID student) {
        return jdbc.sql("""
                SELECT r.id, r.state, r.reserved_at, r.decided_at, i.id AS item_id, i.title, i.author,
                       (SELECT count(*) FROM library.reservation q WHERE q.item_id = r.item_id AND q.state = 'WAITING' AND q.reserved_at < r.reserved_at) AS ahead
                  FROM library.reservation r JOIN library.item i ON i.id = r.item_id
                 WHERE r.student_id = :s AND r.state IN ('WAITING','READY') ORDER BY r.reserved_at
                """).param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> search(String q) {
        return jdbc.sql("""
                SELECT i.id, i.title, i.author, i.edition, i.year, i.kind, i.subject,
                       (SELECT count(*) FROM library.copy c WHERE c.item_id = i.id AND c.state <> 'WITHDRAWN' AND c.state <> 'LOST') AS copies,
                       (SELECT count(*) FROM library.copy c WHERE c.item_id = i.id AND c.state = 'AVAILABLE') AS available,
                       (SELECT count(*) FROM library.reservation r WHERE r.item_id = i.id AND r.state = 'WAITING') AS waiting
                  FROM library.item i
                 WHERE i.ended_on IS NULL AND (:q::text IS NULL OR i.title ILIKE '%' || :q || '%' OR i.author ILIKE '%' || :q || '%' OR i.subject ILIKE '%' || :q || '%' OR i.isbn = :q)
                 ORDER BY i.title LIMIT 50
                """).param("q", q, Types.VARCHAR).query().listOfRows();
    }

    UUID reserve(UUID item, UUID student) {
        return jdbc.sql("SELECT library.reserve(:i, :s)").param("i", item).param("s", student).query(UUID.class).single();
    }

    java.time.LocalDate renew(UUID loan) {
        return jdbc.sql("SELECT library.renew(:l)").param("l", loan).query(java.time.LocalDate.class).single();
    }

    String fineReference(UUID loan) {
        return jdbc.sql("SELECT library.fine_reference(:l)").param("l", loan).query(String.class).single();
    }

    Optional<UUID> loanOwner(UUID loan) {
        return jdbc.sql("SELECT student_id FROM library.loan WHERE id = :l").param("l", loan).query(UUID.class).optional();
    }

    /* ── the desk ── */

    Map<String, Object> tiles() {
        return jdbc.sql("""
                SELECT (SELECT count(*) FROM library.copy WHERE state NOT IN ('WITHDRAWN','LOST')) AS stock,
                       (SELECT count(*) FROM library.loan WHERE returned_at IS NULL) AS on_loan,
                       (SELECT count(*) FROM library.loan WHERE returned_at IS NULL AND due_on < current_date) AS overdue,
                       (SELECT coalesce(sum(fine), 0) FROM library.loan WHERE returned_at IS NOT NULL AND fine_settled_at IS NULL AND fine_waived_at IS NULL) AS fines_unpaid,
                       (SELECT count(*) FROM library.reservation WHERE state = 'WAITING') AS waiting
                """).query().singleRow();
    }

    List<Map<String, Object>> today() {
        return jdbc.sql(LOAN + " WHERE l.issued_at::date = current_date OR l.returned_at::date = current_date ORDER BY greatest(l.issued_at, coalesce(l.returned_at, l.issued_at)) DESC LIMIT 100")
                .query().listOfRows();
    }

    List<Map<String, Object>> overdue() {
        return jdbc.sql(LOAN + " WHERE l.returned_at IS NULL AND l.due_on < current_date ORDER BY l.due_on LIMIT 200").query().listOfRows();
    }

    List<Map<String, Object>> finesUnpaid() {
        return jdbc.sql(LOAN + " WHERE l.returned_at IS NOT NULL AND l.fine IS NOT NULL AND l.fine_settled_at IS NULL AND l.fine_waived_at IS NULL ORDER BY l.returned_at DESC LIMIT 200")
                .query().listOfRows();
    }

    Optional<Map<String, Object>> patron(String number) {
        return jdbc.sql("""
                SELECT st.id AS student_id, NULL::uuid AS person_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name, p.name AS programme
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE upper(st.matric_no) = upper(:n) OR upper(st.admission_no) = upper(:n)
                UNION ALL
                SELECT NULL::uuid, pe.id, pe.staff_number, pe.surname || ', ' || pe.given_names, 'Staff'
                  FROM iam.person pe WHERE upper(pe.staff_number) = upper(:n) AND pe.ended_on IS NULL
                LIMIT 1
                """).param("n", number).query().listOfRows().stream().findFirst();
    }

    UUID issue(String accession, UUID student, UUID person) {
        return jdbc.sql("SELECT library.issue(:a, :s, :p)").param("a", accession).param("s", student, Types.OTHER).param("p", person, Types.OTHER).query(UUID.class).single();
    }

    Map<String, Object> giveBack(String accession) {
        return jdbc.sql("SELECT * FROM library.give_back(:a)").param("a", accession).query().singleRow();
    }

    void waive(UUID loan, String why) {
        jdbc.sql("SELECT library.waive_fine(:l, :w)").param("l", loan).param("w", why).query().singleRow();
    }

    UUID putItem(UUID id, String title, String author, String edition, Integer year, String isbn, String subject, String kind) {
        UUID v = id == null ? UUID.randomUUID() : id;
        jdbc.sql("""
                INSERT INTO library.item (id, title, author, edition, year, isbn, subject, kind) VALUES (:id, :t, :a, :e, :y, :i, :s, :k)
                ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title, author = EXCLUDED.author, edition = EXCLUDED.edition, year = EXCLUDED.year,
                    isbn = EXCLUDED.isbn, subject = EXCLUDED.subject, kind = EXCLUDED.kind
                """).param("id", v).param("t", title).param("a", author, Types.VARCHAR).param("e", edition, Types.VARCHAR).param("y", year, Types.INTEGER)
                .param("i", isbn, Types.VARCHAR).param("s", subject, Types.VARCHAR).param("k", kind).update();
        return v;
    }

    void putCopy(String accession, UUID item, String location) {
        jdbc.sql("""
                INSERT INTO library.copy (accession, item_id, location) VALUES (:a, :i, :l)
                ON CONFLICT (accession) DO UPDATE SET item_id = EXCLUDED.item_id, location = EXCLUDED.location
                """).param("a", accession).param("i", item).param("l", location, Types.VARCHAR).update();
    }
}
