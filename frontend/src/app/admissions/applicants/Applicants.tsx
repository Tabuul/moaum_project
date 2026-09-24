"use client";

/** The applicants on committed admission lists: the pool JAMB admitted, filterable by faculty,
 *  programme and entry mode, whether each has registered for post-UTME, and a per-programme
 *  breakdown — the clear admitted view. */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";

export interface Applicant {
  jamb_reg_no: string; surname: string; other_names: string; jamb_code: string; entry_mode: string;
  aggregate: number | null; programme: string | null; faculty: string | null; faculty_code: string | null;
  registered: boolean; offer_state: string | null;
}
export interface BreakdownRow { faculty: string | null; faculty_code: string | null; programme_code: string; programme: string | null; admitted: number; registered: number }
export interface ApplicantsView { session: string; counts: { total: number; registered: number }; breakdown: BreakdownRow[]; applicants: Applicant[] }
export interface ProgrammeOption { code: string; name: string; facultyCode: string; facultyName: string; archived: boolean }

const modeLabel = (m: string) => (m === "UTME" ? "UTME" : m.charAt(0) + m.slice(1).toLowerCase().replace("_", " "));

export function Applicants({ d, session, q, faculty, programme, entryMode, programmes }: {
  d: ApplicantsView; session: string; q: string; faculty: string; programme: string; entryMode: string; programmes: ProgrammeOption[];
}) {
  const queryNav = useQueryNav();
  const [search, setSearch] = useState(q);
  const total = Number(d.counts.total);
  const registered = Number(d.counts.registered);
  const pending = total - registered;

  // faculties for the filter, and the programmes under the chosen faculty
  const faculties = Array.from(new Map(programmes.filter((p) => !p.archived).map((p) => [p.facultyCode, p.facultyName])).entries())
    .map(([code, name]) => ({ code, name })).sort((a, b) => a.name.localeCompare(b.name));
  const facProgs = programmes.filter((p) => !p.archived && (!faculty || p.facultyCode === faculty)).sort((a, b) => a.name.localeCompare(b.name));

  function navigate(next: Partial<{ q: string; faculty: string; programme: string; entryMode: string }>) {
    const state = { q: search.trim(), faculty, programme, entryMode, ...next };
    const p = new URLSearchParams({ session });
    if (state.q) p.set("q", state.q);
    if (state.faculty) p.set("faculty", state.faculty);
    if (state.programme) p.set("programme", state.programme);
    if (state.entryMode) p.set("entryMode", state.entryMode);
    queryNav(`/admissions/applicants?${p.toString()}`);
  }
  const filtered = !!(q || faculty || programme || entryMode);

  return (
    <>
      <Note kind="info" title="The admitted list — everyone on the committed admission list">
        Everyone JAMB admitted to the University for {session}, from the committed CAPS lists. Filter by faculty, programme or entry mode to see the admitted list for any part of the University, with how many have registered for post-UTME. Each applicant proceeds to the admission process by registering on the applicant portal with their JAMB number.
      </Note>

      <Tiles items={[
        [filtered ? "Admitted (this filter)" : "On the committed list", total.toLocaleString(), null, filtered ? "Matching the filter" : `Admitted for ${session}`],
        ["Registered for post-UTME", registered.toLocaleString(), registered ? "var(--green-ink)" : null, total ? `${Math.round((100 * registered) / total)}% of these` : ""],
        ["Not yet registered", pending.toLocaleString(), pending ? "var(--chrome)" : "var(--green-ink)", "Yet to open their application"],
        ["Showing", String(d.applicants.length), null, "The list below"],
      ]} />

      <Panel title="Filter the admitted list" right={`${session}`}>
        <PBody>
          <div className="grid grid--4 rfgrid" style={{ alignItems: "end" }}>
            <Field id="ap-fac" label="Faculty">
              <SearchSelect id="ap-fac" value={faculty} allLabel="All faculties" placeholder="All faculties"
                options={faculties.map((f) => ({ value: f.code, label: f.name }))}
                onChange={(v) => navigate({ faculty: v, programme: "" })} />
            </Field>
            <Field id="ap-prog" label="Programme">
              <SearchSelect id="ap-prog" value={programme}
                allLabel={faculty ? "All in this faculty" : "All programmes"} placeholder="Search a programme…"
                options={facProgs.map((p) => ({ value: p.code, label: p.name }))}
                onChange={(v) => navigate({ programme: v })} />
            </Field>
            <Field id="ap-em" label="Entry mode">
              <SearchSelect id="ap-em" value={entryMode} allLabel="All modes" placeholder="All modes"
                options={[{ value: "UTME", label: "UTME" }, { value: "DIRECT_ENTRY", label: "Direct Entry" }]}
                onChange={(v) => navigate({ entryMode: v })} />
            </Field>
            <Field id="ap-q" label="Find an applicant">
              <input id="ap-q" className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") navigate({}); }} placeholder="Surname, other names or JAMB number" autoComplete="off" />
            </Field>
          </div>
          <div className="row row--right mt-4">
            {filtered ? <Btn kind="ghost" size="md" onClick={() => { setSearch(""); queryNav(`/admissions/applicants?session=${encodeURIComponent(session)}`); }}>Clear filters</Btn> : null}
            <Btn kind="primary" size="md" onClick={() => navigate({})}>Search</Btn>
          </div>
        </PBody>
      </Panel>

      <Panel title="Admitted by programme" right={`${d.breakdown.length} programme${d.breakdown.length === 1 ? "" : "s"}`}>
        {d.breakdown.length ? (
          <DTable
            cols={["Faculty", "Programme", "Admitted|num", "Registered|num", "Yet to register|num"]}
            rows={d.breakdown.map((b) => [
              <span key="f">{b.faculty ?? "—"}</span>,
              b.programme ? <span key="p">{b.programme}</span> : <span className="sub2 ink-red" key="p">{b.programme_code} — not a programme the University runs</span>,
              <b className="tnum" key="a">{Number(b.admitted).toLocaleString()}</b>,
              <span className="tnum" key="r">{Number(b.registered).toLocaleString()}</span>,
              <span className="tnum" key="y">{(Number(b.admitted) - Number(b.registered)).toLocaleString()}</span>,
            ])}
            texts={d.breakdown.map((b) => `${b.faculty ?? ""} ${b.programme ?? b.programme_code}`)}
          />
        ) : <PBody><div className="sub2">No committed admission list for this session yet. Commit a CAPS list on the JAMB admission lists screen, and the admitted appear here.</div></PBody>}
      </Panel>

      <Panel title="Applicants" right={`${d.applicants.length} shown${filtered ? " · filtered" : ""}`}>
        {d.applicants.length ? (
          <DTable cols={["Applicant", "JAMB number|mid", "Programme (University offers)", "Entry|mid", "Aggregate|mid", "Post-UTME|num"]} rows={d.applicants.map((a) => [
            <Two key="n" a={`${a.surname}, ${a.other_names}`} b={[a.faculty, a.registered && a.offer_state ? a.offer_state.charAt(0) + a.offer_state.slice(1).toLowerCase() : ""].filter(Boolean).join(" · ")} />,
            <span className="tnum" key="j">{a.jamb_reg_no}</span>,
            a.programme ? <span key="p">{a.programme}</span> : <span className="sub2 ink-red" key="p">{a.jamb_code} — not a programme the University runs</span>,
            <span className="sub2" key="e">{modeLabel(a.entry_mode)}</span>,
            <span className="tnum" key="ag">{a.aggregate ?? "—"}</span>,
            a.registered ? <Pil kind="ok" key="s">Registered</Pil> : <Pil kind="grey" key="s">Not yet</Pil>,
          ])} texts={d.applicants.map((a) => `${a.surname} ${a.other_names} ${a.jamb_reg_no}`)} />
        ) : <PBody><div className="sub2">{filtered ? "No applicant matches this filter on the committed list." : "No committed admission list for this session yet."}</div></PBody>}
      </Panel>

      {d.applicants.length >= 200 ? <Note kind="info" title="Only the first 200 are shown">Narrow the list with the faculty, programme or entry-mode filters, or search by name or JAMB number; the counts and the breakdown above are for the whole filtered list.</Note> : null}
    </>
  );
}
