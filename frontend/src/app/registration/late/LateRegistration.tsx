"use client";

/**
 * Late registration (V516): the Registry registers a student whose registration window closed — a late admission, a fees case settled
 * after the deadline, a medical case — on the student's behalf, with a reason. The student's own courses for the semester are listed
 * with what the engine says of each: the registration window and the add and drop period are set aside; the fees, the GST/EPS fee,
 * the load, the prerequisites and every other rule hold. The registration is submitted as the student's would be (approved by the
 * semester's rule or left for the Head of Department), recorded, and the student is told.
 */
import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import type { LateRow, LateStudent } from "@/lib/late-registration";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const SEM = (n: number) => (n === 1 ? "First" : n === 2 ? "Second" : "Third") + " semester";

export function LateRegistration({ recent, session, mayRegister }: { recent: LateRow[]; session: string; mayRegister: boolean }) {
  const router = useRouter();
  const [number, setNumber] = useState("");
  const [ses, setSes] = useState(session);
  const [sem, setSem] = useState(1);
  const [v, setV] = useState<LateStudent | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [reason, setReason] = useState("");

  async function find(n = number, s = ses, m = sem) {
    if (!n.trim()) return;
    const qs = new URLSearchParams({ number: n.trim(), session: s, semester: String(m) });
    const r = await fetch(`/api/bff/api/v1/registration/late/student?${qs.toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); setV(null); return; }
    const d = j as LateStudent;
    setV(d);
    // the student's carry-overs and the courses not yet on the registration that nothing blocks, ticked to start with
    setChosen(new Set(d.menu.filter((x) => !x.registered && !x.blocked_by && (x.carryover || x.deferred)).map((x) => x.offering_id)));
  }

  const onReg = useMemo(() => (v?.menu ?? []).filter((x) => x.registered).reduce((n, x) => n + x.units, 0), [v]);
  const adding = (v?.menu ?? []).filter((x) => chosen.has(x.offering_id)).reduce((n, x) => n + x.units, 0);
  const total = onReg + adding;
  const min = v?.load?.min_units ?? 0;
  const max = v?.load?.max_units ?? 0;

  async function register() {
    if (!v) return;
    const r = await fetch("/api/bff/api/v1/registration/late", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Late registration by the Registry: ${reason.trim()}`) },
      body: JSON.stringify({ studentId: v.student.id, session: v.session, semester: v.semester, offerings: Array.from(chosen), reason: reason.trim() }),
    });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    notify(`${v.student.name} registered: ${j.courses} course${j.courses === 1 ? "" : "s"}, ${j.units} credit units, ${String(j.status).toLowerCase()}. The student is told.`);
    setReason("");
    await find(number, v.session, v.semester);
    router.refresh();
  }

  return (
    <>
      <PageHead title="Late registration" eyebrow="Registry"
        description="Register a student whose registration window has closed, on the student's behalf and with the reason. Only the window and the add and drop period are set aside: the fees, the GST/EPS fee, the course load, the prerequisites and every other rule hold, and the registration goes for approval as the student's would. A registration submitted after the window closes carries the late registration fee where the Bursary set one." />

      <div className="row" style={{ flexWrap: "wrap", gap: 12, alignItems: "flex-end" }}>
        <form className="row row--inline" style={{ gap: 8 }} onSubmit={(e) => { e.preventDefault(); void find(); }}>
          <Field id="lr-number" label="Matriculation or admission number"><input id="lr-number" className="ctl tnum" value={number} onChange={(e) => setNumber(e.target.value)} placeholder="e.g. MOAU/22/SCI/0123" /></Field>
          <Field id="lr-session" label="Academic session"><input id="lr-session" className="ctl tnum" value={ses} onChange={(e) => setSes(e.target.value)} style={{ maxWidth: 120 }} /></Field>
          <Field id="lr-semester" label="Semester"><select id="lr-semester" className="ctl" value={sem} onChange={(e) => { const m = Number(e.target.value); setSem(m); if (v) void find(number, ses, m); }}>
            <option value={1}>First semester</option><option value={2}>Second semester</option><option value={3}>Third semester</option></select></Field>
          <Btn kind="primary" type="submit" disabled={!number.trim()}>Find</Btn>
        </form>
      </div>

      {v ? (
        <>
          <Panel title={v.student.name} right={<Link className="lnk" href={`/students/${v.student.id}`}>Student record</Link>}>
            <PBody>
              <div className="grid grid--4">
                <div className="kv"><span className="k">Number</span><span className="v tnum">{v.student.matric_no ?? v.student.admission_no}</span></div>
                <div className="kv"><span className="k">Programme</span><span className="v">{v.student.programme ?? "—"} · {v.student.current_level} Level</span></div>
                <div className="kv"><span className="k">Registration</span><span className="v">{v.registration ? `${v.registration.status.charAt(0) + v.registration.status.slice(1).toLowerCase()} · ${v.registration.units} units` : "None yet"}</span></div>
                <div className="kv"><span className="k">Course load</span><span className="v tnum">{v.load ? `${v.load.min_units}–${v.load.max_units} units` : "—"}</span></div>
              </div>
              <div className="row row--tight mt-2" style={{ flexWrap: "wrap" }}>
                <Pil kind={v.window ? "warn" : "ok"}>{v.window ? "Window closed: set aside" : "Window open"}</Pil>
                <Pil kind={v.feesCleared ? "ok" : v.feesCleared === false ? "bad" : "grey"}>{v.feesCleared ? "Cleared by the Bursary" : v.feesCleared === false ? "Not cleared by the Bursary" : "Clearance unknown"}</Pil>
                {v.student.status !== "ADMITTED" && v.student.status !== "ACTIVE" && v.student.status !== "PROBATION" ? <Pil kind="bad">{v.student.status.toLowerCase()}</Pil> : null}
              </div>
              {v.window ? <div className="sub2 mt-1">{v.window}</div> : null}
              {v.feesCleared === false ? <Note kind="bad" title="The student is not cleared for registration">The fees hold for a late registration as for the student&rsquo;s own; the Bursary clears the student first.</Note> : null}
            </PBody>
          </Panel>

          <Panel title={`${SEM(v.semester)} ${v.session}: the student's courses`} right={`${total} units${min ? ` · ${min}–${max}` : ""}`}>
            {v.menu.length ? (
              <DTable pageSize={0} cols={["", "Course", "Units|num", "Kind", "What the engine says"]}
                rows={v.menu.map((x) => [
                  <input key="c" type="checkbox" aria-label={`Register ${x.course_code}`} checked={x.registered || chosen.has(x.offering_id)} disabled={x.registered || !!x.blocked_by || !mayRegister}
                    onChange={(e) => { const s = new Set(chosen); if (e.target.checked) s.add(x.offering_id); else s.delete(x.offering_id); setChosen(s); }} />,
                  <span key="t"><b className="tnum">{x.course_code}</b> {x.title}</span>,
                  <span key="u" className="tnum">{x.units}</span>,
                  <span key="k" className="sub2">{x.carryover ? (x.deferred ? "Deferred" : "Carry-over") : x.basis ?? x.kind ?? "—"}</span>,
                  x.registered ? <Pil key="s" kind="ok">On the registration</Pil>
                    : x.blocked_by ? <span key="s" className="sub2 ink-red">{x.blocked_by}</span>
                    : <span key="s" className="sub2">{x.window_set_aside ? "May be registered late (window set aside)" : "May be registered"}</span>,
                ])} />
            ) : <PBody><div className="sub2">No course is offered to the student for this semester.</div></PBody>}
            {mayRegister ? (
              <PBody>
                {total && max && total > max ? <Note kind="bad" title={`Over the maximum of ${max} units`}>Untick courses, or the student asks the Head of Department for an overload first.</Note> : null}
                {total && min && total < min ? <Note kind="info" title={`Below the minimum of ${min} units`}>The submission refuses a load below the minimum; add courses.</Note> : null}
                <Field id="lr-reason" label="Reason" required hint="Ten characters or more; on the registration, the record and the student's notice">
                  <input id="lr-reason" className="ctl" value={reason} maxLength={1000} onChange={(e) => setReason(e.target.value)} placeholder="e.g. admitted late by Senate's decision of 3 October" />
                </Field>
                <div className="mt-2"><Btn kind="primary" disabled={!chosen.size || reason.trim().length < 10} busyLabel="Registering…" onClick={() => register()}>Register {chosen.size} course{chosen.size === 1 ? "" : "s"} and submit</Btn></div>
              </PBody>
            ) : null}
          </Panel>

          {v.history.length ? (
            <Panel title="Late registrations of this student">
              <DTable pageSize={0} cols={["When|mid", "Semester|mid", "Courses|num", "Units|num", "Status", "Reason", "By"]}
                rows={v.history.map((h, i) => [<span key={`a${i}`} className="tnum sub2">{day(h.at)}</span>, <span key={`s${i}`} className="tnum">{h.semester}</span>,
                  <span key={`c${i}`} className="tnum">{h.courses}</span>, <span key={`u${i}`} className="tnum">{h.units}</span>, <span key={`t${i}`}>{h.status.toLowerCase()}</span>,
                  <span key={`r${i}`} className="sub2">{h.reason}</span>, <span key={`b${i}`} className="sub2">{h.by_name ?? h.by_office}</span>])} />
            </Panel>
          ) : null}
        </>
      ) : null}

      <Panel title={`Late registrations, ${session}`} right={`${recent.length} shown`}>
        {recent.length ? (
          <DTable pageSize={25} cols={["When|mid", "Student", "Programme", "Semester|mid", "Courses|num", "Units|num", "Status", "Reason", "By"]}
            rows={recent.map((r) => [
              <span key="a" className="tnum sub2">{day(r.at)}</span>,
              <span key="n"><Link className="lnk" href={`/students/${r.student_id}`}>{r.name}</Link><div className="sub2 tnum">{r.number ?? ""}</div></span>,
              <span key="p" className="sub2">{r.programme ?? "—"}</span>, <span key="s" className="tnum">{r.semester}</span>, <span key="c" className="tnum">{r.courses}</span>,
              <span key="u" className="tnum">{r.units}</span>, <span key="t">{r.status.toLowerCase()}</span>, <span key="r" className="sub2">{r.reason}</span>,
              <span key="b" className="sub2">{r.by_name ?? r.by_office}</span>,
            ])} />
        ) : <PBody><div className="sub2">None this session.</div></PBody>}
      </Panel>
    </>
  );
}
