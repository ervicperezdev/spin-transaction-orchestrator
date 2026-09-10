package com.spin.transactionorchestrator.application.service;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransaction;
import com.spin.transactionorchestrator.application.port.in.ExecuteTransactionCommand;
import com.spin.transactionorchestrator.application.port.out.PaymentProvider;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderResult;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderStatus;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionRules;
import java.time.Clock;
import java.util.Objects;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class TransactionExecutionService implements ExecuteTransaction {
    private static final Logger LOGGER = LoggerFactory.getLogger(TransactionExecutionService.class);
    private final TransactionRepository repository;
    private final PaymentProvider paymentProvider;
    private final Clock clock;

    public TransactionExecutionService(TransactionRepository repository, PaymentProvider paymentProvider, Clock clock) {
        this.repository = Objects.requireNonNull(repository, "repository must not be null");
        this.paymentProvider = Objects.requireNonNull(paymentProvider, "paymentProvider must not be null");
        this.clock = Objects.requireNonNull(clock, "clock must not be null");
    }

    @Override
    public Transaction execute(ExecuteTransactionCommand command) {
        Objects.requireNonNull(command, "command must not be null");
        if (command.idempotencyKey() != null) {
            Optional<Transaction> existing = repository.findByIdempotencyKey(command.idempotencyKey());
            if (existing.isPresent()) {
                LOGGER.atInfo()
                        .addKeyValue("transactionId", existing.get().id())
                        .addKeyValue("type", existing.get().type().name())
                        .addKeyValue("outcome", "idempotent_returned")
                        .log("transaction_completed");
                return existing.get();
            }
        }
        TransactionRules.validate(command.type(), command.amount(), command.currency());
        Transaction transaction = Transaction.pending(command.type(), command.amount(), command.currency(), clock.instant(),
                command.idempotencyKey());
        PaymentProviderResult result = paymentProvider.execute(transaction);

        if (result.status() == PaymentProviderStatus.APPROVED) {
            transaction.approve(result.reference());
        } else if (result.status() == PaymentProviderStatus.REJECTED) {
            transaction.reject(result.rejectionReason());
        } else {
            throw new PaymentProviderException("Provider returned an unsupported status");
        }
        Transaction saved = repository.save(transaction);
        LOGGER.atInfo()
                .addKeyValue("transactionId", saved.id())
                .addKeyValue("type", saved.type().name())
                .addKeyValue("outcome", saved.status().name().toLowerCase())
                .log("transaction_completed");
        return saved;
    }
}
