"use client";

/** V622: the Chief Security Officer's signature on the identity cards — the Directorate of ICT sets the officer's name and uploads the
 *  signature (a PNG or JPEG scan on white, at most 1 MB), replaces or removes it; every student and staff card printed after carries it
 *  above the "Chief Security Officer" line. The image is never public: only ICT, the Security Unit and super read it. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";

const API = "/api/bff/api/v1/credentials/identity-cards/signatory";
interface Signatory { title: string; name: string | null; version: number; set_at: string | null; set_office: string | null; has_signature: boolean; set_by_name: string | null; signatureUrl: string | null }

export function CardSignatory({ actingOffice }: { actingOffice: string | null }) {
  const may = ["ict", "super"].includes(actingOffice ?? "");
  const [s, setS] = useState<Signatory | null>(null);
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    if (!may) return;
    let live = true;
    void (async () => {
      const r = await fetch(API, { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (live && r?.ok) { setS(j as Signatory); setName((j as Signatory).name ?? ""); }
    })();
    return () => { live = false; };
  }, [may]);

  if (!may) return null;
  // the form waits for the record, so a name typed early is never overwritten when it arrives
  if (!s) return <Panel title="Identity card signature"><PBody><div className="sub2">Reading the signature on record…</div></PBody></Panel>;

  async function send(method: "PUT" | "DELETE", path: string, body: unknown, reason: string): Promise<Signatory | null> {
    setBusy(true);
    try {
      const r = await fetch(`${API}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return null; }
      setS(j as Signatory);
      return j as Signatory;
    } finally { setBusy(false); }
  }

  async function upload(file: File) {
    setNote(null);
    if (!/^image\/(png|jpeg)$/.test(file.type)) { setNote("The signature must be a PNG or a JPEG."); return; }
    if (file.size > 1_000_000) { setNote("The file is larger than 1 MB. Scan the signature at a smaller size — 600 pixels wide prints sharply on the card."); return; }
    const dataUrl = await new Promise<string>((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(r.error); r.readAsDataURL(file); });
    const j = await send("PUT", "", { name: name.trim() || null, filename: file.name, contentBase64: dataUrl }, "The Chief Security Officer's signature on the identity cards replaced");
    if (j) notify("Signature saved; the next cards printed carry it");
  }

  return (
    <Panel title="Identity card signature" right={s?.has_signature ? <Pil kind="ok">Uploaded · version {s.version}</Pil> : <Pil kind="warn">No signature yet</Pil>}>
      <PBody>
        <div className="sub2">The student and staff identity cards are signed for the University by the {s?.title ?? "Chief Security Officer"}. The signature uploaded here prints above that line on every card printed after.</div>
        <div className="row row--top mt-2" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
          <div style={{ width: 220, height: 80, border: "1px solid var(--line)", borderRadius: 8, background: "#fff", display: "grid", placeItems: "center" }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            {s?.signatureUrl ? <img src={`/api/bff${s.signatureUrl}`} alt={`Signature of the ${s.title}`} style={{ maxWidth: 200, maxHeight: 70, objectFit: "contain" }} /> : <span className="sub2">No signature</span>}
          </div>
          <div className="grow" style={{ minWidth: 260 }}>
            <Field id="cso-name" label={`Name of the ${s?.title ?? "Chief Security Officer"} (printed under the signature)`}>
              <input id="cso-name" className="ctl" value={name} maxLength={120} onChange={(e) => setName(e.target.value)} disabled={busy} placeholder="e.g. Terver A. Iorkyaa" />
            </Field>
            <div className="row mt-2" style={{ gap: "var(--s-2)", flexWrap: "wrap" }}>
              <Btn kind="secondary" size="sm" disabled={busy || name.trim() === (s?.name ?? "")} onClick={async () => { if (await send("PUT", "", { name: name.trim() }, "The Chief Security Officer's name on the identity cards set")) notify("Name saved"); }}>Save the name</Btn>
              <label className="btn btn--primary btn--sm" style={{ cursor: busy ? "default" : "pointer", opacity: busy ? 0.5 : 1 }}>
                {s?.has_signature ? "Replace the signature" : "Upload the signature"}
                <input type="file" accept="image/png,image/jpeg" hidden disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
              </label>
              {s?.has_signature ? <Btn kind="ghost" size="sm" disabled={busy} onClick={async () => { if (await send("DELETE", "/signature", undefined, "The Chief Security Officer's signature removed from the identity cards")) notify("Signature removed; the cards print the line alone"); }}>Remove the signature</Btn> : null}
            </div>
            <div className="sub2 mt-1">A scan of the signature in dark ink on white paper, cropped close to the ink: a PNG or JPEG of at most 1 MB.{s?.set_at ? ` Last changed ${new Date(s.set_at).toLocaleString("en-GB")}${s.set_by_name ? ` by ${s.set_by_name}` : ""}.` : ""}</div>
            {note ? <div className="sub2 mt-1" style={{ color: "var(--red-ink)" }}>{note}</div> : null}
          </div>
        </div>
      </PBody>
    </Panel>
  );
}
