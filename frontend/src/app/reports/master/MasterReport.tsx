"use client";

/**
 * V650: the Master University Report — the scope bar and the report's filters; the management view (the session, the semester,
 * the scope and the figures that matter, each tile opening its students); the drill-down from the faculties to a department, a
 * programme, a level and its students; the charts beside the figures they draw; every section of the report as the server
 * defines it (the same tables the PDF prints and the Excel carries); GENERATE PDF, GENERATE EXCEL and both, each step shown as it
 * is done; the reports issued before. Every figure is the server's.
 */
import Link from "next/link";
import { useMemo, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { formatDocDateTime } from "@/lib/document/institution";
import { downloadBlob } from "@/lib/exportbrand";
import {
  CARD_WORDS, FEE_STATUS_WORDS, FEE_WORDS, GST_WORDS, PERMIT_WORDS, PRESETS, PSTATUS_WORDS, REG_WORDS, STATUS_WORDS, byDim, cellText, filterLines, kpiText, kpis,
  masterQuery, presetPeriod, semWord, universityRow, type Filters, type HistoryRow, type MasterOptions, type MasterSummary, type Page, type Section, type StudentRow,
  type SummaryRow,
} from "@/lib/master-report";
import { reportCharts } from "@/lib/master-charts";
import { printMasterReport, type ReportPackage } from "@/lib/master-report-pdf";

const BASE = "/api/bff/api/v1/reports/master";
const TITLE = "Master Academic, Finance & Student Report";

function Svg({ svg }: { svg: string }) {
  // drawn by lib/master-charts from the server's figures, every label escaped there
  return <div className="card" style={{ padding: 6, minWidth: 0 }} dangerouslySetInnerHTML={{ __html: svg }} />;
}

function SectionTable({ s }: { s: Section }) {
  const cols = ["S/N|num", ...s.headers.map((h, i) => (s.kinds[i] === "INT" || s.kinds[i] === "MONEY" ? `${h}|num` : h))];
  return (
    <DTable pageSize={s.rows.length > 60 ? 50 : 0} noPrint cols={cols}
      rows={s.rows.map((r, i) => [<span key="sn" className="tnum">{i + 1}</span>, ...s.headers.map((_, c) => (
        <span key={c} className={s.kinds[c] === "INT" || s.kinds[c] === "MONEY" ? "tnum" : undefined}>{cellText(r[c] ?? null, s.kinds[c] ?? "TEXT")}</span>))])} />
  );
}

export function MasterReport({ scope, structure, sessions, ceiling, options, filters, actor, summary, problem, students, history }: {
  scope: Scope; structure: ScopeStructure; sessions: string[]; ceiling: Ceiling; options: MasterOptions; filters: Filters; actor: string | null;
  summary: MasterSummary | null; problem: Problem | null; students: Page<StudentRow> | null; history: HistoryRow[];
}) {
  const pathname = usePathname();
  const params = useSearchParams();
  const queryNav = useQueryNav();
  const [steps, setSteps] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [semesters, setSemesters] = useState(false);
  const [preset, setPreset] = useState(filters.from || filters.to ? "CUSTOM" : "");
  const [err, setErr] = useState<Problem | null>(null);
  const charts = useMemo(() => (summary ? reportCharts(summary) : {}), [summary]);
  const a = summary ? universityRow(summary) : undefined;

  /** the address with these keys set (and the list closed unless asked) */
  const href = (set: Record<string, string | null>, keepList = false) => {
    const p = new URLSearchParams(params.toString());
    if (!keepList) { p.delete("list"); p.delete("page"); }
    for (const [k, v] of Object.entries(set)) { if (v) p.set(k, v); else p.delete(k); }
    return `${pathname}?${p.toString()}`;
  };
  const go = (set: Record<string, string | null>) => queryNav(href(set));
  /** the students behind a figure: the figure's own filters, the scope as it stands */
  const open = (set: Record<string, string | null | undefined>) => {
    const p = new URLSearchParams(params.toString());
    for (const k of ["fee", "reg", "gst", "eps", "card", "permit", "sex"]) p.delete(k);
    for (const [k, v] of Object.entries(set)) { if (v) p.set(k, v); else p.delete(k); }
    p.set("list", "1");
    p.delete("page");
    return `${pathname}?${p.toString()}`;
  };

  function choosePreset(v: string) {
    setPreset(v);
    if (v === "" ) { go({ from: null, to: null }); return; }
    if (v === "CUSTOM") return;
    const b = options.bounds.find((x) => x.session === scope.session);
    const period = presetPeriod(v, new Date(), { sessionFrom: b?.starts_on ?? null, semesterFrom: scope.sem === "2" ? b?.second_from ?? null : b?.first_from ?? null });
    if (period) go({ from: period.from, to: period.to });
    else notify("That period has no start date on the calendar; choose the dates.");
  }

  async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; setErr(p); notifyProblem(p); return null; }
    return j as T;
  }

  async function generate(formats: ("PDF" | "XLSX")[]) {
    if (!summary || !a) return;
    setErr(null);
    // a window opened at the click, before anything is read, so the browser lets the PDF print into it
    const w = formats.includes("PDF") ? window.open("", "_blank") : null;
    if (w) w.document.write(`<p style="font:14px system-ui,sans-serif;padding:24px">Preparing the ${TITLE.toLowerCase()}…</p>`);
    setBusy(true);
    const done: string[] = [];
    const step = (s: string) => { done.push(s); setSteps([...done]); };
    let reference: string | null = null;
    try {
      step("Issuing the report reference…");
      const meta = filterLines(filters, options);
      const issued = await post<{ reference: string }>("/issue", {
        title: TITLE,
        filters: { ...summary.filters, scope: summary.scope },
        figures: Object.fromEntries(kpis(summary).map((k) => [k.label, k.value])),
        rows: a.total,
        sections: summary.sections.map((s) => s.key),
      }, `Master report generated (${formats.join(" + ")})`);
      if (!issued) { w?.close(); return; }
      reference = issued.reference;
      step(`Reference ${reference}`);
      const q = masterQuery(scope, filters, { reference, semesters: semesters ? "true" : undefined });
      let rows = 0;
      if (formats.includes("PDF")) {
        step("Preparing data and calculating statistics…");
        const r = await fetch(`${BASE}/package?${q}`);
        const pkg = (await r.json().catch(() => null)) as MasterSummary | Problem | null;
        if (!r.ok || !pkg || !("sections" in pkg)) { const p = (pkg as Problem) ?? { status: r.status, title: r.statusText }; setErr(p); notifyProblem(p); throw new Error("package"); }
        step("Preparing charts…");
        const ch = reportCharts(pkg);
        rows = pkg.sections.reduce((n, s) => n + s.rows.length, 0);
        const period = filters.from || filters.to ? `${filters.from || "the start of the session"} – ${filters.to || "today"}` : `The whole of ${scope.session}`;
        const report: ReportPackage = {
          reference, title: TITLE, generatedBy: actor, generatedAt: new Date().toISOString(), session: scope.session, semester: semWord(scope.sem), scope: pkg.scope,
          period,
          meta: [["Academic session", scope.session], ["Semester", semWord(scope.sem)], ["Scope", pkg.scope], ["Report period", period], ["Generated by", actor ?? ""],
            ["Report reference", reference], ["Figures read", formatDocDateTime(pkg.at)], ["Amounts", pkg.money === "ALL" ? "All amounts" : pkg.money === "GST" ? "GST and EPS amounts only" : "No amounts"],
            ...meta],
          kpis: kpis(pkg).map((k) => ({ label: k.label, value: kpiText(k) })),
          parts: pkg.sections.filter((s) => s.key !== "executive").map((s) => ({ section: s, charts: ch[s.key] ?? [] })),
        };
        step("Generating PDF…");
        await printMasterReport(report, w);
      }
      if (formats.includes("XLSX")) {
        step("Generating Excel (streamed from the database)…");
        const r = await fetch(`${BASE}/workbook?${q}`);
        if (!r.ok) {
          const j = await r.json().catch(() => null);
          const p = (j as Problem) ?? { status: r.status, title: r.statusText };
          setErr(p); notifyProblem(p); throw new Error("workbook");
        }
        const blob = await r.blob();
        downloadBlob(blob, `master-report-${reference.replace(/\//g, "-")}.xlsx`);
        rows = rows || a.total;
      }
      await post("/finish", { reference, status: "COMPLETED", formats, rows }, `Master report ${reference} completed`);
      step("Completed");
      notify(`${reference} generated`);
    } catch {
      if (reference) await post("/finish", { reference, status: "FAILED", formats, rows: 0 }, `Master report ${reference} failed`);
      step("Failed — nothing was issued beyond the reference, which is marked failed");
      w?.close();
    } finally {
      setBusy(false);
    }
  }

  const select = (key: keyof Filters, label: string, words: Record<string, string>) => (
    <Field id={`mr-${key}`} label={label}>
      <select id={`mr-${key}`} className="ctl" value={filters[key]} onChange={(e) => go({ [key]: e.target.value || null })}>
        <option value="">All</option>
        {Object.entries(words).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
      </select>
    </Field>
  );

  // the drill-down: the faculties, a faculty's departments, a department's programmes, a programme's levels — one level below the scope
  const drill: { rows: SummaryRow[]; label: (r: SummaryRow) => string; next: (r: SummaryRow) => Record<string, string | null>; what: string } | null = !summary ? null
    : !scope.fac ? { rows: byDim(summary, "FACULTY"), label: (r) => r.faculty ?? "(none)", next: (r) => ({ fac: r.faculty_code }), what: "Faculty" }
      : !scope.dept ? { rows: byDim(summary, "DEPARTMENT").filter((r) => r.faculty_code === scope.fac), label: (r) => r.department ?? "(none)", next: (r) => ({ dept: r.dept_code }), what: "Department" }
        : !scope.prog ? { rows: byDim(summary, "PROGRAMME").filter((r) => r.dept_code === scope.dept), label: (r) => r.programme ?? "(none)", next: (r) => ({ prog: r.programme_code }), what: "Programme" }
          : !scope.level ? { rows: byDim(summary, "PROGRAMME_LEVEL").filter((r) => r.programme_code === scope.prog), label: (r) => (r.level == null ? "Not stated" : `${r.level} Level`), next: (r) => ({ level: r.level == null ? null : String(r.level) }), what: "Level" }
            : null;

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="students" count={a?.total ?? 0} of={a?.total ?? 0} />

      <Panel title="Filters">
        <PBody>
          <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
            <Field id="mr-type" label="Programme type">
              <select id="mr-type" className="ctl" value={filters.type} onChange={(e) => go({ type: e.target.value || null })}>
                <option value="">All</option>
                {options.types.map((t) => <option key={t.code} value={t.code}>{t.label}</option>)}
              </select>
            </Field>
            {select("sex", "Gender", { M: "Male", F: "Female", U: "Not stated" })}
            {options.modes.length > 1 ? (
              <Field id="mr-mode" label="Study mode">
                <select id="mr-mode" className="ctl" value={filters.mode} onChange={(e) => go({ mode: e.target.value || null })}>
                  <option value="">All</option>
                  {options.modes.map((m) => <option key={m} value={m.toUpperCase()}>{m}</option>)}
                </select>
              </Field>
            ) : null}
            {options.centres.length > 1 ? (
              <Field id="mr-centre" label="Centre">
                <select id="mr-centre" className="ctl" value={filters.centre} onChange={(e) => go({ centre: e.target.value || null })}>
                  <option value="">All</option>
                  {options.centres.map((m) => <option key={m} value={m.toUpperCase()}>{m}</option>)}
                </select>
              </Field>
            ) : null}
            {select("fee", "School fees", FEE_WORDS)}
            {select("reg", "Registration", REG_WORDS)}
            {select("gst", "GST", GST_WORDS)}
            {select("eps", "EPS", GST_WORDS)}
            {select("card", "Examination card", CARD_WORDS)}
            {select("permit", "GST permit", PERMIT_WORDS)}
          </div>
          {options.money !== "NONE" ? (
            <div className="row" style={{ gap: 10, flexWrap: "wrap", alignItems: "flex-end", marginTop: 8 }}>
              <Field id="mr-preset" label="Transaction period">
                <select id="mr-preset" className="ctl" value={preset} onChange={(e) => choosePreset(e.target.value)}>
                  {PRESETS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </Field>
              {preset === "CUSTOM" ? (
                <>
                  <Field id="mr-from" label="From"><input id="mr-from" type="date" className="ctl" value={filters.from} onChange={(e) => go({ from: e.target.value || null })} /></Field>
                  <Field id="mr-to" label="To"><input id="mr-to" type="date" className="ctl" value={filters.to} onChange={(e) => go({ to: e.target.value || null })} /></Field>
                </>
              ) : filters.from || filters.to ? <span className="sub2">{filters.from} to {filters.to}</span> : null}
              <Field id="mr-purpose" label="Payment purpose">
                <select id="mr-purpose" className="ctl" value={filters.purpose} onChange={(e) => go({ purpose: e.target.value || null })}>
                  <option value="">All</option>
                  {options.purposes.map((p) => <option key={p.code} value={p.code}>{p.label}</option>)}
                </select>
              </Field>
              {select("pstatus", "Payment status", PSTATUS_WORDS)}
              <Field id="mr-channel" label="Payment channel">
                <select id="mr-channel" className="ctl" value={filters.channel} onChange={(e) => go({ channel: e.target.value || null })}>
                  <option value="">All</option>
                  {options.channels.map((c) => <option key={c} value={c}>{c}</option>)}
                </select>
              </Field>
            </div>
          ) : null}
          {filterLines(filters, options).length ? (
            <div className="row" style={{ gap: 6, flexWrap: "wrap", marginTop: 8 }}>
              {filterLines(filters, options).map(([k, v]) => <Pil key={k} kind="info">{k}: {v}</Pil>)}
              <LinkBtn kind="ghost" href={href(Object.fromEntries(["type", "sex", "astatus", "route", "mode", "centre", "fee", "reg", "gst", "eps", "card", "permit", "from", "to", "purpose", "pstatus", "channel"].map((k) => [k, null])))}>Clear filters</LinkBtn>
            </div>
          ) : null}
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}
      {err ? <ProblemNotice problem={err} /> : null}

      {summary && a ? (
        <>
          <Note kind="info" title={`${scope.session} · ${semWord(scope.sem)} · ${summary.scope}`}>
            {a.total.toLocaleString("en-GB")} students{summary.transactions ? `; ${summary.transactions.total.transactions.toLocaleString("en-GB")} transactions in the period, ₦${Number(summary.transactions.total.revenue).toLocaleString("en-GB", { maximumFractionDigits: 0 })} revenue` : ""}.
            {" "}Figures read {formatDocDateTime(summary.at)}. Every figure opens its students.
          </Note>
          <Tiles cls="grid--4" items={kpis(summary).map((k) => [k.label, kpiText(k), null, null, k.open ? open(k.open as Record<string, string>) : undefined] as [string, string, null, null, string | undefined])} />

          <Panel title="Generate the report" right={summary.money === "ALL" ? "All amounts" : summary.money === "GST" ? "GST and EPS amounts" : "No amounts for your office"}>
            <PBody>
              <div className="row" style={{ gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                <Btn kind="primary" disabled={busy} busyLabel="Generating…" onClick={() => generate(["PDF"])}>Generate PDF</Btn>
                <Btn kind="primary" disabled={busy} busyLabel="Generating…" onClick={() => generate(["XLSX"])}>Generate Excel</Btn>
                <Btn kind="secondary" disabled={busy} busyLabel="Generating…" onClick={() => generate(["PDF", "XLSX"])}>Generate PDF + Excel</Btn>
                <label className="row row--inline" style={{ gap: 6 }}>
                  <input type="checkbox" checked={semesters} onChange={(e) => setSemesters(e.target.checked)} />
                  <span className="sub2">Compare the semesters (a second pass; slower)</span>
                </label>
              </div>
              {steps.length ? <ol className="sub2" style={{ margin: "8px 0 0 18px" }}>{steps.map((s, i) => <li key={i}>{s}</li>)}</ol> : null}
              <div className="sub2" style={{ marginTop: 6 }}>The PDF and the Excel are drawn from the same sections at the same moment, under one RPT reference; the PDF lists up to 2,500 rows a list, the Excel every row.</div>
            </PBody>
          </Panel>

          {students ? (
            <Panel title={`Students — ${students.total.toLocaleString("en-GB")}`} right={<LinkBtn kind="ghost" href={href({}, false)}>Close</LinkBtn>}>
              {students.rows.length ? (
                <DTable pageSize={0} noPrint cols={["S/N|num", "Student", "Programme", "Level|num", "School fees", "Registration", "GST", "EPS", "Card", "Permit"]}
                  rows={students.rows.map((r, i) => [
                    <span key="n" className="tnum">{(students.page - 1) * students.size + i + 1}</span>,
                    <span key="s"><Link className="lnk" href={`/students/${r.student_id}`}>{r.surname}, {r.other_names}</Link><div className="sub2 tnum">{r.matric_no ?? r.jamb_no ?? ""}</div></span>,
                    <span key="p">{r.programme ?? ""}<div className="sub2">{r.department ?? ""}</div></span>,
                    <span key="l" className="tnum">{r.level ?? ""}</span>,
                    <span key="f">{FEE_STATUS_WORDS[r.fee_status] ?? r.fee_status}{r.outstanding != null && Number(r.outstanding) > 0 ? <div className="sub2 tnum">owes ₦{Number(r.outstanding).toLocaleString("en-GB")}</div> : null}</span>,
                    <span key="r">{r.registered ? "Registered" : r.paid_not_registered ? "Paid, not registered" : "Not registered"}</span>,
                    <span key="g">{STATUS_WORDS[r.gst_status] ?? r.gst_status}</span>,
                    <span key="e">{STATUS_WORDS[r.eps_status] ?? r.eps_status}</span>,
                    <span key="c">{r.card_issued ? "Issued" : r.card_eligible ? "Eligible" : "—"}</span>,
                    <span key="m">{r.permit_printed ? "Printed" : r.permit_eligible ? "Eligible" : "—"}</span>,
                  ])} />
              ) : <PBody><div className="sub2">No student matches.</div></PBody>}
              <PBody>
                <div className="row" style={{ gap: 8 }}>
                  {students.page > 1 ? <LinkBtn kind="ghost" href={href({ page: String(students.page - 1) }, true)}>Previous</LinkBtn> : null}
                  <span className="sub2">Page {students.page} of {Math.max(1, Math.ceil(students.total / students.size))} · names A to Z</span>
                  {students.page * students.size < students.total ? <LinkBtn kind="ghost" href={href({ page: String(students.page + 1) }, true)}>Next</LinkBtn> : null}
                </div>
              </PBody>
            </Panel>
          ) : null}

          {drill && drill.rows.length ? (
            <Panel title={`Drill down — by ${drill.what.toLowerCase()}`} right="Each name opens the next level; each figure its students">
              <DTable pageSize={0} noPrint cols={[drill.what, "Students|num", "Fees paid|num", "Not paid|num", "Paid not registered|num", "GST paid|num", "EPS paid|num", "Cards issued|num", "Permits printed|num"]}
                rows={[...drill.rows].sort((x, y) => drill.label(x).localeCompare(drill.label(y))).map((r) => {
                  const scoped = drill.next(r);
                  const at = (extra: Record<string, string>) => open({ ...scoped, ...extra });
                  const n = (v: number, extra: Record<string, string>) => (v ? <Link key={JSON.stringify(extra)} className="lnk tnum" href={at(extra)}>{v.toLocaleString("en-GB")}</Link> : <span key={JSON.stringify(extra)} className="sub2 tnum">0</span>);
                  return [
                    <Link key="name" className="lnk" href={href(scoped)}>{drill.label(r)}</Link>,
                    n(r.total, {}), n(r.fees_paid, { fee: "PAID" }), n(r.fees_not_paid, { fee: "NOT_PAID" }), n(r.paid_not_registered, { reg: "PAID_NOT_REGISTERED" }),
                    n(r.gst_paid, { gst: "PAID" }), n(r.eps_paid, { eps: "PAID" }), n(r.card_issued, { card: "ISSUED" }), n(r.permit_printed, { permit: "PRINTED" }),
                  ];
                })} />
            </Panel>
          ) : null}

          {summary.sections.map((s) => (
            <Panel key={s.key} title={s.title} right={s.rows.length > 1 ? `${s.rows.length.toLocaleString("en-GB")} rows` : undefined}>
              {charts[s.key]?.length ? (
                <PBody><div className="grid grid--2" style={{ alignItems: "start" }}>{charts[s.key].map((c, i) => <Svg key={i} svg={c} />)}</div></PBody>
              ) : null}
              <SectionTable s={s} />
              {s.note ? <PBody><div className="sub2">{s.note}</div></PBody> : null}
            </Panel>
          ))}
        </>
      ) : null}

      <Panel title="Report history" right={`${history.length} issued`}>
        {history.length ? (
          <DTable pageSize={10} noPrint cols={["Reference", "Status", "Formats", "Scope", "Rows|num", "Generated", "By"]}
            rows={history.map((h) => [
              <span key="r" className="tnum">{h.reference}</span>,
              <Pil key="s" kind={h.status === "COMPLETED" ? "ok" : h.status === "FAILED" ? "bad" : h.status === "GENERATING" ? "warn" : "grey"}>{h.status.charAt(0) + h.status.slice(1).toLowerCase()}</Pil>,
              <span key="f">{(h.formats ?? "").replace(/[{}]/g, "").replace(",", " + ") || "—"}</span>,
              <span key="sc" className="sub2">{h.scope ?? ""}</span>,
              <span key="n" className="tnum">{h.row_count == null ? "" : Number(h.row_count).toLocaleString("en-GB")}</span>,
              <span key="g" className="sub2">{formatDocDateTime(h.generated_at)}</span>,
              <span key="b" className="sub2">{h.generated_by ?? ""} ({h.actor_office})</span>,
            ])} />
        ) : <PBody><div className="sub2">No master report has been generated yet.</div></PBody>}
      </Panel>
    </>
  );
}
