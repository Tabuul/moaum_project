"use client";
/** A course's code and title corrected (V713): the current and the new side by side, what hangs on the course, the courses
 *  already under the new code or of the new title, the reason — then a confirmation, and the same course under the corrected
 *  code and title. The database judges every step again; this screen only shows what it will say. */
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Pil } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { REASONS, REASON_WORDS, impactLines, impactSentence, readyToReview, reasonText, type CorrectionCheck, type CorrectionDone, type SimilarCourse } from "@/lib/course-correction";
import { shownCode } from "@/lib/course-code";

type Form = { code: string; title: string; reason: string; remarks: string; past: boolean };

function Similar({ rows, flag }: { rows: SimilarCourse[]; flag: (r: SimilarCourse) => React.ReactNode }) {
  return (
    <div className="tablewrap" tabIndex={0} style={{ maxHeight: 200, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
      <table className="tbl--data">
        <thead><tr><th>Course ID</th><th>Code</th><th>Title</th><th>Department</th><th>Level</th><th /></tr></thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.id}>
              <td className="tnum sub2" style={{ maxWidth: 120, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }} title={r.id}>{r.id}</td>
              <td className="tnum"><Link className="lnk" href={`/catalogue/course?code=${encodeURIComponent(r.code)}`} target="_blank">{r.shown}</Link>{r.code !== r.shown ? <div className="sub2">key {r.code}</div> : null}</td>
              <td>{r.title}</td><td className="sub2">{r.dept_name ?? r.dept_code ?? "—"}</td><td className="tnum">{r.level}</td><td>{flag(r)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function CourseCorrection({ course, version, mayCode, mayTitle, ticket, why, onClose, onDone }: {
  course: { id: string; code: string; title: string };
  version: string;
  mayCode: boolean;
  mayTitle: boolean;
  ticket: string;
  /** the ticket's words before the reason, as the course page puts them */
  why: (text: string) => string;
  onClose: () => void;
  onDone: (d: CorrectionDone) => void;
}) {
  const [form, setForm] = useState<Form>({ code: shownCode(course.code), title: course.title, reason: "", remarks: "", past: true });
  const [check, setCheck] = useState<CorrectionCheck | null>(null);
  const [step, setStep] = useState<"edit" | "confirm">("edit");
  const [busy, setBusy] = useState(false);
  const [stale, setStale] = useState<string | null>(null);
  const seq = useRef(0);

  // what the database says the change would be, read again as the code or the title is typed
  useEffect(() => {
    const n = ++seq.current;
    const t = setTimeout(async () => {
      const r = await fetch(`/api/bff/api/v1/catalogue/courses/${encodeURIComponent(course.code)}/correction/check`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Course correction checked") },
        body: JSON.stringify({ code: form.code, title: form.title }),
      });
      const j = await r.json().catch(() => null);
      if (n !== seq.current) return;
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setCheck(j as CorrectionCheck);
    }, 350);
    return () => clearTimeout(t);
  }, [form.code, form.title, course.code]);

  const current = check;
  const changedSince = !!check && check.version !== version;
  const blocker = changedSince ? "This course has been updated by another user since you opened it." : readyToReview(form, current);
  const impact = current?.impact ?? null;
  const unchanged = current?.refusal?.code === "COURSE_UNCHANGED";   // nothing typed yet: a hint, not a refusal
  const lines = impactLines(impact);

  async function save() {
    setBusy(true);
    try {
      const q = ticket.trim() ? `?ticket=${encodeURIComponent(ticket.trim())}` : "";
      const r = await fetch(`/api/bff/api/v1/catalogue/courses/${encodeURIComponent(course.code)}/correction${q}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why(reasonText(form.reason, form.remarks))) },
        body: JSON.stringify({ code: form.code.trim(), title: form.title, reasonKind: form.reason, remarks: form.remarks.trim() || null, version, pastClasses: form.past }),
      });
      const j = (await r.json().catch(() => null)) as (Record<string, unknown> & { code?: string; detail?: string }) | null;
      if (!r.ok) {
        if (j?.code === "COURSE_CHANGED_SINCE") { setStale(String(j.detail ?? "This course has been updated by another user.")); setStep("edit"); return; }
        notifyProblem(j ? (j as unknown as Parameters<typeof notifyProblem>[0]) : { status: r.status, title: r.statusText });
        return;
      }
      const d = j as unknown as CorrectionDone;
      notify(`${d.was} — ${d.wasTitle} now reads ${d.shown} — ${d.title}: the same course`);
      onDone(d);
    } finally {
      setBusy(false);
    }
  }

  const reload = <Btn kind="primary" onClick={() => window.location.reload()}>Reload the course</Btn>;

  if (step === "confirm" && current) {
    return (
      <Modal title="Confirm course change" sub={<span className="tnum">Course ID {course.id} — the same course before and after</span>} onClose={onClose} wide
        foot={<><Btn kind="ghost" disabled={busy} onClick={() => setStep("edit")}>Cancel</Btn><Btn kind="urgent" disabled={busy || !!blocker} onClick={() => void save()}>{busy ? "Saving…" : "Confirm change"}</Btn></>}>
        <div className="stack">
          <table className="tbl--data">
            <thead><tr><th /><th>Current</th><th>New</th></tr></thead>
            <tbody>
              <tr><th scope="row">Code</th><td className="tnum">{current.shown}</td><td className="tnum"><b>{current.newCode}</b>{current.separate ? <div className="sub2">kept as a separate course under {current.newCode} (key {current.key})</div> : null}</td></tr>
              <tr><th scope="row">Title</th><td>{current.title}</td><td><b>{current.newTitle}</b></td></tr>
            </tbody>
          </table>
          <div>
            <div className="eyebrow">Impact</div>
            <div className="sub2">{impactSentence(impact)}</div>
            {lines.length ? <ul className="sub2" style={{ margin: "4px 0 0 18px" }}>{lines.map((l) => <li key={l}>{l}</li>)}</ul> : null}
            {current.titleChanged ? <div className="sub2 mt-2">{form.past
              ? `Every class shows the new title, the ${Number(impact?.pastClasses ?? 0).toLocaleString()} already registered or examined included (results, broadsheets, transcripts).`
              : "Classes already registered or examined keep the title they had; classes from now on show the new title."} Units never change.</div> : null}
          </div>
          <div>
            <div className="eyebrow">Reason</div>
            <div><b>{REASON_WORDS[form.reason] ?? form.reason}</b>{form.remarks.trim() ? ` — ${form.remarks.trim()}` : ""}{ticket.trim() ? <span className="sub2"> · ticket {ticket.trim().toUpperCase()}</span> : null}</div>
          </div>
          {stale ? <Note kind="bad" title="Not saved" action={reload}>{stale}</Note> : null}
        </div>
      </Modal>
    );
  }

  return (
    <Modal title={`Change code or title of ${shownCode(course.code)}`} sub={<span className="tnum">Course ID {course.id} — the course stays the same course; everything on it follows</span>} onClose={onClose} wide
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn kind="primary" disabled={!!blocker} onClick={() => setStep("confirm")}>Review change</Btn></>}>
      <div className="stack">
        {stale || changedSince ? <Note kind="bad" title="Updated by another user" action={reload}>{stale ?? "This course has been updated by another user since you opened it. Reload the latest version before making your change."}</Note> : null}
        <div className="grid grid--2">
          <Field id="cc-code" label="Course code" hint={mayCode ? `Now ${shownCode(course.code)} — CSC 401, or a prefix with its hyphen: MOAU-CHM 101` : "Your office may not change this course's code"}>
            <input id="cc-code" className="ctl tnum" value={form.code} disabled={!mayCode} maxLength={20} autoComplete="off" onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} />
          </Field>
          <Field id="cc-title" label="Course title" hint={mayTitle ? `Now: ${course.title}` : "Your office may not change this course's title"}>
            <input id="cc-title" className="ctl" value={form.title} disabled={!mayTitle} maxLength={120} onChange={(e) => setForm({ ...form, title: e.target.value })} />
          </Field>
        </div>
        {current?.refusal && !unchanged ? <Note kind="bad" title="This change cannot be made">{current.refusal.message}</Note> : null}
        {current && !current.refusal && current.separate ? (
          <Note kind="info" title={`${current.newCode} is already held by another course`}>
            Another course holds {current.newCode} under another title. The University keeps the same code under another title as a separate course, so this course keeps its own record under {current.newCode} (key {current.key}). Nothing is merged.
          </Note>
        ) : null}
        {current && current.sameCode.length ? (
          <div>
            <div className="eyebrow">Courses already under {current.newCode}</div>
            <Similar rows={current.sameCode} flag={(r) => (r.sameTitle ? <Pil kind="bad">same title</Pil> : <Pil kind="grey">another title</Pil>)} />
          </div>
        ) : null}
        {current && current.sameTitle.length ? (
          <div>
            <div className="eyebrow">Courses of the same title under other codes</div>
            <Similar rows={current.sameTitle} flag={(r) => (r.possibleDuplicate ? <Pil kind="warn">possible duplicate</Pil> : null)} />
            <div className="sub2 mt-1">A possible duplicate has the same title, units, level and department. A correction never merges; the duplicates desk does, if they are one course.</div>
          </div>
        ) : null}
        {current?.titleChanged && Number(impact?.pastClasses ?? 0) > 0 ? (
          <label className="row row--inline row--tight">
            <input type="checkbox" checked={form.past} onChange={(e) => setForm({ ...form, past: e.target.checked })} />
            <span>Show the new title on the {Number(impact?.pastClasses).toLocaleString()} class{Number(impact?.pastClasses) === 1 ? "" : "es"} already registered or examined too — results, broadsheets, transcripts. Untick to keep the title they had (a course renamed by the curriculum, not mistyped).</span>
          </label>
        ) : null}
        <div className="grid grid--2">
          <Field id="cc-reason" label="Reason" required>
            <select id="cc-reason" className="ctl" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })}>
              <option value="">Choose…</option>
              {REASONS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
          <Field id="cc-remarks" label="Remarks" hint={form.reason === "OTHER" ? "Required for Other" : "Optional; kept with the change"}>
            <textarea id="cc-remarks" className="ctl" rows={2} maxLength={2000} value={form.remarks} onChange={(e) => setForm({ ...form, remarks: e.target.value })} />
          </Field>
        </div>
        <div>
          <div className="eyebrow">Course usage</div>
          {impact ? <>
            <div className="sub2">{impactSentence(impact)}</div>
            {lines.length ? <ul className="sub2" style={{ margin: "4px 0 0 18px" }}>{lines.map((l) => <li key={l}>{l}</li>)}</ul> : null}
          </> : <div className="sub2">Reading what hangs on the course…</div>}
        </div>
        {blocker && blocker !== "Checking…" && (!current?.refusal || unchanged) ? <div className="sub2" role="status"><b>Before you review:</b> {blocker}</div> : null}
      </div>
    </Modal>
  );
}
