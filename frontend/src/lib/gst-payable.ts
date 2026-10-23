/**
 * V643: whether a student pays the GST fee now. A student pays it who owes it (a GST/EPS course requires it of them), or who is
 * shown a GST/EPS course on the registration page (the programme's at their level, of either curriculum while the curricula are
 * open) though not yet owing it — such a course is held on the registration form until the fee is paid. The server decides both
 * (finance.gst_entitlement, finance.gst_payable_courses); this only reads its answer.
 */
export interface GstPayableCourse { course_code: string; office: string | null }

export interface GstPayState {
  /** the fee is to be paid now: stated above nothing, not yet paid, and owed or shown */
  unpaid: boolean;
  /** the GST/EPS courses shown on the registration page that the fee is not yet owed for (empty when it is owed) */
  shown: string[];
  /** whether a GST course, or an EPS course, is among those shown */
  gstShown: boolean;
  epsShown: boolean;
}

export function gstPayState(e: { required: boolean; stated: boolean; entitled: boolean; fee: number | string },
                            payable: GstPayableCourse[] | null | undefined): GstPayState {
  const notOwed = e.required ? [] : (payable ?? []);
  const shown = notOwed.map((p) => p.course_code);
  return {
    unpaid: (e.required || shown.length > 0) && e.stated && !e.entitled && Number(e.fee) > 0,
    shown,
    gstShown: notOwed.some((p) => p.office !== "EPS"),
    epsShown: notOwed.some((p) => p.office === "EPS"),
  };
}
