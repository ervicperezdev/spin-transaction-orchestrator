package com.spin.transactionorchestrator.infrastructure.persistence;

import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.sql.Types;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.JdbcTypeCode;

@Entity
@Table(name = "transactions")
class TransactionEntity {
    @Id
    private UUID id;
    @Column(name = "account_id", nullable = false, length = 128)
    private String accountId;
    @Column(length = 500)
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private TransactionType type;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 16)
    private TransactionStatus status;

    @Column(nullable = false, precision = 19, scale = 2)
    private BigDecimal amount;

    @JdbcTypeCode(Types.CHAR)
    @Column(nullable = false, length = 3, columnDefinition = "char(3)")
    private String currency;

    @Column(name = "provider_transaction_id", length = 255)
    private String providerTransactionId;
    @Column(name = "balance_after", precision = 19, scale = 2)
    private BigDecimal balanceAfter;
    @Column(name = "rejection_code", length = 64)
    private String rejectionCode;

    @Column(name = "rejection_reason", length = 255)
    private String rejectionReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "idempotency_key", unique = true, length = 255)
    private String idempotencyKey;

    protected TransactionEntity() {
        // Required by JPA.
    }

    TransactionEntity(UUID id, String accountId, String description, TransactionType type, TransactionStatus status, BigDecimal amount, String currency,
            String providerTransactionId, BigDecimal balanceAfter, String rejectionCode, String rejectionReason, Instant createdAt, String idempotencyKey) {
        this.id = id;
        this.accountId = accountId;
        this.description = description;
        this.type = type;
        this.status = status;
        this.amount = amount;
        this.currency = currency;
        this.providerTransactionId = providerTransactionId;
        this.balanceAfter = balanceAfter;
        this.rejectionCode = rejectionCode;
        this.rejectionReason = rejectionReason;
        this.createdAt = createdAt;
        this.idempotencyKey = idempotencyKey;
    }

    UUID id() { return id; }
    String accountId() { return accountId; }
    String description() { return description; }
    TransactionType type() { return type; }
    TransactionStatus status() { return status; }
    BigDecimal amount() { return amount; }
    String currency() { return currency; }
    String providerTransactionId() { return providerTransactionId; }
    BigDecimal balanceAfter() { return balanceAfter; }
    String rejectionCode() { return rejectionCode; }
    String rejectionReason() { return rejectionReason; }
    Instant createdAt() { return createdAt; }
    String idempotencyKey() { return idempotencyKey; }
}
