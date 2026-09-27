"use client";

/** The admission documents, in one place (V282): what may be opened now — viewed, downloaded, printed — and what waits, and after
 *  what. The same component on the applicant's Admission page and in the student's My documents; the rows come from the API. */
import { useEffect, useState } from "react";
import { DTable } from "@/components/proto/DTable";
import { Panel, PBody, Pil } from "@/components/proto/ui";
import { DOC_WORD, GROUP_WORD, docHref, withMode, type AdmissionDocRow } from "@/lib/admission-documents";

export function useAdmissionDocuments(path: string) {
  const [rows, setRows] = useState<AdmissionDocRow[] | null>(null);
  useEffect(() => {
    let live = true;
    fetch(path, { cache: "no-store" })
      .then(async (r) => { const j = await r.json().catch(() => null); if (live) setRows(r.ok && j && Array.isArray(j.rows) ? (j.rows as AdmissionDocRow[]) : []); })
      .catch(() => { if (live) setRows([]); });
    return () => { live = false; };
  }, [path]);
  return rows;
}

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "");

export function AdmissionDocumentsCentre({ rows, side }: { rows: AdmissionDocRow[]; side: "applicant" | "student" }) {
  const now = rows.filter((r) => docHref(r, side) && r.status !== "REVOKED" && r.status !== "NOT_ISSUED");
  const later = rows.filter((r) => !docHref(r, side) || r.status === "NOT_ISSUED");
  const afterGroups = Array.from(new Set(later.map((r) => r.availableAfter ?? "later")));
  return (
    <>
      <Panel title="Admission & screening documents" right={`${now.length} of ${rows.length} available`}>
        {rows.length ? (
          <DTable cols={["Document", "Status|mid", "Action"]} rows={rows.map((r) => {
            const href = docHref(r, side);
            const [word, kind] = DOC_WORD[r.status] ?? [r.status, "grey"];
            return [
              <span key="d"><strong>{r.title}</strong><div className="sub2">{GROUP_WORD[r.group]}{r.number ? ` · No ${r.number}${r.version && r.version > 1 ? ` (v${r.version})` : ""}` : ""}{r.reference ? ` · ${r.reference}` : ""}{r.confirmedAt ? ` · paid ${day(r.confirmedAt)}` : r.issuedOn ? ` · issued ${day(r.issuedOn)}` : ""}</div></span>,
              <Pil key="s" kind={kind}>{word}</Pil>,
              href && r.status !== "REVOKED" ? (
                <span key="a" className="row row--inline row--tight">
                  <a className="btn btn--primary btn--sm" href={href} target="_blank" rel="noopener">View</a>
                  <a className="btn btn--secondary btn--sm" href={withMode(href, "download")} target="_blank" rel="noopener">Download</a>
                  <a className="btn btn--ghost btn--sm" href={withMode(href, "print")} target="_blank" rel="noopener">Print</a>
                </span>
              ) : <span key="a" className="sub2">{r.status === "REVOKED" ? "Revoked; ask the Registry" : r.availableAfter ? `Available ${r.availableAfter}` : "Not yet available"}</span>,
            ];
          })} />
        ) : <PBody><div className="sub2">No document is due yet.</div></PBody>}
      </Panel>
      <Panel title="Required documents & forms" right="Updates itself as you progress">
        <PBody>
          <div className="grid grid--2">
            <div>
              <div className="eyebrow">Available now</div>
              {now.length ? <ul className="plain stack" style={{ gap: 4 }}>{now.map((r) => <li key={r.key} className="row row--tight" style={{ gap: 8 }}><span className="ink-green b700">✓</span><span>{r.title}</span></li>)}</ul> : <div className="sub2">Nothing yet</div>}
            </div>
            <div>
              {afterGroups.length ? afterGroups.map((g) => (
                <div key={g} className="mb-2">
                  <div className="eyebrow">{g.startsWith("not issued") ? "Not issued" : `Available ${g}`}</div>
                  <ul className="plain stack" style={{ gap: 4 }}>{later.filter((r) => (r.availableAfter ?? "later") === g).map((r) => <li key={r.key} className="row row--tight" style={{ gap: 8 }}><span className="sub2">○</span><span className="sub2">{r.title}</span></li>)}</ul>
                </div>
              )) : <div className="sub2">Every document of your admission is available.</div>}
            </div>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
