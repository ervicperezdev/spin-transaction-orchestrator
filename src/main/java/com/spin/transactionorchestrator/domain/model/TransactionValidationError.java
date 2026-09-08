package com.spin.transactionorchestrator.domain.model;

public enum TransactionValidationError {
    INVALID_TRANSACTION_TYPE,
    INVALID_AMOUNT,
    UNSUPPORTED_CURRENCY,
    DEBIT_AMOUNT_LIMIT_EXCEEDED
}
