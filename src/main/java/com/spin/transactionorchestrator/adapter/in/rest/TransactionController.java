package com.spin.transactionorchestrator.adapter.in.rest;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransaction;
import com.spin.transactionorchestrator.application.port.in.ExecuteTransactionCommand;
import com.spin.transactionorchestrator.application.port.in.FindTransactions;
import com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.Currency;
import org.springframework.validation.annotation.Validated;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(value = "/transactions", produces = MediaType.APPLICATION_JSON_VALUE)
@Tag(name = "Transactions")
@Validated
class TransactionController {
    private final ExecuteTransaction executeTransaction;
    private final FindTransactions findTransactions;
    TransactionController(ExecuteTransaction executeTransaction, FindTransactions findTransactions) {
        this.executeTransaction = executeTransaction;
        this.findTransactions = findTransactions;
    }

    @GetMapping
    @Operation(summary = "List transactions", description = "Returns a stable-order, bounded page. Defaults: page=0 and size=20; size is capped at 100. Filters can be combined.")
    @ApiResponses({@ApiResponse(responseCode = "200", description = "Paged transactions", content = @Content(schema = @Schema(implementation = TransactionPageResponse.class))),
            @ApiResponse(responseCode = "400", description = "Invalid page, size, or filter", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INVALID_QUERY_PARAMETER\",\"message\":\"Query parameters are invalid\",\"violations\":[]}")))})
    TransactionPageResponse find(
            @Parameter(description = "Zero-based page number", example = "0") @RequestParam(defaultValue = "0") @Min(0) int page,
            @Parameter(description = "Items per page (1-100)", example = "20") @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size,
            @Parameter(description = "Optional transaction status", example = "APPROVED") @RequestParam(required = false) TransactionStatus status,
            @Parameter(description = "Optional transaction type", example = "DEBIT") @RequestParam(required = false) TransactionType type) {
        var result = findTransactions.find(new FindTransactionsQuery(page, size, status, type));
        return new TransactionPageResponse(result.items().stream().map(this::toResponse).toList(), result.page(),
                result.size(), result.totalItems(), result.totalPages());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Execute a transaction")
    @ApiResponses({@ApiResponse(responseCode = "201", description = "Transaction processed", content = @Content(schema = @Schema(implementation = TransactionResponse.class))),
            @ApiResponse(responseCode = "400", description = "Malformed or invalid transaction request", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INVALID_REQUEST\",\"message\":\"Request body is invalid\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "404", description = "Requested resource not found", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"RESOURCE_NOT_FOUND\",\"message\":\"The requested resource was not found\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "409", description = "Transaction state does not permit the operation", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"BUSINESS_RULE_VIOLATION\",\"message\":\"The transaction cannot be processed in its current state\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "422", description = "Transaction validation rule failed", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INVALID_AMOUNT\",\"message\":\"Transaction validation failed\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "500", description = "Unexpected server failure", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INTERNAL_ERROR\",\"message\":\"An unexpected error occurred\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "503", description = "Payment provider unavailable", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"PAYMENT_PROVIDER_UNAVAILABLE\",\"message\":\"Payment processing is temporarily unavailable\",\"violations\":[]}")))})
    TransactionResponse create(@Valid @RequestBody CreateTransactionRequest request,
            @Parameter(description = "Optional key used to safely retry a request", example = "checkout-4f5d9b")
            @RequestHeader(name = "Idempotency-Key", required = false) String idempotencyKey) {
        Transaction transaction = executeTransaction.execute(toCommand(request, idempotencyKey));
        return toResponse(transaction);
    }
    private ExecuteTransactionCommand toCommand(CreateTransactionRequest request, String idempotencyKey) {
        try {
            return new ExecuteTransactionCommand(TransactionType.valueOf(request.type()), request.amount(),
                    Currency.getInstance(request.currency()), idempotencyKey);
        } catch (IllegalArgumentException exception) { throw new InvalidTransactionRequestException(); }
    }
    private TransactionResponse toResponse(Transaction transaction) {
        return new TransactionResponse(transaction.id(), transaction.type().name(), transaction.amount(),
                transaction.currency().getCurrencyCode(), transaction.status().name(), transaction.createdAt());
    }
}
