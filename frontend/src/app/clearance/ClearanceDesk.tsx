"use client";

/** The clearance desk (V415): an office's stage of fresh or final clearance, or — for the Registry — every office. The
 *  list, its counts and its search are the server's (paged); each office decides only its own stage, only in its turn, and
 *  the server refuses a clearance the record does not support. Nothing here hides what the server would allow or allows
 *  what it would refuse: a button follows the answer. */
import { useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { useQueryNav } from "@/lib/query-nav";
import type { Scope } from "@/lib/scope";
import {
  DECISIONS, OVERALL_WORD, STATE_WORD, stateKind, stateMark, stateWord, studentNumber,
  type Desk, type DeskRow, type ProcessDetail, type Workflows,
} from "@/lib/clearance";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Gate, Gates, Modal } from "@/components/proto/blocks";
import { ScopeBar, type Ceiling, type ScopeStructure } from "@/components/proto/ScopeBar";
import { ProblemNotice } from "@/components/ProblemNotice";

const ANY_UNIT = new Set(["registrar", "dregistrar", "academic"]);
const MANAGERS = new Set(["academic", "registrar", "dregistrar", "super", "admin", "vc", "dvc"]);
const STAGE_TILES: [string, string][] = [["PENDING", "Awaiting you"], ["UNDER_REVIEW", "Under review"], ["REQUIRES_ACTION", "Requires action"],
  ["NOT_CLEARED", "Not cleared"], ["REJECTED", "Rejected"], ["CLEARED", "Cleared"], ["WAITING", "Waiting for an earlier office"], ["NOT_APPLICABLE", "Not required"]];
const OVERALL_TILES = ["IN_PROGRESS", "PARTIALLY_CLEARED", "PENDING_ACTION", "NOT_CLEARED", "REJECTED"];
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const entryWord = (e: string | null | undefined) => (e ? e.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase()).replace(/^Utme$/, "UTME").replace(/^Cce$/, "CCE") : "—");

async function readFile(f: File): Promise<string> {
  return await new Promise((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(r.error); r.readAsDataURL(f); });
}

