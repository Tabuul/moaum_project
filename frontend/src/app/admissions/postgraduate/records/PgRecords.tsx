"use client";

/**
 * V715: postgraduate record management — applicants and students found in one server-side search (by any of their numbers, this
 * portal's or the old portal's, an e-mail, a phone or a name; narrowed by faculty, department, programme, session, kind, state and
 * award), each opened to view, or to correct: an applicant on the postgraduate record page, a student on the student edit page
 * (V642). The search lives in the address, so it is shared and comes back; the list is exported as the register's exports are.
 */
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import type { Problem } from "@/lib/api";
import { Btn, Note, Panel, PBody, Pil, RoleLine } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  EMPTY_FILTERS, awardWord, editHref, filtersQuery, stateWord, viewHref, words,
  type Filters, type SearchAnswer,
} from "@/lib/pg-records";

const EXPORT_COLS = ["S/N", "Name", "Application number", "Old application number", "Matriculation number", "Admission number", "Programme", "Department", "Faculty", "Award", "Session", "Stage", "Status"];

export function PgRecords({ initial, filters: start, actingOffice }: { initial: SearchAnswer | null; filters: Filters; actingOffice: string | null }) {
  const router = useRouter();
  const [f, setF] = useState<Filters>(start);
  const [answer, setAnswer] = useState<SearchAnswer | null>(initial);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const lists = answer?.lists ?? null;
  const may = (p: string) => (answer?.permissions ?? []).includes(p as never);
  const mayExport = may("EXPORT_PG_RECORDS");
  const departments = useMemo(() => (lists?.departments ?? []).filter((d) => !f.faculty || d.faculty_code === f.faculty), [lists, f.faculty]);
  const programmes = useMemo(() => (lists?.programmes ?? []).filter((p) => (!f.faculty || p.faculty_code === f.faculty) && (!f.department || p.dept_code === f.department)), [lists, f.faculty, f.department]);
  const states = f.kind === "STUDENT" ? lists?.studentStatuses ?? [] : f.kind === "APPLICANT" ? lists?.applicationStates ?? [] : [...(lists?.applicationStates ?? []), ...(lists?.studentStatuses ?? []).filter((s) => !(lists?.applicationStates ?? []).includes(s))];

  // the search as typed, read on the server after a pause; the address follows it
  const query = filtersQuery(f);
  useEffect(() => {
    if (query === filtersQuery(start)) return;
    let live = true;
    const h = setTimeout(async () => {
      setBusy(true);
      try {
        const r = await fetch(`/api/bff/api/v1/pg/records/search?${query}`, { cache: "no-store" });
        const j = await r.json().catch(() => null);
        if (!live) return;
        if (r.ok) { setAnswer(j as SearchAnswer); setProblem(null); } else setProblem((j as Problem) ?? { status: r.status, title: r.statusText });
        window.history.replaceState(window.history.state, "", `/admissions/postgraduate/records${query ? `?${query}` : ""}`);
      } finally {
        if (live) setBusy(false);
      }
    }, 350);
    return () => { live = false; clearTimeout(h); };
  }, [query, start]);

  const rows = answer?.rows ?? [];
  const exportRows = () => rows.map((r, i) => [i + 1, r.name, r.application_no ?? "", r.legacy_no ?? "", r.matric_no ?? "", r.admission_no ?? "", r.programme, r.department ?? "",
    r.faculty ?? "", awardWord(r.award), r.session ?? "", r.stage ?? (r.level ? `${r.level}` : ""), stateWord(r.status)]);
  const title = "Postgraduate applicants and students";

  return (
    <>
      <RoleLine allowed={["pgschool", "pgsecretary", "ict", "super"]} actingOffice={actingOffice} canAct={may("EDIT_PG_APPLICANT") || may("EDIT_PG_STUDENT")} action="Correcting postgraduate records" />
      <Panel title="Find a postgraduate applicant or student" right={<span className="sub2">Searched on the server; 200 at most</span>}>
        <PBody>
          <div className="grid grid--3">
            <Field id="pr-q" label="Number, name, e-mail or phone" full hint="An application number (PG/26/000119 or the old portal's), a matriculation, admission or JAMB number, a name, an e-mail or a phone">
              <input id="pr-q" className="ctl" autoFocus value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} placeholder="PG/26/000119, S00220260204082731, BSU/LAW/PHD/23/0012, OCHE Grace …" />
            </Field>
            <Field id="pr-kind" label="Kind">
              <select id="pr-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value, state: "" })}>
                <option value="">Applicants and students</option><option value="APPLICANT">Applicants</option><option value="STUDENT">Students</option>
              </select>
            </Field>
            <Field id="pr-state" label="Stage or status">
              <select id="pr-state" className="ctl" value={f.state} onChange={(e) => setF({ ...f, state: e.target.value })}>
                <option value="">Any</option>{states.map((s) => <option key={s} value={s}>{stateWord(s)}</option>)}
              </select>
            </Field>
          </div>
          <div className="grid grid--5">
            <Field id="pr-fac" label="Faculty">
              <select id="pr-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, department: "", programme: "" })}>
                <option value="">Any</option>{(lists?.faculties ?? []).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="pr-dept" label="Department">
              <select id="pr-dept" className="ctl" value={f.department} onChange={(e) => setF({ ...f, department: e.target.value, programme: "" })}>
                <option value="">Any</option>{departments.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="pr-prog" label="Programme">
              <select id="pr-prog" className="ctl" value={f.programme} onChange={(e) => setF({ ...f, programme: e.target.value })}>
                <option value="">Any</option>{programmes.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="pr-award" label="Qualification">
              <select id="pr-award" className="ctl" value={f.award} onChange={(e) => setF({ ...f, award: e.target.value })}>
                <option value="">Any</option>{(lists?.awards ?? []).map((a) => <option key={a} value={a}>{awardWord(a)}</option>)}
              </select>
            </Field>
            <Field id="pr-ses" label="Session">
              <select id="pr-ses" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>
                <option value="">Any</option>{(lists?.sessions ?? []).map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " (current)" : ""}</option>)}
              </select>
            </Field>
          </div>
          <div className="row mt-2">
            <Btn kind="ghost" onClick={() => setF(EMPTY_FILTERS)}>Clear</Btn>
            {mayExport && rows.length ? (<>
              <Btn kind="secondary" onClick={async () => downloadBlob(await brandedXlsx(title, EXPORT_COLS, exportRows(), { serial: docSerial("PGR") }), "Postgraduate records.xlsx")}>Export Excel</Btn>
              <Btn kind="secondary" onClick={() => brandedPrint(title, `${rows.length} record${rows.length === 1 ? "" : "s"}`, EXPORT_COLS, exportRows(), docSerial("PGR"))}>Export PDF</Btn>
            </>) : null}
            <span className="sub2">{busy ? "Searching…" : answer?.narrowed ? `${rows.length} record${rows.length === 1 ? "" : "s"}${rows.length >= 200 ? " — the first 200; narrow the search" : ""}` : "Type a number or a name, or choose a faculty, programme, session or status."}</span>
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
          {answer?.narrowed && !rows.length && !busy ? <Note kind="info" title="No record found">Check the number, or search by name.</Note> : null}
        </PBody>
        {rows.length ? (
          <DTable pageSize={50} cols={["S/N|num", "Name", "Application number", "Matriculation number", "Programme", "Department", "Faculty", "Award|mid", "Session|mid", "Stage|mid", "Status|mid", "|num"]}
            rows={rows.map((r, i) => [
              <span key="n" className="tnum">{i + 1}</span>,
              <span key="nm"><b>{r.name}</b> <Pil kind={r.kind === "STUDENT" ? "info" : "grey"}>{r.kind === "STUDENT" ? "Student" : "Applicant"}</Pil></span>,
              <span key="a" className="tnum">{r.application_no ?? "—"}{r.legacy_no ? <span className="sub2"> · old {r.legacy_no}</span> : null}</span>,
              <span key="m" className="tnum">{r.matric_no ?? r.admission_no ?? "—"}</span>,
              r.programme, r.department ?? "—", r.faculty ?? "—", awardWord(r.award), r.session ?? "—",
              r.stage ?? (r.level ? `${r.level}` : "—"),
              <Pil key="s" kind={["ACTIVE", "ADMITTED", "OFFERED", "ACCEPTED"].includes(r.status) ? "ok" : ["NOT_OFFERED", "DEPT_DECLINED", "FAC_DECLINED", "WITHDRAWN", "SUSPENDED"].includes(r.status) ? "bad" : "grey"}>{stateWord(r.status)}</Pil>,
              <span key="act" className="row row--inline row--tight">
                <Link className="btn btn--ghost btn--sm" href={viewHref(r)}>View</Link>
                {(r.kind === "STUDENT" ? may("EDIT_PG_STUDENT") : may("EDIT_PG_APPLICANT")) ? <Link className="btn btn--primary btn--sm" href={editHref(r)}>Edit</Link> : null}
              </span>,
            ])} texts={rows.map((r) => `${r.name} ${r.application_no ?? ""} ${r.legacy_no ?? ""} ${r.matric_no ?? ""} ${r.admission_no ?? ""} ${r.programme} ${words(r.status)}`)} />
        ) : null}
      </Panel>
      {answer && !answer.narrowed ? (
        <Note kind="info" title="One record, wherever the person stands">
          An applicant becomes a student on admission; the same person is found here either way. An applicant&rsquo;s record is corrected on the postgraduate record
          page; a student&rsquo;s on the student edit page, where the programme swap, the matriculation correction, the status and the registration live.
          <span className="sub2"> <Btn kind="ghost" size="sm" onClick={() => router.push("/admissions/postgraduate/records/history")}>Change history</Btn></span>
        </Note>
      ) : null}
    </>
  );
}
