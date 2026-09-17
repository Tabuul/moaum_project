"use client";

/** t/postutme — the Academic Office's computed Post-UTME for candidates who did not sit it (V090):
 *  the O'Level aggregate blended with the UTME, for Direct Entry and non-exam programmes. Read-only. */
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Computed {
  jamb_reg_no: string; name: string; programme: string; entry_mode: string;
  olevel_total: number | null; olevel_ceiling: number | null; olevel_scaled: number | null;
  utme: number | null; computed: number | null; source: string;
}

const SRC: Record<string, "ok" | "info" | "grey"> = { "O'Level + UTME": "ok", "O'Level": "info", UTME: "info", none: "grey" };

export function ComputedPostUtme({ rows, session, sessions }: { rows: Computed[]; session: string; sessions: string[] }) {
  const router = useRouter();
  const withUtme = rows.filter((r) => r.utme != null).length;
  const de = rows.filter((r) => r.entry_mode === "DIRECT_ENTRY").length;

  return (
    <>
      <Note kind="info" title="Computed Post-UTME for candidates who did not sit it"
        action={<Link href={`/admissions/screening?session=${encodeURIComponent(session)}`} className="btn btn--ghost btn--sm">Full screening register</Link>}>
        Direct Entry entrants and candidates in programmes not screened by examination never sit the Post-UTME. This is a
        <b> computed</b> screening figure for them, for the Academic Office: the O&rsquo;Level aggregate scaled to 100 under
        the session&rsquo;s grading, blended with the UTME (also out of 100) where the candidate has one; a Direct Entry
        candidate with no UTME shows the O&rsquo;Level figure alone. It is a report — it does not change the sat score or the
        merit engine. The <b>Screening register</b> lists everyone, including those who sat the Post-UTME.
      </Note>
      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
        <div className="field" style={{ minWidth: 160, margin: 0 }}><label htmlFor="pu-s">Session</label>
          <select id="pu-s" className="ctl" value={session} onChange={(e) => router.push(`/admissions/computed-screening?session=${encodeURIComponent(e.target.value)}`)}>
            {(sessions.includes(session) ? sessions : [session, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </div>
      </div></div>
      <Tiles items={[
        ["Non-sitters", String(rows.length), null, `${session} · did not sit the Post-UTME`],
        ["With a UTME to blend", String(withUtme), null, "O'Level + UTME computed"],
        ["Direct Entry", String(de), null, "O'Level basis (no UTME)"],
        ["O'Level only", String(rows.length - withUtme), null, "No UTME on record"],
      ]} />
      <Panel title="Computed Post-UTME" right={`${rows.length} candidate${rows.length === 1 ? "" : "s"}`}>
        {rows.length ? (
          <DTable
            cols={["Candidate", "JAMB no|mid", "Programme", "Mode|mid", "O’Level|num", "UTME|num", "Computed|num", "Basis|mid"]}
            rows={rows.map((r) => [
              <strong key="n">{r.name}</strong>,
              <span className="tnum sub2" key="j">{r.jamb_reg_no}</span>,
              <span className="sub2" key="p">{r.programme}</span>,
              <span className="sub2" key="m">{r.entry_mode === "DIRECT_ENTRY" ? "Direct Entry" : r.entry_mode}</span>,
              <span className="tnum" key="o">{r.olevel_scaled != null ? r.olevel_scaled : "—"}{r.olevel_total != null && r.olevel_ceiling ? <div className="sub2 tnum">{r.olevel_total}/{r.olevel_ceiling}</div> : null}</span>,
              <span className="tnum" key="u">{r.utme ?? "—"}</span>,
              <b className="tnum" key="c">{r.computed != null ? r.computed : "—"}</b>,
              <Pil kind={SRC[r.source] ?? "grey"} key="s">{r.source}</Pil>,
            ])}
            texts={rows.map((r) => `${r.name} ${r.jamb_reg_no} ${r.programme}`)}
          />
        ) : <PBody><div className="sub2">No candidate in {session} is a non-sitter yet — everyone recorded either sat the Post-UTME or has no submitted application.</div></PBody>}
      </Panel>
    </>
  );
}
