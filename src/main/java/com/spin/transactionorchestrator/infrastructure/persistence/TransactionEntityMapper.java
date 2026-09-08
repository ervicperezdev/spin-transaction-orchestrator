package com.spin.transactionorchestrator.infrastructure.persistence;

import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.Currency;
import org.springframework.stereotype.Component;

@Component
class TransactionEntityMapper {
    TransactionEntity toEntity(Transaction transaction) {
        return new TransactionEntity(transaction.id(), transaction.type(), transaction.status(), transaction.amount(),
                transaction.currency().getCurrencyCode(), transaction.providerReference(), transaction.rejectionReason(),
                transaction.createdAt());
    }

    Transaction toDomain(TransactionEntity entity) {
        return Transaction.rehydrate(entity.id(), entity.type(), entity.amount(), Currency.getInstance(entity.currency()),
                entity.createdAt(), entity.status(), entity.providerReference(), entity.rejectionReason());
    }
}
