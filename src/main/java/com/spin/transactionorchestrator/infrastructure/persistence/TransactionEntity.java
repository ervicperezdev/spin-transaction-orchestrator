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

    @Column(name = "provider_reference", length = 255)
    private String providerReference;

    @Column(name = "rejection_reason", length = 255)
    private String rejectionReason;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    protected TransactionEntity() {
        // Required by JPA.
    }

    TransactionEntity(UUID id, TransactionType type, TransactionStatus status, BigDecimal amount, String currency,
            String providerReference, String rejectionReason, Instant createdAt) {
        this.id = id;
        this.type = type;
        this.status = status;
        this.amount = amount;
        this.currency = currency;
        this.providerReference = providerReference;
        this.rejectionReason = rejectionReason;
        this.createdAt = createdAt;
    }

    UUID id() { return id; }
    TransactionType type() { return type; }
    TransactionStatus status() { return status; }
    BigDecimal amount() { return amount; }
    String currency() { return currency; }
    String providerReference() { return providerReference; }
    String rejectionReason() { return rejectionReason; }
    Instant createdAt() { return createdAt; }
}
