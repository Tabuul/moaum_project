"use client";

/** The merit list for a programme: the eligible pool ranked by the session aggregate, with the
 *  proposed offer that fills the quota UTME:DE by the faculty ratio and spills flexibly. It
 *  proposes; the Board still enters and releases the decision. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
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

/** Type-to-search over the programmes — name, faculty or code — so one of ~90 is easy to find. */
function ProgrammePicker({ programmes, chosen, onPick }: { programmes: ProgrammeOption[]; chosen: ProgrammeOption | undefined; onPick: (code: string) => void }) {
  const live = programmes.filter((p) => !p.archived);
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [hi, setHi] = useState(0);
  const term = q.trim().toLowerCase();
  const matches = (term ? live.filter((p) => `${p.name} ${p.facultyName} ${p.code}`.toLowerCase().includes(term)) : live).slice(0, 60);
  const label = chosen ? `${chosen.name} · ${chosen.facultyName}` : "";
  return (
    <div className="field" style={{ flexGrow: 1, minWidth: 300, position: "relative" }}>
      <label htmlFor="mr-prog">Programme</label>
      <input
        id="mr-prog" className="ctl" autoComplete="off" role="combobox" aria-controls="mr-prog-list" aria-expanded={open} aria-autocomplete="list"
        value={open ? q : label}
        placeholder="Type to search — name, faculty or code"
        onFocus={() => { setQ(""); setOpen(true); setHi(0); }}
        onChange={(e) => { setQ(e.target.value); setOpen(true); setHi(0); }}
        onBlur={() => window.setTimeout(() => setOpen(false), 150)}
        onKeyDown={(e) => {
          if (!open) return;
          if (e.key === "ArrowDown") { e.preventDefault(); setHi((h) => Math.min(h + 1, matches.length - 1)); }
          else if (e.key === "ArrowUp") { e.preventDefault(); setHi((h) => Math.max(h - 1, 0)); }
          else if (e.key === "Enter") { e.preventDefault(); const m = matches[hi]; if (m) { onPick(m.code); setOpen(false); (e.target as HTMLInputElement).blur(); } }
          else if (e.key === "Escape") { setOpen(false); }
        }}
      />
      {open ? (
        <ul id="mr-prog-list" role="listbox" style={{ position: "absolute", zIndex: 30, top: "100%", left: 0, right: 0, margin: "2px 0 0", padding: 0, listStyle: "none", maxHeight: 300, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--line)", borderRadius: 8, boxShadow: "0 6px 20px rgba(0,0,0,.12)" }}>
          {matches.length ? matches.map((p, i) => (
            <li key={p.code} role="option" aria-selected={i === hi}
              onMouseDown={(e) => { e.preventDefault(); onPick(p.code); setOpen(false); }}
              onMouseEnter={() => setHi(i)}
              style={{ padding: "8px 10px", cursor: "pointer", borderTop: i ? "1px solid var(--line-2)" : undefined, background: i === hi ? "var(--line-2)" : "transparent" }}>
              <div>{p.name}</div>
              <div className="sub2 tnum">{p.code} · {p.facultyName}</div>
            </li>
          )) : <li className="sub2" style={{ padding: "8px 10px" }}>No programme matches &ldquo;{q}&rdquo;.</li>}
        </ul>
      ) : null}
    </div>
  );
}

export function Merit({ session, programme, programmes, view, problem, actingOffice }: {
  session: string; programme: string; programmes: ProgrammeOption[]; view: MeritView | null; problem: Problem | null; actingOffice: string | null;
}) {
  const router = useRouter();
  const pick = (code: string) => router.push(`/admissions/merit?session=${encodeURIComponent(session)}${code ? `&programme=${encodeURIComponent(code)}` : ""}`);
  const chosen = programmes.find((p) => p.code === programme);
  const mayRecord = ["academic", "registrar"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [recorded, setRecorded] = useState<{ offered: number; waited: number; notOffered: number; skipped: number } | null>(null);
  const [recProblem, setRecProblem] = useState<Problem | null>(null);

  async function record() {
    if (!window.confirm(`Record the merit list for this programme? An offer is entered for each proposed candidate and the waiting list for the rest eligible. Decisions are not released yet.`)) return;
    setBusy(true);
    setRecProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/admissions/merit/record", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Merit list recorded for ${programme}`) }, body: JSON.stringify({ session, programme }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setRecProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setRecorded(j as { offered: number; waited: number; notOffered: number; skipped: number });
      notify(`Merit list recorded for ${programme}`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar"]} actingOffice={actingOffice}
        action="Recording the merit list against a programme" />
      <Note kind="info" title="A proposed merit list — the Board still decides">
        The eligible pool for a programme, ranked by the session&rsquo;s aggregate (UTME scaled and weighted with the Post-UTME score). The proposed offers fill the programme&rsquo;s quota, split UTME to Direct-Entry by the ratio in force for the faculty, and spill flexibly so an approved seat is never left empty. Nobody is admitted here: the Board enters and releases each decision on the applicant&rsquo;s desk.
      </Note>

      <Panel title="Choose a programme" right={`${session}`}>
        <div className="card__body" style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
          <ProgrammePicker programmes={programmes} chosen={chosen} onPick={pick} />
          {chosen ? <Btn kind="ghost" onClick={() => pick("")}>Clear</Btn> : null}
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
          {recProblem ? <ProblemNotice problem={recProblem} /> : null}
          {recorded ? <Note kind="ok" title="The merit list has been recorded">{recorded.offered} offer{recorded.offered === 1 ? "" : "s"} entered, {recorded.waited} on the waiting list, {recorded.notOffered} not offered (ineligible), {recorded.skipped} left untouched (already released). Every candidate now carries a decision, so the JAMB template reconciles. Release the decisions from the Applicants desk when the Board is ready.</Note> : null}
          <Panel title="The merit list" right={<span style={{ display: "inline-flex", gap: 8, alignItems: "center" }}><span className="sub2">{view.counts.pool} in the pool</span>{mayRecord && view.counts.proposed > 0 ? <Btn kind="primary" disabled={busy} onClick={() => void record()}>{busy ? "Recording…" : `Record ${view.counts.proposed} offer${view.counts.proposed === 1 ? "" : "s"}`}</Btn> : null}</span>}>
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
