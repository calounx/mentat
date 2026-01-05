<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">Admin Dashboard</h1>
            <p class="mt-1 text-sm text-gray-400">System-wide overview and health status.</p>
        </div>
        <div class="mt-4 sm:mt-0 flex space-x-3">
            <a href="{{ route('admin.vps.index') }}?action=add"
               class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                <svg class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
                Add VPS
            </a>
            <button wire:click="refresh"
                    wire:loading.attr="disabled"
                    class="inline-flex items-center px-4 py-2 border border-gray-600 rounded-md shadow-sm text-sm font-medium text-gray-300 bg-gray-700 hover:bg-gray-600 disabled:opacity-50">
                <svg wire:loading.class="animate-spin" class="h-5 w-5 mr-2 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                Refresh
            </button>
        </div>
    </div>

    @if($error)
        <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
            <p class="text-sm text-red-200">{{ $error }}</p>
        </div>
    @endif

    <!-- Stats Grid -->
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-8">
        <!-- VPS Servers -->
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="flex items-center">
                    <div class="flex-shrink-0">
                        <svg class="h-6 w-6 text-blue-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 14.25h13.5m-13.5 0a3 3 0 01-3-3m3 3a3 3 0 100 6h13.5a3 3 0 100-6m-16.5-3a3 3 0 013-3h13.5a3 3 0 013 3m-19.5 0a4.5 4.5 0 01.9-2.7L5.737 5.1a3.375 3.375 0 012.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 01.9 2.7m0 0a3 3 0 01-3 3m0 3h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008zm-3 6h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008z" />
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dl>
                            <dt class="text-sm font-medium text-gray-400 truncate">VPS Servers</dt>
                            <dd class="flex items-baseline">
                                <div class="text-2xl font-semibold text-white">{{ $stats['total_vps'] ?? 0 }}</div>
                                <div class="ml-2 text-sm text-gray-500">{{ $stats['active_vps'] ?? 0 }} active</div>
                            </dd>
                        </dl>
                    </div>
                </div>
            </div>
            <div class="bg-gray-700/50 px-5 py-3 flex justify-between items-center">
                <a href="{{ route('admin.vps.index') }}" class="text-sm font-medium text-blue-400 hover:text-blue-300">
                    View all
                </a>
                <a href="{{ route('admin.vps.index') }}?action=add" class="text-sm font-medium text-green-400 hover:text-green-300">
                    + Add new
                </a>
            </div>
        </div>

        <!-- Tenants -->
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="flex items-center">
                    <div class="flex-shrink-0">
                        <svg class="h-6 w-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 003.741-.479 3 3 0 00-4.682-2.72m.94 3.198l.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0112 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 016 18.719m12 0a5.971 5.971 0 00-.941-3.197m0 0A5.995 5.995 0 0012 12.75a5.995 5.995 0 00-5.058 2.772m0 0a3 3 0 00-4.681 2.72 8.986 8.986 0 003.74.477m.94-3.197a5.971 5.971 0 00-.94 3.197M15 6.75a3 3 0 11-6 0 3 3 0 016 0zm6 3a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0zm-13.5 0a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z" />
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dl>
                            <dt class="text-sm font-medium text-gray-400 truncate">Tenants</dt>
                            <dd class="flex items-baseline">
                                <div class="text-2xl font-semibold text-white">{{ $stats['total_tenants'] ?? 0 }}</div>
                                <div class="ml-2 text-sm text-gray-500">{{ $stats['active_tenants'] ?? 0 }} active</div>
                            </dd>
                        </dl>
                    </div>
                </div>
            </div>
            <div class="bg-gray-700/50 px-5 py-3 flex justify-between items-center">
                <a href="{{ route('admin.tenants.index') }}" class="text-sm font-medium text-green-400 hover:text-green-300">
                    View all
                </a>
                <a href="{{ route('admin.tenants.index') }}?action=add" class="text-sm font-medium text-blue-400 hover:text-blue-300">
                    + Add new
                </a>
            </div>
        </div>

        <!-- Sites -->
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="flex items-center">
                    <div class="flex-shrink-0">
                        <svg class="h-6 w-6 text-purple-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418" />
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dl>
                            <dt class="text-sm font-medium text-gray-400 truncate">Sites</dt>
                            <dd class="flex items-baseline">
                                <div class="text-2xl font-semibold text-white">{{ $stats['total_sites'] ?? 0 }}</div>
                                <div class="ml-2 text-sm text-gray-500">{{ $stats['active_sites'] ?? 0 }} active</div>
                            </dd>
                        </dl>
                    </div>
                </div>
            </div>
            <div class="bg-gray-700/50 px-5 py-3 flex justify-between items-center">
                <a href="{{ route('admin.sites.index') }}" class="text-sm font-medium text-purple-400 hover:text-purple-300">
                    View all
                </a>
                <a href="{{ route('admin.sites.index') }}?action=add" class="text-sm font-medium text-blue-400 hover:text-blue-300">
                    + Add new
                </a>
            </div>
        </div>

        <!-- Backups -->
        <div class="bg-gray-800 overflow-hidden shadow rounded-lg border border-gray-700">
            <div class="p-5">
                <div class="flex items-center">
                    <div class="flex-shrink-0">
                        <svg class="h-6 w-6 text-orange-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 7.5l-.625 10.632a2.25 2.25 0 01-2.247 2.118H6.622a2.25 2.25 0 01-2.247-2.118L3.75 7.5m8.25 3v6.75m0 0l-3-3m3 3l3-3M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125z" />
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dl>
                            <dt class="text-sm font-medium text-gray-400 truncate">Backups</dt>
                            <dd class="flex items-baseline">
                                <div class="text-2xl font-semibold text-white">{{ $stats['total_backups'] ?? 0 }}</div>
                            </dd>
                        </dl>
                    </div>
                </div>
            </div>
            <div class="bg-gray-700/50 px-5 py-3">
                <span class="text-sm text-gray-500">System-wide</span>
            </div>
        </div>
    </div>

    <!-- Two Column Layout -->
    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- VPS Health Summary -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">VPS Health Overview</h3>
                <div class="grid grid-cols-4 gap-4">
                    <div class="text-center">
                        <div class="text-3xl font-bold text-green-400">{{ $vpsHealthSummary['healthy'] ?? 0 }}</div>
                        <div class="text-sm text-gray-400">Healthy</div>
                    </div>
                    <div class="text-center">
                        <div class="text-3xl font-bold text-yellow-400">{{ $vpsHealthSummary['degraded'] ?? 0 }}</div>
                        <div class="text-sm text-gray-400">Degraded</div>
                    </div>
                    <div class="text-center">
                        <div class="text-3xl font-bold text-red-400">{{ $vpsHealthSummary['unhealthy'] ?? 0 }}</div>
                        <div class="text-sm text-gray-400">Unhealthy</div>
                    </div>
                    <div class="text-center">
                        <div class="text-3xl font-bold text-gray-400">{{ $vpsHealthSummary['unknown'] ?? 0 }}</div>
                        <div class="text-sm text-gray-400">Unknown</div>
                    </div>
                </div>

                <!-- Health Progress Bar -->
                @php
                    $total = array_sum($vpsHealthSummary);
                    $healthyPercent = $total > 0 ? (($vpsHealthSummary['healthy'] ?? 0) / $total * 100) : 0;
                    $degradedPercent = $total > 0 ? (($vpsHealthSummary['degraded'] ?? 0) / $total * 100) : 0;
                    $unhealthyPercent = $total > 0 ? (($vpsHealthSummary['unhealthy'] ?? 0) / $total * 100) : 0;
                @endphp
                <div class="mt-6">
                    <div class="flex h-4 rounded-full overflow-hidden bg-gray-700">
                        <div class="bg-green-500" style="width: {{ $healthyPercent }}%"></div>
                        <div class="bg-yellow-500" style="width: {{ $degradedPercent }}%"></div>
                        <div class="bg-red-500" style="width: {{ $unhealthyPercent }}%"></div>
                    </div>
                    <div class="mt-2 flex justify-between text-xs text-gray-400">
                        <span>Overall health: {{ round($healthyPercent) }}% healthy</span>
                        <a href="{{ route('admin.vps.index') }}" class="text-blue-400 hover:text-blue-300">View details</a>
                    </div>
                </div>
            </div>
        </div>

        <!-- Recent Alerts -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">Recent Alerts</h3>
                @if(count($recentAlerts) > 0)
                    <ul class="divide-y divide-gray-700">
                        @foreach($recentAlerts as $alert)
                            <li class="py-3">
                                <div class="flex items-start">
                                    @php
                                        $iconColor = match($alert['type']) {
                                            'error' => 'text-red-400',
                                            'warning' => 'text-yellow-400',
                                            default => 'text-blue-400',
                                        };
                                    @endphp
                                    <svg class="h-5 w-5 {{ $iconColor }} mt-0.5 mr-3 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                                        @if($alert['type'] === 'error')
                                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                                        @else
                                            <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                        @endif
                                    </svg>
                                    <div class="flex-1 min-w-0">
                                        <p class="text-sm font-medium text-white">{{ $alert['title'] }}</p>
                                        <p class="text-sm text-gray-400">{{ $alert['message'] }}</p>
                                        @if($alert['tenant'])
                                            <p class="text-xs text-gray-500 mt-1">Tenant: {{ $alert['tenant'] }}</p>
                                        @endif
                                    </div>
                                </div>
                            </li>
                        @endforeach
                    </ul>
                @else
                    <div class="text-center py-6">
                        <svg class="mx-auto h-12 w-12 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                        </svg>
                        <p class="mt-2 text-sm text-gray-400">No alerts at this time.</p>
                    </div>
                @endif
            </div>
        </div>
    </div>

    <!-- SSL Expiring Warning -->
    @if(($stats['ssl_expiring_soon'] ?? 0) > 0)
        <div class="mt-6 bg-yellow-900/50 border border-yellow-600 rounded-lg p-4">
            <div class="flex items-center">
                <svg class="h-5 w-5 text-yellow-400 mr-3" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                </svg>
                <p class="text-sm text-yellow-200">
                    <strong>{{ $stats['ssl_expiring_soon'] }}</strong> site(s) have SSL certificates expiring within 14 days.
                    <a href="{{ route('admin.sites.index') }}?ssl_expiring=1" class="ml-2 underline hover:no-underline">View affected sites</a>
                </p>
            </div>
        </div>
    @endif
</div>
