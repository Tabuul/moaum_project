"use client";

/** sSupport — proto/part8.html: your requests, and a new one to an office (V036). */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { onDay, useAct } from "../common";

export interface ServiceRequest { id: string; ref: string; office_code: string; office: string; subject: string; detail: string | null; raised_at: string; state: string; answer: string | null; answered_at: string | null; student?: string; number?: string; answered_by_name?: string | null; documents?: number }

/** read a file as base64 (no data-URI prefix), for the JSON upload the API expects */
function readBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1] ?? "");
    r.onerror = () => reject(new Error("could not read the file"));
    r.readAsDataURL(file);
  });
}

const DOC_TYPES = ["application/pdf", "image/jpeg", "image/png"];

const OFFICES: [string, string][] = [["registrar", "Registry"], ["bursar", "Bursary"], ["ict", "ICT"], ["library", "Library"], ["services", "Student Services"], ["academic", "Academic Office"], ["hod", "My department"], ["housing", "Housing"]];

export function Support({ requests }: { requests: ServiceRequest[] }) {
  const router = useRouter();
  const { act, busy, problem, setProblem } = useAct();
  const [office, setOffice] = useState("registrar");
  const [subject, setSubject] = useState("");
  const [detail, setDetail] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [uploading, setUploading] = useState(false);
  const [said, setSaid] = useState<string | null>(null);

  /** attach the chosen files to a request just raised; a bad file stops that file, not the request */
  async function attachAll(requestId: string, ref: string): Promise<number> {
    let done = 0;
    for (const f of files) {
      if (!DOC_TYPES.includes(f.type) || f.size > 2_097_152) { setProblem({ status: 422, title: `${f.name} was skipped`, detail: "A supporting document is a PDF, JPEG or PNG of at most 2 MB." }); continue; }
      try {
        const b64 = await readBase64(f);
        const r = await fetch(`/api/bff/api/v1/me/requests/${requestId}/documents`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Document ${f.name} on ${ref}`) }, body: JSON.stringify({ filename: f.name, contentType: f.type, contentBase64: b64 }) });
        if (r.ok) done += 1;
        else setProblem((await r.json().catch(() => null)) ?? { status: r.status, title: `${f.name} was not attached` });
      } catch { setProblem({ status: 500, title: `${f.name} could not be read` }); }
    }
    return done;
  }
  return (
    <>
      <Panel title="Your requests" right={requests.length ? `${requests.filter((r) => r.state === "OPEN" || r.state === "WITH_OFFICE").length} open` : "none yet"}>
        {requests.length ? (
          <DTable cols={["Reference", "Subject", "Office", "Raised", "Documents|mid", "Status|num"]} rows={requests.map((r) => [
            <span className="tnum" key="r">{r.ref}</span>,
            <Two key="s" a={r.subject} b={r.answer ? `Answer: ${r.answer}` : r.detail ?? ""} />,
            <span key="o">{r.office}</span>,
            <span className="sub2 tnum" key="d">{onDay(r.raised_at)}</span>,
            r.documents ? <Pil kind="info" key="dc">{r.documents} attached</Pil> : <span className="sub2" key="dc">—</span>,
            r.state === "RESOLVED" || r.state === "CLOSED" ? <Pil kind="ok" key="p">Resolved</Pil> : r.state === "WITH_OFFICE" ? <Pil kind="info" key="p">Answered — still open</Pil> : <Pil kind="info" key="p">With {r.office}</Pil>,
          ])} />
        ) : <PBody><div className="sub2">Nothing raised yet.</div></PBody>}
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {said ? <Note kind="ok" title={said}>You will be notified here and by SMS when it is answered.</Note> : null}
      <Panel title="Raise a new request">
        <PBody>
          <div className="field"><label>Which office?</label>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {OFFICES.map(([c, l]) => <button type="button" key={c} className={`pill ${office === c ? "pill--info" : ""}`} style={office === c ? { cursor: "pointer" } : { background: "var(--bg)", border: "1px solid var(--line)", color: "var(--muted)", cursor: "pointer" }} onClick={() => setOffice(c)}>{l}</button>)}
            </div></div>
          <Field id="hl-problem" label="What is the problem?"><input id="hl-problem" className="ctl" value={subject} onChange={(e) => setSubject(e.target.value)} placeholder="Describe it in one line" autoComplete="off" /></Field>
          <Field id="hl-detail" label="Anything more the office should know" hint="A reference, a date, an amount."><textarea id="hl-detail" className="ctl" rows={3} value={detail} onChange={(e) => setDetail(e.target.value)} /></Field>
          <Field id="hl-docs" label="Supporting documents" hint="Optional. A receipt, a screenshot or a letter — PDF, JPEG or PNG, up to 2 MB each, up to six.">
            <input id="hl-docs" className="ctl" type="file" multiple accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png" onChange={(e) => setFiles(Array.from(e.target.files ?? []).slice(0, 6))} />
          </Field>
          {files.length ? <div className="sub2">{files.length} file{files.length === 1 ? "" : "s"} chosen: {files.map((f) => f.name).join(", ")}</div> : null}
          <div><Btn kind="primary" disabled={busy !== null || uploading || !subject.trim()} onClick={async () => {
            const r = await act("raise", "POST", "/me/requests", { office, subject, detail: detail || null }, `Request to ${office}: ${subject}`);
            if (!r) return;
            let attached = 0;
            if (files.length && typeof r.id === "string") { setUploading(true); try { attached = await attachAll(r.id, String(r.ref)); } finally { setUploading(false); } router.refresh(); }
            setSaid(`Request ${r.ref} is with ${OFFICES.find((o) => o[0] === office)?.[1]}${attached ? ` — ${attached} document${attached === 1 ? "" : "s"} attached` : ""}`);
            notify(`Request ${r.ref} submitted`);
            setSubject(""); setDetail(""); setFiles([]);
          }}>{uploading ? "Attaching…" : "Submit request"}</Btn></div>
          <div className="sub2">Each office answers on the record; the answer appears against the reference above. A document you attach is visible only to you and the office you asked.</div>
        </PBody>
      </Panel>
    </>
  );
}
