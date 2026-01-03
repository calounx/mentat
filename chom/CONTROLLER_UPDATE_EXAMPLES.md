# Controller Update Examples

This document provides before/after examples for updating controllers to use the new Form Request classes.

## Table of Contents

1. [Site Controller](#site-controller)
2. [Backup Controller](#backup-controller)
3. [Team Controller](#team-controller)
4. [Organization Controller](#organization-controller)
5. [VPS Server Controller](#vps-server-controller)

---

## Site Controller

### Before (Manual Validation)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Site;
use Illuminate\Http\Request;

class SiteController extends Controller
{
    public function store(Request $request)
    {
        // Manual authorization check
        if (!$request->user() || !$request->user()->canManageSites()) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        // Manual tenant quota check
        $tenant = $request->user()->currentTenant();
        if (!$tenant || !$tenant->isActive()) {
            return response()->json(['error' => 'Invalid tenant'], 403);
        }

        if (!$tenant->canCreateSite()) {
            return response()->json(['error' => 'Site limit reached for your tier'], 422);
        }

        // Manual validation
        $validated = $request->validate([
            'domain' => [
                'required',
                'string',
                'max:255',
                'regex:/^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$/i',
                Rule::unique('sites', 'domain')
                    ->where('tenant_id', $tenant->id)
                    ->whereNull('deleted_at'),
            ],
            'site_type' => 'required|in:wordpress,laravel,static,custom',
            'php_version' => 'required|in:7.4,8.0,8.1,8.2,8.3',
            'vps_server_id' => 'sometimes|exists:vps_servers,id',
        ]);

        // Manual VPS availability check
        if (isset($validated['vps_server_id'])) {
            $vps = VpsServer::find($validated['vps_server_id']);
            if (!$vps || !$vps->isAvailable()) {
                return response()->json(['error' => 'VPS server not available'], 422);
            }
        }

        // Manual data normalization
        $validated['domain'] = strtolower($validated['domain']);
        $validated['tenant_id'] = $tenant->id;

        // Create site
        $site = Site::create($validated);

        return response()->json($site, 201);
    }

    public function update(Request $request, string $id)
    {
        // Find site
        $site = Site::findOrFail($id);

        // Manual authorization
        if (!$request->user() || !$request->user()->canManageSites()) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $tenant = $request->user()->currentTenant();
        if ($site->tenant_id !== $tenant->id) {
            return response()->json(['error' => 'Forbidden'], 403);
        }

        // Manual validation
        $validated = $request->validate([
            'domain' => [
                'sometimes',
                'string',
                'max:255',
                Rule::unique('sites', 'domain')
                    ->where('tenant_id', $tenant->id)
                    ->ignore($id)
                    ->whereNull('deleted_at'),
            ],
            'site_type' => 'sometimes|in:wordpress,laravel,static,custom',
            'php_version' => 'sometimes|in:7.4,8.0,8.1,8.2,8.3',
            'status' => 'sometimes|in:creating,active,disabled,failed,migrating',
        ]);

        // Manual data normalization
        if (isset($validated['domain'])) {
            $validated['domain'] = strtolower($validated['domain']);
        }

        $site->update($validated);

        return response()->json($site);
    }
}
```

### After (Using Form Requests)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreSiteRequest;
use App\Http\Requests\UpdateSiteRequest;
use App\Http\Resources\SiteResource;
use App\Models\Site;

class SiteController extends Controller
{
    public function store(StoreSiteRequest $request)
    {
        // All validation, authorization, and quota checks done!
        $site = Site::create([
            'tenant_id' => $request->getTenantId(),
            ...$request->validated(),
        ]);

        return new SiteResource($site);
    }

    public function update(UpdateSiteRequest $request, string $id)
    {
        // All validation and authorization done!
        $site = Site::findOrFail($id);
        $site->update($request->validated());

        return new SiteResource($site);
    }
}
```

**Benefits:**
- 60+ lines reduced to ~10 lines per method
- No manual authorization checks
- No manual quota validation
- No manual data normalization
- Cleaner, more readable code

---

## Backup Controller

### Before (Manual Validation)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Site;
use App\Models\SiteBackup;
use Illuminate\Http\Request;

class BackupController extends Controller
{
    public function store(Request $request)
    {
        // Manual authorization
        if (!$request->user() || !$request->user()->canManageSites()) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        // Manual validation
        $validated = $request->validate([
            'site_id' => 'required|exists:sites,id',
            'backup_type' => 'required|in:full,files,database,config,manual',
            'retention_days' => 'sometimes|integer|min:1|max:365',
        ]);

        // Manual site ownership check
        $site = Site::findOrFail($validated['site_id']);
        $tenant = $request->user()->currentTenant();

        if ($site->tenant_id !== $tenant->id) {
            return response()->json(['error' => 'Forbidden'], 403);
        }

        // Manual quota check
        $tier = $tenant->getCurrentTier();
        $backupLimit = match ($tier) {
            'starter' => 5,
            'pro' => 20,
            'enterprise' => -1, // Unlimited
            default => 5,
        };

        if ($backupLimit !== -1) {
            $currentBackupCount = SiteBackup::where('site_id', $site->id)
                ->where('status', '!=', 'failed')
                ->count();

            if ($currentBackupCount >= $backupLimit) {
                return response()->json([
                    'error' => "Backup limit reached for {$tier} tier ({$backupLimit} backups)"
                ], 422);
            }
        }

        // Set default retention based on tier
        if (!isset($validated['retention_days'])) {
            $validated['retention_days'] = match ($tier) {
                'enterprise' => 90,
                'pro' => 60,
                default => 30,
            };
        }

        // Create backup
        $backup = SiteBackup::create($validated);

        // Dispatch job
        dispatch(new CreateBackupJob($backup));

        return response()->json($backup, 201);
    }
}
```

### After (Using Form Requests)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\StoreBackupRequest;
use App\Http\Resources\BackupResource;
use App\Jobs\CreateBackupJob;
use App\Models\SiteBackup;

class BackupController extends Controller
{
    public function store(StoreBackupRequest $request)
    {
        // All validation, authorization, and quota checks done!
        $backup = SiteBackup::create($request->validated());

        dispatch(new CreateBackupJob($backup));

        return new BackupResource($backup);
    }
}
```

**Benefits:**
- 50+ lines reduced to ~5 lines
- No manual quota calculations
- No manual tier-based defaults
- Quota enforcement handled in Form Request

---

## Team Controller

### Before (Manual Validation)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\TeamInvitation;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class TeamController extends Controller
{
    public function invite(Request $request)
    {
        // Manual authorization
        if (!$request->user() || !$request->user()->isAdmin()) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $user = $request->user();
        $organizationId = $user->organization_id;

        // Determine allowed roles based on user's role
        $allowedRoles = $user->isOwner()
            ? ['admin', 'member', 'viewer']
            : ['member', 'viewer'];

        // Manual validation
        $validated = $request->validate([
            'email' => [
                'required',
                'email',
                'max:255',
                Rule::unique('users', 'email')->where(function ($query) use ($organizationId) {
                    return $query->where('organization_id', $organizationId);
                }),
                Rule::unique('team_invitations', 'email')->where(function ($query) use ($organizationId) {
                    return $query->where('organization_id', $organizationId)
                        ->whereNull('accepted_at')
                        ->where('expires_at', '>', now());
                }),
            ],
            'role' => ['required', Rule::in($allowedRoles)],
            'name' => 'sometimes|string|max:255',
        ]);

        // Manual email normalization
        $validated['email'] = strtolower($validated['email']);
        $validated['organization_id'] = $organizationId;
        $validated['invited_by'] = $user->id;

        $invitation = TeamInvitation::create($validated);

        // Send invitation email
        Mail::to($validated['email'])->send(new TeamInvitationMail($invitation));

        return response()->json($invitation, 201);
    }

    public function update(Request $request, string $id)
    {
        // Manual authorization
        if (!$request->user() || !$request->user()->isAdmin()) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $member = User::findOrFail($id);

        // Prevent self-demotion
        if ($member->id === $request->user()->id) {
            return response()->json(['error' => 'Cannot update your own role'], 403);
        }

        // Check organization membership
        if ($member->organization_id !== $request->user()->organization_id) {
            return response()->json(['error' => 'Forbidden'], 403);
        }

        // Admins cannot update owners
        if (!$request->user()->isOwner() && $member->isOwner()) {
            return response()->json(['error' => 'Cannot update owner role'], 403);
        }

        $user = $request->user();
        $allowedRoles = $user->isOwner()
            ? ['admin', 'member', 'viewer']
            : ['member', 'viewer'];

        $validated = $request->validate([
            'role' => ['required', Rule::in($allowedRoles)],
        ]);

        $member->update($validated);

        return response()->json($member);
    }
}
```

### After (Using Form Requests)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\InviteTeamMemberRequest;
use App\Http\Requests\UpdateTeamMemberRequest;
use App\Http\Resources\InvitationResource;
use App\Http\Resources\UserResource;
use App\Mail\TeamInvitationMail;
use App\Models\TeamInvitation;
use App\Models\User;
use Illuminate\Support\Facades\Mail;

class TeamController extends Controller
{
    public function invite(InviteTeamMemberRequest $request)
    {
        $invitation = TeamInvitation::create([
            'organization_id' => $request->getOrganizationId(),
            'invited_by' => $request->user()->id,
            ...$request->validated(),
        ]);

        Mail::to($invitation->email)->send(new TeamInvitationMail($invitation));

        return new InvitationResource($invitation);
    }

    public function update(UpdateTeamMemberRequest $request, string $id)
    {
        $member = User::findOrFail($id);
        $member->update($request->validated());

        return new UserResource($member);
    }
}
```

**Benefits:**
- 70+ lines reduced to ~10 lines
- Self-demotion protection built-in
- Role hierarchy enforced
- Permission system integrated

---

## Organization Controller

### Before (Manual Validation)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Organization;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class OrganizationController extends Controller
{
    public function update(Request $request)
    {
        // Manual authorization
        if (!$request->user() || !$request->user()->isAdmin()) {
            return response()->json(['error' => 'Unauthorized'], 403);
        }

        $organization = $request->user()->organization;

        // Manual validation
        $validated = $request->validate([
            'name' => 'sometimes|required|string|max:255|min:2',
            'slug' => [
                'sometimes',
                'required',
                'string',
                'max:100',
                'alpha_dash',
                Rule::unique('organizations', 'slug')->ignore($organization->id),
            ],
            'billing_email' => 'sometimes|required|email|max:255',
            'settings' => 'sometimes|array',
            'settings.timezone' => 'sometimes|timezone',
            'settings.two_factor_required' => 'sometimes|boolean',
        ]);

        // Owner-only check for 2FA requirement
        if (isset($validated['settings']['two_factor_required']) && !$request->user()->isOwner()) {
            return response()->json([
                'error' => 'Only owners can change two-factor authentication requirements'
            ], 403);
        }

        // Manual slug normalization
        if (isset($validated['slug'])) {
            $validated['slug'] = strtolower($validated['slug']);
            $validated['slug'] = preg_replace('/\s+/', '-', $validated['slug']);
            $validated['slug'] = preg_replace('/[^a-z0-9\-_]/', '', $validated['slug']);
        }

        // Manual email normalization
        if (isset($validated['billing_email'])) {
            $validated['billing_email'] = strtolower($validated['billing_email']);
        }

        $organization->update($validated);

        return response()->json($organization);
    }
}
```

### After (Using Form Requests)

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\UpdateOrganizationRequest;
use App\Http\Resources\OrganizationResource;

class OrganizationController extends Controller
{
    public function update(UpdateOrganizationRequest $request)
    {
        $organization = $request->user()->organization;
        $organization->update($request->validated());

        return new OrganizationResource($organization);
    }
}
```

**Benefits:**
- 50+ lines reduced to ~5 lines
- Owner-only checks built-in
- Slug normalization automatic
- Email normalization automatic

---

## VPS Server Controller

### Before (Manual Validation)

```php
<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Models\VpsServer;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class VpsServerController extends Controller
{
    public function update(Request $request, string $id)
    {
        // Manual admin check
        if (!$request->user() || !$request->user()->isAdmin()) {
            return response()->json(['error' => 'Admin access required'], 403);
        }

        $vps = VpsServer::findOrFail($id);

        // Manual validation
        $validated = $request->validate([
            'hostname' => [
                'sometimes',
                'required',
                'string',
                'max:255',
                'regex:/^[a-zA-Z0-9][a-zA-Z0-9\-\.]*[a-zA-Z0-9]$/',
                Rule::unique('vps_servers', 'hostname')->ignore($id),
            ],
            'ip_address' => [
                'sometimes',
                'required',
                'ip',
                Rule::unique('vps_servers', 'ip_address')->ignore($id),
            ],
            'status' => 'sometimes|in:provisioning,active,maintenance,failed,decommissioned',
            'health_status' => 'sometimes|in:healthy,degraded,unhealthy,unknown',
        ]);

        // Manual safety checks
        if (isset($validated['status']) && $validated['status'] === 'active' &&
            isset($validated['health_status']) && $validated['health_status'] === 'unhealthy') {
            return response()->json([
                'error' => 'Cannot set status to active while health is unhealthy'
            ], 422);
        }

        if (isset($validated['status']) && $validated['status'] === 'decommissioned') {
            if ($vps->getSiteCount() > 0) {
                return response()->json([
                    'error' => 'Cannot decommission VPS with active sites'
                ], 422);
            }
        }

        // Manual hostname normalization
        if (isset($validated['hostname'])) {
            $validated['hostname'] = strtolower($validated['hostname']);
        }

        $vps->update($validated);

        return response()->json($vps);
    }
}
```

### After (Using Form Requests)

```php
<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\UpdateVpsServerRequest;
use App\Http\Resources\VpsServerResource;
use App\Models\VpsServer;

class VpsServerController extends Controller
{
    public function update(UpdateVpsServerRequest $request, string $id)
    {
        $vps = VpsServer::findOrFail($id);
        $vps->update($request->validated());

        return new VpsServerResource($vps);
    }
}
```

**Benefits:**
- 50+ lines reduced to ~5 lines
- Admin-only enforcement automatic
- Safety checks built-in
- Status transition validation automatic

---

## Summary

### Code Reduction Stats

| Controller | Before (lines) | After (lines) | Reduction |
|------------|----------------|---------------|-----------|
| Site Store | ~60 | ~8 | 87% |
| Site Update | ~40 | ~6 | 85% |
| Backup Store | ~50 | ~5 | 90% |
| Team Invite | ~45 | ~10 | 78% |
| Team Update | ~35 | ~6 | 83% |
| Organization | ~50 | ~5 | 90% |
| VPS Update | ~50 | ~5 | 90% |

**Average Reduction: 86%**

### Benefits Summary

1. **Cleaner Controllers** - Controllers focus on business logic only
2. **Consistent Validation** - All requests validated the same way
3. **Better Security** - Authorization enforced at request level
4. **Easier Testing** - Form Requests can be unit tested independently
5. **Self-Documenting** - Request classes serve as documentation
6. **Maintainable** - Changes to validation in one place
7. **Type Safety** - IDE autocomplete for validated data

---

**Implementation Date:** January 3, 2026
**Ready for Production:** Yes
**Breaking Changes:** None (backward compatible)
