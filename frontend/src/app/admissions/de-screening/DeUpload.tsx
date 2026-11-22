"use client";

/**
 * V773: the CAPS grade windows uploaded — a workbook in the layout of the Direct Entry candidates sheet (the University's two
 * workbooks of 15 November 2026), each row's qualification recorded at once for the candidate on JAMB's live Direct Entry list,
 * registered or not. Read here, checked by the server first (POST …/de-candidates/upload/preview: every row's outcome and problems,
 * nothing written), then recorded (POST …/de-candidates/upload): a row the file carried before unchanged is left as it is, so the
 * same file twice changes nothing. Beside it, a candidate on JAMB's list found by REG NO., to correct one who has not registered.
 */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { xlsxWorkbook } from "@/lib/xlsx";
import { sha256Hex } from "@/lib/caps";
import { parseDeCandidatesWorkbook, type DeUploadRead } from "@/lib/de-candidates";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

/** one row's outcome as the server decided it */
export interface DeUploadOutcome {
  line: number; regNo: string; name?: string | null; programmeCode?: string | null; programme?: string | null;
  outcome: "RECORDED" | "UNCHANGED" | "SKIPPED" | "REPEATED" | string; problems: { level: "ERROR" | "WARNING" | string; text: string }[];
}
export interface DeUploadResult {
  session: string; programme?: string | null; preview: boolean;
  counts: { read: number; recorded: number; unchanged: number; skipped: number; repeated: number; warnings: number };
  rows: DeUploadOutcome[]; uploadId?: string | null;
}
/** a candidate on JAMB's live Direct Entry list, found by REG NO. (GET …/de-candidates/lookup) */
export interface DeLookup { jambKey: string; regNo: string; name?: string | null; programmeCode?: string | null; programme?: string | null; registered: boolean }

/** the rows one request takes */
const MAX_ROWS = 2000;
const OUTCOME: Record<string, [string, "ok" | "grey" | "bad" | "info"]> = {
  RECORDED: ["Recorded", "ok"], UNCHANGED: ["Unchanged", "grey"], SKIPPED: ["Skipped", "bad"], REPEATED: ["Repeated", "info"],
};

