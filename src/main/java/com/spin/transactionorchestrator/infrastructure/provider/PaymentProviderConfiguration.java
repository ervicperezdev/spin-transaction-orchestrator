package com.spin.transactionorchestrator.infrastructure.provider;

import com.spin.transactionorchestrator.application.port.out.PaymentProvider;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

@Configuration
@EnableConfigurationProperties(PaymentProviderProperties.class)
class PaymentProviderConfiguration {
    @Bean
    PaymentProvider paymentProvider(RestClient.Builder builder, PaymentProviderProperties properties) {
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(properties.connectTimeout());
        requestFactory.setReadTimeout(properties.readTimeout());
        return new HttpPaymentProvider(builder.baseUrl(properties.baseUrl()).requestFactory(requestFactory).build(), properties.readTimeout());
    }
}
