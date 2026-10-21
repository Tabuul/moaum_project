"use client";

/** V605: the ID card report — session, faculty, department, programme, level, student status, card status, the dates and who printed;
 *  S/N first, the University heading, filters and the generated-by line on the Excel and the PDF (the one export engine). */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import type { Scope } from "@/lib/scope";
import { ScopeBar, type ScopeStructure } from "@/components/proto/ScopeBar";
import { Btn, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CARD_STATE, cardStateWord } from "@/lib/idcard-desk";

interface Row {
  card_id: string; card_no: string; state: string; version: number; print_count: number; printed_at: string | null; issued_at: string | null; valid_to: string;
  ended_at: string | null; ended_reason: string | null; replacement_reason: string | null; student_id: string; name: string; matric_no: string | null;
  level: number | null; status: string; entry_session: string | null; faculty: string | null; department: string | null; programme: string | null;
  printed_by: string | null; issued_by: string | null;
}

const STATUSES = ["", "ADMITTED", "ACTIVE", "PROBATION", "DORMANT", "DEFERRED", "GRADUATED", "WITHDRAWN"];
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");

export function IdCardReport({ scope, structure, sessions }: { scope: Scope; structure: ScopeStructure; sessions: string[] }) {
  const [status, setStatus] = useState("");
  const [cardState, setCardState] = useState("");
  const [printedFrom, setPrintedFrom] = useState("");
  const [printedTo, setPrintedTo] = useState("");
  const [issuedFrom, setIssuedFrom] = useState("");
  const [issuedTo, setIssuedTo] = useState("");
  const [printedBy, setPrintedBy] = useState("");
  const [rows, setRows] = useState<Row[] | null>(null);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);

  function query(p: number, exportAll: boolean) {
    const q = new URLSearchParams();
    if (scope.session) q.set("session", scope.session);
    if (scope.fac) q.set("fac", scope.fac);
    if (scope.dept) q.set("dept", scope.dept);
    if (scope.prog) q.set("prog", scope.prog);
    if (scope.level) q.set("level", String(scope.level));
    if (status) q.set("status", status);
    if (cardState) q.set("cardState", cardState);
    if (printedFrom) q.set("printedFrom", printedFrom);
    if (printedTo) q.set("printedTo", printedTo);
    if (issuedFrom) q.set("issuedFrom", issuedFrom);
    if (issuedTo) q.set("issuedTo", issuedTo);
    if (printedBy.trim()) q.set("printedBy", printedBy.trim());
    q.set("page", String(p)); q.set("size", "50");
    if (exportAll) q.set("export", "true");
    return q;
  }

  async function load(p = 0): Promise<Row[] | null> {
    setBusy("load"); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/credentials/identity-cards/report?${query(p, false).toString()}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      setRows(j.rows); setTotal(j.total); setPage(j.page);
      return j.rows;
    } finally {
      setBusy(null);
    }
  }

  async function everything(): Promise<Row[]> {
    const r = await fetch(`/api/bff/api/v1/credentials/identity-cards/report?${query(0, true).toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return []; }
    return j.rows;
  }

  const headers = ["S/N", "Student name", "Matriculation number", "Faculty", "Department", "Programme", "Level", "Card number", "Status", "Printed", "Printed by", "Issued", "Issued by"];
  const cells = (all: Row[]) => all.map((r, i) => [i + 1, r.name, r.matric_no ?? "", r.faculty ?? "", r.department ?? "", r.programme ?? "", r.level ?? "", r.card_no, cardStateWord(r.state)[0], day(r.printed_at), r.printed_by ?? "", day(r.issued_at), r.issued_by ?? ""]);
  const meta: [string, string][] = [["Admission session", scope.session || "Any"], ["Faculty", scope.fac || "All"], ["Department", scope.dept || "All"], ["Programme", scope.prog || "All"],
    ["Student status", status || "Any"], ["Card status", cardState ? cardStateWord(cardState)[0] : "Any"], ["Printed", printedFrom || printedTo ? `${printedFrom || "…"} to ${printedTo || "…"}` : "Any"],
    ["Issued", issuedFrom || issuedTo ? `${issuedFrom || "…"} to ${issuedTo || "…"}` : "Any"], ["Printed by", printedBy || "Anyone"]];

  async function excel() {
    setBusy("xlsx");
    try {
      const all = await everything();
      const blob = await brandedXlsx("Student identity cards", headers, cells(all), { serial: docSerial("IDC"), meta, sub: "Security Unit — ID card report" });
      downloadBlob(blob, `id-cards-${(scope.session || "all").replace("/", "-")}.xlsx`);
    } finally {
      setBusy(null);
    }
  }

  async function pdf() {
    setBusy("pdf");
    try {
      const all = await everything();
      brandedPrint("Student identity cards", "Security Unit — ID card report", headers, cells(all), docSerial("IDC"), { meta, orientation: "landscape" });
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <ScopeBar scope={scope} structure={structure} sessions={sessions} what="cards" count={total} of={total} />
      <Panel title="ID card report" right={rows && rows.length ? <span className="row row--tight"><Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void excel()}>{busy === "xlsx" ? "Preparing…" : "Excel"}</Btn><Btn kind="ghost" size="sm" disabled={busy !== null} onClick={() => void pdf()}>{busy === "pdf" ? "Preparing…" : "PDF"}</Btn></span> : null}>
        <PBody>
          <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
            <Field id="icr-status" label="Student status"><select id="icr-status" className="ctl" value={status} onChange={(e) => setStatus(e.target.value)}>{STATUSES.map((s) => <option key={s} value={s}>{s || "Any"}</option>)}</select></Field>
            <Field id="icr-card" label="Card status"><select id="icr-card" className="ctl" value={cardState} onChange={(e) => setCardState(e.target.value)}><option value="">Any</option>{Object.keys(CARD_STATE).filter((k) => k !== "NOT_PRINTED").map((k) => <option key={k} value={k}>{CARD_STATE[k][0]}</option>)}</select></Field>
            <Field id="icr-pf" label="Printed from"><input id="icr-pf" type="date" className="ctl" value={printedFrom} onChange={(e) => setPrintedFrom(e.target.value)} /></Field>
            <Field id="icr-pt" label="Printed to"><input id="icr-pt" type="date" className="ctl" value={printedTo} onChange={(e) => setPrintedTo(e.target.value)} /></Field>
            <Field id="icr-if" label="Issued from"><input id="icr-if" type="date" className="ctl" value={issuedFrom} onChange={(e) => setIssuedFrom(e.target.value)} /></Field>
            <Field id="icr-it" label="Issued to"><input id="icr-it" type="date" className="ctl" value={issuedTo} onChange={(e) => setIssuedTo(e.target.value)} /></Field>
            <Field id="icr-by" label="Printed by"><input id="icr-by" className="ctl" value={printedBy} onChange={(e) => setPrintedBy(e.target.value)} placeholder="officer's name" maxLength={60} /></Field>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void load(0)}>{busy === "load" ? "Loading…" : "Run the report"}</Btn>
          </div>
          <div className="sub2" style={{ marginTop: "var(--s-2)" }}>The scope bar&rsquo;s session is the admission session; faculty, department, programme and level narrow the students. S/N first on the Excel and the PDF, continuous across pages.</div>
        </PBody>
        {problem ? <ProblemNotice problem={problem} /> : null}
        {rows ? (
          rows.length ? (
            <>
              <DTable pageSize={0}
                cols={["S/N|num", "Student", "Faculty / Department", "Programme", "Level|num", "Card", "Status", "Printed", "Printed by", "Issued", "Issued by"]}
                rows={rows.map((r, i) => [
                  <span key="n" className="tnum">{page * 50 + i + 1}</span>, <Two key="s" a={r.name} b={r.matric_no ?? "—"} />,
                  <span key="f" className="sub2">{r.faculty ?? "—"}{r.department ? ` · ${r.department}` : ""}</span>, <span key="p">{r.programme ?? "—"}</span>,
                  <span key="l" className="tnum">{r.level ?? "—"}</span>, <span key="c" className="tnum">{r.card_no}{r.version > 1 ? ` (v${r.version})` : ""}</span>,
                  <Pil key="st" kind={cardStateWord(r.state)[1]}>{cardStateWord(r.state)[0]}</Pil>,
                  <span key="pd" className="sub2 tnum">{day(r.printed_at)}</span>, <span key="pb" className="sub2">{r.printed_by ?? "—"}</span>,
                  <span key="id" className="sub2 tnum">{day(r.issued_at)}</span>, <span key="ib" className="sub2">{r.issued_by ?? "—"}</span>,
                ])}
                texts={rows.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.card_no} ${r.programme ?? ""}`)}
              />
              <PBody><div className="row" style={{ justifyContent: "space-between" }}>
                <span className="sub2">{total} card{total === 1 ? "" : "s"} · page {page + 1} of {Math.max(1, Math.ceil(total / 50))}</span>
                <span className="row row--tight">
                  <Btn kind="ghost" size="sm" disabled={page === 0 || busy !== null} onClick={() => void load(page - 1)}>Previous</Btn>
                  <Btn kind="ghost" size="sm" disabled={(page + 1) * 50 >= total || busy !== null} onClick={() => void load(page + 1)}>Next</Btn>
                </span>
              </div></PBody>
            </>
          ) : <PBody><div className="sub2">No card matches the filters.</div></PBody>
        ) : null}
      </Panel>
    </>
  );
}
