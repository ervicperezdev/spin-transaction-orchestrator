package com.spin.transactionorchestrator.application.port.in;

import com.spin.transactionorchestrator.domain.model.Transaction;
import java.util.List;

public interface FindTransactions {
    List<Transaction> findAll();
}
