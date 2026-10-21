import "server-only";
import { cookies } from "next/headers";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { jpegSize, type Image } from "@/lib/pdf-write";
import type { CardBack } from "@/lib/idcard-pdf";

/**
 * V622: who signs the identity cards for the University — the Chief Security Officer's name and the signature the Directorate of
 * ICT uploaded (as the JPEG the PDF engine embeds), read with the printing office's own sign-in. Without a signature the card prints
 * the line and the title alone; a read that fails never stops the print.
 */
export async function cardSignatory(): Promise<NonNullable<CardBack["signatory"]>> {
  const out: NonNullable<CardBack["signatory"]> = { title: "Chief Security Officer", name: null, image: null };
  const info = await api<{ title: string; name: string | null; has_signature: boolean }>("/api/v1/credentials/identity-cards/signatory");
  if (!info.ok) return out;
  out.title = info.data.title || out.title;
  out.name = info.data.name;
  if (!info.data.has_signature) return out;
  try {
    const tok = await sessionToken();
    const office = (await cookies()).get("moaum_office")?.value;
    const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
    if (office) headers["X-Active-Office"] = office;
    const res = await fetch(`${API_URL}/api/v1/credentials/identity-cards/signatory/signature?format=jpeg`, { headers, cache: "no-store" });
    if (res.ok) {
      const buf = new Uint8Array(await res.arrayBuffer());
      const dim = jpegSize(buf);
      if (dim) out.image = { data: buf, width: dim.width, height: dim.height } satisfies Image;
    }
  } catch { /* the line alone */ }
  return out;
}
