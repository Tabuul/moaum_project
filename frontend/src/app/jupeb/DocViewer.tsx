"use client";

/**
 * A JUPEB applicant's uploaded documents, viewed in a pop-up over the record instead of a new tab: one document at a time,
 * the previous and next of the same candidate a key or a click away, a photographed page turned or seen at full size.
 *
 * The file is fetched through the BFF (the same authorisation as the link it replaces) and shown from a local copy, typed
 * strictly as a PDF or a JPEG/PNG image — the API's own types for these documents — so an uploaded file is never rendered as
 * a web page; anything else is offered as a download only. The API's response carries a sandbox policy that keeps browsers'
 * PDF viewers from drawing it inside a frame, which the local copy does not inherit.
 */
import { useEffect, useState, type MouseEvent, type ReactNode } from "react";
import { Btn, Note } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";

export interface ViewDoc {
  key: string;
  label: string;
  /** a line under the title: the examination body and year, the status */
  sub?: ReactNode;
  filename: string | null;
  /** the document's content, through the BFF */
  url: string;
}

type Shown = { url: string; type: "pdf" | "image" } | { error: string } | null;

/** a plain click opens the viewer; a click meant for a new tab or window keeps the link's own behaviour */
export function viewerClick(open: () => void) {
  return (e: MouseEvent) => {
    if (e.ctrlKey || e.metaKey || e.shiftKey || e.altKey || e.button !== 0) return;
    e.preventDefault();
    open();
  };
}

export function DocViewer({ docs, index, onIndex, onClose, actions }: {
  docs: ViewDoc[]; index: number; onIndex: (i: number) => void; onClose: () => void;
  /** the reviewer's actions on the document shown (Verify, Problem…) */
  actions?: (d: ViewDoc) => ReactNode;
}) {
  const d = docs[Math.min(Math.max(index, 0), docs.length - 1)];
  const url = d?.url ?? "";
  /* what is shown, and how it is turned, belong to one document: moving to another starts afresh */
  const [loaded, setLoaded] = useState<{ for: string; shown: Shown }>({ for: "", shown: null });
  const [pose, setPose] = useState({ for: "", rotate: 0, fit: true });
  const shown = loaded.for === url ? loaded.shown : null;
  const rotate = pose.for === url ? pose.rotate : 0;
  const fit = pose.for === url ? pose.fit : true;

  useEffect(() => {
    if (!url) return;
    let live = true;
    let made: string | null = null;
    const setShown = (x: Shown) => setLoaded({ for: url, shown: x });
    void (async () => {
      try {
        const r = await fetch(url, { cache: "no-store", credentials: "same-origin" });
        if (!r.ok) { if (live) setShown({ error: r.status === 404 ? "The file is not on the record." : `The file could not be opened (${r.status}).` }); return; }
        const ct = (r.headers.get("content-type") ?? "").split(";")[0].trim().toLowerCase();
        const type = ct === "application/pdf" ? "pdf" : ct === "image/jpeg" || ct === "image/png" ? "image" : null;
        if (!type) { if (live) setShown({ error: "This kind of file is not shown here. Download it instead." }); return; }
        const bytes = await r.arrayBuffer();
        made = URL.createObjectURL(new Blob([bytes], { type: type === "pdf" ? "application/pdf" : ct }));
        if (live) setShown({ url: made, type }); else URL.revokeObjectURL(made);
      } catch {
        if (live) setShown({ error: "The file could not be opened." });
      }
    })();
    return () => { live = false; if (made) URL.revokeObjectURL(made); };
  }, [url]);

  /* the arrow keys move between the candidate's documents (Escape closes, as every modal) */
  useEffect(() => {
    function key(e: KeyboardEvent) {
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.tagName === "SELECT")) return;
      if (e.key === "ArrowLeft" && index > 0) { e.preventDefault(); onIndex(index - 1); }
      if (e.key === "ArrowRight" && index < docs.length - 1) { e.preventDefault(); onIndex(index + 1); }
    }
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [index, docs.length, onIndex]);

  if (!d) return null;
  const isImage = shown != null && !("error" in shown) && shown.type === "image";
  return (
    <Modal viewer title={d.label} sub={<>{d.sub}{d.filename ? <span className="tnum"> · {d.filename}</span> : null}</>} onClose={onClose}
      foot={<>
        <Btn kind="ghost" disabled={index <= 0} onClick={() => onIndex(index - 1)} aria-label="Previous document">← Previous</Btn>
        <span className="sub2 tnum">{index + 1} of {docs.length}</span>
        <Btn kind="ghost" disabled={index >= docs.length - 1} onClick={() => onIndex(index + 1)} aria-label="Next document">Next →</Btn>
        {isImage ? <>
          <Btn kind="ghost" onClick={() => setPose({ for: url, rotate: (rotate + 90) % 360, fit })}>Rotate</Btn>
          <Btn kind="ghost" onClick={() => setPose({ for: url, rotate, fit: !fit })}>{fit ? "Actual size" : "Fit"}</Btn>
        </> : null}
        <span className="grow" />
        <a className="btn btn--ghost btn--sm" href={d.url} download={d.filename ?? undefined}>Download</a>
        <a className="btn btn--ghost btn--sm" href={d.url} target="_blank" rel="noreferrer">Open in a new tab</a>
        {actions ? actions(d) : null}
      </>}>
      <div style={{ flex: 1, minHeight: 0, background: "var(--line-2)", display: "flex", overflow: "auto",
        alignItems: isImage && !fit ? "flex-start" : "center", justifyContent: isImage && !fit ? "flex-start" : "center" }}>
        {shown == null ? <div className="sub2" style={{ padding: "var(--s-5)" }}>Opening the document…</div>
          : "error" in shown ? <div style={{ padding: "var(--s-4)", width: "100%", maxWidth: 520 }}><Note kind="bad" title="Not shown">{shown.error}</Note></div>
          : shown.type === "pdf" ? <iframe title={d.label} src={shown.url} style={{ width: "100%", height: "100%", border: 0, background: "#fff" }} />
          // eslint-disable-next-line @next/next/no-img-element
          : <img src={shown.url} alt={d.label} style={{
              transform: `rotate(${rotate}deg)`, transition: "transform .15s", background: "#fff",
              ...(fit ? { maxWidth: rotate % 180 ? "calc(100vh - 220px)" : "100%", maxHeight: rotate % 180 ? "100%" : "calc(100vh - 220px)", objectFit: "contain" } : { maxWidth: "none" }),
            }} />}
      </div>
    </Modal>
  );
}
