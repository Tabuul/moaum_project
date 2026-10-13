/** V441: a legal document (the Privacy Policy first) as the API reads it — tokens filled — and how its text is read into
 *  paragraphs and lists. Safe for the browser: no document engine here (that is lib/legal.ts, server side). */

export interface LegalSection {
  no: number;
  key: string;
  heading: string;
  body: string;
}

export interface LegalDocument {
  id: string;
  kind: "PRIVACY_POLICY" | "TERMS_OF_USE" | "COOKIE_NOTICE";
  version: number;
  status: "DRAFT" | "PUBLISHED" | "ARCHIVED";
  title: string;
  summary: string | null;
  effectiveOn: string | null;
  publishedAt: string | null;
  updatedAt: string | null;
  requiresAcceptance: boolean;
  sections: LegalSection[];
  institution: { name: string; shortName: string; address: string; phone: string; email: string; website: string };
  contact: { name: string; title: string; office: string; email: string; phone: string; address: string; requestDays: number };
}

export type Block = { kind: "p"; text: string } | { kind: "ul"; items: string[] };

/** a section's body: paragraphs separated by blank lines; a paragraph whose lines all begin "- " is a list */
export function blocks(body: string): Block[] {
  const out: Block[] = [];
  for (const para of body.replace(/\r\n/g, "\n").split(/\n\s*\n/)) {
    const lines = para.split("\n").map((l) => l.trim()).filter(Boolean);
    if (!lines.length) continue;
    if (lines.every((l) => l.startsWith("- "))) {
      out.push({ kind: "ul", items: lines.map((l) => l.slice(2).trim()) });
    } else {
      out.push({ kind: "p", text: lines.join(" ") });
    }
  }
  return out;
}

/** the anchor a section is reached by: its key, or its number */
export function anchor(s: LegalSection): string {
  return `s-${s.key || s.no}`;
}

export function legalDay(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso.length === 10 ? iso + "T00:00:00" : iso);
  return Number.isNaN(d.getTime()) ? String(iso) : d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
}
