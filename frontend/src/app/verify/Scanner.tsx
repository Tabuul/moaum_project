"use client";

/** A camera QR scanner for the public verification page. It reads the QR printed on a receipt (or an
 *  exam card, course form or results statement), which encodes a "/verify/…" path, and hands that path
 *  back to the page to open. Only a "/verify/…" path is ever followed, so a stray or hostile QR cannot
 *  redirect the visitor elsewhere. Uses jsQR, so it works on iOS Safari (no BarcodeDetector needed). */
import { useEffect, useRef, useState } from "react";
import jsQR from "jsqr";

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

  const line = "#d8cfbc";

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => { setError(null); setOpen(true); }}
        style={{ width: "100%", marginTop: 12, padding: "11px 14px", fontSize: 14, fontWeight: 600, color: "#0e3f55", background: "#fff", border: `1px solid ${line}`, borderRadius: 9, cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", gap: 8 }}
      >
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect x="3" y="3" width="6" height="6" rx="1" /><rect x="15" y="3" width="6" height="6" rx="1" /><rect x="3" y="15" width="6" height="6" rx="1" />
          <path d="M15 15h2v2M19 15h2M21 19v2h-2M15 21h2" />
        </svg>
        Scan the receipt QR
      </button>
    );
  }

  return (
    <div style={{ marginTop: 12, border: `1px solid ${line}`, borderRadius: 11, overflow: "hidden", background: "#0e1c26" }}>
      <div style={{ position: "relative", aspectRatio: "1 / 1", background: "#0e1c26" }}>
        <video ref={videoRef} muted playsInline style={{ width: "100%", height: "100%", objectFit: "cover", display: error ? "none" : "block" }} />
        {!error ? (
          <div aria-hidden="true" style={{ position: "absolute", inset: "18%", border: "3px solid rgba(255,255,255,.9)", borderRadius: 14, boxShadow: "0 0 0 100vmax rgba(14,28,38,.35)" }} />
        ) : null}
        {error ? (
          <div style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", padding: 22, textAlign: "center", color: "#eaf0f4", fontSize: 13.5, lineHeight: 1.5 }}>{error}</div>
        ) : null}
      </div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: "10px 14px", background: "#0e3f55", color: "#dbe7ec" }}>
        <span style={{ fontSize: 12.5 }}>{error ? "Camera unavailable" : "Point the receipt's QR at the camera"}</span>
        <button type="button" onClick={() => { stop(); setOpen(false); }} style={{ padding: "6px 12px", fontSize: 13, fontWeight: 600, color: "#0e3f55", background: "#fff", border: "none", borderRadius: 7, cursor: "pointer" }}>Close</button>
      </div>
    </div>
  );
}
