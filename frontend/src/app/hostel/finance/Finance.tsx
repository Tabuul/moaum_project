"use client";

/** Hostel finance (V290): the Bursar's figures for a session — charges, paid, outstanding and exempt (no charge is not
 *  revenue and not "unpaid") — by hostel, category and status; the fee rules by hostel, room type, category and level; and
 *  every occupant's fee line for reconciliation. The Bursar states fees here; the Dean allocates rooms elsewhere. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { FEE_STATUS, callHostel, dayOf, naira, type AccountabilityRow, type FeeRule, type RoomCategory } from "@/lib/hostel";

export interface FinanceData { session: string; summary: string; rows: AccountabilityRow[] }
export interface FeesData { session: string; baseFee: number | null; rules: FeeRule[]; categories: RoomCategory[]; halls: { code: string; name: string }[]; roomTypes: { code: string; label: string; beds: number }[] }
interface Summary { totals: { charges: number; paid: number; outstanding: number; transactions: number; transactions_amount: number; paid_occupants: number; unpaid_occupants: number; exempt_allocations: number; refunds: number }; byHall: { hall: string; charges: number; paid: number; outstanding: number; exempt: number; occupants: number }[]; byCategory: { category: string; label: string; charges: number; paid: number; outstanding: number; exempt: number; occupants: number }[]; byStatus: { status: string; occupants: number; amount: number }[] }

const FINANCE = ["bursar", "financecontroller", "super"];

export function HostelFinance({ data, fees, session: s, sessions, office }: { data: FinanceData; fees: FeesData; session: string; sessions: string[]; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = !!office && FINANCE.includes(office);
  const sum = JSON.parse(data.summary) as Summary;
  const t = sum.totals;
  const [s1, s2] = s.split("/");
  const [f, setF] = useState({ hall: "", roomType: "", category: "", level: "", amount: "", note: "" });
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    try {
      const r = await callHostel("PUT", `/hostel/sessions/${s1}/${s2}/fees`, { hall: f.hall || null, roomType: f.roomType || null, category: f.category || null, level: f.level ? Number(f.level) : null, amount: Number(f.amount), note: f.note || null }, `Hostel fee rule stated for ${s}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify("Fee rule stated"); setF({ hall: "", roomType: "", category: "", level: "", amount: "", note: "" }); router.refresh();
    } finally { setBusy(false); }
  }
  async function end(id: string) {
    if (!window.confirm("End this fee rule? Allocations already made keep the fee they were given.")) return;
    const r = await callHostel("POST", `/hostel/fees/${id}/end`, {}, "Hostel fee rule ended");
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify("Fee rule ended"); router.refresh();
  }

  const rows = [...data.rows].sort((a, b) => a.occupant.localeCompare(b.occupant));
  const HEAD = ["S/N", "Occupant", "Number", "Hostel", "Room", "Category", "Fee status", "Amount", "Payment status", "Reference", "Session", "Semester"];
  const body = () => rows.map((r, i) => [i + 1, r.occupant, r.occupant_number ?? "", r.hall_name, `${r.block}-${r.room_no}`, r.category_label, FEE_STATUS[r.fee_status]?.[0] ?? r.fee_status, Number(r.fee_amount), r.payment_status, r.reference_no, r.session, r.semester ?? ""]);
  async function excel() { const blob = await brandedXlsx("Hostel Fees Reconciliation", HEAD, body(), { sheetName: "Hostel fees", serial: docSerial("BUR"), sub: s }); downloadBlob(blob, `hostel-fees-${s.replace("/", "-")}.xlsx`); }
  const pdf = () => brandedPrint("Hostel Fees Reconciliation", s, HEAD, body());
  const dims = (r: FeeRule) => [r.hall_name ?? "Every hostel", r.room_type_label ?? "Every type", r.category_label ?? "Every category", r.level ? `${r.level} Level` : "Every level"].join(" · ");

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/finance">Finance</Link><span>›</span><strong>Hostel fees</strong></div>
      <PageHead title="Hostel finance" description={`${s}. Exempt allocations are never revenue.`}
        actions={<>
          <Field id="hf-session" label="Session"><select id="hf-session" className="ctl" value={s} onChange={(e) => queryNav(`/hostel/finance?session=${encodeURIComponent(e.target.value)}`)}>{(sessions.includes(s) ? sessions : [s, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
          <Btn kind="ghost" onClick={() => void excel()} disabled={!rows.length}>Excel</Btn><Btn kind="ghost" onClick={pdf} disabled={!rows.length}>PDF</Btn>
        </>} />
      <Tiles items={[["TOTAL HOSTEL CHARGES", naira(t.charges), null, `${t.paid_occupants + t.unpaid_occupants} payable allocations`], ["PAID", naira(t.paid), "var(--green-ink)", `${t.paid_occupants} occupants · ${t.transactions} confirmed payments`], ["OUTSTANDING", naira(t.outstanding), "var(--red-ink)", `${t.unpaid_occupants} occupants owe`], ["EXEMPT ALLOCATIONS", t.exempt_allocations, "var(--chrome)", "No charge · not revenue"], ["REFUNDS / ADJUSTMENTS", t.refunds, null, "Through the Bursary's own desk"]]} cls="grid--5" />

      <div className="grid grid--2">
        <Panel title="By hostel">
          {sum.byHall.length === 0 ? <PBody><div className="sub2">No allocation this session.</div></PBody> : <DTable cols={["Hostel", "Occupants|mid", "Charges|num", "Paid|num", "Outstanding|num", "Exempt|mid"]} rows={sum.byHall.map((h) => [h.hall, h.occupants, <span className="tnum" key="c">{naira(h.charges)}</span>, <span className="tnum" key="p">{naira(h.paid)}</span>, <span className="tnum" key="o">{naira(h.outstanding)}</span>, h.exempt])} />}
        </Panel>
        <Panel title="By category">
          {sum.byCategory.length === 0 ? <PBody><div className="sub2">No allocation this session.</div></PBody> : <DTable cols={["Category", "Occupants|mid", "Charges|num", "Paid|num", "Outstanding|num", "Exempt|mid"]} rows={sum.byCategory.map((c) => [c.label, c.occupants, <span className="tnum" key="c">{naira(c.charges)}</span>, <span className="tnum" key="p">{naira(c.paid)}</span>, <span className="tnum" key="o">{naira(c.outstanding)}</span>, c.exempt])} />}
        </Panel>
      </div>

      <Panel title="Fee rules" right={fees.baseFee !== null ? `Session fee ${naira(fees.baseFee)} is the floor; the most specific rule wins` : "No session fee yet: the Dean states it on the window"}>
        {may ? (
          <PBody>
            <div className="grid grid--3">
              <Field id="fr-hall" label="Hostel"><select id="fr-hall" className="ctl" value={f.hall} onChange={(e) => setF({ ...f, hall: e.target.value })}><option value="">Every hostel</option>{fees.halls.map((h) => <option key={h.code} value={h.code}>{h.name}</option>)}</select></Field>
              <Field id="fr-type" label="Room type"><select id="fr-type" className="ctl" value={f.roomType} onChange={(e) => setF({ ...f, roomType: e.target.value })}><option value="">Every type</option>{fees.roomTypes.map((r) => <option key={r.code} value={r.code}>{r.label} ({r.beds})</option>)}</select></Field>
              <Field id="fr-cat" label="Category"><select id="fr-cat" className="ctl" value={f.category} onChange={(e) => setF({ ...f, category: e.target.value })}><option value="">Every category</option>{fees.categories.filter((c) => c.chargeable).map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</select></Field>
              <Field id="fr-level" label="Level"><select id="fr-level" className="ctl" value={f.level} onChange={(e) => setF({ ...f, level: e.target.value })}><option value="">Every level</option>{["100", "200", "300", "400", "500", "600"].map((l) => <option key={l} value={l}>{l} Level</option>)}</select></Field>
              <Field id="fr-amount" label="Fee (₦)" required><input id="fr-amount" type="number" min={0} className="ctl tnum" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} /></Field>
              <Field id="fr-note" label="Note"><input id="fr-note" className="ctl" value={f.note} onChange={(e) => setF({ ...f, note: e.target.value })} /></Field>
            </div>
            <div className="row row--tight mt-1"><Btn kind="primary" onClick={() => void save()} disabled={busy || f.amount === ""}>{busy ? "Saving…" : "State the fee rule"}</Btn><span className="sub2">Student Union and Security categories are never charged; the rule is on the category.</span></div>
          </PBody>
        ) : <PBody><Note kind="info" title="You are reading the fee rules">The Bursar states them.</Note></PBody>}
        {fees.rules.length ? <DTable cols={["Applies to", "Fee|num", "Note", "Stated|mid", "State|mid", "Action|num"]} rows={fees.rules.map((r) => [dims(r), <span className="tnum" key="a">{naira(r.amount)}</span>, <span className="sub2" key="n">{r.note ?? ""}</span>, <span className="tnum sub2" key="d">{dayOf(r.created_at)}{r.created_by_name ? ` · ${r.created_by_name}` : ""}</span>, <Pil kind={r.ended_at ? "grey" : "ok"} key="s">{r.ended_at ? `Ended ${dayOf(r.ended_at)}` : "Live"}</Pil>, may && !r.ended_at ? <Btn kind="ghost" size="sm" key="x" onClick={() => void end(r.id)}>End</Btn> : <span key="x" />])} /> : null}
      </Panel>

      <Panel title="Every occupant's fee line" right="Sorted by name · reconciliation">
        {rows.length === 0 ? <PBody><Note kind="info" title="No records found">No allocation stands for {s}.</Note></PBody> : (
          <DTable cols={["S/N|mid", "Occupant", "Room", "Category", "Fee|num", "Status|mid", "Reference"]}
            texts={rows.map((r) => `${r.occupant} ${r.occupant_number ?? ""} ${r.reference_no}`)}
            rows={rows.map((r, i) => [i + 1, <span key="o"><b>{r.occupant}</b><span className="sub2 blk tnum">{r.occupant_number ?? r.occupant_kind}</span></span>, `${r.hall_name} · ${r.block}-${r.room_no}`, r.category_label, <span className="tnum" key="f">{r.fee_status === "NO_CHARGE" ? "₦0 · no charge" : naira(r.fee_amount)}</span>, <Pil kind={FEE_STATUS[r.fee_status]?.[1] ?? "grey"} key="s">{r.payment_status}</Pil>, <span className="tnum sub2" key="r">{r.reference_no}</span>])} />
        )}
      </Panel>
    </>
  );
}
