"use client";

/**
 * V637: a spillover student's fees for the session, as the Fees page and the dashboard show them — the SP year, each semester's
 * spillover fee and whether a course is registered in it (a semester's fee is owed only then, never a full session for being in
 * spillover), the carry-over courses each semester holds, what is due, paid and still to pay, with Pay and Add carry-over. The server
 * works out every figure (finance.spillover_panel).
 */
import { LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { STATUS_WORDS, semesterLine, semesterWord, spilloverStatus, spilloverTitle, type SpilloverPanel } from "@/lib/spillover";
import { naira } from "./common";

export function SpilloverCard({ sp, compact = false }: { sp: SpilloverPanel; compact?: boolean }) {
  const status = spilloverStatus(sp);
  const [word, kind] = STATUS_WORDS[status];
  const carry = sp.semesters.reduce((a, s) => a + s.carryovers, 0);
  return (
    <Panel title={spilloverTitle(sp)} right={<Pil kind={kind}>{word}</Pil>}>
      <PBody>
        <div className="sub2">
          You are in spillover ({sp.label}) for {sp.session}. You pay a semester&rsquo;s spillover fee only for a semester you register a course in &mdash; never
          the whole session&rsquo;s school fees because you are in spillover.{carry ? ` You have ${carry} carry-over course${carry === 1 ? "" : "s"} to register.` : ""}
        </div>
      </PBody>
      <DTable pageSize={0} cols={["Semester", "Carry-over courses|num", "Spillover fee|num", "This session"]}
        rows={sp.semesters.map((s) => [
          <b key="s">{semesterWord(s.semester)}</b>,
          <span key="c" className="tnum">{s.carryovers}</span>,
          <span key="f" className="tnum">{Number(s.fee) > 0 ? naira(s.fee) : "Not stated"}</span>,
          <span key="w" className="sub2">{s.registered ? <Pil kind="info">Registered</Pil> : null} {semesterLine(s)}</span>,
        ])} />
      {!compact ? sp.semesters.filter((s) => s.courses.length).map((s) => (
        <PBody key={s.semester}>
          <div className="eyebrow">{semesterWord(s.semester)} carry-over courses</div>
          <DTable pageSize={0} cols={["Course", "Title", "Units|num", "Failed in"]}
            rows={s.courses.map((c) => [<span key="c" className="tnum b600">{c.code}</span>, c.title, <span key="u" className="tnum">{c.units}</span>, <span key="f" className="tnum sub2">{c.session}</span>])} />
        </PBody>
      )) : null}
      <PBody>
        {Number(sp.sessionFee) > 0 ? <div className="sub2 mb-1">A spillover item for the whole session ({naira(sp.sessionFee)}) is owed once you register any course this session.</div> : null}
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "center" }}>
          <span className="tnum"><span className="sub2">Owed</span> <b>{naira(sp.due)}</b></span>
          <span className="tnum"><span className="sub2">Paid</span> <b className="ink-green">{naira(sp.paid)}</b></span>
          <span className="tnum"><span className="sub2">To pay</span> <b className={Number(sp.balance) >= 1 ? "ink-red" : ""}>{naira(sp.balance)}</b></span>
          <span className="grow" />
          {status === "PAYMENT_REQUIRED" ? <LinkBtn kind="primary" href={compact ? "/student/fees" : "#pay"}>Pay spillover fee {naira(sp.balance)}</LinkBtn> : null}
          <LinkBtn kind={status === "PAYMENT_REQUIRED" ? "ghost" : "primary"} href="/student/register">Add carry-over</LinkBtn>
          {compact ? <LinkBtn kind="ghost" href="/student/fees">Fees &amp; payments</LinkBtn> : null}
        </div>
        {status === "NOT_STATED" ? <div className="mt-2"><Note kind="info" title="Your spillover fee is not yet stated">The Bursary states the spillover fee for your programme; it is shown here once stated, and your registration waits for it.</Note></div> : null}
      </PBody>
    </Panel>
  );
}
