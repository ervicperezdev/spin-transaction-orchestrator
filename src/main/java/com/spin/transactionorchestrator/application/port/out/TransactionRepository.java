package com.spin.transactionorchestrator.application.port.out;

import com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery;
import com.spin.transactionorchestrator.application.port.in.TransactionPage;
import com.spin.transactionorchestrator.domain.model.Transaction;

public interface TransactionRepository {
    Transaction save(Transaction transaction);

    TransactionPage find(FindTransactionsQuery query);
}
