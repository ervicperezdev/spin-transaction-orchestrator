package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.Transaction;

public interface ExecuteTransaction {
    Transaction execute(ExecuteTransactionCommand command);
}
