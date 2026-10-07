/**
 * Text with formulas (V349): what lies between dollar signs is drawn as a formula — powers and subscripts, fractions,
 * roots, Greek letters and the usual signs — with the page's own elements, never as HTML. See lib/mathtext.ts for what may
 * be written.
 */
import type { CSSProperties, ReactNode } from "react";
import { parseMathText, type MathNode } from "@/lib/mathtext";

const FRAC: CSSProperties = { display: "inline-flex", flexDirection: "column", verticalAlign: "middle", textAlign: "center", margin: "0 .12em", lineHeight: 1.1 };
const NUM: CSSProperties = { borderBottom: "1px solid currentColor", padding: "0 .15em", fontSize: ".85em" };
const DEN: CSSProperties = { padding: "0 .15em", fontSize: ".85em" };
const ROOT: CSSProperties = { borderTop: "1px solid currentColor", paddingLeft: ".1em" };

function draw(nodes: MathNode[], key: string): ReactNode[] {
  return nodes.map((n, i) => {
    const k = `${key}.${i}`;
    switch (n.t) {
      case "text": return <span key={k}>{n.v}</span>;
      case "sup": return <sup key={k}>{draw(n.c, k)}</sup>;
      case "sub": return <sub key={k}>{draw(n.c, k)}</sub>;
      case "frac": return <span key={k} style={FRAC}><span style={NUM}>{draw(n.n, k + "n")}</span><span style={DEN}>{draw(n.d, k + "d")}</span></span>;
      case "sqrt": return <span key={k}>{n.idx ? <sup>{draw(n.idx, k + "i")}</sup> : null}√<span style={ROOT}>{draw(n.c, k)}</span></span>;
      case "math": return <span key={k} className="mathf" style={{ fontFamily: "var(--serif, serif)", whiteSpace: "nowrap" }}>{draw(n.c, k)}</span>;
    }
  });
}

/** the text as typed, its formulas drawn; line breaks kept */
export function MathText({ text, style }: { text: string | null | undefined; style?: CSSProperties }) {
  if (!text) return null;
  return <span style={{ whiteSpace: "pre-line", ...style }}>{draw(parseMathText(text), "m")}</span>;
}
