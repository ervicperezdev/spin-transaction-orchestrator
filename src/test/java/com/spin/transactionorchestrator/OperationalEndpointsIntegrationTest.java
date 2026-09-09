package com.spin.transactionorchestrator;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
class OperationalEndpointsIntegrationTest {
    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16-alpine")
            .withDatabaseName("transactions")
            .withUsername("transactions_app")
            .withPassword("transactions_app");

    @Autowired
    private MockMvc mockMvc;

    @DynamicPropertySource
    static void databaseProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Test
    void exposesOnlySafeHealthDetails() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist());

        mockMvc.perform(get("/actuator/env")).andExpect(status().isNotFound());
        mockMvc.perform(get("/actuator/metrics")).andExpect(status().isOk());
    }

    @Test
    void echoesOnlyValidCorrelationIds() throws Exception {
        String correlationId = "771f078b-f446-4207-b1b7-0ec11b17c5f4";

        mockMvc.perform(get("/actuator/health").header("X-Correlation-ID", correlationId))
                .andExpect(status().isOk())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .string("X-Correlation-ID", correlationId));

        mockMvc.perform(get("/actuator/health").header("X-Correlation-ID", "not-a-uuid"))
                .andExpect(status().isOk())
                .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                        .exists("X-Correlation-ID"));
    }

    @Test
    void exposesExecutableOpenApiContract() throws Exception {
        mockMvc.perform(get("/v3/api-docs"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.info.title").value("Spin Transaction Orchestrator API"))
                .andExpect(jsonPath("$.paths['/transactions'].get").exists())
                .andExpect(jsonPath("$.paths['/transactions'].post.responses['201'].content['application/json'].schema.$ref")
                        .value("#/components/schemas/TransactionResponse"))
                .andExpect(jsonPath("$.components.schemas.CreateTransactionRequest").exists())
                .andExpect(jsonPath("$.components.schemas.TransactionPageResponse").exists())
                .andExpect(jsonPath("$.components.schemas.ApiErrorResponse").exists());
    }
}
