import { AuthLayout } from "@/components/auth/AuthLayout";
import { StatusView } from "./StatusView";
import "../../partnerships.css";

export const dynamic = "force-dynamic";
export const metadata = { title: "Your collaboration enquiry", robots: { index: false, follow: false } };

/** /partnerships/status/{token} — an applicant follows their enquiry by its private link (V658); no session, nothing internal */
export default async function PartnershipStatusPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return (
    <AuthLayout eyebrow="Partnerships" wide legal>
      <div className="card"><div className="card__body ptn-public">
        <StatusView token={token} />
      </div></div>
    </AuthLayout>
  );
}
