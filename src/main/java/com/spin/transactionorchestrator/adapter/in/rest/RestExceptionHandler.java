package com.spin.transactionorchestrator.adapter.in.rest;

import com.spin.transactionorchestrator.application.port.out.PaymentProviderUnavailableException;
import com.spin.transactionorchestrator.domain.model.TransactionValidationException;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice(basePackageClasses = TransactionController.class)
class RestExceptionHandler {
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
        return badRequest(exception.error().name(), "Transaction request violates business rules", List.of());
    }
    @ExceptionHandler(PaymentProviderUnavailableException.class)
    ResponseEntity<ApiErrorResponse> handleProviderUnavailable(PaymentProviderUnavailableException exception) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(new ApiErrorResponse("PAYMENT_PROVIDER_UNAVAILABLE", "Payment processing is temporarily unavailable", List.of()));
    }
    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiErrorResponse> handleUnexpected(Exception exception) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(new ApiErrorResponse("INTERNAL_ERROR", "An unexpected error occurred", List.of()));
    }
    private ResponseEntity<ApiErrorResponse> badRequest(String code, String message, List<ApiErrorResponse.FieldViolation> violations) {
        return ResponseEntity.badRequest().body(new ApiErrorResponse(code, message, violations));
    }
    private ApiErrorResponse.FieldViolation violation(FieldError error) { return new ApiErrorResponse.FieldViolation(error.getField(), error.getDefaultMessage()); }
}
