package ng.edu.moaum.portal;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

/**
 * The module boundaries hold (ARC rule M1): a module may import another
 * module's published API only. A violation fails the build, not a code
 * review (ADR-003). No Spring context, no database — the check is structural.
 */
class ModularityTests {

    @Test
    void moduleBoundariesHold() {
        ApplicationModules modules = ApplicationModules.of(PortalApiApplication.class);
        modules.verify();
        modules.forEach(module -> System.out.println("module: " + module.getDisplayName()));
    }
}
