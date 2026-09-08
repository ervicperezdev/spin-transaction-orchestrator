package com.spin.transactionorchestrator.infrastructure.provider;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "payment-provider")
public record PaymentProviderProperties(String baseUrl, Duration connectTimeout, Duration readTimeout) {
}
