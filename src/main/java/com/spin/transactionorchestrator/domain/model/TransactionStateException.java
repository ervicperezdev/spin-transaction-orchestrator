package com.spin.transactionorchestrator.domain.model;

public class TransactionStateException extends RuntimeException {
    public TransactionStateException(String message) {
        super(message);
    }
}
