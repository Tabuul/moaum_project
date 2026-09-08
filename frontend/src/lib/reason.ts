/**
 * The reason a person gives for a change travels as the X-Reason header and is
 * recorded in the audit trail. A header value may only carry ISO-8859-1
 * characters: the browser's fetch refuses anything else before the request
 * leaves, silently as far as the screen is concerned. So the reason is made
 * header-safe here — typographic punctuation becomes its plain form, and any
 * other character outside ISO-8859-1 is percent-encoded so the auditor can
 * still read it back — rather than lost, or the request never sent.
 */
const PLAIN: Record<string, string> = {
  "—": " - ", // em dash
  "–": "-", // en dash
  "‘": "'", "’": "'", "‚": "'",
  "“": '"', "”": '"', "„": '"',
  "…": "...",
  " ": " ",
  "₦": "NGN ", // naira
  "→": "->",
};

export function reasonHeader(text: string): string {
  let out = "";
  for (const ch of text.normalize("NFC")) {
    const code = ch.codePointAt(0) ?? 0;
    if (code < 0x20 && ch !== "\t") out += " ";
    else if (code <= 0xff) out += ch;
    else if (PLAIN[ch] !== undefined) out += PLAIN[ch];
    else out += encodeURIComponent(ch);
  }
  return out.replace(/\s{2,}/g, " ").trim();
}
