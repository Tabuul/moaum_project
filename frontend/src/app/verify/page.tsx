"use client";

/** /verify — the public entry to verify a payment on the portal. Enter the receipt reference (or
 *  receipt number) and the check code printed on the receipt; it opens the authoritative record. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Scanner } from "./Scanner";

export default function VerifyLanding() {
  const router = useRouter();
  const [ref, setRef] = useState("");
  const [code, setCode] = useState("");

  function go(e: React.FormEvent) {
    e.preventDefault();
    const r = ref.trim();
    if (!r) return;
    router.push(`/verify/receipt/${encodeURIComponent(r)}?c=${encodeURIComponent(code.trim())}`);
  }

  const label: React.CSSProperties = { display: "block", fontSize: 12, textTransform: "uppercase", letterSpacing: ".04em", color: "var(--muted)", marginBottom: 6 };
  const input: React.CSSProperties = { width: "100%", padding: "11px 12px", fontSize: 15, border: "1px solid var(--line)", borderRadius: 9, background: "#fff", color: "var(--ink)", boxSizing: "border-box" };

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "40px 16px", fontFamily: "var(--sans)", color: "var(--ink)" }}>
      <div style={{ width: "100%", maxWidth: 480, background: "#fff", border: "1px solid var(--line)", borderRadius: 14, overflow: "hidden", boxShadow: "0 1px 3px rgba(20,39,58,.08)" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 20px", borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div>
            <div style={{ fontSize: 11, letterSpacing: ".14em", textTransform: "uppercase", color: "var(--amber)", fontWeight: 700 }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: "var(--chrome)" }}>Verify a payment</div>
          </div>
        </div>
        <form onSubmit={go} style={{ padding: 20 }}>
          <p style={{ fontSize: 13.5, color: "#42505f", lineHeight: 1.55, marginTop: 0, marginBottom: 18 }}>
            A receipt is genuine only if it appears here. Enter the <b>reference</b> (or receipt number) and the
            <b> check code</b> printed on the receipt to confirm the payer, amount and date against the Bursary&rsquo;s ledger.
          </p>
          <div style={{ marginBottom: 14 }}>
            <label htmlFor="v-ref" style={label}>Reference or receipt number</label>
            <input id="v-ref" style={input} value={ref} onChange={(e) => setRef(e.target.value)} placeholder="e.g. MOAUM-FEE-370000-6912 or RCT-2025-00001" autoComplete="off" autoCapitalize="characters" />
          </div>
          <div style={{ marginBottom: 20 }}>
            <label htmlFor="v-code" style={label}>Check code</label>
            <input id="v-code" style={{ ...input, letterSpacing: ".08em" }} value={code} onChange={(e) => setCode(e.target.value)} placeholder="e.g. 185A1F24C8C3" autoComplete="off" autoCapitalize="characters" />
          </div>
          <button type="submit" disabled={!ref.trim()} style={{ width: "100%", padding: "12px 14px", fontSize: 15, fontWeight: 700, color: "#fff", background: ref.trim() ? "var(--chrome)" : "#9fb0bc", border: "none", borderRadius: 9, cursor: ref.trim() ? "pointer" : "not-allowed" }}>
            Verify payment
          </button>
          <Scanner onResult={(path) => router.push(path)} />
          <p style={{ fontSize: 11.5, color: "var(--faint)", marginTop: 16, lineHeight: 1.5 }}>
            Scan the QR on the receipt with the camera above, or open it with your phone&rsquo;s camera app &mdash; either way it opens this check with the details filled in.
          </p>
        </form>
      </div>
    </div>
  );
}
