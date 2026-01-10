<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">Organization Management</h1>
            <p class="mt-1 text-sm text-gray-400">Manage all organizations and their resources.</p>
        </div>
        <div class="mt-4 sm:mt-0">
            <button wire:click="openCreateModal"
                    class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                <svg class="-ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
                Create Organization
            </button>
        </div>
    </div>

    <!-- Flash Messages -->
    @if($success)
        <div class="mb-6 rounded-md bg-green-800/50 border border-green-700 p-4">
            <div class="flex">
                <svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
                </svg>
                <div class="ml-3">
                    <p class="text-sm font-medium text-green-300">{{ $success }}</p>
                </div>
            </div>
        </div>
    @endif

    @if($error)
        <div class="mb-6 rounded-md bg-red-800/50 border border-red-700 p-4">
            <div class="flex">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                </svg>
                <div class="ml-3">
                    <p class="text-sm font-medium text-red-300">{{ $error }}</p>
                </div>
            </div>
        </div>
    @endif

    <!-- Stats Cards -->
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-4 mb-8">
        <div class="bg-gray-800 border border-gray-700 rounded-lg shadow p-5">
            <div class="flex items-center">
                <div class="flex-shrink-0">
                    <svg class="h-8 w-8 text-gray-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 21h19.5m-18-18v18m10.5-18v18m6-13.5V21M6.75 6.75h.75m-.75 3h.75m-.75 3h.75m3-6h.75m-.75 3h.75m-.75 3h.75M6.75 21v-3.375c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21M3 3h12m-.75 4.5H21m-3.75 3.75h.008v.008h-.008v-.008zm0 3h.008v.008h-.008v-.008zm0 3h.008v.008h-.008v-.008z" />
                    </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                    <dl>
                        <dt class="text-sm font-medium text-gray-400 truncate">Total Organizations</dt>
                        <dd class="text-lg font-semibold text-white">{{ $stats['total'] }}</dd>
                    </dl>
                </div>
            </div>
        </div>
        <div class="bg-gray-800 border border-gray-700 rounded-lg shadow p-5">
            <div class="flex items-center">
                <div class="flex-shrink-0">
                    <svg class="h-8 w-8 text-green-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                    <dl>
                        <dt class="text-sm font-medium text-gray-400 truncate">Active</dt>
                        <dd class="text-lg font-semibold text-green-400">{{ $stats['active'] }}</dd>
                    </dl>
                </div>
            </div>
        </div>
        <div class="bg-gray-800 border border-gray-700 rounded-lg shadow p-5">
            <div class="flex items-center">
                <div class="flex-shrink-0">
                    <svg class="h-8 w-8 text-yellow-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M14.25 9v6m-4.5 0V9M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                    <dl>
                        <dt class="text-sm font-medium text-gray-400 truncate">Suspended</dt>
                        <dd class="text-lg font-semibold text-yellow-400">{{ $stats['suspended'] }}</dd>
                    </dl>
                </div>
            </div>
        </div>
        <div class="bg-gray-800 border border-gray-700 rounded-lg shadow p-5">
            <div class="flex items-center">
                <div class="flex-shrink-0">
                    <svg class="h-8 w-8 text-red-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                    </svg>
                </div>
                <div class="ml-5 w-0 flex-1">
                    <dl>
                        <dt class="text-sm font-medium text-gray-400 truncate">Cancelled</dt>
                        <dd class="text-lg font-semibold text-red-400">{{ $stats['cancelled'] }}</dd>
                    </dl>
                </div>
            </div>
        </div>
    </div>

    <!-- Filters -->
    <div class="bg-gray-800 rounded-lg shadow border border-gray-700 p-6 mb-6">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div class="sm:col-span-2">
                <label for="search" class="block text-sm font-medium text-gray-400">Search</label>
                <input type="text" wire:model.live.debounce.300ms="search" id="search"
                       placeholder="Organization name or email..."
                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
            </div>
            <div>
                <label for="status" class="block text-sm font-medium text-gray-400">Status</label>
                <select wire:model.live="statusFilter" id="status"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All</option>
                    <option value="active">Active</option>
                    <option value="suspended">Suspended</option>
                    <option value="cancelled">Cancelled</option>
                </select>
            </div>
        </div>
        <div class="mt-4 flex justify-end">
            <button wire:click="clearFilters" class="text-sm text-gray-400 hover:text-white">
                Clear filters
            </button>
        </div>
    </div>

    <!-- Organizations Table -->
    <div class="bg-gray-800 shadow rounded-lg border border-gray-700 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-700">
            <thead class="bg-gray-700">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Organization
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Status
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Users
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Tenants
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Subscription
                    </th>
                    <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Actions
                    </th>
                </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
                @forelse($organizations as $org)
                    <tr class="hover:bg-gray-700/50">
                        <td class="px-6 py-4">
                            <div>
                                <div class="text-sm font-medium text-white">{{ $org->name }}</div>
                                <div class="text-xs text-gray-500">{{ $org->billing_email }}</div>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <x-organization-badge :status="$org->status" />
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm text-gray-300">{{ $org->users_count }}</div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm text-gray-300">{{ $org->tenants_count }}</div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @if($org->subscription)
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                                    @if($org->subscription->stripe_status === 'active') bg-green-100 text-green-800
                                    @elseif($org->subscription->stripe_status === 'trialing') bg-blue-100 text-blue-800
                                    @else bg-gray-100 text-gray-800
                                    @endif">
                                    {{ ucfirst($org->subscription->stripe_status ?? 'None') }}
                                </span>
                            @else
                                <span class="text-sm text-gray-500">None</span>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            <div class="flex justify-end space-x-2">
                                <button wire:click="viewDetails('{{ $org->id }}')"
                                        class="text-blue-400 hover:text-blue-300" title="View Details">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z" />
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                </button>
                                <button wire:click="openEditModal('{{ $org->id }}')"
                                        class="text-yellow-400 hover:text-yellow-300" title="Edit">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                                    </svg>
                                </button>
                                @if($org->status === 'active')
                                    <button wire:click="suspendOrganization('{{ $org->id }}')"
                                            wire:confirm="Are you sure you want to suspend this organization? All tenants will be suspended."
                                            class="text-orange-400 hover:text-orange-300" title="Suspend">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M14.25 9v6m-4.5 0V9M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                        </svg>
                                    </button>
                                @elseif($org->status === 'suspended')
                                    <button wire:click="activateOrganization('{{ $org->id }}')"
                                            class="text-green-400 hover:text-green-300" title="Activate">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z" />
                                        </svg>
                                    </button>
                                @endif
                                <button wire:click="confirmDelete('{{ $org->id }}')"
                                        class="text-red-400 hover:text-red-300" title="Delete">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                                    </svg>
                                </button>
                            </div>
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="6" class="px-6 py-12 text-center">
                            <p class="text-sm text-gray-400">No organizations found.</p>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        @if($organizations->hasPages())
            <div class="bg-gray-700 px-4 py-3 border-t border-gray-600">
                {{ $organizations->links() }}
            </div>
        @endif
    </div>

    <!-- Create Modal -->
    @if($showCreateModal)
        <div class="fixed inset-0 z-50 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen px-4">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75" wire:click="closeCreateModal"></div>

                <div class="relative bg-gray-800 rounded-lg max-w-lg w-full border border-gray-700">
                    <form wire:submit="createOrganization">
                        <div class="px-6 py-4 border-b border-gray-700">
                            <h3 class="text-lg font-medium text-white">Create Organization</h3>
                        </div>

                        <div class="px-6 py-4 space-y-4">
                            @if($error)
                                <div class="rounded-md bg-red-800/50 border border-red-700 p-4">
                                    <div class="flex">
                                        <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                                        </svg>
                                        <div class="ml-3">
                                            <p class="text-sm font-medium text-red-300">{{ $error }}</p>
                                        </div>
                                    </div>
                                </div>
                            @endif

                            <div>
                                <label for="name" class="block text-sm font-medium text-gray-300">Organization Name</label>
                                <input type="text" wire:model="formData.name" id="name"
                                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500">
                                @error('formData.name') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                            </div>

                            <div>
                                <label for="billing_email" class="block text-sm font-medium text-gray-300">Billing Email</label>
                                <input type="email" wire:model="formData.billing_email" id="billing_email"
                                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500">
                                @error('formData.billing_email') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                            </div>
                        </div>

                        <div class="px-6 py-4 bg-gray-700 flex justify-end space-x-3">
                            <button type="button" wire:click="closeCreateModal"
                                    class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600">
                                Cancel
                            </button>
                            <button type="submit"
                                    class="px-4 py-2 bg-blue-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-blue-700">
                                Create
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif

    <!-- Edit Modal -->
    @if($showEditModal)
        <div class="fixed inset-0 z-50 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen px-4">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75" wire:click="closeEditModal"></div>

                <div class="relative bg-gray-800 rounded-lg max-w-lg w-full border border-gray-700">
                    <form wire:submit="saveOrganization">
                        <div class="px-6 py-4 border-b border-gray-700">
                            <h3 class="text-lg font-medium text-white">Edit Organization</h3>
                        </div>

                        <div class="px-6 py-4 space-y-4">
                            @if($error)
                                <div class="rounded-md bg-red-800/50 border border-red-700 p-4">
                                    <div class="flex">
                                        <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                                        </svg>
                                        <div class="ml-3">
                                            <p class="text-sm font-medium text-red-300">{{ $error }}</p>
                                        </div>
                                    </div>
                                </div>
                            @endif

                            <div>
                                <label for="edit_name" class="block text-sm font-medium text-gray-300">Organization Name</label>
                                <input type="text" wire:model="formData.name" id="edit_name"
                                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500">
                                @error('formData.name') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                            </div>

                            <div>
                                <label for="edit_billing_email" class="block text-sm font-medium text-gray-300">Billing Email</label>
                                <input type="email" wire:model="formData.billing_email" id="edit_billing_email"
                                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500">
                                @error('formData.billing_email') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                            </div>
                        </div>

                        <div class="px-6 py-4 bg-gray-700 flex justify-end space-x-3">
                            <button type="button" wire:click="closeEditModal"
                                    class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600">
                                Cancel
                            </button>
                            <button type="submit"
                                    class="px-4 py-2 bg-blue-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-blue-700">
                                Save
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif

    <!-- Details Modal -->
    @if($showDetailsModal && $viewingOrganization)
        <div class="fixed inset-0 z-50 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen px-4">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75" wire:click="closeDetailsModal"></div>

                <div class="relative bg-gray-800 rounded-lg max-w-4xl w-full border border-gray-700 max-h-[90vh] overflow-y-auto">
                    <div class="px-6 py-4 border-b border-gray-700 flex justify-between items-center sticky top-0 bg-gray-800 z-10">
                        <h3 class="text-lg font-medium text-white">{{ $viewingOrganization->name }}</h3>
                        <button wire:click="closeDetailsModal" class="text-gray-400 hover:text-white">
                            <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                            </svg>
                        </button>
                    </div>

                    <div class="px-6 py-4 space-y-6">
                        <!-- Organization Info -->
                        <div class="grid grid-cols-2 gap-4">
                            <div>
                                <p class="text-sm text-gray-400">Status</p>
                                <div class="mt-1">
                                    <x-organization-badge :status="$viewingOrganization->status" />
                                </div>
                            </div>
                            <div>
                                <p class="text-sm text-gray-400">Billing Email</p>
                                <p class="mt-1 text-sm text-white">{{ $viewingOrganization->billing_email }}</p>
                            </div>
                        </div>

                        <!-- Users -->
                        <div>
                            <h4 class="text-sm font-medium text-white mb-3">Users ({{ $viewingOrganization->users->count() }})</h4>
                            @if($viewingOrganization->users->count() > 0)
                                <div class="bg-gray-700 rounded-lg overflow-hidden">
                                    <table class="min-w-full divide-y divide-gray-600">
                                        <thead class="bg-gray-600">
                                            <tr>
                                                <th class="px-4 py-2 text-left text-xs font-medium text-gray-300">Name</th>
                                                <th class="px-4 py-2 text-left text-xs font-medium text-gray-300">Email</th>
                                                <th class="px-4 py-2 text-left text-xs font-medium text-gray-300">Role</th>
                                            </tr>
                                        </thead>
                                        <tbody class="divide-y divide-gray-600">
                                            @foreach($viewingOrganization->users as $user)
                                                <tr>
                                                    <td class="px-4 py-2 text-sm text-white">{{ $user->fullName() }}</td>
                                                    <td class="px-4 py-2 text-sm text-gray-300">{{ $user->email }}</td>
                                                    <td class="px-4 py-2">
                                                        <x-user-badge :role="$user->role" />
                                                    </td>
                                                </tr>
                                            @endforeach
                                        </tbody>
                                    </table>
                                </div>
                            @else
                                <p class="text-sm text-gray-400">No users</p>
                            @endif
                        </div>

                        <!-- Tenants -->
                        <div>
                            <h4 class="text-sm font-medium text-white mb-3">Tenants ({{ $viewingOrganization->tenants->count() }})</h4>
                            @if($viewingOrganization->tenants->count() > 0)
                                <div class="bg-gray-700 rounded-lg overflow-hidden">
                                    <table class="min-w-full divide-y divide-gray-600">
                                        <thead class="bg-gray-600">
                                            <tr>
                                                <th class="px-4 py-2 text-left text-xs font-medium text-gray-300">Name</th>
                                                <th class="px-4 py-2 text-left text-xs font-medium text-gray-300">Status & Tier</th>
                                            </tr>
                                        </thead>
                                        <tbody class="divide-y divide-gray-600">
                                            @foreach($viewingOrganization->tenants as $tenant)
                                                <tr>
                                                    <td class="px-4 py-2 text-sm text-white">{{ $tenant->name }}</td>
                                                    <td class="px-4 py-2">
                                                        <x-tenant-badge :status="$tenant->status" :tier="$tenant->tier" />
                                                    </td>
                                                </tr>
                                            @endforeach
                                        </tbody>
                                    </table>
                                </div>
                            @else
                                <p class="text-sm text-gray-400">No tenants</p>
                            @endif
                        </div>
                    </div>

                    <div class="px-6 py-4 bg-gray-700 flex justify-end">
                        <button wire:click="closeDetailsModal"
                                class="px-4 py-2 bg-gray-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-gray-500">
                            Close
                        </button>
                    </div>
                </div>
            </div>
        </div>
    @endif

    <!-- Delete Confirmation Modal -->
    @if($deletingOrgId)
        <div class="fixed inset-0 z-50 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen px-4">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75" wire:click="cancelDelete"></div>

                <div class="relative bg-gray-800 rounded-lg max-w-lg w-full border border-gray-700">
                    <div class="px-6 py-4">
                        <h3 class="text-lg font-medium text-white mb-4">Delete Organization</h3>

                        @if(count($deleteBlockers) > 0)
                            <div class="rounded-md bg-red-800/50 border border-red-700 p-4 mb-4">
                                <div class="flex">
                                    <svg class="h-5 w-5 text-red-400 flex-shrink-0" viewBox="0 0 20 20" fill="currentColor">
                                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                                    </svg>
                                    <div class="ml-3">
                                        <p class="text-sm font-medium text-red-300 mb-2">Cannot delete organization with:</p>
                                        <ul class="list-disc list-inside text-sm text-red-300 space-y-1">
                                            @foreach($deleteBlockers as $blocker)
                                                <li>{{ $blocker }}</li>
                                            @endforeach
                                        </ul>
                                    </div>
                                </div>
                            </div>
                            <p class="text-sm text-gray-300">Please remove all active resources before deleting this organization.</p>
                        @else
                            <p class="text-sm text-gray-300 mb-4">Are you sure you want to delete this organization? This action cannot be undone.</p>
                        @endif
                    </div>

                    <div class="px-6 py-4 bg-gray-700 flex justify-end space-x-3">
                        <button wire:click="cancelDelete"
                                class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600">
                            Cancel
                        </button>
                        @if(count($deleteBlockers) === 0)
                            <button wire:click="deleteOrganization"
                                    class="px-4 py-2 bg-red-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-red-700">
                                Delete
                            </button>
                        @endif
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
