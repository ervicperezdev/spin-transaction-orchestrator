package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.Transaction;
public interface FindTransactions {
    TransactionPage find(FindTransactionsQuery query);
}
