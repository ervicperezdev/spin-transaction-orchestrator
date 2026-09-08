package com.spin.transactionorchestrator.application.service;

import com.spin.transactionorchestrator.application.port.in.FindTransactions;
import com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery;
import com.spin.transactionorchestrator.application.port.in.TransactionPage;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import java.util.Objects;

public class FindTransactionsService implements FindTransactions {
    private final TransactionRepository repository;

    public FindTransactionsService(TransactionRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository must not be null");
    }

    @Override
    public TransactionPage find(FindTransactionsQuery query) {
        return repository.find(Objects.requireNonNull(query, "query must not be null"));
    }
}
