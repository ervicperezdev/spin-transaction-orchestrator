package com.spin.transactionorchestrator.adapter.in.rest;

import com.spin.transactionorchestrator.application.port.out.PaymentProviderUnavailableException;
import com.spin.transactionorchestrator.domain.model.TransactionStateException;
import com.spin.transactionorchestrator.domain.model.TransactionValidationException;
import java.util.List;
import java.util.NoSuchElementException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackageClasses = TransactionController.class)
class RestExceptionHandler {
    private static final Logger LOGGER = LoggerFactory.getLogger(RestExceptionHandler.class);

    @ExceptionHandler(MethodArgumentNotValidException.class)
    ResponseEntity<ApiErrorResponse> handleBeanValidation(MethodArgumentNotValidException exception) {
        List<ApiErrorResponse.FieldViolation> violations = exception.getBindingResult().getFieldErrors().stream().map(this::violation).toList();
        return badRequest("VALIDATION_ERROR", "Request validation failed", violations);
    }
    @ExceptionHandler({HttpMessageNotReadableException.class, InvalidTransactionRequestException.class})
    ResponseEntity<ApiErrorResponse> handleMalformedRequest(RuntimeException exception) {
        return badRequest("INVALID_REQUEST", "Request body is invalid", List.of());
    }
    @ExceptionHandler(TransactionValidationException.class)
    ResponseEntity<ApiErrorResponse> handleTransactionValidation(TransactionValidationException exception) {
        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY)
                .body(new ApiErrorResponse(exception.error().name(), "Transaction validation failed", List.of()));
    }
    @ExceptionHandler(TransactionStateException.class)
    ResponseEntity<ApiErrorResponse> handleBusinessRule(TransactionStateException exception) {
        return ResponseEntity.status(HttpStatus.CONFLICT).body(new ApiErrorResponse("BUSINESS_RULE_VIOLATION",
                "The transaction cannot be processed in its current state", List.of()));
    }
    @ExceptionHandler(NoSuchElementException.class)
    ResponseEntity<ApiErrorResponse> handleMissingResource(NoSuchElementException exception) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(new ApiErrorResponse("RESOURCE_NOT_FOUND",
                "The requested resource was not found", List.of()));
    }
    @ExceptionHandler(PaymentProviderUnavailableException.class)
    ResponseEntity<ApiErrorResponse> handleProviderUnavailable(PaymentProviderUnavailableException exception) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(new ApiErrorResponse("PAYMENT_PROVIDER_UNAVAILABLE", "Payment processing is temporarily unavailable", List.of()));
    }
    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiErrorResponse> handleUnexpected(Exception exception) {
        // Exception messages and stack traces can contain transaction data or provider responses.
        LOGGER.error("Unhandled REST failure; exceptionType={}", exception.getClass().getName());
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(new ApiErrorResponse("INTERNAL_ERROR", "An unexpected error occurred", List.of()));
    }
    private ResponseEntity<ApiErrorResponse> badRequest(String code, String message, List<ApiErrorResponse.FieldViolation> violations) {
        return ResponseEntity.badRequest().body(new ApiErrorResponse(code, message, violations));
    }
    private ApiErrorResponse.FieldViolation violation(FieldError error) { return new ApiErrorResponse.FieldViolation(error.getField(), error.getDefaultMessage()); }
}
