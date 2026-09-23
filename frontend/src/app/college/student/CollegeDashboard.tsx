import Link from "next/link";
import type { Me } from "@/lib/student-portal";
import { Ico, Note, Panel, PBody, Pil, Tick, Two, WarnIcon } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Passport } from "@/components/proto/blocks";
import { money, day } from "@/lib/format";

function Quick({ icon, title, sub, href }: { icon: string; title: string; sub: string; href: string }) {
  return (
    <Link href={href} className="tile" style={{ textAlign: "left", alignItems: "flex-start", textDecoration: "none" }}>
      <Ico name={icon} size={20} stroke="var(--chrome)" w={1.7} />
      <div style={{ fontSize: 13.5, fontWeight: 600, marginTop: 4 }}>{title}</div>
      <div className="c">{sub}</div>
    </Link>
  );
}

/**
 * The College of Health Sciences student's home — what this portal itself owns for them: identity,
 * matriculation, fees clearance, Senate-published results and the transcript. Course registration,
 * the timetable, continuous assessment and clinical postings belong to the College's own academic
 * system; until that is linked to the portal (a later phase), this dashboard does not show them rather
 * than draw a screen from data the portal does not hold.
 */
export function CollegeStudentDashboard({ s }: { s: Me }) {
  const f = s.fees;
  const cleared = f.clearsRegistration === true;
  const noScheme = f.clearsRegistration === null;
  const published = s.gpa.filter((g) => g.published_count > 0).length;
  return (
    <>
      <Note kind="info" title={`College of Health Sciences — ${s.programme}`}>
        Your course registration, timetable, continuous assessment and clinical postings are held by the College&rsquo;s
        own academic system. This portal carries your admission, matriculation, fees, identity card, Senate-published
        results and transcript.
      </Note>

      {noScheme ? (
        <Note kind="info" title="What a payment releases is not yet stated for this session">
          {f.schemeProblem} Your charges and payments are shown on Fees &amp; payments.
        </Note>
      ) : !cleared ? (
        <div className="notice notice--bad">
          <WarnIcon size={19} />
          <div>
            <div className="notice__t" style={{ color: "var(--red-deep)" }}>Action required</div>
            <p style={{ color: "var(--red-deep)" }}>{f.balance > 0 ? <>Your balance of <strong className="tnum">{money(f.balance)}</strong> for {f.session} is outstanding.</> : f.hasArrears ? <>Arrears from an earlier session stand against you.</> : <>The Bursary has not cleared you.</>}</p>
            <div style={{ display: "flex", gap: 8, marginTop: 11, flexWrap: "wrap" }}>
              <Link href="/student/fees" className="btn btn--urgent btn--sm">Pay now</Link>
              <Link href="/student/fees" className="btn btn--ghost btn--sm">See breakdown</Link>
            </div>
          </div>
        </div>
      ) : (
        <div className="notice notice--ok">
          <Tick size={19} colour="var(--green-ink)" />
          <div>
            <div className="notice__t" style={{ color: "var(--green-ink)" }}>You are cleared for the session</div>
            <p style={{ color: "var(--green-ink)" }}>{f.paidInFull ? `School fees settled in full for ${f.session}.` : `Your payment so far clears ${f.session}; ${money(f.balance)} remains.`}</p>
          </div>
        </div>
      )}

      <div className="card"><div className="card__body">
        <div style={{ display: "flex", gap: 13, alignItems: "flex-start", flexWrap: "wrap" }}>
          <Passport w={64} h={78} radius={6} src={s.hasPhoto ? `/api/bff/api/v1/me/passport?v=${encodeURIComponent(s.matricNo ?? s.admissionNo ?? s.id)}` : null} />
          <div>
            <div style={{ fontSize: 16, fontWeight: 600 }}>{s.name}</div>
            <div className="sub2 tnum">{s.matricNo ?? s.admissionNo}</div>
            <div className="sub2">{s.programme} &middot; {s.department}</div>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
              <span className={`pill ${s.status === "ACTIVE" ? "pill--ok" : "pill--info"}`}><span className="dot" style={{ background: s.status === "ACTIVE" ? "var(--green)" : "var(--chrome)" }} />{s.status.charAt(0) + s.status.slice(1).toLowerCase()}</span>
              <Pil kind="info">{s.level} Level</Pil>
              {s.matricNo ? <Pil kind="grey">Matriculated</Pil> : <Pil kind="grey">Admitted, not yet matriculated</Pil>}
            </div>
          </div>
        </div>
      </div></div>

      <div className="grid grid--4">
        <Quick icon="cap" title="My results" sub={published ? `${published} semester${published === 1 ? "" : "s"} published` : "Nothing published yet"} href="/student/results" />
        <Quick icon="card" title="Fees & payments" sub={f.balance > 0 ? `${money(f.balance)} outstanding` : f.due > 0 ? "Fully paid" : "No charge stated yet"} href="/student/fees" />
        <Quick icon="doc" title="Transcript" sub="Request an official copy" href="/student/transcript" />
        <Quick icon="user" title="Identity card" sub="Your card on the register" href="/student/idcard" />
      </div>

      <Panel title="Notices sent to you" right={s.notices.length ? `${s.notices.length} · email and SMS` : "none yet"}>
        {s.notices.length ? (
          <DTable cols={["When|mid", "Notice", "Channel|mid", "Status|num"]} rows={s.notices.map((n) => [
            <span className="tnum sub2" key="w">{day(n.created_at)}</span>,
            <Two key="n" a={n.subject} b={n.body} />,
            <span className="sub2" key="c">{n.channel === "SMS" ? `SMS · ${n.recipient}` : `Email · ${n.recipient}`}</span>,
            n.state === "SENT" ? <Pil kind="ok" key="s">Sent</Pil> : n.state === "FAILED" ? <Pil kind="bad" key="s">Not delivered</Pil> : <Pil kind="info" key="s">Waiting to be sent</Pil>,
          ])} />
        ) : <PBody><div className="sub2">Every notice the portal sends you is listed here as well, so nothing depends on a message reaching your phone.</div></PBody>}
      </Panel>
    </>
  );
}
