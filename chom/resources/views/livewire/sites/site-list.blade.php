<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">Sites</h1>
            <p class="mt-1 text-sm text-gray-600">Manage your WordPress and HTML sites.</p>
        </div>
        <div class="mt-4 sm:mt-0">
            <x-button variant="primary" href="{{ route('sites.create') }}" icon="plus">
                New Site
            </x-button>
        </div>
    </div>

    <!-- Flash Messages -->
    @if(session('success'))
        <x-alert type="success" dismissible class="mb-4">
            {{ session('success') }}
        </x-alert>
    @endif

    @if(session('error'))
        <x-alert type="error" dismissible class="mb-4">
            {{ session('error') }}
        </x-alert>
    @endif

    <!-- Filters -->
    <x-card class="mb-6">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <!-- Search -->
            <div class="relative flex-1 max-w-md">
                <input type="text"
                       wire:model.live.debounce.300ms="search"
                       placeholder="Search by domain..."
                       class="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <x-icon name="magnifying-glass" size="5" class="text-gray-400" />
                </div>
            </div>

            <!-- Status Filter -->
            <x-form.select
                wire:model.live="statusFilter"
                :options="[
                    '' => 'All Status',
                    'active' => 'Active',
                    'disabled' => 'Disabled',
                    'creating' => 'Creating',
                    'failed' => 'Failed'
                ]"
                class="w-full sm:w-auto"
            />
        </div>
    </x-card>

    <!-- Sites Table -->
    <x-table>
        <x-slot:header>
            <tr>
                <x-table.th>Domain</x-table.th>
                <x-table.th>Type</x-table.th>
                <x-table.th>Status</x-table.th>
                <x-table.th>SSL</x-table.th>
                <x-table.th>Server</x-table.th>
                <x-table.th class="relative">
                    <span class="sr-only">Actions</span>
                </x-table.th>
            </tr>
        </x-slot:header>

        @forelse($sites as $site)
            <tr>
                <x-table.td>
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
                </x-table.td>

                <x-table.td>
                    <x-badge>{{ ucfirst($site->site_type) }}</x-badge>
                </x-table.td>

                <x-table.td>
                    @php
                        $statusVariants = [
                            'active' => 'success',
                            'disabled' => 'default',
                            'creating' => 'warning',
                            'failed' => 'danger',
                        ];
                    @endphp
                    <x-badge :variant="$statusVariants[$site->status] ?? 'default'">
                        {{ ucfirst($site->status) }}
                    </x-badge>
                </x-table.td>

                <x-table.td>
                    @if($site->ssl_enabled)
                        <span class="inline-flex items-center text-green-600">
                            <x-icon name="lock-closed" size="5" class="mr-1" />
                            <span class="text-sm">Secure</span>
                        </span>
                    @else
                        <span class="text-sm text-gray-500">Not enabled</span>
                    @endif
                </x-table.td>

                <x-table.td class="text-sm text-gray-500">
                    {{ $site->vpsServer?->hostname ?? 'N/A' }}
                </x-table.td>

                <x-table.td class="text-right">
                    <div class="flex items-center justify-end space-x-2">
                        @if($site->status === 'active' || $site->status === 'disabled')
                            <button wire:click="toggleSite('{{ $site->id }}')"
                                    class="text-gray-600 hover:text-gray-900">
                                @if($site->status === 'active')
                                    <x-icon name="pause-circle" size="5" />
                                @else
                                    <x-icon name="play-circle" size="5" />
                                @endif
                            </button>
                        @endif

                        <button wire:click="confirmDelete('{{ $site->id }}')"
                                class="text-red-600 hover:text-red-900">
                            <x-icon name="trash" size="5" />
                        </button>
                    </div>
                </x-table.td>
            </tr>
        @empty
            <tr>
                <td colspan="6">
                    <x-empty-state
                        icon="globe"
                        title="No sites"
                        description="Get started by creating a new site."
                    >
                        <x-button variant="primary" href="{{ route('sites.create') }}" icon="plus">
                            New Site
                        </x-button>
                    </x-empty-state>
                </td>
            </tr>
        @endforelse

        @if($sites->hasPages())
        <x-slot:pagination>
            {{ $sites->links() }}
        </x-slot:pagination>
        @endif
    </x-table>

    <!-- Delete Confirmation Modal -->
    @if($deletingSiteId)
        <x-modal :show="true" title="Delete Site" size="md">
            <p class="text-sm text-gray-500 mb-6">
                Are you sure you want to delete this site? This action cannot be undone and all data will be permanently removed.
            </p>

            <x-slot:footer>
                <div class="flex justify-end space-x-3">
                    <x-button variant="secondary" wire:click="cancelDelete">
                        Cancel
                    </x-button>
                    <x-button variant="danger" wire:click="deleteSite">
                        Delete
                    </x-button>
                </div>
            </x-slot:footer>
        </x-modal>
    @endif
</div>
