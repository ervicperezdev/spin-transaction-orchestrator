package com.spin.transactionorchestrator.application.port.out;

import java.util.Objects;

public record PaymentProviderResult(PaymentProviderStatus status, String reference, String rejectionReason) {
    public PaymentProviderResult {
        Objects.requireNonNull(status, "status must not be null");
    }

    public static PaymentProviderResult approved(String reference) {
        return new PaymentProviderResult(PaymentProviderStatus.APPROVED, reference, null);
    }

    public static PaymentProviderResult rejected(String reason) {
        return new PaymentProviderResult(PaymentProviderStatus.REJECTED, null, reason);
    }
}
