"use client";

/** The students behind a statistic (V257): a breadcrumb that says which figure was opened, the filters it
 *  carried, search on the server, a page of fifty at a time, and the whole set as a branded Excel workbook or
 *  PDF with S/N first and names A–Z. The columns follow the figure: payments for the paid, courses for the
 *  registered, both for the paid-but-not-registered, the balance for the unpaid where the office may see it. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DEGREE_WORD, SEMESTER_WORD, WHICH_WORD, statQuery, type StatFilters, type StatPage, type StatRow, type Which } from "@/lib/stats";

const PAY: Record<string, [string, "ok" | "warn" | "bad" | "grey"]> = { FULLY_PAID: ["Paid", "ok"], PART_PAYMENT: ["Part payment", "warn"], NOT_PAID: ["Not paid", "bad"], NO_CHARGE: ["No charge", "grey"] };
const REG: Record<string, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = { LOCKED: ["Locked", "ok"], APPROVED: ["Approved", "ok"], ENDORSED: ["Endorsed", "ok"], SUBMITTED: ["Submitted", "info"], REGISTERED: ["Registered", "ok"], DRAFT: ["Draft", "warn"], RETURNED: ["Returned", "warn"], OPEN: ["Not registered", "bad"] };
const naira = (n: number | undefined | null) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 }));
const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");

export function Detail({ data, filters, which, q: initialQ }: { data: StatPage; filters: StatFilters; which: Which; q: string }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(initialQ);
  const [busy, setBusy] = useState(false);
  const f: StatFilters = { ...filters, session: data.session, semester: data.semester == null ? "" : String(data.semester) };
  const money = data.scope.money;
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const scopeWords = [data.scope.label, data.session, SEMESTER_WORD(data.semester), f.fac, f.dept, f.prog, f.level ? `${f.level} Level` : null, f.degree ? DEGREE_WORD[f.degree] : null, initialQ ? `search “${initialQ}”` : null].filter(Boolean).join(" · ");
  const go = (extra: Record<string, string | number | undefined>) => queryNav(`/stats/students?${statQuery(f, { which, q: initialQ, ...extra })}`);

  /* the columns follow the figure opened */
  const showPay = which !== "REGISTERED";
  const showReg = which !== "PAID" && which !== "NOT_PAID";
  const HEAD = ["S/N", "Student ID", "Student Name", "Faculty", "Department", "Programme", "Level", "Academic Session", "Semester",
    ...(showPay ? ["School Fees Status", ...(money ? ["Amount Payable", "Amount Paid", "Outstanding Balance", "Payment Reference"] : []), "Payment Date"] : []),
    ...(showReg ? ["Course Registration Status", "Registration Date"] : [])];
  const line = (r: StatRow, i: number) => [
    i + 1, r.number, `${r.surname}, ${r.other_names}`, r.faculty, r.department, r.programme, r.level, data.session, SEMESTER_WORD(data.semester),
    ...(showPay ? [PAY[r.pay_status]?.[0] ?? r.pay_status, ...(money ? [Number(r.payable ?? 0), Number(r.paid_amount ?? 0), Number(r.outstanding ?? 0), r.last_reference ?? ""] : []), r.last_paid_at ? dayOf(r.last_paid_at) : ""] : []),
    ...(showReg ? [r.registered ? (REG[r.registration_status ?? ""]?.[0] ?? "Registered") : "Not registered", r.registered_at ? dayOf(r.registered_at) : ""] : []),
  ];

  /** every row of the set, fetched page by page from the same endpoint, for the export */
  async function allRows(): Promise<StatRow[]> {
    const out: StatRow[] = [];
    for (let page = 0; page * 500 < data.total && page < 100; page++) {
      const r = await fetch(`/api/bff/api/v1/stats/students?${statQuery(f, { which, q: initialQ, page, size: 500 })}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as StatPage;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return out;
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = await allRows();
      const title = `${WHICH_WORD[which]} — Student Statistics`;
      const serial = docSerial("STAT");
      if (kind === "xlsx") {
        const blob = await brandedXlsx(title, HEAD, rows.map(line), { sheetName: WHICH_WORD[which].slice(0, 31), serial, sub: scopeWords });
        downloadBlob(blob, `students-${which.toLowerCase()}-${data.session.replace("/", "-")}.xlsx`);
      } else {
        brandedPrint(title, scopeWords, HEAD, rows.map(line), serial);
      }
      notify(`${rows.length} row${rows.length === 1 ? "" : "s"} exported`);
    } catch (e) { const pr = e as { status?: number; title?: string }; notifyProblem({ status: pr?.status ?? 500, title: pr?.title ?? "The export could not be prepared." }); }
    finally { setBusy(false); }
  }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}>
        <Link className="lnk" href="/">Dashboard</Link><span>›</span><Link className="lnk" href={`/stats?${statQuery(f)}`}>Student Statistics</Link><span>›</span><strong>{WHICH_WORD[which]}</strong>
      </div>
      <PageHead title={WHICH_WORD[which]} description={`${scopeWords}. ${data.total.toLocaleString()} student${data.total === 1 ? "" : "s"}, names A–Z, the same rows the figure counted.`}
        actions={<><Btn kind="primary" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>{busy ? "Preparing…" : "Export Excel"}</Btn><Btn kind="secondary" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>Export PDF</Btn><LinkBtn href={`/stats?${statQuery(f)}`}>Back to Statistics</LinkBtn></>} />

      <div className="scope">
        <div className="scope__f grow">
          <label htmlFor="sd-q">Search</label>
          <form onSubmit={(e) => { e.preventDefault(); go({ q: q.trim(), page: 0 }); }} className="row row--tight">
            <input id="sd-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Student ID, name, programme, department, faculty or payment reference" />
            <Btn kind="ghost" type="submit">Search</Btn>
            {initialQ ? <Btn kind="ghost" onClick={() => { setQ(""); go({ q: "", page: 0 }); }}>Clear</Btn> : null}
          </form>
        </div>
        <div className="scope__f">
          <label htmlFor="sd-which">Figure</label>
          <select id="sd-which" className="ctl" value={which} onChange={(e) => queryNav(`/stats/students?${statQuery(f, { which: e.target.value, q: initialQ })}`)}>
            {(Object.keys(WHICH_WORD) as Which[]).map((w) => <option key={w} value={w}>{WHICH_WORD[w]}</option>)}
          </select>
        </div>
      </div>

      <Panel title="Students" right={data.total ? `Page ${data.page + 1} of ${pages} · ${data.total.toLocaleString()} in all` : "None"}>
        {data.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Level|mid", ...(showPay ? ["Fees|mid", ...(money ? ["Payable|num", "Paid|num", "Outstanding|num"] : []), "Last payment"] : []), ...(showReg ? ["Registration|mid", "Registered|mid"] : []), "|num"]}
            rows={data.rows.map((r, i) => {
              const [pw, pk] = PAY[r.pay_status] ?? [r.pay_status, "grey"];
              const [rw, rk] = r.registered ? (REG[r.registration_status ?? ""] ?? ["Registered", "ok"]) : ["Not registered", "bad"];
              return [
                <span key="sn" className="tnum sub2">{data.page * data.size + i + 1}</span>,
                <span key="s"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.number}{r.degree_type ? ` · ${DEGREE_WORD[r.degree_type] ?? r.degree_type}` : ""}</div></span>,
                <span key="p">{r.programme}<div className="sub2">{r.department} · {r.faculty}</div></span>,
                <span key="l" className="tnum">{r.level}</span>,
                ...(showPay ? [
                  <Pil key="pay" kind={pk}>{pw}</Pil>,
                  ...(money ? [<span key="a" className="tnum">{naira(r.payable)}</span>, <span key="b" className="tnum">{naira(r.paid_amount)}</span>, <span key="c" className={`tnum${Number(r.outstanding) > 0 ? " ink-red b600" : ""}`}>{naira(r.outstanding)}</span>] : []),
                  <span key="lp" className="sub2">{r.last_paid_at ? <><span className="tnum">{dayOf(r.last_paid_at)}</span>{money && r.last_reference ? <div className="tnum">{r.last_reference}</div> : null}</> : "—"}</span>,
                ] : []),
                ...(showReg ? [<Pil key="reg" kind={rk as "ok" | "warn" | "bad" | "grey" | "info"}>{rw}</Pil>, <span key="ra" className="tnum sub2">{dayOf(r.registered_at)}</span>] : []),
                <LinkBtn key="o" href={`/students/${r.student_id}`} size="sm">Open</LinkBtn>,
              ];
            })} />
        ) : (
          <PBody><Note kind="info" title="No students found">No students match the selected academic session, semester and filters.</Note></PBody>
        )}
        {pages > 1 ? (
          <PBody>
            <div className="row row--between">
              <Btn kind="ghost" disabled={data.page === 0} onClick={() => go({ page: data.page - 1 })}>Previous</Btn>
              <span className="sub2 tnum">Rows {data.page * data.size + 1}–{Math.min(data.total, (data.page + 1) * data.size)} of {data.total.toLocaleString()}</span>
              <Btn kind="ghost" disabled={data.page + 1 >= pages} onClick={() => go({ page: data.page + 1 })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
