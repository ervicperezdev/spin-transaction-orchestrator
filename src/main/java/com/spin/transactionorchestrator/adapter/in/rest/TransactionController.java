package com.spin.transactionorchestrator.adapter.in.rest;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransaction;
import com.spin.transactionorchestrator.application.port.in.ExecuteTransactionCommand;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import io.swagger.v3.oas.annotations.Operation;
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
            @ApiResponse(responseCode = "400", description = "Malformed or invalid transaction request"),
            @ApiResponse(responseCode = "503", description = "Payment provider unavailable")})
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
