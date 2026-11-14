/**
 * V759: the signature printed above the signatory's name on the admission letter is a setting, not a file in the code. An office
 * that may change the document templates uploads it on Credentials → Document settings for the signatory the template names; the
 * letter's JSON carries it to the letter's owner as a JPEG on white, and the letter draws it in proportion above the name. These are
 * the pieces both sides share: reading the JPEG out of the JSON, fitting it to the space, and the checks the browser makes before
 * it sends a file (the API makes them again).
 */
import { jpegSize, type Image } from "./pdf-write.ts";

/** the signature as the letter's JSON carries it: the JPEG on white the API keeps for the signatory, in base64 */
export interface LetterSignature { jpegBase64: string; width?: number; height?: number }

/** one signatory on the settings screen (GET /api/v1/documents/signatures); the API leaves out the keys it holds no value for */
export interface SignatoryEntry {
  name: string; hasSignature: boolean; version?: number | null; setAt?: string | null; setByName?: string | null; signatureUrl?: string | null;
  /** the document kinds whose current template names this signatory; none for a signature kept for a name no template now states */
  kinds?: string[]; inUse?: boolean;
}

/** the largest file the API takes, as the identity cards' signature (V622) */
export const SIGNATURE_MAX_BYTES = 1_000_000;

/** the space above the signatory's name on the letter, in points: the space a hand signature takes */
export const SIGNATURE_BOX = { w: 140, h: 48 } as const;

export interface Box { x: number; y: number; w: number; h: number }

/** base64 (a data: address's prefix allowed, as a browser's FileReader writes it) as bytes; null when it is not base64 */
export function base64Bytes(b64: string | null | undefined): Uint8Array | null {
  let s = (b64 ?? "").trim();
  const comma = s.indexOf(",");
  if (s.startsWith("data:") && comma > 0) s = s.slice(comma + 1);
  s = s.replace(/\s+/g, "");
  if (!s || s.length % 4 === 1 || !/^[A-Za-z0-9+/]+={0,2}$/.test(s)) return null;
  try {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

/** bytes as base64, in slices so a file of a megabyte never overflows the call stack */
export function bytesBase64(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
}

/** the letter JSON's signature as the JPEG the PDF writer embeds, its size read from the bytes themselves (never trusted from the
 *  JSON); null when none is held, or what came is not a JPEG — the letter then leaves the space for a hand signature */
export function signatureImageOf(sig: LetterSignature | null | undefined): Image | null {
  if (!sig || typeof sig.jpegBase64 !== "string") return null;
  const data = base64Bytes(sig.jpegBase64);
  const size = data ? jpegSize(data) : null;
  if (!data || !size || size.width <= 0 || size.height <= 0) return null;
  return { data, width: size.width, height: size.height };
}

/** the most a pixel of the signature is enlarged to: 150 dots an inch (72 points an inch). A small scan prints at that size rather
 *  than blown up into blocks: 300 pixels wide or more fills the 140-point space */
export const SIGNATURE_MAX_PT_PER_PX = 72 / 150;

/** the image at its own proportions, as large as the box allows (and no larger than 150 dots an inch), standing on the box's
 *  bottom-left corner — so a signature sits on the name beneath it, starts where the name starts, and never reaches above the
 *  box; null for an image with no size */
export function fitBottomLeft(img: { width: number; height: number }, box: Box): Box | null {
  if (!(img.width > 0 && img.height > 0 && box.w > 0 && box.h > 0)) return null;
  const k = Math.min(box.w / img.width, box.h / img.height, SIGNATURE_MAX_PT_PER_PX);
  return { x: box.x, y: box.y, w: img.width * k, h: img.height * k };
}

/** the file's type by its first bytes, as the API reads it: a PNG or a JPEG, or null */
export function imageKind(head: Uint8Array): "image/png" | "image/jpeg" | null {
  if (head.length >= 4 && head[0] === 0x89 && head[1] === 0x50 && head[2] === 0x4e && head[3] === 0x47) return "image/png";
  if (head.length >= 3 && head[0] === 0xff && head[1] === 0xd8 && head[2] === 0xff) return "image/jpeg";
  return null;
}

/** what the browser says before a file is sent, in the words the officer acts on; null when the file may go */
export function signatureFileProblem(file: { size: number }, head: Uint8Array): string | null {
  if (file.size <= 0) return "The file is empty. Choose the scan of the signature.";
  if (!imageKind(head)) return "The signature must be a PNG or a JPEG; this file is neither. Save the scan as a PNG (a transparent background prints best) or a JPEG.";
  if (file.size > SIGNATURE_MAX_BYTES) {
    return `The file is ${fileSize(file.size)}; the limit is 1 MB (1,000,000 bytes). Save the signature smaller: 800 pixels wide prints sharply on the letter.`;
  }
  return null;
}

/** a file's size in the limit's own unit, rounded up, with its bytes — as the API says it: a file just over the limit never reads
 *  as under it or as exactly it ("1.01 MB (1,000,001 bytes)", not "1.0 MB" or "976 KB") */
export function fileSize(bytes: number): string {
  return `${(Math.ceil(bytes / 10_000) / 100).toFixed(2)} MB (${Math.round(bytes).toLocaleString("en-GB")} bytes)`;
}

/** the small letter of a capital of the Latin alphabets — A-Z, Latin-1, Latin Extended-A and -B, Latin Extended Additional — as the
 *  database's translate() has it: the one small letter, or the character as it is */
function small(c: string): string {
  const l = c.toLowerCase();
  return l.length === 1 ? l : c;
}

/** a signatory's name as the database compares it (credentials.signatory_key): composed (NFC), the Latin capitals in small letters,
 *  spaces (a no-break space among them) run together, and none either side of an ASCII punctuation mark — so "andrew  anjah ,maua"
 *  is the signatory "Andrew Anjah, MAUA", and a Yoruba name in capitals the same name written as usual */
export function signatoryKey(name: string | null | undefined): string {
  return (name ?? "").normalize("NFC").replace(/[A-Z\u00c0-\u024f\u1e00-\u1eff]/g, small)
    .replace(/[\t\n\v\f\r \u00a0\u2007\u202f]+/g, " ").replace(/ ?([!-/:-@[-`{-~]) ?/g, "$1").replace(/^ +| +$/g, "");
}

/** the entry for the name a template states: the same name first, else the same signatory by the key */
export function entryFor(entries: SignatoryEntry[], name: string): SignatoryEntry | null {
  return entries.find((e) => e.name === name) ?? entries.find((e) => signatoryKey(e.name) === signatoryKey(name)) ?? null;
}

/** where the screen reads the image: through the BFF with the officer's own sign-in, as the letter prints it (the JPEG on white,
 *  put upright as a phone's photograph says — the file as uploaded may show otherwise), the version in the address so a replaced
 *  signature is never the old one from the browser's cache */
export function signatureSrc(e: SignatoryEntry): string {
  const path = e.signatureUrl || `/api/v1/documents/signatures/image?name=${encodeURIComponent(e.name)}`;
  const sep = path.includes("?") ? "&" : "?";
  return `/api/bff${path}${sep}format=jpeg${/[?&]v=/.test(path) ? "" : `&v=${e.version ?? 0}`}`;
}
