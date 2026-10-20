"use client";

/**
 * The programme swap desk (V578). Desk: what the detector found — the records whose placement looks wrong, why, the officer's
 * reading of each — with a swap opened for one student or prepared for many at once. Swaps: every swap prepared, awaiting a
 * decision or decided, the report (Excel, PDF), and the decision itself — approve or reject by another officer, cancel by the one
 * who prepared it. Nothing is changed from a finding: a swap is prepared, checked and decided, and the server holds every rule.
 */
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal, day } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { StudentOpen } from "@/components/StudentModal";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import {
  CLASS_WORDS, KIND_WORDS, MISMATCH_HEADERS, REPORT_HEADERS, REVIEW_CHOICES, REVIEW_WORDS, STATUS_WORDS, changeWords, mismatchRows, reportRows,
  signalWords, swapsHref, type Classification, type Faculty, type Mismatch, type ReviewStatus, type Swap, type SwapKind, type SwapStatus,
} from "@/lib/programme-swap";
import { swapPost } from "./swap-call";
import { SwapDetail } from "./SwapDetail";
import { TargetPicker, type Target } from "./TargetPicker";

export interface Summary {
  requiring: number; confirmed: number; possible: number; requiresReview: number; swapRequired: number; noAction: number;
  pending: number; completed: number; rejected: number; failed: number; recent: number; asOf: string; refreshing: boolean; prepares: boolean; decides: boolean;
}

const n = (v: unknown) => Number(v ?? 0).toLocaleString("en-GB");
const classPill = (c: Classification): "bad" | "warn" | "info" | "grey" => (c === "CONFIRMED" ? "bad" : c === "REQUIRES_REVIEW" ? "warn" : c === "POSSIBLE" ? "info" : "grey");
const statusPill = (s: SwapStatus): "ok" | "bad" | "warn" | "grey" => (s === "COMPLETED" ? "ok" : s === "PENDING_APPROVAL" ? "warn" : s === "REJECTED" || s === "FAILED" ? "bad" : "grey");

