import { PrelimApplyPage } from "@/components/preliminary/PrelimApplyPage";

export const dynamic = "force-dynamic";

/** /preliminary-technology/apply — the application's first step (V701), on the shared preliminary apply page */
export default async function PreliminaryTechnologyApplyPage() {
  return <PrelimApplyPage slug="preliminary-technology" />;
}
