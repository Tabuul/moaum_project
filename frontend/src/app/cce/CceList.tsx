"use client";

/**
 * JAMB's CCE list at the Academic Office (V379): the template; a file read in the browser (Excel or CSV), its headings matched
 * to the list's fields and correctable; the preview the server makes, every row classified (new, unchanged, updated, a duplicate
 * in the file, requiring review, invalid) and matched by JAMB number, never by name; then the list committed whole or discarded
 * with its reason; the rows not loaded downloadable with why. The import history, and the list as committed with where each
 * listed person stands.
 */
import { useEffect, useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles, KvGrid } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { buildXlsx, csvRows, xlsxRows } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import {
  CLASS_LABEL, CLASSES, LIST_ALIASES, STATUS_LABEL, STATUSES, TEMPLATE_COLUMNS, ccall, day, labelOf, sha256Hex, when,
  type Batch, type BatchRow, type CandidateRow, type Mapping, type Paged,
} from "@/lib/cce";
import { cceSend, type Powers } from "./CceDesk";

export interface TabProps { session: string; powers: Powers; pick: ReactNode; refresh: () => void }

const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
const FIELDS = TEMPLATE_COLUMNS.map(([h, k]) => [k, h] as [string, string]).concat([["other_names", "Other Names"]]);

/** a server-paged list's pager */
export function Pager({ total, page, size, onPage }: { total: number; page: number; size: number; onPage: (p: number) => void }) {
  const pages = Math.max(1, Math.ceil(total / size));
  if (total <= size) return null;
  return (
    <div className="row row--inline row--tight" style={{ justifyContent: "flex-end", padding: "8px 12px" }}>
      <span className="sub2">Page {page + 1} of {pages} · {total.toLocaleString()} in all</span>
      <Btn kind="ghost" disabled={page === 0} onClick={() => onPage(page - 1)}>Previous</Btn>
      <Btn kind="ghost" disabled={page + 1 >= pages} onClick={() => onPage(page + 1)}>Next</Btn>
    </div>
  );
}

/* ── the upload ─────────────────────────────────────────────────────────────────────────────────────────────────── */

interface Read { filename: string; sha: string; head: string[]; body: string[][]; map: string[] }

