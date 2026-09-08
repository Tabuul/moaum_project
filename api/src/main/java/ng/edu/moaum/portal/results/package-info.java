/**
 * Score sheets and the chain they pass (assessment schema, V013): entry,
 * verification, the departmental board, the three faculty desks, Exams and
 * Records, Senate, publication. No desk is skipped, no two consecutive
 * desks are one person, a mark is never overwritten, and nothing reaches a
 * student before the Senate minute. The examination session is the
 * container the sheets are generated in.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Results")
package ng.edu.moaum.portal.results;
