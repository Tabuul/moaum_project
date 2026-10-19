"use client";

/** The transactions behind one figure of the hanging desk — what hangs now, what settled with no one's hand, what needs a person,
 *  what nobody went on to pay (V568) — each with who paid: the name and number, the programme, department and faculty, the level and
 *  session, and the phone and e-mail on record, so the desk can reach the payer. Opened by pressing the figure; downloads as Excel.
 *  V568: the payers of a short payment, a reversal or a hanging Pay on Quickteller payment are told from here, once per case. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal, money } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { when, DESK_HOW, TOLD_CASE, type DeskFigure, type DeskRow, type TellAnswer, type Tellable } from "@/lib/bursary";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

const TITLE: Record<DeskFigure, [string, string]> = {
  hanging: ["Hanging now", "A checkout opened in the last three days and nothing confirmed"],
  resolved: ["Resolved without a person", "Settled in the last three days by Interswitch's notification, the sweep or a request to the gateway"],
  needs: ["Needs a person", "Money against no reference or short, a reversal, a gateway silent, a notification not settled, a payer's receipt to settle"],
  abandoned: ["Abandoned", "Checkouts of the last 14 days nobody went on to pay: never taken to Quickteller, the gateway said not paid, or the payer told with no answer"],
};
const gatewayName = (g: string) => (g === "paydirect" ? "Pay on Quickteller" : g.charAt(0).toUpperCase() + g.slice(1));
const study = (r: DeskRow) => [r.programme, [r.department, r.faculty].filter(Boolean).join(" · "), [r.level ? `${r.level} Level` : null, r.session].filter(Boolean).join(" · ")];

/** what a figure's payers are told, by case: the needs figure tells short payments and reversals, the hanging figure the Pay on
 *  Quickteller payments hanging over the desk's clock */
const TELLS: Partial<Record<DeskFigure, (keyof Tellable)[]>> = { needs: ["short_paid", "reversed"], hanging: ["hanging"] };

