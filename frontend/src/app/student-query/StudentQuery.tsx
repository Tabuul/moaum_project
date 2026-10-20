"use client";

/**
 * The Student Query (V469): one query builder for every office. Student type first — the cards count each type within the
 * office's scope and apply it in one click — then the filters that type has (admission route → centre → faculty →
 * department → programme → session → level → status), each list holding only what the type and the filters above it
 * contain; the quick queries; the filters applied, each removable; a search on the server as one types; the total and the
 * list, names A–Z; and the same selection as a branded workbook or PDF headed with the student type. Every number and every
 * row comes from the one engine; the office's scope is the server's.
 */
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  COMPLETION_WORD, PRESETS, RECOMMENDATION_WORD, SPILLOVER_WORD, activeFilters, spilloverWord, applyPreset, awardWord, exportHeading, levelWord, modeWord, queryString, statusWord,
  typeStudentWord, withChange, EMPTY_QUERY, type Breakdown, type QueryFilters, type QueryOptions, type QueryPage, type QueryRow, type QuerySummary,
} from "@/lib/student-query";

type Group = "faculty" | "department" | "programme" | "";

const vzNum = (n: number) => Number(n).toLocaleString("en-GB");

function Sel({ id, label, value, onChange, any, opts, disabled, hint }: {
  id: string; label: string; value: string; onChange: (v: string) => void; any: string; opts: [string, string][]; disabled?: boolean; hint?: string;
}) {
  return (
    <div className="scope__f"><Field id={id} label={label} hint={hint}>
      <select id={id} className="ctl" value={value} disabled={disabled} onChange={(e) => onChange(e.target.value)}>
        <option value="">{any}</option>
        {opts.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
      </select>
    </Field></div>
  );
}

export function StudentQuery({ filters, group, options, summary, list }: {
  filters: QueryFilters; group: Group; options: QueryOptions; summary: QuerySummary; list: QueryPage;
}) {
  const queryNav = useQueryNav();
  const f = filters;
  const o = options;
  const boundType = o.scope.programmeType ?? null;
  const [q, setQ] = useState(f.q);
  const [busy, setBusy] = useState(false);

  const go = (next: QueryFilters, extra: Record<string, string | number | undefined> = {}) => queryNav(`/student-query?${queryString(next, extra)}`);
  const set = (key: keyof QueryFilters, value: string) => go(withChange(f, key, value), { group: group || undefined });

  // the search runs on the server as one types, a moment after the last key
  useEffect(() => {
    const t = q.trim();
    if (t === f.q) return;
    const timer = setTimeout(() => go({ ...f, q: t }, { group: group || undefined }), 450);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q]);

  const typeName = (code: string | null) => (code ? o.types.find((t) => t.code === code)?.name ?? code : null);
  const faculties = useMemo(() => [...new Map(o.programmes.map((p) => [p.faculty_code, p.faculty])).entries()].sort((a, b) => a[1].localeCompare(b[1])), [o.programmes]);
  const depts = useMemo(() => [...new Map(o.programmes.filter((p) => !f.fac || p.faculty_code === f.fac).map((p) => [p.dept_code, p.department])).entries()].sort((a, b) => a[1].localeCompare(b[1])), [o.programmes, f.fac]);
  const progs = useMemo(() => o.programmes.filter((p) => (!f.fac || p.faculty_code === f.fac) && (!f.dept || p.dept_code === f.dept)).sort((a, b) => a.programme.localeCompare(b.programme)), [o.programmes, f.fac, f.dept]);
  const facultyBound = o.scope.kind === "FACULTY" || o.scope.kind === "DEPARTMENT";
  const deptBound = o.scope.kind === "DEPARTMENT";
  const isJupeb = f.type === "JUPEB";
  const isPrelim = f.type === "PRELIMINARY";
  const isPg = f.type === "POSTGRADUATE";
  const applied = activeFilters(f, o);
  const pages = Math.max(1, Math.ceil(list.total / list.size));
  const heading = exportHeading(f, o);

  /* the columns: the standard list, the same on the screen and in the export */
  const HEAD = ["S/N", "Student Name", "Matric Number", "JAMB Number", "Application Number", "Programme Type", "Admission Route", "Study Mode", "Centre",
    "Faculty", "Department", "Programme", "Level", "Admission Session", "Current Session", "Status", "Course Registration", ...(f.fees ? ["School Fees"] : [])];
  const programmeOf = (r: QueryRow) => r.source === "JUPEB" ? (r.jupeb_combination ? `JUPEB — ${r.jupeb_combination}` : "JUPEB")
    : r.programme_is_target ? `${r.prelim_name ?? "Preliminary"} → ${r.programme ?? "target not set"}` : (r.programme ?? "—");
  const line = (r: QueryRow, i: number) => [
    i + 1, `${r.surname}, ${r.other_names}`, r.matric_no ?? "", r.jamb_no ?? "", r.application_no ?? "",
    r.programme_type_name ?? "Requires classification", r.admission_route_name ?? "", modeWord(r.study_mode), r.centre_name ?? "",
    r.faculty ?? "", r.department ?? "", programmeOf(r), levelWord(r) + (spilloverWord(r.spillover_state) ? ` (${spilloverWord(r.spillover_state)?.short})` : ""), r.admission_session ?? "", r.current_session ?? "", statusWord(r.status),
    regWord(r), ...(f.fees ? [feeWord(r.fee_status)] : []),
  ];

  async function allRows(): Promise<QueryRow[]> {
    const out: QueryRow[] = [];
    for (let p = 0; p * 500 < list.total && p < 200; p++) {
      const r = await fetch(`/api/bff/api/v1/stats/students/query?${queryString(f, { page: p, size: 500 })}`, { cache: "no-store" });
      if (!r.ok) throw (await r.json().catch(() => ({ status: r.status, title: r.statusText })));
      const j = (await r.json()) as QueryPage;
      out.push(...j.rows);
      if (j.rows.length < 500) break;
    }
    return out;
  }
  async function exportAs(kind: "xlsx" | "pdf") {
    setBusy(true);
    try {
      const rows = await allRows();
      const serial = docSerial("SQ");
      if (kind === "xlsx") {
        const blob = await brandedXlsx(heading.title, HEAD, rows.map(line), { sheetName: "Students", serial, sub: heading.sub, meta: heading.meta });
        downloadBlob(blob, `students-${(f.type || "all-types").toLowerCase()}.xlsx`);
      } else {
        brandedPrint(heading.title, heading.sub, HEAD, rows.map(line), serial, { meta: heading.meta, orientation: "landscape" });
      }
      notify(`${rows.length} student${rows.length === 1 ? "" : "s"} exported`);
    } catch (e) { const pr = e as { status?: number; title?: string }; notifyProblem({ status: pr?.status ?? 500, title: pr?.title ?? "The export could not be prepared." }); }
    finally { setBusy(false); }
  }

  const cards = summary.types;
  const breakdown: Breakdown[] = group === "faculty" ? summary.byFaculty : group === "department" ? summary.byDepartment : group === "programme" ? summary.byProgramme : [];

  return (
    <>
      <PageHead title="Student query" description={`${o.scope.label}. Choose the student type, then narrow by the filters it has. Every figure and row is read on the server within your office's scope.`}
        actions={<>
          <Btn kind="primary" disabled={busy || !list.total} onClick={() => void exportAs("xlsx")}>{busy ? "Preparing…" : "Export Excel"}</Btn>
          <Btn kind="secondary" disabled={busy || !list.total} onClick={() => void exportAs("pdf")}>Export PDF</Btn>
          {o.classifies ? <LinkBtn href="/student-query/classification">Classification</LinkBtn> : null}
        </>} />

      {/* the student types as doors */}
      <div className="grid grid--4" role="group" aria-label="Students by programme type">
        {boundType ? null : (
          <button type="button" className="tile stat-tile" onClick={() => set("type", "")} aria-pressed={!f.type}
            style={{ textAlign: "left", font: "inherit", border: !f.type ? "2px solid var(--chrome)" : undefined }}>
            <div className="eyebrow">Total students</div>
            <div className="n tnum">{vzNum(summary.total)}</div>
            <div className="c">All student types{summary.requiresClassification ? ` · ${vzNum(summary.requiresClassification)} require classification` : ""}</div>
          </button>
        )}
        {cards.map((t) => (
          <button key={t.code} type="button" className="tile stat-tile" onClick={() => set("type", boundType ? boundType : t.code)} aria-pressed={f.type === t.code}
            style={{ textAlign: "left", font: "inherit", border: f.type === t.code ? "2px solid var(--chrome)" : undefined }} title={t.description ?? undefined}>
            <div className="eyebrow">{t.name}</div>
            <div className="n tnum">{vzNum(t.count)}</div>
            <div className="c">{typeStudentWord(t.name)}s</div>
          </button>
        ))}
        {!boundType && summary.requiresClassification ? (
          <button type="button" className="tile stat-tile" onClick={() => go({ ...EMPTY_QUERY, session: f.session, classification: "REQUIRES_CLASSIFICATION" })}
            style={{ textAlign: "left", font: "inherit", border: f.classification === "REQUIRES_CLASSIFICATION" ? "2px solid var(--amber-ink)" : undefined }}>
            <div className="eyebrow">Requires classification</div>
            <div className="n tnum" style={{ color: "var(--amber-ink)" }}>{vzNum(summary.requiresClassification)}</div>
            <div className="c">Counted in no type until decided</div>
          </button>
        ) : null}
      </div>

      {/* the filters: student type first, then what that type has, each list within the ones above it */}
      <div className="scope" aria-label="Filters">
        <Sel id="sq-type" label="Student type" value={f.type} any={boundType ? typeName(boundType) ?? "" : "All student types"} disabled={!!boundType}
          opts={boundType ? [] : o.types.map((t) => [t.code, t.name])} onChange={(v) => set("type", v)} />
        {o.routes.length ? <Sel id="sq-route" label="Admission route" value={f.route} any="All" opts={o.routes.map((r) => [r.code, r.name])} onChange={(v) => set("route", v)} /> : null}
        {o.centres.length > 1 || f.centre ? <Sel id="sq-centre" label="Centre" value={f.centre} any="All" opts={o.centres.map((c) => [c.code, c.name])} onChange={(v) => set("centre", v)} /> : null}
        {isJupeb ? null : (
          <>
            <Sel id="sq-fac" label={isPrelim ? "Faculty (of the target)" : "Faculty"} value={facultyBound ? (o.scope.faculty ?? f.fac) : f.fac} any={facultyBound ? (faculties[0]?.[1] ?? "Your faculty") : "All faculties"}
              disabled={facultyBound} opts={facultyBound ? [] : faculties} onChange={(v) => set("fac", v)} />
            <Sel id="sq-dept" label="Department" value={deptBound ? "" : f.dept} any={deptBound ? (depts[0]?.[1] ?? "Your department") : "All departments"}
              disabled={deptBound} opts={deptBound ? [] : depts} onChange={(v) => set("dept", v)} />
            <Sel id="sq-prog" label={isPrelim ? "Target programme" : "Programme"} value={f.prog} any="All programmes" opts={progs.map((p) => [p.programme_code, p.programme])} onChange={(v) => set("prog", v)} />
          </>
        )}
        {isPg || (f.pgAward && !isJupeb) ? <Sel id="sq-award" label="PG type" value={f.pgAward} any="All" opts={o.pgAwards.map((a) => [a, awardWord(a)])} onChange={(v) => set("pgAward", v)} /> : null}
        {isPrelim || f.prelimRoute ? <Sel id="sq-prelim" label="Preliminary type" value={f.prelimRoute} any="All" opts={o.prelimRoutes.map((r) => [r.code, r.name])} onChange={(v) => set("prelimRoute", v)} /> : null}
        {isJupeb ? (
          <>
            <Sel id="sq-comb" label="JUPEB combination" value={f.jupebCombination} any="All" opts={o.jupebCombinations.map((c) => [c.id, c.name])} onChange={(v) => set("jupebCombination", v)} />
            <Sel id="sq-subj" label="JUPEB subject" value={f.jupebSubject} any="Any" opts={o.jupebSubjects.map((s) => [s.id, `${s.code} — ${s.title}`])} onChange={(v) => set("jupebSubject", v)} />
          </>
        ) : null}
        {o.studyModes.length > 1 || f.studyMode ? <Sel id="sq-mode" label="Study mode" value={f.studyMode} any="All" opts={o.studyModes.map((m) => [m, modeWord(m)])} onChange={(v) => set("studyMode", v)} /> : null}
        <Sel id="sq-session" label={isJupeb ? "JUPEB session" : "Session"} value={f.session} any={`Current (${o.currentSession})`}
          opts={(isJupeb || isPrelim ? o.learnerSessions : o.sessions).map((s) => [s, s])} onChange={(v) => set("session", v)}
          hint={isJupeb || isPrelim ? undefined : "The session whose course registrations and fees are read"} />
        {isJupeb || isPrelim ? null : <Sel id="sq-sem" label="Semester" value={f.semester} any="Whole session" opts={o.semesters.map((n) => [String(n), n === 1 ? "First semester" : n === 2 ? "Second semester" : "Third semester"])} onChange={(v) => set("semester", v)} />}
        <Sel id="sq-asession" label="Admission session" value={f.admissionSession} any="Any" opts={o.admissionSessions.map((s) => [s, s])} onChange={(v) => set("admissionSession", v)} />
        {o.levels.length ? <Sel id="sq-level" label="Level" value={f.level} any="All levels" opts={o.levels.map((l) => [String(l), `${l} Level`])} onChange={(v) => set("level", v)} /> : null}
        <Sel id="sq-status" label="Status" value={f.status} any="Any status" opts={[["CURRENT", statusWord("CURRENT")], ...o.statuses.map((s) => [s, statusWord(s)] as [string, string])]} onChange={(v) => set("status", v)} />
        <Sel id="sq-sex" label="Gender" value={f.sex} any="All" opts={[["M", "Male"], ["F", "Female"]]} onChange={(v) => set("sex", v)} />
        <div className="scope__f grow"><Field id="sq-q" label="Search">
          <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ ...f, q: q.trim() }, { group: group || undefined }); }}>
            <input id="sq-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search student by name, matric number, JAMB number or application number" />
            <Btn kind="primary" type="submit">Search</Btn>
            <Btn kind="ghost" onClick={() => { setQ(""); go({ ...EMPTY_QUERY }); }}>Reset</Btn>
          </form>
        </Field></div>
      </div>

      <details className="mt-2">
        <summary className="lnk" style={{ cursor: "pointer" }}>More filters — matriculation, final year, spillover, expected level, reconciliation, graduation, course registration{o.fees ? ", school fees" : ""}{boundType ? "" : ", classification"}, years</summary>
        <div className="scope mt-2">
          {isJupeb || isPrelim ? null : <Sel id="sq-mat" label="Matriculated" value={f.matriculated} any="Any" opts={[["YES", "Matriculated"], ["NO", "Not yet matriculated"]]} onChange={(v) => set("matriculated", v)} />}
          {isJupeb || isPrelim ? null : <Sel id="sq-final" label="Final year" value={f.finalYear} any="Any" opts={[["YES", "Final year only"], ["NO", "Not final year"]]} onChange={(v) => set("finalYear", v)} />}
          {isJupeb || isPrelim ? null : <Sel id="sq-spill" label="Spillover" value={f.spillover} any="Any" opts={Object.entries(SPILLOVER_WORD)} onChange={(v) => set("spillover", v)} />}
          {/* V593: where the cohort engine places the student, and the lifecycle reconciliation's reading */}
          {isJupeb || isPrelim ? null : <Sel id="sq-xlevel" label="Expected level" value={f.expectedLevel} any="Any" opts={[100, 200, 300, 400, 500, 600].map((l) => [String(l), `${l} Level`])} onChange={(v) => set("expectedLevel", v)} />}
          {isJupeb || isPrelim ? null : <Sel id="sq-behind" label="Level on record" value={f.levelBehind} any="Any" opts={[["YES", "Below the expected level"], ["NO", "At or above the expected level"]]} onChange={(v) => set("levelBehind", v)} />}
          {isJupeb || isPrelim ? null : <Sel id="sq-plen" label="Programme length" value={f.programmeLength} any="Any" opts={[3, 4, 5, 6, 7].map((n) => [String(n), `${n} years`])} onChange={(v) => set("programmeLength", v)} />}
          {isJupeb || isPrelim ? null : <Sel id="sq-rec" label="Reconciliation" value={f.recommendation} any="Any" opts={Object.entries(RECOMMENDATION_WORD)} onChange={(v) => set("recommendation", v)} />}
          {isJupeb || isPrelim ? null : <Sel id="sq-compl" label="Completion (as last analysed)" value={f.completion} any="Any" opts={Object.entries(COMPLETION_WORD)} onChange={(v) => set("completion", v)} />}
          <Sel id="sq-grad" label="Graduation" value={f.graduation} any="Any" opts={[["GRADUATED", "Graduated / completed"], ["NOT_GRADUATED", "Not graduated"]]} onChange={(v) => set("graduation", v)} />
          {isPrelim ? null : <Sel id="sq-reg" label="Course registration" value={f.registration} any="Any" opts={[["REGISTERED", "Registered"], ["NOT_REGISTERED", "Not registered"]]} onChange={(v) => set("registration", v)} />}
          {o.fees && !isJupeb && !isPrelim ? <Sel id="sq-fees" label="School fees" value={f.fees} any="Any" opts={[["OUTSTANDING", "Outstanding"], ["COMPLETED", "Completed"]]} onChange={(v) => set("fees", v)} /> : null}
          {boundType ? null : <Sel id="sq-cls" label="Classification" value={f.classification} any="Any" opts={[["CLASSIFIED", "Classified"], ["REQUIRES_CLASSIFICATION", "Requires classification"]]} onChange={(v) => set("classification", v)} />}
          {(["entryYear", "matricYear", "jambYear"] as const).map((k) => (
            <div key={k} className="scope__f"><Field id={`sq-${k}`} label={k === "entryYear" ? "Entry year" : k === "matricYear" ? "Matriculation year" : "JAMB year"}>
              <input id={`sq-${k}`} className="ctl tnum" inputMode="numeric" maxLength={4} defaultValue={f[k]} placeholder="e.g. 2024"
                onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); const v = (e.target as HTMLInputElement).value.trim(); set(k, /^\d{4}$/.test(v) ? v : ""); } }}
                onBlur={(e) => { const v = e.target.value.trim(); if (v !== f[k] && (v === "" || /^\d{4}$/.test(v))) set(k, v); }} />
            </Field></div>
          ))}
        </div>
      </details>

      {/* the quick queries */}
      <div className="row row--tight mt-2" role="group" aria-label="Quick queries" style={{ flexWrap: "wrap", gap: 6 }}>
        {PRESETS.filter((p) => !p.fees || o.fees).map((p) => (
          <Btn key={p.key} kind={(p.group ? group === p.group : false) ? "primary" : "ghost"} size="sm"
            onClick={() => p.group ? go(f, { group: group === p.group ? undefined : p.group }) : go(applyPreset(f, p))}>{p.label}</Btn>
        ))}
      </div>

      {/* the filters applied */}
      <Panel title="Filters applied" right={applied.length ? <Btn kind="ghost" size="sm" onClick={() => go({ ...EMPTY_QUERY })}>Clear all filters</Btn> : "None — every student in your scope"}>
        <PBody>
          {applied.length ? (
            <div className="row" style={{ flexWrap: "wrap", gap: 8 }}>
              {applied.map((a) => (
                <span key={a.key} className="chip row row--inline" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-pill)", padding: "3px 6px 3px 12px", gap: 6 }}>
                  <span className="sub2">{a.label}:</span> <b>{a.value}</b>
                  {a.key === "type" && boundType ? null : (
                    <button type="button" aria-label={`Remove ${a.label}`} title={`Remove ${a.label}`} onClick={() => set(a.key, "")}
                      style={{ border: 0, background: "none", cursor: "pointer", fontSize: 16, lineHeight: 1, padding: "0 4px", color: "var(--muted)" }}>&times;</button>
                  )}
                </span>
              ))}
            </div>
          ) : <div className="sub2">{o.scope.label}{boundType ? ` — ${typeStudentWord(typeName(boundType))}s only` : ""}.</div>}
          <div className="mt-2"><b className="tnum">Total results: {vzNum(list.total)}</b></div>
        </PBody>
      </Panel>

      {group ? (
        <Panel title={group === "faculty" ? "Students by faculty" : group === "department" ? "Students by department" : "Students by programme"}
          right={<Btn kind="ghost" size="sm" onClick={() => go(f)}>Close</Btn>}>
          {breakdown.length ? (
            <DTable pageSize={0} cols={["S/N|num", group === "faculty" ? "Faculty" : group === "department" ? "Department" : "Programme", "Students|num", "|num"]}
              rows={breakdown.map((b, i) => {
                const label = group === "faculty" ? (b.faculty ?? "No faculty (JUPEB)") : group === "department" ? (b.department ?? "No department (JUPEB)") : (b.programme ?? "No programme");
                const sub = group === "faculty" ? null : group === "department" ? b.faculty : `${b.department ?? ""} · ${b.faculty ?? ""}`;
                const next: Partial<QueryFilters> = group === "faculty" ? { fac: b.faculty_code ?? "" } : group === "department" ? { fac: b.faculty_code ?? "", dept: b.dept_code ?? "" }
                  : { fac: b.faculty_code ?? "", dept: b.dept_code ?? "", prog: b.programme_code ?? "" };
                return [
                  <span key="sn" className="tnum sub2">{i + 1}</span>,
                  <span key="l"><b>{label}</b>{sub ? <div className="sub2">{sub}</div> : null}</span>,
                  <span key="n" className="tnum">{vzNum(b.count)}</span>,
                  b.faculty_code ? <Btn key="a" kind="ghost" size="sm" onClick={() => go({ ...f, ...next })}>Students</Btn> : <span key="a" />,
                ];
              })} texts={breakdown.map((b) => `${b.faculty ?? ""} ${b.department ?? ""} ${b.programme ?? ""}`)} />
          ) : <PBody><div className="sub2">No students match the filters.</div></PBody>}
        </Panel>
      ) : null}

      <Panel title={f.type ? `${typeStudentWord(typeName(f.type))}s` : "Students"} right={list.total ? `Page ${list.page + 1} of ${pages} · ${vzNum(list.total)} in all · names A–Z` : "None"}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Programme type", "Admission route", "Study mode", "Centre", "Faculty", "Department", "Programme", "Level|mid",
            "Admission session|mid", "Current session|mid", "Status|mid", "Registration|mid", ...(f.fees ? ["School fees|mid"] : []), "|num"]}
            rows={list.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
              <span key="s"><strong>{r.surname}, {r.other_names}</strong>
                <div className="sub2 tnum">{[r.matric_no, r.jamb_no ? `JAMB ${r.jamb_no}` : null, r.application_no].filter(Boolean).join(" · ") || r.admission_no || "—"}</div></span>,
              r.programme_type_name ? <Pil key="t" kind="info">{r.programme_type_name}</Pil> : <Pil key="t" kind="warn" title={r.classification_note ?? undefined}>Requires classification</Pil>,
              <span key="r">{r.admission_route_name ?? "—"}</span>,
              <span key="m">{modeWord(r.study_mode)}</span>,
              <span key="c">{r.centre_name ?? "—"}</span>,
              <span key="f">{r.faculty ?? "—"}</span>,
              <span key="d">{r.department ?? "—"}</span>,
              <span key="p">{programmeOf(r)}{r.pg_award ? <div className="sub2">{r.pg_award}</div> : null}</span>,
              <span key="l" className="tnum">{levelWord(r)}{spilloverWord(r.spillover_state) ? <div className="sub2" title={spilloverWord(r.spillover_state)?.long}>{spilloverWord(r.spillover_state)?.short}</div> : null}</span>,
              <span key="as" className="tnum">{r.admission_session ?? "—"}</span>,
              <span key="cs" className="tnum">{r.current_session ?? "—"}</span>,
              <Pil key="st" kind={r.status === "ACTIVE" ? "ok" : r.status === "ADMITTED" ? "info" : ["GRADUATED", "COMPLETED", "PROGRESSED"].includes(r.status) ? "grey" : "warn"}>{statusWord(r.status)}</Pil>,
              <span key="rg" className="sub2">{regWord(r)}</span>,
              ...(f.fees ? [<span key="fe" className="sub2">{feeWord(r.fee_status)}</span>] : []),
              openLink(r, o),
            ])} />
        ) : (
          <PBody><Note kind="info" title="No students found">No students match the filters within your office&rsquo;s scope.</Note></PBody>
        )}
        {pages > 1 ? (
          <PBody>
            <div className="row row--between">
              <Btn kind="ghost" disabled={list.page === 0} onClick={() => go(f, { page: list.page - 1, group: group || undefined })}>Previous</Btn>
              <span className="sub2 tnum">Rows {list.page * list.size + 1}–{Math.min(list.total, (list.page + 1) * list.size)} of {vzNum(list.total)}</span>
              <Btn kind="ghost" disabled={list.page + 1 >= pages} onClick={() => go(f, { page: list.page + 1, group: group || undefined })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
      <div className="sub2">Programme type is read from the student&rsquo;s admission and academic record — never from a programme name, a matriculation or JAMB number.
        A record whose fields disagree is shown as <em>requires classification</em> until the Academic Office decides it.</div>
    </>
  );
}

function regWord(r: QueryRow): string {
  if (r.source === "PRELIMINARY") return "—";
  const s = r.registration_status;
  if (!s) return "Not registered";
  return s === "SUBMITTED" ? "Submitted" : s === "APPROVED" ? "Approved" : s === "LOCKED" ? "Locked" : s === "REGISTERED" ? "Registered" : s.charAt(0) + s.slice(1).toLowerCase();
}

function feeWord(s: string | null | undefined): string {
  return s === "FULLY_PAID" ? "Completed" : s === "PART_PAYMENT" ? "Part payment" : s === "NOT_PAID" ? "Not paid" : s === "NO_CHARGE" ? "No charge stated" : "—";
}

/** the door to the learner's own record, where the office may open it: a register student's record (its own scope is the
 *  server's), a JUPEB learner's application for the JUPEB office, a Preliminary application for the Preliminary desk */
function openLink(r: QueryRow, o: QueryOptions) {
  if (r.source === "REGISTER" && r.student_id) return <LinkBtn key="o" href={`/students/${r.student_id}`} size="sm">Open</LinkBtn>;
  if (r.source === "JUPEB" && o.scope.programmeType === "JUPEB") return <LinkBtn key="o" href={`/jupeb/applications/${r.learner_id}`} size="sm">Open</LinkBtn>;
  if (r.source === "PRELIMINARY" && r.application_no && (o.scope.programmeType === "PRELIMINARY" || o.classifies)) {
    return <Link key="o" className="lnk" href={`/preliminary?q=${encodeURIComponent(r.application_no)}`}>Open</Link>;
  }
  return <span key="o" />;
}
