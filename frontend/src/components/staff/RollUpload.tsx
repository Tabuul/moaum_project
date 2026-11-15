"use client";
/**
 * V750: the nominal roll uploaded — the teaching staff's desk (t/lecturers) and the non-teaching staff's (t/staffupload) share it.
 * The University's word of 12 November 2026: the roll is the authentic list of staff; of 14 November (V761): an upload only fills
 * what the record of someone on record is missing, and never touches their sign-in, password or offices.
 *
 * The file is the Excel template (the roll's columns, a sheet of instructions beside them) or the Word roll as issued (.docx). It
 * is checked first — the upload run as a dry run, which writes nothing — and the check says who is new, who will be updated and
 * how, what the upload does not write, and what cannot be loaded; with it, the staff on the portal that the file leaves out. Then
 * Upload writes it. Both are sent in chunks (a new lecturer's sign-in is a bcrypt hash), and a chunk that does not land is counted,
 * not fatal: the upload is idempotent, so the same file again fills the gap. The result, row by row, downloads as Excel.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { xlsxWorkbook } from "@/lib/xlsx";
import { xlsx } from "@/lib/xlsx-write";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { Btn, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  claimedBy, ACTION_PILL, TEMPLATE_NAME, actionWord, addChunk, byRow, changeText, chunkFailed, docxTables, emptyTally, fieldWord, findHeader,
  keptText, readRoll, resultSheet, rollGridFromTables, rollName, rollNumbers, rollTemplate, shown, unresolvedText, wrongRoll,
  type RollAbsent, type RollKind, type RollRead, type RollResult, type RollRow, type RollTally, type RollTemplate,
} from "@/lib/staff-roll";

type View = "changes" | "kept" | "problems" | "unresolved" | "absent";

const XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

/** a .docx (the Word roll) or an .xlsx (the template or the old sheet) as the rows an upload sends */
async function readFile(file: File): Promise<RollRead | null> {
  const buf = await file.arrayBuffer();
  if (/\.docx$/i.test(file.name)) return readRoll(rollGridFromTables(await docxTables(buf)));
  // every sheet, each row at its own row of the sheet: the first sheet that carries a staff list's headings (not the instructions)
  const sheets = await xlsxWorkbook(buf, { rowNumbers: true });
  const sheet = sheets.find((s) => findHeader(s.rows));
  return sheet ? readRoll(sheet.rows) : null;
}

