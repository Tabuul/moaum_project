"use client";

/** Students we cannot reach (V565): the current students within the reader's reach the University holds no e-mail, no phone, or
 *  neither for — counted by faculty, listed a page at a time — so the desk can put the contact right when the student comes, or
 *  send the list to the departments. A student without either gets no notice, no reset link and no ticket update. */
import Link from "next/link";
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface ReachFilters { kind: string; fac: string; level: string; q: string; page: number }
interface ReachRow {
  id: string; name: string; number: string | null; jamb_reg_no: string | null; faculty: string | null; department: string | null; programme: string | null;
  level: number | null; status: string; has_email: boolean; has_phone: boolean; open_ticket: string | null;
}
export interface ReachList {
  kind: string; total: number; page: number; size: number; rows: ReachRow[];
  byFaculty?: { faculty_code: string; faculty: string | null; students: number; no_email: number; no_phone: number; neither: number }[];
  mayEditContact?: boolean; mayExport?: boolean;
}

const KINDS: [string, string][] = [["NEITHER", "No e-mail and no phone"], ["NO_EMAIL", "No e-mail"], ["NO_PHONE", "No phone"]];
const count = (n: number) => Number(n).toLocaleString("en-NG");
const pct = (n: number, of: number) => (of ? `${Math.round((100 * n) / of)}%` : "—");

