"use client";

/**
 * The JAMB admission lists screen — proto/part52.html tCapsIntake, as the
 * prototype lays it out, with the API and the database behind it:
 *
 *   · the two buttons, UTME and Direct Entry, each fixing the list kind
 *   · the file read in this browser and shown back, with its findings
 *   · the list as uploaded, every course resolved by JAMB's name
 *   · then what the prototype could not do: LOAD it, held, and COMMIT it
 *     when the database says it reconciles
 *   · one code, two names — the University's programmes and JAMB's aliases
 */
import { reasonHeader } from "@/lib/reason";
import { useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { xlsxRows } from "@/lib/xlsx";
import { CAPS_DEMO } from "@/lib/caps-demo";
import {
  blockingFindings,
  isError,
  parseCaps,
  sha256Hex,
  toRequest,
  type CapsParse,
  type Cutoffs,
  type ListKind,
  type Programme,
} from "@/lib/caps";
import type { Problem } from "@/lib/api";
import { officeLabel } from "@/lib/offices";
import { Btn, Note, Panel, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AliasMapper } from "./AliasMapper";
import { ProgrammeEditor, type Department } from "./ProgrammeEditor";
import { LoadCutoff } from "../LoadCutoff";
import { Field, Modal } from "@/components/proto/blocks";

export interface CapsBatch {
  id: string;
  session: string;
  source: string;
  filename: string | null;
  fileSha256: string;
  rowsRead: number;
  listKind: ListKind;
  downloadedOn: string;
  uploadedAt: string;
  uploadedBy: string;
  uploadedOffice: string;
  committedAt: string | null;
  /** a list loaded in error: kept, marked, and out of every count (V019) */
  withdrawnAt: string | null;
  withdrawnReason: string | null;
}

export interface AdmissionPolicy {
  session: string;
  state: string;
  inForce: boolean;
  instrument: string | null;
  nucQuota: number;
  weightUtme: number;
  weightPutme: number;
  facultyCutoffs: { facultyCode: string; facultyName: string; quota: number | null; cutoff: number | null }[];
  programmeCutoffs: { code: string; name: string; cutoff: number }[];
  findings: { finding: string; detail: string; owner: string }[];
}

export interface Finding {
  finding: string;
  n: number;
  owner: string;
  whatItMeans: string;
}

const LISTS: Record<ListKind, { label: string; level: number; note: string }> = {
  UTME: { label: "UTME", level: 100, note: "Admitted into 100 Level on the UTME aggregate, out of 400." },
  DIRECT_ENTRY: {
    label: "Direct Entry",
    level: 200,
    note: "Admitted into 200 Level on A-Level, ND, NCE or HND. No UTME aggregate exists — the file sends 0, which is not a score.",
  },
};
const KINDS: ListKind[] = ["UTME", "DIRECT_ENTRY"];
const LOADING_OFFICES = ["academic", "registrar"];

interface FileInfo {
  name: string;
  size: number;
  sha256: string;
  layout?: string;
  cols?: number;
  sample?: boolean;
  err?: string;
}

interface Loaded {
  batch: { id: string; rowsRead: number };
  rowsLoaded: number;
  excluded: { jambRegNo: string; surname: string; otherNames: string; programme: string; aggregate: number | null; cutoff: number }[];
  outcome?: string;
}

function esc(s: string | null | undefined): string {
  return s ?? "";
}

export function CapsIntake({
  session,
  programmes,
  batches,
  batchesProblem,
  reconciliation,
  policy,
  policyProblem,
  actingOffice,
  today,
  departments,
  loadCutoff,
}: {
  session: string;
  programmes: Programme[];
  /** the live departments, for the programme editor */
  departments: Department[];
  /** the one UTME cut-off the lists load under (V024), or null while it is not stated */
  loadCutoff: number | null;
  batches: CapsBatch[];
  batchesProblem: Problem | null;
  reconciliation: Finding[];
  policy: AdmissionPolicy | null;
  policyProblem: Problem | null;
  actingOffice: string | null;
  today: string;
}) {
  const router = useRouter();
  const [kind, setKind] = useState<ListKind>("UTME");
  const [editing, setEditing] = useState<Programme | null>(null);
  const [withdrawing, setWithdrawing] = useState<CapsBatch | null>(null);
  const [why, setWhy] = useState("");
  const [withdrawn, setWithdrawn] = useState<Record<string, string>>({});
  const [file, setFile] = useState<Partial<Record<ListKind, FileInfo>>>({});
  const [rowsRead, setRowsRead] = useState<Partial<Record<ListKind, string[][]>>>({});
  const [busy, setBusy] = useState<ListKind | null>(null);
  const [loaded, setLoaded] = useState<Partial<Record<ListKind, Loaded>>>({});
  const [working, setWorking] = useState<"load" | "commit" | null>(null);
  const [progress, setProgress] = useState<{ sent: number; of: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [committing, setCommitting] = useState<string | null>(null);
  const [committed, setCommitted] = useState<Record<string, string>>({});
  const [resetMsg, setResetMsg] = useState<string | null>(null);
  const [resetting, setResetting] = useState(false);

  async function resetIntake() {
    if (!window.confirm(`Delete the entire JAMB list, applicant accounts, applications and O'Level for ${session}? Admission settings and any students already on the register are kept. This cannot be undone.`)) return;
    if (!window.confirm("Please confirm again: this permanently deletes the uploaded candidates and everything built on them for this session.")) return;
    setResetting(true);
    setProblem(null);
    setResetMsg(null);
    try {
      const r = await post(`/api/v1/admissions/sessions/${session}/reset-intake`, `Reset the JAMB list for ${session}`);
      if (r.ok) {
        const b = (r.body ?? {}) as Record<string, number>;
        setResetMsg(`Reset complete for ${session}: ${b.candidates ?? 0} candidates, ${b.applications ?? 0} applications, ${b.olevel ?? 0} O'Level sittings and ${b.caps_rows ?? 0} CAPS rows deleted; ${b.students_detached ?? 0} students on the register were kept. You can upload a fresh list now.`);
        router.refresh();
      } else {
        setProblem(asProblem(r.status, r.body));
      }
    } finally {
      setResetting(false);
    }
  }

  const mayLoad = actingOffice !== null && LOADING_OFFICES.includes(actingOffice);
  const inForce = !!policy?.inForce;
  /* the list loads under the one general cut-off (V024); the faculty's and programme's are the screening's */
  const cutoffs: Cutoffs | undefined = useMemo(
    () => (loadCutoff === null ? undefined : { faculty: {}, programme: {}, general: loadCutoff }),
    [loadCutoff],
  );
  /* read against the programmes as they are now — so a newly mapped alias resolves without re-uploading */
  const parsed = useMemo(() => {
    const out: Partial<Record<ListKind, ReturnType<typeof parseCaps>>> = {};
    for (const k of KINDS) {
      const rows = rowsRead[k];
      if (rows) out[k] = parseCaps(rows, k, programmes, cutoffs);
    }
    return out;
  }, [rowsRead, programmes, cutoffs]);
  const data: Partial<Record<ListKind, CapsParse>> = Object.fromEntries(
    KINDS.filter((k) => parsed[k] && !isError(parsed[k]!)).map((k) => [k, parsed[k] as CapsParse]),
  );
  const list = LISTS[kind];
  const f = file[kind];
  const d = data[kind];
  const bad = d ? blockingFindings(d) : [];
  const noted = d ? d.findings.filter((x) => !x.blocking) : [];
  const unresolved = d ? d.rows.filter((r) => !r.programme) : [];
  const done = loaded[kind];

  function take(k: ListKind, result: ReturnType<typeof parseCaps>, info: FileInfo, rows?: string[][]) {
    setRowsRead({ ...rowsRead, [k]: rows });
    if (isError(result)) {
      setFile({ ...file, [k]: { ...info, err: result.error } });
    } else {
      setFile({ ...file, [k]: { ...info, layout: result.layout, cols: result.columns } });
    }
    setLoaded({ ...loaded, [k]: undefined });
    setProblem(null);
    setKind(k);
  }

  async function read(k: ListKind, chosen: File) {
    setBusy(k);
    try {
      const buf = await chosen.arrayBuffer();
      const [rows, sha256] = await Promise.all([xlsxRows(buf), sha256Hex(buf)]);
      take(k, parseCaps(rows, k, programmes, cutoffs), { name: chosen.name, size: chosen.size, sha256 }, rows);
    } catch (e) {
      take(
        k,
        {
          error:
            `That file could not be read. ${e instanceof Error ? e.message : String(e)} An .xlsx saved by Excel ` +
            "or by CAPS is expected; a .csv or an older .xls will not open here.",
        },
        { name: chosen.name, size: chosen.size, sha256: "" },
      );
    } finally {
      setBusy(null);
    }
  }

  function demo(k: ListKind) {
    const rows = CAPS_DEMO[k];
    const text = rows.map((r) => r.join("\t")).join("\n");
    take(k, parseCaps(rows, k, programmes, cutoffs), { name: k === "UTME" ? "CAPS-UTME-sample.xlsx" : "CAPS-DE-sample.xlsx", size: text.length, sha256: "", sample: true }, rows);
  }

  async function post(path: string, reason: string, body?: unknown): Promise<{ ok: boolean; body: unknown; status: number }> {
    const response = await fetch(`/api/bff${path}`, {
      method: "POST",
      headers: { "X-Reason": reasonHeader(reason), ...(body !== undefined ? { "Content-Type": "application/json" } : {}) },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const json = await response.json().catch(() => null);
    return { ok: response.ok, body: json, status: response.status };
  }

  function asProblem(status: number, body: unknown): Problem {
    return body && typeof body === "object" && "status" in (body as object)
      ? (body as Problem)
      : { status, title: "The API answered without a problem body" };
  }

  /* a large download goes up in chunks: one request opens the batch, the rest append to it, and the batch is one */
  const CHUNK = 1500;
  async function load() {
    if (!d || !f || f.sample) return;
    setWorking("load");
    setProblem(null);
    try {
      const whole = toRequest(d, { session, filename: f.name, fileSha256: f.sha256, listKind: kind, downloadedOn: today });
      const rows = whole.rows;
      const chunks: typeof rows[] = [];
      for (let i = 0; i < rows.length; i += CHUNK) chunks.push(rows.slice(i, i + CHUNK));
      if (chunks.length === 0) chunks.push([]);
      setProgress({ sent: 0, of: rows.length });
      const first = await post(
        "/api/v1/admissions/caps-batches",
        `CAPS ${list.label} list ${f.name} loaded through the portal`,
        { ...whole, rows: chunks[0], rowsExpected: rows.length },
      );
      if (!first.ok) {
        setProblem(asProblem(first.status, first.body));
        return;
      }
      const result = first.body as Loaded;
      let sent = chunks[0].length;
      setProgress({ sent, of: rows.length });
      for (const chunk of chunks.slice(1)) {
        const r = await post(`/api/v1/admissions/caps-batches/${result.batch.id}/rows`, `CAPS ${list.label} list ${f.name}: rows ${sent + 1} to ${sent + chunk.length}`, { rows: chunk });
        if (!r.ok) {
          setProblem(asProblem(r.status, r.body));
          setLoaded({ ...loaded, [kind]: { ...result, outcome: `${sent} of ${rows.length} rows reached the register before the refusal; the batch stands uncommitted — withdraw it and load the file again.` } });
          return;
        }
        const part = r.body as Loaded;
        result.rowsLoaded += part.rowsLoaded;
        result.excluded = [...result.excluded, ...part.excluded];
        result.batch = part.batch;
        sent += chunk.length;
        setProgress({ sent, of: rows.length });
      }
      setLoaded({ ...loaded, [kind]: result });
      router.refresh();
    } finally {
      setWorking(null);
      setProgress(null);
    }
  }

  async function withdraw(b: CapsBatch) {
    setCommitting(b.id);
    setProblem(null);
    try {
      const r = await post(`/api/v1/admissions/caps-batches/${b.id}/withdraw`, `CAPS list ${b.filename ?? b.id} withdrawn: ${why.trim()}`, { reason: why.trim() });
      if (r.ok) {
        setWithdrawn({ ...withdrawn, [b.id]: why.trim() });
        setWithdrawing(null);
        setWhy("");
        router.refresh();
      } else {
        setProblem(asProblem(r.status, r.body));
      }
    } finally {
      setCommitting(null);
    }
  }

  async function commit(id: string, fromScreen: boolean) {
    setCommitting(id);
    setProblem(null);
    try {
      const r = await post(`/api/v1/admissions/caps-batches/${id}/commit`, "CAPS list committed through the portal");
      if (r.ok) {
        const outcome = String((r.body as { outcome?: string })?.outcome ?? "committed");
        setCommitted({ ...committed, [id]: outcome });
        if (fromScreen && done) setLoaded({ ...loaded, [kind]: { ...done, outcome } });
        router.refresh();
      } else {
        setProblem(asProblem(r.status, r.body));
      }
    } finally {
      setCommitting(null);
    }
  }

  const distinct = d ? new Set(d.rows.map((r) => r.jambCode).filter(Boolean)).size : 0;

  return (
    <>
      <Note kind="info" title="Two lists, uploaded separately, and never as one">
        JAMB approves the UTME and Direct Entry lists separately and the Academic Office downloads them as separate
        files, weeks apart. <b>Each has its own button</b>, and the list kind is fixed by the button you press
        rather than guessed from the file &mdash; a Direct Entry list loaded as UTME puts every one of those
        candidates at 100 Level with a blank aggregate, repeating a year they were admitted past.
      </Note>

      <Note kind="ok" title="Upload the CAPS download itself — the spreadsheet step is no longer needed">
        The file JAMB gives you names the course in <b>its own words</b> (<code>CO_NAME</code> = &ldquo;Medicine
        &amp; Surgery&rdquo;) and carries no course code. The University&rsquo;s programme table is keyed on the
        code, <b>C00061</b>, which this University calls <b>MBBS</b> &mdash; so until now somebody has been
        translating name to code by hand in Excel, for every row of every list.{" "}
        <b>The portal does it here, from all {programmes.length} programmes.</b> Both layouts are read: the raw
        download, and the file the office builds from it today.
      </Note>

      {/* ── the two buttons ── */}
      <div className="card">
        <div className="card__body">
          <div className="eyebrow">Upload the list downloaded from JAMB</div>
          <div className="grid grid--2" style={{ marginTop: 8 }}>
            {KINDS.map((kk) => {
              const c = LISTS[kk];
              const ff = file[kk];
              const dd = data[kk];
              const isBusy = busy === kk;
              const held = batches.filter((b) => b.listKind === kk && !b.withdrawnAt && !withdrawn[b.id]);
              return (
                <div className="card" key={kk} style={{ borderColor: kind === kk ? "var(--chrome)" : "var(--line)" }}>
                  <div className="card__body">
                    <div style={{ display: "flex", alignItems: "center", gap: 9, flexWrap: "wrap" }}>
                      <b style={{ fontSize: 15 }}>{c.label}</b>
                      <Pil kind="grey">{c.level} Level</Pil>
                      {isBusy ? (
                        <Pil kind="info">Reading…</Pil>
                      ) : dd ? (
                        <Pil kind="ok">{dd.rows.length} candidates read</Pil>
                      ) : ff ? (
                        <Pil kind="bad">Could not be read</Pil>
                      ) : held.length ? (
                        <Pil kind={held.some((b) => b.committedAt) ? "ok" : "info"}>
                          {held.reduce((n, b) => n + b.rowsRead, 0)} candidates {held.some((b) => b.committedAt) ? "committed" : "loaded, held"}
                        </Pil>
                      ) : (
                        <Pil kind="grey">Not uploaded</Pil>
                      )}
                    </div>
                    <div className="sub2">{c.note}</div>
                    <label className={`btn ${dd ? "btn--ghost" : "btn--primary"}`} htmlFor={`caps-${kk}`} style={{ cursor: "pointer" }}>
                      {dd ? `Upload a different ${c.label} file` : `Choose the ${c.label} file…`}
                      <input
                        type="file"
                        id={`caps-${kk}`}
                        accept=".xlsx"
                        hidden
                        onChange={(e) => {
                          const chosen = e.target.files?.[0];
                          if (chosen) void read(kk, chosen);
                          e.target.value = "";
                        }}
                      />
                    </label>
                    <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
                      <Btn kind="ghost" onClick={() => demo(kk)}>
                        Use the sample instead
                      </Btn>
                      {dd ? (
                        <Btn kind="ghost" onClick={() => setKind(kk)}>
                          View
                        </Btn>
                      ) : null}
                    </div>
                    {ff ? (
                      <div className="sub2">
                        <b>{esc(ff.name)}</b> &middot; {Math.max(1, Math.round(ff.size / 1024))} KB
                        {ff.layout ? (
                          <>
                            {" "}
                            &middot; {ff.layout} &middot; {ff.cols} columns
                          </>
                        ) : null}
                        {ff.sample ? <> &middot; a sample, shown but not loadable</> : null}
                      </div>
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
          <div className="sub2">
            Nothing leaves this browser until you press the button below: the workbook is unzipped and read here,
            shown back to you, and only then loaded.
          </div>
        </div>
      </div>

      {/* ── the cut-off the list loads under: one general one, stated before the upload (V024) ── */}
      <LoadCutoff session={session} cutoff={loadCutoff} may={mayLoad} />
      {policy === null ? (
        <Note
          kind="info"
          title={`No admission settings exist for ${session} yet`}
          action={
            <Link href={`/admissions/settings?session=${encodeURIComponent(session)}`} className="btn btn--ghost btn--sm">
              Go to the admission settings
            </Link>
          }
        >
          The list loads under the general cut-off above. The faculty&rsquo;s and the programme&rsquo;s own cut-offs, the quotas and the rules
          come from the session&rsquo;s admission settings and apply at screening; nobody is ranked or admitted until those are in force.
          {policyProblem?.detail ? <> <span className="sub2">{policyProblem.detail}</span></> : null}
        </Note>
      ) : !policy.inForce ? (
        <Note
          kind="info"
          title={`The admission settings for ${session} are a draft — the list still loads, nobody is screened until they are in force`}
          action={
            <Link href={`/admissions/settings?session=${encodeURIComponent(session)}`} className="btn btn--ghost btn--sm">
              Go to the admission settings
            </Link>
          }
        >
          {policy.findings.length} finding{policy.findings.length === 1 ? "" : "s"} keep{policy.findings.length === 1 ? "s" : ""} them
          from being put in force. Each names the rule and the office that answers it. The cut-offs below are the screening&rsquo;s.
        </Note>
      ) : null}
      {policy !== null && (
        <Panel
          title="The cut-off, from the admission settings"
          right={policy.inForce ? `${session} · in force · ${policy.instrument ?? ""}` : `${session} · draft`}
        >
          <DTable
            cols={["Faculty", "Code|mid", "Quota|num", "UTME cut-off|num"]}
            rows={policy.facultyCutoffs.map((fc) => [
              <strong key="n">{fc.facultyName}</strong>,
              <span className="tnum" key="c">{fc.facultyCode}</span>,
              <span className="tnum" key="q">{fc.quota ?? <span className="sub2">not distributed</span>}</span>,
              <b className="tnum" key="k">{fc.cutoff ?? <span className="sub2" style={{ fontWeight: 400 }}>none</span>}</b>,
            ])}
          />
          {policy.programmeCutoffs.length > 0 && (
            <div className="card__body">
              <div className="eyebrow">Programmes with a cut-off of their own</div>
              <div className="sub2">
                {policy.programmeCutoffs.map((p) => `${p.name} ${p.cutoff}`).join(" · ")}
              </div>
            </div>
          )}
        </Panel>
      )}

      {f && f.err ? (
        <Note kind="bad" title="That file could not be read">
          {f.err}
        </Note>
      ) : null}

      {!d ? (
        <Note kind="info" title={`Nothing uploaded for ${list.label} yet`}>
          Choose a file above, or press <b>Use the sample instead</b> to see the screen work. The file is read
          whole and checked before a single row is written: one whose rows contradict the list you chose is
          refused entirely rather than loaded and corrected afterwards, because a half-loaded admission list
          looks complete at every desk it passes.
        </Note>
      ) : (
        <>
          <Tiles
            items={[
              [`${list.label} candidates`, String(d.rows.length), null, `Read from ${esc(f?.name)}`],
              ["Entry level", String(list.level), null, kind === "DIRECT_ENTRY" ? "On the prior qualification" : "On the UTME aggregate"],
              ["Programmes", String(distinct), null, "Distinct courses on this list"],
              ["Findings", String(bad.length), bad.length ? "var(--red-ink)" : "var(--green-ink)", bad.length ? "Named below" : d.belowCutoff ? `${d.belowCutoff} under the cut-off, not loaded` : noted.length ? `${noted.length} noted, none blocking` : "Nothing to answer"],
            ]}
          />

          {bad.length ? (
            <>
              <Note kind="bad" title={`${bad.length} row${bad.length === 1 ? "" : "s"} cannot be accepted, so none of the file is written`}>
                The file is accepted whole or not at all. Each row below names the line in your file and what is
                wrong with it. Correct them and upload again &mdash; or, where the finding is a course the
                University has not mapped, map it first.
              </Note>
              <Panel title="What the importer refuses" right={bad.length > 12 ? `The first 12 of ${bad.length}, by line, as the file numbers them` : "By line, as the file numbers them"}>
                <DTable
                  cols={["Row|mid", "JAMB number|mid", "Why it is refused"]}
                  rows={bad.slice(0, 12).map((x) => [
                    <span className="tnum" key="l">{x.line}</span>,
                    <span className="tnum" key="n">{x.regNo}</span>,
                    <span style={{ color: "var(--red-ink)" }} key="m">{x.message}</span>,
                  ])}
                />
              </Panel>
            </>
          ) : unresolved.length ? (
            <Note kind="bad" title={`${unresolved.length} candidate${unresolved.length === 1 ? "" : "s"} on a course this University does not run`}>
              The University has to say which programme each of these means before the list can be loaded &mdash;
              the row itself is left exactly as JAMB sent it. <span className="sub2">&mdash; Academic Office, with the Directorate of ICT</span>
            </Note>
          ) : done ? (
            <Note
              kind="ok"
              title={done.outcome ? `The ${list.label} list is ${done.outcome}` : `${done.rowsLoaded} candidates loaded as the ${list.label} list for ${session} — held, not yet committed${done.excluded.length ? ` · ${done.excluded.length} under the cut-off, on record` : ""}`}
              action={
                done.outcome ? undefined : (
                  <Btn kind="go" onClick={() => void commit(done.batch.id, true)} disabled={committing !== null || !mayLoad}>
                    {committing === done.batch.id ? "Committing…" : `Commit the ${list.label} list`}
                  </Btn>
                )
              }
            >
              {done.outcome
                ? "It is on the register. The reconciliation below is what the database found before it let that happen."
                : "Every row reads, and every course resolves to a University programme. The database will commit the list only when every reconciliation finding below reads zero; if it refuses, it says why, by name."}
            </Note>
          ) : (
            <Note
              kind="ok"
              title="Every row reads, and every course resolves to a University programme"
              action={
                <Btn
                  kind="go"
                  onClick={() => void load()}
                  disabled={working !== null || !mayLoad || !!f?.sample || (kind === "UTME" && !inForce)}
                  title={f?.sample ? "A sample is shown, never loaded" : !mayLoad ? "The admission list is loaded by the Academic Office or the Registrar" : kind === "UTME" && !inForce ? `No admission settings are in force for ${session}` : undefined}
                >
                  {working === "load" ? (progress && progress.of > CHUNK ? `Loading — ${progress.sent.toLocaleString()} of ${progress.of.toLocaleString()} rows…` : "Loading…") : `Load the ${list.label} list${d.belowCutoff ? ` — ${d.rows.length - d.belowCutoff} of ${d.rows.length}` : ""}`}
                </Btn>
              }
            >
              {f?.sample
                ? "This is the sample. A real file is loaded to the register, held, and committed by a second, deliberate act."
                : `The list may be loaded to the register for ${session}, where it is held until it reconciles.`}
              {!mayLoad ? (
                <>
                  {" "}
                  You are acting as <b>{officeLabel(actingOffice)}</b>; the admission list is loaded by the Academic
                  Office or the Registrar.
                </>
              ) : null}
              {kind === "UTME" && !inForce ? (
                <>
                  {" "}
                  <b>No admission settings are in force for {session}</b>, so no cut-off can be applied and nothing
                  may be loaded until they are.
                </>
              ) : d.belowCutoff ? (
                <>
                  {" "}
                  <b>{d.belowCutoff}</b> under the cut-off will be held back, on record.
                </>
              ) : null}
            </Note>
          )}

          {problem ? <ProblemNotice problem={problem} /> : null}

          {d.unresolved.length > 0 && (
            <AliasMapper
              unresolved={d.unresolved}
              counts={Object.fromEntries(d.unresolved.map((n) => [n, d.rows.filter((r) => r.courseName === n).length]))}
              programmes={programmes}
            />
          )}

          {d.belowCutoff > 0 && (
            <Panel title="Under the cut-off — read, not loaded" right={`${d.belowCutoff} of ${d.rows.length} · kept on record with the batch`}>
              <DTable
                cols={["Row|mid", "JAMB number|mid", "Candidate", "Aggregate|num", "Cut-off|num", "Programme"]}
                rows={d.rows.filter((r) => r.belowCutoff !== null).map((r) => [
                  <span className="tnum" key="l">{r.line}</span>,
                  <span className="tnum" key="n">{r.jambRegNo}</span>,
                  <strong key="c">{r.name}</strong>,
                  <b className="tnum" style={{ color: "var(--red-ink)" }} key="a">{r.aggregate}</b>,
                  <span className="tnum" key="k">{r.belowCutoff}</span>,
                  <span className="sub2" key="p">{r.programme?.name ?? ""}</span>,
                ])}
              />
            </Panel>
          )}

          <Panel title={`${list.label} — the list as uploaded`} right={`${esc(f?.name)} · ${f?.layout ?? ""} · ${d.rows.length} candidates`}>
            <DTable
              cols={["JAMB number|mid", "Candidate", "Sex|mid", "State", "Aggregate|mid", "JAMB says|", "The University admits to|", "Faculty", "|num"]}
              texts={d.rows.map((r) => `${r.jambRegNo} ${r.name} ${r.stateOfOrigin} ${r.lga} ${r.courseName ?? ""} ${r.programme?.name ?? ""} ${r.programme?.facultyName ?? ""}`)}
              rows={d.rows.map((r) => [
                <span className="tnum" key="n">{r.jambRegNo}</span>,
                <span key="c">
                  <strong>{r.name}</strong>
                  {r.lga ? <div className="sub2">{r.lga}</div> : null}
                </span>,
                <span className="sub2" key="s">{r.sex}</span>,
                <span className="sub2" key="st">{r.stateOfOrigin}</span>,
                r.aggregate ? (
                  <span key="a">
                    <b className="tnum" style={r.belowCutoff !== null ? { color: "var(--red-ink)" } : undefined}>{r.aggregate}</b>
                    {r.belowCutoff !== null ? <div className="sub2" style={{ color: "var(--red-ink)" }}>under the cut-off of {r.belowCutoff}</div> : null}
                    <div className="sub2">
                      {r.subjects.filter((s) => s[0]).map((s) => `${s[0]} ${s[1] ?? ""}`).join(" · ")}
                      {r.eng ? ` · Eng ${r.eng}` : ""}
                    </div>
                  </span>
                ) : (
                  <span className="sub2" title="a Direct Entry candidate sat no UTME" key="a">n/a</span>
                ),
                <span key="j">
                  <span className="sub2">{r.courseName ?? "—"}</span>
                  {r.jambCode ? <div className="tnum sub2">{r.jambCode}</div> : null}
                </span>,
                r.programme ? (
                  <span key="p">
                    <strong>{r.programme.name}</strong>
                    <div className="sub2">{r.programme.deptCode}</div>
                  </span>
                ) : (
                  <span style={{ color: "var(--red-ink)", fontWeight: 600 }} key="p">not a programme here</span>
                ),
                <span className="sub2" key="f">{r.programme?.facultyName ?? "—"}</span>,
                <Btn kind={r.programme ? "ghost" : "urgent"} key="b" disabled title="Corrections arrive with the candidate record">
                  {r.programme ? "Edit" : "Resolve"}
                </Btn>,
              ])}
            />
          </Panel>

          <Note
            kind="info"
            title="Upload the passports to see them beside the names"
            action={
              <Link href={`/admissions/candidate-data?session=${encodeURIComponent(session)}`} className="btn btn--ghost btn--sm">
                Go to the passports
              </Link>
            }
          >
            JAMB sends the photographs as a separate folder, each file named with the candidate&rsquo;s registration
            number. Once uploaded they appear in this list, which is what an officer checking a name against a face
            actually needs.
          </Note>

          <div style={{ display: "flex", gap: 9, flexWrap: "wrap", alignItems: "center" }}>
            <Btn
              kind="ghost"
              onClick={() => {
                setFile({ ...file, [kind]: undefined });
                setRowsRead({ ...rowsRead, [kind]: undefined });
                setLoaded({ ...loaded, [kind]: undefined });
                setProblem(null);
              }}
            >
              Reset
            </Btn>
          </div>
        </>
      )}

      {/* ── what the register holds for this session ── */}
      <Panel title={`Lists loaded for ${session}`} right={batches.length ? `${batches.length} upload${batches.length === 1 ? "" : "s"}` : "nothing yet"}>
        {problem ? (
          <div className="card__body">
            <ProblemNotice problem={problem} />
          </div>
        ) : null}
        {batchesProblem ? (
          <div className="card__body">
            <ProblemNotice problem={batchesProblem} />
          </div>
        ) : batches.length === 0 ? (
          <div className="card__body">
            <div className="sub2">
              No admission list has been loaded for {session}. Loaded lists are held here until the database says
              they reconcile, and are committed by a second, deliberate act.
            </div>
          </div>
        ) : (
          <DTable
            cols={["Kind|mid", "File", "Rows|num", "Downloaded|mid", "Loaded|mid", "By", "State|mid", "|num"]}
            rows={batches.map((b) => [
              <b key="k">{LISTS[b.listKind]?.label ?? b.listKind}</b>,
              <span key="f">
                {b.filename ?? <span className="sub2">{b.source}</span>}
                <div className="sub2 tnum">{b.fileSha256.slice(0, 12)}…</div>
              </span>,
              <span className="tnum" key="r">{b.rowsRead}</span>,
              <span className="tnum" key="d">{b.downloadedOn}</span>,
              <span className="tnum" key="l">{new Date(b.uploadedAt).toLocaleString("en-GB")}</span>,
              <span className="sub2" key="b">{officeLabel(b.uploadedOffice)}</span>,
              b.withdrawnAt || withdrawn[b.id] ? (
                <span key="s">
                  <Pil kind="grey">withdrawn</Pil>
                  <div className="sub2">{b.withdrawnReason ?? withdrawn[b.id]}</div>
                </span>
              ) : b.committedAt || committed[b.id] ? <Pil kind="ok" key="s">committed</Pil> : <Pil kind="info" key="s">held</Pil>,
              b.withdrawnAt || withdrawn[b.id] || b.committedAt || committed[b.id] ? (
                <span key="c" />
              ) : (
                <span key="c" style={{ display: "inline-flex", gap: 6 }}>
                  <Btn kind="go" onClick={() => void commit(b.id, false)} disabled={committing !== null || !mayLoad} title={!mayLoad ? "The list is committed by the Academic Office or the Registrar" : undefined}>
                    {committing === b.id ? "Committing…" : "Commit"}
                  </Btn>
                  <Btn kind="ghost" onClick={() => { setWithdrawing(b); setWhy(""); }} disabled={committing !== null || !mayLoad} title="A list loaded in error is withdrawn, never deleted">
                    Withdraw
                  </Btn>
                </span>
              ),
            ])}
          />
        )}
      </Panel>

      <Panel title="Does the list reconcile?" right="What the database finds, both ways">
        <DTable
          cols={["Rows|num", "Finding", "What it means", "Owner"]}
          rows={reconciliation.map((x) => [
            <b className="tnum" style={{ color: x.n > 0 ? "var(--red-ink)" : "var(--green-ink)" }} key="n">{x.n}</b>,
            <strong key="f">{x.finding}</strong>,
            <span className="sub2" key="m">{x.whatItMeans}</span>,
            <span className="sub2" key="o">{x.owner}</span>,
          ])}
        />
      </Panel>

      {/* ── the two names, always visible ── */}
      <Panel title="One course code, two names" right={`The University’s programme table is keyed on the same C-code JAMB uses · all ${programmes.length} · ${programmes.filter((p) => !p.jambName || p.jambName.toUpperCase() !== p.name.toUpperCase()).length} of the names differ`}>
        <DTable
          cols={["Code|mid", "JAMB calls it", "The University calls it", "Department|mid", "Faculty", "|num"]}
          texts={programmes.map((p) => `${p.code} ${p.jambName ?? ""} ${p.name} ${p.deptCode} ${p.facultyName ?? ""}`)}
          rows={programmes.map((p) => {
            const same = !!p.jambName && p.jambName.toUpperCase() === p.name.toUpperCase();
            return [
              <b className="tnum" key="c">{p.code}</b>,
              <span className="sub2" key="j">{p.jambName ?? ""}</span>,
              same ? <span className="sub2" key="u">{p.name}</span> : <strong key="u">{p.name}</strong>,
              <span className="tnum" key="d">{p.deptCode}</span>,
              <span className="sub2" key="f">{p.facultyName ?? "—"}</span>,
              <Btn kind="ghost" key="e" onClick={() => setEditing(p)} title="The University's own words for this programme">
                Edit
              </Btn>,
            ];
          })}
        />
      </Panel>
      {editing ? <ProgrammeEditor programme={editing} departments={departments} onClose={() => setEditing(null)} /> : null}
      {withdrawing ? (
        <Modal
          title={`Withdraw ${withdrawing.filename ?? withdrawing.source}`}
          sub={`${LISTS[withdrawing.listKind]?.label ?? withdrawing.listKind} · ${withdrawing.rowsRead} rows · loaded ${new Date(withdrawing.uploadedAt).toLocaleString("en-GB")}`}
          onClose={() => setWithdrawing(null)}
          foot={<>
            <Btn kind="ghost" onClick={() => setWithdrawing(null)}>Cancel</Btn>
            <span style={{ flexGrow: 1 }} />
            <Btn kind="urgent" disabled={!why.trim() || committing !== null} onClick={() => void withdraw(withdrawing)}>
              {committing === withdrawing.id ? "Withdrawing…" : "Withdraw the list"}
            </Btn>
          </>}
        >
          <Note kind="info" title="Withdrawn, not deleted">
            The upload happened, and the record keeps saying so: the file, its rows, who loaded it and when. Withdrawn, the list counts for nothing &mdash; the reconciliation no longer sees it, it cannot be committed, and the registration numbers on it are free for the list that should have been loaded. A list whose candidates already hold admission numbers cannot be withdrawn.
          </Note>
          <div className="grid grid--2 rfgrid">
            <Field id="wd-why" label="Why the list is withdrawn" hint="Goes on the record with the withdrawal" full>
              <input id="wd-why" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} autoComplete="off" placeholder="The wrong file, the wrong kind of list, the wrong session…" />
            </Field>
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </Modal>
      ) : null}

      <Note kind="info" title="JAMB’s name is the JOIN, not a footnote">
        The download names the course and gives no code, so <b>JAMB&rsquo;s name is what the row is matched on</b>{" "}
        &mdash; it is the only thing in the file that says which programme the candidate was admitted to. The
        University&rsquo;s name is then the label: it is what appears on the registration form, the matriculation
        list and the certificate. <b>C00061</b> is the case that shows why the two cannot be collapsed. JAMB calls
        it <i>Medicine &amp; Surgery</i>; this University calls it <b>MBBS</b>. That is not a missing award prefix
        or a capitalisation difference &mdash; the two institutions use different words for the same degree, and
        only one of them belongs on a certificate. The names that match today are not a rule: either side can edit
        a label, so the alias is held per code rather than worked out by comparing strings. A name the alias list
        does not carry is a finding with a candidate against it, never a guess.
      </Note>

      <Note kind="bad" title="One thing to check before this file is sent anywhere">
        The real Direct Entry file the Directorate examined was 2.4&nbsp;MB for 26 rows. The rows were 3&nbsp;KB of
        it; the rest was Excel&rsquo;s cache of workbooks it had been linked to, carrying{" "}
        <b>24,820 other candidates&rsquo; numbers, names, sex, state and aggregate scores</b> invisibly inside it,
        along with the officer&rsquo;s own file path. Under the NDPA 2023 that is a disclosure of personal data every
        time the file is e-mailed. Pasting the rows into a fresh workbook removes it, and this screen reports it on
        every file it reads.
      </Note>

      {mayLoad ? (
        <Panel title={`Reset the JAMB list for ${session}`} right="Start the intake again">
          <div style={{ padding: 16 }}>
            {resetMsg ? <Note kind="ok" title="Done">{resetMsg}</Note> : null}
            <Note kind="bad" title="This clears the uploaded list so you can upload again">
              It deletes, for {session}, the CAPS/JAMB list and its candidates, their O&rsquo;Level, photos and attachments,
              and the applicant intake built on them &mdash; applicant accounts, applications, documents, fee references and
              their gateway records, and screening batches. It <b>keeps</b> your admission settings and policy, and every
              student already on the register (each is detached from the deleted candidate). Use it when a re-upload is
              refused because the previous list is still loaded.
            </Note>
            <div style={{ marginTop: 10 }}>
              <Btn kind="urgent" disabled={resetting} onClick={() => void resetIntake()}>
                {resetting ? "Resetting…" : `Delete the ${session} list, applications and O'Level`}
              </Btn>
            </div>
          </div>
        </Panel>
      ) : null}
    </>
  );
}

export type { ReactNode };
