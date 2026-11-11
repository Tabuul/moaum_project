"use client";

/** V721: old-portal students' dates of birth re-read from the migration file. The file is read here (a number column, a date-of-birth
 *  column), the rows sent as written; the register answers row by row — agrees, to fill, to correct (the record holds the file's day
 *  and month swapped: the old reading), differs (left for the Registry), no date, no record — and the officer writes the filled and the
 *  corrected with a reason, on the audit spine (people.file_dates_of_birth). */
import { useState } from "react";
import Link from "next/link";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { xlsxRows } from "@/lib/xlsx";
import { ACTION_WORDS, dobFileRows, pendingOf, type DobFileRow, type DobResult } from "@/lib/dob-file";

/** people.jamb_dob_officer: who writes a date of birth onto the register */
const WRITERS = ["academic", "registrar", "dregistrar", "records", "ict", "super"];
const CHUNK = 400;

export function DobFromFile({ actingOffice }: { actingOffice: string | null }) {
  const may = WRITERS.includes(actingOffice ?? "");
  const [file, setFile] = useState<{ name: string; rows: DobFileRow[]; empty: number } | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [result, setResult] = useState<DobResult | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);

  async function read(f: File | undefined) {
    if (!f) return;
    setErr(null); setResult(null); setProblem(null);
    try {
      const r = dobFileRows(await xlsxRows(await f.arrayBuffer()));
      if ("err" in r) { setErr(r.err); return; }
      if (!r.rows.length) { setErr("No row carried a matriculation or JAMB number."); return; }
      setFile({ name: f.name, rows: r.rows, empty: r.empty });
    } catch (e) {
      setErr(`That file could not be read. ${e instanceof Error ? e.message : String(e)} An .xlsx is expected.`);
    }
  }

  /** the rows sent in tranches; the answers joined, the counts summed */
  async function run(commit: boolean) {
    if (!file) return;
    setBusy(true); setProblem(null);
    try {
      const all: DobResult = { applied: commit, total: 0, counts: {}, rows: [] };
      for (let i = 0; i < file.rows.length; i += CHUNK) {
        const r = await fetch("/api/bff/api/v1/results/legacy/dates-of-birth", {
          method: "POST", cache: "no-store",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(commit ? `Dates of birth written from the old portal's file ${file.name}` : `Dates of birth read from the old portal's file ${file.name}`) },
          body: JSON.stringify({ rows: file.rows.slice(i, i + CHUNK), commit, reason: commit ? reason.trim() : null }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
        const d = j as DobResult;
        all.total += d.total;
        for (const [k, v] of Object.entries(d.counts)) all.counts[k as keyof DobResult["counts"]] = (all.counts[k as keyof DobResult["counts"]] ?? 0) + (v ?? 0);
        all.rows.push(...d.rows);
      }
      setResult(all);
      if (commit) notify(`${all.counts.CORRECTED ?? 0} record${(all.counts.CORRECTED ?? 0) === 1 ? "" : "s"} corrected, ${all.counts.FILLED ?? 0} filled from the file${all.counts.DIFFERS ? ` · ${all.counts.DIFFERS} differ, left for the Registry` : ""}`);
    } finally { setBusy(false); }
  }

  const c = result?.counts ?? {};
  const pending = result ? pendingOf(result) : 0;
  const shown = result ? result.rows.filter((r) => r.action !== "AGREES") : [];
  return (
    <>
      <Note kind="info" title="Dates of birth from the old portal's file">
        Students imported from the old portal with a date written day, month, year (<span className="tnum">12-09-2003</span>) and no JAMB date-of-birth file may still hold the old
        month-first misreading (9 December 2003). Upload the migration file again: each row is read against the register — a record holding none takes the file&rsquo;s date, one
        holding exactly the misreading is corrected, another date is left for the Registry and listed. Nothing is written until you say so, and every write carries your name, the time and the reason.
        Students with a JAMB date-of-birth file are put right on <Link href="/admissions/candidate-data">Candidate data › Dates of birth</Link>.
      </Note>
      <div className="card"><div className="card__body">
        <div className="eyebrow">Upload the old portal&rsquo;s student or biodata file</div>
        <label className="btn btn--primary" htmlFor="dob-file" style={{ cursor: "pointer", alignSelf: "flex-start" }}>Choose the file…<input type="file" id="dob-file" accept=".xlsx" hidden onChange={(e) => void read(e.target.files?.[0])} /></label>
        <div className="sub2 mt-1">A matriculation number (or JAMB number) column and a date-of-birth column, found by their headers; the other columns are ignored.</div>
      </div></div>
      {err ? <Note kind="bad" title="That file could not be read">{err}</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {file ? (
        <Panel title={file.name} right={`${file.rows.length} rows with a number${file.empty ? ` · ${file.empty} without one, skipped` : ""}`}>
          <PBody>
            <div className="row row--inline row--tight">
              <Btn kind="secondary" busy={busy && !result} disabled={busy} onClick={() => void run(false)}>{result ? "Read the register again" : "Read the file against the register"}</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}
      {result ? (
        <Panel title={result.applied ? "Written to the register" : "The file against the register"} right={`${result.total} rows`}>
          <PBody>
            <Tiles cls="grid--4" items={[
              ["Agree", String(c.AGREES ?? 0), "var(--green-ink)", "The record holds the file's date"],
              [result.applied ? "Filled" : "To fill", String(c.FILLED ?? 0), c.FILLED ? "var(--brand-ink)" : null, "The record held no date"],
              [result.applied ? "Corrected" : "To correct", String(c.CORRECTED ?? 0), c.CORRECTED ? "var(--brand-ink)" : null, "The record held the old misreading"],
              ["Differ", String(c.DIFFERS ?? 0), c.DIFFERS ? "var(--red-ink)" : null, "Another date stands; the Registry decides"],
              ["No date", String(c.UNREADABLE ?? 0), c.UNREADABLE ? "var(--red-ink)" : null, "The file's text is no date"],
              ["No record", String(c.NO_STUDENT ?? 0), c.NO_STUDENT ? "var(--red-ink)" : null, "No student under that number"],
              ["Two records", String(c.AMBIGUOUS ?? 0), c.AMBIGUOUS ? "var(--red-ink)" : null, "Two students under that number"],
            ]} />
            {shown.length ? (
              <DTable pageSize={50} cols={["Row|mid", "Number|mid", "Student", "Programme|mid", "File wrote|mid", "Read as|mid", "On the record|mid", "Reading"]} rows={shown.map((r) => [
                <span key="n" className="tnum">{r.row_no}</span>,
                <span key="m" className="tnum">{r.matric_no ?? r.jamb_reg_no ?? "—"}</span>,
                <span key="s">{r.surname ? <><b>{r.surname}</b>, {r.other_names}</> : "—"}</span>,
                <span key="p" className="tnum">{r.programme_code ?? "—"}</span>,
                <span key="t" className="tnum">{r.file_text ?? "—"}</span>,
                <span key="d" className="tnum">{r.file_date ?? "—"}</span>,
                <span key="h" className="tnum">{r.held ?? "—"}</span>,
                <Pil key="a" kind={ACTION_WORDS[r.action]?.kind ?? "grey"}>{result.applied ? ACTION_WORDS[r.action]?.done : ACTION_WORDS[r.action]?.word}</Pil>,
              ])} texts={shown.map((r) => `${r.matric_no ?? ""} ${r.jamb_reg_no ?? ""} ${r.surname ?? ""} ${r.other_names ?? ""} ${r.action}`)} />
            ) : <Note kind="ok" title="Every record agrees with the file" />}
            {!result.applied && pending ? (
              may ? (
                <div className="mt-3">
                  <Field id="dob-reason" label="Reason for the correction" required full hint="Kept on every record written — the file, and why it is trusted">
                    <input id="dob-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} placeholder={`Dates of birth re-read from ${file?.name ?? "the old portal's file"}, day, month, year`} />
                  </Field>
                  <div className="row mt-2"><Btn kind="primary" busy={busy} busyLabel="Writing…" disabled={reason.trim().length < 10} onClick={() => void run(true)}>Write the file&rsquo;s date to {pending} record{pending === 1 ? "" : "s"}</Btn></div>
                </div>
              ) : <div className="sub2 mt-2">The Academic Office, the Registry, Records or the Director of ICT writes the register.</div>
            ) : null}
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
