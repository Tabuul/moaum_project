"use client";
/** V375: scanning CBT slips from the invigilator's board, where the phone's browser can read QR codes itself (BarcodeDetector).
 *  The invigilator opens it; the camera is theirs and runs only while this is open. Where the browser cannot, the phone's own camera
 *  app does the same: the slip's QR opens the portal's check-in page. Nothing is read from the slip but its code, which the server checks. */
import { useEffect, useRef, useState } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";

interface Detected { rawValue: string }
interface Detector { detect(source: HTMLVideoElement): Promise<Detected[]> }

/** the slip's code from what the camera read: the check-in page's address, or the code itself */
export function tokenOf(raw: string): string | null {
  const v = raw.trim();
  try {
    const u = new URL(v);
    const t = u.searchParams.get("t");
    if (u.pathname.endsWith("/cbt/checkin") && t) return t;
  } catch { /* not an address */ }
  return /^[0-9a-f-]{36}\.[0-9a-f-]{36}\.[0-9A-Fa-f]{12}$/.test(v) ? v : null;
}

export function scannerAvailable(): boolean {
  return typeof window !== "undefined" && "BarcodeDetector" in window && !!navigator.mediaDevices?.getUserMedia;
}

export function SlipScanner({ onToken, onClose }: { onToken: (token: string) => void; onClose: () => void }) {
  const video = useRef<HTMLVideoElement | null>(null);
  const [problem, setProblem] = useState<string | null>(null);
  const [notSlip, setNotSlip] = useState(false);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let timer = 0;
    let done = false;
    const Ctor = (window as unknown as { BarcodeDetector?: new (o: { formats: string[] }) => Detector }).BarcodeDetector;
    if (!Ctor) { window.setTimeout(() => setProblem("This browser cannot read QR codes itself. Use the phone's camera app: the slip's QR opens the check-in page."), 0); return; }
    const detector = new Ctor({ formats: ["qr_code"] });
    navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false }).then((s) => {
      stream = s;
      if (!video.current) return;
      video.current.srcObject = s;
      void video.current.play();
      const look = async () => {
        if (done || !video.current || video.current.readyState < 2) { timer = window.setTimeout(look, 300); return; }
        try {
          const found = await detector.detect(video.current);
          for (const f of found) {
            const t = tokenOf(f.rawValue);
            if (t) { done = true; onToken(t); return; }
            setNotSlip(true);
          }
        } catch { /* a frame it could not read */ }
        timer = window.setTimeout(look, 300);
      };
      timer = window.setTimeout(look, 300);
    }).catch(() => setProblem("The camera could not be opened. Allow the camera for the portal, or use the phone's camera app."));
    return () => { done = true; window.clearTimeout(timer); stream?.getTracks().forEach((t) => t.stop()); };
  }, [onToken]);

  return (
    <Modal title="Scan a CBT slip" sub="Hold the slip's QR in front of the camera" onClose={onClose} foot={<Btn kind="ghost" onClick={onClose}>Close</Btn>}>
      {problem ? <Note kind="info" title="Scanning here is not available">{problem}</Note> : (
        <>
          <video ref={video} playsInline muted style={{ width: "100%", maxHeight: 360, borderRadius: 8, background: "#000" }} />
          {notSlip ? <div className="sub2 mt-1">That code is not a CBT slip&rsquo;s.</div> : <div className="sub2 mt-1">The camera runs only while this window is open; nothing is recorded.</div>}
        </>
      )}
    </Modal>
  );
}
