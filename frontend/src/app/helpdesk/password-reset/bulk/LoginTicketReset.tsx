"use client";

/**
 * Bulk Password Reset, from the Login Issues tickets (V594): every open login and password ticket within the agent's reach, the
 * oldest first — a student's own, and a request from the sign-in page with the student who holds the number given (V594). The
 * eligible are selected all at once, across pages (ticket ids only: the server checks each again), and reset together by the
 * reset from tickets (V582): each student once to the matriculation number, changed at the next sign-in, every one of their tickets
 * resolved with it. A ticket that cannot be reset says why and stays on the desk. No password is shown or recorded.
 */
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { requesterKind, type TicketRow } from "@/lib/helpdesk";
import { RESET_STATE, selectable, tickPage, toggle, type ResetState, type Summary } from "@/lib/ticket-reset";
import { TicketResetDialog } from "../../TicketResetDialog";

export interface TicketPage { rows: TicketRow[]; total: number; page: number; size: number }

const SIZE = 50;
const count = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-NG");
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });

/** the queue's own query for the open login and password tickets, the oldest first */
const query = (page: number, q: string, extra?: Record<string, string>) => {
  const qs = new URLSearchParams({ issue: "login", status: "open", sort: "created", dir: "asc", page: String(page), size: String(SIZE) });
  if (q) qs.set("q", q);
  for (const [k, v] of Object.entries(extra ?? {})) qs.set(k, v);
  return `/api/bff/api/v1/helpdesk/tickets?${qs.toString()}`;
};

