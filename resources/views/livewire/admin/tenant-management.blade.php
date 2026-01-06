<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">Tenant Management</h1>
            <p class="mt-1 text-sm text-gray-400">Manage all tenants and their subscriptions.</p>
        </div>
        <button wire:click="openCreateModal"
                class="mt-4 sm:mt-0 inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500">
            <svg class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Add Tenant
        </button>
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
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-5 mb-8">
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
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700 {{ ($stats['pending_approval'] ?? 0) > 0 ? 'ring-2 ring-yellow-500' : '' }}">
            <div class="p-5">
                <div class="text-sm font-medium text-gray-400">Pending Approval</div>
                <div class="mt-1 text-2xl font-semibold {{ ($stats['pending_approval'] ?? 0) > 0 ? 'text-yellow-400' : 'text-gray-400' }}">{{ $stats['pending_approval'] ?? 0 }}</div>
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
                        Approval
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
                        <td class="px-6 py-4 whitespace-nowrap">
                            @if($tenant->is_approved)
                                <div class="flex items-center">
                                    <svg class="h-5 w-5 text-green-400 mr-1" fill="currentColor" viewBox="0 0 20 20">
                                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                                    </svg>
                                    <span class="text-sm text-green-400">Approved</span>
                                </div>
                                @if($tenant->approved_at)
                                    <div class="text-xs text-gray-500">{{ $tenant->approved_at->format('M d, Y') }}</div>
                                @endif
                            @else
                                <div class="flex items-center">
                                    <svg class="h-5 w-5 text-yellow-400 mr-1" fill="currentColor" viewBox="0 0 20 20">
                                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
                                    </svg>
                                    <span class="text-sm text-yellow-400">Pending</span>
                                </div>
                            @endif
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
                                <button wire:click="openUserModal('{{ $tenant->id }}')"
                                        class="text-purple-400 hover:text-purple-300" title="Manage Users">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" />
                                    </svg>
                                </button>
                                <button wire:click="openEditModal('{{ $tenant->id }}')"
                                        class="text-yellow-400 hover:text-yellow-300" title="Edit">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                                    </svg>
                                </button>
                                @if($tenant->is_approved)
                                    <button wire:click="revokeApproval('{{ $tenant->id }}')"
                                            wire:confirm="Are you sure you want to revoke approval for this tenant? They will no longer be able to create sites."
                                            class="text-orange-400 hover:text-orange-300" title="Revoke Approval">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                                        </svg>
                                    </button>
                                @else
                                    <button wire:click="approveTenant('{{ $tenant->id }}')"
                                            class="text-green-400 hover:text-green-300" title="Approve Tenant">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                        </svg>
                                    </button>
                                @endif
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
                                <button wire:click="deleteTenant('{{ $tenant->id }}')"
                                        wire:confirm="Are you sure you want to delete this tenant? This action cannot be undone."
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
                        <td colspan="7" class="px-6 py-12 text-center">
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

                            <!-- Approval Status -->
                            <div>
                                <h4 class="text-sm font-medium text-gray-400 mb-2">Approval Status</h4>
                                <div class="bg-gray-700 rounded-lg p-4">
                                    @if($selectedTenant->is_approved)
                                        <div class="flex items-center mb-2">
                                            <svg class="h-5 w-5 text-green-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd" />
                                            </svg>
                                            <span class="text-sm text-green-400 font-medium">Approved</span>
                                        </div>
                                        <dl class="grid grid-cols-2 gap-4">
                                            <div>
                                                <dt class="text-xs text-gray-400">Approved At</dt>
                                                <dd class="text-sm text-white">{{ $selectedTenant->approved_at?->format('M d, Y H:i') ?? 'N/A' }}</dd>
                                            </div>
                                            <div>
                                                <dt class="text-xs text-gray-400">Approved By</dt>
                                                <dd class="text-sm text-white">{{ $selectedTenant->approver?->name ?? 'N/A' }}</dd>
                                            </div>
                                        </dl>
                                        <button wire:click="revokeApproval('{{ $selectedTenant->id }}')"
                                                wire:confirm="Are you sure you want to revoke approval?"
                                                class="mt-3 inline-flex items-center px-3 py-1.5 text-xs font-medium text-orange-400 bg-orange-400/10 hover:bg-orange-400/20 rounded-md">
                                            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                                            </svg>
                                            Revoke Approval
                                        </button>
                                    @else
                                        <div class="flex items-center mb-3">
                                            <svg class="h-5 w-5 text-yellow-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" />
                                            </svg>
                                            <span class="text-sm text-yellow-400 font-medium">Pending Approval</span>
                                        </div>
                                        <p class="text-xs text-gray-400 mb-3">This tenant cannot create sites until approved by an administrator.</p>
                                        <button wire:click="approveTenant('{{ $selectedTenant->id }}')"
                                                class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-green-400 bg-green-400/10 hover:bg-green-400/20 rounded-md">
                                            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                            </svg>
                                            Approve Tenant
                                        </button>
                                    @endif
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

    <!-- Create Modal -->
    @if($showCreateModal)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeCreateModal"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
                    <form wire:submit="createTenant">
                        <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                            <h3 class="text-lg font-medium text-white mb-4">Create New Tenant</h3>

                            @if($error)
                                <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                    <p class="text-sm text-red-200">{{ $error }}</p>
                                </div>
                            @endif

                            <div class="space-y-4">
                                <div>
                                    <label for="create_name" class="block text-sm font-medium text-gray-300">Tenant Name</label>
                                    <input type="text" wire:model="createFormData.name" id="create_name"
                                           placeholder="e.g., My Company"
                                           class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    @error('createFormData.name') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div>
                                    <label for="create_organization" class="block text-sm font-medium text-gray-300">Organization</label>
                                    <select wire:model="createFormData.organization_id" id="create_organization"
                                            class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                        <option value="">Select an organization...</option>
                                        @foreach($organizations as $org)
                                            <option value="{{ $org->id }}">{{ $org->name }}</option>
                                        @endforeach
                                    </select>
                                    @error('createFormData.organization_id') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div>
                                    <label for="create_tier" class="block text-sm font-medium text-gray-300">Tier</label>
                                    <select wire:model="createFormData.tier" id="create_tier"
                                            class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                        <option value="starter">Starter</option>
                                        <option value="pro">Pro</option>
                                        <option value="enterprise">Enterprise</option>
                                    </select>
                                    @error('createFormData.tier') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>
                            </div>
                        </div>

                        <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                            <button type="submit"
                                    class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-green-600 text-base font-medium text-white hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500 sm:ml-3 sm:w-auto sm:text-sm">
                                Create Tenant
                            </button>
                            <button type="button" wire:click="closeCreateModal"
                                    class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-700 text-base font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm">
                                Cancel
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif

    <!-- User Management Modal -->
    @if($showUserModal && $userModalTenant)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeUserModal"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-3xl sm:w-full">
                    <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6">
                        <div class="flex items-center justify-between mb-4">
                            <div>
                                <h3 class="text-lg font-medium text-white">Manage Users - {{ $userModalTenant->name }}</h3>
                                <p class="text-sm text-gray-400 mt-1">{{ $userModalTenant->organization->name }}</p>
                            </div>
                            <button wire:click="closeUserModal" class="text-gray-400 hover:text-gray-300">
                                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                                </svg>
                            </button>
                        </div>

                        @if($error)
                            <div class="mb-4 rounded-md bg-red-800/50 border border-red-700 p-4">
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

                        <div class="grid grid-cols-2 gap-6">
                            <!-- Assigned Users -->
                            <div>
                                <h4 class="text-sm font-medium text-gray-300 mb-3">Assigned Users ({{ $userModalTenant->users->count() }})</h4>
                                <div class="bg-gray-700 rounded-lg p-4 max-h-96 overflow-y-auto">
                                    @if($userModalTenant->users->count() > 0)
                                        <div class="space-y-2">
                                            @foreach($userModalTenant->users as $user)
                                                <div class="flex items-center justify-between bg-gray-800 rounded-lg p-3">
                                                    <div class="flex items-center">
                                                        <div class="h-8 w-8 rounded-full bg-gradient-to-br from-orange-400 to-orange-600 flex items-center justify-center mr-3">
                                                            <span class="text-white text-sm font-semibold">{{ strtoupper(substr($user->name, 0, 1)) }}</span>
                                                        </div>
                                                        <div>
                                                            <p class="text-sm font-medium text-white">{{ $user->name }}</p>
                                                            <p class="text-xs text-gray-400">{{ $user->email }}</p>
                                                        </div>
                                                    </div>
                                                    <div class="flex items-center gap-2">
                                                        <x-user-badge :role="$user->role" />
                                                        <button wire:click="removeUser('{{ $user->id }}')"
                                                                class="text-red-400 hover:text-red-300" title="Remove">
                                                            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                                                            </svg>
                                                        </button>
                                                    </div>
                                                </div>
                                            @endforeach
                                        </div>
                                    @else
                                        <div class="text-center py-8">
                                            <svg class="mx-auto h-12 w-12 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
                                            </svg>
                                            <p class="mt-2 text-sm text-gray-500">No users assigned</p>
                                        </div>
                                    @endif
                                </div>
                            </div>

                            <!-- Available Users -->
                            <div>
                                <h4 class="text-sm font-medium text-gray-300 mb-3">Available Users ({{ $organizationUsers->whereNotIn('id', $userModalTenant->users->pluck('id'))->count() }})</h4>
                                <div class="bg-gray-700 rounded-lg p-4 max-h-96 overflow-y-auto">
                                    @php
                                        $availableUsers = $organizationUsers->whereNotIn('id', $userModalTenant->users->pluck('id'));
                                    @endphp

                                    @if($availableUsers->count() > 0)
                                        <div class="space-y-2">
                                            @foreach($availableUsers as $user)
                                                <div class="flex items-center justify-between bg-gray-800 rounded-lg p-3">
                                                    <div class="flex items-center">
                                                        <div class="h-8 w-8 rounded-full bg-gradient-to-br from-blue-400 to-blue-600 flex items-center justify-center mr-3">
                                                            <span class="text-white text-sm font-semibold">{{ strtoupper(substr($user->name, 0, 1)) }}</span>
                                                        </div>
                                                        <div>
                                                            <p class="text-sm font-medium text-white">{{ $user->name }}</p>
                                                            <p class="text-xs text-gray-400">{{ $user->email }}</p>
                                                        </div>
                                                    </div>
                                                    <div class="flex items-center gap-2">
                                                        <x-user-badge :role="$user->role" />
                                                        <button wire:click="assignUser('{{ $user->id }}')"
                                                                class="text-green-400 hover:text-green-300" title="Assign">
                                                            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
                                                            </svg>
                                                        </button>
                                                    </div>
                                                </div>
                                            @endforeach
                                        </div>
                                    @else
                                        <div class="text-center py-8">
                                            <svg class="mx-auto h-12 w-12 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                                            </svg>
                                            <p class="mt-2 text-sm text-gray-500">All organization users are assigned</p>
                                        </div>
                                    @endif
                                </div>
                            </div>
                        </div>
                    </div>

                    <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                        <button wire:click="closeUserModal" type="button" class="w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-800 text-base font-medium text-gray-300 hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500 sm:w-auto sm:text-sm">
                            Done
                        </button>
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
