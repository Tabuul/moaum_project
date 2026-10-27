import { AuthLayout } from "@/components/auth/AuthLayout";
import { ConsentView } from "./ConsentView";
import "../../transcripts.css";

export const dynamic = "force-dynamic";
export const metadata = { title: "Consent to a transcript request", robots: { index: false, follow: false } };

/** /transcripts/consent/{token} — the graduate agrees, or not, to an institution's request for their transcript (V668) */
export default async function TranscriptConsentPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return (
    <AuthLayout eyebrow="Transcripts" wide legal>
      <div className="card"><div className="card__body trn-public">
        <ConsentView token={token} />
      </div></div>
    </AuthLayout>
  );
}
