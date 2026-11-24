package ng.edu.moaum.portal.summer;

import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.OfficeScope;

/**
 * V779 — what the Summer Semester's three controllers share: who acts and who reads (the offices and their authority strings), the
 * unit a reader is held to (the Head of Department's department, the Dean's faculty, a College office's College: the server's, never
 * the request's), the words a CSV is built of, and a jsonb the database built, read as a map. Nothing here touches the database.
 */
final class SummerAccess {

    private SummerAccess() {
    }

    /** who sets the period, authorises a student, opens its examinations, tells the students and verifies a selection (the database
     *  checks the office again: SUMMER_OFFICE) */
    static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    /** who reads the Summer's students, courses and figures: the Academic Office and the Registry, the HOD (the department) and the
     *  Dean (the faculty), the Bursary, ICT and the Super Administrator */
    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_hod','OFFICE_dean',"
            + "'OFFICE_bursar','OFFICE_studentaccounts','OFFICE_ict','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    static final String SESSION = "^\\d{4}/\\d{4}$";

    /** the offices that read the Summer desk (the active office must be one of them: authority is checked against every office the
     *  token carries, so the active office decides the unit a reader is held to) */
    static final Set<String> READER_OFFICES = Set.of("academic", "registrar", "dregistrar", "hod", "dean", "bursar",
            "studentaccounts", "ict", "super", "vc", "dvc");

    /** the office the request acts in */
    static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    /**
     * V739, V779: the faculty, department and programme a read is held to. The active office must be one that reads the Summer desk
     * (else 403, as it was). The client's own faculty, department and programme are handed to {@link OfficeScope#bound}: an office's
     * own unit fills an absent value, a value outside it is refused by OfficeScope with its own SCOPE_* 422, a College office is held
     * to its College's faculties, an unbounded office passes what was asked. What comes back, never what was sent, reaches the SQL.
     */
    static OfficeScope.Bound readerBound(OfficeScope scope, String faculty, String dept, String programme) {
        String o = office();
        if (o == null || !READER_OFFICES.contains(o)) {
            throw new org.springframework.security.access.AccessDeniedException("The Summer desk is read in an office that reads it.");
        }
        return scope.bound(faculty, dept, programme);
    }

    static OfficeScope.Bound readerBound(OfficeScope scope) {
        return readerBound(scope, null, null, null);
    }

    /** whether a row of the desk is inside the unit a reader is held to */
    static boolean within(OfficeScope.Bound b, Object fac, Object dept, Object prog) {
        return (b.fac() == null || b.fac().equalsIgnoreCase(String.valueOf(fac)))
                && (b.dept() == null || b.dept().equalsIgnoreCase(String.valueOf(dept)))
                && (b.prog() == null || b.prog().equalsIgnoreCase(String.valueOf(prog)));
    }

    /**
     * The statements a desk's read makes itself (the facets and counts of the queue, one selection in full, the issues and figures of the
     * roster, the names of an export) run without JIT: CI's PostgreSQL 17 has it on, and on a database whose tables have never been
     * analysed (every CI run) the planner puts a join over the student register above jit_above_cost, so every call would compile its
     * statement for seconds (V652, V663, V782). The functions V779 calls carry jit = off themselves; this is for the rest. SET LOCAL
     * lasts to the end of the transaction and is allowed in a read-only one.
     */
    static void noJit(org.springframework.jdbc.core.simple.JdbcClient jdbc) {
        jdbc.sql("SET LOCAL jit = off").update();
    }

