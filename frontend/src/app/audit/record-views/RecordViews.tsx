"use client";

/**
 * V530: who opened a student's record, for Internal Audit — each time an office opened a student's record (the student record,
 * or ICT Support's record of the student), with the person, the office and when; once for each person, office and record within
 * ten minutes. The student sees which office opened their record and when; the person's name is Internal Audit's to read.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notifyProblem } from "@/components/proto/Toast";
import { officeLabel } from "@/lib/offices";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface RecordViewRow {
  id: string; at: string; record: "STUDENT_RECORD" | "SUPPORT_RECORD"; office: string; office_label: string | null;
  viewer_id: string; viewer: string | null; staff_number: string | null; student_id: string; student: string; number: string | null;
}

export interface RecordViewsData {
  rows: RecordViewRow[]; total: number; page: number; size: number;
  offices: { code: string; label: string; views: number }[];
}

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
export const recordLabel = (r: string) => (r === "SUPPORT_RECORD" ? "ICT Support's record" : "Student record");

export function RecordViews({ d, filters }: { d: RecordViewsData; filters: Record<string, string> }) {
  const router = useRouter();
  const [v, setV] = useState<Record<string, string>>({ from: filters.from ?? "", to: filters.to ?? "", office: filters.office ?? "", q: filters.q ?? "" });
  const applied = Object.fromEntries(Object.entries(filters).filter(([k]) => k !== "page"));
  const filtered = Object.keys(applied).length > 0;
  const pages = Math.max(1, Math.ceil(d.total / d.size));

  function go(next: Record<string, string>, page = 1) {
    const q = new URLSearchParams();
    for (const [k, val] of Object.entries(next)) if (val && val.trim()) q.set(k, val.trim());
    if (page > 1) q.set("page", String(page));
    router.push(`/audit/record-views${q.toString() ? `?${q.toString()}` : ""}`);
  }

  async function excel() {
    // every matched view, 500 a page, up to 20,000
    const all: RecordViewRow[] = [];
    for (let p = 1; all.length < Math.min(d.total, 20000); p++) {
      const q = new URLSearchParams(applied);
      q.set("page", String(p));
      q.set("size", "500");
      const r = await fetch(`/api/bff/api/v1/audit/record-views?${q.toString()}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const rows = (j as RecordViewsData).rows;
      if (!rows.length) break;
      all.push(...rows);
    }
    const meta: [string, string][] = Object.entries(applied).map(([k, val]) => [k === "q" ? "Search" : k[0].toUpperCase() + k.slice(1), val]);
    downloadBlob(await brandedXlsx("Record Views", ["When", "Student", "Number", "Record", "Opened by", "Staff number", "Office"],
      all.map((x) => [when(x.at), x.student, x.number ?? "", recordLabel(x.record), x.viewer ?? "", x.staff_number ?? "", x.office_label ?? officeLabel(x.office)]),
      { sheetName: "Record views", serial: docSerial("RCV"), meta }), `record-views-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  return (
    <>
      <Note kind="info" title="Who opened a student's record">
        Each time an office opened a student&apos;s record, or ICT Support its record of the student, with the person and when: once for each
        person, office and record within ten minutes. The student sees which office opened their record and when, not the person&apos;s name.
        The log cannot be changed.
      </Note>

      <div className="card"><div className="card__body row row--end">
        <div style={{ minWidth: 150 }}><Field id="rv-from" label="From">
          <input id="rv-from" className="ctl" type="date" value={v.from} onChange={(e) => setV({ ...v, from: e.target.value })} /></Field></div>
        <div style={{ minWidth: 150 }}><Field id="rv-to" label="To">
          <input id="rv-to" className="ctl" type="date" value={v.to} onChange={(e) => setV({ ...v, to: e.target.value })} /></Field></div>
        <div style={{ minWidth: 200 }}><Field id="rv-office" label="Office">
          <select id="rv-office" className="ctl" value={v.office} onChange={(e) => setV({ ...v, office: e.target.value })}>
            <option value="">All offices</option>
            {d.offices.map((o) => <option key={o.code} value={o.code}>{officeLabel(o.code) || o.label} ({o.views})</option>)}
          </select></Field></div>
        <div style={{ minWidth: 220, flex: 1 }}><Field id="rv-q" label="Search">
          <input id="rv-q" className="ctl" value={v.q} placeholder="Student or officer: name or number"
                 onChange={(e) => setV({ ...v, q: e.target.value })} onKeyDown={(e) => { if (e.key === "Enter") go(v); }} /></Field></div>
        <Btn kind="primary" onClick={() => go(v)}>Search</Btn>
        {filtered ? <Btn kind="ghost" onClick={() => { setV({ from: "", to: "", office: "", q: "" }); go({}); }}>Clear</Btn> : null}
      </div></div>

      <Panel title="Records opened" right={
        <span className="row" style={{ gap: 8, alignItems: "center" }}>
          <span className="sub2">{d.total.toLocaleString()} {d.total === 1 ? "view" : "views"}{filtered ? " · filtered" : ""}</span>
          <Btn kind="ghost" size="sm" disabled={!d.total} busyLabel="Preparing Excel…" onClick={() => excel()}>Excel</Btn>
        </span>}>
        {d.rows.length ? (
          <DTable pageSize={0} cols={["When|mid", "Student", "Record", "Opened by", "Office"]} rows={d.rows.map((x) => [
            <span className="tnum sub2" key="w">{when(x.at)}</span>,
            <Two key="s" a={x.student} b={x.number ?? ""} />,
            <span key="r">{recordLabel(x.record)}</span>,
            <Two key="p" a={x.viewer ?? "—"} b={x.staff_number ?? ""} />,
            <span key="o">{x.office_label ?? officeLabel(x.office)}</span>,
          ])} texts={d.rows.map((x) => `${x.student} ${x.number ?? ""} ${x.viewer ?? ""} ${x.staff_number ?? ""}`)} />
        ) : <PBody><div className="sub2">{filtered ? "No view matches these filters." : "No student's record has been opened yet."}</div></PBody>}
        {pages > 1 ? (
          <PBody><div className="row" style={{ gap: 8, alignItems: "center" }}>
            <Btn kind="ghost" size="sm" disabled={d.page <= 1} onClick={() => go(applied, d.page - 1)}>Previous</Btn>
            <span className="sub2">Page {d.page} of {pages}</span>
            <Btn kind="ghost" size="sm" disabled={d.page >= pages} onClick={() => go(applied, d.page + 1)}>Next</Btn>
          </div></PBody>
        ) : null}
      </Panel>
    </>
  );
}
