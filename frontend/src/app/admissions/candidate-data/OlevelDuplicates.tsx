"use client";

/** V298 · the O'Level upload check's findings for the session: the same exam number again with other grades (V315: a duplicate is the
 *  same exam number; another number is another sitting) held until the Office keeps the result on record or uses the uploaded one in its place; an exam number on another
 *  applicant's record, recorded and open until the verification is recorded; the same result sent again, not recorded twice. The
 *  Office's word always says how it was verified; the database refuses it otherwise. */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { FINDING_STATE, FINDING_WORD, type OlevelDuplicateRegister, type OlevelDuplicateRow } from "@/lib/candidate-data";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const sitting = (body: string, type: string | null | undefined, year: string | null | undefined, series: string | null | undefined, num: string | null | undefined) =>
  [type || body, year, series, num ? `exam no. ${num}` : "no exam number"].filter(Boolean).join(" · ");
const ACTION: Record<"KEEP" | "USE" | "VERIFIED", [string, string]> = {
  KEEP: ["Keep the result on record", "The uploaded result is set aside; the one on record stands."],
  USE: ["Use the uploaded result", "The result on record is removed and the uploaded one recorded in its place; the candidate's eligibility is read again."],
  VERIFIED: ["Record the verification", "The exam number stays on both records; this records what the examining body or the certificates showed."],
};

