"use client";

/** V574: duplicate programmes merged into one, with their students. The database proposes the merges — codes of one name and
 *  department into the one most students sit on, an older code into the School's catalogue programme that answers to it, the
 *  catalogue's twins into the one in use — the Registry or the School ticks, changes or adds them (or uploads a mapping it edited),
 *  sees what they would do, and merges them with a reason, a few at a time. Each merge can be undone from its record. */
import { Fragment, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import {
  KIND, choicesOf, chunks, movedWords, orderedPairs, readMapping,
  type MergeEffect, type MergeKind, type MergeProgramme, type MergeRecord, type MergeSuggestion,
} from "@/lib/programme-merge";

const BASE = "/api/bff/api/v1/records/programme-merge";
const MERGERS = ["records", "registrar", "dregistrar", "pgschool", "pgsecretary", "super"];
const STEPS: [number, string, string][] = [
  [1, "1 · Codes of one name", "The old portal's codes of one programme, into the one most of its students sit on"],
  [2, "2 · Into the School's catalogue", "Each older programme into the School's programme of its degree and department"],
  [3, "3 · Twins in the catalogue", "Two programmes of one name in the School's own catalogue, into the one in use"],
];
const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

interface Row { step: number; kind: MergeKind | "UPLOADED"; from: string; fromName: string; students: number; to: string; why: string; choices: { code: string; name: string }[] }

export function ProgrammeMerge({ category, suggestions, programmes, history, office }: {
  category: string; suggestions: MergeSuggestion[]; programmes: MergeProgramme[]; history: MergeRecord[]; office: string | null;
}) {
  const router = useRouter();
  const mayMerge = MERGERS.includes(office ?? "") && !(category !== "POST GRADUATE" && ["pgschool", "pgsecretary"].includes(office ?? ""));
  const names = useMemo(() => new Map(programmes.map((p) => [p.code, p.name])), [programmes]);
  const [rows, setRows] = useState<Row[]>(() => suggestions.map((s) => ({
    step: s.step, kind: s.kind, from: s.from_code, fromName: s.from_name, students: Number(s.from_students), to: s.to_code ?? "", why: s.why, choices: choicesOf(s),
  })));
  const [ticked, setTicked] = useState<Set<string>>(() => new Set(suggestions.filter((s) => KIND[s.kind]?.ticked && s.to_code).map((s) => s.from_code)));
  const [changing, setChanging] = useState<Set<string>>(new Set());
  const [effect, setEffect] = useState<MergeEffect[] | null>(null);
  const [asking, setAsking] = useState(false);
  const [reason, setReason] = useState("");
  const [progress, setProgress] = useState<string | null>(null);
  const [undoing, setUndoing] = useState<MergeRecord | null>(null);
  const [undoReason, setUndoReason] = useState("");
  const [mapping, setMapping] = useState<string | null>(null);

  const chosen = rows.filter((r) => ticked.has(r.from) && r.to && r.to !== r.from);
  const pairs = orderedPairs(chosen.map((r) => ({ step: r.step, from: r.from, to: r.to })));
  const chosenStudents = chosen.reduce((n, r) => n + r.students, 0);
  const onDuplicates = rows.reduce((n, r) => n + r.students, 0);

  const tick = (code: string, on: boolean) => setTicked((t) => { const n = new Set(t); if (on) n.add(code); else n.delete(code); return n; });
  const target = (code: string, to: string) => { setRows((rs) => rs.map((r) => (r.from === code ? { ...r, to } : r))); setEffect(null); if (to) tick(code, true); };

  async function send<T>(path: string, body: unknown, why: string): Promise<T | null> {
    const r = await fetch(`${BASE}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
    return j as T;
  }

  async function preview() {
    const j = await send<MergeEffect[]>("/preview", { pairs }, `What ${pairs.length} programme merges would do`);
    if (j) setEffect(j);
  }

  async function merge() {
    const groups = chunks(pairs, 20);
    let done = 0;
    let students = 0;
    for (const g of groups) {
      setProgress(`Merging ${done + 1}–${done + g.length} of ${pairs.length}…`);
      const j = await send<MergeEffect[]>("", { pairs: g, reason: reason.trim() }, `Programmes merged: ${reason.trim()}`);
      if (!j) { setProgress(done ? `${done} merged before the refusal; the rest were not.` : null); router.refresh(); return; }
      done += j.length;
      students += j.reduce((n, e) => n + Number(e.students ?? 0), 0);
    }
    setProgress(null);
    setAsking(false);
    setEffect(null);
    notify(`${done} programme${done === 1 ? "" : "s"} merged; ${students} student move${students === 1 ? "" : "s"} recorded`);
    router.refresh();
  }

  async function undo() {
    if (!undoing) return;
    const j = await send<{ students: number }>(`/${undoing.id}/undo`, { reason: undoReason.trim() }, `Programme merge ${undoing.from_code} into ${undoing.to_code} undone: ${undoReason.trim()}`);
    if (j) {
      notify(`${undoing.from_code} is its own programme again; ${j.students} student${j.students === 1 ? "" : "s"} back on it`);
      setUndoing(null);
      setUndoReason("");
      router.refresh();
    }
  }

  async function excel() {
    const head = ["Step", "What", "Old code", "Old programme", "Students", "Merge into", "Into programme", "Why", "Choices"];
    const body = rows.map((r) => [r.step, r.kind === "UPLOADED" ? "From the mapping" : KIND[r.kind].label, r.from, r.fromName, r.students, r.to, names.get(r.to) ?? "", r.why,
      r.choices.map((c) => `${c.code} ${c.name}`).join("; ")]);
    downloadBlob(await brandedXlsx("Programme Merge: Proposed", head, body, {
      sub: `${category === "POST GRADUATE" ? "Postgraduate" : "Undergraduate"} programmes · fill "Merge into" where the School chooses, then upload the file here`, serial: docSerial("PMG"),
    }), `programme-merge-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function upload(file: File) {
    const grid = /\.csv$/i.test(file.name) ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
    const read = readMapping(grid.map((r) => r.map((c) => String(c ?? ""))));
    if (read.problem) { notifyProblem({ status: 400, title: "That file could not be read as a mapping", detail: read.problem }); return; }
    const known = new Set(rows.map((r) => r.from));
    setRows((rs) => [
      ...rs.map((r) => { const p = read.pairs.find((x) => x.from === r.from); return p ? { ...r, to: p.to } : r; }),
      ...read.pairs.filter((p) => !known.has(p.from)).map((p) => ({ step: 2, kind: "UPLOADED" as const, from: p.from, fromName: names.get(p.from) ?? "", students: 0, to: p.to, why: "from the mapping uploaded", choices: [] })),
    ]);
    setTicked(new Set(read.pairs.map((p) => p.from)));
    setEffect(null);
    setMapping(`${file.name}: ${read.pairs.length} merge${read.pairs.length === 1 ? "" : "s"} read and ticked; nothing else is ticked.`);
  }

  const targetCell = (r: Row) => {
    const open = changing.has(r.from) || !r.to;
    if (!open) {
      return <span><Two a={<span className="tnum">{r.to}</span>} b={names.get(r.to) ?? r.to} />
        {mayMerge ? <button type="button" className="lnk sub2" onClick={() => setChanging((c) => new Set(c).add(r.from))}>Change</button> : null}</span>;
    }
    return (
      <select className="ctl" aria-label={`Merge ${r.from} into`} value={r.to} onChange={(e) => target(r.from, e.target.value)} style={{ maxWidth: 320 }}>
        <option value="">Leave it as it is</option>
        {r.choices.length ? <optgroup label="The department's programmes of this degree">{r.choices.map((c) => <option key={c.code} value={c.code}>{`${c.code} ${c.name}`}</option>)}</optgroup> : null}
        <optgroup label="Every programme">{programmes.filter((p) => p.code !== r.from).map((p) => <option key={p.code} value={p.code}>{`${p.code} ${p.name}${p.award ? "" : " (older code)"}`}</option>)}</optgroup>
      </select>
    );
  };

  return (
    <>
      <Note kind="info" title="One programme, one code">
        Merging a programme into another moves its students, applications, fee lines and settings to the one kept. Each student&rsquo;s move is recorded, and the
        old code is archived and kept as another name of the programme, so a later upload naming it lands on the merged programme. Matriculation numbers,
        results and payments do not change. A merge can be undone from its record below.
      </Note>
      <div className="row row--tight" style={{ flexWrap: "wrap", gap: 8 }}>
        <LinkBtn kind={category === "POST GRADUATE" ? "primary" : "ghost"} size="sm" href="/records/programme-merge?category=POST%20GRADUATE">Postgraduate</LinkBtn>
        <LinkBtn kind={category === "UNDER GRADUATE" ? "primary" : "ghost"} size="sm" href="/records/programme-merge?category=UNDER%20GRADUATE">Undergraduate</LinkBtn>
      </div>
      <Tiles items={[
        ["Merges proposed", String(rows.filter((r) => r.to).length), null, `${rows.length} codes looked at`],
        ["Students on them", String(onDuplicates), null, "Students on the codes proposed for a merge"],
        ["Ticked", String(pairs.length), pairs.length ? "var(--green-ink)" : null, `${chosenStudents} student${chosenStudents === 1 ? "" : "s"} would move`],
        ["Merges made", String(history.filter((m) => !m.undone_at).length), null, `${history.filter((m) => m.undone_at).length} undone`],
      ]} />
      <Panel title="The merges" right={<span className="row row--tight" style={{ gap: 6 }}>
        <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={() => excel()}>Excel</Btn>
        <label className="btn btn--ghost btn--sm" style={{ cursor: "pointer" }}>Upload a mapping
          <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
        </label>
      </span>}>
        <PBody>
          <div className="sub2">Ticked merges run in the order shown: codes of one name first, then into the School&rsquo;s catalogue, then the catalogue&rsquo;s twins.
            Where the School chooses, pick the programme, or download the Excel, fill &ldquo;Merge into&rdquo; and upload it.</div>
          {mapping ? <div className="sub2 mt-1">{mapping}</div> : null}
        </PBody>
        {rows.length ? STEPS.map(([step, title, sub]) => {
          const these = rows.filter((r) => r.step === step);
          if (!these.length) return null;
          return (
            <Fragment key={step}>
              <PBody><div className="b600">{title}</div><div className="sub2">{sub}</div></PBody>
              <DTable cols={["|mid", "Programme", "Students|num", "Merge into", "Why"]} rows={these.map((r) => [
                <input key="t" type="checkbox" className="chk" aria-label={`Merge ${r.from}`} disabled={!r.to} checked={ticked.has(r.from) && !!r.to}
                  onChange={(e) => { tick(r.from, e.target.checked); setEffect(null); }} />,
                <Two key="f" a={<span className="tnum">{r.from}</span>} b={r.fromName} />,
                <span key="n" className="tnum">{r.students}</span>,
                <span key="to">{targetCell(r)}</span>,
                <span key="w"><Pil kind={r.kind === "UPLOADED" ? "info" : KIND[r.kind].tone}>{r.kind === "UPLOADED" ? "From the mapping" : KIND[r.kind].label}</Pil><div className="sub2">{r.why}</div></span>,
              ])} texts={these.map((r) => `${r.from} ${r.fromName} ${r.to} ${names.get(r.to) ?? ""}`)} />
            </Fragment>
          );
        }) : <PBody><div className="sub2">No duplicate programme is left to merge.</div></PBody>}
        <PBody>
          <div className="row row--tight" style={{ gap: 8, flexWrap: "wrap" }}>
            <Btn kind="ghost" disabled={!pairs.length} busyLabel="Working it out…" onClick={() => preview()}>{`See what ${pairs.length} merge${pairs.length === 1 ? "" : "s"} would do`}</Btn>
            {mayMerge ? <Btn kind="primary" disabled={!pairs.length || !effect} onClick={() => setAsking(true)}>{`Merge ${pairs.length} programme${pairs.length === 1 ? "" : "s"}`}</Btn>
              : <span className="sub2">Programmes are merged by the Registry, and postgraduate programmes by the School of Postgraduate Studies.</span>}
          </div>
          {mayMerge && pairs.length && !effect ? <div className="sub2 mt-1">See what they would do first.</div> : null}
        </PBody>
      </Panel>
      {effect ? (
        <Panel title={`What ${effect.length} merge${effect.length === 1 ? "" : "s"} would do`} right={`${effect.filter((e) => e.refused).length} refused`}>
          <DTable cols={["Programme", "Into", "Students|num", "Moved", "Left on the old code"]} rows={effect.map((e) => [
            <Two key="f" a={<span className="tnum">{e.from}</span>} b={e.fromName ?? names.get(e.from) ?? ""} />,
            <Two key="t" a={<span className="tnum">{e.to}</span>} b={e.toName ?? names.get(e.to) ?? ""} />,
            <span key="n" className="tnum">{e.refused ? "—" : Number(e.students ?? 0)}</span>,
            <span key="m">{e.refused ? <Pil kind="bad">Refused</Pil> : movedWords(e.moved)}{e.refused ? <div className="sub2">{e.refused.replace(/^[A-Z_]+: /, "")}</div> : null}</span>,
            <span key="k" className="sub2">{e.kept && Object.keys(e.kept).length ? movedWords(e.kept) : "—"}</span>,
          ])} />
        </Panel>
      ) : null}
      <Panel title="Merges made" right={`${history.length} · the latest first`}>
        {history.length ? (
          <DTable cols={["When|mid", "Programme", "Into", "Students|num", "Why", "|num"]} rows={history.map((m) => [
            <span key="w" className="sub2 tnum">{when(m.merged_at)}<div>{m.merged_by_name ?? m.merged_office ?? ""}</div></span>,
            <Two key="f" a={<span className="tnum">{m.from_code}</span>} b={m.from_name} />,
            <Two key="t" a={<span className="tnum">{m.to_code}</span>} b={m.to_name} />,
            <span key="n" className="tnum">{m.students}</span>,
            <span key="r" className="sub2">{m.reason}{m.undone_at ? <div><Pil kind="grey">Undone</Pil> {when(m.undone_at)}{m.undone_by_name ? ` · ${m.undone_by_name}` : ""}: {m.undo_reason}</div> : null}</span>,
            <span key="u">{mayMerge && m.may_undo ? <Btn kind="ghost" size="sm" onClick={() => { setUndoing(m); setUndoReason(""); }}>Undo</Btn> : null}</span>,
          ])} texts={history.map((m) => `${m.from_code} ${m.from_name} ${m.to_code} ${m.to_name} ${m.reason}`)} />
        ) : <PBody><div className="sub2">No programme has been merged yet.</div></PBody>}
      </Panel>
      {asking ? (
        <Modal title={`Merge ${pairs.length} programme${pairs.length === 1 ? "" : "s"}`} onClose={() => { if (!progress) setAsking(false); }}
          foot={<><Btn kind="ghost" disabled={!!progress} onClick={() => setAsking(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={reason.trim().length < 10 || !!progress} busyLabel="Merging…" onClick={() => merge()}>Merge them</Btn></>}>
          <p>{chosenStudents} student{chosenStudents === 1 ? "" : "s"} move to the programme kept, each move recorded. The old codes are archived and kept as other names
            of the programmes they were merged into. They are sent twenty at a time.</p>
          <Field id="pm-reason" label="Why these are one programme" required hint="Ten characters or more; kept with each merge and each student's move">
            <textarea id="pm-reason" className="ctl" rows={3} maxLength={2000} value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. The School of Postgraduate Studies' list of programmes, approved by the Board on …" />
          </Field>
          {progress ? <div className="sub2">{progress}</div> : null}
        </Modal>
      ) : null}
      {undoing ? (
        <Modal title={`Undo: ${undoing.from_code} into ${undoing.to_code}`} onClose={() => setUndoing(null)}
          foot={<><Btn kind="ghost" onClick={() => setUndoing(null)}>Cancel</Btn>
            <Btn kind="primary" disabled={undoReason.trim().length < 10} busyLabel="Undoing…" onClick={() => undo()}>Undo the merge</Btn></>}>
          <p>{undoing.from_name} becomes its own programme again: what the merge moved goes back to it, and its students&rsquo; moves are recorded.</p>
          <Field id="pm-undo" label="Why it is undone" required hint="Ten characters or more">
            <textarea id="pm-undo" className="ctl" rows={3} maxLength={2000} value={undoReason} onChange={(e) => setUndoReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </>
  );
}
