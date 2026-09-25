import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { XlsxLogo } from "@/lib/xlsx";

/** the University crest read from the public folder on the server, for a workbook built in a route handler;
 *  undefined when the file is missing or is not a PNG, so the document is still produced, unbranded */
export function crestPng(): XlsxLogo | undefined {
  try {
    const buf = readFileSync(join(process.cwd(), "public", "crest.png"));
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    if (dv.getUint32(0) !== 0x89504e47) return undefined;
    return { png: new Uint8Array(buf), w: dv.getUint32(16), h: dv.getUint32(20) };
  } catch {
    return undefined;
  }
}