export function RollUpload({ kind, templates, endpoint, chunk, what, onDone }: {
  kind: RollKind;
  /** the templates this desk hands out: the teaching staff's one, or the senior and the junior staff's */
  templates: RollTemplate[];
  /** the upload: /api/bff/api/v1/iam/lecturers/import or …/iam/staff/import */
  endpoint: string;
  /** rows a request */
  chunk: number;
  /** "teaching staff" or "non-academic staff", for the reason and the words */
  what: string;
  /** the list on record reloaded after an upload */
  onDone: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number; dry: boolean } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [file, setFile] = useState<{ name: string; read: RollRead } | null>(null);
  const [check, setCheck] = useState<RollTally | null>(null);
  const [done, setDone] = useState<RollTally | null>(null);
  const [absent, setAbsent] = useState<RollAbsent[] | null>(null);
  const [absentProblem, setAbsentProblem] = useState<string | null>(null);
  const [view, setView] = useState<View>("changes");
  const academic = kind === "ACADEMIC";

  function fail(p: Problem) { setProblem(p); notifyProblem(p); }

  function downloadTemplate(t: RollTemplate) {
    const book = xlsx(rollTemplate(t));
    downloadBlob(new Blob([book as BlobPart], { type: XLSX_TYPE }), `Nominal roll template - ${TEMPLATE_NAME[t]}.xlsx`);
  }

  async function pick(f: File) {
    setProblem(null); setCheck(null); setDone(null); setAbsent(null); setAbsentProblem(null); setFile(null); setView("changes");
    let read: RollRead | null;
    try {
      read = await readFile(f);
    } catch (e) {
      fail({ status: 400, title: "That file could not be read.", detail: `Upload the Excel template (.xlsx) or the nominal roll as issued (.docx). ${e instanceof Error ? e.message : ""}`.trim() });
      return;
    }
    if (!read) {
      fail({ status: 400, title: "No heading row of a staff list in that file.", detail: `The headings are the roll's (FIRST NAME, MIDDLE NAME, LAST-SURNAME, ${academic ? "PNO" : "PNO or JP-NO"} …) or the old sheet's (PNO, Full Names, …). Download the template.` });
      return;
    }
    const wrong = wrongRoll(read.header, kind);
    if (wrong) { fail({ status: 400, title: wrong }); return; }
    if (!read.rows.length && !read.repeats.length) { fail({ status: 400, title: `No ${what} found in the file.` }); return; }
    setFile({ name: f.name, read });
    void loadAbsent(read);
    await run(read, true);
  }

  /** the staff on the portal, of this kind and the file's series, whose number the file does not give (it reads; nobody is ended) */
  async function loadAbsent(read: RollRead) {
    try {
      const r = await fetch("/api/bff/api/v1/iam/staff/roll-absent", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Nominal roll of ${what} compared with the portal`) },
        body: JSON.stringify({ kind, numbers: rollNumbers(read) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok || !Array.isArray(j)) { setAbsentProblem(String(j?.detail ?? j?.title ?? `The list could not be read (${r.status}).`)); return; }
      setAbsent(j as RollAbsent[]);
    } catch {
      setAbsentProblem("The list could not be read: the request did not reach the portal.");
    }
  }

  async function run(read: RollRead, dry: boolean) {
    setBusy(true); setProblem(null);
    const rows = read.rows;
    let sum = emptyTally(dry, read.repeats);
    let claimed: Record<string, string> = {};   // the e-mail addresses earlier requests gave: kept from the later rows, in a check as in the upload
    try {
      const chunks: RollRow[][] = [];
      for (let i = 0; i < rows.length; i += chunk) chunks.push(rows.slice(i, i + chunk));
      setProgress({ done: 0, total: rows.length, dry });
      for (const part of chunks) {
        try {
          const r = await fetch(endpoint, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(dry ? `Nominal roll: ${rows.length} ${what} rows checked` : `Nominal roll: ${rows.length} ${what} uploaded`) },
            body: JSON.stringify({ rows: part, dryRun: dry, claimed }),
          });
          const j = await r.json().catch(() => null);
          sum = !r.ok || !j ? chunkFailed(sum, part.length, j?.title ? String(j.title) : `A request failed (${r.status}).`) : addChunk(sum, j);
          if (r.ok && j && Array.isArray(j.results)) claimed = claimedBy(j.results as RollResult[], claimed);
        } catch {
          sum = chunkFailed(sum, part.length, "A request did not reach the portal.");   // keep going: the upload is idempotent
        }
        setProgress((p) => (p ? { ...p, done: Math.min(p.done + part.length, p.total) } : p));
        if (dry) setCheck(sum); else setDone(sum);
      }
      if (!dry) {
        notify(`${sum.created} added · ${sum.updated} updated · ${sum.unchanged} unchanged${sum.skipped + sum.errors ? ` · ${sum.skipped + sum.errors} not loaded` : ""}`);
        onDone();
      }
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  async function exportResult(t: RollTally) {
    const s = resultSheet(t, absent);
    const title = t.dry ? `Nominal roll check: ${what}` : `Nominal roll upload: ${what}`;
    downloadBlob(await brandedXlsx(title, s.headers, s.rows, { sheetName: t.dry ? "Check" : "Upload", serial: docSerial("ROLL"), sub: file?.name, noSerialColumn: true }),
      `${t.dry ? "Nominal roll check" : "Nominal roll upload"} - ${what} - ${(file?.name ?? "roll").replace(/\.(docx|xlsx)$/i, "")}.xlsx`);
  }

  const t = done ?? check;
  const results = t ? byRow(t.results) : [];
  const changed = results.filter((r) => r.action === "CREATED" || r.action === "UPDATED");
  const kept = results.filter((r) => r.kept.length);
  const problems = results.filter((r) => r.action === "SKIPPED" || r.action === "ERROR");
  const unresolved = results.filter((r) => r.unresolved.length && r.action !== "SKIPPED" && r.action !== "ERROR");
  const toWrite = check ? check.created + check.updated : 0;
  const rowCell = (r: RollResult) => <span key="row" className="tnum">{r.row ?? "—"}</span>;
  const idCell = (r: RollResult) => <span key="id" className="tnum b700">{r.staffNumber ?? "—"}</span>;
  const nameCell = (r: RollResult) => <span key="nm">{r.name || "—"}{r.endedOn ? <div className="sub2">Left the University on {shown(r.endedOn)}</div> : null}</span>;
  const actCell = (r: RollResult, dry: boolean) => <Pil key="act" kind={ACTION_PILL[r.action] ?? "grey"}>{actionWord(r.action, dry)}</Pil>;
  const text = (r: RollResult) => `${r.row ?? ""} ${r.staffNumber ?? ""} ${r.name} ${r.error ?? ""} ${r.changes.map((c) => fieldWord(c.field)).join(" ")} ${r.unresolved.map((u) => u.onRoll ?? "").join(" ")}`;

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Upload the nominal roll" right={file ? `${file.name} · ${file.read.rows.length + file.read.repeats.length} rows` : `Person · establishment record · ${academic ? "department" : "posting"}`}>
        <PBody>
          <div className="sub2">
            The nominal roll as issued (<b>.docx</b>) or the <b>Excel template</b>, whose columns are the roll&apos;s
            {academic ? " (17)" : ": the senior staff under PNO, the junior staff under JP-NO (16 each)"}. The file is <b>checked first</b> and
            nothing is written until <b>Upload</b>. Someone on record is found by the staff number and has <b>only what their record
            is missing</b> filled from the roll: a detail the portal holds differently is kept and listed under Not written, and
            a blank or NA cell never erases what is on record. Their sign-in, password and offices are never touched.
            {` A staff number on record as ${academic ? "non-teaching" : "teaching"} staff is not loaded here.`}
          </div>
          <div className="row mt-2">
            {templates.map((tp) => (
              <Btn key={tp} kind="ghost" onClick={() => downloadTemplate(tp)}>{templates.length > 1 ? `${TEMPLATE_NAME[tp]} template` : "Download template"}</Btn>
            ))}
            <label className={`btn btn--secondary btn--sm m-0${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer" }}>
              {busy && progress?.dry ? "Checking…" : "Check a file (.xlsx or .docx)"}
              <input type="file" accept=".xlsx,.docx" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void pick(f); e.target.value = ""; }} />
            </label>
            {file && check && !done && !busy ? (
              <Btn kind="primary" disabled={!toWrite && !check.failedRows} onClick={() => void run(file.read, false)}>
                {toWrite || check.failedRows ? `Upload: ${check.created} new, ${check.updated} to update` : "Nothing to upload"}
              </Btn>
            ) : null}
            {progress ? <span className="sub2 tnum">{progress.dry ? "Checking" : "Uploading"} {progress.done} of {progress.total}…</span> : null}
          </div>
          {file ? (
            <div className="sub2 mt-2">
              Read as {rollName(file.read.header)}: the headings at row {file.read.headerRow}, {file.read.rows.length} row{file.read.rows.length === 1 ? "" : "s"} to send
              {file.read.repeats.length ? `, ${file.read.repeats.length} repeating a staff number already in the file (not sent)` : ""}.
              {/\.docx$/i.test(file.name) ? " Row numbers count down the Word table, its heading row 1." : ""}
            </div>
          ) : null}
        </PBody>
      </Panel>

      {t ? (
        <>
          <Tiles items={[
            [t.dry ? "New" : "Added", String(t.created), null, academic ? `${t.credentialed} with a sign-in · ${t.granted} with the lecturer office` : "Placed in their posting"],
            [t.dry ? "To update" : "Updated", String(t.updated), null, "The roll fills what the record is missing"],
            ["Unchanged", String(t.unchanged), null, "Nothing missing to fill"],
            [t.dry ? "Will not be loaded" : "Not loaded", String(t.skipped + t.errors), t.skipped + t.errors ? "var(--red-ink)" : null, t.skipped + t.errors ? "See Not loaded below" : "Every row can be loaded"],
          ]} />
          <Note kind={t.skipped || t.errors || t.failedRows ? "bad" : "ok"}
            title={t.dry
              ? (t.skipped || t.errors || t.failedRows ? "Checked: some rows cannot be loaded" : "Checked: every row can be loaded")
              : (t.skipped || t.errors || t.failedRows ? "Uploaded, with rows to follow up" : "The roll is uploaded")}>
            {t.rows} row(s) {t.dry ? "checked" : "read"} · {t.created} {t.dry ? "new" : "added"} · {t.updated} {t.dry ? "to update" : "updated"} · {t.unchanged} unchanged
            {t.skipped ? ` · ${t.skipped} not loaded` : ""}{t.errors ? ` · ${t.errors} with an error` : ""}
            {academic && !t.dry && t.created ? ` · ${t.credentialed} sign-in(s) made, ${t.granted} lecturer office(s) given` : ""}.
            {kept.length ? <> {kept.length} row(s) give a detail the upload does not write (see Not written).</> : null}
            {t.failedRows ? <><br /><b>{t.failedRows} row(s) did not send.</b> {t.dry ? "Check the file again." : "Upload the same file again to fill the gap."}</> : null}
            {t.missing.length ? <><br /><b>Not on the portal, as the roll spells {academic ? "the department" : "the posting"}:</b> {t.missing.join(" · ")}. {academic ? "Ask ICT to add the department (Department upload)" : "Ask ICT to add it or its spelling"}, or correct the cell, and upload again.</> : null}
            {t.firstError ? <><br />First problem: {t.firstError}</> : null}
            {t.dry ? <><br />Nothing has been written yet. Upload to keep it.</> : null}
          </Note>

          <Panel title={t.dry ? "What the upload will do, row by row" : "What the upload did, row by row"}
            right={<Tabs label="Rows" value={view} onChange={setView} items={[
              { id: "changes", label: t.dry ? "New and to update" : "Added and updated", count: changed.length },
              { id: "kept", label: "Not written", count: kept.length },
              { id: "problems", label: "Not loaded", count: problems.length },
              { id: "unresolved", label: "Not resolved", count: unresolved.length },
              { id: "absent", label: "On the portal, not on this roll", count: absent ? absent.length : "…" },
            ]} />}>
            <PBody>
              <div className="row">
                <span className="sub2 grow">
                  {view === "changes" ? "Each row new to the portal, or whose record the roll fills: the field, what the portal held and what the roll gives."
                    : view === "kept" ? `What the roll gives and the upload does not write: for someone on record, a detail the portal holds differently (kept as it is, for HR to look at — ${academic ? "the Edit form on this desk corrects the names, sex, rank, phone, e-mail and department; ask ICT for anything else" : "ask ICT to correct a record where the roll is right"}) and a lecturer office left where it is; for anyone, an e-mail, phone or sign-in the portal cannot take.`
                    : view === "problems" ? "Rows that are not loaded, with the reason. Correct the file, or ask ICT to add the department or posting it names, and upload again."
                    : view === "unresolved" ? "Rows loaded with a cell the portal could not place or read, or a name the roll leaves blank or writes as a query: the record keeps what it held for that field."
                    : `In service on the portal as ${academic ? "teaching" : "non-teaching"} staff${file?.read.header.junior ? " (the JP series)" : academic ? "" : " (the P series)"}, and not on this file. Nobody is ended by this list.`}
                </span>
                <Btn kind="ghost" onClick={() => void exportResult(t)}>Download the result (.xlsx)</Btn>
              </div>
            </PBody>
            {view === "changes" ? (
              changed.length ? (
                <DTable cols={["Row|num", "Staff id", "Name", "|mid", "Changes"]} texts={changed.map(text)} rows={changed.map((r) => [
                  rowCell(r), idCell(r), nameCell(r), actCell(r, t.dry),
                  <span key="c">{r.action === "CREATED"
                    ? <span className="sub2">{r.changes.map((c) => `${fieldWord(c.field)} ${shown(c.to)}`).join(" · ")}</span>
                    : r.changes.map((c, i) => <div key={i} className="sub2">{changeText(c)}</div>)}</span>,
                ])} />
              ) : <PBody><div className="sub2">No row is new or changes a record.</div></PBody>
            ) : view === "kept" ? (
              kept.length ? (
                <DTable cols={["Row|num", "Staff id", "Name", "Not written"]} texts={kept.map(text)} rows={kept.map((r) => [
                  rowCell(r), idCell(r), nameCell(r), <span key="k">{r.kept.map((k, i) => <div key={i} className="sub2">{keptText(k)}</div>)}</span>,
                ])} />
              ) : <PBody><div className="sub2">Every detail on the roll is the portal&apos;s, or fills a blank.</div></PBody>
            ) : view === "problems" ? (
              problems.length ? (
                <DTable cols={["Row|num", "Staff id", "Name", "|mid", "Why"]} texts={problems.map(text)} rows={problems.map((r) => [
                  rowCell(r), idCell(r), nameCell(r), actCell(r, t.dry), <span key="e" className="sub2">{r.error ?? "—"}</span>,
                ])} />
              ) : <PBody><div className="sub2">Every row can be loaded.</div></PBody>
            ) : view === "unresolved" ? (
              unresolved.length ? (
                <DTable cols={["Row|num", "Staff id", "Name", "Not resolved"]} texts={unresolved.map(text)} rows={unresolved.map((r) => [
                  rowCell(r), idCell(r), nameCell(r), <span key="u">{r.unresolved.map((u, i) => <div key={i} className="sub2">{unresolvedText(u)}</div>)}</span>,
                ])} />
              ) : <PBody><div className="sub2">Every cell was placed and read.</div></PBody>
            ) : absentProblem ? (
              <PBody><Note kind="bad" title="The staff not on this roll could not be listed">{absentProblem}</Note></PBody>
            ) : !absent ? (
              <PBody><div className="sub2">Reading the staff on record…</div></PBody>
            ) : absent.length ? (
              <DTable cols={["Staff id", "Name", "Rank", "Posting"]} texts={absent.map((a) => `${a.staff_number} ${a.name} ${a.rank ?? ""} ${a.posting ?? ""}`)} rows={absent.map((a) => [
                <span key="id" className="tnum b700">{a.staff_number}</span>, <span key="n">{a.name}</span>,
                <span key="r" className="sub2">{a.rank ?? "—"}</span>, <span key="p" className="sub2">{a.posting ?? "—"}</span>,
              ])} />
            ) : <PBody><div className="sub2">Everyone in service on the portal is on this roll.</div></PBody>}
          </Panel>
        </>
      ) : null}
    </>
  );
}
