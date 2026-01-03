# Team Collaboration Module

## Overview

The Team Collaboration module is a bounded context responsible for managing team members, invitations, roles, permissions, and organizational collaboration within the CHOM application.

## Responsibilities

- Team member invitation and onboarding
- Role and permission management
- Team member removal
- Ownership transfer
- Collaboration access control
- Team statistics and analytics

## Architecture

### Service Contracts

- `InvitationInterface` - Team invitation operations

### Services

- `TeamOrchestrator` - Orchestrates team operations (wraps TeamManagementService)
- `InvitationService` - Implements invitation operations

### Value Objects

- `TeamRole` - Encapsulates role information with hierarchy
- `Permission` - Encapsulates granular permissions

## Usage Examples

### Team Invitations

```php
use App\Modules\Team\Contracts\InvitationInterface;

$invitationService = app(InvitationInterface::class);

// Send invitation
$invitation = $invitationService->send(
    organizationId: $orgId,
    email: 'user@example.com',
    role: 'member',
    permissions: ['manage_sites', 'view_analytics']
);

// Accept invitation
$success = $invitationService->accept($token, $userId);

// Cancel invitation
$success = $invitationService->cancel($invitationId);

// Resend invitation
$success = $invitationService->resend($invitationId);

// Get pending invitations
$pending = $invitationService->getPending($organizationId);

// Check if valid
$valid = $invitationService->isValid($token);
```

### Role Management

```php
use App\Modules\Team\Services\TeamOrchestrator;
use App\Modules\Team\ValueObjects\TeamRole;

$orchestrator = app(TeamOrchestrator::class);

// Update member role
$newRole = TeamRole::admin();
$user = $orchestrator->updateMemberRole($userId, $newRole);

// Check role hierarchy
$ownerRole = TeamRole::owner();
$adminRole = TeamRole::admin();
$isHigher = $ownerRole->isHigherThan($adminRole); // true

// Check role type
$role = TeamRole::fromString('admin');
$hasAdmin = $role->hasAdminPrivileges(); // true
```

### Permission Management

```php
use App\Modules\Team\ValueObjects\Permission;

// Create individual permissions
$permissions = [
    Permission::manageSites(),
    Permission::manageBackups(),
    Permission::viewAnalytics(),
];

// Update member permissions
$user = $orchestrator->updateMemberPermissions($userId, $permissions);

// Create from strings
$permissions = Permission::createSet([
    'manage_sites',
    'manage_backups'
]);
```

### Team Operations

```php
// Remove member
$success = $orchestrator->removeMember($userId, $organizationId);

// Transfer ownership
$success = $orchestrator->transferOwnership(
    organizationId: $orgId,
    newOwnerId: $newOwnerId,
    currentOwnerId: $currentOwnerId
);

// Get team statistics
$stats = $orchestrator->getStatistics($organizationId);
// Returns:
// - total_members
// - owners/admins/members/viewers count
// - active_members
// - inactive_members
```

## Value Objects

### TeamRole

Provides type-safe role handling:

- Role validation
- Hierarchy comparison (higher/lower than)
- Role type checking (isOwner, isAdmin, hasAdminPrivileges)
- Predefined role factories

### Permission

Encapsulates granular permissions:

- Permission validation
- Type-safe permission creation
- Predefined permission factories
- Permission set creation

## Role Hierarchy

The module implements a role hierarchy:

1. Owner (Level 4) - Full control
2. Admin (Level 3) - Administrative access
3. Member (Level 2) - Standard access
4. Viewer (Level 1) - Read-only access

## Available Permissions

- `manage_sites` - Create, update, delete sites
- `manage_backups` - Create, restore backups
- `manage_billing` - Access billing and subscriptions
- `view_analytics` - View analytics and reports
- `manage_team` - Invite, remove team members

## Module Dependencies

This module depends on:

- `TeamManagementService` (existing service)
- User model and repository
- TeamInvitation model
- Mail system for invitations

## Integration with Existing Code

This module wraps the existing `TeamManagementService` to:

1. Provide a clean module interface
2. Add value objects for type safety
3. Implement extended invitation features
4. Add team statistics
5. Maintain backward compatibility

## Events

The module uses existing team events:

- `MemberInvited` - When invitation is sent
- `MemberJoined` - When invitation is accepted
- `MemberRemoved` - When member is removed
- `MemberRoleUpdated` - When role changes
- `OwnershipTransferred` - When ownership transfers

## Security Considerations

1. Role hierarchy is enforced (can't promote to higher role)
2. Last owner cannot be removed or demoted
3. Self-modification is prevented
4. All operations are logged for auditing
5. Invitation expiry enforced (7 days default)

## Testing

Test the module using:

```bash
php artisan test --filter=Team
```

## Future Enhancements

- Fine-grained resource-level permissions
- Custom role creation
- Permission groups/templates
- Team activity audit log
- Member activity analytics
- Bulk invitation management
- Role-based UI customization