export function ProgrammeSwap({ tab, summary, faculties, filters, mismatches, swaps, problem, actingOffice, generatedBy }: {
  tab: "desk" | "swaps"; summary: Summary; faculties: Faculty[]; filters: Record<string, string>;
  mismatches: { rows: Mismatch[]; total: number; page: number; size: number; asOf: string } | null; swaps: Swap[] | null; problem: Problem | null;
  actingOffice: string | null; generatedBy: string | null;
}) {
  const go = useQueryNav();
  const nav = (changes: Record<string, string>) => go(swapsHref(tab, { ...filters, page: "", ...changes }));
  const [open, setOpen] = useState<string | null>(null);
  const [review, setReview] = useState<Mismatch | null>(null);
  const [chosen, setChosen] = useState<Set<string>>(new Set());
  const [bulk, setBulk] = useState(false);
  const [batch, setBatch] = useState<string | null>(null);
  // the tiles link within the scope chosen, never with a list's own filters
  const scope = { fac: filters.fac ?? "", dept: filters.dept ?? "" };
  const departments = faculties.flatMap((f) => f.departments.map((d) => ({ value: d.code, label: `${d.name} — ${f.name}`, faculty: f.code })));
  const programmes = faculties.flatMap((f) => f.departments.flatMap((d) => d.programmes.map((p) => ({ value: p.code, label: `${p.name} — ${d.name}`, dept: d.code, faculty: f.code }))));

  return (
    <>
      <Tiles items={[
        ["Students requiring swap", n(summary.requiring), summary.requiring ? "var(--amber-ink)" : null, `${n(summary.confirmed)} confirmed · ${n(summary.possible)} possible`, swapsHref("desk", scope)],
        ["Requires review", n(summary.requiresReview), summary.requiresReview ? "var(--amber-ink)" : null, "Signals disagree, or documentation asked for", swapsHref("desk", { ...scope, class: "REQUIRES_REVIEW" })],
        ["Pending approval", n(summary.pending), summary.pending ? "var(--amber-ink)" : null, `${n(summary.swapRequired)} findings with a swap on its way`, swapsHref("swaps", { ...scope, status: "PENDING_APPROVAL" })],
        ["Completed", n(summary.completed), "var(--green-ink)", `${n(summary.recent)} in the last 7 days · ${n(summary.rejected)} rejected · ${n(summary.failed)} failed or cancelled`, swapsHref("swaps", { ...scope, status: "COMPLETED" })],
      ]} />
      <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "center" }}>
        <Tabs look="line" label="Programme swap" value={tab} onChange={(t) => go(swapsHref(t, {}))} items={[{ id: "desk", label: "Mismatches", count: n(summary.requiring) }, { id: "swaps", label: "Swaps", count: n(summary.pending) }]} />
        <span className="grow" />
        <span className="sub2">Detector run {new Date(summary.asOf).toLocaleString("en-GB")}</span>
        <Btn kind="ghost" onClick={() => go(swapsHref(tab, { ...filters, refresh: "1" }))}>Run the detector again</Btn>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {tab === "desk" ? (
        <Panel title="Records whose placement looks wrong" right={mismatches ? `${n(mismatches.total)} found` : ""}>
          <PBody>
            <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
              <Field id="ps-q" label="Search" style={{ flex: "2 1 220px" }}>
                <input id="ps-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Name, matriculation or JAMB number"
                  onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
              </Field>
              <Field id="ps-fac" label="Faculty" style={{ flex: "1 1 180px" }}>
                <SearchSelect id="ps-fac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "", prog: "" })} allLabel="Any faculty" options={faculties.map((f) => ({ value: f.code, label: f.name }))} />
              </Field>
              <Field id="ps-dept" label="Department" style={{ flex: "1 1 200px" }}>
                <SearchSelect id="ps-dept" value={filters.dept ?? ""} onChange={(v) => nav({ dept: v, prog: "" })} allLabel="Any department"
                  options={departments.filter((d) => !filters.fac || d.faculty === filters.fac).map((d) => ({ value: d.value, label: d.label }))} />
              </Field>
              <Field id="ps-prog" label="Programme" style={{ flex: "1 1 220px" }}>
                <SearchSelect id="ps-prog" value={filters.prog ?? ""} onChange={(v) => nav({ prog: v })} allLabel="Any programme"
                  options={programmes.filter((p) => (!filters.fac || p.faculty === filters.fac) && (!filters.dept || p.dept === filters.dept)).map((p) => ({ value: p.value, label: p.label }))} />
              </Field>
              <Field id="ps-class" label="Mismatch" style={{ flex: "0 1 170px" }}>
                <select id="ps-class" className="ctl" value={filters.class ?? ""} onChange={(e) => nav({ class: e.target.value })}>
                  <option value="">Any</option>
                  {(["CONFIRMED", "REQUIRES_REVIEW", "POSSIBLE"] as Classification[]).map((c) => <option key={c} value={c}>{CLASS_WORDS[c]}</option>)}
                </select>
              </Field>
              <Field id="ps-review" label="Review" style={{ flex: "0 1 190px" }}>
                <select id="ps-review" className="ctl" value={filters.review ?? ""} onChange={(e) => nav({ review: e.target.value })}>
                  <option value="">Any</option>
                  {(Object.keys(REVIEW_WORDS) as ReviewStatus[]).map((c) => <option key={c} value={c}>{REVIEW_WORDS[c]}</option>)}
                </select>
              </Field>
              <Field id="ps-level" label="Level" style={{ flex: "0 1 110px" }}>
                <select id="ps-level" className="ctl" value={filters.level ?? ""} onChange={(e) => nav({ level: e.target.value })}>
                  <option value="">Any</option>
                  {[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l}</option>)}
                </select>
              </Field>
              <Field id="ps-status" label="Status on record" style={{ flex: "0 1 150px" }}>
                <select id="ps-status" className="ctl" value={filters.status ?? ""} onChange={(e) => nav({ status: e.target.value })}>
                  <option value="">Any</option>
                  {["ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "DORMANT"].map((x) => <option key={x} value={x}>{x.charAt(0) + x.slice(1).toLowerCase()}</option>)}
                </select>
              </Field>
              {Object.keys(filters).length ? <Btn kind="ghost" onClick={() => go(swapsHref("desk", {}))}>Clear</Btn> : null}
            </div>
          </PBody>
          {mismatches && mismatches.rows.length ? (
            <>
              <PBody>
                <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)" }}>
                  {summary.prepares ? <Btn kind="primary" size="sm" disabled={!chosen.size} onClick={() => setBulk(true)}>Swap selected ({chosen.size})</Btn> : null}
                  <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx("Programme mismatches", MISMATCH_HEADERS, mismatchRows(mismatches.rows),
                    { sheetName: "Mismatches", serial: docSerial("PSM"), sub: "Records whose placement looks wrong" }), "programme-mismatches.xlsx")}>Excel</Btn>
                  <span className="sub2">Page {mismatches.page + 1} of {Math.max(1, Math.ceil(mismatches.total / mismatches.size))}</span>
                  <Btn kind="ghost" size="sm" disabled={mismatches.page === 0} onClick={() => go(swapsHref("desk", { ...filters, page: String(mismatches.page - 1) }))}>Previous</Btn>
                  <Btn kind="ghost" size="sm" disabled={(mismatches.page + 1) * mismatches.size >= mismatches.total} onClick={() => go(swapsHref("desk", { ...filters, page: String(mismatches.page + 1) }))}>Next</Btn>
                </div>
              </PBody>
              <DTable pageSize={0} cols={[...(summary.prepares ? ["|mid"] : []), "Student", "Programme now", "Level|mid", "Mismatch", "Why", "Suggested", "Review", "Action"]}
                rows={mismatches.rows.map((m) => [
                  ...(summary.prepares ? [<input key="c" type="checkbox" className="pchk" aria-label={`Select ${m.surname}`} checked={chosen.has(m.student_id)}
                    onChange={(e) => setChosen((s) => { const t = new Set(s); if (e.target.checked) t.add(m.student_id); else t.delete(m.student_id); return t; })} />] : []),
                  <span key="s"><b>{m.surname}, {m.other_names}</b><div className="sub2 tnum">{m.matric_no ?? m.jamb_reg_no ?? "—"} · {m.status.charAt(0) + m.status.slice(1).toLowerCase()}</div></span>,
                  <span key="p">{m.programme}<div className="sub2">{m.department ?? m.dept_code} · {m.faculty ?? m.faculty_code}</div></span>,
                  <span key="l" className="tnum">{m.current_level ?? "—"}</span>,
                  <Pil key="k" kind={classPill(m.classification)}>{CLASS_WORDS[m.classification]}</Pil>,
                  <span key="w" className="sub2">{signalWords(m).map((w, i) => <div key={i}>{w}</div>)}</span>,
                  <span key="g">{m.suggested_programme_name ?? m.suggested_programme ?? (m.suggested_dept ? `Department ${m.suggested_dept}` : "—")}</span>,
                  <span key="r"><Pil kind={m.review_status === "SWAPPED" ? "ok" : m.review_status === "NOT_REVIEWED" ? "grey" : "info"}>{REVIEW_WORDS[m.review_status]}</Pil>{m.review_note ? <div className="sub2">{m.review_note}</div> : null}</span>,
                  <span key="a" className="row row--inline row--tight row--right">
                    {summary.prepares ? <Btn kind="ghost" size="sm" onClick={() => setReview(m)}>Review</Btn> : null}
                    {summary.prepares && m.review_status !== "SWAPPED" ? <LinkBtn kind="primary" size="sm" href={`/programme-swap/${m.student_id}`}>Initiate swap</LinkBtn> : null}
                    <StudentOpen id={m.student_id} label="Record" kind="ghost" />
                  </span>,
                ])} />
            </>
          ) : <PBody><div className="sub2">{mismatches ? "No record matches the filters. The detector reads the whole register: a matriculation number in another department's series, a registration mostly of another department's courses, or an admission to another programme." : "The list could not be read."}</div></PBody>}
          <PBody>
            <Note kind="info" title="How a record is flagged">
              Two signals agreeing on another department make a <b>confirmed</b> mismatch; one makes a <b>possible</b> one; two that disagree <b>require review</b>.
              Nothing is changed by a finding: an officer records what they made of it, and a swap — prepared here, decided by another officer — is what moves the record.
            </Note>
          </PBody>
        </Panel>
      ) : (
        <SwapsTab swaps={swaps ?? []} filters={filters} faculties={faculties} nav={nav} summary={summary} generatedBy={generatedBy} onOpen={setOpen} onBatch={setBatch} />
      )}

      {review ? <ReviewModal m={review} onClose={() => setReview(null)} onDone={() => { setReview(null); go(swapsHref("desk", { ...filters })); }} /> : null}
      {bulk ? <BulkModal students={mismatches?.rows.filter((m) => chosen.has(m.student_id)) ?? []} faculties={faculties} onClose={() => setBulk(false)}
        onDone={() => { setBulk(false); setChosen(new Set()); go(swapsHref("swaps", { ...scope, status: "PENDING_APPROVAL" })); }} /> : null}
      {open ? <SwapDetail id={open} actingOffice={actingOffice} onClose={() => setOpen(null)} onChanged={() => go(swapsHref("swaps", { ...filters }))} /> : null}
      {batch ? <BatchModal batch={batch} swaps={(swaps ?? []).filter((s) => s.batch_id === batch && s.status === "PENDING_APPROVAL")} onClose={() => setBatch(null)}
        onDone={() => { setBatch(null); go(swapsHref("swaps", { ...filters })); }} /> : null}
    </>
  );
}

