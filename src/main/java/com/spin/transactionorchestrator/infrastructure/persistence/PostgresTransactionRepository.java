package com.spin.transactionorchestrator.infrastructure.persistence;

import com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery;
import com.spin.transactionorchestrator.application.port.in.TransactionPage;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.Objects;
import java.util.Optional;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
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
    public Optional<Transaction> findByIdempotencyKey(String key) {
        Objects.requireNonNull(key, "key must not be null");
        return repository.findByIdempotencyKey(key).map(mapper::toDomain);
    }

    @Override
    public TransactionPage find(FindTransactionsQuery query) {
        Objects.requireNonNull(query, "query must not be null");
        var pageable = PageRequest.of(query.page(), query.size(), Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id")));
        var result = repository.findAll(specification(query), pageable);
        return new TransactionPage(result.getContent().stream().map(mapper::toDomain).toList(), result.getNumber(),
                result.getSize(), result.getTotalElements(), result.getTotalPages());
    }

    private Specification<TransactionEntity> specification(FindTransactionsQuery query) {
        Specification<TransactionEntity> specification = Specification.where(null);
        if (query.status() != null) {
            specification = specification.and((root, ignored, builder) -> builder.equal(root.get("status"), query.status()));
        }
        if (query.type() != null) {
            specification = specification.and((root, ignored, builder) -> builder.equal(root.get("type"), query.type()));
        }
        return specification;
    }
}
