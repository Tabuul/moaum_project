"use client";

/** V572: the Registry's and the departments' upload of student phone numbers and e-mail addresses. The students missing a contact
 *  within the office's reach are counted and written into a template; the filled file is previewed row by row (nothing written)
 *  and then loaded, filling only the contacts a student does not hold — a contact held is kept, one another student holds refused. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { csvRows, xlsxRows } from "@/lib/xlsx";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { contactRows, missingWord, OUTCOME, TEMPLATE_HEAD, type ContactLoad, type ContactRow } from "@/lib/contact-upload";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface ContactSummary {
  scope: string; faculty: string | null; department: string | null; missing: number; neither: number; no_phone: number; no_email: number;
  uploads: { id: string; uploaded_at: string; file_name: string | null; office: string; faculty: string | null; department: string | null; rows_read: number;
    students_filled: number; phones_filled: number; emails_filled: number; refused: number; reason: string; uploaded_by: string | null }[];
}

const n = (v: number) => Number(v ?? 0).toLocaleString("en-NG");

async function post(path: string, fileName: string, rows: ContactRow[], reason: string): Promise<ContactLoad | null> {
  const r = await fetch(`/api/bff/api/v1/student-contacts/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify({ fileName, rows }),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }); return null; }
  return j as ContactLoad;
}

export function ContactUpload({ summary }: { summary: ContactSummary }) {
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [file, setFile] = useState<{ name: string; rows: ContactRow[] } | null>(null);
  const [preview, setPreview] = useState<ContactLoad | null>(null);
  const [done, setDone] = useState<ContactLoad | null>(null);

  async function template(neitherOnly: boolean) {
    setBusy(neitherOnly ? "neither" : "all");
    try {
      const r = await fetch(`/api/bff/api/v1/student-contacts/missing${neitherOnly ? "?neitherOnly=true" : ""}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The students could not be read just now." }); return; }
      const list = j as { scope: string; rows: { number: string | null; name: string; faculty: string | null; department: string | null; programme: string | null; level: number | null; no_phone: boolean; no_email: boolean }[] };
      const rows = list.rows.map((s) => [s.number ?? "", s.name, s.faculty ?? "", s.department ?? "", s.programme ?? "", s.level ?? "", missingWord(s.no_phone, s.no_email), "", ""]);
      const blob = await brandedXlsx("Student Contacts", TEMPLATE_HEAD, rows, {
        sub: `${list.scope}: ${neitherOnly ? "no phone and no e-mail" : "a phone or an e-mail missing"}`, serial: docSerial("CONTACT"), sheetName: "Contacts",
      });
      downloadBlob(blob, `student-contacts-${neitherOnly ? "neither" : "missing"}.xlsx`);
    } finally { setBusy(null); }
  }

  async function read(f: File) {
    setBusy("read"); setPreview(null); setDone(null);
    try {
      const isCsv = /\.csv$/i.test(f.name) || f.type === "text/csv";
      const grid = isCsv ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
      const { rows, error } = contactRows(grid);
      if (error) { notifyProblem({ status: 400, title: error, detail: "Download the template to see the columns." }); return; }
      if (rows.length > 20000) { notifyProblem({ status: 400, title: `${n(rows.length)} rows: one upload holds 20,000 at most.`, detail: "Split the file by faculty or department." }); return; }
      setFile({ name: f.name, rows });
      const p = await post("upload/preview", f.name, rows, `Student contacts previewed from ${f.name}: ${rows.length} rows`);
      if (p) setPreview(p);
    } catch {
      notifyProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx template filled in, or a .csv." });
    } finally { setBusy(null); }
  }

  async function confirm() {
    if (!file) return;
    setBusy("load");
    try {
      const d = await post("upload", file.name, file.rows, `Student contacts uploaded from ${file.name}: ${file.rows.length} rows`);
      if (d) {
        notify(`${n(d.counts.FILLED ?? 0)} student${(d.counts.FILLED ?? 0) === 1 ? "" : "s"} given a contact`);
        setDone(d); setPreview(null); setFile(null);
        router.refresh();
      }
    } finally { setBusy(null); }
  }

  const shown = preview ?? done;
  const filled = shown?.counts.FILLED ?? 0;
  const refused = shown ? shown.total - filled - (shown.counts.ALREADY ?? 0) : 0;
  return (
    <div className="stack">
      <Panel title="Students we hold no contact for" right={<span className="sub2">{summary.scope}</span>}>
        <PBody>
          <Tiles cls="grid--4" items={[
            ["No phone and no e-mail", n(summary.neither), summary.neither ? "var(--red-ink)" : null, "They receive no notice and no reset link"],
            ["A contact missing", n(summary.missing), null, "No phone, no e-mail or neither"],
            ["No phone", n(summary.no_phone), null, "No text message reaches them"],
            ["No e-mail", n(summary.no_email), null, "No e-mail or reset link reaches them"],
          ]} />
          <div className="sub2 mt-2">
            The template lists the current students (active, on probation, admitted or deferred) missing a contact, with the Phone and E-mail columns to fill from the class
            lists or the students themselves. Only a contact the student does not hold is filled: one they hold is kept, and a phone or e-mail another student holds is refused.
          </div>
          <div className="row mt-2" style={{ gap: 8, flexWrap: "wrap" }}>
            <Btn kind="secondary" busy={busy === "neither"} busyLabel="Preparing…" disabled={!summary.neither || !!busy} onClick={() => void template(true)}>
              {`Template: no phone and no e-mail (${n(summary.neither)})`}
            </Btn>
            <Btn kind="ghost" busy={busy === "all"} busyLabel="Preparing…" disabled={!summary.missing || !!busy} onClick={() => void template(false)}>
              {`Template: a contact missing (${n(summary.missing)})`}
            </Btn>
            <label className={`btn btn--primary btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
              {busy === "read" ? "Reading…" : "Upload the filled file (.xlsx / .csv)"}
              <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={!!busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
            </label>
          </div>
        </PBody>
      </Panel>

      {shown ? (
        <Panel title={preview ? "Preview — nothing has been written" : "Loaded"} right={<span className="sub2">{file?.name ?? ""}</span>}>
          <PBody>
            <Tiles cls="grid--4" items={[
              ["Rows", n(shown.total), null, shown.scope],
              [preview ? "Students to fill" : "Students filled", n(filled), filled ? "var(--green-ink)" : null, `${n(shown.fields.phones)} phone${shown.fields.phones === 1 ? "" : "s"}, ${n(shown.fields.emails)} e-mail${shown.fields.emails === 1 ? "" : "s"}`],
              ["Held already", n(shown.counts.ALREADY ?? 0), null, "Left as they are"],
              ["Not written", n(refused), refused ? "var(--red-ink)" : null, "See each row's reason"],
            ]} />
            {preview ? (
              <div className="row mt-2" style={{ gap: 8 }}>
                <Btn kind="go" busy={busy === "load"} busyLabel="Loading…" disabled={!!busy || !filled} onClick={() => void confirm()}>
                  {`Fill the contacts of ${n(filled)} student${filled === 1 ? "" : "s"}`}
                </Btn>
                <Btn kind="ghost" disabled={!!busy} onClick={() => { setPreview(null); setFile(null); }}>Cancel</Btn>
              </div>
            ) : null}
          </PBody>
          <DTable title="Each row" pageSize={25} cols={["Row|num", "Student", "Phone", "E-mail", "Outcome|mid", "What happens"]} rows={shown.rows.map((r) => [
            <span key="n" className="tnum sub2">{r.row_no}</span>,
            <span key="s">{r.name ?? <span className="sub2">—</span>}<div className="sub2 tnum">{r.number ?? r.number_in}</div></span>,
            <span key="p" className="tnum">{r.phone ?? r.phone_in}</span>,
            <span key="e">{r.email ?? r.email_in}</span>,
            <Pil key="o" kind={OUTCOME[r.outcome]?.[1] ?? "grey"}>{OUTCOME[r.outcome]?.[0] ?? r.outcome}</Pil>,
            <span key="m" className="sub2">{r.message}</span>,
          ])} texts={shown.rows.map((r) => `${r.number_in} ${r.name ?? ""} ${r.outcome} ${r.message}`)} />
        </Panel>
      ) : null}

      {summary.uploads.length ? (
        <Panel title="Uploads">
          <DTable pageSize={10} cols={["When", "By", "File", "Reach", "Rows|num", "Students filled|num", "Phones|num", "E-mails|num", "Not written|num"]} rows={summary.uploads.map((u) => [
            <span key="w" className="tnum">{new Date(u.uploaded_at).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })}</span>,
            <span key="b">{u.uploaded_by ?? "—"}</span>,
            <span key="f" className="sub2">{u.file_name ?? "—"}</span>,
            <span key="r" className="sub2">{u.department ?? u.faculty ?? "The University"}</span>,
            <span key="n" className="tnum">{n(u.rows_read)}</span>,
            <span key="s" className="tnum">{n(u.students_filled)}</span>,
            <span key="p" className="tnum">{n(u.phones_filled)}</span>,
            <span key="e" className="tnum">{n(u.emails_filled)}</span>,
            <span key="x" className="tnum">{n(u.refused)}</span>,
          ])} />
        </Panel>
      ) : (
        <Note kind="info" title="No upload yet">Uploads made from this page are listed here with what each filled.</Note>
      )}
    </div>
  );
}
