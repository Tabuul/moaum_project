package ng.edu.moaum.portal.dbops;

import java.sql.Types;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import tools.jackson.databind.ObjectMapper;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * V640: what the Database Operations screens share — who reads what (the portal's permissions are each endpoint's offices), the
 * scope a request is held to and its words, and the query log, written in a transaction of its own so a read stays read-only.
 */
@Component
class Operations {

    /** examination readiness: the Database Operations office, ICT, the Academic Office, the Registry, Records, the examinations
     *  officers, the faculties and departments (their own), the Bursary, the Vice-Chancellor's offices */
    static final String READINESS_READERS = "hasAnyAuthority('OFFICE_dbops','OFFICE_ict','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_bursar',"
            + "'OFFICE_studentaccounts','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";
    /** the query engine and data quality: the Database Operations office, ICT, the Registry, the Academic Office, Records */
    static final String QUERY_READERS = "hasAnyAuthority('OFFICE_dbops','OFFICE_ict','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic',"
            + "'OFFICE_records','OFFICE_admin','OFFICE_super')";
    /** saved and shared reports: whoever reads either */
    static final String SAVED_READERS = "hasAnyAuthority('OFFICE_dbops','OFFICE_ict','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_bursar',"
            + "'OFFICE_studentaccounts','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";
    static final String OPERATOR = "hasAnyAuthority('OFFICE_dbops','OFFICE_admin','OFFICE_super')";

    /** the offices that read amounts on these lists — the student record's fee readers (V360) and the Database Operations office;
     *  an examinations officer reads the readiness without the amounts */
    static final Set<String> AMOUNTS = Set.of("dbops", "ict", "academic", "registrar", "dregistrar", "records", "dean", "facultyofficer", "hod",
            "bursar", "studentaccounts", "vc", "dvc", "admin", "super", "provost", "audit");
    /** the offices that read everyone's query log and the whole register of official reports */
    static final Set<String> AUDITORS = Set.of("dbops", "ict", "admin", "super", "audit");

    private static final ObjectMapper JSON = new ObjectMapper();

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final TransactionTemplate own;

    Operations(JdbcClient jdbc, OfficeScope scope, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.own = new TransactionTemplate(transactions);
        this.own.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    }

    static String office() {
        return AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
    }

    static boolean amounts() {
        return AMOUNTS.contains(office());
    }

    static String json(Object o) {
        return o == null ? null : JSON.writeValueAsString(o);
    }

    /** the faculty, department and programme a request is held to, from the server's own record of the office */
    OfficeScope.Bound bound(String fac, String dept, String prog) {
        return scope.bound(fac, dept, prog);
    }

    /** the scope in words, for a report's heading and the log */
    String words(OfficeScope.Bound b) {
        if (b.prog() != null) {
            return jdbc.sql("SELECT name FROM ref.programme WHERE code = :p").param("p", b.prog()).query(String.class).optional()
                    .map(n -> "Programme: " + n).orElse("Programme " + b.prog());
        }
        if (b.dept() != null) {
            return jdbc.sql("SELECT name FROM ref.department WHERE code = :d").param("d", b.dept()).query(String.class).optional()
                    .map(n -> "Department of " + n).orElse("Department " + b.dept());
        }
        if (b.fac() != null) {
            return jdbc.sql("SELECT name FROM ref.faculty WHERE code = :f").param("f", b.fac()).query(String.class).optional()
                    .map(n -> "Faculty of " + n).orElse("Faculty " + b.fac());
        }
        return "The University";
    }

    /** a line of the query log, in a transaction of its own: the person, the office, what was done, to what, with which filters */
    void log(String action, String source, String title, Map<String, Object> definition, String scopeWords, Integer rows, String reference,
             String format, UUID savedId) {
        AuditContext ctx = AuditContextHolder.required();
        own.executeWithoutResult(st -> jdbc.sql("""
                INSERT INTO reporting.query_log (actor_id, actor_office, action, source, title, definition, scope, row_count, reference, format, saved_query_id)
                VALUES (:a, :o, :act, :src, :t, CAST(:def AS jsonb), :sc, :n, :ref, :fmt, :sq)
                """).param("a", ctx.actorId()).param("o", ctx.actorOffice()).param("act", action).param("src", source)
                .param("t", title, Types.VARCHAR).param("def", json(definition), Types.VARCHAR).param("sc", scopeWords, Types.VARCHAR)
                .param("n", rows, Types.INTEGER).param("ref", reference, Types.VARCHAR).param("fmt", format, Types.VARCHAR)
                .param("sq", savedId, Types.OTHER).update());
    }
}
