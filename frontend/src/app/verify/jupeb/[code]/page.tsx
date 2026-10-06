import Link from "next/link";
import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";
import { FEE_KIND, PAPER_KIND } from "@/lib/jupeb";

export const dynamic = "force-dynamic";

type Facts = Record<string, unknown>;
interface V {
  genuine: boolean; revoked?: boolean; revokedOn?: string; code?: string; kind?: string; issuedOn?: string; facts?: Facts;
  current?: boolean; currentFacts?: Facts | null; withdrawn?: boolean; deferred?: boolean;
}

const day = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const naira = (v: unknown) => (v == null ? "—" : "₦" + Number(v).toLocaleString("en-NG", { maximumFractionDigits: 2 }));
const STATUS: Record<string, string> = { ADMITTED: "Admitted", NOT_ADMITTED: "Not admitted", PENDING: "Pending", PROCESSING: "Processing", REQUIRES_REVIEW: "Requires review" };

/** the facts a paper printed, as rows — only what the paper itself shows */
function rows(f: Facts | null | undefined): [string, string][] {
  if (!f) return [];
  const out: [string, string][] = [];
  const add = (k: string, label: string, fmt: (v: unknown) => string = (v) => String(v)) => { if (f[k] != null && f[k] !== "") out.push([label, fmt(f[k])]); };
  add("name", "Name"); add("applicationNo", "Application number"); add("examNo", "JUPEB examination number"); add("session", "Session");
  add("programme", "Programme"); add("combination", "Subject combination"); add("examination", "Examination");
  add("submittedOn", "Submitted", day); add("admissionStatus", "Admission status", (v) => STATUS[String(v)] ?? String(v)); add("admissionRef", "Admission reference");
  add("admittedOn", "Admitted on", day); add("acceptedOn", "Accepted on", day); add("registeredOn", "Subjects registered", day);
  add("subjects", "Subjects", (v) => (Array.isArray(v) ? v.join(", ") : String(v))); add("gradePoint", "Grade point");
  add("reference", "Payment reference"); add("fee", "Fee", (v) => FEE_KIND[String(v)] ?? String(v)); add("amount", "Amount", naira); add("paidOn", "Paid on", day);
  return out;
}

function Facts({ f }: { f: Facts | null | undefined }) {
  const grades = Array.isArray(f?.grades) ? (f?.grades as { subject: string; grade: string }[]) : [];
  return (
    <>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(170px, 1fr))", gap: "var(--s-2)" }}>
        {rows(f).map(([k, v]) => (
          <div key={k} style={{ padding: "var(--s-2)", border: "1px solid var(--line)", borderRadius: "var(--r-sm)" }}><div className="eyebrow">{k}</div><div className="b600">{v}</div></div>
        ))}
      </div>
      {grades.length ? (
        <table className="tbl mt-2" style={{ width: "100%" }}>
          <thead><tr><th style={{ textAlign: "left" }}>Subject</th><th>Grade</th></tr></thead>
          <tbody>{grades.map((g) => <tr key={g.subject}><td>{g.subject}</td><td style={{ textAlign: "center" }}><b>{g.grade}</b></td></tr>)}</tbody>
        </table>
      ) : null}
    </>
  );
}

/** /verify/jupeb/{code} — the public verification of a JUPEB paper (V343): the QR on the paper opens the University's record */
export default async function Page({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const r = await api<V>(`/api/v1/verify/jupeb/${encodeURIComponent(code)}`);
  const v: V = r.ok ? r.data : { genuine: false };
  const what = v.kind ? PAPER_KIND[v.kind] ?? v.kind : "JUPEB paper";
  const verdict: [kind: "ok" | "bad" | "info", title: string, text: string] = !v.genuine
    ? v.revoked
      ? ["bad", "Not valid — withdrawn by the JUPEB Office", `This ${what.toLowerCase()} was revoked on ${day(v.revokedOn)}. Treat it as not valid.`]
      : ["bad", "Not verified", "No JUPEB paper of the University has this code. Treat the paper as not genuine."]
    : v.current
      ? ["ok", "Genuine — the University's record says what this paper says", `This ${what.toLowerCase()} was issued on ${day(v.issuedOn)} and still matches the record.`]
      : ["info", "Genuine, but no longer current", v.withdrawn ? `This ${what.toLowerCase()} was issued on ${day(v.issuedOn)}; the application has since been withdrawn.`
        : `This ${what.toLowerCase()} was issued on ${day(v.issuedOn)}; the record has changed since. What it printed and what the record says now are shown below.`];
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-5) var(--s-3)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 640, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow"><div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div><div className="phead__t ink-chrome">JUPEB paper verification</div></div>
        </div>
        <div className="card__body">
          <Note kind={verdict[0]} title={verdict[1]}>{verdict[2]}</Note>
          {v.genuine ? (
            <>
              <div className="eyebrow">{what} · code {v.code}</div>
              <div className="sub2" style={{ marginBottom: "var(--s-2)" }}>{v.current ? "As printed, and as the record stands:" : "As printed:"}</div>
              <Facts f={v.facts} />
              {!v.current && v.currentFacts ? (
                <>
                  <div className="eyebrow mt-3">The record now</div>
                  <Facts f={v.currentFacts} />
                </>
              ) : null}
              {v.deferred ? <p className="sub2 mt-2">The admission is deferred to a later session.</p> : null}
            </>
          ) : null}
          <div className="sub2 mt-3">Only what the paper itself shows is disclosed. A paper is verified against the University&rsquo;s register, not by its appearance. <Link href="/verify/jupeb">Check another code</Link>.</div>
        </div>
      </div>
    </div>
  );
}
