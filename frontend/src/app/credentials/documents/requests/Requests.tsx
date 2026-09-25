"use client";

/** The request queue (V262): filtered by stage, kind, payment, delivery, faculty, department, programme and session; searched on the
 *  server by name, ID, request or document number; exported with S/N first and names A–Z. */
import { useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { KIND, PAYMENT, STAGE, dayOf, naira } from "@/lib/documents";
import type { ReqFilters, ReqList } from "./page";

export function Requests({ list, filters }: { list: ReqList; filters: ReqFilters }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const rows = list.rows;
  const go = (next: Partial<ReqFilters>) => { const f = { ...filters, ...next, page: next.page ?? "" }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } if (next.dept !== undefined) f.prog = ""; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/credentials/documents/requests?${qs}`); };
  const faculties = [...new Map(list.options.map((o) => [o.faculty_code, o.faculty])).entries()].filter(([k]) => k);
  const depts = [...new Map(list.options.filter((o) => !filters.fac || o.faculty_code === filters.fac).map((o) => [o.dept_code, o.department])).entries()].filter(([k]) => k);
  const progs = [...new Map(list.options.filter((o) => (!filters.fac || o.faculty_code === filters.fac) && (!filters.dept || o.dept_code === filters.dept)).map((o) => [o.programme_code, o.programme])).entries()];
  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const scope = [filters.stage ? filters.stage.toLowerCase().replace(/_/g, " ") : "every request", filters.kind ? KIND[filters.kind]?.[0] : "", filters.payment, filters.delivery, filters.fac, filters.dept, filters.prog, filters.session, filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ");
  const HEAD = ["S/N", "Request Number", "Student ID", "Student Name", "Programme", "Faculty", "Department", "Transcript Type", "Session", "Payment Status", "Amount", "Request Status", "Delivery Method", "Request Date", "Due", "Document Number"];
  const body = () => rows.map((r, i) => [i + 1, r.ref, r.student_number, r.student_name, r.programme ?? "", r.faculty ?? "", r.department ?? "", r.kind_label, r.session ?? "", PAYMENT[r.payment_status]?.[0] ?? r.payment_status, Number(r.fee ?? 0), STAGE[r.stage]?.[0] ?? r.stage, r.delivery, dayOf(r.requested_at), r.sla_due_on ? dayOf(r.sla_due_on) : "", r.document_number ?? ""]);
  async function excel() { const blob = await brandedXlsx("Document Requests", HEAD, body(), { sheetName: "Requests", serial: docSerial("DOC"), sub: scope }); downloadBlob(blob, "document-requests.xlsx"); }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/credentials/documents">Documents office</Link><span>›</span><strong>Requests</strong></div>
      <PageHead title="Document requests" description={`${scope}. ${list.total.toLocaleString()} request(s); names A–Z.`}
        actions={<><Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Download Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Document Requests", scope, HEAD, body(), docSerial("DOC"))} disabled={!rows.length}>Download PDF</Btn><LinkBtn kind="ghost" href="/credentials/documents">Back to the office</LinkBtn></>} />
      <div className="scope">
        <div className="scope__f"><Field id="rf-stage" label="Stage"><select id="rf-stage" className="ctl" value={filters.stage} onChange={(e) => go({ stage: e.target.value })}><option value="">Every stage</option><option value="OPEN">Open</option><option value="NEW">New (paid, not started)</option><option value="BREACHING">Breaching SLA</option>{Object.entries(STAGE).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="rf-kind" label="Document"><select id="rf-kind" className="ctl" value={filters.kind} onChange={(e) => go({ kind: e.target.value })}><option value="">Every kind</option>{["TRANSCRIPT", "SESSIONAL_TRANSCRIPT", "MINI_TRANSCRIPT", "ACADEMIC_STATEMENT"].map((k) => <option key={k} value={k}>{KIND[k][0]}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="rf-pay" label="Payment"><select id="rf-pay" className="ctl" value={filters.payment} onChange={(e) => go({ payment: e.target.value })}><option value="">Any</option><option value="PAID">Paid</option><option value="PENDING">Pending</option><option value="UNPAID">Unpaid</option><option value="FREE">No fee</option></select></Field></div>
        <div className="scope__f"><Field id="rf-dl" label="Delivery"><select id="rf-dl" className="ctl" value={filters.delivery} onChange={(e) => go({ delivery: e.target.value })}><option value="">Any</option><option value="DIGITAL">Digital</option><option value="PHYSICAL">Physical</option><option value="BOTH">Both</option></select></Field></div>
        <div className="scope__f"><Field id="rf-fac" label="Faculty"><select id="rf-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">Every faculty</option>{faculties.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="rf-dept" label="Department"><select id="rf-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">Every department</option>{depts.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="rf-prog" label="Programme"><select id="rf-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">Every programme</option>{progs.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field></div>
        <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><Field id="rf-q" label="Search"><input id="rf-q" className="ctl" placeholder="Name, student ID, request, document number or code" value={q} onChange={(e) => setQ(e.target.value)} /></Field><Btn kind="secondary" type="submit">Search</Btn></form>
      </div>
      <Panel title={`${list.total.toLocaleString()} request(s)`} right={pages > 1 ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => go({ page: String(list.page - 1) })} disabled={list.page <= 0}>Previous</Btn><span className="sub2">Page {list.page + 1} of {pages}</span><Btn kind="ghost" onClick={() => go({ page: String(list.page + 1) })} disabled={list.page + 1 >= pages}>Next</Btn></span> : "Names A–Z"}>
        {rows.length ? <DTable pageSize={0} cols={["S/N|num", "Request|mid", "Student", "Programme", "Document", "Payment|mid", "Stage|mid", "Delivery|mid", "Requested|mid", "|num"]} rows={rows.map((r, i) => [
          <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
          <span key="r"><Link className="lnk tnum b600" href={`/credentials/documents/requests/${r.id}`}>{r.ref}</Link>{r.breaching ? <div><Pil kind="bad">SLA</Pil></div> : r.sla_due_on ? <div className="sub2 tnum">due {dayOf(r.sla_due_on)}</div> : null}</span>,
          <span key="s"><strong>{r.student_name}</strong><div className="sub2 tnum">{r.student_number} · {r.student_status.toLowerCase()}</div></span>,
          <span key="p">{r.programme ?? "—"}<div className="sub2">{r.department ?? "—"} · {r.faculty ?? "—"}</div></span>,
          <span key="k">{r.kind_label}{r.session ? <div className="sub2">{r.session}{r.semester ? ` · semester ${r.semester}` : ""}</div> : null}{r.document_number ? <div className="sub2 tnum">{r.document_number}{r.document_version && r.document_version > 1 ? ` v${r.document_version}` : ""}</div> : null}</span>,
          <span key="pay"><Pil kind={PAYMENT[r.payment_status]?.[1] ?? "grey"}>{PAYMENT[r.payment_status]?.[0] ?? r.payment_status}</Pil>{r.fee ? <div className="sub2 tnum">{naira(r.fee)}</div> : null}</span>,
          <Pil key="st" kind={STAGE[r.stage]?.[1] ?? "grey"}>{STAGE[r.stage]?.[0] ?? r.stage}</Pil>,
          <span key="dl" className="sub2">{r.delivery.toLowerCase()}{r.express ? " · urgent" : ""}{r.destination !== "SELF" ? <div>{r.destination_name}</div> : null}</span>,
          <span key="d" className="tnum sub2">{dayOf(r.requested_at)}</span>,
          <LinkBtn key="o" href={`/credentials/documents/requests/${r.id}`} size="sm" kind={["READY", "HELD_AT_CLEARANCE", "PROCESSING", "GENERATED", "VERIFIED", "CORRECTION", "RELEASED"].includes(r.stage) ? "primary" : "ghost"}>{["READY", "PROCESSING", "CORRECTION"].includes(r.stage) ? "Process" : r.stage === "GENERATED" ? "Check" : r.stage === "VERIFIED" ? "Release" : r.stage === "RELEASED" ? "Deliver" : "Open"}</LinkBtn>,
        ])} texts={rows.map((r) => `${r.student_name} ${r.student_number} ${r.ref} ${r.kind_label} ${r.stage}`)} /> : <PBody><div className="sub2">No request matches. Widen the filters.</div></PBody>}
      </Panel>
    </>
  );
}