export function ClearanceDesk({ workflows, workflow, session, desk, detail, scope, structure, sessions, ceiling, params, actingOffice }: {
  workflows: Workflows; workflow: string; session: string; desk: Desk | null; detail: ProcessDetail | null; scope: Scope; structure: ScopeStructure;
  sessions: string[]; ceiling: Ceiling; params: { unit: string; status: string; sex: string; entry: string; q: string; page: number };
  actingOffice: string | null;
}) {
  const router = useRouter();
  const nav = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState(params.q);
  const [refusals, setRefusals] = useState<{ process: string; code: string; why: string }[]>([]);
  const office = actingOffice ?? "";
  const wf = workflows.workflows.find((w) => w.code === workflow) ?? workflows.workflows[0];
  const unitsOfWf = wf.stages.filter((s) => s.active);
  const mine = workflows.myUnits;
  const unit = desk?.unit ?? null;
  const canSignUnit = !!unit && mine.includes(unit);
  const chooseUnit = ANY_UNIT.has(office) || mine.length > 1 || mine.length === 0;

  function go(patch: Record<string, string>) {
    const p = new URLSearchParams({ wf: workflow, session, unit: params.unit, status: params.status, sex: params.sex, entry: params.entry, q: params.q,
      fac: scope.fac, dept: scope.dept, prog: scope.prog, level: scope.level, ...patch });
    for (const [k, v] of [...p.entries()]) if (!v) p.delete(k);
    if (!("page" in patch)) p.delete("page");
    nav(`/clearance?${p.toString()}`);
  }
  const open = (id: string) => go({ process: id, page: String(params.page) });
  const close = () => go({ process: "", page: String(params.page) });

  async function call<T>(path: string, method: string, body: unknown, reason: string): Promise<T | null> {
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/clearance${path}`, {
        method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j ?? { status: r.status, title: "The request was refused." }) as Problem; setProblem(p); notifyProblem(p); return null; }
      return j as T;
    } catch {
      const p = { status: 0, title: "The network dropped the request." }; setProblem(p); notifyProblem(p); return null;
    }
  }

  async function clearSelected() {
    if (!unit || !selected.size) return;
    setBusy(true);
    const r = await call<{ cleared: number; refused: { process: string; code: string; why: string }[] }>("/desk/clear", "POST",
      { processes: [...selected], unit }, `${unit} clearance given to ${selected.size} student(s)`);
    setBusy(false);
    if (r) {
      notify(`${r.cleared} cleared${r.refused.length ? `, ${r.refused.length} refused` : ""}`);
      setRefusals(r.refused);
      setSelected(new Set());
      router.refresh();
    }
  }

  async function exportAs(kind: "xlsx" | "pdf") {
    const q = new URLSearchParams({ workflow, session, export: "true", size: "20000" });
    for (const [k, v] of [["unit", params.unit || (desk?.unit ?? "")], ["status", params.status], ["fac", scope.fac], ["dept", scope.dept], ["prog", scope.prog],
      ["level", scope.level], ["sex", params.sex], ["entry", params.entry], ["q", params.q]] as [string, string][]) if (v) q.set(k, v);
    setBusy(true);
    try {
      const r = await fetch(`/api/bff/api/v1/clearance/desk?${q.toString()}`);
      if (!r.ok) { const p = await r.json().catch(() => ({ status: r.status, title: "The report could not be read." })); setProblem(p); notifyProblem(p); return; }
      const d = (await r.json()) as Desk;
      const stageLabels = unitsOfWf.map((s) => s.label);
      const headers = ["Name", "Number", "Reference", "Faculty", "Department", "Programme", "Level", "Admission type", ...stageLabels, "Overall"];
      const rows = d.rows.map((x) => [`${x.surname}, ${x.other_names}`, studentNumber(x), x.reference, x.faculty ?? "", x.department ?? "", x.programme ?? "",
        x.level ?? "", entryWord(x.entry_mode), ...unitsOfWf.map((s) => stateWord(x.stages.find((y) => y.unit === s.unit)?.state)), stateWord(x.overall)]);
      const title = `${wf.label} — ${unit ? (wf.stages.find((s) => s.unit === unit)?.label ?? unit) + " stage" : "every office"}`;
      const meta: [string, string][] = [["Session", session], ["Filter", params.status ? stateWord(params.status) : "All"], ["Students", String(d.total)]];
      if (kind === "xlsx") downloadBlob(await brandedXlsx(title, headers, rows, { sub: session, meta, serial: docSerial("CLR") }), `clearance-${workflow.toLowerCase()}-${session.replace("/", "-")}.xlsx`);
      else brandedPrint(title, `Session ${session}`, headers, rows, docSerial("CLR"), { meta });
    } finally { setBusy(false); }
  }

  const tiles = desk?.tiles ?? {};
  const tileItems: [string, string, string | null, string, string][] = unit
    ? STAGE_TILES.filter(([k]) => (tiles[k] ?? 0) > 0 || ["PENDING", "REQUIRES_ACTION", "NOT_CLEARED", "CLEARED"].includes(k)).map(([k, label]) => [label, (tiles[k] ?? 0).toLocaleString(),
        k === "CLEARED" ? "var(--green-ink)" : k === "NOT_CLEARED" || k === "REJECTED" ? "var(--red-ink)" : k === "REQUIRES_ACTION" ? "var(--amber-ink)" : null,
        params.status === k ? "Shown below" : "Show them", k])
    : [...OVERALL_TILES, wf.complete_word].map((k) => [OVERALL_WORD[k] ?? k, (tiles[k] ?? 0).toLocaleString(),
        k === wf.complete_word ? "var(--green-ink)" : k === "NOT_CLEARED" || k === "REJECTED" ? "var(--red-ink)" : k === "PENDING_ACTION" ? "var(--amber-ink)" : null,
        params.status === k ? "Shown below" : "Show them", k]);

  const rows = desk?.rows ?? [];
  const start = (desk?.page ?? 0) * (desk?.size ?? 50);
  const pages = desk ? Math.max(1, Math.ceil(desk.total / desk.size)) : 1;

  return (
    <>
      <div className="row row--tight" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
        <Tabs label="Clearance" value={workflow} onChange={(v) => go({ wf: v, unit: "", status: "" })}
          items={workflows.workflows.filter((w) => w.active).map((w) => ({ id: w.code, label: w.label }))} />
        <span className="grow" />
        {MANAGERS.has(office) ? <LinkBtn href="/clearance/manage">Clearance management</LinkBtn> : null}
        <LinkBtn href="/clearance/units">Gate clearances by unit</LinkBtn>
      </div>
      {!wf.active ? <Note kind="info" title={`${wf.label} is not in use`}>The Registry turns it on under Clearance management.</Note> : null}

      <ScopeBar scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} what="students" count={desk?.total ?? 0} of={desk?.processes ?? 0} />

      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-2)", alignItems: "flex-end", margin: "var(--s-2) 0" }}>
        {chooseUnit ? (
          <Field id="clr-unit" label="Office">
            <select id="clr-unit" className="ctl" style={{ minWidth: 200 }} value={params.unit || unit || ""} onChange={(e) => go({ unit: e.target.value, status: "" })}>
              {ANY_UNIT.has(office) || mine.length === 0 ? <option value="">Every office (overall)</option> : null}
              {unitsOfWf.filter((s) => ANY_UNIT.has(office) || mine.length === 0 || mine.includes(s.unit)).map((s) => <option key={s.unit} value={s.unit}>{s.label}</option>)}
            </select>
          </Field>
        ) : null}
        <Field id="clr-sex" label="Gender">
          <select id="clr-sex" className="ctl" value={params.sex} onChange={(e) => go({ sex: e.target.value })}>
            <option value="">All</option><option value="F">Female</option><option value="M">Male</option>
          </select>
        </Field>
        <Field id="clr-entry" label="Admission type">
          <select id="clr-entry" className="ctl" value={params.entry} onChange={(e) => go({ entry: e.target.value })}>
            <option value="">All</option>{["UTME", "DIRECT_ENTRY", "TRANSFER", "CCE", "POSTGRADUATE"].map((e) => <option key={e} value={e}>{entryWord(e)}</option>)}
          </select>
        </Field>
        <Field id="clr-q" label="Search" hint="Name, matric, JAMB or application number, or the clearance reference">
          <form className="row row--tight" style={{ flexWrap: "nowrap" }} onSubmit={(e) => { e.preventDefault(); go({ q: search.trim() }); }}>
            <input id="clr-q" className="ctl" style={{ minWidth: 240 }} value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search" autoComplete="off" />
            <Btn kind="ghost" type="submit">Search</Btn>
          </form>
        </Field>
      </div>

      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={tileItems.map(([label, value, colour, sub, k]) => [label, value, colour, sub, `/clearance?${new URLSearchParams({ wf: workflow, session, ...(params.unit || unit ? { unit: params.unit || unit || "" } : {}), status: params.status === k ? "" : k, ...(scope.fac ? { fac: scope.fac } : {}), ...(scope.dept ? { dept: scope.dept } : {}), ...(params.q ? { q: params.q } : {}) }).toString()}`])} />

      {refusals.length ? (
        <Note kind="bad" title={`${refusals.length} not cleared — the record says why`}
          action={<Btn kind="ghost" onClick={() => setRefusals([])}>Done</Btn>}>
          {refusals.slice(0, 8).map((r) => `${rows.find((x) => x.process_id === r.process)?.surname ?? r.process.slice(0, 8)}: ${r.why}`).join(" · ")}
        </Note>
      ) : null}

      <Panel title={unit ? `${wf.stages.find((s) => s.unit === unit)?.label ?? unit} stage` : "Every office"}
        right={<span className="row row--tight">
          {canSignUnit ? <Btn kind="go" disabled={busy || !selected.size} onClick={() => void clearSelected()}>Clear the selected ({selected.size})</Btn> : null}
          <Btn kind="ghost" disabled={busy || !desk?.total} onClick={() => void exportAs("xlsx")}>Export (Excel)</Btn>
          <Btn kind="ghost" disabled={busy || !desk?.total} onClick={() => void exportAs("pdf")}>PDF</Btn>
        </span>}>
        {!desk ? <PBody><div className="sub2">Choose a session.</div></PBody> : !rows.length ? (
          <PBody><div className="sub2">{desk.processes ? "No student matches these filters." : `No ${wf.label.toLowerCase()} has been started for ${session}.`}</div></PBody>
        ) : (
          <>
            <DTable pageSize={0}
              cols={[...(canSignUnit ? ["|mid"] : []), "S/N|num", "Student", "Number", "Faculty · Department", "Level|num", "Admission", unit ? "This stage|mid" : "Overall|mid", "Offices", "|num"]}
              rows={rows.map((x: DeskRow, i) => [
                ...(canSignUnit ? [<input key="x" type="checkbox" className="chk" aria-label={`Select ${x.surname}`} disabled={x.my_state === "CLEARED" || !x.my_opened}
                  checked={selected.has(x.process_id)} onChange={(e) => { const n = new Set(selected); if (e.target.checked) n.add(x.process_id); else n.delete(x.process_id); setSelected(n); }} />] : []),
                <span key="n" className="tnum sub2">{start + i + 1}</span>,
                <span key="s"><b>{x.surname}, {x.other_names}</b><span className="sub2"> · {x.reference}</span></span>,
                <span key="m" className="tnum">{studentNumber(x)}</span>,
                <span key="f" className="sub2">{x.faculty ?? "—"} · {x.department ?? "—"}<br />{x.programme ?? ""}</span>,
                <span key="l" className="tnum">{x.level ?? "—"}</span>,
                <span key="e" className="sub2">{entryWord(x.entry_mode)}</span>,
                unit ? <span key="st"><Pil kind={stateKind(x.my_state)}>{stateWord(x.my_state)}</Pil>{x.my_item ? <span className="sub2"> · {x.my_item}</span> : null}</span>
                  : <Pil key="st" kind={stateKind(x.overall)}>{stateWord(x.overall)}</Pil>,
                <span key="o" className="tnum" title={x.stages.map((s) => `${s.label}: ${stateWord(s.state)}`).join("\n")} style={{ letterSpacing: "2px" }}>
                  {x.stages.map((s) => <span key={s.unit} className={s.state === "CLEARED" ? "ink-green" : s.state === "NOT_CLEARED" || s.state === "REJECTED" ? "ink-red" : "sub2"}>{stateMark(s.state)}</span>)}
                </span>,
                <Btn key="a" kind="ghost" size="sm" onClick={() => open(x.process_id)}>Open</Btn>,
              ])} />
            <PBody>
              <div className="row row--tight">
                <span className="sub2">{start + 1}–{start + rows.length} of {desk.total.toLocaleString()}</span>
                <span className="grow" />
                <Btn kind="ghost" size="sm" disabled={params.page <= 0} onClick={() => go({ page: String(params.page - 1) })}>Previous</Btn>
                <Btn kind="ghost" size="sm" disabled={params.page + 1 >= pages} onClick={() => go({ page: String(params.page + 1) })}>Next</Btn>
              </div>
            </PBody>
          </>
        )}
      </Panel>

      {detail ? <ProcessPanel key={`${detail.process.id}:${detail.history.length}:${detail.documents.length}`} detail={detail} busy={busy} setBusy={setBusy} call={call} onClose={close} onDone={() => router.refresh()} /> : null}
    </>
  );
}

/** one student's clearance: the stages, what the record says for the office's own, the documents, the decision and every word given */
function ProcessPanel({ detail, busy, setBusy, call, onClose, onDone }: {
  detail: ProcessDetail; busy: boolean; setBusy: (b: boolean) => void;
  call: <T>(path: string, method: string, body: unknown, reason: string) => Promise<T | null>; onClose: () => void; onDone: () => void;
}) {
  const p = detail.process;
  const signable = detail.stages.filter((s) => detail.myUnits.includes(s.unit) && (s.applies || detail.canOverride));
  const [unit, setUnit] = useState(signable.find((s) => s.opened && s.state !== "CLEARED")?.unit ?? signable[0]?.unit ?? "");
  const [state, setState] = useState("CLEARED");
  const [item, setItem] = useState("");
  const [note, setNote] = useState("");
  const [internal, setInternal] = useState("");
  const [override, setOverride] = useState(false);
  const [review, setReview] = useState<{ id: string; label: string; state: string } | null>(null);
  const [reviewReason, setReviewReason] = useState("");
  const [cancelling, setCancelling] = useState(false);
  const [cancelReason, setCancelReason] = useState("");
  const stage = detail.stages.find((s) => s.unit === unit) ?? null;
  const need = DECISIONS.find((d) => d.state === state)?.needsReason ?? (override ? "The reason for the override" : null);
  const ev = unit ? detail.evidence[unit] : undefined;
  const live = !p.cancelled_at;

  async function decide() {
    if (!stage) return;
    setBusy(true);
    const r = await call<{ overall: string }>(`/processes/${p.id}/stages/${unit}`, "POST",
      { state: override && state === "NOT_APPLICABLE" ? "NOT_APPLICABLE" : state, item: item.trim() || null, note: note.trim() || null, internalNote: internal.trim() || null, override },
      `${stage.label} clearance: ${stateWord(state).toLowerCase()} for ${p.reference}`);
    setBusy(false);
    if (r) { notify(`${stage.label}: ${stateWord(state).toLowerCase()} — the student is told`); setItem(""); setNote(""); setInternal(""); setOverride(false); onDone(); }
  }

  async function reviewDoc() {
    if (!review) return;
    setBusy(true);
    const r = await call(`/documents/${review.id}/review`, "POST", { state: review.state, reason: reviewReason.trim() || null }, `Document ${review.label}: ${review.state.toLowerCase()}`);
    setBusy(false);
    if (r) { notify(`${review.label}: ${stateWord(review.state).toLowerCase()}`); setReview(null); setReviewReason(""); onDone(); }
  }

  async function upload(f: File | undefined, label: string) {
    if (!f || !unit) return;
    setBusy(true);
    const r = await call(`/processes/${p.id}/documents`, "POST", { unit, label, fileName: f.name, contentBase64: await readFile(f) }, `Document ${label} uploaded for ${p.reference}`);
    setBusy(false);
    if (r) { notify(`${label} uploaded`); onDone(); }
  }

  return (
    <Modal title={`${p.surname}, ${p.other_names}`} sub={`${p.workflow_label} · ${p.reference} · ${p.session}`} onClose={onClose} wide
      foot={<>{detail.canCancel && live ? <Btn kind="ghost" onClick={() => setCancelling(true)}>Cancel this clearance</Btn> : null}<span className="grow" /><Btn kind="ghost" onClick={onClose}>Close</Btn></>}>
      <div className="row row--tight" style={{ flexWrap: "wrap", gap: "var(--s-2)" }}>
        <Pil kind={stateKind(p.overall)}>{stateWord(p.overall)}</Pil>
        <span className="sub2">{studentNumber(p)} · {p.programme ?? "—"} · {p.department ?? "—"}, {p.faculty ?? "—"} · {p.level ?? "—"} level · {entryWord(p.entry_mode)}</span>
        {p.cancelled_at ? <Pil kind="grey">Cancelled: {p.cancel_reason}</Pil> : null}
      </div>

      <div className="grid grid--2 mt-2">
        <div>
          <div className="b600 mb-1">Offices</div>
          <Gates>
            {detail.stages.map((s, i) => (
              <Gate key={s.unit} state={s.state === "CLEARED" || s.state === "NOT_APPLICABLE" ? "done" : "todo"} last={i === detail.stages.length - 1}
                title={<span>{s.label} — <Pil kind={stateKind(s.state)}>{stateWord(s.state)}</Pil>{s.overridden ? <Pil kind="warn"> override</Pil> : null}</span>}
                sub={[s.item, s.note, s.officer ? `${s.officer} · ${when(s.decided_at)}` : null, !s.required ? "Optional" : null].filter(Boolean).join(" · ") || (s.state === "WAITING" ? "Opens when the earlier offices clear" : s.state === "NOT_APPLICABLE" ? "Does not apply to this student" : "Nothing decided yet")} />
            ))}
          </Gates>
        </div>
        <div>
          {signable.length && live ? (
            <>
              <div className="b600 mb-1">Your office&rsquo;s word</div>
              {signable.length > 1 ? (
                <Field id="clr-d-unit" label="Stage">
                  <select id="clr-d-unit" className="ctl" value={unit} onChange={(e) => setUnit(e.target.value)}>
                    {signable.map((s) => <option key={s.unit} value={s.unit}>{s.label} — {stateWord(s.state)}</option>)}
                  </select>
                </Field>
              ) : <div className="sub2 mb-1">{stage?.label} — {stateWord(stage?.state)}</div>}
              {ev ? <Evidence unit={unit} ev={ev} /> : null}
              {stage && !stage.opened && stage.applies ? <Note kind="info" title="Not yet open">This stage opens when the earlier offices have cleared the student.</Note> : null}
              <Field id="clr-d-state" label="Decision">
                <select id="clr-d-state" className="ctl" value={state} onChange={(e) => setState(e.target.value)}>
                  {DECISIONS.map((d) => <option key={d.state} value={d.state}>{d.label}</option>)}
                  {detail.canOverride ? <option value="NOT_APPLICABLE">Not required (override)</option> : null}
                </select>
              </Field>
              {need || state !== "CLEARED" ? (
                <Field id="clr-d-item" label={need ?? "Detail"} required={!!need}>
                  <textarea id="clr-d-item" className="ctl" rows={2} value={item} onChange={(e) => setItem(e.target.value)} />
                </Field>
              ) : null}
              <Field id="clr-d-note" label="Official remark" hint="The student sees it">
                <input id="clr-d-note" className="ctl" value={note} onChange={(e) => setNote(e.target.value)} />
              </Field>
              <Field id="clr-d-int" label="Internal note" hint="Never shown to the student">
                <input id="clr-d-int" className="ctl" value={internal} onChange={(e) => setInternal(e.target.value)} />
              </Field>
              {detail.canOverride ? (
                <label className="row row--tight mb-1"><input type="checkbox" className="chk" checked={override || state === "NOT_APPLICABLE"} onChange={(e) => setOverride(e.target.checked)} />
                  <span className="sub2">Override the engine&rsquo;s check (a stage not yet open, an obligation outstanding) — kept as an override with its reason</span></label>
              ) : null}
              <Btn kind={state === "CLEARED" ? "go" : "primary"} disabled={busy || !stage || (!!need && !item.trim()) || ((override || state === "NOT_APPLICABLE") && !item.trim())}
                onClick={() => void decide()}>{state === "CLEARED" ? "Clear" : DECISIONS.find((d) => d.state === state)?.label ?? "Save"}</Btn>
            </>
          ) : <Note kind="info" title="Read only">Your office gives no word on this clearance{live ? "" : " — it was cancelled"}.</Note>}
        </div>
      </div>

      <div className="b600 mt-3 mb-1">Documents</div>
      {detail.documents.length ? (
        <DTable pageSize={0} cols={["Office", "Document", "Uploaded", "State|mid", "|num"]}
          rows={detail.documents.map((d) => [
            <span key="u" className="sub2">{d.unit_label}</span>,
            <span key="l">{d.label}{d.superseded ? <span className="sub2"> (replaced)</span> : null}<br /><a className="sub2" href={`/api/bff/api/v1/clearance/documents/${d.id}/file`} target="_blank" rel="noreferrer">{d.file_name}</a></span>,
            <span key="w" className="sub2">{when(d.uploaded_at)} · {d.uploaded_office === "student" ? "by the student" : d.uploaded_office}</span>,
            <span key="s"><Pil kind={d.state === "APPROVED" ? "ok" : d.state === "REJECTED" || d.state === "REQUIRES_REUPLOAD" ? "bad" : "info"}>{d.state.replace(/_/g, " ").toLowerCase()}</Pil>{d.reason ? <span className="sub2"> · {d.reason}</span> : null}</span>,
            detail.myUnits.includes(d.unit) && !d.superseded && live ? (
              <span key="a" className="row row--tight">
                <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setReview({ id: d.id, label: d.label, state: "APPROVED" })}>Approve</Btn>
                <Btn kind="ghost" size="sm" disabled={busy} onClick={() => setReview({ id: d.id, label: d.label, state: "REJECTED" })}>Reject</Btn>
              </span>
            ) : <span key="a" />,
          ])} />
      ) : <div className="sub2">No document uploaded.</div>}
      {stage && detail.myUnits.includes(unit) && live ? (
        <div className="row row--tight mt-1" style={{ flexWrap: "wrap" }}>
          {(stage.documents.length ? stage.documents : ["Supporting document"]).map((label) => (
            <label key={label} className="btn btn--ghost btn--sm" style={{ cursor: busy ? "wait" : "pointer" }}>Upload {label}
              <input type="file" accept="application/pdf,image/jpeg,image/png" hidden onChange={(e) => void upload(e.target.files?.[0], label)} />
            </label>
          ))}
        </div>
      ) : null}

      <div className="b600 mt-3 mb-1">Every word given</div>
      {detail.history.length ? (
        <DTable pageSize={0} cols={["When", "Office", "Word|mid", "Detail", "By"]}
          rows={detail.history.map((h, i) => [
            <span key="w" className="sub2">{when(h.decided_at)}</span>, <span key="u">{h.label}</span>,
            <span key="s"><Pil kind={stateKind(h.state)}>{STATE_WORD[h.state] ?? h.state}</Pil>{h.override ? <Pil kind="warn">override</Pil> : null}</span>,
            <span key="d" className="sub2">{[h.item, h.note, h.internal_note ? `Internal: ${h.internal_note}` : null, h.previous_state ? `was ${stateWord(h.previous_state).toLowerCase()}` : null].filter(Boolean).join(" · ")}</span>,
            <span key={`b${i}`} className="sub2">{h.officer ?? "—"}{h.office ? ` (${h.office})` : ""}</span>,
          ])} />
      ) : <div className="sub2">No office has given its word yet.</div>}

      {review ? (
        <Modal title={`${review.state === "APPROVED" ? "Approve" : "Reject"} ${review.label}`} onClose={() => setReview(null)}
          foot={<><Btn kind="ghost" onClick={() => setReview(null)}>Cancel</Btn><span className="grow" />
            <Btn kind={review.state === "APPROVED" ? "go" : "urgent"} disabled={busy || (review.state !== "APPROVED" && !reviewReason.trim())} onClick={() => void reviewDoc()}>{review.state === "APPROVED" ? "Approve" : "Reject"}</Btn></>}>
          {review.state !== "APPROVED" ? (
            <Field id="clr-rv" label="Reason" required hint="The student is told, and uploads it again">
              <textarea id="clr-rv" className="ctl" rows={2} value={reviewReason} onChange={(e) => setReviewReason(e.target.value)} />
            </Field>
          ) : <div className="sub2">The document is approved for the stage.</div>}
        </Modal>
      ) : null}
      {cancelling ? (
        <Modal title="Cancel this clearance" sub={p.reference} onClose={() => setCancelling(false)}
          foot={<><Btn kind="ghost" onClick={() => setCancelling(false)}>Keep it</Btn><span className="grow" />
            <Btn kind="urgent" disabled={busy || !cancelReason.trim()} onClick={async () => { setBusy(true); const r = await call(`/processes/${p.id}/cancel`, "POST", { reason: cancelReason.trim() }, `Clearance ${p.reference} cancelled`); setBusy(false); if (r) { notify(`${p.reference} cancelled`); setCancelling(false); onDone(); } }}>Cancel the clearance</Btn></>}>
          <Field id="clr-cancel" label="Reason" required hint="Every word given is kept">
            <textarea id="clr-cancel" className="ctl" rows={2} value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} />
          </Field>
        </Modal>
      ) : null}
    </Modal>
  );
}

const naira = (n: unknown) => `₦${Number(n ?? 0).toLocaleString("en-NG", { maximumFractionDigits: 0 })}`;

/** what the record says for the office's stage, in the office's words */
function Evidence({ unit, ev }: { unit: string; ev: Record<string, unknown> }) {
  const line = (k: string, v: string, bad = false) => <div key={k} className="row row--tight"><span className="sub2" style={{ minWidth: 150 }}>{k}</span><b className={bad ? "ink-red" : undefined}>{v}</b></div>;
  const out: ReactNode[] = [];
  if (unit === "BURSARY") {
    if (Array.isArray(ev.sessions)) {
      out.push(line("Outstanding (sessions stated)", naira(ev.outstanding), Number(ev.outstanding) > 0));
      for (const s of ev.sessions as { session: string; stated: boolean; due: number; balance: number }[]) out.push(line(s.session, s.stated ? `${naira(s.due)} due · balance ${naira(s.balance)}` : "fees not stated (old portal)", s.stated && s.balance > 0));
    } else {
      out.push(line("Fees stated", ev.stated ? "Yes" : "No", !ev.stated));
      out.push(line("Due · paid", `${naira(ev.due)} · ${naira(ev.paid)}`));
      out.push(line("Outstanding", ev.outstanding == null ? "—" : naira(ev.outstanding), Number(ev.outstanding) > 0));
    }
  } else if (unit === "LIBRARY") {
    out.push(line("Items on loan", String(ev.openLoans ?? 0), Number(ev.openLoans) > 0));
    out.push(line("Fines unpaid", naira(ev.fines), Number(ev.unpaidFines) > 0));
    for (const l of (ev.loans as { accession: string; title: string | null; dueOn: string }[] | undefined) ?? []) out.push(line(l.accession, `${l.title ?? "—"} · due ${when(l.dueOn)}`, true));
  } else if (unit === "HOSTEL") {
    out.push(line("Still checked in", String(ev.checkedIn ?? 0), Number(ev.checkedIn) > 0));
    out.push(line("Checkout clearance pending", String(ev.clearancePending ?? 0), Number(ev.clearancePending) > 0));
    out.push(line("Damage charges unpaid", naira(ev.charges), Number(ev.unsettledCharges) > 0));
    for (const s of (ev.stays as { reference: string | null; session: string; state: string; feeStatus: string | null }[] | undefined) ?? []) out.push(line(s.reference ?? s.session, `${s.session} · ${s.state.toLowerCase().replace(/_/g, " ")}${s.feeStatus ? ` · fee ${s.feeStatus.toLowerCase()}` : ""}`));
  } else if (unit === "HEALTH") {
    out.push(line("Fitness", ev.fitness ? String(ev.fitness) : "Not recorded", !ev.fitness));
    if (ev.fitnessOn) out.push(line("Recorded", when(String(ev.fitnessOn))));
  } else if (unit === "DEPARTMENT") {
    const g = ev.graduand as { session: string; cgpa: number; award: string; unmet: string | null; senate: string } | null | undefined;
    if (g) { out.push(line("Graduand audit", `${g.session} · CGPA ${g.cgpa} · ${g.senate.toLowerCase()}`)); if (g.unmet) out.push(line("Unmet", g.unmet, true)); }
    else if (ev.registrations) for (const r of ev.registrations as { semester: number; status: string }[]) out.push(line(`Registration, semester ${r.semester}`, r.status.toLowerCase()));
  } else if (unit === "ALUMNI") {
    out.push(line("Details confirmed", ev.confirmed ? `Yes, ${when(String(ev.confirmedAt))}` : "No", !ev.confirmed));
    out.push(line("E-mail · phone · address", [ev.email ? "e-mail" : null, ev.phone ? "phone" : null, ev.address ? "address" : null].filter(Boolean).join(", ") || "none on record"));
  }
  const docs = ev.documents as Record<string, string> | undefined;
  if (docs && Object.keys(docs).length) out.push(line("Documents", Object.entries(docs).map(([k, v]) => `${k}: ${v.toLowerCase()}`).join(" · ")));
  return out.length ? <div className="card card--quiet mb-2" style={{ padding: "var(--s-2)" }}>{out}</div> : null;
}
