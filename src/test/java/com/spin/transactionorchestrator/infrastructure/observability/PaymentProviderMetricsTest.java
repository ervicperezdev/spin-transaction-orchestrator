package com.spin.transactionorchestrator.infrastructure.observability;

import static org.assertj.core.api.Assertions.assertThat;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

class PaymentProviderMetricsTest {
    @Test
    void recordsOnlyBoundedOutcomeTags() {
        SimpleMeterRegistry registry = new SimpleMeterRegistry();
        PaymentProviderMetrics metrics = new PaymentProviderMetrics(registry);

        metrics.record(metrics.start(), "approved");

        assertThat(registry.get("payment.provider.requests").tag("outcome", "approved").counter().count()).isOne();
        assertThat(registry.get("payment.provider.request.duration").tag("outcome", "approved").timer().count()).isOne();
    }
}
