import { NextResponse } from "next/server";
import { deflateSync } from "node:zlib";
import { cookies } from "next/headers";
import { api, API_URL } from "@/lib/api";
import { publicOrigin } from "@/lib/public-origin";
import { sessionToken } from "@/lib/session";
import { jpegSize, type Image, type Page } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { loadInstitution } from "@/lib/document/institution-server";
import { cardSignatory } from "@/lib/idcard-signatory-server";
import { finishPdf } from "@/lib/document/pdf";
import type { LiveStaffCard } from "@/lib/staff-card-face";
import { staffCardPage } from "@/lib/staff-card-page";

export const dynamic = "force-dynamic";

/**
 * V698: every staff identity card in force as one PDF, a card (front and back) to a page, names A–Z — for the Security Unit to print
 * them all, or a faculty's, a unit's, the ones a search finds or the ones ticked (?faculty, ?unit, ?q, ?ids). The API holds it to the
 * Security Unit (and super) and reads the cards from the register; a card's photograph is the one on file, a blank frame without.
 */
export async function GET(req: Request) {
  await loadInstitution();
  const url = new URL(req.url);
  const q = new URLSearchParams();
  for (const k of ["faculty", "unit", "q"]) { const v = url.searchParams.get(k); if (v) q.set(k, v); }
  for (const v of (url.searchParams.get("ids") ?? "").split(",").map((x) => x.trim()).filter(Boolean)) q.append("ids", v);
  const r = await api<{ cards: (LiveStaffCard & { person_id: string })[] }>(`/api/v1/credentials/identity-cards/staff/print${q.size ? `?${q.toString()}` : ""}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const cards = r.data.cards.filter((c) => c.face?.staff_number);
  if (!cards.length) {
    return NextResponse.json({ status: 404, title: "No staff card in force to print", detail: "Issue the cards on the Staff ID Cards desk first; the print carries each card's number." }, { status: 404 });
  }

  // the photographs on file, a few at a time; the writer embeds JPEG, so a PNG photograph leaves its frame blank
  const tok = await sessionToken();
  const office = (await cookies()).get("moaum_office")?.value ?? process.env.PORTAL_ACTIVE_OFFICE;
  const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
  if (office) headers["X-Active-Office"] = office;
  const photos = new Map<string, Image>();
  const want = cards.filter((c) => c.face.has_photo);
  for (let i = 0; i < want.length; i += 8) {
    await Promise.all(want.slice(i, i + 8).map(async (c) => {
      try {
        const res = await fetch(`${API_URL}/api/v1/credentials/identity-cards/staff/${encodeURIComponent(c.person_id)}/photo`, { headers, cache: "no-store" });
        if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
          const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf);
          if (dim) photos.set(c.person_id, { data: buf, width: dim.width, height: dim.height });
        }
      } catch { /* the blank frame */ }
    }));
  }

  // the crest and the signature drawn once and shared by every page (the writer embeds each image once)
  const crest = crestImage();
  const signatory = await cardSignatory();
  const pages: Page[] = [];
  const origin = publicOrigin(req);
  for (const c of cards) {
    const p = staffCardPage(c, photos.get(c.person_id) ?? null, crest, signatory, origin);
    if (p) pages.push(p);
  }
  const what = url.searchParams.get("unit") ? `unit ${url.searchParams.get("unit")}` : url.searchParams.get("faculty") ? `faculty ${url.searchParams.get("faculty")}` : "all";
  // the cards' drawing compressed: some 66 KB a page uncompressed, a print of every card runs to thousands of pages
  const bytes = finishPdf(pages, `Staff identity cards (${pages.length}) · ${what}`, "ID_CARD", {}, { deflate: (b) => deflateSync(b) });
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="staff-id-cards-${what.replace(/[^A-Za-z0-9]+/g, "-")}-${pages.length}.pdf"` },
  });
}
