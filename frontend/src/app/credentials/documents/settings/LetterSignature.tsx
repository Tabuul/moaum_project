"use client";

/** V759: the signature printed above the signatory's name on the admission letter — a setting, uploaded here (a PNG or JPEG of at
 *  most 1 MB) by the offices that change the document templates, for the signatory the admission letter's template names. Replaced
 *  as a new version, or removed; the audit trail keeps both. An admission letter is drawn with the template in force whenever it is
 *  opened, so every letter, the letters issued earlier included, prints the signature of the signatory that template names; one
 *  kept for a signatory the template in force does not name prints on no letter. The offices that read the templates see it; only
 *  the offices that change them are offered the upload. */
import { useEffect, useRef, useState } from "react";
import type { Problem } from "@/lib/api";
import { callDocs, dayOf } from "@/lib/documents";
import { bytesBase64, entryFor, signatureFileProblem, signatureSrc, type SignatoryEntry } from "@/lib/letter-signature";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";

const LIST = "/api/bff/api/v1/documents/signatures";
const UNREAD: Problem = { status: 503, title: "The signatures could not be read", detail: "The signature on record could not be read just now. Reload the page; if it stays, tell the Directorate of ICT." };

/** the signatories on record, or the problem that stopped the read */
async function readSignatures(): Promise<SignatoryEntry[] | Problem> {
  const r = await fetch(LIST, { cache: "no-store" }).catch(() => null);
  const j: unknown = r ? await r.json().catch(() => null) : null;
  if (r?.ok && Array.isArray(j)) return j as SignatoryEntry[];
  return j && typeof j === "object" && "status" in j ? (j as Problem) : UNREAD;
}

/** who uploaded it and when, as one line */
const setLine = (e: SignatoryEntry) => [e.version ? `Version ${e.version}` : null, e.setAt ? `uploaded ${dayOf(e.setAt)}` : null, e.setByName ? `by ${e.setByName}` : null].filter(Boolean).join(", ");

