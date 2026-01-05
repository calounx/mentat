<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">Site Overview</h1>
            <p class="mt-1 text-sm text-gray-400">View and manage all sites across all tenants.</p>
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
                <div class="text-sm font-medium text-gray-400">Total Sites</div>
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
                <div class="text-sm font-medium text-gray-400">SSL Enabled</div>
                <div class="mt-1 text-2xl font-semibold text-blue-400">{{ $stats['ssl_enabled'] }}</div>
            </div>
        </div>
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700 {{ $stats['ssl_expiring'] > 0 ? 'ring-2 ring-yellow-500' : '' }}">
            <div class="p-5">
                <div class="text-sm font-medium text-gray-400">SSL Expiring Soon</div>
                <div class="mt-1 text-2xl font-semibold {{ $stats['ssl_expiring'] > 0 ? 'text-yellow-400' : 'text-gray-400' }}">
                    {{ $stats['ssl_expiring'] }}
                </div>
            </div>
        </div>
    </div>

    <!-- Filters -->
    <div class="bg-gray-800 rounded-lg shadow border border-gray-700 p-4 mb-6">
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-6">
            <!-- Search -->
            <div class="sm:col-span-2">
                <label for="search" class="block text-sm font-medium text-gray-400">Search</label>
                <input type="text"
                       wire:model.live.debounce.300ms="search"
                       id="search"
                       placeholder="Domain or tenant..."
                       class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
            </div>

            <!-- Status Filter -->
            <div>
                <label for="status" class="block text-sm font-medium text-gray-400">Status</label>
                <select wire:model.live="statusFilter"
                        id="status"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All</option>
                    <option value="creating">Creating</option>
                    <option value="active">Active</option>
                    <option value="disabled">Disabled</option>
                    <option value="failed">Failed</option>
                    <option value="deleting">Deleting</option>
                </select>
            </div>

            <!-- Type Filter -->
            <div>
                <label for="type" class="block text-sm font-medium text-gray-400">Type</label>
                <select wire:model.live="typeFilter"
                        id="type"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All</option>
                    <option value="wordpress">WordPress</option>
                    <option value="laravel">Laravel</option>
                    <option value="html">HTML</option>
                </select>
            </div>

            <!-- VPS Filter -->
            <div>
                <label for="vps" class="block text-sm font-medium text-gray-400">VPS</label>
                <select wire:model.live="vpsFilter"
                        id="vps"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All</option>
                    @foreach($vpsServers as $vps)
                        <option value="{{ $vps->id }}">{{ $vps->hostname }}</option>
                    @endforeach
                </select>
            </div>

            <!-- Tenant Filter -->
            <div>
                <label for="tenant" class="block text-sm font-medium text-gray-400">Tenant</label>
                <select wire:model.live="tenantFilter"
                        id="tenant"
                        class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                    <option value="">All</option>
                    @foreach($tenants as $tenant)
                        <option value="{{ $tenant->id }}">{{ $tenant->name }}</option>
                    @endforeach
                </select>
            </div>
        </div>

        <!-- SSL Expiring Toggle & Clear -->
        <div class="mt-4 flex items-center justify-between">
            <label class="inline-flex items-center cursor-pointer">
                <input type="checkbox" wire:model.live="sslExpiringOnly" class="sr-only peer">
                <div class="relative w-11 h-6 bg-gray-600 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-yellow-800 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-yellow-500"></div>
                <span class="ms-3 text-sm font-medium text-gray-300">Show only sites with SSL expiring soon</span>
            </label>
            <button wire:click="clearFilters" class="text-sm text-gray-400 hover:text-white">
                Clear filters
            </button>
        </div>
    </div>

    <!-- Sites Table -->
    <div class="bg-gray-800 shadow rounded-lg border border-gray-700 overflow-hidden">
        <table class="min-w-full divide-y divide-gray-700">
            <thead class="bg-gray-700">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Site
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Tenant
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        VPS
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Status
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">
                        SSL
                    </th>
                    <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-300 uppercase tracking-wider">
                        Actions
                    </th>
                </tr>
            </thead>
            <tbody class="divide-y divide-gray-700">
                @forelse($sites as $site)
                    <tr class="hover:bg-gray-700/50">
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div>
                                <div class="text-sm font-medium text-white">
                                    <a href="{{ $site->getUrl() }}" target="_blank" class="hover:text-blue-400">
                                        {{ $site->domain }}
                                        <svg class="inline h-3 w-3 ml-1 text-gray-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 6H5.25A2.25 2.25 0 003 8.25v10.5A2.25 2.25 0 005.25 21h10.5A2.25 2.25 0 0018 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25" />
                                        </svg>
                                    </a>
                                </div>
                                <div class="text-xs text-gray-500">
                                    {{ ucfirst($site->site_type) }} | PHP {{ $site->php_version }}
                                </div>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm text-gray-300">{{ $site->tenant->name ?? 'N/A' }}</div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm text-gray-300">{{ $site->vpsServer->hostname ?? 'N/A' }}</div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $statusConfig = match($site->status) {
                                    'active' => ['color' => 'bg-green-100 text-green-800', 'label' => 'Active'],
                                    'disabled' => ['color' => 'bg-gray-100 text-gray-800', 'label' => 'Disabled'],
                                    'creating' => ['color' => 'bg-blue-100 text-blue-800', 'label' => 'Creating'],
                                    'failed' => ['color' => 'bg-red-100 text-red-800', 'label' => 'Failed'],
                                    'deleting' => ['color' => 'bg-orange-100 text-orange-800', 'label' => 'Deleting'],
                                    default => ['color' => 'bg-gray-100 text-gray-800', 'label' => ucfirst($site->status)],
                                };
                            @endphp
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusConfig['color'] }}">
                                {{ $statusConfig['label'] }}
                            </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @if($site->ssl_enabled)
                                @if($site->isSslExpired())
                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                                        Expired
                                    </span>
                                @elseif($site->isSslExpiringSoon())
                                    <div>
                                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                                            Expiring
                                        </span>
                                        <div class="text-xs text-yellow-400 mt-1">{{ $site->ssl_expires_at->diffForHumans() }}</div>
                                    </div>
                                @else
                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                        Valid
                                    </span>
                                @endif
                            @else
                                <span class="text-xs text-gray-500">Not enabled</span>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            <div class="flex justify-end space-x-2">
                                @if($site->status === 'active' || $site->status === 'disabled')
                                    <button wire:click="toggleSite('{{ $site->id }}')"
                                            class="{{ $site->status === 'active' ? 'text-orange-400 hover:text-orange-300' : 'text-green-400 hover:text-green-300' }}"
                                            title="{{ $site->status === 'active' ? 'Disable' : 'Enable' }}">
                                        @if($site->status === 'active')
                                            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25v13.5m-7.5-13.5v13.5" />
                                            </svg>
                                        @else
                                            <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                                <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 5.653c0-.856.917-1.398 1.667-.986l11.54 6.348a1.125 1.125 0 010 1.971l-11.54 6.347a1.125 1.125 0 01-1.667-.985V5.653z" />
                                            </svg>
                                        @endif
                                    </button>
                                @endif
                                @if($site->ssl_enabled && ($site->isSslExpiringSoon() || $site->isSslExpired()))
                                    <button wire:click="renewSSL('{{ $site->id }}')"
                                            class="text-blue-400 hover:text-blue-300"
                                            title="Renew SSL">
                                        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                            <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
                                        </svg>
                                    </button>
                                @endif
                                <button wire:click="openEditModal('{{ $site->id }}')"
                                        class="text-yellow-400 hover:text-yellow-300" title="Edit">
                                    <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                                    </svg>
                                </button>
                                <button wire:click="deleteSite('{{ $site->id }}')"
                                        wire:confirm="Are you sure you want to delete this site? This will also delete it from the VPS and cannot be undone."
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
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418" />
                            </svg>
                            <p class="mt-2 text-sm text-gray-400">No sites found.</p>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        <!-- Pagination -->
        @if($sites->hasPages())
            <div class="bg-gray-700 px-4 py-3 border-t border-gray-600">
                {{ $sites->links() }}
            </div>
        @endif
    </div>

    <!-- Edit Modal -->
    @if($showEditModal)
        <div class="fixed inset-0 z-50 overflow-y-auto" aria-labelledby="modal-title" role="dialog" aria-modal="true">
            <div class="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity" wire:click="closeEditModal"></div>

                <div class="inline-block align-bottom bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
                    <form wire:submit="saveSite">
                        <div class="bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                            <h3 class="text-lg font-medium text-white mb-4">Edit Site</h3>

                            @if($error)
                                <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                    <p class="text-sm text-red-200">{{ $error }}</p>
                                </div>
                            @endif

                            <div class="space-y-4">
                                <div>
                                    <label for="php_version" class="block text-sm font-medium text-gray-300">PHP Version</label>
                                    <select wire:model="editFormData.php_version" id="php_version"
                                            class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                        <option value="7.4">PHP 7.4</option>
                                        <option value="8.0">PHP 8.0</option>
                                        <option value="8.1">PHP 8.1</option>
                                        <option value="8.2">PHP 8.2</option>
                                        <option value="8.3">PHP 8.3</option>
                                    </select>
                                    @error('editFormData.php_version') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
                                </div>

                                <div>
                                    <label for="document_root" class="block text-sm font-medium text-gray-300">Document Root (optional)</label>
                                    <input type="text" wire:model="editFormData.document_root" id="document_root"
                                           placeholder="e.g., public"
                                           class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                    @error('editFormData.document_root') <span class="text-red-400 text-xs">{{ $message }}</span> @enderror
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
