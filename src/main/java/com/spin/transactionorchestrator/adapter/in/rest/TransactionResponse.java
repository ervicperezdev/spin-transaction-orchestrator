package com.spin.transactionorchestrator.adapter.in.rest;

import io.swagger.v3.oas.annotations.media.Schema;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

@Schema(name = "TransactionResponse", description = "Public representation of a processed transaction")
public record TransactionResponse(UUID id, String accountId, String description, String type, BigDecimal amount, String currency,
        String status, String providerTransactionId, BigDecimal balanceAfter, String rejectionCode, String rejectionReason, Instant createdAt) {
}
