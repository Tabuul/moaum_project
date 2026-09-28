"use client";

/** Import hostels and rooms (V290): the University's workbook read in the browser — every sheet found, the header row
 *  detected, each column mapped to a field, the rows previewed and validated on the server (NEW, EXISTING, UPDATED,
 *  DUPLICATE, ERROR) — then committed without duplicates. Re-uploading the same file changes nothing. */
import { useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { csvRows, xlsxWorkbook, type Sheet } from "@/lib/xlsx";
import { HOSTEL_OFFICERS, callHostel } from "@/lib/hostel";

const FIELDS: [string, string, RegExp][] = [
  ["hall_code", "Hostel code", /^(hostel|hall)[ _-]?(code|id)$|^code$/i],
  ["hall", "Hostel name", /^(hostel|hall)([ _-]?name)?$|^name$/i],
  ["block", "Block / wing", /^(block|wing)/i],
  ["floor", "Floor", /^floor|^level$/i],
  ["room", "Room number", /^room([ _-]?(no|number|name))?$/i],
  ["capacity", "Capacity (beds)", /^(capacity|beds?|bed[ _-]?space|spaces?|occupancy)$/i],
  ["category", "Category", /^(category|type of room|use|purpose|reserved)/i],
  ["room_type", "Room type", /^room[ _-]?type$/i],
  ["gender", "Gender", /^(gender|sex)$/i],
  ["hall_kind", "Hostel kind", /^(kind|hostel[ _-]?kind)$/i],
];
type Outcome = "NEW" | "EXISTING" | "UPDATED" | "DUPLICATE" | "ERROR";
interface PreviewRow { row_no: number; hall_code: string | null; hall_name: string | null; block: string | null; room_no: string | null; beds: number | null; category: string | null; room_type: string | null; sex: string | null; floor: number | null; outcome: Outcome; message: string }
interface Report { committed: boolean; received: number; counts: Record<Outcome, number>; rows: PreviewRow[] }
const TONE: Record<Outcome, "ok" | "grey" | "info" | "warn" | "bad"> = { NEW: "ok", EXISTING: "grey", UPDATED: "info", DUPLICATE: "warn", ERROR: "bad" };

function guessHeader(rows: string[][]): number {
  for (let i = 0; i < Math.min(rows.length, 15); i++) {
    const hits = rows[i].filter((c) => FIELDS.some(([, , re]) => re.test(c.trim()))).length;
    if (hits >= 2) return i;
  }
  return 0;
}

export function HostelImport({ office }: { office: string | null }) {
  const router = useRouter();
  const may = !!office && HOSTEL_OFFICERS.includes(office);
  const file = useRef<HTMLInputElement>(null);
  const [name, setName] = useState("");
  const [sheets, setSheets] = useState<Sheet[]>([]);
  const [sheet, setSheet] = useState(0);
  const [header, setHeader] = useState(0);
  const [map, setMap] = useState<Record<string, number>>({});
  const [report, setReport] = useState<Report | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const rows = sheets[sheet]?.rows ?? [];
  const head = rows[header] ?? [];
  const body = rows.slice(header + 1).filter((r) => r.some((c) => c.trim() !== ""));

  function autoMap(h: string[]) {
    const m: Record<string, number> = {};
    FIELDS.forEach(([k, , re]) => { const i = h.findIndex((c) => re.test(c.trim())); if (i >= 0) m[k] = i; });
    return m;
  }

  async function read(f: File) {
    setError(null); setReport(null); setName(f.name);
    try {
      const buf = await f.arrayBuffer();
      const found: Sheet[] = /\.csv$/i.test(f.name) ? [{ name: "CSV", rows: csvRows(new TextDecoder().decode(buf)) }] : await xlsxWorkbook(buf);
      if (!found.length) throw new Error("the file has no sheet in it");
      setSheets(found); setSheet(0);
      const h = guessHeader(found[0].rows); setHeader(h); setMap(autoMap(found[0].rows[h] ?? []));
    } catch (e) {
      setError(e instanceof Error ? e.message : "The file could not be read"); setSheets([]);
    }
  }
  function pickSheet(i: number) { setSheet(i); const h = guessHeader(sheets[i]?.rows ?? []); setHeader(h); setMap(autoMap(sheets[i]?.rows[h] ?? [])); setReport(null); }
  function pickHeader(i: number) { setHeader(i); setMap(autoMap(rows[i] ?? [])); setReport(null); }

  const records = () => body.map((r) => {
    const o: Record<string, string> = {};
    for (const [k] of FIELDS) { const i = map[k]; if (i !== undefined && i >= 0) o[k] = r[i] ?? ""; }
    return o;
  });
  const ready = map.room !== undefined && map.capacity !== undefined && (map.hall !== undefined || map.hall_code !== undefined);

  async function run(commit: boolean) {
    setBusy(true);
    try {
      const r = await callHostel<Report>("POST", commit ? "/hostel/import" : "/hostel/import/preview", { rows: records() }, commit ? `Hostels and rooms imported from ${name}` : `Hostel workbook previewed: ${name}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setReport(r.data);
      if (commit) { notify(`${r.data.counts.NEW} created · ${r.data.counts.UPDATED} updated · ${r.data.counts.EXISTING} already there`); router.refresh(); }
    } finally { setBusy(false); }
  }

  const c = report?.counts;
  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/hostel">Accommodation</Link><span>›</span><strong>Import hostels &amp; rooms</strong></div>
      <PageHead title="Import hostels and rooms" description="The University's workbook, read here: choose the sheet and the header row, check the mapping, preview what would change, then import. A room already on the record is updated, never duplicated." />
      {!may ? <Note kind="info" title="You are reading this desk">The Dean of Student Affairs and the housing desk import.</Note> : null}

      <Panel title="1 · The workbook" right=".xlsx or .csv">
        <PBody>
          <div className="row row--tight" style={{ gap: 12, alignItems: "flex-end" }}>
            <Field id="hi-file" label="File"><input id="hi-file" ref={file} type="file" accept=".xlsx,.csv" className="ctl" onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); }} disabled={!may} /></Field>
            {sheets.length > 1 ? <Field id="hi-sheet" label="Sheet"><select id="hi-sheet" className="ctl" value={sheet} onChange={(e) => pickSheet(Number(e.target.value))}>{sheets.map((s, i) => <option key={s.name} value={i}>{s.name} ({s.rows.length} rows)</option>)}</select></Field> : null}
            {rows.length ? <Field id="hi-head" label="Header row"><select id="hi-head" className="ctl" value={header} onChange={(e) => pickHeader(Number(e.target.value))}>{rows.slice(0, 15).map((r, i) => <option key={i} value={i}>Row {i + 1}: {r.slice(0, 5).join(" · ").slice(0, 60)}</option>)}</select></Field> : null}
          </div>
          {error ? <Note kind="bad" title="The file could not be read">{error}</Note> : null}
          {sheets.length ? <div className="sub2 mt-1">{name}: {sheets.length} sheet{sheets.length === 1 ? "" : "s"}, {body.length} data rows under the header on &ldquo;{sheets[sheet]?.name}&rdquo;.</div> : null}
        </PBody>
      </Panel>

      {rows.length ? (
        <Panel title="2 · The columns" right="Hostel, room number and capacity are required">
          <PBody>
            <div className="grid grid--3">
              {FIELDS.map(([k, label]) => (
                <Field id={`hi-${k}`} label={label} key={k}>
                  <select id={`hi-${k}`} className="ctl" value={map[k] ?? -1} onChange={(e) => { setMap({ ...map, [k]: Number(e.target.value) }); setReport(null); }}>
                    <option value={-1}>— not in the file —</option>
                    {head.map((h, i) => <option key={i} value={i}>{h || `Column ${i + 1}`}</option>)}
                  </select>
                </Field>
              ))}
            </div>
            <div className="sub2 mt-1">Category words the import understands: General, Special / Reserved, Student Union (or SU), Security. A blank category is General. A capacity of 1 to 64 beds. Gender F or M, or blank to follow the hostel.</div>
            <div className="row row--tight mt-2"><Btn kind="primary" onClick={() => void run(false)} disabled={!may || !ready || busy || !body.length}>{busy ? "Checking…" : `Preview ${body.length} rows`}</Btn>{!ready ? <span className="sub2">Map the hostel, the room number and the capacity first.</span> : null}</div>
          </PBody>
        </Panel>
      ) : null}

      {report && c ? (
        <>
          <Tiles items={[["NEW", c.NEW, "var(--green-ink)", "Will be created"], ["UPDATED", c.UPDATED, null, "Capacity or category changes"], ["EXISTING", c.EXISTING, "var(--chrome)", "Already as stated"], ["DUPLICATE", c.DUPLICATE, "var(--amber-ink)", "Repeated in the file"], ["ERROR", c.ERROR, "var(--red-ink)", "Not importable"]]} cls="grid--5" />
          <Panel title={report.committed ? "3 · Imported" : "3 · Preview — nothing written yet"} right={report.committed ? <Pil kind="ok">Done</Pil> : <Btn kind="primary" onClick={() => void run(true)} disabled={!may || busy || (c.NEW + c.UPDATED) === 0}>{busy ? "Importing…" : `Import ${c.NEW + c.UPDATED} rows`}</Btn>}>
            {c.ERROR ? <PBody><Note kind="info" title={`${c.ERROR} row${c.ERROR === 1 ? "" : "s"} will be skipped`}>Correct them in the workbook and upload again, or import the rest now; the import is safe to repeat.</Note></PBody> : null}
            <DTable
              cols={["S/N|mid", "Row|mid", "Hostel", "Block|mid", "Room|mid", "Beds|mid", "Category", "Gender|mid", "Outcome|mid", "Note"]}
              rows={report.rows.map((r, i) => [i + 1, <span className="tnum" key="r">{r.row_no}</span>, <span key="h">{r.hall_name ?? ""} <span className="sub2 tnum">{r.hall_code ?? ""}</span></span>, r.block ?? "", <b className="tnum" key="n">{r.room_no ?? ""}</b>, <span className="tnum" key="b">{r.beds ?? ""}</span>, r.category ?? "", r.sex ?? "", <Pil kind={TONE[r.outcome]} key="o">{r.outcome}</Pil>, <span className="sub2" key="m">{r.message}</span>])}
            />
          </Panel>
        </>
      ) : null}
    </>
  );
}
