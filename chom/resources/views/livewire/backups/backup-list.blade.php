<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">Backups</h1>
            <p class="mt-1 text-sm text-gray-600">Manage backups for all your sites.</p>
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

    <!-- Stats -->
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-3 mb-6">
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Total Backups</dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900">{{ $backups->total() }}</dd>
            </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Total Size</dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900">
                    {{ number_format($totalSize / (1024 * 1024 * 1024), 2) }} GB
                </dd>
            </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Sites with Backups</dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900">{{ $sites->count() }}</dd>
            </div>
        </div>
    </div>

    <!-- Filters -->
    <div class="bg-white shadow rounded-lg mb-6">
        <div class="px-4 py-4 sm:px-6 flex flex-col sm:flex-row sm:items-center gap-4">
            <!-- Site Filter -->
            <div class="flex-1">
                <select wire:model.live="siteFilter"
                        class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                    <option value="">All Sites</option>
                    @foreach($sites as $site)
                        <option value="{{ $site->id }}">{{ $site->domain }}</option>
                    @endforeach
                </select>
            </div>

            <!-- Type Filter -->
            <div>
                <select wire:model.live="typeFilter"
                        class="border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                    <option value="">All Types</option>
                    <option value="full">Full</option>
                    <option value="files">Files Only</option>
                    <option value="database">Database Only</option>
                </select>
            </div>

            <!-- Create Backup Dropdown -->
            <div class="relative" x-data="{ open: false }">
                <button @click="open = !open"
                        class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                    <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                    </svg>
                    Create Backup
                </button>

                <div x-show="open"
                     @click.away="open = false"
                     x-transition
                     class="absolute right-0 mt-2 w-56 bg-white rounded-md shadow-lg z-10 border">
                    <div class="py-1">
                        @foreach($sites as $site)
                            <button wire:click="showCreateModal('{{ $site->id }}')"
                                    @click="open = false"
                                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                                {{ $site->domain }}
                            </button>
                        @endforeach
                        @if($sites->isEmpty())
                            <span class="block px-4 py-2 text-sm text-gray-500">No sites available</span>
                        @endif
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Backups Table -->
    <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Site
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Type
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Size
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Created
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Expires
                    </th>
                    <th scope="col" class="relative px-6 py-3">
                        <span class="sr-only">Actions</span>
                    </th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                @forelse($backups as $backup)
                    <tr class="{{ $backup->isExpired() ? 'bg-red-50' : '' }}">
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="text-sm font-medium text-gray-900">
                                {{ $backup->site?->domain ?? 'Deleted Site' }}
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $typeColors = [
                                    'full' => 'bg-blue-100 text-blue-800',
                                    'files' => 'bg-green-100 text-green-800',
                                    'database' => 'bg-purple-100 text-purple-800',
                                ];
                            @endphp
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $typeColors[$backup->backup_type] ?? 'bg-gray-100 text-gray-800' }}">
                                {{ ucfirst($backup->backup_type) }}
                            </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                            {{ $backup->getSizeFormatted() }}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                            {{ $backup->created_at->format('M d, Y H:i') }}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @if($backup->expires_at)
                                @if($backup->isExpired())
                                    <span class="text-sm text-red-600 font-medium">Expired</span>
                                @else
                                    <span class="text-sm text-gray-500">{{ $backup->expires_at->diffForHumans() }}</span>
                                @endif
                            @else
                                <span class="text-sm text-gray-400">Never</span>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            <div class="flex items-center justify-end space-x-2">
                                <button wire:click="confirmRestore('{{ $backup->id }}')"
                                        class="text-blue-600 hover:text-blue-900"
                                        title="Restore">
                                    <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                                    </svg>
                                </button>
                                <button wire:click="confirmDelete('{{ $backup->id }}')"
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
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 8h14M5 8a2 2 0 110-4h14a2 2 0 110 4M5 8v10a2 2 0 002 2h10a2 2 0 002-2V8m-9 4h4"/>
                            </svg>
                            <h3 class="mt-2 text-sm font-medium text-gray-900">No backups</h3>
                            <p class="mt-1 text-sm text-gray-500">Get started by creating a backup for one of your sites.</p>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        @if($backups->hasPages())
            <div class="px-6 py-4 border-t border-gray-200">
                {{ $backups->links() }}
            </div>
        @endif
    </div>

    <!-- Create Backup Modal -->
    @if($creatingBackupForSite)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Create Backup</h3>

                <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 mb-2">Backup Type</label>
                    <div class="space-y-2">
                        <label class="flex items-center">
                            <input type="radio" wire:model="backupType" value="full" class="h-4 w-4 text-blue-600">
                            <span class="ml-2 text-sm text-gray-700">Full Backup (Files + Database)</span>
                        </label>
                        <label class="flex items-center">
                            <input type="radio" wire:model="backupType" value="files" class="h-4 w-4 text-blue-600">
                            <span class="ml-2 text-sm text-gray-700">Files Only</span>
                        </label>
                        <label class="flex items-center">
                            <input type="radio" wire:model="backupType" value="database" class="h-4 w-4 text-blue-600">
                            <span class="ml-2 text-sm text-gray-700">Database Only</span>
                        </label>
                    </div>
                </div>

                <div class="flex justify-end space-x-3">
                    <button wire:click="closeCreateModal"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Cancel
                    </button>
                    <button wire:click="createBackup"
                            class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                        Create Backup
                    </button>
                </div>
            </div>
        </div>
    @endif

    <!-- Restore Confirmation Modal -->
    @if($restoringBackupId)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Restore Backup</h3>
                <p class="text-sm text-gray-500 mb-2">
                    Are you sure you want to restore this backup? This will:
                </p>
                <ul class="text-sm text-gray-500 mb-6 list-disc list-inside">
                    <li>Overwrite current site files</li>
                    <li>Replace the database with backup data</li>
                    <li>This action cannot be undone</li>
                </ul>
                <div class="flex justify-end space-x-3">
                    <button wire:click="cancelRestore"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Cancel
                    </button>
                    <button wire:click="restoreBackup"
                            class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-yellow-600 hover:bg-yellow-700">
                        Restore
                    </button>
                </div>
            </div>
        </div>
    @endif

    <!-- Delete Confirmation Modal -->
    @if($deletingBackupId)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Delete Backup</h3>
                <p class="text-sm text-gray-500 mb-6">
                    Are you sure you want to delete this backup? This action cannot be undone.
                </p>
                <div class="flex justify-end space-x-3">
                    <button wire:click="cancelDelete"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Cancel
                    </button>
                    <button wire:click="deleteBackup"
                            class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-red-600 hover:bg-red-700">
                        Delete
                    </button>
                </div>
            </div>
        </div>
    @endif
</div>
