# Component Library Quick Reference

## Common Patterns

### Buttons
```blade
<!-- Primary action -->
<x-button variant="primary">Save</x-button>

<!-- Secondary action -->
<x-button variant="secondary">Cancel</x-button>

<!-- Danger action -->
<x-button variant="danger">Delete</x-button>

<!-- With icon -->
<x-button variant="primary" icon="plus">Create</x-button>

<!-- With loading state -->
<x-button :loading="$isSaving" loadingText="Saving...">Save</x-button>

<!-- As link -->
<x-button href="{{ route('home') }}">Go Home</x-button>
```

### Alerts
```blade
<!-- Success -->
<x-alert type="success">Operation successful!</x-alert>

<!-- Error -->
<x-alert type="error">Something went wrong.</x-alert>

<!-- Warning -->
<x-alert type="warning">Please be careful.</x-alert>

<!-- Info -->
<x-alert type="info">Here's some information.</x-alert>

<!-- Dismissible -->
<x-alert type="success" dismissible>You can close this.</x-alert>

<!-- Flash messages -->
@if(session('success'))
    <x-alert type="success" dismissible>{{ session('success') }}</x-alert>
@endif
```

### Forms
```blade
<!-- Text input -->
<x-form.input
    label="Email"
    name="email"
    type="email"
    placeholder="john@example.com"
    required
/>

<!-- Select dropdown -->
<x-form.select
    label="Status"
    name="status"
    :options="['active' => 'Active', 'inactive' => 'Inactive']"
    placeholder="Choose status"
/>

<!-- Textarea -->
<x-form.textarea
    label="Description"
    name="description"
    rows="5"
/>

<!-- Toggle switch -->
<x-form.toggle
    label="Enable Feature"
    description="Turn this feature on or off"
    name="feature_enabled"
    :checked="true"
/>
```

### Cards
```blade
<!-- Simple card -->
<x-card>
    Card content here
</x-card>

<!-- Card with header and footer -->
<x-card>
    <x-slot:header>
        <h3 class="text-lg font-medium">Title</h3>
    </x-slot:header>

    Content here

    <x-slot:footer>
        <x-button>Action</x-button>
    </x-slot:footer>
</x-card>
```

### Modals
```blade
<x-modal :show="$showModal" title="Confirmation" size="md">
    Are you sure?

    <x-slot:footer>
        <x-button variant="secondary">Cancel</x-button>
        <x-button variant="danger">Confirm</x-button>
    </x-slot:footer>
</x-modal>
```

### Tables
```blade
<x-table>
    <x-slot:header>
        <tr>
            <x-table.th>Name</x-table.th>
            <x-table.th>Email</x-table.th>
        </tr>
    </x-slot:header>

    @foreach($items as $item)
    <tr>
        <x-table.td>{{ $item->name }}</x-table.td>
        <x-table.td>{{ $item->email }}</x-table.td>
    </tr>
    @endforeach
</x-table>
```

### Stats Cards
```blade
<x-stats-card
    label="Total Users"
    :value="1234"
    icon="users"
    icon-color="text-blue-500"
/>
```

### Icons
```blade
<!-- Basic icon -->
<x-icon name="check-circle" />

<!-- With size and color -->
<x-icon name="trash" size="6" class="text-red-500" />

<!-- Common icons -->
<x-icon name="plus" />
<x-icon name="trash" />
<x-icon name="pencil" />
<x-icon name="check-circle" />
<x-icon name="x-circle" />
<x-icon name="globe" />
<x-icon name="lock-closed" />
```

### Badges
```blade
<x-badge variant="success">Active</x-badge>
<x-badge variant="danger">Error</x-badge>
<x-badge variant="warning">Pending</x-badge>
<x-badge variant="default">Draft</x-badge>
```

### Empty States
```blade
<x-empty-state
    icon="folder"
    title="No items found"
    description="Create your first item to get started"
>
    <x-button variant="primary" href="{{ route('items.create') }}">
        Create Item
    </x-button>
</x-empty-state>
```

### Page Headers
```blade
<x-page-header
    title="Sites"
    description="Manage your websites"
>
    <x-slot:actions>
        <x-button variant="primary" href="{{ route('sites.create') }}">
            New Site
        </x-button>
    </x-slot:actions>
</x-page-header>
```

### Loading States
```blade
<!-- Inline loader -->
<x-loading size="md" text="Loading..." />

<!-- With Livewire -->
<x-loading wire:loading wire:target="submit" />
```

### Notifications
```javascript
// Success
window.notifySuccess('Success!', 'Operation completed');

// Error
window.notifyError('Error!', 'Something went wrong');

// Warning
window.notifyWarning('Warning!', 'Please be careful');

// Info
window.notifyInfo('Info', 'Here is some information');

// Custom
window.notify('success', 'Title', 'Message', 5000);
```

