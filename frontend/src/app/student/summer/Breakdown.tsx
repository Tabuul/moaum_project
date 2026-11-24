"use client";

/** V779 · the Summer fees, itemised: one row for the programme fee, one for each selected course, the server's own sum written out,
 *  what is owed and what is paid, and the reference to pay what is owed. The Bursary states the figures; the portal charges the
 *  programme fee once a Summer and a fee a course, never twice; nothing here works a sum the server has not. */
import { useState } from "react";
import { Btn, KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import { PayByCard, useAct } from "../common";
import { chargeLines, chargeStateWord, feeFormula, naira, num, plural, verificationTone, verificationWord, type MySummer } from "@/lib/summer";

export function Breakdown({ d }: { d: MySummer }) {
  const { act, busy, problem } = useAct();
  const a = d.account;
  const [drawn, setDrawn] = useState<{ reference: string; amount: number } | null>(null);
  const [seen, setSeen] = useState(a);
  if (a !== seen) {
    setSeen(a);
    setDrawn(null);
  }
  const due = num(d.summary?.due ?? a?.due);
  const paid = num(d.summary?.paid ?? a?.paid);
  const lines = chargeLines(d);
  const formula = feeFormula(d.summary);
  const total = d.summary?.formula?.total != null ? num(d.summary.formula.total) : due + paid;
  // V739: the server names an open reference only when it may be paid now, with its own amount; otherwise a new one is drawn
  const open = drawn ?? (a?.openReference && a.openAmount != null && due > 0 ? { reference: a.openReference, amount: num(a.openAmount) } : null);
  async function draw() {
    const r = await act("ref", "POST", "/me/summer/reference", { session: d.session }, "Summer Semester fees reference", "");
    if (r && typeof r.reference === "string" && r.amount != null) {
      setDrawn({ reference: r.reference, amount: num(r.amount as number) });
      notify("Reference ready — pay it below");
    } else if (r && r.takenBack) {
      // V741: what was chosen is no longer outstanding (passed since, or no longer taught): taken back, nothing owed
      notify("A course you selected is no longer outstanding and was taken back; nothing more is owed.");
    }
  }
  const nothingYet = !d.fee && !(due > 0 || paid > 0 || lines.length > 0);
  return (
    <Panel title="Fees and itemised calculation" right={d.fee ? `${naira(d.fee.programme_fee)} once · ${naira(d.fee.course_fee)} a course` : "Not published"}>
      <PBody>
        {nothingYet ? (
          <Note kind="info" title="The fees are not published yet">The Bursary publishes the Summer Semester fees; you can select your courses once they are.</Note>
        ) : lines.length === 0 ? (
          <div className="sub2">{num(a?.credit) > 0 ? "No Summer course of yours is charged now." : "Nothing is charged yet."} The programme fee ({naira(d.fee?.programme_fee)}) is charged once, with your first course, and each course adds {naira(d.fee?.course_fee)}.</div>
        ) : null}
      </PBody>
      {lines.length > 0 ? (
        <>
          <DTable pageSize={0} noPrint cols={["Item", "Detail", "Amount|num", "State|mid"]} title="Summer Semester fees" rows={lines.map((l, i) => [
            <b key={`i${i}`} className="tnum">{l.kind === "PROGRAMME" ? "Programme fee" : l.code}</b>,
            <span key={`t${i}`} className="sub2">{l.kind === "PROGRAMME" ? "Charged once a Summer, with your first course" : (l.title ?? "")}
              {l.kind === "COURSE" && l.verification ? <span className="blk"><Pil kind={verificationTone(l.verification)}>{verificationWord(l.verification).toUpperCase()}</Pil></span> : null}</span>,
            <span key={`a${i}`} className="tnum">{naira(l.amount)}</span>,
            <Pil key={`s${i}`} kind={l.state === "PAID" ? "ok" : l.state === "DUE" ? "warn" : "grey"}>{chargeStateWord(l.state).toUpperCase()}</Pil>,
          ])} foot={["Total", plural(lines.filter((l) => l.kind === "COURSE").length, "course"), <b key="t" className="tnum">{naira(total)}</b>, null]} />
          <PBody>
            {formula ? <div className="sub2" aria-label="How the fee is worked out">Worked out as <b className="tnum">{formula}</b>.</div> : null}
          </PBody>
        </>
      ) : null}
      <PBody>
        {d.fee || lines.length > 0 || due > 0 || paid > 0 ? (
          <KvGrid cls="grid--3" pairs={[
            ["Total charged", <span key="t" className="tnum">{naira(total)}</span>],
            ["Paid", <span key="pd" className="tnum">{naira(paid)}</span>],
            ["Owed now", <b key="o" className="tnum" style={{ color: due > 0 ? "var(--red-ink)" : "var(--green-ink)" }}>{naira(due)}</b>],
          ]} />
        ) : null}
        {num(a?.credit) > 0 ? (
          <Note kind="info" title={`${naira(a?.credit)} is held for you as a Summer credit`}>
            It is money you paid for a course that was taken off your registration (and the programme fee, once no Summer course of yours remains), or a payment that arrived after what it was for had changed. If the programme fee is held and you select a course again while registration is open, it pays the programme fee again and you pay only for the course. Otherwise the Bursary applies it to your next Summer or refunds it; nothing is refunded automatically.
          </Note>
        ) : null}
        {due > 0 && d.period?.open_now ? (
          open ? (
            <div className="mt-2">
              <div className="sub2 mb-2">Reference <b className="tnum">{open.reference}</b> for {naira(open.amount)}. Pay it by card or USSD, or at a bank against the reference. Your courses are registered when the payment is confirmed.</div>
              <div className="row" style={{ flexWrap: "wrap" }}><PayByCard reference={open.reference} amount={open.amount} /></div>
            </div>
          ) : (
            <div className="mt-2">
              <Btn kind="primary" size="md" busy={busy === "ref"} busyLabel="Preparing the reference…" disabled={busy !== null} onClick={() => void draw()}>Pay {naira(due)}</Btn>
              <div className="sub2 mt-1">One reference for everything owed now; then pay it by card or USSD. Your courses are registered when the payment is confirmed, and the Academic Office verifies each against your record.</div>
            </div>
          )
        ) : due > 0 ? (
          <div className="sub2 mt-2">Registration is closed: no payment is taken. Remove the course you selected and did not pay.</div>
        ) : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </PBody>
    </Panel>
  );
}