export function LetterSignature({ signatory, templateVersion, may }: { signatory: string; templateVersion: number | null; may: boolean }) {
  const [entries, setEntries] = useState<SignatoryEntry[] | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [act, setAct] = useState<"upload" | "remove" | null>(null);
  const busy = act !== null;
  const [removing, setRemoving] = useState<SignatoryEntry | null>(null);
  const file = useRef<HTMLInputElement>(null);

  /** the signatures on record; the screen says so when they cannot be read rather than offering an upload over one it cannot see */
  async function load(): Promise<void> {
    const r = await readSignatures();
    if (Array.isArray(r)) setEntries(r); else setProblem(r);
  }
  useEffect(() => {
    let live = true;
    void (async () => {
      const r = await readSignatures();
      if (!live) return;
      if (Array.isArray(r)) setEntries(r); else setProblem(r);
    })();
    return () => { live = false; };
  }, []);

  const cur = entries ? entryFor(entries, signatory) : null;
  const has = !!cur?.hasSignature;
  // a signature still held for a signatory the letter's template in force does not name (the API lists one entry a signatory, so
  // every entry but the letter's is another): no letter prints it while no version names that signatory
  const others = (entries ?? []).filter((e) => e.hasSignature && e !== cur);

  async function upload(f: File) {
    setNote(null); setProblem(null);
    const bad = signatureFileProblem(f, new Uint8Array(await f.slice(0, 8).arrayBuffer()));
    if (bad) { setNote(bad); return; }
    setAct("upload");
    try {
      const contentBase64 = bytesBase64(new Uint8Array(await f.arrayBuffer()));
      const x = await callDocs("PUT", "/documents/signatures", { name: signatory, filename: f.name, contentBase64 }, `The signature of ${signatory} on the admission letter ${has ? "replaced" : "uploaded"}`);
      if (!x.ok) { setProblem(x.problem); return; }
      await load();
      notify(`Signature ${has ? "replaced" : "saved"}: every admission letter that names ${signatory} prints it`);
    } finally { setAct(null); }
  }

  async function remove(e: SignatoryEntry) {
    setNote(null); setProblem(null);
    setAct("remove");
    // the letter's own signatory, or one kept for a signatory no letter names now (removing it changes no letter)
    const printed = e === cur;
    try {
      const x = await callDocs("DELETE", `/documents/signatures?name=${encodeURIComponent(e.name)}`, undefined, `The signature of ${e.name} removed from the admission letter`);
      if (!x.ok) { setRemoving(null); setProblem(x.problem); return; }
      setRemoving(null);
      await load();
      notify(printed ? `Signature removed: the letters that name ${e.name} leave the space for a hand signature` : `Signature of ${e.name} removed. No letter printed it.`);
    } finally { setAct(null); }
  }

  const picture = entries === null
    ? <span className="sub2">{problem ? "The signature on record could not be read." : "Reading the signature on record…"}</span>
    : has && cur
      // eslint-disable-next-line @next/next/no-img-element
      ? <img src={signatureSrc(cur)} alt={`Signature of ${signatory}`} style={{ maxWidth: "100%", maxHeight: 94, objectFit: "contain" }} />
      : <span className="sub2">No signature uploaded: the letter leaves the space for a hand signature</span>;

  return (
    <Panel title="Admission letter signature" right={entries === null ? undefined : has ? <Pil kind="ok">Uploaded · version {cur?.version ?? 1}</Pil> : <Pil kind="warn">No signature</Pil>}>
      <PBody>
        <div className="sub2">The signatory the admission letter names{templateVersion ? ` (template version ${templateVersion})` : ""}</div>
        <div className="b600">{signatory}</div>
        <div className="row row--top mt-2" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
          <div style={{ width: 300, maxWidth: "100%", minHeight: 110, padding: 8, border: "1px solid var(--line)", borderRadius: 8, background: "#fff", display: "grid", placeItems: "center", textAlign: "center" }}>
            {picture}
          </div>
          <div className="grow" style={{ minWidth: 260 }}>
            <div>Printed above the name on every admission letter that names this signatory, including letters already issued. If a later version of the template names someone else, upload that person&apos;s signature.</div>
            {may && entries !== null ? (
              <>
                <div className="row mt-2" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
                  <Btn kind="primary" disabled={busy} busy={act === "upload"} busyLabel="Saving the signature…" onClick={() => file.current?.click()}>{has ? "Replace the signature" : "Upload a signature"}</Btn>
                  {has && cur ? <Btn kind="ghost" disabled={busy} onClick={() => setRemoving(cur)}>Remove the signature</Btn> : null}
                  <input ref={file} type="file" accept="image/png,image/jpeg" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ""; if (f) void upload(f); }} />
                </div>
                <div className="sub2 mt-1">A PNG or JPEG of at most 1 MB, cropped close to the ink. At least 300 pixels wide fills the space; a smaller scan prints smaller. A transparent PNG prints best.</div>
              </>
            ) : null}
            {has && cur ? <div className="sub2 mt-1">{setLine(cur)}</div> : null}
            {note ? <div className="sub2 mt-1" role="alert" style={{ color: "var(--red-ink)" }}>{note}</div> : null}
          </div>
        </div>
        {problem ? <div className="mt-2"><ProblemNotice problem={problem} /></div> : null}
        {others.length ? (
          <div className="mt-3">
            <div className="eyebrow">Other signatures held</div>
            <div className="sub2">Kept for signatories the admission letter&apos;s template in force does not name. They print on no letter now, and print again if a later version of the template names that signatory. Removing one changes no letter.</div>
            {others.map((e) => (
              <div key={e.name} className="row mt-1" style={{ gap: "var(--s-2)", flexWrap: "wrap", alignItems: "center" }}>
                <strong>{e.name}</strong>
                <span className="sub2">{setLine(e)}</span>
                {may ? <Btn kind="ghost" disabled={busy} onClick={() => setRemoving(e)}>Remove</Btn> : null}
              </div>
            ))}
          </div>
        ) : null}
      </PBody>
      {removing ? (
        <Modal title="Remove the signature?" onClose={() => { if (!busy) setRemoving(null); }}
          foot={<><Btn kind="ghost" disabled={busy} onClick={() => setRemoving(null)}>Keep it</Btn><Btn kind="urgent" disabled={busy} busy={act === "remove"} busyLabel="Removing…" onClick={() => remove(removing)}>Remove the signature</Btn></>}>
          {removing === cur
            ? <p>The signature of <strong>{removing.name}</strong> stops printing on every admission letter, the letters already issued included: they print with the space above the name left for a hand signature.</p>
            : <p>The signature of <strong>{removing.name}</strong> prints on no letter now: the admission letter&apos;s template in force names {signatory}. Removing it changes no letter; if a later version names this signatory again, their letters print with the space for a hand signature until a signature is uploaded.</p>}
          <p className="sub2 mt-1">The removal is kept on the audit trail. A signature can be uploaded again at any time.</p>
        </Modal>
      ) : null}
    </Panel>
  );
}
