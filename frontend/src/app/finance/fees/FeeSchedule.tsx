"use client";

/**
 * The Bursar's desk: the session's charges stated as a schedule, the
 * clearance scheme put in force under an instrument, and the references
 * students generated that wait on the bank's record. Every act is the
 * Bursar's; a student's charge is computed from what is stated here, never
 * typed against the student.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { Btn, IcoBtn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { semesterText } from "@/lib/student-portal";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify , notifyProblem } from "@/components/proto/Toast";

export interface ScheduleItem { id: string; item: string; amount: number; level: number | null; entry_mode: string | null; faculty_code: string | null; faculty_name: string | null; programme_code: string | null; programme_name: string | null; fee_group: string | null; fee_group_name: string | null; semester: number | null; ord: number; spillover: boolean }
export interface FeeGroup { code: string; name: string; applies_category: string | null }
export interface FeeItem { code: string; name: string }
export interface ProgrammeOption { code: string; name: string; category: string; faculty_code: string }
export interface Schedule {
  session: string;
  items: ScheduleItem[];
  scheme: { id?: string; instrument?: string; from_date?: string; until_date?: string | null; decided_by?: string; rules?: string };
  schemeInForce: boolean;
  position: { students_paying: number; confirmed: number; references_open: number };
}
export interface OpenReference { id: string; reference: string; session: string; purpose: string; amount: number; generated_at: string; expires_at: string; matric_no: string | null; admission_no: string | null; surname: string; other_names: string; programme: string; current_level: number }
export interface ApplicantFees { session: string; stated: boolean; carriedFrom?: string | null; applicationFee: number; portalCharge: number; acceptanceFee: number; checkingFee: number }

const naira = (n: number | string) => `₦${Number(n).toLocaleString("en-NG")}`;
const esc = (s: string) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c] ?? c);

/** Parse the approved-fees cross-tab (faculty blocks × 1st/2nd/Total rows × level bands × Indigene/Non-indigene)
 *  into one row per cell. A band like "100/200DE" is level 100 plus level 200 for Direct Entry. */
interface FeeRow { faculty: string; level: number; entryMode: string | null; semester: number; indigene: string; amount: number; spillover?: boolean }
function parseFeeMatrix(grid: (string | number | null)[][]): FeeRow[] {
  const norm = (v: string | number | null | undefined) => String(v ?? "").trim();
  const hIdx = grid.findIndex((r) => r.some((c) => /faculty\s*\/\s*semester|^faculty$/i.test(norm(c))));
  if (hIdx < 0) return [];
  const header = grid[hIdx].map(norm);
  const facCol = header.findIndex((c) => /faculty/i.test(c));
  const bands: { col: number; level: number; de: number | null }[] = [];
  const spillBands: { col: number }[] = [];
  for (let c = facCol + 1; c < header.length; c++) {
    const h = header[c];
    if (!h) continue;
    if (/spill/i.test(h)) { spillBands.push({ col: c }); continue; } // the spillover band, level-agnostic
    const nums = h.match(/\d{3}/g);
    if (!nums) continue;
    bands.push({ col: c, level: Number(nums[0]), de: /de/i.test(h) && nums[1] ? Number(nums[1]) : null });
  }
  const semOf = (s: string) => (/1st|first/i.test(s) ? 1 : /2nd|second/i.test(s) ? 2 : /3rd|third/i.test(s) ? 3 : null);
  const rows: FeeRow[] = [];
  let fac = "";
  for (let i = hIdx + 1; i < grid.length; i++) {
    const r = grid[i].map(norm);
    const c1 = r[facCol];
    if (!c1) continue;
    if (!/semester|total/i.test(c1)) { fac = c1; continue; } // a faculty name starts a block
    const sem = semOf(c1);
    if (!sem || !fac) continue; // skip the Total row
    for (const b of bands) {
      const cell = (v: string, indigene: string, level: number, mode: string | null) => {
        const n = Number(v.replace(/[^0-9.]/g, ""));
        if (level && n > 0) rows.push({ faculty: fac, level, entryMode: mode, semester: sem, indigene, amount: Math.round(n * 100) / 100 });
      };
      cell(r[b.col] ?? "", "INDIGENE", b.level, null);
      cell(r[b.col + 1] ?? "", "NON_INDIGENE", b.level, null);
      if (b.de) { cell(r[b.col] ?? "", "INDIGENE", b.de, "DIRECT_ENTRY"); cell(r[b.col + 1] ?? "", "NON_INDIGENE", b.de, "DIRECT_ENTRY"); }
    }
    for (const b of spillBands) {
      const spill = (v: string, indigene: string) => {
        const n = Number(v.replace(/[^0-9.]/g, ""));
        if (n > 0) rows.push({ faculty: fac, level: 0, entryMode: null, semester: sem, indigene, amount: Math.round(n * 100) / 100, spillover: true });
      };
      spill(r[b.col] ?? "", "INDIGENE");
      spill(r[b.col + 1] ?? "", "NON_INDIGENE");
    }
  }
  return rows;
}

/** True when the sheet is a plain one-row-per-fee table (a Faculty column and an
 *  Amount column), not the faculty×level cross-tab. */
function looksFlat(grid: (string | number | null)[][]): boolean {
  return grid.some((r) => {
    const cs = r.map((c) => String(c ?? "").trim().toLowerCase());
    return cs.some((c) => /facult/.test(c) && !c.includes("/")) && cs.some((c) => /amount|fee/.test(c));
  });
}

/** Parse a one-row-per-fee sheet. Each row is a single fee line: Faculty, Level,
 *  Entry mode, Semester, Indigene, Amount (Item / Spillover / Programme optional).
 *  Raw values pass straight to the importer, which normalises them; only the entry
 *  mode is canonicalised here so "Direct Entry"/"DE" reach it as DIRECT_ENTRY. */
