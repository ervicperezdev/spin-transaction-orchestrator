package com.spin.transactionorchestrator.infrastructure.observability;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.util.Objects;

/** Records bounded-cardinality, provider-level signals only. */
public final class PaymentProviderMetrics {
    private static final String REQUESTS = "payment.provider.requests";
    private static final String LATENCY = "payment.provider.request.duration";
    private final MeterRegistry meterRegistry;

    public PaymentProviderMetrics(MeterRegistry meterRegistry) {
        this.meterRegistry = Objects.requireNonNull(meterRegistry, "meterRegistry must not be null");
    }

    public Timer.Sample start() {
        return Timer.start(meterRegistry);
    }

    public void record(Timer.Sample sample, String outcome) {
        meterRegistry.counter(REQUESTS, "outcome", outcome).increment();
        sample.stop(meterRegistry.timer(LATENCY, "outcome", outcome));
    }
}
