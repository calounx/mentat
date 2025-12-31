<div>
    <!-- Header -->
    <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Dashboard</h1>
        <p class="mt-1 text-sm text-gray-600">
            Welcome back! Here's an overview of your hosting.
        </p>
    </div>

    @if($tenant)
        <!-- Stats Grid -->
        <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8">
            <!-- Total Sites -->
            <x-stats-card
                label="Total Sites"
                :value="$stats['total_sites']"
                icon="globe"
                icon-color="text-gray-400"
            />

            <!-- Active Sites -->
            <x-stats-card
                label="Active Sites"
                :value="$stats['active_sites']"
                icon="check-circle"
                icon-color="text-green-400"
            />

            <!-- Storage Used -->
            <x-stats-card
                label="Storage Used"
                :value="number_format($stats['storage_used_mb'] / 1024, 2) . ' GB'"
                icon="database"
                icon-color="text-blue-400"
            />

            <!-- SSL Expiring -->
            <x-stats-card
                label="SSL Expiring Soon"
                :value="$stats['ssl_expiring_soon']"
                icon="lock-closed"
                :icon-color="$stats['ssl_expiring_soon'] > 0 ? 'text-yellow-400' : 'text-gray-400'"
            />
        </div>

        <!-- Quick Actions & Recent Sites -->
        <div class="grid grid-cols-1 gap-5 lg:grid-cols-2">
            <!-- Quick Actions -->
            <x-card>
                <x-slot:header>
                    <h3 class="text-lg leading-6 font-medium text-gray-900">Quick Actions</h3>
                </x-slot:header>

                <div class="grid grid-cols-2 gap-4">
                    <x-button
                        variant="primary"
                        href="{{ route('sites.create') }}"
                        icon="plus"
                        class="justify-center"
                    >
                        New Site
                    </x-button>

                    <x-button
                        variant="secondary"
                        href="{{ route('sites.index') }}"
                        icon="bars-3"
                        class="justify-center"
                    >
                        View Sites
                    </x-button>
                </div>
            </x-card>

            <!-- Recent Sites -->
            <x-card>
                <x-slot:header>
                    <h3 class="text-lg leading-6 font-medium text-gray-900">Recent Sites</h3>
                </x-slot:header>

                @if(count($recentSites) > 0)
                    <ul class="divide-y divide-gray-200">
                        @foreach($recentSites as $site)
                            <li class="py-3 flex items-center justify-between">
                                <div class="flex items-center">
                                    <span class="inline-flex items-center justify-center h-8 w-8 rounded-full {{ $site['status'] === 'active' ? 'bg-green-100' : 'bg-gray-100' }}">
                                        <span class="text-sm font-medium {{ $site['status'] === 'active' ? 'text-green-800' : 'text-gray-800' }}">
                                            {{ strtoupper(substr($site['domain'], 0, 1)) }}
                                        </span>
                                    </span>
                                    <div class="ml-3">
                                        <p class="text-sm font-medium text-gray-900">{{ $site['domain'] }}</p>
                                        <p class="text-xs text-gray-500">{{ $site['created_at'] }}</p>
                                    </div>
                                </div>
                                <div class="flex items-center space-x-2">
                                    @if($site['ssl_enabled'])
                                        <x-badge variant="success">SSL</x-badge>
                                    @endif
                                    <x-badge :variant="$site['status'] === 'active' ? 'success' : 'default'">
                                        {{ ucfirst($site['status']) }}
                                    </x-badge>
                                </div>
                            </li>
                        @endforeach
                    </ul>
                @else
                    <x-empty-state
                        icon="globe"
                        title="No sites created yet"
                        description="Get started by creating your first site."
                    >
                        <x-button variant="primary" href="{{ route('sites.create') }}" icon="plus">
                            Create Site
                        </x-button>
                    </x-empty-state>
                @endif
            </x-card>
        </div>

        <!-- Tier Info -->
        <div class="mt-8">
            <x-card>
                <div class="flex items-center justify-between">
                    <div>
                        <h3 class="text-lg leading-6 font-medium text-gray-900">Current Plan</h3>
                        <p class="mt-1 text-sm text-gray-600">
                            {{ ucfirst($tenant->tier) }} Plan
                        </p>
                    </div>
                    <x-badge variant="primary" size="lg">
                        {{ ucfirst($tenant->tier) }}
                    </x-badge>
                </div>
            </x-card>
        </div>
    @else
        <x-alert type="warning">
            No tenant configured. Please contact support.
        </x-alert>
    @endif
</div>
