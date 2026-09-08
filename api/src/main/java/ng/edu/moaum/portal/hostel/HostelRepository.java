package ng.edu.moaum.portal.hostel;

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
class HostelRepository {

    private final JdbcClient jdbc;

    HostelRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    String currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse(null);
    }

    /* ── the student's side ── */

    Optional<Map<String, Object>> studentView(UUID student, String session) {
        return jdbc.sql("SELECT * FROM hostel.student_view(:s, :n)").param("s", student).param("n", session).query().listOfRows().stream().findFirst();
    }

    List<Map<String, Object>> history(UUID student) {
        return jdbc.sql("""
                SELECT ap.session, ap.state, h.name AS hall_name, r.block, r.room_no, al.bed, al.basis, al.confirmed_at, al.lapsed_at, ap.applied_at
                  FROM hostel.application ap
                  LEFT JOIN LATERAL (SELECT * FROM hostel.allocation x WHERE x.application_id = ap.id ORDER BY (x.confirmed_at IS NOT NULL) DESC, x.allocated_at DESC LIMIT 1) al ON true
                  LEFT JOIN hostel.room r ON r.id = al.room_id
                  LEFT JOIN hostel.hall h ON h.code = r.hall_code
                 WHERE ap.student_id = :s ORDER BY ap.session DESC
                """).param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> halls() {
        return jdbc.sql("""
                SELECT h.code, h.name, h.sex,
                       (SELECT coalesce(sum(r.beds), 0) FROM hostel.room r WHERE r.hall_code = h.code AND NOT r.out_of_service) AS beds,
                       (SELECT count(*) FROM hostel.room r WHERE r.hall_code = h.code) AS rooms,
                       (SELECT coalesce(sum(r.beds), 0) FROM hostel.room r WHERE r.hall_code = h.code AND r.out_of_service) AS out_of_service
                  FROM hostel.hall h WHERE h.ended_on IS NULL ORDER BY h.name
                """).query().listOfRows();
    }

    UUID apply(UUID student, String session, String hall, String category, String note) {
        return jdbc.sql("SELECT hostel.apply(:s, :n, :h, :c, :t)").param("s", student).param("n", session)
                .param("h", hall, Types.VARCHAR).param("c", category, Types.VARCHAR).param("t", note, Types.VARCHAR).query(UUID.class).single();
    }

    String feeReference(UUID application) {
        return jdbc.sql("SELECT hostel.new_fee_reference(:a)").param("a", application).query(String.class).single();
    }

    Optional<UUID> roomOf(UUID student, String session) {
        return jdbc.sql("""
                SELECT al.room_id FROM hostel.allocation al JOIN hostel.application ap ON ap.id = al.application_id
                 WHERE ap.student_id = :s AND ap.session = :n AND al.confirmed_at IS NOT NULL AND al.ended_at IS NULL
                 ORDER BY al.confirmed_at DESC LIMIT 1
                """).param("s", student).param("n", session).query(UUID.class).optional();
    }

    List<Map<String, Object>> maintenanceOfRoom(UUID room) {
        return jdbc.sql("""
                SELECT m.id, m.issue, m.raised_at, m.state, m.note, m.decided_at, st.surname || ', ' || st.other_names AS raised_by_name
                  FROM hostel.maintenance_request m JOIN people.student st ON st.id = m.raised_by
                 WHERE m.room_id = :r ORDER BY m.raised_at DESC
                """).param("r", room).query().listOfRows();
    }

    UUID raise(UUID room, UUID student, String issue) {
        UUID id = UUID.randomUUID();
        jdbc.sql("INSERT INTO hostel.maintenance_request (id, room_id, raised_by, issue) VALUES (:id, :r, :s, :i)")
                .param("id", id).param("r", room).param("s", student).param("i", issue).update();
        return id;
    }

    /* ── the office ── */

    Optional<Map<String, Object>> setting(String session) {
        return jdbc.sql("SELECT session, fee, hold_hours, applications_close, seed, drawn_at, drawn_by FROM hostel.session_setting WHERE session = :s")
                .param("s", session).query().listOfRows().stream().findFirst();
    }

    void putSetting(String session, BigDecimal fee, int holdHours, LocalDate close) {
        jdbc.sql("""
                INSERT INTO hostel.session_setting (session, fee, hold_hours, applications_close) VALUES (:s, :f, :h, :c)
                ON CONFLICT (session) DO UPDATE SET fee = EXCLUDED.fee, hold_hours = EXCLUDED.hold_hours, applications_close = EXCLUDED.applications_close
                """).param("s", session).param("f", fee).param("h", holdHours).param("c", close, Types.DATE).update();
    }

    void putHall(String code, String name, String sex) {
        jdbc.sql("""
                INSERT INTO hostel.hall (code, name, sex) VALUES (:c, :n, :x)
                ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, sex = EXCLUDED.sex, ended_on = NULL
                """).param("c", code).param("n", name).param("x", sex, Types.VARCHAR).update();
    }

    void putRoom(String hall, String block, String roomNo, int beds, boolean out, String note) {
        jdbc.sql("""
                INSERT INTO hostel.room (hall_code, block, room_no, beds, out_of_service, note) VALUES (:h, :b, :r, :n, :o, :t)
                ON CONFLICT (hall_code, block, room_no) DO UPDATE SET beds = EXCLUDED.beds, out_of_service = EXCLUDED.out_of_service, note = EXCLUDED.note
                """).param("h", hall).param("b", block).param("r", roomNo).param("n", beds).param("o", out).param("t", note, Types.VARCHAR).update();
    }

    Map<String, Object> counts(String session) {
        return jdbc.sql("""
                SELECT (SELECT coalesce(sum(r.beds), 0) FROM hostel.room r JOIN hostel.hall h ON h.code = r.hall_code WHERE NOT r.out_of_service AND h.ended_on IS NULL) AS beds,
                       (SELECT coalesce(sum(r.beds), 0) FROM hostel.room r WHERE r.out_of_service) AS out_of_service,
                       (SELECT count(*) FROM hostel.application ap WHERE ap.session = :s AND ap.state <> 'WITHDRAWN') AS applications,
                       (SELECT count(*) FROM hostel.application ap WHERE ap.session = :s AND ap.category <> 'NONE' AND ap.state <> 'WITHDRAWN') AS priority,
                       (SELECT count(*) FROM hostel.application ap WHERE ap.session = :s AND ap.state = 'ALLOCATED') AS allocated,
                       (SELECT count(*) FROM hostel.application ap WHERE ap.session = :s AND ap.state = 'CONFIRMED') AS confirmed,
                       (SELECT count(*) FROM hostel.application ap WHERE ap.session = :s AND ap.state = 'UNSUCCESSFUL') AS reserves,
                       (SELECT count(*) FROM hostel.application ap WHERE ap.session = :s AND ap.state = 'LAPSED') AS lapsed,
                       (SELECT count(*) FROM hostel.free_beds(:s)) AS free
                """).param("s", session).query().singleRow();
    }

    List<Map<String, Object>> draw(String session) {
        return jdbc.sql("""
                SELECT ap.draw_position, ap.state, ap.category, coalesce(st.matric_no, st.admission_no) AS number,
                       st.surname || ', ' || st.other_names AS name, hp.name AS hall_requested,
                       h.name AS hall_name, r.block, r.room_no, al.bed, al.basis, al.held_until, al.confirmed_at, al.lapsed_at
                  FROM hostel.application ap
                  JOIN people.student st ON st.id = ap.student_id
                  LEFT JOIN hostel.hall hp ON hp.code = ap.hall_code
                  LEFT JOIN LATERAL (SELECT * FROM hostel.allocation x WHERE x.application_id = ap.id AND x.ended_at IS NULL
                                      ORDER BY (x.lapsed_at IS NULL) DESC, x.allocated_at DESC LIMIT 1) al ON true
                  LEFT JOIN hostel.room r ON r.id = al.room_id
                  LEFT JOIN hostel.hall h ON h.code = r.hall_code
                 WHERE ap.session = :s AND ap.state <> 'WITHDRAWN'
                 ORDER BY ap.draw_position NULLS LAST, ap.applied_at
                """).param("s", session).query().listOfRows();
    }

    Map<String, Object> runDraw(String session, String seed) {
        return jdbc.sql("SELECT * FROM hostel.draw(:s, :d)").param("s", session).param("d", seed).query().singleRow();
    }

    int lapse(String session) {
        return jdbc.sql("SELECT hostel.lapse_holds(:s)").param("s", session).query(Integer.class).single();
    }

    List<Map<String, Object>> maintenance() {
        return jdbc.sql("""
                SELECT m.id, m.issue, m.raised_at, m.state, m.note, m.decided_at, h.name AS hall_name, r.block, r.room_no,
                       st.surname || ', ' || st.other_names AS raised_by_name, coalesce(st.matric_no, st.admission_no) AS number
                  FROM hostel.maintenance_request m JOIN hostel.room r ON r.id = m.room_id JOIN hostel.hall h ON h.code = r.hall_code
                  JOIN people.student st ON st.id = m.raised_by
                 ORDER BY (m.state IN ('FIXED','CLOSED')), m.raised_at DESC LIMIT 200
                """).query().listOfRows();
    }

    int decideMaintenance(UUID id, String state, String note) {
        return jdbc.sql("UPDATE hostel.maintenance_request SET state = :st, note = :n, decided_at = now() WHERE id = :id")
                .param("st", state).param("n", note, Types.VARCHAR).param("id", id).update();
    }
}
