"use client";
/** V376: a question's diagram and its options' images — put on, replaced or taken off. Each is a change of the question's content:
 *  a new version, kept whole for the attempts that drew the old one, and waiting for moderation again. PNG or JPEG, at most 1 MB.
 *  Refused while an open examination draws the question (the server's rule). */
import { useState } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { MathText } from "@/components/proto/MathText";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";

export interface ImageQuestion { id: string; stem: string; options: string[]; image_id?: string | null; option_images?: (string | null)[] | null }

const MAX = 1024 * 1024;
const thumb = (id: string) => `/api/bff/api/v1/cbt/questions/images/${id}`;

/** the file as base64, without its data: prefix */
function base64Of(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => { const s = String(r.result ?? ""); resolve(s.slice(s.indexOf(",") + 1)); };
    r.onerror = () => reject(r.error);
    r.readAsDataURL(file);
  });
}

export function QuestionImages({ q, course, onChanged, onClose }: { q: ImageQuestion; course: string; onChanged: () => void; onClose: () => void }) {
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);

  async function call(path: string, body: unknown, reason: string) {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/cbt/questions/${q.id}${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      notify(reason);
      onChanged();
    } finally { setBusy(false); }
  }
  async function upload(file: File | undefined, option: number | null) {
    if (!file) return;
    if (!["image/png", "image/jpeg"].includes(file.type)) { setProblem("Choose a PNG or a JPEG."); return; }
    if (file.size > MAX) { setProblem(`The image is ${Math.round(file.size / 1024)} KB; at most 1 MB. Crop it or save it smaller.`); return; }
    await call("/image", { filename: file.name, contentType: file.type, data: await base64Of(file), option },
      option == null ? `A diagram put on a question in ${course}` : `An image put on option ${String.fromCharCode(65 + option)} of a question in ${course}`);
  }

  const slot = (label: string, image: string | null | undefined, option: number | null) => (
    <div className="row row--inline" style={{ gap: 12, alignItems: "center", borderTop: "1px solid var(--line, #e5e7eb)", padding: "8px 0", flexWrap: "wrap" }}>
      <div style={{ width: 120 }}>
        {image ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={thumb(image)} alt={`${label} image`} style={{ maxWidth: 120, maxHeight: 90, objectFit: "contain", border: "1px solid var(--line, #e5e7eb)", borderRadius: 4 }} />
        ) : <span className="sub2">No image</span>}
      </div>
      <div style={{ flex: 1, minWidth: 180 }}>{label}</div>
      <label className={`btn btn--secondary btn--sm${busy ? " is-disabled" : ""}`} style={{ cursor: "pointer" }}>
        {image ? "Replace" : "Add an image"}
        <input type="file" accept="image/png,image/jpeg" hidden disabled={busy} onChange={(e) => { void upload(e.target.files?.[0], option); e.target.value = ""; }} />
      </label>
      {image ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => void call("/image/remove", { option }, option == null ? `The diagram taken off a question in ${course}` : `The image taken off option ${String.fromCharCode(65 + option)} of a question in ${course}`)}>Remove</Btn> : null}
    </div>
  );

  return (
    <Modal title="Images of the question" sub={course} wide onClose={onClose} foot={<Btn kind="ghost" onClick={onClose}>Close</Btn>}>
      <p><MathText text={q.stem} /></p>
      <div className="sub2 mb-2">PNG or JPEG, at most 1 MB. Each change makes a new version, which waits for moderation again.</div>
      {problem ? <Note kind="bad" title="Not uploaded">{problem}</Note> : null}
      {slot("The question's diagram", q.image_id, null)}
      {q.options.map((o, i) => <div key={i}>{slot(`Option ${String.fromCharCode(65 + i)}: ${o}`, q.option_images?.[i] ?? null, i)}</div>)}
    </Modal>
  );
}
