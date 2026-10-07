/**
 * Formulas in plain text (V349), for the JUPEB practice questions: what lies between dollar signs is a formula —
 * $x^2$, $H_2O$, $\frac{1}{2}mv^2$, $\sqrt{b^2 - 4ac}$, $\alpha + \beta$, $2H_2 + O_2 \to 2H_2O$ — and everything else is text.
 * The text is parsed into a small tree the page draws with its own elements (never as HTML), and read back as plain text for
 * the exports. A formula that cannot be read is shown as it was typed; \$ is a dollar sign.
 */

export type MathNode =
  | { t: "text"; v: string }
  | { t: "sup"; c: MathNode[] }
  | { t: "sub"; c: MathNode[] }
  | { t: "frac"; n: MathNode[]; d: MathNode[] }
  | { t: "sqrt"; c: MathNode[]; idx: MathNode[] | null }
  | { t: "math"; c: MathNode[] };

/** the commands a formula may use, and what each draws */
export const SYMBOLS: Record<string, string> = {
  alpha: "α", beta: "β", gamma: "γ", delta: "δ", epsilon: "ε", varepsilon: "ε", zeta: "ζ", eta: "η", theta: "θ", vartheta: "ϑ", iota: "ι",
  kappa: "κ", lambda: "λ", mu: "μ", nu: "ν", xi: "ξ", pi: "π", rho: "ρ", sigma: "σ", tau: "τ", upsilon: "υ", phi: "φ", varphi: "φ", chi: "χ",
  psi: "ψ", omega: "ω", Gamma: "Γ", Delta: "Δ", Theta: "Θ", Lambda: "Λ", Xi: "Ξ", Pi: "Π", Sigma: "Σ", Upsilon: "Υ", Phi: "Φ", Psi: "Ψ", Omega: "Ω",
  times: "×", div: "÷", pm: "±", mp: "∓", cdot: "·", ast: "∗", le: "≤", leq: "≤", ge: "≥", geq: "≥", ne: "≠", neq: "≠", approx: "≈", equiv: "≡",
  sim: "∼", propto: "∝", infty: "∞", to: "→", rightarrow: "→", leftarrow: "←", leftrightarrow: "↔", Rightarrow: "⇒", Leftarrow: "⇐",
  Leftrightarrow: "⇔", rightleftharpoons: "⇌", uparrow: "↑", downarrow: "↓", degree: "°", circ: "°", partial: "∂", nabla: "∇", sum: "∑",
  prod: "∏", int: "∫", oint: "∮", angle: "∠", perp: "⊥", parallel: "∥", therefore: "∴", because: "∵", in: "∈", notin: "∉", subset: "⊂",
  subseteq: "⊆", supset: "⊃", cup: "∪", cap: "∩", emptyset: "∅", forall: "∀", exists: "∃", hbar: "ℏ", ell: "ℓ", prime: "′", ldots: "…",
  cdots: "⋯", triangle: "△", square: "□", neg: "¬", land: "∧", lor: "∨", sin: "sin", cos: "cos", tan: "tan", log: "log", ln: "ln",
  lim: "lim", exp: "exp", min: "min", max: "max",
};
const SPACES: Record<string, string> = { ",": " ", ";": " ", " ": " ", quad: " ", qquad: "  " };

/** the text with its formulas parsed: text and math nodes in order */
export function parseMathText(input: string): MathNode[] {
  const out: MathNode[] = [];
  let text = "";
  let i = 0;
  const flush = () => { if (text) { out.push({ t: "text", v: text }); text = ""; } };
  while (i < input.length) {
    const ch = input[i];
    if (ch === "\\" && input[i + 1] === "$") { text += "$"; i += 2; continue; }
    if (ch === "$") {
      const end = findClosingDollar(input, i + 1);
      if (end < 0 || end === i + 1) { text += ch; i++; continue; }
      flush();
      const p = new Parser(input.slice(i + 1, end));
      out.push({ t: "math", c: p.list(null) });
      i = end + 1;
      continue;
    }
    text += ch;
    i++;
  }
  flush();
  return out;
}

function findClosingDollar(s: string, from: number): number {
  for (let j = from; j < s.length; j++) {
    if (s[j] === "\\") { j++; continue; }
    if (s[j] === "$") return j;
    if (s[j] === "\n") return -1;
  }
  return -1;
}

class Parser {
  private i = 0;
  private readonly s: string;
  constructor(s: string) { this.s = s; }

