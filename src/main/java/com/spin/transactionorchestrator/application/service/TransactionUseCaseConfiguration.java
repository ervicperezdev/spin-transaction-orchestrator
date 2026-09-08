package com.spin.transactionorchestrator.application.service;

import com.spin.transactionorchestrator.application.port.in.ExecuteTransaction;
import com.spin.transactionorchestrator.application.port.in.FindTransactions;
import com.spin.transactionorchestrator.application.port.out.PaymentProvider;
import com.spin.transactionorchestrator.application.port.out.TransactionRepository;
import java.time.Clock;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class TransactionUseCaseConfiguration {
    @Bean
    Clock clock() { return Clock.systemUTC(); }

    @Bean
    ExecuteTransaction executeTransaction(TransactionRepository repository, PaymentProvider paymentProvider, Clock clock) {
        return new TransactionExecutionService(repository, paymentProvider, clock);
    }

    @Bean
    FindTransactions findTransactions(TransactionRepository repository) {
        return new FindTransactionsService(repository);
    }
}
