<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">VPS Management</h1>
            <p class="mt-1 text-sm text-gray-400">Manage all VPS servers across the platform.</p>
        </div>
        <div class="mt-4 sm:mt-0">
            <button wire:click="openAddForm"
                    class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                <svg class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
                Add VPS
            </button>
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

    <!-- Filters -->
    <div class="bg-gray-800 rounded-lg shadow border border-gray-700 p-4 mb-6">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-4">
            <!-- Search -->
            <div>
                <label for="search" class="block text-sm font-medium text-gray-400">Search</label>
                <input type="text"
                       wire:model.live.debounce.300ms="search"
                       id="search"
                       placeholder="Hostname or IP..."
                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
            </div>

            <!-- Status Filter -->
            <div>
                <label for="status" class="block text-sm font-medium text-gray-400">Status</label>
                <select wire:model.live="statusFilter"
                        id="status"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All Statuses</option>
                    <option value="provisioning">Provisioning</option>
                    <option value="active">Active</option>
                    <option value="maintenance">Maintenance</option>
                    <option value="failed">Failed</option>
                    <option value="decommissioned">Decommissioned</option>
                </select>
            </div>

            <!-- Health Filter -->
            <div>
                <label for="health" class="block text-sm font-medium text-gray-400">Health</label>
                <select wire:model.live="healthFilter"
                        id="health"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All Health</option>
                    <option value="healthy">Healthy</option>
                    <option value="degraded">Degraded</option>
                    <option value="unhealthy">Unhealthy</option>
                    <option value="unknown">Unknown</option>
                </select>
            </div>

            <!-- Provider Filter -->
            <div>
                <label for="provider" class="block text-sm font-medium text-gray-400">Provider</label>
                <select wire:model.live="providerFilter"
                        id="provider"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All Providers</option>
                    @foreach($providers as $provider)
                        <option value="{{ $provider }}">{{ ucfirst($provider) }}</option>
                    @endforeach
                </select>
            </div>
        </div>
    </div>

    <!-- VPS Table -->
    <div class="bg-gray-800 shadow rounded-lg border border-gray-700 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-700">
            <thead class="bg-gray-700">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Server
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Specs
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Status
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Health
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Sites
                    </th>
                    <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Actions
                    </th>
                </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
                @forelse($vpsServers as $vps)
                    <tr class="hover:bg-gray-700/50">
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div>
                                <div class="text-sm font-medium text-white">{{ $vps->hostname }}</div>
                                <div class="text-sm text-gray-400">{{ $vps->ip_address }}</div>
                                <div class="text-xs text-gray-500">{{ ucfirst($vps->provider) }}{{ $vps->region ? ' / ' . $vps->region : '' }}</div>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm text-gray-300">
                                {{ $vps->spec_cpu }} CPU, {{ number_format($vps->spec_memory_mb / 1024, 1) }} GB RAM
                            </div>
                            <div class="text-xs text-gray-500">{{ $vps->spec_disk_gb }} GB Disk</div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $statusColor = match($vps->status) {
                                    'active' => 'bg-green-100 text-green-800',
                                    'provisioning' => 'bg-blue-100 text-blue-800',
                                    'maintenance' => 'bg-yellow-100 text-yellow-800',
                                    'failed' => 'bg-red-100 text-red-800',
                                    'decommissioned' => 'bg-gray-100 text-gray-800',
                                    default => 'bg-gray-100 text-gray-800',
                                };
                            @endphp
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusColor }}">
                                {{ ucfirst($vps->status) }}
                            </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $healthColor = match($vps->health_status) {
                                    'healthy' => 'text-green-400',
                                    'degraded' => 'text-yellow-400',
                                    'unhealthy' => 'text-red-400',
                                    default => 'text-gray-400',
                                };
                            @endphp
                            <div class="flex items-center">
                                <span class="h-2.5 w-2.5 rounded-full {{ str_replace('text-', 'bg-', $healthColor) }} mr-2"></span>
                                <div>
                                    @if(in_array($vps->health_status, ['unhealthy', 'degraded', 'unknown']))
                                        <button wire:click="viewHealth('{{ $vps->id }}')"
                                                class="text-sm {{ $healthColor }} hover:underline cursor-pointer text-left">
                                            {{ ucfirst($vps->health_status) }}
                                        </button>
                                        @if($vps->health_error)
                                            <div class="text-xs {{ $vps->health_status === 'unhealthy' ? 'text-red-300' : 'text-yellow-300' }} mt-1 max-w-xs truncate" title="{{ $vps->health_error }}">
                                                {{ Str::limit($vps->health_error, 50) }}
                                            </div>
                                        @endif
                                    @else
                                        <span class="text-sm {{ $healthColor }}">{{ ucfirst($vps->health_status) }}</span>
                                    @endif
                                </div>
                            </div>
                            @if($vps->last_health_check_at)
                                <div class="text-xs text-gray-500 mt-1">{{ $vps->last_health_check_at->diffForHumans() }}</div>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-300">
                            {{ $vps->sites_count }}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            <div class="flex justify-end space-x-2">
                                <button wire:click="viewHealth('{{ $vps->id }}')"
                                        class="text-blue-400 hover:text-blue-300" title="View Health">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
                                    </svg>
                                </button>
                                <button wire:click="testConnection('{{ $vps->id }}')"
                                        class="text-green-400 hover:text-green-300" title="Test Connection">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 017.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 011.06 0z" />
                                    </svg>
                                </button>
                                <button wire:click="openEditForm('{{ $vps->id }}')"
                                        class="text-yellow-400 hover:text-yellow-300" title="Edit">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                                    </svg>
                                </button>
                                <button wire:click="deleteVps('{{ $vps->id }}')"
                                        wire:confirm="Are you sure you want to delete this VPS? This action cannot be undone."
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
                            <svg class="mx-auto h-12 w-12 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.25 14.25h13.5m-13.5 0a3 3 0 01-3-3m3 3a3 3 0 100 6h13.5a3 3 0 100-6m-16.5-3a3 3 0 013-3h13.5a3 3 0 013 3m-19.5 0a4.5 4.5 0 01.9-2.7L5.737 5.1a3.375 3.375 0 012.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 01.9 2.7m0 0a3 3 0 01-3 3m0 3h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008zm-3 6h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008z" />
                            </svg>
                            <p class="mt-2 text-sm text-gray-400">No VPS servers found.</p>
                            <button wire:click="openAddForm" class="mt-4 text-blue-400 hover:text-blue-300">
                                Add your first VPS
                            </button>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        <!-- Pagination -->
        @if($vpsServers->hasPages())
            <div class="bg-gray-700 px-4 py-3 border-t border-gray-600">
                {{ $vpsServers->links() }}
            </div>
        @endif
    </div>

    <!-- Add/Edit VPS Modal -->
    @if($showForm)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeForm"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
                    <form wire:submit="saveVps">
                        <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                            <h3 class="text-lg font-medium text-white mb-4">
                                {{ $isEditing ? 'Edit VPS Server' : 'Add VPS Server' }}
                            </h3>

                            @if($error)
                                <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                    <p class="text-sm text-red-200">{{ $error }}</p>
                                </div>
                            @endif

                            <div class="space-y-4">
                                <div>
                                    <label for="hostname" class="block text-sm font-medium text-gray-300">Hostname</label>
                                    <input type="text" wire:model="formData.hostname" id="hostname"
                                           class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    @error('formData.hostname') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div>
                                    <label for="ip_address" class="block text-sm font-medium text-gray-300">IP Address</label>
                                    <input type="text" wire:model="formData.ip_address" id="ip_address"
                                           class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    @error('formData.ip_address') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div class="grid grid-cols-2 gap-4">
                                    <div>
                                        <label for="provider" class="block text-sm font-medium text-gray-300">Provider</label>
                                        <select wire:model="formData.provider" id="provider"
                                                class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                            <option value="custom">Custom</option>
                                            <option value="hetzner">Hetzner</option>
                                            <option value="digitalocean">DigitalOcean</option>
                                            <option value="vultr">Vultr</option>
                                            <option value="linode">Linode</option>
                                        </select>
                                    </div>

                                    <div>
                                        <label for="region" class="block text-sm font-medium text-gray-300">Region</label>
                                        <input type="text" wire:model="formData.region" id="region" placeholder="e.g., us-east-1"
                                               class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    </div>
                                </div>

                                <div class="grid grid-cols-3 gap-4">
                                    <div>
                                        <label for="spec_cpu" class="block text-sm font-medium text-gray-300">CPU Cores</label>
                                        <input type="number" wire:model="formData.spec_cpu" id="spec_cpu" min="1"
                                               class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    </div>

                                    <div>
                                        <label for="spec_memory_mb" class="block text-sm font-medium text-gray-300">RAM (MB)</label>
                                        <input type="number" wire:model="formData.spec_memory_mb" id="spec_memory_mb" min="512" step="512"
                                               class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    </div>

                                    <div>
                                        <label for="spec_disk_gb" class="block text-sm font-medium text-gray-300">Disk (GB)</label>
                                        <input type="number" wire:model="formData.spec_disk_gb" id="spec_disk_gb" min="10"
                                               class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    </div>
                                </div>

                                <div>
                                    <label for="allocation_type" class="block text-sm font-medium text-gray-300">Allocation Type</label>
                                    <select wire:model="formData.allocation_type" id="allocation_type"
                                            class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                        <option value="shared">Shared (multiple tenants)</option>
                                        <option value="dedicated">Dedicated (single tenant)</option>
                                    </select>
                                </div>
                            </div>
                        </div>

                        <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                            <button type="submit"
                                    class="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm">
                                {{ $isEditing ? 'Update' : 'Create' }}
                            </button>
                            <button type="button" wire:click="closeForm"
                                    class="mt-3 w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-700 text-base font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm">
                                Cancel
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif

    <!-- Health Details Modal -->
    @if($showHealthModal)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeHealthModal"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-2xl sm:w-full">
                    <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6">
                        <div class="flex justify-between items-start mb-4">
                            <h3 class="text-lg font-medium text-white">VPS Health Details</h3>
                            <button wire:click="closeHealthModal" class="text-gray-400 hover:text-white">
                                <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                                </svg>
                            </button>
                        </div>

                        @if($isLoadingHealth)
                            <div class="flex justify-center py-12">
                                <svg class="animate-spin h-8 w-8 text-blue-500" fill="none" viewBox="0 0 24 24">
                                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                                </svg>
                            </div>
                        @elseif(!empty($vpsHealthData['error']))
                            <div class="bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                <div class="flex items-start">
                                    <svg class="h-5 w-5 text-red-400 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
                                    </svg>
                                    <div class="flex-1">
                                        <h4 class="text-sm font-medium text-red-200 mb-1">Connection Error</h4>
                                        <p class="text-sm text-red-200 whitespace-pre-wrap">{{ $vpsHealthData['error'] }}</p>
                                    </div>
                                </div>
                            </div>
                        @else
                            @if(isset($vpsHealthData['vps']))
                                <div class="mb-6">
                                    <p class="text-lg font-medium text-white">{{ $vpsHealthData['vps']->hostname }}</p>
                                    <p class="text-sm text-gray-400">{{ $vpsHealthData['vps']->ip_address }}</p>

                                    @if($vpsHealthData['vps']->health_error)
                                        <div class="mt-4 bg-red-900/30 border border-red-500/50 rounded-lg p-3">
                                            <div class="flex items-start">
                                                <svg class="h-5 w-5 text-red-400 mr-2 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
                                                </svg>
                                                <div>
                                                    <p class="text-xs font-medium text-red-300">Last Error</p>
                                                    <p class="text-xs text-red-200 mt-1">{{ $vpsHealthData['vps']->health_error }}</p>
                                                </div>
                                            </div>
                                        </div>
                                    @endif
                                </div>
                            @endif

                            @if(isset($vpsHealthData['health']))
                                <div class="grid grid-cols-2 gap-4 mb-6">
                                    <div class="bg-gray-700 rounded-lg p-4">
                                        <div class="text-sm text-gray-400">Status</div>
                                        <div class="text-xl font-semibold text-white capitalize">{{ $vpsHealthData['health']['status'] ?? 'Unknown' }}</div>
                                    </div>
                                    @if(isset($vpsHealthData['dashboard']))
                                        <div class="bg-gray-700 rounded-lg p-4">
                                            <div class="text-sm text-gray-400">Uptime</div>
                                            <div class="text-xl font-semibold text-white">{{ $vpsHealthData['dashboard']['uptime'] ?? 'N/A' }}</div>
                                        </div>
                                    @endif
                                </div>

                                @if(isset($vpsHealthData['dashboard']))
                                    <div class="grid grid-cols-3 gap-4">
                                        <div class="bg-gray-700 rounded-lg p-4">
                                            <div class="text-sm text-gray-400">CPU</div>
                                            <div class="text-xl font-semibold text-white">{{ $vpsHealthData['dashboard']['cpu_percent'] ?? 'N/A' }}%</div>
                                        </div>
                                        <div class="bg-gray-700 rounded-lg p-4">
                                            <div class="text-sm text-gray-400">Memory</div>
                                            <div class="text-xl font-semibold text-white">{{ $vpsHealthData['dashboard']['memory_percent'] ?? 'N/A' }}%</div>
                                        </div>
                                        <div class="bg-gray-700 rounded-lg p-4">
                                            <div class="text-sm text-gray-400">Disk</div>
                                            <div class="text-xl font-semibold text-white">{{ $vpsHealthData['dashboard']['disk_percent'] ?? 'N/A' }}%</div>
                                        </div>
                                    </div>
                                @endif
                            @else
                                <p class="text-gray-400 text-center py-8">No health data available.</p>
                            @endif
                        @endif
                    </div>

                    <div class="bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                        <button type="button" wire:click="closeHealthModal"
                                class="w-full inline-flex justify-center rounded-md border border-gray-600 shadow-sm px-4 py-2 bg-gray-700 text-base font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 sm:w-auto sm:text-sm">
                            Close
                        </button>
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
