<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">Sites</h1>
            <p class="mt-1 text-sm text-gray-600">Manage your WordPress and HTML sites.</p>
        </div>
        <div class="mt-4 sm:mt-0">
            <a href="{{ route('sites.create') }}"
               class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                </svg>
                New Site
            </a>
        </div>
    </div>

    <!-- Flash Messages -->
    @if(session('success'))
        <div class="mb-4 bg-green-50 border-l-4 border-green-400 p-4">
            <p class="text-sm text-green-700">{{ session('success') }}</p>
        </div>
    @endif

    @if(session('error'))
        <div class="mb-4 bg-red-50 border-l-4 border-red-400 p-4">
            <p class="text-sm text-red-700">{{ session('error') }}</p>
        </div>
    @endif

    <!-- Filters -->
    <div class="bg-white shadow rounded-lg mb-6">
        <div class="px-4 py-4 sm:px-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <!-- Search -->
            <div class="relative flex-1 max-w-md">
                <input type="text"
                       wire:model.live.debounce.300ms="search"
                       placeholder="Search by domain..."
                       class="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <svg class="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                    </svg>
                </div>
            </div>

            <!-- Status Filter -->
            <select wire:model.live="statusFilter"
                    class="border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                <option value="">All Status</option>
                <option value="active">Active</option>
                <option value="disabled">Disabled</option>
                <option value="creating">Creating</option>
                <option value="failed">Failed</option>
            </select>
        </div>
    </div>

    <!-- Sites Table -->
    <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Domain
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Type
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Status
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        SSL
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Server
                    </th>
                    <th scope="col" class="relative px-6 py-3">
                        <span class="sr-only">Actions</span>
                    </th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                @forelse($sites as $site)
                    <tr>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="flex items-center">
                                <div>
                                    <div class="text-sm font-medium text-gray-900">
                                        <a href="{{ $site->getUrl() }}" target="_blank" class="hover:text-blue-600">
                                            {{ $site->domain }}
                                        </a>
                                    </div>
                                    <div class="text-sm text-gray-500">
                                        PHP {{ $site->php_version }}
                                    </div>
                                </div>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                {{ ucfirst($site->site_type) }}
                            </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $statusColors = [
                                    'active' => 'bg-green-100 text-green-800',
                                    'disabled' => 'bg-gray-100 text-gray-800',
                                    'creating' => 'bg-yellow-100 text-yellow-800',
                                    'failed' => 'bg-red-100 text-red-800',
                                ];
                            @endphp
                            @if(in_array($site->status, ['creating', 'failed']))
                                <button wire:click="viewStatus('{{ $site->id }}')"
                                        class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusColors[$site->status] ?? 'bg-gray-100 text-gray-800' }} hover:opacity-80 cursor-pointer transition-opacity">
                                    {{ ucfirst($site->status) }}
                                </button>
                            @else
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusColors[$site->status] ?? 'bg-gray-100 text-gray-800' }}">
                                    {{ ucfirst($site->status) }}
                                </span>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @if($site->ssl_enabled)
                                @if($site->isSslExpired())
                                    <button wire:click="viewSSLStatus('{{ $site->id }}')"
                                            class="inline-flex items-center text-red-600 hover:text-red-800 cursor-pointer transition-colors">
                                        <svg class="h-5 w-5 mr-1" fill="currentColor" viewBox="0 0 20 20">
                                            <path fill-rule="evenodd" d="M10 1.944A11.954 11.954 0 012.166 5C2.056 5.649 2 6.319 2 7c0 5.225 3.34 9.67 8 11.317C14.66 16.67 18 12.225 18 7c0-.682-.057-1.35-.166-2.001A11.954 11.954 0 0110 1.944zM11 14a1 1 0 11-2 0 1 1 0 012 0zm0-7a1 1 0 10-2 0v3a1 1 0 102 0V7z" clip-rule="evenodd"/>
                                        </svg>
                                        <span class="text-sm font-medium">Expired</span>
                                    </button>
                                @elseif($site->isSslExpiringSoon())
                                    <button wire:click="viewSSLStatus('{{ $site->id }}')"
                                            class="inline-flex items-center text-yellow-600 hover:text-yellow-800 cursor-pointer transition-colors">
                                        <svg class="h-5 w-5 mr-1" fill="currentColor" viewBox="0 0 20 20">
                                            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                        </svg>
                                        <span class="text-sm font-medium">Expiring Soon</span>
                                    </button>
                                @else
                                    <span class="inline-flex items-center text-green-600">
                                        <svg class="h-5 w-5 mr-1" fill="currentColor" viewBox="0 0 20 20">
                                            <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"/>
                                        </svg>
                                        <span class="text-sm">Secure</span>
                                    </span>
                                @endif
                            @else
                                <span class="text-sm text-gray-500">Not enabled</span>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                            {{ $site->vpsServer?->hostname ?? 'N/A' }}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            <div class="flex items-center justify-end space-x-2">
                                @if($site->status === 'failed')
                                    <button wire:click="retrySite('{{ $site->id }}')"
                                            class="text-yellow-600 hover:text-yellow-900"
                                            title="Retry Provisioning">
                                        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                                        </svg>
                                    </button>
                                @endif
                                @if($site->status === 'active' || $site->status === 'disabled')
                                    <button wire:click="toggleSite('{{ $site->id }}')"
                                            class="text-gray-600 hover:text-gray-900"
                                            title="{{ $site->status === 'active' ? 'Disable' : 'Enable' }}">
                                        @if($site->status === 'active')
                                            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                            </svg>
                                        @else
                                            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                            </svg>
                                        @endif
                                    </button>
                                @endif

                                <button wire:click="openEditModal('{{ $site->id }}')"
                                        class="text-blue-600 hover:text-blue-900"
                                        title="Edit">
                                    <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
                                    </svg>
                                </button>

                                <button wire:click="confirmDelete('{{ $site->id }}')"
                                        class="text-red-600 hover:text-red-900"
                                        title="Delete">
                                    <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                                    </svg>
                                </button>
                            </div>
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="6" class="px-6 py-12 text-center">
                            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                            </svg>
                            <h3 class="mt-2 text-sm font-medium text-gray-900">No sites</h3>
                            <p class="mt-1 text-sm text-gray-500">Get started by creating a new site.</p>
                            <div class="mt-6">
                                <a href="{{ route('sites.create') }}"
                                   class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700">
                                    <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                                    </svg>
                                    New Site
                                </a>
                            </div>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        <!-- Pagination -->
        @if($sites->hasPages())
            <div class="px-6 py-4 border-t border-gray-200">
                {{ $sites->links() }}
            </div>
        @endif
    </div>

    <!-- Delete Confirmation Modal -->
    @if($deletingSiteId)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Delete Site</h3>
                <p class="text-sm text-gray-500 mb-6">
                    Are you sure you want to delete this site? This action cannot be undone and all data will be permanently removed.
                </p>
                <div class="flex justify-end space-x-3">
                    <button wire:click="cancelDelete"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Cancel
                    </button>
                    <button wire:click="deleteSite"
                            class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-red-600 hover:bg-red-700">
                        Delete
                    </button>
                </div>
            </div>
        </div>
    @endif

    <!-- Edit Site Modal -->
    @if($showEditModal)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Edit Site</h3>

                @if($editError)
                    <div class="mb-4 bg-red-50 border-l-4 border-red-400 p-3 rounded">
                        <p class="text-sm text-red-700">{{ $editError }}</p>
                    </div>
                @endif

                <form wire:submit="saveSite">
                    <div class="space-y-4">
                        <div>
                            <label for="edit_php_version" class="block text-sm font-medium text-gray-700">PHP Version</label>
                            <select wire:model="editForm.php_version" id="edit_php_version"
                                    class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                                <option value="7.4">PHP 7.4</option>
                                <option value="8.0">PHP 8.0</option>
                                <option value="8.1">PHP 8.1</option>
                                <option value="8.2">PHP 8.2</option>
                                <option value="8.3">PHP 8.3</option>
                            </select>
                            @error('editForm.php_version') <span class="text-red-500 text-xs">{{ $message }}</span> @enderror
                        </div>

                        <div>
                            <label for="edit_document_root" class="block text-sm font-medium text-gray-700">Document Root (optional)</label>
                            <input type="text" wire:model="editForm.document_root" id="edit_document_root"
                                   placeholder="e.g., public"
                                   class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm">
                            <p class="mt-1 text-xs text-gray-500">Leave empty for default web root</p>
                            @error('editForm.document_root') <span class="text-red-500 text-xs">{{ $message }}</span> @enderror
                        </div>
                    </div>

                    <div class="mt-6 flex justify-end space-x-3">
                        <button type="button" wire:click="closeEditModal"
                                class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                            Cancel
                        </button>
                        <button type="submit"
                                class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                            Save Changes
                        </button>
                    </div>
                </form>
            </div>
        </div>
    @endif

    <!-- Site Status Modal -->
    @if($showStatusModal && $viewingSite)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-2xl w-full mx-4 max-h-[80vh] overflow-y-auto">
                <div class="flex justify-between items-center mb-4">
                    <h3 class="text-lg font-medium text-gray-900">Site Status Details</h3>
                    <button wire:click="closeStatusModal" class="text-gray-400 hover:text-gray-500">
                        <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                    </button>
                </div>

                <div class="space-y-4">
                    <!-- Domain & Status -->
                    <div class="bg-gray-50 rounded-lg p-4">
                        <div class="flex items-center justify-between">
                            <div>
                                <h4 class="text-sm font-medium text-gray-700">Domain</h4>
                                <p class="text-base font-semibold text-gray-900 mt-1">{{ $viewingSite->domain }}</p>
                            </div>
                            <div class="text-right">
                                <h4 class="text-sm font-medium text-gray-700">Status</h4>
                                @php
                                    $statusColors = [
                                        'active' => 'bg-green-100 text-green-800',
                                        'disabled' => 'bg-gray-100 text-gray-800',
                                        'creating' => 'bg-yellow-100 text-yellow-800',
                                        'failed' => 'bg-red-100 text-red-800',
                                    ];
                                @endphp
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusColors[$viewingSite->status] ?? 'bg-gray-100 text-gray-800' }} mt-1">
                                    {{ ucfirst($viewingSite->status) }}
                                </span>
                            </div>
                        </div>
                    </div>

                    <!-- Status Information -->
                    @if($viewingSite->status === 'creating')
                        <div class="bg-blue-50 border-l-4 border-blue-400 p-4 rounded">
                            <div class="flex items-start">
                                <svg class="h-5 w-5 text-blue-400 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                                </svg>
                                <div class="flex-1">
                                    <h4 class="text-sm font-medium text-blue-800 mb-1">Site Provisioning in Progress</h4>
                                    <p class="text-sm text-blue-700">
                                        Your site is currently being provisioned. This process typically takes 2-5 minutes and includes:
                                    </p>
                                    <ul class="mt-2 text-sm text-blue-700 list-disc list-inside space-y-1">
                                        <li>Creating directory structure</li>
                                        <li>Configuring web server</li>
                                        <li>Setting up PHP-FPM</li>
                                        @if($viewingSite->site_type === 'wordpress')
                                            <li>Installing WordPress</li>
                                            <li>Configuring database</li>
                                        @endif
                                        <li>Applying security settings</li>
                                    </ul>
                                    <p class="mt-2 text-sm text-blue-700">The page will update automatically when provisioning is complete.</p>
                                </div>
                            </div>
                        </div>
                    @elseif($viewingSite->status === 'failed')
                        <div class="bg-red-50 border-l-4 border-red-400 p-4 rounded">
                            <div class="flex items-start">
                                <svg class="h-5 w-5 text-red-400 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
                                </svg>
                                <div class="flex-1">
                                    <h4 class="text-sm font-medium text-red-800 mb-1">Provisioning Failed</h4>
                                    @if($viewingSite->failure_reason)
                                        <p class="text-sm text-red-700 whitespace-pre-wrap">{{ $viewingSite->failure_reason }}</p>
                                    @else
                                        <p class="text-sm text-red-700">
                                            Site provisioning failed. Please try again or contact support if the issue persists.
                                        </p>
                                    @endif
                                    <div class="mt-3">
                                        <button wire:click="retrySite('{{ $viewingSite->id }}')"
                                                class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500">
                                            <svg class="h-4 w-4 mr-1.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                                            </svg>
                                            Retry Provisioning
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    @endif

                    <!-- Additional Site Info -->
                    <div class="grid grid-cols-2 gap-4">
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">Site Type</h4>
                            <p class="text-sm text-gray-900 mt-1">{{ ucfirst($viewingSite->site_type) }}</p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">PHP Version</h4>
                            <p class="text-sm text-gray-900 mt-1">{{ $viewingSite->php_version }}</p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">Server</h4>
                            <p class="text-sm text-gray-900 mt-1">{{ $viewingSite->vpsServer?->hostname ?? 'N/A' }}</p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">Created</h4>
                            <p class="text-sm text-gray-900 mt-1">{{ $viewingSite->created_at->format('M d, Y H:i') }}</p>
                        </div>
                    </div>
                </div>

                <div class="mt-6 flex justify-end">
                    <button wire:click="closeStatusModal"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Close
                    </button>
                </div>
            </div>
        </div>
    @endif

    <!-- SSL Status Modal -->
    @if($showSSLModal && $viewingSSLSite)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-2xl w-full mx-4">
                <div class="flex justify-between items-center mb-4">
                    <h3 class="text-lg font-medium text-gray-900">SSL Certificate Status</h3>
                    <button wire:click="closeSSLModal" class="text-gray-400 hover:text-gray-500">
                        <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                    </button>
                </div>

                <div class="space-y-4">
                    <!-- Domain & SSL Status -->
                    <div class="bg-gray-50 rounded-lg p-4">
                        <div class="flex items-center justify-between">
                            <div>
                                <h4 class="text-sm font-medium text-gray-700">Domain</h4>
                                <p class="text-base font-semibold text-gray-900 mt-1">{{ $viewingSSLSite->domain }}</p>
                            </div>
                            <div class="text-right">
                                <h4 class="text-sm font-medium text-gray-700">SSL Status</h4>
                                @if($viewingSSLSite->isSslExpired())
                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800 mt-1">
                                        Expired
                                    </span>
                                @elseif($viewingSSLSite->isSslExpiringSoon())
                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800 mt-1">
                                        Expiring Soon
                                    </span>
                                @else
                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 mt-1">
                                        Valid
                                    </span>
                                @endif
                            </div>
                        </div>
                    </div>

                    <!-- SSL Warning/Error Message -->
                    @if($viewingSSLSite->isSslExpired())
                        <div class="bg-red-50 border-l-4 border-red-400 p-4 rounded">
                            <div class="flex items-start">
                                <svg class="h-5 w-5 text-red-400 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
                                </svg>
                                <div class="flex-1">
                                    <h4 class="text-sm font-medium text-red-800 mb-1">SSL Certificate Expired</h4>
                                    <p class="text-sm text-red-700">
                                        The SSL certificate for this domain expired on {{ $viewingSSLSite->ssl_expires_at->format('F j, Y') }}.
                                        Your site is now showing as "Not Secure" to visitors, which may impact trust and SEO rankings.
                                    </p>
                                    <p class="text-sm text-red-700 mt-2">
                                        <strong>Action Required:</strong> Renew the SSL certificate immediately to restore HTTPS protection.
                                    </p>
                                </div>
                            </div>
                        </div>
                    @elseif($viewingSSLSite->isSslExpiringSoon())
                        <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4 rounded">
                            <div class="flex items-start">
                                <svg class="h-5 w-5 text-yellow-400 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z" />
                                </svg>
                                <div class="flex-1">
                                    <h4 class="text-sm font-medium text-yellow-800 mb-1">SSL Certificate Expiring Soon</h4>
                                    <p class="text-sm text-yellow-700">
                                        The SSL certificate for this domain will expire on {{ $viewingSSLSite->ssl_expires_at->format('F j, Y') }}
                                        (in {{ $viewingSSLSite->ssl_expires_at->diffForHumans() }}).
                                    </p>
                                    <p class="text-sm text-yellow-700 mt-2">
                                        <strong>Recommended Action:</strong> SSL certificates typically auto-renew, but you should verify renewal is configured.
                                        Contact support if you need assistance.
                                    </p>
                                </div>
                            </div>
                        </div>
                    @else
                        <div class="bg-green-50 border-l-4 border-green-400 p-4 rounded">
                            <div class="flex items-start">
                                <svg class="h-5 w-5 text-green-400 mr-3 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                </svg>
                                <div class="flex-1">
                                    <h4 class="text-sm font-medium text-green-800 mb-1">SSL Certificate Valid</h4>
                                    <p class="text-sm text-green-700">
                                        Your SSL certificate is valid and properly configured. Your site is secure.
                                    </p>
                                </div>
                            </div>
                        </div>
                    @endif

                    <!-- SSL Details -->
                    <div class="grid grid-cols-2 gap-4">
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">SSL Enabled</h4>
                            <p class="text-sm text-gray-900 mt-1">{{ $viewingSSLSite->ssl_enabled ? 'Yes' : 'No' }}</p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">Expiration Date</h4>
                            <p class="text-sm text-gray-900 mt-1">
                                @if($viewingSSLSite->ssl_expires_at)
                                    {{ $viewingSSLSite->ssl_expires_at->format('M d, Y') }}
                                @else
                                    N/A
                                @endif
                            </p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">Days Until Expiration</h4>
                            <p class="text-sm text-gray-900 mt-1">
                                @if($viewingSSLSite->ssl_expires_at)
                                    @if($viewingSSLSite->isSslExpired())
                                        <span class="text-red-600 font-medium">Expired {{ $viewingSSLSite->ssl_expires_at->diffForHumans() }}</span>
                                    @else
                                        {{ $viewingSSLSite->ssl_expires_at->diffInDays(now()) }} days
                                    @endif
                                @else
                                    N/A
                                @endif
                            </p>
                        </div>
                        <div>
                            <h4 class="text-sm font-medium text-gray-700">Auto-Renewal</h4>
                            <p class="text-sm text-gray-900 mt-1">
                                <span class="inline-flex items-center text-green-600">
                                    <svg class="h-4 w-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                                    </svg>
                                    Enabled
                                </span>
                            </p>
                        </div>
                    </div>
                </div>

                <div class="mt-6 flex justify-end">
                    <button wire:click="closeSSLModal"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Close
                    </button>
                </div>
            </div>
        </div>
    @endif
</div>
