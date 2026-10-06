"use client";

/** /verify/jupeb — the public entry to verify a JUPEB statement of result, letter, slip or receipt by the code printed under its QR (V343) */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { Scanner } from "../Scanner";

export default function VerifyJupeb() {
  const router = useRouter();
  const [code, setCode] = useState("");
  const clean = code.toUpperCase().replace(/[^A-Z0-9]/g, "");
  function go(e: React.FormEvent) {
    e.preventDefault();
    if (clean.length === 12) router.push(`/verify/jupeb/${clean.slice(0, 4)}-${clean.slice(4, 8)}-${clean.slice(8)}`);
  }
  return (
    <div style={{ minHeight: "100vh", background: "var(--bg)", display: "flex", alignItems: "flex-start", justifyContent: "center", padding: "var(--s-8) var(--s-4)" }}>
      <div className="card" style={{ width: "100%", maxWidth: 480, overflow: "hidden" }}>
        <div className="card__head" style={{ borderBottom: "2px solid var(--chrome)" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/crest.png" alt="University crest" style={{ width: 40, height: 42, objectFit: "contain" }} />
          <div className="grow">
            <div className="eyebrow" style={{ color: "var(--amber)" }}>Rev. Fr. Moses Orshio Adasu University, Makurdi</div>
            <div className="phead__t ink-chrome">Verify a JUPEB paper</div>
          </div>
        </div>
        <form onSubmit={go} className="card__body">
          <p className="m-0 ink-muted">
            A JUPEB statement of result, admission or acceptance letter, slip or receipt is genuine only if its code opens the University&rsquo;s record here.
            Enter the twelve-character <b>code</b> printed under the QR.
          </p>
          <Field id="vj-code" label="Verification code">
            <input id="vj-code" className="ctl" style={{ letterSpacing: ".1em" }} value={code} onChange={(e) => setCode(e.target.value)} placeholder="e.g. YUEM-AC86-WGKW"
              autoComplete="off" autoCapitalize="characters" maxLength={16} />
          </Field>
          <Btn kind="primary" size="md" type="submit" disabled={clean.length !== 12} style={{ width: "100%" }}>Verify</Btn>
          <Scanner onResult={(path) => router.push(path)} />
          <p className="sub2 ink-faint m-0">Or scan the QR on the paper with the camera above, or with your phone&rsquo;s camera app.</p>
        </form>
      </div>
    </div>
  );
}
