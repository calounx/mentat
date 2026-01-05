<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">Tenant Management</h1>
            <p class="mt-1 text-sm text-gray-400">Manage all tenants and their subscriptions.</p>
        </div>
    </div>

    <!-- Flash Messages -->
    @if($success)
        <div class="mb-4 bg-green-900/50 border-l-4 border-green-500 p-4 rounded">
            <p class="text-sm text-green-200">{{ $success }}</p>
        </div>
    @endif

    @if($error)
        <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
            <p class="text-sm text-red-200">{{ $error }}</p>
        </div>
    @endif

    <!-- Stats Cards -->
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-4 mb-8">
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="text-sm font-medium text-gray-400">Total Tenants</div>
                <div class="mt-1 text-2xl font-semibold text-white">{{ $stats['total'] }}</div>
            </div>
        </div>
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="text-sm font-medium text-gray-400">Active</div>
                <div class="mt-1 text-2xl font-semibold text-green-400">{{ $stats['active'] }}</div>
            </div>
        </div>
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="text-sm font-medium text-gray-400">Pro Tier</div>
                <div class="mt-1 text-2xl font-semibold text-purple-400">{{ $stats['by_tier']['pro'] ?? 0 }}</div>
            </div>
        </div>
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="text-sm font-medium text-gray-400">Enterprise</div>
                <div class="mt-1 text-2xl font-semibold text-orange-400">{{ $stats['by_tier']['enterprise'] ?? 0 }}</div>
            </div>
        </div>
    </div>

    <!-- Filters -->
    <div class="bg-gray-800 rounded-lg shadow border border-gray-700 p-4 mb-6">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <!-- Search -->
            <div>
                <label for="search" class="block text-sm font-medium text-gray-400">Search</label>
                <input type="text"
                       wire:model.live.debounce.300ms="search"
                       id="search"
                       placeholder="Tenant name or organization..."
                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
            </div>

            <!-- Tier Filter -->
            <div>
                <label for="tier" class="block text-sm font-medium text-gray-400">Tier</label>
                <select wire:model.live="tierFilter"
                        id="tier"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All Tiers</option>
                    <option value="starter">Starter</option>
                    <option value="pro">Pro</option>
                    <option value="enterprise">Enterprise</option>
                </select>
            </div>

            <!-- Status Filter -->
            <div>
                <label for="status" class="block text-sm font-medium text-gray-400">Status</label>
                <select wire:model.live="statusFilter"
                        id="status"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All Statuses</option>
                    <option value="active">Active</option>
                    <option value="suspended">Suspended</option>
                    <option value="cancelled">Cancelled</option>
                </select>
            </div>
        </div>
    </div>

    <!-- Tenants Table -->
    <div class="bg-gray-800 shadow rounded-lg border border-gray-700 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-700">
            <thead class="bg-gray-700">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Tenant
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Organization
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Tier
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Status
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Sites / VPS
                    </th>
                    <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Actions
                    </th>
                </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
                @forelse($tenants as $tenant)
                    <tr class="hover:bg-gray-700/50">
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div>
                                <div class="text-sm font-medium text-white">{{ $tenant->name }}</div>
                                <div class="text-xs text-gray-500">{{ $tenant->slug }}</div>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm text-gray-300">{{ $tenant->organization->name ?? 'N/A' }}</div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $tierColor = match($tenant->tier) {
                                    'starter' => 'bg-gray-100 text-gray-800',
                                    'pro' => 'bg-purple-100 text-purple-800',
                                    'enterprise' => 'bg-orange-100 text-orange-800',
                                    default => 'bg-gray-100 text-gray-800',
                                };
                            @endphp
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $tierColor }}">
                                {{ ucfirst($tenant->tier) }}
                            </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $statusColor = match($tenant->status) {
                                    'active' => 'text-green-400',
                                    'suspended' => 'text-yellow-400',
                                    'cancelled' => 'text-red-400',
                                    default => 'text-gray-400',
                                };
                            @endphp
                            <div class="flex items-center">
                                <span class="h-2 w-2 rounded-full {{ str_replace('text-', 'bg-', $statusColor) }} mr-2"></span>
                                <span class="text-sm {{ $statusColor }}">{{ ucfirst($tenant->status) }}</span>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300">
                            {{ $tenant->sites_count }} sites / {{ $tenant->vps_allocations_count }} VPS
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            <div class="flex justify-end space-x-2">
                                <button wire:click="viewDetails('{{ $tenant->id }}')"
                                        class="text-blue-400 hover:text-blue-300" title="View Details">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z" />
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                </button>
                                <button wire:click="openEditModal('{{ $tenant->id }}')"
                                        class="text-yellow-400 hover:text-yellow-300" title="Edit">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                                    </svg>
                                </button>
                                @if($tenant->status === 'active')
                                    <button wire:click="updateStatus('{{ $tenant->id }}', 'suspended')"
                                            wire:confirm="Are you sure you want to suspend this tenant?"
                                            class="text-orange-400 hover:text-orange-300" title="Suspend">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25v13.5m-7.5-13.5v13.5" />
                                        </svg>
                                    </button>
                                @else
                                    <button wire:click="updateStatus('{{ $tenant->id }}', 'active')"
                                            class="text-green-400 hover:text-green-300" title="Activate">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z" />
                                        </svg>
                                    </button>
                                @endif
                            </div>
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="6" class="px-6 py-12 text-center">
                            <svg class="mx-auto h-12 w-12 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 18.72a9.094 9.094 0 003.741-.479 3 3 0 00-4.682-2.72m.94 3.198l.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0112 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 016 18.719m12 0a5.971 5.971 0 00-.941-3.197m0 0A5.995 5.995 0 0012 12.75a5.995 5.995 0 00-5.058 2.772m0 0a3 3 0 00-4.681 2.72 8.986 8.986 0 003.74.477m.94-3.197a5.971 5.971 0 00-.94 3.197M15 6.75a3 3 0 11-6 0 3 3 0 016 0zm6 3a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0zm-13.5 0a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z" />
                            </svg>
                            <p class="mt-2 text-sm text-gray-400">No tenants found.</p>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        <!-- Pagination -->
        @if($tenants->hasPages())
            <div class="bg-gray-700 px-4 py-3 border-t border-gray-600">
                {{ $tenants->links() }}
            </div>
        @endif
    </div>

    <!-- Details Modal -->
    @if($showDetailsModal && $selectedTenant)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeDetailsModal"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-2xl sm:w-full">
                    <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6">
                        <div class="flex justify-between items-start mb-4">
                            <h3 class="text-lg font-medium text-white">Tenant Details</h3>
                            <button wire:click="closeDetailsModal" class="text-gray-400 hover:text-white">
                                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                                </svg>
                            </button>
                        </div>

                        <div class="space-y-6">
                            <!-- Basic Info -->
                            <div>
                                <h4 class="text-sm font-medium text-gray-400 mb-2">Basic Information</h4>
                                <div class="bg-gray-700 rounded-lg p-4">
                                    <dl class="grid grid-cols-2 gap-4">
                                        <div>
                                            <dt class="text-xs text-gray-400">Name</dt>
                                            <dd class="text-sm text-white">{{ $selectedTenant->name }}</dd>
                                        </div>
                                        <div>
                                            <dt class="text-xs text-gray-400">Slug</dt>
                                            <dd class="text-sm text-white">{{ $selectedTenant->slug }}</dd>
                                        </div>
                                        <div>
                                            <dt class="text-xs text-gray-400">Organization</dt>
                                            <dd class="text-sm text-white">{{ $selectedTenant->organization->name ?? 'N/A' }}</dd>
                                        </div>
                                        <div>
                                            <dt class="text-xs text-gray-400">Created</dt>
                                            <dd class="text-sm text-white">{{ $selectedTenant->created_at->format('M d, Y') }}</dd>
                                        </div>
                                    </dl>
                                </div>
                            </div>

                            <!-- Sites -->
                            <div>
                                <h4 class="text-sm font-medium text-gray-400 mb-2">Sites ({{ $selectedTenant->sites->count() }})</h4>
                                @if($selectedTenant->sites->count() > 0)
                                    <div class="bg-gray-700 rounded-lg divide-y divide-gray-600">
                                        @foreach($selectedTenant->sites->take(5) as $site)
                                            <div class="p-3 flex justify-between items-center">
                                                <div>
                                                    <div class="text-sm text-white">{{ $site->domain }}</div>
                                                    <div class="text-xs text-gray-400">{{ ucfirst($site->site_type) }} | {{ $site->php_version }}</div>
                                                </div>
                                                @php
                                                    $siteStatusColor = match($site->status) {
                                                        'active' => 'text-green-400',
                                                        'disabled' => 'text-yellow-400',
                                                        'failed' => 'text-red-400',
                                                        default => 'text-gray-400',
                                                    };
                                                @endphp
                                                <span class="text-xs {{ $siteStatusColor }}">{{ ucfirst($site->status) }}</span>
                                            </div>
                                        @endforeach
                                        @if($selectedTenant->sites->count() > 5)
                                            <div class="p-3 text-center text-xs text-gray-400">
                                                +{{ $selectedTenant->sites->count() - 5 }} more sites
                                            </div>
                                        @endif
                                    </div>
                                @else
                                    <p class="text-sm text-gray-400">No sites.</p>
                                @endif
                            </div>

                            <!-- VPS Allocations -->
                            <div>
                                <h4 class="text-sm font-medium text-gray-400 mb-2">VPS Allocations</h4>
                                @if($selectedTenant->vpsAllocations->count() > 0)
                                    <div class="bg-gray-700 rounded-lg divide-y divide-gray-600">
                                        @foreach($selectedTenant->vpsAllocations as $allocation)
                                            <div class="p-3">
                                                <div class="text-sm text-white">{{ $allocation->vps->hostname ?? 'Unknown' }}</div>
                                                <div class="text-xs text-gray-400">{{ $allocation->memory_mb_allocated ?? 0 }} MB allocated</div>
                                            </div>
                                        @endforeach
                                    </div>
                                @else
                                    <p class="text-sm text-gray-400">No VPS allocations.</p>
                                @endif
                            </div>
                        </div>
                    </div>

                    <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                        <button type="button" wire:click="closeDetailsModal"
                                class="w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-700 text-base font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 sm:w-auto sm:text-sm">
                            Close
                        </button>
                    </div>
                </div>
            </div>
        </div>
    @endif

    <!-- Edit Modal -->
    @if($showEditModal)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeEditModal"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
                    <form wire:submit="saveTenant">
                        <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                            <h3 class="text-lg font-medium text-white mb-4">Edit Tenant</h3>

                            @if($error)
                                <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                    <p class="text-sm text-red-200">{{ $error }}</p>
                                </div>
                            @endif

                            <div class="space-y-4">
                                <div>
                                    <label for="tier" class="block text-sm font-medium text-gray-300">Tier</label>
                                    <select wire:model="editFormData.tier" id="tier"
                                            class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                        <option value="starter">Starter</option>
                                        <option value="pro">Pro</option>
                                        <option value="enterprise">Enterprise</option>
                                    </select>
                                    @error('editFormData.tier') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div>
                                    <label for="status" class="block text-sm font-medium text-gray-300">Status</label>
                                    <select wire:model="editFormData.status" id="status"
                                            class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                        <option value="active">Active</option>
                                        <option value="suspended">Suspended</option>
                                        <option value="cancelled">Cancelled</option>
                                    </select>
                                    @error('editFormData.status') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div>
                                    <label for="metrics_retention_days" class="block text-sm font-medium text-gray-300">Metrics Retention (days)</label>
                                    <input type="number" wire:model="editFormData.metrics_retention_days" id="metrics_retention_days"
                                           min="1" max="365"
                                           class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    @error('editFormData.metrics_retention_days') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>
                            </div>
                        </div>

                        <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                            <button type="submit"
                                    class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm">
                                Save
                            </button>
                            <button type="button" wire:click="closeEditModal"
                                    class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-700 text-base font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm">
                                Cancel
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif
</div>
