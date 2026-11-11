"use client";

/**
 * The acceptance fee monitor (V724). The figures first — released offers, not paid, awaiting the bank, the earlier fee
 * paid and the balance owing, the balance paid, paid in full, still owing, the outstanding and collected sums — each a
 * door that applies itself; the filters (session, standing, faculty → programme, entry mode, a search); the list, with
 * each row a door to the applicant's record on the Admitted List; and DOWNLOAD — the same selection as a branded
 * workbook, the download recorded. Every row and figure is the server's (admissions.acceptance_fee_monitor): the fee due
 * is the acceptance fee as stated now, so an applicant who paid ₦25,000 before the revision to ₦35,000 reads a ₦10,000
 * balance, never the fee again. V724 follow-up: the part payers' balance in its own figure beside their count (the
 * unpaid sum across every offer is another figure), the offers paid above the fee (for the refund desk) and those confirmed
 * without a reference as bands of their own, and a row on the register opens the student's record.
 */
import { useEffect, useMemo, useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { formatDocDateTime } from "@/lib/document/institution";
import { logExport } from "@/lib/export-log";
import {
  ACCEPTANCE_HEAD, BANDS, EMPTY_ACCEPTANCE, acceptanceFileName, acceptanceLine, acceptanceMeta, acceptancePath, acceptanceQuery, acceptanceRecordHref, bandWord, entryWord,
  naira, stillOwing, withAcceptanceChange, type AcceptanceFilters, type AcceptanceOptions, type AcceptancePage, type AcceptanceRow, type AcceptanceSummary,
} from "@/lib/acceptance-fees";

const vzNum = (n: number | string) => Number(n).toLocaleString("en-GB");
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : null);

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

const BAND_KIND: Record<string, "grey" | "info" | "ok" | "bad" | "warn"> = {
  NOT_PAID: "bad", PENDING: "warn", PART_PAID: "warn", SETTLED_IN_PARTS: "ok", PAID_IN_FULL: "ok", OVERPAID: "warn", CONFIRMED_WITHOUT_REFERENCE: "info",
};

