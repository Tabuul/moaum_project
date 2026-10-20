"use client";

/** V584: the students one contact upload gave a phone or an e-mail to, field by field, with what became of it — still waiting for
 *  the student (with whether a code has been sent), confirmed by the student or at the ICT Support Desk, or said not to be theirs —
 *  so the department chases those who have not answered (in class, or by sending them to sign in). The waiting first; an Excel. */
import { useEffect, useState } from "react";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

type Outcome = "WAITING" | "CONFIRMED" | "DESK" | "REFUSED";
interface Row {
  student_id: string; number: string | null; name: string; programme: string | null; department: string | null; level: number | null;
  field: "EMAIL" | "PHONE"; value: string | null; outcome: Outcome; code_sent: boolean; decided_at: string | null;
}
interface Upload { id: string; uploaded_at: string; file_name: string | null; faculty: string | null; department: string | null; uploaded_by: string | null; rows: Row[] }

const OUTCOME: Record<Outcome, [string, "warn" | "ok" | "bad" | "info"]> = {
  WAITING: ["Waiting for the student", "warn"], CONFIRMED: ["Confirmed by the student", "ok"], DESK: ["Confirmed at the desk", "info"], REFUSED: ["Not theirs", "bad"],
};
const FIELD = { EMAIL: "E-mail", PHONE: "Phone" } as const;
const day = (s: string) => new Date(s).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

export function UploadStudents({ id, onClose }: { id: string; onClose: () => void }) {
  const [data, setData] = useState<Upload | null>(null);
  const [waitingOnly, setWaitingOnly] = useState(true);

  useEffect(() => {
    let alive = true;
    void fetch(`/api/bff/api/v1/student-contacts/uploads/${id}/students`, { cache: "no-store" }).then(async (r) => {
      const j = await r.json().catch(() => null);
      if (!alive) return;
      if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The upload's students could not be read just now." }); onClose(); return; }
      setData(j as Upload);
    });
    return () => { alive = false; };
  }, [id, onClose]);

  if (!data) return null;
  const waiting = data.rows.filter((r) => r.outcome === "WAITING");
  const rows = waitingOnly ? waiting : data.rows;
  const title = `${data.file_name ?? "Upload"} of ${day(data.uploaded_at)}`;

  async function excel() {
    if (!data) return;
    downloadBlob(await brandedXlsx("Uploaded contacts", ["Student", "Number", "Programme", "Department", "Level", "Contact", "Value", "What became of it", "A code sent", "When"],
      rows.map((r) => [r.name, r.number ?? "", r.programme ?? "", r.department ?? "", r.level ?? "", FIELD[r.field], r.value ?? "", OUTCOME[r.outcome][0],
        r.outcome === "WAITING" ? (r.code_sent ? "Yes" : "No") : "", r.decided_at ? day(r.decided_at) : ""]),
      { sheetName: "Students", serial: docSerial("CONTACT"), sub: `${title}${waitingOnly ? ": still waiting" : ""}` }), `uploaded-contacts-${waitingOnly ? "waiting" : "all"}.xlsx`);
  }

  return (
    <Panel title={`Students of ${title}`} right={<Btn kind="ghost" size="sm" onClick={onClose}>Close</Btn>}>
      <PBody>
        <div className="row" style={{ gap: 12, flexWrap: "wrap", alignItems: "center" }}>
          <span className="sub2">
            {waiting.length ? `${waiting.length.toLocaleString("en-NG")} contact${waiting.length === 1 ? "" : "s"} still wait for the student: they confirm it when they sign in (a code is sent to it), or at the ICT Support Desk. No password reset link goes to it meanwhile.`
              : "Every contact from this upload has been answered."}
          </span>
          <label className="sub2 row" style={{ gap: 6 }}>
            <input type="checkbox" checked={waitingOnly} onChange={(e) => setWaitingOnly(e.target.checked)} /> Waiting only
          </label>
          {rows.length ? <Btn kind="ghost" size="sm" busyLabel="Preparing Excel..." onClick={excel}>Excel</Btn> : null}
        </div>
      </PBody>
      <DTable pageSize={25} cols={["Student", "Programme", "Level|num", "Contact", "What became of it", "When"]} rows={rows.map((r) => [
        <span key="n">{r.name}<div className="sub2 tnum">{r.number ?? ""}</div></span>,
        <span key="p" className="sub2">{r.programme ?? "—"}<div>{r.department ?? ""}</div></span>,
        <span key="l" className="tnum">{r.level ?? "—"}</span>,
        <span key="c">{FIELD[r.field]}<div className="sub2 tnum">{r.value ?? ""}</div></span>,
        <span key="o"><Pil kind={OUTCOME[r.outcome][1]}>{OUTCOME[r.outcome][0]}</Pil>{r.outcome === "WAITING" && r.code_sent ? <div className="sub2">A code has been sent</div> : null}</span>,
        <span key="d" className="sub2 tnum">{r.decided_at ? day(r.decided_at) : "—"}</span>,
      ])} texts={rows.map((r) => `${r.name} ${r.number ?? ""} ${r.programme ?? ""} ${r.value ?? ""}`)} />
    </Panel>
  );
}
