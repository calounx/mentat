#!/usr/bin/env python3
"""
CHOM Platform - Example Metrics Instrumentation

This file provides example implementations for all metrics required by the
advanced Grafana dashboards. Use this as a reference to instrument your
application.

Installation:
    pip install prometheus-client

Usage:
    from prometheus_client import start_http_server
    start_http_server(9090)  # Expose metrics on port 9090
"""

from prometheus_client import Counter, Histogram, Gauge, Info
import time

# ============================================================================
# HTTP Request Metrics - Required for SRE Golden Signals Dashboard
# ============================================================================

# Total HTTP requests counter
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'code', 'job']
)

# HTTP request duration histogram
http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint', 'job'],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)

# HTTP request size histogram
http_request_size_bytes = Histogram(
    'http_request_size_bytes',
    'HTTP request size in bytes',
    ['job'],
    buckets=(100, 1000, 10000, 100000, 1000000, 10000000)
)

# HTTP response size histogram
http_response_size_bytes = Histogram(
    'http_response_size_bytes',
    'HTTP response size in bytes',
    ['job'],
    buckets=(100, 1000, 10000, 100000, 1000000, 10000000)
)

# Example usage in Flask/FastAPI middleware
def track_request_metrics(request, response, duration):
    """
    Track HTTP request metrics

    Args:
        request: HTTP request object
        response: HTTP response object
        duration: Request duration in seconds
    """
    http_requests_total.labels(
        method=request.method,
        endpoint=request.path,
        code=response.status_code,
        job='chom'
    ).inc()

    http_request_duration_seconds.labels(
        method=request.method,
        endpoint=request.path,
        job='chom'
    ).observe(duration)

    if hasattr(request, 'content_length') and request.content_length:
        http_request_size_bytes.labels(job='chom').observe(request.content_length)

    if hasattr(response, 'content_length') and response.content_length:
        http_response_size_bytes.labels(job='chom').observe(response.content_length)


# ============================================================================
# Deployment Metrics - Required for DevOps Deployment Dashboard
# ============================================================================

# Deployment counter
chom_deployment_total = Counter(
    'chom_deployment_total',
    'Total deployments and rollbacks',
    ['type', 'environment', 'version']  # type: deployment|rollback
)

# Deployment duration gauge
chom_deployment_duration_seconds = Gauge(
    'chom_deployment_duration_seconds',
    'Deployment duration in seconds',
    ['environment', 'version']
)

# Lead time for changes
chom_deployment_lead_time_minutes = Gauge(
    'chom_deployment_lead_time_minutes',
    'Lead time from first commit to deployment in minutes',
    ['environment']
)

# Deployment info
chom_deployment_info = Gauge(
    'chom_deployment_info',
    'Current deployment information',
    ['type', 'version', 'environment']
)

def track_deployment(deployment_type, environment, version, duration_seconds=None, lead_time_minutes=None):
    """
    Track deployment metrics

    Args:
        deployment_type: 'deployment' or 'rollback'
        environment: 'production', 'staging', etc.
        version: Deployment version (e.g., 'v1.2.3', git SHA)
        duration_seconds: Time taken to deploy (optional)
        lead_time_minutes: Time from first commit to deployment (optional)
    """
    chom_deployment_total.labels(
        type=deployment_type,
        environment=environment,
        version=version
    ).inc()

    if duration_seconds:
        chom_deployment_duration_seconds.labels(
            environment=environment,
            version=version
        ).set(duration_seconds)

    if lead_time_minutes:
        chom_deployment_lead_time_minutes.labels(
            environment=environment
        ).set(lead_time_minutes)

    chom_deployment_info.labels(
        type=deployment_type,
        version=version,
        environment=environment
    ).set(1)


# ============================================================================
# Error Budget & SLO Metrics - Required for SRE Dashboard
# ============================================================================

# Error budget consumption
chom_error_budget_consumed_total = Counter(
    'chom_error_budget_consumed_total',
    'Total error budget consumed (minutes)',
    ['service']
)

def consume_error_budget(service, minutes):
    """
    Track error budget consumption

    Args:
        service: Service name
        minutes: Minutes of error budget consumed
    """
    chom_error_budget_consumed_total.labels(service=service).inc(minutes)


# ============================================================================
# Incident Metrics - Required for DevOps Dashboard
# ============================================================================

# Mean Time to Recovery
chom_incident_mttr_minutes = Gauge(
    'chom_incident_mttr_minutes',
    'Mean time to recovery in minutes',
    ['severity']
)

