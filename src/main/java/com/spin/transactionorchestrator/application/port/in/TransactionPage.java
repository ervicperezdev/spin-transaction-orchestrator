package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.List;
import java.util.Objects;

/** A bounded, stable-order page returned by the transaction query use case. */
public record TransactionPage(List<Transaction> items, int page, int size, long totalItems, int totalPages) {
    public TransactionPage {
        items = List.copyOf(Objects.requireNonNull(items, "items must not be null"));
        if (page < 0 || size < 1 || totalItems < 0 || totalPages < 0) {
            throw new IllegalArgumentException("page metadata is invalid");
        }
    }
}
