package com.spin.transactionorchestrator.application.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery;
import com.spin.transactionorchestrator.application.port.in.TransactionPage;
import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class FindTransactionsServiceTest {
    @Test
    void delegatesTheQueryToTheRepository() {
        TransactionRepository repository = new TransactionRepository() {
            @Override
            public Transaction save(Transaction transaction) {
                return transaction;
            }

            @Override
            public TransactionPage find(FindTransactionsQuery query) {
                return new TransactionPage(java.util.List.of(), query.page(), query.size(), 0, 0);
            }

            @Override
            public Optional<Transaction> findByIdempotencyKey(String key) {
                return Optional.empty();
            }
        };

        assertThat(new FindTransactionsService(repository).find(new FindTransactionsQuery(0, 20, null, null)).items()).isEmpty();
    }
}