export function OlevelDuplicates({ session, initial, may }: { session: string; initial: OlevelDuplicateRegister | null; may: boolean }) {
  const [reg, setReg] = useState<OlevelDuplicateRegister | null>(initial);
  const [show, setShow] = useState<"OPEN" | "ALL">("OPEN");
  const [acting, setActing] = useState<{ row: OlevelDuplicateRow; action: "KEEP" | "USE" | "VERIFIED" } | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const rows = reg?.rows ?? [];
  const open = rows.filter((r) => r.state === "HELD" || r.state === "OPEN");
  const shown = show === "OPEN" ? open : rows;
  const count = (k: OlevelDuplicateRow["kind"]) => rows.filter((r) => r.kind === k).length;

  async function decide() {
    if (!acting) return;
    if (!note.trim()) { const pr: Problem = { status: 422, title: "Say how it was verified — with the examining body, the certificate or the result checker." }; setProblem(pr); return; }
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/admissions/sessions/${session}/candidate-data/olevel-duplicates/${acting.row.id}/${acting.action}`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`O'Level upload finding: ${ACTION[acting.action][0]} for ${acting.row.jamb_key}`) }, body: JSON.stringify({ note: note.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return; }
      setReg(j as OlevelDuplicateRegister); setActing(null); setNote("");
      notify(`${ACTION[acting.action][0]} · ${acting.row.jamb_key}`);
    } finally { setBusy(false); }
  }
  async function excel() {
    const head = ["S/N", "JAMB number", "Candidate", "Finding", "State", "Uploaded", "Uploaded subjects", "On record", "On record subjects", "File", "Detected", "Decided", "Note"];
    const body = shown.map((r, i) => [i + 1, r.jamb_key, r.candidate ?? "", FINDING_WORD[r.kind][0], FINDING_STATE[r.state][0], sitting(r.exam_body, r.exam_type_raw, r.exam_year, r.exam_series, r.exam_number), r.subjects ?? "",
      r.kind === "NUMBER_ELSEWHERE" ? `${r.other_candidate ?? ""} ${r.other_jamb_key ?? ""} · ${r.other_exam_year ?? ""} · exam no. ${r.other_exam_number ?? ""}` : `${r.other_exam_year ?? ""} · exam no. ${r.other_exam_number ?? "none"}`,
      r.other_subjects ?? "", r.source_name, when(r.detected_at), r.decided_at ? `${when(r.decided_at)} · ${r.decided_office ?? ""}${r.decided_by ? ` · ${r.decided_by}` : ""}` : "", r.note ?? ""]);
    downloadBlob(await brandedXlsx("Duplicate O'Level Uploads", head, body, { sheetName: "Duplicates", serial: docSerial("OLD"), sub: `${session} · ${show === "OPEN" ? "needing a decision" : "every finding"}` }), `olevel-duplicates-${session.replace("/", "-")}.xlsx`);
  }

  return (
    <Panel title="Duplicate O’Level uploads" right={open.length ? <Pil kind="bad">{open.length} to decide</Pil> : `${rows.length} finding${rows.length === 1 ? "" : "s"}`}>
      <PBody>
        <div className="stack">
          <div className="sub2">Every sitting an upload carries is checked before it is recorded. <b>The same result again</b> — the same examining body and exam number (however it is written), or the same examination with the same grades — is not recorded twice. <b>The same exam number with other grades</b> is held, not recorded, until the Office decides which is the candidate&rsquo;s. Another exam number of the same body — the same year and series or not — is another sitting and is recorded: results are combined across sittings. <b>An exam number already on another applicant&rsquo;s record</b> is recorded and stays open until its verification is recorded.</div>
          {problem && !acting ? <ProblemNotice problem={problem} /> : null}
          <Tiles items={[
            ["Held — same number, other grades", String(rows.filter((r) => r.state === "HELD").length), rows.some((r) => r.state === "HELD") ? "var(--red-ink)" : null, `${count("SAME_SITTING")} found in all`],
            ["Open — shared exam number", String(rows.filter((r) => r.state === "OPEN").length), rows.some((r) => r.state === "OPEN") ? "var(--amber-ink)" : null, `${count("NUMBER_ELSEWHERE")} found in all`],
            ["Same result sent again", String(count("SAME_RESULT")), null, "Not recorded twice"],
            ["Decided", String(rows.filter((r) => ["KEPT", "USED", "VERIFIED"].includes(r.state)).length), null, "With how it was verified"],
          ]} />
          <div className="row row--between">
            <label className="sub2 row row--tight" style={{ gap: 6 }}><input type="checkbox" className="pchk" checked={show === "ALL"} onChange={(e) => setShow(e.target.checked ? "ALL" : "OPEN")} /> Show every finding, the decided and the skipped too</label>
            <Btn kind="secondary" disabled={!shown.length} onClick={() => void excel()}>Excel</Btn>
          </div>
          {shown.length ? (
            <DTable pageSize={25} cols={["Candidate", "Finding", "Uploaded", "On record", "Detected|mid", "State", "|num"]} rows={shown.map((r) => [
              <span key="c"><strong>{r.candidate ?? "Not on a list yet"}</strong><div className="sub2 tnum">{r.jamb_key}</div></span>,
              <Pil key="k" kind={FINDING_WORD[r.kind][1]}>{FINDING_WORD[r.kind][0]}</Pil>,
              <span key="u">{sitting(r.exam_body, r.exam_type_raw, r.exam_year, r.exam_series, r.exam_number)}<div className="sub2">{r.subjects ?? ""}</div><div className="sub2">{r.source_name}</div></span>,
              <span key="o">{r.kind === "NUMBER_ELSEWHERE" ? <><b>{r.other_candidate ?? r.other_jamb_key ?? "—"}</b> <span className="tnum sub2">{r.other_jamb_key ?? ""}</span><div>{r.other_exam_year ?? ""}{r.other_exam_number ? ` · exam no. ${r.other_exam_number}` : ""}</div></>
                : <>{r.other_exam_year ?? "—"}{r.other_exam_number ? ` · exam no. ${r.other_exam_number}` : " · no exam number"}{r.other_on_record === false ? <div className="sub2">no longer on record</div> : null}</>}<div className="sub2">{r.other_subjects ?? ""}</div></span>,
              <span key="d" className="tnum sub2">{when(r.detected_at)}</span>,
              <span key="s"><Pil kind={FINDING_STATE[r.state][1]}>{FINDING_STATE[r.state][0]}</Pil>{r.decided_at ? <div className="sub2">{when(r.decided_at)} · {r.decided_office ?? ""}{r.decided_by ? ` · ${r.decided_by}` : ""}{r.note ? ` — ${r.note}` : ""}</div> : null}</span>,
              <span key="x" className="row row--inline row--tight" style={{ justifyContent: "flex-end" }}>
                {may && r.state === "HELD" ? <><Btn kind="secondary" size="sm" onClick={() => { setNote(""); setProblem(null); setActing({ row: r, action: "KEEP" }); }}>Keep on record</Btn><Btn kind="go" size="sm" onClick={() => { setNote(""); setProblem(null); setActing({ row: r, action: "USE" }); }}>Use uploaded</Btn></> : null}
                {may && r.state === "OPEN" ? <Btn kind="secondary" size="sm" onClick={() => { setNote(""); setProblem(null); setActing({ row: r, action: "VERIFIED" }); }}>Record verification</Btn> : null}
              </span>,
            ])} texts={shown.map((r) => `${r.jamb_key} ${r.candidate ?? ""} ${r.exam_number ?? ""} ${r.other_exam_number ?? ""} ${r.other_jamb_key ?? ""} ${r.exam_body} ${r.exam_year ?? ""}`)} />
          ) : <Note kind="ok" title={rows.length ? "Nothing waits for a decision" : "No duplicate has been found in this session's O’Level uploads"}>{rows.length ? "Tick the box above to see every finding." : "Each upload is checked as it is recorded."}</Note>}
        </div>
      </PBody>
      {acting ? (
        <Modal title={ACTION[acting.action][0]} sub={`${acting.row.candidate ?? acting.row.jamb_key} · ${acting.row.jamb_key}`} onClose={() => setActing(null)}
          foot={<><Btn kind="ghost" onClick={() => setActing(null)}>Back</Btn><span className="grow" /><Btn kind={acting.action === "USE" ? "go" : "primary"} disabled={busy} onClick={() => void decide()}>{ACTION[acting.action][0]}</Btn></>}>
          <div className="stack">
            {problem ? <ProblemNotice problem={problem} /> : null}
            <p>{ACTION[acting.action][1]}</p>
            <div className="sub2"><b>Uploaded:</b> {sitting(acting.row.exam_body, acting.row.exam_type_raw, acting.row.exam_year, acting.row.exam_series, acting.row.exam_number)} — {acting.row.subjects ?? ""}</div>
            <div className="sub2"><b>On record:</b> {acting.row.kind === "NUMBER_ELSEWHERE" ? `${acting.row.other_candidate ?? ""} ${acting.row.other_jamb_key ?? ""} · ` : ""}{acting.row.other_exam_year ?? "—"}{acting.row.other_exam_number ? ` · exam no. ${acting.row.other_exam_number}` : ""} — {acting.row.other_subjects ?? ""}</div>
            <Field id="old-note" label="How it was verified" hint="The examining body, the candidate's certificate or the result checker — it stays on the record" required>
              <textarea id="old-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} />
            </Field>
          </div>
        </Modal>
      ) : null}
    </Panel>
  );
}
