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
    </div>
</div>
