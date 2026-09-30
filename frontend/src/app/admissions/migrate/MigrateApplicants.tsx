"use client";

/** t/migrate — bring the paid applicants over from the old portal (V167), with their email and phone (V296). A spreadsheet of
 *  the applicants who applied and paid — JAMB number, email, phone number — is read in the browser and sent up in small chunks;
 *  each row is created idempotently (a login on the JAMB CAPS record + a submitted, paid application) or, for an applicant
 *  already migrated, given the file's email and phone. The initial password is the JAMB number. The applicant fee must be set
 *  for the session first. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { firstEmail, firstMobile } from "@/lib/contacts";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { Btn, LinkBtn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";

interface Fee { stated: boolean; applicationFee: number; portalCharge: number }
/** the contacts of the session's migrated applicants: how many have a real email and phone (V296) */
export interface Contacts { migrated: number; with_email: number; with_phone: number; without_email: number; without_phone: number; without_both: number }
/** a row of the file: the JAMB number and the email and phone cells as written; the name and programme come from CAPS */
interface Row { jambKey: string; email: string; phone: string }
interface Problem { jambKey: string; name?: string; status: string }
/** a row whose email or phone in the file could not be used, and why (V296) */
interface ContactNote { jambKey: string; outcome: string; email: string; phone: string; emailNote?: string | null; phoneNote?: string | null; emailNow?: string | null; phoneNow?: string | null }
interface Tally { imported: number; updated: number; existed: number; skipped: number; placeholders: number; passportsLinked: number; problems: Problem[]; notes: ContactNote[]; capsRows?: number; capsSample?: string[] }

// the file the office fills: the JAMB number, the applicant's email and phone number (V296)
const COLS = ["JAMB Number", "Email", "Phone Number"];
const EXAMPLE = [["202699168863AH", "adaeze.okafor@example.com", "08031234567"], ["202699168864BC", "terhemba.iorvaa@example.com", "07061234567"]];
const CHUNK = 50;
const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");
const placeholder = (v: string | null | undefined, kind: "email" | "phone") => !v || (kind === "email" ? /@migrate\.moau\.local$/.test(v) : v === "00000000000");

/** find the column index whose header matches any of the needles */
function pick(headers: string[], needles: string[]): number {
  const h = headers.map(norm);
  for (const n of needles) {
    const i = h.findIndex((x) => x.includes(n));
    if (i >= 0) return i;
  }
  return -1;
}

