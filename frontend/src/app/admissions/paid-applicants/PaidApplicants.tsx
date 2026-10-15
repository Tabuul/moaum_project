"use client";

/**
 * The Post-UTME paid applicants report (V479). The figures first — paid applicants in all, by gender and entry mode, by
 * payment status — each a door that applies itself; the filters (session, payment status, faculty → department →
 * programme, gender, entry mode, payment dates, JAMB number, a search), each list holding what the session's applicants
 * applied for within the office's scope; what the selection is missing, counted and never a reason to leave a row out;
 * the faculties and programmes, each a door; the list, names A–Z, in the eight columns the Academic Office asked for; and
 * DOWNLOAD PAID POST-UTME APPLICANTS — the same selection as a branded workbook or PDF, every download recorded by the
 * server. Every row and figure is the server's; the office's scope is the server's.
 */
import { useEffect, useMemo, useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { formatDocDateTime } from "@/lib/document/institution";
import { reasonHeader } from "@/lib/reason";
import {
  EMPTY_PAID, NOT_AVAILABLE, PAID_HEAD, PAID_STATUSES, aggregateCell, entryWord, genderWord, missingWord, paidFileName, paidHeading, paidLine, paidPath,
  paidQuery, statusWord, withPaidChange, type PaidExport, type PaidFilters, type PaidOptions, type PaidPage, type PaidRow, type PaidSummary,
} from "@/lib/paid-applicants";

const vzNum = (n: number | string) => Number(n).toLocaleString("en-GB");

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
function Door({ label, n, sub, on, onClick }: { label: string; n: number; sub: string; on: boolean; onClick: () => void }) {
  return (
    <button type="button" className="tile stat-tile" onClick={onClick} aria-pressed={on}
      style={{ textAlign: "left", font: "inherit", border: on ? "2px solid var(--chrome)" : undefined }}>
      <div className="eyebrow">{label}</div>
      <div className="n tnum">{vzNum(n)}</div>
      <div className="c">{sub}</div>
    </button>
  );
}

/** a value the record does not hold, said as such */
function Absent({ word = NOT_AVAILABLE }: { word?: string }) {
  return <Pil kind="warn">{word}</Pil>;
}

export function PaidApplicants({ filters, options, summary, list, sessions }: {
  filters: PaidFilters; options: PaidOptions; summary: PaidSummary; list: PaidPage; sessions: string[];
}) {
  const queryNav = useQueryNav();
  const f = filters;
  const o = options;
  const [q, setQ] = useState(f.q);
  const [jamb, setJamb] = useState(f.jamb);
  const [format, setFormat] = useState<"XLSX" | "PDF">("XLSX");
  const [stage, setStage] = useState<string | null>(null);

  const go = (next: PaidFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/admissions/paid-applicants?${paidQuery(next, extra)}`);
  const set = (key: keyof PaidFilters, value: string) => go(withPaidChange(f, key, value));

  // the search runs on the server as one types, a moment after the last key
  useEffect(() => {
    const t = q.trim();
    if (t === f.q) return;
    const timer = setTimeout(() => go({ ...f, q: t }), 450);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const facBound = !!o.scope.faculty;
  const deptBound = !!o.scope.department;
  const faculties = useMemo(() => [...new Map(o.programmes.map((p) => [p.faculty_code, p.faculty])).entries()].sort((a, b) => a[1].localeCompare(b[1])), [o.programmes]);
  const depts = useMemo(() => [...new Map(o.programmes.filter((p) => !f.fac || p.faculty_code === f.fac).map((p) => [p.dept_code, p.department])).entries()]
    .sort((a, b) => a[1].localeCompare(b[1])), [o.programmes, f.fac]);
  const progs = useMemo(() => o.programmes.filter((p) => (!f.fac || p.faculty_code === f.fac) && (!f.dept || p.dept_code === f.dept))
    .sort((a, b) => a.programme.localeCompare(b.programme)), [o.programmes, f.fac, f.dept]);
  const deptOf = (prog: string | null) => o.programmes.find((p) => p.programme_code === prog)?.dept_code ?? "";
  const nameOf = { faculty: faculties.find(([c]) => c === f.fac)?.[1], department: depts.find(([c]) => c === f.dept)?.[1], programme: progs.find((p) => p.programme_code === f.prog)?.programme };

  const status = f.status || "VERIFIED";
  const paidOnly = status === "VERIFIED";
  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const bySex = (s: string) => summary.bySex.find((x) => x.sex === s)?.n ?? 0;
  const byEntry = (e: string) => summary.byEntryMode.find((x) => x.entry_mode === e)?.n ?? 0;
  const byStatus = (s: string) => summary.byStatus.find((x) => x.status === s)?.n ?? 0;
  const statusesHeld = summary.byStatus.filter((s) => s.n > 0);
  const range = f.from || f.to ? `paid ${f.from ? `from ${f.from}` : ""}${f.from && f.to ? " " : ""}${f.to ? `to ${f.to}` : ""}` : null;
  const word = paidOnly ? "paid applicant" : "applicant";
  type Chip = { key: keyof PaidFilters; label: string; value: string };
  const applied = ([
    f.status ? { key: "status", label: "Payment status", value: statusWord(f.status) } : null,
    f.fac && !facBound ? { key: "fac", label: "Faculty", value: nameOf.faculty ?? f.fac } : null,
    f.dept && !deptBound ? { key: "dept", label: "Department", value: nameOf.department ?? f.dept } : null,
    f.prog ? { key: "prog", label: "Programme", value: nameOf.programme ?? f.prog } : null,
    f.sex ? { key: "sex", label: "Gender", value: genderWord(f.sex) } : null,
    f.entry ? { key: "entry", label: "Entry mode", value: entryWord(f.entry) } : null,
    f.from ? { key: "from", label: "Paid from", value: f.from } : null,
    f.to ? { key: "to", label: "Paid to", value: f.to } : null,
    f.jamb ? { key: "jamb", label: "JAMB number", value: f.jamb } : null,
    f.q ? { key: "q", label: "Search", value: f.q } : null,
  ] as (Chip | null)[]).filter((x): x is Chip => !!x);
  const clear = () => { setQ(""); setJamb(""); go({ ...EMPTY_PAID, session: f.session }); };

  /** the whole selection, from the server, as a workbook or a PDF; the server records the download either way */
  async function download() {
    if (stage) return;
    try {
      if (format === "XLSX") {
        setStage("PREPARING REPORT...");
        const body = { format: "XLSX", status: f.status || undefined, fac: f.fac || undefined, dept: f.dept || undefined, prog: f.prog || undefined,
          sex: f.sex || undefined, entry: f.entry || undefined, from: f.from || undefined, to: f.to || undefined, jamb: f.jamb || undefined, q: f.q || undefined };
        const r = await fetch(`/api/bff${paidPath(f.session)}/export`, {
          method: "POST", cache: "no-store",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Paid Post-UTME applicants of ${f.session} downloaded (Excel)`) },
          body: JSON.stringify(body),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
        const d = j as PaidExport;
        setStage("GENERATING EXCEL...");
        const h = paidHeading(f, d.labels, d.total, d.generatedBy, formatDocDateTime(new Date()));
        const blob = await brandedXlsx(h.title, PAID_HEAD, d.rows.map(paidLine), { sheetName: "Paid applicants", serial: docSerial("PUA"), sub: h.sub, meta: h.meta });
        downloadBlob(blob, paidFileName(f, "xlsx"));
        notify(`${vzNum(d.total)} ${word}${d.total === 1 ? "" : "s"} downloaded as Excel`);
      } else {
        setStage("GENERATING PDF...");
        const r = await fetch(`/admissions/paid-applicants/pdf?${paidQuery(f)}`, { cache: "no-store" });
        if (!r.ok) {
          const j = await r.json().catch(() => null);
          notifyProblem(j ?? { status: r.status, title: r.statusText });
          return;
        }
        const blob = await r.blob();
        downloadBlob(blob, paidFileName(f, "pdf"));
        notify(`${vzNum(list.total)} ${word}${list.total === 1 ? "" : "s"} downloaded as PDF`);
      }
    } catch {
      notifyProblem({ status: 0, title: "The download could not be prepared. Check the connection and try again." });
    } finally {
      setStage(null);
    }
  }

  const line = (r: PaidRow, i: number) => {
    const agg = aggregateCell(r);
    return [
      <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
      r.jamb_reg_no ? <span key="j" className="tnum">{r.jamb_reg_no}</span> : <Absent key="j" />,
      <span key="n"><strong>{r.full_name}</strong>
        <div className="sub2 tnum">{[r.application_no, r.paid_at ? `paid ${formatDocDateTime(r.paid_at)}` : null, r.receipt_no ? `receipt ${r.receipt_no}` : null,
          (r.verified_payments ?? 0) > 1 ? `${r.verified_payments} confirmed payments` : null].filter(Boolean).join(" · ")}</div>
        {paidOnly ? null : <Pil kind={r.payment_status === "VERIFIED" ? "ok" : r.payment_status === "PENDING" ? "warn" : "grey"}>{statusWord(r.payment_status)}</Pil>}</span>,
      <span key="p">{r.programme ?? <Absent />}
        {r.faculty ? <div className="sub2">{[r.department, r.faculty].filter(Boolean).join(" · ")}</div>
          : r.programme ? <div className="sub2"><Pil kind="warn">Not on the programme register</Pil></div> : null}</span>,
      r.sex ? <span key="g">{genderWord(r.sex)}</span> : <Absent key="g" />,
      typeof agg === "number" ? <span key="a" className="tnum">{agg}</span> : <Absent key="a" word={agg} />,
      r.phone ? <span key="ph" className="tnum">{r.phone}</span> : <Absent key="ph" />,
      r.email ? <span key="e" style={{ wordBreak: "break-all" }}>{r.email}</span> : <Absent key="e" />,
    ];
  };

  return (
    <>
      <PageHead title="Paid Post-UTME applicants"
        description={`${f.session} admission session. Candidates whose Post-UTME application fee the payment service has confirmed — one row an application, however many attempts it took. Every figure and row is read on the server within your office's scope.`}
        actions={<>
          <label className="sr-only" htmlFor="pua-format">Format</label>
          <select id="pua-format" className="ctl" style={{ width: "auto" }} value={format} disabled={!!stage} onChange={(e) => setFormat(e.target.value as "XLSX" | "PDF")}>
            <option value="XLSX">Excel (.xlsx)</option>
            <option value="PDF">PDF</option>
          </select>
          <Btn kind="primary" disabled={!list.total} busy={!!stage} busyLabel={stage ?? undefined} onClick={() => download()}>DOWNLOAD PAID POST-UTME APPLICANTS</Btn>
        </>} />

      {/* the figures, each a door */}
      <div className="grid grid--4" role="group" aria-label="Paid applicants by gender and entry mode">
        <Door label={paidOnly ? `Paid applicants${range ? ` (${range})` : ""}` : `Applicants — ${statusWord(status).toLowerCase()}`} n={summary.total}
          sub={applied.length ? "Within the filters applied" : "In your scope"} on={!f.sex && !f.entry} onClick={() => go({ ...f, sex: "", entry: "" })} />
        <Door label="Male" n={bySex("M")} sub={`${word}s`} on={f.sex === "M"} onClick={() => set("sex", f.sex === "M" ? "" : "M")} />
        <Door label="Female" n={bySex("F")} sub={`${word}s`} on={f.sex === "F"} onClick={() => set("sex", f.sex === "F" ? "" : "F")} />
        {summary.bySex.some((x) => !x.sex) ? (
          <div className="tile stat-tile">
            <div className="eyebrow">Gender not recorded</div>
            <div className="n tnum" style={{ color: "var(--amber-ink)" }}>{vzNum(summary.bySex.find((x) => !x.sex)?.n ?? 0)}</div>
            <div className="c">Neither the candidate nor JAMB&rsquo;s record holds it</div>
          </div>
        ) : null}
        <Door label="UTME" n={byEntry("UTME")} sub={`${word}s by UTME`} on={f.entry === "UTME"} onClick={() => set("entry", f.entry === "UTME" ? "" : "UTME")} />
        <Door label="Direct Entry" n={byEntry("DIRECT_ENTRY")} sub={`${word}s by Direct Entry`} on={f.entry === "DIRECT_ENTRY"} onClick={() => set("entry", f.entry === "DIRECT_ENTRY" ? "" : "DIRECT_ENTRY")} />
        {byEntry("TRANSFER") ? <Door label="Transfer" n={byEntry("TRANSFER")} sub={`${word}s by transfer`} on={f.entry === "TRANSFER"} onClick={() => set("entry", f.entry === "TRANSFER" ? "" : "TRANSFER")} /> : null}
      </div>
      {statusesHeld.length > 1 || !paidOnly ? (
        <div className="row row--tight mt-2" role="group" aria-label="By payment status" style={{ flexWrap: "wrap", gap: 6 }}>
          <span className="sub2">By payment status:</span>
          {PAID_STATUSES.filter((s) => s === "ALL" || byStatus(s) > 0).map((s) => (
            <Btn key={s} kind={status === s ? "primary" : "ghost"} size="sm" onClick={() => set("status", s === "VERIFIED" ? "" : s)}>
              {`${statusWord(s)}${s === "ALL" ? "" : ` · ${vzNum(byStatus(s))}`}`}
            </Btn>
          ))}
        </div>
      ) : null}

      {/* the filters */}
      <div className="scope" aria-label="Filters">
        <Sel id="pua-session" label="Admission session" value={f.session} opts={sessions.map((s) => [s, s])} onChange={(v) => set("session", v)} />
        <Sel id="pua-status" label="Payment status" value={f.status} any={statusWord("VERIFIED")} hint="Paid means confirmed by the payment service"
          opts={PAID_STATUSES.filter((s) => s !== "VERIFIED").map((s) => [s, statusWord(s)])} onChange={(v) => set("status", v)} />
        <div className="scope__f"><Field id="pua-fac" label="Faculty">
          <SearchSelect id="pua-fac" value={facBound ? (o.scope.faculty ?? "") : f.fac} disabled={facBound} allLabel={facBound ? undefined : "All faculties"} placeholder="All faculties"
            options={faculties.map(([c, n]) => ({ value: c, label: n }))} onChange={(v) => set("fac", v)} />
        </Field></div>
        <div className="scope__f"><Field id="pua-dept" label="Department">
          <SearchSelect id="pua-dept" value={deptBound ? (o.scope.department ?? "") : f.dept} disabled={deptBound} allLabel={deptBound ? undefined : f.fac ? "All in this faculty" : "All departments"}
            placeholder="All departments" options={depts.map(([c, n]) => ({ value: c, label: n }))} onChange={(v) => set("dept", v)} />
        </Field></div>
        <div className="scope__f"><Field id="pua-prog" label="Programme">
          <SearchSelect id="pua-prog" value={f.prog} allLabel={f.dept ? "All in this department" : f.fac ? "All in this faculty" : "All programmes"} placeholder="Search a programme…"
            options={progs.map((p) => ({ value: p.programme_code, label: p.programme, sub: `${vzNum(p.applicants)} applicant${p.applicants === 1 ? "" : "s"}` }))}
            onChange={(v) => go({ ...f, prog: v, dept: v ? deptOf(v) || f.dept : f.dept })} />
        </Field></div>
        <Sel id="pua-sex" label="Gender" value={f.sex} any="All" opts={[["M", "Male"], ["F", "Female"]]} onChange={(v) => set("sex", v)} />
        <Sel id="pua-entry" label="Entry mode" value={f.entry} any="All" opts={[["UTME", "UTME"], ["DIRECT_ENTRY", "Direct Entry"], ["TRANSFER", "Transfer"]]} onChange={(v) => set("entry", v)} />
        <div className="scope__f"><Field id="pua-from" label="Paid from">
          <input id="pua-from" type="date" className="ctl tnum" value={f.from} max={f.to || undefined} onChange={(e) => set("from", e.target.value)} />
        </Field></div>
        <div className="scope__f"><Field id="pua-to" label="Paid to">
          <input id="pua-to" type="date" className="ctl tnum" value={f.to} min={f.from || undefined} onChange={(e) => set("to", e.target.value)} />
        </Field></div>
        <div className="scope__f"><Field id="pua-jamb" label="JAMB number">
          <form onSubmit={(e) => { e.preventDefault(); set("jamb", jamb.trim()); }}>
            <input id="pua-jamb" className="ctl tnum" value={jamb} maxLength={40} placeholder="e.g. 202660110469AJ"
              onChange={(e) => setJamb(e.target.value)} onBlur={() => { if (jamb.trim() !== f.jamb) set("jamb", jamb.trim()); }} />
          </form>
        </Field></div>
        <div className="scope__f grow"><Field id="pua-q" label="Search">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ ...f, q: q.trim() }); }}>
            <input id="pua-q" className="ctl" value={q} maxLength={80} onChange={(e) => setQ(e.target.value)} placeholder="Search by JAMB number, candidate's name or programme" />
            <Btn kind="primary" type="submit">Search</Btn>
            <Btn kind="ghost" onClick={clear}>Reset</Btn>
          </form>
        </Field></div>
      </div>

      <Panel title="Filters applied" right={applied.length ? <Btn kind="ghost" size="sm" onClick={clear}>Clear all filters</Btn> : `None — every ${word} in your scope`}>
        <PBody>
          {applied.length ? (
            <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
              {applied.map((a) => (
                <span key={a.key} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px", gap: 6 }}>
                  <span className="sub2">{a.label}:</span> <b>{a.value}</b>
                  <button type="button" aria-label={`Remove ${a.label}`} title={`Remove ${a.label}`}
                    onClick={() => { if (a.key === "q") setQ(""); if (a.key === "jamb") setJamb(""); set(a.key, ""); }}
                    style={{ border: 0, background: "none", cursor: "pointer", fontSize: 16, lineHeight: 1, padding: "0 4px", color: "var(--muted)" }}>&times;</button>
                </span>
              ))}
            </div>
          ) : null}
          <div className={applied.length ? "mt-2" : undefined}><b className="tnum">Total: {vzNum(list.total)} {word}{list.total === 1 ? "" : "s"}</b></div>
        </PBody>
      </Panel>

      {/* what the selection is missing: counted, said on each row, never a reason to leave a row out */}
      {list.missing.length ? (
        <Note kind="bad" title="Data check — some records are incomplete">
          <div>Every applicant is listed and downloaded; a value the record does not hold reads <b>{NOT_AVAILABLE}</b>. Within the filters applied:</div>
          <ul style={{ margin: "6px 0 0 18px" }}>
            {list.missing.map((m) => <li key={m.field}><b className="tnum">{vzNum(m.n)}</b> without {missingWord(m.field).charAt(0).toLowerCase() + missingWord(m.field).slice(1)}</li>)}
          </ul>
          {list.missing.some((m) => m.field === "PHONE" || m.field === "EMAIL") ? (
            <div className="sub2 mt-1">Applicants brought over from the old portal came without contacts; the placeholders they carry are not shown as contacts.</div>
          ) : null}
        </Note>
      ) : list.total ? <Note kind="ok" title="Data check">Every record in the selection holds each of the eight columns.</Note> : null}

      <div className="grid grid--2">
        <Panel title="By faculty" right={`${summary.byFaculty.length}`}>
          {summary.byFaculty.length ? (
            <DTable pageSize={0} cols={["Faculty", `${paidOnly ? "Paid" : "Applicants"}|num`, "|num"]}
              rows={summary.byFaculty.map((b) => [
                <span key="f">{b.faculty ?? <Absent word="Programme not on the register" />}</span>,
                <span key="n" className="tnum">{vzNum(b.n)}</span>,
                b.faculty_code && !facBound ? <Btn key="a" kind="ghost" size="sm" onClick={() => set("fac", b.faculty_code ?? "")}>View</Btn> : <span key="a" />,
              ])} />
          ) : <PBody><div className="sub2">None.</div></PBody>}
        </Panel>
        <Panel title="By programme" right={`${summary.byProgramme.length}`}>
          {summary.byProgramme.length ? (
            <DTable pageSize={10} cols={["Programme", `${paidOnly ? "Paid" : "Applicants"}|num`, "|num"]}
              texts={summary.byProgramme.map((b) => `${b.programme ?? ""} ${b.faculty ?? ""}`)}
              rows={summary.byProgramme.map((b) => [
                <span key="p">{b.programme ?? <Absent word="Programme not on the register" />}{b.faculty ? <div className="sub2">{b.faculty}</div> : null}</span>,
                <span key="n" className="tnum">{vzNum(b.n)}</span>,
                b.programme_code ? <Btn key="a" kind="ghost" size="sm" onClick={() => go({ ...f, fac: b.faculty_code ?? f.fac, dept: deptOf(b.programme_code), prog: b.programme_code ?? "" })}>View</Btn> : <span key="a" />,
              ])} />
          ) : <PBody><div className="sub2">None.</div></PBody>}
        </Panel>
      </div>

      <Panel title={paidOnly ? "Paid applicants" : "Applicants"} right={list.total ? `Page ${list.page + 1} of ${pages} · ${vzNum(list.total)} in all · names A–Z` : "None"}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", ...PAID_HEAD.map((h, i) => (i === 4 ? `${h}|num` : h))]} rows={list.rows.map(line)} />
        ) : (
          <PBody><Note kind="info" title={`No ${word}s found`}>No {word}s match the filters within your office&rsquo;s scope.</Note></PBody>
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
      <div className="sub2">Paid means an application-fee payment the payment service confirmed; a reversal by the Bursary undoes it, and a checking,
        acceptance or school fee never counts. The UTME aggregate is JAMB&rsquo;s, as the merit list reads it — never computed; a Direct Entry candidate sat no UTME.
        Each download is recorded with who took it, when, the filters and the number of rows.</div>
    </>
  );
}
