package com.spin.transactionorchestrator.application.port.out;

import com.spin.transactionorchestrator.domain.model.Transaction;

public interface PaymentProvider {
    PaymentProviderResult execute(Transaction transaction);
}
