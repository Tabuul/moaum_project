"use client";

/** t/migrate — bring the paid applicants over from the old portal (V167). A spreadsheet of the ~13,000
 *  who applied and paid is read in the browser, mapped to the columns the importer needs, then sent up in
 *  small chunks; each row is created idempotently (candidate + login + submitted, paid application). The
 *  initial password is the JAMB number. The applicant fee must be set for the session first. */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { Btn, LinkBtn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";

interface Fee { stated: boolean; applicationFee: number; portalCharge: number }
/** a row carries either a single `name`, or a `surname`/`otherNames` pair, plus the rest */
interface Row { jambKey: string; name?: string; surname?: string; otherNames?: string; programme: string; entryMode: string; email: string; phone: string; utme: string }
interface Problem { jambKey: string; name: string; status: string }
type NameOrder = "first" | "last";

// the migration only verifies against CAPS and confirms payment, so the template is the JAMB number
// alone; email/phone are still read if a file happens to carry them (for the login/contact)
const COLS = ["JAMB Number"];
const CHUNK = 50;
const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

/** split a single name field into surname + other names, on a comma or on the chosen order */
function splitName(raw: string, order: NameOrder): { surname: string; otherNames: string } {
  const n = (raw ?? "").trim();
  if (n.includes(",")) { const [s, ...rest] = n.split(","); return { surname: s.trim(), otherNames: rest.join(",").trim() }; }
  const t = n.split(/\s+/).filter(Boolean);
  if (t.length <= 1) return { surname: n, otherNames: "" };
  return order === "last"
    ? { surname: t[t.length - 1], otherNames: t.slice(0, -1).join(" ") }
    : { surname: t[0], otherNames: t.slice(1).join(" ") };
}

/** the effective surname/other names for a row, given the chosen order for single-name files */
function names(r: Row, order: NameOrder): { surname: string; otherNames: string } {
  if (r.name != null) return splitName(r.name, order);
  return { surname: r.surname ?? "", otherNames: r.otherNames ?? "" };
}

/** find the column index whose header matches any of the needles */
function pick(headers: string[], needles: string[]): number {
  const h = headers.map(norm);
  for (const n of needles) {
    const i = h.findIndex((x) => x.includes(n));
    if (i >= 0) return i;
  }
  return -1;
}

export function MigrateApplicants({ session, fee, actingOffice }: { session: string; fee: Fee; actingOffice: string | null }) {
  const may = ["academic", "registrar", "dregistrar", "ict", "super"].includes(actingOffice ?? "");
  const [rows, setRows] = useState<Row[] | null>(null);
  const [nameOrder, setNameOrder] = useState<NameOrder>("first");
  const [parallel, setParallel] = useState(6);
  const [fileName, setFileName] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; of: number } | null>(null);
  const [result, setResult] = useState<{ imported: number; existed: number; skipped: number; placeholders: number; passportsLinked: number; problems: Problem[]; capsRows?: number; capsSample?: string[] } | null>(null);
  const [resetting, setResetting] = useState(false);
  const [resetInfo, setResetInfo] = useState<{ candidates: number; applications: number; accounts: number; passports_kept: number } | null>(null);
  const money = (n: number) => `₦${Number(n).toLocaleString("en-NG")}`;

  // clear only the old-portal migration's records (candidate/account/application), so it can be re-run
  // against the CAPS list — keeps the CAPS rows, O'Level and passports (passports re-link by JAMB number)
  async function resetMigrated() {
    if (!window.confirm("Clear the migrated applicants for " + session + "? This removes only the migrated candidate/account/application records so you can re-run the migration against the CAPS list. The CAPS list, O'Level results and passports are kept (passports re-link by JAMB number). Proceed?")) return;
    setResetting(true); setResetInfo(null); setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/import-applicants/reset-migrated`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Reset migrated applicants for ${session} to re-run against CAPS`) }, body: "{}",
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j?.detail ?? "The reset could not run."); return; }
      setResetInfo({ candidates: Number(j?.candidates ?? 0), applications: Number(j?.applications ?? 0), accounts: Number(j?.accounts ?? 0), passports_kept: Number(j?.passports_kept ?? 0) });
      notify(`Migrated applicants reset for ${session}`);
    } finally {
      setResetting(false);
    }
  }

  function template() {
    const blob = buildXlsx(COLS, [["202699168863AH"], ["202699168864BC"]], "Applicants");
    downloadBlob(blob, "old-portal-applicants-template.xlsx");
  }

  async function read(file: File | undefined) {
    if (!file) return;
    setErr(null); setResult(null); setRows(null); setFileName(file.name);
    try {
      const grid = /\.csv$/i.test(file.name) ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
      if (grid.length < 2) { setErr("The file has no data rows under the header."); return; }
      const head = grid[0];
      const iK = pick(head, ["jamb", "regno", "registration", "reg"]);
      const iS = pick(head, ["surname", "lastname"]);
      const iO = pick(head, ["othername", "othernames", "firstname", "givenname", "middlename"]);
      // a single full-name column: a header that is "name" but not surname/other/username
      const iN = head.findIndex((h) => { const x = norm(h); return x === "name" || x === "fullname" || (x.includes("name") && !x.includes("surname") && !x.includes("other") && !x.includes("user") && !x.includes("first") && !x.includes("last")); });
      const iP = pick(head, ["programme", "program", "course", "department"]);
      const iM = pick(head, ["entrymode", "entry", "mode"]);
      const iE = pick(head, ["email", "mail"]);
      const iH = pick(head, ["phone", "mobile", "gsm", "telephone", "tel", "msisdn"]);
      const iA = pick(head, ["aggregate", "aggr", "utme", "score"]);
      const hasSplit = iS >= 0 && iO >= 0;
      if (iK < 0) { setErr("The JAMB / registration number column was not found in the header row."); return; }
      // names/programme are no longer required — they come from the JAMB CAPS list; only the JAMB number is needed
      const out: Row[] = [];
      for (let r = 1; r < grid.length; r++) {
        const g = grid[r];
        const jambKey = (g[iK] ?? "").trim();
        if (!jambKey) continue;
        out.push({
          jambKey,
          ...(hasSplit
            ? { surname: (g[iS] ?? "").trim(), otherNames: (g[iO] ?? "").trim() }
            : { name: (g[iN] ?? "").trim() }),
          programme: iP >= 0 ? (g[iP] ?? "").trim() : "",
          entryMode: iM >= 0 ? (g[iM] ?? "").trim() : "UTME",
          email: iE >= 0 ? (g[iE] ?? "").trim() : "",
          phone: iH >= 0 ? (g[iH] ?? "").trim() : "",
          utme: iA >= 0 ? (g[iA] ?? "").trim() : "",
        });
      }
      if (!out.length) { setErr("No row carried a JAMB number."); return; }
      setRows(out);
      window.scrollTo(0, 0);
    } catch (e) {
      setErr(`That file could not be read. ${e instanceof Error ? e.message : String(e)} An .xlsx or .csv is expected.`);
    }
  }

  async function run() {
    if (!rows) return;
    const all = rows;
    const total = all.length;
    setBusy(true); setErr(null); setResult(null);
    // build every chunk up front (names already split for the chosen order)
    const chunks: { jambKey: string; surname: string; otherNames: string; programme: string; entryMode: string; email: string; phone: string; utme: string }[][] = [];
    for (let i = 0; i < total; i += CHUNK) {
      chunks.push(all.slice(i, i + CHUNK).map((r) => {
        const { surname, otherNames } = names(r, nameOrder);
        return { jambKey: r.jambKey, surname, otherNames, programme: r.programme, entryMode: r.entryMode, email: r.email, phone: r.phone, utme: r.utme };
      }));
    }
    const tally = { imported: 0, existed: 0, skipped: 0, placeholders: 0, passportsLinked: 0, problems: [] as Problem[], capsRows: 0, capsSample: [] as string[] };
    let next = 0;
    let done = 0;
    let stopped = false;
    // a pool of workers, each pulling the next chunk — several chunks in flight at once
    async function worker() {
      while (!stopped) {
        const my = next++;
        if (my >= chunks.length) break;
        const slice = chunks[my];
        // resilient: a transient failure (502 during a deploy restart, a network blip) retries with
        // backoff instead of aborting the whole run — the import is idempotent, so a retried chunk
        // just re-counts already-imported rows as "existed". Only give up after several tries.
        let r: Response | null = null;
        let j: { imported?: number; existed?: number; skipped?: number; placeholders?: number; capsRows?: number; capsSample?: string[]; problems?: Problem[]; detail?: string; title?: string } | null = null;
        for (let attempt = 1; attempt <= 5 && !stopped; attempt++) {
          r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/import-applicants`, {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old-portal applicants imported for ${session}: chunk ${my + 1} of ${chunks.length}`) },
            body: JSON.stringify({ rows: slice }),
          }).catch(() => null);
          j = r ? await r.json().catch(() => null) : null;
          if (r && r.ok) break;
          // a 4xx that is a real validation problem should not be retried; a 502/503/504/network is transient
          const transient = !r || r.status === 502 || r.status === 503 || r.status === 504 || r.status === 429 || r.status >= 500;
          if (!transient) { break; }
          if (attempt < 5) { setProgress({ done, of: total }); await new Promise((res) => setTimeout(res, 1500 * attempt)); }
        }
        if (!r || !r.ok) {
          stopped = true;
          setErr((j && (j.detail || j.title)) || `A chunk kept failing (${r ? `${r.status} ${r.statusText}` : "network"}) after several retries. What imported so far is kept — wait a minute for the server, then run the file again and it skips them.`);
          return;
        }
        tally.imported += j?.imported ?? 0;
        tally.existed += j?.existed ?? 0;
        tally.skipped += j?.skipped ?? 0;
        tally.placeholders += j?.placeholders ?? 0;
        tally.capsRows = j?.capsRows ?? tally.capsRows;
        if (Array.isArray(j?.capsSample) && j.capsSample.length) tally.capsSample = j.capsSample;
        for (const p of (j?.problems as Problem[] | undefined) ?? []) tally.problems.push(p);
        done += slice.length;
        setProgress({ done, of: total });
        setResult({ ...tally });
      }
    }
    try {
      await Promise.all(Array.from({ length: Math.max(1, Math.min(parallel, chunks.length)) }, worker));
      if (!stopped) {
        // one final sweep so any passports held for these candidates link on
        const lr = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/import-applicants/link-held`, {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Link held passports after import for ${session}`) }, body: "{}",
        }).catch(() => null);
        const lj = lr && lr.ok ? await lr.json().catch(() => null) : null;
        tally.passportsLinked = lj?.passportsLinked ?? 0;
        setProgress({ done: total, of: total });
        setResult({ ...tally });
        notify(`${tally.imported} imported · ${tally.existed} already on record`);
      }
    } finally {
      setBusy(false);
    }
  }

  function downloadProblems() {
    if (!result?.problems.length) return;
    const blob = buildXlsx(["JAMB Number", "Name", "Why it was not imported"], result.problems.map((p) => [p.jambKey, p.name, p.status]), "Not imported");
    downloadBlob(blob, `applicants-not-imported-${session.replace(/[^0-9]+/g, "-")}.xlsx`);
  }

  const amount = fee.applicationFee + fee.portalCharge;

  return (
    <>
      <Note kind="info" title="Migrate the applicants who already applied and paid on the old portal">
        The <b>JAMB CAPS list is the source of the applicant&rsquo;s data</b> — name, programme, sex, state, LGA, UTME and
        subjects all come from it, so <b>upload and commit the CAPS list first</b>. This migration only <b>confirms the
        payment and creates the login</b>: for each row it finds the applicant on the CAPS list by <b>JAMB number</b>,
        creates their account (initial password = their JAMB number), and writes a confirmed application-fee receipt marked
        paid and submitted. So the file needs only the <b>JAMB number</b> (email and phone are optional, for the login and
        contact — a placeholder stands in where a row has none; any name/programme columns are ignored, CAPS is used). A
        JAMB number <b>not on the CAPS list is skipped and reported</b>. It is safe to run the same file more than once —
        an applicant who already has an account is skipped, not duplicated.
      </Note>

      {fee.stated ? (
        <Note kind="ok" title={`The applicant fee is set for ${session}`}>
          Each imported applicant will have a confirmed receipt of <b>{money(amount)}</b> — application fee {money(fee.applicationFee)} + portal charge {money(fee.portalCharge)}.
        </Note>
      ) : (
        <Note kind="bad" title={`The applicant fee is not set for ${session}`}
          action={<LinkBtn kind="urgent" href="/finance/fees">Set the fee</LinkBtn>}>
          The application fee, portal charge and acceptance fee are not stated for {session}, so imported receipts would use
          the portal’s <b>fallback</b> amounts. Set the applicant fee first, then import, so every receipt shows the right money.
        </Note>
      )}

      <Panel title="Re-run the migration from scratch" right="Clears only the migrated applicants">
        <PBody>
          <div className="sub2 mb-2">
            If applicants were migrated before the CAPS list was uploaded, clear the migration and import the file again so
            every applicant is rebuilt from CAPS. This removes only the migrated <b>candidate / account / application</b>
            records — the CAPS list, O&rsquo;Level results and passports are kept (passports re-link by JAMB number).
          </div>
          <div className="row">
            <Btn kind="urgent" disabled={resetting || !may} onClick={() => void resetMigrated()}>{resetting ? "Clearing…" : "Reset migrated applicants"}</Btn>
            {!may ? <span className="sub2">Only the Academic Office, Registry or ICT may run this.</span> : null}
            {resetInfo ? <span className="sub2 ink-green">Cleared {resetInfo.candidates.toLocaleString()} candidate{resetInfo.candidates === 1 ? "" : "s"}, {resetInfo.applications.toLocaleString()} application{resetInfo.applications === 1 ? "" : "s"}; {resetInfo.passports_kept.toLocaleString()} passport{resetInfo.passports_kept === 1 ? "" : "s"} kept for re-linking.</span> : null}
          </div>
        </PBody>
      </Panel>

      <div className="card"><div className="card__body row">
        <label className="btn btn--ghost" htmlFor="mig-file" style={{ cursor: "pointer" }}>Choose the applicants file (.xlsx or .csv)…
          <input type="file" id="mig-file" accept=".xlsx,.csv" hidden onChange={(e) => void read(e.target.files?.[0])} />
        </label>
        <Btn kind="ghost" onClick={template}>Download the template</Btn>
        {fileName ? <span className="sub2">{fileName}</span> : null}
      </div></div>

      {err ? <Note kind="bad" title="That file could not be used">{err}</Note> : null}

      {rows ? (
        <>
          <Tiles items={[
            ["Rows read", String(rows.length), null, "Applicants in the file"],
            ["Application state", "Paid + submitted", null, "As agreed for the migration"],
            ["Initial password", "JAMB number", null, "Changed on first sign-in"],
            ["Receipt amount", fee.stated ? money(amount) : "fallback", fee.stated ? null : "var(--red-ink)", "Per imported applicant"],
          ]} />
          {rows.some((r) => r.name != null) ? (
            <div className="card"><div className="card__body row row--end">
              <div style={{ minWidth: 240 }}><Field id="mig-order" label="Name order in the single Name column">
                <select id="mig-order" className="ctl" value={nameOrder} onChange={(e) => setNameOrder(e.target.value as NameOrder)}>
                  <option value="first">Surname first — e.g. AHUMBE Aondofa Kingsley</option>
                  <option value="last">Surname last — e.g. Aondofa Kingsley Ahumbe</option>
                </select>
              </Field></div>
              <span className="sub2">A name written &ldquo;Surname, Other names&rdquo; is split on the comma either way. Check the split below before importing.</span>
            </div></div>
          ) : null}
          <Panel title="First rows, as read" right={`${rows.length} to verify & confirm`}>
            <PBody><div className="sub2 mb-2">Each JAMB number is verified against the CAPS list; the name, programme, sex, state, LGA and UTME come from CAPS. Email and phone (if the file carries them) are used for the login and contact, otherwise a placeholder stands in.</div></PBody>
            <DTable
              cols={["JAMB no|mid", "Email", "Phone|mid"]}
              rows={rows.slice(0, 8).map((r) => [
                <span className="tnum sub2" key="j">{r.jambKey}</span>,
                <span className="sub2" key="e">{r.email || <span className="ink-chrome">placeholder</span>}</span>,
                <span className="tnum sub2" key="h">{r.phone || <span className="ink-chrome">placeholder</span>}</span>,
              ])}
            />
            <PBody>
              <div className="row">
                <Btn kind="primary" disabled={busy || !may} onClick={() => void run()}>{busy ? "Importing…" : `Import ${rows.length} applicant${rows.length === 1 ? "" : "s"}`}</Btn>
                <div style={{ minWidth: 150 }}><Field id="mig-par" label="Parallel uploads">
                  <select id="mig-par" className="ctl" value={parallel} disabled={busy} onChange={(e) => setParallel(Number(e.target.value))}>
                    {[2, 4, 6, 8, 10, 12].map((n) => <option key={n} value={n}>{n} at a time</option>)}
                  </select>
                </Field></div>
                {!may ? <span className="sub2">Only the Academic Office, Registry or ICT may import.</span> : null}
              </div>
              <div className="sub2 mt-2">
                The initial password is not hashed at import — the JAMB number is the initial password, and the applicant&rsquo;s
                real password is hashed when they set it on first sign-in — so the import is fast. <b>Parallel uploads</b> can
                be raised to finish sooner; lower it only if you see timeouts. It is safe to leave running, and safe to re-run:
                rows already imported are skipped.
              </div>
              {progress ? <div className="sub2 mt-2">Imported {Math.min(progress.done, progress.of).toLocaleString()} of {progress.of.toLocaleString()}…</div> : null}
            </PBody>
          </Panel>
        </>
      ) : null}

      {result ? (
        <Panel title="Import result" right={busy ? "running…" : "done"}>
          <PBody>
            <Tiles items={[
              ["Imported", String(result.imported), "var(--green-ink)", "New accounts created"],
              ["Already existed", String(result.existed), null, "Skipped — not duplicated"],
              ["On placeholder contacts", String(result.placeholders), result.placeholders ? "var(--chrome)" : null, "Imported; no email/phone yet"],
              ["Not imported", String(result.skipped), result.skipped ? "var(--red-ink)" : null, "Bad or unusable rows"],
            ]} />
            {result.skipped > 0 && result.problems.some((p) => (p.status ?? "").includes("not on the JAMB CAPS list")) ? (
              result.capsRows === 0 ? (
                <Note kind="bad" title={`No JAMB CAPS rows exist for ${session}`}>
                  The importer verifies each JAMB number against the CAPS list for <b>{session}</b>, and there are <b>0</b> CAPS rows under that session — so every row is skipped. The CAPS list was uploaded under a <b>different session</b>, or not committed. Upload/commit the CAPS list for {session}, then re-run.
                </Note>
              ) : (
                <Note kind="bad" title={`${result.capsRows?.toLocaleString()} CAPS rows on file, but the JAMB numbers are not matching`}>
                  CAPS rows exist for <b>{session}</b>, so this is a <b>number-format mismatch</b> — the JAMB numbers in your file do not equal the CAPS registration numbers. Compare the format:
                  {result.capsSample?.length ? <> the CAPS numbers look like <b className="tnum">{result.capsSample.join(", ")}</b>.</> : null} Make the file&rsquo;s JAMB column match that exactly (no extra characters, not the application number), then re-run.
                </Note>
              )
            ) : null}
            {result.passportsLinked ? (
              <Note kind="ok" title={`${result.passportsLinked} held passport${result.passportsLinked === 1 ? "" : "s"} linked to the imported applicants`}>
                Passports uploaded earlier that had no candidate to attach to have now snapped onto the applicants this import created, matched on the JAMB number.
              </Note>
            ) : null}
            {result.problems.length ? (
              <>
                <div className="mt-2 mb-2"><Btn kind="ghost" onClick={downloadProblems}>Download the rows not imported</Btn></div>
                <DTable cols={["JAMB no|mid", "Name", "Why"]} rows={result.problems.slice(0, 20).map((p) => [
                  <span className="tnum sub2" key="j">{p.jambKey}</span>, <span key="n">{p.name}</span>, <span className="sub2" key="w">{p.status}</span>,
                ])} />
              </>
            ) : <div className="sub2">Every row was imported or already existed. Nothing was rejected.</div>}
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
