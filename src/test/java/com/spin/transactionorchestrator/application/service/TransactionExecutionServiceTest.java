package com.spin.transactionorchestrator.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransactionCommand;
import com.spin.transactionorchestrator.application.port.out.PaymentProvider;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderResult;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import com.spin.transactionorchestrator.domain.model.TransactionValidationError;
import com.spin.transactionorchestrator.domain.model.TransactionValidationException;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Currency;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class TransactionExecutionServiceTest {
    private static final Clock CLOCK = Clock.fixed(Instant.parse("2026-09-08T00:00:00Z"), ZoneOffset.UTC);

    @Test
    void savesAnApprovedTransactionWithProviderReference() {
        InMemoryRepository repository = new InMemoryRepository();
        PaymentProvider provider = transaction -> PaymentProviderResult.approved("provider-123");
        TransactionExecutionService service = new TransactionExecutionService(repository, provider, CLOCK);

        Transaction result = service.execute(command());

        assertThat(result.status()).isEqualTo(TransactionStatus.APPROVED);
        assertThat(result.providerReference()).isEqualTo("provider-123");
        assertThat(result.rejectionReason()).isNull();
        assertThat(repository.transactions).containsExactly(result);
    }

    @Test
    void savesARejectedTransactionWithReason() {
        InMemoryRepository repository = new InMemoryRepository();
        PaymentProvider provider = transaction -> PaymentProviderResult.rejected("insufficient funds");
        TransactionExecutionService service = new TransactionExecutionService(repository, provider, CLOCK);

        Transaction result = service.execute(command());

        assertThat(result.status()).isEqualTo(TransactionStatus.REJECTED);
        assertThat(result.rejectionReason()).isEqualTo("insufficient funds");
        assertThat(result.providerReference()).isNull();
        assertThat(repository.transactions).containsExactly(result);
    }

    @Test
    void rejectsAmountAtMinimumBeforeCallingProvider() {
        assertRejectedBeforeExternalInteractions(
                new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("1.00"), mxn(), null),
                TransactionValidationError.INVALID_AMOUNT);
    }

    @Test
    void acceptsAmountJustAboveMinimum() {
        PaymentProvider provider = approvedProvider();
        TransactionRepository repository = savingRepository();

        Transaction result = new TransactionExecutionService(repository, provider, CLOCK)
                .execute(new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("1.01"), mxn(), null));

        assertThat(result.status()).isEqualTo(TransactionStatus.APPROVED);
        verify(provider).execute(org.mockito.ArgumentMatchers.any(Transaction.class));
    }

    @Test
    void rejectsDebitAboveMaximumBeforeCallingProvider() {
        assertRejectedBeforeExternalInteractions(
                new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("10000.01"), mxn(), null),
                TransactionValidationError.DEBIT_AMOUNT_LIMIT_EXCEEDED);
    }

    @Test
    void acceptsDebitAtMaximum() {
        PaymentProvider provider = approvedProvider();
        TransactionRepository repository = savingRepository();

        new TransactionExecutionService(repository, provider, CLOCK)
                .execute(new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("10000.00"), mxn(), null));

        verify(provider).execute(org.mockito.ArgumentMatchers.any(Transaction.class));
    }

    @Test
    void doesNotApplyDebitLimitToCredit() {
        PaymentProvider provider = approvedProvider();
        TransactionRepository repository = savingRepository();

        new TransactionExecutionService(repository, provider, CLOCK)
                .execute(new ExecuteTransactionCommand(TransactionType.CREDIT, new BigDecimal("10000.01"), mxn(), null));

        verify(provider).execute(org.mockito.ArgumentMatchers.any(Transaction.class));
    }

    @Test
    void rejectsNonMxnCurrencyBeforeCallingProvider() {
        assertRejectedBeforeExternalInteractions(
                new ExecuteTransactionCommand(TransactionType.CREDIT, new BigDecimal("25.50"), Currency.getInstance("USD"), null),
                TransactionValidationError.UNSUPPORTED_CURRENCY);
    }

    @Test
    void rejectsMissingTransactionTypeBeforeCallingProvider() {
        assertRejectedBeforeExternalInteractions(
                new ExecuteTransactionCommand(null, new BigDecimal("25.50"), mxn(), null),
                TransactionValidationError.INVALID_TRANSACTION_TYPE);
    }

    @Test
    void returnsExistingTransactionOnDuplicateIdempotencyKeyWithoutCallingProvider() {
        InMemoryRepository repository = new InMemoryRepository();
        PaymentProvider provider = mock(PaymentProvider.class);
        when(provider.execute(org.mockito.ArgumentMatchers.any(Transaction.class)))
                .thenReturn(com.spin.transactionorchestrator.application.port.out.PaymentProviderResult.approved("provider-123"));
        TransactionExecutionService service = new TransactionExecutionService(repository, provider, CLOCK);
        ExecuteTransactionCommand commandWithKey = new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("25.50"), mxn(), "idem-key-abc");

        Transaction first = service.execute(commandWithKey);
        Transaction second = service.execute(commandWithKey);

        assertThat(second).isSameAs(first);
        verify(provider, org.mockito.Mockito.times(1)).execute(org.mockito.ArgumentMatchers.any(Transaction.class));
        assertThat(repository.transactions).hasSize(1);
    }

    private void assertRejectedBeforeExternalInteractions(
            ExecuteTransactionCommand command, TransactionValidationError expectedError) {
        PaymentProvider provider = mock(PaymentProvider.class);
        TransactionRepository repository = mock(TransactionRepository.class);
        TransactionExecutionService service = new TransactionExecutionService(repository, provider, CLOCK);

        assertThatThrownBy(() -> service.execute(command))
                .isInstanceOf(TransactionValidationException.class)
                .extracting(exception -> ((TransactionValidationException) exception).error())
                .isEqualTo(expectedError);

        verifyNoInteractions(provider, repository);
    }

    private PaymentProvider approvedProvider() {
        PaymentProvider provider = mock(PaymentProvider.class);
        when(provider.execute(org.mockito.ArgumentMatchers.any(Transaction.class)))
                .thenReturn(PaymentProviderResult.approved("provider-123"));
        return provider;
    }

    private TransactionRepository savingRepository() {
        TransactionRepository repository = mock(TransactionRepository.class);
        when(repository.save(org.mockito.ArgumentMatchers.any(Transaction.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        return repository;
    }

    private ExecuteTransactionCommand command() {
        return new ExecuteTransactionCommand(TransactionType.DEBIT, new BigDecimal("25.50"), mxn(), null);
    }

    private Currency mxn() {
        return Currency.getInstance("MXN");
    }

    private static final class InMemoryRepository implements TransactionRepository {
        private final List<Transaction> transactions = new ArrayList<>();

        @Override
        public Transaction save(Transaction transaction) {
            transactions.add(transaction);
            return transaction;
        }

        @Override
        public com.spin.transactionorchestrator.application.port.in.TransactionPage find(
                com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery query) {
            return new com.spin.transactionorchestrator.application.port.in.TransactionPage(List.copyOf(transactions),
                    query.page(), query.size(), transactions.size(), 1);
        }

        @Override
        public Optional<Transaction> findByIdempotencyKey(String key) {
            return transactions.stream()
                    .filter(t -> key.equals(t.idempotencyKey()))
                    .findFirst();
        }
    }
}
