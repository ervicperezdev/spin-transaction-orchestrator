package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;

/** Transport-neutral query for a bounded transaction search. */
public record FindTransactionsQuery(int page, int size, TransactionStatus status, TransactionType type) {
    public FindTransactionsQuery {
        if (page < 0) throw new IllegalArgumentException("page must be zero or greater");
        if (size < 1 || size > 100) throw new IllegalArgumentException("size must be between 1 and 100");
    }
}
