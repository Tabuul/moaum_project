"use client";

/** The matriculation number by configuration (V263): the format rule, the series with the last number each issued, each faculty's
 *  segment and series, each programme's code — or none — with its faculty segment and series, and the number every programme would
 *  give next. A code is never invented: a programme set to carry one without one is refused, and a series never goes back. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

export interface Format { id: string; university_code: string; faculty_code: boolean; programme_code: boolean; year: boolean; sequence: boolean; sequence_digits: number; separator: string; note: string | null }
export interface Series { code: string; name: string; last_issued: number; active: boolean; note: string | null; issued: number; last_issued_at: string | null }
export interface Faculty { code: string; name: string; matric_code: string | null; matric_series: string | null; programmes: number }
export interface ProgrammeRow { programme_code: string; programme: string; faculty_code: string; faculty: string; faculty_matric_code: string | null; faculty_series: string | null; matric_code: string | null; matric_uses_code: boolean; matric_faculty_code: string | null; matric_series: string | null; series_effective: string; sample: string; problem: string | null; students_admitted: number; archived: boolean; category: string | null }
export interface ConfigData { format: Format; series: Series[]; faculties: Faculty[]; programmes: ProgrammeRow[]; recent: { matric_no: string; series_code: string; sequence: number; issued_at: string; reason: string | null; student_name: string; programme: string | null }[] }

const CONFIG = ["academic", "registrar", "dregistrar", "super"];
async function put<T>(path: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1/matriculation/config${path}`, { method: "PUT", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}

export function MatricConfig({ data, office }: { data: ConfigData; office: string | null }) {
  const router = useRouter();
  const may = !!office && CONFIG.includes(office);
  const f = data.format;
  const [fmt, setFmt] = useState({ universityCode: f.university_code, facultyCode: f.faculty_code, programmeCode: f.programme_code, year: f.year, sequenceDigits: String(f.sequence_digits), separator: f.separator, note: f.note ?? "" });
  const [fac, setFac] = useState("");
  const [q, setQ] = useState("");
  const [busy, setBusy] = useState(false);
  const [ser, setSer] = useState<{ code: string; name: string; lastIssued: string; active: boolean; note: string; isNew: boolean } | null>(null);
  const [facForm, setFacForm] = useState<{ code: string; name: string; matricCode: string; matricSeries: string } | null>(null);
  const [prog, setProg] = useState<{ row: ProgrammeRow; matricCode: string; uses: boolean; facultyCode: string; series: string } | null>(null);
  const rows = data.programmes.filter((p) => (!fac || p.faculty_code === fac) && (!q || `${p.programme} ${p.programme_code} ${p.matric_code ?? ""}`.toLowerCase().includes(q.toLowerCase())));
  const missing = data.programmes.filter((p) => p.problem);
  const sample = (facSeg: string, progSeg: string | null, seq: number) => [fmt.universityCode, fmt.facultyCode ? facSeg : null, fmt.programmeCode ? progSeg : null, fmt.year ? new Date().getFullYear().toString().slice(2) : null, Number(fmt.sequenceDigits) > 0 ? String(seq).padStart(Number(fmt.sequenceDigits), "0") : String(seq)].filter((x) => x && x.trim()).join(fmt.separator);

  async function run<T>(p: Promise<{ ok: true; data: T } | { ok: false; problem: Problem }>, done: string) {
    setBusy(true);
    try { const r = await p; if (!r.ok) { notifyProblem(r.problem); return null; } notify(done); router.refresh(); return r.data; } finally { setBusy(false); }
  }
  const saveFormat = () => run(put("/format", { ...fmt, sequenceDigits: Number(fmt.sequenceDigits) || 0 }, "Matriculation format rule"), "Format saved");
  const saveSeries = async () => { if (!ser) return; if (await run(put(`/series/${ser.code}`, { name: ser.name, lastIssued: ser.lastIssued === "" ? null : Number(ser.lastIssued), active: ser.active, note: ser.note || null }, `Matriculation series ${ser.code}`), "Series saved")) setSer(null); };
  const saveFaculty = async () => { if (!facForm) return; if (await run(put(`/faculties/${facForm.code}`, { matricCode: facForm.matricCode || null, matricSeries: facForm.matricSeries || null }, `Matriculation segment of faculty ${facForm.code}`), "Faculty saved")) setFacForm(null); };
  const saveProgramme = async () => { if (!prog) return; if (await run(put(`/programmes/${prog.row.programme_code}`, { matricCode: prog.matricCode || null, matricUsesCode: prog.uses, matricFacultyCode: prog.facultyCode || null, matricSeries: prog.series || null }, `Matriculation code of ${prog.row.programme}`), "Programme saved")) setProg(null); };

  const HEAD = ["S/N", "Faculty", "Programme", "Programme Ref", "Faculty Segment", "Programme Code", "Carries Code", "Series", "Next Number", "Problem"];
  const body = () => rows.map((p, i) => [i + 1, p.faculty, p.programme, p.programme_code, p.matric_faculty_code ?? p.faculty_matric_code ?? p.faculty_code, p.matric_code ?? "", p.matric_uses_code ? "Yes" : "No", p.series_effective, p.sample, p.problem ?? ""]);
  async function excel() { const blob = await brandedXlsx("Matriculation Number Configuration", HEAD, body(), { sheetName: "Programmes", serial: docSerial("MAT") }); downloadBlob(blob, "matriculation-format.xlsx"); }

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/matriculation">Matriculation</Link><span>›</span><strong>Number format</strong></div>
      <PageHead title="Matriculation number format" description={`${f.university_code}${f.separator}{FACULTY}${f.programme_code ? `${f.separator}{PROGRAMME}` : ""}${f.year ? `${f.separator}{YY}` : ""}${f.separator}{SEQUENCE} — the programme segment only where the programme is configured to carry one; the sequence from the series the faculty or programme belongs to.`}
        actions={<><Btn kind="secondary" onClick={() => void excel()}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Matriculation Number Configuration", "", HEAD, body(), docSerial("MAT"))}>PDF</Btn><LinkBtn kind="ghost" href="/matriculation">Back to matriculation</LinkBtn></>} />
      {!may ? <Note kind="info" title="You are reading this configuration">The Registry and the Academic Office change it.</Note> : null}
      {missing.length ? <Note kind="bad" title={`${missing.length} programme(s) are set to carry a code and have none`}>A run that reaches one of them stops: no code is invented. Give each its code below, or set it to carry none.</Note> : null}
      <Tiles items={[["Series", String(data.series.length), null, data.series.map((s) => `${s.code} ${s.last_issued}`).join(" · ")], ["Programmes with a code", String(data.programmes.filter((p) => p.matric_code).length), "var(--green-ink)", `of ${data.programmes.length}`], ["Carrying none", String(data.programmes.filter((p) => !p.matric_uses_code).length), null, "Medicine, Pharmacy, Law and the unconfigured"], ["Numbers issued on record", String(data.series.reduce((a, s) => a + Number(s.issued), 0)), null, "Since this rule"]]} cls="grid--4" />

      <div className="grid grid--2">
        <Panel title="The format rule" right={<span className="tnum">{sample("AD", fmt.programmeCode ? "ACC" : null, 13557)} · {sample("MBBS", null, 6094)}</span>}>
          <PBody>
            <div className="grid grid--3">
              <Field id="mf-u" label="University code"><input id="mf-u" className="ctl" value={fmt.universityCode} onChange={(e) => setFmt({ ...fmt, universityCode: e.target.value.toUpperCase() })} maxLength={6} disabled={!may} /></Field>
              <Field id="mf-sep" label="Separator"><select id="mf-sep" className="ctl" value={fmt.separator} onChange={(e) => setFmt({ ...fmt, separator: e.target.value })} disabled={!may}><option value="/">/</option><option value="-">-</option></select></Field>
              <Field id="mf-d" label="Sequence padding" hint="0: the number as counted"><input id="mf-d" type="number" min={0} max={8} className="ctl" value={fmt.sequenceDigits} onChange={(e) => setFmt({ ...fmt, sequenceDigits: e.target.value })} disabled={!may} /></Field>
            </div>
            <div className="row row--tight mt-1" style={{ gap: 16 }}>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={fmt.facultyCode} onChange={(e) => setFmt({ ...fmt, facultyCode: e.target.checked })} disabled={!may} /> Faculty code</label>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={fmt.programmeCode} onChange={(e) => setFmt({ ...fmt, programmeCode: e.target.checked })} disabled={!may} /> Programme code (where the programme carries one)</label>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={fmt.year} onChange={(e) => setFmt({ ...fmt, year: e.target.checked })} disabled={!may} /> Year of entry</label>
              <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked disabled /> Sequence</label>
            </div>
            <Field id="mf-n" label="Note" full><input id="mf-n" className="ctl" value={fmt.note} onChange={(e) => setFmt({ ...fmt, note: e.target.value })} disabled={!may} /></Field>
            {may ? <Btn kind="primary" onClick={() => void saveFormat()} disabled={busy}>Save the rule</Btn> : null}
            <div className="sub2 mt-1">Numbers already issued never change; the rule governs the next one.</div>
          </PBody>
        </Panel>
        <Panel title="Series" right={may ? <Btn kind="secondary" onClick={() => setSer({ code: "", name: "", lastIssued: "0", active: true, note: "", isNew: true })}>Add a series</Btn> : `${data.series.length}`}>
          <DTable cols={["Series", "Last issued|num", "Issued here|num", "Last at|mid", "State|mid", "|num"]} rows={data.series.map((s) => [<span key="c"><strong>{s.name}</strong><div className="sub2 tnum">{s.code}{s.note ? ` · ${s.note}` : ""}</div></span>, <strong key="l" className="tnum">{s.last_issued}</strong>, <span key="i" className="tnum">{s.issued}</span>, <span key="a" className="tnum sub2">{s.last_issued_at ? new Date(s.last_issued_at).toLocaleDateString("en-GB") : "—"}</span>, <Pil key="st" kind={s.active ? "ok" : "grey"}>{s.active ? "Active" : "Off"}</Pil>, may ? <Btn key="e" kind="ghost" onClick={() => setSer({ code: s.code, name: s.name, lastIssued: String(s.last_issued), active: s.active, note: s.note ?? "", isNew: false })}>Edit</Btn> : <span key="e" />])} />
        </Panel>
      </div>

      <Panel title="Faculties" right="The segment the number carries, and the series">
        <DTable cols={["Faculty", "Code|mid", "Segment|mid", "Series|mid", "Programmes|num", "|num"]} rows={data.faculties.map((x) => [x.name, <span key="c" className="tnum sub2">{x.code}</span>, <strong key="m" className="tnum">{x.matric_code ?? x.code}</strong>, <span key="s" className="tnum">{x.matric_series ?? "GENERAL"}</span>, <span key="p" className="tnum">{x.programmes}</span>, may ? <Btn key="e" kind="ghost" onClick={() => setFacForm({ code: x.code, name: x.name, matricCode: x.matric_code ?? "", matricSeries: x.matric_series ?? "" })}>Edit</Btn> : <span key="e" />])} />
      </Panel>

      <Panel title="Programmes" right={<span className="row row--inline row--tight"><Field id="pc-fac" label=""><select id="pc-fac" className="ctl" value={fac} onChange={(e) => setFac(e.target.value)}><option value="">Every faculty</option>{data.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field><Field id="pc-q" label=""><input id="pc-q" className="ctl" placeholder="Search programme or code" value={q} onChange={(e) => setQ(e.target.value)} /></Field></span>}>
        <DTable pageSize={50} cols={["S/N|num", "Programme", "Faculty segment|mid", "Programme code|mid", "Carries code|mid", "Series|mid", "Next number", "|num"]} rows={rows.map((p, i) => [
          <span key="sn" className="tnum sub2">{i + 1}</span>,
          <span key="p"><strong>{p.programme}</strong><div className="sub2 tnum">{p.programme_code} · {p.faculty}{p.students_admitted ? ` · ${p.students_admitted} admitted awaiting a number` : ""}</div></span>,
          <span key="f" className="tnum">{p.matric_faculty_code ?? p.faculty_matric_code ?? p.faculty_code}{p.matric_faculty_code ? <span className="sub2"> (own)</span> : null}</span>,
          <strong key="c" className="tnum">{p.matric_code ?? "—"}</strong>,
          <Pil key="u" kind={p.matric_uses_code ? "ok" : "grey"}>{p.matric_uses_code ? "Yes" : "No"}</Pil>,
          <span key="s" className="tnum">{p.series_effective}{p.matric_series ? <span className="sub2"> (own)</span> : null}</span>,
          p.problem ? <Pil key="n" kind="bad">{p.problem}</Pil> : <strong key="n" className="tnum">{p.sample}</strong>,
          may ? <Btn key="e" kind="ghost" onClick={() => setProg({ row: p, matricCode: p.matric_code ?? "", uses: p.matric_uses_code, facultyCode: p.matric_faculty_code ?? "", series: p.matric_series ?? "" })}>Edit</Btn> : <span key="e" />,
        ])} texts={rows.map((p) => `${p.programme} ${p.programme_code} ${p.matric_code ?? ""} ${p.faculty}`)} />
      </Panel>

      <Panel title="Numbers issued most recently" right="From the history, never edited">
        {data.recent.length ? <DTable cols={["Number", "Student", "Programme", "Series|mid", "Issued|mid", "Why"]} rows={data.recent.map((h) => [<strong key="n" className="tnum">{h.matric_no}</strong>, h.student_name, <span key="p" className="sub2">{h.programme ?? ""}</span>, <span key="s" className="tnum">{h.series_code} · {h.sequence}</span>, <span key="i" className="tnum sub2">{new Date(h.issued_at).toLocaleString("en-GB")}</span>, <span key="r" className="sub2">{h.reason ?? ""}</span>])} /> : <PBody><div className="sub2">No number has been issued under this rule yet.</div></PBody>}
      </Panel>

      {ser ? (
        <Modal title={ser.isNew ? "A new series" : `Series ${ser.code}`} onClose={() => setSer(null)} foot={<><Btn kind="ghost" onClick={() => setSer(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveSeries()} disabled={busy || !ser.code.trim() || !ser.name.trim()}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="sr-c" label="Code" required><input id="sr-c" className="ctl" value={ser.code} onChange={(e) => setSer({ ...ser, code: e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "") })} disabled={!ser.isNew} maxLength={20} /></Field>
            <Field id="sr-n" label="Name" required><input id="sr-n" className="ctl" value={ser.name} onChange={(e) => setSer({ ...ser, name: e.target.value })} /></Field>
            <Field id="sr-l" label="Last number issued" hint="Moves forward only; the next number is this plus one"><input id="sr-l" type="number" min={0} className="ctl" value={ser.lastIssued} onChange={(e) => setSer({ ...ser, lastIssued: e.target.value })} /></Field>
            <Field id="sr-t" label="Note"><input id="sr-t" className="ctl" value={ser.note} onChange={(e) => setSer({ ...ser, note: e.target.value })} /></Field>
          </div>
          <label className="row row--tight" style={{ gap: 6 }}><input type="checkbox" checked={ser.active} onChange={(e) => setSer({ ...ser, active: e.target.checked })} /> Active</label>
        </Modal>
      ) : null}
      {facForm ? (
        <Modal title={`Faculty ${facForm.name}`} onClose={() => setFacForm(null)} foot={<><Btn kind="ghost" onClick={() => setFacForm(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveFaculty()} disabled={busy}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="ff-c" label="Segment the number carries" hint="Blank: the faculty's own code"><input id="ff-c" className="ctl" value={facForm.matricCode} onChange={(e) => setFacForm({ ...facForm, matricCode: e.target.value.toUpperCase() })} maxLength={6} /></Field>
            <Field id="ff-s" label="Series"><select id="ff-s" className="ctl" value={facForm.matricSeries} onChange={(e) => setFacForm({ ...facForm, matricSeries: e.target.value })}><option value="">General</option>{data.series.map((s) => <option key={s.code} value={s.code}>{s.name}</option>)}</select></Field>
          </div>
        </Modal>
      ) : null}
      {prog ? (
        <Modal title={prog.row.programme} sub={`${prog.row.programme_code} · ${prog.row.faculty}`} onClose={() => setProg(null)} foot={<><Btn kind="ghost" onClick={() => setProg(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveProgramme()} disabled={busy || (prog.uses && !prog.matricCode.trim())}>Save</Btn></>}>
          <div className="grid grid--2">
            <label className="row row--tight" style={{ gap: 6, gridColumn: "1 / -1" }}><input type="checkbox" checked={prog.uses} onChange={(e) => setProg({ ...prog, uses: e.target.checked })} /> This programme carries a programme code in the number</label>
            <Field id="pf-c" label="Programme code" hint="As the schedule prints it; never invented" required={prog.uses}><input id="pf-c" className="ctl" value={prog.matricCode} onChange={(e) => setProg({ ...prog, matricCode: e.target.value.toUpperCase() })} maxLength={6} disabled={!prog.uses} /></Field>
            <Field id="pf-f" label="Own faculty segment" hint={`Blank: the faculty's (${prog.row.faculty_matric_code ?? prog.row.faculty_code})`}><input id="pf-f" className="ctl" value={prog.facultyCode} onChange={(e) => setProg({ ...prog, facultyCode: e.target.value.toUpperCase() })} maxLength={6} /></Field>
            <Field id="pf-s" label="Series" hint={`Blank: the faculty's (${prog.row.faculty_series ?? "GENERAL"})`}><select id="pf-s" className="ctl" value={prog.series} onChange={(e) => setProg({ ...prog, series: e.target.value })}><option value="">The faculty&rsquo;s</option>{data.series.map((s) => <option key={s.code} value={s.code}>{s.name}</option>)}</select></Field>
          </div>
          <div className="sub2 mt-1">Next number: <strong className="tnum">{sample(prog.facultyCode || prog.row.faculty_matric_code || prog.row.faculty_code, prog.uses ? (prog.matricCode || "?") : null, (data.series.find((s) => s.code === (prog.series || prog.row.faculty_series || "GENERAL"))?.last_issued ?? 0) + 1)}</strong></div>
        </Modal>
      ) : null}
    </>
  );
}
