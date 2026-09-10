package com.spin.transactionorchestrator.domain.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Currency;
import java.util.Objects;
import java.util.UUID;

public final class Transaction {
    private final UUID id;
    private final String accountId;
    private final String description;
    private final TransactionType type;
    private final BigDecimal amount;
    private final Currency currency;
    private final Instant createdAt;
    private TransactionStatus status;
    private String providerTransactionId;
    private BigDecimal balanceAfter;
    private String rejectionCode;
    private String rejectionReason;
    private final String idempotencyKey;

    private Transaction(UUID id, String accountId, String description, TransactionType type, BigDecimal amount, Currency currency, Instant createdAt,
            String idempotencyKey) {
        this.id = Objects.requireNonNull(id, "id must not be null");
        this.accountId = requireText(accountId, "accountId must not be blank");
        this.description = description;
        this.type = Objects.requireNonNull(type, "type must not be null");
        this.amount = Objects.requireNonNull(amount, "amount must not be null");
        this.currency = Objects.requireNonNull(currency, "currency must not be null");
        this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
        this.status = TransactionStatus.PENDING;
        this.idempotencyKey = idempotencyKey;
    }

    public static Transaction pending(TransactionType type, BigDecimal amount, Currency currency, Instant createdAt,
            String idempotencyKey) {
        return pending("legacy-account", null, type, amount, currency, createdAt, idempotencyKey);
    }
    public static Transaction pending(String accountId, String description, TransactionType type, BigDecimal amount, Currency currency, Instant createdAt,
            String idempotencyKey) {
        return new Transaction(UUID.randomUUID(), accountId, description, type, amount, currency, createdAt, idempotencyKey);
    }

    /**
     * Reconstitutes a transaction previously persisted by the repository adapter.
     * Terminal-state payloads are validated here so invalid persistence data cannot
     * create a domain object that could not have been reached through its behavior.
     */
    public static Transaction rehydrate(UUID id, String accountId, String description, TransactionType type, BigDecimal amount, Currency currency,
            Instant createdAt, TransactionStatus status, String providerTransactionId, BigDecimal balanceAfter, String rejectionCode, String rejectionReason,
            String idempotencyKey) {
        Transaction transaction = new Transaction(id, accountId, description, type, amount, currency, createdAt, idempotencyKey);
        transaction.status = Objects.requireNonNull(status, "status must not be null");

        switch (status) {
            case PENDING -> {
                if (providerTransactionId != null || balanceAfter != null || rejectionReason != null) {
                    throw new IllegalArgumentException("Pending transactions must not contain a terminal-state payload");
                }
            }
            case APPROVED -> {
                transaction.providerTransactionId = transaction.requireText(providerTransactionId,
                        "providerTransactionId must not be blank for approved transactions");
                transaction.balanceAfter = Objects.requireNonNull(balanceAfter, "balanceAfter must not be null for approved transactions");
                if (rejectionReason != null) {
                    throw new IllegalArgumentException("Approved transactions must not contain a rejection reason");
                }
            }
            case REJECTED -> {
                transaction.rejectionReason = transaction.requireText(rejectionReason,
                        "rejection reason must not be blank for rejected transactions");
                transaction.providerTransactionId = providerTransactionId;
                transaction.rejectionCode = rejectionCode;
            }
        }
        return transaction;
    }

    public void approve(String providerTransactionId, BigDecimal balanceAfter) {
        ensurePending();
        this.status = TransactionStatus.APPROVED;
        this.providerTransactionId = requireText(providerTransactionId, "providerTransactionId must not be blank");
        this.balanceAfter = Objects.requireNonNull(balanceAfter, "balanceAfter must not be null");
    }
    public void approve(String providerTransactionId) { approve(providerTransactionId, BigDecimal.ZERO); }

    public void reject(String providerTransactionId, String code, String reason) {
        ensurePending();
        this.status = TransactionStatus.REJECTED;
        this.rejectionReason = requireText(reason, "rejection reason must not be blank");
        this.providerTransactionId = providerTransactionId;
        this.rejectionCode = code;
    }
    public void reject(String reason) { reject(null, null, reason); }

    private void ensurePending() {
        if (status != TransactionStatus.PENDING) {
            throw new TransactionStateException("Only pending transactions can be finalized");
        }
    }

    private String requireText(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new IllegalArgumentException(message);
        }
        return value;
    }

    public UUID id() { return id; }
    public String accountId() { return accountId; }
    public String description() { return description; }
    public TransactionType type() { return type; }
    public BigDecimal amount() { return amount; }
    public Currency currency() { return currency; }
    public Instant createdAt() { return createdAt; }
    public TransactionStatus status() { return status; }
    public String providerTransactionId() { return providerTransactionId; }
    public BigDecimal balanceAfter() { return balanceAfter; }
    public String rejectionCode() { return rejectionCode; }
    /** @deprecated use providerTransactionId. */
    public String providerReference() { return providerTransactionId; }
    public String rejectionReason() { return rejectionReason; }
    public String idempotencyKey() { return idempotencyKey; }
}
