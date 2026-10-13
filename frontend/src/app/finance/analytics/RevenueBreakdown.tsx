"use client";

/** The revenue breakdown: one full-width report in place of a wall of narrow tables. The dimension is chosen from its
 *  group (classification, academic, students, payment); each value is a row with its share drawn beside it and the
 *  total beneath; a value narrows the filters, its transactions are a click away, and the view chosen exports on its own. */
import { useState } from "react";
import { Btn, LinkBtn, Panel, PBody, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { vzNum } from "@/components/proto/vz";
import { naira, type FinFigures, type FinFilters } from "@/lib/analytics";

export type BreakRow = FinFigures & { key: string; label: string; sub?: string; next: Partial<FinFilters> };

export interface BreakView {
  id: string;
  group: string;
  /** the tab's word and the dimension column's heading */
  label: string;
  /** the export's title word, when it differs from the tab's */
  what?: string;
  /** one value and many, for the line above the table */
  noun: [string, string];
  rows: BreakRow[];
}

/** a share to one decimal, a sliver shown as under 0.1% rather than nothing */
export function shareWord(part: number | string, whole: number | string): string {
  const w = Number(whole);
  if (!w) return "—";
  const s = (100 * Number(part)) / w;
  return s > 0 && s < 0.05 ? "<0.1%" : `${s.toFixed(1)}%`;
}

export function RevenueBreakdown({ views, totals, canOpen, txHref, go, busy, onExport }: {
  views: BreakView[];
  totals: FinFigures;
  canOpen: boolean;
  txHref: (next?: Partial<FinFilters>) => string;
  go: (next: Partial<FinFilters>) => void;
  busy: boolean;
  onExport: (kind: "xlsx" | "pdf", what: string, rows: BreakRow[]) => void;
}) {
  const [by, setBy] = useState(views[0]?.id ?? "");
  const view = views.find((v) => v.id === by) ?? views[0];
  if (!view) return null;
  const groups = [...new Set(views.map((v) => v.group))];
  const inGroup = views.filter((v) => v.group === view.group);
  const whole = Number(totals.amount);
  const xs = view.rows;
  const top = xs.reduce<BreakRow | null>((a, r) => (!a || Number(r.amount) > Number(a.amount) ? r : a), null);
  const what = view.what ?? view.label;

  const rows = xs.map((r, i) => [
    <span key="sn" className="tnum sub2">{i + 1}</span>,
    <button key="l" type="button" className="lnk b600 rbk__lbl" onClick={() => go(r.next)} title={`Narrow the report to ${r.label}`}>
      {r.label}{r.sub ? <div className="sub2">{r.sub}</div> : null}
    </button>,
    <span key="t" className="tnum">{vzNum(r.transactions)}</span>,
    <span key="p" className="tnum">{vzNum(r.payers)}</span>,
    <span key="a" className="tnum b600">{naira(r.amount)}</span>,
    <Share key="s" part={r.amount} whole={whole} />,
    canOpen ? <LinkBtn key="x" href={txHref(r.next)} size="sm" kind="ghost">Transactions</LinkBtn> : <span key="x" />,
  ]);
  // the total beneath: payers counted once however many rows a payer falls in
  const foot = [
    null,
    <span key="l">Total</span>,
    <span key="t" className="tnum">{vzNum(totals.transactions)}</span>,
    <span key="p" className="tnum">{vzNum(totals.payers)}</span>,
    <span key="a" className="tnum">{naira(totals.amount)}</span>,
    <span key="s" className="tnum">{whole ? "100.0%" : "—"}</span>,
    canOpen ? <LinkBtn key="x" href={txHref()} size="sm" kind="ghost">All transactions</LinkBtn> : <span key="x" />,
  ];

  return (
    <Panel title="Revenue breakdown" right={xs.length ? (
      <span className="row row--inline row--tight">
        <Btn kind="ghost" size="sm" disabled={busy} onClick={() => onExport("xlsx", what, xs)}>Excel</Btn>
        <Btn kind="ghost" size="sm" disabled={busy} onClick={() => onExport("pdf", what, xs)}>PDF</Btn>
      </span>
    ) : null}>
      <PBody className="rbk__nav">
        <div className="rbk__tabs">
          {groups.length > 1 ? (
            <Tabs label="Breakdown group" items={groups.map((g) => ({ id: g, label: g }))} value={view.group}
              onChange={(g) => setBy(views.find((v) => v.group === g)?.id ?? by)} />
          ) : null}
          <Tabs look="line" label="Break down by" items={inGroup.map((v) => ({ id: v.id, label: v.label, count: v.rows.length }))} value={view.id} onChange={setBy} />
        </div>
        {/* on a phone the two strips are one list */}
        <div className="rbk__pick">
          <Field id="rbk-by" label="Break down by">
            <select id="rbk-by" className="ctl" value={view.id} onChange={(e) => setBy(e.target.value)}>
              {groups.map((g) => (
                <optgroup key={g} label={g}>
                  {views.filter((v) => v.group === g).map((v) => <option key={v.id} value={v.id}>{v.label} ({v.rows.length})</option>)}
                </optgroup>
              ))}
            </select>
          </Field>
        </div>
        <div className="rbk__sum">
          Revenue by {what.toLowerCase()} · {vzNum(xs.length)} {xs.length === 1 ? view.noun[0] : view.noun[1]}
          {top && xs.length > 1 ? <> · largest: <b>{top.label}</b>, {naira(top.amount)} ({shareWord(top.amount, whole)})</> : null}
          {xs.length > 1 ? <span className="rbk__hint"> · choose a {view.noun[0]} to narrow the report</span> : null}
        </div>
      </PBody>
      {xs.length ? (
        <div className="rbk">
          <DTable pageSize={0} title={`Revenue by ${what.toLowerCase()}`}
            cols={["S/N|num", view.label, "Transactions|num", "Unique payers|num", "Amount|num", "Share of revenue|num", "|num"]}
            rows={rows} foot={foot} texts={xs.map((r) => `${r.label} ${r.sub ?? ""}`)} />
        </div>
      ) : <PBody><div className="sub2">No payment records match the selected filters.</div></PBody>}
    </Panel>
  );
}

/** a row's share of the revenue, drawn and stated */
function Share({ part, whole }: { part: number | string; whole: number }) {
  const s = whole ? Math.min(100, Math.max(0, (100 * Number(part)) / whole)) : 0;
  return (
    <span className="rbk__share">
      <span className="rbk__bar" aria-hidden="true"><span style={{ width: `${s > 0 && s < 0.6 ? 0.6 : s}%` }} /></span>
      <span className="tnum">{shareWord(part, whole)}</span>
    </span>
  );
}
