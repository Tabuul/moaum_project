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
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";

interface Report { received: number; applied: number; notFound: string[]; alreadyReleased: string[]; outOfRange: string[] }

export interface PostUtmeRow { programme_code: string; programme: string; faculty: string | null; registered: number; scored: number; released: number; awaiting: number }
export interface PostUtme { session: string; counts: { programmes: number; awaitingScores: number }; programmes: PostUtmeRow[] }

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

export function ScoreUpload({ session, sessions, actingOffice, postUtme }: { session: string; sessions: string[]; actingOffice: string | null; postUtme: PostUtme | null }) {
  const router = useRouter();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [report, setReport] = useState<Report | null>(null);
  const [released, setReleased] = useState<number | null>(null);
  const [clearProg, setClearProg] = useState("");
  const [clearConfirm, setClearConfirm] = useState("");
  const [cleared, setCleared] = useState<number | null>(null);
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

  async function clearScores() {
    setBusy(true);
    setProblem(null);
    setCleared(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/clear`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Post-UTME scores cleared for ${session}${clearProg ? ` · ${clearProg}` : ""}`) },
        body: JSON.stringify({ programmeCode: clearProg || null, confirm: clearConfirm.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setCleared(Number((j as { cleared: number }).cleared));
      setClearConfirm("");
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

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
      // upload in chunks so no single request is long enough to time out, and a transient failure
      // (a deploy restart, a blip) retries that chunk instead of failing the whole upload. Re-uploading
      // is safe — a score is simply re-entered. Results are summed across chunks.
      const CHUNK = 500;
      const total: Report = { received: 0, applied: 0, notFound: [], alreadyReleased: [], outOfRange: [] };
      for (let i = 0; i < rows.length; i += CHUNK) {
        const slice = rows.slice(i, i + CHUNK);
        let done = false;
        for (let attempt = 1; attempt <= 5 && !done; attempt++) {
          const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/upload`, {
            method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Post-UTME scores uploaded for ${session}: rows ${i + 1}–${i + slice.length}`) },
            body: JSON.stringify({ rows: slice }),
          }).catch(() => null);
          const j = r ? await r.json().catch(() => null) : null;
          if (r && r.ok && j) {
            const c = j as Report;
            total.received += c.received ?? 0;
            total.applied += c.applied ?? 0;
            total.notFound.push(...(c.notFound ?? []));
            total.alreadyReleased.push(...(c.alreadyReleased ?? []));
            total.outOfRange.push(...(c.outOfRange ?? []));
            setReport({ ...total });
            done = true;
            break;
          }
          const transient = !r || r.status >= 500 || r.status === 429;
          if (!transient) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r ? r.status : 0, title: r ? r.statusText : "network" }); return; }
          if (attempt < 5) { await new Promise((res) => setTimeout(res, 1500 * attempt)); }
        }
        if (!done) { setProblem({ status: 503, title: "The upload kept failing after retries. What uploaded so far is kept — wait a moment and upload again; scores already entered are simply re-entered." } as Problem); return; }
      }
    } finally {
      setBusy(false);
    }
  }

  // download the applicants still awaiting a score for a programme (or all), as a fill-in template:
  // JAMB Number, Name, Programme, Score — fill Score and load it straight back to upload
  async function downloadAwaiting(code: string | null, label: string) {
    const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/awaiting${code ? `?programme=${encodeURIComponent(code)}` : ""}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok || !Array.isArray(j)) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
    const rows = (j as { jamb_reg_no: string; name: string; programme: string }[]).map((x) => [x.jamb_reg_no, x.name, x.programme, ""]);
    const blob = buildXlsx(["JAMB Number", "Name", "Programme", "Score"], rows, "Awaiting scores");
    downloadBlob(blob, `awaiting-scores-${label.replace(/[^a-z0-9]+/gi, "-")}-${session.replace("/", "-")}.xlsx`);
  }

  // score every remaining unscored applicant as zero — the deliberate finalising step for stragglers
  async function zeroMissing(code: string | null, label: string, count: number) {
    if (!window.confirm(`Score the ${count.toLocaleString()} remaining applicant${count === 1 ? "" : "s"} in ${label} with no Post-UTME score as ZERO? Do this only once you have finished uploading real scores — it decides the stragglers as non-qualified. A real score uploaded later still overrides (until it is released).`)) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/zero-missing${code ? `?programme=${encodeURIComponent(code)}` : ""}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Remaining unscored applicants scored zero for ${session}${code ? ` · ${label}` : ""}`) }, body: "{}",
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <Note kind="info" title="Upload the Post-UTME scores and reconcile them against the applicants">
        The scores collected from the CBT exam, uploaded here by the Directorate of ICT, the Super Administrator or the Academic Office. Each row is keyed by the candidate&rsquo;s <b>JAMB registration number</b> or <b>application number</b> and reconciled against the session&rsquo;s applicants: a matched candidate whose score is not yet released has it entered; the rest are reported and nothing is invented. Releasing the scores is done from the Applicants desk.
      </Note>

      {postUtme ? (
        <Panel title="Programmes whose Post-UTME scores must be uploaded" right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}>
          <span className="sub2">{postUtme.counts.awaitingScores ? `${postUtme.counts.awaitingScores} still awaiting` : "All scored"}</span>
          {postUtme.programmes.some((r) => Number(r.awaiting) > 0) ? <>
            <Btn kind="ghost" disabled={busy} onClick={() => void downloadAwaiting(null, "all")}>Download all awaiting</Btn>
            <Btn kind="ghost" disabled={busy} onClick={() => void zeroMissing(null, "all programmes", postUtme.programmes.reduce((n, r) => n + Number(r.awaiting), 0))}>Score remaining as zero</Btn>
          </> : null}
        </span>}>
          <div className="card__body" style={{ paddingBottom: 0 }}>
            <div className="sub2">These are the programmes whose applicants have registered for Post-UTME for {session}. Every one must have its screening scores uploaded and released before the admission process (merit list, offers) proceeds for it. A programme still awaiting scores is highlighted.</div>
          </div>
          {postUtme.programmes.length ? (
            <DTable
              cols={["Faculty", "Programme", "Registered|num", "Scored|num", "Released|num", "Awaiting|num", "Status|mid"]}
              rows={postUtme.programmes.map((r) => [
                <span key="f">{r.faculty ?? "—"}</span>,
                <span key="p">{r.programme}</span>,
                <span className="tnum" key="rg">{Number(r.registered).toLocaleString()}</span>,
                <span className="tnum" key="sc">{Number(r.scored).toLocaleString()}</span>,
                <span className="tnum" key="rl">{Number(r.released).toLocaleString()}</span>,
                Number(r.awaiting) ? <button key="aw" onClick={() => void downloadAwaiting(r.programme_code, r.programme)} title={`Download the ${Number(r.awaiting).toLocaleString()} applicants awaiting a score`} className="tnum" style={{ background: "none", border: 0, padding: 0, color: "var(--red-ink)", fontWeight: 700, textDecoration: "underline", cursor: "pointer" }}>{Number(r.awaiting).toLocaleString()}</button> : <span className="tnum" key="aw">0</span>,
                Number(r.awaiting) ? <Pil kind="bad" key="s">Scores due</Pil> : Number(r.released) >= Number(r.registered) ? <Pil kind="ok" key="s">Released</Pil> : <Pil kind="warn" key="s">Uploaded, release</Pil>,
              ])}
              texts={postUtme.programmes.map((r) => `${r.faculty ?? ""} ${r.programme}`)}
            />
          ) : <PBody><div className="sub2">No applicant has registered for Post-UTME this session yet. Programmes appear here as applicants register.</div></PBody>}
        </Panel>
      ) : null}

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

      <Panel title="Clear uploaded Post-UTME scores" right="For scores uploaded in error">
        <PBody>
          <Note kind="bad" title="Remove uploaded Post-UTME scores">
            Use this only when Post-UTME scores were uploaded in error — for a programme that is not exam-screened, or a
            wrong file. It removes the score, its entry and its release for {session}, so the register falls back to the
            O&rsquo;Level + UTME computation. It <b>cannot be undone</b>; re-upload the correct scores if needed.
          </Note>
          {cleared !== null ? <Note kind="ok" title={`${cleared} score${cleared === 1 ? "" : "s"} cleared`}>Those candidates no longer carry a Post-UTME score for {session}.</Note> : null}
          <div style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
            <div className="field" style={{ minWidth: 260, margin: 0 }}><label htmlFor="cs-prog">Programme</label>
              <select id="cs-prog" className="ctl" value={clearProg} onChange={(e) => { setClearProg(e.target.value); setCleared(null); }}>
                <option value="">All programmes ({session})</option>
                {(postUtme?.programmes ?? []).filter((p) => Number(p.scored) > 0).map((p) => <option key={p.programme_code} value={p.programme_code}>{p.programme} — {p.scored} scored</option>)}
              </select>
            </div>
            <div className="field" style={{ minWidth: 180, margin: 0 }}><label htmlFor="cs-confirm">Type CLEAR SCORES</label>
              <input id="cs-confirm" className="ctl tnum" value={clearConfirm} onChange={(e) => setClearConfirm(e.target.value)} placeholder="CLEAR SCORES" autoComplete="off" />
            </div>
            <Btn kind="urgent" disabled={!mayRelease || busy || clearConfirm.trim().toUpperCase() !== "CLEAR SCORES"} onClick={() => void clearScores()}>{busy ? "Clearing…" : "Clear scores"}</Btn>
          </div>
          {!mayRelease ? <div className="sub2" style={{ marginTop: 6 }}>Only the Academic Office or Registry may clear scores.</div> : null}
        </PBody>
      </Panel>
    </>
  );
}
