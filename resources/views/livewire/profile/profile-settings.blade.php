<div>
    <!-- Header -->
    <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">
            @if($isViewingSelf)
                Profile Settings
            @else
                User Profile: {{ $viewingUser->name }}
            @endif
        </h1>
        <p class="mt-1 text-sm text-gray-600">
            @if($isViewingSelf)
                Manage your account settings and password.
            @else
                View and manage {{ $viewingUser->name }}'s profile information.
            @endif
        </p>
    </div>

    <!-- Flash Messages -->
    @if($success)
        <div class="mb-4 bg-green-50 border-l-4 border-green-400 p-4">
            <p class="text-sm text-green-700">{{ $success }}</p>
        </div>
    @endif

    @if($error)
        <div class="mb-4 bg-red-50 border-l-4 border-red-400 p-4">
            <p class="text-sm text-red-700">{{ $error }}</p>
        </div>
    @endif

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- Profile Information -->
        <div class="bg-white shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Profile Information</h3>
                <p class="text-sm text-gray-500 mb-6">Update your account's profile information and email address.</p>

                <form wire:submit="updateProfile" class="space-y-4">
                    <div>
                        <label for="name" class="block text-sm font-medium text-gray-700">Name</label>
                        <input type="text" id="name" wire:model="name"
                               class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                        @error('name') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div>
                        <label for="email" class="block text-sm font-medium text-gray-700">Email</label>
                        <input type="email" id="email" wire:model="email"
                               class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                        @error('email') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="flex justify-end">
                        <button type="submit"
                                class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                            Save Profile
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Update Password (Only for own profile) -->
        @if($isViewingSelf)
            <div class="bg-white shadow rounded-lg">
                <div class="px-4 py-5 sm:p-6">
                    <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Update Password</h3>
                    <p class="text-sm text-gray-500 mb-6">Ensure your account is using a strong password for security.</p>

                    <form wire:submit="updatePassword" class="space-y-4">
                    <div>
                        <label for="current_password" class="block text-sm font-medium text-gray-700">Current Password</label>
                        <input type="password" id="current_password" wire:model="current_password"
                               class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                        @error('current_password') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div>
                        <label for="new_password" class="block text-sm font-medium text-gray-700">New Password</label>
                        <input type="password" id="new_password" wire:model="new_password"
                               class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                        @error('new_password') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                        <p class="mt-1 text-xs text-gray-500">Password must be at least 8 characters with mixed case and numbers.</p>
                    </div>

                    <div>
                        <label for="new_password_confirmation" class="block text-sm font-medium text-gray-700">Confirm New Password</label>
                        <input type="password" id="new_password_confirmation" wire:model="new_password_confirmation"
                               class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                    </div>

                    <div class="flex justify-end">
                        <button type="submit"
                                class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                            Update Password
                        </button>
                    </div>
                </form>
            </div>
        </div>
        @endif

        <!-- Account Information (Read-only) -->
        <div class="bg-white shadow rounded-lg lg:col-span-2">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Account Information</h3>
                <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <div>
                        <dt class="text-sm font-medium text-gray-500">Organization</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ $viewingUser->organization?->name ?? 'N/A' }}</dd>
                    </div>
                    <div>
                        <dt class="text-sm font-medium text-gray-500">Role</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ ucfirst($viewingUser->role ?? 'Member') }}</dd>
                    </div>
                    <div>
                        <dt class="text-sm font-medium text-gray-500">Member Since</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ $viewingUser->created_at->format('F d, Y') }}</dd>
                    </div>
                    @if($viewingUser->isSuperAdmin())
                        <div>
                            <dt class="text-sm font-medium text-gray-500">Super Admin</dt>
                            <dd class="mt-1">
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-orange-100 text-orange-800">
                                    Yes
                                </span>
                            </dd>
                        </div>
                    @endif
                </dl>
            </div>
        </div>

        <!-- Role Management (Admin Only) -->
        @if($canEditRole && auth()->user()->isAdmin())
            <div class="bg-white shadow rounded-lg lg:col-span-2">
                <div class="px-4 py-5 sm:p-6">
                    <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Role Management</h3>
                    <p class="text-sm text-gray-500 mb-6">
                        Update the user's role within the organization. Role changes take effect immediately.
                    </p>

                    <!-- Role Success/Error Messages -->
                    @if($roleSuccess)
                        <div class="mb-4 bg-green-50 border-l-4 border-green-400 p-4">
                            <p class="text-sm text-green-700">{{ $roleSuccess }}</p>
                        </div>
                    @endif

                    @if($roleError)
                        <div class="mb-4 bg-red-50 border-l-4 border-red-400 p-4">
                            <p class="text-sm text-red-700">{{ $roleError }}</p>
                        </div>
                    @endif

                    <form wire:submit="updateRole" class="space-y-4">
                        <div>
                            <label for="role" class="block text-sm font-medium text-gray-700">User Role</label>
                            <select id="role" wire:model="role"
                                    class="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                                @foreach($availableRoles as $availableRole)
                                    <option value="{{ $availableRole }}">{{ ucfirst($availableRole) }}</option>
                                @endforeach
                            </select>
                            @error('role') <span class="text-sm text-red-600">{{ $message }}</span> @enderror

                            <!-- Role descriptions -->
                            <div class="mt-3 p-3 bg-gray-50 rounded-md">
                                <p class="text-xs text-gray-600 font-medium mb-2">Role Permissions:</p>
                                <ul class="text-xs text-gray-600 space-y-1">
                                    <li><strong>Owner:</strong> Full organization control, can manage billing and delete the organization</li>
                                    <li><strong>Admin:</strong> Manage users, sites, and settings (cannot manage billing)</li>
                                    <li><strong>Member:</strong> Create and manage their own sites</li>
                                    <li><strong>Viewer:</strong> Read-only access to sites and backups</li>
                                </ul>
                            </div>
                        </div>

                        <!-- Warning -->
                        <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4">
                            <div class="flex">
                                <svg class="h-5 w-5 text-yellow-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                </svg>
                                <div>
                                    <p class="text-sm text-yellow-700">
                                        <strong>Warning:</strong> Role changes take effect immediately. The user may gain or lose access to features based on their new role.
                                    </p>
                                </div>
                            </div>
                        </div>

                        <div class="flex justify-end">
                            <button type="submit"
                                    class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                                Update Role
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        @endif

        <!-- Access & Permissions -->
        <div class="bg-white shadow rounded-lg lg:col-span-2">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Access & Permissions</h3>
                <p class="text-sm text-gray-500 mb-6">
                    Tenants and sites {{ $isViewingSelf ? 'you have' : 'this user has' }} access to within the organization.
                </p>

                <!-- Summary Stats -->
                <div class="grid grid-cols-2 gap-4 mb-6">
                    <div class="bg-blue-50 rounded-lg p-4">
                        <div class="flex items-center">
                            <svg class="h-8 w-8 text-blue-600 mr-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/>
                            </svg>
                            <div>
                                <p class="text-2xl font-bold text-blue-900">{{ $userTenants->count() }}</p>
                                <p class="text-sm text-blue-700">{{ Str::plural('Tenant', $userTenants->count()) }}</p>
                            </div>
                        </div>
                    </div>

                    <div class="bg-green-50 rounded-lg p-4">
                        <div class="flex items-center">
                            <svg class="h-8 w-8 text-green-600 mr-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                            </svg>
                            <div>
                                <p class="text-2xl font-bold text-green-900">{{ $totalSites }}</p>
                                <p class="text-sm text-green-700">{{ Str::plural('Site', $totalSites) }}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Tenants List -->
                @if($userTenants->count() > 0)
                    <div class="space-y-4">
                        @foreach($userTenants as $tenant)
                            <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
                                <div class="flex items-center justify-between mb-3">
                                    <div class="flex items-center">
                                        <div class="h-10 w-10 rounded-lg bg-gradient-to-br from-blue-400 to-blue-600 flex items-center justify-center mr-3">
                                            <svg class="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/>
                                            </svg>
                                        </div>
                                        <div>
                                            <h4 class="text-base font-medium text-gray-900">{{ $tenant->name }}</h4>
                                            <p class="text-sm text-gray-500">{{ $tenant->slug }}</p>
                                        </div>
                                    </div>
                                    <div class="flex items-center gap-2">
                                        <x-tenant-badge :status="$tenant->status" :tier="$tenant->tier" />
                                    </div>
                                </div>

                                <!-- Sites under this tenant -->
                                @if($tenant->sites->count() > 0)
                                    <div class="mt-3 pt-3 border-t border-gray-200">
                                        <p class="text-xs font-medium text-gray-500 uppercase tracking-wide mb-2">Sites ({{ $tenant->sites->count() }})</p>
                                        <div class="space-y-2">
                                            @foreach($tenant->sites as $site)
                                                <div class="flex items-center justify-between text-sm bg-gray-50 rounded px-3 py-2">
                                                    <div class="flex items-center">
                                                        <svg class="h-4 w-4 text-gray-400 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                                                        </svg>
                                                        <span class="font-medium text-gray-900">{{ $site->domain }}</span>
                                                    </div>
                                                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium
                                                        @if($site->status === 'active') bg-green-100 text-green-800
                                                        @elseif($site->status === 'creating') bg-blue-100 text-blue-800
                                                        @elseif($site->status === 'failed') bg-red-100 text-red-800
                                                        @else bg-gray-100 text-gray-800
                                                        @endif">
                                                        {{ ucfirst($site->status) }}
                                                    </span>
                                                </div>
                                            @endforeach
                                        </div>
                                    </div>
                                @else
                                    <div class="mt-3 pt-3 border-t border-gray-200">
                                        <p class="text-sm text-gray-500 italic">No sites in this tenant</p>
                                    </div>
                                @endif
                            </div>
                        @endforeach
                    </div>
                @else
                    <div class="text-center py-8 bg-gray-50 rounded-lg">
                        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4"/>
                        </svg>
                        <p class="mt-2 text-sm text-gray-500">No tenants assigned</p>
                        @if(auth()->user()->isAdmin() && !$isViewingSelf)
                            <p class="mt-1 text-xs text-gray-400">Contact an administrator to grant access</p>
                        @endif
                    </div>
                @endif
            </div>
        </div>
    </div>
</div>
