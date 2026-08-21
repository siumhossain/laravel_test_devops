<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Prometheus\CollectorRegistry;
use Symfony\Component\HttpFoundation\Response;

class RecordMetrics
{
    public function __construct(private readonly CollectorRegistry $registry) {}

    public function handle(Request $request, Closure $next): Response
    {
        if ($request->is('metrics')) {
            return $next($request);
        }

        $start = microtime(true);

        /** @var Response $response */
        $response = $next($request);

        $route = $request->route()?->uri() ?? $request->path();
        $duration = microtime(true) - $start;

        $this->registry->getOrRegisterCounter(
            namespace: 'app',
            name: 'http_requests_total',
            help: 'Total HTTP requests',
            labels: ['method', 'route', 'status'],
        )->inc([$request->method(), $route, (string) $response->getStatusCode()]);

        $this->registry->getOrRegisterHistogram(
            namespace: 'app',
            name: 'http_request_duration_seconds',
            help: 'HTTP request duration in seconds',
            labels: ['method', 'route'],
            buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
        )->observe($duration, [$request->method(), $route]);

        return $response;
    }
}
