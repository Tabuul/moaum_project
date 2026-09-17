"use client";

/** t/migrate — bring the paid applicants over from the old portal (V167). A spreadsheet of the ~13,000
 *  who applied and paid is read in the browser, mapped to the columns the importer needs, then sent up in
 *  small chunks; each row is created idempotently (candidate + login + submitted, paid application). The
 *  initial password is the JAMB number. The applicant fee must be set for the session first. */
import { useState } from "react";
import Link from "next/link";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Fee { stated: boolean; applicationFee: number; portalCharge: number }
interface Row { jambKey: string; surname: string; otherNames: string; programme: string; entryMode: string; email: string; phone: string }
interface Problem { jambKey: string; name: string; status: string }

const COLS = ["JAMB Number", "Surname", "Other Names", "Programme", "Entry Mode", "Email", "Phone"];
const CHUNK = 100;
const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

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
  const [fileName, setFileName] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; of: number } | null>(null);
  const [result, setResult] = useState<{ imported: number; existed: number; skipped: number; problems: Problem[] } | null>(null);
  const money = (n: number) => `₦${Number(n).toLocaleString("en-NG")}`;

  function template() {
    const blob = buildXlsx(COLS, [["202699168863AH", "AHUMBE", "Aondofa Kingsley", "B. Sc. ARCHITECTURE", "UTME", "name@example.com", "08030000000"]], "Applicants");
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
      const iP = pick(head, ["programme", "program", "course", "department"]);
      const iM = pick(head, ["entrymode", "entry", "mode"]);
      const iE = pick(head, ["email", "mail"]);
      const iH = pick(head, ["phone", "mobile", "gsm", "telephone", "tel", "msisdn"]);
      const missing = [["JAMB Number", iK], ["Surname", iS], ["Other Names", iO], ["Email", iE], ["Phone", iH]].filter(([, i]) => (i as number) < 0).map(([n]) => n);
      if (missing.length) { setErr(`These columns were not found in the header row: ${missing.join(", ")}. Use the template so the columns are named as the importer expects.`); return; }
      const out: Row[] = [];
      for (let r = 1; r < grid.length; r++) {
        const g = grid[r];
        const jambKey = (g[iK] ?? "").trim();
        if (!jambKey) continue;
        out.push({
          jambKey,
          surname: (g[iS] ?? "").trim(),
          otherNames: (g[iO] ?? "").trim(),
          programme: iP >= 0 ? (g[iP] ?? "").trim() : "",
          entryMode: iM >= 0 ? (g[iM] ?? "").trim() : "UTME",
          email: (g[iE] ?? "").trim(),
          phone: (g[iH] ?? "").trim(),
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
    setBusy(true); setErr(null); setResult(null);
    const tally = { imported: 0, existed: 0, skipped: 0, problems: [] as Problem[] };
    try {
      for (let i = 0; i < rows.length; i += CHUNK) {
        const slice = rows.slice(i, i + CHUNK);
        setProgress({ done: i, of: rows.length });
        const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/import-applicants`, {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old-portal applicants imported for ${session}: rows ${i + 1}–${i + slice.length}`) },
          body: JSON.stringify({ rows: slice }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) { setErr((j && (j.detail || j.title)) || `The import stopped at row ${i + 1}. ${r.status} ${r.statusText}. What was imported before this is kept — you can run the file again and it will skip them.`); return; }
        tally.imported += j.imported ?? 0;
        tally.existed += j.existed ?? 0;
        tally.skipped += j.skipped ?? 0;
        for (const p of (j.problems as Problem[] | undefined) ?? []) tally.problems.push(p);
        setResult({ ...tally });
      }
      setProgress({ done: rows.length, of: rows.length });
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
        Upload the spreadsheet of applicants from the previous portal. Each one is created here as a full applicant
        account, their application is marked <b>paid and submitted</b>, and a confirmed application-fee receipt is written.
        Their <b>initial password is their JAMB number</b> — they change it on first sign-in. It is safe to run the same
        file more than once: an applicant who already has an account is skipped, not duplicated.
      </Note>

      {fee.stated ? (
        <Note kind="ok" title={`The applicant fee is set for ${session}`}>
          Each imported applicant will have a confirmed receipt of <b>{money(amount)}</b> — application fee {money(fee.applicationFee)} + portal charge {money(fee.portalCharge)}.
        </Note>
      ) : (
        <Note kind="bad" title={`The applicant fee is not set for ${session}`}
          action={<Link href="/finance/fees" className="btn btn--urgent btn--sm">Set the fee</Link>}>
          The application fee, portal charge and acceptance fee are not stated for {session}, so imported receipts would use
          the portal’s <b>fallback</b> amounts. Set the applicant fee first, then import, so every receipt shows the right money.
        </Note>
      )}

      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
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
          <Panel title="First rows, as read" right={`${rows.length} to import`}>
            <DTable
              cols={["JAMB no|mid", "Surname", "Other names", "Programme", "Mode|mid", "Email", "Phone|mid"]}
              rows={rows.slice(0, 8).map((r) => [
                <span className="tnum sub2" key="j">{r.jambKey}</span>,
                <strong key="s">{r.surname}</strong>,
                <span className="sub2" key="o">{r.otherNames}</span>,
                <span className="sub2" key="p">{r.programme || "—"}</span>,
                <span className="sub2" key="m">{r.entryMode || "UTME"}</span>,
                <span className="sub2" key="e">{r.email}</span>,
                <span className="tnum sub2" key="h">{r.phone}</span>,
              ])}
            />
            <PBody>
              <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
                <Btn kind="primary" disabled={busy || !may} onClick={() => void run()}>{busy ? "Importing…" : `Import ${rows.length} applicant${rows.length === 1 ? "" : "s"}`}</Btn>
                {!may ? <span className="sub2">Only the Academic Office, Registry or ICT may import.</span> : null}
                {busy ? <span className="sub2">The initial passwords are securely hashed, so this is deliberately slow — leave it running.</span> : null}
              </div>
              {progress ? <div className="sub2" style={{ marginTop: 8 }}>Sent {Math.min(progress.done, progress.of)} of {progress.of}…</div> : null}
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
              ["Not imported", String(result.skipped), result.skipped ? "var(--red-ink)" : null, "Bad or unusable rows"],
              ["Total handled", String(result.imported + result.existed + result.skipped), null, "Rows processed"],
            ]} />
            {result.problems.length ? (
              <>
                <div style={{ margin: "8px 0" }}><Btn kind="ghost" onClick={downloadProblems}>Download the rows not imported</Btn></div>
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
