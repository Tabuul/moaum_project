"use client";

/**
 * t/lecturers — bulk-onboard teaching staff from the "List of teaching staff"
 * sheet (V137), and view the staff on record. Each row becomes a person, a
 * sign-in (username and first password are the staff id P<PNO>, must be changed
 * on first sign-in), the lecturer office scoped to the home department, and an
 * establishment record (sex, first appointment, rank, CONUASS).
 *
 * Sent in small chunks: every sign-in is a bcrypt (cost 12) hash, so one large
 * request would time out. A chunk that fails to send does not stop the rest —
 * the import is idempotent, so uploading again fills any gap. A department not
 * on the register is reported so it can be created first.
 */
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface StaffRow {
  id: string; staff_number: string | null; name: string; email: string | null; phone: string | null;
  present_rank: string | null; sex: string | null; conuass_step: number | null;
  home_department: string | null; departments: string | null;
  has_signin: boolean; must_change: boolean; username: string | null; last_sign_in_at: string | null;
}

const MAY = ["ict", "super", "admin", "registrar", "dregistrar"];
const CHUNK = 25; // bcrypt-12 is ~¼s per row; keep each request short so it never times out

interface Row { pno: string; full_names: string; sex: string; date_first_appointment: string; department: string; present_rank: string; phone: string; conuass: string }
interface Tally { rows: number; created: number; existing: number; credentialed: number; granted: number; records: number; no_department: number; skipped: number; failedRows: number; firstError: string | null; missing: string[] }

