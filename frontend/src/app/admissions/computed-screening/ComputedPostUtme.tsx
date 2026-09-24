"use client";

/** t/postutme — the Academic Office's computed Post-UTME for candidates who did not sit it (V090):
 *  the O'Level aggregate blended with the UTME, for Direct Entry and non-exam programmes. Read-only. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";

export interface Computed {
  jamb_reg_no: string; name: string; programme: string; entry_mode: string;
  olevel_total: number | null; olevel_ceiling: number | null; olevel_scaled: number | null;
  utme: number | null; computed: number | null; source: string;
}
export interface ProgAudit {
  programme: string; programme_code: string | null; index_programme: boolean;
  applications: number; submitted: number; applied_paid: number;
}

const SRC: Record<string, "ok" | "info" | "grey"> = { "O'Level + UTME": "ok", "O'Level": "info", UTME: "info", none: "grey" };

export function ComputedPostUtme({ rows, session, sessions, audit = [], actingOffice = null }: { rows: Computed[]; session: string; sessions: string[]; audit?: ProgAudit[]; actingOffice?: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const withUtme = rows.filter((r) => r.utme != null).length;
  const de = rows.filter((r) => r.entry_mode === "DIRECT_ENTRY").length;
  const mayEnter = ["academic", "registrar", "dregistrar", "ict", "admin", "super"].includes(actingOffice ?? "");
  const [entering, setEntering] = useState(false);
  const [entered, setEntered] = useState<{ entered: number; noOlevel: number } | null>(null);

  // enter these computed O'Level figures as the Post-UTME (screening) score for the non-index applicants,
  // so they get a screening figure and enter the merit list (release the scores afterwards)
  async function enterAsScores() {
    if (!window.confirm(`Enter the computed O'Level figure as the Post-UTME score for the ${rows.length} non-index applicant(s) shown? They then need the scores released to enter the merit list. A real score is never overwritten.`)) return;
    setEntering(true); setEntered(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/screening-scores/from-olevel`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`O'Level entered as Post-UTME score for non-index programmes for ${session}`) }, body: "{}",
      });
      const j = await r.json().catch(() => null);
      if (r.ok && j) { setEntered({ entered: Number(j.entered ?? 0), noOlevel: Number(j.noOlevel ?? 0) }); notify(`${Number(j.entered ?? 0)} O’Level scores entered`); router.refresh(); }
    } finally {
      setEntering(false);
    }
  }

  // export: the whole computed list, not just the page, with the crest, title and a serial
  const XCOLS = ["JAMB No", "Candidate", "Programme", "Mode", "O'Level /100", "O'Level total", "UTME", "Computed", "Basis"];
  // the export is grouped by programme, and within each programme the highest computed score first
  const xrows = (): (string | number | null)[][] => [...rows]
    .sort((a, b) => (a.programme ?? "").localeCompare(b.programme ?? "") || (b.computed ?? -1) - (a.computed ?? -1) || (a.name ?? "").localeCompare(b.name ?? ""))
    .map((r) => [
      r.jamb_reg_no, r.name, r.programme, r.entry_mode === "DIRECT_ENTRY" ? "Direct Entry" : r.entry_mode,
      r.olevel_scaled, r.olevel_total != null && r.olevel_ceiling ? `${r.olevel_total}/${r.olevel_ceiling}` : "",
      r.utme, r.computed, r.source,
    ]);
  const title = `Computed Post-UTME · ${session}`;
  function toExcel() {
    const serial = docSerial("CPU");
    void brandedXlsx(title, XCOLS, xrows(), { sheetName: "Computed Post-UTME", serial, sub: session })
      .then((blob) => downloadBlob(blob, `computed-post-utme-${session.replace(/[^0-9]+/g, "-")}.xlsx`));
  }
  function toPrint() {
    brandedPrint(title, `${session} · non-index programmes, applied and paid`, XCOLS, xrows(), docSerial("CPU"));
  }

  return (
    <>
      <Note kind="info" title="Computed Post-UTME for candidates who did not sit it">
        Direct Entry entrants and candidates in programmes not screened by examination never sit the Post-UTME. This is a
        <b> computed</b> screening figure for them, for the Academic Office: the UTME scaled to 100 and the O&rsquo;Level
        aggregate scaled to 100 (under the session&rsquo;s grading), combined on the session&rsquo;s admission weights —
        UTME 70%, O&rsquo;Level 30% by default; a Direct Entry candidate with no UTME shows the O&rsquo;Level figure alone.
        It lists the non-index programmes only, for applicants who applied and paid. Use <b>Enter O&rsquo;Level as Post-UTME
        score</b> to record the O&rsquo;Level figure (scaled to 100) as their screening score, then release the scores — so
        these applicants enter the merit list. A real Post-UTME score is never overwritten.
      </Note>
      <div className="card"><div className="card__body row row--end">
        <div style={{ minWidth: 160 }}><Field id="pu-s" label="Session">
          <select id="pu-s" className="ctl" value={session} onChange={(e) => queryNav(`/admissions/computed-screening?session=${encodeURIComponent(e.target.value)}`)}>
            {(sessions.includes(session) ? sessions : [session, ...sessions]).map((x) => <option key={x} value={x}>{x}</option>)}
          </select>
        </Field></div>
      </div></div>
      <Tiles items={[
        ["Non-sitters", String(rows.length), null, `${session} · did not sit the Post-UTME`],
        ["With a UTME to blend", String(withUtme), null, "O'Level + UTME computed"],
        ["Direct Entry", String(de), null, "O'Level basis (no UTME)"],
        ["O'Level only", String(rows.length - withUtme), null, "No UTME on record"],
      ]} />
      {entered ? (
        <Note kind="ok" title={`${entered.entered.toLocaleString()} O'Level figure${entered.entered === 1 ? "" : "s"} entered as the Post-UTME score`}>
          These non-index applicants now carry their O&rsquo;Level (scaled to 100) as the screening score. <b>Release the scores</b> (Upload PUTME Score → Release, or the Applicants desk) for them to enter the merit list.
          {entered.noOlevel ? <> {entered.noOlevel.toLocaleString()} still have no O&rsquo;Level on record, so nothing could be computed for them — upload their O&rsquo;Level, or score them zero.</> : null}
        </Note>
      ) : null}
      <Panel title="Computed Post-UTME" right={<span className="row row--inline">
        <span className="sub2">{rows.length} candidate{rows.length === 1 ? "" : "s"}</span>
        {mayEnter ? <Btn kind="primary" disabled={!rows.length || entering} onClick={() => void enterAsScores()}>{entering ? "Entering…" : "Enter O'Level as Post-UTME score"}</Btn> : null}
        <Btn kind="ghost" disabled={!rows.length} onClick={toExcel}>Download Excel</Btn>
        <Btn kind="ghost" disabled={!rows.length} onClick={toPrint}>Print / PDF</Btn>
      </span>}>
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

      {audit.length ? (
        <Panel title="Why a programme appears here — or does not" right={`${audit.length} programme${audit.length === 1 ? "" : "s"} with applications`}>
          <PBody>
            <div className="sub2 mb-2">
              A programme is on the computed list above when it is <b>not</b> exam-screened (non-index) <b>and</b> has applicants who applied and paid.
              An <b>index</b> programme is screened by the Post-UTME examination — its scores are uploaded, not computed (remove it from the exam list in Admission settings to make it non-index).
              A non-index programme with <b>0 applied &amp; paid</b> has no completed applications to compute yet.
            </div>
            <DTable
              cols={["Programme", "Screening|mid", "Applications|num", "Submitted|num", "Applied & paid|num", "On computed list|mid"]}
              rows={audit.map((a) => {
                const onList = !a.index_programme && a.applied_paid > 0;
                return [
                  <span key="p">{a.programme}{a.programme_code ? <span className="sub2"> · {a.programme_code}</span> : <span className="sub2 ink-red"> · no programme code matched</span>}</span>,
                  <Pil kind={a.index_programme ? "warn" : "ok"} key="s">{a.index_programme ? "Index (exam)" : "Non-index"}</Pil>,
                  <span className="tnum" key="a">{a.applications}</span>,
                  <span className="tnum" key="su">{a.submitted}</span>,
                  <span className="tnum" key="ap" style={{ color: a.applied_paid === 0 ? "var(--red-ink)" : undefined }}>{a.applied_paid}</span>,
                  <Pil kind={onList ? "ok" : "grey"} key="o">{onList ? "Yes" : a.index_programme ? "No — index" : "No — none paid"}</Pil>,
                ];
              })}
              texts={audit.map((a) => `${a.programme} ${a.programme_code ?? ""} ${a.index_programme ? "index" : "non-index"}`)}
            />
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
