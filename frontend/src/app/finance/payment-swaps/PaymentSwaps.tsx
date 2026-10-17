"use client";

/**
 * School fees payment swaps (V527): the swaps by status (each figure a door), the filters (status, session, dates, a search by
 * swap, payment reference, receipt, matriculation number or name), the list, newest first, and the same selection as a branded
 * workbook or PDF; a swap opens with its accounts, timeline and the officer's choices; NEW PAYMENT SWAP for the Students
 * Account Officer and the Bursar. Every row and figure is the server's.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { formatDocDateTime } from "@/lib/document/institution";
import type { Problem } from "@/lib/api";
import { STATUS_WORDS, SWAP_HEAD, SWAP_STATUSES, swapLine, swapQuery, type SwapDetail, type SwapFilters, type SwapList, type SwapStatus } from "@/lib/payment-swaps";
import { NewSwap } from "./NewSwap";
import { SwapView } from "./SwapView";
import { swapGet } from "./swap-call";

function Door({ label, n, sub, on, onClick }: { label: string; n: number; sub: string; on: boolean; onClick: () => void }) {
  return (
    <button type="button" className="tile stat-tile" onClick={onClick} aria-pressed={on}
      style={{ textAlign: "left", font: "inherit", border: on ? "2px solid var(--chrome)" : undefined }}>
      <div className="eyebrow">{label}</div>
      <div className="n tnum">{n.toLocaleString("en-GB")}</div>
      <div className="c">{sub}</div>
    </button>
  );
}

const DOOR_SUB: Record<SwapStatus, string> = {
  PENDING_APPROVAL: "Waiting for a Bursar officer",
  COMPLETED: "Payment moved",
  REJECTED: "Decided against",
  CANCELLED: "Withdrawn before a decision",
  FAILED: "Checked again and refused; nothing changed",
  REVERSED: "Taken back by a reversal",
};

export function PaymentSwaps({ filters, list, office, initial }: { filters: SwapFilters; list: SwapList; office: string | null; initial: SwapDetail | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const f = filters;
  const [q, setQ] = useState(f.q);
  const [making, setMaking] = useState(false);
  const [open, setOpen] = useState<SwapDetail | null>(initial);
  const [err, setErr] = useState<Problem | null>(null);
  const mayInitiate = office === "bursar" || office === "studentaccounts";
  const count = (s: SwapStatus) => Number(list.counts.find((c) => c.status === s)?.n ?? 0);
  const go = (next: SwapFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/finance/payment-swaps?${swapQuery(next, extra)}`);

  // the search runs on the server as one types, a moment after the last key
  useEffect(() => {
    const t = q.trim();
    if (t === f.q) return;
    const timer = setTimeout(() => go({ ...f, q: t }), 450);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  async function show(id: string) {
    setErr(null);
    const r = await swapGet<SwapDetail>(`/${id}`);
    if (!r.ok) { setErr(r.problem); notifyProblem(r.problem); return; }
    setOpen(r.data);
  }

  async function download(format: "XLSX" | "PDF") {
    const r = await swapGet<SwapList>(`?${swapQuery(f, { all: true })}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    const when = (iso: string | null | undefined) => (iso ? formatDocDateTime(iso) : "");
    const rows = r.data.rows.map((x) => swapLine(x, when));
    const title = "School fees payment swaps";
    const meta: [string, string][] = [
      ["Status", f.status ? STATUS_WORDS[f.status as SwapStatus]?.[1] ?? f.status : "All"],
      ["Session", f.session || "All"],
      ["Initiated", f.from || f.to ? `${f.from || "…"} to ${f.to || "…"}` : "Any date"],
      ["Search", f.q || "—"],
      ["Swaps", String(rows.length)],
    ];
    const serial = docSerial("SWAP");
    if (format === "XLSX") {
      const blob = await brandedXlsx(title, SWAP_HEAD, rows, { sheetName: "Payment swaps", serial, meta });
      downloadBlob(blob, `payment-swaps-${new Date().toISOString().slice(0, 10)}.xlsx`);
    } else {
      brandedPrint(title, "Misallocated school fees payments reallocated to the students they belong to", SWAP_HEAD, rows, serial, { meta, orientation: "landscape" });
    }
    notify(`${rows.length} swap${rows.length === 1 ? "" : "s"} exported`);
  }

  const pages = Math.max(1, Math.ceil(list.total / list.size));

  return (
    <>
      <Note kind="info" title="A payment swap moves a verified school-fees payment to the student it belongs to">
        The whole payment moves; its reference, amount, date, receipt and gateway record never change, and it is never deleted or paid twice.
        A Bursar officer other than the one who initiated the swap approves it, and it is executed at once with both accounts reconciled — or nothing changes.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}

      <div className="grid grid--3">
        {SWAP_STATUSES.map((s) => (
          <Door key={s} label={STATUS_WORDS[s][1]} n={count(s)} sub={DOOR_SUB[s]} on={f.status === s} onClick={() => go({ ...f, status: f.status === s ? "" : s })} />
        ))}
      </div>

      <Panel title="Payment swaps" right={`${list.total.toLocaleString("en-GB")} found`}>
        <PBody>
          <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
            <Field id="sw-q" label="Search" hint="Swap, payment reference, receipt, matriculation number or name">
              <input id="sw-q" className="ctl" value={q} autoComplete="off" onChange={(e) => setQ(e.target.value)} />
            </Field>
            <Field id="sw-st" label="Status">
              <select id="sw-st" className="ctl" value={f.status} onChange={(e) => go({ ...f, status: e.target.value })}>
                <option value="">All</option>
                {SWAP_STATUSES.map((s) => <option key={s} value={s}>{STATUS_WORDS[s][1]}</option>)}
              </select>
            </Field>
            <Field id="sw-ses" label="Session" hint="e.g. 2025/2026">
              <input id="sw-ses" className="ctl tnum" defaultValue={f.session} autoComplete="off" onBlur={(e) => { const v = e.target.value.trim(); if (v !== f.session && (v === "" || /^\d{4}\/\d{4}$/.test(v))) go({ ...f, session: v }); }} />
            </Field>
            <Field id="sw-from" label="Initiated from"><input id="sw-from" type="date" className="ctl" value={f.from} onChange={(e) => go({ ...f, from: e.target.value })} /></Field>
            <Field id="sw-to" label="to"><input id="sw-to" type="date" className="ctl" value={f.to} onChange={(e) => go({ ...f, to: e.target.value })} /></Field>
            <span className="grow" />
            <Btn kind="ghost" busyLabel="Preparing..." onClick={() => download("XLSX")}>Download Excel</Btn>
            <Btn kind="ghost" busyLabel="Preparing..." onClick={() => download("PDF")}>Download PDF</Btn>
            {mayInitiate ? <Btn kind="primary" onClick={() => setMaking(true)}>New payment swap</Btn> : null}
          </div>
        </PBody>
        {list.rows.length ? (
          <DTable cols={["Swap", "Payment", "Amount|num", "From (credited)", "To (belongs to)", "Status", "Initiated", "|num"]} rows={list.rows.map((r) => [
            <span key="s" className="tnum">{r.swap_ref}{r.kind === "REVERSAL" ? <div className="sub2">Reversal</div> : null}</span>,
            <span key="p"><span className="tnum">{r.reference}</span><div className="sub2">{r.session}{r.legacy ? " · old portal" : ""}</div></span>,
            <b key="a" className="tnum">{money(Number(r.amount))}</b>,
            <span key="f"><span className="tnum">{r.from_matric ?? ""}</span><div className="sub2">{r.from_name}</div></span>,
            <span key="t"><span className="tnum">{r.to_matric ?? ""}</span><div className="sub2">{r.to_name}</div></span>,
            <span key="st"><Pil kind={STATUS_WORDS[r.status]?.[0] ?? "grey"}>{STATUS_WORDS[r.status]?.[1] ?? r.status}</Pil>{r.flags && r.flags !== "{}" ? <div className="sub2">To follow up</div> : null}</span>,
            <span key="i" className="sub2">{formatDocDateTime(r.initiated_at)}<div>{r.initiated_by_me ? "by you" : r.initiated_by ?? ""}</div></span>,
            <Btn key="o" kind="secondary" busyLabel="Opening..." onClick={() => show(r.id)}>Open</Btn>,
          ])} texts={list.rows.map((r) => `${r.swap_ref} ${r.reference} ${r.from_matric ?? ""} ${r.to_matric ?? ""} ${r.from_name} ${r.to_name}`)} />
        ) : <PBody><div className="sub2">No payment swap matches.</div></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row" style={{ gap: 8 }}>
              <Btn kind="ghost" disabled={list.page <= 0} onClick={() => go(f, { page: list.page - 1 })}>Previous</Btn>
              <span className="sub2">Page {list.page + 1} of {pages}</span>
              <Btn kind="ghost" disabled={list.page + 1 >= pages} onClick={() => go(f, { page: list.page + 1 })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {making ? <NewSwap onClose={() => setMaking(false)} onDone={(d) => { setMaking(false); setOpen(d); notify(`${d.swap.swap_ref} sent for approval`); router.refresh(); }} /> : null}
      {open ? <SwapView detail={open} office={office} onClose={() => setOpen(null)} onChanged={(d) => { if (d) setOpen(d); router.refresh(); }} /> : null}
    </>
  );
}
