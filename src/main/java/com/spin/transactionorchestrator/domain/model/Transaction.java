package com.spin.transactionorchestrator.domain.model;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.Currency;
import java.util.Objects;
import java.util.UUID;

public final class Transaction {
    private final UUID id;
    private final TransactionType type;
    private final BigDecimal amount;
    private final Currency currency;
    private final Instant createdAt;
    private TransactionStatus status;
    private String providerReference;
    private String rejectionReason;

    private Transaction(UUID id, TransactionType type, BigDecimal amount, Currency currency, Instant createdAt) {
        this.id = Objects.requireNonNull(id, "id must not be null");
        this.type = Objects.requireNonNull(type, "type must not be null");
        this.amount = Objects.requireNonNull(amount, "amount must not be null");
        this.currency = Objects.requireNonNull(currency, "currency must not be null");
        this.createdAt = Objects.requireNonNull(createdAt, "createdAt must not be null");
        this.status = TransactionStatus.PENDING;
    }

    public static Transaction pending(TransactionType type, BigDecimal amount, Currency currency, Instant createdAt) {
        return new Transaction(UUID.randomUUID(), type, amount, currency, createdAt);
    }

    /**
     * Reconstitutes a transaction previously persisted by the repository adapter.
     * Terminal-state payloads are validated here so invalid persistence data cannot
     * create a domain object that could not have been reached through its behavior.
     */
    public static Transaction rehydrate(UUID id, TransactionType type, BigDecimal amount, Currency currency,
            Instant createdAt, TransactionStatus status, String providerReference, String rejectionReason) {
        Transaction transaction = new Transaction(id, type, amount, currency, createdAt);
        transaction.status = Objects.requireNonNull(status, "status must not be null");

        switch (status) {
            case PENDING -> {
                if (providerReference != null || rejectionReason != null) {
                    throw new IllegalArgumentException("Pending transactions must not contain a terminal-state payload");
                }
            }
            case APPROVED -> {
                transaction.providerReference = transaction.requireText(providerReference,
                        "providerReference must not be blank for approved transactions");
                if (rejectionReason != null) {
                    throw new IllegalArgumentException("Approved transactions must not contain a rejection reason");
                }
            }
            case REJECTED -> {
                transaction.rejectionReason = transaction.requireText(rejectionReason,
                        "rejection reason must not be blank for rejected transactions");
                if (providerReference != null) {
                    throw new IllegalArgumentException("Rejected transactions must not contain a provider reference");
                }
            }
        }
        return transaction;
    }

    public void approve(String providerReference) {
        ensurePending();
        this.status = TransactionStatus.APPROVED;
        this.providerReference = requireText(providerReference, "providerReference must not be blank");
    }

    public void reject(String reason) {
        ensurePending();
        this.status = TransactionStatus.REJECTED;
        this.rejectionReason = requireText(reason, "rejection reason must not be blank");
    }

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
    public TransactionType type() { return type; }
    public BigDecimal amount() { return amount; }
    public Currency currency() { return currency; }
    public Instant createdAt() { return createdAt; }
    public TransactionStatus status() { return status; }
    public String providerReference() { return providerReference; }
    public String rejectionReason() { return rejectionReason; }
}