export function Reach({ f, list }: { f: ReachFilters; list: ReachList }) {
  const go = useQueryNav();
  const [q, setQ] = useState(f.q);
  const nav = (patch: Partial<ReachFilters>) => {
    const next = { ...f, page: 1, ...patch };
    const qs = new URLSearchParams();
    if (next.kind !== "NEITHER") qs.set("kind", next.kind);
    for (const k of ["fac", "level", "q"] as const) if (next[k]) qs.set(k, next[k]);
    if (next.page > 1) qs.set("page", String(next.page));
    go(`/helpdesk/reach${qs.toString() ? `?${qs.toString()}` : ""}`);
  };
  const by = list.byFaculty ?? [];
  const sum = (k: "students" | "no_email" | "no_phone" | "neither") => by.reduce((n, r) => n + Number(r[k]), 0);
  const students = sum("students");
  const pages = Math.max(1, Math.ceil(list.total / (list.size || 50)));
  const kindWord = KINDS.find(([k]) => k === f.kind)?.[1] ?? "";
  const HEAD = ["S/N", "Student", "Matriculation or admission number", "JAMB number", "Faculty", "Department", "Programme", "Level", "Status", "E-mail on record", "Phone on record", "Open ticket"];

  async function excel() {
    const qs = new URLSearchParams({ kind: f.kind, export: "true", size: "20000" });
    for (const k of ["fac", "level", "q"] as const) if (f[k]) qs.set(k, f[k]);
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/reach?${qs.toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The list could not be read just now." }); return; }
    const rows = (j as ReachList).rows.map((x, i) => [i + 1, x.name, x.number ?? "", x.jamb_reg_no ?? "", x.faculty ?? "", x.department ?? "", x.programme ?? "", x.level ?? "",
      x.status, x.has_email ? "Yes" : "No", x.has_phone ? "Yes" : "No", x.open_ticket ?? ""]);
    downloadBlob(await brandedXlsx("Students We Cannot Reach", HEAD, rows, { sub: kindWord, serial: docSerial("REACH") }), "students-we-cannot-reach.xlsx");
  }

  return (
    <>
      <PageHead eyebrow="ICT Support Desk"
        description="The current students within your reach the University holds no e-mail or phone for. Such a student gets no notice, no reset link and no ticket update: put the contact right on the student's record when they come to the desk, or send the list to the departments to collect it." />
      <Tiles cls="grid--4" items={[
        ["Current students", count(students), null, "active, on probation, admitted, deferred"],
        ["No e-mail", count(sum("no_email")), sum("no_email") ? "var(--amber-ink)" : null, pct(sum("no_email"), students), "/helpdesk/reach?kind=NO_EMAIL"],
        ["No phone", count(sum("no_phone")), sum("no_phone") ? "var(--amber-ink)" : null, pct(sum("no_phone"), students), "/helpdesk/reach?kind=NO_PHONE"],
        ["Neither", count(sum("neither")), sum("neither") ? "var(--red-ink)" : null, `${pct(sum("neither"), students)} cannot be reached at all`, "/helpdesk/reach"],
      ]} />
      {by.length ? (
        <Panel title="By faculty">
          <DTable pageSize={0} noPrint cols={["Faculty", "Students|num", "No e-mail|num", "No phone|num", "Neither|num"]} rows={by.map((r) => [
            <button key="f" type="button" className="lnk" onClick={() => nav({ fac: r.faculty_code })}>{r.faculty ?? r.faculty_code}</button>,
            <span key="s" className="tnum">{count(r.students)}</span>,
            <span key="e" className="tnum">{count(r.no_email)}<span className="sub2"> · {pct(Number(r.no_email), Number(r.students))}</span></span>,
            <span key="p" className="tnum">{count(r.no_phone)}</span>,
            <b key="n" className="tnum">{count(r.neither)}</b>,
          ])} />
        </Panel>
      ) : null}
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); nav({ q: q.trim() }); }}>
        <Field id="rc-kind" label="Students with">
          <select id="rc-kind" className="ctl" value={f.kind} onChange={(e) => nav({ kind: e.target.value })}>
            {KINDS.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
          </select>
        </Field>
        <Field id="rc-fac" label="Faculty">
          <select id="rc-fac" className="ctl" value={f.fac} onChange={(e) => nav({ fac: e.target.value })}>
            <option value="">Any</option>
            {by.map((r) => <option key={r.faculty_code} value={r.faculty_code}>{r.faculty ?? r.faculty_code}</option>)}
          </select>
        </Field>
        <Field id="rc-level" label="Level">
          <select id="rc-level" className="ctl" value={f.level} onChange={(e) => nav({ level: e.target.value })}>
            <option value="">Any</option>
            {[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l}</option>)}
          </select>
        </Field>
        <Field id="rc-q" label="Name or number"><input id="rc-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} /></Field>
        <button type="submit" className="btn btn--primary btn--sm" style={{ alignSelf: "flex-end" }}>Search</button>
      </form>
      <Panel title={`${count(list.total)} student${list.total === 1 ? "" : "s"} · ${kindWord.toLowerCase()}${pages > 1 ? ` · page ${list.page} of ${pages}` : ""}`}
        right={list.mayExport ? <Btn kind="ghost" disabled={!list.total} busyLabel="Preparing Excel..." onClick={excel}>Excel</Btn> : undefined}>
        {!list.mayEditContact ? <PBody><Note kind="info" title="Contact editing is not on your posting">You can raise a ticket with the contact the student gives; the Head of the Support Desk grants contact editing.</Note></PBody> : null}
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Number", "Faculty", "Programme", "Level|num", "E-mail|mid", "Phone|mid", "Open ticket"]} rows={list.rows.map((r, i) => [
            <span key="n" className="tnum sub2">{(list.page - 1) * (list.size || 50) + i + 1}</span>,
            <Link key="s" className="lnk" href={`/helpdesk/students/${r.id}`}>{r.name}</Link>,
            <span key="m" className="tnum">{r.number ?? "—"}</span>,
            <span key="f" className="sub2">{r.faculty ?? "—"}<div>{r.department ?? ""}</div></span>,
            <span key="p" className="sub2">{r.programme ?? "—"}</span>,
            <span key="l" className="tnum">{r.level ?? "—"}</span>,
            <Pil key="e" kind={r.has_email ? "ok" : "bad"}>{r.has_email ? "On record" : "None"}</Pil>,
            <Pil key="ph" kind={r.has_phone ? "ok" : "bad"}>{r.has_phone ? "On record" : "None"}</Pil>,
            <span key="t" className="tnum sub2">{r.open_ticket ?? "—"}</span>,
          ])} />
        ) : <PBody><span className="sub2">No current student within your reach is without {f.kind === "NO_PHONE" ? "a phone" : f.kind === "NO_EMAIL" ? "an e-mail" : "both"}{f.fac || f.level || f.q ? " among those filtered" : ""}.</span></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row row--inline" style={{ gap: 6 }}>
              <Btn kind="ghost" disabled={list.page <= 1} onClick={() => nav({ page: list.page - 1 })}>Previous</Btn>
              <Btn kind="ghost" disabled={list.page >= pages} onClick={() => nav({ page: list.page + 1 })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
