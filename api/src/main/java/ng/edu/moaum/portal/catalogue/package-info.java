/**
 * The course catalogue (V042): a department owns its courses and creates them,
 * into BOARD state — making one live is a curriculum change the Faculty Board
 * and Senate decide. Ending a course dates it and keeps it on every transcript
 * that carries it; nothing here is ever removed.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Course catalogue")
package ng.edu.moaum.portal.catalogue;
