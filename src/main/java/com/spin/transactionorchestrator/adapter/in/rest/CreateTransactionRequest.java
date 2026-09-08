package com.spin.transactionorchestrator.adapter.in.rest;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.math.BigDecimal;

@Schema(name = "CreateTransactionRequest")
public record CreateTransactionRequest(
        @Schema(description = "Transaction direction", example = "DEBIT", allowableValues = {"DEBIT", "CREDIT"})
        @NotBlank(message = "type is required")
        @Pattern(regexp = "DEBIT|CREDIT", message = "type must be DEBIT or CREDIT") String type,
        @Schema(description = "Transaction amount, greater than 1.00", example = "25.50")
        @NotNull(message = "amount is required")
        @DecimalMin(value = "1.00", inclusive = false, message = "amount must be greater than 1.00") BigDecimal amount,
        @Schema(description = "Three-letter ISO 4217 currency code", example = "MXN")
        @NotBlank(message = "currency is required")
        @Pattern(regexp = "[A-Z]{3}", message = "currency must be a three-letter uppercase code") String currency) {
}
