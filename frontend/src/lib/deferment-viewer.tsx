"use client";

import { useEffect, useState } from "react";
import { Btn } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";

/** a supporting document opened in a modal on the same page: fetched through the authorised door, shown as PDF or image, downloadable from here; never a new tab */
export function DocViewer({ url, title, image, onClose }: { url: string; title: string; image: boolean; onClose: () => void }) {
  const [blob, setBlob] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let alive = true; let objectUrl: string | null = null;
    (async () => {
      try {
        const r = await fetch(url, { credentials: "same-origin" });
        if (!r.ok) { if (alive) setError(r.status === 403 ? "You are not authorised to view this document." : `The document could not be loaded (${r.status}).`); return; }
        const b = await r.blob();
        objectUrl = URL.createObjectURL(b);
        if (alive) setBlob(objectUrl);
      } catch { if (alive) setError("The document could not be loaded."); }
    })();
    return () => { alive = false; if (objectUrl) URL.revokeObjectURL(objectUrl); };
  }, [url]);
  return (
    <Modal title="Supporting Document" sub={`${title} · opens here; close to return to the application`} wide onClose={onClose}
      foot={<>{blob ? <a href={blob} download={title.replace(/[^\w.\- ]+/g, "_")} className="btn btn--ghost btn--sm">Download</a> : null}<span className="grow" /><Btn kind="primary" onClick={onClose}>Close</Btn></>}>
      {error ? <div className="sub2 ink-red">{error}</div> : !blob ? <div className="sub2">Loading the document…</div> : image ? (
        <div style={{ display: "flex", justifyContent: "center" }}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={blob} alt={title} style={{ maxWidth: "100%", maxHeight: "70vh", borderRadius: "var(--r-md)", border: "1px solid var(--line-2)" }} />
        </div>
      ) : (
        <iframe src={blob} title={title} style={{ width: "100%", height: "72vh", border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", background: "var(--surface)" }} />
      )}
    </Modal>
  );
}

