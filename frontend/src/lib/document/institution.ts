/**
 * The University's official identity as every document reads it (V320): the one profile row the API
 * serves at /api/v1/public/institution, with what the code carried before it as the fallback so a
 * document is still branded when the profile cannot be read. Nothing here fetches; the server and the
 * client each have a loader beside this file.
 */
export interface Institution {
  name: string;
  shortName: string;
  motto: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  country: string | null;
  phone: string | null;
  email: string | null;
  website: string | null;
  /** the logo as uploaded (a PNG or JPEG), as an API path, or null for the built-in crest */
  logoUrl: string | null;
  /** the JPEG derivative the PDF engine embeds, as an API path, or null */
  logoJpegUrl: string | null;
  logoVersion: number;
  footerNote: string | null;
  showGeneratedBy: boolean;
  showPageNumbers: boolean;
  dateFormat: "LONG" | "SHORT";
}

/** what the code carried before the profile existed */
export const DEFAULT_INSTITUTION: Institution = {
  name: "Rev. Fr. Moses Orshio Adasu University, Makurdi",
  shortName: "MOAUM",
  motto: null,
  address: null,
  city: "Makurdi",
  state: "Benue State",
  country: "Nigeria",
  phone: null,
  email: null,
  website: null,
  logoUrl: null,
  logoJpegUrl: null,
  logoVersion: 0,
  footerNote: null,
  showGeneratedBy: true,
  showPageNumbers: true,
  dateFormat: "LONG",
};

const str = (v: unknown): string | null => (v == null ? null : String(v).trim() || null);

/** the API's JSON as the documents want it, every field present and nothing "undefined" */
export function normaliseInstitution(raw: Record<string, unknown> | null | undefined): Institution {
  if (!raw) return DEFAULT_INSTITUTION;
  const name = str(raw.name) ?? DEFAULT_INSTITUTION.name;
  return {
    name,
    shortName: str(raw.shortName) ?? DEFAULT_INSTITUTION.shortName,
    motto: str(raw.motto),
    address: str(raw.address),
    city: str(raw.city),
    state: str(raw.state),
    country: str(raw.country),
    phone: str(raw.phone),
    email: str(raw.email),
    website: str(raw.website),
    logoUrl: str(raw.logoUrl),
    logoJpegUrl: str(raw.logoJpegUrl),
    logoVersion: Number(raw.logoVersion ?? 0) || 0,
    footerNote: str(raw.footerNote),
    showGeneratedBy: raw.showGeneratedBy !== false,
    showPageNumbers: raw.showPageNumbers !== false,
    dateFormat: raw.dateFormat === "SHORT" ? "SHORT" : "LONG",
  };
}

/** the address as one line: "No. 1 University Road, Makurdi, Benue State, Nigeria" — only what is set */
export function addressLine(i: Institution): string {
  return [i.address, i.city, i.state, i.country].filter((x): x is string => !!x).join(", ");
}

/** the contact line: "Tel +234… | info@… | www.…" — only what is set, and the website without its scheme */
export function contactLine(i: Institution): string {
  const site = i.website ? i.website.replace(/^https?:\/\//i, "").replace(/\/$/, "") : null;
  return [i.phone ? `Tel ${i.phone}` : null, i.email, site].filter((x): x is string => !!x).join("  |  ");
}

/** the name in capitals, as a letterhead has it */
export function nameUpper(i: Institution): string {
  return i.name.toUpperCase();
}

const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];

/** a date in the University's configured style: 04 October 2026 (LONG) or 04/10/2026 (SHORT); "—" for nothing */
export function formatDocDate(iso: string | Date | null | undefined, i: Institution = DEFAULT_INSTITUTION): string {
  if (!iso) return "—";
  const d = iso instanceof Date ? iso : new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  return i.dateFormat === "SHORT" ? `${dd}/${mm}/${d.getFullYear()}` : `${dd} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/** a date and time: "04 October 2026, 20:42" */
export function formatDocDateTime(iso: string | Date | null | undefined, i: Institution = DEFAULT_INSTITUTION): string {
  if (!iso) return "—";
  const d = iso instanceof Date ? iso : new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return `${formatDocDate(d, i)}, ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/** the naira amount as the finance documents print it */
export function formatMoney(n: number | string | null | undefined, currency = "NGN"): string {
  if (n == null || n === "") return "—";
  const v = Number(n);
  if (Number.isNaN(v)) return String(n);
  const amount = v.toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return currency === "NGN" ? `₦${amount}` : `${currency} ${amount}`;
}
