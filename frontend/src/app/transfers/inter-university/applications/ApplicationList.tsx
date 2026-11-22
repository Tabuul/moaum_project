"use client";

/** V766: the transfer applications as a desk reads them — the Registry's (every application of the session) and the Head of
 *  Department's or College Dean's (those of their department that have reached them; the API scopes them). Filters by session, state
 *  (with the counts the database gives for the other filters), programme and a search; each row opens the application. */
import Link from "next/link";
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { PAGE_SIZE, STATES, cgpaOf, dayWords, listQuery, officeWords, type ApplicationList as List } from "@/lib/transfer-application";

export interface ListFilters { session: string | null; state: string | null; programme: string | null; q: string | null; page: number }

export function ApplicationList({ data, problem, filters, sessions, programmes, path, extra = {}, states = [...STATES] }: {
  data: List | null; problem: Problem | null; filters: ListFilters; sessions: string[]; programmes: { code: string; name: string }[];
  /** the page's own address, the detail at `${path}/${id}` */
  path: string;
  /** other parameters the page keeps (the tab) */
  extra?: Record<string, string>;
  /** the states the chips offer */
  states?: string[];
}) {
  const go = useQueryNav();
  const [q, setQ] = useState(filters.q ?? "");
  const href = (patch: Partial<ListFilters>) => {
    const n = { ...filters, page: 0, ...patch };
    const qs = listQuery({ ...n, page: n.page || null });
    const more = new URLSearchParams(extra).toString();
    // "every session" and "every state" are said in the address, so a desk's default (the window's session, the department's waiting
    // applications) is not put back in their place
    return `${path}?${[qs, more, n.session ? "" : "all=1", n.state ? "" : "state="].filter(Boolean).join("&")}`;
  };
  const counts = data?.counts ?? {};
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  const pages = Math.max(1, Math.ceil((data?.total ?? 0) / PAGE_SIZE));
  return (
    <>
      <Panel title="Filters">
        <PBody>
          <form className="row row--inline row--tight" style={{ flexWrap: "wrap", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); go(href({ q })); }}>
            <Field id="ia-session" label="Session">
              <select id="ia-session" className="ctl" value={filters.session ?? ""} onChange={(e) => go(href({ session: e.target.value || null }))}>
                <option value="">Every session</option>
                {filters.session && !sessions.includes(filters.session) ? <option value={filters.session}>{filters.session}</option> : null}
                {sessions.map((s) => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
            <Field id="ia-programme" label="Programme">
              <select id="ia-programme" className="ctl" value={filters.programme ?? ""} onChange={(e) => go(href({ programme: e.target.value || null }))}>
                <option value="">Every programme</option>
                {programmes.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
              </select>
            </Field>
            <Field id="ia-q" label="Search" hint="Application or JAMB number, name, matriculation number there, university">
              <input id="ia-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} style={{ minWidth: 240 }} />
            </Field>
            <Btn kind="primary" type="submit">Search</Btn>
          </form>
          <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }} role="group" aria-label="State">
            <Link className={`btn btn--sm ${filters.state ? "btn--ghost" : "btn--secondary"}`} href={href({ state: null })}>All · {total}</Link>
            {states.map((s) => (
              <Link key={s} className={`btn btn--sm ${filters.state === s ? "btn--secondary" : "btn--ghost"}`} href={href({ state: s })} aria-current={filters.state === s ? "true" : undefined}>
                {officeWords(s)[0]} · {counts[s] ?? 0}
              </Link>
            ))}
          </div>
        </PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : data ? (
        <Panel title={`${data.total.toLocaleString()} application${data.total === 1 ? "" : "s"}`} right={pages > 1 ? (
          <span className="row row--inline row--tight">
            <span className="sub2">page {filters.page + 1} of {pages}</span>
            <Btn kind="ghost" size="sm" disabled={filters.page === 0} onClick={() => go(href({ ...filters, page: filters.page - 1 }))}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={filters.page + 1 >= pages} onClick={() => go(href({ ...filters, page: filters.page + 1 }))}>Next</Btn>
          </span>) : undefined}>
          {data.rows.length ? (
            <DTable cols={["S/N|num", "Application", "Applicant", "University", "Applied for", "CGPA|num", "State", "Documents", "Updated"]} rows={data.rows.map((r, i) => {
              const [word, pill] = officeWords(r.state);
              const d = r.documents ?? {};
              return [
                <span key="n" className="tnum sub2">{filters.page * PAGE_SIZE + i + 1}</span>,
                <span key="a"><Link className="lnk tnum b600" href={`${path}/${r.id}`}>{r.applicationNo}</Link><div className="sub2 tnum">{r.session}</div></span>,
                <span key="p">{r.surname}, {r.otherNames}<div className="sub2 tnum">{r.jambRegNo ?? ""}</div></span>,
                <span key="u">{r.universityName ?? r.universityNamed ?? "—"}{!r.universityCode && r.universityNamed ? <div><Pil kind="warn">Not on the list</Pil></div> : null}</span>,
                <span key="g">{r.programmeName ?? r.programme}<div className="sub2">{r.level ? `${r.level} Level` : ""}{r.hodLevel && r.hodLevel !== r.level ? ` · recommended for ${r.hodLevel} Level` : ""}</div></span>,
                <span key="c" className="tnum">{cgpaOf(r.cgpa, r.cgpaScale)}</span>,
                <Pil key="s" kind={pill}>{word}</Pil>,
                <span key="d" className="sub2 tnum">{d.pending ?? 0} to check · {d.accepted ?? 0} accepted{d.rejected ? ` · ${d.rejected} rejected` : ""}</span>,
                <span key="t" className="sub2 tnum">{dayWords(r.updatedAt) || "—"}</span>,
              ];
            })} texts={data.rows.map((r) => `${r.applicationNo} ${r.surname} ${r.otherNames} ${r.jambRegNo ?? ""} ${r.universityName ?? r.universityNamed ?? ""}`)} />
          ) : <PBody><Note kind="info" title="No application matches">No transfer application for the filters chosen.</Note></PBody>}
        </Panel>
      ) : null}
    </>
  );
}
