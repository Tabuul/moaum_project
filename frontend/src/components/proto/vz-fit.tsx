"use client";

/** vz-fit — a chart drawn at the width it is shown at. An SVG with a fixed viewBox shrinks its text with the panel: a
 *  660-unit line in a 296px quarter-width panel draws its axis at 5px. FitLine measures its panel and draws the Line at
 *  that width, so the axis reads at its own size whether the panel is a quarter of a desktop or a phone's whole width. */
import { useEffect, useRef, useState, type ComponentProps } from "react";
import { Line } from "./vz";

export function FitLine(props: Omit<ComponentProps<typeof Line>, "width">) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState<number | null>(null);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const seen = new ResizeObserver(([e]) => setWidth(Math.round(e.contentRect.width)));
    seen.observe(el);
    return () => seen.disconnect();
  }, []);
  return <div ref={box}><Line {...props} width={Math.max(240, width ?? 460)} /></div>;
}
