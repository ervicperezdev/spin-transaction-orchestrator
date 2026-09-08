package com.spin.transactionorchestrator.application.service;

import com.spin.transactionorchestrator.application.port.in.FindTransactions;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.List;
import java.util.Objects;

public class FindTransactionsService implements FindTransactions {
    private final TransactionRepository repository;

    public FindTransactionsService(TransactionRepository repository) {
        this.repository = Objects.requireNonNull(repository, "repository must not be null");
    }

    @Override
    public List<Transaction> findAll() {
        return repository.findAll();
    }
}
