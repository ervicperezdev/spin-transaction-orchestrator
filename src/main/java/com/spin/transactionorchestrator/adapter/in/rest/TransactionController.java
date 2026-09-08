package com.spin.transactionorchestrator.adapter.in.rest;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransaction;
import com.spin.transactionorchestrator.application.port.in.ExecuteTransactionCommand;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.Currency;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/transactions")
@Tag(name = "Transactions")
class TransactionController {
    private final ExecuteTransaction executeTransaction;
    TransactionController(ExecuteTransaction executeTransaction) { this.executeTransaction = executeTransaction; }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @Operation(summary = "Execute a transaction")
    @ApiResponses({@ApiResponse(responseCode = "201", description = "Transaction processed"),
            @ApiResponse(responseCode = "400", description = "Malformed or invalid transaction request", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INVALID_REQUEST\",\"message\":\"Request body is invalid\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "404", description = "Requested resource not found", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"RESOURCE_NOT_FOUND\",\"message\":\"The requested resource was not found\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "409", description = "Transaction state does not permit the operation", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"BUSINESS_RULE_VIOLATION\",\"message\":\"The transaction cannot be processed in its current state\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "422", description = "Transaction validation rule failed", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INVALID_AMOUNT\",\"message\":\"Transaction validation failed\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "500", description = "Unexpected server failure", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"INTERNAL_ERROR\",\"message\":\"An unexpected error occurred\",\"violations\":[]}"))),
            @ApiResponse(responseCode = "503", description = "Payment provider unavailable", content = @Content(schema = @Schema(implementation = ApiErrorResponse.class), examples = @ExampleObject(value = "{\"code\":\"PAYMENT_PROVIDER_UNAVAILABLE\",\"message\":\"Payment processing is temporarily unavailable\",\"violations\":[]}")))})
    TransactionResponse create(@Valid @RequestBody CreateTransactionRequest request) {
        Transaction transaction = executeTransaction.execute(toCommand(request));
        return new TransactionResponse(transaction.id(), transaction.type().name(), transaction.amount(),
                transaction.currency().getCurrencyCode(), transaction.status().name(), transaction.createdAt());
    }
    private ExecuteTransactionCommand toCommand(CreateTransactionRequest request) {
        try {
            return new ExecuteTransactionCommand(TransactionType.valueOf(request.type()), request.amount(), Currency.getInstance(request.currency()));
        } catch (IllegalArgumentException exception) { throw new InvalidTransactionRequestException(); }
    }
}