  /** nodes until the closing brace (or the end) */
  list(close: "}" | "]" | null): MathNode[] {
    const out: MathNode[] = [];
    let text = "";
    const push = (n: MathNode) => { if (text) { out.push({ t: "text", v: text }); text = ""; } out.push(n); };
    while (this.i < this.s.length) {
      const ch = this.s[this.i];
      if (close && ch === close) { this.i++; break; }
      if (ch === "^" || ch === "_") {
        this.i++;
        const arg = this.atom();
        push(ch === "^" ? { t: "sup", c: arg } : { t: "sub", c: arg });
        continue;
      }
      if (ch === "{") { this.i++; const inner = this.list("}"); if (text) { out.push({ t: "text", v: text }); text = ""; } out.push(...inner); continue; }
      if (ch === "\\") {
        const cmd = this.command();
        if (cmd === "frac") { const n = this.atom(); const d = this.atom(); push({ t: "frac", n, d }); continue; }
        if (cmd === "sqrt") {
          let idx: MathNode[] | null = null;
          if (this.s[this.i] === "[") { this.i++; idx = this.list("]"); }
          push({ t: "sqrt", c: this.atom(), idx });
          continue;
        }
        if (cmd === "text" || cmd === "mathrm" || cmd === "mathbf" || cmd === "operatorname") { const inner = this.atom(); if (text) { out.push({ t: "text", v: text }); text = ""; } out.push(...inner); continue; }
        text += this.symbol(cmd);
        continue;
      }
      text += ch;
      this.i++;
    }
    if (text) out.push({ t: "text", v: text });
    return out;
  }

  /** one argument: a braced group, a command, or a single character */
  private atom(): MathNode[] {
    while (this.s[this.i] === " ") this.i++;
    const ch = this.s[this.i];
    if (ch === undefined) return [];
    if (ch === "{") { this.i++; return this.list("}"); }
    if (ch === "\\") {
      const cmd = this.command();
      if (cmd === "frac") { const n = this.atom(); const d = this.atom(); return [{ t: "frac", n, d }]; }
      if (cmd === "sqrt") return [{ t: "sqrt", c: this.atom(), idx: null }];
      return [{ t: "text", v: this.symbol(cmd) }];
    }
    this.i++;
    return [{ t: "text", v: ch }];
  }

  /** the command after a backslash: a run of letters, or one other character (\{, \}, \,) */
  private command(): string {
    this.i++;
    const m = /^[A-Za-z]+/.exec(this.s.slice(this.i));
    if (m) { this.i += m[0].length; return m[0]; }
    const one = this.s[this.i] ?? "";
    this.i++;
    return one;
  }

  private symbol(cmd: string): string {
    if (cmd in SPACES) return SPACES[cmd];
    if (cmd === "{" || cmd === "}" || cmd === "%" || cmd === "&" || cmd === "#" || cmd === "_" || cmd === "$") return cmd;
    if (cmd === "\\") return "\n";
    return SYMBOLS[cmd] ?? "\\" + cmd;
  }
}

/** the text with its formulas written out plainly, for an export: x^2 → x², a fraction as a/b */
export function mathToPlain(nodes: MathNode[]): string {
  const SUP: Record<string, string> = { "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "−": "⁻", "n": "ⁿ", "°": "°", "′": "′" };
  const SUB: Record<string, string> = { "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋" };
  const mapAll = (s: string, m: Record<string, string>) => ([...s].every((c) => c in m) ? [...s].map((c) => m[c]).join("") : null);
  const walk = (ns: MathNode[]): string => ns.map((n) => {
    switch (n.t) {
      case "text": return n.v;
      case "math": return walk(n.c);
      case "sup": { const v = walk(n.c); return mapAll(v, SUP) ?? `^(${v})`; }
      case "sub": { const v = walk(n.c); return mapAll(v, SUB) ?? `_(${v})`; }
      case "frac": { const a = walk(n.n); const b = walk(n.d); return `${a.length > 1 ? `(${a})` : a}/${b.length > 1 ? `(${b})` : b}`; }
      case "sqrt": { const v = walk(n.c); return `${n.idx ? walk(n.idx) : ""}√${v.length > 1 ? `(${v})` : v}`; }
    }
  }).join("");
  return walk(nodes);
}

/** plain text of a question as typed, for Excel and PDF */
export const plainMath = (s: string | null | undefined) => (s ? mathToPlain(parseMathText(s)) : "");
