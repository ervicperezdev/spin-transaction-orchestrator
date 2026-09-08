package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.util.Currency;

public record ExecuteTransactionCommand(TransactionType type, BigDecimal amount, Currency currency,
        String idempotencyKey) {
}
