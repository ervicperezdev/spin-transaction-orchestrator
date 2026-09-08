package com.spin.transactionorchestrator.infrastructure.provider;

import com.spin.transactionorchestrator.application.port.out.PaymentProvider;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderResult;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderUnavailableException;
import com.spin.transactionorchestrator.domain.model.Transaction;
import java.time.Duration;
import java.util.Locale;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestClientResponseException;

/** HTTP adapter; no transport type crosses the application port. */
public final class HttpPaymentProvider implements PaymentProvider {
    private final RestClient client;
    private final Duration readTimeout;

    public HttpPaymentProvider(RestClient client, Duration readTimeout) {
        this.client = client;
        this.readTimeout = readTimeout;
    }

    @Override
    public PaymentProviderResult execute(Transaction transaction) {
        try {
            ProviderResponse response = client.post()
                    .uri("/payments")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(new ProviderRequest(transaction))
                    .retrieve()
                    .body(ProviderResponse.class);
            return translate(response);
        } catch (RestClientResponseException exception) {
            throw new PaymentProviderUnavailableException(
                    "Payment provider returned HTTP " + exception.getStatusCode().value(), exception);
        } catch (RestClientException exception) {
            throw new PaymentProviderUnavailableException("Payment provider is unavailable or timed out after " + readTimeout, exception);
        }
    }

    private PaymentProviderResult translate(ProviderResponse response) {
        if (response == null || response.status() == null) {
            throw new PaymentProviderUnavailableException("Payment provider returned an invalid response");
        }
        return switch (response.status().toUpperCase(Locale.ROOT)) {
            case "APPROVED" -> PaymentProviderResult.approved(response.reference());
            case "REJECTED" -> PaymentProviderResult.rejected(response.rejectionReason());
            default -> throw new PaymentProviderUnavailableException("Payment provider returned unsupported status: " + response.status());
        };
    }

    private record ProviderRequest(String transactionId, String type, String amount, String currency) {
        private ProviderRequest(Transaction transaction) {
            this(transaction.id().toString(), transaction.type().name(), transaction.amount().toPlainString(), transaction.currency().getCurrencyCode());
        }
    }

    private record ProviderResponse(String status, String reference, String rejectionReason) {
    }
}
