"use client";

/**
 * V535: a fee upload shown before it changes anything. The structure upload (Fee Setup) and the "fees to state" sheet (Students
 * with no school fee stated) are applied and undone on the server, and this window shows what they would do: for each faculty
 * or programme the lines new, changed, the same and ended, every amount that changes, a faculty that would be left with no line,
 * and the students with no fee stated before and after. The structure is uploaded for the faculties and programmes in the file
 * only, unless the Bursary chooses the whole session — and then confirms the faculties it would end. A workbook in the College's
 * block layout has each block matched to a programme or faculty here first.
 */
import { useEffect, useMemo, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { semesterName } from "@/lib/student-portal";
import { blockRows, suggestTargets, type ReadWorkbook, type StructureRow, type Target } from "@/lib/fee-matrix";

export type UploadRead = ReadWorkbook | { layout: "LINES"; rows: Record<string, string>[] };
interface Effect {
  action: "STRUCTURE" | "LINES"; scope: "LISTED" | "SESSION" | null; result: Record<string, unknown>;
  linesBefore: number; linesAfter: number;
  totals: { new: number; changed: number; same: number; ended: number };
  groups: { faculty: string; facultyCode: string | null; programme: string | null; programmeCode: string | null; new: number; changed: number; same: number; ended: number; losesAll: boolean }[];
  changes: { faculty: string; programme: string | null; level: number | null; entryMode: string | null; semester: number | null; indigene: string | null; spillover: boolean; item: string; old: number; new: number }[];
  gaps: { before: { students: number; groups: number }; after: { students: number; groups: number };
    rows: { faculty: string; programme: string | null; level: number | null; entryMode: string | null; spillover: boolean; students: number }[] };
}

const naira = (n: number | string) => `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;
const count = (n: number) => Number(n).toLocaleString("en-NG");
const named = (s: string | null | undefined) =>
  (s ?? "").toLowerCase().replace(/(^|\s)\S/g, (c) => c.toUpperCase()).replace(/ (And|Of|For|In|The) /g, (m) => m.toLowerCase());
const MODE: Record<string, string> = { UTME: "UTME", DIRECT_ENTRY: "Direct entry", TRANSFER: "Transfer", JUPEB: "JUPEB", SANDWICH: "Sandwich", CCE: "CCE", POSTGRADUATE: "Postgraduate" };
const levelText = (level: number | null, spill: boolean) => (spill ? "Spillover" : level ? `${level}` : "Every level");
const semText = (s: number | null) => (s ? semesterName(s) : "Whole session");

export function FeeUploadPreview({ session, action, fileName, read, cce = false, programmes, faculties, onClose, onApplied }: {
  session: string; action: "STRUCTURE" | "LINES"; fileName: string; read: UploadRead; cce?: boolean;
  programmes: { code: string; name: string; category: string; faculty_code: string }[]; faculties: { code: string; name: string }[];
  onClose: () => void; onApplied: (result: Record<string, unknown>, scope: "LISTED" | "SESSION" | null) => void;
}) {
  const targets = useMemo<Target[]>(() => [
    ...programmes.filter((p) => !/post/i.test(p.category)).map((p): Target => ({ kind: "PROGRAMME", code: p.code, name: p.name, faculty_code: p.faculty_code })),
    ...faculties.map((f): Target => ({ kind: "FACULTY", code: f.code, name: f.name })),
  ], [programmes, faculties]);
  const blocks = read.layout === "BLOCKS" ? read.blocks : [];
  const [mapping, setMapping] = useState<string[]>(() => suggestTargets(blocks.map((b) => b.label), targets).map((t) => (t ? `${t.kind === "PROGRAMME" ? "P" : "F"}:${t.code}` : "")));
  const [scope, setScope] = useState<"LISTED" | "SESSION">("LISTED");
  const [confirmWhole, setConfirmWhole] = useState(false);
  const [effect, setEffect] = useState<Effect | null>(null);
  const [effectFor, setEffectFor] = useState("");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState<"preview" | "apply" | null>(null);

  const rows = useMemo<(StructureRow | Record<string, string>)[]>(() => {
    if (read.layout === "LINES" || read.layout === "FLAT" || read.layout === "MATRIX") return read.rows;
    if (read.layout !== "BLOCKS") return [];
    return read.blocks.flatMap((b, i) => {
      const m = mapping[i] ?? "";
      if (!m) return [];
      return blockRows(b, m.startsWith("P:") ? { programmeCode: m.slice(2) } : { faculty: m.slice(2) });
    });
  }, [read, mapping]);
  const ask = JSON.stringify({ rows, scope: action === "STRUCTURE" ? scope : null });
  const left = blocks.filter((_, i) => !mapping[i]).length;
  const base = `/api/bff/api/v1/finance/sessions/${session}/${action === "STRUCTURE" ? "fee-structure" : "fee-lines"}`;

  // the effect, worked out again whenever what would be sent changes
  useEffect(() => {
    if (!rows.length) return; // nothing to send: the window says so
    let alive = true;
    const t = setTimeout(() => {
      void (async () => {
        setBusy("preview");
        setProblem(null);
        try {
          const r = await fetch(`${base}/preview`, { method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify(action === "STRUCTURE" ? { rows, scope } : { rows }) });
          const j = await r.json().catch(() => null);
          if (!alive) return;
          if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); setEffect(null); setEffectFor(""); return; }
          setEffect(j as Effect);
          setEffectFor(ask);
          setConfirmWhole(false);
        } finally {
          if (alive) setBusy(null);
        }
      })();
    }, 350);
    return () => { alive = false; clearTimeout(t); };
    // ask carries rows and scope
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ask]);

  const losing = (effect?.groups ?? []).filter((g) => g.losesAll);
  const wholeNeedsWord = action === "STRUCTURE" && scope === "SESSION" && losing.length > 0;
  const current = effect !== null && effectFor === ask;
  const nothing = current && effect.totals.new + effect.totals.changed + effect.totals.ended === 0;

  async function apply() {
    setBusy("apply");
    setProblem(null);
    try {
      const reason = action === "STRUCTURE"
        ? `Approved ${cce ? "CCE " : ""}fees structure uploaded for ${session} (${scope === "SESSION" ? "the whole session replaced" : "the faculties and programmes in the file"}) from ${fileName}`
        : `Fee lines stated for ${session} from the sheet of students with no fee stated (${fileName})`;
      const r = await fetch(base, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
        body: JSON.stringify(action === "STRUCTURE" ? { rows, scope, confirmWhole: scope === "SESSION" } : { rows }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      onApplied(j as Record<string, unknown>, action === "STRUCTURE" ? scope : null);
    } finally {
      setBusy(null);
    }
  }

  const applyLabel = action === "LINES" ? `Add ${effect ? count(effect.totals.new) : ""} line${effect?.totals.new === 1 ? "" : "s"}`
    : scope === "SESSION" ? `Replace the whole ${cce ? "CCE" : "full-time"} structure` : `Replace only what the file names`;
  const layoutWords = read.layout === "BLOCKS" ? `${read.blocks.length} block${read.blocks.length === 1 ? "" : "s"} in the College layout`
    : read.layout === "MATRIX" ? "the faculty cross-tab" : read.layout === "FLAT" ? "one row per fee" : read.layout === "LINES" ? "the sheet of fees to state" : "";

  return (
    <Modal wide title={action === "STRUCTURE" ? `Before the structure is uploaded for ${session}` : `Before the lines are added for ${session}`}
      sub={`${fileName} · ${layoutWords} · ${count(rows.length)} line${rows.length === 1 ? "" : "s"} read`}
      onClose={onClose}
      foot={<>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind={action === "STRUCTURE" && scope === "SESSION" ? "urgent" : "primary"} busy={busy === "apply"}
          disabled={!current || busy !== null || !rows.length || nothing || (wholeNeedsWord && !confirmWhole)} onClick={() => void apply()}>
          {busy === "apply" ? "Applying…" : applyLabel}
        </Btn>
      </>}>
      {read.layout === "BLOCKS" ? (
        <>
          <div className="sub2">Each block of the sheet is charged to the programme or faculty it names. Check each one; a block left out is not uploaded.</div>
          <DTable pageSize={0} cols={["Block in the sheet", "Lines|num", "Charged to"]} rows={read.blocks.map((b, i) => [
            <span key="b"><b>{b.label}</b><div className="sub2">{b.bands.map((x) => x.head).join(" · ")}</div></span>,
            <span key="n" className="tnum">{count(b.lines.length)}</span>,
            <select key="t" aria-label={`Charge ${b.label} to`} className="ctl" style={{ minWidth: 260 }} value={mapping[i] ?? ""}
              onChange={(e) => setMapping((m) => m.map((v, k) => (k === i ? e.target.value : v)))}>
              <option value="">Leave this block out</option>
              <optgroup label="Programmes">
                {targets.filter((t) => t.kind === "PROGRAMME").map((t) => <option key={t.code} value={`P:${t.code}`}>{t.name} ({t.code})</option>)}
              </optgroup>
              <optgroup label="Faculties (every programme of it)">
                {targets.filter((t) => t.kind === "FACULTY").map((t) => <option key={t.code} value={`F:${t.code}`}>{named(t.name)}</option>)}
              </optgroup>
            </select>,
          ])} />
          {left ? <Note kind="bad" title={`${left} block${left === 1 ? " is" : "s are"} left out`}>Choose the programme or faculty for {left === 1 ? "it" : "each"}, or upload without {left === 1 ? "it" : "them"}.</Note> : null}
          {read.mismatches.length ? (
            <Note kind="info" title={`In ${read.mismatches.length} cell${read.mismatches.length === 1 ? "" : "s"} the 1st and 2nd semester do not make the TOTAL`}>
              The TOTAL was used, shared between the semesters as the sheet shares them.
              <div className="mt-1">
                {read.mismatches.map((m, i) => (
                  <div key={i} className="sub2">{m.label} {m.band} ({m.indigene === "INDIGENE" ? "indigene" : "non-indigene"}): {naira(m.first)} + {naira(m.second)} on the sheet, TOTAL {naira(m.total)} → {naira(m.used[0])} and {naira(m.used[1])}</div>
                ))}
              </div>
            </Note>
          ) : null}
        </>
      ) : null}

      {action === "STRUCTURE" ? (
        <div className="stack" style={{ gap: 4 }}>
          <label className="row row--inline row--tight"><input type="radio" name="fu-scope" checked={scope === "LISTED"} onChange={() => setScope("LISTED")} /> Replace only the faculties and programmes in this file; every other line stays as it is</label>
          <label className="row row--inline row--tight"><input type="radio" name="fu-scope" checked={scope === "SESSION"} onChange={() => setScope("SESSION")} /> Replace the whole {cce ? "CCE" : "full-time"} structure for {session}: a faculty not in the file is left with no fee</label>
        </div>
      ) : null}

      {problem ? <ProblemNotice problem={problem} /> : null}
      {!rows.length ? <Note kind="info" title="Nothing to upload">Every block is left out.</Note>
        : !effect ? <div className="sub2">{busy === "preview" ? "Working out what the upload would change…" : ""}</div> : (
        <>
          <Tiles items={[
            ["Lines in force", `${count(effect.linesBefore)} → ${count(effect.linesAfter)}`, null, session],
            ["New", count(effect.totals.new), effect.totals.new ? "var(--green-ink)" : null, "Lines the session has not held"],
            ["Amount changed", count(effect.totals.changed), effect.totals.changed ? "var(--amber-ink, #8a5a00)" : null, `${count(effect.totals.same)} the same`],
            ["Ended", count(effect.totals.ended), effect.totals.ended ? "var(--red-ink)" : null, "Lines no longer charged"],
          ]} />
          {losing.length ? (
            <Note kind="bad" title={`${losing.length} faculty or programme${losing.length === 1 ? " would be" : "s would be"} left with no fee for ${session}`}>
              {losing.map((g) => (g.programme ? `${g.programme} (${named(g.faculty)})` : named(g.faculty))).join(", ")}.
              {wholeNeedsWord ? (
                <label className="row row--inline row--tight mt-1"><input type="checkbox" className="pchk" checked={confirmWhole} onChange={(e) => setConfirmWhole(e.target.checked)} /> I mean to end every line of {losing.length === 1 ? "it" : "them"}</label>
              ) : null}
            </Note>
          ) : null}
          {nothing ? <Note kind="info" title="The file changes nothing">Every line in it is already in force with the same amount.</Note> : null}
          <DTable title="By faculty and programme" pageSize={10} cols={["Faculty", "Programme", "New|num", "Changed|num", "Same|num", "Ended|num"]}
            rows={effect.groups.map((g) => [
              <span key="f">{named(g.faculty)}</span>,
              <span key="p">{g.programme ?? <span className="sub2">Every programme</span>}{g.losesAll ? <> <Pil kind="bad">No fee left</Pil></> : null}</span>,
              <span key="n" className="tnum">{count(g.new)}</span>,
              <span key="c" className="tnum">{count(g.changed)}</span>,
              <span key="s" className="tnum">{count(g.same)}</span>,
              <span key="e" className="tnum">{count(g.ended)}</span>,
            ])} />
          {effect.changes.length ? (
            <DTable title="Amounts that change" pageSize={10} cols={["Faculty / programme", "Level", "Entry mode", "Semester", "Indigene", "Now|num", "After|num"]}
              rows={effect.changes.map((c) => [
                <span key="f">{c.programme ?? named(c.faculty)}</span>,
                <span key="l" className="tnum">{levelText(c.level, c.spillover)}</span>,
                <span key="m">{MODE[c.entryMode ?? ""] ?? c.entryMode ?? "Every entry mode"}</span>,
                <span key="s">{semText(c.semester)}</span>,
                <span key="i">{c.indigene === "INDIGENE" ? "Indigene" : c.indigene === "NON_INDIGENE" ? "Non-indigene" : "Both"}</span>,
                <span key="o" className="tnum">{naira(c.old)}</span>,
                <b key="n" className="tnum">{naira(c.new)}</b>,
              ])} />
          ) : null}
          <Note kind={effect.gaps.after.students > effect.gaps.before.students ? "bad" : effect.gaps.after.students ? "info" : "ok"}
            title={effect.gaps.after.students ? `${count(effect.gaps.after.students)} undergraduate${effect.gaps.after.students === 1 ? "" : "s"} would still have no school fee stated`
              : "Every live undergraduate would have a school fee stated"}>
            Now {count(effect.gaps.before.students)} in {count(effect.gaps.before.groups)} group{effect.gaps.before.groups === 1 ? "" : "s"}; after the upload {count(effect.gaps.after.students)} in {count(effect.gaps.after.groups)}.
          </Note>
          {effect.gaps.rows.length ? (
            <DTable title="Still with no fee stated after the upload" pageSize={10} cols={["Faculty", "Programme", "Level", "Entry mode", "Students|num"]}
              rows={effect.gaps.rows.map((g) => [
                <span key="f">{named(g.faculty)}</span>,
                <span key="p">{g.programme}</span>,
                <span key="l" className="tnum">{levelText(g.level, g.spillover)}</span>,
                <span key="m">{MODE[g.entryMode ?? ""] ?? g.entryMode ?? "—"}</span>,
                <b key="n" className="tnum">{count(g.students)}</b>,
              ])} />
          ) : null}
        </>
      )}
    </Modal>
  );
}
