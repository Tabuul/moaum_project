"use client";
/** V376: an image of a CBT question or option. In the examination room it is fetched with the attempt's token (an <img> cannot send
 *  one), so the server shows it only inside the running attempt that drew it; in the office's bank and preview it is read through the
 *  question's bank. Each image is fetched once per page and kept while the page lives. */
import { useEffect, useState, type CSSProperties } from "react";

const loaded = new Map<string, string>();

export function CbtImage({ src, headers, alt, style }: { src: string; headers?: Record<string, string>; alt: string; style?: CSSProperties }) {
  const [url, setUrl] = useState<string | null | undefined>(() => loaded.get(src));
  const headerKey = JSON.stringify(headers ?? {});
  useEffect(() => {
    if (loaded.has(src)) return;
    let gone = false;
    fetch(src, { headers: JSON.parse(headerKey) as Record<string, string> }).then(async (r) => {
      if (gone) return;
      if (!r.ok) { setUrl(null); return; }
      const u = URL.createObjectURL(await r.blob());
      loaded.set(src, u);
      setUrl(u);
    }).catch(() => { if (!gone) setUrl(null); });
    return () => { gone = true; };
  }, [src, headerKey]);
  if (url === null) return <span className="sub2" style={{ display: "block", ...style }}>[The image could not be loaded: tell the invigilator.]</span>;
  if (!url) return <span className="sub2" style={{ display: "block", minHeight: 40, ...style }}>Loading the image…</span>;
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={url} alt={alt} style={{ display: "block", maxWidth: "100%", maxHeight: 420, objectFit: "contain", margin: "8px 0", ...style }} />;
}
