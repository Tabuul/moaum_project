"use client";

/** tInstitution — the official identity every document carries (V320): the name, the short name, the motto, the address and
 *  contacts, the logo, and the document defaults. What is saved here heads every PDF, print and workbook the portal issues
 *  from then on; documents already issued keep the identity they were issued under. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { addressLine, contactLine, formatDocDateTime, nameUpper, type Institution } from "@/lib/document/institution";
import { institutionLogoUrl } from "@/lib/document/institution-client";
import { previewDocument } from "@/lib/document/html";
import { DOCUMENT_PROFILES } from "@/lib/document/profiles";

const SAMPLE_ROWS = Array.from({ length: 60 }, (_, i) => [`MOAUM/SC/CMP/25/${String(70001 + i).padStart(5, "0")}`, ["Adaeze Okafor", "Terhemba Iorfa", "Grace Abah", "Musa Danladi", "Ngozi Eze"][i % 5], 100 + (i % 4) * 100, 40 + ((i * 13) % 60)]);

export function InstitutionProfile({ initial, actingOffice, actorName }: { initial: Institution; actingOffice: string | null; actorName: string | null }) {
  const router = useRouter();
  const may = ["ict", "super", "admin", "registrar", "dregistrar"].includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [inst, setInst] = useState<Institution>(initial);
  const [f, setF] = useState({
    name: initial.name, shortName: initial.shortName, motto: initial.motto ?? "", address: initial.address ?? "", city: initial.city ?? "",
    state: initial.state ?? "", country: initial.country ?? "", phone: initial.phone ?? "", email: initial.email ?? "", website: initial.website ?? "",
    footerNote: initial.footerNote ?? "", showGeneratedBy: initial.showGeneratedBy, showPageNumbers: initial.showPageNumbers, dateFormat: initial.dateFormat,
  });
  const [logoNote, setLogoNote] = useState<string | null>(null);
  const set = (k: keyof typeof f, v: string | boolean) => setF({ ...f, [k]: v });
  const preview: Institution = { ...inst, name: f.name || inst.name, shortName: f.shortName || inst.shortName, motto: f.motto || null, address: f.address || null, city: f.city || null, state: f.state || null, country: f.country || null, phone: f.phone || null, email: f.email || null, website: f.website || null, footerNote: f.footerNote || null, showGeneratedBy: f.showGeneratedBy, showPageNumbers: f.showPageNumbers, dateFormat: f.dateFormat };

  async function send(method: "PUT" | "DELETE", path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setProblem(null);
    try {
      const r = await fetch(path, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
      const j = (await r.json().catch(() => null)) as Record<string, unknown> | null;
      if (!r.ok) { const p = (j as unknown as Problem) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    const j = await send("PUT", "/api/bff/api/v1/platform/institution", {
      name: f.name, shortName: f.shortName, motto: f.motto || null, address: f.address || null, city: f.city || null, state: f.state || null, country: f.country || null,
      phone: f.phone || null, email: f.email || null, website: f.website || null, footerNote: f.footerNote || null,
      showGeneratedBy: f.showGeneratedBy, showPageNumbers: f.showPageNumbers, dateFormat: f.dateFormat,
    }, "Institution profile updated");
    if (j) setInst((cur) => ({ ...cur, ...(j as unknown as Partial<Institution>), logoUrl: (j.logoUrl as string | null) ?? null, logoJpegUrl: (j.logoJpegUrl as string | null) ?? null }));
  }

  async function uploadLogo(file: File) {
    setLogoNote(null);
    if (file.size > 2_000_000) { setLogoNote("The file is larger than 2 MB. Export the logo at 600 pixels on its longest side; it prints sharply on every document."); return; }
    const dataUrl = await new Promise<string>((res, rej) => { const r = new FileReader(); r.onload = () => res(String(r.result)); r.onerror = () => rej(r.error); r.readAsDataURL(file); });
    const j = await send("PUT", "/api/bff/api/v1/platform/institution/logo", { filename: file.name, contentType: file.type, contentBase64: dataUrl }, "Logo replaced");
    if (j) { setInst((cur) => ({ ...cur, logoUrl: (j.logoUrl as string | null) ?? null, logoJpegUrl: (j.logoJpegUrl as string | null) ?? null, logoVersion: Number(j.logoVersion ?? cur.logoVersion + 1) })); setLogoNote(`${file.name} is now the logo on every new document.`); }
  }

  async function clearLogo() {
    const j = await send("DELETE", "/api/bff/api/v1/platform/institution/logo", undefined, "Logo removed; the built-in crest stands");
    if (j) setInst((cur) => ({ ...cur, logoUrl: null, logoJpegUrl: null, logoVersion: Number(j.logoVersion ?? cur.logoVersion + 1) }));
  }

  function sampleReport() {
    void previewDocument("STANDARD_REPORT", {
      title: "Sample report", subtitle: "2025/2026 Academic Session — First Semester", meta: [["Faculty", "Science"], ["Department", "Mathematics and Computer Science"], ["Programme", "B.Sc. Computer Science"], ["Level", "All"], ["Status", "All"]],
      headers: ["Matriculation number", "Name", "Level", "Score"], rows: SAMPLE_ROWS, generatedBy: actorName, reference: `${preview.shortName}/SAMPLE/1`,
      footnote: "A sample: the rows are invented. Every real report prints under this header with the filters it was made with.",
    });
  }

  const logoSrc = `${institutionLogoUrl(inst)}${inst.logoUrl ? `&t=${inst.logoVersion}` : ""}`;
  const missing = [!preview.motto ? "motto" : null, !addressLine(preview) ? "address" : null, !preview.phone && !preview.email ? "a telephone or e-mail" : null, !preview.website ? "website" : null].filter(Boolean);

  return (
    <>
      <Note kind="info" title="One identity, every document">
        Heads every PDF, print and workbook the portal issues. A change reaches only documents issued from now on.
      </Note>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {missing.length ? <Note kind="bad" title={`The header is missing ${missing.join(", ")}`}>Documents print without them.</Note> : null}

      <div className="grid grid--2">
        <Panel title="The University" right={<Pil kind={may ? "ok" : "grey"}>{may ? "You may change this" : "Read only"}</Pil>}>
          <PBody>
            <div className="grid grid--2 rfgrid">
              <Field id="ip-name" label="Name" required full><input id="ip-name" className="ctl" value={f.name} disabled={!may} onChange={(e) => set("name", e.target.value)} /></Field>
              <Field id="ip-short" label="Short name" hint="Heads continuation pages and serials"><input id="ip-short" className="ctl" value={f.shortName} disabled={!may} onChange={(e) => set("shortName", e.target.value)} /></Field>
              <Field id="ip-motto" label="Motto"><input id="ip-motto" className="ctl" value={f.motto} disabled={!may} onChange={(e) => set("motto", e.target.value)} /></Field>
              <Field id="ip-addr" label="Address" full><input id="ip-addr" className="ctl" value={f.address} disabled={!may} onChange={(e) => set("address", e.target.value)} placeholder="P.M.B. …, University Road" /></Field>
              <Field id="ip-city" label="City"><input id="ip-city" className="ctl" value={f.city} disabled={!may} onChange={(e) => set("city", e.target.value)} /></Field>
              <Field id="ip-state" label="State"><input id="ip-state" className="ctl" value={f.state} disabled={!may} onChange={(e) => set("state", e.target.value)} /></Field>
              <Field id="ip-country" label="Country"><input id="ip-country" className="ctl" value={f.country} disabled={!may} onChange={(e) => set("country", e.target.value)} /></Field>
              <Field id="ip-phone" label="Telephone"><input id="ip-phone" className="ctl tnum" value={f.phone} disabled={!may} onChange={(e) => set("phone", e.target.value)} placeholder="+234 …" /></Field>
              <Field id="ip-email" label="E-mail"><input id="ip-email" className="ctl tnum" value={f.email} disabled={!may} onChange={(e) => set("email", e.target.value)} placeholder="info@…" /></Field>
              <Field id="ip-web" label="Website"><input id="ip-web" className="ctl tnum" value={f.website} disabled={!may} onChange={(e) => set("website", e.target.value)} placeholder="https://www.…" /></Field>
            </div>
          </PBody>
        </Panel>
        <Panel title="Document defaults" right="Applied by the central document system">
          <PBody>
            <div className="grid grid--2 rfgrid">
              <Field id="ip-foot" label="Footer note" full hint="A copyright line or a standing notice, on every page"><input id="ip-foot" className="ctl" value={f.footerNote} disabled={!may} onChange={(e) => set("footerNote", e.target.value)} /></Field>
              <Field id="ip-date" label="Date style"><select id="ip-date" className="ctl" value={f.dateFormat} disabled={!may} onChange={(e) => set("dateFormat", e.target.value)}><option value="LONG">04 October 2026</option><option value="SHORT">04/10/2026</option></select></Field>
              <div className="field"><label htmlFor="ip-gen"><input id="ip-gen" type="checkbox" checked={f.showGeneratedBy} disabled={!may} onChange={(e) => set("showGeneratedBy", e.target.checked)} /> Print who generated a report</label></div>
              <div className="field"><label htmlFor="ip-pn"><input id="ip-pn" type="checkbox" checked={f.showPageNumbers} disabled={!may} onChange={(e) => set("showPageNumbers", e.target.checked)} /> Print page numbers (Page X of Y)</label></div>
            </div>
            <div className="row mt-3">
              <Btn kind="primary" disabled={!may || busy || !f.name.trim() || !f.shortName.trim()} onClick={() => void save()}>{busy ? "Saving…" : "Save the profile"}</Btn>
              <span className="sub2">Every change is written to the audit trail in your name.</span>
            </div>
          </PBody>
        </Panel>
      </div>

      <div className="grid grid--2">
        <Panel title="Logo" right={inst.logoUrl ? <Pil kind="ok">Uploaded · version {inst.logoVersion}</Pil> : <Pil kind="grey">Built-in crest</Pil>}>
          <PBody>
            <div className="row row--top">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={logoSrc} alt="Logo" style={{ width: 96, height: 96, objectFit: "contain", border: "1px solid var(--line)", borderRadius: 8, padding: 6, background: "#fff" }} />
              <div className="grow t-sm" style={{ lineHeight: 1.6 }}>
                A PNG (with transparency) or JPEG, at most 2 MB; 600 pixels on the longest side prints sharply.
                <div className="row mt-2">
                  <label className="btn btn--primary btn--sm" style={{ cursor: may ? "pointer" : "default", opacity: may ? 1 : 0.5 }}>
                    {inst.logoUrl ? "Replace the logo" : "Upload a logo"}
                    <input type="file" accept="image/png,image/jpeg" hidden disabled={!may || busy} onChange={(e) => { const file = e.target.files?.[0]; if (file) void uploadLogo(file); e.target.value = ""; }} />
                  </label>
                  {inst.logoUrl ? <Btn kind="ghost" disabled={!may || busy} onClick={() => void clearLogo()}>Back to the built-in crest</Btn> : null}
                </div>
                {logoNote ? <div className="sub2 mt-1">{logoNote}</div> : null}
              </div>
            </div>
          </PBody>
        </Panel>
        <Panel title="How a document will head" right="As the form reads now, before saving">
          <PBody>
            <div style={{ border: "1px solid var(--line)", borderRadius: 8, padding: 14, background: "#fff", color: "#13242d" }}>
              <div style={{ display: "flex", gap: 12, alignItems: "center", borderBottom: "2px solid #0d3f54", paddingBottom: 8 }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={logoSrc} alt="" style={{ width: 48, height: 48, objectFit: "contain" }} />
                <div>
                  <div style={{ fontWeight: 800, color: "#0d3f54", fontSize: 13 }}>{nameUpper(preview)}</div>
                  {preview.motto ? <div style={{ fontStyle: "italic", fontSize: 10.5, color: "#5a6b74" }}>&ldquo;{preview.motto}&rdquo;</div> : null}
                  {addressLine(preview) ? <div style={{ fontSize: 10, color: "#5a6b74" }}>{addressLine(preview)}</div> : null}
                  {contactLine(preview) ? <div style={{ fontSize: 10, color: "#5a6b74" }}>{contactLine(preview)}</div> : null}
                </div>
              </div>
              <div style={{ display: "flex", alignItems: "baseline", gap: 10, marginTop: 8 }}><b style={{ fontSize: 12, letterSpacing: ".04em" }}>RESULT BROADSHEET</b><span style={{ marginLeft: "auto", fontSize: 9, color: "#5a6b74", fontWeight: 700 }}>CONFIDENTIAL</span></div>
              <div style={{ fontSize: 10.5, color: "#5a6b74" }}>B.Sc. Computer Science — 400 Level · 2025/2026 Academic Session — First Semester</div>
              <div style={{ borderTop: "1px solid #c9d3d9", marginTop: 10, paddingTop: 4, fontSize: 9, color: "#6b7b85", display: "flex", justifyContent: "space-between" }}>
                <span>{preview.name} | RESULT BROADSHEET{preview.footerNote ? ` · ${preview.footerNote}` : ""}</span><span>Generated {formatDocDateTime(new Date(), preview)}{preview.showGeneratedBy && actorName ? ` by ${actorName}` : ""}{preview.showPageNumbers ? " · Page 1 of 3" : ""}</span>
              </div>
            </div>
            <div className="row mt-3">
              <Btn kind="primary" onClick={sampleReport}>Preview a sample report (print)</Btn>
              <a className="btn btn--ghost btn--sm" href="/platform/institution/sample/pdf" target="_blank" rel="noopener">Sample report · PDF</a>
            </div>
            
          </PBody>
        </Panel>
      </div>

      <Panel title="Document profiles" right="What each kind of document carries">
        <PBody>
          <div className="grid grid--3">
            {Object.values(DOCUMENT_PROFILES).map((p) => (
              <div key={p.id} className="t-sm" style={{ lineHeight: 1.5 }}>
                <b>{p.id.replace(/_/g, " ")}</b>
                <div className="sub2">{p.title || "Own title"} · {p.orientation} · header {p.header}{p.continuation === "compact" ? ", compact on continuation" : ""} · {p.footer ? (p.pageNumbers ? "footer with page numbers" : "footer") : "no footer"}{p.serialColumn ? " · S/N column" : ""}{p.copy ? ` · ${p.copy}` : ""}{p.confidentiality ? ` · ${p.confidentiality}` : ""}</div>
              </div>
            ))}
          </div>
        </PBody>
      </Panel>
    </>
  );
}
