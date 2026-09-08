package com.spin.transactionorchestrator.infrastructure.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Currency;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@Import({PostgresTransactionRepository.class, TransactionEntityMapper.class})
@Testcontainers(disabledWithoutDocker = true)
class PostgresTransactionRepositoryIntegrationTest {
    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine")
            .withDatabaseName("transactions")
            .withUsername("transactions_app")
            .withPassword("transactions_app");

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Autowired
    private PostgresTransactionRepository repository;

    @Test
    void preservesApprovedTransactionAcrossPostgresRoundTrip() {
        Instant createdAt = Instant.parse("2026-09-08T04:05:06.123456Z");
        Transaction transaction = Transaction.pending(TransactionType.DEBIT, new BigDecimal("9999.99"), mxn(), createdAt);
        transaction.approve("provider-123");

        Transaction persisted = repository.save(transaction);
        Transaction rehydrated = repository.findAll().getFirst();

        assertThat(rehydrated.id()).isEqualTo(persisted.id());
        assertThat(rehydrated.amount()).isEqualByComparingTo("9999.99");
        assertThat(rehydrated.currency()).isEqualTo(mxn());
        assertThat(rehydrated.createdAt()).isEqualTo(createdAt);
        assertThat(rehydrated.status()).isEqualTo(TransactionStatus.APPROVED);
        assertThat(rehydrated.providerReference()).isEqualTo("provider-123");
        assertThat(rehydrated.rejectionReason()).isNull();
    }

    @Test
    void preservesRejectedTransactionAcrossPostgresRoundTrip() {
        Instant createdAt = Instant.parse("2026-09-08T04:05:07Z");
        Transaction transaction = Transaction.pending(TransactionType.CREDIT, new BigDecimal("25.50"), mxn(), createdAt);
        transaction.reject("Insufficient balance");

        repository.save(transaction);
        Transaction rehydrated = repository.findAll().getFirst();

        assertThat(rehydrated.amount()).isEqualByComparingTo("25.50");
        assertThat(rehydrated.currency()).isEqualTo(mxn());
        assertThat(rehydrated.createdAt()).isEqualTo(createdAt);
        assertThat(rehydrated.status()).isEqualTo(TransactionStatus.REJECTED);
        assertThat(rehydrated.providerReference()).isNull();
        assertThat(rehydrated.rejectionReason()).isEqualTo("Insufficient balance");
    }

    private Currency mxn() {
        return Currency.getInstance("MXN");
    }
}
