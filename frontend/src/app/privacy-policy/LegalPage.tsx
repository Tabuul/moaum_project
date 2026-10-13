import Link from "next/link";
import { anchor, blocks, legalDay, type LegalDocument } from "@/lib/legal-text";
import { PrintButton } from "./PrintButton";

/** the one authoritative page of a legal document (V441): the University's letterhead, the version and its dates, a table of
 *  contents that works on a phone, every section with an anchor, the contact block, print styles; a draft is marked as one */
export function LegalPage({ doc, pdfHref, preview }: { doc: LegalDocument; pdfHref: string; preview: boolean }) {
  const inst = doc.institution;
  return (
    <div className="lp">
      <style>{`
        .lp{min-height:100vh;background:var(--bg);padding:var(--s-5) var(--s-3)}
        .lp__doc{max-width:860px;margin:0 auto;background:var(--card,#fff);border:1px solid var(--line);border-radius:12px;overflow:hidden}
        .lp__head{display:flex;gap:16px;align-items:center;padding:20px 24px;border-bottom:3px solid var(--chrome)}
        .lp__head img{width:56px;height:58px;object-fit:contain;flex:none}
        .lp__uni{font-weight:800;letter-spacing:.02em;text-transform:uppercase;color:var(--chrome);font-size:15px;line-height:1.2}
        .lp__sub{color:var(--muted);font-size:13px;margin-top:2px}
        .lp__title{padding:22px 24px 6px;font-size:28px;font-weight:800;line-height:1.15}
        .lp__facts{display:flex;flex-wrap:wrap;gap:8px 22px;padding:0 24px 16px;color:var(--muted);font-size:13px}
        .lp__facts b{color:var(--ink)}
        .lp__tools{display:flex;flex-wrap:wrap;gap:8px;padding:0 24px 18px}
        .lp__summary{margin:0 24px 18px;padding:14px 16px;background:var(--bg);border-left:4px solid var(--chrome);border-radius:6px;font-size:15px;line-height:1.55}
        .lp__toc{margin:0 24px 8px;border:1px solid var(--line);border-radius:8px;padding:12px 16px}
        .lp__toc summary{cursor:pointer;font-weight:700}
        .lp__toc ol{columns:2;column-gap:28px;margin:10px 0 0;padding-left:22px;font-size:14px;line-height:1.7}
        .lp__toc a{color:var(--chrome);text-decoration:none}
        .lp__toc a:hover{text-decoration:underline}
        .lp__s{padding:18px 24px 4px;scroll-margin-top:16px}
        .lp__s h2{font-size:17px;margin:0 0 8px;color:var(--chrome)}
        .lp__s p{margin:0 0 10px;line-height:1.6;font-size:15px}
        .lp__s ul{margin:0 0 10px;padding-left:22px;line-height:1.6;font-size:15px}
        .lp__s li{margin-bottom:4px}
        .lp__foot{margin-top:18px;padding:18px 24px 22px;border-top:1px solid var(--line);background:var(--bg);font-size:13px;color:var(--muted);line-height:1.6}
        .lp__draft{margin:0 24px 14px;padding:10px 14px;border-radius:6px;background:#fff7e6;border:1px solid #f0c36d;color:#7a4b00;font-weight:600}
        @media (max-width:700px){.lp{padding:var(--s-3) var(--s-2)}.lp__toc ol{columns:1}.lp__title{font-size:22px}.lp__head{padding:16px}.lp__s,.lp__facts,.lp__tools,.lp__summary,.lp__toc{padding-left:16px;padding-right:16px;margin-left:0;margin-right:0}.lp__summary,.lp__toc,.lp__draft{margin:0 16px 14px}}
        @media print{.lp{padding:0;background:#fff}.lp__doc{border:0;max-width:none}.lp__tools,.lp__toc summary::marker{display:none}.lp__toc{border:0}.lp__toc ol{columns:2}.lp__s{break-inside:avoid-page}a{color:inherit;text-decoration:none}}
      `}</style>
      <article className="lp__doc">
        <header className="lp__head">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="" />
          <div>
            <div className="lp__uni">{inst.name || "The University"}</div>
            <div className="lp__sub">{[inst.address, inst.website].filter(Boolean).join(" · ")}</div>
          </div>
        </header>
        <h1 className="lp__title">{doc.title}</h1>
        <div className="lp__facts">
          <span>Version <b>{doc.version}</b></span>
          <span>Effective <b>{legalDay(doc.effectiveOn)}</b></span>
          <span>Published <b>{legalDay(doc.publishedAt)}</b></span>
          <span>Last updated <b>{legalDay(doc.updatedAt)}</b></span>
        </div>
        {preview || doc.status !== "PUBLISHED" ? <div className="lp__draft">{doc.status === "PUBLISHED" ? "Preview" : `${doc.status === "DRAFT" ? "Draft" : "Archived version"} — not the published policy`}</div> : null}
        <div className="lp__tools">
          <a className="btn btn--secondary btn--sm" href={pdfHref} target="_blank" rel="noopener">Download PDF</a>
          <PrintButton />
          <Link className="btn btn--ghost btn--sm" href="/login">Sign in</Link>
        </div>
        {doc.summary ? <div className="lp__summary">{doc.summary}</div> : null}
        <details className="lp__toc" open>
          <summary>Contents</summary>
          <ol>
            {doc.sections.map((s) => <li key={s.key}><a href={`#${anchor(s)}`}>{s.heading}</a></li>)}
          </ol>
        </details>
        {doc.sections.map((s) => (
          <section className="lp__s" id={anchor(s)} key={s.key}>
            <h2>{s.no}. {s.heading}</h2>
            {blocks(s.body).map((b, i) => b.kind === "p"
              ? <p key={i}>{b.text}</p>
              : <ul key={i}>{b.items.map((it, j) => <li key={j}>{it}</li>)}</ul>)}
          </section>
        ))}
        <footer className="lp__foot">
          <div><b>{inst.name}</b>{inst.address ? ` · ${inst.address}` : ""}{inst.phone ? ` · ${inst.phone}` : ""}{inst.email ? ` · ${inst.email}` : ""}</div>
          <div>Privacy contact: {[doc.contact.name, doc.contact.title, doc.contact.office].filter(Boolean).join(", ") || "the University's privacy office"}{doc.contact.email ? ` · ${doc.contact.email}` : ""}{doc.contact.phone ? ` · ${doc.contact.phone}` : ""}</div>
          <div>{doc.title} · version {doc.version} · effective {legalDay(doc.effectiveOn)}</div>
        </footer>
      </article>
    </div>
  );
}

/** before any version is published: what the visitor is told, and whom to ask */
export function LegalPending({ title, institution }: { title: string; institution: { name?: string | null; email?: string | null; phone?: string | null } | null }) {
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 640 }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow">{institution?.name ?? "The University"}</div><div className="phead__t ink-chrome">{title}</div></div>
        </div>
        <div className="card__body">
          <p style={{ marginTop: 0 }}>The University&apos;s {title} is being finalised and will be published here. Until then, questions about your personal information go to the University{institution?.email ? ` at ${institution.email}` : ""}{institution?.phone ? ` or ${institution.phone}` : ""}.</p>
          <Link className="btn btn--ghost btn--sm" href="/login">Sign in</Link>
        </div>
      </div>
    </div>
  );
}
