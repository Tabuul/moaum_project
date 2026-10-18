"use client";

/** V451: on the Bursary's fee page, the live undergraduates with no school fee stated for the session — no line at all, or
 *  none for a semester that is open — by group of alike students, and the standing "charged as" rules: a faculty named in a
 *  rule is charged another faculty's lines while it has none of its own in a session, so each session's upload covers it. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { semesterName } from "@/lib/student-portal";
import { buildXlsx, xlsxRowsAsync } from "@/lib/xlsx";
import { FeeUploadPreview } from "./FeeUploadPreview";

interface Gap {
  faculty_code: string; faculty: string | null; programme_code: string; programme: string; level: number | null; entry_mode: string | null;
  indigene: boolean | null; spillover: boolean; students: number; charged_as: string | null; stated: boolean; missing: string | null;
}
interface Gaps {
  session: string; students: number; groups: number; openSemesters: number[]; scheduleLines: number;
  /** V461: every semester on the session's calendar, for the sheet the Bursary fills */
  semesters?: number[];
  watch: { told_at: string | null; told: number; students: number; groups: number; checked_at: string } | null;
  rows: Gap[];
}
interface Rule {
  faculty_code: string; faculty: string; source_faculty_code: string; source_faculty: string; from_session: string | null; note: string | null;
  set_at: string; set_office: string | null; set_by_name: string | null; from_reached: boolean; in_force: boolean;
}

const count = (n: number) => Number(n).toLocaleString("en-NG");
const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" });
/** "SOCIAL SCIENCES" as "Social Sciences", the small words kept small */
const named = (s: string | null | undefined) =>
  (s ?? "").toLowerCase().replace(/(^|\s)\S/g, (c) => c.toUpperCase()).replace(/ (And|Of|For|In|The) /g, (m) => m.toLowerCase());
const ENTRY: Record<string, string> = { UTME: "UTME", DIRECT_ENTRY: "Direct entry", TRANSFER: "Transfer", JUPEB: "JUPEB", SANDWICH: "Sandwich" };
const semesters = (list: string | null) => (list ?? "").split(",").filter(Boolean).map((n) => semesterName(Number(n)).toLowerCase());
/** V461: the sheet the Bursary fills for the students with no fee stated, and reads back */
const SHEET = ["Faculty", "Faculty code", "Programme code", "Programme", "Level", "Entry mode", "Semester", "Indigene", "Spillover", "Students", "Amount"];
type SheetResult = { rows: number; added: number; no_amount: number; already: number; no_programme: number; charged_as: number; skipped: number; first_error: string | null };

