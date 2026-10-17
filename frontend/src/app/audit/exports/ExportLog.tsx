"use client";

/**
 * V523: the export log, for Internal Audit — every report the portal's export engine handed someone (an Excel workbook, or a
 * print / PDF), recorded as it was made for the person and the office they acted in, with the report, the rows, the filters it was
 * drawn with, the screen and the serial printed on the document. Nothing in it is changed or taken out. V529: an export is unusual
 * when it is large or one of many by the same person in a short time (the watch, set here by Internal Audit or super); Internal
 * Audit is told of it as it is made, and the list marks and finds it.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { officeLabel } from "@/lib/offices";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface ExportRow {
  id: string; at: string; person_id: string; name: string | null; number: string | null; office: string; office_label: string | null;
  report: string; format: "XLSX" | "PRINT" | "PDF" | "CSV"; row_count: number; filters: string | null; screen: string | null; serial: string | null;
  large: boolean; burst: boolean;
}

export interface ExportWatch {
  enabled: boolean; large_rows: number; burst_count: number; burst_minutes: number;
  updated_at: string | null; updated_office: string | null; updated_by_name: string | null;
}

export interface ExportLogView {
  rows: ExportRow[]; total: number; page: number; size: number;
  offices: { code: string; label: string; exports: number }[];
  watch: ExportWatch;
}

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const formatLabel = (f: string) => (f === "PRINT" ? "Print / PDF" : f === "PDF" ? "PDF" : f === "CSV" ? "CSV" : "Excel");

/** why an export is unusual, in a word or two */
export function unusualLine(e: Pick<ExportRow, "large" | "burst">): string {
  return [e.large ? "Large" : null, e.burst ? "Many in a short time" : null].filter(Boolean).join(" · ");
}

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

/** V529: what makes an export unusual — set by Internal Audit or super, read by the Deputy Director of Audit */
function WatchPanel({ watch, maySet }: { watch: ExportWatch; maySet: boolean }) {
  const router = useRouter();
  const [w, setW] = useState({ enabled: watch.enabled, largeRows: String(watch.large_rows), burstCount: String(watch.burst_count), burstMinutes: String(watch.burst_minutes) });
  const [why, setWhy] = useState("");
  const changed = w.enabled !== watch.enabled || Number(w.largeRows) !== watch.large_rows || Number(w.burstCount) !== watch.burst_count || Number(w.burstMinutes) !== watch.burst_minutes;
  async function save() {
    const r = await fetch("/api/bff/api/v1/exports/watch", {
      method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why.trim()) },
      body: JSON.stringify({ enabled: w.enabled, largeRows: Number(w.largeRows), burstCount: Number(w.burstCount), burstMinutes: Number(w.burstMinutes) }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify("The export watch is set");
    setWhy("");
    router.refresh();
  }
  const digits = (x: string) => x.replace(/[^0-9]/g, "");
  return (
    <Panel title="When an export is unusual" right={watch.updated_at ? <span className="sub2">Set {when(watch.updated_at)}{watch.updated_by_name ? ` by ${watch.updated_by_name}` : ""}</span> : null}>
      <PBody>
        <div className="sub2">Internal Audit is told, by e-mail and on the portal, of an export of at least the rows below, or when a person&apos;s exports reach the number below within the minutes below; once each. The person who made it is not told, and nothing is stopped.</div>
        <div className="row row--end mt-2" style={{ flexWrap: "wrap", gap: 12 }}>
          <Field id="ew-on" label="Watch"><select id="ew-on" className="ctl" disabled={!maySet} value={w.enabled ? "on" : "off"} onChange={(e) => setW({ ...w, enabled: e.target.value === "on" })}><option value="on">On</option><option value="off">Off</option></select></Field>
          <Field id="ew-rows" label="Large export: rows"><input id="ew-rows" className="ctl tnum" inputMode="numeric" disabled={!maySet} value={w.largeRows} onChange={(e) => setW({ ...w, largeRows: digits(e.target.value) })} /></Field>
          <Field id="ew-count" label="Many exports: number"><input id="ew-count" className="ctl tnum" inputMode="numeric" disabled={!maySet} value={w.burstCount} onChange={(e) => setW({ ...w, burstCount: digits(e.target.value) })} /></Field>
          <Field id="ew-mins" label="Within minutes"><input id="ew-mins" className="ctl tnum" inputMode="numeric" disabled={!maySet} value={w.burstMinutes} onChange={(e) => setW({ ...w, burstMinutes: digits(e.target.value) })} /></Field>
          {maySet ? <div style={{ minWidth: 220, flex: 1 }}><Field id="ew-why" label="Why it changes"><input id="ew-why" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} /></Field></div> : null}
          {maySet ? <Btn kind="primary" disabled={!changed || why.trim().length < 5} onClick={() => save()}>Save</Btn> : <span className="sub2">Set by the Director of Internal Audit</span>}
        </div>
      </PBody>
    </Panel>
  );
}

