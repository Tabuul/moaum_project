import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { TransferReview, type Review } from "./TransferReview";

export const dynamic = "force-dynamic";

/** /transfers/[id] — V734: one inter-departmental transfer application reviewed: the student's academic profile, each side's department,
 *  faculty and College, the reason, the old portal's documents, what is paid, every decision so far, and the desk's Approve or Decline */
export default async function TransferReviewPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, review] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Review>(`/api/v1/transfers/${encodeURIComponent(id)}`),
  ]);
  return (
    <Shell route="t/transfers" me={me.ok ? me.data : null}>
      {review.ok ? <TransferReview review={review.data} /> : <ProblemNotice problem={review.problem} />}
    </Shell>
  );
}
