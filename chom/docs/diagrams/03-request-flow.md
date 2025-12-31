# CHOM Request Flow Architecture

This diagram shows the complete flow of an HTTP request through the CHOM application, from initial reception to response delivery.

```mermaid
graph TB
    subgraph "Client"
        CLIENT[API Client<br/>Web/Mobile/CLI]
    end

    subgraph "Entry Point"
        NGINX_ENTRY[Nginx<br/>Reverse Proxy]
        PHP_FPM[PHP-FPM 8.2/8.4<br/>Process Pool]
    end

    subgraph "Laravel Bootstrap"
        KERNEL[HTTP Kernel<br/>Request Handler]
        ROUTER[Router<br/>Route Matching]
    end

    subgraph "Middleware Stack - Execution Order"
        MW1[1. TrustProxies<br/>Proxy Header Validation]
        MW2[2. EncryptCookies<br/>Decrypt Cookies]
        MW3[3. SecurityHeaders<br/>Set HSTS/CSP/X-Frame]
        MW4[4. ThrottleRequests<br/>Rate Limiting Check]
        MW5[5. SubstituteBindings<br/>Route Model Binding]

        subgraph "Authenticated Routes Only"
            MW6[6. Authenticate Sanctum<br/>Token Validation]
            MW7[7. EnsureTenantContext<br/>Load & Verify Tenant]
            MW8[8. RequireTwoFactor<br/>2FA Verification]
            MW9[9. VerifyRequestSignature<br/>Webhook Signature]
            MW10[10. RotateToken<br/>Token Rotation]
            MW11[11. AuditSecurityEvents<br/>Log Security Actions]
            MW12[12. PerformanceMonitoring<br/>Metrics Collection]
        end
    end

    subgraph "Controller Layer"
        VALIDATE[Request Validation<br/>FormRequest Rules]
        CONTROLLER[Controller Method<br/>Business Logic Entry]
    end

    subgraph "Authorization Layer"
        POLICY[Policy Check<br/>Resource Authorization]
        GATE[Gate Check<br/>Feature Authorization]
    end

    subgraph "Service Layer"
        SERVICE[Service Class<br/>Business Logic]
        TRANSACTION[Database Transaction<br/>Begin]
    end

    subgraph "Repository Layer"
        REPO[Repository<br/>Data Access Abstraction]
        CACHE_CHECK{Cache Hit?}
    end

    subgraph "ORM Layer - Eloquent"
        GLOBAL_SCOPES[Global Scopes<br/>Apply tenant_id Filter]
        QUERY_BUILDER[Query Builder<br/>Build SQL]
        QUERY_LOG[Query Logging<br/>Debug Bar]
    end

    subgraph "Database Layer"
        CONNECTION_POOL[Connection Pool<br/>PDO Connections]
        DB_QUERY[Execute Query<br/>Prepared Statement]
        DB[(Database<br/>MySQL/PostgreSQL/SQLite)]
    end

    subgraph "Cache Layer"
        REDIS_CHECK{Redis<br/>Cache Check}
        CACHE_WRITE[Cache Write<br/>TTL: 5min-1hr]
        REDIS[(Redis Cache<br/>Query/Session/API)]
    end

    subgraph "Response Pipeline"
        MODEL_TRANSFORM[Model to Array<br/>Hidden Fields Removed]
        RESOURCE[API Resource<br/>JSON Transformation]
        RESPONSE_MW[Response Middleware<br/>Reverse Order]
        JSON_RESPONSE[JSON Response<br/>Format + Headers]
    end

    subgraph "Monitoring & Logging"
        METRICS[Prometheus Metrics<br/>Request Duration<br/>Status Codes]
        APP_LOG[Application Logs<br/>Error/Info/Debug]
        AUDIT[Audit Log<br/>Security Events]
    end

    %% Request Flow
    CLIENT -->|1. HTTP Request<br/>GET/POST/PUT/DELETE| NGINX_ENTRY
    NGINX_ENTRY -->|2. FastCGI Protocol| PHP_FPM
    PHP_FPM -->|3. Bootstrap Laravel| KERNEL
    KERNEL -->|4. Match Route| ROUTER

    %% Middleware Stack
    ROUTER -->|5. Execute Middleware| MW1
    MW1 --> MW2
    MW2 --> MW3
    MW3 --> MW4
    MW4 --> MW5
    MW5 --> MW6

    %% Authenticated Middleware
    MW6 -->|Token Valid| MW7
    MW7 -->|Tenant Active| MW8
    MW8 -->|2FA Verified| MW9
    MW9 -->|Signature OK| MW10
    MW10 -->|Rotated if needed| MW11
    MW11 -->|Logged| MW12
    MW12 -->|Continue| VALIDATE

    %% Authentication Failures
    MW6 -.->|Token Invalid| JSON_RESPONSE
    MW7 -.->|No Tenant| JSON_RESPONSE
    MW8 -.->|2FA Required| JSON_RESPONSE
    MW9 -.->|Invalid Signature| JSON_RESPONSE

    %% Rate Limiting
    MW4 -.->|Rate Limit Hit| JSON_RESPONSE

    %% Controller Flow
    VALIDATE -->|Valid| CONTROLLER
    VALIDATE -.->|Invalid| JSON_RESPONSE
    CONTROLLER -->|Check Authorization| POLICY
    POLICY -->|Authorized| GATE
    POLICY -.->|Unauthorized 403| JSON_RESPONSE
    GATE -->|Allowed| SERVICE
    GATE -.->|Forbidden| JSON_RESPONSE

    %% Service Layer
    SERVICE -->|Start Transaction| TRANSACTION
    TRANSACTION -->|Query Data| REPO

    %% Repository & Cache
    REPO -->|Check Cache| CACHE_CHECK
    CACHE_CHECK -->|Hit| REDIS_CHECK
    CACHE_CHECK -->|Miss| GLOBAL_SCOPES
    REDIS_CHECK -->|Return Cached| SERVICE

    %% ORM & Database
    GLOBAL_SCOPES -->|Apply Filters| QUERY_BUILDER
    QUERY_BUILDER -->|Log Query| QUERY_LOG
    QUERY_BUILDER -->|Execute| CONNECTION_POOL
    CONNECTION_POOL --> DB_QUERY
    DB_QUERY --> DB
    DB -->|Result Set| QUERY_BUILDER
    QUERY_BUILDER -->|Hydrate Models| REPO

    %% Cache Write
    REPO -->|Store in Cache| CACHE_WRITE
    CACHE_WRITE --> REDIS

    %% Response Flow
    REPO -->|Return Data| SERVICE
    SERVICE -->|Commit Transaction| TRANSACTION
    TRANSACTION -->|Return to Controller| CONTROLLER
    CONTROLLER -->|Transform| MODEL_TRANSFORM
    MODEL_TRANSFORM -->|Apply Resource| RESOURCE
    RESOURCE -->|Pass Through MW| RESPONSE_MW
    RESPONSE_MW -->|Build Response| JSON_RESPONSE
    JSON_RESPONSE -->|HTTP Response| CLIENT

    %% Monitoring
    MW12 -.->|Record Metrics| METRICS
    SERVICE -.->|Log Events| APP_LOG
    MW11 -.->|Audit Trail| AUDIT
    QUERY_LOG -.->|Debug Info| APP_LOG

    %% Error Handling
    SERVICE -.->|Exception| JSON_RESPONSE
    DB_QUERY -.->|SQL Error| JSON_RESPONSE
    CONTROLLER -.->|Business Error| JSON_RESPONSE

    %% Styling
    classDef entry fill:#dc2626,stroke:#333,stroke-width:2px,color:#fff
    classDef middleware fill:#ea580c,stroke:#333,stroke-width:2px,color:#fff
    classDef controller fill:#4f46e5,stroke:#333,stroke-width:2px,color:#fff
    classDef service fill:#7c3aed,stroke:#333,stroke-width:2px,color:#fff
    classDef data fill:#059669,stroke:#333,stroke-width:2px,color:#fff
    classDef response fill:#0891b2,stroke:#333,stroke-width:2px,color:#fff
    classDef monitor fill:#d97706,stroke:#333,stroke-width:2px,color:#fff

    class NGINX_ENTRY,PHP_FPM,KERNEL,ROUTER entry
    class MW1,MW2,MW3,MW4,MW5,MW6,MW7,MW8,MW9,MW10,MW11,MW12 middleware
    class VALIDATE,CONTROLLER,POLICY,GATE controller
    class SERVICE,TRANSACTION,REPO service
    class GLOBAL_SCOPES,QUERY_BUILDER,CONNECTION_POOL,DB_QUERY,DB,REDIS_CHECK,CACHE_WRITE,REDIS data
    class MODEL_TRANSFORM,RESOURCE,RESPONSE_MW,JSON_RESPONSE response
    class METRICS,APP_LOG,AUDIT monitor
```

