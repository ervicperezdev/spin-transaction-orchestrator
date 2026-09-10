package com.spin.transactionorchestrator.adapter.in.rest;

import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import com.spin.transactionorchestrator.application.port.in.ExecuteTransaction;
import com.spin.transactionorchestrator.application.port.in.FindTransactions;
import com.spin.transactionorchestrator.application.port.in.FindTransactionsQuery;
import com.spin.transactionorchestrator.application.port.in.TransactionPage;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionStatus;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import com.spin.transactionorchestrator.domain.model.TransactionValidationError;
import com.spin.transactionorchestrator.domain.model.TransactionValidationException;
import com.spin.transactionorchestrator.domain.model.TransactionStateException;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.Currency;
import java.util.NoSuchElementException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

@WebMvcTest(TransactionController.class)
class TransactionControllerTest {
    @Autowired private MockMvc mockMvc;
    @MockBean private ExecuteTransaction executeTransaction;
    @MockBean private FindTransactions findTransactions;

    @Test void returnsDefaultBoundedPageThroughFindTransactionsUseCase() throws Exception {
        Transaction transaction = Transaction.pending("acct-123", "Purchase", TransactionType.DEBIT, new BigDecimal("25.50"), Currency.getInstance("MXN"), Instant.parse("2026-09-08T00:00:00Z"), null);
        when(findTransactions.find(new FindTransactionsQuery(0, 20, null, null)))
                .thenReturn(new TransactionPage(java.util.List.of(transaction), 0, 20, 1, 1));

        mockMvc.perform(get("/transactions"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.items[0].id").value(transaction.id().toString()))
                .andExpect(jsonPath("$.items[0].providerReference").doesNotExist())
                .andExpect(jsonPath("$.page").value(0)).andExpect(jsonPath("$.size").value(20))
                .andExpect(jsonPath("$.totalItems").value(1)).andExpect(jsonPath("$.totalPages").value(1));
        verify(findTransactions).find(new FindTransactionsQuery(0, 20, null, null));
    }

    @Test void mapsFiltersAndPaginationOnlyToFindTransactionsUseCase() throws Exception {
        when(findTransactions.find(new FindTransactionsQuery(2, 10, TransactionStatus.APPROVED, TransactionType.CREDIT)))
                .thenReturn(new TransactionPage(java.util.List.of(), 2, 10, 0, 0));

        mockMvc.perform(get("/transactions?page=2&size=10&status=APPROVED&type=CREDIT"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.items").isEmpty());
        verify(findTransactions).find(new FindTransactionsQuery(2, 10, TransactionStatus.APPROVED, TransactionType.CREDIT));
        verify(executeTransaction, times(0)).execute(org.mockito.ArgumentMatchers.any());
    }

    @Test void rejectsInvalidPaginationAndFiltersWithStableErrorContract() throws Exception {
        mockMvc.perform(get("/transactions?page=-1"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_QUERY_PARAMETER"));
        mockMvc.perform(get("/transactions?size=101"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_QUERY_PARAMETER"));
        mockMvc.perform(get("/transactions?status=UNKNOWN"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_QUERY_PARAMETER"));
        verify(findTransactions, times(0)).find(org.mockito.ArgumentMatchers.any());
    }
    @Test void createsTransactionAndInvokesUseCaseOnce() throws Exception {
        Transaction transaction = Transaction.pending("acct-123", "Purchase", TransactionType.DEBIT, new BigDecimal("25.50"), Currency.getInstance("MXN"), Instant.parse("2026-09-08T00:00:00Z"), null);
        transaction.approve("provider-reference-not-exposed");
        when(executeTransaction.execute(argThat(command -> command.type() == TransactionType.DEBIT && command.amount().compareTo(new BigDecimal("25.50")) == 0 && command.currency().equals(Currency.getInstance("MXN"))))).thenReturn(transaction);
        mockMvc.perform(post("/transactions").contentType(MediaType.APPLICATION_JSON).content(validRequest()))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.id").value(transaction.id().toString()))
                .andExpect(jsonPath("$.type").value("DEBIT")).andExpect(jsonPath("$.amount").value(25.50))
                .andExpect(jsonPath("$.currency").value("MXN")).andExpect(jsonPath("$.status").value("APPROVED"))
                .andExpect(jsonPath("$.accountId").value("acct-123"))
                .andExpect(jsonPath("$.createdAt").value("2026-09-08T00:00:00Z"))
                .andExpect(jsonPath("$.providerReference").doesNotExist()).andExpect(jsonPath("$.rejectionReason").doesNotExist());
        verify(executeTransaction, times(1)).execute(argThat(command -> command.type() == TransactionType.DEBIT && command.amount().compareTo(new BigDecimal("25.50")) == 0 && command.currency().equals(Currency.getInstance("MXN"))));
    }
    @Test void rejectsMalformedRequestWithoutCallingUseCase() throws Exception {
        mockMvc.perform(post("/transactions").contentType(MediaType.APPLICATION_JSON).content("{\"accountId\":\"acct-123\",\"type\":\"DEBIT\",\"currency\":\"MXN\"}"))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.message").value("Request validation failed")).andExpect(jsonPath("$.violations[0].field").value("amount"));
        verify(executeTransaction, times(0)).execute(org.mockito.ArgumentMatchers.any());
    }
    @Test void exposesStableBusinessValidationCodeWithoutExceptionDetails() throws Exception {
        when(executeTransaction.execute(org.mockito.ArgumentMatchers.any())).thenThrow(new TransactionValidationException(TransactionValidationError.DEBIT_AMOUNT_LIMIT_EXCEEDED, "internal business detail"));
        mockMvc.perform(post("/transactions").contentType(MediaType.APPLICATION_JSON).content("{\"accountId\":\"acct-123\",\"type\":\"DEBIT\",\"amount\":10000.01,\"currency\":\"MXN\"}"))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("DEBIT_AMOUNT_LIMIT_EXCEEDED"))
                .andExpect(jsonPath("$.message").value("Transaction validation failed"))
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("internal business detail"))));
    }
    @Test void mapsBusinessRuleFailureToSafeConflictResponse() throws Exception {
        when(executeTransaction.execute(org.mockito.ArgumentMatchers.any())).thenThrow(new TransactionStateException("transaction-id=secret"));
        mockMvc.perform(post("/transactions").contentType(MediaType.APPLICATION_JSON).content(validRequest()))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("BUSINESS_RULE_VIOLATION"))
                .andExpect(jsonPath("$.message").value("The transaction cannot be processed in its current state"));
    }
    @Test void mapsMissingResourceToSafeNotFoundResponse() throws Exception {
        when(executeTransaction.execute(org.mockito.ArgumentMatchers.any())).thenThrow(new NoSuchElementException("transaction-id=secret"));
        mockMvc.perform(post("/transactions").contentType(MediaType.APPLICATION_JSON).content(validRequest()))
                .andExpect(status().isNotFound()).andExpect(jsonPath("$.code").value("RESOURCE_NOT_FOUND"))
                .andExpect(jsonPath("$.message").value("The requested resource was not found"));
    }
    @Test void hidesUnexpectedFailureDetails() throws Exception {
        when(executeTransaction.execute(org.mockito.ArgumentMatchers.any())).thenThrow(new IllegalStateException("provider payload=secret"));
        mockMvc.perform(post("/transactions").contentType(MediaType.APPLICATION_JSON).content(validRequest()))
                .andExpect(status().isInternalServerError()).andExpect(jsonPath("$.code").value("INTERNAL_ERROR"))
                .andExpect(jsonPath("$.message").value("An unexpected error occurred"))
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("secret"))));
    }
    private String validRequest() { return "{\"accountId\":\"acct-123\",\"description\":\"Purchase\",\"type\":\"DEBIT\",\"amount\":25.50,\"currency\":\"MXN\"}"; }
}
