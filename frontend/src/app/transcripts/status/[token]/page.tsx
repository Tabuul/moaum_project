import { AuthLayout } from "@/components/auth/AuthLayout";
import { StatusView } from "./StatusView";
import "../../transcripts.css";

export const dynamic = "force-dynamic";
export const metadata = { title: "Your transcript request", robots: { index: false, follow: false } };

/** /transcripts/status/{token} — a transcript request followed by its private link (V668); no session, nothing internal */
export default async function TranscriptStatusPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return (
    <AuthLayout eyebrow="Transcripts" wide legal>
      <div className="card"><div className="card__body trn-public">
        <StatusView token={token} />
      </div></div>
    </AuthLayout>
  );
}
