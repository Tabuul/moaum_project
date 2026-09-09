"use client";

/** The merit list for a programme: the eligible pool ranked by the session aggregate, with the
 *  proposed offer that fills the quota UTME:DE by the faculty ratio and spills flexibly. It
 *  proposes; the Board still enters and releases the decision. */
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface ProgrammeOption { code: string; name: string; facultyName: string; archived: boolean }
export interface MeritRow {
  rank: number; app_id: string; jamb_reg_no: string; surname: string; other_names: string;
  entry_mode: string; utme: number | null; putme: number | null; aggregate: number | null;
  state_of_origin: string | null; lga: string | null; meets_cutoff: boolean; meets_compulsory: boolean;
  eligible: boolean; basis: string; proposed_offer: boolean;
}
export interface MeritView { session: string; programme: string; counts: { pool: number; eligible: number; proposed: number }; rows: MeritRow[] }

const BASIS: Record<string, string> = { NM: "National Merit", SM: "State Merit", ELG: "Equality of LG", LOCALITY: "Locality" };
const mode = (m: string) => (m === "UTME" ? "UTME" : m.charAt(0) + m.slice(1).toLowerCase().replace("_", " "));

export function Merit({ session, programme, programmes, view, problem }: {
  session: string; programme: string; programmes: ProgrammeOption[]; view: MeritView | null; problem: Problem | null;
}) {
  const router = useRouter();
  const pick = (code: string) => router.push(`/admissions/merit?session=${encodeURIComponent(session)}${code ? `&programme=${encodeURIComponent(code)}` : ""}`);
  const chosen = programmes.find((p) => p.code === programme);

  return (
    <>
      <Note kind="info" title="A proposed merit list — the Board still decides">
        The eligible pool for a programme, ranked by the session&rsquo;s aggregate (UTME scaled and weighted with the Post-UTME score). The proposed offers fill the programme&rsquo;s quota, split UTME to Direct-Entry by the ratio in force for the faculty, and spill flexibly so an approved seat is never left empty. Nobody is admitted here: the Board enters and releases each decision on the applicant&rsquo;s desk.
      </Note>

      <Panel title="Choose a programme" right={`${session}`}>
        <div className="card__body" style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
          <div className="field" style={{ flexGrow: 1, minWidth: 280 }}>
            <label htmlFor="mr-prog">Programme</label>
            <select id="mr-prog" className="ctl" value={programme} onChange={(e) => pick(e.target.value)}>
              <option value="">— choose a programme —</option>
              {programmes.filter((p) => !p.archived).map((p) => <option key={p.code} value={p.code}>{p.name} · {p.facultyName}</option>)}
            </select>
          </div>
        </div>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["Pool", String(view.counts.pool), null, chosen ? chosen.name : programme],
            ["Eligible", String(view.counts.eligible), Number(view.counts.eligible) ? "var(--green-ink)" : null, "Cut-off, compulsory credits and screening met"],
            ["Proposed offers", String(view.counts.proposed), Number(view.counts.proposed) ? "var(--green-ink)" : null, "Filling the quota, by merit"],
            ["Not eligible", String(view.counts.pool - view.counts.eligible), view.counts.pool - view.counts.eligible ? "var(--chrome)" : null, "Below cut-off, missing a credit, or unscored"],
          ]} />
          <Panel title="The merit list" right={`${view.counts.pool} in the pool · ranked by aggregate`}>
            {view.rows.length ? (
              <DTable
                cols={["#|mid", "Candidate", "JAMB|mid", "Entry|mid", "UTME|mid", "Post-UTME|mid", "Aggregate|mid", "Basis|mid", "Eligible|mid", "Proposed|num"]}
                rows={view.rows.map((r) => [
                  <span className="tnum" key="r">{r.rank}</span>,
                  <Two key="n" a={`${r.surname}, ${r.other_names}`} b={[r.state_of_origin, r.lga].filter(Boolean).join(" · ")} />,
                  <span className="tnum" key="j">{r.jamb_reg_no}</span>,
                  <span className="sub2" key="e">{mode(r.entry_mode)}</span>,
                  <span className="tnum" key="u">{r.utme ?? "—"}</span>,
                  <span className="tnum" key="p">{r.putme ?? "—"}</span>,
                  <strong className="tnum" key="a">{r.aggregate ?? "—"}</strong>,
                  <span className="sub2" key="b">{BASIS[r.basis] ?? r.basis}</span>,
                  r.eligible ? <Pil kind="ok" key="el">Eligible</Pil> : <Pil kind="grey" key="el">{!r.meets_compulsory ? "No Eng/Maths credit" : !r.meets_cutoff ? "Below cut-off" : "Not scored"}</Pil>,
                  r.proposed_offer ? <Pil kind="ok" key="o">Offer</Pil> : <Pil kind="grey" key="o">—</Pil>,
                ])}
                texts={view.rows.map((r) => `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.basis}`)}
              />
            ) : <PBody><div className="sub2">No applicant has registered and been scored for this programme yet. The list fills as applicants register for post-UTME, sit the screening, and their scores are released.</div></PBody>}
          </Panel>
        </>
      ) : (
        <Note kind="info" title="Choose a programme to see its merit list">Pick a programme above. The list is drawn from the applicants who registered for it, sat the screening and had their scores released.</Note>
      )}
    </>
  );
}
