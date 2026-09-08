package com.spin.transactionorchestrator.adapter.in.rest;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

@Schema(name = "ApiErrorResponse")
public record ApiErrorResponse(@Schema(example = "VALIDATION_ERROR") String code,
                               @Schema(example = "Request validation failed") String message,
                               List<FieldViolation> violations) {
    public record FieldViolation(String field, String message) { }
}
