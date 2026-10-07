"use client";

/**
 * The JUPEB Office's continuous assessment (V355): the session's parts and their maxima (set here — never assumed), each subject's
 * progress, and each subject's sheet — entered by its lecturers or the office, locked when final for the Board (scores due on the
 * calendar's date), unlocked only with a reason.
 */
import { useEffect, useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { day, jcall, when } from "@/lib/jupeb";
import { CaSheetEditor } from "./CaSheet";

interface Comp { id?: string; code: string; title: string; max_score: number | string; ord: number; active: boolean }
interface Progress { subject_id: string; code: string; title: string; students: number; complete: number; locked_at: string | null }
interface Data { session: string; components: Comp[]; due: { starts_on: string; deadline_on: string | null; title: string } | null; progress: Progress[]; classes: { id: string; name: string }[] }

export function JupebCa({ canWrite }: { canWrite: boolean }) {
  const [sessions, setSessions] = useState<string[]>([]);
  const [session, setSession] = useState("");
  const [d, setD] = useState<Data | null>(null);
  const [comps, setComps] = useState<Comp[]>([]);
  const [subject, setSubject] = useState("");
  const [klass, setKlass] = useState("");
  const [tick, setTick] = useState(0);
  const [unlock, setUnlock] = useState<{ reason: string } | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<{ session: string; sessions: { session: string }[] }>("/api/v1/jupeb/office/dashboard").then((r) => {
      if (live && r.ok) { setSessions(r.data.sessions.map((x) => x.session)); setSession((s) => s || r.data.session); }
    });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    let live = true;
    if (session) void jcall<Data>(`/api/v1/jupeb/office/ca/components?session=${encodeURIComponent(session)}`).then((r) => {
      if (!live) return;
      if (r.ok) { setD(r.data); setComps(r.data.components.filter((c) => c.active)); } else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [session, tick]);
  if (!d) return <Note kind="info" title="Loading…">One moment.</Note>;
  const due = d.due ? d.due.deadline_on ?? d.due.starts_on : null;
  async function saveComps() {
    setBusy(true);
    try {
      const body = { session: d!.session, components: comps.map((c, i) => ({ code: c.code.trim().toUpperCase(), title: c.title.trim(), maxScore: Number(c.max_score), ord: i + 1, active: true })) };
      const r = await jcall<Data>("/api/v1/jupeb/office/ca/components", "PUT", body, `JUPEB assessment parts for ${d!.session}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setD(r.data); setComps(r.data.components.filter((c) => c.active)); notify("The parts of the assessment are saved.");
    } finally { setBusy(false); }
  }
  async function lockIt(on: boolean, reason?: string) {
    const r = await jcall(`/api/v1/jupeb/office/ca/${on ? "lock" : "unlock"}`, "POST", { session: d!.session, subjectId: subject, reason: reason ?? null },
      on ? "JUPEB assessment locked" : `JUPEB assessment unlocked: ${reason}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    setUnlock(null); setTick((t) => t + 1); notify(on ? "Locked: the scores are final for the Board." : "Unlocked.");
  }
  const total = comps.reduce((n, c) => n + (Number(c.max_score) || 0), 0);
  const validComps = comps.every((c) => /^[A-Za-z0-9_]{1,20}$/.test(c.code.trim()) && c.title.trim().length >= 2 && Number(c.max_score) > 0);
  return (
    <>
      <PageHead title="JUPEB continuous assessment" description="The session's parts of the continuous assessment and their maxima, each subject's scores entered by its lecturers, locked when final for the Board."
        actions={<select className="ctl" aria-label="Session" value={d.session} onChange={(e) => { setSession(e.target.value); setSubject(""); }}>{sessions.map((x) => <option key={x}>{x}</option>)}</select>} />
      {due ? <Note kind="info" title={`Due to the Board ${day(due)}`}>{d.due?.title}</Note> : null}
      <Panel title="The parts of the assessment" right={<Pil kind="info">{`Out of ${total}`}</Pil>}>
        <PBody>
          <p className="sub2">The parts the session&rsquo;s assessment is made of, and the most each is marked out of — set by the JUPEB Office as the Board asks; nothing is assumed. A part taken off is set aside with its scores kept.</p>
          {comps.map((c, i) => (
            <div key={i} className="row" style={{ gap: "var(--s-2)", marginTop: "var(--s-1)" }}>
              <input className="ctl" style={{ width: 110 }} aria-label={`Part ${i + 1} code`} placeholder="TEST1" maxLength={20} disabled={!canWrite} value={c.code} onChange={(e) => setComps(comps.map((x, j) => (j === i ? { ...x, code: e.target.value.toUpperCase() } : x)))} />
              <input className="ctl grow" aria-label={`Part ${i + 1} title`} placeholder="First test" maxLength={80} disabled={!canWrite} value={c.title} onChange={(e) => setComps(comps.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))} />
              <input className="ctl" style={{ width: 90 }} aria-label={`Part ${i + 1} maximum`} type="number" min={0.5} max={1000} step="0.5" disabled={!canWrite} value={c.max_score} onChange={(e) => setComps(comps.map((x, j) => (j === i ? { ...x, max_score: e.target.value } : x)))} />
              {canWrite ? <Btn kind="ghost" aria-label="Take off" onClick={() => setComps(comps.filter((_, j) => j !== i))}>&times;</Btn> : null}
            </div>
          ))}
          {canWrite ? <div className="row mt-2">
            {comps.length < 12 ? <Btn kind="ghost" onClick={() => setComps([...comps, { code: "", title: "", max_score: "", ord: comps.length + 1, active: true }])}>Add a part</Btn> : null}
            <Btn kind="secondary" disabled={busy || !validComps} onClick={() => void saveComps()}>{busy ? "Saving…" : "Save the parts"}</Btn></div> : null}
        </PBody>
      </Panel>
      <Panel title="Subjects">
        <PBody>
          <DTable pageSize={0} cols={["Subject", "Students|num", "Complete|num", "State", "|mid"]} rows={d.progress.filter((p) => p.students > 0).map((p) => [`${p.title} (${p.code})`, p.students, p.complete,
            p.locked_at ? <Pil key="l" kind="ok">{`Locked ${when(p.locked_at)}`}</Pil> : p.complete === p.students ? <Pil key="l" kind="info">Complete — to lock</Pil> : <Pil key="l" kind="warn">Being entered</Pil>,
            <Btn key="o" kind="ghost" onClick={() => setSubject(p.subject_id)}>Open</Btn>])} />
        </PBody>
      </Panel>
      {subject ? (
        <Panel title={`Scores — ${d.progress.find((p) => p.subject_id === subject)?.title ?? ""}`} right={<select className="ctl" style={{ width: 180 }} aria-label="Class" value={klass} onChange={(e) => setKlass(e.target.value)}>
          <option value="">Every class</option>{d.classes.map((k) => <option key={k.id} value={k.id}>{k.name}</option>)}</select>}>
          <PBody>
            <CaSheetEditor key={`${subject}|${klass}|${tick}`} url={`/api/v1/jupeb/office/ca/sheet?session=${encodeURIComponent(d.session)}&subject=${subject}${klass ? `&klass=${klass}` : ""}`}
              saveUrl="/api/v1/jupeb/office/ca/scores" canEdit={canWrite}
              extra={(sheet) => canWrite ? (sheet.lock ? <Btn kind="ghost" onClick={() => setUnlock({ reason: "" })}>Unlock…</Btn>
                : <Btn kind="secondary" onClick={() => { if (window.confirm(`Lock ${sheet.subject.title}? Its scores become final for the Board; only the JUPEB Office unlocks it, with a reason.`)) void lockIt(true); }}>Lock</Btn>) : null} />
          </PBody>
        </Panel>
      ) : null}
      {unlock ? (
        <Modal title="Unlock the subject's assessment" onClose={() => setUnlock(null)}
          foot={<><Btn kind="ghost" onClick={() => setUnlock(null)}>Cancel</Btn><Btn kind="primary" disabled={unlock.reason.trim().length < 5} onClick={() => void lockIt(false, unlock.reason.trim())}>Unlock</Btn></>}>
          <Field id="ca-why" label="Why" required><input id="ca-why" className="ctl" maxLength={500} value={unlock.reason} onChange={(e) => setUnlock({ reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
