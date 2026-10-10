"use client";

/** The transactions behind a figure (V279): the filters that counted them carried in the address, search on the
 *  server, fifty a page newest first, a student's own payments a click away, and the whole set as a branded Excel
 *  workbook or PDF with S/N first — never a database id — and every column the finance record holds. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import { PRESETS, entryWord, finQuery, naira, sexWord, whenAt, type FinFilters, type FinPage, type FinTransaction } from "@/lib/analytics";

const HEAD = ["S/N", "Payment Reference", "Student ID", "Student Name", "Gender", "Faculty", "Department", "Programme", "Level", "Entry Type", "Session", "Payment Type",
  "Receipt No", "Amount (₦)", "Payment Date", "Payment Status", "Payment Channel", "Source"];
const line = (r: FinTransaction, sn: number) => [sn, r.reference, r.number ?? "", `${r.surname}, ${r.other_names ?? ""}`.trim(), sexWord(r.sex), r.faculty ?? "", r.department ?? "", r.programme ?? "",
  r.level ?? "", entryWord(r.entry_mode), r.session, r.category, r.receipt_no ?? "", Number(r.amount), whenAt(r.confirmed_at), r.status, r.channel ?? "", r.source];

export function Transactions({ data, filters, studentId }: { data: FinPage; filters: FinFilters; studentId: string }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const [busy, setBusy] = useState(false);
  const f = filters;
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const words = [data.scope.label, f.from && f.to ? (f.from === f.to ? f.from : `${f.from} → ${f.to}`) : f.preset ? PRESETS.find((p) => p.key === f.preset)?.label : "any date",
    data.filters.session ? `session ${data.filters.session}` : "all sessions", f.types ? `types ${f.types}` : "all payment types", f.sex ? sexWord(f.sex) : null,
    f.fac || null, f.dept || null, f.prog || null, f.level ? `${f.level} Level` : null, f.entry ? entryWord(f.entry) : null, f.channel || null,
    studentId ? "one student" : null, f.q ? `search “${f.q}”` : null].filter(Boolean).join(" · ");
  const go = (extra: Record<string, string | number | undefined>) => queryNav(`/finance/analytics/transactions?${finQuery(f, { studentId: studentId || undefined, ...extra })}`);
  const sum = data.rows.reduce((s, r) => s + Number(r.amount), 0);

  async function allRows(): Promise<FinTransaction[]> {
    const out: FinTransaction[] = [];
    for (let page = 0; page * 500 < data.total && page < 200; page++) {
      const r = await fetch(`/api/bff/api/v1/analytics/finance/transactions?${finQuery(f, { page, size: 500, studentId: studentId || undefined }, true)}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as FinPage;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return out;
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = await allRows();
      const serial = docSerial("FIN");
      const title = "Payment Transactions — Financial Analytics";
      const body = rows.map((r, i) => line(r, i + 1));
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body, { sheetName: "Transactions", serial, sub: words }), `payment-transactions-${serial}.xlsx`);
      else brandedPrint(title, words, HEAD, body, serial);
      notify("Financial report generated successfully.");
    } catch (e) { notifyProblem((e as Problem) ?? { status: 0, title: "Unable to load financial statistics. Please try again." }); }
    finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title="Payment transactions" description={`${words}. ${data.total.toLocaleString()} confirmed payment${data.total === 1 ? "" : "s"}, newest first`}
        actions={<><Btn kind="primary" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>{busy ? "Preparing…" : "Export Excel"}</Btn><Btn kind="secondary" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>Export PDF</Btn><LinkBtn href={`/finance/analytics?${finQuery(f)}`}>Back to analytics</LinkBtn></>} />
      <div className="scope">
        <div className="scope__f" style={{ flex: 2 }}><Field id="tx-q" label="Search">
          <input id="tx-q" className="ctl" value={q} placeholder="Name, matriculation or admission number, application number, JAMB number, reference, receipt" onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go({ q, page: 0 }); }} />
        </Field></div>
        <div className="scope__f"><Btn kind="secondary" onClick={() => go({ q, page: 0 })}>Search</Btn></div>
        {studentId ? <div className="scope__f"><LinkBtn kind="ghost" href={`/finance/analytics/transactions?${finQuery(f)}`}>All students</LinkBtn></div> : null}
      </div>
      {!data.total ? <Note kind="info" title="No payment records match the selected filters">Widen the date, the session or the payment types on the analytics page.</Note> : null}
      <Panel title={`Transactions ${data.page * data.size + 1}–${Math.min(data.total, (data.page + 1) * data.size)} of ${data.total.toLocaleString()}`} right={<span className="sub2">This page: {naira(sum)}</span>}>
        <DTable pageSize={0} cols={["S/N|num", "Reference", "Student", "Gender|mid", "Faculty / Department", "Programme", "Level|mid", "Entry|mid", "Session|mid", "Payment type", "Amount|num", "Paid on", "Channel", "|num"]} rows={data.rows.map((r, i) => [
          <span key="sn" className="tnum sub2">{data.page * data.size + i + 1}</span>,
          <span key="r" className="tnum">{r.reference}{r.receipt_no ? <div className="sub2">{r.receipt_no}</div> : null}</span>,
          <span key="s"><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{r.number ?? "—"}</div></span>,
          <span key="g">{sexWord(r.sex)}</span>,
          <span key="f">{r.faculty ?? "—"}<div className="sub2">{r.department ?? ""}</div></span>,
          <span key="p">{r.programme ?? "—"}</span>,
          <span key="l" className="tnum">{r.level ?? "—"}</span>,
          <span key="e">{entryWord(r.entry_mode)}</span>,
          <span key="ss" className="tnum">{r.session}</span>,
          <span key="c"><Pil kind="info">{r.category}</Pil>{r.purpose ? <div className="sub2">{r.purpose}</div> : null}</span>,
          <span key="a" className="tnum b600">{naira(r.amount)}</span>,
          <span key="d" className="sub2 tnum">{whenAt(r.confirmed_at)}</span>,
          <span key="ch" className="sub2">{r.channel ?? "—"}</span>,
          r.student_id ? <Link key="x" className="lnk" href={`/finance/analytics/transactions?${finQuery(f, { studentId: r.student_id })}`}>This student</Link> : <span key="x" />,
        ])} texts={data.rows.map((r) => `${r.reference} ${r.surname} ${r.number ?? ""}`)} />
        <PBody>
          <div className="row row--between">
            <span className="sub2">Page {data.page + 1} of {pages}</span>
            <span className="row row--inline row--tight">
              <Btn kind="ghost" size="sm" disabled={data.page === 0} onClick={() => go({ page: data.page - 1 })}>Previous</Btn>
              <Btn kind="ghost" size="sm" disabled={data.page + 1 >= pages} onClick={() => go({ page: data.page + 1 })}>Next</Btn>
            </span>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