/* ── the swaps and the report ── */

function SwapsTab({ swaps, filters, faculties, nav, summary, generatedBy, onOpen, onBatch }: {
  swaps: Swap[]; filters: Record<string, string>; faculties: Faculty[]; nav: (c: Record<string, string>) => void; summary: Summary; generatedBy: string | null;
  onOpen: (id: string) => void; onBatch: (b: string) => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const programmes = faculties.flatMap((f) => f.departments.flatMap((d) => d.programmes.map((p) => ({ value: p.code, label: `${p.name} — ${d.name}` }))));
  const title = "Programme swap report";
  const scope = [filters.status ? STATUS_WORDS[filters.status as SwapStatus] : "", filters.session, filters.kind ? KIND_WORDS[filters.kind as SwapKind] : ""].filter(Boolean).join(" · ") || "Every swap";
  const meta: [string, string][] = [["Filters", scope], ["Swaps", String(swaps.length)]];
  return (
    <Panel title="Programme swaps" right={`${swaps.length.toLocaleString("en-GB")} listed`}>
      <PBody>
        <div className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
          <Field id="sw-q" label="Search" style={{ flex: "2 1 200px" }}>
            <input id="sw-q" className="ctl" type="search" defaultValue={filters.q ?? ""} placeholder="Reference, name, matriculation or JAMB number"
              onKeyDown={(e) => { if (e.key === "Enter") nav({ q: (e.target as HTMLInputElement).value }); }} />
          </Field>
          <Field id="sw-status" label="Status" style={{ flex: "0 1 160px" }}>
            <select id="sw-status" className="ctl" value={filters.status ?? ""} onChange={(e) => nav({ status: e.target.value })}>
              <option value="">Any</option>
              {(Object.keys(STATUS_WORDS) as SwapStatus[]).map((s) => <option key={s} value={s}>{STATUS_WORDS[s]}</option>)}
            </select>
          </Field>
          <Field id="sw-session" label="Effective session" style={{ flex: "0 1 140px" }}>
            <input id="sw-session" className="ctl" defaultValue={filters.session ?? ""} placeholder="2026/2027" onKeyDown={(e) => { if (e.key === "Enter") nav({ session: (e.target as HTMLInputElement).value }); }} />
          </Field>
          <Field id="sw-fac" label="Faculty (old or new)" style={{ flex: "1 1 170px" }}>
            <SearchSelect id="sw-fac" value={filters.fac ?? ""} onChange={(v) => nav({ fac: v, dept: "" })} allLabel="Any" options={faculties.map((f) => ({ value: f.code, label: f.name }))} />
          </Field>
          <Field id="sw-dept" label="Department (old or new)" style={{ flex: "1 1 190px" }}>
            <SearchSelect id="sw-dept" value={filters.dept ?? ""} onChange={(v) => nav({ dept: v })} allLabel="Any"
              options={faculties.filter((f) => !filters.fac || f.code === filters.fac).flatMap((f) => f.departments.map((d) => ({ value: d.code, label: d.name })))} />
          </Field>
          <Field id="sw-from" label="Old programme" style={{ flex: "1 1 200px" }}>
            <SearchSelect id="sw-from" value={filters.from ?? ""} onChange={(v) => nav({ from: v })} allLabel="Any" options={programmes} />
          </Field>
          <Field id="sw-to" label="New programme" style={{ flex: "1 1 200px" }}>
            <SearchSelect id="sw-to" value={filters.to ?? ""} onChange={(v) => nav({ to: v })} allLabel="Any" options={programmes} />
          </Field>
          <Field id="sw-level" label="Level" style={{ flex: "0 1 100px" }}>
            <select id="sw-level" className="ctl" value={filters.level ?? ""} onChange={(e) => nav({ level: e.target.value })}>
              <option value="">Any</option>
              {[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l}</option>)}
            </select>
          </Field>
          <Field id="sw-kind" label="Change type" style={{ flex: "0 1 200px" }}>
            <select id="sw-kind" className="ctl" value={filters.kind ?? ""} onChange={(e) => nav({ kind: e.target.value })}>
              <option value="">Any</option>
              {(Object.keys(KIND_WORDS) as SwapKind[]).map((k) => <option key={k} value={k}>{KIND_WORDS[k]}</option>)}
            </select>
          </Field>
          <Field id="sw-fd" label="From" style={{ flex: "0 1 150px" }}><input id="sw-fd" type="date" className="ctl" value={filters.fromDate ?? ""} onChange={(e) => nav({ fromDate: e.target.value })} /></Field>
          <Field id="sw-td" label="To" style={{ flex: "0 1 150px" }}><input id="sw-td" type="date" className="ctl" value={filters.toDate ?? ""} onChange={(e) => nav({ toDate: e.target.value })} /></Field>
          {Object.keys(filters).length ? <Btn kind="ghost" onClick={() => nav(Object.fromEntries(Object.keys(filters).map((k) => [k, ""])))}>Clear</Btn> : null}
          <span className="grow" />
          <Btn kind="primary" busy={busy === "excel"} busyLabel="Preparing…" disabled={!swaps.length} onClick={async () => {
            setBusy("excel");
            try { downloadBlob(await brandedXlsx(title, REPORT_HEADERS, reportRows(swaps), { sheetName: "Programme swaps", serial: docSerial("PSW"), sub: scope, meta }), "programme-swap-report.xlsx"); }
            finally { setBusy(null); }
          }}>Download Excel</Btn>
          <Btn kind="ghost" disabled={!swaps.length} onClick={() => brandedPrint(title, scope, REPORT_HEADERS, reportRows(swaps), docSerial("PSW"), { meta, generatedBy, orientation: "landscape" })}>Download PDF</Btn>
        </div>
      </PBody>
      {swaps.length ? (
        <DTable cols={["Reference", "Student", "From", "To", "Change", "Session", "Status", "Prepared", "Decided", "Action"]}
          texts={swaps.map((s) => `${s.swap_ref} ${s.student} ${s.matric_no ?? ""} ${s.from_programme_name ?? ""} ${s.to_programme_name ?? ""} ${s.status}`)}
          rows={swaps.map((s) => [
            <span key="r" className="tnum">{s.swap_ref}{s.batch_id ? <div className="sub2">Batch</div> : null}</span>,
            <span key="s"><b>{s.student}</b><div className="sub2 tnum">{s.matric_no ?? s.jamb_reg_no ?? "—"}</div></span>,
            <span key="f">{s.from_programme_name ?? s.from_programme}<div className="sub2">{s.from_department ?? s.from_dept} · {s.from_level ?? "—"} Level</div></span>,
            <span key="t">{s.to_programme_name ?? s.to_programme}<div className="sub2">{s.to_department ?? s.to_dept} · {s.to_level} Level</div></span>,
            <span key="c">{KIND_WORDS[s.kind]}<div className="sub2">{changeWords(s)}</div></span>,
            <span key="e" className="tnum">{s.effective_session}</span>,
            <span key="st"><Pil kind={statusPill(s.status)}>{STATUS_WORDS[s.status]}</Pil>{s.review.length ? <div className="sub2">{s.review.length} point{s.review.length === 1 ? "" : "s"} to review</div> : null}</span>,
            <span key="p" className="sub2">{s.prepared_by}<div className="tnum">{day(s.prepared_at)}</div></span>,
            <span key="d" className="sub2">{s.decided_by ?? "—"}{s.decided_at ? <div className="tnum">{day(s.decided_at)}</div> : null}</span>,
            <span key="a" className="row row--inline row--tight row--right">
              <Btn kind={s.status === "PENDING_APPROVAL" && summary.decides ? "primary" : "ghost"} size="sm" onClick={() => onOpen(s.id)}>{s.status === "PENDING_APPROVAL" && summary.decides ? "Decide" : "View"}</Btn>
              {s.batch_id && s.status === "PENDING_APPROVAL" && summary.decides ? <Btn kind="ghost" size="sm" onClick={() => onBatch(s.batch_id as string)}>Batch</Btn> : null}
            </span>,
          ])} />
      ) : <PBody><div className="sub2">No swap matches the filters.</div></PBody>}
    </Panel>
  );
}