def track_incident_resolution(severity, duration_minutes):
    """
    Track incident resolution time

    Args:
        severity: 'critical', 'high', 'medium', 'low'
        duration_minutes: Time taken to resolve incident
    """
    chom_incident_mttr_minutes.labels(severity=severity).set(duration_minutes)


# ============================================================================
# Pipeline Metrics - Required for DevOps Dashboard
# ============================================================================

# Pipeline runs counter
chom_pipeline_runs_total = Counter(
    'chom_pipeline_runs_total',
    'Total CI/CD pipeline runs',
    ['pipeline', 'status']  # status: success|failure
)

# Pipeline duration histogram
chom_pipeline_duration_seconds = Histogram(
    'chom_pipeline_duration_seconds',
    'CI/CD pipeline duration in seconds',
    ['pipeline', 'stage'],
    buckets=(30, 60, 120, 300, 600, 1200, 1800, 3600)
)

def track_pipeline(pipeline_name, stage, status, duration_seconds=None):
    """
    Track CI/CD pipeline metrics

    Args:
        pipeline_name: Name of the pipeline (e.g., 'build', 'test', 'deploy')
        stage: Pipeline stage (e.g., 'build', 'test', 'deploy')
        status: 'success' or 'failure'
        duration_seconds: Time taken for this stage
    """
    chom_pipeline_runs_total.labels(
        pipeline=pipeline_name,
        status=status
    ).inc()

    if duration_seconds:
        chom_pipeline_duration_seconds.labels(
            pipeline=pipeline_name,
            stage=stage
        ).observe(duration_seconds)


# ============================================================================
# Git Metrics - Required for DevOps Dashboard
# ============================================================================

# Git commits counter
chom_git_commits_total = Counter(
    'chom_git_commits_total',
    'Total git commits',
    ['branch']
)

def track_git_commit(branch):
    """
    Track git commit activity

    Args:
        branch: Git branch name
    """
    chom_git_commits_total.labels(branch=branch).inc()


# ============================================================================
# Service Dependency Metrics - Required for Infrastructure Dashboard
# ============================================================================

# Inter-service latency histogram
chom_service_latency_seconds = Histogram(
    'chom_service_latency_seconds',
    'Inter-service communication latency',
    ['source_service', 'target_service'],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0)
)

def track_service_call(source_service, target_service, duration_seconds):
    """
    Track inter-service communication

    Args:
        source_service: Calling service
        target_service: Called service
        duration_seconds: Call duration
    """
    chom_service_latency_seconds.labels(
        source_service=source_service,
        target_service=target_service
    ).observe(duration_seconds)


# ============================================================================
# SSL Certificate Metrics - Required for Infrastructure Dashboard
# ============================================================================

# SSL certificate expiry timestamp
ssl_certificate_expiry_seconds = Gauge(
    'ssl_certificate_expiry_seconds',
    'SSL certificate expiry timestamp (Unix timestamp)',
    ['domain', 'issuer']
)

# SSL certificate validity
ssl_certificate_valid = Gauge(
    'ssl_certificate_valid',
    'SSL certificate validity (1=valid, 0=invalid)',
    ['domain']
)

def track_ssl_certificate(domain, issuer, expiry_timestamp, is_valid):
    """
    Track SSL certificate status

    Args:
        domain: Domain name
        issuer: Certificate issuer
        expiry_timestamp: Unix timestamp of expiry
        is_valid: Boolean indicating certificate validity
    """
    ssl_certificate_expiry_seconds.labels(
        domain=domain,
        issuer=issuer
    ).set(expiry_timestamp)

    ssl_certificate_valid.labels(domain=domain).set(1 if is_valid else 0)


# ============================================================================
# Backup Metrics - Required for Infrastructure Dashboard
# ============================================================================

# Backup counter
chom_backup_total = Counter(
    'chom_backup_total',
    'Total backup operations',
    ['type', 'status']  # type: database|files, status: success|failure
)

# Backup duration gauge
chom_backup_duration_seconds = Gauge(
    'chom_backup_duration_seconds',
    'Backup operation duration in seconds',
    ['type', 'instance']
)

# Last backup timestamp
chom_backup_last_timestamp_seconds = Gauge(
    'chom_backup_last_timestamp_seconds',
    'Timestamp of last backup operation',
    ['type', 'status']
)

# Backup size
chom_backup_size_bytes = Gauge(
    'chom_backup_size_bytes',
    'Backup size in bytes',
    ['type']
)

