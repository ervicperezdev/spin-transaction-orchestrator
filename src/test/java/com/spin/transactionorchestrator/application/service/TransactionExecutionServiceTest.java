package com.spin.transactionorchestrator.application.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransactionCommand;
import com.spin.transactionorchestrator.application.port.out.PaymentProvider;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderResult;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Currency;
import java.util.List;
import org.junit.jupiter.api.Test;

class TransactionExecutionServiceTest {
    private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-09-08T00:00:00Z"), ZoneOffset.UTC);

    @Test
    void savesAnApprovedTransactionWithProviderReference() {
        InMemoryRepository repository = new InMemoryRepository();
        PaymentProvider provider = transaction -> PaymentProviderResult.approved("provider-123");
        TransactionExecutionService service = new TransactionExecutionService(repository, provider, CLOCK);

        Transaction result = service.execute(command());

        assertThat(result.status()).isEqualTo(TransactionStatus.APPROVED);
        assertThat(result.providerReference()).isEqualTo("provider-123");
        assertThat(result.rejectionReason()).isNull();
        assertThat(repository.transactions).containsExactly(result);
    }

    @Test
    void savesARejectedTransactionWithReason() {
        InMemoryRepository repository = new InMemoryRepository();
        PaymentProvider provider = transaction -> PaymentProviderResult.rejected("insufficient funds");
        TransactionExecutionService service = new TransactionExecutionService(repository, provider, CLOCK);

        Transaction result = service.execute(command());

        assertThat(result.status()).isEqualTo(TransactionStatus.REJECTED);
        assertThat(result.rejectionReason()).isEqualTo("insufficient funds");
        assertThat(result.providerReference()).isNull();
        assertThat(repository.transactions).containsExactly(result);
    }

    private ExecuteTransactionCommand command() {
        return new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("25.50"), Currency.getInstance("MXN"));
    }

    private static final class InMemoryRepository implements TransactionRepository {
        private final List<Transaction> transactions = new ArrayList<>();

        @Override
        public Transaction save(Transaction transaction) {
            transactions.add(transaction);
            return transaction;
        }

        @Override
        public List<Transaction> findAll() {
            return List.copyOf(transactions);
        }
    }
}
