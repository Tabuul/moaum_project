package ng.edu.moaum.portal.wallet;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class WalletRepository {

    private final JdbcClient jdbc;

    WalletRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    String currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027");
    }

    /* ── the student ── */

    BigDecimal balance(UUID student) {
        return jdbc.sql("SELECT finance.wallet_balance(:s)").param("s", student).query(BigDecimal.class).single();
    }

    List<Map<String, Object>> statement(UUID student) {
        return jdbc.sql("SELECT * FROM finance.wallet_statement(:s)").param("s", student).query().listOfRows();
    }

    Map<String, Object> position(UUID student, String session) {
        return jdbc.sql("SELECT * FROM finance.position(:s, :n)").param("s", student).param("n", session).query().singleRow();
    }

    Optional<Map<String, Object>> status(UUID student) {
        return jdbc.sql("""
                SELECT n.session, n.number, n.state, n.reason, n.correctable, n.loaded_at FROM finance.nelfund_status n
                 WHERE n.student_id = :s ORDER BY n.loaded_at DESC LIMIT 1
                """).param("s", student).query().listOfRows().stream().findFirst();
    }

    String apply(UUID student, String session, BigDecimal amount) {
        return jdbc.sql("SELECT finance.apply_wallet(:s, :n, :a)").param("s", student).param("n", session).param("a", amount, Types.NUMERIC).query(String.class).single();
    }

    String topup(UUID student, String session, BigDecimal amount) {
        return jdbc.sql("SELECT finance.wallet_topup_reference(:s, :n, :a)").param("s", student).param("n", session).param("a", amount).query(String.class).single();
    }

    UUID creditWallet(UUID student, String session, BigDecimal amount, String reason, String source) {
        return jdbc.sql("SELECT finance.credit_wallet(:s, :n, :a, :r, :src)")
                .param("s", student).param("n", session).param("a", amount).param("r", reason)
                .param("src", source, Types.VARCHAR)
                .query(UUID.class).single();
    }

    /* ── sources of funding (a setting) ── */

    List<Map<String, Object>> sources() {
        return jdbc.sql("SELECT code, name, nature, sponsor, account, active, note, sort FROM finance.funding_source ORDER BY sort, name")
                .query().listOfRows();
    }

    Map<String, Object> upsertSource(String code, String name, String nature, String sponsor, String account,
                                     boolean active, String note, Integer sort) {
        return jdbc.sql("SELECT * FROM finance.upsert_funding_source(:c, :n, :na, :sp, :ac, :ok, :no, :so)")
                .param("c", code).param("n", name).param("na", nature).param("sp", sponsor, Types.VARCHAR)
                .param("ac", account, Types.VARCHAR).param("ok", active).param("no", note, Types.VARCHAR)
                .param("so", sort, Types.INTEGER).query().singleRow();
    }

    /* ── withdrawing the wallet to a bank account ── */

    Map<String, Object> eligibility(UUID student, String session) {
        return jdbc.sql("SELECT * FROM finance.withdrawal_eligibility(:s, :n)").param("s", student).param("n", session).query().singleRow();
    }

    Map<String, Object> requestWithdrawal(UUID student, String session, BigDecimal amount, String bank, String acctNo, String acctName) {
        return jdbc.sql("SELECT * FROM finance.request_withdrawal(:s, :n, :a, :b, :no, :nm)")
                .param("s", student).param("n", session).param("a", amount, Types.NUMERIC)
                .param("b", bank).param("no", acctNo).param("nm", acctName).query().singleRow();
    }

    Optional<Map<String, Object>> myWithdrawal(UUID student) {
        return jdbc.sql("""
                SELECT id, session, amount, bank_name, account_no, account_name, state, reason,
                       requested_at, decided_at, paid_at, paid_ref
                  FROM finance.wallet_withdrawal WHERE student_id = :s ORDER BY requested_at DESC LIMIT 1
                """).param("s", student).query().listOfRows().stream().findFirst();
    }

    List<Map<String, Object>> withdrawalQueue(String session) {
        return jdbc.sql("SELECT * FROM finance.withdrawal_queue(:n)").param("n", session, Types.VARCHAR).query().listOfRows();
    }

    void approveWithdrawal(UUID id) {
        jdbc.sql("SELECT finance.approve_withdrawal(:i)").param("i", id).query().singleRow();
    }

    void rejectWithdrawal(UUID id, String why) {
        jdbc.sql("SELECT finance.reject_withdrawal(:i, :w)").param("i", id).param("w", why).query().singleRow();
    }

    void payWithdrawal(UUID id, String ref) {
        jdbc.sql("SELECT finance.pay_withdrawal(:i, :r)").param("i", id).param("r", ref, Types.VARCHAR).query().singleRow();
    }

    /* ── the reports ── */

    List<Map<String, Object>> fundingSummary(String session) {
        return jdbc.sql("SELECT * FROM finance.funding_summary(:n)").param("n", session, Types.VARCHAR).query().listOfRows();
    }

    Map<String, Object> cashflow(String session) {
        return jdbc.sql("SELECT * FROM finance.wallet_cashflow(:n)").param("n", session, Types.VARCHAR).query().singleRow();
    }

    /* ── the Bursary ── */

    Map<String, Object> tiles(String session) {
        return jdbc.sql("""
                SELECT (SELECT coalesce(sum(amount), 0) FROM finance.nelfund_batch WHERE session = :n) AS received,
                       (SELECT count(*) FROM finance.nelfund_batch WHERE session = :n) AS batches,
                       (SELECT coalesce(sum(r.amount), 0) FROM finance.nelfund_row r JOIN finance.nelfund_batch b ON b.id = r.batch_id WHERE b.session = :n AND r.state = 'MATCHED') AS allocated,
                       (SELECT coalesce(sum(r.amount), 0) FROM finance.nelfund_row r JOIN finance.nelfund_batch b ON b.id = r.batch_id WHERE b.session = :n AND r.state = 'UNMATCHED') AS unallocated,
                       (SELECT count(*) FROM finance.nelfund_row r JOIN finance.nelfund_batch b ON b.id = r.batch_id WHERE b.session = :n AND r.state = 'UNMATCHED') AS unmatched_rows,
                       (SELECT coalesce(sum(r.amount), 0) FROM finance.nelfund_row r JOIN finance.nelfund_batch b ON b.id = r.batch_id WHERE b.session = :n AND r.state = 'REVERSED') AS reversed,
                       (SELECT count(DISTINCT r.student_id) FROM finance.nelfund_row r JOIN finance.nelfund_batch b ON b.id = r.batch_id WHERE b.session = :n AND r.state = 'MATCHED') AS students
                """).param("n", session).query().singleRow();
    }

    List<Map<String, Object>> batches(String session) {
        return jdbc.sql("""
                SELECT b.id, b.ref, b.received_on, b.amount, b.rows_read, b.note, b.loaded_at,
                       count(*) FILTER (WHERE r.state = 'MATCHED') AS matched,
                       count(*) FILTER (WHERE r.state = 'UNMATCHED') AS unmatched,
                       count(*) FILTER (WHERE r.state = 'REVERSED') AS reversed
                  FROM finance.nelfund_batch b LEFT JOIN finance.nelfund_row r ON r.batch_id = b.id
                 WHERE b.session = :n GROUP BY b.id ORDER BY b.received_on DESC, b.loaded_at DESC
                """).param("n", session).query().listOfRows();
    }

    List<Map<String, Object>> unmatched(String session) {
        return jdbc.sql("""
                SELECT r.id, r.matric_no, r.name_on_remit, r.amount, r.why, r.owner, b.ref AS batch_ref, b.received_on,
                       st.surname || ', ' || st.other_names AS student_name, st.status AS student_status
                  FROM finance.nelfund_row r JOIN finance.nelfund_batch b ON b.id = r.batch_id LEFT JOIN people.student st ON st.id = r.student_id
                 WHERE b.session = :n AND r.state = 'UNMATCHED' ORDER BY b.received_on, r.matric_no
                """).param("n", session).query().listOfRows();
    }

    Map<String, Object> load(String ref, String session, LocalDate received, String note, String rowsJson) {
        return jdbc.sql("SELECT * FROM finance.load_nelfund_batch(:r, :n, :d, :t, :j::jsonb)").param("r", ref).param("n", session)
                .param("d", received, Types.DATE).param("t", note, Types.VARCHAR).param("j", rowsJson).query().singleRow();
    }

    void match(UUID row, UUID student, String note) {
        jdbc.sql("SELECT finance.match_nelfund_row(:r, :s, :t)").param("r", row).param("s", student).param("t", note).query().singleRow();
    }

    void reverse(UUID row, String why) {
        jdbc.sql("SELECT finance.reverse_nelfund_row(:r, :w)").param("r", row).param("w", why).query().singleRow();
    }

    Optional<UUID> studentByNumber(String number) {
        return jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1")
                .param("n", number).query(UUID.class).optional();
    }

    /** who the ledger belongs to, for the Bursary's lookup */
    Map<String, Object> studentHeader(UUID student) {
        return jdbc.sql("""
                SELECT s.id, s.surname || ', ' || s.other_names AS name, s.matric_no, s.admission_no, s.status,
                       coalesce(s.matric_no, s.admission_no) AS number
                  FROM people.student s WHERE s.id = :s
                """).param("s", student).query().singleRow();
    }

    Map<String, Object> statusTiles(String session) {
        return jdbc.sql("""
                SELECT count(*) AS applied, count(*) FILTER (WHERE state = 'APPROVED') AS approved,
                       count(*) FILTER (WHERE state = 'NOT_APPROVED') AS not_approved, count(*) FILTER (WHERE state = 'PENDING') AS pending,
                       count(*) FILTER (WHERE state = 'NOT_APPROVED' AND correctable) AS correctable
                  FROM finance.nelfund_status WHERE session = :n
                """).param("n", session).query().singleRow();
    }

    List<Map<String, Object>> refusals(String session) {
        return jdbc.sql("""
                SELECT coalesce(reason, 'No reason given by the Fund') AS reason, count(*) AS students, bool_or(correctable) AS correctable
                  FROM finance.nelfund_status WHERE session = :n AND state = 'NOT_APPROVED' GROUP BY reason ORDER BY count(*) DESC
                """).param("n", session).query().listOfRows();
    }

    Map<String, Object> loadStatus(String session, String rowsJson) {
        return jdbc.sql("SELECT * FROM finance.load_nelfund_status(:n, :j::jsonb)").param("n", session).param("j", rowsJson).query().singleRow();
    }
}
