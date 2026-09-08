package com.spin.transactionorchestrator.domain.model;

import java.math.BigDecimal;
import java.util.Currency;

public final class TransactionRules {
    private static final BigDecimal MINIMUM_AMOUNT = new BigDecimal("1.00");
    private static final BigDecimal MAXIMUM_DEBIT_AMOUNT = new BigDecimal("10000.00");
    private static final Currency MXN = Currency.getInstance("MXN");

    private TransactionRules() {
    }

    public static void validate(TransactionType type, BigDecimal amount, Currency currency) {
        if (type == null) {
            throw new TransactionValidationException(
                    TransactionValidationError.INVALID_TRANSACTION_TYPE, "Transaction type must be CREDIT or DEBIT");
        }
        if (amount == null || amount.compareTo(MINIMUM_AMOUNT) <= 0) {
            throw new TransactionValidationException(
                    TransactionValidationError.INVALID_AMOUNT, "Amount must be greater than 1.00 MXN");
        }
        if (!MXN.equals(currency)) {
            throw new TransactionValidationException(
                    TransactionValidationError.UNSUPPORTED_CURRENCY, "Only MXN currency is supported");
        }
        if (type == TransactionType.DEBIT && amount.compareTo(MAXIMUM_DEBIT_AMOUNT) > 0) {
            throw new TransactionValidationException(
                    TransactionValidationError.DEBIT_AMOUNT_LIMIT_EXCEEDED, "DEBIT amount must not exceed 10000.00 MXN");
        }
    }
}