## Request Flow Detailed Breakdown

### Phase 1: Request Reception (10-20ms)

```
1. Nginx Reverse Proxy
   - TLS termination
   - Static file serving (bypasses PHP)
   - Load balancing (if multiple PHP-FPM pools)
   - Request buffering

2. PHP-FPM Process Pool
   - Process manager: dynamic (min: 2, max: 10)
   - Request queuing if pool full
   - Process lifecycle management
```

### Phase 2: Laravel Bootstrap (5-15ms)

```php
3. HTTP Kernel (app/Http/Kernel.php)
   - Load application
   - Register middleware
   - Handle exceptions
   - Service provider booting

4. Router (routes/api.php)
   - Route matching: O(1) lookup via compiled routes
   - Parameter extraction
   - Route model binding preparation
```

### Phase 3: Middleware Execution (20-50ms)

#### Global Middleware (Always Executed)
```php
1. TrustProxies (2ms)
   - Validate X-Forwarded-* headers
   - Set trusted proxy IPs

2. EncryptCookies (3ms)
   - Decrypt incoming cookies
   - Prepare for encryption on response

3. SecurityHeaders (1ms)
   - Strict-Transport-Security: max-age=31536000
   - X-Content-Type-Options: nosniff
   - X-Frame-Options: DENY
   - Content-Security-Policy: default-src 'self'

4. ThrottleRequests (5ms)
   - Redis-based rate limiting
   - Key: {user_id}:{route}:{minute}
   - Limits: 5/min (auth), 60/min (api), 2/min (sensitive)

5. SubstituteBindings (8ms)
   - Route model binding
   - Fetch models by ID from route parameters
   - Applies global scopes (tenant filtering)
```

