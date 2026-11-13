"use client";

/**
 * V605: the Security Unit's student identity card desk — search a student (matriculation, JAMB or admission number, name, phone,
 * e-mail; a page at a time from the server), see the particulars, the photograph, the matriculation number and the eligibility
 * reading with its reasons (finance's word on the fees; never the office clearance), preview the card, print it, hand it over,
 * replace it on a reason, end it, and read the whole history. Every act is the server's; the buttons say what is happening.
 */
import { useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Passport } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { cardSvg, type CardBack, type CardFace } from "@/lib/idcard-design";
import { getInstitution, institutionLogoUrl } from "@/lib/document/institution-client";
import { ACTION_WORDS, BLOOD_GROUPS, END_STATES, REPLACE_REASONS, actionsFor, cardStateWord, deskBloodGroup, eligibilityWords, eventWord, reasonWord,
  type CardRow, type DeskStudent, type SearchRow } from "@/lib/idcard-desk";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function IdCardDesk({ actingOffice, initialStudent }: { actingOffice: string | null; initialStudent: string | null }) {
  const may = ["security", "super"].includes(actingOffice ?? "");
  const [q, setQ] = useState("");
  const [rows, setRows] = useState<SearchRow[] | null>(null);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [searching, setSearching] = useState(false);
  const [sel, setSel] = useState<DeskStudent | null>(null);
  const [opening, setOpening] = useState<string | null>(initialStudent);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [replace, setReplace] = useState<{ reason: string; note: string } | null>(null);
  const [ending, setEnding] = useState<{ state: string; reason: string } | null>(null);
  const [showCard, setShowCard] = useState(false);
  const [loadedInitial, setLoadedInitial] = useState(false);
  // V622: the blood group the card prints, added or corrected here
  const [blood, setBlood] = useState("");

  async function get<T>(path: string): Promise<T | null> {
    const r = await fetch(`/api/bff/api/v1/credentials/identity-cards${path}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    return j as T;
  }

  async function post<T>(path: string, body: unknown, reason: string): Promise<T | null> {
    const r = await fetch(`/api/bff/api/v1/credentials/identity-cards${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
    return j as T;
  }

  async function search(p = 0) {
    const term = q.trim();
    if (term.length < 2) { notify("Type at least two characters of a number or a name"); return; }
    setSearching(true); setProblem(null);
    try {
      const j = await get<{ rows: SearchRow[]; total: number; page: number }>(`/students/search?q=${encodeURIComponent(term)}&page=${p}&size=25`);
      if (!j) return;
      setRows(j.rows); setTotal(j.total); setPage(j.page);
    } finally {
      setSearching(false);
    }
  }

  async function open(id: string) {
    setOpening(id); setProblem(null); setReplace(null); setEnding(null);
    try {
      const j = await get<DeskStudent>(`/students/${encodeURIComponent(id)}`);
      if (j) { setSel(j); setShowCard(false); setBlood(j.student.blood_group ?? ""); }
    } finally {
      setOpening(null);
    }
  }

  // the student named in the address (from a record, a search elsewhere) opened once
  if (initialStudent && !loadedInitial) { setLoadedInitial(true); void open(initialStudent); }

  async function act(key: keyof typeof ACTION_WORDS, path: string, body: unknown, reason: string, done: string) {
    if (!sel) return;
    setBusy(key); setProblem(null);
    try {
      const j = await post<Record<string, unknown>>(path, body, reason);
      if (!j) { notify(key === "print" || key === "reprint" ? "FAILED TO GENERATE ID CARD. PLEASE TRY AGAIN." : "The act was refused; the reason is shown."); return; }
      notify(done);
      setReplace(null); setEnding(null);
      await open(sel.student.student_id);
      if (rows) await search(page);   // the results say the card's new state too
      if (key === "print" || key === "reprint" || key === "replace") {
        window.open(`/credentials/idcards/student/pdf?id=${encodeURIComponent(sel.student.student_id)}`, "_blank", "noopener");
      }
    } finally {
      setBusy(null);
    }
  }

  async function saveBlood() {
    if (!sel || !blood) return;
    // V749: the group the record shows, saved as it stands, is the desk confirming it
    const confirming = sel.eligibility.checks?.blood_group === false && blood === (sel.student.blood_group ?? "");
    setBusy("blood"); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/credentials/identity-cards/students/${encodeURIComponent(sel.student.student_id)}/blood-group`, {
        method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Blood group ${blood} ${confirming ? "confirmed" : "recorded"} at the card desk`) },
        body: JSON.stringify({ bloodGroup: blood }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return; }
      notify(`Blood group ${String((j as { bloodGroup?: string }).bloodGroup ?? blood)} ${confirming ? "confirmed" : "recorded"}; the card prints it`);
      await open(sel.student.student_id);
    } finally { setBusy(null); }
  }

  const s = sel?.student;
  const e = sel?.eligibility;
  const words = e ? eligibilityWords(e) : null;
  // V749: whether the group on the record is confirmed, and what the desk's entry does with it
  const bg = e ? deskBloodGroup(e, s?.blood_group, blood) : null;
  const can = e ? actionsFor(e, sel?.card ?? null, may) : { print: false, collect: false, replace: false, end: false };
  const cardWord = cardStateWord(sel?.card?.state ?? null);

  return (
    <>
      <Panel title="Student ID card" right="Search by matriculation, JAMB or admission number, name, phone or e-mail">
        <PBody>
          <form className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }} onSubmit={(ev) => { ev.preventDefault(); void search(0); }}>
            <Field id="idc-q" label="Search student"><input id="idc-q" className="ctl" value={q} onChange={(ev) => setQ(ev.target.value)} placeholder="MOAU/AD/BUS/21/12345, a JAMB number, a name, a phone or an e-mail" style={{ minWidth: 360 }} maxLength={80} autoFocus /></Field>
            <Btn kind="primary" disabled={searching} onClick={() => void search(0)}>{searching ? "SEARCHING..." : "SEARCH STUDENT"}</Btn>
          </form>
          <div className="sub2" style={{ marginTop: "var(--s-2)" }}>A student&rsquo;s first card is issued on the matriculation number and a confirmed blood group (V699, V749); a card after it — a replacement — is printed once the student has paid the replacement fee on their portal. The photograph and the school fees are shown, never held against the card; clearance is never read here.</div>
        </PBody>
        {rows ? (
          rows.length ? (
            <>
              <DTable pageSize={0}
                cols={["Student", "JAMB|mid", "Faculty / Department", "Programme", "Level|num", "Session|mid", "Status", "School fees|mid", "ID card", "|num"]}
                rows={rows.map((r) => [
                  <Two key="s" a={r.name} b={r.matric_no ?? r.admission_no ?? "—"} />, <span key="j" className="tnum sub2">{r.jamb_reg_no ?? "—"}</span>,
                  <span key="f" className="sub2">{r.faculty ?? "—"}{r.department ? ` · ${r.department}` : ""}</span>, <span key="p">{r.programme ?? "—"}</span>,
                  <span key="l" className="tnum">{r.level ?? "—"}</span>, <span key="e" className="tnum sub2">{r.entry_session ?? "—"}</span>, <span key="st">{r.status}</span>,
                  <Pil key="fee" kind={r.fees_ok ? "ok" : "bad"}>{r.fees_ok ? "Satisfied" : "Not satisfied"}</Pil>,
                  <Pil key="c" kind={cardStateWord(r.card_state)[1]}>{r.card_no ? `${r.card_no} · ` : ""}{cardStateWord(r.card_state)[0]}{!r.card_state && r.eligible ? " · eligible" : ""}</Pil>,
                  <span key="a" className="row row--tight">
                    <Btn kind="ghost" size="sm" disabled={opening === r.student_id} onClick={() => void open(r.student_id)}>{opening === r.student_id ? "Opening…" : "VIEW"}</Btn>
                    <LinkBtn kind="ghost" href={`/students/${r.student_id}`}>Record</LinkBtn>
                  </span>,
                ])}
                texts={rows.map((r) => `${r.name} ${r.matric_no ?? ""} ${r.jamb_reg_no ?? ""} ${r.programme ?? ""}`)}
              />
              <PBody><div className="row" style={{ justifyContent: "space-between" }}>
                <span className="sub2">{total} student{total === 1 ? "" : "s"} · page {page + 1} of {Math.max(1, Math.ceil(total / 25))}</span>
                <span className="row row--tight">
                  <Btn kind="ghost" size="sm" disabled={page === 0 || searching} onClick={() => void search(page - 1)}>Previous</Btn>
                  <Btn kind="ghost" size="sm" disabled={(page + 1) * 25 >= total || searching} onClick={() => void search(page + 1)}>Next</Btn>
                </span>
              </div></PBody>
            </>
          ) : <PBody><div className="sub2">No student matches. Try the matriculation number, the JAMB number or the surname.</div></PBody>
        ) : null}
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {sel && s && e && words ? (
        <Panel title={`${s.name} · ${s.matric_no ?? s.admission_no ?? "no number"}`} right={<span className="row row--tight"><Pil kind={cardWord[1]}>{sel.card ? `${sel.card.card_no} · ` : ""}{cardWord[0]}</Pil><Btn kind="ghost" size="sm" onClick={() => setSel(null)}>Close</Btn></span>}>
          <PBody>
            <div className="row row--top" style={{ gap: "var(--s-5)", flexWrap: "wrap" }}>
              <Passport w={112} h={139} radius={5} src={sel.photo && s.matric_no ? `/api/bff/api/v1/credentials/identity-cards/students/${encodeURIComponent(s.student_id)}/photo?v=${encodeURIComponent(s.matric_no)}` : null} />
              <div className="grow" style={{ minWidth: 260 }}>
                <div className="grid grid--3" style={{ gap: "var(--s-2)" }}>
                  {([["Matriculation number", s.matric_no ?? "Not yet issued"], ["JAMB number", s.jamb_reg_no ?? "—"], ["Admission number", s.admission_no ?? "—"],
                    ["Faculty", s.faculty ?? "—"], ["Department", s.department ?? "—"], ["Programme", s.programme ?? "—"],
                    ["Level", s.level ? `${s.level} Level` : "—"], ["Admission session", s.entry_session ?? "—"], ["Current session", s.current_session ?? "—"],
                    ["Student status", s.status], ["Academic enrolment", `${s.entry_mode ?? "—"} · ${s.programme_code ?? ""}`], ["Photograph", sel.photo ? "Official photograph on record" : "Missing"],
                    ["Blood group", bg?.shown ?? s.blood_group ?? "Not on record"]] as [string, string][]).map(([k, v]) => (
                    <div key={k}><div className="sub2">{k}</div><div className={k.includes("number") ? "tnum" : ""}>{v}</div></div>
                  ))}
                </div>
              </div>
            </div>
            <Note kind={words.kind} title={words.title} action={!sel.photo && may ? <LinkBtn kind="ghost" href={`/students/${s.student_id}?tab=biodata`}>Photograph on the record</LinkBtn> : undefined}>
              {words.lines.map((l) => <div key={l}>{words.kind === "ok" ? "✓ " : "— "}{l}</div>)}
              {/* V699: said, not held against the card */}
              {words.warnings.map((w) => <div key={w} className="sub2">· {w}</div>)}
            </Note>
            {may ? (
              <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
                <Field id="idc-blood" label={bg?.label ?? "Add the blood group"}>
                  <select id="idc-blood" className="ctl" value={blood} onChange={(ev) => setBlood(ev.target.value)} disabled={busy !== null}>
                    <option value="">Choose…</option>
                    {BLOOD_GROUPS.map((g) => <option key={g} value={g}>{g}</option>)}
                  </select>
                </Field>
                <Btn kind="secondary" disabled={busy !== null || !bg?.canSave} busy={busy === "blood"} busyLabel="Saving…" onClick={() => void saveBlood()}>SAVE BLOOD GROUP</Btn>
                <span className="sub2">
                  Printed on the card; kept on the student&rsquo;s record.
                  {bg && !bg.confirmed ? " Not yet confirmed, so the card waits: the group saved here, the one shown or a corrected one, counts as confirmed." : ""}
                </span>
              </div>
            ) : null}
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
              <Btn kind="ghost" onClick={() => setShowCard((v) => !v)}>{showCard ? "HIDE ID CARD" : "VIEW ID CARD"}</Btn>
              {can.print ? <Btn kind="primary" disabled={busy !== null} onClick={() => void act(sel.card ? "reprint" : "print", `/students/${s.student_id}/print`, {}, sel.card ? `Identity card ${sel.card.card_no} printed again` : "Identity card printed", "ID CARD PRINTED SUCCESSFULLY")}>{busy === "print" || busy === "reprint" ? ACTION_WORDS.print[1] : sel.card ? ACTION_WORDS.reprint[0] : ACTION_WORDS.print[0]}</Btn> : null}
              {can.collect ? <Btn kind="go" disabled={busy !== null} onClick={() => void act("collect", `/students/${s.student_id}/collect`, { note: "handed to the student at the desk" }, `Identity card ${sel.card?.card_no} handed to the student`, "ID CARD ISSUED — HANDED TO THE STUDENT")}>{busy === "collect" ? ACTION_WORDS.collect[1] : ACTION_WORDS.collect[0]}</Btn> : null}
              {can.replace ? <Btn kind="ghost" disabled={busy !== null} onClick={() => { setEnding(null); setReplace(replace ? null : { reason: "LOST", note: "" }); }}>{ACTION_WORDS.replace[0]}…</Btn> : null}
              {can.end ? <Btn kind="ghost" disabled={busy !== null} onClick={() => { setReplace(null); setEnding(ending ? null : { state: "LOST", reason: "" }); }}>{ACTION_WORDS.end[0]}…</Btn> : null}
              {sel.card ? <a className="btn btn--ghost" href={`/credentials/idcards/student/pdf?id=${encodeURIComponent(s.student_id)}`} target="_blank" rel="noopener">Open the print (PDF)</a> : null}
              {sel.card?.verify_path ? <a className="btn btn--ghost" href={sel.card.verify_path} target="_blank" rel="noopener">What a scan shows</a> : null}
            </div>
            {replace ? (
              <Note kind="info" title="Replace the card — the current card is ended with the reason, the new one printed under a new number">
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
                  <Field id="idc-rr" label="Reason"><select id="idc-rr" className="ctl" value={replace.reason} onChange={(ev) => setReplace({ ...replace, reason: ev.target.value })}>{REPLACE_REASONS.map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
                  <Field id="idc-rn" label="Note (what happened)"><input id="idc-rn" className="ctl" value={replace.note} onChange={(ev) => setReplace({ ...replace, note: ev.target.value })} maxLength={300} style={{ minWidth: 300 }} /></Field>
                  <Btn kind="urgent" disabled={busy !== null || (replace.reason === "OTHER" && replace.note.trim().length < 5)} onClick={() => void act("replace", `/students/${s.student_id}/print`, { replaceReason: replace.reason, note: replace.note.trim() || null }, `Identity card replaced: ${reasonWord(replace.reason)}`, "ID CARD REPLACED — NEW CARD PRINTED")}>{busy === "replace" ? ACTION_WORDS.replace[1] : "CONFIRM REPLACEMENT"}</Btn>
                </div>
              </Note>
            ) : null}
            {ending && sel.card ? (
              <Note kind="bad" title={`End card ${sel.card.card_no} — the record stays; a replacement is printed on a reason afterwards`}>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end" }}>
                  <Field id="idc-es" label="As"><select id="idc-es" className="ctl" value={ending.state} onChange={(ev) => setEnding({ ...ending, state: ev.target.value })}>{END_STATES.map(([k, w]) => <option key={k} value={k}>{w}</option>)}</select></Field>
                  <Field id="idc-er" label="Why"><input id="idc-er" className="ctl" value={ending.reason} onChange={(ev) => setEnding({ ...ending, reason: ev.target.value })} maxLength={300} style={{ minWidth: 300 }} /></Field>
                  <Btn kind="urgent" disabled={busy !== null || ending.reason.trim().length < 5} onClick={() => void act("end", `/cards/${sel.card!.id}/end`, { state: ending.state, reason: ending.reason.trim() }, `Identity card ${sel.card!.card_no} ended: ${ending.state.toLowerCase()}`, `ID CARD ${ending.state}`)}>{busy === "end" ? ACTION_WORDS.end[1] : "CONFIRM"}</Btn>
                </div>
              </Note>
            ) : null}
          </PBody>
          {showCard ? <CardPreview s={s} card={sel.card} photo={sel.photo} /> : null}
          <Panel title="ID card history" right={`${sel.cards.length} card${sel.cards.length === 1 ? "" : "s"}`}>
            {sel.cards.length ? (
              <DTable pageSize={0}
                cols={["Card", "Version|num", "Status", "Printed", "Printed by", "Issued", "Issued by", "Reason", "Previous card"]}
                rows={sel.cards.map((c: CardRow) => [
                  <span key="n" className="tnum">{c.card_no}</span>, <span key="v" className="tnum">{c.version}{c.print_count > 1 ? ` · ${c.print_count} prints` : ""}</span>,
                  <Pil key="s" kind={cardStateWord(c.state)[1]}>{cardStateWord(c.state)[0]}</Pil>,
                  <span key="p" className="sub2 tnum">{when(c.printed_at)}</span>, <span key="pb" className="sub2">{c.printed_by ?? "—"}</span>,
                  <span key="i" className="sub2 tnum">{when(c.collected_at)}</span>, <span key="ib" className="sub2">{c.issued_by ?? "—"}</span>,
                  <span key="r" className="sub2">{c.replacement_reason ? `Replacement: ${reasonWord(c.replacement_reason)}` : ""}{c.ended_reason ? `${c.replacement_reason ? " · " : ""}Ended: ${c.ended_reason}` : ""}</span>,
                  <span key="pc" className="sub2 tnum">{c.previous_card_no ?? "—"}</span>,
                ])}
              />
            ) : <PBody><div className="sub2">No card has been printed for this student.</div></PBody>}
            {sel.events.length ? (
              <DTable pageSize={10} cols={["When", "Act", "By", "Note"]} rows={sel.events.map((ev) => [
                <span key="w" className="sub2 tnum">{when(ev.at)}</span>, <b key="a">{eventWord(ev)}</b>, <span key="b" className="sub2">{ev.actor ?? "—"}{ev.actor_office ? ` (${ev.actor_office})` : ""}</span>, <span key="n" className="sub2">{ev.note ?? ""}</span>,
              ])} texts={sel.events.map((ev) => `${eventWord(ev)} ${ev.note ?? ""}`)} />
            ) : null}
          </Panel>
        </Panel>
      ) : null}
    </>
  );
}

