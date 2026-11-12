"use client";

/** studentSummer — V735: the Summer Semester. The student sees whether they may take it and why; their outstanding courses of both
 *  semesters, each with its own semester and the session and semester it was failed in; selects the ones to take; pays one reference
 *  for what is owed (the programme fee once a Summer, a fee a course, as the Bursary published them) through the gateways every fee
 *  uses; and the payment's confirmation registers the courses. A course added later is charged its course fee alone. */
import { useState } from "react";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard, onDay, useAct, when } from "../common";
import {
  categoryWord, courseReasonWord, failedInWord, naira, nextStep, notEligibleWord, num, periodWords, selectionCost, semesterWord,
  type MySummer, type SummerCourse,
} from "@/lib/summer";

function Period({ d }: { d: MySummer }) {
  const p = d.period;
  if (!p) return null;
  const [word, tone] = periodWords(p);
  return (
    <Panel title={`Summer Semester ${p.session}`} right={<Pil kind={tone}>{word.toUpperCase()}</Pil>}>
      <PBody>
        <KvGrid pairs={[
          ["Registration opens", onDay(p.registration_opens)],
          ["Registration closes", onDay(p.registration_closes)],
          ["Examinations", p.exams_from ? `${onDay(p.exams_from)} – ${onDay(p.exams_to)}` : "Not yet dated"],
          ["Results expected", onDay(p.results_due)],
        ]} />
      </PBody>
    </Panel>
  );
}