export function AcceptanceFees({ filters, options, summary, list, sessions }: {
  filters: AcceptanceFilters; options: AcceptanceOptions; summary: AcceptanceSummary; list: AcceptancePage; sessions: string[];
}) {
  const queryNav = useQueryNav();
  const f = filters;
  const [q, setQ] = useState(f.q);
  const [stage, setStage] = useState<string | null>(null);

  const go = (next: AcceptanceFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/admissions/acceptance-fees?${acceptanceQuery(next, extra)}`);
  const set = (key: keyof AcceptanceFilters, value: string) => go(withAcceptanceChange(f, key, value));
  const toggle = (key: "band" | "entryMode", value: string) => set(key, f[key] === value ? "" : value);

  // the search runs on the server as one types, a moment after the last key
  useEffect(() => {
    const t = q.trim();
    if (t === f.q) return;
    const timer = setTimeout(() => go({ ...f, q: t }), 450);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const faculties = useMemo(() => [...options.faculties].sort((a, b) => a.name.localeCompare(b.name)), [options.faculties]);
  const progs = useMemo(() => options.programmes.filter((p) => !f.faculty || p.faculty === f.faculty).sort((a, b) => a.name.localeCompare(b.name)), [options.programmes, f.faculty]);
  const labels = { faculty: faculties.find((x) => x.code === f.faculty)?.name, programme: progs.find((p) => p.code === f.programme)?.name };
  const facultyOf = (code: string) => options.programmes.find((p) => p.code === code)?.faculty ?? "";
  const pages = Math.max(1, Math.ceil(list.total / Math.max(1, list.size)));
  const owing = stillOwing(summary);
  const overpaid = summary.overpaid ?? 0;
  const byHand = summary.confirmedWithoutReference ?? 0;
  type Chip = { key: keyof AcceptanceFilters; label: string; value: string };
  const applied = ([
    f.band ? { key: "band", label: "Standing", value: bandWord(f.band) } : null,
    f.faculty ? { key: "faculty", label: "Faculty", value: labels.faculty ?? f.faculty } : null,
    f.programme ? { key: "programme", label: "Programme", value: labels.programme ?? f.programme } : null,
    f.entryMode ? { key: "entryMode", label: "Entry mode", value: entryWord(f.entryMode) } : null,
    f.q ? { key: "q", label: "Search", value: f.q } : null,
  ] as (Chip | null)[]).filter((x): x is Chip => !!x);
  const clear = () => { setQ(""); go({ ...EMPTY_ACCEPTANCE, session: f.session }); };

  /** the whole selection as a workbook: the server's rows, page by page, never more than it holds; the download recorded */
  async function download() {
    if (stage) return;
    setStage("PREPARING…");
    try {
      const rows: AcceptanceRow[] = [];
      const size = 500;
      for (let page = 0; page < 200; page++) {
        const r = await fetch(`/api/bff${acceptancePath(f.session)}?${acceptanceQuery(f, { page, size }, false)}`, { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
        const d = j as AcceptancePage;
        rows.push(...d.rows);
        if (rows.length >= d.total || d.rows.length === 0) break;
        setStage(`PREPARING… ${vzNum(rows.length)} of ${vzNum(d.total)}`);
      }
      setStage("GENERATING EXCEL…");
      const title = `ACCEPTANCE FEE MONITOR${f.band ? ` — ${bandWord(f.band).toUpperCase()}` : ""}`;
      const sub = `${f.session} admission session`;
      const meta = acceptanceMeta(f, labels, rows.length, formatDocDateTime(new Date()));
      const blob = await brandedXlsx(title, ACCEPTANCE_HEAD, rows.map(acceptanceLine), { sheetName: "Acceptance fees", serial: docSerial("ACF"), sub, meta });
      downloadBlob(blob, acceptanceFileName(f, "xlsx"));
      logExport({ report: title, format: "XLSX", rows: rows.length, meta, sub });
      notify(`${vzNum(rows.length)} offer${rows.length === 1 ? "" : "s"} downloaded as Excel`);
    } catch {
      notifyProblem({ status: 0, title: "The download could not be prepared. Check the connection and try again." });
    } finally {
      setStage(null);
    }
  }

  const line = (r: AcceptanceRow, i: number) => {
    const href = acceptanceRecordHref(r, f.session);
    return [
      <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
      <span key="n"><strong>{[r.surname, r.otherNames].filter(Boolean).join(", ")}</strong>
        <div className="sub2 tnum">{[r.jambRegNo, r.applicationNo, r.admissionNo ? `admitted ${r.admissionNo}` : null].filter(Boolean).join(" · ")}</div></span>,
      <span key="p">{r.programme ?? <Pil kind="warn">Not on the programme register</Pil>}<div className="sub2">{entryWord(r.entryMode)}</div></span>,
      <span key="d" className="tnum">{naira(r.feeDue)}</span>,
      <span key="pd" className="tnum">{naira(r.paidTotal)}
        <div className="sub2">{r.payments ? `${r.payments} payment${r.payments === 1 ? "" : "s"}${r.firstAmount !== null && r.firstAmount !== undefined && Number(r.firstAmount) < Number(r.feeDue) ? ` · first ${naira(r.firstAmount)}` : ""}${r.lastPaidAt ? ` · ${when(r.lastPaidAt)}` : ""}` : "—"}</div></span>,
      <span key="b" className="tnum" style={Number(r.balance) > 0 ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{naira(r.balance)}
        {Number(r.excess ?? 0) > 0 ? <div className="sub2 tnum" style={{ color: "var(--amber-ink)" }}>{naira(r.excess)} above the fee</div> : null}
        {r.openReference ? <div className="sub2 tnum">{r.openReference} · {naira(r.openAmount)} open</div> : null}</span>,
      <Pil key="s" kind={BAND_KIND[r.band] ?? "grey"}>{bandWord(r.band)}</Pil>,
      <span key="l" className="tnum">{r.lettersIssued ? `${r.lettersIssued}` : "—"}</span>,
      // V724: on the register, the student's own record (the Bursary reads it); before that, the applicant on the admissions desk
      href ? <LinkBtn key="o" kind="ghost" href={href}>Record</LinkBtn> : <span key="o" />,
    ];
  };

  return (
    <>
      <PageHead title="Acceptance fee monitor"
        description={`${f.session} admission session. Every released UTME and Direct Entry offer (not declined or lapsed) with the acceptance fee as stated now${summary.feeDue != null ? ` — ${naira(summary.feeDue)}` : ""}, what the payment service has confirmed and the balance. An applicant who paid the fee at an earlier figure owes the difference, never the fee again; the admission letter waits for the balance.`}
        actions={<Btn kind="primary" disabled={!list.total} busy={!!stage} busyLabel={stage ?? undefined} onClick={() => download()}>DOWNLOAD ACCEPTANCE FEES</Btn>} />

      {/* the figures, each a door */}
      <div className="grid grid--4" role="group" aria-label="Offers by acceptance fee standing">
        <Door label="Released offers" n={vzNum(summary.offers)} sub={applied.length && !f.band ? "Within the filters applied" : "In your scope"} on={!f.band} onClick={() => set("band", "")} />
        <Door label="Not paid" n={vzNum(summary.notPaid)} sub="No acceptance payment confirmed" on={f.band === "NOT_PAID"} onClick={() => toggle("band", "NOT_PAID")} colour={summary.notPaid ? "var(--red-ink)" : undefined} />
        <Door label="Awaiting the bank" n={vzNum(summary.pending)} sub="A reference drawn, not yet confirmed" on={f.band === "PENDING"} onClick={() => toggle("band", "PENDING")} colour={summary.pending ? "var(--amber-ink)" : undefined} />
        <Door label="Paid the earlier fee — owing" n={vzNum(summary.partPaid)} sub={`Paid before the revision; a balance stands${summary.paidOldAmount ? ` · ${vzNum(summary.paidOldAmount)} paid below the fee as stated now` : ""}`} on={f.band === "PART_PAID"} onClick={() => toggle("band", "PART_PAID")} colour={summary.partPaid ? "var(--amber-ink)" : undefined} />
        <Door label="Balance owed by part payers" n={naira(summary.outstandingBalance ?? 0)} sub={`What the ${vzNum(summary.partPaid)} who paid the earlier fee still owe`} on={false} colour={Number(summary.outstandingBalance ?? 0) > 0 ? "var(--red-ink)" : undefined} />
        <Door label="Paid the balance" n={vzNum(summary.settledInParts)} sub="The revised fee met in more than one payment" on={f.band === "SETTLED_IN_PARTS"} onClick={() => toggle("band", "SETTLED_IN_PARTS")} colour="var(--green-ink)" />
        <Door label="Paid in full" n={vzNum(summary.paidInFull)} sub="The fee as stated, in one payment" on={f.band === "PAID_IN_FULL"} onClick={() => toggle("band", "PAID_IN_FULL")} colour="var(--green-ink)" />
        <Door label="Paid above the fee — for the refund desk" n={vzNum(overpaid)} sub={`More confirmed than the fee as stated now · ${naira(summary.excess ?? 0)} in excess`} on={f.band === "OVERPAID"} onClick={() => toggle("band", "OVERPAID")} colour={overpaid ? "var(--amber-ink)" : undefined} />
        <Door label="Confirmed without a reference" n={vzNum(byHand)} sub="Confirmed by hand or carried over: owes nothing" on={f.band === "CONFIRMED_WITHOUT_REFERENCE"} onClick={() => toggle("band", "CONFIRMED_WITHOUT_REFERENCE")} />
        <Door label="Still owing" n={vzNum(owing)} sub="Not paid, awaiting the bank, or a balance" on={false} colour={owing ? "var(--red-ink)" : undefined} />
        <Door label="Unpaid across all offers" n={naira(summary.outstanding)} sub={`The whole fee where nothing is paid, and the balances · collected ${naira(summary.collected)}`} on={false} colour={Number(summary.outstanding) > 0 ? "var(--red-ink)" : undefined} />
      </div>

      {/* the filters */}
      <div className="scope" aria-label="Filters">
        <Sel id="acf-session" label="Admission session" value={f.session} opts={sessions.map((s) => [s, s])} onChange={(v) => set("session", v)} />
        <Sel id="acf-band" label="Standing" value={f.band} any="Every standing" hint="As the payment service confirmed it"
          opts={BANDS.map((b) => [b, bandWord(b)])} onChange={(v) => set("band", v)} />
        <div className="scope__f"><Field id="acf-fac" label="Faculty">
          <SearchSelect id="acf-fac" value={f.faculty} allLabel="All faculties" placeholder="All faculties"
            options={faculties.map((x) => ({ value: x.code, label: x.name }))} onChange={(v) => set("faculty", v)} />
        </Field></div>
        <div className="scope__f"><Field id="acf-prog" label="Programme">
          <SearchSelect id="acf-prog" value={f.programme} allLabel={f.faculty ? "All in this faculty" : "All programmes"} placeholder="Search a programme…"
            options={progs.map((p) => ({ value: p.code, label: p.name }))}
            onChange={(v) => go({ ...f, programme: v, faculty: v ? facultyOf(v) || f.faculty : f.faculty })} />
        </Field></div>
        <Sel id="acf-entry" label="Entry mode" value={f.entryMode} any="All" opts={[["UTME", "UTME"], ["DIRECT_ENTRY", "Direct Entry"]]} onChange={(v) => set("entryMode", v)} />
        <div className="scope__f grow"><Field id="acf-q" label="Search">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ ...f, q: q.trim() }); }}>
            <input id="acf-q" className="ctl" value={q} maxLength={80} onChange={(e) => setQ(e.target.value)} placeholder="Search by JAMB number, application number or name" />
            <Btn kind="primary" type="submit">Search</Btn>
            <Btn kind="ghost" onClick={clear}>Reset</Btn>
          </form>
        </Field></div>
      </div>

      <Panel title="Filters applied" right={applied.length ? <Btn kind="ghost" size="sm" onClick={clear}>Clear all filters</Btn> : "None — every released offer in your scope"}>
        <PBody>
          {applied.length ? (
            <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
              {applied.map((a) => (
                <span key={a.key} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px", gap: 6 }}>
                  <span className="sub2">{a.label}:</span> <b>{a.value}</b>
                  <button type="button" aria-label={`Remove ${a.label}`} title={`Remove ${a.label}`}
                    onClick={() => { if (a.key === "q") setQ(""); set(a.key, ""); }}
                    style={{ border: 0, background: "none", cursor: "pointer", fontSize: 16, lineHeight: 1, padding: "0 4px", color: "var(--muted)" }}>&times;</button>
                </span>
              ))}
            </div>
          ) : null}
          <div className={applied.length ? "mt-2" : undefined}><b className="tnum">Total: {vzNum(list.total)} offer{list.total === 1 ? "" : "s"}</b></div>
        </PBody>
      </Panel>

      {summary.partPaid ? (
        <Note kind="bad" title={`${vzNum(summary.partPaid)} applicant${summary.partPaid === 1 ? "" : "s"} paid the acceptance fee at an earlier figure and owe${summary.partPaid === 1 ? "s" : ""} the balance${summary.outstandingBalance != null ? ` — ${naira(summary.outstandingBalance)} in all` : ""}`}>
          Each sees the balance on the applicant dashboard and pays it there; the admission letter is issued once it is paid, and the student portal stays shut until then. The place is held from the first payment.
        </Note>
      ) : null}
      {overpaid ? (
        <Note kind="info" title={`${vzNum(overpaid)} applicant${overpaid === 1 ? "" : "s"} paid above the acceptance fee as stated now — ${naira(summary.excess ?? 0)} in excess`}>
          Nothing more is owed. Choose the &ldquo;Paid above the fee&rdquo; standing to list them for the refund desk; a refund follows the Bursary&rsquo;s own procedure.
        </Note>
      ) : null}

      <Panel title="Offers" right={list.total ? `Page ${list.page + 1} of ${pages} · ${vzNum(list.total)} in all · names A–Z` : "None"}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Applicant", "Programme", "Fee due|num", "Paid|num", "Balance|num", "Standing|mid", "Letters|num", "|num"]} rows={list.rows.map(line)} />
        ) : (
          <PBody><Note kind="info" title="No offers found">No released offers match the filters within your office&rsquo;s scope.</Note></PBody>
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
      <div className="sub2">The fee due is the acceptance fee stated for the session on Fee Setup, as it stands now; paid means a payment the payment service confirmed, and a
        reference still awaiting the bank never counts. Paid the earlier fee: the first confirmed payment was below the fee as stated now, so a balance stands and the
        admission letter waits for it. Paid the balance: the revised fee was met in more than one payment. Paid above the fee: more was confirmed than the fee as stated
        now — nothing is owed, and the excess is for the refund desk. Confirmed without a reference: the acceptance was confirmed by hand or carried over, and owes nothing.
        Unpaid across all offers counts the whole fee of every offer with nothing paid as well as the balances. Each download is recorded with who took it, when and the filters.</div>
    </>
  );
}
