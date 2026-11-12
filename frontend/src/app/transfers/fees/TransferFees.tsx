"use client";

/**
 * The inter-departmental transfer fee monitor (V727), cloned from the acceptance fee monitor. The figures first — the
 * applications, not paid, awaiting the bank, part paid, paid in full, paid above the fee, the old portal's payments waiting for an
 * application, ready for the final approval, the sums outstanding and collected — each a door that applies itself; the filters
 * (session, standing, what it waits for, faculty → department, a search); the list, each row a door to the student's record; and
 * DOWNLOAD — the same selection as a workbook, the download recorded by the server. Every row and figure is the server's
 * (people.transfer_fee_monitor): the fee due is the fee the Bursary states now, so a student who paid part of it here or on the old
 * portal reads the balance, never the fee again.
 */
import { useEffect, useMemo, useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { formatDocDateTime } from "@/lib/document/institution";
import { logExport } from "@/lib/export-log";
import {
  ALL_SESSIONS, AWAITINGS, BANDS, EMPTY_TRANSFER_FEES, TRANSFER_FEES_API, TRANSFER_FEE_HEAD, awaitingWord, bandKind, bandWord, naira, sessionWord, snakeKeys, stillOwing,
  summaryTotal, transferFeeFileName, transferFeeLine, transferFeeMeta, transferFeeQuery, withTransferFeeChange, type TransferFeeFilters, type TransferFeeOptions,
  type TransferFeePage, type TransferFeeRow, type TransferFeeSummary,
} from "@/lib/transfer-fees";

const vzNum = (n: number | string) => Number(n).toLocaleString("en-GB");
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : null);
/** the offices that read the old portal's transfer payments (GET /transfers/legacy) */
const RECONCILERS = ["academic", "registrar", "dregistrar", "bursar", "studentaccounts", "ict", "admin", "super"];

