package com.spin.transactionorchestrator.application.port.out;

import java.util.Objects;
import java.math.BigDecimal;

public record PaymentProviderResult(PaymentProviderStatus status, String providerTransactionId, BigDecimal balance,
        String rejectionCode, String rejectionReason) {
    public PaymentProviderResult {
        Objects.requireNonNull(status, "status must not be null");
    }

    public static PaymentProviderResult approved(String providerTransactionId, BigDecimal balance) {
        return new PaymentProviderResult(PaymentProviderStatus.APPROVED, providerTransactionId, balance, null, null);
    }

    public static PaymentProviderResult approved(String providerTransactionId) {
        return approved(providerTransactionId, BigDecimal.ZERO);
    }

    public static PaymentProviderResult rejected(String providerTransactionId, String code, String reason) {
        return new PaymentProviderResult(PaymentProviderStatus.REJECTED, providerTransactionId, null, code, reason);
    }

    public static PaymentProviderResult rejected(String reason) {
        return rejected(null, null, reason);
    }
}
