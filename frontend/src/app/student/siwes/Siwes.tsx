"use client";

/** studentSiwes — V752: SIWES registration at 300 Level, Second Semester. What the server says of the student (registration.
 *  siwes_eligibility) and nothing more: whether SIWES is theirs this session and, when it is not, why; the course, the training period
 *  and the deadline; the SIWES registration fee, paid once through the gateways every fee uses (a reference already drawn is paid, never a
 *  second one); then the SIWES course registered — approved as it is made, the only course of the Second Semester — its receipt and its
 *  printed form. The school fees of the semester are owed as ever; the SIWES fee is a payment of its own, never a school fee.
 *  V777 (every SIWES course carries the fee): a student whose SIWES course is among their ordinary courses (mode COURSE) sees their
 *  courses — each with its own level and semester — the fee, paid once a session, and a link to Course Registration of the semester
 *  where the course is registered; a student who holds an unpaid SIWES course from before the rule is told so and asked the fee now.
 *  The SIWES semester's page (the Second Semester of a programme SIWES binds) is as it was. */
import { useState } from "react";
import Link from "next/link";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { PayByCard, useAct, when } from "../common";
import { notify } from "@/components/proto/Toast";
import { shownCode } from "@/lib/course-code";
import {
  clearsThemselves, courseRegistrationPage, courseWhere, courseWords, coursesToRegister, dateWord, dropOthersWords, heldAs, heldCourses, heldStanding, historyLine, isCourseMode, naira, num, otherCoursesOf,
  ownCourseLine, ownCourseList, ownCourses, periodWords, reasonWords, registerLinks, schoolFeesOwed, schoolFeesWords, siwesCourseOf, siwesElsewhere, siwesNext, siwesTiles,
  sourceWord, submitLinks, unitName, FEES_PAGE, type HeldStanding, type MySiwes,
} from "@/lib/siwes";

/** the student's SIWES of the other sessions — the payment that settled each session's fee and the SIWES registration — each opening
 *  that session's SIWES here (its course, payment, receipt and printed form) */
function OtherSessions({ d }: { d: MySiwes }) {
  const rows = siwesElsewhere(d);
  if (!rows.length) return null;
  return (
    <Panel title="Your SIWES in other sessions" right={`${rows.length} session${rows.length === 1 ? "" : "s"}`}>
      <PBody>
        {rows.map((h) => {
          const [session, paid, registration] = historyLine(h);
          return (
            <div key={h.session} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
              <span className="tnum b600" style={{ minWidth: 92 }}>{session}</span>
              <span className="grow"><span className="blk">Fee: {paid}</span><span className="blk sub2">Registration: {registration}</span></span>
              <LinkBtn kind="ghost" size="sm" href={`/student/siwes?session=${encodeURIComponent(h.session)}`}>Open {h.session}</LinkBtn>
            </div>
          );
        })}
      </PBody>
    </Panel>
  );
}

/** the session's SIWES: the student's programme and course, the training period and the registration window */
function Details({ d }: { d: MySiwes }) {
  const p = d.period;
  const [word, tone] = periodWords(p, d.registrationOpen);
  return (
    <Panel title="SIWES details" right={<Pil kind={tone}>{word.toUpperCase()}</Pil>}>
      <PBody>
        <KvGrid pairs={[
          ["Session", d.session ?? "—"],
          ["Level", "300 Level"],
          ["Semester", "Second Semester"],
          ["Programme", d.programme?.name ?? "—"],
          ["Department", unitName(d.department) || "—"],
          ["Faculty", unitName(d.faculty) || "—"],
          // once registered, the course registered (never one the programme was mapped to since); before, the programme's course
          ["SIWES course", courseWords(siwesCourseOf(d))],
          ["Duration", p?.durationMonths ? `${p.durationMonths} month${p.durationMonths === 1 ? "" : "s"}` : "—"],
          ["Training starts", dateWord(p?.trainingStarts)],
          ["Expected completion", dateWord(p?.trainingEnds)],
          ["Registration opens", dateWord(p?.registrationOpens)],
          ["Registration closes", dateWord(p?.registrationCloses)],
        ]} />
      </PBody>
    </Panel>
  );
}

