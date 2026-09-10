package com.spin.transactionorchestrator.infrastructure.persistence;

import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.Currency;
import org.springframework.stereotype.Component;

@Component
class TransactionEntityMapper {
    TransactionEntity toEntity(Transaction transaction) {
        return new TransactionEntity(transaction.id(), transaction.accountId(), transaction.description(), transaction.type(), transaction.status(), transaction.amount(),
                transaction.currency().getCurrencyCode(), transaction.providerTransactionId(), transaction.balanceAfter(), transaction.rejectionCode(), transaction.rejectionReason(),
                transaction.createdAt(), transaction.idempotencyKey());
    }

    Transaction toDomain(TransactionEntity entity) {
        return Transaction.rehydrate(entity.id(), entity.accountId(), entity.description(), entity.type(), entity.amount(), Currency.getInstance(entity.currency()),
                entity.createdAt(), entity.status(), entity.providerTransactionId(), entity.balanceAfter(), entity.rejectionCode(), entity.rejectionReason(),
                entity.idempotencyKey());
    }
}
