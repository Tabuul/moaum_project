"use client";

/** /verify — the public entry to verify a payment on the portal. Enter the receipt reference (or
 *  receipt number) and the check code printed on the receipt; it opens the authoritative record. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
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

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 480, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Verify a payment</div>
          </div>
        </div>
        <form onSubmit={go} className="card__body">
          <p className="m-0 ink-muted">
            A receipt is genuine only if it appears here. Enter the <b>reference</b> (or receipt number) and the
            <b> check code</b> printed on the receipt to confirm the payer, amount and date against the Bursary&rsquo;s ledger.
          </p>
          <Field id="v-ref" label="Reference or receipt number">
            <input id="v-ref" className="ctl" value={ref} onChange={(e) => setRef(e.target.value)} placeholder="e.g. MOAUM-FEE-370000-6912 or RCT-2025-00001" autoComplete="off" autoCapitalize="characters" />
          </Field>
          <Field id="v-code" label="Check code">
            <input id="v-code" className="ctl" style={{ letterSpacing: ".08em" }} value={code} onChange={(e) => setCode(e.target.value)} placeholder="e.g. 185A1F24C8C3" autoComplete="off" autoCapitalize="characters" />
          </Field>
          <Btn kind="primary" size="md" type="submit" disabled={!ref.trim()} style={{ width: "100%" }}>
            Verify payment
          </Btn>
          <Scanner onResult={(path) => router.push(path)} />
          <p className="sub2 ink-faint m-0">
            Scan the QR on the receipt with the camera above, or open it with your phone&rsquo;s camera app &mdash; either way it opens this check with the details filled in.
          </p>
        </form>
      </div>
    </div>
  );
}
