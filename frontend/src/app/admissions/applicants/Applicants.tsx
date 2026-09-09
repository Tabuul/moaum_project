"use client";

/** The applicants on committed admission lists: the pool JAMB admitted, whether each has
 *  registered for post-UTME, and the programme the University offers them. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Applicant {
  jamb_reg_no: string; surname: string; other_names: string; jamb_code: string; entry_mode: string;
  aggregate: number | null; programme: string | null; registered: boolean; offer_state: string | null;
}
export interface ApplicantsView { session: string; counts: { total: number; registered: number }; applicants: Applicant[] }

export function Applicants({ d, session, q }: { d: ApplicantsView; session: string; q: string }) {
  const router = useRouter();
  const [search, setSearch] = useState(q);
  const total = Number(d.counts.total);
  const registered = Number(d.counts.registered);
  const pending = total - registered;

  function go() {
    const p = new URLSearchParams();
    p.set("session", session);
    if (search.trim()) p.set("q", search.trim());
    router.push(`/admissions/applicants?${p.toString()}`);
  }

  return (
    <>
      <Note kind="info" title="These are the applicants on the committed admission list">
        Everyone JAMB admitted to the University for {session}, from the committed CAPS lists. Each proceeds to post-UTME by registering on the applicant portal with their JAMB number, which opens their application and screening. This screen shows who has registered and who has not, so the office can follow the pool up.
      </Note>

      <Tiles items={[
        ["On the committed list", total.toLocaleString(), null, `Admitted for ${session}`],
        ["Registered for post-UTME", registered.toLocaleString(), registered ? "var(--green-ink)" : null, total ? `${Math.round((100 * registered) / total)}% of the pool` : ""],
        ["Not yet registered", pending.toLocaleString(), pending ? "var(--chrome)" : "var(--green-ink)", "Yet to open their application"],
        ["Showing", String(d.applicants.length), null, "Search to find a candidate"],
      ]} />

      <Panel title="Applicants" right={`${session} · committed admission list`}>
        <div className="card__body" style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end", borderBottom: "1px solid var(--line-2)" }}>
          <div className="field" style={{ flexGrow: 1, minWidth: 220 }}><label htmlFor="ap-q">Find an applicant</label>
            <input id="ap-q" className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") go(); }} placeholder="Surname, other names or JAMB number" autoComplete="off" />
          </div>
          <button className="btn btn--primary" onClick={go}>Search</button>
          {q ? <button className="btn btn--ghost" onClick={() => { setSearch(""); router.push(`/admissions/applicants?session=${encodeURIComponent(session)}`); }}>Clear</button> : null}
        </div>
        {d.applicants.length ? (
          <DTable cols={["Applicant", "JAMB number|mid", "Programme (University offers)", "Entry|mid", "Aggregate|mid", "Post-UTME|num"]} rows={d.applicants.map((a) => [
            <Two key="n" a={`${a.surname}, ${a.other_names}`} b={a.registered && a.offer_state ? a.offer_state.charAt(0) + a.offer_state.slice(1).toLowerCase() : ""} />,
            <span className="tnum" key="j">{a.jamb_reg_no}</span>,
            a.programme ? <span key="p">{a.programme}</span> : <span className="sub2" key="p" style={{ color: "var(--red-ink)" }}>{a.jamb_code} — not a programme the University runs</span>,
            <span className="sub2" key="e">{a.entry_mode === "UTME" ? "UTME" : a.entry_mode.charAt(0) + a.entry_mode.slice(1).toLowerCase().replace("_", " ")}</span>,
            <span className="tnum" key="ag">{a.aggregate ?? "—"}</span>,
            a.registered ? <Pil kind="ok" key="s">Registered</Pil> : <Pil kind="grey" key="s">Not yet</Pil>,
          ])} texts={d.applicants.map((a) => `${a.surname} ${a.other_names} ${a.jamb_reg_no}`)} />
        ) : <PBody><div className="sub2">{q ? "No applicant matches that search on the committed list." : "No committed admission list for this session yet. Commit a CAPS list on the JAMB admission lists screen, and the applicants appear here."}</div></PBody>}
      </Panel>

      {d.applicants.length >= 200 ? <Note kind="info" title="Only the first 200 are shown">The committed list is large. Use the search to find a specific applicant by name or JAMB number; the counts above are for the whole list.</Note> : null}
    </>
  );
}
