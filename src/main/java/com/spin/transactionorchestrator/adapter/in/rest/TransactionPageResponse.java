package com.spin.transactionorchestrator.adapter.in.rest;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

@Schema(name = "TransactionPageResponse", description = "A page ordered by createdAt descending, then id descending")
public record TransactionPageResponse(List<TransactionResponse> items,
                                      @Schema(example = "0", description = "Zero-based requested page") int page,
                                      @Schema(example = "20", description = "Requested page size") int size,
                                      @Schema(example = "42", description = "Total matching transactions") long totalItems,
                                      @Schema(example = "3", description = "Total pages matching the query") int totalPages) { }
