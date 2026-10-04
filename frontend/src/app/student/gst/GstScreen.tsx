"use client";
/** s/gst — GST & EPS (V314): the GST fee the Bursar stated for the student, whether a confirmed payment covers it, the reference to
 *  pay it against, the receipts, and the GST and EPS courses with their registration and result status. One payment covers both;
 *  until it is confirmed the GST/EPS courses are locked on the registration form. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { GstView, Me } from "@/lib/student-portal";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { naira, onDay, when } from "../common";

const STATE: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  PAID: ["PAID", "ok"], NOT_PAID: ["NOT PAID", "bad"], PENDING: ["REFERENCE OPEN", "warn"], NOT_STATED: ["NO FEE STATED", "grey"], NOT_REQUIRED: ["NOT REQUIRED", "grey"],
};

export function GstScreen({ s, gst }: { s: Me; gst: GstView }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  /* the clock read once, so a render is pure: an open reference is "awaiting payment" until it expires */
  const [now] = useState(() => Date.now());
  const e = gst.entitlement;
  const [word, kind] = STATE[e.state] ?? [e.state, "grey"];
  const gstCourses = gst.courses.filter((c) => c.general_office !== "EPS");
  const epsCourses = gst.courses.filter((c) => c.general_office === "EPS");
  const gstReg = gstCourses.some((c) => c.registered);
  const epsReg = epsCourses.some((c) => c.registered);
  const lockedWord = e.entitled ? "REGISTERED" : "LOCKED";
  const unpaid = e.stated && !e.entitled && e.fee > 0;

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

  const courseRows = (list: GstView["courses"]) => list.map((c, i) => [
    <span key="n" className="tnum sub2">{i + 1}</span>, <span key="c"><b className="tnum">{c.code}</b><div className="sub2">{c.title} · {c.units} units · semester {c.semester}</div></span>,
    c.offering_id ? <Pil key="o" kind="info">Offered</Pil> : <Pil key="o" kind="grey">Not offered this session</Pil>,
    <Pil key="r" kind={c.registered ? "ok" : e.entitled || !unpaid ? "grey" : "bad"}>{c.registered ? "Registered" : unpaid ? "Locked" : "Not registered"}</Pil>,
    <span key="s" className="sub2">{c.result_stage === "PUBLISHED" ? "Published" : c.result_stage ? "In progress" : "—"}</span>,
  ]);

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {unpaid ? (
        <Note kind="bad" title="GST PAYMENT REQUIRED" action={<Btn kind="primary" disabled={busy} onClick={() => void pay()}>{busy ? "Generating…" : e.open_reference ? "Show my reference" : "PAY GST FEE"}</Btn>}>
          You are required to pay the GST fee of <b className="tnum">{naira(Number(e.fee))}</b> for {gst.session} before you can register GST/EPS courses. GST payment covers both GST and EPS requirements. Please complete your GST payment to continue with course registration.
        </Note>
      ) : null}
      {e.state === "NOT_STATED" ? <Note kind="info" title={`No GST fee is stated for ${gst.session} yet`}>The Bursar states the GST fee for the session; nothing is owed until then, and your GST/EPS courses register as usual.</Note> : null}
      {e.state === "NOT_REQUIRED" && !e.stated ? <Note kind="info" title="No GST/EPS course is offered to your programme at your level">Nothing is owed for GST this session.</Note> : null}
      <Tiles items={[
        ["GST FEE", e.stated ? naira(Number(e.fee)) : "—", null, e.stated ? `For ${gst.session}` : "Not yet stated"],
        ["PAYMENT STATUS", word, kind === "ok" ? "var(--green-ink)" : kind === "bad" ? "var(--red-ink)" : null, e.paid_at ? `Paid ${onDay(e.paid_at)}` : e.open_reference ? `Reference ${e.open_reference}` : e.stated ? `${naira(Number(e.paid))} of ${naira(Number(e.fee))} paid` : "—"],
        ["GST ENTITLEMENT", e.entitled ? "ACTIVE" : unpaid ? "LOCKED" : "—", e.entitled ? "var(--green-ink)" : unpaid ? "var(--red-ink)" : null, e.entitled ? "You may register GST courses" : unpaid ? "Pay the GST fee to unlock" : "Nothing owed"],
        ["EPS ENTITLEMENT", e.entitled ? (e.covers_eps ? "COVERED" : "ACTIVE") : unpaid ? "LOCKED" : "—", e.entitled ? "var(--green-ink)" : unpaid ? "var(--red-ink)" : null, e.covers_eps ? "Covered by the GST payment" : "Not covered by GST"],
        ["GST REGISTRATION", gstReg ? "REGISTERED" : unpaid ? lockedWord : "NOT REGISTERED", gstReg ? "var(--green-ink)" : unpaid ? "var(--red-ink)" : null, `${gstCourses.filter((c) => c.registered).length} of ${gstCourses.length} GST course${gstCourses.length === 1 ? "" : "s"}`],
        ["EPS REGISTRATION", epsReg ? "REGISTERED" : unpaid ? lockedWord : "NOT REGISTERED", epsReg ? "var(--green-ink)" : unpaid ? "var(--red-ink)" : null, `${epsCourses.filter((c) => c.registered).length} of ${epsCourses.length} EPS course${epsCourses.length === 1 ? "" : "s"}`],
      ]} />

      {e.open_reference && !e.entitled ? (
        <Panel title="Pay the GST fee" right={<Pil kind="warn">REFERENCE OPEN</Pil>}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[["Reference", <b key="r" className="tnum">{e.open_reference}</b>], ["Amount", <b key="a" className="tnum">{naira(Number(e.open_amount))}</b>], ["Expires", when(e.open_expires_at)]]} />
            <div className="sub2 mt-1">Quote this reference and nothing else — at a bank branch, by transfer, or by card on Fees &amp; payments. The gateway or the Bursary confirms it; your GST and EPS courses unlock the moment it is confirmed, and you are told by email and SMS.</div>
            <div className="row row--inline row--tight mt-2"><LinkBtn kind="primary" href={`/student/fees?session=${encodeURIComponent(gst.session)}`}>Pay online on Fees &amp; payments</LinkBtn><LinkBtn kind="ghost" href="/student/register">Course registration</LinkBtn></div>
          </PBody>
        </Panel>
      ) : null}
      {e.entitled && e.reference ? (
        <Panel title="GST fee" right={<Pil kind="ok">PAID</Pil>}>
          <PBody><KvGrid cls="grid--4" pairs={[
            ["Payment reference", <span key="r" className="tnum">{e.reference}</span>], ["Payment date", onDay(e.paid_at)], ["Amount", <b key="a" className="tnum">{naira(Number(e.paid))}</b>],
            ["Receipt", <span key="x" className="row row--inline row--tight"><a className="btn btn--primary btn--sm" href={`/student/receipt/${encodeURIComponent(e.reference)}/pdf`} target="_blank" rel="noopener">View receipt</a><LinkBtn kind="ghost" size="sm" href="/student/register">Register courses</LinkBtn></span>],
          ]} /></PBody>
        </Panel>
      ) : null}

      <Panel title="GST courses" right={<span className="sub2">{s.programme} · {s.level} Level</span>}>
        {gstCourses.length ? <DTable cols={["S/N|num", "Course", "Offered|mid", "Registration|mid", "Result|mid"]} rows={courseRows(gstCourses)} /> : <PBody><div className="sub2">No GST course is offered to your programme at {s.level} level.</div></PBody>}
      </Panel>
      <Panel title="EPS courses" right={<span className="sub2">{e.covers_eps ? "Covered by the GST payment" : "Not covered by GST"}</span>}>
        {epsCourses.length ? <DTable cols={["S/N|num", "Course", "Offered|mid", "Registration|mid", "Result|mid"]} rows={courseRows(epsCourses)} /> : <PBody><div className="sub2">No EPS course is offered to your programme at {s.level} level.</div></PBody>}
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
