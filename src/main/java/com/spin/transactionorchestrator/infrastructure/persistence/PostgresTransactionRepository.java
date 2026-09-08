package com.spin.transactionorchestrator.infrastructure.persistence;

import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.List;
import java.util.Objects;
import org.springframework.stereotype.Repository;

@Repository
public class PostgresTransactionRepository implements TransactionRepository {
    private final SpringDataTransactionJpaRepository repository;
    private final TransactionEntityMapper mapper;

    public PostgresTransactionRepository(SpringDataTransactionJpaRepository repository, TransactionEntityMapper mapper) {
        this.repository = Objects.requireNonNull(repository, "repository must not be null");
        this.mapper = Objects.requireNonNull(mapper, "mapper must not be null");
    }

    @Override
    public Transaction save(Transaction transaction) {
        Objects.requireNonNull(transaction, "transaction must not be null");
        return mapper.toDomain(repository.save(mapper.toEntity(transaction)));
    }

    @Override
    public List<Transaction> findAll() {
        return repository.findAllByOrderByCreatedAtDescIdDesc().stream().map(mapper::toDomain).toList();
    }
}
