package ng.edu.moaum.portal.shared;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

/** V359: which X-Forwarded-For entry is the person's, and what is not trusted; Oct 2026: an entry counted from the end */
class ClientAddressTest {

    @Test
    void railwaysEdgeWritesTheFirstEntryAndALoadBalancerTheLast() {
        assertThat(ClientAddress.pick("102.89.1.7", "10.250.3.4", 0)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("1.2.3.4, 102.89.1.7", "10.0.0.5", 1)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("1.2.3.4, 102.89.1.7", "10.0.0.5", 0)).isEqualTo("1.2.3.4");
        assertThat(ClientAddress.entry("first", null)).isEqualTo(0);
        assertThat(ClientAddress.entry("last", "some-environment")).isEqualTo(1);
        assertThat(ClientAddress.entry(null, "some-environment")).isEqualTo(0);
        assertThat(ClientAddress.entry(null, null)).isEqualTo(1);
    }

    /** CloudFront in front of the load balancer: CloudFront appends the viewer, the balancer appends CloudFront */
    @Test
    void twoAppendingEdgesLeaveThePersonSecondFromLast() {
        assertThat(ClientAddress.entry("2", null)).isEqualTo(2);
        assertThat(ClientAddress.entry(" 2 ", "some-environment")).isEqualTo(2);
        assertThat(ClientAddress.entry("0", null)).isEqualTo(1);        // not a count: the default for the edge
        assertThat(ClientAddress.entry("second", null)).isEqualTo(1);
        // what the client wrote, the viewer as CloudFront saw it, CloudFront as the balancer saw it
        assertThat(ClientAddress.pick("1.2.3.4, 102.89.1.7, 13.32.121.34", "10.0.0.5", 2)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("102.89.1.7, 13.32.121.34", "10.0.0.5", 2)).isEqualTo("102.89.1.7");
        // a chain shorter than the count was written by the edges alone: its first entry is the person's
        assertThat(ClientAddress.pick("102.89.1.7", "10.0.0.5", 2)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("102.89.1.7, 13.32.121.34", "10.0.0.5", 3)).isEqualTo("102.89.1.7");
        // the entry picked is still checked: not an address, the connection's own
        assertThat(ClientAddress.pick("evil.example.com, 13.32.121.34", "10.0.0.5", 2)).isEqualTo("10.0.0.5");
    }

    @Test
    void withoutAHeaderTheConnectionItselfAndNothingThatIsNotAnAddress() {
        assertThat(ClientAddress.pick(null, "127.0.0.1", 0)).isEqualTo("127.0.0.1");
        assertThat(ClientAddress.pick("", "0:0:0:0:0:0:0:1", 1)).isEqualTo("0:0:0:0:0:0:0:1");
        assertThat(ClientAddress.pick("102.89.1.7:51234", null, 0)).isEqualTo("102.89.1.7");
        assertThat(ClientAddress.pick("[2001:db8::1]", null, 0)).isEqualTo("2001:db8::1");
        assertThat(ClientAddress.pick("evil.example.com", "10.0.0.5", 0)).isEqualTo("10.0.0.5");
        assertThat(ClientAddress.pick("'; DROP TABLE x; --", null, 1)).isNull();
        assertThat(ClientAddress.local("127.0.0.1")).isTrue();
        assertThat(ClientAddress.local("102.89.1.7")).isFalse();
    }
}
