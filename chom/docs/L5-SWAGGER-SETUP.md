# L5-Swagger Integration Guide

This guide explains how to integrate L5-Swagger for automatic OpenAPI documentation generation in CHOM.

## Table of Contents
- [Installation](#installation)
- [Configuration](#configuration)
- [Controller Annotations](#controller-annotations)
- [Schema Definitions](#schema-definitions)
- [Generating Documentation](#generating-documentation)
- [Accessing Swagger UI](#accessing-swagger-ui)
- [Best Practices](#best-practices)

---

## Installation

### Step 1: Install Package

```bash
cd /home/calounx/repositories/mentat/chom
composer require darkaonline/l5-swagger
```

### Step 2: Publish Configuration

```bash
php artisan vendor:publish --provider "L5Swagger\L5SwaggerServiceProvider"
```

This creates:
- `config/l5-swagger.php` - Configuration file
- `storage/api-docs/` - Generated documentation directory
- `resources/views/vendor/l5-swagger/` - Swagger UI views

---

## Configuration

### Edit `config/l5-swagger.php`

```php
<?php

return [
    'default' => 'default',
    'documentations' => [
        'default' => [
            'api' => [
                'title' => 'CHOM SaaS Platform API',
            ],
            'routes' => [
                'api' => 'api/documentation',  // Swagger UI route
                'docs' => 'docs',               // JSON docs route
            ],
            'paths' => [
                'docs' => storage_path('api-docs'),
                'docs_json' => 'api-docs.json',
                'docs_yaml' => 'api-docs.yaml',
                'annotations' => [
                    base_path('app/Http/Controllers/Api'),
                    base_path('app/OpenApi'),
                ],
                'excludes' => [],
            ],
            'scanOptions' => [
                'analyser' => null,
                'analysis' => null,
                'processors' => [],
                'pattern' => null,
                'exclude' => [],
            ],
            'securityDefinitions' => [
                'securitySchemes' => [
                    'bearerAuth' => [
                        'type' => 'http',
                        'scheme' => 'bearer',
                        'bearerFormat' => 'Sanctum',
                    ],
                ],
                'security' => [
                    ['bearerAuth' => []],
                ],
            ],
            'generate_always' => env('L5_SWAGGER_GENERATE_ALWAYS', false),
            'generate_yaml_copy' => true,
            'proxy' => false,
            'additional_config_url' => null,
            'operations_sort' => env('L5_SWAGGER_OPERATIONS_SORT', null),
            'validator_url' => null,
            'ui' => [
                'display' => [
                    'dark_mode' => false,
                    'doc_expansion' => 'list',
                    'filter' => true,
                ],
            ],
            'constants' => [
                'L5_SWAGGER_CONST_HOST' => env('L5_SWAGGER_CONST_HOST', 'http://localhost:8000/api/v1'),
            ],
        ],
    ],
    'defaults' => [
        'routes' => [
            'docs' => 'docs',
            'oauth2_callback' => 'api/oauth2-callback',
            'middleware' => [
                'api' => [],
                'asset' => [],
                'docs' => [],
                'oauth2_callback' => [],
            ],
            'group_options' => [],
        ],
        'paths' => [
            'docs' => storage_path('api-docs'),
            'views' => base_path('resources/views/vendor/l5-swagger'),
            'base' => env('L5_SWAGGER_BASE_PATH', null),
            'swagger_ui_assets_path' => env('L5_SWAGGER_UI_ASSETS_PATH', 'vendor/swagger-api/swagger-ui/dist/'),
            'excludes' => [],
        ],
        'scanOptions' => [
            'default_processors_configuration' => [],
        ],
        'securityDefinitions' => [
            'securitySchemes' => [],
            'security' => [],
        ],
        'generate_always' => env('L5_SWAGGER_GENERATE_ALWAYS', false),
        'generate_yaml_copy' => env('L5_SWAGGER_GENERATE_YAML_COPY', false),
        'proxy' => false,
        'additional_config_url' => null,
        'operations_sort' => env('L5_SWAGGER_OPERATIONS_SORT', null),
        'validator_url' => null,
        'ui' => [
            'display' => [
                'dark_mode' => env('L5_SWAGGER_UI_DARK_MODE', false),
                'doc_expansion' => env('L5_SWAGGER_UI_DOC_EXPANSION', 'none'),
                'filter' => env('L5_SWAGGER_UI_FILTERS', true),
            ],
            'authorization' => [
                'persist_authorization' => env('L5_SWAGGER_UI_PERSIST_AUTHORIZATION', false),
            ],
        ],
        'constants' => [],
    ],
];
```

### Add to `.env`

```env
L5_SWAGGER_GENERATE_ALWAYS=true
L5_SWAGGER_CONST_HOST=http://localhost:8000/api/v1
```

For production:
```env
L5_SWAGGER_GENERATE_ALWAYS=false
L5_SWAGGER_CONST_HOST=https://api.chom.example.com/api/v1
```

---

## Controller Annotations

### Base Controller Annotation

Create `app/Http/Controllers/Controller.php` with base OpenAPI info:

```php
<?php

namespace App\Http\Controllers;

use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Foundation\Validation\ValidatesRequests;
use Illuminate\Routing\Controller as BaseController;

/**
 * @OA\Info(
 *     version="1.0.0",
 *     title="CHOM SaaS Platform API",
 *     description="Comprehensive REST API for CHOM multi-tenant WordPress hosting platform",
 *     @OA\Contact(
 *         email="support@chom.example.com",
 *         name="CHOM API Support"
 *     ),
 *     @OA\License(
 *         name="MIT",
 *         url="https://opensource.org/licenses/MIT"
 *     )
 * )
 *
 * @OA\Server(
 *     url="http://localhost:8000/api/v1",
 *     description="Local development server"
 * )
 *
 * @OA\Server(
 *     url="https://staging.chom.example.com/api/v1",
 *     description="Staging server"
 * )
 *
 * @OA\Server(
 *     url="https://api.chom.example.com/api/v1",
 *     description="Production server"
 * )
 *
 * @OA\SecurityScheme(
 *     securityScheme="bearerAuth",
 *     type="http",
 *     scheme="bearer",
 *     bearerFormat="Sanctum",
 *     description="Laravel Sanctum bearer token authentication"
 * )
 *
 * @OA\Tag(
 *     name="Authentication",
 *     description="User authentication and session management"
 * )
 *
 * @OA\Tag(
 *     name="Sites",
 *     description="WordPress site management and provisioning"
 * )
 *
 * @OA\Tag(
 *     name="Backups",
 *     description="Backup creation, management, and restoration"
 * )
 *
 * @OA\Tag(
 *     name="Team",
 *     description="Team member and invitation management"
 * )
 *
 * @OA\Tag(
 *     name="Organization",
 *     description="Organization settings and configuration"
 * )
 */
class Controller extends BaseController
{
    use AuthorizesRequests, ValidatesRequests;
}
```

### Example: AuthController with Annotations

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AuthController extends Controller
{
    /**
     * Register a new user with organization
     *
     * @OA\Post(
     *     path="/auth/register",
     *     summary="Register a new user and organization",
     *     description="Creates a new user account with an associated organization and default tenant. Returns an API token for immediate use.",
     *     operationId="register",
     *     tags={"Authentication"},
     *     security={},
     *     @OA\RequestBody(
     *         required=true,
     *         description="Registration details",
     *         @OA\JsonContent(
     *             required={"name","email","password","password_confirmation","organization_name"},
     *             @OA\Property(property="name", type="string", maxLength=255, example="John Doe"),
     *             @OA\Property(property="email", type="string", format="email", maxLength=255, example="john@example.com"),
     *             @OA\Property(property="password", type="string", format="password", minLength=8, example="SecurePassword123!"),
     *             @OA\Property(property="password_confirmation", type="string", format="password", example="SecurePassword123!"),
     *             @OA\Property(property="organization_name", type="string", maxLength=255, example="ACME Corporation")
     *         )
     *     ),
     *     @OA\Response(
     *         response=201,
     *         description="Registration successful",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=true),
     *             @OA\Property(property="data", type="object",
     *                 @OA\Property(property="user", type="object",
     *                     @OA\Property(property="id", type="string", format="uuid"),
     *                     @OA\Property(property="name", type="string"),
     *                     @OA\Property(property="email", type="string"),
     *                     @OA\Property(property="role", type="string", example="owner")
     *                 ),
     *                 @OA\Property(property="organization", type="object",
     *                     @OA\Property(property="id", type="string", format="uuid"),
     *                     @OA\Property(property="name", type="string"),
     *                     @OA\Property(property="slug", type="string")
     *                 ),
     *                 @OA\Property(property="tenant", type="object",
     *                     @OA\Property(property="id", type="string", format="uuid"),
     *                     @OA\Property(property="name", type="string"),
     *                     @OA\Property(property="tier", type="string", example="starter")
     *                 ),
     *                 @OA\Property(property="token", type="string", example="1|abcdefghijklmnopqrstuvwxyz")
     *             )
     *         )
     *     ),
     *     @OA\Response(
     *         response=422,
     *         description="Validation error",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=false),
     *             @OA\Property(property="message", type="string", example="The given data was invalid."),
     *             @OA\Property(property="errors", type="object",
     *                 @OA\Property(property="email", type="array", @OA\Items(type="string", example="The email has already been taken."))
     *             )
     *         )
     *     ),
     *     @OA\Response(
     *         response=500,
     *         description="Registration failed",
     *         @OA\JsonContent(ref="#/components/schemas/ErrorResponse")
     *     )
     * )
     */
    public function register(Request $request): JsonResponse
    {
        // Implementation...
    }

    /**
     * Login user
     *
     * @OA\Post(
     *     path="/auth/login",
     *     summary="Login user",
     *     description="Authenticate with email and password to receive an API token.",
     *     operationId="login",
     *     tags={"Authentication"},
     *     security={},
     *     @OA\RequestBody(
     *         required=true,
     *         @OA\JsonContent(
     *             required={"email","password"},
     *             @OA\Property(property="email", type="string", format="email", example="john@example.com"),
     *             @OA\Property(property="password", type="string", format="password", example="SecurePassword123!")
     *         )
     *     ),
     *     @OA\Response(
     *         response=200,
     *         description="Login successful",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=true),
     *             @OA\Property(property="data", type="object",
     *                 @OA\Property(property="user", type="object",
     *                     @OA\Property(property="id", type="string", format="uuid"),
     *                     @OA\Property(property="name", type="string"),
     *                     @OA\Property(property="email", type="string"),
     *                     @OA\Property(property="role", type="string")
     *                 ),
     *                 @OA\Property(property="organization", type="object",
     *                     @OA\Property(property="id", type="string", format="uuid"),
     *                     @OA\Property(property="name", type="string"),
     *                     @OA\Property(property="slug", type="string")
     *                 ),
     *                 @OA\Property(property="token", type="string")
     *             )
     *         )
     *     ),
     *     @OA\Response(
     *         response=401,
     *         description="Invalid credentials",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=false),
     *             @OA\Property(property="error", type="object",
     *                 @OA\Property(property="code", type="string", example="INVALID_CREDENTIALS"),
     *                 @OA\Property(property="message", type="string", example="The provided credentials are incorrect.")
     *             )
     *         )
     *     )
     * )
     */
    public function login(Request $request): JsonResponse
    {
        // Implementation...
    }

    /**
     * Get current user
     *
     * @OA\Get(
     *     path="/auth/me",
     *     summary="Get current user",
     *     description="Returns details about the currently authenticated user",
     *     operationId="getCurrentUser",
     *     tags={"Authentication"},
     *     security={{"bearerAuth":{}}},
     *     @OA\Response(
     *         response=200,
     *         description="User details retrieved successfully",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=true),
     *             @OA\Property(property="data", type="object",
     *                 @OA\Property(property="user", type="object",
     *                     @OA\Property(property="id", type="string", format="uuid"),
     *                     @OA\Property(property="name", type="string"),
     *                     @OA\Property(property="email", type="string"),
     *                     @OA\Property(property="role", type="string"),
     *                     @OA\Property(property="email_verified_at", type="string", format="date-time", nullable=true)
     *                 ),
     *                 @OA\Property(property="organization", type="object", nullable=true),
     *                 @OA\Property(property="tenant", type="object", nullable=true)
     *             )
     *         )
     *     ),
     *     @OA\Response(
     *         response=401,
     *         description="Unauthenticated",
     *         @OA\JsonContent(ref="#/components/schemas/ErrorResponse")
     *     )
     * )
     */
    public function me(Request $request): JsonResponse
    {
        // Implementation...
    }
}
```

### Example: SiteController with Annotations

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SiteController extends Controller
{
    /**
     * List all sites
     *
     * @OA\Get(
     *     path="/sites",
     *     summary="List all sites",
     *     description="Returns a paginated list of all sites for the current tenant with optional filtering",
     *     operationId="listSites",
     *     tags={"Sites"},
     *     security={{"bearerAuth":{}}},
     *     @OA\Parameter(
     *         name="status",
     *         in="query",
     *         description="Filter by site status",
     *         required=false,
     *         @OA\Schema(type="string", enum={"creating","active","disabled","failed","deleting"})
     *     ),
     *     @OA\Parameter(
     *         name="type",
     *         in="query",
     *         description="Filter by site type",
     *         required=false,
     *         @OA\Schema(type="string", enum={"wordpress","html","laravel"})
     *     ),
     *     @OA\Parameter(
     *         name="search",
     *         in="query",
     *         description="Search by domain name",
     *         required=false,
     *         @OA\Schema(type="string")
     *     ),
     *     @OA\Parameter(
     *         name="page",
     *         in="query",
     *         description="Page number",
     *         required=false,
     *         @OA\Schema(type="integer", default=1)
     *     ),
     *     @OA\Parameter(
     *         name="per_page",
     *         in="query",
     *         description="Items per page",
     *         required=false,
     *         @OA\Schema(type="integer", default=20, maximum=100)
     *     ),
     *     @OA\Response(
     *         response=200,
     *         description="Sites retrieved successfully",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=true),
     *             @OA\Property(property="data", type="array", @OA\Items(ref="#/components/schemas/Site")),
     *             @OA\Property(property="meta", ref="#/components/schemas/PaginationMeta")
     *         )
     *     )
     * )
     */
    public function index(Request $request): JsonResponse
    {
        // Implementation...
    }

    /**
     * Create a new site
     *
     * @OA\Post(
     *     path="/sites",
     *     summary="Create a new site",
     *     description="Provisions a new WordPress site on the platform. Site creation is async.",
     *     operationId="createSite",
     *     tags={"Sites"},
     *     security={{"bearerAuth":{}}},
     *     @OA\RequestBody(
     *         required=true,
     *         @OA\JsonContent(
     *             required={"domain"},
     *             @OA\Property(property="domain", type="string", maxLength=253, example="example.com"),
     *             @OA\Property(property="site_type", type="string", enum={"wordpress","html","laravel"}, default="wordpress"),
     *             @OA\Property(property="php_version", type="string", enum={"8.2","8.4"}, default="8.2"),
     *             @OA\Property(property="ssl_enabled", type="boolean", default=true)
     *         )
     *     ),
     *     @OA\Response(
     *         response=201,
     *         description="Site creation started",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=true),
     *             @OA\Property(property="data", ref="#/components/schemas/Site"),
     *             @OA\Property(property="message", type="string", example="Site is being created.")
     *         )
     *     ),
     *     @OA\Response(
     *         response=403,
     *         description="Site limit exceeded",
     *         @OA\JsonContent(
     *             @OA\Property(property="success", type="boolean", example=false),
     *             @OA\Property(property="error", type="object",
     *                 @OA\Property(property="code", type="string", example="SITE_LIMIT_EXCEEDED"),
     *                 @OA\Property(property="message", type="string"),
     *                 @OA\Property(property="details", type="object",
     *                     @OA\Property(property="current_sites", type="integer"),
     *                     @OA\Property(property="limit", type="integer")
     *                 )
     *             )
     *         )
     *     )
     * )
     */
    public function store(Request $request): JsonResponse
    {
        // Implementation...
    }
}
```

---

## Schema Definitions

Create reusable schema definitions in `app/OpenApi/Schemas/`.

### Example: `app/OpenApi/Schemas/Site.php`

```php
<?php

namespace App\OpenApi\Schemas;

/**
 * @OA\Schema(
 *     schema="Site",
 *     type="object",
 *     title="Site",
 *     description="WordPress site resource",
 *     required={"id","domain","site_type","status"},
 *     @OA\Property(property="id", type="string", format="uuid", example="550e8400-e29b-41d4-a716-446655440000"),
 *     @OA\Property(property="domain", type="string", example="example.com"),
 *     @OA\Property(property="url", type="string", format="uri", example="https://example.com"),
 *     @OA\Property(property="site_type", type="string", enum={"wordpress","html","laravel"}, example="wordpress"),
 *     @OA\Property(property="php_version", type="string", example="8.2"),
 *     @OA\Property(property="ssl_enabled", type="boolean", example=true),
 *     @OA\Property(property="ssl_expires_at", type="string", format="date-time", nullable=true),
 *     @OA\Property(property="status", type="string", enum={"creating","active","disabled","failed","deleting"}, example="active"),
 *     @OA\Property(property="storage_used_mb", type="integer", example=245),
 *     @OA\Property(property="created_at", type="string", format="date-time"),
 *     @OA\Property(property="updated_at", type="string", format="date-time"),
 *     @OA\Property(property="vps", type="object", nullable=true,
 *         @OA\Property(property="id", type="string", format="uuid"),
 *         @OA\Property(property="hostname", type="string")
 *     )
 * )
 */
class Site
{
    // Empty class - annotations only
}
```

### Example: `app/OpenApi/Schemas/ErrorResponse.php`

```php
<?php

namespace App\OpenApi\Schemas;

/**
 * @OA\Schema(
 *     schema="ErrorResponse",
 *     type="object",
 *     title="Error Response",
 *     description="Standard error response format",
 *     required={"success","error"},
 *     @OA\Property(property="success", type="boolean", example=false),
 *     @OA\Property(property="error", type="object",
 *         required={"code","message"},
 *         @OA\Property(property="code", type="string", example="ERROR_CODE"),
 *         @OA\Property(property="message", type="string", example="An error occurred."),
 *         @OA\Property(property="details", type="object", additionalProperties=true)
 *     )
 * )
 */
class ErrorResponse
{
    // Empty class - annotations only
}
```

### Example: `app/OpenApi/Schemas/PaginationMeta.php`

```php
<?php

namespace App\OpenApi\Schemas;

/**
 * @OA\Schema(
 *     schema="PaginationMeta",
 *     type="object",
 *     title="Pagination Metadata",
 *     @OA\Property(property="pagination", type="object",
 *         @OA\Property(property="current_page", type="integer", example=1),
 *         @OA\Property(property="per_page", type="integer", example=20),
 *         @OA\Property(property="total", type="integer", example=42),
 *         @OA\Property(property="total_pages", type="integer", example=3)
 *     )
 * )
 */
class PaginationMeta
{
    // Empty class - annotations only
}
```

---

## Generating Documentation

### Manual Generation

```bash
php artisan l5-swagger:generate
```

This generates:
- `storage/api-docs/api-docs.json` - OpenAPI JSON
- `storage/api-docs/api-docs.yaml` - OpenAPI YAML

### Automatic Generation

Set in `.env`:
```env
L5_SWAGGER_GENERATE_ALWAYS=true
```

Documentation regenerates on every request (development only).

### Production Setup

For production, generate once and disable auto-generation:

```bash
php artisan l5-swagger:generate
```

`.env`:
```env
L5_SWAGGER_GENERATE_ALWAYS=false
```

---

## Accessing Swagger UI

### Local Development

Visit: `http://localhost:8000/api/documentation`

### Staging

Visit: `https://staging.chom.example.com/api/documentation`

### Production

Visit: `https://api.chom.example.com/api/documentation`

### Testing with Swagger UI

1. Visit Swagger UI URL
2. Click "Authorize" button
3. Enter Bearer token: `Bearer YOUR_TOKEN_HERE`
4. Click "Authorize"
5. Try API endpoints directly from the UI

---

## Best Practices

### 1. Keep Annotations Minimal

Use `@OA\JsonContent(ref="#/components/schemas/Site")` instead of inline definitions:

```php
// Bad - Inline definition
@OA\JsonContent(
    @OA\Property(property="id", type="string"),
    @OA\Property(property="domain", type="string"),
    // ... 20 more properties
)

// Good - Reference schema
@OA\JsonContent(ref="#/components/schemas/Site")
```

### 2. Reuse Components

Define common responses once:

```php
/**
 * @OA\Response(
 *     response="NotFound",
 *     description="Resource not found",
 *     @OA\JsonContent(ref="#/components/schemas/ErrorResponse")
 * )
 */
```

Then reference:
```php
@OA\Response(response=404, ref="#/components/responses/NotFound")
```

### 3. Document All Error Responses

Always document:
- 200/201 Success
- 400 Bad Request
- 401 Unauthorized
- 403 Forbidden
- 404 Not Found
- 422 Validation Error
- 500 Server Error

### 4. Use Examples

Provide realistic examples:

```php
@OA\Property(
    property="domain",
    type="string",
    example="example.com",  // Always include examples
    description="The site domain name"
)
```

### 5. Keep Documentation Up-to-Date

Run after controller changes:
```bash
php artisan l5-swagger:generate
```

### 6. Validate Generated Documentation

Use online validator:
```bash
# Generate and validate
php artisan l5-swagger:generate
curl -X POST "https://validator.swagger.io/validator/debug" \
  -H "Content-Type: application/json" \
  -d @storage/api-docs/api-docs.json
```

---

## Troubleshooting

### Documentation Not Generating

**Issue**: `php artisan l5-swagger:generate` fails

**Solutions**:
1. Check annotations syntax
2. Ensure `storage/api-docs/` is writable
3. Clear cache: `php artisan cache:clear`
4. Check PHP memory limit

### Swagger UI Not Loading

**Issue**: Blank page at `/api/documentation`

**Solutions**:
1. Verify route is published
2. Check `storage/api-docs/api-docs.json` exists
3. Check browser console for errors
4. Verify L5_SWAGGER_CONST_HOST in `.env`

### Authentication Not Working

**Issue**: "Authorize" button doesn't work

**Solutions**:
1. Check `securitySchemes` in config
2. Verify `security={{"bearerAuth":{}}}` in annotations
3. Include `Bearer` prefix in token

---

## Directory Structure

```
app/
├── Http/
│   └── Controllers/
│       ├── Controller.php (Base annotations)
│       └── Api/
│           └── V1/
│               ├── AuthController.php (Annotated)
│               ├── SiteController.php (Annotated)
│               ├── BackupController.php (Annotated)
│               └── TeamController.php (Annotated)
└── OpenApi/
    └── Schemas/
        ├── Site.php
        ├── Backup.php
        ├── User.php
        ├── ErrorResponse.php
        └── PaginationMeta.php

config/
└── l5-swagger.php

storage/
└── api-docs/
    ├── api-docs.json (Generated)
    └── api-docs.yaml (Generated)
```

---

## Next Steps

1. **Add annotations** to all controllers
2. **Create schema classes** for all models
3. **Generate documentation**: `php artisan l5-swagger:generate`
4. **Test Swagger UI**: Visit `/api/documentation`
5. **Customize UI**: Edit views in `resources/views/vendor/l5-swagger/`

---

## Resources

- [L5-Swagger Documentation](https://github.com/DarkaOnLine/L5-Swagger)
- [OpenAPI Specification](https://swagger.io/specification/)
- [Swagger Editor](https://editor.swagger.io/)
- [Swagger Validator](https://validator.swagger.io/)

---

**Last Updated**: 2024-01-15
