"use client";

/** The transactions behind one figure of the hanging desk — what hangs now, what settled with no one's hand, what needs a person —
 *  each with who paid: the name and number, the programme, department and faculty, the level and session, and the phone and e-mail
 *  on record, so the desk can reach the payer. Opened by pressing the figure; downloads as Excel. */
import { Btn, LinkBtn, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { when, DESK_HOW, type DeskFigure, type DeskRow } from "@/lib/bursary";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

const TITLE: Record<DeskFigure, [string, string]> = {
  hanging: ["Hanging now", "A checkout opened in the last three days and nothing confirmed"],
  resolved: ["Resolved without a person", "Settled in the last three days by Interswitch's notification, the sweep or a request to the gateway"],
  needs: ["Needs a person", "Money against no reference or short, a reversal, a gateway silent, a notification not settled, a payer's receipt to settle"],
};
const gatewayName = (g: string) => (g === "paydirect" ? "Pay on Quickteller" : g.charAt(0).toUpperCase() + g.slice(1));
const study = (r: DeskRow) => [r.programme, [r.department, r.faculty].filter(Boolean).join(" · "), [r.level ? `${r.level} Level` : null, r.session].filter(Boolean).join(" · ")];

export function DeskTransactions({ kind, rows }: { kind: DeskFigure; rows: DeskRow[] }) {
  const [title, sub] = TITLE[kind];
  const total = rows.reduce((n, r) => n + Number(r.amount ?? 0), 0);

  async function excel() {
    const head = ["When", "Payer", "Number", "Programme", "Department", "Faculty", "Level", "Session", "Phone", "E-mail", "Reference", "Purpose", "Gateway", "Amount", "What", "Why"];
    const body = rows.map((r) => [when(r.at), r.payer ?? "", r.number ?? "", r.programme ?? "", r.department ?? "", r.faculty ?? "", r.level ?? "", r.session ?? "",
      r.phone ?? "", r.email ?? "", r.reference ?? "", r.purpose ?? "", gatewayName(r.gateway), r.amount == null ? "" : Number(r.amount), DESK_HOW[r.how]?.[0] ?? r.how, r.why ?? ""]);
    downloadBlob(await brandedXlsx(`Hanging Payments: ${title}`, head, body, { sub, serial: docSerial("HNG"), meta: [["Transactions", String(rows.length)], ["Amount", money(total)]] }),
      `hanging-${kind}-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  return (
    <div id="transactions">
      <Panel title={`${title} · ${rows.length} transaction${rows.length === 1 ? "" : "s"}`}
        right={<span className="row row--tight">
          {rows.length ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn> : null}
          <LinkBtn kind="ghost" href="/finance/hanging">Close</LinkBtn>
        </span>}>
        <PBody><div className="sub2">{`${sub}. ${money(total)} in all.`}</div></PBody>
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
              <span key="h"><Pil kind={DESK_HOW[r.how]?.[1] ?? "grey"}>{DESK_HOW[r.how]?.[0] ?? r.how}</Pil>{r.why ? <div className="sub2">{r.why}</div> : null}</span>,
            ];
          })} texts={rows.map((r) => `${r.reference ?? ""} ${r.payer ?? ""} ${r.number ?? ""} ${r.programme ?? ""} ${r.department ?? ""} ${r.phone ?? ""} ${r.email ?? ""}`)} />
        ) : <PBody><div className="sub2">Nothing here.</div></PBody>}
      </Panel>
    </div>
  );
}
