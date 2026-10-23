/**
 * V646: one course code, different titles — separate courses. A second course under a code has its own key: the code and its
 * curriculum (CSC 401 BMAS, CSC 401 CCMAS2) or a number (CSC 401 V2). The key is the course's identity everywhere; the code shown
 * is the key without that mark (catalogue.shown_code), and the title, with the curriculum, tells the courses apart.
 */
const VARIANT = / ((?:BMAS|CCMAS|V)\d?)$/;

/** the code a course is shown under: CSC 401 BMAS → CSC 401; an ordinary code as it is */
export function shownCode(code: string | null | undefined): string {
  return (code ?? "").replace(VARIANT, "");
}

/** the mark of a separate course under a code (BMAS, CCMAS2, V2), or null for the course the code was first held by */
export function codeVariant(code: string | null | undefined): string | null {
  const m = (code ?? "").match(VARIANT);
  return m ? m[1] : null;
}

/** "CSC 401 — Computer Networks", with the curriculum where the course is a separate one under its code */
export function courseLabel(code: string | null | undefined, title?: string | null, curriculum?: string | null): string {
  const v = codeVariant(code);
  const tag = v ? (curriculum || v.replace(/\d$/, "")) : null;
  return `${shownCode(code)}${title ? ` — ${title}` : ""}${tag && tag !== "V" ? ` (${tag})` : ""}`;
}

/** the key a structure row's choice is held under: the code without spacing or punctuation, and the title as compared */
export function titleChoiceKey(code: string, title: string): string {
  return `${code.toUpperCase().replace(/[^A-Z0-9]/g, "")}|${title.toLowerCase().replace(/&/g, "and").replace(/[^a-z0-9]/g, "")}`;
}
