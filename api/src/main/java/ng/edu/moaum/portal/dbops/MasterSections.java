package ng.edu.moaum.portal.dbops;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Function;

import ng.edu.moaum.portal.shared.XlsxStream.Col;
import ng.edu.moaum.portal.shared.XlsxStream.Kind;

/**
 * V650: the Master University Report's sections, defined once — each a title, its columns (with how each is written: text, a
 * whole number, naira, a date, a moment) and its rows. The dashboard's tables, the PDF's tables and the Excel's sheets are all
 * these, so a figure cannot read one way on paper and another in the workbook. The summary sections are drawn from
 * reporting.master_summary's rows; the lists (students, transactions, GST and EPS courses) are columns over the rows the database
 * streams. The money a reader may not read is left out of the columns, not blanked.
 */
final class MasterSections {

    private MasterSections() {
    }

    record Section(String key, String title, List<Col> cols, List<Object[]> rows, String note) {
        Map<String, Object> json() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", key);
            m.put("title", title);
            m.put("headers", cols.stream().map(Col::header).toList());
            m.put("kinds", cols.stream().map(c -> c.kind().name()).toList());
            m.put("rows", rows);
            m.put("note", note);
            return m;
        }
    }

    /** a list's column: its header, how it is written, and the value from a row the database returned */
    record Column(Col col, Function<Map<String, Object>, Object> value) {
    }

    record Detail(String key, String title, List<Column> columns, String note) {
        List<Col> cols() {
            return columns.stream().map(Column::col).toList();
        }

        Object[] row(Map<String, Object> r) {
            Object[] out = new Object[columns.size()];
            for (int i = 0; i < out.length; i++) out[i] = columns.get(i).value().apply(r);
            return out;
        }
    }

    static long n(Object o) {
        return o == null ? 0 : ((Number) o).longValue();
    }

    static String s(Object o) {
        return o == null ? "" : String.valueOf(o);
    }

    static List<Map<String, Object>> dim(List<Map<String, Object>> rows, String d) {
        return rows.stream().filter(r -> d.equals(r.get("dim"))).toList();
    }

    static Map<String, Object> all(List<Map<String, Object>> rows) {
        return rows.stream().filter(r -> "ALL".equals(r.get("dim"))).findFirst().orElse(Map.of());
    }

    static String sex(Object v) {
        String u = s(v).toUpperCase();
        return "M".equals(u) || "MALE".equals(u) ? "Male" : "F".equals(u) || "FEMALE".equals(u) ? "Female" : "Not stated";
    }

    static String sem(Object v) {
        long n = v == null ? 0 : n(v);
        return n == 1 ? "First semester" : n == 2 ? "Second semester" : n == 3 ? "Third semester" : "";
    }

    static final Map<String, String> FEE = Map.of("FULLY_PAID", "Paid in full", "PART_PAYMENT", "Partially paid", "NOT_PAID", "Not paid", "NO_CHARGE", "No fee stated");
    static final Map<String, String> GSTW = Map.of("PAID", "Paid", "PART_PAID", "Part paid", "NOT_PAID", "Not paid", "NOT_APPLICABLE", "Not owed");
    static final Map<String, String> PST = Map.of("SUCCESSFUL", "Successful", "PENDING", "Pending", "FAILED", "Failed (expired unpaid)", "REVERSED", "Reversed", "REFUNDED", "Refunded");

    private static Col t(String h, int w) { return Col.text(h, w); }
    private static Col i(String h) { return Col.num(h); }
    private static Col m(String h) { return Col.money(h); }

    /** the student counts every summary table carries */
    private static final List<Map.Entry<String, String>> COUNTS = List.of(
            Map.entry("Total", "total"), Map.entry("Male", "male"), Map.entry("Female", "female"), Map.entry("Fees paid", "fees_paid"),
            Map.entry("Part paid", "fees_part"), Map.entry("Not paid", "fees_not_paid"), Map.entry("Paid not registered", "paid_not_registered"),
            Map.entry("Registered", "registered"), Map.entry("GST paid", "gst_paid"), Map.entry("GST not paid", "gst_not_paid"), Map.entry("EPS paid", "eps_paid"),
            Map.entry("EPS not paid", "eps_not_paid"), Map.entry("Cards issued", "card_issued"), Map.entry("Permits printed", "permit_printed"));

    private static List<Col> withCounts(List<Col> lead) {
        List<Col> c = new ArrayList<>(lead);
        for (Map.Entry<String, String> e : COUNTS) c.add(i(e.getKey()));
        return c;
    }

    private static Object[] withCounts(Map<String, Object> r, Object... lead) {
        Object[] out = new Object[lead.length + COUNTS.size()];
        System.arraycopy(lead, 0, out, 0, lead.length);
        for (int k = 0; k < COUNTS.size(); k++) out[lead.length + k] = n(r.get(COUNTS.get(k).getValue()));
        return out;
    }

    private static Comparator<Map<String, Object>> by(String... keys) {
        Comparator<Map<String, Object>> c = Comparator.comparing(r -> s(r.get(keys[0])));
        for (int k = 1; k < keys.length; k++) {
            String key = keys[k];
            c = c.thenComparing(r -> s(r.get(key)));
        }
        return c;
    }

    /** the summary sections, in the report's order, from master_summary's rows, the transactions' figures and the semesters */
    @SuppressWarnings("unchecked")
    static List<Section> summary(List<Map<String, Object>> rows, Map<String, Object> tx, List<Map<String, Object>> semesters,
                                 List<Map<String, Object>> quality, List<Map<String, Object>> reconciliation, String money) {
        List<Section> out = new ArrayList<>();
        boolean all = "ALL".equals(money);
        boolean gstMoney = !"NONE".equals(money);
        Map<String, Object> a = all(rows);
        List<Map<String, Object>> faculties = dim(rows, "FACULTY").stream().sorted(by("faculty")).toList();

        // the executive summary and the University's structure
        List<Object[]> ex = new ArrayList<>();
        ex.add(new Object[] {"Total students", n(a.get("total"))});
        ex.add(new Object[] {"Faculties", (long) faculties.size()});
        ex.add(new Object[] {"Departments", (long) dim(rows, "DEPARTMENT").size()});
        ex.add(new Object[] {"Programmes", (long) dim(rows, "PROGRAMME").size()});
        ex.add(new Object[] {"Male students", n(a.get("male"))});
        ex.add(new Object[] {"Female students", n(a.get("female"))});
        if (n(a.get("sex_unknown")) > 0) ex.add(new Object[] {"Gender not stated", n(a.get("sex_unknown"))});
        for (String[] k : new String[][] {{"School fees paid in full", "fees_paid"}, {"School fees partially paid", "fees_part"}, {"School fees not paid", "fees_not_paid"},
                {"No school fee stated", "no_fee"}, {"Paid but not registered", "paid_not_registered"}, {"Registered", "registered"}, {"GST paid", "gst_paid"},
                {"GST not paid", "gst_not_paid"}, {"EPS paid", "eps_paid"}, {"EPS not paid", "eps_not_paid"}, {"Examination cards eligible", "card_eligible"},
                {"Examination cards issued", "card_issued"}, {"GST permits generated", "permit_generated"}, {"GST permits printed", "permit_printed"}}) {
            ex.add(new Object[] {k[0], n(a.get(k[1]))});
        }
        List<Object[]> exMoney = new ArrayList<>();
        if (all) {
            exMoney.add(new Object[] {"School fees obligation", a.get("payable")});
            exMoney.add(new Object[] {"School fees paid by these students", a.get("paid_amount")});
            exMoney.add(new Object[] {"School fees outstanding", a.get("outstanding")});
        }
        if (gstMoney) {
            exMoney.add(new Object[] {"GST paid by these students", a.get("gst_paid_amount")});
            exMoney.add(new Object[] {"GST outstanding", a.get("gst_outstanding")});
        }
        if (tx != null && tx.get("total") instanceof Map<?, ?> tt) {
            ex.add(new Object[] {"Transactions in the period", n(tt.get("transactions"))});
            ex.add(new Object[] {"Unique students paying", n(tt.get("students"))});
            exMoney.add(new Object[] {"Revenue in the period", tt.get("revenue")});
            for (String[] p : new String[][] {{"SCHOOL_FEES", "School fees revenue in the period"}, {"GST_FEE", "GST revenue in the period"}, {"EPS_FEE", "EPS revenue in the period"}}) {
                Object rev = ((List<Map<String, Object>>) tx.getOrDefault("byPurpose", List.of())).stream().filter(x -> p[0].equals(x.get("code")))
                        .map(x -> x.get("revenue")).findFirst().orElse(0);
                exMoney.add(new Object[] {p[1], rev});
            }
        }
        out.add(new Section("executive", "Executive summary", List.of(t("Measure", 40), i("Students / count")), ex, null));
        if (!exMoney.isEmpty()) out.add(new Section("executive_money", "Executive summary — naira", List.of(t("Measure", 40), m("Amount (₦)")), exMoney,
                "Students and naira are separate measures; revenue is successful payments only, net of refunds paid."));

        out.add(new Section("faculty", "Faculty summary", withCounts(List.of(t("Faculty", 34), i("Departments"), i("Programmes"))),
                faculties.stream().map(r -> withCounts(r, s(r.get("faculty")), n(r.get("departments")), n(r.get("programmes")))).toList(), null));
        out.add(new Section("department", "Department summary", withCounts(List.of(t("Faculty", 30), t("Department", 32), i("Programmes"))),
                dim(rows, "DEPARTMENT").stream().sorted(by("faculty", "department")).map(r -> withCounts(r, s(r.get("faculty")), s(r.get("department")), n(r.get("programmes")))).toList(), null));
        List<Col> pc = withCounts(List.of(t("Faculty", 26), t("Department", 28), t("Programme", 34)));
        pc.add(i("GST registered"));
        pc.add(i("EPS registered"));
        out.add(new Section("programme", "Programme summary", pc,
                dim(rows, "PROGRAMME").stream().sorted(by("faculty", "department", "programme")).map(r -> {
                    Object[] base = withCounts(r, s(r.get("faculty")), s(r.get("department")), s(r.get("programme")));
                    Object[] o = java.util.Arrays.copyOf(base, base.length + 2);
                    o[base.length] = n(r.get("gst_registered"));
                    o[base.length + 1] = n(r.get("eps_registered"));
                    return o;
                }).toList(), null));
        out.add(new Section("programme_level", "Programme summary by level", withCounts(List.of(t("Faculty", 26), t("Department", 28), t("Programme", 34), i("Level"))),
                dim(rows, "PROGRAMME_LEVEL").stream().sorted(by("faculty", "department", "programme").thenComparing(r -> n(r.get("level"))))
                        .map(r -> withCounts(r, s(r.get("faculty")), s(r.get("department")), s(r.get("programme")), r.get("level"))).toList(), null));
        out.add(new Section("level", "Level summary", withCounts(List.of(t("Level", 12))),
                dim(rows, "LEVEL").stream().sorted(Comparator.comparing(r -> r.get("level") == null ? 9999L : n(r.get("level"))))
                        .map(r -> withCounts(r, r.get("level") == null ? "Not stated" : r.get("level") + " Level")).toList(), null));
        out.add(new Section("programme_type", "Programme type summary", withCounts(List.of(t("Programme type", 24))),
                dim(rows, "PROGRAMME_TYPE").stream().sorted(by("programme_type")).map(r -> withCounts(r, r.get("programme_type") == null ? "Not stated" : s(r.get("programme_type")))).toList(), null));

        List<Col> gc = List.of(t("Gender", 12), i("Total"), i("Fees paid"), i("Part paid"), i("Not paid"), i("Paid not registered"), i("Registered"), i("GST paid"),
                i("GST not paid"), i("EPS paid"), i("EPS not paid"));
        Function<Map<String, Object>, Object[]> gl = r -> new Object[] {sex(r.get("sex")), n(r.get("total")), n(r.get("fees_paid")), n(r.get("fees_part")), n(r.get("fees_not_paid")),
                n(r.get("paid_not_registered")), n(r.get("registered")), n(r.get("gst_paid")), n(r.get("gst_not_paid")), n(r.get("eps_paid")), n(r.get("eps_not_paid"))};
        out.add(new Section("gender", "Gender statistics", gc, dim(rows, "GENDER").stream().sorted(Comparator.comparing(r -> sex(r.get("sex")))).map(gl).toList(), null));
        List<Col> gfc = new ArrayList<>(List.of(t("Faculty", 30)));
        gfc.addAll(gc);
        out.add(new Section("faculty_gender", "Gender by faculty", gfc, dim(rows, "FACULTY_GENDER").stream().sorted(by("faculty").thenComparing(r -> sex(r.get("sex")))).map(r -> {
            Object[] g = gl.apply(r);
            Object[] o = new Object[g.length + 1];
            o[0] = s(r.get("faculty"));
            System.arraycopy(g, 0, o, 1, g.length);
            return o;
        }).toList(), null));

        // school fees
        long total = n(a.get("total"));
        List<Object[]> fs = new ArrayList<>();
        for (String[] k : new String[][] {{"Total students", "total"}, {"Paid in full", "fees_paid"}, {"Partially paid", "fees_part"}, {"Not paid", "fees_not_paid"},
                {"No fee stated", "no_fee"}, {"Any school-fees payment", "any_payment"}, {"Paid but not registered", "paid_not_registered"}, {"Registered", "registered"},
                {"Registered, school fees not paid", "registered_not_paid"}}) {
            long v = n(a.get(k[1]));
            fs.add(new Object[] {k[0], v, total > 0 ? Math.round(v * 1000.0 / total) / 10.0 : 0.0});
        }
        out.add(new Section("fees", "School fees statistics", List.of(t("Measure", 36), i("Students"), new Col("% of students", Kind.MONEY, 14)), fs,
                "Counts are students; the naira are in the executive summary and the faculty table."));
        List<Col> ffc = new ArrayList<>(List.of(t("Faculty", 34), i("Students"), i("Paid in full"), i("Part paid"), i("Not paid"), i("No fee stated"), i("Paid not registered")));
        if (all) ffc.addAll(List.of(m("Obligation (₦)"), m("Paid (₦)"), m("Outstanding (₦)")));
        out.add(new Section("fees_faculty", "School fees by faculty", ffc, faculties.stream().map(r -> {
            List<Object> o = new ArrayList<>(List.of(s(r.get("faculty")), n(r.get("total")), n(r.get("fees_paid")), n(r.get("fees_part")), n(r.get("fees_not_paid")),
                    n(r.get("no_fee")), n(r.get("paid_not_registered"))));
            if (all) {
                o.add(r.get("payable"));
                o.add(r.get("paid_amount"));
                o.add(r.get("outstanding"));
            }
            return o.toArray();
        }).toList(), null));

        // transactions
        if (tx != null) {
            out.add(new Section("tx_status", "Financial summary by payment status", List.of(t("Status", 24), i("Transactions"), i("Unique students"), m("Amount (₦)"), m("Revenue (₦)")),
                    ((List<Map<String, Object>>) tx.getOrDefault("byStatus", List.of())).stream().map(x -> new Object[] {PST.getOrDefault(s(x.get("status")), s(x.get("status"))),
                            n(x.get("transactions")), n(x.get("students")), x.get("amount"), x.get("net")}).toList(),
                    "Only successful payments, net of refunds paid, are revenue; pending, failed, reversed and refunded payments are not."));
            out.add(new Section("tx_purpose", "Payment purpose summary", List.of(t("Payment purpose", 30), i("Transactions"), i("Unique students"), i("Successful"), i("Pending"),
                    i("Failed"), i("Reversed"), i("Refunded"), m("Revenue (₦)")),
                    ((List<Map<String, Object>>) tx.getOrDefault("byPurpose", List.of())).stream().map(x -> new Object[] {s(x.get("label")), n(x.get("transactions")),
                            n(x.get("students")), n(x.get("successful")), n(x.get("pending")), n(x.get("failed")), n(x.get("reversed")), n(x.get("refunded")), x.get("revenue")}).toList(), null));
            out.add(new Section("tx_faculty", "Revenue by faculty", List.of(t("Faculty", 34), m("School fees (₦)"), m("All purposes (₦)")),
                    ((List<Map<String, Object>>) tx.getOrDefault("byFaculty", List.of())).stream().map(x -> new Object[] {x.get("faculty") == null ? "Applicants and others" : s(x.get("faculty")),
                            x.get("school_fees"), x.get("revenue")}).toList(), null));
        }

        // GST and EPS
        List<Col> gstc = new ArrayList<>(List.of(t("Faculty", 34), i("GST students"), i("Registered"), i("Not registered"), i("Paid"), i("Not paid")));
        if (gstMoney) gstc.addAll(List.of(m("Paid by them (₦)"), m("Outstanding (₦)")));
        Function<Map<String, Object>, Object[]> gstl = r -> {
            List<Object> o = new ArrayList<>(List.of(r.get("faculty") == null ? "THE SCOPE" : s(r.get("faculty")), n(r.get("gst_applicable")), n(r.get("gst_registered")),
                    Math.max(0, n(r.get("gst_applicable")) - n(r.get("gst_registered"))), n(r.get("gst_paid")), n(r.get("gst_not_paid"))));
            if (gstMoney) {
                o.add(r.get("gst_paid_amount"));
                o.add(r.get("gst_outstanding"));
            }
            return o.toArray();
        };
        List<Object[]> gstRows = new ArrayList<>(faculties.stream().map(gstl).toList());
        if (!a.isEmpty()) gstRows.add(gstl.apply(withoutFaculty(a)));
        out.add(new Section("gst", "GST statistics", gstc, gstRows, "GST students: the GST fee owed, or a GST course registered. Registration and payment are counted apart."));
        Function<Map<String, Object>, Object[]> epsl = r -> new Object[] {r.get("faculty") == null ? "THE SCOPE" : s(r.get("faculty")), n(r.get("eps_applicable")),
                n(r.get("eps_registered")), Math.max(0, n(r.get("eps_applicable")) - n(r.get("eps_registered"))), n(r.get("eps_paid")), n(r.get("eps_not_paid"))};
        List<Object[]> epsRows = new ArrayList<>(faculties.stream().map(epsl).toList());
        if (!a.isEmpty()) epsRows.add(epsl.apply(withoutFaculty(a)));
        out.add(new Section("eps", "EPS statistics", List.of(t("Faculty", 34), i("EPS students"), i("Registered"), i("Not registered"), i("Paid"), i("Not paid")), epsRows,
                "EPS students: the EPS fee owed, or an EPS course registered."));

        // registration, the card, the permit
        Function<Map<String, Object>, Object[]> regl = r -> new Object[] {r.get("faculty") == null ? "THE SCOPE" : s(r.get("faculty")), n(r.get("total")), n(r.get("registered")),
                n(r.get("not_registered")), n(r.get("paid_not_registered")), n(r.get("carryover_registered")), n(r.get("reg_approved")), n(r.get("reg_pending"))};
        List<Object[]> regRows = new ArrayList<>(faculties.stream().map(regl).toList());
        if (!a.isEmpty()) regRows.add(regl.apply(withoutFaculty(a)));
        out.add(new Section("registration", "Course registration statistics", List.of(t("Faculty", 34), i("Students"), i("Registered"), i("Not registered"), i("Paid not registered"),
                i("With carry-overs"), i("Approved"), i("Pending approval")), regRows, null));
        Function<Map<String, Object>, Object[]> cardl = r -> new Object[] {r.get("faculty") == null ? "THE SCOPE" : s(r.get("faculty")), n(r.get("total")), n(r.get("card_eligible")),
                n(r.get("card_issued")), n(r.get("card_not_issued")), n(r.get("card_not_eligible"))};
        List<Object[]> cardRows = new ArrayList<>(faculties.stream().map(cardl).toList());
        if (!a.isEmpty()) cardRows.add(cardl.apply(withoutFaculty(a)));
        out.add(new Section("cards", "Examination card statistics", List.of(t("Faculty", 34), i("Students"), i("Eligible"), i("Issued"), i("Eligible, not drawn"), i("Not eligible")),
                cardRows, "Eligible is the card's own rule; issued is a card the student drew from the portal. They are counted apart."));
        Function<Map<String, Object>, Object[]> perml = r -> new Object[] {r.get("faculty") == null ? "THE SCOPE" : s(r.get("faculty")), n(r.get("permit_eligible")),
                n(r.get("permit_generated")), n(r.get("permit_printed")), n(r.get("permit_not_printed"))};
        List<Object[]> permRows = new ArrayList<>(faculties.stream().map(perml).toList());
        if (!a.isEmpty()) permRows.add(perml.apply(withoutFaculty(a)));
        out.add(new Section("permits", "GST & EPS examination permit statistics", List.of(t("Faculty", 34), i("Eligible"), i("Generated"), i("Printed"), i("Eligible, not printed")),
                permRows, null));

        // the semesters, the transactions by semester and day
        if (semesters != null && !semesters.isEmpty()) {
            List<Col> sc = new ArrayList<>(List.of(t("Semester", 18), i("Students"), i("Fees paid"), i("Not paid"), i("Paid not registered"), i("Registered"), i("GST paid"),
                    i("EPS paid"), i("Cards issued"), i("Permits printed")));
            out.add(new Section("semesters", "Semester summary", sc, semesters.stream().map(r -> new Object[] {sem(r.get("semester")), n(r.get("total")), n(r.get("fees_paid")),
                    n(r.get("fees_not_paid")), n(r.get("paid_not_registered")), n(r.get("registered")), n(r.get("gst_paid")), n(r.get("eps_paid")), n(r.get("card_issued")),
                    n(r.get("permit_printed"))}).toList(), "School fees are a session's; registration, the card and the permit are the semester's."));
        }
        if (tx != null) {
            out.add(new Section("tx_semester", "Transactions by semester", List.of(t("Semester", 18), i("Successful transactions"), m("Revenue (₦)")),
                    ((List<Map<String, Object>>) tx.getOrDefault("bySemester", List.of())).stream().map(x -> new Object[] {x.get("semester") == null ? "Not stated" : sem(x.get("semester")),
                            n(x.get("transactions")), x.get("amount")}).toList(), null));
            out.add(new Section("tx_daily", "Daily transaction analysis", List.of(Col.date("Day"), i("Successful transactions"), m("Revenue (₦)")),
                    ((List<Map<String, Object>>) tx.getOrDefault("byDay", List.of())).stream().map(x -> new Object[] {x.get("day") == null ? null : java.time.LocalDate.parse(s(x.get("day"))),
                            n(x.get("transactions")), x.get("amount")}).toList(), null));
        }

        // reconciliation and data quality
        out.add(new Section("reconciliation", "Reconciliation", List.of(t("Check", 70), t("Holds", 8), new Col("Left", Kind.MONEY, 16), new Col("Right", Kind.MONEY, 16)),
                reconciliation.stream().map(c -> new Object[] {s(c.get("check")), Boolean.TRUE.equals(c.get("holds")) ? "Yes" : "NO", c.get("left"), c.get("right")}).toList(), null));
        List<Object[]> q = new ArrayList<>();
        if (quality != null) for (Map<String, Object> x : quality) if (n(x.get("n")) > 0) q.add(new Object[] {s(x.get("area")), s(x.get("label")), n(x.get("n"))});
        q.add(new Object[] {"Report", "Registered, school fees not paid", n(a.get("registered_not_paid"))});
        q.add(new Object[] {"Report", "GST course registered, GST not paid", n(a.get("gst_registered_not_paid"))});
        q.add(new Object[] {"Report", "Examination card drawn, not eligible now", n(a.get("card_issued_not_eligible"))});
        q.add(new Object[] {"Report", "GST permit generated, not eligible now", n(a.get("permit_generated_not_eligible"))});
        out.add(new Section("quality", "Data quality and exceptions", List.of(t("Area", 24), t("Finding", 60), i("Records")), q,
                "Reported, never put right here: each office puts its own right on its own screen."));
        out.add(new Section("definitions", "Definitions", List.of(t("Figure", 30), t("What it means", 110)), DEFINITIONS.stream().map(d -> new Object[] {d[0], d[1]}).toList(), null));
        return out.stream().filter(x -> !x.rows().isEmpty()).toList();
    }

    private static Map<String, Object> withoutFaculty(Map<String, Object> a) {
        Map<String, Object> m = new LinkedHashMap<>(a);
        m.put("faculty", null);
        return m;
    }

    static final List<String[]> DEFINITIONS = List.of(
            new String[] {"Students", "Every student of the scope the student statistics engine counts for the session: in study (active or on probation), the session's fresh students, and anyone registered or paid."},
            new String[] {"School fees paid", "The student's school-fee obligation for the session is met in full on the Bursary's fee lines (short by under one naira counts as paid)."},
            new String[] {"Partially paid", "A verified school-fees payment below the obligation."},
            new String[] {"Not paid", "A school fee is charged and no verified school-fees payment is recorded for the session."},
            new String[] {"No fee stated", "No school fee is stated for the student in the session; never counted as not paid."},
            new String[] {"Paid but not registered", "A verified school-fees payment for the session (the examination card's test: any amount) and no course registration of the semester."},
            new String[] {"Registered", "A course registration of the semester, as the registration engine reads it across the University, College and postgraduate registers."},
            new String[] {"GST paid", "The GST engine's entitlement: a verified GST payment (or an exemption) for the session. GST registration and GST payment are counted apart."},
            new String[] {"GST not paid", "The GST fee is owed (a GST course required, a carry-over or a course registered) or a GST course is registered, and it is not paid."},
            new String[] {"EPS paid", "The EPS entitlement: the GST fee where the Bursar's setting says it covers EPS, else a payment of the EPS fee."},
            new String[] {"Examination card eligible", "The card's own rule: a submitted course registration of the semester with courses, and a verified school-fees payment for the session."},
            new String[] {"Examination card issued", "A card the student drew from the portal (download or print), as the portal records it; the portal cannot see a printer."},
            new String[] {"GST permit eligible", "A GST or EPS course on a submitted registration of the semester, the school fees paid by the card's test, and the GST fee paid where it is owed."},
            new String[] {"GST permit generated / printed", "The permit issued to the student, and the times it was printed, as the permit's own record holds them; a revoked permit is not counted."},
            new String[] {"Transactions", "Every payment of the one ledger in the period (the day it was confirmed, else generated, in Lagos), each counted once; a payment reallocated to another purpose is one transaction under its corrected purpose."},
            new String[] {"Revenue", "Successful (verified) payments only, net of any refund paid against them; pending, failed (expired unpaid), reversed and refunded payments are never revenue."},
            new String[] {"Unique students", "The distinct students (or applicants) behind the transactions: one student who paid three times is three transactions and one student."});

    /* ── the lists ───────────────────────────────────────────────────────────────────────────────────────────────────── */

    private static Column c(Col col, Function<Map<String, Object>, Object> f) {
        return new Column(col, f);
    }

    private static String name(Map<String, Object> r) {
        String sn = s(r.get("surname")), on = s(r.get("other_names"));
        return on.isEmpty() ? sn : sn + ", " + on;
    }

    /** the students' school fees, one row a student (names A to Z) */
    static Detail fees(String money, String session, int semester) {
        List<Column> cols = new ArrayList<>(List.of(c(t("Student name", 32), MasterSections::name), c(t("Matric no", 22), r -> r.get("matric_no")),
                c(t("JAMB no", 16), r -> r.get("jamb_no")), c(t("Gender", 10), r -> sex(r.get("sex"))), c(t("Faculty", 26), r -> r.get("faculty")),
                c(t("Department", 26), r -> r.get("department")), c(t("Programme", 30), r -> r.get("programme")), c(t("Programme type", 16), r -> r.get("programme_type")),
                c(i("Level"), r -> r.get("level")), c(t("Admission session", 12), r -> r.get("entry_session")), c(t("Session", 11), r -> session),
                c(t("Semester", 15), r -> sem(semester))));
        if ("ALL".equals(money)) {
            cols.add(c(m("Total fee (₦)"), r -> r.get("payable")));
            cols.add(c(m("Amount paid (₦)"), r -> r.get("paid_amount")));
            cols.add(c(m("Outstanding (₦)"), r -> r.get("outstanding")));
        }
        cols.add(c(t("Payment status", 16), r -> FEE.getOrDefault(s(r.get("fee_status")), s(r.get("fee_status")))));
        cols.add(c(t("Registration", 15), r -> Boolean.TRUE.equals(r.get("registered")) ? "Registered" : "Not registered"));
        cols.add(c(Col.moment("Last payment"), r -> r.get("last_paid_at")));
        return new Detail("fee_details", "School fees details", cols, null);
    }

    static Detail cards(String session, int semester) {
        return new Detail("card_details", "Examination cards", List.of(c(t("Student", 32), MasterSections::name), c(t("Matric no", 22), r -> r.get("matric_no")),
                c(t("Faculty", 26), r -> r.get("faculty")), c(t("Department", 26), r -> r.get("department")), c(t("Programme", 30), r -> r.get("programme")),
                c(i("Level"), r -> r.get("level")), c(t("Session", 11), r -> session), c(t("Semester", 15), r -> sem(semester)),
                c(t("Card status", 18), r -> Boolean.TRUE.equals(r.get("card_issued")) ? "Issued" : Boolean.TRUE.equals(r.get("card_eligible")) ? "Eligible, not drawn" : "Not eligible"),
                c(Col.moment("First drawn"), r -> r.get("card_issued_at")), c(i("Times drawn"), r -> r.get("card_times"))), null);
    }

    static Detail permits(String session, int semester) {
        return new Detail("permit_details", "GST & EPS examination permits", List.of(c(t("Student", 32), MasterSections::name), c(t("Matric no", 22), r -> r.get("matric_no")),
                c(t("Faculty", 26), r -> r.get("faculty")), c(t("Department", 26), r -> r.get("department")), c(t("Programme", 30), r -> r.get("programme")),
                c(i("Level"), r -> r.get("level")), c(t("Session", 11), r -> session), c(t("Semester", 15), r -> sem(semester)),
                c(t("GST registration", 15), r -> Boolean.TRUE.equals(r.get("gst_registered")) || Boolean.TRUE.equals(r.get("eps_registered")) ? "Registered" : "Not registered"),
                c(t("GST payment", 12), r -> GSTW.getOrDefault(s(r.get("gst_status")), s(r.get("gst_status")))),
                c(t("Permit status", 14), r -> Boolean.TRUE.equals(r.get("permit_printed")) ? "Printed" : Boolean.TRUE.equals(r.get("permit_generated")) ? "Generated"
                        : Boolean.TRUE.equals(r.get("permit_eligible")) ? "Eligible" : "Not eligible"),
                c(t("Reference", 22), r -> r.get("permit_reference")), c(Col.moment("Generated"), r -> r.get("permit_generated_at")), c(i("Times printed"), r -> r.get("permit_printed_times"))),
                null);
    }

    static Detail courses(String office, String session, int semester) {
        return new Detail(office.toLowerCase() + "_courses", office + " registration", List.of(c(t("Student", 32), MasterSections::name), c(t("Matric no", 22), r -> r.get("matric_no")),
                c(t("JAMB no", 16), r -> r.get("jamb_no")), c(t("Gender", 10), r -> sex(r.get("sex"))), c(t("Faculty", 26), r -> r.get("faculty")),
                c(t("Department", 26), r -> r.get("department")), c(t("Programme", 30), r -> r.get("programme")), c(i("Level"), r -> r.get("level")),
                c(t("Session", 11), r -> session), c(t("Semester", 15), r -> sem(semester)), c(t("Course code", 12), r -> r.get("course_code")),
                c(t("Course title", 34), r -> r.get("title")), c(i("Units"), r -> r.get("units")),
                c(t("Registration", 18), r -> Boolean.TRUE.equals(r.get("registered")) ? "Registered" : "Owed, not registered"),
                c(t(office + " payment", 12), r -> GSTW.getOrDefault(s(r.get("payment_status")), s(r.get("payment_status")))),
                c(t("Payment reference", 24), r -> r.get("payment_reference"))), null);
    }

    static Detail transactions(String key, String title) {
        return new Detail(key, title, List.of(c(t("Payment reference", 26), r -> r.get("reference")), c(t("Gateway reference", 22), r -> r.get("gateway_reference")),
                c(t("Student", 30), MasterSections::name), c(t("Matric / number", 22), r -> r.get("number")), c(t("JAMB no", 16), r -> r.get("jamb_reg_no")),
                c(t("Gender", 10), r -> r.get("sex") == null ? "" : sex(r.get("sex"))), c(t("Faculty", 24), r -> r.get("faculty")), c(t("Department", 24), r -> r.get("department")),
                c(t("Programme", 28), r -> r.get("programme")), c(t("Programme type", 14), r -> r.get("programme_type")), c(i("Level"), r -> r.get("level")),
                c(t("Session", 11), r -> r.get("session")), c(t("Semester", 15), r -> sem(r.get("semester"))),
                c(t("Payment purpose", 26), r -> r.get("purpose_label") == null ? r.get("purpose") : r.get("purpose_label")), c(m("Amount (₦)"), r -> r.get("amount")),
                c(m("Refunded (₦)"), r -> r.get("refunded")), c(m("Net (₦)"), r -> r.get("net_amount")),
                c(Col.moment("Payment date"), r -> r.get("confirmed_at") != null ? r.get("confirmed_at") : r.get("generated_at")),
                c(t("Status", 16), r -> PST.getOrDefault(s(r.get("status")), s(r.get("status")))), c(t("Channel", 16), r -> r.get("channel"))), null);
    }

    static Object nz(Object o) {
        return Objects.requireNonNullElse(o, "");
    }
}
