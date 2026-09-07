/**
 * The shared kernel (DSN §3): typed values every module needs and no business
 * behaviour. It is the only package every other module may depend on
 * (ARC rule M7), and it is OPEN so that its whole surface is that API.
 */
@org.springframework.modulith.ApplicationModule(type = org.springframework.modulith.ApplicationModule.Type.OPEN)
package ng.edu.moaum.portal.shared;