export function LoginTicketReset({ first, summary }: { first: TicketPage; summary: Summary | null }) {
  const [list, setList] = useState<TicketPage>(first);
  const [figures, setFigures] = useState(summary?.figures ?? null);
  const [page, setPage] = useState(1);
  const [q, setQ] = useState("");
  const [search, setSearch] = useState("");
  const [ticked, setTicked] = useState<Set<string>>(new Set());
  const [finding, setFinding] = useState(false);
  const [resetting, setResetting] = useState<string[] | null>(null);
  const [tick, setTick] = useState(0);
  const may = !!summary?.may;

  // the page asked again on a new page, a search, or after a reset; the first page came with the screen
  const read = useCallback(async (p: number, s: string) => {
    const r = await fetch(query(p, s), { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The tickets could not be read just now." }); return null; }
    return j as TicketPage;
  }, []);
  useEffect(() => {
    if (tick === 0 && page === 1 && search === "") return;
    let live = true;
    void read(page, search).then((j) => { if (live && j) setList(j); });
    void fetch("/api/bff/api/v1/helpdesk/tickets/password-reset/summary", { cache: "no-store" })
      .then(async (r) => { if (live && r.ok) setFigures(((await r.json()) as Summary).figures); });
    return () => { live = false; };
  }, [page, search, tick, read]);

  /** every eligible ticket of the search, on every page — ids from the server (the reset checks each again) */
  async function selectAll() {
    setFinding(true);
    try {
      const r = await fetch(query(1, search, { eligibleIds: "true" }), { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const ids = (j as { ids: string[]; over: boolean }).ids;
      setTicked(new Set(ids));
      notify(ids.length ? `${count(ids.length)} eligible ticket${ids.length === 1 ? "" : "s"} selected` : "No ticket here may be reset");
      if ((j as { over: boolean }).over) notify("The first 10,000 eligible tickets are selected; reset them, then select again.");
    } finally { setFinding(false); }
  }

  const pages = Math.max(1, Math.ceil(list.total / SIZE));
  const firstRow = (list.page - 1) * list.size;
  const pageEligible = list.rows.filter((r) => selectable(r.reset_state)).length;

  return (
    <>
      <PageHead title="Bulk password reset" eyebrow="ICT Support Desk"
        description="The open Login Issues tickets — a student's own, and those asked from the sign-in page with the student who holds the number given. Select the eligible, all at once, and reset them together: each student is reset once to the matriculation number and must change it at the next sign-in, and every ticket of theirs is resolved with it. A ticket that cannot be reset says why and stays on the desk. No password is shown or recorded."
        actions={<><LinkBtn href="/helpdesk/password-reset">One student</LinkBtn><LinkBtn href="/helpdesk/password-reset/bulk/students">Students without a ticket</LinkBtn>
          <LinkBtn href="/helpdesk/password-reset/tickets">Resets from tickets</LinkBtn><LinkBtn href="/helpdesk/password-reset/history">Password reset history</LinkBtn></>} />

      {figures ? (
        <Tiles cls="grid--3" items={[
          ["Open login tickets", count(figures.open), figures.open ? "var(--amber-ink)" : null, `${count(figures.public)} asked from the sign-in page`],
          ["A student found", count(figures.students), null, "their own ticket, or the number given"],
          ["No student for the number", count(figures.unmatched), figures.unmatched ? "var(--red-ink)" : null, "asked from the sign-in page; the desk confirms who they are"],
          ["In a reset now", count(figures.inOperation), null, "being reset, or waiting for approval"],
          ["Failed before", count(figures.failed), figures.failed ? "var(--amber-ink)" : null, "eligible again"],
          ["Reset today", count(figures.resetToday), figures.resetToday ? "var(--green-ink)" : null, "tickets resolved by a reset"],
        ]} />
      ) : null}

      {!may ? (
        <Note kind="info" title="Resets from tickets are not on your posting">
          You can read the tickets; the Head of the ICT Support Desk grants BULK_RESET_FROM_TICKETS to reset them from here.
        </Note>
      ) : null}

      <Panel title="Login Issues tickets" right={<span className="sub2 tnum">{count(list.total)} open · the oldest first</span>}>
        <PBody>
          <form className="row row--end" style={{ gap: 8, flexWrap: "wrap" }} onSubmit={(e) => { e.preventDefault(); setPage(1); setSearch(q.trim()); }}>
            <Field id="lt-q" label="Ticket, name, number given, e-mail or phone" style={{ flex: "2 1 300px" }}>
              <input id="lt-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="TICK-2026-10496 or BSU/SS/PUB/23/71456" />
            </Field>
            <Btn kind="primary" type="submit">Search</Btn>
            {search ? <Btn kind="ghost" onClick={() => { setQ(""); setSearch(""); setPage(1); }}>Clear</Btn> : null}
          </form>
          {may ? (
            <div className="row mt-2" style={{ gap: 8, flexWrap: "wrap", alignItems: "center" }}>
              <b className="tnum">Selected: {count(ticked.size)}</b>
              <Btn kind="ghost" size="sm" busy={finding} busyLabel="Finding…" onClick={() => void selectAll()}>Select all eligible tickets</Btn>
              <Btn kind="ghost" size="sm" disabled={!pageEligible} onClick={() => setTicked((t) => tickPage(t, list.rows, true))}>Select the eligible on this page</Btn>
              <Btn kind="ghost" size="sm" disabled={!ticked.size} onClick={() => setTicked(new Set())}>Clear selection</Btn>
              <span style={{ flex: 1 }} />
              <Btn kind="primary" disabled={!ticked.size} onClick={() => setResetting([...ticked])}>
                {ticked.size ? `Reset and resolve ${count(ticked.size)} ticket${ticked.size === 1 ? "" : "s"}` : "Reset and resolve"}
              </Btn>
            </div>
          ) : null}
        </PBody>
        {list.rows.length ? (
          <DTable pageSize={0} cols={[...(may ? ["|mid"] : []), "S/N|num", "Ticket", "Requester", "Student", "Password reset", "Raised|mid"]} rows={list.rows.map((r, i) => {
            const st = r.reset_state ? RESET_STATE[r.reset_state as ResetState] : null;
            const own = r.requester_kind === "STUDENT";
            return [
              ...(may ? [selectable(r.reset_state)
                ? <input key="tk" type="checkbox" className="chk" aria-label={`Select ${r.number} for a password reset`} checked={ticked.has(r.id)} onChange={(e) => setTicked((t) => toggle(t, r.id, e.target.checked))} />
                : <span key="tk" />] : []),
              <span key="sn" className="tnum sub2">{firstRow + i + 1}</span>,
              <span key="t"><Link className="lnk tnum b600" href={`/helpdesk/tickets/${r.id}`}>{r.number}</Link><div className="sub2">{r.subject}</div></span>,
              <span key="r"><strong>{r.requester_name}</strong><div className="sub2 tnum">{r.requester_number ?? r.requester_email ?? ""} · {requesterKind(r.requester_kind)}</div></span>,
              own
                ? <span key="s">{r.requester_name}<div className="sub2 tnum">{r.requester_number ?? ""}{r.department ? ` · ${r.department}` : ""}</div></span>
                : r.matched_name
                  ? <span key="s">{r.matched_name}<div className="sub2 tnum">{r.matched_matric ?? ""}{r.matched_programme ? ` · ${r.matched_programme}` : ""}{r.matched_level ? ` · ${r.matched_level}` : ""}</div></span>
                  : <span key="s" className="sub2">No student found</span>,
              st ? <Pil key="rs" kind={st.tone}>{st.label}</Pil> : <span key="rs" className="sub2">Not eligible</span>,
              <span key="cr" className="tnum sub2">{when(r.created_at)}</span>,
            ];
          })} />
        ) : (
          <PBody><Note kind="ok" title={search ? "No open login ticket matches" : "No open login ticket"}>{search ? "Clear the search to see every open Login Issues ticket." : "Every Login Issues ticket within your reach is resolved."}</Note></PBody>
        )}
        {pages > 1 ? (
          <PBody>
            <div className="row row--between">
              <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(page - 1)}>Previous</Btn>
              <span className="sub2 tnum">Page {page} of {count(pages)} · {count(list.total)} tickets{ticked.size ? ` · ${count(ticked.size)} selected across pages` : ""}</span>
              <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => setPage(page + 1)}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>

      {resetting ? (
        <TicketResetDialog ticketIds={resetting} onClose={(done) => { setResetting(null); if (done) { setTicked(new Set()); setTick((n) => n + 1); } }} />
      ) : null}
    </>
  );
}
