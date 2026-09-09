"use client";

/** tScores — bulk Post-UTME score upload. Paste or load rows keyed by JAMB number or application
 *  number; each is reconciled against the session's applicants and the matched scores are entered. */
import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Report { received: number; applied: number; notFound: string[]; alreadyReleased: string[]; outOfRange: string[] }

/** parse pasted/loaded text: one row per line, "key<sep>score" (comma, tab, or spaces); a header line is skipped */
function parse(text: string): { key: string; score: number }[] {
  const out: { key: string; score: number }[] = [];
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!t) continue;
    const m = t.split(/[,\t;]+|\s{2,}|\s+(?=\d+(?:\.\d+)?$)/).map((x) => x.trim()).filter(Boolean);
    if (m.length < 2) continue;
    const key = m[0];
    const score = Number(m[m.length - 1]);
    if (!Number.isFinite(score)) continue; // header or malformed → skip
    out.push({ key, score });
  }
  return out;
}

export function ScoreUpload({ session, sessions, actingOffice }: { session: string; sessions: string[]; actingOffice: string | null }) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [report, setReport] = useState<Report | null>(null);
  const [released, setReleased] = useState<number | null>(null);
  const file = useRef<HTMLInputElement | null>(null);
  const rows = parse(text);
  const mayRelease = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");

  async function release() {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/release`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Screening scores released for ${session}`) }, body: "{}",
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setReleased(Number((j as { released: number }).released));
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  function pick(s: string) { router.push(`/admissions/scores?session=${encodeURIComponent(s)}`); }

  async function loadFile(f: File) {
    const t = await f.text();
    setText((prev) => (prev.trim() ? prev + "\n" : "") + t);
  }

  function downloadTemplate() {
    const csv = "JAMB number or Application number,Score (0-100)\r\n20261234AB,68.5\r\nAPP/26/000002,72\r\n";
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `post-utme-score-template-${session.replace("/", "-")}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }

  async function upload() {
    setBusy(true);
    setProblem(null);
    setReport(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/upload`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Post-UTME scores uploaded for ${session}`) },
        body: JSON.stringify({ rows }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setReport(j as Report);
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Upload the Post-UTME scores and reconcile them against the applicants">
        The scores collected from the CBT exam, uploaded here by the Directorate of ICT, the Super Administrator or the Academic Office. Each row is keyed by the candidate&rsquo;s <b>JAMB registration number</b> or <b>application number</b> and reconciled against the session&rsquo;s applicants: a matched candidate whose score is not yet released has it entered; the rest are reported and nothing is invented. Releasing the scores is done from the Applicants desk.
      </Note>

      <Panel title="Post-UTME scores" right={
        <select className="ws__select" value={session} onChange={(e) => pick(e.target.value)} aria-label="Session">
          {(sessions.length ? sessions : [session]).map((s) => <option key={s} value={s}>{s}</option>)}
        </select>
      }>
        <PBody>
          <div className="sub2" style={{ marginBottom: 8 }}>One candidate per line: the JAMB number or application number, then the score (0&ndash;100), separated by a comma, tab or spaces. A header line is ignored. Paste from a spreadsheet, or load a CSV.</div>
          <textarea className="ctl" rows={10} value={text} onChange={(e) => setText(e.target.value)} placeholder={"20261234AB, 68.5\n20265678CD, 72\nAPP/26/000002, 55"} style={{ fontFamily: "var(--mono, monospace)", width: "100%" }} />
          <input ref={file} type="file" accept=".csv,text/csv,text/plain" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void loadFile(f); e.target.value = ""; }} />
          {problem ? <ProblemNotice problem={problem} /> : null}
          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center", marginTop: 8 }}>
            <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
            <Btn kind="ghost" onClick={() => file.current?.click()}>Load a CSV</Btn>
            <Btn kind="primary" disabled={busy || !rows.length} onClick={() => void upload()}>{busy ? "Uploading…" : `Upload ${rows.length} score${rows.length === 1 ? "" : "s"}`}</Btn>
            {text.trim() ? <Btn kind="ghost" onClick={() => { setText(""); setReport(null); }}>Clear</Btn> : null}
            <span className="sub2">{rows.length} row{rows.length === 1 ? "" : "s"} parsed</span>
          </div>
        </PBody>
      </Panel>

      {report ? (
        <>
          <Tiles items={[
            ["Received", String(report.received), null, "Rows read"],
            ["Applied", String(report.applied), report.applied ? "var(--green-ink)" : null, "Matched and entered"],
            ["Not matched", String(report.notFound.length), report.notFound.length ? "var(--red-ink)" : null, "No applicant on this session"],
            ["Skipped", String(report.alreadyReleased.length + report.outOfRange.length), (report.alreadyReleased.length + report.outOfRange.length) ? "var(--chrome)" : null, "Released or out of range"],
          ]} />
          {report.notFound.length || report.alreadyReleased.length || report.outOfRange.length ? (
            <Panel title="Reconciliation" right="Rows that were not applied">
              <DTable cols={["Key", "Why|num"]} rows={[
                ...report.notFound.map((k) => [<span className="tnum" key="k">{k}</span>, <Pil kind="bad" key="w">No applicant match</Pil>]),
                ...report.alreadyReleased.map((k) => [<span className="tnum" key="k">{k}</span>, <Pil kind="info" key="w">Score already released</Pil>]),
                ...report.outOfRange.map((k) => [<span className="tnum" key="k">{k}</span>, <Pil kind="grey" key="w">Score out of 0–100</Pil>]),
              ]} />
            </Panel>
          ) : <Note kind="ok" title="Every row reconciled and applied">All {report.applied} scores matched an applicant and were entered.</Note>}
        </>
      ) : null}

      <Panel title="Release the scores" right="Held until released; the Board decides on released scores">
        <PBody>
          <div className="sub2" style={{ marginBottom: 8 }}>An uploaded score is entered but <b>held</b> until it is released — a candidate&rsquo;s aggregate and the Board&rsquo;s decision both wait on it. Releasing publishes every entered score for {session} (seated or uploaded) and notifies each applicant.</div>
          {released !== null ? <Note kind="ok" title={`${released} score${released === 1 ? "" : "s"} released for ${session}`}>They are no longer held; the Board can now decide, and each applicant has been notified.</Note> : null}
          <Btn kind="primary" disabled={!mayRelease || busy} onClick={() => void release()}>{busy ? "Releasing…" : "Release scores"}</Btn>
          {!mayRelease ? <div className="sub2" style={{ marginTop: 6 }}>Releasing is the Academic Office&rsquo;s act; ask them to release, or release from the Applicants desk.</div> : null}
        </PBody>
      </Panel>
    </>
  );
}
