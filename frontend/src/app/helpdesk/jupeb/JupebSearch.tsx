"use client";
/** The support desk's JUPEB search (V347): the JUPEB programme's candidates and students, found by application number, the
 *  old portal's App No, the examination number, email, phone or name — for an agent whose posting reaches JUPEB records
 *  (the JUPEB Support queue, a University-wide posting, or a posting on the JUPEB Office). The server searches and pages. */
import { useEffect, useState } from "react";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { STATE_SHORT, jcall, stateKind, streamLabel } from "@/lib/jupeb";

interface Row {
  id: string; application_no: string; legacy_ref: string | null; exam_no: string | null; surname: string; first_name: string; middle_name: string | null; email: string; phone: string | null;
  session: string; state: string; stream: string | null; combination_code: string | null; legacy_source: string | null;
}
interface List { total: number; page: number; size: number; rows: Row[]; capabilities: string[]; sessions: string[] }

export function JupebSearch() {
  const [f, setF] = useState({ q: "", session: "", state: "" });
  const [page, setPage] = useState(1);
  const [list, setList] = useState<List | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [asked, setAsked] = useState({ q: "", session: "", state: "" });
  useEffect(() => {
    const qs = new URLSearchParams({ page: String(page), size: "50" });
    if (asked.q.trim()) qs.set("q", asked.q.trim());
    if (asked.session) qs.set("session", asked.session);
    if (asked.state) qs.set("state", asked.state);
    let live = true;
    void jcall<List>(`/api/v1/helpdesk/support/jupeb?${qs.toString()}`).then((r) => {
      if (!live) return;
      if (r.ok) { setList(r.data); setProblem(null); } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [asked, page]);
  return (
    <>
      <PageHead title="JUPEB student support" description="Every act is on the support ledger."
        actions={<LinkBtn href="/helpdesk">Support Desk</LinkBtn>} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {problem?.status === 422 ? <Note kind="info" title="JUPEB records are reached through a posting">The Head of the ICT Support Desk posts agents on the JUPEB Support queue.</Note> : null}
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); setPage(1); setAsked({ ...f }); }}>
        <div className="row">
          <Field id="js-q" label="Search" style={{ flex: "2 1 300px" }}><input id="js-q" className="ctl" type="search" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })}
            placeholder="Application number, old App No, JUPEB number, email, phone or surname" /></Field>
          <Field id="js-s" label="Session" style={{ flex: "0 1 140px" }}><select id="js-s" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>
            <option value="">Any</option>{(list?.sessions ?? []).map((x) => <option key={x}>{x}</option>)}</select></Field>
          <Field id="js-st" label="Stage" style={{ flex: "0 1 160px" }}><select id="js-st" className="ctl" value={f.state} onChange={(e) => setF({ ...f, state: e.target.value })}>
            <option value="">Any</option>{Object.entries(STATE_SHORT).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}><Btn kind="primary" type="submit">Search</Btn></div>
        </div>
      </form>
      {list ? (
        <Panel title="JUPEB records" right={<span className="sub2">{list.total.toLocaleString()} found</span>}>
          {list.rows.length ? (
            <DTable pageSize={0} cols={["S/N|num", "Candidate", "Application No.", "JUPEB No.", "Session|mid", "Programme", "Combination", "Stage|mid", "Contact", "|num"]} rows={list.rows.map((r, i) => [
              <span key="n" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
              <span key="c"><strong>{r.surname}, {r.first_name}{r.middle_name ? ` ${r.middle_name}` : ""}</strong>{r.legacy_source ? <div className="sub2">Old portal {r.legacy_ref ?? ""}</div> : null}</span>,
              <span key="a" className="tnum">{r.application_no}</span>, <span key="e" className="tnum">{r.exam_no ?? "—"}</span>, r.session, streamLabel(r.stream), r.combination_code ?? "—",
              <Pil key="s" kind={stateKind(r.state)}>{STATE_SHORT[r.state] ?? r.state}</Pil>,
              <span key="ct" className="sub2">{r.email}{r.phone ? ` · ${r.phone}` : ""}</span>,
              <LinkBtn key="o" kind="primary" size="sm" href={`/helpdesk/jupeb/${r.id}`}>Open</LinkBtn>,
            ])} />
          ) : <PBody><div className="sub2">{asked.q ? "No JUPEB record matches." : "Search by application number, the old portal's App No, JUPEB number, email, phone or surname."}</div></PBody>}
          <PBody><div className="row row--base">
            <span className="sub2">{list.total ? `Showing ${(list.page - 1) * list.size + 1}–${Math.min(list.page * list.size, list.total)} of ${list.total.toLocaleString()}` : ""}</span>
            <span className="grow" />
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={list.page * list.size >= list.total} onClick={() => setPage(page + 1)}>Next</Btn>
          </div></PBody>
        </Panel>
      ) : null}
    </>
  );
}
