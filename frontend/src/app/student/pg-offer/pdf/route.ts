import { pgOfferResponse } from "@/lib/pg-offer-pdf";

export const dynamic = "force-dynamic";

/** V389: the PG student's own offer of admission, from the application that became their student record */
export async function GET(req: Request) {
  return pgOfferResponse(req, "/api/v1/pg/student/application");
}
