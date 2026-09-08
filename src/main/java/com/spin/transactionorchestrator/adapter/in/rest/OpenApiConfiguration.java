package com.spin.transactionorchestrator.adapter.in.rest;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;

@OpenAPIDefinition(info = @Info(
        title = "Spin Transaction Orchestrator API",
        version = "v1",
        description = "API contract for creating and listing transaction orchestration requests."))
final class OpenApiConfiguration {
    private OpenApiConfiguration() {
    }
}
