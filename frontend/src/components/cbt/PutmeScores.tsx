"use client";
/** V385: the Post-UTME CBT scores desk. For the Directorate of ICT (mode "ict"): every applicant's best approved attempt, the official score
 *  file generated, downloaded and sent to the Academic Office. For the Academic Office (mode "academic"): the files it was sent — received,
 *  downloaded, previewed line by line and imported into the applications' screening scores, or rejected with a reason. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, downloadBlob } from "@/lib/exportbrand";
import { num, whenAt } from "@/lib/cbt";
import { EXPORT_WORD, PREVIEW_WORD, type PreviewRow, type PutmeExport, type PutmeImportSummary, type PutmeScoresPage } from "@/lib/putme-cbt";

const HEAD = ["JAMB Number", "Candidate Name", "Application Number", "Faculty", "Department", "Programme", "Admission Session", "Examination", "Total Questions", "Questions Attempted", "Total Marks", "Score", "Percentage", "Exam Date", "Submission Status", "Result Status"];

export function PutmeScores({ page, mode, acting }: { page: PutmeScoresPage; mode: "ict" | "academic"; acting: string | null }) {
  const router = useRouter();
  const go = useQueryNav();
  const s = page.session;
  const path = `/api/bff/api/v1/admissions/sessions/${s}/putme-scores`;
  const mayExport = mode === "ict" && ["ict", "super"].includes(acting ?? "");
  const mayImport = mode === "academic" && ["academic", "registrar", "dregistrar", "super"].includes(acting ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [exportExam, setExportExam] = useState("");
  const [send, setSend] = useState<PutmeExport | null>(null);
  const [message, setMessage] = useState("");
  const [note, setNote] = useState<{ x: PutmeExport; action: "cancel" | "reject" } | null>(null);
  const [reason, setReason] = useState("");
  const [preview, setPreview] = useState<(Omit<PutmeExport, "rows"> & { rows: PreviewRow[]; summary: Record<string, number> }) | null>(null);
  const [importMode, setImportMode] = useState<"KEEP" | "REPLACE">("KEEP");
  const [importReason, setImportReason] = useState("");
  const here = mode === "ict" ? "/ict/putme-scores" : "/admissions/putme-scores";
  const q = (patch: Record<string, string>) => {
    const p = new URLSearchParams();
    p.set("session", patch.session ?? s);
    for (const k of ["exam", "q", "status", "prog", "fac"]) { const v = k in patch ? patch[k] : (typeof window !== "undefined" ? new URLSearchParams(window.location.search).get(k) ?? "" : ""); if (v) p.set(k, v); }
    return `${here}?${p.toString()}`;
  };

  async function call(url: string, body: unknown, why: string): Promise<Record<string, unknown> | null> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
      return j as Record<string, unknown>;
    } finally { setBusy(false); }
  }

  async function generate() {
    const j = await call(`${path}/exports`, { examId: exportExam || null }, `Generate the official Post-UTME score file for ${s}`);
    if (j) { notify(`${j.reference} generated: ${num(j.rows_count as number)} candidates`); router.refresh(); }
  }
  async function download(x: PutmeExport) {
    setBusy(true);
    try {
      const r = await fetch(`${path}/exports/${x.id}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      const rows = (j.rows as PutmeExport["rows"]) ?? [];
      const body = rows.map((c) => [c.jamb_reg_no, c.candidate_name, c.application_no ?? "", c.faculty ?? "", c.department ?? "", c.programme ?? "", x.session, c.exam_title ?? "", c.questions ?? "", c.attempted ?? "", c.max_marks ?? "", c.score == null ? "" : Number(c.score), Number(c.percentage), c.exam_date ? whenAt(c.exam_date) : "", c.attempt_status ?? "", c.outcome === "VOID" ? "Void" : "Scored"]);
      downloadBlob(await brandedXlsx("Post-UTME CBT Scores", HEAD, body, { sheetName: "Scores", serial: x.reference, sub: `${x.reference} · ${x.session}${x.exam_title ? ` · ${x.exam_title}` : ""} · ${num(x.rows_count)} candidates · SHA-256 ${x.sha256.slice(0, 16)}…`, meta: [["File hash (SHA-256)", x.sha256], ["Generated", whenAt(x.generated_at)], ["Generated by", x.generated_by_name ?? ""]] }), `${x.reference}.xlsx`);
      if (mode === "academic" && mayImport && ["SENT_TO_ACADEMIC", "RECEIVED", "DOWNLOADED"].includes(x.state)) {
        await call(`${path}/exports/${x.id}/DOWNLOAD`, {}, `Download the Post-UTME score file ${x.reference}`);
        router.refresh();
      }
    } catch (e) { notifyProblem({ status: 500, title: "The spreadsheet could not be built", detail: e instanceof Error ? e.message : String(e) }); }
    finally { setBusy(false); }
  }
  async function doSend() {
    if (!send) return;
    const j = await call(`${path}/exports/${send.id}/send`, { message: message.trim() || null }, `Send the Post-UTME score file ${send.reference} to the Academic Office`);
    if (j) { notify(`${send.reference} sent to the Academic Office`); setSend(null); setMessage(""); router.refresh(); }
  }
  async function doNote() {
    if (!note) return;
    if (!reason.trim()) { notifyProblem({ status: 422, title: "Give the reason; it goes on the record." }); return; }
    const url = note.action === "cancel" ? `${path}/exports/${note.x.id}/cancel` : `${path}/exports/${note.x.id}/REJECT`;
    const j = await call(url, { reason: reason.trim() }, `${note.action === "cancel" ? "Cancel" : "Reject"} the Post-UTME score file ${note.x.reference}: ${reason.trim()}`);
    if (j) { notify(`${note.x.reference} ${note.action === "cancel" ? "cancelled" : "rejected"}`); setNote(null); setReason(""); router.refresh(); }
  }
  async function receive(x: PutmeExport) {
    const j = await call(`${path}/exports/${x.id}/RECEIVE`, {}, `Receive the Post-UTME score file ${x.reference}`);
    if (j) { notify(`${x.reference} received`); router.refresh(); }
  }
  async function openPreview(x: PutmeExport) {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`${path}/exports/${x.id}/preview`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setPreview(j); setImportMode("KEEP"); setImportReason("");
    } finally { setBusy(false); }
  }
  async function doImport() {
    if (!preview) return;
    if (importMode === "REPLACE" && !importReason.trim()) { notifyProblem({ status: 422, title: "Replacing scores already on the record names the reason." }); return; }
    const j = await call(`${path}/exports/${preview.id}/import`, { mode: importMode, reason: importReason.trim() || null }, `Import the Post-UTME score file ${preview.reference} (${importMode.toLowerCase()} existing scores)`);
    if (j) {
      const imp = j.import as Record<string, number>;
      notify(`${preview.reference} imported: ${num(imp.applied)} entered, ${num(imp.replaced)} replaced, ${num(imp.kept)} kept, ${num(imp.released)} released and untouched`);
      setPreview(null); router.refresh();
    }
  }

  const imports = (x: PutmeExport): PutmeImportSummary[] => { try { return x.imports ? (JSON.parse(x.imports) as PutmeImportSummary[]) : []; } catch { return []; } };
  const c = page.counts;
  const files = mode === "academic" ? page.exports.filter((x) => x.state !== "GENERATED" && x.state !== "CANCELLED") : page.exports;

  return (
    <>
      <PageHead title={mode === "ict" ? "Post-UTME CBT scores" : "Post-UTME score files"} description={mode === "ict" ? `Every applicant's best approved CBT attempt of ${s}; the official file is generated here and sent to the Academic Office` : `The official Post-UTME score files the Directorate of ICT sent for ${s}: receive, download, preview and import into the applications' screening scores`}
        actions={<span className="row row--inline row--tight">
          <label htmlFor="ps-session" className="sub2">Session</label>
          <input id="ps-session" className="ctl tnum" style={{ width: 110 }} defaultValue={s} onBlur={(e) => { if (/^\d{4}\/\d{4}$/.test(e.target.value) && e.target.value !== s) go(q({ session: e.target.value })); }} />
          {mode === "academic" ? <LinkBtn kind="ghost" href={`/admissions/scores?session=${encodeURIComponent(s)}`}>Release scores</LinkBtn> : null}
        </span>} />
      {problem ? <Note kind="bad" title={problem.title}>{problem.detail ?? ""}</Note> : null}
      <Tiles items={[
        ["APPLICANTS", num(c.applicants), null, `${num(c.scored)} with a CBT score`],
        ["OFFICIAL", num(c.official), c.official ? "var(--green-ink)" : null, "Results approved by the Directorate"],
        ["EXPORTED", num(c.exported), null, `${num(page.exports.filter((x) => x.state !== "CANCELLED" && x.state !== "REJECTED").length)} files`],
        ["IMPORTED", num(c.imported), null, "On the applications' record"],
        ["RELEASED", num(c.released), null, "Released by the Academic Office"],
        ["AVERAGE", c.average == null ? "—" : `${Number(c.average).toFixed(1)}%`, null, c.highest == null ? "No official score yet" : `highest ${Number(c.highest).toFixed(1)} · lowest ${Number(c.lowest).toFixed(1)}`],
      ]} />
      {mode === "ict" ? (
        <Panel title="Examinations of the session" right={mayExport ? <span className="row row--inline row--tight">
          <select className="ctl" value={exportExam} onChange={(e) => setExportExam(e.target.value)}><option value="">Every approved examination</option>{page.exams.map((e) => <option key={e.id} value={e.id}>{e.title} · results {e.results_state.toLowerCase().replace("_", " ")}</option>)}</select>
          <Btn kind="primary" disabled={busy || !c.official} onClick={() => void generate()}>{busy ? "Working…" : "Generate official score file"}</Btn>
        </span> : null}>
          {page.exams.length ? <DTable cols={["Reference", "Examination", "State|mid", "Results|mid", "Window", "Sat|num", "|num"]} rows={page.exams.map((e) => [
            <span key="r" className="tnum">{e.reference}</span>, <b key="t">{e.title}</b>, <Pil key="s" kind="grey">{e.live_state}</Pil>,
            <Pil key="x" kind={e.results_state === "APPROVED" || e.results_state === "PUBLISHED" ? "ok" : "warn"}>{e.results_state.replace("_", " ")}</Pil>,
            <span key="w" className="sub2 tnum">{e.starts_at ? `${whenAt(e.starts_at)} → ${whenAt(e.ends_at)}` : "—"}</span>, <span key="n" className="tnum">{num(e.sat)}</span>,
            <LinkBtn key="o" kind="ghost" size="sm" href={`/ict/cbt/${e.id}?tab=results`}>Open</LinkBtn>,
          ])} /> : <PBody><div className="sub2">No Post-UTME examination for {s} yet. Create one under Post-UTME CBT Examinations.</div></PBody>}
          <PBody><div className="sub2">A file is generated from examinations whose results are approved; review and approve them on each examination first. Candidates never see a score here: the Academic Office imports the file and releases the scores.</div></PBody>
        </Panel>
      ) : null}
      <Panel title={mode === "ict" ? "Official score files" : "Files from the Directorate of ICT"} right={<span className="sub2">{files.length} file{files.length === 1 ? "" : "s"}</span>}>
        {files.length ? <DTable cols={["Reference", "Examination", "Candidates|num", "State|mid", "Generated", "Sent", "Hash", "|num"]} rows={files.map((x) => [
          <span key="r"><b className="tnum">{x.reference}</b>{x.message ? <div className="sub2">“{x.message}”</div> : null}{x.closing_note ? <div className="sub2">{x.state === "REJECTED" ? "Rejected" : "Cancelled"}: {x.closing_note}</div> : null}
            {imports(x).map((i) => <div key={i.id} className="sub2">Imported {whenAt(i.importedAt)}{i.importedBy ? ` by ${i.importedBy}` : ""}: {num(i.applied)} entered · {num(i.unchanged)} same · {num(i.replaced)} replaced · {num(i.kept)} kept · {num(i.released)} released · {num(i.notFound)} not found{i.reason ? ` — ${i.reason}` : ""}</div>)}</span>,
          <span key="e" className="sub2">{x.exam_title ?? "Every approved examination"}</span>, <span key="n" className="tnum">{num(x.rows_count)}</span>,
          <Pil key="s" kind={(EXPORT_WORD[x.state] ?? ["", "grey"])[1]}>{(EXPORT_WORD[x.state] ?? [x.state])[0]}</Pil>,
          <span key="g" className="sub2 tnum">{whenAt(x.generated_at)}{x.generated_by_name ? ` · ${x.generated_by_name}` : ""}</span>,
          <span key="t" className="sub2 tnum">{x.sent_at ? `${whenAt(x.sent_at)}${x.sent_by_name ? ` · ${x.sent_by_name}` : ""}` : "—"}</span>,
          <span key="h" className="sub2 tnum" title={x.sha256}>{x.sha256.slice(0, 12)}…</span>,
          <span key="a" className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
            <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void download(x)}>Download</Btn>
            {mayExport && x.state === "GENERATED" ? <Btn kind="go" size="sm" disabled={busy} onClick={() => { setSend(x); setMessage(""); }}>Send to Academic Office</Btn> : null}
            {mayExport && !["IMPORTED", "CANCELLED", "REJECTED"].includes(x.state) ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setNote({ x, action: "cancel" }); setReason(""); }}>Cancel</Btn> : null}
            {mayImport && x.state === "SENT_TO_ACADEMIC" ? <Btn kind="secondary" size="sm" disabled={busy} onClick={() => void receive(x)}>Confirm receipt</Btn> : null}
            {mayImport && ["SENT_TO_ACADEMIC", "RECEIVED", "DOWNLOADED", "IMPORTED"].includes(x.state) ? <Btn kind="primary" size="sm" disabled={busy} onClick={() => void openPreview(x)}>{x.state === "IMPORTED" ? "Preview again" : "Preview & import"}</Btn> : null}
            {mayImport && ["SENT_TO_ACADEMIC", "RECEIVED", "DOWNLOADED"].includes(x.state) ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setNote({ x, action: "reject" }); setReason(""); }}>Reject</Btn> : null}
          </span>,
        ])} texts={files.map((x) => `${x.reference} ${x.state}`)} /> : <PBody><div className="sub2">{mode === "ict" ? "No official score file generated yet." : "No score file has been sent for this session."}</div></PBody>}
      </Panel>
      {mode === "ict" ? (
        <Panel title={`Scores · ${s}`} right={<span className="row row--inline row--tight">
          <select className="ctl" defaultValue={typeof window !== "undefined" ? new URLSearchParams(window.location.search).get("status") ?? "" : ""} onChange={(e) => go(q({ status: e.target.value }))}>
            <option value="">Every score</option><option value="OFFICIAL">Official (approved)</option><option value="UNAPPROVED">Awaiting approval</option><option value="EXPORTED">Exported</option><option value="NOT_EXPORTED">Not yet exported</option><option value="IMPORTED">Imported by the Academic Office</option><option value="RELEASED">Released</option><option value="VOID">Void</option>
          </select>
          <select className="ctl" defaultValue={typeof window !== "undefined" ? new URLSearchParams(window.location.search).get("prog") ?? "" : ""} onChange={(e) => go(q({ prog: e.target.value }))}><option value="">Every programme</option>{page.programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</select>
          <input className="ctl" placeholder="Search JAMB number, name or application number" defaultValue={typeof window !== "undefined" ? new URLSearchParams(window.location.search).get("q") ?? "" : ""} onKeyDown={(e) => { if (e.key === "Enter") go(q({ q: (e.target as HTMLInputElement).value })); }} />
          <span className="sub2">{num(page.total)} rows</span>
        </span>}>
          {page.rows.length ? <DTable cols={["S/N|num", "JAMB Number", "Candidate", "Programme", "Examination", "Questions|num", "Score|num", "Percentage|num", "Status|mid", "On record|mid", "File"]} rows={page.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{(page.page - 1) * page.size + i + 1}</span>,
            <span key="j" className="tnum">{r.jamb_reg_no}</span>,
            <span key="c"><b>{r.surname}, {r.other_names}</b><div className="sub2 tnum">{r.application_no ?? ""}</div></span>,
            <span key="p" className="sub2">{r.programme ?? "—"}<div>{r.faculty ?? ""}</div></span>,
            <span key="e" className="sub2">{r.exam_title}</span>,
            <span key="q" className="tnum">{num(r.attempted)}/{num(r.questions)}</span>,
            <span key="s" className="tnum">{r.score == null ? "—" : `${Number(r.score)}/${r.max_marks}`}</span>,
            <b key="pc" className="tnum">{Number(r.percentage).toFixed(2)}</b>,
            <Pil key="st" kind={r.outcome === "VOID" ? "bad" : r.official ? "ok" : "warn"}>{r.outcome === "VOID" ? "Void" : r.official ? "Official" : r.results_state.replace("_", " ")}</Pil>,
            <span key="o" className="sub2 tnum">{r.score_released_at ? `Released ${Number(r.existing_score)}` : r.existing_score != null ? `Imported ${Number(r.existing_score)}` : "—"}</span>,
            <span key="f" className="sub2 tnum">{r.exported_in ?? "—"}</span>,
          ])} /> : <PBody><div className="sub2">No Post-UTME CBT score for {s} matches.</div></PBody>}
          {page.total > page.size ? <PBody><div className="row row--inline row--tight"><span className="sub2">Page {page.page} of {Math.ceil(page.total / page.size)}</span>{page.page > 1 ? <Btn kind="ghost" size="sm" onClick={() => go(`${q({})}&page=${page.page - 1}`)}>Previous</Btn> : null}{page.page * page.size < page.total ? <Btn kind="ghost" size="sm" onClick={() => go(`${q({})}&page=${page.page + 1}`)}>Next</Btn> : null}</div></PBody> : null}
        </Panel>
      ) : null}

      {send ? (
        <Modal title="Send to the Academic Office" sub={`${send.reference} · ${num(send.rows_count)} candidates`} onClose={() => setSend(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setSend(null)}>Back</Btn><Btn kind="go" disabled={busy} onClick={() => void doSend()}>Send</Btn></span>}>
          <div className="sub2 mb-2">The Academic Office&rsquo;s officers are told by e-mail; the file becomes theirs to receive, download and import. Its hash is {send.sha256.slice(0, 16)}… and does not change.</div>
          <Field id="sx-msg" label="Message (optional)"><textarea id="sx-msg" className="ctl" rows={3} maxLength={2000} value={message} onChange={(e) => setMessage(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {note ? (
        <Modal title={note.action === "cancel" ? "Cancel the score file" : "Reject the score file"} sub={note.x.reference} onClose={() => setNote(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setNote(null)}>Back</Btn><Btn kind="urgent" disabled={busy || !reason.trim()} onClick={() => void doNote()}>{note.action === "cancel" ? "Cancel the file" : "Reject"}</Btn></span>}>
          <Field id="nx-reason" label="Reason" required><textarea id="nx-reason" className="ctl" rows={3} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {preview ? (
        <Modal title={`Import ${preview.reference}`} sub={`${num(preview.rows_count)} candidates · hash ${preview.sha256.slice(0, 16)}…`} wide onClose={() => setPreview(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setPreview(null)}>Back</Btn>{mayImport ? <Btn kind="primary" disabled={busy} onClick={() => void doImport()}>{busy ? "Importing…" : preview.state === "IMPORTED" ? "Import again" : "Confirm import"}</Btn> : null}</span>}>
          <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
            {Object.entries(preview.summary).map(([k, v]) => <Pil key={k} kind={(PREVIEW_WORD[k as keyof typeof PREVIEW_WORD] ?? ["", "grey"])[1]}>{(PREVIEW_WORD[k as keyof typeof PREVIEW_WORD] ?? [k])[0]}: {num(v)}</Pil>)}
          </div>
          <div className="grid grid--2">
            <Field id="im-mode" label="A different score already held" hint="A released score is never touched either way; the previous value of a replaced score is kept on the history">
              <select id="im-mode" className="ctl" value={importMode} onChange={(e) => setImportMode(e.target.value as "KEEP" | "REPLACE")}><option value="KEEP">Keep the existing score</option><option value="REPLACE">Replace it with the file&rsquo;s score (reason required)</option></select>
            </Field>
            <Field id="im-reason" label="Reason for replacing" required={importMode === "REPLACE"}><input id="im-reason" className="ctl" disabled={importMode !== "REPLACE"} value={importReason} onChange={(e) => setImportReason(e.target.value)} /></Field>
          </div>
          <DTable pageSize={50} cols={["S/N|num", "JAMB Number", "Candidate", "Programme", "File score|num", "Held|num", "Outcome|mid"]} rows={preview.rows.map((r) => [
            <span key="n" className="tnum sub2">{r.sn}</span>, <span key="j" className="tnum">{r.jamb_reg_no}</span>, <span key="c">{r.candidate_name}<div className="sub2 tnum">{r.application_no ?? ""}</div></span>,
            <span key="p" className="sub2">{r.programme ?? "—"}</span>, <b key="s" className="tnum">{Number(r.percentage).toFixed(2)}</b>,
            <span key="h" className="tnum">{r.existing_score == null ? "—" : Number(r.existing_score).toFixed(2)}{r.score_released_at ? " (released)" : ""}</span>,
            <Pil key="o" kind={(PREVIEW_WORD[r.outcome] ?? ["", "grey"])[1]}>{(PREVIEW_WORD[r.outcome] ?? [r.outcome])[0]}</Pil>,
          ])} texts={preview.rows.map((r) => `${r.jamb_reg_no} ${r.candidate_name} ${r.outcome}`)} />
        </Modal>
      ) : null}
    </>
  );
}
