package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.util.Currency;
import java.util.Objects;

public record ExecuteTransactionCommand(TransactionType type, BigDecimal amount, Currency currency) {
    public ExecuteTransactionCommand {
        Objects.requireNonNull(type, "type must not be null");
        Objects.requireNonNull(amount, "amount must not be null");
        Objects.requireNonNull(currency, "currency must not be null");
    }
}
