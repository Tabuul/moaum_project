import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/** Portal gap audit: the student never downloads or prints the identity card — it is printed and issued by the card desk and handed
 *  over in person; the student's page shows its status (issued, valid to, lost, replaced). The address answers so an old link explains. */
export async function GET() {
  return NextResponse.json({ status: 403, title: "The identity card is issued by the card desk",
    detail: "Your card is printed and handed over in person; the ID card page shows its status." }, { status: 403 });
}
