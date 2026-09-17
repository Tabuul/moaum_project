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
/** a row carries either a single `name`, or a `surname`/`otherNames` pair, plus the rest */
interface Row { jambKey: string; name?: string; surname?: string; otherNames?: string; programme: string; entryMode: string; email: string; phone: string }
interface Problem { jambKey: string; name: string; status: string }
type NameOrder = "first" | "last";

const COLS = ["JAMB Number", "Name", "Programme", "Email", "Phone"];
const CHUNK = 100;
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
  const [fileName, setFileName] = useState<string>("");
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; of: number } | null>(null);
  const [result, setResult] = useState<{ imported: number; existed: number; skipped: number; placeholders: number; passportsLinked: number; problems: Problem[] } | null>(null);
  const money = (n: number) => `₦${Number(n).toLocaleString("en-NG")}`;

  function template() {
    const blob = buildXlsx(COLS, [["202699168863AH", "AHUMBE Aondofa Kingsley", "B. Sc. ARCHITECTURE", "name@example.com", "08030000000"]], "Applicants");
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
      const hasSplit = iS >= 0 && iO >= 0;
      if (iK < 0) { setErr("The JAMB / registration number column was not found in the header row."); return; }
      if (!hasSplit && iN < 0) { setErr("No name column was found. Provide either a single “Name” column, or separate “Surname” and “Other Names” columns."); return; }
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
    const tally = { imported: 0, existed: 0, skipped: 0, placeholders: 0, passportsLinked: 0, problems: [] as Problem[] };
    try {
      for (let i = 0; i < rows.length; i += CHUNK) {
        const slice = rows.slice(i, i + CHUNK).map((r) => {
          const { surname, otherNames } = names(r, nameOrder);
          return { jambKey: r.jambKey, surname, otherNames, programme: r.programme, entryMode: r.entryMode, email: r.email, phone: r.phone };
        });
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
        tally.placeholders += j.placeholders ?? 0;
        tally.passportsLinked += j.passportsLinked ?? 0;
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
        Upload the spreadsheet of applicants from the previous portal. Each one is created here as an applicant account,
        their application is marked <b>paid and submitted</b>, and a confirmed application-fee receipt is written. Their
        <b> initial password is their JAMB number</b> — they change it on first sign-in. Only the <b>JAMB number</b> and the
        applicant&rsquo;s <b>name</b> are required — the name may be one <b>Name</b> column (split into surname and other
        names) or separate <b>Surname</b> and <b>Other Names</b> columns. <b>Email and phone are optional</b>: where a row has none, a placeholder stands
        in and the applicant signs in with their JAMB number, then adds their real email and phone in their profile — no
        message is sent to a placeholder. It is safe to run the same file more than once: an applicant who already has an
        account is skipped, not duplicated.
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
          {rows.some((r) => r.name != null) ? (
            <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, alignItems: "flex-end", flexWrap: "wrap" }}>
              <div className="field" style={{ minWidth: 240, margin: 0 }}><label htmlFor="mig-order">Name order in the single Name column</label>
                <select id="mig-order" className="ctl" value={nameOrder} onChange={(e) => setNameOrder(e.target.value as NameOrder)}>
                  <option value="first">Surname first — e.g. AHUMBE Aondofa Kingsley</option>
                  <option value="last">Surname last — e.g. Aondofa Kingsley Ahumbe</option>
                </select>
              </div>
              <span className="sub2">A name written &ldquo;Surname, Other names&rdquo; is split on the comma either way. Check the split below before importing.</span>
            </div></div>
          ) : null}
          <Panel title="First rows, as read" right={`${rows.length} to import`}>
            <DTable
              cols={["JAMB no|mid", "Surname", "Other names", "Programme", "Mode|mid", "Email", "Phone|mid"]}
              rows={rows.slice(0, 8).map((r) => {
                const nm = names(r, nameOrder);
                return [
                  <span className="tnum sub2" key="j">{r.jambKey}</span>,
                  <strong key="s">{nm.surname.toUpperCase()}</strong>,
                  <span className="sub2" key="o">{nm.otherNames}</span>,
                  <span className="sub2" key="p">{r.programme || "—"}</span>,
                  <span className="sub2" key="m">{r.entryMode || "UTME"}</span>,
                  <span className="sub2" key="e">{r.email || <span style={{ color: "var(--chrome)" }}>placeholder</span>}</span>,
                  <span className="tnum sub2" key="h">{r.phone || <span style={{ color: "var(--chrome)" }}>placeholder</span>}</span>,
                ];
              })}
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
              ["On placeholder contacts", String(result.placeholders), result.placeholders ? "var(--chrome)" : null, "Imported; no email/phone yet"],
              ["Not imported", String(result.skipped), result.skipped ? "var(--red-ink)" : null, "Bad or unusable rows"],
            ]} />
            {result.passportsLinked ? (
              <Note kind="ok" title={`${result.passportsLinked} held passport${result.passportsLinked === 1 ? "" : "s"} linked to the imported applicants`}>
                Passports uploaded earlier that had no candidate to attach to have now snapped onto the applicants this import created, matched on the JAMB number.
              </Note>
            ) : null}
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
