import { api } from "@/lib/api";
import { receiptPurpose } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

interface VerifyResult {
  genuine: boolean;
  name?: string; matricNo?: string | null; programme?: string | null; level?: number | null;
  amount?: number; purpose?: string; session?: string; term?: string | null; channel?: string | null;
  confirmedOn?: string | null; receiptNo?: string | null; passport?: string | null;
}

const naira = (n: number | undefined) => (n == null ? "—" : `NGN ${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** /verify/receipt/[reference] — the public verification page a receipt's QR opens.
 *  It shows the authoritative Bursary record, so an altered or cloned receipt is exposed
 *  when the payer, amount or date on paper does not match what is shown here. Public. */
export default async function Page({ params, searchParams }: {
  params: Promise<{ reference: string }>; searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { reference } = await params;
  const sp = await searchParams;
  const c = typeof sp.c === "string" ? sp.c : "";
  const r = await api<VerifyResult>(`/api/v1/verify/receipt/${encodeURIComponent(reference)}?c=${encodeURIComponent(c)}`);
  const v = r.ok ? r.data : { genuine: false };
  const ok = v.genuine;

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "40px 16px", fontFamily: "var(--sans)", color: "var(--ink)" }}>
      <div style={{ width: "100%", maxWidth: 560, background: "#fff", border: "1px solid var(--line)", borderRadius: 14, overflow: "hidden", boxShadow: "0 1px 3px rgba(20,39,58,.08)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 20px", borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div>
            <div style={{ fontSize: 11, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--amber)", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "var(--chrome)" }}>Receipt verification</div>
          </div>
        </div>

        <div style={{ padding: 20 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, padding: "12px 14px", borderRadius: 10, marginBottom: 16,
            background: ok ? "var(--green-bg)" : "var(--red-bg)", border: `1px solid ${ok ? "var(--green-line)" : "var(--red-line)"}`, color: ok ? "var(--green-ink)" : "var(--red-deep)" }}>
            <span style={{ fontSize: 22 }}>{ok ? "✓" : "✕"}</span>
            <div>
              <div className="b700 t-md">{ok ? "Genuine — this receipt is on the Bursary's ledger" : "Not verified"}</div>
              <div style={{ fontSize: 12.5 }}>{ok
                ? "Check that the payer, amount and date below match the receipt in hand."
                : "No confirmed receipt matches this code. A receipt is real only if it appears here — check the reference, or treat it as not genuine."}</div>
            </div>
          </div>

          {ok ? (
           <>
            {v.passport ? (
              <div style={{ display: "flex", justifyContent: "center", marginBottom: 14 }}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={v.passport} alt="Student passport" style={{ width: 96, height: 112, objectFit: "cover", borderRadius: 8, border: "1px solid var(--line)" }} />
              </div>
            ) : null}
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
              <tbody>
                {[["Received from", v.name], ["Matriculation number", v.matricNo ?? "—"], ["Programme", v.programme ?? "—"],
                  ...(v.level ? [["Level", `${v.level} Level`]] : []),
                  ["Being payment for", receiptPurpose(v.purpose)], ["Session", v.session],
                  ...(v.term ? [["Semester", v.term]] : []),
                  ["Amount", naira(v.amount)],
                  ["Channel", v.channel ?? "—"], ["Confirmed on", day(v.confirmedOn)], ["Receipt number", v.receiptNo ?? "—"]].map(([k, val], i) => (
                  <tr key={i} style={{ borderBottom: "1px solid var(--line-2)" }}>
                    <td style={{ padding: "9px 8px 9px 0", color: "var(--muted)", whiteSpace: "nowrap", verticalAlign: "top", fontSize: 12, textTransform: "uppercase", letterSpacing: ".04em" }}>{k}</td>
                    <td style={{ padding: "9px 0", fontWeight: k === "Amount" ? 700 : 500, textAlign: "right", overflowWrap: "anywhere" }}>{val ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
           </>
          ) : null}

          <p style={{ fontSize: 11.5, color: "var(--faint)", marginTop: 18, lineHeight: 1.5 }}>
            This page reads the University&rsquo;s payment ledger directly; it is the record, and the printed receipt is only a view of it.
            Verified {day(new Date().toISOString())}.
          </p>
        </div>
      </div>
    </div>
  );
}
