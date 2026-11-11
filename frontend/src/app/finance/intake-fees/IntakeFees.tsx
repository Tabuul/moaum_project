"use client";

/**
 * The school-fee readiness monitor (V724), in two tabs. Fee configuration: the undergraduate programmes with and without a
 * full-time fee line in force reaching a fresh UTME (100 Level) or Direct Entry (200 Level) entrant of the session, by
 * faculty — a programme without one reads "school fees not yet available" on its freshers' applicant dashboards, and the
 * student portal stays shut to them while the gate is on. Applicants: every fresher of the session on the register with
 * the state of their school fees (finance.school_fee_state) and of their student portal (finance.portal_access_state), the
 * figures each a door that applies itself, the filters, the list with each row a door to the student's record, and the
 * download. Every row and figure is the server's (finance.programme_fee_coverage, finance.intake_fee_monitor); the gate
 * itself is set on Fee Setup. The figures above the list are counted with the list's own filters (but for the two states,
 * so each state stays a door), and the coverage figures count programmes — a programme is covered when every entry of it is.
 */
import { useEffect, useMemo, useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { formatDocDateTime } from "@/lib/document/institution";
import { logExport } from "@/lib/export-log";
import {
  EMPTY_INTAKE, FEE_STATES, INTAKE_HEAD, PORTAL_STATES, clearsOnWord, entryWord, feeStateWord, intakeFileName, intakeLine, intakeMeta, intakePath, intakeQuery, naira,
  portalStateWord, withIntakeChange, type Coverage, type IntakeFilters, type IntakeOptions, type IntakePage, type IntakeRow, type IntakeSummary, type IntakeTab, type PortalGate,
} from "@/lib/intake-fees";

const vzNum = (n: number | string | null | undefined) => Number(n ?? 0).toLocaleString("en-GB");
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");

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
function Door({ label, n, sub, on, onClick, colour }: { label: string; n: string; sub: string; on: boolean; onClick: () => void; colour?: string }) {
  return (
    <button type="button" className="tile stat-tile" onClick={onClick} aria-pressed={on}
      style={{ textAlign: "left", font: "inherit", border: on ? "2px solid var(--chrome)" : undefined }}>
      <div className="eyebrow">{label}</div>
      <div className="n tnum" style={colour ? { color: colour } : undefined}>{n}</div>
      <div className="c">{sub}</div>
    </button>
  );
}

const FEE_KIND: Record<string, "grey" | "info" | "ok" | "bad" | "warn"> = {
  NOT_CONFIGURED: "bad", NOT_OPEN: "warn", AVAILABLE: "grey", PAYMENT_PENDING: "warn", PART_PAID: "info", PAID: "ok",
};
const PORTAL_KIND: Record<string, "grey" | "info" | "ok" | "bad" | "warn"> = {
  OPEN: "grey", EXCEPTION: "info", CLEARED: "ok", HELD_ACCEPTANCE_BALANCE: "bad", HELD_FEES_NOT_AVAILABLE: "bad", HELD_FEES_UNPAID: "warn",
};
const FEE_COLOUR: Record<string, string | undefined> = {
  NOT_CONFIGURED: "var(--red-ink)", NOT_OPEN: "var(--amber-ink)", PAYMENT_PENDING: "var(--amber-ink)", PAID: "var(--green-ink)",
};
const PORTAL_COLOUR: Record<string, string | undefined> = {
  CLEARED: "var(--green-ink)", HELD_ACCEPTANCE_BALANCE: "var(--red-ink)", HELD_FEES_NOT_AVAILABLE: "var(--red-ink)", HELD_FEES_UNPAID: "var(--amber-ink)",
};

export function IntakeFees({ filters, coverage, summary, options, list, gate, actingOffice, sessions }: {
  filters: IntakeFilters; coverage: Coverage; summary: IntakeSummary; options: IntakeOptions; list: IntakePage; gate: PortalGate | null;
  actingOffice: string | null; sessions: string[];
}) {
  const queryNav = useQueryNav();
  const f = filters;
  const [q, setQ] = useState(f.q);
  const [stage, setStage] = useState<string | null>(null);
  const [uncoveredOnly, setUncoveredOnly] = useState(false);

  const go = (next: IntakeFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/finance/intake-fees?${intakeQuery(next, extra)}`);
  const set = (key: keyof IntakeFilters, value: string) => go(withIntakeChange(f, key, value));
  const toggle = (key: "feeState" | "portalState" | "entryMode", value: string) => go({ ...withIntakeChange(f, key, f[key] === value ? "" : value), tab: "applicants" });
  const tab = (t: IntakeTab) => go({ ...f, tab: t });

  // the search runs on the server as one types, a moment after the last key
  useEffect(() => {
    const t = q.trim();
    if (t === f.q) return;
    const timer = setTimeout(() => go({ ...f, q: t, tab: "applicants" }), 450);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const faculties = useMemo(() => [...options.faculties].sort((a, b) => a.name.localeCompare(b.name)), [options.faculties]);
  const progs = useMemo(() => options.programmes.filter((p) => !f.faculty || p.faculty === f.faculty).sort((a, b) => a.name.localeCompare(b.name)), [options.programmes, f.faculty]);
  const labels = { faculty: faculties.find((x) => x.code === f.faculty)?.name, programme: progs.find((p) => p.code === f.programme)?.name };
  const facultyOf = (code: string) => options.programmes.find((p) => p.code === code)?.faculty ?? "";
  const pages = Math.max(1, Math.ceil(list.total / Math.max(1, list.size)));
  const feeN = (s: string) => summary.feeStates?.[s] ?? 0;
  const portalN = (s: string) => summary.portalStates?.[s] ?? 0;
  type Chip = { key: keyof IntakeFilters; label: string; value: string };
  const applied = ([
    f.feeState ? { key: "feeState", label: "Fee state", value: feeStateWord(f.feeState) } : null,
    f.portalState ? { key: "portalState", label: "Portal", value: portalStateWord(f.portalState) } : null,
    f.faculty ? { key: "faculty", label: "Faculty", value: labels.faculty ?? f.faculty } : null,
    f.programme ? { key: "programme", label: "Programme", value: labels.programme ?? f.programme } : null,
    f.entryMode ? { key: "entryMode", label: "Entry mode", value: entryWord(f.entryMode) } : null,
    f.q ? { key: "q", label: "Search", value: f.q } : null,
  ] as (Chip | null)[]).filter((x): x is Chip => !!x);
  const clear = () => { setQ(""); go({ ...EMPTY_INTAKE, session: f.session, tab: "applicants" }); };

  /** the whole selection as a workbook: the server's rows, page by page, never more than it holds; the download recorded */
  async function download() {
    if (stage) return;
    setStage("PREPARING…");
    try {
      const rows: IntakeRow[] = [];
      const size = 500;
      for (let page = 0; page < 200; page++) {
        const r = await fetch(`/api/bff${intakePath(f.session)}?${intakeQuery(f, { page, size }, true)}`, { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
        const d = j as IntakePage;
        rows.push(...d.rows);
        if (rows.length >= d.total || d.rows.length === 0) break;
        setStage(`PREPARING… ${vzNum(rows.length)} of ${vzNum(d.total)}`);
      }
      setStage("GENERATING EXCEL…");
      const title = `SCHOOL FEES READINESS${f.portalState ? ` — ${portalStateWord(f.portalState).toUpperCase()}` : f.feeState ? ` — ${feeStateWord(f.feeState).toUpperCase()}` : ""}`;
      const sub = `${f.session} entry session`;
      const meta = intakeMeta(f, labels, rows.length, formatDocDateTime(new Date()));
      const blob = await brandedXlsx(title, INTAKE_HEAD, rows.map(intakeLine), { sheetName: "Freshers", serial: docSerial("SFR"), sub, meta });
      downloadBlob(blob, intakeFileName(f, "xlsx"));
      logExport({ report: title, format: "XLSX", rows: rows.length, meta, sub });
      notify(`${vzNum(rows.length)} fresher${rows.length === 1 ? "" : "s"} downloaded as Excel`);
    } catch {
      notifyProblem({ status: 0, title: "The download could not be prepared. Check the connection and try again." });
    } finally {
      setStage(null);
    }
  }

  const coverageRows = useMemo(() => {
    const rows = uncoveredOnly ? coverage.rows.filter((r) => !r.covered) : coverage.rows;
    return [...rows].sort((a, b) => (a.faculty ?? "").localeCompare(b.faculty ?? "") || a.programme.localeCompare(b.programme) || a.level - b.level);
  }, [coverage.rows, uncoveredOnly]);
  // V724: the server counts programmes, not programme × entry; the rows (one an entry) give the figure only where an older server
  // leaves it out
  const gapProgrammes = coverage.uncoveredWithFreshers
    ?? new Set(coverage.rows.filter((r) => !r.covered && r.admitted > 0).map((r) => r.programmeCode)).size;
  const maySetFees = ["bursar", "studentaccounts", "super"].includes(actingOffice ?? "");

  const line = (r: IntakeRow, i: number) => [
    <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
    <span key="n"><strong>{[r.surname, r.otherNames].filter(Boolean).join(", ")}</strong>
      <div className="sub2 tnum">{[r.matricNo, r.admissionNo].filter(Boolean).join(" · ") || "—"}</div></span>,
    <span key="p">{r.programme ?? r.programmeCode ?? <Pil kind="warn">Not on the programme register</Pil>}
      <div className="sub2">{[entryWord(r.entryMode), r.currentLevel ? `${r.currentLevel} Level` : null].filter(Boolean).join(" · ")}</div></span>,
    <span key="d" className="tnum">{r.feeStated ? naira(r.due) : <Pil kind="bad">Not stated</Pil>}
      {r.feeStated && Number(r.dueFirstSemester) !== Number(r.due) ? <div className="sub2 tnum">first semester {naira(r.dueFirstSemester)}</div> : null}</span>,
    <span key="pd" className="tnum">{naira(r.paid)}{r.openReference ? <div className="sub2 tnum">{r.openReference} open</div> : null}</span>,
    <span key="b" className="tnum" style={Number(r.balance) > 0 ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{naira(r.balance)}</span>,
    <Pil key="fs" kind={FEE_KIND[r.feeState] ?? "grey"}>{feeStateWord(r.feeState)}</Pil>,
    <span key="ps"><Pil kind={PORTAL_KIND[r.portalState] ?? "grey"}>{portalStateWord(r.portalState)}</Pil>
      {/* V724: the acceptance balance comes before the school fees; a record with no applicant account has no dashboard to pay on */}
      {Number(r.acceptanceBalance ?? 0) > 0 ? <div className="sub2 tnum" style={{ color: "var(--red-ink)", fontWeight: 600 }}>acceptance balance {naira(r.acceptanceBalance)} owed</div> : null}
      {r.hasApplicantAccount === false ? <div className="mt-1"><Pil kind="grey">No applicant account</Pil></div> : null}
      <div className="sub2">{r.accountOpened ? `student account opened${r.lastSignedInAt ? ` · signed in ${when(r.lastSignedInAt)}` : " · never signed in"}` : "no student account yet"}</div></span>,
    <LinkBtn key="o" kind="ghost" href={`/students/${r.studentId}`}>Record</LinkBtn>,
  ];

  return (
    <>
      <PageHead title="School fees readiness"
        description={`${f.session} entry session. Whether the school fees reach every programme's freshers, and where each fresher on the register stands: fees stated, paid, and the student portal open or held. ${gate ? (gate.enabled ? `The student portal fee gate is ON from ${gate.fromSession}: the portal opens when the ${clearsOnWord(gate.clearsOn).toLowerCase()} and the payment is verified.` : "The student portal fee gate is OFF.") : ""}`}
        actions={<>
          {maySetFees ? <LinkBtn kind="ghost" href={`/finance/fees?session=${encodeURIComponent(f.session)}`}>Fee Setup</LinkBtn> : null}
          {f.tab === "applicants" ? <Btn kind="primary" disabled={!list.total} busy={!!stage} busyLabel={stage ?? undefined} onClick={() => download()}>DOWNLOAD FRESHERS</Btn> : null}
        </>} />

      <div className="row row--between" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
        <Tabs<IntakeTab> label="School fees readiness" value={f.tab} onChange={tab} items={[
          { id: "coverage", label: "Fee configuration", count: coverage.uncovered ? `${vzNum(coverage.uncovered)} without` : undefined },
          { id: "applicants", label: "Applicants", count: vzNum(summary.freshers) },
        ]} />
        <div style={{ minWidth: 200 }}><Field id="sfr-session" label="Entry session">
          <select id="sfr-session" className="ctl" value={f.session} onChange={(e) => set("session", e.target.value)}>
            {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </Field></div>
      </div>

      {f.tab === "coverage" ? (
        <>
          <Tiles cls="grid--4" items={[
            ["Programmes", vzNum(coverage.programmes), null, "Undergraduate programmes, each read for a UTME (100 Level) and a Direct Entry (200 Level) entrant"],
            ["With a fee line in force", vzNum(coverage.covered), "var(--green-ink)", "A full-time FEE line reaches every entrant of the programme"],
            ["Without", vzNum(coverage.uncovered), coverage.uncovered ? "var(--red-ink)" : null, "Programmes where no line reaches an entrant: nothing is charged at a guess"],
            ["Without, with freshers admitted", vzNum(gapProgrammes), gapProgrammes ? "var(--red-ink)" : null, "Programmes whose freshers’ dashboards read “school fees not yet available”"],
          ]} />
          {gapProgrammes ? (
            <Note kind="bad" title={`${vzNum(gapProgrammes)} programme${gapProgrammes === 1 ? " has" : "s have"} freshers admitted and no fee line reaching them`}
              action={maySetFees ? <LinkBtn kind="primary" href={`/finance/fees?session=${encodeURIComponent(f.session)}`}>State the fees on Fee Setup</LinkBtn> : undefined}>
              Those freshers see &ldquo;{f.session} school fees not yet available&rdquo; on the applicant dashboard and cannot pay; while the gate is on the student portal stays shut to them.
              A fee line is &ldquo;published&rdquo; the moment it is in force for the session and the payment window is open — there is no separate publish step.
            </Note>
          ) : coverage.programmes ? <Note kind="ok" title="Every programme with freshers admitted has a fee line reaching them">A programme without one has no fresher of this session on the register yet.</Note> : null}

          <div className="grid grid--2">
            <Panel title="By faculty" right={`${coverage.byFaculty.length}`}>
              {coverage.byFaculty.length ? (
                <DTable pageSize={0} cols={["Faculty", "Programmes|num", "With fees|num", "Without|num"]}
                  rows={coverage.byFaculty.map((b) => [
                    <span key="f">{b.name ?? <Pil kind="warn">Programme not on the register</Pil>}</span>,
                    <span key="n" className="tnum">{vzNum(b.programmes)}</span>,
                    <span key="c" className="tnum">{vzNum(b.covered)}</span>,
                    <span key="u" className="tnum" style={b.uncovered ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{vzNum(b.uncovered)}</span>,
                  ])} />
              ) : <PBody><div className="sub2">None.</div></PBody>}
            </Panel>
            <Panel title="How a fee reaches a fresher">
              <PBody>
                <div className="sub2" style={{ lineHeight: 1.55 }}>
                  A fresher is charged what Fee Setup states for their session, level and entry mode: a UTME entrant at 100 Level, a Direct Entry entrant at 200 Level, each by
                  the programme&rsquo;s own lines or the faculty&rsquo;s or the University&rsquo;s, as the fee engine reads them. The fee is never typed against the student.
                  Once a line is in force and the window is open the applicant dashboard shows the fees and takes the payment through the payment gateway; the student portal
                  opens when {gate ? clearsOnWord(gate.clearsOn).toLowerCase() : "the first semester's fees are paid"} and verified. Matriculation and the register are untouched.
                </div>
              </PBody>
            </Panel>
          </div>

          <Panel title="Programmes" right={<label className="row row--tight sub2" style={{ gap: 6 }}><input type="checkbox" checked={uncoveredOnly} onChange={(e) => setUncoveredOnly(e.target.checked)} />Without a fee line only</label>}>
            {coverageRows.length ? (
              <DTable pageSize={25} cols={["Programme", "Faculty", "Entry|mid", "Level|num", "Fee lines|num", "Freshers admitted|num", "State|mid"]}
                texts={coverageRows.map((r) => `${r.programme} ${r.programmeCode} ${r.faculty ?? ""} ${r.entryMode}`)}
                rows={coverageRows.map((r) => [
                  <span key="p"><strong>{r.programme}</strong><div className="sub2 tnum">{r.programmeCode}</div></span>,
                  <span key="f">{r.faculty ?? "—"}</span>,
                  <span key="e">{entryWord(r.entryMode)}</span>,
                  <span key="l" className="tnum">{r.level}</span>,
                  <span key="n" className="tnum">{vzNum(r.lines)}</span>,
                  <span key="a" className="tnum" style={!r.covered && r.admitted ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{vzNum(r.admitted)}</span>,
                  <Pil key="s" kind={r.covered ? "ok" : r.admitted ? "bad" : "warn"}>{r.covered ? "Fees stated" : r.admitted ? "No fee line — freshers waiting" : "No fee line"}</Pil>,
                ])} />
            ) : <PBody><div className="sub2">{uncoveredOnly ? "Every programme entry has a fee line in force." : "No undergraduate programme on the register."}</div></PBody>}
          </Panel>
        </>
      ) : (
        <>
          {/* the figures, each a door */}
          <Tiles cls="grid--4" items={[
            ["Freshers on the register", vzNum(summary.freshers), null, `UTME and Direct Entry, admitted into ${f.session}`],
            ["Cleared for the portal", vzNum(summary.cleared), "var(--green-ink)", "The portal is open to them: fees paid as the gate asks, let through by the Bursary, or not gated"],
            ["Not cleared", vzNum(summary.notCleared), summary.notCleared ? "var(--red-ink)" : null, "Held on the applicant dashboard: an acceptance balance, or the fees not stated or unpaid"],
            ["Signed in to the student portal", vzNum(summary.signedIn ?? 0), null, `At least once · ${vzNum(summary.accountsOpened)} student account${summary.accountsOpened === 1 ? "" : "s"} opened`],
          ]} />
          <div className="grid grid--3" role="group" aria-label="Freshers by fee state">
            {FEE_STATES.map((s) => (
              <Door key={s} label={feeStateWord(s)} n={vzNum(feeN(s))} sub="by school fees" on={f.feeState === s} onClick={() => toggle("feeState", s)} colour={feeN(s) ? FEE_COLOUR[s] : undefined} />
            ))}
          </div>
          <div className="grid grid--3 mt-2" role="group" aria-label="Freshers by student portal state">
            {PORTAL_STATES.map((s) => (
              <Door key={s} label={portalStateWord(s)} n={vzNum(portalN(s))} sub="by student portal" on={f.portalState === s} onClick={() => toggle("portalState", s)} colour={portalN(s) ? PORTAL_COLOUR[s] : undefined} />
            ))}
          </div>

          {/* the filters */}
          <div className="scope" aria-label="Filters">
            <Sel id="sfr-fee" label="Fee state" value={f.feeState} any="Every state" opts={FEE_STATES.map((s) => [s, feeStateWord(s)])} onChange={(v) => toggle("feeState", v === f.feeState ? "" : v)} />
            <Sel id="sfr-portal" label="Student portal" value={f.portalState} any="Every state" opts={PORTAL_STATES.map((s) => [s, portalStateWord(s)])} onChange={(v) => go({ ...f, portalState: v })} />
            <div className="scope__f"><Field id="sfr-fac" label="Faculty">
              <SearchSelect id="sfr-fac" value={f.faculty} allLabel="All faculties" placeholder="All faculties"
                options={faculties.map((x) => ({ value: x.code, label: x.name }))} onChange={(v) => set("faculty", v)} />
            </Field></div>
            <div className="scope__f"><Field id="sfr-prog" label="Programme">
              <SearchSelect id="sfr-prog" value={f.programme} allLabel={f.faculty ? "All in this faculty" : "All programmes"} placeholder="Search a programme…"
                options={progs.map((p) => ({ value: p.code, label: p.name }))}
                onChange={(v) => go({ ...f, programme: v, faculty: v ? facultyOf(v) || f.faculty : f.faculty })} />
            </Field></div>
            <Sel id="sfr-entry" label="Entry mode" value={f.entryMode} any="All" opts={[["UTME", "UTME"], ["DIRECT_ENTRY", "Direct Entry"]]} onChange={(v) => go({ ...f, entryMode: v })} />
            <div className="scope__f grow"><Field id="sfr-q" label="Search">
              <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ ...f, q: q.trim() }); }}>
                <input id="sfr-q" className="ctl" value={q} maxLength={80} onChange={(e) => setQ(e.target.value)} placeholder="Search by admission number, matriculation number or name" />
                <Btn kind="primary" type="submit">Search</Btn>
                <Btn kind="ghost" onClick={clear}>Reset</Btn>
              </form>
            </Field></div>
          </div>

          <Panel title="Filters applied" right={applied.length ? <Btn kind="ghost" size="sm" onClick={clear}>Clear all filters</Btn> : "None — every fresher of the session"}>
            <PBody>
              {applied.length ? (
                <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
                  {applied.map((a) => (
                    <span key={a.key} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px", gap: 6 }}>
                      <span className="sub2">{a.label}:</span> <b>{a.value}</b>
                      <button type="button" aria-label={`Remove ${a.label}`} title={`Remove ${a.label}`}
                        onClick={() => { if (a.key === "q") setQ(""); go({ ...withIntakeChange(f, a.key, ""), tab: "applicants" }); }}
                        style={{ border: 0, background: "none", cursor: "pointer", fontSize: 16, lineHeight: 1, padding: "0 4px", color: "var(--muted)" }}>&times;</button>
                    </span>
                  ))}
                </div>
              ) : null}
              <div className={applied.length ? "mt-2" : undefined}><b className="tnum">Total: {vzNum(list.total)} fresher{list.total === 1 ? "" : "s"}</b></div>
            </PBody>
          </Panel>

          <Panel title="Freshers" right={list.total ? `Page ${list.page + 1} of ${pages} · ${vzNum(list.total)} in all · names A–Z` : "None"}>
            {list.rows.length ? (
              <DTable pageSize={0} cols={["S/N|num", "Student", "Programme", "Due|num", "Paid|num", "Balance|num", "School fees|mid", "Student portal", "|num"]} rows={list.rows.map(line)} />
            ) : (
              <PBody><Note kind="info" title="No freshers found">No fresher of {f.session} matches the filters.</Note></PBody>
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
          <div className="sub2">The school fees are the fee engine&rsquo;s for the student&rsquo;s session, level and entry mode; paid means a payment the payment service confirmed, and a reference still
            awaiting the bank never counts. The student portal&rsquo;s state is read afresh on every request: held while an acceptance fee balance is owed (it comes first), or while the fees are not
            stated or not paid as the gate asks; cleared once they are; open by a Bursary exception for a stated time; or open where the gate does not apply (a matriculated or returning student,
            an earlier cohort, a record with no applicant account to pay from, the gate off). Each download is recorded.</div>
        </>
      )}
    </>
  );
}
