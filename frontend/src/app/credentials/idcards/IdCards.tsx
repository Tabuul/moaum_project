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
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface CardDesk {
  cards: { id: string; card_no: string; issued_at: string; valid_to: string; state: string; ended_at: string | null; ended_reason: string | null; student_id: string; matric_no: string; surname: string; other_names: string; programme: string; current_level: number }[];
  waiting: { student_id: string; matric_no: string; surname: string; other_names: string; programme: string; current_level: number; status?: string; had_one: boolean }[];
}

export function IdCards({ desk, q, actingOffice }: { desk: CardDesk; q: string; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = ["library", "security", "super"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [search, setSearch] = useState(q);

  async function act(key: string, path: string, body: unknown, reason: string) {
    setBusy(key);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/credentials/identity-cards${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
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
        The Library prints it when the Bursary&rsquo;s position releases ID_CARD &mdash; the first instalment under the recommended scheme &mdash; and Security hands it over against the photograph on file. A student with no matriculation number has no card yet; a lost card is ended here and a replacement issued.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Waiting for a card" right={<form onSubmit={(e) => { e.preventDefault(); queryNav(`/credentials/idcards?q=${encodeURIComponent(search)}`); }} style={{ display: "inline-flex", gap: 6 }}><input className="ws__in" value={search} placeholder="Matriculation number or surname" onChange={(e) => setSearch(e.target.value)} aria-label="Find a student" /><Btn kind="ghost" onClick={() => queryNav(`/credentials/idcards?q=${encodeURIComponent(search)}`)}>Find</Btn></form>}>
        <DTable cols={["Student", "Programme", "Level|mid", "Status|mid", "|num"]} rows={desk.waiting.map((w) => [
          <Two key="s" a={`${w.surname}, ${w.other_names}`} b={w.matric_no} />, <span className="sub2" key="p">{w.programme}</span>, <span className="tnum" key="l">{w.current_level}</span>,
          <Pil key="st" kind={w.status === "ACTIVE" ? "ok" : w.status === "PROBATION" ? "warn" : "grey"}>{(w.status ?? "—").charAt(0) + (w.status ?? "—").slice(1).toLowerCase()}</Pil>,
          <Btn kind="primary" key="i" disabled={!may || busy !== null} onClick={() => void act(`issue-${w.student_id}`, `/students/${w.student_id}/issue`, { reason: w.had_one ? "replacement" : null }, `Identity card issued to ${w.matric_no}`)}>{busy === `issue-${w.student_id}` ? "Issuing…" : w.had_one ? "Issue a replacement" : "Issue the card"}</Btn>,
        ])} texts={desk.waiting.map((w) => `${w.surname} ${w.other_names} ${w.matric_no} ${w.programme}`)} />
        {!desk.waiting.length ? <div className="card__body"><div className="sub2">Nobody is waiting{q ? ` for "${q}"` : ""}.</div></div> : null}
      </Panel>
      <Panel title="Cards issued" right={`${desk.cards.length}`}>
        <DTable cols={["Card", "Student", "Issued|mid", "Valid to|mid", "State|mid", "|num"]} rows={desk.cards.map((c) => [
          <span className="tnum" key="n">{c.card_no}</span>, <Two key="s" a={`${c.surname}, ${c.other_names}`} b={`${c.matric_no} · ${c.programme}`} />,
          <span className="sub2 tnum" key="i">{new Date(c.issued_at).toLocaleDateString("en-GB")}</span>, <span className="sub2 tnum" key="v">{new Date(c.valid_to).toLocaleDateString("en-GB")}</span>,
          c.state === "ISSUED" ? <Pil kind="ok" key="t">Live</Pil> : <Pil kind="grey" key="t">{c.state.charAt(0) + c.state.slice(1).toLowerCase()}{c.ended_reason ? ` · ${c.ended_reason}` : ""}</Pil>,
          c.state === "ISSUED" ? <Btn kind="ghost" key="l" disabled={!may || busy !== null} onClick={() => { const reason = window.prompt("What happened to the card? This goes on the record."); if (!reason) return; void act(`lost-${c.id}`, `/students/${c.student_id}/lost`, { reason }, `Identity card ${c.card_no} reported lost: ${reason}`); }}>Report lost</Btn> : <span key="l" />,
        ])} texts={desk.cards.map((c) => `${c.card_no} ${c.surname} ${c.other_names} ${c.matric_no}`)} />
        {!desk.cards.length ? <div className="card__body"><div className="sub2">No card has been issued yet.</div></div> : null}
      </Panel>
    </>
  );
}