/** the fees and the payment: what was published, what is owed and paid, the reference for what is owed */
function Fees({ d }: { d: MySummer }) {
  const { act, busy, problem } = useAct();
  const a = d.account;
  const [drawn, setDrawn] = useState<{ reference: string; amount: number } | null>(null);
  const [seen, setSeen] = useState(a);
  if (a !== seen) {
    setSeen(a);
    setDrawn(null);
  }
  const due = num(a?.due);
  // the open reference is for what is owed only while its amount is: the server closes one drawn for another figure
  const open = drawn ?? (a?.openReference && due > 0 ? { reference: a.openReference, amount: due } : null);
  async function draw() {
    const r = await act("ref", "POST", "/me/summer/reference", { session: d.session }, "Summer Semester fees reference", "Reference ready — pay it below");
    if (r && typeof r.reference === "string" && r.amount != null) setDrawn({ reference: r.reference, amount: num(r.amount as number) });
  }
  return (
    <Panel title="Summer Semester fees" right={d.fee ? `${naira(d.fee.programme_fee)} once · ${naira(d.fee.course_fee)} a course` : "Not published"}>
      <PBody>
        {!d.fee && !(a && (num(a.due) > 0 || num(a.paid) > 0)) ? (
          <Note kind="info" title="The fees are not published yet">The Bursary publishes the Summer Semester fees; you can select your courses once they are.</Note>
        ) : (
          <KvGrid pairs={[
            ["Programme fee", a?.programmeFeeState ? <span key="p" className="tnum">{naira(a.programmeFee)} · {a.programmeFeeState === "PAID" ? "paid" : "owed"}</span> : <span key="p" className="tnum">{naira(d.fee?.programme_fee)} · charged with your first course</span>],
            ["Course fees owed", <span key="c" className="tnum">{naira(a?.courseFeesDue)} ({a?.coursesSelected ?? 0} course{a?.coursesSelected === 1 ? "" : "s"})</span>],
            ["Paid", <span key="pd" className="tnum">{naira(a?.paid)}</span>],
            ["Outstanding", <b key="o" className="tnum" style={{ color: due > 0 ? "var(--red-ink)" : "var(--green-ink)" }}>{naira(due)}</b>],
          ]} />
        )}
        {due > 0 ? (
          open ? (
            <div className="mt-2">
              <div className="sub2 mb-2">Reference <b className="tnum">{open.reference}</b> for {naira(open.amount)}. Pay it by card or USSD, or at a bank against the reference. Your courses are registered when the payment is confirmed.</div>
              <div className="row" style={{ flexWrap: "wrap" }}><PayByCard reference={open.reference} amount={open.amount} /></div>
            </div>
          ) : (
            <div className="mt-2">
              <Btn kind="primary" size="md" busy={busy === "ref"} busyLabel="Preparing the reference…" disabled={busy !== null || !d.period?.open_now} onClick={() => void draw()}>Pay {naira(due)}</Btn>
              <div className="sub2 mt-1">{d.period?.open_now ? "One reference for everything owed now; then pay it by card or USSD." : "Registration is closed: no payment is taken."}</div>
            </div>
          )
        ) : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** the outstanding courses: ticked and selected together; a selected one taken back before it is paid */
function Courses({ d }: { d: MySummer }) {
  const { act, busy, problem } = useAct();
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const courses = d.courses ?? [];
  const canSelect = !!d.period?.open_now && !!d.fee && !!d.eligibility?.eligible;
  const cost = selectionCost(picked.size, d.account, d.fee);
  function toggle(c: SummerCourse) {
    setPicked((x) => {
      const n = new Set(x);
      if (n.has(c.course_code)) n.delete(c.course_code); else n.add(c.course_code);
      return n;
    });
  }
  async function select() {
    const r = await act("select", "POST", "/me/summer/select", { session: d.session, courses: [...picked] }, "Summer Semester courses selected",
      `${picked.size} course${picked.size === 1 ? "" : "s"} selected — pay to register`);
    if (r) setPicked(new Set());
  }
  if (!courses.length) {
    return <Note kind="info" title="No outstanding course">Every course you registered is passed, or its result is awaited.</Note>;
  }
  return (
    <Panel title="Your outstanding courses" right={`${courses.length} · first and second semester together`}>
      <DTable cols={["|mid", "Course", "Title", "Units|num", "Course's semester", "Failed in", "Status", "Fee|num", "|mid"]} rows={courses.map((c) => [
        c.selectable && canSelect ? <input key={`t${c.course_code}`} type="checkbox" aria-label={`Select ${c.course_code}`} checked={picked.has(c.course_code)} onChange={() => toggle(c)} /> : <span key={`t${c.course_code}`} />,
        <b key={`c${c.course_code}`} className="tnum">{c.course_code}</b>,
        <span key={`n${c.course_code}`}>{c.title ?? "—"}</span>,
        <span key={`u${c.course_code}`} className="tnum">{c.units ?? "—"}</span>,
        <span key={`s${c.course_code}`}>{c.both_semesters ? "Both" : semesterWord(c.course_semester)}</span>,
        <span key={`f${c.course_code}`} className="sub2">{failedInWord(c)}{c.attempts > 1 ? ` · ${c.attempts} attempts` : ""}</span>,
        c.status === "REGISTERED" ? <Pil key={`p${c.course_code}`} kind="ok">REGISTERED</Pil>
          : c.status === "SELECTED" ? <Pil key={`p${c.course_code}`} kind="warn">SELECTED · UNPAID</Pil>
          : c.selectable ? <Pil key={`p${c.course_code}`} kind="info">OUTSTANDING</Pil>
          : <span key={`p${c.course_code}`} className="sub2">{courseReasonWord(c.reason)}</span>,
        <span key={`fee${c.course_code}`} className="tnum">{naira(c.course_fee)}</span>,
        c.status === "SELECTED" && d.period?.open_now ? (
          <Btn key={`x${c.course_code}`} kind="ghost" size="sm" disabled={busy !== null}
               onClick={() => void act(`x${c.course_code}`, "POST", "/me/summer/unselect", { session: d.session, course: c.course_code }, `Summer course ${c.course_code} taken back`, `${c.course_code} taken back`)}>Remove</Btn>
        ) : <span key={`x${c.course_code}`} />,
      ])} />
      <PBody>
        {canSelect ? (
          <div className="row" style={{ flexWrap: "wrap", alignItems: "center" }}>
            <Btn kind="primary" size="md" busy={busy === "select"} busyLabel="Selecting…" disabled={busy !== null || picked.size === 0} onClick={() => void select()}>
              {picked.size ? `Select ${picked.size} course${picked.size === 1 ? "" : "s"} · ${naira(cost)}` : "Tick the courses to take"}
            </Btn>
            <span className="sub2">{d.account?.programmeFeeState ? "The programme fee is already charged; each course adds its course fee." : `The programme fee (${naira(d.fee?.programme_fee)}) is charged once, with your first course.`}</span>
          </div>
        ) : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** the Summer registration the payment made — printable as the Summer course form */
function Registered({ d, name, number }: { d: MySummer; name: string; number: string }) {
  const rows = d.registered ?? [];
  if (!rows.length) return null;
  const units = rows.reduce((s, r) => s + (r.units ?? 0), 0);
  return (
    <Panel title="Summer Semester registration" right={<Pil kind="ok">{(rows[0].registration_status ?? "APPROVED").toUpperCase()}</Pil>}>
      <PBody>
        <div className="sub2">{name} · <span className="tnum">{number}</span> · {d.session} Summer Semester · {rows.length} course{rows.length === 1 ? "" : "s"}, {units} units</div>
      </PBody>
      <DTable title={`Summer Semester ${d.session} · ${name} · ${number}`} cols={["Course", "Title", "Units|num", "Course's semester", "Failed in", "Lecturer", "Paid by"]} rows={rows.map((r) => [
        <b key={`c${r.course_code}`} className="tnum">{r.course_code}</b>,
        <span key={`n${r.course_code}`}>{r.title ?? "—"}</span>,
        <span key={`u${r.course_code}`} className="tnum">{r.units ?? "—"}</span>,
        <span key={`s${r.course_code}`}>{semesterWord(r.course_semester)}</span>,
        <span key={`f${r.course_code}`} className="sub2">{r.original_session ? `${semesterWord(r.original_semester)} semester, ${r.original_session}` : "—"}</span>,
        <span key={`l${r.course_code}`}>{r.lecturer ?? "Not yet allocated"}</span>,
        <span key={`p${r.course_code}`} className="tnum t-xs">{r.receipt_no ?? r.paid_reference ?? "—"}</span>,
      ])} />
    </Panel>
  );
}

export function Summer({ d, paid = null, name, number }: { d: MySummer; paid?: string | null; name: string; number: string }) {
  const a = d.account;
  const payments = d.payments ?? [];
  const back = paid ? payments.find((p) => p.reference === paid) ?? null : null;
  const confirmed = !!back?.confirmed_at;
  const confirming = !!paid && !confirmed && !!back;
  if (!d.period) {
    return <Note kind="info" title="No Summer Semester is set">The Academic Office sets the Summer Semester of a session; you will be told when it opens.</Note>;
  }
  const e = d.eligibility;
  const took = !!a && (num(a.due) > 0 || num(a.paid) > 0);
  return (
    <>
      {confirming ? (
        <div className="card"><div className="card__body" style={{ alignItems: "center", textAlign: "center", gap: "var(--s-4)", padding: "var(--s-6) var(--s-5)" }}>
          <div><div className="t-lg b700" style={{ letterSpacing: "-.3px" }}>Confirming your payment</div>
            <p className="sub2" style={{ margin: "6px auto 0", maxWidth: "44ch", lineHeight: 1.55 }}>Reference {paid}. Your courses are registered when it is confirmed.</p></div>
          <Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>
        </div></div>
      ) : null}
      {confirmed && back ? (
        <Note kind="ok" title="Summer Semester payment confirmed">Reference {back.reference} · {naira(back.amount)}{back.receipt_no ? ` · receipt ${back.receipt_no}` : ""}. Your courses are registered below.</Note>
      ) : null}
      <Tiles items={[
        ["Summer Semester", d.period.session, null, periodWords(d.period)[0]],
        ["You", e?.eligible ? "Eligible" : took ? "Registered" : "Not eligible", null, e?.eligible ? categoryWord(e.category) : took ? "" : notEligibleWord(e?.reason)],
        ["Outstanding courses", String(d.courses?.filter((c) => c.status !== "REGISTERED").length ?? 0), null, `${a?.coursesSelected ?? 0} selected · ${a?.coursesPaid ?? 0} registered`],
        ["Owed now", naira(a?.due), null, `${naira(a?.paid)} paid`],
      ]} />
      <Note kind={e?.eligible || took ? "info" : "bad"} title={nextStep(d)}>
        {e?.eligible
          ? "Select any of your outstanding courses of the first and second semesters together. A course is registered once its fee is paid; you may add more while registration is open."
          : took ? "What you paid for stays registered." : "If you believe this is wrong, ask your department or the Academic Office."}
      </Note>
      <Period d={d} />
      {e?.eligible || took ? <Fees d={d} /> : null}
      {e?.eligible || took ? <Courses d={d} /> : null}
      <Registered d={d} name={name} number={number} />
      {payments.length ? (
        <Panel title="Summer Semester payments" right={String(payments.length)}>
          <DTable cols={["Reference", "For", "Amount|num", "Drawn", "Status"]} rows={payments.map((p) => [
            <span key={`r${p.reference}`} className="tnum t-xs">{p.reference}</span>,
            <span key={`f${p.reference}`} className="sub2">{p.purpose.replace(/^Summer semester fees, [^:]+: /, "")}</span>,
            <span key={`a${p.reference}`} className="tnum">{naira(p.amount)}</span>,
            <span key={`d${p.reference}`} className="sub2">{when(p.generated_at)}</span>,
            p.confirmed_at ? <Pil key={`s${p.reference}`} kind="ok">PAID{p.receipt_no ? ` · ${p.receipt_no}` : ""}</Pil> : <Pil key={`s${p.reference}`} kind="warn">AWAITING PAYMENT</Pil>,
          ])} />
        </Panel>
      ) : null}
    </>
  );
}
