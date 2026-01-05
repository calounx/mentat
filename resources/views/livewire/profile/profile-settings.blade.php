<div>
    <!-- Header -->
    <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Profile Settings</h1>
        <p class="mt-1 text-sm text-gray-600">Manage your account settings and password.</p>
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

        <!-- Update Password -->
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

        <!-- Account Information (Read-only) -->
        <div class="bg-white shadow rounded-lg lg:col-span-2">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Account Information</h3>
                <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                    <div>
                        <dt class="text-sm font-medium text-gray-500">Organization</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ auth()->user()->organization?->name ?? 'N/A' }}</dd>
                    </div>
                    <div>
                        <dt class="text-sm font-medium text-gray-500">Role</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ ucfirst(auth()->user()->role ?? 'Member') }}</dd>
                    </div>
                    <div>
                        <dt class="text-sm font-medium text-gray-500">Member Since</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ auth()->user()->created_at->format('F d, Y') }}</dd>
                    </div>
                    @if(auth()->user()->isSuperAdmin())
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
    </div>
</div>
