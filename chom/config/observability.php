<?php

return [
    'enabled' => env('OBSERVABILITY_ENABLED', true),
    'loki_url' => env('LOKI_URL', 'http://10.10.100.10:3100'),
    'prometheus_gateway' => env('PROMETHEUS_GATEWAY', 'http://10.10.100.10:9091'),
    'tempo_endpoint' => env('TEMPO_ENDPOINT', 'http://10.10.100.10:4318'),
    'service_name' => env('OBSERVABILITY_SERVICE_NAME', 'chom-api'),
];
