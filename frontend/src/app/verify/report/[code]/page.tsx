import { api } from "@/lib/api";

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
    <div style={{ minHeight: "100vh", background: "#f6f3ea", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "40px 16px", fontFamily: "system-ui, -apple-system, Segoe UI, sans-serif", color: "#16273a" }}>
      <div style={{ width: "100%", maxWidth: 560, background: "#fff", border: "1px solid #e4ddcd", borderRadius: 14, overflow: "hidden", boxShadow: "0 1px 3px rgba(20,39,58,.08)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 20px", borderBottom: "2px solid #0e3f55" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div>
            <div style={{ fontSize: 11, letterSpacing: ".14em", textTransform: "uppercase", color: "#b0842e", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "#0e3f55" }}>Return verification</div>
          </div>
        </div>
        <div style={{ padding: 20 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "12px 14px", borderRadius: 10, marginBottom: 16,
            background: ok ? "#e6f0e8" : "#f5e9ef", border: `1px solid ${ok ? "#c4ddca" : "#e2c6d3"}`, color: ok ? "#2f6b45" : "#7a3b52" }}>
            <span style={{ fontSize: 22 }}>{ok ? "✓" : "✕"}</span>
            <div>
              <div style={{ fontWeight: 700, fontSize: 15 }}>{ok ? "Genuine — this return was kept by the portal" : "Not verified"}</div>
              <div style={{ fontSize: 12.5 }}>{ok
                ? "Check that the return, the period, the row count and the totals below match the copy in hand."
                : "No kept return carries this code. A return is genuine only if it appears here — check the code, or treat the copy as not verified."}</div>
            </div>
          </div>
          {ok ? (
            <dl style={{ display: "grid", gridTemplateColumns: "max-content 1fr", gap: "8px 16px", margin: 0, fontSize: 14 }}>
              <dt style={{ color: "#6b7785" }}>Return</dt><dd style={{ margin: 0, fontWeight: 600 }}>{v.title}</dd>
              {v.subtitle ? <><dt style={{ color: "#6b7785" }}>Scope</dt><dd style={{ margin: 0 }}>{v.subtitle}</dd></> : null}
              <dt style={{ color: "#6b7785" }}>Period</dt><dd style={{ margin: 0 }}>{v.period}</dd>
              <dt style={{ color: "#6b7785" }}>Taken</dt><dd style={{ margin: 0 }}>{day(v.taken_at)}{v.taken_office ? ` · ${OFFICE[v.taken_office] ?? v.taken_office}` : ""}</dd>
              <dt style={{ color: "#6b7785" }}>Rows</dt><dd style={{ margin: 0 }}>{Number(v.row_count).toLocaleString()}</dd>
              {totals.length ? <><dt style={{ color: "#6b7785" }}>Totals</dt><dd style={{ margin: 0 }}>{totals.map(([k, val]) => <div key={k}><span style={{ color: "#6b7785" }}>{k}:</span> {val}</div>)}</dd></> : null}
              <dt style={{ color: "#6b7785" }}>Filed</dt><dd style={{ margin: 0 }}>{v.filed_at ? `${v.filed_to} · ${day(v.filed_at)}` : "Not yet filed"}</dd>
              <dt style={{ color: "#6b7785" }}>Code</dt><dd style={{ margin: 0, fontFamily: "ui-monospace, monospace" }}>{v.verification_code}</dd>
            </dl>
          ) : null}
        </div>
      </div>
    </div>
  );
}
