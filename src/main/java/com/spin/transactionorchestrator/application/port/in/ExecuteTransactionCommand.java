package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.util.Currency;

public record ExecuteTransactionCommand(String accountId, String description, TransactionType type, BigDecimal amount,
        Currency currency, String idempotencyKey) {
    public ExecuteTransactionCommand(TransactionType type, BigDecimal amount, Currency currency, String idempotencyKey) {
        this("legacy-account", null, type, amount, currency, idempotencyKey);
    }
}
