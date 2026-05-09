/**
 * telemetry.ts — OpenTelemetry + Application Insights setup
 *
 * Must be imported FIRST in index.ts before any other module so
 * auto-instrumentation patches are applied before dependencies load.
 *
 * Pattern mirrors Agent365-Samples observability guidance:
 * use @azure/monitor-opentelemetry-exporter with the OTel SDK Node.
 */

import { NodeSDK } from "@opentelemetry/sdk-node";
import { AzureMonitorTraceExporter } from "@azure/monitor-opentelemetry-exporter";
import { Resource } from "@opentelemetry/resources";
import { SEMRESATTRS_SERVICE_NAME, SEMRESATTRS_SERVICE_VERSION } from "@opentelemetry/semantic-conventions";
import { HttpInstrumentation } from "@opentelemetry/instrumentation-http";
import { ExpressInstrumentation } from "@opentelemetry/instrumentation-express";
import { config } from "./config";

let sdk: NodeSDK | null = null;

export function initTelemetry(): void {
  if (!config.appInsightsConnectionString) {
    console.warn(
      "[telemetry] APPINSIGHTS_CONNECTION_STRING not set — telemetry disabled"
    );
    return;
  }

  const exporter = new AzureMonitorTraceExporter({
    connectionString: config.appInsightsConnectionString,
  });

  sdk = new NodeSDK({
    resource: new Resource({
      [SEMRESATTRS_SERVICE_NAME]: config.otelServiceName,
      [SEMRESATTRS_SERVICE_VERSION]: config.otelServiceVersion,
      environment: config.appEnv,
    }),
    traceExporter: exporter,
    instrumentations: [
      new HttpInstrumentation(),
      new ExpressInstrumentation(),
    ],
  });

  sdk.start();
  console.info(
    `[telemetry] OpenTelemetry started — service=${config.otelServiceName} env=${config.appEnv}`
  );
}

export async function shutdownTelemetry(): Promise<void> {
  if (sdk) {
    await sdk.shutdown();
    console.info("[telemetry] OpenTelemetry shut down");
  }
}