    /** a request's text parameter, null when absent or blank */
    static String nz(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /** a request's code word (a state, a basis, a payment status): null when absent or blank, else in upper case as the database writes it */
    static String up(String s) {
        String v = nz(s);
        return v == null ? null : v.toUpperCase(java.util.Locale.ROOT);
    }

    /** a page number, never below 0 */
    static int page(Integer page) {
        return page == null ? 0 : Math.max(0, page);
    }

    /** a page size: the default when absent, 1 to the ceiling */
    static int size(Integer size, int dflt, int max) {
        return size == null ? dflt : Math.max(1, Math.min(size, max));
    }

    static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** a jsonb the database built, as a map the response carries */
    static Map<String, Object> json(String text) {
        return JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** a map's keys written as a person's JSON writes them: students_selected as studentsSelected */
    static Map<String, Object> camel(Map<String, Object> row) {
        Map<String, Object> out = new LinkedHashMap<>();
        row.forEach((k, v) -> out.put(camel(k), v));
        return out;
    }

    static String camel(String snake) {
        StringBuilder b = new StringBuilder();
        boolean up = false;
        for (char c : snake.toCharArray()) {
            if (c == '_') {
                up = true;
            } else {
                b.append(up ? Character.toUpperCase(c) : c);
                up = false;
            }
        }
        return b.toString();
    }

    /** the session as a file name carries it: 2025/2026 written 2025-2026 */
    static String fileSession(String session) {
        return session.replace('/', '-');
    }

    /** how a selection was confirmed, in the words the desk's screen and the student read (the spec's 5.1 viaWord, lib/summer.ts
     *  VIA_WORD): the selections CSV's "Verified by" says what the screen says, never an office code */
    static String verifiedByWord(String via) {
        if (via == null) return "";
        return switch (via) {
            case "RESULTS" -> "Confirmed by your results";
            case "AUTHORISATION" -> "Named by the Academic Office";
            case "OFFICER" -> "Confirmed by the Academic Office";
            default -> via;
        };
    }

    /** what became of the money of a selected course, for the selections CSV's "Payment": the live charge (PAID, and whether its entry
     *  stands, or DUE), or — for a paid course the Academic Office then found not outstanding or rejected, whose charge
     *  registration.summer_verify cancels and whose fee it holds as a DECISION credit for the Bursar — the state of that credit
     *  (creditState, the queue row's credit_state); a course never paid is "Not paid" */
    static String paymentWord(String chargeState, boolean entryLive, String creditState) {
        if ("PAID".equals(chargeState)) return entryLive ? "Paid" : "Paid, not registered";
        if ("DUE".equals(chargeState)) return "Unpaid";
        if (creditState != null) {
            return switch (creditState) {
                case "OPEN" -> "Paid, held as Summer credit";
                case "APPLIED" -> "Paid, Summer credit applied";
                case "REFUNDED" -> "Paid, Summer credit refunded";
                default -> "Paid";
            };
        }
        return "Not paid";
    }

    /**
     * A CSV the server builds (V779): UTF-8 with the byte order mark, CRLF lines, a cell quoted when it must be, and a text cell
     * that begins with =, +, - or @ prefixed with an apostrophe so a spreadsheet never runs it as a formula. A number is a number
     * and is left as it is. Kept in memory: the three exports are bounded by their row limit.
     */
    static final class Csv {
        private final StringBuilder out = new StringBuilder("﻿");
        private int rows;

        Csv(String... header) {
            line(header);
        }

        void row(Object... cells) {
            line(cells);
            rows++;
        }

        /** the rows written, the header not counted */
        int rows() {
            return rows;
        }

        byte[] bytes() {
            return out.toString().getBytes(StandardCharsets.UTF_8);
        }

        private void line(Object... cells) {
            for (int i = 0; i < cells.length; i++) {
                if (i > 0) out.append(',');
                out.append(cell(cells[i]));
            }
            out.append("\r\n");
        }

        static String cell(Object v) {
            if (v == null) return "";
            String s = String.valueOf(v);
            if (!(v instanceof Number) && !s.isEmpty() && "=+-@".indexOf(s.charAt(0)) >= 0) {
                s = "'" + s;
            }
            boolean quote = s.indexOf(',') >= 0 || s.indexOf('"') >= 0 || s.indexOf('\r') >= 0 || s.indexOf('\n') >= 0;
            return quote ? "\"" + s.replace("\"", "\"\"") + "\"" : s;
        }
    }
}
