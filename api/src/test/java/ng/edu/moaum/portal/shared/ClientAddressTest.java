package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** V359: which X-Forwarded-For entry is the person's, and what is not trusted */
class ClientAddressTest {

    @Test
    void railwaysEdgeWritesTheFirstEntryAndALoadBalancerTheLast() {
        assertThat(ClientAddress.pick("102.89.1.7", "10.250.3.4", true)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("1.2.3.4, 102.89.1.7", "10.0.0.5", false)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("1.2.3.4, 102.89.1.7", "10.0.0.5", true)).isEqualTo("1.2.3.4");
        assertThat(ClientAddress.first("first", null)).isTrue();
        assertThat(ClientAddress.first("last", "some-environment")).isFalse();
        assertThat(ClientAddress.first(null, "some-environment")).isTrue();
        assertThat(ClientAddress.first(null, null)).isFalse();
    }

    @Test
    void withoutAHeaderTheConnectionItselfAndNothingThatIsNotAnAddress() {
        assertThat(ClientAddress.pick(null, "127.0.0.1", true)).isEqualTo("127.0.0.1");
        assertThat(ClientAddress.pick("", "0:0:0:0:0:0:0:1", false)).isEqualTo("0:0:0:0:0:0:0:1");
        assertThat(ClientAddress.pick("102.89.1.7:51234", null, true)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("[2001:db8::1]", null, true)).isEqualTo("2001:db8::1");
        assertThat(ClientAddress.pick("evil.example.com", "10.0.0.5", true)).isEqualTo("10.0.0.5");
        assertThat(ClientAddress.pick("'; DROP TABLE x; --", null, false)).isNull();
        assertThat(ClientAddress.local("127.0.0.1")).isTrue();
        assertThat(ClientAddress.local("102.89.1.7")).isFalse();
    }
}
