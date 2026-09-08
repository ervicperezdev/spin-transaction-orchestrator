package com.spin.transactionorchestrator.infrastructure.persistence;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

interface SpringDataTransactionJpaRepository extends JpaRepository<TransactionEntity, UUID>, JpaSpecificationExecutor<TransactionEntity> {
    Optional<TransactionEntity> findByIdempotencyKey(String idempotencyKey);
}