/** the card as it prints — the very drawing the print makes (lib/idcard-design), on screen: the front with the photograph and the
 *  particulars, the back with the barcode, the conditions and the Chief Security Officer's signature; a card not yet printed is marked
 *  a preview, its number assigned and its signed QR made when printed */
function CardPreview({ s, card, photo }: { s: DeskStudent["student"]; card: CardRow | null; photo: boolean }) {
  const [, setLoaded] = useState(0);
  const [sig, setSig] = useState<{ title: string; name: string | null; url: string | null } | null>(null);
  useEffect(() => {
    let live = true;
    // the University's name and logo as its profile holds them, and who signs the cards
    void getInstitution().then(() => { if (live) setLoaded((n) => n + 1); });
    void fetch("/api/bff/api/v1/credentials/identity-cards/signatory", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((j: { title?: string; name?: string | null; signatureUrl?: string | null } | null) => {
        if (live && j) setSig({ title: j.title || "Chief Security Officer", name: j.name ?? null, url: j.signatureUrl ? `/api/bff${j.signatureUrl}` : null });
      })
      .catch(() => { /* the line and the title alone */ });
    return () => { live = false; };
  }, []);
  const number = s.matric_no ?? "";
  const longDay = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });
  const face: CardFace = {
    kind: "student", name: s.name, number,
    // the University's layout of 12 November 2026: no level, session or graduation year; the validity in the foot
    fields: [["Faculty", s.faculty ?? "—"], ["Blood group", s.blood_group ?? "—"], ["Programme", s.programme ?? "—"],
      ["Admitted", (s.entry_session ?? "").slice(0, 4) || "—"]],
    foot: [["Valid until", card ? longDay(card.valid_to) : "4 years from print"]],
    serial: card ? card.card_no : "PREVIEW",
  };
  const back: CardBack = {
    kind: "student", barcode: number, serial: card ? card.card_no : "Number when printed",
    aside: ["In an emergency", s.reach_phone ?? "-"], signatory: { title: sig?.title ?? "Chief Security Officer", name: sig?.name ?? null },
  };
  const hrefs = {
    photo: photo && s.matric_no ? `/api/bff/api/v1/credentials/identity-cards/students/${encodeURIComponent(s.student_id)}/photo?v=${encodeURIComponent(s.matric_no)}` : null,
    crest: institutionLogoUrl(), signature: sig?.url ?? null,
  };
  const id = s.student_id.replace(/[^A-Za-z0-9]/g, "").slice(0, 12);
  const side: React.CSSProperties = { width: 400, maxWidth: "100%", filter: "drop-shadow(0 4px 10px rgba(16, 38, 52, .18))" };
  return (
    <PBody>
      <div className="row row--top" style={{ gap: "var(--s-4)", flexWrap: "wrap" }}>
        <div style={side} data-testid="idcard-front" dangerouslySetInnerHTML={{ __html: cardSvg("front", { face, back }, hrefs, `f${id}`) }} />
        <div style={side} data-testid="idcard-back" dangerouslySetInnerHTML={{ __html: cardSvg("back", { face, back }, hrefs, `b${id}`) }} />
      </div>
      <div className="sub2" style={{ marginTop: "var(--s-2)" }}>
        {card ? "The print (PDF) carries this design with the card's signed verification QR in the box on the back." : "A preview: the card's number and its signed verification QR are made when it is printed."}
      </div>
    </PBody>
  );
}