## Component Props Reference

### Button
- `variant`: primary, secondary, danger, success, warning
- `size`: xs, sm, md, lg, xl
- `type`: button, submit, reset
- `loading`: boolean
- `icon`: icon name
- `href`: URL (creates link)

### Alert
- `type`: success, error, warning, info
- `dismissible`: boolean
- `icon`: boolean

### Badge
- `variant`: default, primary, success, danger, warning, info
- `size`: sm, md, lg
- `removable`: boolean

### Modal
- `show`: boolean
- `title`: string
- `size`: sm, md, lg, xl, full
- `closeable`: boolean

### Form Input
- `label`: string
- `name`: string (required)
- `type`: text, email, password, etc.
- `required`: boolean
- `help`: string
- `error`: string

### Stats Card
- `label`: string
- `value`: string/number
- `icon`: icon name
- `iconColor`: color class
- `trend`: string
- `trendDirection`: up, down

## Tailwind Utilities

Common classes used with components:

```blade
<!-- Spacing -->
class="mb-4"        <!-- margin-bottom -->
class="mt-6"        <!-- margin-top -->
class="px-4 py-2"   <!-- padding x and y -->

<!-- Layout -->
class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4"

<!-- Flex -->
class="flex items-center justify-between space-x-4"

<!-- Text -->
class="text-sm text-gray-600"
class="font-medium text-gray-900"

<!-- Width -->
class="w-full"
class="max-w-2xl"
```

## Example: Complete Form

```blade
<form wire:submit="save">
    <x-card>
        <x-slot:header>
            <h3 class="text-lg font-medium">Edit Profile</h3>
        </x-slot:header>

        <div class="space-y-6">
            <x-form.input
                label="Name"
                name="name"
                wire:model="name"
                required
            />

            <x-form.input
                label="Email"
                name="email"
                type="email"
                wire:model="email"
                required
            />

            <x-form.select
                label="Role"
                name="role"
                wire:model="role"
                :options="$roles"
            />

            <x-form.toggle
                label="Active"
                description="Enable or disable this user"
                name="active"
                :checked="$active"
            />
        </div>

        <x-slot:footer>
            <div class="flex justify-end space-x-3">
                <x-button variant="secondary" href="{{ route('users') }}">
                    Cancel
                </x-button>
                <x-button variant="primary" type="submit" :loading="$saving">
                    Save Changes
                </x-button>
            </div>
        </x-slot:footer>
    </x-card>
</form>
```

## Example: Complete Table

```blade
<x-page-header title="Users" description="Manage system users">
    <x-slot:actions>
        <x-button variant="primary" href="{{ route('users.create') }}" icon="plus">
            New User
        </x-button>
    </x-slot:actions>
</x-page-header>

@if(session('success'))
    <x-alert type="success" dismissible class="mb-4">
        {{ session('success') }}
    </x-alert>
@endif

<x-table>
    <x-slot:header>
        <tr>
            <x-table.th>Name</x-table.th>
            <x-table.th>Email</x-table.th>
            <x-table.th>Role</x-table.th>
            <x-table.th>Status</x-table.th>
            <x-table.th class="relative">Actions</x-table.th>
        </tr>
    </x-slot:header>

    @forelse($users as $user)
    <tr>
        <x-table.td>{{ $user->name }}</x-table.td>
        <x-table.td>{{ $user->email }}</x-table.td>
        <x-table.td>{{ $user->role }}</x-table.td>
        <x-table.td>
            <x-badge :variant="$user->active ? 'success' : 'default'">
                {{ $user->active ? 'Active' : 'Inactive' }}
            </x-badge>
        </x-table.td>
        <x-table.td class="text-right">
            <button class="text-blue-600 hover:text-blue-900 mr-3">
                <x-icon name="pencil" size="5" />
            </button>
            <button class="text-red-600 hover:text-red-900">
                <x-icon name="trash" size="5" />
            </button>
        </x-table.td>
    </tr>
    @empty
    <tr>
        <td colspan="5">
            <x-empty-state
                icon="users"
                title="No users found"
                description="Create your first user to get started"
            >
                <x-button variant="primary" href="{{ route('users.create') }}">
                    Create User
                </x-button>
            </x-empty-state>
        </td>
    </tr>
    @endforelse

    @if($users->hasPages())
    <x-slot:pagination>
        {{ $users->links() }}
    </x-slot:pagination>
    @endif
</x-table>
```

---

**Need help?** See COMPONENT-LIBRARY.md for full documentation.