/** V777: the SIWES courses that are the student's — each with the level and semester it is taught in, since a SIWES course is any
 *  level's and either semester's — and where they register them. The period's registration window and training dates are those of the
 *  programmes SIWES binds, never shown as theirs */
function CourseDetails({ d }: { d: MySiwes }) {
  const own = ownCourses(d);
  return (
    <Panel title="SIWES details">
      <PBody>
        <KvGrid pairs={[
          ["Session", d.session ?? "—"],
          ["Programme", d.programme?.name ?? "—"],
          ["Department", unitName(d.department) || "—"],
          ["Faculty", unitName(d.faculty) || "—"],
          [own.length === 1 ? "SIWES course" : "SIWES courses", own.length ? <span key="c">{own.map((c) => <span key={c.code} className="blk">{ownCourseLine(c)}</span>)}</span> : "—"],
          ["Registered on", "Course Registration"],
        ]} />
      </PBody>
    </Panel>
  );
}

/** the SIWES registration fee: what the Bursary published, whether it is paid, and the one reference it is paid against */
function Fee({ d, pay }: { d: MySiwes; pay: boolean }) {
  const { act, busy, problem } = useAct();
  const [now] = useState(() => Date.now());
  const [drawn, setDrawn] = useState<{ reference: string; amount: number } | null>(null);
  const [seen, setSeen] = useState(d.openReference);
  if (d.openReference !== seen) {
    setSeen(d.openReference);
    setDrawn(null);
  }
  // a reference still open is paid as it is (its amount kept until it expires); an expired one is drawn again by the server
  const live = d.openReference && (!d.openReference.expiresAt || new Date(d.openReference.expiresAt).getTime() > now) ? d.openReference : null;
  const open = drawn ?? (live ? { reference: live.reference, amount: num(live.amount) } : null);
  async function draw() {
    const r = await act("ref", "POST", "/me/siwes/reference", {}, "SIWES registration fee reference", "");
    if (r && typeof r.reference === "string" && r.amount != null) {
      setDrawn({ reference: r.reference, amount: num(r.amount as number) });
      notify("Reference ready — pay it below");
    }
  }
  const published = d.fee?.state === "PUBLISHED";
  // V777: where the course is registered once the payment is confirmed — Course Registration for a SIWES course among the ordinary ones
  const byCourse = isCourseMode(d);
  const toRegister = ownCourseList(coursesToRegister(d));
  // a course already on the registration (registered before the rule) needs nothing more once the fee is paid
  const afterPayment = byCourse
    ? (toRegister || !heldCourses(d).length ? `Register ${toRegister || "your SIWES course"} on Course Registration once the payment is confirmed.`
      : "Your SIWES course is already on your registration; nothing more is needed once the payment is confirmed.")
    : "Register your SIWES course here once the payment is confirmed.";
  return (
    <Panel title="SIWES registration fee" right={d.paid ? <Pil kind="ok">PAID</Pil> : published ? naira(d.fee?.amount) : "Not published"}>
      <PBody>
        {d.paid ? (
          <KvGrid pairs={[
            ["Amount", <b key="a" className="tnum">{naira(d.paid.amount)}</b>],
            ["Payment reference", <span key="r" className="tnum">{d.paid.reference ?? "—"}</span>],
            ["Receipt number", <span key="n" className="tnum">{d.paid.receiptNo ?? "—"}</span>],
            ["Paid", d.paid.source === "OLD_PORTAL" ? `${dateWord(d.paid.at)} · on the old portal` : when(d.paid.at)],
          ]} />
        ) : (
          <KvGrid pairs={[
            ["Fee", <b key="a" className="tnum">{published ? naira(d.fee?.amount) : "Not published yet"}</b>],
            ["Status", "Not paid"],
            ["For", byCourse ? `Every SIWES course you register in ${d.session ?? "the session"}, once for the session` : "SIWES registration, once for the session"],
            ["School fees", "Paid apart, as every semester"],
          ]} />
        )}
        {d.paid && d.paid.source !== "OLD_PORTAL" && d.paid.reference ? (
          <div className="row mt-2" style={{ flexWrap: "wrap" }}>
            <LinkBtn kind="secondary" href={`/student/receipt/${encodeURIComponent(d.paid.reference)}`}>View payment receipt</LinkBtn>
          </div>
        ) : d.paid ? (
          <div className="sub2 mt-2">Paid on the old portal ({sourceWord(d.paid.source)}): it counts for this session&rsquo;s SIWES fee. Its receipt is the old portal&rsquo;s.</div>
        ) : null}
        {pay ? (
          open ? (
            <div className="mt-2">
              <div className="sub2 mb-2">Reference <b className="tnum">{open.reference}</b> for {naira(open.amount)}. Pay it by card or USSD, or at a bank against the reference. {afterPayment}</div>
              <div className="row" style={{ flexWrap: "wrap" }}><PayByCard reference={open.reference} amount={open.amount} /></div>
            </div>
          ) : (
            <div className="mt-2">
              <Btn kind="primary" size="md" busy={busy === "ref"} busyLabel="Preparing the reference…" disabled={busy !== null} onClick={() => void draw()}>Pay SIWES registration fee · {naira(d.fee?.amount)}</Btn>
              <div className="sub2 mt-1">One reference for the fee; then pay it by card or USSD. The fee is paid once a session.</div>
            </div>
          )
        ) : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** the SIWES course registration: made by the student once the fee is paid, approved as it is made, printed as the course form */
function Registration({ d, register, print, name, number }: { d: MySiwes; register: boolean; print: boolean; name: string; number: string }) {
  const { act, busy, problem } = useAct();
  const r = d.registration;
  const others = otherCoursesOf(d);
  const formQuery = `session=${encodeURIComponent(d.session ?? "")}&semester=2`;
  async function doRegister() {
    const j = await act("reg", "POST", "/me/siwes/register", {}, `SIWES course ${d.course?.code ?? ""} registered by the student`.trim(), "");
    if (j) notify(`${typeof j.courseCode === "string" ? j.courseCode : d.course?.code ?? "SIWES course"} registered — status: ${String(j.status ?? "APPROVED").toLowerCase()}`);
  }
  return (
    <Panel title="SIWES course registration" right={r ? <Pil kind={["APPROVED", "LOCKED"].includes(r.status) ? "ok" : "warn"}>{r.status.toUpperCase()}</Pil> : <Pil kind="grey">NOT REGISTERED</Pil>}>
      <PBody>
        {r ? (
          <KvGrid pairs={[
            ["Student", <span key="s">{name} · <span className="tnum">{number}</span></span>],
            ["Course", courseWords(siwesCourseOf(d))],
            ["Registered", when(r.at)],
            ["Semester", `Second Semester, ${d.session ?? ""}`],
          ]} />
        ) : (
          <div className="sub2">{d.course ? `${courseWords(d.course)} is the only course you register in the Second Semester. It is registered here once the SIWES fee is paid, and approved as it is registered.` : "The Academic Office has not set your programme's SIWES course yet."}</div>
        )}
        {/* K10: the SIWES course is registered only once the Second Semester school fees are cleared (REG_SEMESTER_FEES_DUE) */}
        {d.paid && !r && schoolFeesOwed(d) ? (
          <div className="sub2 mt-1">The SIWES course is registered once the Second Semester school fees are paid, as every semester: {schoolFeesWords(d, d.session)}. Pay them on <Link className="lnk" href={FEES_PAGE.href}>{FEES_PAGE.label}</Link>, then register here.</div>
        ) : null}
        {others.length && !r ? (
          <Note kind="bad" title="Other Second Semester courses are on your registration">
            {/* what Course Registration offers now (K11): Remove while add and drop is open, the reset when allowed, else the offices */}
            {dropOthersWords(others, d.clearing)}. Then register your SIWES course here.
            {clearsThemselves(d.clearing) ? <div className="mt-1"><LinkBtn kind="secondary" href={courseRegistrationPage(d.session).href}>Course registration, Second Semester</LinkBtn></div> : null}
          </Note>
        ) : null}
        <div className="row mt-2" style={{ flexWrap: "wrap" }}>
          {register ? (
            <Btn kind="primary" size="md" busy={busy === "reg"} busyLabel="Registering…" disabled={busy !== null} onClick={() => void doRegister()}>Register SIWES course{d.course ? ` · ${d.course.code}` : ""}</Btn>
          ) : null}
          {print ? (
            <>
              <a className="btn btn--primary btn--sm" href={`/student/form/pdf?${formQuery}`} target="_blank" rel="noopener">Print SIWES course registration</a>
              <LinkBtn kind="ghost" href={`/student/form?${formQuery}`}>View the form</LinkBtn>
            </>
          ) : null}
        </div>
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}

/** V777: a SIWES course among the student's ordinary courses is registered on Course Registration, the fee paid — not here. Each of
 *  their courses is listed with where it stands, and the link goes to Course Registration of the semester it is taught in (one for
 *  each semester). No other course is "in the way" of it, and nothing is printed from here: it prints with the rest of the registration */
function CourseRegistration({ d }: { d: MySiwes }) {
  const own = ownCourses(d);
  const toRegister = coursesToRegister(d);
  const links = registerLinks(d);
  const submits = submitLinks(d);
  const unsent = heldAs(d, "UNSENT");
  const awaiting = heldAs(d, "AWAITING");
  const allHeld = own.length > 0 && !toRegister.length;
  // a course only on a registration that is a draft (or was returned) is not registered: it is on the registration, not submitted
  const head = !allHeld ? <Pil kind="grey">NOT REGISTERED</Pil> : unsent.length ? <Pil kind="warn">NOT SUBMITTED</Pil>
    : awaiting.length ? <Pil kind="info">AWAITING APPROVAL</Pil> : <Pil kind="ok">REGISTERED</Pil>;
  const standing: Record<HeldStanding, { pill: string; kind: "ok" | "warn" | "info"; words: string | null }> = {
    REGISTERED: { pill: "ON YOUR REGISTRATION", kind: "ok", words: null },
    AWAITING: { pill: "AWAITING APPROVAL", kind: "info", words: "On your registration, waiting for approval" },
    UNSENT: { pill: "NOT SUBMITTED", kind: "warn", words: "On your registration, not yet submitted" },
  };
  return (
    <Panel title="SIWES course registration" right={head}>
      <PBody>
        {own.map((c) => {
          const st = c.held ? standing[heldStanding(c)] : null;
          return (
            <div key={c.code} className="row" style={{ padding: "6px 0", borderBottom: "1px solid var(--line-2)", alignItems: "center", flexWrap: "wrap", gap: 8 }}>
              <span className="tnum b600" style={{ minWidth: 92 }}>{shownCode(c.code)}</span>
              <span className="grow">{c.title ?? ""}<span className="blk sub2">{courseWhere(c, " · ")}</span>{st?.words ? <span className="blk sub2">{st.words}</span> : null}</span>
              {st ? <Pil kind={st.kind}>{st.pill}</Pil> : <Pil kind="grey">NOT REGISTERED</Pil>}
            </div>
          );
        })}
        <div className="sub2 mt-1">
          A SIWES course is registered on Course Registration once the SIWES fee is paid: paying does not register it. It is approved with your registration.
          {unsent.length ? " A course on a registration that is only saved, or was returned to you, is not registered until you submit the registration." : ""}
        </div>
        <div className="row mt-2" style={{ flexWrap: "wrap" }}>
          {d.paid ? links.map((l) => <LinkBtn key={l.href} kind="primary" href={l.href}>Register on {l.label}</LinkBtn>) : null}
          {d.paid ? submits.map((l) => <LinkBtn key={`submit-${l.href}`} kind="primary" href={l.href}>Submit your registration on {l.label}</LinkBtn>) : null}
        </div>
        {!d.paid && toRegister.length ? <div className="sub2 mt-1">Pay the SIWES registration fee above first.</div> : null}
      </PBody>
    </Panel>
  );
}

export function Siwes({ d, paid = null, name, number }: { d: MySiwes; paid?: string | null; name: string; number: string }) {
  const n = siwesNext(d);
  const confirmed = !!paid && d.paid?.reference === paid;
  const confirming = !!paid && !confirmed && d.openReference?.reference === paid;
  const byCourse = isCourseMode(d);
  // the student's SIWES is shown in full only where it is theirs: eligible now, or paid, or registered
  const theirs = d.eligible || !!d.paid || !!d.registration;
  const toRegister = ownCourseList(coursesToRegister(d));
  return (
    <>
      {confirming ? (
        <div className="card"><div className="card__body" style={{ alignItems: "center", textAlign: "center", gap: "var(--s-4)", padding: "var(--s-6) var(--s-5)" }}>
          <div><div className="t-lg b700" style={{ letterSpacing: "-.3px" }}>Confirming your payment</div>
            <p className="sub2" style={{ margin: "6px auto 0", maxWidth: "44ch", lineHeight: 1.55 }}>Reference {paid}. {byCourse ? "Register your SIWES course on Course Registration once it is confirmed." : "Register your SIWES course here once it is confirmed."}</p></div>
          <Btn kind="ghost" onClick={() => window.location.reload()}>Check again</Btn>
        </div></div>
      ) : null}
      {confirmed && d.paid ? (
        <Note kind="ok" title="SIWES registration fee confirmed">Reference {d.paid.reference} · {naira(d.paid.amount)}{d.paid.receiptNo ? ` · receipt ${d.paid.receiptNo}` : ""}. {
          byCourse ? (toRegister ? `Now register ${toRegister} on Course Registration.` : heldCourses(d).length
              ? (heldAs(d, "UNSENT").length ? "Your SIWES course is on your registration, not yet submitted: submit the registration on Course Registration." : "Your SIWES course is on your registration.")
              : "Now register your SIWES course on Course Registration.")
            : d.registration ? "Your SIWES course is registered." : "Now register your SIWES course below."}</Note>
      ) : null}
      {/* v4-2: on ELSEWHERE the student's own SIWES sessions and nothing owed here; a student SIWES does not bind owes nothing */}
      <Tiles items={siwesTiles(d, n.step).map(([label, value, sub]) => [label, value, null, sub])} />
      {/* K10: a step taken on another page (the Second Semester school fees, on Fees & payments) links there; V777: Course Registration */}
      <Note kind={n.tone} title={n.title} action={n.link ? <LinkBtn kind="urgent" href={n.link.href}>{n.link.label}</LinkBtn> : undefined}>
        {/* why not, reason by reason, when there is more than one */}
        {n.step === "NOT_ELIGIBLE" && reasonWords(d.reasons).length > 1 ? (
          <ul style={{ margin: 0, paddingLeft: "1.2em" }}>{reasonWords(d.reasons).map((w) => <li key={w}>{w}</li>)}</ul>
        ) : n.words}
        {n.step === "NOT_ELIGIBLE" ? <div className="mt-1 sub2">If you believe this is wrong, ask your department or the Academic Office.</div> : null}
      </Note>
      {/* the session shown is not the student's SIWES, which is in another: its sessions first, never this session's details as theirs */}
      {n.step === "ELSEWHERE" ? <OtherSessions d={d} /> : null}
      {n.step !== "ELSEWHERE" ? (byCourse ? <CourseDetails d={d} /> : <Details d={d} />) : null}
      {theirs ? <Fee d={d} pay={n.pay} /> : null}
      {theirs ? (byCourse ? <CourseRegistration d={d} /> : <Registration d={d} register={n.register} print={n.print} name={name} number={number} />) : null}
      {n.step !== "ELSEWHERE" ? <OtherSessions d={d} /> : null}
    </>
  );
}
