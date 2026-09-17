"use client";

/** tCandidateData — proto/part54.html: three downloads, matched on the registration number, both ways. */
import { reasonHeader } from "@/lib/reason";
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import type { AttachmentState } from "@/lib/matriculation";
import { xlsxRows } from "@/lib/xlsx";
import { CRED, capsMatch, dobParse, jambNumFromName, olParse, type DobRow, type OlRow } from "@/lib/candidate-data";
import { Btn, Ico, IcoBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Passport } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { OlevelView } from "./OlevelView";

interface Pas { num: string; file: string; how: string; size: number; w: number; h: number; url: string }

const CD_TABS: [string, string, string][] = [
  ["pas", "Passports", "A folder of images, named by the JAMB number"],
  ["dob", "Dates of birth", "One spreadsheet row per candidate"],
  ["ol", "O’Level results", "One spreadsheet row per SUBJECT"],
];

export function CandidateData({ state, actingOffice }: { state: AttachmentState; actingOffice: string | null }) {
  const router = useRouter();
  const [viewing, setViewing] = useState<{ key: string; name: string } | null>(null);
  const [tab, setTab] = useState("pas");
  const [pas, setPas] = useState<Pas[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [dob, setDob] = useState<{ rows: DobRow[]; trimmed: number } | null>(null);
  const [ol, setOl] = useState<{ rows: OlRow[]; lines: number } | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);
  const [gq, setGq] = useState("");
  const [gprog, setGprog] = useState("");
  const [gshow, setGshow] = useState(60);
  const may = ["academic", "registrar", "dregistrar"].includes(actingOffice ?? "");

  /* V038: a file attaches only to a candidate on a committed list, so the matcher sees only committed candidates */
  const cands = state.candidates.filter((c) => c.committed).map((c) => ({ num: c.jambKey, name: `${c.surname}, ${c.otherNames}`, list: c.entryMode === "DIRECT_ENTRY" ? "de" : "utme", has: c }));
  const uncommitted = state.candidates.filter((c) => !c.committed).length;
  const held = (kind: string) => state.attachments.filter((a) => a.kind === kind);

  function readPassports(files: FileList | null) {
    if (!files || !files.length) return;
    setBusy(true);
    const out: Pas[] = [];
    let pending = files.length;
    const done = () => { if (!--pending) { out.sort((a, b) => (a.num < b.num ? -1 : 1)); setPas(out); setBusy(false); window.scrollTo(0, 0); } };
    Array.from(files).forEach((f) => {
      const got = jambNumFromName(f.name);
      const rd = new FileReader();
      rd.onload = () => {
        const img = new Image();
        img.onload = () => { out.push({ num: got.num, file: f.name, how: got.how, size: f.size, w: img.width, h: img.height, url: String(rd.result) }); done(); };
        img.onerror = () => { out.push({ num: got.num, file: f.name, how: got.how, size: f.size, w: 0, h: 0, url: "" }); done(); };
        img.src = String(rd.result);
      };
      rd.onerror = () => { out.push({ num: got.num, file: f.name, how: got.how, size: f.size, w: 0, h: 0, url: "" }); done(); };
      rd.readAsDataURL(f);
    });
  }

  async function readSheet(file: File | undefined, which: "dob" | "ol") {
    if (!file) return;
    setErr(null);
    try {
      const rows = await xlsxRows(await file.arrayBuffer());
      const res = which === "dob" ? dobParse(rows) : olParse(rows);
      if ("err" in res) { setErr(res.err); return; }
      if (which === "dob") setDob(res as { rows: DobRow[]; trimmed: number }); else setOl(res as { rows: OlRow[]; lines: number });
      window.scrollTo(0, 0);
    } catch (e) {
      setErr(`That file could not be read. ${e instanceof Error ? e.message : String(e)} An .xlsx is expected.`);
    }
  }

  async function record(kind: string, items: { sourceName: string; jambKey: string | null; readAs: string; payload: Record<string, unknown>; bytes?: number; widthPx?: number; heightPx?: number }[]) {
    setBusy(true);
    setProblem(null);
    /* A whole O'Level list is tens of MB in one body — too large for a single request; send it in
       tranches. record() is idempotent per source name and re-matches everything held on every call,
       so the tranches add up and the last findings stand. */
    const CHUNK = 400;
    try {
      let recorded = 0;
      const tally: Record<string, number> = {};
      for (let i = 0; i < items.length; i += CHUNK) {
        const slice = items.slice(i, i + CHUNK);
        if (items.length > CHUNK) setSaid(`Recording ${Math.min(i + slice.length, items.length)} of ${items.length}…`);
        const r = await fetch(`/api/bff/api/v1/admissions/sessions/${state.session}/candidate-data`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${kind} download recorded for ${state.session}`) }, body: JSON.stringify({ kind, items: slice }) });
        const j = await r.json().catch(() => null);
        if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
        recorded += (j.recorded as number) ?? 0;
        for (const a of (j.attached as { kind: string; newly_attached: number }[] | undefined) ?? []) {
          tally[a.kind] = (tally[a.kind] ?? 0) + a.newly_attached;
        }
      }
      const attached = Object.entries(tally).filter(([, n]) => n > 0).map(([k, n]) => `${n} ${k.toLowerCase().replace("_", " ")}`).join(", ");
      setSaid(`${recorded} recorded; ${attached || "nothing newly"} attached to a candidate.`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const counts = (m: ReturnType<typeof capsMatch>, unit: string, one: string) => (
    <Tiles items={[
      ["Matched to a candidate", String(m.matched.length), "var(--green-ink)", "Attached to the record"],
      [`${one} with no candidate`, String(m.orphan.length), m.orphan.length ? "var(--red-ink)" : null, m.orphan.length ? "Held, not discarded" : "Everything attached"],
      ["Candidates still waiting", String(m.missing.length), m.missing.length ? "var(--chrome)" : "var(--green-ink)", m.missing.length ? `No ${unit} yet` : "Every candidate has one"],
      ["On the admission lists", String(m.candidates), null, "UTME and Direct Entry"],
    ]} />
  );
  const orphans = (m: ReturnType<typeof capsMatch>, what: string, label: (o: { num: string }) => string) => m.orphan.length ? (
    <>
      <Note kind="bad" title={`${m.orphan.length} ${what} match no candidate on either list`}>
        They are <b>held, not discarded</b>. A file that matches nobody today matches somebody the moment the next tranche of the admission list is uploaded — JAMB sends these in a different order and on a different day. Throwing them away means downloading them again, and being unable to say whether they ever arrived.
      </Note>
      <Panel title="Held, waiting for a candidate" right="Matched again automatically when the next list is uploaded">
        <DTable cols={["JAMB number|mid", "What arrived"]} rows={m.orphan.slice(0, 10).map((o) => [<span className="tnum" key="n">{o.num}</span>, <span className="sub2" key="w">{label(o)}</span>])} />
      </Panel>
    </>
  ) : null;
  const missing = (m: ReturnType<typeof capsMatch>, what: string) => m.missing.length ? (
    <Panel title={`Candidates with no ${what} yet`} right={`${m.missing.length} of ${m.candidates}`}>
      <DTable cols={["JAMB number|mid", "Candidate", "List|mid"]} rows={m.missing.slice(0, 10).map((c) => [<span className="tnum" key="n">{c.num}</span>, <strong key="c">{c.name}</strong>, <Pil kind={c.list === "de" ? "info" : "grey"} key="l">{c.list === "de" ? "Direct Entry" : "UTME"}</Pil>])} />
    </Panel>
  ) : null;

  /* ── the passports already on record, for everyone who has one (V007) ── */
  const pasGallery = () => {
    const onRecord = state.candidates.filter((c) => c.hasPassport);
    if (!onRecord.length) return null;
    const base = `/api/bff/api/v1/admissions/sessions/${state.session}/candidate-data`;
    const progs = Array.from(new Set(onRecord.map((c) => c.programme))).sort();
    const q = gq.trim().toLowerCase();
    const shown = onRecord
      .filter((c) => !gprog || c.programme === gprog)
      .filter((c) => !q || `${c.surname} ${c.otherNames} ${c.jambKey}`.toLowerCase().includes(q))
      .sort((a, b) => a.programme.localeCompare(b.programme) || a.surname.localeCompare(b.surname) || a.otherNames.localeCompare(b.otherNames));
    const page = shown.slice(0, gshow);
    const noImage = onRecord.filter((c) => !c.hasPassportImage).length;
    return (
      <Panel title="Passports on record" right={`${onRecord.length} of ${state.candidates.length} candidates`}>
        <PBody>
          <div style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap", marginBottom: 12 }}>
            <div className="field" style={{ minWidth: 220, margin: 0 }}><label htmlFor="pg-q">Search</label>
              <input id="pg-q" className="ctl" value={gq} onChange={(e) => { setGq(e.target.value); setGshow(60); }} placeholder="Surname, other names or JAMB number" autoComplete="off" />
            </div>
            <div className="field" style={{ minWidth: 200, margin: 0 }}><label htmlFor="pg-p">Programme</label>
              <select id="pg-p" className="ctl" value={gprog} onChange={(e) => { setGprog(e.target.value); setGshow(60); }}>
                <option value="">All programmes</option>
                {progs.map((p) => <option key={p} value={p}>{p}</option>)}
              </select>
            </div>
            <span className="sub2">{shown.length} shown</span>
          </div>
          {noImage ? (
            <Note kind="info" title={`${noImage} candidate${noImage === 1 ? " has" : "s have"} a passport recorded without a stored image`}>
              A photograph over <b>64 KB</b> is recorded by name, size and dimensions only — the image itself was not kept in the browser, so there is nothing to show here for it. JAMB’s passports are tiny and almost always stored; a large one can be re-uploaded from the folder above to store the image.
            </Note>
          ) : null}
          {shown.length ? (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 12 }}>
              {page.map((c) => (
                <div key={c.id} style={{ width: 104 }}>
                  <Passport w={104} h={119} radius={6} src={c.hasPassportImage ? `${base}/passport/${c.id}/image` : null} alt={`${c.surname} ${c.otherNames}`} />
                  <div className="sub2" style={{ fontWeight: 600, marginTop: 4, lineHeight: 1.25 }}>{c.surname.toUpperCase()}</div>
                  <div className="sub2" style={{ lineHeight: 1.25 }}>{c.otherNames}</div>
                  <div className="sub2 tnum">{c.jambKey}</div>
                  <div className="sub2" style={{ lineHeight: 1.2 }}>{c.programme}</div>
                </div>
              ))}
            </div>
          ) : <div className="sub2">No candidate on record matches your search.</div>}
          {shown.length > gshow ? (
            <div style={{ marginTop: 12 }}><Btn kind="ghost" onClick={() => setGshow(gshow + 120)}>Show more — {shown.length - gshow} more</Btn></div>
          ) : null}
        </PBody>
      </Panel>
    );
  };

  /* ── passports ── */
  const pasBody = () => {
    const all = pas ?? [];
    const named = all.filter((p) => p.num);
    const unnamed = all.filter((p) => !p.num);
    const m = pas ? capsMatch(named, cands) : null;
    const small = m ? m.matched.filter((p) => p.w && p.w < 300) : [];
    const derived = named.filter((p) => p.how);
    return (
      <>
        <div className="card"><div className="card__body">
          <div className="eyebrow">Upload the passports downloaded from JAMB</div>
          <label className="drop" htmlFor="cd-pas" style={{ cursor: "pointer" }}>
            <Ico name="box" size={30} stroke="var(--chrome)" w={1.6} />
            <div className="drop__t">Choose the whole folder of photographs</div>
            <div className="drop__s">JAMB names each file after the candidate and then adds to it — <span className="tnum">202699168863AH_Face.jpg</span>. The registration number is read out of the name, whatever is wrapped around it, and that is what it is matched on. Select them all at once.</div>
            <input type="file" id="cd-pas" accept="image/*" multiple hidden onChange={(e) => readPassports(e.target.files)} />
          </label>
          {busy ? <div className="sub2">Reading…</div> : null}
          <div className="sub2">Nothing leaves this browser until you record what was read; a photograph over 64 KB is recorded by name, size and dimensions only.</div>
        </div></div>
        {!m ? (
          <Note kind="info" title={held("PASSPORT").length ? `${held("PASSPORT").length} photographs already recorded for ${state.session}` : "No photographs uploaded yet"}>{held("PASSPORT").length ? `${held("PASSPORT").filter((a) => a.matched).length} attached to a candidate, ${held("PASSPORT").filter((a) => !a.matched && a.jambKey).length} held for nobody yet, ${held("PASSPORT").filter((a) => a.readAs === "UNREADABLE").length} unreadable.${uncommitted ? ` ${uncommitted} candidate${uncommitted === 1 ? " is" : "s are"} on a list not yet committed — their files stay held until it is.` : ""} Choose the folder above to record more.` : "Choose the folder above."}</Note>
        ) : (
          <>
            {counts(m, "photograph", "Photographs")}
            {derived.length ? (
              <>
                <Note kind="info" title={`The registration number was read out of ${derived.length} filename${derived.length === 1 ? "" : "s"}`}>
                  JAMB does not send <span className="tnum">202699168863AH.jpg</span>. It sends <span className="tnum">202699168863AH_Face.jpg</span>, and stripping only the extension leaves <span className="tnum">202699168863AH_FACE</span>, which matches no candidate — so <b>every photograph would have arrived as an orphan</b>. The suffix is <b>not</b> stripped by name, because <i>_Face</i> is JAMB’s decision and JAMB can change it: what is done instead is to <b>find</b> the number in the name — twelve digits then two or three letters — which survives <i>_Face</i>, <i>(1)</i>, <i>Copy of</i>, and a folder path.
                </Note>
                <Panel title="What each number was read from" right={`${derived.length} of ${named.length} filenames`}>
                  <DTable cols={["JAMB number|mid", "The file as JAMB named it"]} rows={derived.slice(0, 10).map((p) => [<span className="tnum" key="n">{p.num}</span>, <span className="sub2 tnum" key="f">{p.file}</span>])} />
                </Panel>
              </>
            ) : null}
            {unnamed.length ? (
              <>
                <Note kind="bad" title={`${unnamed.length} file${unnamed.length === 1 ? " carries" : "s carry"} no registration number in the name`}>
                  Nothing in {unnamed.length === 1 ? "this name" : "these names"} has the shape of a JAMB number, so there is nobody to attach the photograph to and <b>no guess is made</b>. It is named here, with the filename as it arrived, for somebody to look at. A photograph put against the wrong candidate is worse than one not put anywhere.
                </Note>
                <Panel title="Named, not guessed at" right="A person has to say who these belong to">
                  <DTable cols={["The file as it arrived", "Size|num"]} rows={unnamed.slice(0, 10).map((p) => [<span className="tnum" key="f">{p.file}</span>, <span className="sub2" key="s">{Math.round(p.size / 1024)} KB</span>])} />
                </Panel>
              </>
            ) : null}
            {orphans(m, "photographs", (o) => (o as Pas).file)}
            {small.length ? (
              <Note kind="info" title={`${small.length} photograph${small.length === 1 ? " is" : "s are"} too small for an identity card`}>
                JAMB’s passports come at about <b>132 × 151 pixels</b> — roughly 11 × 13 mm once printed. That is ample for screening a candidate at a desk and matching a face to a record, and it is nowhere near enough for the identity card, which is why the card photograph is captured at the counter instead. These are stored as the <b>screening</b> photograph and are not offered to the card printer.
              </Note>
            ) : null}
            <Panel title="Photographs attached" right={`${m.matched.length} of ${m.candidates} candidates`}>
              <PBody>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 12 }}>
                  {m.matched.slice(0, 24).map((p) => (
                    <div key={p.file} style={{ width: 104 }}>
                      {p.url ? <img src={p.url} alt="" style={{ width: 104, height: 119, objectFit: "cover", border: "1px solid var(--line)", borderRadius: 6 }} /> : <div style={{ width: 104, height: 119, border: "1px solid var(--red-line)", borderRadius: 6, background: "var(--red-bg)" }} />}
                      <div className="sub2 tnum" style={{ marginTop: 4 }}>{p.num}</div>
                      <div className="sub2" style={{ lineHeight: 1.3 }}>{(m.byNum[p.num]?.name ?? "").split(",")[0]}</div>
                      <div className="sub2">{p.w}×{p.h}</div>
                    </div>
                  ))}
                </div>
                <div style={{ marginTop: 12 }}>
                  <Btn kind="primary" disabled={busy || !may} onClick={() => void record("PASSPORT", all.map((p) => ({ sourceName: p.file, jambKey: p.num || null, readAs: p.num ? (p.how ? "EMBEDDED" : "EXACT") : "UNREADABLE", payload: p.url && p.size <= 65536 ? { dataUrl: p.url } : {}, bytes: p.size, widthPx: p.w || undefined, heightPx: p.h || undefined })))}>Record what was read</Btn>
                </div>
              </PBody>
            </Panel>
            {missing(m, "photograph")}
          </>
        )}
        {pasGallery()}
      </>
    );
  };

  /* ── dates of birth ── */
  const dobBody = () => {
    const m = dob ? capsMatch(dob.rows, cands) : null;
    const amb = dob ? dob.rows.filter((r) => r.ambiguous) : [];
    return (
      <>
        <div className="card"><div className="card__body">
          <div className="eyebrow">Upload the date-of-birth file</div>
          <label className="btn btn--primary" htmlFor="cd-dob" style={{ cursor: "pointer", alignSelf: "flex-start" }}>Choose the date-of-birth file…<input type="file" id="cd-dob" accept=".xlsx" hidden onChange={(e) => void readSheet(e.target.files?.[0], "dob")} /></label>
        </div></div>
        {err ? <Note kind="bad" title="That file could not be read">{err}</Note> : null}
        {!m || !dob ? (
          <Note kind="info" title={held("DATE_OF_BIRTH").length ? `${held("DATE_OF_BIRTH").length} dates of birth already recorded for ${state.session}` : "No dates of birth uploaded yet"}>{held("DATE_OF_BIRTH").length ? `${held("DATE_OF_BIRTH").filter((a) => a.matched).length} attached to a candidate. Choose the file above to record more.` : "Choose the file above."}</Note>
        ) : (
          <>
            {counts(m, "date of birth", "Rows")}
            {dob.trimmed ? (
              <Note kind="info" title={`${dob.trimmed} registration number${dob.trimmed === 1 ? "" : "s"} had a trailing space, and were trimmed`}>
                Every number in this file ends with a space — <span className="tnum">“202440000065EA ”</span>. Joined as it arrives it matches <b>nothing at all</b>, and the screen would report nought matched, which reads as a broken import rather than as one stray character. Keys are trimmed on the way in from every file, and this note says when trimming is what made the match.
              </Note>
            ) : null}
            {amb.length ? (
              <Note kind="bad" title={`${amb.length} ${amb.length === 1 ? "date of birth is" : "dates of birth are"} ambiguous`} action={<Btn kind="urgent">Confirm the format with the Academic Office</Btn>}>
                Dates arrive as text in the form <b>DD-MM-YYYY</b>, and nothing in the file says so. Where both the day and the month are twelve or less the value reads equally well the other way round: <span className="tnum">05-07-2002</span> is the 5th of July or the 7th of May. That is not a rare edge: <b>144 of the 365 dates in a year — two in five — are ambiguous under this format</b>. They are <b>not parsed on an assumption</b>: a birthday moved by months is a candidate whose age at admission and whose match against NIN are both quietly wrong. One question to JAMB settles all of them.
              </Note>
            ) : null}
            {orphans(m, "rows", (o) => (o as DobRow).raw)}
            <Panel title="Dates of birth" right={`${m.matched.length} matched to a candidate`}>
              <DTable
                cols={["JAMB number|mid", "As JAMB gives the name", "On the admission list", "Date of birth|mid", "Reading"]}
                rows={m.matched.slice(0, 14).map((r) => [
                  <span className="tnum" key="n">{r.num}</span>,
                  <span key="j"><strong>{[r.surname, r.first, r.middle].filter(Boolean).join(" ")}</strong><div className="sub2">surname, first and middle, in three columns</div></span>,
                  <span key="l"><span className="sub2">{m.byNum[r.num]?.name}</span><div className="sub2">one column, on the admission list</div></span>,
                  <span className="tnum" key="d">{r.dob}</span>,
                  r.ambiguous ? <Pil kind="bad" key="r">ambiguous</Pil> : <span className="sub2" key="r">{r.reading}</span>,
                ])}
              />
              <PBody><Btn kind="primary" disabled={busy || !may} onClick={() => void record("DATE_OF_BIRTH", dob.rows.map((r) => ({ sourceName: `${r.raw}`, jambKey: r.num || null, readAs: "COLUMN", payload: { dob: r.dob, ambiguous: r.ambiguous, surname: r.surname, first: r.first, middle: r.middle, kind: r.kind } })))}>Record what was read</Btn></PBody>
            </Panel>
            {missing(m, "date of birth")}
          </>
        )}
      </>
    );
  };

  /* ── O'Level ── */
  const olBody = () => {
    const m = ol ? capsMatch(ol.rows, cands) : null;
    const short = m ? m.matched.filter((r) => !r.meets) : [];
    return (
      <>
        <div className="card"><div className="card__body">
          <div className="eyebrow">Upload the O’Level file</div>
          <label className="btn btn--primary" htmlFor="cd-ol" style={{ cursor: "pointer", alignSelf: "flex-start" }}>Choose the O’Level file…<input type="file" id="cd-ol" accept=".xlsx" hidden onChange={(e) => void readSheet(e.target.files?.[0], "ol")} /></label>
        </div></div>
        {err ? <Note kind="bad" title="That file could not be read">{err}</Note> : null}
        {!m || !ol ? (
          <Note kind="info" title={held("OLEVEL").length ? `${held("OLEVEL").length} O’Level results already recorded for ${state.session}` : "No O’Level results uploaded yet"}>{held("OLEVEL").length ? `${held("OLEVEL").filter((a) => a.matched).length} attached to a candidate. Choose the file above to record more.` : "Choose the file above."}</Note>
        ) : (
          <>
            <Note kind="info" title="The file is one row per SUBJECT, not per candidate">
              {ol.lines} rows collapsed to <b>{ol.rows.length} candidate{ol.rows.length === 1 ? "" : "s"}</b>. Nine rows is one candidate with nine subjects, so nothing can be said about whether anybody qualifies until the file is grouped by number. JAMB also abbreviates subject names inconsistently — <i>English Lang.</i>, <i>Lit. English</i>, <i>Bible Knowled/Crk</i> — so they are normalised before English and Mathematics can be found among them.
            </Note>
            {counts(m, "O’Level result", "Results")}
            {orphans(m, "results", (o) => `${(o as OlRow).subjects.length} subjects`)}
            {short.length ? (
              <Note kind="bad" title={`${short.length} candidate${short.length === 1 ? " does" : "s do"} not meet five credits including English and Mathematics`}>
                A credit is A1 to C6; D7, E8 and F9 are not. This is the general minimum and it is checked here because the file makes it free to check. <b>It is not the whole requirement:</b> each programme also names the subjects it wants, and those are Senate’s to set rather than this screen’s to assume.
              </Note>
            ) : null}
            <Panel title="O’Level results" right={`${m.matched.length} matched to a candidate`}>
              <DTable
                cols={["JAMB number|mid", "Candidate", "Exam|mid", "Year|mid", "Subjects|mid", "Credits|mid", "English|mid", "Maths|mid", "Five credits|num"]}
                rows={m.matched.map((r) => [
                  <span className="tnum" key="n">{r.num}</span>,
                  <span key="c"><strong>{m.byNum[r.num]?.name}</strong><div className="sub2">{r.subjects.map((s) => `${s.subject} ${s.grade}`).join(" · ")}</div></span>,
                  <span key="e"><span className="sub2">{r.type}</span><div className="sub2 tnum">{r.exnum}</div></span>,
                  <span className="tnum" key="y">{r.year}</span>, <span className="tnum" key="s">{r.subjects.length}</span>, <b className="tnum" key="k">{r.credits}</b>,
                  r.eng ? <Pil kind={CRED[r.eng] ? "ok" : "bad"} key="en">{r.eng}</Pil> : <Pil kind="bad" key="en">none</Pil>,
                  r.maths ? <Pil kind={CRED[r.maths] ? "ok" : "bad"} key="ma">{r.maths}</Pil> : <Pil kind="bad" key="ma">none</Pil>,
                  r.meets ? <Pil kind="ok" key="f">Yes</Pil> : <Pil kind="bad" key="f">No</Pil>,
                ])}
                texts={m.matched.map((r) => `${r.num} ${m.byNum[r.num]?.name ?? ""}`)}
              />
              <PBody><Btn kind="primary" disabled={busy || !may} onClick={() => void record("OLEVEL", ol.rows.map((r) => ({ sourceName: `${r.num} ${r.type} ${r.year}`.trim(), jambKey: r.num || null, readAs: "COLUMN", payload: { subjects: r.subjects, credits: r.credits, meets: r.meets, examNumber: r.exnum, year: r.year, type: r.type, sittings: r.sittings.map((s) => ({ type: s.type, year: s.year, examNumber: s.exnum, subjects: s.subjects })) } })))}>Record what was read</Btn></PBody>
            </Panel>
            <Panel title="Results recorded, and the screening score they carry" right={`${state.candidates.filter((c) => c.hasOlevel).length} of ${state.candidates.length} candidates`}>
              {state.candidates.some((c) => c.hasOlevel) ? (
                <DTable
                  cols={["Candidate", "Number|mid", "Programme", "|num"]}
                  texts={state.candidates.filter((c) => c.hasOlevel).map((c) => `${c.surname} ${c.otherNames} ${c.jambKey} ${c.programme}`)}
                  rows={state.candidates.filter((c) => c.hasOlevel).map((c) => [
                    <strong key="n">{c.surname}, {c.otherNames}</strong>,
                    <span className="tnum" key="k">{c.jambKey}</span>,
                    <span className="sub2" key="p">{c.programme}</span>,
                    <IcoBtn key="v" icon="eye" label={`View the O’Level read for ${c.surname}`} onClick={() => setViewing({ key: c.jambKey, name: `${c.surname}, ${c.otherNames}` })} />,
                  ])}
                />
              ) : (
                <div className="card__body"><div className="sub2">No result has attached to a candidate yet. They attach on the registration number once the admission list carries it.</div></div>
              )}
              <div className="card__body">
                <div className="sub2">
                  Each result is shown as JAMB sent it, sitting by sitting &mdash; WAEC, NECO and NABTEB apart. The screening score under the session&rsquo;s O&rsquo;Level grading is computed for the Academic Office and shown to nobody else, the applicant included.
                </div>
              </div>
            </Panel>
            {viewing ? <OlevelView session={state.session} jambKey={viewing.key} name={viewing.name} onClose={() => setViewing(null)} /> : null}
            <Note kind="info" title="The exam number is here so the result can be verified with WAEC, and it must be">
              JAMB passes on what the candidate declared and what the examination board returned; it is not itself the awarding body. The University verifies the result directly with WAEC or NECO before clearance, and a result that does not verify voids the admission — which is exactly why the exam number travels with the grades rather than being asked for again later.
            </Note>
            {missing(m, "O’Level result")}
          </>
        )}
      </>
    );
  };

  return (
    <>
      <Note kind="info" title="Three separate downloads, all matched on the JAMB registration number">
        The passports, the dates of birth and the O’Level results come from JAMB as three different things and arrive at different times. Each is matched to a candidate already on an admission list, and each is counted <b>both ways</b>: what arrived with nobody to attach it to, and who is still waiting for it.
      </Note>
      {!cands.length ? (
        <Note kind="bad" title="No admission list has been uploaded yet" action={<Link href={`/admissions/caps?session=${encodeURIComponent(state.session)}`} className="btn btn--primary btn--sm">Go to the admission lists</Link>}>
          There is nothing to match against. Upload the UTME or Direct Entry list first — these three attach to candidates, they do not create them. A photograph is not an admission.
        </Note>
      ) : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title="Recorded">{said}</Note> : null}
      {state.findings.some((f) => f.n) ? (
        <Panel title="As the register stands" right={state.session}>
          <DTable cols={["Finding", "Count|mid", "Whose|mid", "What it means"]} rows={state.findings.map((f) => [<strong key="f">{f.finding}</strong>, <span className="tnum" key="n">{f.n}</span>, <span className="sub2" key="o">{f.owner}</span>, <span className="sub2" key="w">{f.whatItMeans}</span>])} />
        </Panel>
      ) : null}
      <div className="card"><div className="card__body">
        <div className="rectabs">
          {CD_TABS.map((t) => {
            const n = t[0] === "pas" ? (pas ? pas.length : 0) : t[0] === "dob" ? (dob ? dob.rows.length : 0) : ol ? ol.rows.length : 0;
            return <button key={t[0]} className={`rectab${tab === t[0] ? " is-on" : ""}`} onClick={() => setTab(t[0])}><span className="t">{t[1]}{n ? ` · ${n}` : ""}</span><span className="s">{t[2]}</span></button>;
          })}
        </div>
      </div></div>
      {tab === "pas" ? pasBody() : tab === "dob" ? dobBody() : olBody()}
    </>
  );
}
