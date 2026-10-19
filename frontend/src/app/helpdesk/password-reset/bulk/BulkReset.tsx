"use client";

/**
 * Bulk Password Reset (V559): the students the agent may reset — searched, filtered, or those with an open Login Issues ticket —
 * chosen with their boxes across pages, and reset in one operation to the default student credential (the matriculation number,
 * changed at the next sign-in) by the one reset service of the single reset. Before anything is done the server says which may be
 * reset and why not the others; the reason is required; the work runs on the server and its real progress is shown; the result
 * names every student reset and every one not, with why. No password is ever sent or shown.
 */
import { useState, useSyncExternalStore } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MAX, STATUS, type BulkHistory, type DeskSummary, type Preview } from "@/lib/bulk-reset";
import { BulkConfirm, call, previewFor } from "./BulkConfirm";

export interface Filters { q: string; fac: string; dept: string; prog: string; level: string; status: string; account: string; login: boolean; page: number }
export interface Candidate {
  id: string; name: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null; faculty: string | null; department: string | null;
  programme: string | null; level: number | null; status: string; account: "NO_ACCOUNT" | "LOCKED" | "CHANGE_REQUIRED" | "NORMAL"; last_signed_in_at: string | null;
  ticket_id: string | null; ticket_number: string | null; ticket_status: string | null;
}
export interface Candidates {
  total: number; page: number; size: number; rows: Candidate[]; scope: string;
  options?: { faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code: string }[]; programmes: { code: string; name: string; dept_code: string }[] };
}
/** a student chosen: by id, with the open Login Issues ticket the reset is recorded on (no name or number is kept) */
interface Chosen { ticket: string | null }

const KEY = "moaum.bulkReset.selection";
const count = (n: number) => Number(n).toLocaleString("en-NG");
const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const ACCOUNT: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  NO_ACCOUNT: ["No account yet", "grey"], LOCKED: ["Locked", "bad"], CHANGE_REQUIRED: ["Must change", "warn"], NORMAL: ["Normal", "ok"],
};
const STUDENT_STATUSES = ["ACTIVE", "PROBATION", "ADMITTED", "DEFERRED", "DORMANT", "GRADUATED"];

/* the selection, kept in this browser tab across pages, filters and a reload; read as an external store so the server and the first
   paint agree (nothing chosen) */
const NONE: Map<string, Chosen> = new Map();
const listeners = new Set<() => void>();
let held: Map<string, Chosen> | null = null;
const subscribe = (cb: () => void) => { listeners.add(cb); return () => { listeners.delete(cb); }; };
const readChosen = () => {
  if (held === null) {
    try {
      const raw = window.sessionStorage.getItem(KEY);
      held = raw ? new Map(JSON.parse(raw) as [string, Chosen][]) : NONE;
    } catch { held = NONE; }
  }
  return held;
};
const setChosen = (change: (m: Map<string, Chosen>) => Map<string, Chosen>) => {
  held = change(readChosen());
  try { window.sessionStorage.setItem(KEY, JSON.stringify([...held.entries()])); } catch { /* kept for this page only */ }
  listeners.forEach((l) => l());
};