export function Lecturers({ actingOffice, staff }: { actingOffice: string | null; staff: StaffRow[] }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tally, setTally] = useState<Tally | null>(null);
  const [search, setSearch] = useState("");

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return q ? staff.filter((s) => s.name.toLowerCase().includes(q) || (s.staff_number ?? "").toLowerCase().includes(q) || (s.departments ?? "").toLowerCase().includes(q)) : staff;
  }, [staff, search]);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONUASS"],
      [["29", "PROF. PAUL AONDONA ANGAHAR (example — delete this row)", "M", "01/12/1992", "ACCOUNTING", "PROFESSOR", "07068010515", "7"]],
      "Teaching staff",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Teaching staff template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function upload(file: File) {
    setProblem(null); setTally(null); setProgress(null);
    let rows: Row[];
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = {
        pno: at(["pno", "staff"]), name: at(["full name", "name"]), sex: at(["sex", "gender"]),
        appt: at(["appt", "appoint", "1st"]), dept: at(["department", "dept"]), rank: at(["rank"]),
        phone: at(["phone", "mobile", "gsm"]), conuass: at(["conuas", "connuas", "conuass"]),
      };
      if (ci.pno < 0 || ci.name < 0 || ci.dept < 0) {
        setProblem({ status: 400, title: "That file needs PNO, Full Names and Department columns.", detail: "Download the template — it matches the List of teaching staff." });
        return;
      }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      rows = grid.slice(1)
        .filter((r) => g(r, ci.pno).replace(/\D/g, "") && !/^pno$/i.test(g(r, ci.pno)))
        .map((r) => ({
          pno: g(r, ci.pno), full_names: g(r, ci.name), sex: g(r, ci.sex),
          date_first_appointment: g(r, ci.appt), department: g(r, ci.dept),
          present_rank: g(r, ci.rank), phone: g(r, ci.phone), conuass: g(r, ci.conuass),
        }));
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet." });
      return;
    }
    if (!rows.length) { setProblem({ status: 400, title: "No teaching staff found in the file." }); return; }

    setBusy(true);
    const sum: Tally = { rows: 0, created: 0, existing: 0, credentialed: 0, granted: 0, records: 0, no_department: 0, skipped: 0, failedRows: 0, firstError: null, missing: [] };
    try {
      const chunks: Row[][] = [];
      for (let i = 0; i < rows.length; i += CHUNK) chunks.push(rows.slice(i, i + CHUNK));
      setProgress({ done: 0, total: rows.length });
      for (const chunk of chunks) {
        try {
          const r = await fetch("/api/bff/api/v1/iam/lecturers/import", {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`${rows.length} teaching staff uploaded`) },
            body: JSON.stringify({ rows: chunk }),
          });
          const j = await r.json().catch(() => null);
          if (!r.ok || !j) { sum.failedRows += chunk.length; if (!sum.firstError && j?.title) sum.firstError = String(j.title); }
          else {
            sum.rows += Number(j.rows ?? 0); sum.created += Number(j.created ?? 0); sum.existing += Number(j.existing ?? 0);
            sum.credentialed += Number(j.credentialed ?? 0); sum.granted += Number(j.granted ?? 0); sum.records += Number(j.records ?? 0);
            sum.no_department += Number(j.no_department ?? 0); sum.skipped += Number(j.skipped ?? 0);
            if (!sum.firstError && j.first_error) sum.firstError = String(j.first_error);
            if (j.missing_departments) for (const d of String(j.missing_departments).split(", ")) if (d && !sum.missing.includes(d)) sum.missing.push(d);
          }
        } catch { sum.failedRows += chunk.length; }   // a chunk that never lands: keep going, the import is idempotent
        setProgress((p) => (p ? { done: Math.min(p.done + chunk.length, p.total), total: p.total } : p));
        setTally({ ...sum, missing: [...sum.missing] });
      }
    } finally {
      setBusy(false);
      setProgress(null);
      router.refresh();   // reload the staff list below
    }
  }

  return (
    <>
      <RoleLine allowed={["ict", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Onboarding teaching staff" />
      <Note kind="info" title="Upload the list of teaching staff, and see who is on record">
        Straight from the <b>List of teaching staff</b>: PNO, full names, sex, date of first appointment, department, present
        rank, phone and CONUASS. Each row becomes a lecturer four ways at once — the person on record; a sign-in where the
        <b> username and first password are both the staff id</b> (the PNO becomes <b>P29</b>, changed on first sign-in); the
        <b> lecturer office at the home department</b>; and the establishment record (sex, appointment, rank, CONUASS). A
        lecturer who teaches another department&rsquo;s course is handled by that department&rsquo;s <b>teaching allocation</b>,
        and every course assigned to them shows on their one dashboard. Re-uploading never duplicates, and a password already
        set is never reset. The department must exist first (add it on the Department upload screen).
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Registry">Your office may not onboard teaching staff.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      {tally ? (
        <>
          <Tiles cls="grid--4" items={[
            ["New staff", String(tally.created), null, "Added to the register"],
            ["Sign-ins issued", String(tally.credentialed), null, "Username & first password = P<PNO>"],
            ["Department grants", String(tally.granted), null, "Lecturer office at the home department"],
            ["Records kept", String(tally.records), null, "Sex · appointment · rank · CONUASS"],
          ]} />
          <Note kind={tally.no_department || tally.skipped || tally.failedRows ? "bad" : "ok"} title={tally.no_department || tally.skipped || tally.failedRows ? "Loaded, with some rows to follow up" : "Teaching staff loaded"}>
            {tally.rows} row(s) read · {tally.created} new · {tally.existing} already on record · {tally.granted} department grant(s)
            {tally.no_department ? ` · ${tally.no_department} with no matching department` : ""}{tally.skipped ? ` · ${tally.skipped} skipped` : ""}.
            {tally.failedRows ? <><br /><b>{tally.failedRows} row(s) did not send</b> (a slow batch). The upload is idempotent — just upload the same file again to fill the gap.</> : null}
            {tally.missing.length ? <><br /><b>Create these departments first, then re-upload:</b> {tally.missing.join(", ")}.</> : null}
            {tally.firstError ? <><br />First problem: {tally.firstError}</> : null}
          </Note>
        </>
      ) : null}

      {may ? (
        <Panel title="Upload teaching staff" right="Person · sign-in · department · establishment">
          <PBody>
            <div className="sub2">
              The file needs <b>PNO</b>, <b>Full Names</b> and <b>Department</b> at least; Sex, Date of 1st Appt, Present Rank,
              Phone and CONUASS are carried when present. The PNO becomes the staff id <b>P&lt;number&gt;</b>.
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginTop: 10 }}>
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--primary btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
                {busy ? "Uploading…" : "Upload teaching staff (.xlsx)"}
                <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
              </label>
              {progress ? <span className="sub2 tnum">Onboarding {progress.done} of {progress.total}…</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Teaching staff on record" right={`${staff.length} lecturer${staff.length === 1 ? "" : "s"}`}>
        <PBody>
          <input className="ctl" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, staff id or department" style={{ maxWidth: 340 }} />
        </PBody>
        {shown.length ? (
          <DTable cols={["Staff id", "Name", "Department", "Rank", "Sign-in"]} rows={shown.slice(0, 500).map((s) => [
            <span className="tnum" key="i" style={{ fontWeight: 700 }}>{s.staff_number ?? "—"}</span>,
            <span key="n">{s.name}{s.sex ? <span className="sub2"> · {s.sex}</span> : null}</span>,
            <span key="d">{s.departments ?? s.home_department ?? "—"}</span>,
            <span key="r" className="sub2">{s.present_rank ?? "—"}{s.conuass_step ? ` · CONUASS ${s.conuass_step}` : ""}</span>,
            s.has_signin
              ? (s.last_sign_in_at ? <Pil kind="ok" key="s">Active</Pil> : s.must_change ? <Pil kind="info" key="s">First password set</Pil> : <Pil kind="ok" key="s">Issued</Pil>)
              : <Pil kind="grey" key="s">No sign-in</Pil>,
          ])} />
        ) : <PBody><div className="sub2">{staff.length ? "No staff match that search." : "No teaching staff on record yet. Upload the list above."}</div></PBody>}
        {shown.length > 500 ? <PBody><div className="sub2">Showing the first 500 of {shown.length}. Narrow the search to find a particular lecturer.</div></PBody> : null}
      </Panel>
    </>
  );
}
