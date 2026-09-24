import { api } from "@/lib/api";
import { Note } from "@/components/proto/ui";

export const dynamic = "force-dynamic";

interface VerifyResult {
  genuine: boolean;
  title?: string; subtitle?: string | null; period?: string; report?: string; row_count?: number;
  taken_at?: string; taken_office?: string | null; totals?: string | null; headers?: string | null;
  filed_to?: string | null; filed_at?: string | null; verification_code?: string;
}

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const OFFICE: Record<string, string> = {
  registrar: "Registry", dregistrar: "Registry", academic: "Academic Affairs", records: "Exams & Records", bursar: "Bursary", audit: "Internal Audit",
  hrm: "Human Resource Management", ict: "ICT Directorate", admin: "Administration", vc: "Vice-Chancellor's Office", dvc: "Deputy Vice-Chancellor's Office",
  pgschool: "School of Postgraduate Studies", pgsecretary: "School of Postgraduate Studies", super: "System Administration",
};

/** /verify/report/[code] — the public page a kept return's footing names. It shows what the portal
 *  kept under that code — the return, the period, when it was taken, the row count and the totals —
 *  so a filed copy can be checked against it. Public, like a receipt's verification. */
export default async function Page({ params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const r = await api<VerifyResult>(`/api/v1/verify/report/${encodeURIComponent(code)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;
  const totals: [string, string][] = [];
  if (ok && v.totals) {
    try {
      const t = JSON.parse(v.totals) as Record<string, string | number | null>;
      for (const [k, val] of Object.entries(t)) if (val != null && val !== "" && typeof val !== "object") totals.push([k.replace(/_/g, " "), typeof val === "number" ? val.toLocaleString() : String(val)]);
    } catch { /* a kept copy without totals */ }
  }

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 560, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Return verification</div>
          </div>
        </div>
        <div className="card__body">
          <Note kind={ok ? "ok" : "bad"} title={ok ? "Genuine — this return was kept by the portal" : "Not verified"}>
            {ok
              ? "Check that the return, the period, the row count and the totals below match the copy in hand."
              : "No kept return carries this code. A return is genuine only if it appears here — check the code, or treat the copy as not verified."}
          </Note>
          {ok ? (
            <dl className="m-0" style={{ display: "grid", gridTemplateColumns: "max-content 1fr", gap: "var(--s-2) var(--s-4)" }}>
              <dt className="ink-muted">Return</dt><dd className="m-0 b600">{v.title}</dd>
              {v.subtitle ? <><dt className="ink-muted">Scope</dt><dd className="m-0">{v.subtitle}</dd></> : null}
              <dt className="ink-muted">Period</dt><dd className="m-0">{v.period}</dd>
              <dt className="ink-muted">Taken</dt><dd className="m-0">{day(v.taken_at)}{v.taken_office ? ` · ${OFFICE[v.taken_office] ?? v.taken_office}` : ""}</dd>
              <dt className="ink-muted">Rows</dt><dd className="m-0">{Number(v.row_count).toLocaleString()}</dd>
              {totals.length ? <><dt className="ink-muted">Totals</dt><dd className="m-0">{totals.map(([k, val]) => <div key={k}><span className="ink-muted">{k}:</span> {val}</div>)}</dd></> : null}
              <dt className="ink-muted">Filed</dt><dd className="m-0">{v.filed_at ? `${v.filed_to} · ${day(v.filed_at)}` : "Not yet filed"}</dd>
              <dt className="ink-muted">Code</dt><dd className="m-0" style={{ fontFamily: "var(--mono)" }}>{v.verification_code}</dd>
            </dl>
          ) : null}
        </div>
      </div>
    </div>
  );
}