function parseFeeFlat(grid: (string | number | null)[][]): Record<string, string>[] {
  const norm = (v: string | number | null | undefined) => String(v ?? "").trim();
  const hIdx = grid.findIndex((r) => {
    const cs = r.map((c) => norm(c).toLowerCase());
    return cs.some((c) => /facult/.test(c) && !c.includes("/semester")) && cs.some((c) => /amount|fee/.test(c));
  });
  if (hIdx < 0) return [];
  const H = grid[hIdx].map((c) => norm(c).toLowerCase());
  const find = (re: RegExp) => H.findIndex((c) => re.test(c));
  const col = {
    faculty: find(/facult/), level: find(/level/), mode: find(/entry|mode/),
    semester: find(/semester|(^|\b)sem(\b|$)/), indigene: find(/indigen|origin|state/),
    amount: find(/amount|fee/), item: find(/item|descrip|charge|purpose/),
    spill: find(/spill/), programme: find(/programme|program|course/),
  };
  const modeOf = (v: string): string | null => {
    const s = v.toUpperCase().replace(/[^A-Z]/g, "");
    if (!s) return null;
    if (s === "DE" || s.includes("DIRECT")) return "DIRECT_ENTRY";
    if (s.includes("TRANSFER")) return "TRANSFER";
    if (s.includes("UTME")) return "UTME";
    if (s.includes("JUPEB")) return "JUPEB";
    if (s.includes("SANDWICH")) return "SANDWICH";
    if (s.includes("POST") || s === "PG") return "POSTGRADUATE";
    return v.toUpperCase().trim();
  };
  const rows: Record<string, string>[] = [];
  for (let i = hIdx + 1; i < grid.length; i++) {
    const r = grid[i].map(norm);
    const cell = (k: keyof typeof col) => (col[k] >= 0 ? (r[col[k]] ?? "") : "");
    const amt = cell("amount").replace(/[^0-9.]/g, "");
    if (!amt || Number(amt) <= 0) continue;
    const fac = cell("faculty");
    const prog = col.programme >= 0 ? cell("programme") : "";
    if (!fac && !prog) continue;
    const row: Record<string, string> = { amount: amt };
    if (fac) row.faculty = fac;
    if (prog) row.programmeCode = prog;
    if (cell("level")) row.level = cell("level");
    const m = col.mode >= 0 ? modeOf(cell("mode")) : null;
    if (m) row.entryMode = m;
    if (cell("semester")) row.semester = cell("semester");
    if (cell("indigene")) row.indigene = cell("indigene");
    if (col.item >= 0 && cell("item")) row.item = cell("item");
    if (col.spill >= 0 && /^(y|t|1|true|yes|spill)/i.test(cell("spill"))) row.spillover = "true";
    rows.push(row);
  }
  return rows;
}

