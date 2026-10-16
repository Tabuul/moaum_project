"use client";

/** Level Change History (V500): every change of a student's academic level within the reader's reach — by ICT Support (progressed or
 *  corrected, with the ticket), by the Registry's decisions and the cohort corrections — newest first, filtered, and the whole of it
 *  as a branded Excel workbook or PDF (S/N first, display only). */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, PageHead, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { HISTORY_ACTIONS, ruleWord } from "@/lib/level-management";

export interface LevelHistoryRow {
  id: string; decided_at: string; student_id: string; student: string; number: string | null; programme: string | null;
  previous_level: number | null; new_level: number; rule: string | null; reason: string; changed_by: string | null; actor_office: string | null;
  ticket_number: string | null; session: string | null; semester: number | null;
}
export interface LevelHistoryList { total: number; rows: LevelHistoryRow[]; page: number; size: number; scope: string }
export interface LevelHistoryFilters { action: string; q: string; from: string; to: string }

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function LevelHistory({ list, page, filters }: { list: LevelHistoryList; page: number; filters: LevelHistoryFilters }) {
  const go = useQueryNav();
  const qs = (patch: Partial<LevelHistoryFilters> & { page?: string }) => {
    const p = new URLSearchParams();
    for (const [k, v] of Object.entries({ ...filters, page: "1", ...patch })) if (v && !(k === "page" && v === "1")) p.set(k, v);
    return p.toString();
  };
  const nav = (patch: Partial<LevelHistoryFilters> & { page?: string }) => go(`/helpdesk/levels/history${qs(patch) ? "?" + qs(patch) : ""}`);
  const pages = Math.max(1, Math.ceil(list.total / (list.size || 50)));
  const HEAD = ["S/N", "Student", "Matric No", "Programme", "Previous Level", "New Level", "Action", "Changed By", "Role", "Reason", "Ticket", "Date"];
  const line = (r: LevelHistoryRow, i: number) => [i + 1, r.student, r.number ?? "", r.programme ?? "", r.previous_level ?? "", r.new_level, ruleWord(r.rule),
    r.changed_by ?? "", r.actor_office ?? "", r.reason, r.ticket_number ?? "", when(r.decided_at)];

  async function all(): Promise<LevelHistoryRow[] | null> {
    const p = new URLSearchParams({ export: "true", size: "5000" });
    for (const [k, v] of Object.entries(filters)) if (v) p.set(k, v);
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/levels/history?${p.toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The history could not be read just now." }); return null; }
    return (j as LevelHistoryList).rows;
  }
  const sub = [HISTORY_ACTIONS.find(([k]) => k === filters.action)?.[1] ?? "Every change", filters.q ? `“${filters.q}”` : null,
    filters.from ? `from ${filters.from}` : null, filters.to ? `to ${filters.to}` : null].filter(Boolean).join(" · ");

  return (
    <>
      <PageHead title="Level change history" eyebrow="ICT Support Desk"
        description={`Every change of a student's academic level within your reach (${list.scope}), newest first: progressions and corrections by ICT Support, with the reason and the ticket, and the Registry's and the cohort corrections.`}
        actions={<><LinkBtn href="/helpdesk/levels">Student level management</LinkBtn><LinkBtn href="/helpdesk/password-reset/history">Password reset history</LinkBtn></>} />
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ action: String(f.get("action") ?? ""), q: String(f.get("q") ?? "").trim(), from: String(f.get("from") ?? ""), to: String(f.get("to") ?? "") }); }}>
        <Field id="lh-action" label="Action"><select id="lh-action" name="action" className="ctl" defaultValue={filters.action}>{HISTORY_ACTIONS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
        <Field id="lh-q" label="Student, matric number or ticket"><input id="lh-q" name="q" className="ctl" defaultValue={filters.q} maxLength={80} /></Field>
        <Field id="lh-from" label="From"><input id="lh-from" name="from" type="date" className="ctl" defaultValue={filters.from} /></Field>
        <Field id="lh-to" label="To"><input id="lh-to" name="to" type="date" className="ctl" defaultValue={filters.to} /></Field>
        <Btn kind="primary" type="submit" busyLabel="Filtering...">Filter</Btn>
      </form>
      <Panel title={`${list.total.toLocaleString("en-GB")} level change${list.total === 1 ? "" : "s"}`}
        right={<div className="row row--inline" style={{ gap: 6 }}>
          <Btn kind="ghost" size="sm" disabled={!list.total} busyLabel="Preparing Excel..." onClick={async () => {
            const rows = await all();
            if (!rows) return;
            downloadBlob(await brandedXlsx("Level Change History", HEAD, rows.map(line), { sub, serial: docSerial("LVL") }), "level-change-history.xlsx");
          }}>Excel</Btn>
          <Btn kind="ghost" size="sm" disabled={!list.total} busyLabel="Preparing PDF..." onClick={async () => {
            const rows = await all();
            if (rows) brandedPrint("Level Change History", sub, HEAD, rows.map(line), docSerial("LVL"));
          }}>PDF</Btn>
        </div>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Matric No", "Previous|num", "New|num", "Action", "Changed by", "Reason", "Ticket|mid", "Date/time"]}
            rows={list.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{(page - 1) * (list.size || 50) + i + 1}</span>,
              <span key="s"><Link className="lnk" href={`/helpdesk/students/${r.student_id}`}>{r.student}</Link><div className="sub2">{r.programme ?? ""}</div></span>,
              <span key="m" className="tnum">{r.number ?? "—"}</span>,
              <span key="p" className="tnum">{r.previous_level ?? "—"}</span>,
              <b key="n" className="tnum">{r.new_level}</b>,
              <span key="a">{ruleWord(r.rule)}</span>,
              <span key="b">{r.changed_by ?? "—"}<div className="sub2">{r.actor_office ?? ""}</div></span>,
              <span key="r" className="sub2">{r.reason}</span>,
              <span key="t" className="tnum sub2">{r.ticket_number ?? "—"}</span>,
              <span key="w" className="sub2 tnum">{when(r.decided_at)}</span>,
            ])} />
        ) : <PBody><div className="sub2">No level change matches.</div></PBody>}
        {pages > 1 ? (
          <PBody><div className="row row--inline" style={{ gap: "var(--s-2)" }}>
            {page > 1 ? <Btn kind="ghost" size="sm" onClick={() => nav({ page: String(page - 1) })}>Previous</Btn> : null}
            <span className="sub2">Page {page} of {pages}</span>
            {page < pages ? <Btn kind="ghost" size="sm" onClick={() => nav({ page: String(page + 1) })}>Next</Btn> : null}
          </div></PBody>
        ) : null}
      </Panel>
    </>
  );
}