export function DeskTransactions({ kind, rows, tellable = null, mayTell = false, tellAfterHours = 24 }: {
  kind: DeskFigure; rows: DeskRow[]; tellable?: Tellable | null; mayTell?: boolean; tellAfterHours?: number;
}) {
  const router = useRouter();
  const [title, sub] = TITLE[kind];
  const total = rows.reduce((n, r) => n + Number(r.amount ?? 0), 0);
  const cases = TELLS[kind] ?? [];
  const toTell = tellable ? cases.reduce((n, c) => n + Number(tellable[c] ?? 0), 0) : 0;
  const [asking, setAsking] = useState(false);
  const [answer, setAnswer] = useState<TellAnswer | null>(null);

  /** V568: the payers of the figure's cases told, once per case */
  async function tell() {
    const caseCode = kind === "hanging" ? "HANGING" : null;
    const told: TellAnswer = { told: 0, unreached: 0, byCase: {}, tellable: tellable ?? { short_paid: 0, reversed: 0, hanging: 0, total: 0 } };
    for (const c of caseCode ? [caseCode] : ["SHORT_PAID", "REVERSED"]) {
      const r = await fetch("/api/bff/api/v1/payments/bursary/tell", { method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Payers told: ${TOLD_CASE[c]}`) }, body: JSON.stringify({ caseCode: c }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const a = j as TellAnswer;
      told.told += Number(a.told); told.unreached += Number(a.unreached); told.tellable = a.tellable;
      for (const [k, v] of Object.entries(a.byCase ?? {})) told.byCase[k] = (told.byCase[k] ?? 0) + Number(v);
    }
    setAnswer(told);
    setAsking(false);
    notify(`${told.told} payer${told.told === 1 ? "" : "s"} told${told.unreached ? `; ${told.unreached} with no address on record` : ""}`);
    router.refresh();
  }

  async function excel() {
    const head = ["When", "Payer", "Number", "Programme", "Department", "Faculty", "Level", "Session", "Phone", "E-mail", "Reference", "Purpose", "Gateway", "Amount", "What", "Why", "Told"];
    const body = rows.map((r) => [when(r.at), r.payer ?? "", r.number ?? "", r.programme ?? "", r.department ?? "", r.faculty ?? "", r.level ?? "", r.session ?? "",
      r.phone ?? "", r.email ?? "", r.reference ?? "", r.purpose ?? "", gatewayName(r.gateway), r.amount == null ? "" : Number(r.amount), DESK_HOW[r.how]?.[0] ?? r.how, r.why ?? "",
      r.told_at ? `${when(r.told_at)}: ${TOLD_CASE[r.told_case ?? ""] ?? r.told_case ?? ""}` : ""]);
    downloadBlob(await brandedXlsx(`Hanging Payments: ${title}`, head, body, { sub, serial: docSerial("HNG"), meta: [["Transactions", String(rows.length)], ["Amount", money(total)]] }),
      `hanging-${kind}-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  return (
    <div id="transactions">
      <Panel title={`${title} · ${rows.length} transaction${rows.length === 1 ? "" : "s"}`}
        right={<span className="row row--tight">
          {mayTell && cases.length ? <Btn kind="primary" size="sm" disabled={toTell === 0} onClick={() => setAsking(true)}>{toTell ? `Tell ${toTell} payer${toTell === 1 ? "" : "s"}` : "Every payer told"}</Btn> : null}
          {rows.length ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn> : null}
          <LinkBtn kind="ghost" href="/finance/hanging">Close</LinkBtn>
        </span>}>
        <PBody><div className="sub2">{`${sub}. ${money(total)} in all.`}</div></PBody>
        {answer ? <PBody><Note kind="ok" title={`${answer.told} payer${answer.told === 1 ? "" : "s"} told`}>
          {Object.entries(answer.byCase).map(([k, v]) => `${v} of a ${TOLD_CASE[k] ?? k}`).join(", ") || "Nobody new to tell"}.
          {answer.unreached ? ` ${answer.unreached} have no e-mail or phone on record; they are told once one is.` : ""}
        </Note></PBody> : null}
        {rows.length ? (
          <DTable cols={["When|mid", "Payer", "Programme", "Contact", "Reference", "Amount|num", "What"]} rows={rows.map((r, i) => {
            const [prog, dept, level] = study(r);
            return [
              <span key="w" className="sub2 tnum">{when(r.at)}</span>,
              <Two key="p" a={r.payer ?? <span className="sub2">Not on the portal</span>} b={r.number ?? (r.payer_kind ? r.payer_kind.toLowerCase() : "")} />,
              <span key="g">{prog ?? "—"}{dept ? <div className="sub2">{dept}</div> : null}{level ? <div className="sub2">{level}</div> : null}</span>,
              <span key="c" className="sub2">{r.phone ? <div className="tnum">{r.phone}</div> : null}{r.email ? <div style={{ wordBreak: "break-all" }}>{r.email}</div> : null}{!r.phone && !r.email ? "—" : null}</span>,
              <Two key={`r${i}`} a={<span className="tnum">{r.reference ?? "—"}</span>} b={[r.purpose, gatewayName(r.gateway)].filter(Boolean).join(" · ")} />,
              <b key="a" className="tnum">{r.amount == null ? "—" : money(Number(r.amount))}</b>,
              <span key="h"><Pil kind={DESK_HOW[r.how]?.[1] ?? "grey"}>{DESK_HOW[r.how]?.[0] ?? r.how}</Pil>{r.why ? <div className="sub2">{r.why}</div> : null}
                {r.told_at ? <div className="sub2">Told {when(r.told_at)}: {TOLD_CASE[r.told_case ?? ""] ?? r.told_case}</div> : null}</span>,
            ];
          })} texts={rows.map((r) => `${r.reference ?? ""} ${r.payer ?? ""} ${r.number ?? ""} ${r.programme ?? ""} ${r.department ?? ""} ${r.phone ?? ""} ${r.email ?? ""}`)} />
        ) : <PBody><div className="sub2">Nothing here.</div></PBody>}
      </Panel>
      {asking && tellable ? (
        <Modal title={`Tell ${toTell} payer${toTell === 1 ? "" : "s"}`} onClose={() => setAsking(false)}
          foot={<><Btn kind="ghost" onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="primary" busyLabel="Telling..." onClick={() => tell()}>Tell them</Btn></>}>
          <p>Each payer is told by e-mail, SMS and on the portal (a postgraduate or JUPEB applicant by their own portal&rsquo;s message), once for each case:</p>
          <ul>
            {kind === "needs" ? <>
              <li><b>{Number(tellable.short_paid)} short paid</b>: less than the reference asks was reported. The reference stays open, the payment is with the Bursary. Do not pay it again; contact the Bursary with the receipt.</li>
              <li><b>{Number(tellable.reversed)} reversed</b>: Interswitch reported a reversal. Check whether the money came back, and contact the Bursary before paying again.</li>
            </> : <li><b>{Number(tellable.hanging)}</b> whose Pay on Quickteller payment has hung over {tellAfterHours} hours: if they paid, enter the receipt&rsquo;s Payment Log Id where they pay; if not, pay when ready.</li>}
          </ul>
          <p className="sub2">A payer already told of a case is not told again. One with no e-mail or phone on record is left until one is.</p>
        </Modal>
      ) : null}
    </div>
  );
}
