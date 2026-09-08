package com.spin.transactionorchestrator.application.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.List;
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
            public List<Transaction> findAll() {
                return List.of();
            }
        };

        assertThat(new FindTransactionsService(repository).findAll()).isEmpty();
    }
}
