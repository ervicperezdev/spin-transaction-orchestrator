package com.spin.transactionorchestrator.adapter.in.rest;

final class InvalidTransactionRequestException extends RuntimeException {
    InvalidTransactionRequestException() { super("Invalid transaction request"); }
}
