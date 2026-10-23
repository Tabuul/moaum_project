/**
 * Database Operations (V640): the office whose Database Operators query, analyse, reconcile, classify and report from the
 * University's operational database through the application — examination readiness, the controlled query engine, saved and
 * shared reports, official report references, the query log and data quality. Every source of truth stays where it is (the
 * register, the classification engine, central finance, the registration engine, the programme structure, the results); this
 * module only reads them, held to the acting office's scope, in read-only transactions.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Database Operations")
package ng.edu.moaum.portal.dbops;
