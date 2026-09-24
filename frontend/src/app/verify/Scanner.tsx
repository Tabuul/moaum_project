"use client";

/** A camera QR scanner for the public verification page. It reads the QR printed on a receipt (or an
 *  exam card, course form or results statement), which encodes a "/verify/…" path, and hands that path
 *  back to the page to open. Only a "/verify/…" path is ever followed, so a stray or hostile QR cannot
 *  redirect the visitor elsewhere. Uses jsQR, so it works on iOS Safari (no BarcodeDetector needed). */
import { useEffect, useRef, useState } from "react";
import jsQR from "jsqr";
import { Btn } from "@/components/proto/ui";

/** Pull a safe in-app verification path out of whatever the QR decodes to. Accepts a full URL or a bare
 *  path; returns the "/verify/…" path with its query, or null when the QR is not one of ours. */
function verifyTarget(text: string): string | null {
  const t = (text || "").trim();
  let path = "";
  try {
    const u = new URL(t);            // a full URL (however it was encoded)
    path = u.pathname + u.search;
  } catch {
    path = t;                        // a bare path
  }
  return path.startsWith("/verify/") ? path : null;
}

export function Scanner({ onResult }: { onResult: (path: string) => void }) {
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const rafRef = useRef<number | null>(null);
  const doneRef = useRef(false);

  function stop() {
    if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  useEffect(() => {
    if (!open) return;
    doneRef.current = false;
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d", { willReadFrequently: true });

    const tick = () => {
      const v = videoRef.current;
      if (!doneRef.current && v && v.readyState === v.HAVE_ENOUGH_DATA && ctx) {
        canvas.width = v.videoWidth;
        canvas.height = v.videoHeight;
        ctx.drawImage(v, 0, 0, canvas.width, canvas.height);
        try {
          const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
          const found = jsQR(img.data, img.width, img.height, { inversionAttempts: "dontInvert" });
          if (found) {
            const path = verifyTarget(found.data);
            if (path) {
              doneRef.current = true;
              stop();
              onResult(path);
              return;
            }
            setError("That QR is not a MOAUM verification code. Point it at a receipt's QR.");
          }
        } catch { /* a frame we could not read; try the next one */ }
      }
      rafRef.current = requestAnimationFrame(tick);
    };

    (async () => {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } });
        streamRef.current = stream;
        const v = videoRef.current;
        if (v) {
          v.srcObject = stream;
          v.setAttribute("playsinline", "true");
          await v.play();
        }
        rafRef.current = requestAnimationFrame(tick);
      } catch (e) {
        const err = e as DOMException;
        setError(
          err && err.name === "NotAllowedError"
            ? "Camera permission was declined. Allow the camera, or type the reference and check code above."
            : err && err.name === "NotFoundError"
              ? "No camera was found on this device. Type the reference and check code above."
              : "The camera could not be opened. Type the reference and check code above.",
        );
      }
    })();

    return stop;
  }, [open, onResult]);

  if (!open) {
    return (
      <Btn kind="ghost" size="md" onClick={() => { setError(null); setOpen(true); }} style={{ width: "100%" }}>
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="3" y="3" width="6" height="6" rx="1" /><rect x="15" y="3" width="6" height="6" rx="1" /><rect x="3" y="15" width="6" height="6" rx="1" />
          <path d="M15 15h2v2M19 15h2M21 19v2h-2M15 21h2" />
        </svg>
        Scan the receipt QR
      </Btn>
    );
  }

  return (
    <div style={{ border: "1px solid var(--line)", borderRadius: "var(--r-lg)", overflow: "hidden", background: "var(--chrome-deep)" }}>
      <div style={{ position: "relative", aspectRatio: "1 / 1", background: "var(--chrome-deep)" }}>
        <video ref={videoRef} muted playsInline style={{ width: "100%", height: "100%", objectFit: "cover", display: error ? "none" : "block" }} />
        {!error ? (
          <div aria-hidden="true" style={{ position: "absolute", inset: "18%", border: "3px solid var(--surface)", borderRadius: "var(--r-xl)", boxShadow: "0 0 0 100vmax rgba(14,28,38,.35)" }} />
        ) : null}
        {error ? (
          <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", padding: "var(--s-6)", textAlign: "center", color: "var(--chrome-ink)" }}>{error}</div>
        ) : null}
      </div>
      <div className="row row--between" style={{ padding: "var(--s-3) var(--s-4)", background: "var(--chrome)", color: "var(--chrome-ink)" }}>
        <span className="t-sm">{error ? "Camera unavailable" : "Point the receipt's QR at the camera"}</span>
        <Btn kind="ghost" size="sm" onClick={() => { stop(); setOpen(false); }}>Close</Btn>
      </div>
    </div>
  );
}
