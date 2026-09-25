"use client";

/** The Student Payment Report of the College of Health Sciences (V256): every College student's fees position for
 *  a session or for one semester of it — amount payable, paid, outstanding, status, last payment — with the totals
 *  at the top, the same by programme, the filters and search the Finance Controller asked for, and the report as a
 *  branded Excel workbook or PDF with S/N first and names A–Z. Everything is read from the register as it stands. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface PayRow {
  id: string; surname: string; other_names: string; number: string; level: number; faculty: string; department: string; dept_code: string;
  programme_code: string; programme: string; student_status: string;
  payable: number; paid: number; outstanding: number; status: string; last_paid_at: string | null; last_reference: string | null; last_channel: string | null; payments: number;
}
export interface PayTotals { students: number; payable: number; paid: number; outstanding: number; fullyPaid: number; partPayment: number; notPaid: number; noCharge: number; withBalance: number }
export interface PayReport {
  session: string; semester: number | null; summary: PayTotals;
  byProgramme: (PayTotals & { programme_code: string; programme: string; department: string })[];
  rows: PayRow[];
  options: { programmes: { code: string; name: string; dept_code: string; department: string }[]; levels: number[]; sessions: string[] };
}
export interface PayFilters { session: string; semester: string; programme: string; dept: string; level: string; status: string; q: string }

const STATUS: Record<string, [string, "ok" | "warn" | "bad" | "grey"]> = {
  FULLY_PAID: ["Fully Paid", "ok"], PART_PAYMENT: ["Part Payment", "warn"], NOT_PAID: ["Outstanding", "bad"], NO_CHARGE: ["No charge", "grey"],
};
const PERIOD: Record<string, string> = { "": "Whole session", "1": "First semester", "2": "Second semester" };
const naira = (n: number | string) => "₦" + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 });
const dayOf = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");

export function PaymentReport({ report, filters, basePath, role }: { report: PayReport; filters: PayFilters; basePath: string; role: string }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const [openProg, setOpenProg] = useState<string | null>(null);
  const t = report.summary;
  const period = PERIOD[filters.semester] ?? "Whole session";
  const progs = report.options.programmes.filter((p) => !filters.dept || p.dept_code === filters.dept);
  const depts = [...new Map(report.options.programmes.map((p) => [p.dept_code, p.department])).entries()].sort((a, b) => a[1].localeCompare(b[1]));
  const scope = [
    report.session, period,
    filters.dept ? depts.find((d) => d[0] === filters.dept)?.[1] : null,
    filters.programme ? report.options.programmes.find((p) => p.code === filters.programme)?.name : null,
    filters.level ? `${filters.level} Level` : null,
    filters.status ? STATUS[filters.status]?.[0] : null,
    filters.q ? `search “${filters.q}”` : null,
  ].filter(Boolean).join(" · ");
  const shown = openProg ? report.rows.filter((r) => r.programme_code === openProg) : report.rows;

  function go(next: Partial<PayFilters>) {
    const f = { ...filters, ...next };
    if (next.dept !== undefined) f.programme = "";
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
    queryNav(`${basePath}${qs.toString() ? `?${qs}` : ""}`);
  }

  const HEAD = ["S/N", "Student Name", "Matriculation / Registration Number", "Level", "Faculty / College", "Department", "Programme of Study", "Academic Session", "Period", "Amount Payable", "Amount Paid", "Amount Outstanding", "Payment Status", "Date of Last Payment", "Payment Reference"];
  const body = (rows: PayRow[]) => rows.map((r, i) => [
    i + 1, `${r.surname}, ${r.other_names}`, r.number, r.level, r.faculty, r.department, r.programme, report.session, period,
    Number(r.payable), Number(r.paid), Number(r.outstanding), STATUS[r.status]?.[0] ?? r.status, r.last_paid_at ? dayOf(r.last_paid_at) : "", r.last_reference ?? "",
  ]);
  const SUMMARY_HEAD = ["S/N", "Description", "Value"];
  const summaryRows = () => [
    [1, "Total Number of Students", t.students], [2, "Total Amount Payable", Number(t.payable)], [3, "Total Amount Paid", Number(t.paid)],
    [4, "Total Amount Outstanding", Number(t.outstanding)], [5, "Fully Paid Students", t.fullyPaid], [6, "Part-Payment Students", t.partPayment],
    [7, "Students with Outstanding Balance", t.withBalance],
  ];
  const PROG_HEAD = ["S/N", "Programme", "Department", "Students", "Amount Payable", "Amount Paid", "Amount Outstanding", "Fully Paid", "Part Payment", "Outstanding"];
  const progRows = () => report.byProgramme.map((p, i) => [i + 1, p.programme, p.department, p.students, Number(p.payable), Number(p.paid), Number(p.outstanding), p.fullyPaid, p.partPayment, p.withBalance]);

  async function toExcel() {
    const serial = docSerial("CHSPAY");
    const blob = await brandedXlsx("Student Payment Report — College of Health Sciences", HEAD, body(shown), { sheetName: "Payment report", serial, sub: scope });
    downloadBlob(blob, `chs-student-payment-report-${report.session.replace("/", "-")}${filters.semester ? `-sem${filters.semester}` : ""}.xlsx`);
  }
  async function summaryExcel() {
    const serial = docSerial("CHSPAY");
    const blob = await brandedXlsx("Student Payment Summary — College of Health Sciences", PROG_HEAD, [...progRows()], { sheetName: "By programme", serial, sub: scope });
    downloadBlob(blob, `chs-payment-summary-${report.session.replace("/", "-")}.xlsx`);
  }
  function toPdf() { brandedPrint("Student Payment Report — College of Health Sciences", scope, HEAD, body(shown), docSerial("CHSPAY")); }
  /** the seven-line summary the letter asks for at the top of the report, as its own page */
  function summaryPdf() { brandedPrint("Student Payment Summary — College of Health Sciences", scope, SUMMARY_HEAD, summaryRows(), docSerial("CHSPAY")); }
  function progPdf() { brandedPrint("Student Payments by Programme — College of Health Sciences", scope, PROG_HEAD, progRows(), docSerial("CHSPAY")); }

  return (
    <>
      <PageHead title="Student Payment Report" description={`${role}, College of Health Sciences · ${report.session} · ${period}. Each student's amount payable, paid and outstanding, read from the fee schedule and the confirmed payments; the totals are of the set shown.`}
        actions={<><Btn kind="primary" onClick={() => void toExcel()}>Download Excel</Btn><Btn kind="secondary" onClick={toPdf}>Download PDF</Btn><Btn kind="ghost" onClick={summaryPdf}>Summary PDF</Btn><LinkBtn href="/finance/fees">Fee Setup and Schedule</LinkBtn></>} />

      <div className="scope">
        <div className="scope__f"><Field id="pr-session" label="Academic session">
          <select id="pr-session" className="ctl" value={report.session} onChange={(e) => go({ session: e.target.value })}>
            {(report.options.sessions.includes(report.session) ? report.options.sessions : [report.session, ...report.options.sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="pr-period" label="Period" hint="Payments cover the first semester before the second">
          <select id="pr-period" className="ctl" value={filters.semester} onChange={(e) => go({ semester: e.target.value })}>
            {Object.entries(PERIOD).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="pr-dept" label="Department">
          <select id="pr-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}>
            <option value="">All departments</option>{depts.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="pr-prog" label="Programme">
          <select id="pr-prog" className="ctl" value={filters.programme} onChange={(e) => go({ programme: e.target.value })}>
            <option value="">All programmes</option>{progs.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="pr-level" label="Level">
          <select id="pr-level" className="ctl" value={filters.level} onChange={(e) => go({ level: e.target.value })}>
            <option value="">All levels</option>{report.options.levels.map((l) => <option key={l} value={String(l)}>{l} Level</option>)}
          </select>
        </Field></div>
        <div className="scope__f"><Field id="pr-status" label="Payment status">
          <select id="pr-status" className="ctl" value={filters.status} onChange={(e) => go({ status: e.target.value })}>
            <option value="">Every status</option>{Object.entries(STATUS).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
          </select>
        </Field></div>
        <div className="scope__f grow"><Field id="pr-q" label="Search" hint="Name, matriculation number or payment reference">
          <form onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }} className="row row--tight">
            <input id="pr-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="e.g. MOAUM/MED/24/9907 or a reference" />
            <Btn kind="ghost" type="submit">Search</Btn>
            {filters.q ? <Btn kind="ghost" onClick={() => { setQ(""); go({ q: "" }); }}>Clear</Btn> : null}
          </form>
        </Field></div>
      </div>

      <Tiles items={[
        ["Total students", String(t.students), null, scope],
        ["Total amount payable", naira(t.payable), null, period],
        ["Total amount paid", naira(t.paid), Number(t.paid) > 0 ? "var(--green-ink)" : null, t.payable > 0 ? `${Math.round((100 * Number(t.paid)) / Number(t.payable))}% of payable` : "No charge stated"],
        ["Total amount outstanding", naira(t.outstanding), Number(t.outstanding) > 0 ? "var(--red-ink)" : "var(--green-ink)", `${t.withBalance} student${t.withBalance === 1 ? "" : "s"} with a balance`],
        ["Fully paid students", String(t.fullyPaid), t.fullyPaid ? "var(--green-ink)" : null, t.students ? `${Math.round((100 * t.fullyPaid) / t.students)}% of students` : "—"],
        ["Part-payment students", String(t.partPayment), t.partPayment ? "var(--amber-ink)" : null, "Paid something, balance remains"],
        ["Students with outstanding balance", String(t.withBalance), t.withBalance ? "var(--red-ink)" : null, `${t.notPaid} with nothing paid`],
        ["No charge stated", String(t.noCharge), null, t.noCharge ? "No fee row matches these students" : "Every student has a charge"],
      ]} />

      <Panel title="By programme" right={<span className="row row--inline row--tight"><span className="sub2">{report.byProgramme.length} programme{report.byProgramme.length === 1 ? "" : "s"}</span><Btn kind="ghost" size="sm" onClick={() => void summaryExcel()}>Excel</Btn><Btn kind="ghost" size="sm" onClick={progPdf}>PDF</Btn></span>}>
        {report.byProgramme.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Programme", "Students|num", "Payable|num", "Paid|num", "Outstanding|num", "Fully paid|num", "Part payment|num", "Outstanding|num", "|num"]}
            rows={report.byProgramme.map((p, i) => [
              <span key="sn" className="tnum sub2">{i + 1}</span>,
              <span key="p"><strong>{p.programme}</strong><div className="sub2">{p.department}</div></span>,
              <span key="n" className="tnum">{p.students}</span>,
              <span key="a" className="tnum">{naira(p.payable)}</span>,
              <span key="b" className="tnum ink-green">{naira(p.paid)}</span>,
              <span key="c" className={`tnum${Number(p.outstanding) > 0 ? " ink-red b600" : ""}`}>{naira(p.outstanding)}</span>,
              <span key="d" className="tnum">{p.fullyPaid}</span>,
              <span key="e" className="tnum">{p.partPayment}</span>,
              <span key="f" className="tnum">{p.withBalance}</span>,
              <Btn key="o" kind={openProg === p.programme_code ? "primary" : "ghost"} size="sm" onClick={() => setOpenProg(openProg === p.programme_code ? null : p.programme_code)}>{openProg === p.programme_code ? "All Students" : "Students"}</Btn>,
            ])} />
        ) : <PBody><div className="sub2">No College student matches these filters.</div></PBody>}
      </Panel>

      <Panel title={openProg ? `Students · ${report.byProgramme.find((p) => p.programme_code === openProg)?.programme ?? ""}` : "Students"} right={`${shown.length} of ${report.rows.length} · names A–Z within programme`}>
        {shown.length ? (
          <DTable cols={["S/N|num", "Student", "Level|mid", "Programme", "Payable|num", "Paid|num", "Outstanding|num", "Status|mid", "Last payment", "|num"]}
            rows={shown.map((r, i) => {
              const [word, kind] = STATUS[r.status] ?? [r.status, "grey"];
              return [
                <span key="sn" className="tnum sub2">{i + 1}</span>,
                <span key="s"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.number}</div></span>,
                <span key="l" className="tnum">{r.level}</span>,
                <span key="p">{r.programme}<div className="sub2">{r.department}</div></span>,
                <span key="a" className="tnum">{naira(r.payable)}</span>,
                <span key="b" className="tnum">{naira(r.paid)}</span>,
                <span key="c" className={`tnum${Number(r.outstanding) > 0 ? " ink-red b600" : ""}`}>{naira(r.outstanding)}</span>,
                <Pil key="st" kind={kind}>{word}</Pil>,
                <span key="lp" className="sub2">{r.last_paid_at ? <><span className="tnum">{dayOf(r.last_paid_at)}</span><div className="tnum">{r.last_reference}{r.last_channel ? ` · ${r.last_channel}` : ""}</div></> : "—"}</span>,
                <LinkBtn key="o" href={`/students/${r.id}`} size="sm">Open</LinkBtn>,
              ];
            })}
            texts={shown.map((r) => `${r.surname} ${r.other_names} ${r.number} ${r.programme} ${STATUS[r.status]?.[0] ?? ""} ${r.last_reference ?? ""}`)} />
        ) : <PBody><div className="sub2">No College student matches these filters.</div></PBody>}
        <PBody><div className="sub2">Amount outstanding is amount payable less amount paid. In a semester view the session&rsquo;s payments cover the first semester&rsquo;s charge before the second&rsquo;s, which is how registration reads them; a student who paid the session at once is fully paid in both. <Link className="lnk" href="/finance/payments">Every confirmed payment</Link> is on the Bursary&rsquo;s payments query.</div></PBody>
      </Panel>

      {t.students === 0 ? <Note kind="info" title="No College student is on the register for these filters">Students appear here once they are on the register with a College programme; a charge appears once the fee schedule for the session names their level or programme.</Note> : null}
    </>
  );
}