export function MigrateApplicants({ session, fee, contacts, actingOffice }: { session: string; fee: Fee; contacts: Contacts | null; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["academic", "registrar", "dregistrar", "ict", "super"].includes(actingOffice ?? "");
  const [rows, setRows] = useState<Row[] | null>(null);
  const [cols, setCols] = useState<{ email: boolean; phone: boolean }>({ email: false, phone: false });
  const [parallel, setParallel] = useState(6);
  const [fileName, setFileName] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; of: number } | null>(null);
  const [result, setResult] = useState<Tally | null>(null);
  const [resetting, setResetting] = useState(false);
  const [resetInfo, setResetInfo] = useState<{ candidates: number; applications: number; accounts: number; passports_kept: number } | null>(null);
  const [fetching, setFetching] = useState(false);
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
      router.refresh();
    } finally {
      setResetting(false);
    }
  }

  function template() {
    const blob = buildXlsx(COLS, EXAMPLE, "Applicants");
    downloadBlob(blob, "old-portal-applicants-template.xlsx");
  }

  /** the migrated applicants still without a real email or phone, in the template's shape: fill the two columns and upload it */
  async function downloadMissing() {
    setFetching(true);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/import-applicants/contacts?missing=true`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const list = (j?.rows ?? []) as { jambKey: string; email?: string | null; phone?: string | null; name?: string; applicationNo?: string; programme?: string; missing?: string }[];
      if (!list.length) { notify("Every migrated applicant has an email and a phone number"); return; }
      const blob = buildXlsx([...COLS, "Name (from CAPS)", "Application Number", "Programme", "Missing"],
        list.map((x) => [x.jambKey, x.email ?? "", x.phone ?? "", x.name ?? "", x.applicationNo ?? "", x.programme ?? "", x.missing ?? ""]), "Contacts to fill");
      downloadBlob(blob, `applicants-without-contacts-${session.replace(/[^0-9]+/g, "-")}.xlsx`);
    } finally {
      setFetching(false);
    }
  }

  async function read(file: File | undefined) {
    if (!file) return;
    setErr(null); setResult(null); setRows(null); setFileName(file.name);
    try {
      const grid = /\.csv$/i.test(file.name) ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
      if (grid.length < 2) { setErr("The file has no data rows under the header."); return; }
      const head = grid[0];
      const iK = pick(head, ["jamb", "regno", "registration", "reg"]);
      const iE = pick(head, ["email", "mail"]);
      const iH = pick(head, ["phone", "mobile", "gsm", "telephone", "msisdn", "tel"]);
      if (iK < 0) { setErr("The JAMB / registration number column was not found in the header row."); return; }
      // the names, programme and UTME come from the JAMB CAPS list; the file gives the JAMB number, the email and the phone
      const out: Row[] = [];
      for (let r = 1; r < grid.length; r++) {
        const g = grid[r];
        const jambKey = (g[iK] ?? "").trim();
        if (!jambKey) continue;
        out.push({ jambKey, email: iE >= 0 ? (g[iE] ?? "").trim().slice(0, 400) : "", phone: iH >= 0 ? (g[iH] ?? "").trim().slice(0, 200) : "" });
      }
      if (!out.length) { setErr("No row carried a JAMB number."); return; }
      setCols({ email: iE >= 0, phone: iH >= 0 });
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
    const chunks: Row[][] = [];
    for (let i = 0; i < total; i += CHUNK) chunks.push(all.slice(i, i + CHUNK));
    const tally: Tally = { imported: 0, updated: 0, existed: 0, skipped: 0, placeholders: 0, passportsLinked: 0, problems: [], notes: [], capsRows: 0, capsSample: [] };
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
        let j: (Partial<Tally> & { detail?: string; title?: string }) | null = null;
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
          const why = (j && (j.detail || j.title)) || `A chunk kept failing (${r ? `${r.status} ${r.statusText}` : "network"}) after several retries. What imported so far is kept — wait a minute for the server, then run the file again and it skips them.`;
          setErr(String(why)); notify(String(why), "bad");
          return;
        }
        tally.imported += j?.imported ?? 0;
        tally.updated += j?.updated ?? 0;
        tally.existed += j?.existed ?? 0;
        tally.skipped += j?.skipped ?? 0;
        tally.placeholders += j?.placeholders ?? 0;
        tally.capsRows = j?.capsRows ?? tally.capsRows;
        if (Array.isArray(j?.capsSample) && j.capsSample.length) tally.capsSample = j.capsSample;
        for (const p of j?.problems ?? []) tally.problems.push(p);
        for (const n of j?.notes ?? []) tally.notes.push(n);
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
        notify(`${tally.imported} imported · ${tally.updated} given their contacts · ${tally.existed} already on record`);
      }
    } finally {
      setBusy(false);
      router.refresh();   // the contacts panel reads the accounts again
    }
  }

  function downloadProblems() {
    if (!result?.problems.length) return;
    const blob = buildXlsx(["JAMB Number", "Why it was not imported"], result.problems.map((p) => [p.jambKey, p.status]), "Not imported");
    downloadBlob(blob, `applicants-not-imported-${session.replace(/[^0-9]+/g, "-")}.xlsx`);
  }

  function downloadNotes() {
    if (!result?.notes.length) return;
    const blob = buildXlsx(["JAMB Number", "Email in the file", "Why the email was not used", "Phone in the file", "Why the phone was not used", "Email on the account now", "Phone on the account now"],
      result.notes.map((n) => [n.jambKey, n.email, n.emailNote ?? "", n.phone, n.phoneNote ?? "", placeholder(n.emailNow, "email") ? "(none yet)" : n.emailNow ?? "", placeholder(n.phoneNow, "phone") ? "(none yet)" : n.phoneNow ?? ""]),
      "Contacts not used");
    downloadBlob(blob, `applicant-contacts-not-used-${session.replace(/[^0-9]+/g, "-")}.xlsx`);
  }

  const amount = fee.applicationFee + fee.portalCharge;
  // what the file carries, read as the database will read it
  const usableEmail = rows ? rows.filter((r) => firstEmail(r.email)).length : 0;
  const usablePhone = rows ? rows.filter((r) => firstMobile(r.phone)).length : 0;
  const seen = new Map<string, number>();
  for (const r of rows ?? []) { const e = firstEmail(r.email); if (e) seen.set(e, (seen.get(e) ?? 0) + 1); }
  const shared = [...seen.values()].filter((n) => n > 1).length;

  return (
    <>
      <Note kind="info" title="Migrate the applicants who already applied and paid on the old portal">
        The <b>JAMB CAPS list is the source of the applicant&rsquo;s data</b> — name, programme, sex, state, LGA, UTME and
        subjects all come from it, so <b>upload and commit the CAPS list first</b>. This migration <b>confirms the payment,
        creates the login and records the applicant&rsquo;s email and phone number</b>: for each row it finds the applicant on
        the CAPS list by <b>JAMB number</b>, creates their account (initial password = their JAMB number) with the email and
        phone in the file, and writes a confirmed application-fee receipt marked paid and submitted. So the file carries the
        <b> JAMB number, the email and the phone number</b> — download the template; any name or programme column is ignored,
        CAPS is used. An applicant <b>already migrated takes the email and phone in the file</b>, so the same upload fills in
        the contacts of the applicants brought over earlier without them. A JAMB number <b>not on the CAPS list is skipped and
        reported</b>. It is safe to run the same file more than once — nobody is duplicated.
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

      {contacts && Number(contacts.migrated) > 0 ? (
        <Panel title={`Contacts of the migrated applicants · ${session}`} right={Number(contacts.without_email) + Number(contacts.without_phone) ? "Some still without" : "Complete"}>
          <PBody>
            <Tiles items={[
              ["Migrated applicants", Number(contacts.migrated).toLocaleString(), null, "Brought over from the old portal"],
              ["With an email", Number(contacts.with_email).toLocaleString(), Number(contacts.without_email) ? null : "var(--green-ink)", `${Number(contacts.without_email).toLocaleString()} still on a placeholder`],
              ["With a phone number", Number(contacts.with_phone).toLocaleString(), Number(contacts.without_phone) ? null : "var(--green-ink)", `${Number(contacts.without_phone).toLocaleString()} still on a placeholder`],
              ["Without either", Number(contacts.without_both).toLocaleString(), Number(contacts.without_both) ? "var(--red-ink)" : null, "No email, no phone"],
            ]} />
            <div className="row mt-2">
              <Btn kind="secondary" disabled={fetching || !(Number(contacts.without_email) + Number(contacts.without_phone))} onClick={() => void downloadMissing()}>{fetching ? "Preparing…" : "Download the applicants still without an email or phone"}</Btn>
              <span className="sub2">The list comes in the template&rsquo;s shape: fill the Email and Phone Number columns and upload it here. A password reset by email and every notice by email or SMS reach an applicant only once their real contacts are on the account.</span>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Re-run the migration from scratch" right="Clears only the migrated applicants">
        <PBody>
          <div className="sub2 mb-2">
            If applicants were migrated before the CAPS list was uploaded, clear the migration and import the file again so
            every applicant is rebuilt from CAPS. This removes only the migrated <b>candidate / account / application</b>
            records — the CAPS list, O&rsquo;Level results and passports are kept (passports re-link by JAMB number).
            It is not needed to add emails and phone numbers: uploading them updates the applicants already migrated.
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
        <Btn kind="ghost" onClick={template}>Download the template (JAMB Number, Email, Phone Number)</Btn>
        {fileName ? <span className="sub2">{fileName}</span> : null}
      </div></div>

      {err ? <Note kind="bad" title="That file could not be used">{err}</Note> : null}

      {rows ? (
        <>
          <Tiles items={[
            ["Rows read", rows.length.toLocaleString(), null, "Applicants in the file"],
            ["With a usable email", usableEmail.toLocaleString(), usableEmail === rows.length ? "var(--green-ink)" : null, cols.email ? `${(rows.length - usableEmail).toLocaleString()} without one` : "No Email column in the file"],
            ["With a usable phone", usablePhone.toLocaleString(), usablePhone === rows.length ? "var(--green-ink)" : null, cols.phone ? `${(rows.length - usablePhone).toLocaleString()} without one` : "No Phone Number column in the file"],
            ["Receipt amount", fee.stated ? money(amount) : "fallback", fee.stated ? null : "var(--red-ink)", "Per newly imported applicant"],
          ]} />
          {!cols.email || !cols.phone ? (
            <Note kind="bad" title={`The file has no ${!cols.email && !cols.phone ? "Email or Phone Number columns" : !cols.email ? "Email column" : "Phone Number column"}`}>
              The applicants will come over on a placeholder where the file gives no contact. Add the column (download the template for its shape) and upload again; an applicant already migrated takes the contacts then.
            </Note>
          ) : null}
          {shared ? (
            <Note kind="info" title={`${shared.toLocaleString()} email address${shared === 1 ? " appears" : "es appear"} on more than one row`}>
              An email is a way to sign in and to reset the password, so it goes on one applicant&rsquo;s account only: the first row imported takes it, and the others are listed after the import (with their phone numbers still recorded) for the office to give each applicant an address of their own.
            </Note>
          ) : null}
          <Panel title="First rows, as read" right={`${rows.length.toLocaleString()} to verify & confirm`}>
            <PBody><div className="sub2 mb-2">Each JAMB number is verified against the CAPS list; the name, programme, sex, state, LGA and UTME come from CAPS. The email and phone number go on the applicant&rsquo;s login and contact: the first usable email in a cell, and the first Nigerian mobile number (0803…, 803…, +234 803…), as shown here. A cell with neither leaves a placeholder, reported after the import.</div></PBody>
            <DTable
              cols={["JAMB no|mid", "Email in the file", "Read as", "Phone in the file|mid", "Read as|mid"]}
              rows={rows.slice(0, 8).map((r) => {
                const e = firstEmail(r.email);
                const p = firstMobile(r.phone);
                return [
                  <span className="tnum sub2" key="j">{r.jambKey}</span>,
                  <span className="sub2" key="e">{r.email || "—"}</span>,
                  e ? <span key="ee">{e}</span> : <span key="ee" className="ink-chrome sub2">{r.email ? "not usable — placeholder" : "none — placeholder"}</span>,
                  <span className="tnum sub2" key="h">{r.phone || "—"}</span>,
                  p ? <span key="pp" className="tnum">{p}</span> : <span key="pp" className="ink-chrome sub2">{r.phone ? "not usable — placeholder" : "none — placeholder"}</span>,
                ];
              })}
            />
            <PBody>
              <div className="row">
                <Btn kind="primary" disabled={busy || !may} onClick={() => void run()}>{busy ? "Importing…" : `Import ${rows.length.toLocaleString()} applicant${rows.length === 1 ? "" : "s"}`}</Btn>
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
                rows already imported are not duplicated, and take the email and phone in the file.
              </div>
              {progress ? <div className="sub2 mt-2">Done {Math.min(progress.done, progress.of).toLocaleString()} of {progress.of.toLocaleString()}…</div> : null}
            </PBody>
          </Panel>
        </>
      ) : null}

      {result ? (
        <Panel title="Import result" right={busy ? "running…" : "done"}>
          <PBody>
            <Tiles cls="grid--5" items={[
              ["Imported", result.imported.toLocaleString(), "var(--green-ink)", "New accounts created"],
              ["Contacts updated", result.updated.toLocaleString(), result.updated ? "var(--green-ink)" : null, "Already migrated; email or phone added"],
              ["Already on record", result.existed.toLocaleString(), null, "Nothing to change — not duplicated"],
              ["Still on a placeholder", result.placeholders.toLocaleString(), result.placeholders ? "var(--chrome)" : null, "No usable email or phone yet"],
              ["Not imported", result.skipped.toLocaleString(), result.skipped ? "var(--red-ink)" : null, "Bad or unusable rows"],
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
            {result.notes.length ? (
              <>
                <Note kind="info" title={`${result.notes.length.toLocaleString()} row${result.notes.length === 1 ? "" : "s"}: an email or phone in the file was not used`}
                  action={<Btn kind="secondary" onClick={downloadNotes}>Download them</Btn>}>
                  Not an email address, not a Nigerian mobile number, missing from the file, or an email already on another applicant&rsquo;s account (an email signs in one applicant only). Correct them in the file and upload it again; the applicants take the corrected contacts.
                </Note>
                <DTable cols={["JAMB no|mid", "Email", "Phone"]} rows={result.notes.slice(0, 20).map((n) => [
                  <span className="tnum sub2" key="j">{n.jambKey}</span>,
                  <span className="sub2" key="e">{n.emailNote ?? "used"}</span>,
                  <span className="sub2" key="p">{n.phoneNote ?? "used"}</span>,
                ])} />
              </>
            ) : null}
            {result.problems.length ? (
              <>
                <div className="mt-2 mb-2"><Btn kind="ghost" onClick={downloadProblems}>Download the rows not imported</Btn></div>
                <DTable cols={["JAMB no|mid", "Why"]} rows={result.problems.slice(0, 20).map((p) => [
                  <span className="tnum sub2" key="j">{p.jambKey}</span>, <span className="sub2" key="w">{p.status}</span>,
                ])} />
              </>
            ) : <div className="sub2 mt-2">Every row was imported, given its contacts, or already on record. Nothing was rejected.</div>}
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