export function DeUpload({ session, programme, mayUpload, onFound, onRecorded }: {
  session: string;
  /** the programme chosen on the page (its code), or "" — only for the "another programme" warning */
  programme: string;
  mayUpload: boolean;
  onFound: (c: DeLookup) => void;
  onRecorded: () => void;
}) {
  const base = `/api/bff/api/v1/admissions/sessions/${session}/de-candidates`;
  const [busy, setBusy] = useState<"read" | "preview" | "record" | "find" | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [file, setFile] = useState<{ name: string; sha: string | null; read: DeUploadRead } | null>(null);
  const [result, setResult] = useState<DeUploadResult | null>(null);
  const [regNo, setRegNo] = useState("");
  const [findProblem, setFindProblem] = useState<Problem | null>(null);

  // the page's programme comes from its address: only a programme code is sent (anything else, typed there by hand, would refuse the whole file)
  const body = (f: { name: string; sha: string | null; read: DeUploadRead }) =>
    JSON.stringify({ filename: f.name.slice(0, 255), sha256: f.sha, programme: /^C[0-9]{5}$/.test(programme) ? programme : null, rows: f.read.rows });

  async function post(path: string, f: { name: string; sha: string | null; read: DeUploadRead }, reason: string): Promise<DeUploadResult | null> {
    const r = await fetch(`${base}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body(f) });
    const j = await r.json().catch(() => null);
    if (!r.ok) {
      const refusal = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText };
      setProblem(refusal); notifyProblem(refusal);
      return null;
    }
    return j as DeUploadResult;
  }

  async function choose(chosen: File) {
    setBusy("read");
    setProblem(null);
    setResult(null);
    setFile(null);
    try {
      const buf = await chosen.arrayBuffer();
      let read: DeUploadRead;
      try {
        read = parseDeCandidatesWorkbook(await xlsxWorkbook(buf, { rowNumbers: true }));
      } catch {
        const refusal = { status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx in the layout of the Direct Entry candidates sheet." };
        setProblem(refusal); notifyProblem(refusal);
        return;
      }
      const sha = await sha256Hex(buf).catch(() => null);
      const f = { name: chosen.name, sha, read };
      setFile(f);
      if (!read.rows.length) return;
      if (read.rows.length > MAX_ROWS) {
        setProblem({ status: 400, title: `The file holds ${read.rows.length.toLocaleString()} candidates' rows; one upload takes at most ${MAX_ROWS.toLocaleString()}.`, detail: "Split it by programme and upload each part." });
        return;
      }
      setBusy("preview");
      setResult(await post("/upload/preview", f, "Preview of a Direct Entry qualification upload"));
    } finally {
      setBusy(null);
    }
  }

  async function record() {
    if (!file) return;
    setBusy("record");
    setProblem(null);
    try {
      const done = await post("/upload", file, `Direct Entry qualifications uploaded from ${file.name} (${file.read.rows.length} rows)`);
      if (!done) return;
      setResult(done);
      notify(`${done.counts.recorded} recorded, ${done.counts.unchanged} unchanged, ${done.counts.skipped} skipped`);
      onRecorded();
    } finally {
      setBusy(null);
    }
  }

  async function find() {
    const q = regNo.trim();
    if (!q) return;
    setBusy("find");
    setFindProblem(null);
    try {
      const r = await fetch(`${base}/lookup?regNo=${encodeURIComponent(q)}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (r.ok && j) { onFound(j as DeLookup); setRegNo(""); }
      else setFindProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText || "No such candidate." });
    } catch {
      setFindProblem({ status: 0, title: "The network dropped the request.", detail: "Try again in a moment." });
    } finally {
      setBusy(null);
    }
  }

  const c = result?.counts;
  const preview = !!result?.preview;
  return (
    <Panel title="Upload the CAPS grade windows" right={session}>
      <PBody>
        <div className="sub2">
          A workbook in the layout of the Direct Entry candidates sheet: each row&rsquo;s qualification is recorded for the candidate on
          JAMB&rsquo;s live Direct Entry list; a qualification typed here by hand is kept unless the file carries the same kind.
        </div>
        {mayUpload ? (
          <div className="row mt-2">
            <label className="btn btn--primary" style={{ cursor: busy ? "default" : "pointer", margin: 0 }}>
              {busy === "read" ? "Reading the file…" : busy === "preview" ? "Checking every row…" : "Choose the workbook (.xlsx)"}
              <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy !== null} onChange={(e) => { const f = e.target.files?.[0]; if (f) void choose(f); e.target.value = ""; }} />
            </label>
            {file ? <span className="sub2">{file.name}{file.read.sheet ? ` · sheet “${file.read.sheet}”, header on row ${file.read.headerLine} · ${file.read.rows.length} row${file.read.rows.length === 1 ? "" : "s"} read` : ""}</span> : null}
          </div>
        ) : <div className="sub2 mt-2">Uploading is the Academic Office&rsquo;s or the Registrar&rsquo;s.</div>}
        {problem ? <ProblemNotice problem={problem} /> : null}
        {file?.read.problems.length ? (
          <Note kind={file.read.rows.length ? "info" : "bad"} title={file.read.rows.length ? `${file.read.problems.length} line${file.read.problems.length === 1 ? "" : "s"} of the file not sent` : "Nothing in the file could be read"}>
            {file.read.problems.slice(0, 50).map((p, i) => <div key={i}>{p}</div>)}
            {file.read.problems.length > 50 ? <div>…and {file.read.problems.length - 50} more.</div> : null}
          </Note>
        ) : null}
        {result && c ? (
          <div className="mt-3">
            <Tiles cls="grid--5" items={[
              ["Read", String(c.read), null, "Rows in the file"],
              [preview ? "To record" : "Recorded", String(c.recorded), c.recorded ? "var(--green-ink)" : null, preview ? "New or changed" : "Written now"],
              ["Unchanged", String(c.unchanged), null, "Already as the file says"],
              ["Skipped", String(c.skipped), c.skipped ? "var(--red-ink)" : null, "Not recorded: see the problems"],
              ["With warnings", String(c.warnings), c.warnings ? "var(--amber-ink)" : null, "Recorded, worth a look"],
            ]} />
            {preview && mayUpload ? (
              <div className="row mt-2">
                <Btn kind="primary" disabled={busy !== null || !c.recorded} onClick={() => void record()}>{busy === "record" ? "Recording…" : `Record ${c.recorded}`}</Btn>
                <span className="sub2">{c.recorded ? "Nothing is written until you record." : "Nothing in the file would change what is recorded."}</span>
              </div>
            ) : null}
            {!preview ? <Note kind="ok" title={`${c.recorded} recorded, ${c.unchanged} unchanged, ${c.skipped} skipped`}>{c.repeated ? `${c.repeated} repeated line${c.repeated === 1 ? "" : "s"} recorded once. ` : ""}Choose the corrected file again to put a skipped row right.</Note> : null}
            <DTable
              cols={["Line|num", "REG NO.", "Candidate", "Programme", "Outcome|mid", "Problems"]}
              texts={result.rows.map((r) => `${r.regNo} ${r.name ?? ""} ${r.programme ?? ""} ${r.outcome} ${r.problems.map((p) => p.text).join(" ")}`)}
              rows={result.rows.map((r) => {
                const [word, kind] = OUTCOME[r.outcome] ?? [r.outcome, "grey" as const];
                return [
                  <span className="tnum" key="l">{r.line}</span>,
                  <span className="tnum" key="r">{r.regNo}</span>,
                  r.name ? <span key="n">{r.name}</span> : <span className="sub2" key="n">Not on JAMB&rsquo;s list</span>,
                  r.programme ? <Two key="p" a={r.programme} b={r.programmeCode ?? ""} /> : <span className="sub2" key="p">—</span>,
                  <Pil kind={kind} key="o">{preview && r.outcome === "RECORDED" ? "To record" : word}</Pil>,
                  <span key="x">{r.problems.length ? r.problems.map((p, i) => (
                    <div key={i} style={{ color: p.level === "ERROR" ? "var(--red-ink)" : "var(--amber-ink)" }}>{p.text}</div>
                  )) : <span className="sub2">—</span>}</span>,
                ];
              })}
            />
          </div>
        ) : null}

        <div className="row row--end mt-4" style={{ gap: "var(--s-3)" }}>
          <Field id="de-find" label="Find a candidate on JAMB's Direct Entry list by REG NO." hint="To record or correct the qualification of a candidate who has not registered on the portal">
            <input id="de-find" className="ctl tnum" value={regNo} autoComplete="off" onChange={(e) => setRegNo(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); void find(); } }} style={{ minWidth: 220 }} />
          </Field>
          <Btn kind="ghost" disabled={busy !== null || !regNo.trim()} onClick={() => void find()}>{busy === "find" ? "Finding…" : "Find"}</Btn>
        </div>
        {findProblem ? <ProblemNotice problem={findProblem} /> : null}
      </PBody>
    </Panel>
  );
}