function Sel({ id, label, value, onChange, any, opts, hint }: {
  id: string; label: string; value: string; onChange: (v: string) => void; any?: string; opts: [string, string][]; hint?: string;
}) {
  return (
    <div className="scope__f"><Field id={id} label={label} hint={hint}>
      <select id={id} className="ctl" value={value} onChange={(e) => onChange(e.target.value)}>
        {any !== undefined ? <option value="">{any}</option> : null}
        {opts.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
    </Field></div>
  );
}

/** a figure that applies itself when chosen */
function Door({ label, n, sub, on, onClick, colour }: { label: string; n: string; sub: string; on: boolean; onClick?: () => void; colour?: string }) {
  return onClick ? (
    <button type="button" className="tile stat-tile" onClick={onClick} aria-pressed={on}
      style={{ textAlign: "left", font: "inherit", border: on ? "2px solid var(--chrome)" : undefined }}>
      <div className="eyebrow">{label}</div>
      <div className="n tnum" style={colour ? { color: colour } : undefined}>{n}</div>
      <div className="c">{sub}</div>
    </button>
  ) : (
    <div className="tile stat-tile">
      <div className="eyebrow">{label}</div>
      <div className="n tnum" style={colour ? { color: colour } : undefined}>{n}</div>
      <div className="c">{sub}</div>
    </div>
  );
}

export function TransferFees({ filters, summary, list, options, sessions, actingOffice }: {
  filters: TransferFeeFilters; summary: TransferFeeSummary; list: TransferFeePage; options: TransferFeeOptions; sessions: string[]; actingOffice: string | null;
}) {
  const rows = list.rows;
  const queryNav = useQueryNav();
  const f = filters;
  const [q, setQ] = useState(f.search);
  const [stage, setStage] = useState<string | null>(null);

  const go = (next: TransferFeeFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/transfers/fees?${transferFeeQuery(next, extra)}`);
  const set = (key: keyof TransferFeeFilters, value: string) => go(withTransferFeeChange(f, key, value));
  const toggle = (key: "band" | "awaiting", value: string) => set(key, f[key] === value ? "" : value);

  // the search runs on the server as one types, a moment after the last key
  useEffect(() => {
    const t = q.trim();
    if (t === f.search) return;
    const timer = setTimeout(() => go({ ...f, search: t }), 450);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  // the faculties and departments within the office's scope, as the server offers them
  const faculties = useMemo(() => [...options.faculties].sort((a, b) => a.name.localeCompare(b.name)), [options.faculties]);
  const depts = useMemo(() => options.departments.filter((d) => !f.faculty || d.faculty_code === f.faculty).map((d) => ({ ...d, faculty: d.faculty_code ?? "" }))
    .sort((a, b) => a.name.localeCompare(b.name)), [options.departments, f.faculty]);
  const pages = Math.max(1, Math.ceil(list.total / Math.max(1, list.size)));
  const labels = { faculty: faculties.find((x) => x.code === f.faculty)?.name, dept: depts.find((d) => d.code === f.dept)?.name };
  const bands = summary.bands ?? {};
  const waits = summary.awaiting ?? {};
  const total = summary.total ?? summaryTotal(summary);
  const credits = summary.awaitingApplication ?? bands.AWAITING_APPLICATION ?? 0;
  const applications = summary.applications ?? total - credits;
  // not paid, awaiting the bank or part paid: a closed application (band CLOSED: declined or not recommended) owes nothing and is
  // counted in neither the Not paid nor the Still owing figure
  const owing = stillOwing(summary);
  const closed = bands.CLOSED ?? 0;
  const unstated = summary.fee === null || summary.fee === undefined || (bands.FEE_NOT_STATED ?? 0) > 0;
  const mayReconcile = RECONCILERS.includes(actingOffice ?? "");
  type Chip = { key: keyof TransferFeeFilters; label: string; value: string };
  const applied = ([
    f.band ? { key: "band", label: "Standing", value: bandWord(f.band) } : null,
    f.awaiting ? { key: "awaiting", label: "Awaiting", value: awaitingWord(f.awaiting) } : null,
    f.faculty ? { key: "faculty", label: "Faculty", value: labels.faculty ?? f.faculty } : null,
    f.dept ? { key: "dept", label: "Department", value: labels.dept ?? f.dept } : null,
    f.search ? { key: "search", label: "Search", value: f.search } : null,
  ] as (Chip | null)[]).filter((x): x is Chip => !!x);
  const clear = () => { setQ(""); go({ ...EMPTY_TRANSFER_FEES, session: f.session }); };

  /** the selection as a workbook: the server's rows, the download recorded on its side (admissions.report_export) */
  async function download() {
    if (stage) return;
    setStage("PREPARING…");
    try {
      const r = await fetch(`/api/bff${TRANSFER_FEES_API}/export`, {
        method: "POST", cache: "no-store",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Transfer fee monitor downloaded (${f.session})`) },
        body: JSON.stringify({ format: "XLSX", ...f }),
      });
      if (!r.ok) { const j = await r.json().catch(() => null); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const title = `INTER-DEPARTMENTAL TRANSFER FEES${f.band ? ` — ${bandWord(f.band).toUpperCase()}` : ""}`;
      const sub = f.session === ALL_SESSIONS ? sessionWord(ALL_SESSIONS) : `${f.session} session`;
      if ((r.headers.get("content-type") ?? "").includes("json")) {
        // the rows, for the workbook built here (as the acceptance fee monitor builds its own)
        const j = await r.json();
        const got = ((Array.isArray(j) ? j : j?.rows ?? []) as Record<string, unknown>[]).map((x) => snakeKeys<TransferFeeRow>(x));
        setStage("GENERATING EXCEL…");
        const named = { faculty: j?.labels?.faculty ?? labels.faculty, dept: j?.labels?.department ?? labels.dept };
        const meta = transferFeeMeta(f, named, summary.fee, got.length, formatDocDateTime(new Date()));
        const blob = await brandedXlsx(title, TRANSFER_FEE_HEAD, got.map(transferFeeLine), { sheetName: "Transfer fees", serial: docSerial("TRF"), sub, meta });
        downloadBlob(blob, transferFeeFileName(f, "xlsx"));
        notify(`${vzNum(got.length)} row${got.length === 1 ? "" : "s"} downloaded as Excel`);
      } else {
        // a workbook the server built
        downloadBlob(await r.blob(), transferFeeFileName(f, "xlsx"));
        logExport({ report: title, format: "XLSX", rows: list.total, sub, meta: transferFeeMeta(f, labels, summary.fee, list.total, formatDocDateTime(new Date())) });
        notify("The transfer fees downloaded as Excel");
      }
    } catch {
      notifyProblem({ status: 0, title: "The download could not be prepared. Check the connection and try again." });
    } finally {
      setStage(null);
    }
  }

  const line = (r: TransferFeeRow, i: number) => [
    <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
    <span key="n"><strong>{r.name}</strong>
      <div className="sub2 tnum">{[r.matric_no, r.legacy_ref ? `old portal ${r.legacy_ref}` : null].filter(Boolean).join(" · ")}</div></span>,
    <span key="p">{r.application_id ? <><span className="sub2">{r.from_programme ?? "—"}</span><div><b>→ {r.to_programme ?? "—"}</b></div></>
      : <><span className="sub2">{r.from_programme ?? "—"}</span><div><Pil kind="info">No application yet</Pil></div></>}
      {r.session ? <div className="sub2 tnum">{r.session}{r.applied_at ? ` · applied ${when(r.applied_at)}` : ""}</div> : null}</span>,
    <span key="d" className="tnum">{naira(r.fee_due)}</span>,
    <span key="pd" className="tnum">{naira(r.paid_total)}
      <div className="sub2">{[Number(r.portal_paid ?? 0) > 0 ? `${naira(r.portal_paid)} here` : null, Number(r.old_portal_paid ?? 0) > 0 ? `${naira(r.old_portal_paid)} on the old portal` : null]
        .filter(Boolean).join(" · ") || "—"}{r.payments ? ` · ${r.payments} payment${r.payments === 1 ? "" : "s"}` : ""}</div></span>,
    <span key="b" className="tnum" style={Number(r.balance ?? 0) > 0 ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{naira(r.balance)}
      {Number(r.excess ?? 0) > 0 ? <div className="sub2 tnum" style={{ color: "var(--amber-ink)" }}>{naira(r.excess)} above the fee</div> : null}
      {r.pending ? <div className="sub2">A payment awaits the bank</div> : null}</span>,
    <Pil key="s" kind={bandKind(r.band)}>{bandWord(r.band)}</Pil>,
    <span key="a" className="sub2">{awaitingWord(r.awaiting)}</span>,
    <LinkBtn key="o" kind="ghost" href={`/students/${r.student_id}`}>Record</LinkBtn>,
  ];

  return (
    <>
      <PageHead title="Transfer fees"
        description={`${sessionWord(f.session)}${f.session === ALL_SESSIONS ? "" : " session"}. Every inter-departmental transfer application with the fee as the Bursary states it now${summary.fee != null ? ` — ${naira(summary.fee)}` : ""}${summary.previousFee != null && summary.revisedAt ? ` (revised from ${naira(summary.previousFee)} on ${when(summary.revisedAt)})` : ""}, what is paid on this portal and on the old one, and the balance. Any verified payment lets the current HOD act; the Academic Office's final approval waits for the whole fee, with nothing awaiting the bank.`}
        actions={<Btn kind="primary" disabled={!list.total} busy={!!stage} busyLabel={stage ?? undefined} onClick={() => download()}>DOWNLOAD TRANSFER FEES</Btn>} />

      {unstated ? (
        <Note kind="bad" title="The Bursary has not stated the transfer fee">
          No balance can be read and no transfer can be completed until the fee is stated on Fee setup.
        </Note>
      ) : null}

      {/* the figures, each a door */}
      <div className="grid grid--4" role="group" aria-label="Applications by transfer fee standing">
        <Door label="Applications" n={vzNum(applications)} sub={`${f.faculty || f.dept || f.search ? "Within the filters applied" : "Within your scope"}${closed ? ` · ${vzNum(closed)} closed, nothing owed` : ""}`}
          on={!f.band && !f.awaiting} onClick={() => go({ ...f, band: "", awaiting: "" })} />
        <Door label="Not paid" n={vzNum(bands.NOT_PAID ?? 0)} sub="Nothing verified: the current HOD waits for a payment" on={f.band === "NOT_PAID"} onClick={() => toggle("band", "NOT_PAID")} colour={bands.NOT_PAID ? "var(--red-ink)" : undefined} />
        <Door label="Awaiting the bank" n={vzNum(bands.PENDING ?? 0)} sub="A reference drawn, not yet confirmed" on={f.band === "PENDING"} onClick={() => toggle("band", "PENDING")} colour={bands.PENDING ? "var(--amber-ink)" : undefined} />
        <Door label="Part paid — balance owed" n={vzNum(bands.PART_PAID ?? 0)} sub="Moves through the desks; the final approval waits for the balance" on={f.band === "PART_PAID"} onClick={() => toggle("band", "PART_PAID")} colour={bands.PART_PAID ? "var(--amber-ink)" : undefined} />
        <Door label="Paid in full" n={vzNum(bands.PAID_IN_FULL ?? 0)} sub="The fee as stated, in one payment" on={f.band === "PAID_IN_FULL"} onClick={() => toggle("band", "PAID_IN_FULL")} colour="var(--green-ink)" />
        <Door label="Paid in full, in parts" n={vzNum(bands.SETTLED_IN_PARTS ?? 0)} sub="Here, on the old portal, or both" on={f.band === "SETTLED_IN_PARTS"} onClick={() => toggle("band", "SETTLED_IN_PARTS")} colour="var(--green-ink)" />
        <Door label="Paid above the fee" n={vzNum(bands.OVERPAID ?? 0)} sub={`${naira(summary.excess)} above the fee; no refund is made by the portal`} on={f.band === "OVERPAID"} onClick={() => toggle("band", "OVERPAID")} colour={bands.OVERPAID ? "var(--amber-ink)" : undefined} />
        <Door label="Paid on the old portal, no application" n={vzNum(credits)} sub="Counts toward the fee once the student applies" on={f.band === "AWAITING_APPLICATION"} onClick={() => toggle("band", "AWAITING_APPLICATION")} colour={credits ? "var(--chrome)" : undefined} />
        <Door label="Ready for the final approval" n={vzNum(summary.readyForFinalApproval ?? 0)} sub="With the Academic Office, the fee paid in full" on={f.awaiting === "ACADEMIC_OFFICE"} onClick={() => toggle("awaiting", "ACADEMIC_OFFICE")} colour={summary.readyForFinalApproval ? "var(--green-ink)" : undefined} />
        <Door label="Still owing" n={vzNum(owing)} sub={`Not paid, awaiting the bank or part paid · ${naira(summary.outstanding)} outstanding`} on={false} colour={Number(summary.outstanding) > 0 ? "var(--red-ink)" : undefined} />
        <Door label="Collected" n={naira(Number(summary.collectedPortal ?? 0) + Number(summary.collectedOldPortal ?? 0))} sub={`${naira(summary.collectedPortal)} on this portal · ${naira(summary.collectedOldPortal)} on the old portal`} on={false} />
        <Door label="Old-portal payments unmatched" n={vzNum(summary.unmatchedPayments ?? 0)} sub={mayReconcile ? "Decided on Old-portal transfers" : "Decided by the Academic Office, the Registry, the Bursary or ICT"} on={false}
          onClick={mayReconcile ? () => queryNav("/transfers/old-portal?status=UNMATCHED") : undefined} colour={summary.unmatchedPayments ? "var(--red-ink)" : undefined} />
      </div>

      {/* the filters */}
      <div className="scope" aria-label="Filters">
        <Sel id="trf-session" label="Session" value={f.session} opts={[...sessions.map((s) => [s, s] as [string, string]), [ALL_SESSIONS, sessionWord(ALL_SESSIONS)]]} onChange={(v) => set("session", v)} />
        <Sel id="trf-band" label="Standing" value={f.band} any="Every standing" opts={BANDS.map((b) => [b, `${bandWord(b)}${bands[b] ? ` (${bands[b]})` : ""}`])} onChange={(v) => set("band", v)} />
        <Sel id="trf-await" label="Awaiting" value={f.awaiting} any="Anything" hint="The desk the application sits at"
          opts={AWAITINGS.map((a) => [a, `${awaitingWord(a)}${waits[a] ? ` (${waits[a]})` : ""}`])} onChange={(v) => set("awaiting", v)} />
        <div className="scope__f"><Field id="trf-fac" label="Faculty">
          <SearchSelect id="trf-fac" value={f.faculty} allLabel="All faculties" placeholder="All faculties"
            options={faculties.map((x) => ({ value: x.code, label: x.name }))} onChange={(v) => set("faculty", v)} />
        </Field></div>
        <div className="scope__f"><Field id="trf-dept" label="Department" hint="Left or moved to">
          <SearchSelect id="trf-dept" value={f.dept} allLabel={f.faculty ? "All in this faculty" : "All departments"} placeholder="Search a department…"
            options={depts.map((d) => ({ value: d.code, label: d.name }))}
            onChange={(v) => go({ ...f, dept: v, faculty: v ? depts.find((d) => d.code === v)?.faculty || f.faculty : f.faculty })} />
        </Field></div>
        <div className="scope__f grow"><Field id="trf-q" label="Search">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ ...f, search: q.trim() }); }}>
            <input id="trf-q" className="ctl" value={q} maxLength={80} onChange={(e) => setQ(e.target.value)} placeholder="Search by matriculation number, name or old-portal reference" />
            <Btn kind="primary" type="submit">Search</Btn>
            <Btn kind="ghost" onClick={clear}>Reset</Btn>
          </form>
        </Field></div>
      </div>

      <Panel title="Filters applied" right={applied.length ? <Btn kind="ghost" size="sm" onClick={clear}>Clear all filters</Btn> : "None — every application in your scope"}>
        <PBody>
          {applied.length ? (
            <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
              {applied.map((a) => (
                <span key={a.key} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px", gap: 6 }}>
                  <span className="sub2">{a.label}:</span> <b>{a.value}</b>
                  <button type="button" aria-label={`Remove ${a.label}`} title={`Remove ${a.label}`}
                    onClick={() => { if (a.key === "search") setQ(""); set(a.key, ""); }}
                    style={{ border: 0, background: "none", cursor: "pointer", fontSize: 16, lineHeight: 1, padding: "0 4px", color: "var(--muted)" }}>&times;</button>
                </span>
              ))}
            </div>
          ) : null}
          <div className={applied.length ? "mt-2" : undefined}><b className="tnum">Total: {vzNum(list.total)} row{list.total === 1 ? "" : "s"}</b></div>
        </PBody>
      </Panel>

      {bands.PART_PAID ? (
        <Note kind="bad" title={`${vzNum(bands.PART_PAID)} application${bands.PART_PAID === 1 ? "" : "s"} part paid — the balance is owed before the final approval`}>
          Each student sees the balance on their transfer page and pays it there; the desks act meanwhile, and the Academic Office&rsquo;s final approval follows the payment.
        </Note>
      ) : null}
      {bands.OVERPAID ? (
        <Note kind="info" title={`${vzNum(bands.OVERPAID)} student${bands.OVERPAID === 1 ? "" : "s"} paid above the fee — ${naira(summary.excess)} in excess`}>
          Nothing more is owed. The portal makes no refund; the Bursary decides by its own procedure.
        </Note>
      ) : null}

      <Panel title="Applications" right={list.total ? `Page ${list.page + 1} of ${pages} · ${vzNum(list.total)} in all · names A–Z` : "None"}>
        {rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "From → To", "Fee due|num", "Paid|num", "Balance|num", "Standing|mid", "Awaiting", "|num"]} rows={rows.map(line)} />
        ) : (
          <PBody><Note kind="info" title="No applications found">No transfer application or old-portal credit matches the filters within your office&rsquo;s scope.</Note></PBody>
        )}
        {pages > 1 ? (
          <PBody>
            <div className="row row--between">
              <Btn kind="ghost" disabled={list.page === 0} onClick={() => go(f, { page: list.page - 1 })}>Previous</Btn>
              <span className="sub2 tnum">Rows {list.page * list.size + 1}–{Math.min(list.total, (list.page + 1) * list.size)} of {vzNum(list.total)}</span>
              <Btn kind="ghost" disabled={list.page + 1 >= pages} onClick={() => go(f, { page: list.page + 1 })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
      <div className="sub2">The fee due is the inter-departmental transfer fee as the Bursary states it now (a completed transfer, the fee it was completed against);
        paid means verified — a payment the bank confirmed on this portal, or an old-portal payment counted toward the application on Old-portal transfers — and a
        reference still awaiting the bank never counts. Paid on the old portal, no application: the student paid toward a transfer on the old portal and has not applied
        here; the payment counts once they do. Each download is recorded with who took it, when and the filters.</div>
    </>
  );
}