/* ── the officer's reading of a finding ── */

function ReviewModal({ m, onClose, onDone }: { m: Mismatch; onClose: () => void; onDone: () => void }) {
  const [status, setStatus] = useState<ReviewStatus>(m.review_status === "SWAPPED" || m.review_status === "SWAP_REQUIRED" ? "UNDER_REVIEW" : m.review_status);
  const [note, setNote] = useState(m.review_note ?? "");
  const [busy, setBusy] = useState(false);
  return (
    <Modal title="What was made of this record" sub={`${m.surname}, ${m.other_names} · ${m.matric_no ?? m.jamb_reg_no ?? ""}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><Btn kind="primary" busy={busy} busyLabel="Saving…" onClick={async () => {
        setBusy(true);
        try {
          const r = await swapPost(`/mismatches/${m.student_id}/review`, { status, note }, `Programme mismatch review: ${status}`);
          if (!r.ok) { notifyProblem(r.problem); return; }
          notify("Review recorded");
          onDone();
        } finally { setBusy(false); }
      }}>Record</Btn></>}>
      <KvGrid cls="grid--2" pairs={[["Programme now", `${m.programme} (${m.department ?? m.dept_code})`], ["Mismatch", CLASS_WORDS[m.classification]], ["Why", signalWords(m).join("; ") || "—"],
        ["Suggested", m.suggested_programme_name ?? m.suggested_dept ?? "—"]]} />
      <Field id="rv-status" label="Review" full>
        <select id="rv-status" className="ctl" value={status} onChange={(e) => setStatus(e.target.value as ReviewStatus)}>
          {REVIEW_CHOICES.map((c) => <option key={c} value={c}>{REVIEW_WORDS[c]}</option>)}
        </select>
      </Field>
      <Field id="rv-note" label="Note" hint="What was checked, what is awaited" full>
        <textarea id="rv-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
      </Field>
    </Modal>
  );
}

/* ── many at once ── */

function BulkModal({ students, faculties, onClose, onDone }: { students: Mismatch[]; faculties: Faculty[]; onClose: () => void; onDone: () => void }) {
  const [target, setTarget] = useState<Target>({ faculty: "", dept: "", programme: "", level: "" });
  const [session, setSession] = useState("");
  const [kind, setKind] = useState<SwapKind>("LEGACY_MIGRATION_CORRECTION");
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ batchId: string; prepared: Record<string, unknown>[]; skipped: { student: string; matric_no: string; why: string }[] } | null>(null);
  const ready = target.programme && target.level && reason.trim().length >= 10;
  return (
    <Modal wide title={`Swap ${students.length} selected student${students.length === 1 ? "" : "s"}`} sub="One programme and level for all; each is checked on its own" onClose={onClose}
      foot={result ? <Btn kind="primary" onClick={onDone}>Go to the pending swaps</Btn> : <>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind="primary" disabled={!ready} busy={busy} busyLabel="Preparing the swaps…" onClick={async () => {
          setBusy(true);
          try {
            const r = await swapPost<{ batchId: string; prepared: Record<string, unknown>[]; skipped: { student: string; matric_no: string; why: string }[] }>("/bulk",
              { studentIds: students.map((s) => s.student_id), toProgramme: target.programme, toLevel: Number(target.level), session: session || null, kind, reason },
              `Bulk programme swap to ${target.programme}`);
            if (!r.ok) { notifyProblem(r.problem); return; }
            setResult(r.data);
            notify(`${r.data.prepared.length} swap${r.data.prepared.length === 1 ? "" : "s"} prepared for approval${r.data.skipped.length ? `, ${r.data.skipped.length} skipped` : ""}`);
          } finally { setBusy(false); }
        }}>Prepare the swaps</Btn></>}>
      {result ? (
        <>
          <Note kind={result.skipped.length ? "info" : "ok"} title={`${result.prepared.length} prepared, ${result.skipped.length} skipped`}>Batch {result.batchId.slice(0, 8)}: another officer approves the batch, or each swap, on the Swaps tab.</Note>
          {result.skipped.length ? <DTable pageSize={0} cols={["Student", "Number", "Why skipped"]} rows={result.skipped.map((s) => [s.student, <span key="m" className="tnum">{s.matric_no}</span>, s.why])} /> : null}
        </>
      ) : (
        <>
          <div className="tablewrap" tabIndex={0}><table className="tbl--data"><tbody>
            {students.map((s) => <tr key={s.student_id}><td>{s.surname}, {s.other_names}</td><td className="tnum">{s.matric_no ?? s.jamb_reg_no}</td><td className="sub2">{s.programme} · {s.current_level ?? "—"}</td></tr>)}
          </tbody></table></div>
          <TargetPicker faculties={faculties} value={target} onChange={setTarget} />
          <div className="grid grid--2">
            <Field id="bk-session" label="Effective session" hint="Blank: the current session"><input id="bk-session" className="ctl" value={session} onChange={(e) => setSession(e.target.value)} placeholder="2026/2027" /></Field>
            <Field id="bk-kind" label="Change type">
              <select id="bk-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value as SwapKind)}>
                {(Object.keys(KIND_WORDS) as SwapKind[]).map((k) => <option key={k} value={k}>{KIND_WORDS[k]}</option>)}
              </select>
            </Field>
          </div>
          <Field id="bk-reason" label="Reason" hint="Kept on every swap of the batch; ten characters at least" full>
            <textarea id="bk-reason" className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Programme mapped to the old code during the legacy migration" />
          </Field>
        </>
      )}
    </Modal>
  );
}

/* ── a batch decided at once ── */

function BatchModal({ batch, swaps, onClose, onDone }: { batch: string; swaps: Swap[]; onClose: () => void; onDone: () => void }) {
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState<"approve" | "reject" | null>(null);
  const [result, setResult] = useState<{ decided: { swapRef: string; status: string }[]; skipped: { student: string; why: string }[] } | null>(null);
  async function decide(approve: boolean) {
    setBusy(approve ? "approve" : "reject");
    try {
      const r = await swapPost<{ decided: { swapRef: string; status: string }[]; skipped: { student: string; why: string }[] }>(`/batches/${batch}/decide`, { approve, note },
        `Programme swap batch ${approve ? "approved" : "rejected"}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      setResult(r.data);
      notify(`${r.data.decided.length} decided${r.data.skipped.length ? `, ${r.data.skipped.length} skipped` : ""}`);
    } finally { setBusy(null); }
  }
  return (
    <Modal wide title={`Decide the batch: ${swaps.length} swap${swaps.length === 1 ? "" : "s"} pending`} sub={`Batch ${batch.slice(0, 8)}`} onClose={onClose}
      foot={result ? <Btn kind="primary" onClick={onDone}>Close</Btn> : <>
        <Btn kind="ghost" onClick={onClose}>Cancel</Btn>
        <Btn kind="ghost" busy={busy === "reject"} busyLabel="Rejecting…" disabled={!!busy || note.trim().length < 10} onClick={() => decide(false)}>Reject all</Btn>
        <Btn kind="primary" busy={busy === "approve"} busyLabel="Processing the swaps…" disabled={!!busy} onClick={() => decide(true)}>Approve and execute all</Btn></>}>
      {result ? (
        <>
          <Note kind="ok" title={`${result.decided.length} decided`}>{result.decided.map((d) => `${d.swapRef} ${d.status.toLowerCase()}`).join(", ") || "None"}</Note>
          {result.skipped.length ? <DTable pageSize={0} cols={["Student", "Why"]} rows={result.skipped.map((s) => [s.student, s.why])} /> : null}
        </>
      ) : (
        <>
          <Note kind="info" title="Each swap is checked again on the record as it stands">A record that changed since its swap was prepared fails that swap alone; the rest go through. The officer who prepared the batch cannot decide it.</Note>
          <DTable pageSize={0} cols={["Reference", "Student", "From", "To"]} rows={swaps.map((s) => [<span key="r" className="tnum">{s.swap_ref}</span>, s.student, `${s.from_programme_name ?? s.from_programme} · ${s.from_level ?? "—"}`, `${s.to_programme_name ?? s.to_programme} · ${s.to_level}`])} />
          <Field id="bt-note" label="Note" hint="Required to reject; kept on each swap" full><textarea id="bt-note" className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </>
      )}
    </Modal>
  );
}
