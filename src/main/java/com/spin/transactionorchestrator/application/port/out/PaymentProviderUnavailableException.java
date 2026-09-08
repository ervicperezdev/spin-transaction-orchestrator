package com.spin.transactionorchestrator.application.port.out;

/** Raised when the provider cannot return a business decision. */
public class PaymentProviderUnavailableException extends RuntimeException {
    public PaymentProviderUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }

    public PaymentProviderUnavailableException(String message) {
        super(message);
    }
}