export function FeeWatch({ session, faculties, programmes = [], sessions, may }: { session: string; faculties: { code: string; name: string }[]; programmes?: { code: string; name: string; category: string; faculty_code: string }[]; sessions: string[]; may: boolean }) {
  const [gaps, setGaps] = useState<Gaps | null>(null);
  const [rules, setRules] = useState<Rule[] | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [form, setForm] = useState<{ faculty: string; source: string; from: string; note: string } | null>(null);
  const [ending, setEnding] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const [sheet, setSheet] = useState<SheetResult | null>(null);
  /** V535: the filled sheet read, shown with its effect before the lines are added */
  const [pending, setPending] = useState<{ fileName: string; rows: Record<string, string>[] } | null>(null);
  const router = useRouter();

  useEffect(() => {
    let alive = true;
    void (async () => {
      const [g, r] = await Promise.all([
        fetch(`/api/bff/api/v1/finance/sessions/${session}/fee-gaps`, { cache: "no-store" }),
        fetch(`/api/bff/api/v1/finance/fee-sources?session=${encodeURIComponent(session)}`, { cache: "no-store" }),
      ]);
      if (!alive) return;
      setGaps(g.ok ? ((await g.json()) as Gaps) : null);
      setRules(r.ok ? ((await r.json()) as Rule[]) : []);
    })();
    return () => { alive = false; };
  }, [session, tick]);

  async function send(key: string, method: "PUT" | "DELETE", path: string, body: unknown, reason: string): Promise<boolean> {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/finance${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
        setProblem(p);
        notifyProblem(p);
        return false;
      }
      notify(reason);
      setTick((t) => t + 1);
      return true;
    } finally {
      setBusy(null);
    }
  }

  /** V461: one row per group of students and semester not stated — programme, level, entry mode, indigeneship, spillover —
   *  the amount left blank for the Bursary to fill; "Upload the filled sheet" adds the lines, never replacing the structure */
  function downloadSheet() {
    if (!gaps) return;
    const all = gaps.semesters?.length ? gaps.semesters : [1, 2];
    // a group of a faculty charged as another (V451) is stated on the faculty it follows, one line for both faculties:
    // a line of its own would end the rule for every student of the faculty
    const byKey = new Map<string, (string | number)[]>();
    for (const g of gaps.rows) {
      for (const sem of g.stated ? (g.missing ?? "").split(",").filter(Boolean).map(Number) : all) {
        const fac = g.charged_as ?? g.faculty_code;
        const prog = g.charged_as ? "" : g.programme_code;
        const level = g.spillover ? "" : g.level ?? "";
        const ind = g.indigene === null ? "" : g.indigene ? "Indigene" : "Non-indigene";
        const key = [fac, prog, level, g.entry_mode ?? "", sem, ind, g.spillover].join("|");
        const had = byKey.get(key);
        if (had) { had[9] = Number(had[9]) + Number(g.students); continue; }
        byKey.set(key, [named(g.charged_as ? facultyName(g.charged_as) : g.faculty ?? g.faculty_code), fac, prog,
          g.charged_as ? `Every programme of ${facultyName(g.charged_as)} (${named(g.faculty ?? g.faculty_code)} is charged as it)` : g.programme,
          level, g.entry_mode ?? "", sem, ind, g.spillover ? "Yes" : "No", Number(g.students), ""]);
      }
    }
    const rows = [...byKey.values()];
    const blob = buildXlsx(SHEET, rows, "Fees to state");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `fees to state for ${session.replace("/", "-")}.xlsx`;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function uploadSheet(file: File) {
    setBusy("sheet");
    setProblem(null);
    setSheet(null);
    try {
      let grid: string[][];
      try {
        grid = await xlsxRowsAsync(await file.arrayBuffer());
      } catch {
        const p = { status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the sheet downloaded here, with the amounts filled in." };
        setProblem(p); notifyProblem(p); return;
      }
      const head = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (name: string) => head.indexOf(name.toLowerCase());
      if (["Programme code", "Semester", "Amount"].some((h) => at(h) < 0)) {
        const p = { status: 400, title: "That is not the sheet downloaded here.", detail: "It needs the Programme code, Semester and Amount columns. Download the sheet, fill the amounts and upload it." };
        setProblem(p); notifyProblem(p); return;
      }
      const cell = (r: string[], name: string) => { const i = at(name); return i < 0 ? "" : String(r[i] ?? "").trim(); };
      const rows = grid.slice(1).filter((r) => r.some((c) => String(c ?? "").trim() !== "")).map((r) => ({
        facultyCode: cell(r, "Faculty code"), programmeCode: cell(r, "Programme code"), level: cell(r, "Level"), entryMode: cell(r, "Entry mode"), semester: cell(r, "Semester"),
        indigene: cell(r, "Indigene"), spillover: cell(r, "Spillover"), amount: cell(r, "Amount"),
      }));
      if (!rows.length) {
        const p = { status: 400, title: "The sheet has no rows.", detail: "Download the sheet, fill the amounts and upload it." };
        setProblem(p); notifyProblem(p); return;
      }
      setPending({ fileName: file.name, rows });
    } finally {
      setBusy(null);
    }
  }

  function added(res: SheetResult) {
    setSheet(res);
    setPending(null);
    notify(`${res.added.toLocaleString()} fee line${res.added === 1 ? "" : "s"} added for ${session}`);
    setTick((t) => t + 1);
    router.refresh();
  }

  const facultyName = (code: string) => named(faculties.find((f) => f.code === code)?.name ?? code);
  const byFaculty = Object.entries((gaps?.rows ?? []).reduce<Record<string, number>>((m, g) => {
    const k = named(g.faculty ?? g.faculty_code);
    m[k] = (m[k] ?? 0) + Number(g.students);
    return m;
  }, {})).sort((a, b) => b[1] - a[1]);
  const listed = gaps !== null && gaps.groups > 0 && gaps.scheduleLines > 0;
  const openWords = (gaps?.openSemesters ?? []).map((n) => semesterName(n).toLowerCase()).join(" and ");

  return (
    <>
      <Panel title="Students with no school fee stated" right={session}>
        <PBody>
          {gaps === null ? <div className="sub2">Reading the students the stated lines reach&hellip;</div>
            : gaps.groups === 0 ? (
              <Note kind="ok" title={`Every live undergraduate has a school fee stated for ${session}`}>
                {openWords ? `Including the ${openWords} semester, which is open.` : "No semester of the session is open yet."} Postgraduate and CCE students are read on their own pages.
              </Note>
            ) : gaps.scheduleLines === 0 ? (
              <Note kind="info" title={`No school fee is stated for ${session} yet`}>
                {count(gaps.students)} live undergraduates in {count(gaps.groups)} groups wait on the session&rsquo;s fees structure. Upload it on this page.
              </Note>
            ) : (
              <Note kind="bad" title={`${count(gaps.students)} undergraduate${gaps.students === 1 ? " has" : "s have"} no school fee stated for ${session}`}>
                They are shown nothing to pay for it, and cannot register for that semester, until a line reaches them. State their lines on this page, or name below the faculty they are charged as.
                {gaps.watch?.told_at ? <span className="blk sub2">The Bursary was told on {day(gaps.watch.told_at)}, and is told again when another group appears.</span> : null}
              </Note>
            )}
        </PBody>
        {listed ? (
          <>
            <PBody>
              <div className="row" style={{ flexWrap: "wrap", gap: 6 }}>
                {byFaculty.map(([f, n]) => <Pil key={f} kind="grey">{f} · {count(n)}</Pil>)}
              </div>
              {may ? (
                <div className="row mt-2" style={{ flexWrap: "wrap" }}>
                  <Btn kind="ghost" onClick={downloadSheet}>Download a sheet to fill</Btn>
                  <label className={`btn btn--primary m-0${busy === "sheet" ? " btn--disabled" : ""}`} style={{ cursor: busy === "sheet" ? "not-allowed" : "pointer" }}>
                    {busy === "sheet" ? "Adding the lines…" : "Upload the filled sheet"}
                    <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy === "sheet"}
                           onChange={(e) => { const f = e.target.files?.[0]; if (f) void uploadSheet(f); e.target.value = ""; }} />
                  </label>
                  <span className="sub2">One row per group and semester not stated; fill the Amount, and the lines are added beside the structure (nothing in it is replaced). A row left blank is not added. You see what the sheet adds, and who is still left with no fee, before it is added.</span>
                </div>
              ) : null}
              {pending ? (
                <FeeUploadPreview session={session} action="LINES" fileName={pending.fileName} read={{ layout: "LINES", rows: pending.rows }}
                  programmes={programmes} faculties={faculties} onClose={() => setPending(null)} onApplied={(j) => added(j as unknown as SheetResult)} />
              ) : null}
              {sheet ? (
                <Note kind={sheet.added ? "ok" : "info"} title={`${sheet.added.toLocaleString()} fee line${sheet.added === 1 ? "" : "s"} added for ${session}`}>
                  {[sheet.no_amount ? `${sheet.no_amount.toLocaleString()} row${sheet.no_amount === 1 ? "" : "s"} with no amount left out` : null,
                    sheet.already ? `${sheet.already.toLocaleString()} already stated, not added twice` : null,
                    sheet.no_programme ? `${sheet.no_programme.toLocaleString()} naming no programme or faculty on record` : null,
                    sheet.charged_as ? `${sheet.charged_as.toLocaleString()} for a faculty charged as another, not added (state its line on the faculty it follows)` : null,
                    sheet.skipped ? `${sheet.skipped.toLocaleString()} refused${sheet.first_error ? ` (${sheet.first_error})` : ""}` : null]
                    .filter(Boolean).join("; ") || "Every row with an amount was added."}
                </Note>
              ) : null}
            </PBody>
            <DTable pageSize={25}
              cols={["Faculty", "Programme", "Level|num", "Entry mode", "Indigene", "Students|num", "Not stated"]}
              texts={gaps.rows.map((g) => `${g.faculty_code} ${g.faculty ?? ""} ${g.programme_code} ${g.programme} ${g.level ?? ""} ${g.entry_mode ?? ""}`)}
              rows={gaps.rows.map((g) => [
                <span key="f">{named(g.faculty ?? g.faculty_code)}{g.charged_as ? <div className="sub2">Charged as {facultyName(g.charged_as)}</div> : null}</span>,
                <span key="p"><b className="tnum">{g.programme_code}</b> {g.programme}</span>,
                <span key="l" className="tnum">{g.spillover ? "Spillover" : g.level ?? "—"}</span>,
                <span key="e">{ENTRY[g.entry_mode ?? ""] ?? g.entry_mode ?? "—"}</span>,
                <span key="i">{g.indigene === null ? "—" : g.indigene ? "Indigene" : "Non-indigene"}</span>,
                <b key="n" className="tnum">{count(g.students)}</b>,
                g.stated ? <Pil key="m" kind="warn">{semesters(g.missing).map((w) => `${w.charAt(0).toUpperCase()}${w.slice(1)} semester`).join(", ")}</Pil>
                  : <Pil key="m" kind="bad">No fee line</Pil>,
              ])} />
          </>
        ) : null}
      </Panel>

      <Panel title="Charged as another faculty" right="A standing rule">
        <PBody>
          <div className="sub2">
            A faculty named here is charged the other faculty&rsquo;s lines (by level, entry mode, indigeneship, spillover and semester) while it has no line of its own in a session, so each session&rsquo;s upload covers it. Once its own lines are stated, they alone apply. Its CCE and postgraduate students are never charged by a rule.
          </div>
        </PBody>
        {rules === null ? null : rules.length ? (
          <DTable cols={["Faculty", "Charged as", "From", `In ${session}`, "Set", ""]}
            rows={rules.map((r) => [
              <span key="f"><b>{named(r.faculty)}</b>{r.note ? <div className="sub2">{r.note}</div> : null}</span>,
              <span key="s">{named(r.source_faculty)}</span>,
              <span key="from" className="tnum">{r.from_session ?? "Every session"}</span>,
              r.in_force ? <Pil key="st" kind="ok">In force</Pil>
                : !r.from_reached ? <Pil key="st" kind="grey">From {r.from_session}</Pil>
                : <Pil key="st" kind="info" title="Its own lines apply in this session">Waits: own lines stated</Pil>,
              <span key="by" className="sub2">{day(r.set_at)}{r.set_by_name ? ` · ${r.set_by_name}` : r.set_office ? ` · ${r.set_office}` : ""}</span>,
              may ? (
                ending === r.faculty_code ? (
                  <span key="a" className="row">
                    <Btn kind="urgent" disabled={busy !== null} onClick={async () => { if (await send("end", "DELETE", `/fee-sources/${encodeURIComponent(r.faculty_code)}`, undefined, `${named(r.faculty)} no longer charged as ${named(r.source_faculty)}`)) setEnding(null); }}>End the rule</Btn>
                    <Btn kind="ghost" onClick={() => setEnding(null)}>Keep it</Btn>
                  </span>
                ) : (
                  <span key="a" className="row">
                    <Btn kind="ghost" onClick={() => setForm({ faculty: r.faculty_code, source: r.source_faculty_code, from: r.from_session ?? "", note: r.note ?? "" })}>Change</Btn>
                    <Btn kind="ghost" onClick={() => setEnding(r.faculty_code)}>End</Btn>
                  </span>
                )
              ) : <span key="a" />,
            ])} />
        ) : <PBody><div className="sub2">No faculty is charged as another.</div></PBody>}
        {may ? (
          <PBody>
            {form ? (
              <div className="row row--end" style={{ flexWrap: "wrap" }}>
                <Field id="fs-fac" label="Faculty">
                  <select id="fs-fac" className="ctl" style={{ minWidth: 200 }} value={form.faculty} onChange={(e) => setForm({ ...form, faculty: e.target.value })}>
                    <option value="">Choose the faculty</option>
                    {faculties.map((f) => <option key={f.code} value={f.code}>{named(f.name)}</option>)}
                  </select>
                </Field>
                <Field id="fs-src" label="Charged as">
                  <select id="fs-src" className="ctl" style={{ minWidth: 200 }} value={form.source} onChange={(e) => setForm({ ...form, source: e.target.value })}>
                    <option value="">Choose the faculty it follows</option>
                    {faculties.filter((f) => f.code !== form.faculty).map((f) => <option key={f.code} value={f.code}>{named(f.name)}</option>)}
                  </select>
                </Field>
                <Field id="fs-from" label="From">
                  <select id="fs-from" className="ctl" style={{ minWidth: 140 }} value={form.from} onChange={(e) => setForm({ ...form, from: e.target.value })}>
                    <option value="">Every session</option>
                    {Array.from(new Set([...sessions, session, form.from].filter(Boolean))).sort().map((s) => <option key={s} value={s}>{s}</option>)}
                  </select>
                </Field>
                <Field id="fs-note" label="Note">
                  <input id="fs-note" className="ctl" style={{ minWidth: 240 }} maxLength={300} value={form.note} placeholder="The decision it rests on" onChange={(e) => setForm({ ...form, note: e.target.value })} />
                </Field>
                <Btn kind="primary" disabled={!form.faculty || !form.source || busy !== null}
                  onClick={async () => {
                    const ok = await send("set", "PUT", `/fee-sources/${encodeURIComponent(form.faculty)}`,
                      { source: form.source, fromSession: form.from || null, note: form.note.trim() || null },
                      `${facultyName(form.faculty)} charged as ${facultyName(form.source)}${form.from ? ` from ${form.from}` : ""}`);
                    if (ok) setForm(null);
                  }}>Save the rule</Btn>
                <Btn kind="ghost" onClick={() => { setForm(null); setProblem(null); }}>Cancel</Btn>
              </div>
            ) : (
              <Btn kind="secondary" onClick={() => setForm({ faculty: "", source: "", from: session, note: "" })}>Name a faculty charged as another</Btn>
            )}
            {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
