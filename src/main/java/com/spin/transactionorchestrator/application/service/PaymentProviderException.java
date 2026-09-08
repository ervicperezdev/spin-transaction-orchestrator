package com.spin.transactionorchestrator.application.service;

public class PaymentProviderException extends RuntimeException {
    public PaymentProviderException(String message) {
        super(message);
    }
}
