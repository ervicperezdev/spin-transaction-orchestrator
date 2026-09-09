package com.spin.transactionorchestrator.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Currency;
import org.junit.jupiter.api.Test;

class TransactionEntityMapperTest {
    private final TransactionEntityMapper mapper = new TransactionEntityMapper();

    @Test
    void roundTripsAnApprovedTransactionWithoutLosingMonetaryOrTerminalStateData() {
        Instant createdAt = Instant.parse("2026-09-08T04:05:06.123456Z");
        Transaction transaction = Transaction.pending(TransactionType.DEBIT, new BigDecimal("9999.99"), mxn(), createdAt, null);
        transaction.approve("provider-123");

        Transaction rehydrated = mapper.toDomain(mapper.toEntity(transaction));

        assertThat(rehydrated.id()).isEqualTo(transaction.id());
        assertThat(rehydrated.amount()).isEqualByComparingTo("9999.99");
        assertThat(rehydrated.currency()).isEqualTo(mxn());
        assertThat(rehydrated.createdAt()).isEqualTo(createdAt);
        assertThat(rehydrated.status()).isEqualTo(TransactionStatus.APPROVED);
        assertThat(rehydrated.providerReference()).isEqualTo("provider-123");
    }

    @Test
    void roundTripsARejectedTransactionWithoutLosingTerminalStateData() {
        Transaction transaction = Transaction.pending(TransactionType.CREDIT, new BigDecimal("25.50"), mxn(), Instant.EPOCH, null);
        transaction.reject("Insufficient balance");

        Transaction rehydrated = mapper.toDomain(mapper.toEntity(transaction));

        assertThat(rehydrated.status()).isEqualTo(TransactionStatus.REJECTED);
        assertThat(rehydrated.rejectionReason()).isEqualTo("Insufficient balance");
        assertThat(rehydrated.providerReference()).isNull();
    }

    private Currency mxn() {
        return Currency.getInstance("MXN");
    }
}