#### Authenticated Route Middleware
```php
6. Authenticate Sanctum (15ms)
   - Extract Bearer token from Authorization header
   - Query personal_access_tokens table
   - Verify token expiration
   - Load authenticated user
   - Check abilities/scopes

7. EnsureTenantContext (10ms)
   - Load user's current tenant
   - Verify tenant exists
   - Check tenant is active
   - Set tenant in request attributes
   - Make available to all downstream components

8. RequireTwoFactor (8ms)
   - Check if 2FA required for user role
   - Verify 2FA is enabled
   - Check session has 2FA verification
   - Validate verification timestamp (<24hrs)
   - Allow grace period for setup

9. VerifyRequestSignature (5ms)
   - For webhooks only (Stripe, etc.)
   - Calculate HMAC-SHA256 signature
   - Compare with header signature
   - Prevent replay attacks

10. RotateToken (12ms)
    - Check token age
    - If < 15min until expiry: create new token
    - Delete old token (after grace period)
    - Add X-New-Token header to response

11. AuditSecurityEvents (7ms)
    - Log security-relevant actions
    - Record: user, tenant, IP, action, resource
    - Calculate hash chain for integrity
    - Store in audit_logs table

12. PerformanceMonitoring (3ms)
    - Start request timer
    - Increment request counter
    - Track route-specific metrics
    - Prepared for response-time recording
```

### Phase 4: Controller & Authorization (10-30ms)

```php
// Request Validation (10ms)
- Run FormRequest rules
- Validate input types, formats, constraints
- Custom validation rules
- Early return on failure (422 response)

// Controller Method (5ms)
- Extract validated data
- Prepare for service call
- Handle method-specific logic

// Policy Check (8ms)
- Load applicable policy (e.g., SitePolicy)
- Run policy method (e.g., update())
- Check: user role, tenant ownership, resource status
- Return: authorize or deny (403)

// Gate Check (7ms)
- Feature-level authorization
- Check: subscriptions, tier limits, feature flags
- Example: Can user create more sites?
```

### Phase 5: Service Layer Execution (30-100ms)

```php
// Service Class (Variable duration)
class SiteService {
    public function createSite(array $data): Site {
        // 1. Business validation (5ms)
        $this->validateBusinessRules($data);

        // 2. Start database transaction (2ms)
        DB::beginTransaction();

        try {
            // 3. Create site record (15ms)
            $site = $this->repository->create($data);

            // 4. Allocate VPS (20ms)
            $vps = $this->vpsService->allocate($site);

            // 5. Dispatch background job (5ms)
            DeploySiteJob::dispatch($site);

            // 6. Update cached statistics (10ms)
            $site->tenant->updateCachedStats();

            // 7. Commit transaction (8ms)
            DB::commit();

            return $site;
        } catch (Exception $e) {
            DB::rollBack();
            throw $e;
        }
    }
}
```

### Phase 6: Repository & Database (20-80ms)

```php
// Repository Layer (10ms)
- Abstraction over Eloquent
- Caching logic
- Query optimization

// Cache Check (5ms)
$cacheKey = "sites:tenant:{$tenantId}:list";
if (Cache::has($cacheKey)) {
    return Cache::get($cacheKey); // ~2ms from Redis
}

// Global Scopes (8ms)
- Automatically applied to all queries
- tenant_id filter
- soft delete filter
- Example: WHERE tenant_id = '{current_tenant_id}'

// Query Builder (15ms)
- Build SQL with parameter binding
- Apply eager loading (with relations)
- Apply query scopes
- Log query to debugbar

// Connection Pool (5ms)
- Reuse existing PDO connection
- Or establish new connection (100ms if cold)

// Execute Query (30ms average)
SELECT * FROM sites
WHERE tenant_id = ?
  AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 20;

// Hydrate Models (20ms)
- Convert result rows to Eloquent models
- Cast attributes (dates, booleans, encrypted fields)
- Load relationships

// Cache Write (3ms)
Cache::put($cacheKey, $sites, 300); // 5 min TTL
```

