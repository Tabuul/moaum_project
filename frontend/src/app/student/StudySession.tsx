"use client";
/** V733 · Academic session management — the University's master prompt of 12 November 2026 (part A). The College runs MBBS one
 *  session behind the University's calendar: an MBBS student reads the session they stand in, their level and the University's session,
 *  chooses another approved session (each other one says why it cannot be chosen), confirms the change — previous session, new session,
 *  level — and reads every change. Shown only to a student who may choose (a College-run programme, studying); the level never changes
 *  with the session, and registration, fees, GST/EPS, permits and results all open on the session chosen. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { day } from "@/lib/format";

export interface StudySessionOption {
  session: string; state: string; starts_on: string; is_university: boolean; is_own: boolean; selectable: boolean; why: string | null;
}
export interface StudySessionChange {
  at: string; from_session: string | null; to_session: string | null; level: number | null; office: string | null; approval: string;
  reason: string | null; by_name: string | null;
}
export interface StudySessionPage {
  eligible: boolean; refusal: string | null; session: string; own: boolean; university: string | null;
  student: { matric_no: string | null; name: string; current_level: number; programme: string | null; behind_max: number | null };
  options: StudySessionOption[]; history: StudySessionChange[];
}

/** why a session cannot be chosen, in words */
export function whyWords(why: string | null): string {
  switch (why) {
    case "BEFORE_ENTRY": return "before your entry session";
    case "TOO_FAR_BEHIND": return "further behind the University than your programme allows";
    case "BEHIND_YOUR_REGISTRATION": return "earlier than a session you registered courses in";
    case "LEVEL_REGISTERED_ELSEWHERE": return "your present level is registered in another session";
    default: return why ? why.replace(/_/g, " ").toLowerCase() : "";
  }
}

/** how a change stood: the student's own choice, an office's, the roll-over */
export function approvalWords(a: string): string {
  return a === "NOT_REQUIRED" ? "Your own choice" : a === "SET_BY_OFFICE" ? "Set by an office" : a === "ROLL_OVER" ? "Session roll-over" : a;
}

export function StudySession() {
  const router = useRouter();
  const [page, setPage] = useState<StudySessionPage | null>(null);
  const [pick, setPick] = useState("");
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);

  useEffect(() => {
    let live = true;
    void fetch("/api/bff/api/v1/me/study-session", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((j: StudySessionPage | null) => { if (live && j) setPage(j); })
      .catch(() => undefined);
    return () => { live = false; };
  }, []);

  if (!page || !page.eligible) return null;
  const choosable = page.options.filter((o) => o.selectable && !o.is_own);
  const chosen = page.options.find((o) => o.session === pick) ?? null;

  async function save() {
    if (!chosen || busy || !page) return;
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch("/api/bff/api/v1/me/study-session", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Academic session changed from ${page.session} to ${chosen.session}`) },
        body: JSON.stringify({ session: chosen.session }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p: Problem = j ?? { status: r.status, title: r.statusText };
        setErr(p);
        notifyProblem(p);
        return;
      }
      setPage(j as StudySessionPage);
      setConfirm(false);
      setPick("");
      notify(`Your academic session is now ${chosen.session}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="Academic session management" right={page.own ? <Pil kind="info">Your own session</Pil> : <Pil kind="grey">The University&rsquo;s session</Pil>}>
      <PBody>
        <KvGrid pairs={[
          ["Current academic session", <b key="s">{page.session}</b>],
          ["Current academic level", `${page.student.current_level} Level`],
          ["The University's session", page.university ?? "—"],
          ["Programme", page.student.programme ?? "—"],
        ]} />
        <div className="sub2 mt-1">
          The College runs {page.student.programme ?? "your programme"} on its own calendar, up to {page.student.behind_max ?? 1} session{(page.student.behind_max ?? 1) === 1 ? "" : "s"} behind
          the University&rsquo;s. Course registration, school fees, GST/EPS, examination permits and results open on the session you stand in. Changing it never
          changes your level or anything already registered or paid.
        </div>
        {err ? <ProblemNotice problem={err} /> : null}
        <div className="row row--inline row--tight mt-1" style={{ flexWrap: "wrap", gap: 8, alignItems: "flex-end" }}>
          <label className="sub2" htmlFor="ss-pick" style={{ display: "block" }}>Available academic sessions
            <select id="ss-pick" className="ctl" value={pick} onChange={(e) => setPick(e.target.value)} style={{ display: "block", minWidth: 260 }}>
              <option value="">Choose a session…</option>
              {page.options.map((o) => (
                <option key={o.session} value={o.session} disabled={!o.selectable || o.is_own}>
                  {o.session}{o.is_university ? " (the University's)" : ""}{o.is_own ? " — your session now" : !o.selectable ? ` — ${whyWords(o.why)}` : ""}
                </option>
              ))}
            </select>
          </label>
          <Btn kind="primary" disabled={!chosen || !chosen.selectable || chosen.is_own || busy} onClick={() => setConfirm(true)}>Update session</Btn>
        </div>
        {!choosable.length ? <div className="sub2 mt-1">No other session is open to you now. The College or the Academic Office sets one the rules do not allow — a repeated year, for instance.</div> : null}
      </PBody>
      {page.history.length ? (
        <DTable cols={["When|mid", "From", "To", "Level|mid", "How", "By"]} rows={page.history.map((h, i) => [
          <span key={`a${i}`} className="tnum">{day(h.at)}</span>,
          h.from_session ?? "The University's",
          h.to_session ?? "The University's",
          h.level != null ? `${h.level}` : "—",
          <span key={`h${i}`}>{approvalWords(h.approval)}{h.reason ? <div className="sub2">{h.reason}</div> : null}</span>,
          h.by_name ?? "—",
        ])} />
      ) : null}
      {confirm && chosen ? (
        <Modal title="Change your academic session?" onClose={() => { if (!busy) setConfirm(false); }}
          foot={<div className="row row--inline row--tight row--right" style={{ gap: 8 }}>
            <Btn kind="ghost" disabled={busy} onClick={() => setConfirm(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Confirm the change"}</Btn>
          </div>}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[
              ["Previous academic session", page.session],
              ["New academic session", <b key="n">{chosen.session}</b>],
              ["Current academic level", `${page.student.current_level} Level`],
            ]} />
            <Note kind="info" title="What changes">Your registration, fees, GST/EPS, examination permits and results open on {chosen.session}. Your level stays {page.student.current_level} Level; nothing registered or paid is altered. The change is recorded.</Note>
          </PBody>
        </Modal>
      ) : null}
    </Panel>
  );
}
