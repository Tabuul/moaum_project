"use client";

/** The register of issued documents (V262): every certificate and transcript with its number, version, status, holder, downloads
 *  and verifications; a document opened with its trail and its versions; revoked by the Registrar with the instrument; reissued as
 *  a new version with the old kept; a flag cleared after review; the verification log. */
import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, KvGrid, LinkBtn, PageHead, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DOC_STATUS, EVENT_WORDS, KIND, callDocs, dayOf, verifyPathFor, whenAt, type DocumentFull, type DocumentRow } from "@/lib/documents";
import type { RegFilters, RegList } from "./page";

const OFFICE = ["academic", "registrar", "dregistrar", "records"];
const SIGNERS = ["registrar", "dregistrar", "academic"];
const REVOKERS = ["registrar", "vc"];

export function Register({ list, filters, verifications, office }: { list: RegList; filters: RegFilters; verifications: { key: string; status: string; kind: string | null; at: string; ip: string | null; number: string | null; student_name: string | null }[]; office: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = !!office && OFFICE.includes(office);
  const signer = !!office && SIGNERS.includes(office);
  const revoker = !!office && REVOKERS.includes(office);
  const [q, setQ] = useState(filters.q);
  const [tab, setTab] = useState<"documents" | "verifications">("documents");
  const [doc, setDoc] = useState<DocumentFull | null>(null);
  const [ask, setAsk] = useState<"revoke" | "reissue" | null>(null);
  const [reason, setReason] = useState("");
  const [instrument, setInstrument] = useState("");
  const [busy, setBusy] = useState(false);
  const rows = list.rows;
  const go = (next: Partial<RegFilters>) => { const f = { ...filters, ...next, page: next.page ?? "" }; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/credentials/documents/register?${qs}`); };
  const pages = Math.max(1, Math.ceil(list.total / list.size));

  async function open(id: string) {
    const x = await callDocs<DocumentFull>("GET", `/documents/issued/${id}`, undefined, "Open an issued document");
    if (!x.ok) { notifyProblem(x.problem); return; }
    setDoc(x.data);
  }
  async function act() {
    if (!doc) return;
    if (!reason.trim() || (ask === "revoke" && !instrument.trim())) { notifyProblem({ status: 422, title: ask === "revoke" ? "A revocation carries its reason and the minute it rests on." : "A reissue carries its reason." }); return; }
    setBusy(true);
    try {
      const x = ask === "revoke" ? await callDocs("POST", `/documents/issued/${doc.id}/revoke`, { reason: reason.trim(), instrument: instrument.trim() }, `Revoke ${doc.number}: ${reason.trim()}`)
        : await callDocs<{ version: number }>("POST", `/documents/issued/${doc.id}/reissue`, { reason: reason.trim() }, `Reissue ${doc.number}: ${reason.trim()}`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      notify(ask === "revoke" ? "Document revoked; verification now answers REVOKED" : `Reissued as version ${(x.data as { version: number }).version}`); setAsk(null); setReason(""); setInstrument(""); setDoc(null); router.refresh();
    } finally { setBusy(false); }
  }
  async function clearFlag() {
    if (!doc) return;
    const x = await callDocs("POST", `/documents/issued/${doc.id}/clear-flag`, { reason: "Reviewed; the document stands" }, `Clear the flag on ${doc.number}`);
    if (!x.ok) { notifyProblem(x.problem); return; }
    notify("Flag cleared"); setDoc(null); router.refresh();
  }
  const HEAD = ["S/N", "Document Type", "Number", "Version", "Student ID", "Student Name", "Programme", "Faculty", "Award", "Issued", "Status", "Verification Reference", "Downloads", "Verifications"];
  const body = () => rows.map((r, i) => [i + 1, r.kind_label, r.number ?? "", r.version, r.student_number ?? "", r.student_name ?? r.holder ?? "", r.programme ?? "", r.faculty ?? "", r.award ?? "", dayOf(r.issued_on), DOC_STATUS[r.status]?.[0] ?? r.status, r.verification_code, r.downloads, r.verifications]);
  async function excel() { const blob = await brandedXlsx("Issued Documents", HEAD, body(), { sheetName: "Documents", serial: docSerial("DOC") }); downloadBlob(blob, "issued-documents.xlsx"); }
  const VHEAD = ["S/N", "When", "Key", "Result", "Document", "Holder", "Source"];
  const vbody = () => verifications.map((v, i) => [i + 1, whenAt(v.at), v.key, v.status, v.number ?? "", v.student_name ?? "", v.ip ?? ""]);

  return (
    <>
      <div className="row row--tight sub2" style={{ gap: 6 }}><Link className="lnk" href="/credentials/documents">Documents office</Link><span>›</span><strong>Issued documents</strong></div>
      <PageHead title="Issued documents" description={`${list.total.toLocaleString()} document(s), names A–Z. Each opens with its versions, its trail, its downloads and its verifications.`}
        actions={<>{tab === "documents" ? <><Btn kind="secondary" onClick={() => void excel()} disabled={!rows.length}>Excel</Btn><Btn kind="ghost" onClick={() => brandedPrint("Issued Documents", "", HEAD, body(), docSerial("DOC"))} disabled={!rows.length}>PDF</Btn></> : <Btn kind="secondary" onClick={() => brandedPrint("Document Verifications", "Last 100", VHEAD, vbody(), docSerial("DOC"))} disabled={!verifications.length}>PDF</Btn>}<LinkBtn kind="ghost" href="/credentials/documents">Back to the office</LinkBtn></>} />
      <Tabs value={tab} onChange={setTab} items={[{ id: "documents", label: `Documents (${list.total})` }, { id: "verifications", label: `Verification log (${verifications.length})` }]} />
      {tab === "documents" ? (
        <>
          <div className="scope">
            <div className="scope__f"><Field id="rg-kind" label="Kind"><select id="rg-kind" className="ctl" value={filters.kind} onChange={(e) => go({ kind: e.target.value })}><option value="">Every kind</option>{Object.entries(KIND).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></Field></div>
            <div className="scope__f"><Field id="rg-st" label="Status"><select id="rg-st" className="ctl" value={filters.status} onChange={(e) => go({ status: e.target.value })}><option value="">Any</option><option value="ACTIVE">Valid</option><option value="REVOKED">Revoked</option><option value="REPLACED">Replaced</option></select></Field></div>
            <div className="scope__f"><Field id="rg-fl" label="Flagged"><select id="rg-fl" className="ctl" value={filters.flagged} onChange={(e) => go({ flagged: e.target.value })}><option value="">All</option><option value="true">Flagged only</option></select></Field></div>
            <form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><Field id="rg-q" label="Search"><input id="rg-q" className="ctl" placeholder="Name, student ID, number, verification code, request" value={q} onChange={(e) => setQ(e.target.value)} /></Field><Btn kind="secondary" type="submit">Search</Btn></form>
          </div>
          <Panel title={`${list.total.toLocaleString()} document(s)`} right={pages > 1 ? <span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => go({ page: String(list.page - 1) })} disabled={list.page <= 0}>Previous</Btn><span className="sub2">Page {list.page + 1} of {pages}</span><Btn kind="ghost" onClick={() => go({ page: String(list.page + 1) })} disabled={list.page + 1 >= pages}>Next</Btn></span> : "Names A–Z"}>
            {rows.length ? <DTable pageSize={0} cols={["S/N|num", "Document", "Holder", "Programme", "Issued|mid", "Status|mid", "Verification|mid", "Activity|num", "|num"]} rows={rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{list.page * list.size + i + 1}</span>,
              <span key="d"><strong>{r.kind_label}</strong> <span className="tnum sub2">{r.number}</span>{r.version > 1 ? <span className="sub2"> · v{r.version}</span> : null}{r.flagged_at ? <div><Pil kind="warn">Flagged</Pil> <span className="sub2">{r.flag_reason}</span></div> : null}</span>,
              <span key="h"><strong>{r.student_name ?? r.holder}</strong><div className="sub2 tnum">{r.student_number ?? ""}</div></span>,
              <span key="p">{r.programme ?? ""}<div className="sub2">{r.award ?? ""}{r.class_of_degree ? ` · ${r.class_of_degree}` : ""}</div></span>,
              <span key="i" className="tnum sub2">{dayOf(r.issued_on)}</span>,
              <Pil key="s" kind={DOC_STATUS[r.status]?.[1] ?? "grey"}>{DOC_STATUS[r.status]?.[0] ?? r.status}</Pil>,
              <Link key="v" className="lnk tnum" href={verifyPathFor(r.verification_code)}>{r.verification_code}</Link>,
              <span key="a" className="tnum sub2">{r.downloads} dl · {r.verifications} ver</span>,
              <span key="o" className="row row--inline row--tight"><Btn kind="primary" onClick={() => void open(r.id)}>Open</Btn>{r.status === "ACTIVE" ? <a className="btn btn--ghost btn--sm" href={`/credentials/documents/register/${r.id}/pdf`} target="_blank" rel="noopener">PDF</a> : null}</span>,
            ])} texts={rows.map((r) => `${r.student_name ?? ""} ${r.student_number ?? ""} ${r.number ?? ""} ${r.verification_code} ${r.kind_label}`)} /> : <PBody><div className="sub2">No document matches.</div></PBody>}
          </Panel>
        </>
      ) : (
        <Panel title="Verifications by strangers, newest first" right="Public page and QR scans">
          {verifications.length ? <DTable pageSize={50} cols={["When|mid", "Key", "Result|mid", "Document", "Holder", "Source|mid"]} rows={verifications.map((v) => [<span key="w" className="tnum sub2">{whenAt(v.at)}</span>, <span key="k" className="tnum">{v.key}</span>, <Pil key="s" kind={DOC_STATUS[v.status]?.[1] ?? "grey"}>{DOC_STATUS[v.status]?.[0] ?? v.status}</Pil>, <span key="d" className="tnum sub2">{v.number ?? ""}{v.kind ? ` · ${KIND[v.kind]?.[0] ?? v.kind}` : ""}</span>, <span key="h" className="sub2">{v.student_name ?? ""}</span>, <span key="ip" className="sub2 tnum">{v.ip ?? ""}</span>])} /> : <PBody><div className="sub2">No verification yet.</div></PBody>}
        </Panel>
      )}

      {doc ? (
        <Modal title={`${doc.kind_label} ${doc.number ?? ""}`} sub={`${doc.student_name ?? doc.holder} · ${doc.student_number ?? ""} · version ${doc.version} · ${DOC_STATUS[doc.status]?.[0] ?? doc.status}`} wide onClose={() => setDoc(null)}
          foot={<>{may && doc.flagged_at ? <Btn kind="secondary" onClick={() => void clearFlag()}>Clear the flag</Btn> : null}{signer && doc.status === "ACTIVE" ? <Btn kind="secondary" onClick={() => { setReason(""); setAsk("reissue"); }}>Reissue (new version)</Btn> : null}{revoker && doc.status === "ACTIVE" ? <Btn kind="urgent" onClick={() => { setReason(""); setInstrument(""); setAsk("revoke"); }}>Revoke</Btn> : null}<Btn kind="ghost" onClick={() => setDoc(null)}>Close</Btn></>}>
          <KvGrid cls="grid--3" pairs={[["Verification code", <Link key="v" className="lnk tnum" href={verifyPathFor(doc.verification_code)}>{doc.verification_code}</Link>], ["Issued", `${dayOf(doc.issued_on)} · ${doc.issued_office}`], ["Template", `version ${doc.template_version ?? "—"}`], ["Award", doc.award ?? "—"], ["Class", doc.class_of_degree ?? "—"], ["Session", doc.graduation_session ?? "—"], ["Request", doc.request_ref ?? "—"], ["Downloads", String(doc.downloads)], ["Verifications", String(doc.verifications)]]} />
          {doc.flagged_at ? <div className="mt-2"><Pil kind="warn">Flagged {whenAt(doc.flagged_at)}</Pil> <span className="sub2">{doc.flag_reason}</span></div> : null}
          {doc.revoked_on ? <div className="mt-2"><Pil kind="bad">Revoked {dayOf(doc.revoked_on)}</Pil> <span className="sub2">{doc.revoked_reason}</span></div> : null}
          {doc.versions?.length ? <Panel title="Versions"><DTable cols={["Version|mid", "Code", "Issued|mid", "Status|mid", "Note"]} rows={doc.versions.map((v) => [<span key="v" className="tnum">v{v.version}</span>, <span key="c" className="tnum">{v.verification_code}</span>, <span key="i" className="tnum sub2">{dayOf(v.issued_on)}</span>, <Pil key="s" kind={DOC_STATUS[v.status]?.[1] ?? "grey"}>{DOC_STATUS[v.status]?.[0] ?? v.status}</Pil>, <span key="n" className="sub2">{v.note ?? ""}</span>])} /></Panel> : null}
          {doc.events?.length ? <Panel title="Trail"><DTable cols={["When|mid", "Step", "Note", "By"]} rows={doc.events.map((e) => [<span key="w" className="tnum sub2">{whenAt(e.at)}</span>, <strong key="a">{EVENT_WORDS[e.action] ?? e.action.toLowerCase()}</strong>, <span key="n" className="sub2">{e.note ?? ""}</span>, <span key="b" className="sub2">{e.actor ?? e.actor_office ?? "portal"}</span>])} /></Panel> : null}
          {doc.downloadsLog?.length || doc.verificationsLog?.length ? <div className="sub2 mt-2">Downloads: {(doc.downloadsLog ?? []).slice(0, 8).map((l) => `${l.kind.toLowerCase()} ${whenAt(l.at)}`).join(", ") || "none"} · Verifications: {(doc.verificationsLog ?? []).slice(0, 8).map((l) => `${l.status.toLowerCase()} ${whenAt(l.at)}`).join(", ") || "none"}</div> : null}
        </Modal>
      ) : null}
      {ask && doc ? (
        <Modal title={ask === "revoke" ? `Revoke ${doc.number}` : `Reissue ${doc.number}`} onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind={ask === "revoke" ? "urgent" : "primary"} onClick={() => void act()} disabled={busy}>{ask === "revoke" ? "Revoke" : "Reissue"}</Btn></>}>
          <p>{ask === "revoke" ? "The record is kept; verification answers REVOKED with the date and the instrument; every secure link is withdrawn; the holder is told. Only the Registrar or the Vice-Chancellor revokes, and only citing a Senate or Council minute." : "A new version is generated from the record as it now stands, with a new verification code under the same number; the old version is kept and verifies as REPLACED; the holder is told."}</p>
          <Field id="ac-r" label="Reason" required full><textarea id="ac-r" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field>
          {ask === "revoke" ? <Field id="ac-i" label="Instrument (the minute)" required><input id="ac-i" className="ctl" value={instrument} onChange={(e) => setInstrument(e.target.value)} placeholder="SEN/2026/118" /></Field> : null}
        </Modal>
      ) : null}
    </>
  );
}
