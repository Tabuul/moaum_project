import Link from "next/link";
import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { KIND, verifyPathFor, type Statement } from "@/lib/documents";

export const dynamic = "force-dynamic";

interface Consumed { ok: boolean; why?: string; id?: string; kind?: string; number?: string; version?: number; code?: string; issuedOn?: string; statement?: Statement; forKind?: string }

/** /documents/d/{token} — a recipient's secure link (V262): the document opens as a PDF while the token lives; each opening is logged */
export default async function Page({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const t = token.replace(/[^a-f0-9]/gi, "").toLowerCase();
  const r = await api<{ result: string }>(`/api/v1/verify/download/${encodeURIComponent(t)}`);
  const c: Consumed = r.ok ? (JSON.parse(r.data.result) as Consumed) : { ok: false, why: r.problem.title };
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 600, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">Official document — secure link</div></div>
        </div>
        <div className="card__body">
          {c.ok && c.statement ? (
            <>
              <Note kind="ok" title={`${KIND[c.kind ?? ""]?.[0] ?? c.kind} ${c.number ?? ""}`}>Issued to {c.statement.holder} ({c.statement.matricNo}) · {c.statement.programme} · issued {c.issuedOn ? new Date(c.issuedOn).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : ""}. This link expires; the verification reference on the document does not.</Note>
              <div className="row row--tight"><a className="btn btn--primary btn--sm" href={`/documents/d/${t}/pdf`} target="_blank" rel="noopener">Open the document (PDF)</a><Link className="btn btn--ghost btn--sm" href={verifyPathFor(c.code ?? "")}>Verify it against the record</Link></div>
            </>
          ) : (
            <Note kind="bad" title={c.why === "EXPIRED" ? "This link has expired" : c.why === "EXHAUSTED" ? "This link has been used the permitted number of times" : c.why === "REVOKED" || c.why === "REPLACED" ? `The document is ${String(c.why).toLowerCase()}` : "This link is not valid"}>
              The document itself may still be valid: verify it by the reference printed on it at <Link className="lnk" href="/verify/document">/verify/document</Link>. The holder can issue a fresh link from the portal.
            </Note>
          )}
        </div>
      </div>
    </div>
  );
}
