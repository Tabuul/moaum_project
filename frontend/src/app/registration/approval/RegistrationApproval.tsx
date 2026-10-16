"use client";

/**
 * Course registration approval (V491): the rule for a session and semester — AUTOMATIC APPROVAL or HOD APPROVAL REQUIRED, whether a
 * student may reset the registration, whether the examination card follows approval — set with a reason; the figures, each opening
 * the registrations behind it; the waiting registrations judged again in one act; one held for review judged again once it is put
 * right. The server decides every part of it.
 */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import {
  FIGURES, MODE_WORD, reasonWords, semesterWord, type ApprovalMode, type Overview, type OverviewRow, type Rules,
} from "@/lib/registration-approval";

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const vz = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");

export function RegistrationApproval({ rules, session, semester, kind, q, overview, list, mayChange }: {
  rules: Rules; session: string; semester: number | null; kind: string; q: string; overview: Overview | null;
  list: { kind: string; total: number; page: number; size: number; rows: OverviewRow[] } | null; mayChange: boolean;
}) {
  const router = useRouter();
  const go = useQueryNav();
  const nav = (patch: Record<string, string | number | null>) => {
    const next: Record<string, string> = { session, semester: semester ? String(semester) : "", kind, q, page: "0" };
    for (const [k, v] of Object.entries(patch)) next[k] = v == null ? "" : String(v);
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "page" && v === "0")) qs.set(k, v);
    go(`/registration/approval?${qs.toString()}`);
  };
  const rule = overview?.rule;
  const [form, setForm] = useState({
    session: session as string, semester: semester ? String(semester) : "", mode: (rule?.mode ?? "AUTO_APPROVAL") as ApprovalMode,
    reset: rule?.allow_student_reset ?? true, card: rule?.card_on_approval ?? true, reason: "",
  });
  const [cards, setCards] = useState<{ available: number; approved: number } | null>(null);
  const [search, setSearch] = useState(q);

  // the cards the students may print now ask the Bursary's clearance of each one: read after the page, not before it
  useEffect(() => {
    if (!session) return;
    let alive = true;
    void (async () => {
      const r = await fetch(`/api/bff/api/v1/registration/approval/overview/cards?session=${encodeURIComponent(session)}${semester ? `&semester=${semester}` : ""}`, { cache: "no-store", headers: { "X-Background": "1" } });
      const j = r.ok ? await r.json() : null;
      if (alive && j) setCards(j);
    })();
    return () => { alive = false; };
  }, [session, semester]);

  async function saveRule() {
    const r = await fetch("/api/bff/api/v1/registration/approval/rules", {
      method: "PUT",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course registration approval set to ${MODE_WORD[form.mode]}: ${form.reason.trim()}`) },
      body: JSON.stringify({ session: form.session || null, semester: form.semester ? Number(form.semester) : null, mode: form.mode, allowStudentReset: form.reset, cardOnApproval: form.card, reason: form.reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    const done = j?.processed as { considered: number; approved: number; review: number } | undefined;
    notify(done ? `Saved. ${done.considered} waiting registration${done.considered === 1 ? "" : "s"} judged: ${done.approved} approved, ${done.review} held for review.` : "Saved");
    setForm({ ...form, reason: "" });
    router.refresh();
  }

  async function processNow() {
    const r = await fetch("/api/bff/api/v1/registration/approval/process", {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Waiting course registrations of ${session} judged again`) },
      body: JSON.stringify({ session, semester }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(`${j.considered} waiting registration${j.considered === 1 ? "" : "s"} judged: ${j.approved} approved, ${j.review} held for review.`);
    router.refresh();
  }

  async function revalidate(id: string) {
    const r = await fetch(`/api/bff/api/v1/registration/approval/registrations/${id}/revalidate`, {
      method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Course registration held for review judged again") }, body: "{}",
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(j.approved ? "Approved" : `Still held: ${reasonWords(String(j.result))}`, j.approved ? "ok" : "bad");
    router.refresh();
  }

  const pages = list ? Math.max(1, Math.ceil(list.total / list.size)) : 1;
  const auto = rule?.mode === "AUTO_APPROVAL";
  return (
    <>
      <PageHead title="Course registration approval" eyebrow="Academic settings"
        description="How a course registration is approved, session by session. Under automatic approval a registration that passes every registration rule (fees, GST/EPS, units, the courses offered to the student) is approved when the student submits it, and the examination card follows. One that does not is held for review with the reason. The Head of Department's approval returns when the rule is set back." />

      <div className="row" style={{ flexWrap: "wrap", gap: 12 }}>
        <Field id="ra-session" label="Session"><select id="ra-session" className="ctl" value={session} onChange={(e) => nav({ session: e.target.value })}>
          {rules.sessions.map((s) => <option key={s} value={s}>{s}{s === rules.current ? " (current)" : ""}</option>)}
        </select></Field>
        <Field id="ra-semester" label="Semester"><select id="ra-semester" className="ctl" value={semester ? String(semester) : ""} onChange={(e) => nav({ semester: e.target.value || null })}>
          <option value="">Every semester</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
        </select></Field>
      </div>

      {rule ? (
        <Note kind={auto ? "ok" : "info"} title={`COURSE REGISTRATION APPROVAL · ${session}${semester ? ` · ${semesterWord(semester)}` : ""}: ${MODE_WORD[rule.mode].toUpperCase()}`}>
          {auto ? "HOD approval is not required. " : "Each registration waits on the Head of Department's approval. "}
          Student reset: <b>{rule.allow_student_reset ? "ON" : "OFF"}</b> · Examination card on approval: <b>{rule.card_on_approval ? "ON" : "OFF"}</b>.
          {rule.applies_as === "STANDING" || rule.applies_as === "DEFAULT" ? " The standing rule applies; no rule is set for this session." : ""}
          {rule.reason ? <div className="sub2 mt-1">{rule.reason}{rule.set_by ? ` — ${rule.set_by}` : ""}{rule.set_at ? `, ${when(rule.set_at)}` : ""}</div> : null}
        </Note>
      ) : null}

      {overview ? (
        <div className="grid grid--4" role="group" aria-label="Course registration figures">
          {FIGURES.map((f) => (
            <button key={f.kind} type="button" className="tile stat-tile" aria-pressed={kind === f.kind} onClick={() => nav({ kind: f.kind })}
              style={{ textAlign: "left", font: "inherit", border: kind === f.kind ? "2px solid var(--chrome)" : undefined }}>
              <div className="eyebrow">{f.label}</div>
              <div className="n tnum" style={f.kind === "REVIEW" && Number(overview[f.key]) > 0 ? { color: "var(--red-ink)" } : undefined}>{vz(overview[f.key] as number)}</div>
            </button>
          ))}
          <div className="tile stat-tile">
            <div className="eyebrow">Exam cards available</div>
            <div className="n tnum">{cards ? vz(cards.available) : "…"}</div>
            <div className="c">{cards ? `of ${vz(cards.approved)} approved, cleared by the Bursary` : "Asking the Bursary's clearance"}</div>
          </div>
        </div>
      ) : null}

      {mayChange ? (
        <div className="grid grid--2">
          <Panel title="Set the rule" right="Recorded with your name and the reason">
            <PBody>
              <div className="stack">
                <div className="row" style={{ flexWrap: "wrap", gap: 12 }}>
                  <Field id="rf-session" label="Session"><select id="rf-session" className="ctl" value={form.session} onChange={(e) => setForm({ ...form, session: e.target.value, semester: e.target.value ? form.semester : "" })}>
                    <option value="">The standing rule (every session)</option>
                    {rules.sessions.map((s) => <option key={s} value={s}>{s}</option>)}
                  </select></Field>
                  <Field id="rf-semester" label="Semester"><select id="rf-semester" className="ctl" value={form.semester} disabled={!form.session} onChange={(e) => setForm({ ...form, semester: e.target.value })}>
                    <option value="">The whole session</option><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option>
                  </select></Field>
                </div>
                <Field id="rf-mode" label="Course registration approval">
                  <div className="stack" style={{ gap: 4 }}>
                    {(["AUTO_APPROVAL", "HOD_APPROVAL_REQUIRED"] as ApprovalMode[]).map((m) => (
                      <label key={m} className="row row--inline row--tight"><input type="radio" name="rf-mode" checked={form.mode === m} onChange={() => setForm({ ...form, mode: m })} /> {MODE_WORD[m].toUpperCase()}</label>
                    ))}
                  </div>
                </Field>
                <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={form.reset} onChange={(e) => setForm({ ...form, reset: e.target.checked })} /> ALLOW STUDENT REGISTRATION RESET</label>
                <label className="row row--inline row--tight"><input type="checkbox" className="chk" checked={form.card} onChange={(e) => setForm({ ...form, card: e.target.checked })} /> ALLOW EXAM CARD IMMEDIATELY AFTER APPROVAL</label>
                <Field id="rf-reason" label="Reason" required hint="Ten characters or more; kept on the audit trail">
                  <input id="rf-reason" className="ctl" value={form.reason} maxLength={2000} onChange={(e) => setForm({ ...form, reason: e.target.value })} placeholder="e.g. Senate suspended HOD approval for the semester" />
                </Field>
                <div><Btn kind="primary" disabled={form.reason.trim().length < 10} busyLabel="SAVING..." onClick={() => saveRule()}>Save the rule</Btn></div>
                {form.mode === "AUTO_APPROVAL" ? <div className="sub2">Saving automatic approval also judges the registrations already waiting on a Head: approved where they pass, held for review where they do not.</div> : null}
              </div>
            </PBody>
          </Panel>
          <Panel title="The rules set" right={`${rules.rules.length}`}>
            <DTable pageSize={0} cols={["Applies to", "Approval", "Reset|mid", "Card|mid", "Set"]} rows={rules.rules.map((x) => [
              <span key="a">{x.session ? `${x.session}${x.semester ? ` · ${semesterWord(x.semester)}` : ""}` : <b>The standing rule</b>}</span>,
              <Pil key="m" kind={x.mode === "AUTO_APPROVAL" ? "ok" : "info"}>{MODE_WORD[x.mode]}</Pil>,
              <span key="r">{x.allow_student_reset ? "On" : "Off"}</span>,
              <span key="c">{x.card_on_approval ? "On" : "Off"}</span>,
              <span key="s" className="sub2">{x.set_by ?? "—"}{x.set_office ? ` (${x.set_office})` : ""}<div>{when(x.set_at)}</div><div>{x.reason}</div></span>,
            ])} />
            {auto ? <PBody><Btn kind="secondary" busyLabel="Processing…" onClick={() => processNow()}>Judge the waiting registrations now</Btn></PBody> : null}
          </Panel>
        </div>
      ) : null}

      {list ? (
        <Panel title={FIGURES.find((f) => f.kind === list.kind)?.label ?? "Registrations"} right={`${vz(list.total)} · page ${list.page + 1} of ${pages}`}>
          <PBody>
            <form className="row row--inline" style={{ gap: 8 }} onSubmit={(e) => { e.preventDefault(); nav({ q: search.trim() }); }}>
              <input className="ctl" aria-label="Search by name or matriculation number" placeholder="Name or matriculation number" value={search} onChange={(e) => setSearch(e.target.value)} />
              <Btn kind="ghost" type="submit">Search</Btn>
            </form>
          </PBody>
          {list.rows.length ? (
            <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Level|mid", "Semester|mid", "Status|mid", "Approved by", "Held for review", "Resets|mid", "Card|mid", "|num"]}
              rows={list.rows.map((r, i) => [
                <span key="n" className="tnum sub2">{list.page * list.size + i + 1}</span>,
                <span key="s"><Link className="lnk" href={`/students/${r.student_id}`}>{r.full_name}</Link><div className="sub2 tnum">{r.matric_no ?? ""}</div></span>,
                <span key="p" className="sub2">{r.programme ?? "—"}</span>,
                <span key="l" className="tnum">{r.level ?? "—"}</span>,
                <span key="m" className="tnum">{r.semester}</span>,
                <Pil key="st" kind={r.status === "APPROVED" || r.status === "LOCKED" ? "ok" : r.status === "SUBMITTED" ? "warn" : "grey"}>{r.status}</Pil>,
                <span key="a" className="sub2">{r.approval_mode === "AUTO" ? "Automatic" : r.approval_mode === "HOD" ? "Head of Department" : r.status === "APPROVED" || r.status === "LOCKED" ? "Earlier approval" : "—"}</span>,
                <span key="v" className="sub2">{r.review_reason ? reasonWords(r.review_reason) : "—"}</span>,
                <span key="r" className="tnum">{r.resets || "—"}{r.reregistered ? <div className="sub2">registered again</div> : null}</span>,
                <span key="c" className="tnum">{r.card_times ?? "—"}</span>,
                r.review_reason && r.status === "SUBMITTED" && mayChange ? <Btn key="x" kind="ghost" size="sm" busyLabel="Checking…" onClick={() => revalidate(r.registration_id)}>Validate again</Btn> : <span key="x" />,
              ])} />
          ) : <PBody><div className="sub2">None.</div></PBody>}
          {pages > 1 ? (
            <PBody><div className="row row--between">
              <Btn kind="ghost" disabled={list.page === 0} onClick={() => nav({ page: list.page - 1 })}>Previous</Btn>
              <Btn kind="ghost" disabled={list.page + 1 >= pages} onClick={() => nav({ page: list.page + 1 })}>Next</Btn>
            </div></PBody>
          ) : null}
        </Panel>
      ) : null}
      <div className="sub2">A course registration reset keeps what it held on the record (the status, the approval and every course). The student&rsquo;s results, payments,
        GST/EPS entitlement and earlier semesters are never touched. A registration with a mark entered, a locked one, or a closed semester&rsquo;s is not reset.
        A course brought over from the old portal under another code is merged in Course Management, not here.</div>
    </>
  );
}
