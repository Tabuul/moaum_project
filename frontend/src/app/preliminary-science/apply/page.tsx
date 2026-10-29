import { PrelimApplyPage } from "@/components/preliminary/PrelimApplyPage";

export const dynamic = "force-dynamic";

/** The Preliminary Science application's first step (V446), on the shared preliminary apply page (V701) */
export default async function PrelimApplyRoute() {
  return <PrelimApplyPage slug="preliminary-science" />;
}
