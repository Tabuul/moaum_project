"use client";

/**
 * The Library's card desk — proto/part25.html tIdCards, as drawn: who on
 * the matriculation register holds no live card, the cards issued, and the
 * act of issuing one — on the matriculation number, when the scheme
 * releases ID_CARD, one live card at a time. A lost card is ended on the
 * record and replaced.
 */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface CardDesk {
  cards: { id: string; card_no: string; issued_at: string; valid_to: string; state: string; ended_at: string | null; ended_reason: string | null; student_id: string; matric_no: string; surname: string; other_names: string; programme: string; current_level: number; verify_path?: string }[];
  waiting: { student_id: string; matric_no: string; surname: string; other_names: string; programme: string; current_level: number; status?: string; had_one: boolean }[];
}
/** V439: the staff cards in the register */
export interface StaffDesk {
  cards: { id: string; card_no: string; issued_at: string; valid_to: string; state: string; ended_reason: string | null; person_id: string; staff_number: string | null; surname: string; given_names: string; department: string | null; verify_path: string }[];
}

export function IdCards({ desk, staff, q, actingOffice }: { desk: CardDesk; staff: StaffDesk | null; q: string; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = ["library", "security", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [search, setSearch] = useState(q);
  const [staffNo, setStaffNo] = useState("");

  async function act(key: string, path: string, body: unknown, reason: string) {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/credentials/identity-cards${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(reason);
      router.refresh();
    } finally {
      setBusy(null);
    }
  }

  const live = desk.cards.filter((c) => c.state === "ISSUED");
  return (
    <>
      <Tiles items={[
        ["Waiting for a card", String(desk.waiting.length), desk.waiting.length ? "var(--red-ink)" : null, "On the matriculation register, no live card"],
        ["Live cards", String(live.length), "var(--green-ink)", "One per student"],
        ["Lost or replaced", String(desk.cards.length - live.length), null, "Ended on the record"],
        ["Issued today", String(desk.cards.filter((c) => c.issued_at.slice(0, 10) === new Date().toISOString().slice(0, 10)).length), null, "By the Library"],
      ]} />
      <Note kind="info" title="A card is keyed on the matriculation number and released by the scheme">
        Printed once the first instalment is paid; Security hands it over against the photograph on file. A lost card is ended here and replaced.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Waiting for a card" right={<form onSubmit={(e) => { e.preventDefault(); queryNav(`/credentials/idcards?q=${encodeURIComponent(search)}`); }} className="row row--inline row--tight"><input className="ws__in" value={search} placeholder="Matriculation number or surname" onChange={(e) => setSearch(e.target.value)} aria-label="Find a student" /><Btn kind="ghost" onClick={() => queryNav(`/credentials/idcards?q=${encodeURIComponent(search)}`)}>Find</Btn></form>}>
        <DTable cols={["Student", "Programme", "Level|mid", "Status|mid", "|num"]} rows={desk.waiting.map((w) => [
          <Two key="s" a={`${w.surname}, ${w.other_names}`} b={w.matric_no} />, <span className="sub2" key="p">{w.programme}</span>, <span className="tnum" key="l">{w.current_level}</span>,
          <Pil key="st" kind={w.status === "ACTIVE" ? "ok" : w.status === "PROBATION" ? "warn" : "grey"}>{(w.status ?? "—").charAt(0) + (w.status ?? "—").slice(1).toLowerCase()}</Pil>,
          <Btn kind="primary" key="i" disabled={!may || busy !== null} onClick={() => void act(`issue-${w.student_id}`, `/students/${w.student_id}/issue`, { reason: w.had_one ? "replacement" : null }, `Identity card issued to ${w.matric_no}`)}>{busy === `issue-${w.student_id}` ? "Issuing…" : w.had_one ? "Issue a replacement" : "Issue the card"}</Btn>,
        ])} texts={desk.waiting.map((w) => `${w.surname} ${w.other_names} ${w.matric_no} ${w.programme}`)} />
        {!desk.waiting.length ? <PBody><div className="sub2">Nobody is waiting{q ? ` for "${q}"` : ""}.</div></PBody> : null}
      </Panel>
      <Panel title="Cards issued" right={`${desk.cards.length}`}>
        <DTable cols={["Card", "Student", "Issued|mid", "Valid to|mid", "State|mid", "|num"]} rows={desk.cards.map((c) => [
          <span key="n"><span className="tnum">{c.card_no}</span>{c.verify_path && c.state === "ISSUED" ? <div className="sub2"><a href={c.verify_path} target="_blank" rel="noopener" title="The address the card's QR carries; the public page shows the card only with this code">Check address</a></div> : null}</span>, <Two key="s" a={`${c.surname}, ${c.other_names}`} b={`${c.matric_no} · ${c.programme}`} />,
          <span className="sub2 tnum" key="i">{new Date(c.issued_at).toLocaleDateString("en-GB")}</span>, <span className="sub2 tnum" key="v">{new Date(c.valid_to).toLocaleDateString("en-GB")}</span>,
          c.state === "ISSUED" ? <Pil kind="ok" key="t">Live</Pil> : <Pil kind="grey" key="t">{c.state.charAt(0) + c.state.slice(1).toLowerCase()}{c.ended_reason ? ` · ${c.ended_reason}` : ""}</Pil>,
          c.state === "ISSUED" ? <span key="l" className="row row--tight"><a className="btn btn--ghost btn--sm" href={`/credentials/idcards/student/pdf?id=${encodeURIComponent(c.student_id)}`} target="_blank" rel="noopener">Print</a><Btn kind="ghost" disabled={!may || busy !== null} onClick={() => { const reason = window.prompt("What happened to the card? This goes on the record."); if (!reason) return; void act(`lost-${c.id}`, `/students/${c.student_id}/lost`, { reason }, `Identity card ${c.card_no} reported lost: ${reason}`); }}>Report lost</Btn></span> : <span key="l" />,
        ])} texts={desk.cards.map((c) => `${c.card_no} ${c.surname} ${c.other_names} ${c.matric_no}`)} />
        {!desk.cards.length ? <PBody><div className="sub2">No card has been issued yet.</div></PBody> : null}
      </Panel>
      {staff ? (
        <Panel title="Staff identity cards" right={may ? <form onSubmit={(e) => { e.preventDefault(); if (staffNo.trim()) void act("staff-issue", "/staff/issue", { staffNumber: staffNo.trim() }, `Staff identity card issued to ${staffNo.trim()}`); }} className="row row--inline row--tight"><input className="ws__in" value={staffNo} placeholder="Staff number" onChange={(e) => setStaffNo(e.target.value)} aria-label="Staff number to issue a card to" /><Btn kind="primary" disabled={busy !== null || !staffNo.trim()} onClick={() => { if (staffNo.trim()) void act("staff-issue", "/staff/issue", { staffNumber: staffNo.trim() }, `Staff identity card issued to ${staffNo.trim()}`); }}>Issue card</Btn></form> : `${staff.cards.length}`}>
          <DTable cols={["Card", "Member of staff", "Issued|mid", "Valid to|mid", "State|mid", "|num"]} rows={staff.cards.map((c) => [
            <span key="n"><span className="tnum">{c.card_no}</span>{c.state === "ISSUED" ? <div className="sub2"><a href={c.verify_path} target="_blank" rel="noopener" title="The address the card's QR carries">Check address</a></div> : null}</span>,
            <Two key="s" a={`${c.surname}, ${c.given_names}`} b={`${c.staff_number ?? ""}${c.department ? ` · ${c.department}` : ""}`} />,
            <span className="sub2 tnum" key="i">{new Date(c.issued_at).toLocaleDateString("en-GB")}</span>, <span className="sub2 tnum" key="v">{new Date(c.valid_to).toLocaleDateString("en-GB")}</span>,
            c.state === "ISSUED" ? <Pil kind="ok" key="t">Live</Pil> : <Pil kind="grey" key="t">{c.state.charAt(0) + c.state.slice(1).toLowerCase()}{c.ended_reason ? ` · ${c.ended_reason}` : ""}</Pil>,
            c.state === "ISSUED" ? <span key="l" className="row row--tight"><a className="btn btn--ghost btn--sm" href={`/staff/idcard/pdf?id=${encodeURIComponent(c.person_id)}`} target="_blank" rel="noopener">Print</a>{may ? <Btn kind="ghost" disabled={busy !== null} onClick={() => { const reason = window.prompt("What happened to the card? This goes on the record."); if (!reason) return; void act(`slost-${c.id}`, `/staff/${c.person_id}/lost`, { reason }, `Staff identity card ${c.card_no} reported lost: ${reason}`); }}>Report lost</Btn> : null}</span> : <span key="l" />,
          ])} texts={staff.cards.map((c) => `${c.card_no} ${c.surname} ${c.given_names} ${c.staff_number ?? ""}`)} />
          {!staff.cards.length ? <PBody><div className="sub2">No staff card has been issued yet. A card is issued on the staff number to a member of staff in office; its QR carries the address the public check answers.</div></PBody> : null}
        </Panel>
      ) : null}
    </>
  );
}
