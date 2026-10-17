import { NextRequest } from "next/server";
import { leaveSupportView } from "../leave";

/** V521: the agent leaves the student's portal — the view ended on the API, the agent's own session back */
export async function POST(request: NextRequest) {
  return leaveSupportView(request);
}
