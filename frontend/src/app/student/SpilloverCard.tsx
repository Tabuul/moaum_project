"use client";

/**
 * V637: a spillover student's fees for the session, as the Fees page and the dashboard show them — the SP year, each semester's
 * spillover fee and whether a course is registered in it (a semester's fee is owed only then, never a full session for being in
 * spillover), the carry-over courses each semester holds, what is due, paid and still to pay, with Pay and Add carry-over. The server
 * works out every figure (finance.spillover_panel).
 */
import { LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { SEMESTER_STATUS_WORDS, STATUS_WORDS, semesterLine, semesterWord, spilloverStatus, spilloverTitle, type SpilloverPanel } from "@/lib/spillover";
import { naira } from "./common";

export function SpilloverCard({ sp, compact = false }: { sp: SpilloverPanel; compact?: boolean }) {
  const status = spilloverStatus(sp);
  const [word, kind] = STATUS_WORDS[status];
  const carry = sp.semesters.reduce((a, s) => a + s.carryovers, 0);
  // V664: each semester's own fee, the payments applied to it and what is left — a semester to pay is named, never the session
  const perSemester = sp.semesters.some((s) => s.status);
  const owing = sp.semesters.filter((s) => s.status === "PAYMENT_REQUIRED" || s.status === "PART_PAID");
  return (
    <Panel title={spilloverTitle(sp)} right={<Pil kind={kind}>{word}</Pil>}>
      <PBody>
        <div className="sub2">
          You are in spillover ({sp.label}) for {sp.session}. You pay a semester&rsquo;s spillover fee only for a semester you register a course in &mdash; never
          the whole session&rsquo;s school fees because you are in spillover. Each semester is paid for itself: a first semester payment does not open
          the second semester. Every course you register in spillover is a carry-over: add the courses you still owe with Add carry-over.{carry ? ` Your published results state ${carry} carry-over course${carry === 1 ? "" : "s"}.` : ""}
        </div>
      </PBody>
      {perSemester ? (
        <DTable pageSize={0} cols={["Semester", "Carry-overs on results|num", "Courses registered|num", "Spillover fee|num", "Paid|num", "Outstanding|num", "Status"]}
          rows={sp.semesters.map((s) => {
            const [word, tone] = SEMESTER_STATUS_WORDS[s.status ?? "NOTHING_OWED"];
            return [
              <b key="s">{semesterWord(s.semester)}</b>,
              <span key="c" className="tnum">{s.carryovers}</span>,
              <span key="r" className="tnum">{s.registeredCourses ?? 0}</span>,
              <span key="f" className="tnum">{Number(s.fee) > 0 ? naira(s.fee) : "Not stated"}</span>,
              <span key="p" className="tnum ink-green">{s.registered ? naira(s.paid ?? 0) : "—"}</span>,
              <span key="o" className={`tnum${Number(s.outstanding ?? 0) >= 1 ? " ink-red b600" : ""}`}>{s.registered ? naira(s.outstanding ?? 0) : "—"}</span>,
              <span key="w"><Pil kind={tone}>{word}</Pil><div className="sub2 mt-1">{semesterLine(s)}</div></span>,
            ];
          })} />
      ) : (
        <DTable pageSize={0} cols={["Semester", "Carry-overs on results|num", "Courses registered|num", "Spillover fee|num", "This session"]}
          rows={sp.semesters.map((s) => [
            <b key="s">{semesterWord(s.semester)}</b>,
            <span key="c" className="tnum">{s.carryovers}</span>,
            <span key="r" className="tnum">{s.registeredCourses ?? 0}</span>,
            <span key="f" className="tnum">{Number(s.fee) > 0 ? naira(s.fee) : "Not stated"}</span>,
            <span key="w" className="sub2">{s.registered ? <Pil kind="info">Registered</Pil> : null} {semesterLine(s)}</span>,
          ])} />
      )}
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
          {status === "PAYMENT_REQUIRED" ? (
            owing.length === 1
              ? <LinkBtn kind="primary" href={compact ? "/student/fees" : "#pay"}>Pay {semesterWord(owing[0].semester).toLowerCase()} fee {naira(owing[0].toClear ?? owing[0].outstanding ?? sp.balance)}</LinkBtn>
              : <LinkBtn kind="primary" href={compact ? "/student/fees" : "#pay"}>Pay spillover fee {naira(sp.balance)}</LinkBtn>
          ) : null}
          <LinkBtn kind={status === "PAYMENT_REQUIRED" ? "ghost" : "primary"} href="/student/register?carry=1">Add carry-over</LinkBtn>
          {compact ? <LinkBtn kind="ghost" href="/student/fees">Fees &amp; payments</LinkBtn> : null}
        </div>
        {status === "NOT_STATED" ? <div className="mt-2"><Note kind="info" title="Your spillover fee is not yet stated">The Bursary states the spillover fee for your programme; it is shown here once stated, and your registration waits for it.</Note></div> : null}
      </PBody>
    </Panel>
  );
}
