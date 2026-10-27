"use client";

/**
 * Payments archived for review (V670): verified active revenue against what is archived (the archived money is never income), the
 * archive by what it holds (each figure a door to its payments), the filters (status, reason, session, semester, purpose, channel,
 * source, dates, amount, and a search by archive or payment reference, old-portal number, gateway or transaction reference,
 * matriculation, JAMB or application number, migration batch or name — on the server), the list, newest first, and the same
 * selection as a branded workbook or PDF (S/N first); a payment opens with its original record, the archive, the verification
 * status, the evidence, the proposal and the decision; ARCHIVE A PAYMENT and the possible duplicates for the Students Account
 * Officer and the Bursar. Every row and figure is the server's.
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
  ARCHIVE_HEAD, ARCHIVE_STATES, CATEGORIES, OUTCOME_WORDS, SOURCE_WORDS, STATE_WORDS, archiveLine, archiveQuery, verificationWords,
  type ArchiveDetail, type ArchiveFilters, type ArchiveList, type ArchiveSource, type ArchiveState, type Catalogue, type Figures,
} from "@/lib/payment-archive";
import { ArchiveView } from "./ArchiveView";
import { NewArchive } from "./NewArchive";
import { Suspects } from "./Suspects";
import { archiveGet } from "./archive-call";

function Door({ label, n, amount, sub, on, onClick }: { label: string; n: number; amount: number; sub: string; on: boolean; onClick: () => void }) {
  return (
    <button type="button" className="tile stat-tile" onClick={onClick} aria-pressed={on}
      style={{ textAlign: "left", font: "inherit", border: on ? "2px solid var(--chrome)" : undefined }}>
      <div className="eyebrow">{label}</div>
      <div className="n tnum">{n.toLocaleString("en-GB")}</div>
      <div className="c tnum">{money(amount)}</div>
      <div className="c">{sub}</div>
    </button>
  );
}

export function PaymentArchive({ filters, list, catalogue, figures, office, initial }: {
  filters: ArchiveFilters; list: ArchiveList; catalogue: Catalogue; figures: Figures | null; office: string | null; initial: ArchiveDetail | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const f = filters;
  const [q, setQ] = useState(f.q);
  const [making, setMaking] = useState<{ payment?: string; related?: string; reason?: string } | null>(null);
  const [suspects, setSuspects] = useState(false);
  const [open, setOpen] = useState<ArchiveDetail | null>(initial);
  const [err, setErr] = useState<Problem | null>(null);
  const mayArchive = office === "bursar" || office === "studentaccounts";
  const go = (next: ArchiveFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/finance/payment-archive?${archiveQuery(next, extra)}`);
  const door = (state: string, reason = "") => go({ ...f, state: f.state === state && f.reason === reason ? "" : state, reason: f.state === state && f.reason === reason ? "" : reason });

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
    const r = await archiveGet<ArchiveDetail>(`/${id}`);
    if (!r.ok) { setErr(r.problem); notifyProblem(r.problem); return; }
    setOpen(r.data);
  }

  async function download(format: "XLSX" | "PDF") {
    const r = await archiveGet<ArchiveList>(`?${archiveQuery(f, { all: true })}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    const when = (iso: string | null | undefined) => (iso ? formatDocDateTime(iso) : "");
    const rows = r.data.rows.map((x) => archiveLine(x, when));
    const title = "Archived payments";
    const total = r.data.rows.reduce((s, x) => s + Number(x.amount), 0);
    const meta: [string, string][] = [
      ["Status", f.state === "OPEN" ? "Open (not yet settled)" : f.state ? STATE_WORDS[f.state as ArchiveState]?.[1] ?? f.state : "All"],
      ["Reason", f.reason ? catalogue.reasons.find((x) => x.code === f.reason)?.label ?? f.reason : "All"],
      ["Session", f.session || "All"],
      ["Purpose", f.category || "All"],
      ["Archived", f.from || f.to ? `${f.from || "…"} to ${f.to || "…"}` : "Any date"],
      ["Search", f.q || "—"],
      ["Payments", String(rows.length)],
      ["Amount", money(total)],
      ["Note", "Archived payments are kept for the audit and are never counted as income or towards a student's fees until the Bursary settles them."],
    ];
    const serial = docSerial("PAR");
    if (format === "XLSX") {
      const blob = await brandedXlsx(title, ARCHIVE_HEAD, rows, { sheetName: "Archived payments", serial, meta });
      downloadBlob(blob, `archived-payments-${new Date().toISOString().slice(0, 10)}.xlsx`);
    } else {
      brandedPrint(title, "Payments archived for review — kept for the audit, excluded from verified active revenue and from every student's paid figures",
        ARCHIVE_HEAD, rows, serial, { meta, orientation: "landscape" });
    }
    notify(`${rows.length} archived payment${rows.length === 1 ? "" : "s"} exported`);
  }

  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const fg = figures;

  return (
    <>
      <Note kind="info" title="An archived payment is never deleted — and never income until it is settled">
        Archiving keeps the payment exactly as it was received (reference, amount, date, gateway record) and takes it out of income, of the student&apos;s
        paid figures and of every entitlement. It counts again only when a Bursar officer, other than the officer who proposed it, approves it restored to the
        student it stands on or reallocated to its true owner; a duplicate or a payment never received stays archived for good.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}

      {fg ? (
        <div className="grid grid--3">
          <div className="tile stat-tile"><div className="eyebrow">Verified active revenue{fg.session ? ` · ${fg.session}` : ""}</div>
            <div className="n tnum">{money(Number(fg.activeAmount))}</div><div className="c">{Number(fg.activeCount).toLocaleString("en-GB")} student payments that count</div></div>
          <div className="tile stat-tile"><div className="eyebrow">Archived / under review</div>
            <div className="n tnum">{money(Number(fg.archivedAmount))}</div><div className="c">{Number(fg.archivedCount).toLocaleString("en-GB")} payments kept apart — not income</div></div>
          <div className="tile stat-tile"><div className="eyebrow">Student payments recorded</div>
            <div className="n tnum">{money(Number(fg.recordedAmount))}</div><div className="c">{Number(fg.recordedCount).toLocaleString("en-GB")} confirmed transactions in all</div></div>
        </div>
      ) : null}

      {fg ? (
        <div className="grid grid--4">
          <Door label="Open, pending recognition" n={fg.open} amount={Number(fg.openAmount)} sub="Archived, under review or waiting" on={f.state === "OPEN" && !f.reason} onClick={() => door("OPEN")} />
          <Door label="Duplicate payments" n={fg.duplicates} amount={Number(fg.duplicateAmount)} sub="Archived as, or confirmed, duplicates" on={f.reason === "DUPLICATE_PAYMENT"} onClick={() => go({ ...f, state: "", reason: f.reason === "DUPLICATE_PAYMENT" ? "" : "DUPLICATE_PAYMENT" })} />
          <Door label="Wrong student" n={fg.wrongStudent} amount={Number(fg.wrongStudentAmount)} sub="On a student who did not make it" on={f.reason === "WRONG_STUDENT"} onClick={() => go({ ...f, state: "", reason: f.reason === "WRONG_STUDENT" ? "" : "WRONG_STUDENT" })} />
          <Door label="Ownership pending" n={fg.ownershipPending} amount={Number(fg.ownershipPendingAmount)} sub="Owner not yet established" on={f.state === "UNDER_REVIEW"} onClick={() => door("UNDER_REVIEW")} />
          <Door label="Awaiting Bursar approval" n={fg.awaitingBursar} amount={Number(fg.awaitingBursarAmount)} sub="Verified — ready for reconciliation" on={f.state === "PENDING_BURSAR_APPROVAL"} onClick={() => door("PENDING_BURSAR_APPROVAL")} />
          <Door label="Reconciled" n={fg.reconciled} amount={Number(fg.reconciledAmount)} sub={`${fg.reallocated} reallocated to their owner`} on={f.state === "RECONCILED"} onClick={() => door("RECONCILED")} />
          <Door label="Never received" n={fg.notReceived} amount={Number(fg.notReceivedAmount)} sub="Excluded for good" on={f.state === "NOT_RECEIVED"} onClick={() => door("NOT_RECEIVED")} />
          <Door label="Unresolved" n={fg.unresolved} amount={Number(fg.unresolvedAmount)} sub="No settlement proposed yet" on={f.state === "ARCHIVED"} onClick={() => door("ARCHIVED")} />
        </div>
      ) : null}

      <Panel title="Archived payments" right={`${list.total.toLocaleString("en-GB")} found`}>
        <PBody>
          <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
            <Field id="par-q" label="Search" hint="Archive or payment reference, old-portal number, gateway or transaction reference, matriculation, JAMB or application number, batch, name">
              <input id="par-q" className="ctl" value={q} autoComplete="off" onChange={(e) => setQ(e.target.value)} />
            </Field>
            <Field id="par-st" label="Status">
              <select id="par-st" className="ctl" value={f.state} onChange={(e) => go({ ...f, state: e.target.value })}>
                <option value="">All</option>
                <option value="OPEN">Open (not yet settled)</option>
                {ARCHIVE_STATES.map((s) => <option key={s} value={s}>{STATE_WORDS[s][1]}</option>)}
              </select>
            </Field>
            <Field id="par-rc" label="Reason">
              <select id="par-rc" className="ctl" value={f.reason} onChange={(e) => go({ ...f, reason: e.target.value })}>
                <option value="">All</option>
                {catalogue.reasons.map((r) => <option key={r.code} value={r.code}>{r.label}</option>)}
              </select>
            </Field>
            <Field id="par-ses" label="Session">
              <select id="par-ses" className="ctl" value={f.session} onChange={(e) => go({ ...f, session: e.target.value })}>
                <option value="">All</option>
                {catalogue.sessions.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field id="par-sem" label="Semester">
              <select id="par-sem" className="ctl" value={f.semester} onChange={(e) => go({ ...f, semester: e.target.value })}>
                <option value="">All</option><option value="1">First</option><option value="2">Second</option>
              </select>
            </Field>
            <Field id="par-cat" label="Purpose">
              <select id="par-cat" className="ctl" value={f.category} onChange={(e) => go({ ...f, category: e.target.value })}>
                <option value="">All</option>
                {CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </Field>
            <Field id="par-ch" label="Channel">
              <select id="par-ch" className="ctl" value={f.channel} onChange={(e) => go({ ...f, channel: e.target.value })}>
                <option value="">All</option>
                {catalogue.channels.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </Field>
            <Field id="par-src" label="Source">
              <select id="par-src" className="ctl" value={f.source} onChange={(e) => go({ ...f, source: e.target.value })}>
                <option value="">All</option>
                {(Object.keys(SOURCE_WORDS) as ArchiveSource[]).map((s) => <option key={s} value={s}>{SOURCE_WORDS[s]}</option>)}
              </select>
            </Field>
            <Field id="par-from" label="Archived from"><input id="par-from" type="date" className="ctl" value={f.from} onChange={(e) => go({ ...f, from: e.target.value })} /></Field>
            <Field id="par-to" label="to"><input id="par-to" type="date" className="ctl" value={f.to} onChange={(e) => go({ ...f, to: e.target.value })} /></Field>
            <Field id="par-pf" label="Paid from"><input id="par-pf" type="date" className="ctl" value={f.paidFrom} onChange={(e) => go({ ...f, paidFrom: e.target.value })} /></Field>
            <Field id="par-pt" label="to"><input id="par-pt" type="date" className="ctl" value={f.paidTo} onChange={(e) => go({ ...f, paidTo: e.target.value })} /></Field>
            <Field id="par-amt" label="Amount (₦)">
              <input id="par-amt" className="ctl tnum" defaultValue={f.amount} autoComplete="off" inputMode="decimal"
                onBlur={(e) => { const v = e.target.value.trim(); if (v !== f.amount && (v === "" || /^\d{1,12}(\.\d{1,2})?$/.test(v))) go({ ...f, amount: v }); }} />
            </Field>
            <span className="grow" />
            <Btn kind="ghost" busyLabel="Preparing..." onClick={() => download("XLSX")}>Download Excel</Btn>
            <Btn kind="ghost" busyLabel="Preparing..." onClick={() => download("PDF")}>Download PDF</Btn>
            <Btn kind="ghost" onClick={() => setSuspects(true)}>Possible duplicates</Btn>
            {mayArchive ? <Btn kind="primary" onClick={() => setMaking({})}>Archive a payment</Btn> : null}
          </div>
        </PBody>
        {list.rows.length ? (
          <DTable cols={["S/N|num", "Archive", "Payment", "Student", "Amount|num", "Reason", "Status", "Verification", "Archived", "|num"]} rows={list.rows.map((r, i) => {
            const [vk, vw] = verificationWords(r.state);
            return [
              <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
              <span key="a" className="tnum">{r.archive_ref}{r.source !== "DESK" ? <div className="sub2">{SOURCE_WORDS[r.source]}</div> : null}</span>,
              <span key="p"><span className="tnum">{r.reference}</span><div className="sub2">{r.purpose}{r.purpose.includes(r.session) ? "" : ` · ${r.session}`}{r.legacy_payref ? ` · old ${r.legacy_payref}` : ""}</div></span>,
              <span key="s">{r.name}<div className="sub2 tnum">{r.number ?? ""}{r.current_number && r.current_number !== r.number ? ` → now ${r.current_number}` : ""}</div></span>,
              <b key="m" className="tnum">{money(Number(r.amount))}</b>,
              <span key="r">{r.reason}{r.outcome ? <div className="sub2">{OUTCOME_WORDS[r.outcome]?.[0]}{r.owner_number ? ` · ${r.owner_number}` : ""}</div> : null}</span>,
              <Pil key="st" kind={STATE_WORDS[r.state]?.[0] ?? "grey"}>{STATE_WORDS[r.state]?.[1] ?? r.state}</Pil>,
              <span key="v" className="sub2"><Pil kind={vk}>{vw}</Pil></span>,
              <span key="w" className="sub2">{formatDocDateTime(r.archived_at)}<div>{r.archived_by ?? ""}</div></span>,
              <Btn key="o" kind="secondary" busyLabel="Opening..." onClick={() => show(r.id)}>Open</Btn>,
            ];
          })} texts={list.rows.map((r) => `${r.archive_ref} ${r.reference} ${r.number ?? ""} ${r.name} ${r.reason}`)} />
        ) : <PBody><div className="sub2">No archived payment matches.</div></PBody>}
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

      {suspects ? <Suspects session={f.session} mayArchive={mayArchive} onClose={() => setSuspects(false)}
        onArchive={(payment, related) => { setSuspects(false); setMaking({ payment, related, reason: "DUPLICATE_PAYMENT" }); }} /> : null}
      {making ? <NewArchive catalogue={catalogue} preset={making} onClose={() => setMaking(null)}
        onDone={(d) => { setMaking(null); setOpen(d); notify(`${d.archive.archive_ref}: payment archived for review`); router.refresh(); }} /> : null}
      {open ? <ArchiveView detail={open} office={office} catalogue={catalogue} onClose={() => setOpen(null)}
        onChanged={(d) => { if (d) setOpen(d); router.refresh(); }} /> : null}
    </>
  );
}
