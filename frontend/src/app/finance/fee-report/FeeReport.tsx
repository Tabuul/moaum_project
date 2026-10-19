"use client";

/** The school fees report: for a session, each faculty, department and level — the students paid in full, the students still owing
 *  (part payments among them), the amount paid and the amount owing — and the grand total at the foot; downloaded as Excel or PDF,
 *  S/N first, with the grand total as the last row. The page's address names the session and the scope: it is the link to share. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { FEE_REPORT_HEADERS, feeReportHref, feeReportRows, type FeeReport as Report } from "@/lib/fee-report";

type Unit = { faculty_code: string; faculty: string; dept_code: string; department: string };
const fmt = (v: number | string) => Number(v ?? 0).toLocaleString("en-GB");
/** naira with its kobo, always two places */
const money = (v: number) => `₦${Number(v ?? 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

export function FeeReport({ data, structure, fac, dept, generatedBy }: { data: Report; structure: Unit[]; fac: string; dept: string; generatedBy: string | null }) {
  const go = useQueryNav();
  const [busy, setBusy] = useState<string | null>(null);
  const faculties = Array.from(new Map(structure.map((u) => [u.faculty_code, u.faculty])).entries());
  const departments = structure.filter((u) => !fac || u.faculty_code === fac);
  const scopeWords = [fac ? faculties.find(([c]) => c === fac)?.[1] ?? fac : "", dept ? departments.find((u) => u.dept_code === dept)?.department ?? dept : ""].filter(Boolean).join(" · ")
    || "Every faculty";
  const title = `School fees report, ${data.session}`;
  const t = data.total;

  async function excel() {
    setBusy("excel");
    try {
      const blob = await brandedXlsx(title, FEE_REPORT_HEADERS, feeReportRows(data), {
        sheetName: "School fees", serial: docSerial("SFR"), sub: scopeWords,
        meta: [["Session", data.session], ["Scope", scopeWords], ["Students counted", fmt(t.students)], ["Generated", new Date(data.generatedAt).toLocaleString("en-GB")]],
      });
      downloadBlob(blob, `school-fees-report-${data.session.replace("/", "-")}${fac ? `-${fac}` : ""}${dept ? `-${dept}` : ""}.xlsx`);
    } finally { setBusy(null); }
  }

  function pdf() {
    brandedPrint(title, scopeWords, FEE_REPORT_HEADERS, feeReportRows(data), docSerial("SFR"),
      { meta: [["Session", data.session], ["Scope", scopeWords]], generatedBy, orientation: "landscape" });
  }

  async function copyLink() {
    const link = `${window.location.origin}${feeReportHref(data.session, fac, dept)}`;
    try { await navigator.clipboard.writeText(link); notify("Link copied: anyone with access to the report opens this session and scope"); }
    catch { notify(link, "info", 15000); }
  }

  return (
    <>
      <Panel title={`Session ${data.session}`} right={scopeWords}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <Field id="sfr-session" label="Session" style={{ flex: "0 1 160px" }}>
              <select id="sfr-session" className="ctl" value={data.session} onChange={(e) => go(feeReportHref(e.target.value, fac, dept))}>
                {(data.sessions.includes(data.session) ? data.sessions : [data.session, ...data.sessions]).map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field id="sfr-fac" label="Faculty" style={{ flex: "1 1 220px" }}>
              <select id="sfr-fac" className="ctl" value={fac} onChange={(e) => go(feeReportHref(data.session, e.target.value, ""))}>
                {faculties.length > 1 ? <option value="">Every faculty</option> : null}
                {faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}
              </select>
            </Field>
            <Field id="sfr-dept" label="Department" style={{ flex: "1 1 220px" }}>
              <select id="sfr-dept" className="ctl" value={dept} onChange={(e) => go(feeReportHref(data.session, fac, e.target.value))}>
                {departments.length > 1 ? <option value="">Every department</option> : null}
                {departments.map((u) => <option key={u.dept_code} value={u.dept_code}>{u.department}</option>)}
              </select>
            </Field>
            <span className="grow" />
            <Btn kind="primary" busy={busy === "excel"} busyLabel="Preparing…" disabled={!data.rows.length} onClick={() => excel()}>Download Excel</Btn>
            <Btn kind="ghost" disabled={!data.rows.length} onClick={() => pdf()}>Download PDF</Btn>
            <Btn kind="ghost" onClick={() => copyLink()}>Copy link</Btn>
          </div>
        </PBody>
        <PBody>
          <Tiles items={[
            ["Students paid", fmt(t.paid_students), "var(--green-ink)", "Paid the session's school fees in full"],
            ["Students owing", fmt(t.owing_students), t.owing_students ? "var(--red-ink)" : null, `${fmt(t.part_paid)} of them part-paid`],
            ["Amount paid", money(Number(t.amount_paid)), null, "School-fees payments confirmed for the session"],
            ["Amount owing", money(Number(t.amount_owing)), Number(t.amount_owing) ? "var(--red-ink)" : null, `Of ${money(Number(t.amount_due))} due by the fee setup`],
          ]} />
        </PBody>
        {data.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Session", "Faculty", "Department", "Level|mid", "Students paid|num", "Students owing|num", "Amount paid|num", "Amount owing|num"]}
            rows={data.rows.map((x, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>,
              <span key="s" className="tnum">{data.session}</span>,
              <span key="f">{x.faculty}</span>,
              <span key="d">{x.department}</span>,
              <span key="l" className="tnum">{x.level ?? "—"}</span>,
              <span key="p" className="tnum">{fmt(x.paid_students)}</span>,
              <span key="o" className={`tnum${x.owing_students ? " ink-red" : ""}`}>{fmt(x.owing_students)}{x.part_paid ? <div className="sub2">{fmt(x.part_paid)} part-paid</div> : null}</span>,
              <span key="a" className="tnum">{money(Number(x.amount_paid))}</span>,
              <span key="w" className={`tnum${Number(x.amount_owing) ? " ink-red" : ""}`}>{money(Number(x.amount_owing))}</span>,
            ])}
            foot={[<span key="n" />, <span key="s" />, <b key="f">Grand total</b>, <span key="d" />, <span key="l" />,
              <b key="p" className="tnum">{fmt(t.paid_students)}</b>, <b key="o" className="tnum">{fmt(t.owing_students)}</b>,
              <b key="a" className="tnum">{money(Number(t.amount_paid))}</b>, <b key="w" className="tnum">{money(Number(t.amount_owing))}</b>]} />
        ) : <PBody><div className="sub2">No student is counted for {data.session}{fac || dept ? " in this faculty or department" : ""}.</div></PBody>}
        <PBody>
          <Note kind="info" title="How the figures are read">
            Each student&rsquo;s position is the one their fees page and Student Accounts show: due by the fee setup for their programme and level, paid from
            the session&rsquo;s confirmed school-fees payments (gateway, bank, old portal and carried-over credit). &ldquo;Paid&rdquo; is paid in full (short by under ₦1
            counts as paid); &ldquo;owing&rdquo; includes part payments. Counted: students on the register (active or on probation), the session&rsquo;s new intake not yet
            matriculated, and anyone else who paid school fees in the session.
            {t.no_fee ? ` ${fmt(t.no_fee)} counted student${t.no_fee === 1 ? " has" : "s have"} no fee stated for the session and appear${t.no_fee === 1 ? "s" : ""} in neither column.` : ""}
          </Note>
        </PBody>
      </Panel>
    </>
  );
}
