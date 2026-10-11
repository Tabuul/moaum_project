import { pgOfferResponse } from "@/lib/pg-offer-pdf";

export const dynamic = "force-dynamic";

/** the applicant's confirmation of offer of admission, once the acceptance fee is paid */
export async function GET(req: Request) {
  return pgOfferResponse(req, "/api/v1/pg/me");
}