### Phase 7: Response Construction (10-20ms)

```php
// Model to Array (5ms)
- Remove hidden fields (passwords, keys)
- Apply casts
- Include relationships

// API Resource Transformation (8ms)
class SiteResource extends JsonResource {
    public function toArray($request) {
        return [
            'id' => $this->id,
            'domain' => $this->domain,
            'type' => $this->site_type,
            'status' => $this->status,
            'ssl_enabled' => $this->ssl_enabled,
            'url' => $this->getUrl(),
            'created_at' => $this->created_at->toIso8601String(),
        ];
    }
}

// Response Middleware (Reverse Order) (5ms)
- Execute middleware terminate() methods
- PerformanceMonitoring: record duration
- AuditSecurityEvents: finalize log entry

// JSON Response (2ms)
- Wrap in standard envelope
- Add response headers
- Set status code
```

### Phase 8: Response Delivery

```php
// Response Format
{
    "success": true,
    "data": { /* resource */ },
    "meta": {
        "total": 15,
        "per_page": 20,
        "current_page": 1
    }
}

// Headers
Content-Type: application/json
X-New-Token: {rotated_token} // if token rotation occurred
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 55
X-Request-ID: uuid

// Nginx sends to client
- Gzip compression
- Keep-alive connection
- Response buffering
```

## Error Handling Flow

```mermaid
graph LR
    ERROR[Exception Thrown] --> HANDLER[Exception Handler]

    HANDLER --> AUTH_ERROR{Authentication<br/>Error?}
    HANDLER --> VALIDATION{Validation<br/>Error?}
    HANDLER --> AUTHZ_ERROR{Authorization<br/>Error?}
    HANDLER --> BUSINESS{Business<br/>Logic Error?}
    HANDLER --> SYSTEM{System<br/>Error?}

    AUTH_ERROR -->|Yes| RESP_401[401 Unauthenticated]
    VALIDATION -->|Yes| RESP_422[422 Validation Failed]
    AUTHZ_ERROR -->|Yes| RESP_403[403 Forbidden]
    BUSINESS -->|Yes| RESP_400[400 Bad Request]
    SYSTEM -->|Yes| RESP_500[500 Internal Error]

    RESP_401 --> LOG[Log Error]
    RESP_422 --> LOG
    RESP_403 --> LOG
    RESP_400 --> LOG
    RESP_500 --> LOG

    LOG --> NOTIFY{Critical?}
    NOTIFY -->|Yes| ALERT[Send Alert]
    NOTIFY -->|No| METRICS[Update Metrics]

    ALERT --> METRICS
    METRICS --> CLIENT[Return Error Response]
```

## Performance Benchmarks

### Typical Request Timings
```
Metric                          Cold Start    Warm (Cached)
─────────────────────────────────────────────────────────────
Total Request Time              250-400ms     80-150ms
├─ Nginx + PHP-FPM             10-20ms       10-20ms
├─ Laravel Bootstrap           15-30ms       5-15ms
├─ Middleware Stack            50-80ms       20-50ms
├─ Authorization               15-25ms       10-20ms
├─ Database Query              50-120ms      2-5ms (cached)
├─ Business Logic              30-80ms       30-80ms
└─ Response Construction       10-20ms       10-20ms

Database Queries per Request    2-8 queries   0-2 queries (cached)
Memory Usage                    25-35 MB      20-30 MB
CPU Time                        100-200ms     50-100ms
```

### Optimization Strategies Applied

1. **Query Optimization**
   - Eager loading relationships (N+1 prevention)
   - Index optimization on tenant_id, status, created_at
   - Cached aggregates for counts/sums

2. **Caching Strategy**
   - Redis for session, query, API response caching
   - Cache warming for frequently accessed data
   - TTL: 5 min (dynamic), 1 hour (static)

3. **Connection Pooling**
   - Redis: persistent connections
   - Database: PDO connection reuse
   - SSH: connection pool for VPS management

4. **Global Scopes Optimization**
   - Tenant filtering at database level
   - Prevents full table scans
   - Indexed columns for fast lookups

5. **Background Processing**
   - Long-running tasks queued (deployment, backups)
   - Immediate response to client
   - Status polling for completion
