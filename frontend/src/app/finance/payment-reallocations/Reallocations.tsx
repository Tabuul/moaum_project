"use client";

/**
 * Bursary payment reallocation and correction (V649): the corrections by status (each figure a door), the filters (status, session,
 * purpose, dates, a search by correction, payment reference, receipt, matriculation number, name or officer), the list, newest
 * first, and the same selection as a branded workbook or PDF (S/N first); a correction opens with the payment, both obligations,
 * the timeline and the officer's choices; NEW CORRECTION for the Students Account Officer and the Bursar. Every row and figure is
 * the server's.
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
import {
  REALLOC_HEAD, REALLOC_STATUSES, STATUS_WORDS, periodWords, reallocLine, reallocQuery,
  type Destination, type ReallocDetail, type ReallocFilters, type ReallocList, type ReallocStatus,
} from "@/lib/payment-reallocations";
import { NewReallocation } from "./NewReallocation";
import { ReallocationView } from "./ReallocationView";
import { reallocGet } from "./realloc-call";

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

const DOOR_SUB: Record<ReallocStatus, string> = {
  PENDING_APPROVAL: "Waiting for a Bursar officer",
  RETURNED: "Sent back to be changed",
  COMPLETED: "Payment reallocated",
  REJECTED: "Decided against",
  CANCELLED: "Withdrawn before a decision",
  FAILED: "Checked again and refused; nothing changed",
  REVERSED: "Taken back by a reversal",
};

export function Reallocations({ filters, list, destinations, office, initial }: {
  filters: ReallocFilters; list: ReallocList; destinations: Destination[]; office: string | null; initial: ReallocDetail | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const f = filters;
  const [q, setQ] = useState(f.q);
  const [making, setMaking] = useState(false);
  const [open, setOpen] = useState<ReallocDetail | null>(initial);
  const [err, setErr] = useState<Problem | null>(null);
  const mayInitiate = office === "bursar" || office === "studentaccounts";
  const count = (s: ReallocStatus) => Number(list.counts.find((c) => c.status === s)?.n ?? 0);
  const go = (next: ReallocFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/finance/payment-reallocations?${reallocQuery(next, extra)}`);

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
    const r = await reallocGet<ReallocDetail>(`/${id}`);
    if (!r.ok) { setErr(r.problem); notifyProblem(r.problem); return; }
    setOpen(r.data);
  }

  async function download(format: "XLSX" | "PDF") {
    const r = await reallocGet<ReallocList>(`?${reallocQuery(f, { all: true })}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    const when = (iso: string | null | undefined) => (iso ? formatDocDateTime(iso) : "");
    const rows = r.data.rows.map((x) => reallocLine(x, when));
    const title = "Payment reallocations and corrections";
    const meta: [string, string][] = [
      ["Status", f.status ? STATUS_WORDS[f.status as ReallocStatus]?.[1] ?? f.status : "All"],
      ["Session", f.session || "All"],
      ["Purpose", f.purpose ? destinations.find((d) => d.code === f.purpose)?.label ?? f.purpose : "All"],
      ["Initiated", f.from || f.to ? `${f.from || "…"} to ${f.to || "…"}` : "Any date"],
      ["Search", f.q || "—"],
      ["Corrections", String(rows.length)],
    ];
    const serial = docSerial("REA");
    if (format === "XLSX") {
      const blob = await brandedXlsx(title, REALLOC_HEAD, rows, { sheetName: "Payment reallocations", serial, meta });
      downloadBlob(blob, `payment-reallocations-${new Date().toISOString().slice(0, 10)}.xlsx`);
    } else {
      brandedPrint(title, "Verified payments moved from the purpose, session or semester they were applied to onto the one they were meant for", REALLOC_HEAD, rows, serial, { meta, orientation: "landscape" });
    }
    notify(`${rows.length} correction${rows.length === 1 ? "" : "s"} exported`);
  }

  const pages = Math.max(1, Math.ceil(list.total / list.size));

  return (
    <>
      <Note kind="info" title="A correction moves a verified payment to the purpose, session or semester it was meant for">
        The payment&apos;s reference, amount, date, receipt and gateway record never change, and nothing is paid twice: the ledger moves the income between accounts with no new cash.
        The destination&apos;s fee, what is already paid towards it and the balance are the finance engine&apos;s; a balance is paid through the student&apos;s normal payment page.
        A Bursar officer other than the one who initiated the correction approves it, and it is executed at once — or nothing changes.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}

      <div className="grid grid--3">
        {REALLOC_STATUSES.map((s) => (
          <Door key={s} label={STATUS_WORDS[s][1]} n={count(s)} sub={DOOR_SUB[s]} on={f.status === s} onClick={() => go({ ...f, status: f.status === s ? "" : s })} />
        ))}
      </div>

      <Panel title="Payment reallocations" right={`${list.total.toLocaleString("en-GB")} found`}>
        <PBody>
          <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
            <Field id="ra-q" label="Search" hint="Correction, payment reference, receipt, matriculation number, name or officer">
              <input id="ra-q" className="ctl" value={q} autoComplete="off" onChange={(e) => setQ(e.target.value)} />
            </Field>
            <Field id="ra-st" label="Status">
              <select id="ra-st" className="ctl" value={f.status} onChange={(e) => go({ ...f, status: e.target.value })}>
                <option value="">All</option>
                {REALLOC_STATUSES.map((s) => <option key={s} value={s}>{STATUS_WORDS[s][1]}</option>)}
              </select>
            </Field>
            <Field id="ra-pu" label="Purpose" hint="Original or new">
              <select id="ra-pu" className="ctl" value={f.purpose} onChange={(e) => go({ ...f, purpose: e.target.value })}>
                <option value="">All</option>
                {destinations.map((d) => <option key={d.code} value={d.code}>{d.label}</option>)}
              </select>
            </Field>
            <Field id="ra-ses" label="Session" hint="e.g. 2025/2026">
              <input id="ra-ses" className="ctl tnum" defaultValue={f.session} autoComplete="off" onBlur={(e) => { const v = e.target.value.trim(); if (v !== f.session && (v === "" || /^\d{4}\/\d{4}$/.test(v))) go({ ...f, session: v }); }} />
            </Field>
            <Field id="ra-from" label="Initiated from"><input id="ra-from" type="date" className="ctl" value={f.from} onChange={(e) => go({ ...f, from: e.target.value })} /></Field>
            <Field id="ra-to" label="to"><input id="ra-to" type="date" className="ctl" value={f.to} onChange={(e) => go({ ...f, to: e.target.value })} /></Field>
            <span className="grow" />
            <Btn kind="ghost" busyLabel="Preparing..." onClick={() => download("XLSX")}>Download Excel</Btn>
            <Btn kind="ghost" busyLabel="Preparing..." onClick={() => download("PDF")}>Download PDF</Btn>
            {mayInitiate ? <Btn kind="primary" onClick={() => setMaking(true)}>New correction</Btn> : null}
          </div>
        </PBody>
        {list.rows.length ? (
          <DTable cols={["Correction", "Payment", "Amount|num", "From", "To", "Balance|num", "Status", "Initiated", "|num"]} rows={list.rows.map((r) => [
            <span key="s" className="tnum">{r.realloc_ref}{r.kind === "REVERSAL" ? <div className="sub2">Reversal</div> : null}</span>,
            <span key="p"><span className="tnum">{r.reference}</span><div className="sub2">{r.matric_no ?? ""} {r.name}{r.legacy ? " · old portal" : ""}</div></span>,
            <b key="a" className="tnum">{money(Number(r.amount))}</b>,
            <span key="f">{r.from_purpose}<div className="sub2">{periodWords(r.from_session, r.from_semester, r.from_level)}</div></span>,
            <span key="t">{r.to_purpose}<div className="sub2">{periodWords(r.to_session, r.to_semester, r.to_level)}</div></span>,
            <span key="b" className="tnum">{r.balance_after == null ? "—" : money(Number(r.balance_after))}{r.surplus && Number(r.surplus) > 0 ? <div className="sub2">surplus {money(Number(r.surplus))}</div> : null}</span>,
            <span key="st"><Pil kind={STATUS_WORDS[r.status]?.[0] ?? "grey"}>{STATUS_WORDS[r.status]?.[1] ?? r.status}</Pil>{r.flags && r.flags !== "{}" ? <div className="sub2">To follow up</div> : null}</span>,
            <span key="i" className="sub2">{formatDocDateTime(r.initiated_at)}<div>{r.initiated_by_me ? "by you" : r.initiated_by ?? ""}</div></span>,
            <Btn key="o" kind="secondary" busyLabel="Opening..." onClick={() => show(r.id)}>Open</Btn>,
          ])} texts={list.rows.map((r) => `${r.realloc_ref} ${r.reference} ${r.matric_no ?? ""} ${r.name} ${r.from_purpose} ${r.to_purpose}`)} />
        ) : <PBody><div className="sub2">No payment correction matches.</div></PBody>}
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

      {making ? <NewReallocation destinations={destinations} onClose={() => setMaking(false)}
        onDone={(d) => { setMaking(false); setOpen(d); notify(`${d.reallocation.realloc_ref} sent for approval`); router.refresh(); }} /> : null}
      {open ? <ReallocationView detail={open} office={office} destinations={destinations} onClose={() => setOpen(null)}
        onChanged={(d) => { if (d) setOpen(d); router.refresh(); }} /> : null}
    </>
  );
}