export function CceUpload({ session, powers, pick, refresh, mapping }: TabProps & { mapping: Mapping }) {
  const [read, setRead] = useState<Read | null>(null);
  const [busy, setBusy] = useState(false);
  const [batch, setBatch] = useState<Batch | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  function template() {
    const blob = buildXlsx(TEMPLATE_COLUMNS.map(([h]) => h), [TEMPLATE_COLUMNS.map(([, , , ex]) => ex)], "CCE list");
    downloadBlob(blob, `cce-candidate-list-template-${session.replace("/", "-")}.xlsx`);
  }

  async function choose(file: File | null) {
    setProblem(null); setBatch(null); setRead(null);
    if (!file) return;
    try {
      const buf = await file.arrayBuffer();
      const grid = /\.csv$/i.test(file.name) ? csvRows(new TextDecoder().decode(buf)) : await xlsxRows(buf);
      const at = grid.findIndex((r) => r.filter((c) => LIST_ALIASES[norm(String(c ?? ""))]).length >= 2);
      if (at < 0) { setProblem("No row of headings was recognised. Use the template's headings: JAMB Number, Surname, First Name, Date of Birth, Programme Code …"); return; }
      const head = grid[at].map((h) => String(h ?? "").trim());
      const body = grid.slice(at + 1).filter((r) => r && r.some((c) => String(c ?? "").trim() !== "")).map((r) => r.map((c) => String(c ?? "").trim()));
      if (!body.length) { setProblem("The file has headings but no rows under them."); return; }
      if (body.length > 20000) { setProblem(`${body.length.toLocaleString()} rows: load the list in parts of 20,000 rows at most.`); return; }
      setRead({ filename: file.name, sha: await sha256Hex(buf), head, body, map: head.map((h) => LIST_ALIASES[norm(h)] ?? "") });
    } catch (e) {
      setProblem(`The file could not be read: ${e instanceof Error ? e.message : String(e)}. Save it as .xlsx or .csv and try again.`);
    }
  }

  const missing = read ? ["jamb_reg_no", "surname", "date_of_birth"].filter((k) => !read.map.includes(k))
    .concat(read.map.includes("first_name") || read.map.includes("other_names") ? [] : ["first_name"])
    .concat(read.map.includes("programme_code") || read.map.includes("programme") ? [] : ["programme_code"]) : [];

  async function preview() {
    if (!read) return;
    setBusy(true);
    try {
      const rows = read.body.map((r) => {
        const o: Record<string, string> = {};
        read.map.forEach((k, i) => { if (k && r[i] !== undefined && r[i] !== "" && o[k] === undefined) o[k] = r[i]; });
        return o;
      });
      const b = await cceSend<Batch>("/batches", "POST", { session, filename: read.filename, sha256: read.sha, rows }, `The CCE list ${read.filename} read for ${session}`);
      if (b) { setBatch(b); refresh(); }
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title="CCE candidate list upload" description="Only a committed list lets anybody apply." actions={pick} />
      <Panel title="The session this list is for">
        <PBody>
          <KvGrid cls="grid--4" pairs={[
            ["CCE session", <b key="s" className="tnum">{session}</b>],
            ["Mapped undergraduate session", <span key="u" className="tnum">{mapping.undergraduate_session ?? "—"}</span>],
            ["Relationship", mapping.relationship ?? "—"],
            ["Current CCE session", <span key="c" className="tnum">{mapping.route_session ?? "—"}{mapping.overridden ? " (named by the Academic Office)" : ""}</span>],
          ]} />
          {session !== mapping.route_session ? (
            <Note kind="info" title={`${session} is not the current CCE session`}>The current CCE session is {mapping.route_session}.</Note>
          ) : null}
        </PBody>
      </Panel>
      {!powers.academic ? (
        <Note kind="info" title="The Academic Office loads the list" />
      ) : batch ? (
        <BatchView id={batch.id} powers={powers} refresh={refresh} onDone={() => { setBatch(null); setRead(null); }} />
      ) : (
        <Panel title="1 · The file" right={<Btn kind="ghost" onClick={template}>Download the template</Btn>}>
          <PBody>
            <Field id="cce-file" label="The CCE list (Excel .xlsx or .csv)" hint="Headings are found and matched below; correct any match.">
              <input id="cce-file" type="file" className="ctl" accept=".xlsx,.csv" onChange={(e) => void choose(e.target.files?.[0] ?? null)} />
            </Field>
            {problem ? <Note kind="bad" title="The file was not read">{problem}</Note> : null}
            {read ? (
              <>
                <div className="sub2 mb-2"><b>{read.filename}</b> · {read.body.length.toLocaleString()} row{read.body.length === 1 ? "" : "s"} under the headings</div>
                <DTable noPrint pageSize={0} cols={["Heading in the file", "Read as", "First row"]} rows={read.head.map((h, i) => [
                  <b key="h">{h || <span className="sub2">(no heading)</span>}</b>,
                  <select key="m" className="ctl" aria-label={`Read ${h} as`} value={read.map[i]} onChange={(e) => setRead({ ...read, map: read.map.map((x, j) => (j === i ? e.target.value : x)) })}>
                    <option value="">— not read —</option>
                    {FIELDS.map(([k, label]) => <option key={k} value={k}>{label}</option>)}
                  </select>,
                  <span key="v" className="sub2">{read.body[0]?.[i] ?? ""}</span>,
                ])} />
                {missing.length ? <Note kind="bad" title="A field every row needs is not matched">{missing.map((k) => FIELDS.find(([f]) => f === k)?.[1] ?? k).join(", ")}: match a heading to it, or add the column to the file.</Note> : null}
                <div className="row row--inline mt-2">
                  <Btn kind="primary" size="md" disabled={busy || missing.length > 0} onClick={() => void preview()}>{busy ? "Reading the rows…" : `Preview ${read.body.length.toLocaleString()} rows for ${session}`}</Btn>
                  <span className="sub2">Nothing is loaded until you commit the preview.</span>
                </div>
              </>
            ) : null}
          </PBody>
        </Panel>
      )}
    </>
  );
}

/* ── one uploaded list: its counts, its rows, commit or discard ─────────────────────────────────────────────────── */

export function BatchView({ id, powers, refresh, onDone }: { id: string; powers: Powers; refresh: () => void; onDone?: () => void }) {
  const [data, setData] = useState<(Paged<BatchRow> & { batch: Batch }) | null>(null);
  const [cls, setCls] = useState<string>("");
  const [page, setPage] = useState(0);
  const [tick, setTick] = useState(0);
  const [busy, setBusy] = useState(false);
  const [discarding, setDiscarding] = useState(false);
  const [reason, setReason] = useState("");
  useEffect(() => {
    let live = true;
    void ccall<Paged<BatchRow> & { batch: Batch }>(`/api/v1/cce/batches/${id}/rows?classification=${cls}&page=${page}&size=100`).then((r) => {
      if (!live) return;
      if (r.ok) setData(r.data); else notifyProblem(r.problem);
    });
    return () => { live = false; };
  }, [id, cls, page, tick]);
  if (!data) return <Note kind="info" title="Reading the list…">One moment.</Note>;
  const b = data.batch;
  const n = (k: string) => Number(b.counts?.[k] ?? 0);
  const loads = n("NEW") + n("UPDATED");

  async function commit() {
    if (!window.confirm(`Commit ${b.filename}? ${n("NEW")} new and ${n("UPDATED")} updated rows are loaded; ${n("DUPLICATE") + n("REQUIRES_REVIEW") + n("INVALID")} are not.`)) return;
    setBusy(true);
    try {
      const r = await cceSend<Batch>(`/batches/${b.id}/commit`, "POST", {}, `The CCE list ${b.filename} committed for ${b.session}`);
      if (r) { setTick((t) => t + 1); refresh(); }
    } finally { setBusy(false); }
  }
  async function discard() {
    setBusy(true);
    try {
      const r = await cceSend<Batch>(`/batches/${b.id}/discard`, "POST", { reason: reason.trim() }, `The CCE list ${b.filename} discarded: ${reason.trim()}`);
      if (r) { setDiscarding(false); setTick((t) => t + 1); refresh(); }
    } finally { setBusy(false); }
  }

  return (
    <>
      <Panel title={`${b.filename} · ${b.session}`} right={<span className="row row--inline row--tight">
        <Pil kind={b.state === "COMMITTED" ? "ok" : b.state === "DISCARDED" ? "grey" : "warn"}>{b.state === "PREVIEW" ? "Preview — not loaded" : b.state === "COMMITTED" ? "Committed" : "Discarded"}</Pil>
        <a className="btn btn--ghost btn--sm" href={`/api/bff/api/v1/cce/batches/${b.id}/report.csv`} download={`${b.filename.replace(/\.[A-Za-z0-9]+$/, "")}-not-loaded.csv`}>Rows not loaded (CSV)</a>
        <a className="btn btn--ghost btn--sm" href={`/api/bff/api/v1/cce/batches/${b.id}/report.csv?all=true`} download={`${b.filename.replace(/\.[A-Za-z0-9]+$/, "")}-every-row.csv`}>Every row (CSV)</a>
      </span>}>
        <PBody>
          <div className="sub2 mb-2">Read {when(b.uploaded_at)} by {b.uploaded_by_name ?? "—"} · {b.rows_read.toLocaleString()} rows
            {b.committed_at ? <> · committed {when(b.committed_at)} by {b.committed_by_name ?? "—"}{b.applied ? `: ${b.applied.added ?? 0} added, ${b.applied.updated ?? 0} updated, ${b.applied.unchanged ?? 0} unchanged${b.applied.skipped ? `, ${b.applied.skipped} skipped (changed since the preview)` : ""}` : ""}</> : null}
            {b.discarded_at ? <> · discarded {when(b.discarded_at)}: {b.discard_reason}</> : null}</div>
          <Tiles cls="grid--3" items={CLASSES.map((k) => [CLASS_LABEL[k][0].toUpperCase(), n(k), k === "INVALID" && n(k) ? "var(--red-ink)" : k === "NEW" && n(k) ? "var(--green-ink)" : null] as [string, number, string | null])} />
          {b.state === "PREVIEW" && powers.academic ? (
            <div className="row row--inline mt-2">
              <Btn kind="go" size="md" disabled={busy || loads === 0} onClick={() => void commit()}>Commit: load {loads.toLocaleString()} row{loads === 1 ? "" : "s"}</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => setDiscarding(true)}>Discard</Btn>
              {onDone ? <Btn kind="ghost" onClick={onDone}>Another file</Btn> : null}
              <span className="sub2">Matched by JAMB number, never by name.</span>
            </div>
          ) : onDone ? <div className="row row--inline mt-2"><Btn kind="secondary" onClick={onDone}>Load another file</Btn></div> : null}
        </PBody>
      </Panel>
      <Panel title="The rows" right={<Tabs look="line" label="Rows" value={cls} onChange={(v) => { setCls(v); setPage(0); }}
        items={[{ id: "", label: "All", count: b.rows_read }, ...CLASSES.filter((k) => n(k)).map((k) => ({ id: k, label: CLASS_LABEL[k][0], count: n(k) }))]} />}>
        <DTable pageSize={0} cols={["Row|num", "JAMB number", "Name", "Date of birth", "Programme", "Result", "Why / what changes"]} rows={data.rows.map((r) => [
          <span key="n" className="tnum">{r.row_no}</span>,
          <span key="j" className="tnum">{r.jamb_reg_no ?? "—"}</span>,
          <span key="nm">{[r.surname, r.first_name, r.middle_name].filter(Boolean).join(" ") || "—"}<div className="sub2">{[r.sex, r.phone, r.email].filter(Boolean).join(" · ")}</div></span>,
          <span key="d" className="tnum">{day(r.date_of_birth)}</span>,
          <span key="p">{r.programme ?? r.programme_code ?? "—"}</span>,
          <Pil key="c" kind={labelOf(CLASS_LABEL, r.classification)[1]}>{labelOf(CLASS_LABEL, r.classification)[0]}</Pil>,
          <span key="w" className="sub2">{r.issues.join("; ")}{r.changes && Object.keys(r.changes).length ? <>{r.issues.length ? " · " : ""}{Object.entries(r.changes).map(([k, v]) => `${k.replace(/_/g, " ")}: ${v.from ?? "—"} → ${v.to ?? "—"}`).join("; ")}</> : null}{r.notes.length ? <>{r.issues.length ? " · " : ""}<i>{r.notes.join("; ")}</i></> : null}</span>,
        ])} />
        <Pager total={data.total} page={page} size={data.size} onPage={setPage} />
      </Panel>
      {discarding ? (
        <Modal title="Discard the list" sub={b.filename} onClose={() => setDiscarding(false)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setDiscarding(false)}>Back</Btn><Btn kind="urgent" disabled={busy || !reason.trim()} onClick={() => void discard()}>Discard it</Btn></span>}>
          <Field id="cce-discard" label="Why it is not loaded" required hint="Kept with the list in the import history"><textarea id="cce-discard" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}

/* ── the import history ─────────────────────────────────────────────────────────────────────────────────────────── */

export function CceImports({ session, powers, pick, refresh }: TabProps) {
  const [rows, setRows] = useState<Batch[] | null>(null);
  const [open, setOpen] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<{ rows: Batch[] }>(`/api/v1/cce/batches?session=${encodeURIComponent(session)}`).then((r) => { if (live && r.ok) setRows(r.data.rows); else if (live && !r.ok) notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, open]);
  if (open) return <><PageHead title="Import history" actions={<Btn kind="ghost" onClick={() => setOpen(null)}>← Every list</Btn>} /><BatchView id={open} powers={powers} refresh={refresh} /></>;
  return (
    <>
      <PageHead title="Import history" description={session} actions={pick} />
      <Panel title="The lists" right={powers.academic ? <LinkBtn kind="secondary" href="/cce/upload">Upload a list</LinkBtn> : null}>
        {rows === null ? <PBody><div className="sub2">Reading…</div></PBody> : rows.length ? (
          <DTable cols={["Read", "File", "Rows|num", "New|num", "Updated|num", "Not loaded|num", "State", ""]} rows={rows.map((b) => [
            <span key="w">{when(b.uploaded_at)}<div className="sub2">{b.uploaded_by_name ?? "—"}</div></span>,
            <b key="f">{b.filename}</b>, b.rows_read,
            Number(b.counts?.NEW ?? 0), Number(b.counts?.UPDATED ?? 0), Number(b.counts?.DUPLICATE ?? 0) + Number(b.counts?.REQUIRES_REVIEW ?? 0) + Number(b.counts?.INVALID ?? 0),
            <Pil key="s" kind={b.state === "COMMITTED" ? "ok" : b.state === "DISCARDED" ? "grey" : "warn"}>{b.state === "PREVIEW" ? "Preview" : b.state === "COMMITTED" ? `Committed ${day(b.committed_at)}` : `Discarded: ${b.discard_reason}`}</Pil>,
            <Btn key="o" kind="ghost" onClick={() => setOpen(b.id)}>Open</Btn>,
          ])} />
        ) : <PBody><div className="sub2">No CCE list has been loaded for {session}.</div></PBody>}
      </Panel>
    </>
  );
}

/* ── the list as committed ──────────────────────────────────────────────────────────────────────────────────────── */

export function CceCandidates({ session, powers, pick, initialStatus }: TabProps & { initialStatus: string | null }) {
  const [status, setStatus] = useState(initialStatus ?? "");
  const [q, setQ] = useState("");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);
  const [tick, setTick] = useState(0);
  const [data, setData] = useState<Paged<CandidateRow> | null>(null);
  const [acting, setActing] = useState<CandidateRow | null>(null);
  const [reason, setReason] = useState("");
  useEffect(() => {
    let live = true;
    void ccall<Paged<CandidateRow>>(`/api/v1/cce/candidates?session=${encodeURIComponent(session)}&status=${status}&q=${encodeURIComponent(query)}&page=${page}&size=50`)
      .then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, status, query, page, tick]);
  const exporting = useMemo(() => data?.rows ?? [], [data]);

  async function standing() {
    if (!acting) return;
    const to = acting.status === "WITHDRAWN" ? "LISTED" : "WITHDRAWN";
    const r = await cceSend(`/candidates/${acting.id}/standing`, "POST", { standing: to, reason: reason.trim() }, `${acting.name} ${to === "WITHDRAWN" ? "withdrawn from" : "reinstated on"} the CCE list: ${reason.trim()}`);
    if (r) { setActing(null); setReason(""); setTick((t) => t + 1); }
  }

  return (
    <>
      <PageHead title="CCE candidate list" description={session} actions={pick} />
      <Panel title="Listed candidates" right={<span className="row row--inline row--tight">
        <form onSubmit={(e) => { e.preventDefault(); setQuery(q.trim()); setPage(0); }}><input className="ctl" style={{ width: 230 }} placeholder="Search" aria-label="Search the CCE list" value={q} onChange={(e) => setQ(e.target.value)} /></form>
        <select className="ctl" aria-label="Where they stand" value={status} onChange={(e) => { setStatus(e.target.value); setPage(0); }}>
          <option value="">Every candidate</option>
          {STATUSES.map((s) => <option key={s} value={s}>{STATUS_LABEL[s][0]}</option>)}
        </select>
      </span>}>
        {data === null ? <PBody><div className="sub2">Reading…</div></PBody> : (
          <>
            <DTable pageSize={0} cols={["JAMB number", "Name", "Date of birth", "Programme", "Stands", "Application", ""]} rows={exporting.map((c) => [
              <span key="j" className="tnum">{c.jamb_reg_no}</span>,
              <span key="n">{c.name}<div className="sub2">{[c.sex, c.phone, c.email].filter(Boolean).join(" · ")}</div></span>,
              <span key="d" className="tnum">{day(c.date_of_birth)}</span>,
              <span key="p">{c.programme}<div className="sub2">{c.department ?? ""}</div></span>,
              <span key="s"><Pil kind={labelOf(STATUS_LABEL, c.status)[1]}>{labelOf(STATUS_LABEL, c.status)[0]}</Pil>{c.status === "WITHDRAWN" && c.standing_reason ? <div className="sub2">{c.standing_reason}</div> : null}</span>,
              c.application_id ? <Link key="a" href={`/cce/applications/${c.application_id}`} className="tnum">{c.application_no}</Link> : <span key="a" className="sub2">—</span>,
              powers.academic && !["ADMITTED"].includes(c.status) ? <Btn key="x" kind="ghost" onClick={() => { setActing(c); setReason(""); }}>{c.status === "WITHDRAWN" ? "Reinstate" : "Withdraw"}</Btn> : <span key="x" />,
            ])} />
            <Pager total={data.total} page={page} size={data.size} onPage={setPage} />
          </>
        )}
      </Panel>
      {acting ? (
        <Modal title={acting.status === "WITHDRAWN" ? "Reinstate on the CCE list" : "Withdraw from the CCE list"} sub={`${acting.name} · ${acting.jamb_reg_no}`} onClose={() => setActing(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setActing(null)}>Back</Btn><Btn kind={acting.status === "WITHDRAWN" ? "primary" : "urgent"} disabled={!reason.trim()} onClick={() => void standing()}>{acting.status === "WITHDRAWN" ? "Reinstate" : "Withdraw"}</Btn></span>}>
          <p className="sub2">{acting.status === "WITHDRAWN" ? "Reinstated, the candidate may apply again while the window is open." : "Withdrawn, the candidate cannot open an application; nothing is deleted. An admitted candidate is not withdrawn here."}</p>
          <Field id="cce-standing" label="The reason" required><textarea id="cce-standing" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
