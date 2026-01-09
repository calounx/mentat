<div class="vps-health-monitor" wire:poll.{{ $refreshInterval }}s="refresh">
    {{-- Header --}}
    <div class="mb-6 flex items-center justify-between">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">
                {{ $vps->hostname }}
            </h1>
            <p class="text-sm text-gray-600">
                {{ $vps->ip_address }}
            </p>
        </div>

        <div class="flex items-center gap-3">
            {{-- Status Indicator --}}
            <div class="flex items-center gap-2">
                <svg class="h-5 w-5 text-{{ $healthStatus['color'] }}-500" fill="currentColor" viewBox="0 0 20 20">
                    <circle cx="10" cy="10" r="8"/>
                </svg>
                <span class="text-sm font-medium text-{{ $healthStatus['color'] }}-700">
                    {{ $healthStatus['status'] }}
                </span>
            </div>

            {{-- Refresh Button --}}
            <button wire:click="refresh"
                    wire:loading.attr="disabled"
                    class="rounded-md bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 disabled:opacity-50">
                <svg wire:loading.remove class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                <svg wire:loading class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
            </button>

            {{-- Export Menu --}}
            <div x-data="{ open: false }" class="relative">
                <button @click="open = !open"
                        class="rounded-md bg-white px-3 py-2 text-sm font-medium text-gray-700 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50">
                    Export
                    <svg class="-mr-1 ml-2 h-4 w-4 inline" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd"/>
                    </svg>
                </button>

                <div x-show="open"
                     @click.away="open = false"
                     x-transition
                     class="absolute right-0 mt-2 w-36 origin-top-right rounded-md bg-white shadow-lg ring-1 ring-black ring-opacity-5 z-10">
                    <div class="py-1">
                        <a href="#" wire:click.prevent="exportPdf" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                            Export as PDF
                        </a>
                        <a href="#" wire:click.prevent="exportCsv" class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-100">
                            Export as CSV
                        </a>
                    </div>
                </div>
            </div>
        </div>
    </div>

    {{-- Error Display --}}
    @if($error)
        <div class="mb-6 rounded-md bg-red-50 p-4">
            <div class="flex">
                <svg class="h-5 w-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                </svg>
                <div class="ml-3">
                    <p class="text-sm text-red-800">{{ $error }}</p>
                </div>
            </div>
        </div>
    @endif

    {{-- Main Grid Layout --}}
    <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">

        {{-- Health Status Card --}}
        <div class="rounded-lg bg-white shadow-md ring-1 ring-gray-200">
            <div class="border-b border-gray-200 px-6 py-4">
                <h2 class="text-lg font-semibold text-gray-900">Health Status</h2>
            </div>
            <div class="p-6">
                @if($healthData)
                    {{-- Services Status --}}
                    <div class="mb-4">
                        <h3 class="mb-3 text-sm font-medium text-gray-700">Services</h3>
                        <div class="grid grid-cols-2 gap-3">
                            @foreach(($healthData['services'] ?? []) as $service => $status)
                                <div class="flex items-center gap-2">
                                    <svg class="h-4 w-4 text-{{ $status ? 'green' : 'red' }}-500" fill="currentColor" viewBox="0 0 20 20">
                                        <circle cx="10" cy="10" r="8"/>
                                    </svg>
                                    <span class="text-sm text-gray-700">{{ ucfirst(str_replace('_', ' ', $service)) }}</span>
                                </div>
                            @endforeach
                        </div>
                    </div>

                    {{-- Resources --}}
                    @if(isset($healthData['resources']))
                        <div class="mb-4">
                            <h3 class="mb-3 text-sm font-medium text-gray-700">Resources</h3>

                            {{-- CPU --}}
                            <div class="mb-3">
                                <div class="mb-1 flex justify-between text-xs">
                                    <span class="text-gray-600">CPU</span>
                                    <span class="font-medium text-gray-900">{{ $healthData['resources']['cpu_percent'] ?? 0 }}%</span>
                                </div>
                                <div class="h-2 w-full rounded-full bg-gray-200">
                                    <div class="h-2 rounded-full bg-{{ ($healthData['resources']['cpu_percent'] ?? 0) > 80 ? 'red' : (($healthData['resources']['cpu_percent'] ?? 0) > 60 ? 'yellow' : 'green') }}-500"
                                         style="width: {{ $healthData['resources']['cpu_percent'] ?? 0 }}%"></div>
                                </div>
                            </div>

                            {{-- Memory --}}
                            <div class="mb-3">
                                <div class="mb-1 flex justify-between text-xs">
                                    <span class="text-gray-600">Memory</span>
                                    <span class="font-medium text-gray-900">{{ $healthData['resources']['memory_percent'] ?? 0 }}%</span>
                                </div>
                                <div class="h-2 w-full rounded-full bg-gray-200">
                                    <div class="h-2 rounded-full bg-{{ ($healthData['resources']['memory_percent'] ?? 0) > 85 ? 'red' : (($healthData['resources']['memory_percent'] ?? 0) > 70 ? 'yellow' : 'green') }}-500"
                                         style="width: {{ $healthData['resources']['memory_percent'] ?? 0 }}%"></div>
                                </div>
                            </div>

                            {{-- Disk --}}
                            <div class="mb-3">
                                <div class="mb-1 flex justify-between text-xs">
                                    <span class="text-gray-600">Disk</span>
                                    <span class="font-medium text-gray-900">{{ $healthData['resources']['disk_percent'] ?? 0 }}%</span>
                                </div>
                                <div class="h-2 w-full rounded-full bg-gray-200">
                                    <div class="h-2 rounded-full bg-{{ ($healthData['resources']['disk_percent'] ?? 0) > 80 ? 'red' : (($healthData['resources']['disk_percent'] ?? 0) > 60 ? 'yellow' : 'green') }}-500"
                                         style="width: {{ $healthData['resources']['disk_percent'] ?? 0 }}%"></div>
                                </div>
                            </div>

                            {{-- Load Average --}}
                            @if(isset($healthData['resources']['load_average']))
                                <div class="mt-4 rounded-md bg-gray-50 p-3">
                                    <div class="flex justify-between text-xs">
                                        <span class="text-gray-600">Load Average</span>
                                        <span class="font-mono text-gray-900">
                                            {{ implode(', ', array_map(fn($v) => number_format($v, 2), $healthData['resources']['load_average'])) }}
                                        </span>
                                    </div>
                                </div>
                            @endif
                        </div>
                    @endif

                    {{-- Uptime --}}
                    @if(isset($healthData['uptime_seconds']))
                        <div class="rounded-md bg-blue-50 p-3">
                            <div class="flex justify-between text-sm">
                                <span class="text-blue-700">Uptime</span>
                                <span class="font-medium text-blue-900">{{ $this->formatUptime($healthData['uptime_seconds']) }}</span>
                            </div>
                        </div>
                    @endif

                    {{-- Sites Count --}}
                    <div class="mt-3 rounded-md bg-green-50 p-3">
                        <div class="flex justify-between text-sm">
                            <span class="text-green-700">Active Sites</span>
                            <span class="font-medium text-green-900">{{ $healthData['sites_count'] ?? 0 }}</span>
                        </div>
                    </div>
                @else
                    {{-- Loading Skeleton --}}
                    <div class="animate-pulse space-y-4">
                        <div class="h-4 rounded bg-gray-200"></div>
                        <div class="h-4 rounded bg-gray-200"></div>
                        <div class="h-4 rounded bg-gray-200"></div>
                        <div class="h-20 rounded bg-gray-200"></div>
                    </div>
                @endif
            </div>
        </div>

        {{-- Statistics Card --}}
        <div class="rounded-lg bg-white shadow-md ring-1 ring-gray-200 lg:col-span-2">
            <div class="border-b border-gray-200 px-6 py-4">
                <h2 class="text-lg font-semibold text-gray-900">Statistics (Last 24h)</h2>
            </div>
            <div class="p-6">
                @if($stats)
                    <div class="grid gap-6 md:grid-cols-2">
                        {{-- CPU Usage Chart --}}
                        <div>
                            <h3 class="mb-3 text-sm font-medium text-gray-700">CPU Usage</h3>
                            <div class="rounded-lg bg-gray-50 p-4">
                                <canvas id="cpuChart" class="h-32"></canvas>
                            </div>
                            @if(isset($stats['cpu_usage']))
                                <script>
                                    document.addEventListener('DOMContentLoaded', function() {
                                        const ctx = document.getElementById('cpuChart');
                                        if (ctx && typeof Chart !== 'undefined') {
                                            new Chart(ctx, {
                                                type: 'line',
                                                data: {
                                                    labels: @json(array_keys($stats['cpu_usage'] ?? [])),
                                                    datasets: [{
                                                        label: 'CPU %',
                                                        data: @json(array_values($stats['cpu_usage'] ?? [])),
                                                        borderColor: 'rgb(59, 130, 246)',
                                                        backgroundColor: 'rgba(59, 130, 246, 0.1)',
                                                        tension: 0.4
                                                    }]
                                                },
                                                options: {
                                                    responsive: true,
                                                    maintainAspectRatio: false,
                                                    scales: {
                                                        y: {
                                                            beginAtZero: true,
                                                            max: 100
                                                        }
                                                    }
                                                }
                                            });
                                        }
                                    });
                                </script>
                            @endif
                        </div>

                        {{-- Memory Usage Chart --}}
                        <div>
                            <h3 class="mb-3 text-sm font-medium text-gray-700">Memory Usage</h3>
                            <div class="rounded-lg bg-gray-50 p-4">
                                <canvas id="memoryChart" class="h-32"></canvas>
                            </div>
                            @if(isset($stats['memory_usage']))
                                <script>
                                    document.addEventListener('DOMContentLoaded', function() {
                                        const ctx = document.getElementById('memoryChart');
                                        if (ctx && typeof Chart !== 'undefined') {
                                            new Chart(ctx, {
                                                type: 'line',
                                                data: {
                                                    labels: @json(array_keys($stats['memory_usage'] ?? [])),
                                                    datasets: [{
                                                        label: 'Memory %',
                                                        data: @json(array_values($stats['memory_usage'] ?? [])),
                                                        borderColor: 'rgb(34, 197, 94)',
                                                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                                                        tension: 0.4
                                                    }]
                                                },
                                                options: {
                                                    responsive: true,
                                                    maintainAspectRatio: false,
                                                    scales: {
                                                        y: {
                                                            beginAtZero: true,
                                                            max: 100
                                                        }
                                                    }
                                                }
                                            });
                                        }
                                    });
                                </script>
                            @endif
                        </div>

                        {{-- Disk I/O --}}
                        @if(isset($stats['disk_io']))
                            <div>
                                <h3 class="mb-3 text-sm font-medium text-gray-700">Disk I/O</h3>
                                <div class="space-y-2 rounded-lg bg-gray-50 p-4">
                                    <div class="flex justify-between text-sm">
                                        <span class="text-gray-600">Read</span>
                                        <span class="font-medium text-gray-900">{{ $stats['disk_io']['read'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-gray-600">Write</span>
                                        <span class="font-medium text-gray-900">{{ $stats['disk_io']['write'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-gray-600">IOPS</span>
                                        <span class="font-medium text-gray-900">{{ $stats['disk_io']['iops'] ?? 'N/A' }}</span>
                                    </div>
                                </div>
                            </div>
                        @endif

                        {{-- Network Traffic --}}
                        @if(isset($stats['network']))
                            <div>
                                <h3 class="mb-3 text-sm font-medium text-gray-700">Network Traffic</h3>
                                <div class="space-y-2 rounded-lg bg-gray-50 p-4">
                                    <div class="flex justify-between text-sm">
                                        <span class="text-gray-600">Inbound</span>
                                        <span class="font-medium text-gray-900">{{ $stats['network']['inbound'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-gray-600">Outbound</span>
                                        <span class="font-medium text-gray-900">{{ $stats['network']['outbound'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-gray-600">Connections</span>
                                        <span class="font-medium text-gray-900">{{ $stats['network']['connections'] ?? 'N/A' }}</span>
                                    </div>
                                </div>
                            </div>
                        @endif
                    </div>
                @else
                    {{-- Loading Skeleton --}}
                    <div class="grid gap-6 md:grid-cols-2">
                        <div class="animate-pulse">
                            <div class="mb-3 h-4 w-24 rounded bg-gray-200"></div>
                            <div class="h-32 rounded bg-gray-200"></div>
                        </div>
                        <div class="animate-pulse">
                            <div class="mb-3 h-4 w-24 rounded bg-gray-200"></div>
                            <div class="h-32 rounded bg-gray-200"></div>
                        </div>
                    </div>
                @endif
            </div>
        </div>

        {{-- Alerts Panel --}}
        <div class="rounded-lg bg-white shadow-md ring-1 ring-gray-200 md:col-span-2 lg:col-span-1">
            <div class="border-b border-gray-200 px-6 py-4">
                <h2 class="text-lg font-semibold text-gray-900">Recent Alerts</h2>
            </div>
            <div class="p-6">
                @if(count($alerts) > 0)
                    <div class="space-y-3">
                        @foreach($alerts as $alert)
                            <div class="rounded-md border border-{{ $alert['severity'] === 'critical' ? 'red' : 'yellow' }}-200 bg-{{ $alert['severity'] === 'critical' ? 'red' : 'yellow' }}-50 p-3">
                                <div class="flex">
                                    <svg class="h-5 w-5 text-{{ $alert['severity'] === 'critical' ? 'red' : 'yellow' }}-400" fill="currentColor" viewBox="0 0 20 20">
                                        <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                    </svg>
                                    <div class="ml-3 flex-1">
                                        <p class="text-sm font-medium text-{{ $alert['severity'] === 'critical' ? 'red' : 'yellow' }}-800">
                                            {{ $alert['message'] }}
                                        </p>
                                        <p class="mt-1 text-xs text-{{ $alert['severity'] === 'critical' ? 'red' : 'yellow' }}-700">
                                            {{ $alert['timestamp']->diffForHumans() }}
                                        </p>
                                    </div>
                                </div>
                            </div>
                        @endforeach
                    </div>
                @else
                    <div class="text-center">
                        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                        </svg>
                        <p class="mt-2 text-sm text-gray-500">No alerts</p>
                        <p class="text-xs text-gray-400">All systems operating normally</p>
                    </div>
                @endif
            </div>
        </div>

        {{-- Sites on this VPS --}}
        <div class="rounded-lg bg-white shadow-md ring-1 ring-gray-200 md:col-span-2">
            <div class="border-b border-gray-200 px-6 py-4">
                <h2 class="text-lg font-semibold text-gray-900">Sites on this VPS</h2>
            </div>
            <div class="p-6">
                @if($sites->count() > 0)
                    <div class="overflow-x-auto">
                        <table class="min-w-full divide-y divide-gray-200">
                            <thead>
                                <tr>
                                    <th class="px-3 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Domain</th>
                                    <th class="px-3 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Status</th>
                                    <th class="px-3 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">SSL</th>
                                    <th class="px-3 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-500">Type</th>
                                    <th class="px-3 py-3 text-right text-xs font-medium uppercase tracking-wider text-gray-500">Actions</th>
                                </tr>
                            </thead>
                            <tbody class="divide-y divide-gray-200 bg-white">
                                @foreach($sites as $site)
                                    <tr>
                                        <td class="whitespace-nowrap px-3 py-4 text-sm font-medium text-gray-900">
                                            {{ $site->domain }}
                                        </td>
                                        <td class="whitespace-nowrap px-3 py-4 text-sm">
                                            <span class="inline-flex rounded-full px-2 py-1 text-xs font-semibold {{ $site->status === 'active' ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800' }}">
                                                {{ ucfirst($site->status) }}
                                            </span>
                                        </td>
                                        <td class="whitespace-nowrap px-3 py-4 text-sm">
                                            @if($site->ssl_enabled)
                                                <span class="inline-flex items-center gap-1 text-green-600">
                                                    <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                                                        <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"/>
                                                    </svg>
                                                    Enabled
                                                </span>
                                            @else
                                                <span class="inline-flex items-center gap-1 text-gray-400">
                                                    <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                                                        <path d="M10 2a5 5 0 00-5 5v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2H7V7a3 3 0 015.905-.75 1 1 0 001.937-.5A5.002 5.002 0 0010 2z"/>
                                                    </svg>
                                                    Disabled
                                                </span>
                                            @endif
                                        </td>
                                        <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                                            {{ ucfirst($site->site_type) }}
                                        </td>
                                        <td class="whitespace-nowrap px-3 py-4 text-right text-sm">
                                            <a href="/sites/{{ $site->id }}" class="text-blue-600 hover:text-blue-900">View</a>
                                            <span class="mx-2 text-gray-300">|</span>
                                            <a href="/sites/{{ $site->id }}/ssl" class="text-blue-600 hover:text-blue-900">SSL</a>
                                        </td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @else
                    <div class="text-center">
                        <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                        </svg>
                        <p class="mt-2 text-sm text-gray-500">No sites on this VPS</p>
                        <p class="text-xs text-gray-400">Sites will appear here once deployed</p>
                    </div>
                @endif
            </div>
        </div>
    </div>

    {{-- Chart.js Script --}}
    @push('scripts')
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    @endpush

    {{-- Alpine.js for dropdowns --}}
    @push('scripts')
        <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>
    @endpush
</div>
