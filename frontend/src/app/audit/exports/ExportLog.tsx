"use client";

/**
 * V523: the export log, for Internal Audit — every report the portal's export engine handed someone (an Excel workbook, or a
 * print / PDF), recorded as it was made for the person and the office they acted in, with the report, the rows, the filters it was
 * drawn with, the screen and the serial printed on the document. Nothing in it is changed or taken out.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notifyProblem } from "@/components/proto/Toast";
import { officeLabel } from "@/lib/offices";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface ExportRow {
  id: string; at: string; person_id: string; name: string | null; number: string | null; office: string; office_label: string | null;
  report: string; format: "XLSX" | "PRINT"; row_count: number; filters: string | null; screen: string | null; serial: string | null;
}

export interface ExportLogView {
  rows: ExportRow[]; total: number; page: number; size: number;
  offices: { code: string; label: string; exports: number }[];
}

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const formatLabel = (f: string) => (f === "PRINT" ? "Print / PDF" : "Excel");

/** the filters as "Session: 2025/2026 · Faculty: Science" */
export function filtersLine(raw: string | null): string {
  if (!raw) return "";
  try {
    const o = JSON.parse(raw) as Record<string, unknown>;
    return Object.entries(o).map(([k, v]) => `${k}: ${String(v)}`).join(" · ");
  } catch {
    return raw;
  }
}

export function ExportLog({ d, filters }: { d: ExportLogView; filters: Record<string, string> }) {
  const router = useRouter();
  const [v, setV] = useState<Record<string, string>>({ from: filters.from ?? "", to: filters.to ?? "", office: filters.office ?? "", format: filters.format ?? "", q: filters.q ?? "" });
  const pages = Math.max(1, Math.ceil(d.total / d.size));

  function go(next: Record<string, string>, page = 1) {
    const q = new URLSearchParams();
    for (const [k, val] of Object.entries(next)) if (val && val.trim()) q.set(k, val.trim());
    if (page > 1) q.set("page", String(page));
    router.push(`/audit/exports${q.toString() ? `?${q.toString()}` : ""}`);
  }

  async function excel() {
    // every matched entry, 500 a page, up to 20,000
    const all: ExportRow[] = [];
    const base = new URLSearchParams();
    for (const [k, val] of Object.entries(filters)) if (k !== "page" && val) base.set(k, val);
    for (let p = 1; all.length < Math.min(d.total, 20000); p++) {
      const q = new URLSearchParams(base);
      q.set("page", String(p));
      q.set("size", "500");
      const r = await fetch(`/api/bff/api/v1/exports?${q.toString()}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const rows = (j as ExportLogView).rows;
      if (!rows.length) break;
      all.push(...rows);
    }
    const head = ["When", "Person", "Number", "Office", "Report", "Format", "Rows", "Filters", "Screen", "Serial"];
    const meta: [string, string][] = Object.entries(filters).filter(([k]) => k !== "page").map(([k, val]) => [k === "q" ? "Search" : k[0].toUpperCase() + k.slice(1), val]);
    downloadBlob(await brandedXlsx("Export Log", head, all.map((e) => [when(e.at), e.name ?? "", e.number ?? "", e.office_label ?? officeLabel(e.office), e.report,
      formatLabel(e.format), e.row_count, filtersLine(e.filters), e.screen ?? "", e.serial ?? ""]), { sheetName: "Export log", serial: docSerial("EXL"), meta }),
      `export-log-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  const applied = Object.fromEntries(Object.entries(filters).filter(([k]) => k !== "page"));
  const filtered = Object.keys(applied).length > 0;

  return (
    <>
      <Note kind="info" title="Every report exported from the portal">
        Each Excel workbook and each print or PDF made through the portal&apos;s export engine is recorded as it is made: who made it, the office
        they acted in, the report, the rows, the filters and the serial printed on the document. A copy found anywhere can be traced by its serial.
        The log cannot be changed or emptied.
      </Note>

      <div className="card"><div className="card__body row row--end">
        <div style={{ minWidth: 150 }}><Field id="ex-from" label="From">
          <input id="ex-from" className="ctl" type="date" value={v.from} onChange={(e) => setV({ ...v, from: e.target.value })} /></Field></div>
        <div style={{ minWidth: 150 }}><Field id="ex-to" label="To">
          <input id="ex-to" className="ctl" type="date" value={v.to} onChange={(e) => setV({ ...v, to: e.target.value })} /></Field></div>
        <div style={{ minWidth: 200 }}><Field id="ex-office" label="Office">
          <select id="ex-office" className="ctl" value={v.office} onChange={(e) => setV({ ...v, office: e.target.value })}>
            <option value="">All offices</option>
            {d.offices.map((o) => <option key={o.code} value={o.code}>{officeLabel(o.code) || o.label} ({o.exports})</option>)}
          </select></Field></div>
        <div style={{ minWidth: 140 }}><Field id="ex-format" label="Format">
          <select id="ex-format" className="ctl" value={v.format} onChange={(e) => setV({ ...v, format: e.target.value })}>
            <option value="">Excel and print</option>
            <option value="XLSX">Excel</option>
            <option value="PRINT">Print / PDF</option>
          </select></Field></div>
        <div style={{ minWidth: 220, flex: 1 }}><Field id="ex-q" label="Search">
          <input id="ex-q" className="ctl" value={v.q} placeholder="Report, person, number, screen or serial"
                 onChange={(e) => setV({ ...v, q: e.target.value })} onKeyDown={(e) => { if (e.key === "Enter") go(v); }} /></Field></div>
        <Btn kind="primary" onClick={() => go(v)}>Search</Btn>
        {filtered ? <Btn kind="ghost" onClick={() => { setV({ from: "", to: "", office: "", format: "", q: "" }); go({}); }}>Clear</Btn> : null}
      </div></div>

      <Panel title="Exports" right={
        <span className="row" style={{ gap: 8, alignItems: "center" }}>
          <span className="sub2">{d.total.toLocaleString()} {d.total === 1 ? "export" : "exports"}{filtered ? " · filtered" : ""}</span>
          <Btn kind="ghost" size="sm" disabled={!d.total} busyLabel="Preparing Excel…" onClick={() => excel()}>Excel</Btn>
        </span>}>
        {d.rows.length ? (
          <DTable pageSize={0} cols={["When|mid", "Person", "Report", "Format|mid", "Rows|num", "Filters", "Serial"]} rows={d.rows.map((e) => [
            <span className="tnum sub2" key="w">{when(e.at)}</span>,
            <Two key="p" a={e.name ?? "—"} b={`${e.number ? e.number + " · " : ""}${e.office_label ?? officeLabel(e.office)}`} />,
            <Two key="r" a={e.report} b={e.screen ?? ""} />,
            <Pil key="f" kind={e.format === "PRINT" ? "grey" : "info"}>{formatLabel(e.format)}</Pil>,
            <span className="tnum" key="n">{e.row_count.toLocaleString()}</span>,
            <span className="sub2" key="fl">{filtersLine(e.filters) || "—"}</span>,
            <span className="tnum sub2" key="s">{e.serial ?? "—"}</span>,
          ])} texts={d.rows.map((e) => `${e.name ?? ""} ${e.number ?? ""} ${e.report} ${e.serial ?? ""}`)} />
        ) : <PBody><div className="sub2">{filtered ? "No export matches these filters." : "Nothing has been exported yet."}</div></PBody>}
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
