"use client";

/** The applicants behind a stage of the admission funnel (V279): the stage as a breadcrumb, the other stages a
 *  click away, search on the server, fifty a page names A–Z, and the whole set as a branded workbook or PDF with
 *  S/N first. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { entryWord, sexWord } from "@/lib/stats";
import type { Problem } from "@/lib/api";

export interface FunnelRow {
  session: string; application_no: string | null; surname: string; other_names: string; jamb_reg_no: string | null; programme: string | null; entry_mode: string | null; sex: string | null;
  faculty: string | null; department: string | null; student_id: string | null; admission_no: string | null; matric_no: string | null;
  fee_paid: boolean; admitted: boolean; checking_paid?: boolean; accepted: boolean; screening_submitted?: boolean; screening_ok?: boolean; on_register: boolean; fees_paid?: boolean; registered?: boolean; matriculated?: boolean;
  fee_confirmed_at: string | null; decision_released_at: string | null; accepted_at: string | null; cleared_at: string | null;
}
export interface FunnelPage { scope: { kind: string; label: string; pg: boolean }; session: string; stage: string; label: string; total: number; page: number; size: number; rows: FunnelRow[] }
type Params = { session: string; stage: string; fac: string; dept: string; prog: string; sex: string; entry: string; q: string };

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "");
const UG_STAGES = ["applied", "fee_paid", "admitted", "checking_paid", "accepted", "screening_submitted", "screening_ok", "on_register", "fees_paid", "registered", "matriculated"];
const PG_STAGES = ["applied", "fee_paid", "submitted", "dept_decided", "admitted", "checking_paid", "accepted", "on_register"];
const WORD: Record<string, string> = { applied: "Applications", fee_paid: "Application fee paid", admitted: "Admitted", checking_paid: "Checking fee paid", accepted: "Acceptance paid", screening_submitted: "Screening submitted",
  screening_ok: "Screening successful", on_register: "On the register", fees_paid: "School fees paid", registered: "Courses registered", matriculated: "Matriculated", submitted: "Submitted", dept_decided: "Department decided" };

export function FunnelRows({ data, params }: { data: FunnelPage; params: Params }) {
  const queryNav = useQueryNav();
  const [q, setQ] = useState(params.q);
  const [busy, setBusy] = useState(false);
  const pages = Math.max(1, Math.ceil(data.total / data.size));
  const go = (extra: Partial<Params> & { page?: number }) => {
    const u = new URLSearchParams();
    const n = { ...params, session: data.session, stage: data.stage, ...extra };
    for (const [k, v] of Object.entries(n)) if (v !== "" && v !== undefined && v !== null && k !== "page") u.set(k, String(v));
    if (extra.page) u.set("page", String(extra.page));
    queryNav(`/stats/funnel?${u.toString()}`);
  };
  const words = [data.scope.label, data.session, data.label, params.fac || null, params.dept || null, params.prog || null, params.sex ? sexWord(params.sex) : null, params.entry ? entryWord(params.entry) : null, params.q ? `search “${params.q}”` : null].filter(Boolean).join(" · ");
  const HEAD = ["S/N", "Applicant", "Application No", "JAMB Reg No", "Gender", "Faculty", "Department", "Programme", "Entry Type", "Session", "Application Fee", "Admitted", "Accepted", "On Register", "Admission No", "Matric No"];
  const line = (r: FunnelRow, sn: number) => [sn, `${r.surname}, ${r.other_names}`, r.application_no ?? "", r.jamb_reg_no ?? "", sexWord(r.sex), r.faculty ?? "", r.department ?? "", r.programme ?? "", entryWord(r.entry_mode), r.session,
    r.fee_paid ? day(r.fee_confirmed_at) || "Yes" : "No", r.admitted ? day(r.decision_released_at) || "Yes" : "No", r.accepted ? day(r.accepted_at) || "Yes" : "No", r.on_register ? "Yes" : "No", r.admission_no ?? "", r.matric_no ?? ""];
  const apiQuery = (page: number, size: number) => { const u = new URLSearchParams(); for (const [k, v] of Object.entries({ ...params, session: data.session, stage: data.stage })) if (v) u.set(k, v); u.set("page", String(page)); u.set("size", String(size)); return u.toString(); };
  async function allRows(): Promise<FunnelRow[]> {
    const out: FunnelRow[] = [];
    for (let page = 0; page * 500 < data.total && page < 100; page++) {
      const r = await fetch(`/api/bff/api/v1/analytics/admissions/funnel/rows?${apiQuery(page, 500)}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as FunnelPage;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return out;
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = await allRows();
      const serial = docSerial("ADM");
      const title = `${data.label} — Admission Funnel`;
      const body = rows.map((r, i) => line(r, i + 1));
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, HEAD, body, { sheetName: data.label.slice(0, 31), serial, sub: words }), `admission-${data.stage}-${serial}.xlsx`);
      else brandedPrint(title, words, HEAD, body, serial);
      notify("Report generated successfully.");
    } catch (e) { notifyProblem((e as Problem) ?? { status: 0, title: "Unable to load the applicants. Please try again." }); }
    finally { setBusy(false); }
  }
  const stages = data.scope.pg ? PG_STAGES : UG_STAGES;
  return (
    <>
      <PageHead title={`${data.label} · Admission funnel`} description={`${words}. ${data.total.toLocaleString()} applicant${data.total === 1 ? "" : "s"} at this stage, names A–Z.`}
        actions={<><Btn kind="primary" disabled={busy || !data.total} onClick={() => void exportAs("xlsx")}>{busy ? "Preparing…" : "Export Excel"}</Btn><Btn kind="secondary" disabled={busy || !data.total} onClick={() => void exportAs("pdf")}>Export PDF</Btn><LinkBtn href={`/stats?session=${encodeURIComponent(data.session)}`}>Student Statistics</LinkBtn></>} />
      <div className="row row--tight mb-2" style={{ flexWrap: "wrap", gap: 6 }}>
        {stages.map((s) => <button key={s} type="button" className={`btn btn--sm ${s === data.stage ? "btn--primary" : "btn--ghost"}`} onClick={() => go({ stage: s })}>{WORD[s] ?? s}</button>)}
      </div>
      <div className="scope">
        <div className="scope__f" style={{ flex: 2 }}><Field id="fn-q" label="Search"><input id="fn-q" className="ctl" value={q} placeholder="Name, JAMB number, application number" onChange={(e) => setQ(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go({ q }); }} /></Field></div>
        <div className="scope__f"><Btn kind="secondary" onClick={() => go({ q })}>Search</Btn></div>
      </div>
      {!data.total ? <Note kind="info" title="No applicant is at this stage within the filters">Choose another stage or widen the filters.</Note> : null}
      <Panel title={`${data.page * data.size + 1}–${Math.min(data.total, (data.page + 1) * data.size)} of ${data.total.toLocaleString()}`}>
        <DTable pageSize={0} cols={["S/N|num", "Applicant", "Numbers", "Gender|mid", "Programme", "Faculty / Department", "Entry|mid", "Fee|mid", "Admitted|mid", "Accepted|mid", "Register|mid"]} rows={data.rows.map((r, i) => [
          <span key="sn" className="tnum sub2">{data.page * data.size + i + 1}</span>,
          <span key="n"><b>{r.surname}, {r.other_names}</b></span>,
          <span key="no" className="tnum sub2">{r.application_no ?? ""}{r.jamb_reg_no ? <div>{r.jamb_reg_no}</div> : null}{r.admission_no ? <div>{r.admission_no}</div> : null}{r.matric_no ? <div>{r.matric_no}</div> : null}</span>,
          <span key="g">{sexWord(r.sex)}</span>,
          <span key="p">{r.programme ?? "—"}</span>,
          <span key="f">{r.faculty ?? "—"}<div className="sub2">{r.department ?? ""}</div></span>,
          <span key="e">{entryWord(r.entry_mode)}</span>,
          <Pil key="fee" kind={r.fee_paid ? "ok" : "grey"}>{r.fee_paid ? day(r.fee_confirmed_at) || "Paid" : "—"}</Pil>,
          <Pil key="adm" kind={r.admitted ? "ok" : "grey"}>{r.admitted ? day(r.decision_released_at) || "Yes" : "—"}</Pil>,
          <Pil key="acc" kind={r.accepted ? "ok" : "grey"}>{r.accepted ? day(r.accepted_at) || "Yes" : "—"}</Pil>,
          <Pil key="reg" kind={r.on_register ? "ok" : "grey"}>{r.on_register ? (r.matriculated ? "Matriculated" : "Yes") : "—"}</Pil>,
        ])} texts={data.rows.map((r) => `${r.surname} ${r.other_names} ${r.application_no ?? ""} ${r.jamb_reg_no ?? ""}`)} />
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