export function FeeSchedule({ session, schedule, open, faculties, feeGroups, programmes, applicantFees, feeItems, sessions, actingOffice }: { session: string; schedule: Schedule; open: OpenReference[]; faculties: { code: string; name: string }[]; feeGroups: FeeGroup[]; programmes: ProgrammeOption[]; applicantFees: ApplicantFees | null; feeItems: FeeItem[]; sessions: string[]; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = actingOffice === "bursar" || actingOffice === "super";
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [adding, setAdding] = useState(false);
  const [confirming, setConfirming] = useState<OpenReference | null>(null);
  const [scheming, setScheming] = useState(false);
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [feeMsg, setFeeMsg] = useState<string | null>(null);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [clearing, setClearing] = useState(false);
  const [filterFac, setFilterFac] = useState("");
  const [filterSem, setFilterSem] = useState("");
  const [filterSpill, setFilterSpill] = useState("");
  const [pageSize, setPageSize] = useState(25);
  const [page, setPage] = useState(0);
  const val = (k: string, d = "") => edits[k] ?? d;

  const appliesTo = (i: ScheduleItem) => [i.fee_group_name, i.spillover ? "Spillover" : i.level ? `${i.level} Level` : null, i.entry_mode, i.faculty_name, i.programme_name, i.semester ? semesterText(i.semester) : null].filter(Boolean).join(" · ") || "Every student";

  const filteredItems = schedule.items.filter((i) =>
    (!filterFac || i.faculty_code === filterFac || (filterFac === "__none__" && !i.faculty_code)) &&
    (!filterSem || String(i.semester ?? "") === filterSem) &&
    (!filterSpill || (filterSpill === "spill" ? i.spillover : !i.spillover)));
  const pageCount = pageSize > 0 ? Math.max(1, Math.ceil(filteredItems.length / pageSize)) : 1;
  const pageItems = pageSize > 0 ? filteredItems.slice(page * pageSize, page * pageSize + pageSize) : filteredItems;

  function exportExcel() {
    const blob = buildXlsx(
      ["Item", "Applies to", "Level", "Semester", "Faculty", "Entry mode", "Spillover", "Amount"],
      filteredItems.map((i) => [i.item, appliesTo(i), i.spillover ? "Spillover" : i.level ? String(i.level) : "All", i.semester ? String(i.semester) : "Session", i.faculty_name ?? "All", i.entry_mode ?? "All", i.spillover ? "Yes" : "No", i.amount]),
      `Fee schedule ${session.replace("/", "-")}`,
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `Fee schedule ${session.replace("/", "-")}.xlsx`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  function exportPdf() {
    const facLabel = filterFac === "__none__" ? "No faculty (all students)" : filterFac ? (faculties.find((f) => f.code === filterFac)?.name ?? "") : "All faculties";
    const rowsHtml = filteredItems.map((i) => `<tr><td>${esc(i.item)}</td><td>${esc(appliesTo(i))}</td><td style="text-align:right">${naira(i.amount)}</td></tr>`).join("");
    const html = `<!doctype html><html><head><meta charset="utf-8"><title>Fee schedule ${esc(session)}</title>
      <style>body{font:13px system-ui,Arial,sans-serif;padding:24px;color:#111}h1{font-size:18px;margin:0 0 2px}.sub{color:#555;margin:0 0 14px}
      table{border-collapse:collapse;width:100%}th,td{border:1px solid #ccc;padding:6px 8px;text-align:left;vertical-align:top}
      th{background:#f3f4f6}tfoot td{font-weight:700}</style></head><body>
      <h1>Rev. Fr. Moses Orshio Adasu University, Makurdi</h1>
      <p class="sub">Fee schedule — ${esc(session)} · ${esc(facLabel)}${filterSem ? ` · Semester ${esc(filterSem)}` : ""}${filterSpill === "spill" ? " · Spillover only" : filterSpill === "normal" ? " · Excluding spillover" : ""} · ${filteredItems.length} lines</p>
      <table><thead><tr><th>Item</th><th>Applies to</th><th style="text-align:right">Amount</th></tr></thead>
      <tbody>${rowsHtml}</tbody></table></body></html>`;
    const w = window.open("", "_blank");
    if (!w) { setProblem({ status: 400, title: "Allow pop-ups to print", detail: "Your browser blocked the print window. Allow pop-ups for this site, or use Download Excel." }); notifyProblem({ status: 400, title: "Allow pop-ups to print", detail: "Your browser blocked the print window. Allow pop-ups for this site, or use Download Excel." }); return; }
    w.document.write(html);
    w.document.close();
    w.focus();
    setTimeout(() => w.print(), 300);
  }

  function openEdit(i: ScheduleItem) {
    const known = feeItems.some((it) => it.name === i.item);
    setEditingId(i.id);
    setAdding(true);
    setEdits({
      item: known ? i.item : "__other__", itemOther: known ? "" : i.item, amount: String(i.amount),
      addSession: session, semester: i.semester ? String(i.semester) : "", group: i.fee_group ?? "",
      level: i.level ? String(i.level) : "", mode: i.entry_mode ?? "", faculty: i.faculty_code ?? "", progs: i.programme_code ?? "",
    });
  }
  const [af, setAf] = useState({
    applicationFee: String(applicantFees?.applicationFee ?? ""),
    portalCharge: String(applicantFees?.portalCharge ?? ""),
    acceptanceFee: String(applicantFees?.acceptanceFee ?? ""),
    checkingFee: String(applicantFees?.checkingFee ?? ""),
  });

  // the applicant fees live under admissions, not finance, so they have their own save
  // the deferment application fee (V264): stated by the Bursary in people.deferment_setting, read by the student's Deferment screen
  const [df, setDf] = useState("");
  const [dfMeta, setDfMeta] = useState<{ fee_updated_at: string | null } | null>(null);
  useEffect(() => {
    let alive = true;
    fetch("/api/bff/api/v1/deferments/settings").then((r) => (r.ok ? r.json() : null)).then((j) => {
      if (alive && j) { setDf(String(j.fee ?? "")); setDfMeta({ fee_updated_at: j.fee_updated_at ?? null }); }
    }).catch(() => { /* leave blank */ });
    return () => { alive = false; };
  }, []);
  async function saveDefermentFee(): Promise<void> {
    setBusy("df"); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/deferments/settings", { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Deferment application fee stated: ${df}`) }, body: JSON.stringify({ fee: Number(df) || 0 }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setDfMeta({ fee_updated_at: (j as { fee_updated_at?: string | null }).fee_updated_at ?? new Date().toISOString() });
      notify("Deferment application fee stated");
    } finally { setBusy(null); }
  }
  // the inter-departmental transfer processing fee (Bursary-set; defaults to ₦10,000 when unset)
  const [tf, setTf] = useState("");
  const [tfStated, setTfStated] = useState(false);
  useEffect(() => {
    let alive = true;
    fetch("/api/bff/api/v1/finance/transfer-fee").then((r) => (r.ok ? r.json() : null)).then((j) => {
      if (alive && j) { setTf(String(j.amount ?? "")); setTfStated(!!j.stated); }
    }).catch(() => { /* leave blank */ });
    return () => { alive = false; };
  }, []);
  async function saveTransferFee(): Promise<void> {
    const ok = await send("tf", "PUT", "/transfer-fee", { amount: Number(tf) || 0 }, `Inter-departmental transfer fee set to ${tf}`);
    if (ok) setTfStated(true);
  }

  // the postgraduate application/acceptance fees (admissions.pg_fee), read by the PG apply page
  const [pgf, setPgf] = useState({ applicationFee: "", acceptanceFee: "", checkingFee: "" });
  const [pgfStated, setPgfStated] = useState(false);
  useEffect(() => {
    let alive = true;
    fetch(`/api/bff/api/v1/pg/sessions/${session}/fees`).then((r) => (r.ok ? r.json() : null)).then((j) => {
      if (alive && j) { setPgf({ applicationFee: String(j.application_fee ?? ""), acceptanceFee: String(j.acceptance_fee ?? ""), checkingFee: String(j.checking_fee ?? "") }); setPgfStated(!!j.stated); }
    }).catch(() => { /* leave blank */ });
    return () => { alive = false; };
  }, [session]);
  async function savePgFees(): Promise<void> {
    setBusy("pgf"); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/sessions/${session}/fees`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Postgraduate fees stated for ${session}`) },
        body: JSON.stringify({ applicationFee: Number(pgf.applicationFee) || 0, acceptanceFee: Number(pgf.acceptanceFee) || 0, checkingFee: Number(pgf.checkingFee) || 0 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setPgfStated(true);
    } finally { setBusy(null); }
  }

  async function saveApplicantFees(): Promise<void> {
    setBusy("af");
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/applicant-fees`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Applicant / Post-UTME fees stated for ${session}`) },
        body: JSON.stringify({ applicationFee: Number(af.applicationFee) || 0, portalCharge: Number(af.portalCharge) || 0, acceptanceFee: Number(af.acceptanceFee) || 0, checkingFee: Number(af.checkingFee) || 0 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  async function send(key: string, method: "POST" | "PUT", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally {
      setBusy(null);
    }
  }

  async function uploadFees(file: File) {
    setBusy("feeupload");
    setProblem(null);
    setFeeMsg(null);
    try {
      const isCsv = /\.csv$/i.test(file.name) || file.type === "text/csv";
      let grid: (string | number | null)[][];
      try {
        grid = isCsv ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
      } catch (err) {
        setProblem({ status: 400, title: "That file could not be read.",
          detail: `${err instanceof Error ? err.message : String(err)}. Save it from Excel as “Excel Workbook (.xlsx)” or as “CSV (Comma delimited) (.csv)” and upload that — an old .xls or a renamed file will not read.` }); notifyProblem({ status: 400, title: "That file could not be read.",
          detail: `${err instanceof Error ? err.message : String(err)}. Save it from Excel as “Excel Workbook (.xlsx)” or as “CSV (Comma delimited) (.csv)” and upload that — an old .xls or a renamed file will not read.` });
        return;
      }
      const rows = looksFlat(grid) ? parseFeeFlat(grid) : parseFeeMatrix(grid);
      if (!rows.length) {
        setProblem({ status: 400, title: "No fee rows could be read from that file.", detail: "One-row-per-fee: give it Faculty, Level, Entry mode, Semester, Indigene and Amount columns. Cross-tab: a FACULTY/SEMESTER header with level columns, then a block per faculty with 1st and 2nd Semester rows." }); notifyProblem({ status: 400, title: "No fee rows could be read from that file.", detail: "One-row-per-fee: give it Faculty, Level, Entry mode, Semester, Indigene and Amount columns. Cross-tab: a FACULTY/SEMESTER header with level columns, then a block per faculty with 1st and 2nd Semester rows." });
        return;
      }
      const r = await fetch(`/api/bff/api/v1/finance/sessions/${session}/fee-structure`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Approved fees structure uploaded for ${session}`) }, body: JSON.stringify({ rows }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const c = j as { rows: number; lines: number; faculties: number; no_faculty: number };
      setFeeMsg(`${c.lines} fee lines loaded across ${c.faculties} faculties${c.no_faculty ? ` · ${c.no_faculty} rows had a faculty name that did not match one on the register` : ""}. It replaced the previous structure for ${session}.`);
      router.refresh();
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the approved-fees .xlsx." }); notifyProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the approved-fees .xlsx." });
    } finally {
      setBusy(null);
    }
  }

  const rules = schedule.scheme.rules ? (JSON.parse(schedule.scheme.rules) as Record<string, string>) : {};
  const total = schedule.items.filter((i) => !i.level && !i.entry_mode && !i.faculty_code && !i.programme_code).reduce((n, i) => n + Number(i.amount), 0);

  return (
    <>
      <RoleLine allowed={["bursar"]} actingOffice={actingOffice} canAct={may} action="Stating fees and the clearance scheme" />
      <Tiles items={[
        ["Items stated", String(schedule.items.length), null, `${session} · every item applies where its filters match`],
        ["Charge to everybody", naira(total), null, "Items with no filter"],
        ["Confirmed this session", naira(schedule.position.confirmed), "var(--green-ink)", `${schedule.position.students_paying} student${schedule.position.students_paying === 1 ? "" : "s"} paying`],
        ["References waiting", String(schedule.position.references_open), schedule.position.references_open ? "var(--red-ink)" : null, "Against the bank's record"],
      ]} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {schedule.schemeInForce ? (
        <Note kind="ok" title={`Clearance scheme in force under ${schedule.scheme.instrument}`}>
          From {schedule.scheme.from_date}{schedule.scheme.until_date ? ` to ${schedule.scheme.until_date}` : ""}. Registration releases at {rules.REGISTRATION ?? "—"}, the examination at {rules.EXAMINATION ?? "—"}, results at {rules.RESULTS ?? "—"}; arrears block everything.
        </Note>
      ) : (
        <Note kind="bad" title="No clearance scheme is in force, so no payment releases anything" action={<Btn kind="urgent" disabled={!may} onClick={() => { setScheming(true); setEdits({}); }}>Put the recommended scheme in force</Btn>}>
          The portal refuses rather than assumes what a payment releases. The recommended scheme: the first instalment, half the charge, opens registration, the identity card and the library; payment in full opens the examination, results, the transcript and convocation; arrears block everything. It is put in force under a minute, from a date.
        </Note>
      )}
      <Panel title={`The charges for ${session}`} right={<span className="row">
        <select aria-label="Session" className="ctl" style={{ width: "auto" }} value={session} onChange={(e) => { if (e.target.value !== session) queryNav(`/finance/fees?session=${encodeURIComponent(e.target.value)}`); }}>
          {(sessions.length ? sessions : [session]).map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
        <Btn kind="primary" disabled={!may} onClick={() => { setEditingId(null); setAdding(true); setEdits({}); }}>Add an item</Btn>
      </span>}>
        <PBody>
          <div className="row row--end">
            <Field id="flt-fac" label="Faculty">
              <select id="flt-fac" className="ctl" style={{ minWidth: 180 }} value={filterFac} onChange={(e) => { setFilterFac(e.target.value); setPage(0); }}>
                <option value="">Every faculty</option>
                <option value="__none__">No faculty (all students)</option>
                {faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}
              </select>
            </Field>
            <Field id="flt-sem" label="Semester">
              <select id="flt-sem" className="ctl" style={{ minWidth: 130 }} value={filterSem} onChange={(e) => { setFilterSem(e.target.value); setPage(0); }}>
                <option value="">Whole session</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
              </select>
            </Field>
            <Field id="flt-spill" label="Spillover">
              <select id="flt-spill" className="ctl" style={{ minWidth: 140 }} value={filterSpill} onChange={(e) => { setFilterSpill(e.target.value); setPage(0); }}>
                <option value="">All students</option><option value="normal">Exclude spillover</option><option value="spill">Spillover only</option>
              </select>
            </Field>
            <Field id="flt-size" label="Per page">
              <select id="flt-size" className="ctl" style={{ minWidth: 120 }} value={String(pageSize)} onChange={(e) => { setPageSize(Number(e.target.value)); setPage(0); }}>
                {[10, 25, 50, 100].map((n) => <option key={n} value={n}>{n}</option>)}<option value="0">All</option>
              </select>
            </Field>
            <span className="grow" />
            <Btn kind="ghost" onClick={exportExcel}>Download Excel</Btn>
            <Btn kind="ghost" onClick={exportPdf}>Download PDF</Btn>
          </div>
          <div className="sub2 mt-2">{filteredItems.length} of {schedule.items.length} line{schedule.items.length === 1 ? "" : "s"}{filterFac || filterSem || filterSpill ? " (filtered)" : ""}.</div>
        </PBody>
        <DTable cols={["Item", "Applies to", "Amount|num", "|num"]} rows={pageItems.map((i) => [
          <strong key="i">{i.item}{i.spillover ? <Pil kind="info" key="sp">Spillover</Pil> : null}</strong>,
          <span className="sub2" key="a">{appliesTo(i)}</span>,
          <span className="tnum" key="m">{naira(i.amount)}</span>,
          <span key="x" className="row row--tight row--right">
            <IcoBtn key="e" icon="edit" label={`Edit ${i.item}`} disabled={!may || busy !== null} onClick={() => openEdit(i)} />
            <Btn kind="ghost" disabled={!may || busy !== null} onClick={() => void send(`end-${i.id}`, "POST", `/sessions/${session}/schedule/${i.id}/end`, {}, `Fee item ended: ${i.item}`)}>{busy === `end-${i.id}` ? "Ending…" : "End"}</Btn>
          </span>,
        ])} />
        {!schedule.items.length ? <PBody><div className="sub2">No charge is stated for {session}. Until one is, no student owes anything, no reference can be generated, and registration waits.</div></PBody>
          : !filteredItems.length ? <PBody><div className="sub2">No fee line matches the filters.</div></PBody> : null}
        {pageSize > 0 && filteredItems.length > pageSize ? (
          <PBody>
            <div className="row row--right">
              <Btn kind="ghost" disabled={page <= 0} onClick={() => setPage((p) => Math.max(0, p - 1))}>Previous</Btn>
              <span className="sub2">Page {Math.min(page, pageCount - 1) + 1} of {pageCount}</span>
              <Btn kind="ghost" disabled={page >= pageCount - 1} onClick={() => setPage((p) => Math.min(pageCount - 1, p + 1))}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
      {may ? (
        <Panel title="Upload the approved fees structure" right="Council's approved table, in one upload">
          <PBody>
            <div className="sub2 mb-2">Upload the approved fees spreadsheet — a block per faculty, with 1st and 2nd Semester rows and a column for each level, split Indigene / Non-indigene. Each cell becomes a fee line above: a student is charged the cell for their faculty, level, semester and state of origin (an indigene is of the University&rsquo;s State). A student can pay the semester due or the full session at once. <b>Uploading replaces the whole structure for {session}.</b> Accepts a real Excel workbook (.xlsx) or the same sheet saved as CSV (.csv) — if a file will not read, in Excel choose <i>Save As → Excel Workbook</i> or <i>CSV (Comma delimited)</i>. Two shapes work: this faculty×level cross-tab, or a plain <b>one-row-per-fee</b> table with columns <i>Faculty, Level, Entry mode, Semester, Indigene, Amount</i> (the clearer format — one line, charged once).</div>
            <div className="row">
              <label className={`btn btn--primary m-0${busy === "feeupload" ? " btn--disabled" : ""}`} style={{ cursor: busy === "feeupload" ? "not-allowed" : "pointer" }}>
                {busy === "feeupload" ? "Uploading…" : "Upload approved fees (.xlsx / .csv)"}
                <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={busy === "feeupload"} onChange={(e) => { const f = e.target.files?.[0]; if (f) void uploadFees(f); e.target.value = ""; }} />
              </label>
              <Btn kind="ghost" disabled={busy !== null || !schedule.items.length} onClick={() => setClearing(true)}>{busy === "clear" ? "Clearing…" : `Clear the ${session} schedule`}</Btn>
            </div>
            <div className="sub2 mt-2">An upload already replaces this session&rsquo;s schedule. Use <b>Clear</b> only to empty a session whose fees were stated by mistake (for example the wrong session) — then switch to the right session above and upload.</div>
            {feeMsg ? <Note kind="ok" title="Approved fees loaded">{feeMsg}</Note> : null}
          </PBody>
        </Panel>
      ) : null}
      <Panel title="References waiting on the bank's record" right={`${open.length}`}>
        <DTable cols={["Reference", "Student", "Amount|num", "Generated|mid", "|num"]} rows={open.map((r) => [
          <span className="tnum" key="r">{r.reference}</span>,
          <Two key="s" a={`${r.surname}, ${r.other_names}`} b={`${r.matric_no ?? r.admission_no} · ${r.programme} · ${r.current_level} Level`} />,
          <span className="tnum" key="a">{naira(r.amount)}</span>,
          <span className="sub2 tnum" key="g">{new Date(r.generated_at).toLocaleString("en-GB")}</span>,
          <Btn kind="primary" key="c" disabled={!may} onClick={() => { setConfirming(r); setEdits({}); }}>Confirm</Btn>,
        ])} texts={open.map((r) => `${r.reference} ${r.surname} ${r.other_names} ${r.matric_no} ${r.admission_no}`)} />
        {!open.length ? <PBody><div className="sub2">Nothing waits. A reference a student generates appears here until the bank&rsquo;s record is matched to it, by the Bursary or by a gateway&rsquo;s webhook.</div></PBody> : null}
      </Panel>
      {adding ? (() => {
        const addSession = val("addSession", session);
        const facultyPick = val("faculty");
        const facultyName = faculties.find((f) => f.code === facultyPick)?.name;
        const facProgrammes = facultyPick ? programmes.filter((pr) => pr.faculty_code === facultyPick) : programmes;
        const itemName = val("item") === "__other__" ? val("itemOther").trim() : val("item");
        const selectedProgs = (val("progs") ? val("progs").split(",") : []).filter(Boolean);
        const toggleProg = (code: string) => { const s = new Set(selectedProgs); if (s.has(code)) s.delete(code); else s.add(code); setEdits({ ...edits, progs: [...s].join(",") }); };
        return (
        <Modal title={editingId ? "Edit the charge item" : "An item of the charge"} sub={`${addSession} · applies where every filter it carries matches, or is blank`} onClose={() => { setAdding(false); setEditingId(null); }}
          foot={<><Btn kind="ghost" onClick={() => { setAdding(false); setEditingId(null); }}>Cancel</Btn><span className="grow" /><Btn kind="primary" disabled={!itemName || !val("amount") || busy !== null} onClick={async () => {
            const shared = { item: itemName, amount: Number(val("amount")), level: val("level") ? Number(val("level")) : null, entryMode: val("mode") || null, feeGroup: val("group") || null, semester: val("semester") ? Number(val("semester")) : null, ord: Number(val("ord") || "0"), facultyCode: val("faculty") || null };
            let ok = true;
            if (editingId) {
              // edit the one line in place
              ok = await send("edit", "PUT", `/sessions/${addSession}/schedule/${editingId}`, { ...shared, programmeCode: selectedProgs[0] ?? null }, `Fee item edited for ${addSession}: ${itemName}`);
            } else if (selectedProgs.length) {
              // one row per chosen programme; the fee applies to exactly those
              for (const code of selectedProgs) {
                ok = (await send(`add-${code}`, "POST", `/sessions/${addSession}/schedule`, { ...shared, programmeCode: code }, `Fee item stated for ${addSession}: ${itemName} · ${code}`)) && ok;
              }
            } else {
              // none chosen: the whole faculty (if one is set), else every programme
              ok = await send("add", "POST", `/sessions/${addSession}/schedule`, { ...shared, programmeCode: null }, `Fee item stated for ${addSession}: ${itemName}`);
            }
            if (ok) { setAdding(false); setEditingId(null); if (addSession !== session) queryNav(`/finance/fees?session=${encodeURIComponent(addSession)}`); }
          }}>{busy === "edit" ? "Saving…" : busy === "add" || (busy ?? "").startsWith("add-") ? "Stating…" : editingId ? "Save changes" : "State the item"}</Btn></>}>
          <div className="grid grid--2">
            <Field id="fi" label="Payment item" hint="A payment category; choose Other to name a one-off">
              <select id="fi" className="ctl" value={val("item")} onChange={(e) => setEdits({ ...edits, item: e.target.value })}>
                <option value="">— choose an item —</option>
                {feeItems.map((it) => <option key={it.code} value={it.name}>{it.name}</option>)}
                <option value="__other__">Other (type a name)…</option>
              </select>
            </Field>
            <Field id="fa" label="Amount" hint="In naira"><input id="fa" className="ctl tnum" value={val("amount")} inputMode="numeric" onChange={(e) => setEdits({ ...edits, amount: e.target.value })} /></Field>
          </div>
          {val("item") === "__other__" ? <Field id="fio" label="Item name" hint="The name this charge appears under"><input id="fio" className="ctl" value={val("itemOther")} onChange={(e) => setEdits({ ...edits, itemOther: e.target.value })} placeholder="e.g. Faculty dues" /></Field> : null}
          <div className="grid grid--2">
            <Field id="fs" label="Session" hint="Which session this charge is for"><select id="fs" className="ctl" value={addSession} onChange={(e) => setEdits({ ...edits, addSession: e.target.value })}>{(sessions.length ? sessions : [session]).map((s) => <option key={s} value={s}>{s}</option>)}</select></Field>
            <Field id="fsem" label="Semester" hint="Blank for the whole session"><select id="fsem" className="ctl" value={val("semester")} onChange={(e) => setEdits({ ...edits, semester: e.target.value })}><option value="">Whole session</option><option value="1">First semester</option><option value="2">Second semester</option></select></Field>
          </div>
          <Field id="fg" label="Programme group" hint="Undergraduate, Postgraduate, GST, EPS — blank for every group">
            <select id="fg" className="ctl" value={val("group")} onChange={(e) => setEdits({ ...edits, group: e.target.value })}>
              <option value="">Every group</option>
              {feeGroups.map((g) => <option key={g.code} value={g.code}>{g.name}</option>)}
            </select>
          </Field>
          <div className="grid grid--2">
            <Field id="fl" label="Level" hint="Blank for every level; 700–900 are postgraduate"><select id="fl" className="ctl" value={val("level")} onChange={(e) => setEdits({ ...edits, level: e.target.value })}><option value="">Every level</option>{[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l === 700 ? "700 · PGD" : l === 800 ? "800 · Master’s" : l === 900 ? "900 · Doctoral" : l}</option>)}</select></Field>
            <Field id="fm" label="Entry mode" hint="Blank for every mode"><select id="fm" className="ctl" value={val("mode")} onChange={(e) => setEdits({ ...edits, mode: e.target.value })}><option value="">Every mode</option><option>UTME</option><option>DIRECT_ENTRY</option><option>TRANSFER</option><option>POSTGRADUATE</option></select></Field>
          </div>
          <Field id="ff" label="Faculty" hint="Choose a faculty to list its programmes"><select id="ff" className="ctl" value={val("faculty")} onChange={(e) => setEdits({ ...edits, faculty: e.target.value, progs: "" })}><option value="">Every faculty</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></Field>
          <Field id="fp" label="Programmes" hint={facultyPick ? `Tick a single programme, two or more, or none for all programmes in ${facultyName ?? "the faculty"}` : "Choose a faculty above to target specific programmes; otherwise the charge applies to every programme"}>
            {facultyPick ? (
              <>
                <div className="row mb-2">
                  <Btn kind="ghost" onClick={() => setEdits({ ...edits, progs: facProgrammes.map((pr) => pr.code).join(",") })}>Select all</Btn>
                  {selectedProgs.length ? <Btn kind="ghost" onClick={() => setEdits({ ...edits, progs: "" })}>Clear (all in faculty)</Btn> : null}
                  <span className="sub2">{selectedProgs.length ? `${selectedProgs.length} selected` : `All programmes in ${facultyName ?? "the faculty"}`}</span>
                </div>
                <div style={{ maxHeight: 180, overflowY: "auto", border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", padding: "var(--s-2)", display: "grid", gap: "var(--s-1)" }}>
                  {facProgrammes.length ? facProgrammes.map((pr) => (
                    <label key={pr.code} className="sub2 row" style={{ cursor: "pointer" }}>
                      <input type="checkbox" className="pchk" checked={selectedProgs.includes(pr.code)} onChange={() => toggleProg(pr.code)} /> {pr.name}
                    </label>
                  )) : <span className="sub2">No programme in this faculty.</span>}
                </div>
              </>
            ) : <div className="sub2">Applies to every programme. Choose a faculty above to target one, two or more.</div>}
          </Field>
        </Modal>
        );
      })() : null}
      {confirming ? (
        <Modal title={`Confirm ${confirming.reference}`} sub={`${confirming.surname}, ${confirming.other_names} · ${naira(confirming.amount)}`} onClose={() => setConfirming(null)}
          foot={<><Btn kind="ghost" onClick={() => setConfirming(null)}>Cancel</Btn><span className="grow" /><Btn kind="go" disabled={!val("channel") || busy !== null} onClick={async () => { const ok = await send("confirm", "POST", `/references/${confirming.reference}/confirm`, { channel: val("channel"), note: val("note") || undefined }, `Payment ${confirming.reference} confirmed against the bank's record`); if (ok) setConfirming(null); }}>{busy === "confirm" ? "Confirming…" : "Confirm the payment"}</Btn></>}>
          <Field id="ch" label="Channel"><select id="ch" className="ctl" value={val("channel")} onChange={(e) => setEdits({ ...edits, channel: e.target.value })}><option value="">Choose…</option><option>Bank transfer</option><option>Bank branch</option><option>USSD</option><option>Card</option></select></Field>
          <Field id="nt" label="Note" hint="Teller number, transaction reference"><input id="nt" className="ctl" value={val("note")} onChange={(e) => setEdits({ ...edits, note: e.target.value })} /></Field>
          <Note kind="info" title="Confirmed against the bank's record, not by this page">The receipt is issued the moment you confirm, and the student is told by email and SMS.</Note>
        </Modal>
      ) : null}
      {scheming ? (
        <Modal title="Put the recommended clearance scheme in force" sub="Under a minute, from a date" onClose={() => setScheming(false)}
          foot={<><Btn kind="ghost" onClick={() => setScheming(false)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={!val("instrument") || busy !== null} onClick={async () => { const ok = await send("scheme", "POST", "/clearance-scheme", { instrument: val("instrument"), from: val("from") || undefined }, `Clearance scheme put in force under ${val("instrument")}`); if (ok) setScheming(false); }}>{busy === "scheme" ? "Putting in force…" : "Put in force"}</Btn></>}>
          <Field id="si" label="Instrument" hint="The Council or Bursary minute that approved it"><input id="si" className="ctl" value={val("instrument")} onChange={(e) => setEdits({ ...edits, instrument: e.target.value })} placeholder="BUR/2026/04" /></Field>
          <Field id="sf" label="From" hint="Blank for today"><input id="sf" className="ctl tnum" type="date" value={val("from")} onChange={(e) => setEdits({ ...edits, from: e.target.value })} /></Field>
          <div className="sub2">Registration, identity card and library release at the first instalment; the examination, results, transcript and convocation at payment in full; hostel is not gated; arrears block everything. Two schemes cannot overlap in time.</div>
        </Modal>
      ) : null}
      {clearing ? (
        <Modal title={`Clear the ${session} schedule`} sub={`${schedule.items.length} line${schedule.items.length === 1 ? "" : "s"} will be removed`} onClose={() => setClearing(false)}
          foot={<><Btn kind="ghost" onClick={() => setClearing(false)}>Cancel</Btn><span className="grow" /><Btn kind="urgent" disabled={busy !== null} onClick={async () => { const ok = await send("clear", "POST", `/sessions/${session}/schedule/clear`, {}, `Fee schedule cleared for ${session}`); if (ok) setClearing(false); }}>{busy === "clear" ? "Clearing…" : "Clear the schedule"}</Btn></>}>
          <Note kind="bad" title={`Every fee line for ${session} will be ended`}>No student on {session} will owe anything until a new structure is stated. Receipts and payments already made are untouched. Upload the approved fees for the right session afterwards.</Note>
        </Modal>
      ) : null}
      <Panel title="Applicant · Post-UTME fees" right={applicantFees?.stated ? `Stated for ${session}` : applicantFees?.carriedFrom ? `Carried forward from ${applicantFees.carriedFrom} — not yet stated for ${session}` : `Built-in figures (nothing stated yet)`}>
        <PBody>
          <div className="sub2 mb-3">
            The charges an applicant pays before they are a student &mdash; the Post-UTME screening fee (with the portal and payment charge) and the acceptance fee an offer carries. They are a payment item of their own, under <b>Applicant</b>, kept apart from the student charges above because an applicant is not yet on the register.
          </div>
          <div className="grid grid--3">
            <Field id="af-app" label="Post-UTME screening fee" hint="What the applicant pays to apply and be screened"><input id="af-app" className="ctl tnum" inputMode="numeric" value={af.applicationFee} onChange={(e) => setAf({ ...af, applicationFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="2000" disabled={!may} /></Field>
            <Field id="af-port" label="Portal and payment charge" hint="Added to the screening fee at checkout"><input id="af-port" className="ctl tnum" inputMode="numeric" value={af.portalCharge} onChange={(e) => setAf({ ...af, portalCharge: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="300" disabled={!may} /></Field>
            <Field id="af-acc" label="Acceptance fee" hint="Paid on an offer; credited to first-session charges"><input id="af-acc" className="ctl tnum" inputMode="numeric" value={af.acceptanceFee} onChange={(e) => setAf({ ...af, acceptanceFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="30000" disabled={!may} /></Field>
            <Field id="af-chk" label="Admission checking fee" hint="Paid on its own, once, to view the released admission status; the acceptance fee follows separately"><input id="af-chk" className="ctl tnum" inputMode="numeric" value={af.checkingFee} onChange={(e) => setAf({ ...af, checkingFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="0" disabled={!may} /></Field>
          </div>
          <div className="row mt-2">
            <Btn kind="primary" disabled={!may || busy !== null || !af.applicationFee.trim()} onClick={() => void saveApplicantFees()}>{busy === "af" ? "Saving…" : "State the applicant fees"}</Btn>
            <span className="sub2">Applying costs the screening fee plus the portal charge &mdash; {naira((Number(af.applicationFee) || 0) + (Number(af.portalCharge) || 0))}. Accepting an offer costs the acceptance fee plus the checking fee &mdash; {naira((Number(af.acceptanceFee) || 0) + (Number(af.checkingFee) || 0))}.</span>
          </div>
        </PBody>
      </Panel>
      <Panel title="Postgraduate · application &amp; acceptance fees" right={pgfStated ? `Stated for ${session}` : `Default (not yet stated for ${session})`}>
        <PBody>
          <div className="sub2 mb-3">
            The fees a postgraduate applicant pays &mdash; the application fee to apply through the School of Postgraduate Studies, and the acceptance fee an offer carries. Read by the postgraduate apply page (<b>/pg/apply</b>). Until stated, a sensible default applies.
          </div>
          <div className="grid grid--2">
            <Field id="pgf-app" label="PG application fee" hint="What a postgraduate applicant pays to apply"><input id="pgf-app" className="ctl tnum" inputMode="numeric" value={pgf.applicationFee} onChange={(e) => setPgf({ ...pgf, applicationFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="20000" disabled={!may} /></Field>
            <Field id="pgf-acc" label="PG acceptance fee" hint="Paid on an offer"><input id="pgf-acc" className="ctl tnum" inputMode="numeric" value={pgf.acceptanceFee} onChange={(e) => setPgf({ ...pgf, acceptanceFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="50000" disabled={!may} /></Field>
            <Field id="pgf-chk" label="PG checking fee" hint="Paid on acceptance, with the acceptance fee"><input id="pgf-chk" className="ctl tnum" inputMode="numeric" value={pgf.checkingFee} onChange={(e) => setPgf({ ...pgf, checkingFee: e.target.value.replace(/[^0-9.]/g, "") })} placeholder="3000" disabled={!may} /></Field>
          </div>
          <div className="row mt-2">
            <Btn kind="primary" disabled={!may || busy !== null || !pgf.applicationFee.trim()} onClick={() => void savePgFees()}>{busy === "pgf" ? "Saving…" : "State the postgraduate fees"}</Btn>
            <span className="sub2">A postgraduate applicant pays {naira(Number(pgf.applicationFee) || 0)} to apply; accepting an offer costs {naira((Number(pgf.acceptanceFee) || 0) + (Number(pgf.checkingFee) || 0))} (acceptance {naira(Number(pgf.acceptanceFee) || 0)} + checking {naira(Number(pgf.checkingFee) || 0)}).</span>
          </div>
        </PBody>
      </Panel>
      <Panel title="Deferment · application fee" right={dfMeta?.fee_updated_at ? `Stated by the Bursary · ${new Date(dfMeta.fee_updated_at).toLocaleDateString("en-GB")}` : "Default ₦10,000 until the Bursary states it"}>
        <PBody>
          <div className="sub2 mb-3">
            The fee a student pays before the deferment application form opens. It is generated as a payment reference on the student&rsquo;s Deferment screen, paid by card or at the bank, and confirmed like every other payment; only a confirmed payment opens the form. The fee is not refunded when an application is refused. Stated here by the Bursary; never hard-coded in the application.
          </div>
          <div className="grid grid--2">
            <Field id="df-fee" label="Deferment application fee" hint="Zero waives the fee"><input id="df-fee" className="ctl tnum" inputMode="numeric" value={df} onChange={(e) => setDf(e.target.value.replace(/[^0-9.]/g, ""))} placeholder="10000" disabled={!may} /></Field>
          </div>
          <div className="row mt-2">
            <Btn kind="primary" disabled={!may || busy !== null || !df.trim()} onClick={() => void saveDefermentFee()}>{busy === "df" ? "Saving…" : "State the deferment fee"}</Btn>
            <span className="sub2">A student pays {naira(Number(df) || 0)} before the deferment application form opens.</span>
          </div>
        </PBody>
      </Panel>
      <Panel title="Inter-departmental transfer · processing fee" right={tfStated ? "Set by the Bursary" : "Not set yet — required before any transfer"}>
        <PBody>
          <div className="sub2 mb-3">
            The non-refundable fee a student pays to process an inter-departmental transfer. It is set here by the
            Bursary and read by the transfer desk and the student&rsquo;s page. There is no default: until you set it, a
            student can apply but cannot pay, so no transfer can proceed.
          </div>
          <div className="row row--end">
            <Field id="tf-amt" label="Transfer processing fee"><input id="tf-amt" className="ctl tnum" inputMode="numeric" value={tf} onChange={(e) => setTf(e.target.value.replace(/[^0-9.]/g, ""))} placeholder="10000" disabled={!may} /></Field>
            <Btn kind="primary" disabled={!may || busy !== null || !tf.trim()} onClick={() => void saveTransferFee()}>{busy === "tf" ? "Saving…" : "Set the transfer fee"}</Btn>
            <span className="sub2">A student who transfers will pay {naira(Number(tf) || 0)}.</span>
          </div>
        </PBody>
      </Panel>
      <Pil kind="grey">Every act here is the Bursar&rsquo;s, on the record</Pil>
    </>
  );
}
