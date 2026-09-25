import Link from "next/link";
import { Note } from "@/components/proto/ui";
import { DOC_STATUS, type Verify } from "@/lib/documents";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const LABEL: Record<string, string> = { holder: "Name", programme: "Programme", award: "Award", classOfDegree: "Class of degree", faculty: "Faculty", department: "Department", graduationSession: "Graduation session", graduationDate: "Graduation date", session: "Session", level: "Level" };

/** the public verification page (V262): a reference or a document number typed or scanned; the University's record answers VALID, REVOKED, REPLACED or NOT FOUND with public fields only */
export function VerifyDocument({ v, keyAsked }: { v: Verify | null; keyAsked: string }) {
  const st = v?.status ?? "";
  const ok = st === "VALID";
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 640, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">University document verification</div></div>
        </div>
        <div className="card__body">
          <form method="get" action="/verify/document" className="row row--tight" style={{ alignItems: "flex-end" }}>
            <div className="field grow"><label className="field__l" htmlFor="vk">Verification reference or document number</label><input id="vk" name="key" className="ctl tnum" defaultValue={keyAsked} placeholder="e.g. 1VHBQ-P4CSE-44M5R-ABV9D-F16AM or CERT/2026/000123" autoComplete="off" /></div>
            <button type="submit" className="btn btn--primary btn--sm">Verify document</button>
          </form>
          {v ? (
            <>
              <Note kind={ok ? "ok" : st === "REPLACED" ? "info" : "bad"} title={ok ? "VALID DOCUMENT — authentic and currently valid" : st === "REVOKED" ? "REVOKED — this document was officially revoked" : st === "REPLACED" ? "REPLACED — a later version of this document is the official one" : st === "NOT_FOUND" ? "NOT FOUND — no document bears this reference" : "INVALID — the document could not be validated"}>
                {ok ? "Authentic verification reference · issued by the University · current status confirmed against the record." : st === "REVOKED" ? `Revoked on ${day(v.revokedOn)}${v.revokedUnder ? ` under ${v.revokedUnder}` : ""}. Treat the document as withdrawn.` : st === "REPLACED" ? `Replaced by ${v.replacedBy ?? "a later version"}. Ask the holder for the current document.` : v.remedy ?? "The reference does not resolve to an issued document."}
              </Note>
              {st !== "NOT_FOUND" && st !== "INVALID" ? (
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: "var(--s-2)" }}>
                  {([["Document type", v.kindLabel ?? v.kind ?? "—"], ["Number", v.number ?? "—"], ["Status", DOC_STATUS[st]?.[0] ?? st], ["Issued on", day(v.issuedOn)], ["Version", String(v.version ?? 1)], ["Issued by", v.issuingAuthority ?? "The Registrar"], ["Issuing institution", v.issuingInstitution ?? ""]] as [string, string][])
                    .concat(Object.keys(LABEL).filter((k) => (v as unknown as Record<string, unknown>)[k] !== undefined && (v as unknown as Record<string, unknown>)[k] !== null).map((k) => [LABEL[k], k === "graduationDate" ? day(String((v as unknown as Record<string, unknown>)[k])) : String((v as unknown as Record<string, unknown>)[k])] as [string, string]))
                    .map(([k, val], i) => <div key={i} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600" style={{ overflowWrap: "anywhere" }}>{val}</div></div>)}
                </div>
              ) : null}
              <div className="sub2">Verified {v.verifiedAt ? new Date(v.verifiedAt).toLocaleString("en-GB") : "now"} · reference {v.verificationCode ?? keyAsked}. Only fields the University has approved for public disclosure are shown.</div>
            </>
          ) : <div className="sub2">Scan the QR code on the document, or type the verification reference or the document number printed on it. No account is needed.</div>}
          <div className="sub2"><Link className="lnk" href="/">The portal</Link></div>
        </div>
      </div>
    </div>
  );
}