export function BulkReset({ f, list, summary, history }: { f: Filters; list: Candidates; summary: DeskSummary | null; history: BulkHistory | null }) {
  const nav = useQueryNav();
  const router = useRouter();
  const chosen = useSyncExternalStore(subscribe, readChosen, () => NONE);
  const [q, setQ] = useState(f.q);
  const [busy, setBusy] = useState<"all" | "preview" | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [preview, setPreview] = useState<Preview | null>(null);
  const [note, setNote] = useState<string | null>(null);

  const opts = list.options;
  const depts = (opts?.departments ?? []).filter((d) => !f.fac || d.faculty_code === f.fac);
  const progs = (opts?.programmes ?? []).filter((p) => (!f.dept || p.dept_code === f.dept) && (!f.fac || depts.some((d) => d.code === p.dept_code)));
  const go = (change: Partial<Filters>) => {
    const next = { ...f, page: 1, ...change };
    const qs = new URLSearchParams();
    for (const k of ["q", "fac", "dept", "prog", "level", "status", "account"] as const) if (next[k]) qs.set(k, String(next[k]));
    if (next.login) qs.set("login", "1");
    if (next.page > 1) qs.set("page", String(next.page));
    nav(`/helpdesk/password-reset/bulk${qs.toString() ? `?${qs.toString()}` : ""}`);
  };
  const pageIds = list.rows.map((r) => r.id);
  const allOnPage = pageIds.length > 0 && pageIds.every((id) => chosen.has(id));
  const pages = Math.max(1, Math.ceil(list.total / list.size));

  function toggle(r: Candidate, on: boolean) {
    setChosen((m) => {
      const n = new Map(m);
      if (on) n.set(r.id, { ticket: r.ticket_id });
      else n.delete(r.id);
      return n;
    });
  }
  function togglePage(on: boolean) {
    setChosen((m) => {
      const n = new Map(m);
      for (const r of list.rows) {
        if (on) n.set(r.id, { ticket: r.ticket_id });
        else n.delete(r.id);
      }
      return n;
    });
  }
  async function selectAllMatching() {
    setBusy("all");
    setProblem(null);
    const qs = new URLSearchParams({ all: "true" });
    for (const k of ["q", "fac", "dept", "prog", "level", "status", "account"] as const) if (f[k]) qs.set(k, String(f[k]));
    if (f.login) qs.set("login", "true");
    const r = await call<{ ids: string[]; tickets: Record<string, string>; over: boolean }>(`/candidates?${qs.toString()}`);
    setBusy(null);
    if (!r.ok) { setProblem(r.problem); return; }
    setChosen((m) => {
      const n = new Map(m);
      for (const id of r.data.ids) if (!n.has(id)) n.set(id, { ticket: r.data.tickets[id] ?? null });
      return n;
    });
    setNote(r.data.over ? `The first ${count(r.data.ids.length)} matching students are chosen: one operation resets 1,000 at most.` : `${count(r.data.ids.length)} matching students chosen.`);
  }

  async function openPreview() {
    if (!chosen.size) return;
    setBusy("preview");
    setProblem(null);
    const r = await previewFor([...chosen.keys()]);
    setBusy(null);
    if (!r.ok) { setProblem(r.problem); return; }
    setPreview(r.data);
  }
  const tickets = () => {
    const out: Record<string, string> = {};
    chosen.forEach((c, id) => { if (c.ticket) out[id] = c.ticket; });
    return out;
  };

  return (
    <>
      <PageHead title="Bulk password reset" eyebrow="ICT Support Desk"
        description="Choose the students — by search, by filter, or those with an open Login Issues ticket — and reset them together. Each is reset to the matriculation number and must change it at the next sign-in; each is checked against your scope and the desk's policy, and a student who cannot be reset is named with the reason. No password is shown or recorded."
        actions={<><LinkBtn href="/helpdesk/password-reset">One student</LinkBtn><LinkBtn href="/helpdesk/password-reset/history">Password reset history</LinkBtn></>} />

      {summary ? (
        <Tiles cls="grid--3" items={[
          ["Login issues", count(summary.loginIssues), summary.loginIssues ? "var(--amber-ink)" : null, "students with an open ticket", "/helpdesk/password-reset/bulk?login=1"],
          ["Awaiting approval", count(summary.awaitingApproval ?? 0), summary.awaitingApproval ? "var(--amber-ink)" : null,
            summary.scope === "The University" ? "bulk resets for you to decide" : "your bulk resets", "/helpdesk/password-reset/bulk/history?status=AWAITING_APPROVAL"],
          ["Resets today", count(summary.resetsToday), null, summary.scope === "The University" ? "at the desk" : "yours", "/helpdesk/password-reset/history"],
          ["Bulk resets today", count(summary.bulkToday), null, "operations", "/helpdesk/password-reset/bulk/history"],
          ["Students reset", count(summary.studentsResetToday), summary.studentsResetToday ? "var(--green-ink)" : null, "in bulk today", "#bulk-history"],
          ["Failed resets", count(summary.failedToday), summary.failedToday ? "var(--red-ink)" : null, "in bulk today", "#bulk-history"],
        ]} />
      ) : null}

      <Panel title="Choose the students" right={<span className="sub2">Your scope: {list.scope}</span>}>
        <PBody>
          <form className="row row--end" style={{ gap: 8, flexWrap: "wrap" }} onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}>
            <Field id="br-q" label="Name, matriculation, JAMB or application number, phone, e-mail or ticket" style={{ flex: "2 1 300px" }}>
              <input id="br-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="MOAU/SC/CSC/26/10001" />
            </Field>
            <Field id="br-fac" label="Faculty" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="br-fac" value={f.fac} onChange={(v) => go({ fac: v, dept: "", prog: "" })} allLabel="Any faculty" options={(opts?.faculties ?? []).map((x) => ({ value: x.code, label: x.name }))} />
            </Field>
            <Field id="br-dept" label="Department" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="br-dept" value={f.dept} onChange={(v) => go({ dept: v, prog: "" })} allLabel="Any department" options={depts.map((x) => ({ value: x.code, label: x.name }))} />
            </Field>
            <Field id="br-prog" label="Programme" style={{ flex: "1 1 200px" }}>
              <SearchSelect id="br-prog" value={f.prog} onChange={(v) => go({ prog: v })} allLabel="Any programme" options={progs.map((x) => ({ value: x.code, label: x.name }))} />
            </Field>
            <Field id="br-level" label="Level" style={{ flex: "0 1 110px" }}>
              <select id="br-level" className="ctl" value={f.level} onChange={(e) => go({ level: e.target.value })}>
                <option value="">Any</option>
                {[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l}</option>)}
              </select>
            </Field>
            <Field id="br-status" label="Student status" style={{ flex: "0 1 150px" }}>
              <select id="br-status" className="ctl" value={f.status} onChange={(e) => go({ status: e.target.value })}>
                <option value="">Any</option>
                {STUDENT_STATUSES.map((s) => <option key={s} value={s}>{s[0] + s.slice(1).toLowerCase()}</option>)}
              </select>
            </Field>
            <Field id="br-account" label="Account" style={{ flex: "0 1 160px" }}>
              <select id="br-account" className="ctl" value={f.account} onChange={(e) => go({ account: e.target.value })}>
                <option value="">Any</option>
                {Object.entries(ACCOUNT).map(([k, [v]]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </Field>
            <label className="row row--inline row--tight" style={{ gap: 6, paddingBottom: 8 }}>
              <input type="checkbox" className="pchk" checked={f.login} onChange={(e) => go({ login: e.target.checked })} /> Login issues only
            </label>
            <Btn kind="ghost" type="submit">Search</Btn>
          </form>
        </PBody>

        <PBody>
          <div className="row row--between" style={{ gap: 8, flexWrap: "wrap" }}>
            <div className="row row--inline" style={{ gap: 8, flexWrap: "wrap" }}>
              <b>{chosen.size ? `${count(chosen.size)} student${chosen.size === 1 ? "" : "s"} selected` : "No student selected"}</b>
              <Btn kind="ghost" disabled={!list.rows.length} onClick={() => togglePage(!allOnPage)}>{allOnPage ? "Unselect this page" : "Select all on this page"}</Btn>
              <Btn kind="ghost" busy={busy === "all"} disabled={!list.total} onClick={() => void selectAllMatching()}>Select all {count(Math.min(list.total, MAX))} matching</Btn>
              <Btn kind="ghost" disabled={!chosen.size} onClick={() => { setChosen(() => new Map()); setNote(null); }}>Clear selection</Btn>
            </div>
            <Btn kind="urgent" busy={busy === "preview"} disabled={!chosen.size || chosen.size > MAX || busy !== null} onClick={() => void openPreview()}>Reset passwords ({count(chosen.size)})</Btn>
          </div>
          {chosen.size > MAX ? <div className="sub2 mt-1">One operation resets {count(MAX)} students at most: clear some of the {count(chosen.size)} chosen, and reset the rest in a second operation.</div> : null}
          {note ? <div className="sub2 mt-1">{note}</div> : null}
          {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
        </PBody>

        <div className="tablewrap" tabIndex={0}>
          <table className="tbl tbl--data">
            <thead>
              <tr>
                <th style={{ width: 32 }}><input type="checkbox" className="pchk" aria-label="Select every student on this page" checked={allOnPage} onChange={(e) => togglePage(e.target.checked)} /></th>
                <th>S/N</th><th>Student</th><th>Matriculation number</th><th>JAMB number</th><th>Faculty</th><th>Department</th><th>Programme</th>
                <th>Level</th><th>Status</th><th>Account</th><th>Last sign-in</th><th>Login issue</th>
              </tr>
            </thead>
            <tbody>
              {list.rows.map((r, i) => (
                <tr key={r.id} className={chosen.has(r.id) ? "is-on" : ""}>
                  <td><input type="checkbox" className="pchk" aria-label={`Select ${r.name}`} checked={chosen.has(r.id)} onChange={(e) => toggle(r, e.target.checked)} /></td>
                  <td className="tnum sub2">{(list.page - 1) * list.size + i + 1}</td>
                  <td><Link href={`/helpdesk/students/${r.id}`} className="b600">{r.name}</Link></td>
                  <td className="tnum">{r.matric_no ?? <span className="sub2">None ({r.admission_no ?? "—"})</span>}</td>
                  <td className="tnum sub2">{r.jamb_reg_no ?? "—"}</td>
                  <td className="sub2">{r.faculty ?? "—"}</td>
                  <td className="sub2">{r.department ?? "—"}</td>
                  <td>{r.programme ?? "—"}</td>
                  <td className="tnum">{r.level ?? "—"}</td>
                  <td className="sub2">{r.status[0] + r.status.slice(1).toLowerCase()}</td>
                  <td><Pil kind={ACCOUNT[r.account]?.[1] ?? "grey"}>{ACCOUNT[r.account]?.[0] ?? r.account}</Pil></td>
                  <td className="sub2 tnum">{r.last_signed_in_at ? when(r.last_signed_in_at) : "Never"}</td>
                  <td>{r.ticket_number ? <Link href={`/helpdesk/tickets/${r.ticket_id}`} className="tnum">{r.ticket_number}</Link> : <span className="sub2">—</span>}</td>
                </tr>
              ))}
              {!list.rows.length ? <tr><td colSpan={13} className="sub2">No student matches{f.login ? " with an open Login Issues ticket" : ""} within your scope.</td></tr> : null}
            </tbody>
          </table>
        </div>
        <PBody>
          <div className="row row--between">
            <span className="sub2">{count(list.total)} student{list.total === 1 ? "" : "s"} · page {list.page} of {pages}</span>
            <span className="row row--inline" style={{ gap: 6 }}>
              <Btn kind="ghost" disabled={list.page <= 1} onClick={() => go({ page: list.page - 1 })}>Previous</Btn>
              <Btn kind="ghost" disabled={list.page >= pages} onClick={() => go({ page: list.page + 1 })}>Next</Btn>
            </span>
          </div>
        </PBody>
      </Panel>

      {history ? (
        <div id="bulk-history">
          <Panel title="Bulk password reset history" right={<Link className="lnk" href="/helpdesk/password-reset/bulk/history">{history.everyone ? "Every bulk reset" : "All yours"} ({count(history.total)})</Link>}>
            <DTable pageSize={10} cols={["Reference", "Date", "Performed by", "Reason", "Selected|num", "Reset|num", "Failed|num", "Status", "Tickets"]} rows={history.rows.map((h) => [
              <Link key="r" href={`/helpdesk/password-reset/bulk/${h.id}`} className="b600 tnum">{h.reference}</Link>,
              <span key="d" className="tnum sub2">{when(h.created_at)}</span>,
              <span key="p">{h.performed_by}<div className="sub2">{h.office}</div></span>,
              <span key="w" className="sub2">{h.reason}</span>,
              <span key="t" className="tnum">{count(h.total)}</span>,
              <span key="s" className="tnum">{count(h.succeeded)}</span>,
              <span key="f" className="tnum">{count(h.failed)}</span>,
              <Pil key="st" kind={STATUS[h.status]?.[1] ?? "grey"}>{STATUS[h.status]?.[0] ?? h.status}</Pil>,
              <span key="k" className="sub2 tnum">{h.tickets ?? "—"}</span>,
            ])} />
          </Panel>
        </div>
      ) : null}

      {preview ? (
        <BulkConfirm preview={preview} ids={[...chosen.keys()]} tickets={tickets()} onClose={() => setPreview(null)}
          onEnded={() => { setChosen(() => new Map()); router.refresh(); }} />
      ) : null}
    </>
  );
}
