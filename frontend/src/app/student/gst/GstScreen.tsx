"use client";
/** s/gst — GST & EPS (V314): the GST fee the Bursar stated for the student, whether a confirmed payment covers it, the reference to
 *  pay it against, the receipts, and the GST and EPS courses with their registration and result status. One payment covers both;
 *  until it is confirmed the GST/EPS courses are locked on the registration form.
 *  V366: the fee is owed only when a GST or EPS course requires it of the student this session — a course their programme offers at
 *  their level, or a carryover — and the page says which, and why not when it is not.
 *  The reference is paid by card or USSD from this page (the same gateways as school fees), and the gateway returns the payer here. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { GstView, Me } from "@/lib/student-portal";
import { COURSE_STATUS_WORD, SOURCE_WORD, reasonWord } from "@/lib/gst";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { PayByCard, naira, onDay, when } from "../common";

const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  PAID: ["PAID", "ok"], NOT_PAID: ["NOT PAID", "bad"], PENDING: ["REFERENCE OPEN", "warn"], NOT_STATED: ["NO FEE STATED", "grey"], NOT_REQUIRED: ["NOT REQUIRED", "grey"],
  EXEMPT: ["NO FEE FOR YOU", "info"],
};

export function GstScreen({ s, gst, paid = null }: { s: Me; gst: GstView; paid?: string | null }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  /* the clock read once, so a render is pure: an open reference is "awaiting payment" until it expires */
  const [now] = useState(() => Date.now());
  const e = gst.entitlement;
  const el = gst.eligibility ?? null;
  const [word, kind] = STATE[e.state] ?? [e.state, "grey"];
  const gstCourses = gst.courses.filter((c) => c.general_office !== "EPS");
  const epsCourses = gst.courses.filter((c) => c.general_office === "EPS");
  const owes = (list: GstView["courses"]) => list.filter((c) => c.counts !== false);
  const gstReg = owes(gstCourses).some((c) => c.registered);
  const epsReg = owes(epsCourses).some((c) => c.registered);
  const lockedWord = e.entitled ? "REGISTERED" : "LOCKED";
  const unpaid = e.required && e.stated && !e.entitled && e.fee > 0;
  const concerned = e.required || e.state === "PAID";

  async function pay() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/me/gst/reference", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ session: gst.session }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      notify(`Reference ${j.reference} generated for the GST fee`);
      router.refresh();
    } finally { setBusy(false); }
  }

  const why = (c: GstView["courses"][number]) => (
    <span className="sub2">
      {SOURCE_WORD[c.source ?? ""] ?? "—"}
      {c.source === "CARRYOVER" ? ` · failed ${c.failed_in ?? ""}${c.last_grade ? ` (${c.last_grade})` : ""} · re-register` : ""}
      {c.status === "ALREADY_PASSED" && c.passed_in ? ` · passed ${c.passed_in}` : ""}
    </span>
  );
  const courseRows = (list: GstView["courses"]) => list.map((c, i) => {
    const [sw, sk] = COURSE_STATUS_WORD[c.status ?? ""] ?? [c.offering_id ? "Offered" : "Not run this session", c.offering_id ? "info" : "grey"];
    const owed = c.counts !== false;
    return [
      <span key="n" className="tnum sub2">{i + 1}</span>,
      <span key="c"><b className="tnum">{c.code}</b>{c.source === "CARRYOVER" ? <> <Pil kind="warn">CARRYOVER</Pil></> : null}<div className="sub2">{c.title} · {c.units} units · semester {c.semester}</div></span>,
      <span key="w">{why(c)}</span>,
      <Pil key="o" kind={sk}>{sw}</Pil>,
      <Pil key="r" kind={c.registered ? "ok" : !owed ? "grey" : e.entitled || !unpaid ? "grey" : "bad"}>{c.registered ? "Registered" : !owed ? "—" : unpaid ? "Locked" : "Not registered"}</Pil>,
      <span key="s" className="sub2">{c.result_stage === "PUBLISHED" ? "Published" : c.result_stage ? "In progress" : "—"}</span>,
    ];
  });
  const cols = ["S/N|num", "Course", "Why it concerns you", "This session|mid", "Registration|mid", "Result|mid"];

  const back = paid ? gst.references.find((r) => r.reference === paid) ?? null : null;
  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {back && back.confirmed_at ? <Note kind="ok" title="GST fee payment confirmed">Reference {back.reference} is confirmed. It covers both GST and EPS: register your GST/EPS courses on Course registration.</Note> : null}
      {back && !back.confirmed_at ? (
        <Note kind="info" title="Confirming your GST payment" action={<Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>}>
          The gateway tells the University directly when the money lands, and the portal re-checks the reference every ten minutes. Reference {back.reference}. If you were not debited, pay again below.
        </Note>
      ) : null}
      {unpaid ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={e.open_reference ? null : <Btn kind="primary" disabled={busy} onClick={() => void pay()}>{busy ? "Generating…" : "PAY GST FEE"}</Btn>}>
          You are required to pay the GST fee of <b className="tnum">{naira(Number(e.fee))}</b> for {gst.session} before you can register GST/EPS courses: {reasonWord(e.reason)}
          {owes(gst.courses).length ? ` (${owes(gst.courses).map((c) => c.code).join(", ")})` : ""}. GST payment covers both GST and EPS requirements. Please complete your GST payment to continue with course registration.
        </Note>
      ) : null}
      {e.required && e.state === "NOT_STATED" ? <Note kind="info" title={`No GST fee is stated for ${gst.session} yet`}>The Bursar states the GST fee for the session; nothing is owed until then, and your GST/EPS courses register as usual.</Note> : null}
      {e.state === "EXEMPT" ? <Note kind="info" title={`No GST fee for you in ${gst.session}`}>The GST fee the Bursar stated for students of your category is nothing. Your GST/EPS courses register as usual.</Note> : null}
      {e.state === "NOT_REQUIRED" ? (
        <Note kind="info" title={`No GST or EPS payment is required of you in ${gst.session}`}>
          {el ? <>GST: {reasonWord(el.gst_reason)}. EPS: {reasonWord(el.eps_reason)}.</> : "No GST or EPS course is offered to your programme at your level, and none is carried over."}
          {" "}Nothing is owed and nothing holds your course registration. If you believe a course is missing, ask ICT Support to check your eligibility.
        </Note>
      ) : null}
      {e.review ? (
        <Note kind="info" title="Paid, though no course requires it this session">
          No GST or EPS course requires the fee of you in {gst.session}. Your payment stands as paid; the Bursary reviews it. Nothing is deleted or refunded without them.
        </Note>
      ) : null}
      {concerned ? (
        <Tiles items={[
          ["GST FEE", e.stated ? naira(Number(e.fee)) : "—", null, e.stated ? `For ${gst.session}` : "Not yet stated"],
          ["PAYMENT STATUS", word, kind === "ok" ? "var(--green-ink)" : kind === "bad" ? "var(--red-ink)" : null, e.paid_at ? `Paid ${onDay(e.paid_at)}` : e.open_reference ? `Reference ${e.open_reference}` : e.stated ? `${naira(Number(e.paid))} of ${naira(Number(e.fee))} paid` : "—"],
          ["GST ENTITLEMENT", e.entitled ? "ACTIVE" : unpaid ? "LOCKED" : "—", e.entitled ? "var(--green-ink)" : unpaid ? "var(--red-ink)" : null, e.entitled ? "You may register GST courses" : unpaid ? "Pay the GST fee to unlock" : "Nothing owed"],
          ["EPS ENTITLEMENT", e.entitled ? (e.covers_eps ? "COVERED" : "ACTIVE") : unpaid ? "LOCKED" : "—", e.entitled ? "var(--green-ink)" : unpaid ? "var(--red-ink)" : null, e.covers_eps ? "Covered by the GST payment" : "Not covered by GST"],
          ["GST REGISTRATION", gstReg ? "REGISTERED" : unpaid && e.gst_required !== false ? lockedWord : e.gst_required === false ? "NOT REQUIRED" : "NOT REGISTERED", gstReg ? "var(--green-ink)" : unpaid && e.gst_required !== false ? "var(--red-ink)" : null, `${owes(gstCourses).filter((c) => c.registered).length} of ${owes(gstCourses).length} GST course${owes(gstCourses).length === 1 ? "" : "s"} owed`],
          ["EPS REGISTRATION", epsReg ? "REGISTERED" : unpaid && e.eps_required ? lockedWord : !e.eps_required ? "NOT REQUIRED" : "NOT REGISTERED", epsReg ? "var(--green-ink)" : unpaid && e.eps_required ? "var(--red-ink)" : null, `${owes(epsCourses).filter((c) => c.registered).length} of ${owes(epsCourses).length} EPS course${owes(epsCourses).length === 1 ? "" : "s"} owed`],
        ]} />
      ) : null}

      {e.open_reference && !e.entitled ? (
        <Panel title="Pay the GST fee" right={<Pil kind="warn">REFERENCE OPEN</Pil>}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[["Reference", <b key="r" className="tnum">{e.open_reference}</b>], ["Amount", <b key="a" className="tnum">{naira(Number(e.open_amount))}</b>], ["Expires", when(e.open_expires_at)]]} />
            <div className="row mt-2"><PayByCard reference={e.open_reference} amount={Number(e.open_amount)} /></div>
            <div className="sub2 mt-1">Pay by card or USSD above, or quote this reference and nothing else at a bank branch or by transfer. The gateway or the Bursary confirms it; your GST and EPS courses unlock the moment it is confirmed, and you are told by email and SMS.</div>
            <div className="row row--inline row--tight mt-2"><LinkBtn kind="ghost" href="/student/register">Course registration</LinkBtn></div>
          </PBody>
        </Panel>
      ) : null}
      {e.entitled && e.reference ? (
        <Panel title="GST fee" right={<span className="row row--inline row--tight"><Pil kind="ok">PAID</Pil>{e.source === "LEGACY_PORTAL" ? <Pil kind="info">Paid on the old portal</Pil> : null}</span>}>
          <PBody><KvGrid cls="grid--4" pairs={[
            ["Payment reference", <span key="r" className="tnum">{e.legacy_reference ?? e.reference}</span>], ["Payment date", onDay(e.paid_at)], ["Amount", <b key="a" className="tnum">{naira(Number(e.paid))}</b>],
            ["Payment source", e.source === "LEGACY_PORTAL" ? "Old portal — reconciled, nothing to pay again" : e.channel ?? "This portal"],
            ["Receipt", <span key="x" className="row row--inline row--tight"><a className="btn btn--primary btn--sm" href={`/student/receipt/${encodeURIComponent(e.reference)}/pdf`} target="_blank" rel="noopener">View receipt</a><LinkBtn kind="ghost" size="sm" href="/student/register">Register courses</LinkBtn></span>],
            ["Academic session", gst.session], ["GST registration", gstReg ? "Registered" : e.gst_required === false ? "Not required" : "Available"], ["EPS registration", epsReg ? "Registered" : !e.eps_required ? "Not required" : e.covers_eps ? "Available" : "—"],
          ]} />
          {e.source === "LEGACY_PORTAL" ? <div className="sub2 mt-1">Your GST payment on the old portal{e.legacy_reference ? ` (${e.legacy_reference})` : ""} was verified and reconciled by the Bursary; it covers both GST and EPS for {gst.session}. You will not be asked to pay again.</div> : null}
          </PBody>
        </Panel>
      ) : null}

      <Panel title="GST courses" right={<span className="sub2">{s.programme} · {s.level} Level</span>}>
        {gstCourses.length ? <DTable cols={cols} rows={courseRows(gstCourses)} /> : <PBody><div className="sub2">No GST course concerns you this session: none is offered to your programme at {s.level} level, and you carry none over.</div></PBody>}
      </Panel>
      <Panel title="EPS courses" right={<span className="sub2">{e.covers_eps ? "Covered by the GST payment" : "Not covered by GST"}</span>}>
        {epsCourses.length ? <DTable cols={cols} rows={courseRows(epsCourses)} /> : <PBody><div className="sub2">No EPS course concerns you this session: none is offered to your programme at {s.level} level, and you carry none over.</div></PBody>}
      </Panel>
      <Panel title="GST payment history">
        {gst.references.length ? <DTable cols={["S/N|num", "Reference", "Session|mid", "Amount|num", "Generated|mid", "Status|mid", "Receipt|mid"]} rows={gst.references.map((r, i) => [
          <span key="n" className="tnum sub2">{i + 1}</span>, <span key="r" className="tnum">{r.reference}</span>, <span key="s" className="tnum">{r.session}</span>, <span key="a" className="tnum">{naira(Number(r.amount))}</span>,
          <span key="g" className="sub2">{when(r.generated_at)}</span>,
          <Pil key="t" kind={r.confirmed_at ? "ok" : new Date(r.expires_at).getTime() > now ? "warn" : "grey"}>{r.confirmed_at ? `Confirmed ${onDay(r.confirmed_at)}` : new Date(r.expires_at).getTime() > now ? "Awaiting payment" : "Expired"}</Pil>,
          r.confirmed_at ? <a key="x" className="btn btn--ghost btn--sm" href={`/student/receipt/${encodeURIComponent(r.reference)}/pdf`} target="_blank" rel="noopener">Receipt</a> : <span key="x" className="sub2">—</span>,
        ])} /> : <PBody><div className="sub2">No GST payment on record yet.</div></PBody>}
      </Panel>
    </>
  );
}