def track_backup(backup_type, instance, status, duration_seconds, size_bytes):
    """
    Track backup operations

    Args:
        backup_type: 'database' or 'files'
        instance: Instance identifier
        status: 'success' or 'failure'
        duration_seconds: Time taken for backup
        size_bytes: Size of backup in bytes
    """
    chom_backup_total.labels(
        type=backup_type,
        status=status
    ).inc()

    chom_backup_duration_seconds.labels(
        type=backup_type,
        instance=instance
    ).set(duration_seconds)

    chom_backup_last_timestamp_seconds.labels(
        type=backup_type,
        status=status
    ).set(time.time())

    if status == 'success':
        chom_backup_size_bytes.labels(type=backup_type).set(size_bytes)


# ============================================================================
# Logging Metrics - Required for Infrastructure Dashboard
# ============================================================================

# Log entries counter
chom_log_entries_total = Counter(
    'chom_log_entries_total',
    'Total log entries by level',
    ['service', 'level', 'error_type']  # level: debug|info|warning|error|critical
)

def track_log_entry(service, level, error_type=''):
    """
    Track log entry

    Args:
        service: Service name
        level: Log level (debug, info, warning, error, critical)
        error_type: Type of error (optional, for error/critical logs)
    """
    chom_log_entries_total.labels(
        service=service,
        level=level,
        error_type=error_type
    ).inc()


# ============================================================================
# Example Integration Patterns
# ============================================================================

# Example 1: Flask Middleware
def create_flask_middleware(app):
    """
    Example Flask middleware for automatic metric tracking
    """
    from flask import request, g

    @app.before_request
    def before_request():
        g.start_time = time.time()

    @app.after_request
    def after_request(response):
        if hasattr(g, 'start_time'):
            duration = time.time() - g.start_time
            track_request_metrics(request, response, duration)
        return response

    return app


# Example 2: FastAPI Middleware
async def fastapi_metrics_middleware(request, call_next):
    """
    Example FastAPI middleware for automatic metric tracking
    """
    start_time = time.time()
    response = await call_next(request)
    duration = time.time() - start_time

    http_requests_total.labels(
        method=request.method,
        endpoint=request.url.path,
        code=response.status_code,
        job='chom'
    ).inc()

    http_request_duration_seconds.labels(
        method=request.method,
        endpoint=request.url.path,
        job='chom'
    ).observe(duration)

    return response


# Example 3: Decorator for Function Timing
def track_function_duration(metric_name, labels=None):
    """
    Decorator to track function execution duration

    Usage:
        @track_function_duration('my_function')
        def my_function():
            pass
    """
    def decorator(func):
        def wrapper(*args, **kwargs):
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                return result
            finally:
                duration = time.time() - start_time
                # Track duration (implement your histogram here)
        return wrapper
    return decorator


# Example 4: Context Manager for Service Calls
class ServiceCallTracker:
    """
    Context manager for tracking service-to-service calls

    Usage:
        with ServiceCallTracker('api', 'database'):
            result = database.query()
    """
    def __init__(self, source, target):
        self.source = source
        self.target = target
        self.start_time = None

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration = time.time() - self.start_time
        track_service_call(self.source, self.target, duration)


# ============================================================================
# Example Usage in Application
# ============================================================================

if __name__ == '__main__':
    """
    Example usage of metrics instrumentation
    """
    from prometheus_client import start_http_server

    # Start metrics HTTP server
    print("Starting metrics server on port 9090...")
    start_http_server(9090)

    # Simulate some metrics
    print("Generating sample metrics...")

    # HTTP request metrics
    track_request_metrics(
        type('Request', (), {'method': 'GET', 'path': '/api/users', 'content_length': 0})(),
        type('Response', (), {'status_code': 200, 'content_length': 1234})(),
        0.123
    )

    # Deployment metrics
    track_deployment(
        deployment_type='deployment',
        environment='production',
        version='v1.2.3',
        duration_seconds=300,
        lead_time_minutes=45
    )

    # Backup metrics
    track_backup(
        backup_type='database',
        instance='mysql-primary',
        status='success',
        duration_seconds=120,
        size_bytes=1024*1024*500  # 500MB
    )

    # SSL certificate metrics
    track_ssl_certificate(
        domain='example.com',
        issuer='Let\'s Encrypt',
        expiry_timestamp=time.time() + (90 * 24 * 60 * 60),  # 90 days from now
        is_valid=True
    )

    # Pipeline metrics
    track_pipeline(
        pipeline_name='build-and-deploy',
        stage='build',
        status='success',
        duration_seconds=180
    )

    # Log metrics
    track_log_entry(
        service='api',
        level='info'
    )

    print("Sample metrics generated!")
    print("Metrics available at http://localhost:9090/metrics")
    print("Press Ctrl+C to exit...")

    # Keep server running
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutting down...")
