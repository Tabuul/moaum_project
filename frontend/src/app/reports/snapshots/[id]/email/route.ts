import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { buildXlsx } from "@/lib/xlsx";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { XlsxLogo } from "@/lib/xlsx";
import { keptReportPdf, type KeptReport } from "@/lib/report-pdf";

export const dynamic = "force-dynamic";

interface Snapshot {
  id: string; title: string; subtitle: string | null; period: string; headers: string; rows: string;
  verification_code: string; taken_at: string; taken_office: string | null; taken_by_name: string | null;
  filed_to: string | null; filed_at: string | null; note: string | null;
}

/** the crest as the workbook wants it (PNG with its size), read from the site's own files */
function crestPng(): XlsxLogo | undefined {
  try {
    const buf = readFileSync(join(process.cwd(), "public", "crest.png"));
    const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    if (dv.getUint32(0) !== 0x89504e47) return undefined;
    return { png: new Uint8Array(buf), w: dv.getUint32(16), h: dv.getUint32(20) };
  } catch {
    return undefined;
  }
}

const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

/** POST /reports/snapshots/[id]/email — build the kept copy's PDF and Excel workbook on the server
 *  and queue them to the recipients through the API's outbox (V230). The files are built from the
 *  kept rows, never from the live register, so what is sent is what was kept. */
export async function POST(req: Request, ctx: { params: Promise<{ id: string }> }) {
  const { id } = await ctx.params;
  const body = (await req.json().catch(() => null)) as { to?: string[]; message?: string } | null;
  const to = Array.isArray(body?.to) ? body!.to.map(String) : [];
  if (!to.length) return NextResponse.json({ status: 400, title: "Give at least one email address" }, { status: 400 });

  const snap = await api<Snapshot>(`/api/v1/reports/snapshots/${encodeURIComponent(id)}`);
  if (!snap.ok) return NextResponse.json(snap.problem, { status: snap.problem.status });
  const s = snap.data;
  const headers = JSON.parse(s.headers) as string[];
  const rows = JSON.parse(s.rows) as (string | number | null)[][];
  const base = `${slug(s.title)}-${slug(s.period)}`;

  const kept: KeptReport = { ...s, headers, rows };
  const pdfBytes = keptReportPdf(kept);
  const xlsx = buildXlsx(headers, rows, "Kept copy", {
    school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI",
    title: `${s.title} · ${s.period} · kept copy ${s.verification_code}`,
    date: "Kept " + new Date(s.taken_at).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }),
    logo: crestPng(),
  });
  const xlsxBytes = new Uint8Array(await xlsx.arrayBuffer());

  const r = await api<{ queued: { notice: string; to: string }[] }>(`/api/v1/reports/snapshots/${encodeURIComponent(id)}/email`, {
    method: "POST",
    reason: `Emailed ${s.title} for ${s.period} to ${to.length} recipient${to.length === 1 ? "" : "s"}`,
    body: {
      to, message: body?.message ?? null,
      attachments: [
        { filename: `${base}.pdf`, contentType: "application/pdf", base64: Buffer.from(pdfBytes).toString("base64") },
        { filename: `${base}.xlsx`, contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", base64: Buffer.from(xlsxBytes).toString("base64") },
      ],
    },
  });
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  return NextResponse.json(r.data);
}
