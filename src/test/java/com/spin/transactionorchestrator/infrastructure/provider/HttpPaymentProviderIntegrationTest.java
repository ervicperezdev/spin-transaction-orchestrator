package com.spin.transactionorchestrator.infrastructure.provider;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.equalToJson;
import static com.github.tomakehurst.wiremock.client.WireMock.post;
import static com.github.tomakehurst.wiremock.client.WireMock.postRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlEqualTo;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.github.tomakehurst.wiremock.WireMockServer;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderResult;
import com.spin.transactionorchestrator.application.port.out.PaymentProviderUnavailableException;
import com.spin.transactionorchestrator.domain.model.Transaction;
import com.spin.transactionorchestrator.domain.model.TransactionType;
import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.Currency;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

class HttpPaymentProviderIntegrationTest {
    private WireMockServer provider;
    private HttpPaymentProvider adapter;
    private Transaction transaction;

    @BeforeEach
    void startProvider() {
        provider = new WireMockServer();
        provider.start();
        transaction = Transaction.pending(TransactionType.DEBIT, new BigDecimal("25.50"), Currency.getInstance("MXN"), Instant.EPOCH, null);
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setReadTimeout(Duration.ofSeconds(2));
        adapter = new HttpPaymentProvider(RestClient.builder().baseUrl(provider.baseUrl()).requestFactory(requestFactory).build(), Duration.ofMillis(100));
    }

    @AfterEach
    void stopProvider() { provider.stop(); }

    @Test
    void translatesApprovedResponse() {
        provider.stubFor(post("/payments").willReturn(aResponse().withHeader("Content-Type", "application/json")
                .withBody("{\"status\":\"APPROVED\",\"reference\":\"provider-123\"}")));

        PaymentProviderResult result = adapter.execute(transaction());

        assertThat(result).isEqualTo(PaymentProviderResult.approved("provider-123"));
        provider.verify(postRequestedFor(urlEqualTo("/payments")).withRequestBody(equalToJson(requestBody())));
    }

    @Test
    void translatesRejectedResponse() {
        provider.stubFor(post("/payments").willReturn(aResponse().withHeader("Content-Type", "application/json")
                .withBody("{\"status\":\"REJECTED\",\"rejectionReason\":\"insufficient funds\"}")));

        assertThat(adapter.execute(transaction())).isEqualTo(PaymentProviderResult.rejected("insufficient funds"));
    }

    @Test
    void translates4xxAnd5xxToProviderUnavailableException() {
        provider.stubFor(post("/payments").willReturn(aResponse().withStatus(400)));
        assertThatThrownBy(() -> adapter.execute(transaction())).isInstanceOf(PaymentProviderUnavailableException.class)
                .hasMessageContaining("HTTP 400");

        provider.resetAll();
        provider.stubFor(post("/payments").willReturn(aResponse().withStatus(503)));
        assertThatThrownBy(() -> adapter.execute(transaction())).isInstanceOf(PaymentProviderUnavailableException.class)
                .hasMessageContaining("HTTP 503");
    }

    @Test
    void translatesTimeoutToProviderUnavailableException() {
        adapter = createAdapter(Duration.ofMillis(200));

        provider.stubFor(post("/payments").willReturn(aResponse().withFixedDelay(500).withStatus(200)
                .withHeader("Content-Type", "application/json").withBody("{\"status\":\"APPROVED\",\"reference\":\"late\"}")));

        assertThatThrownBy(() -> adapter.execute(transaction())).isInstanceOf(PaymentProviderUnavailableException.class)
                .hasMessageContaining("unavailable or timed out");
    }

    private Transaction transaction() {
        return transaction;
    }

    private String requestBody() {
        return "{\"transactionId\":\"" + transaction().id() + "\",\"type\":\"DEBIT\",\"amount\":\"25.50\",\"currency\":\"MXN\"}";
    }

    private HttpPaymentProvider createAdapter(Duration timeout) {
    SimpleClientHttpRequestFactory requestFactory =
            new SimpleClientHttpRequestFactory();

    requestFactory.setReadTimeout(timeout);

    RestClient restClient = RestClient.builder()
            .baseUrl(provider.baseUrl())
            .requestFactory(requestFactory)
            .build();

    return new HttpPaymentProvider(restClient, timeout);
}
}
