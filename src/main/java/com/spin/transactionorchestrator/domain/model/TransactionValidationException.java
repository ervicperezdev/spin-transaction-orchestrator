package com.spin.transactionorchestrator.domain.model;

public class TransactionValidationException extends RuntimeException {
    private final TransactionValidationError error;

    public TransactionValidationException(TransactionValidationError error, String message) {
        super(message);
        this.error = error;
    }

    public TransactionValidationError error() {
        return error;
    }
}