export function ExportLog({ d, filters, maySet }: { d: ExportLogView; filters: Record<string, string>; maySet: boolean }) {
  const router = useRouter();
  const [v, setV] = useState<Record<string, string>>({ from: filters.from ?? "", to: filters.to ?? "", office: filters.office ?? "", format: filters.format ?? "", q: filters.q ?? "", unusual: filters.unusual ?? "" });
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
    const head = ["When", "Person", "Number", "Office", "Report", "Format", "Rows", "Unusual", "Filters", "Screen", "Serial"];
    const meta: [string, string][] = Object.entries(filters).filter(([k]) => k !== "page").map(([k, val]) => [k === "q" ? "Search" : k[0].toUpperCase() + k.slice(1), val]);
    downloadBlob(await brandedXlsx("Export Log", head, all.map((e) => [when(e.at), e.name ?? "", e.number ?? "", e.office_label ?? officeLabel(e.office), e.report,
      formatLabel(e.format), e.row_count, unusualLine(e), filtersLine(e.filters), e.screen ?? "", e.serial ?? ""]), { sheetName: "Export log", serial: docSerial("EXL"), meta }),
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
            <option value="PDF">PDF (built by the portal)</option>
            <option value="CSV">CSV</option>
          </select></Field></div>
        <div style={{ minWidth: 150 }}><Field id="ex-unusual" label="Which">
          <select id="ex-unusual" className="ctl" value={v.unusual} onChange={(e) => setV({ ...v, unusual: e.target.value })}>
            <option value="">Every export</option>
            <option value="1">Unusual only</option>
          </select></Field></div>
        <div style={{ minWidth: 220, flex: 1 }}><Field id="ex-q" label="Search">
          <input id="ex-q" className="ctl" value={v.q} placeholder="Report, person, number, screen or serial"
                 onChange={(e) => setV({ ...v, q: e.target.value })} onKeyDown={(e) => { if (e.key === "Enter") go(v); }} /></Field></div>
        <Btn kind="primary" onClick={() => go(v)}>Search</Btn>
        {filtered ? <Btn kind="ghost" onClick={() => { setV({ from: "", to: "", office: "", format: "", q: "", unusual: "" }); go({}); }}>Clear</Btn> : null}
      </div></div>

      <Panel title="Exports" right={
        <span className="row" style={{ gap: 8, alignItems: "center" }}>
          <span className="sub2">{d.total.toLocaleString()} {d.total === 1 ? "export" : "exports"}{filtered ? " · filtered" : ""}</span>
          <Btn kind="ghost" size="sm" disabled={!d.total} busyLabel="Preparing Excel…" onClick={() => excel()}>Excel</Btn>
        </span>}>
        {d.rows.length ? (
          <DTable pageSize={0} cols={["When|mid", "Person", "Report", "Format|mid", "Rows|num", "Unusual", "Filters", "Serial"]} rows={d.rows.map((e) => [
            <span className="tnum sub2" key="w">{when(e.at)}</span>,
            <Two key="p" a={e.name ?? "—"} b={`${e.number ? e.number + " · " : ""}${e.office_label ?? officeLabel(e.office)}`} />,
            <Two key="r" a={e.report} b={e.screen ?? ""} />,
            <Pil key="f" kind={e.format === "PRINT" ? "grey" : "info"}>{formatLabel(e.format)}</Pil>,
            <span className="tnum" key="n">{e.row_count.toLocaleString()}</span>,
            e.large || e.burst ? <Pil key="u" kind="warn">{unusualLine(e)}</Pil> : <span key="u" className="sub2">—</span>,
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

      <WatchPanel watch={d.watch} maySet={maySet} />
    </>
  );
}
