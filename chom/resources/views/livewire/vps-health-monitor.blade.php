<div class="vps-health-monitor" wire:poll.{{ $refreshInterval }}s="refresh">
    {{-- Elegant Header --}}
    <div class="mb-8 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
            <h1 class="font-display text-3xl font-semibold text-stone-900 mb-2">
                {{ $vps->hostname }}
            </h1>
            <p class="text-sm font-mono text-stone-600">
                {{ $vps->ip_address }}
            </p>
        </div>

        <div class="flex items-center gap-3">
            {{-- Status Indicator with Elegant Badge --}}
            <div class="status-badge status-{{ $healthStatus['color'] }}">
                <span class="status-dot {{ $healthStatus['color'] }}"></span>
                {{ $healthStatus['status'] }}
            </div>

            {{-- Refresh Button --}}
            <button wire:click="refresh"
                    wire:loading.attr="disabled"
                    class="btn btn-secondary">
                <svg wire:loading.remove class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                <svg wire:loading class="h-4 w-4 spinner-elegant" fill="none" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                Refresh
            </button>

            {{-- Export Menu with Alpine.js --}}
            <div x-data="{ open: false }" class="relative">
                <button @click="open = !open"
                        class="btn btn-secondary">
                    Export
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd"/>
                    </svg>
                </button>

                <div x-show="open"
                     @click.away="open = false"
                     x-transition:enter="transition ease-out duration-200"
                     x-transition:enter-start="opacity-0 scale-95"
                     x-transition:enter-end="opacity-100 scale-100"
                     x-transition:leave="transition ease-in duration-150"
                     x-transition:leave-start="opacity-100 scale-100"
                     x-transition:leave-end="opacity-0 scale-95"
                     class="absolute right-0 mt-3 w-48 origin-top-right rounded-xl bg-white shadow-lg ring-1 ring-black/5 z-50 overflow-hidden"
                     style="display: none;">
                    <div class="py-2">
                        <a href="#" wire:click.prevent="exportPdf" class="flex items-center gap-3 px-4 py-2.5 text-sm text-stone-700 hover:bg-emerald-50 hover:text-emerald-700 transition-colors duration-200">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                            </svg>
                            Export as PDF
                        </a>
                        <a href="#" wire:click.prevent="exportCsv" class="flex items-center gap-3 px-4 py-2.5 text-sm text-stone-700 hover:bg-emerald-50 hover:text-emerald-700 transition-colors duration-200">
                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                            </svg>
                            Export as CSV
                        </a>
                    </div>
                </div>
            </div>
        </div>
    </div>

    {{-- Error Display with Refined Styling --}}
    @if($error)
        <div class="card mb-6">
            <div class="card-body">
                <div class="flex items-start gap-3">
                    <div class="flex-shrink-0">
                        <svg class="h-5 w-5 text-ruby-500" fill="currentColor" viewBox="0 0 20 20">
                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                        </svg>
                    </div>
                    <div class="flex-1">
                        <p class="text-sm font-medium text-ruby-800">{{ $error }}</p>
                    </div>
                </div>
            </div>
        </div>
    @endif

    {{-- Main Grid Layout with Staggered Animation --}}
    <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">

        {{-- Health Status Card --}}
        <div class="card stagger-item">
            <div class="card-header">
                <h2 class="font-display text-xl font-semibold text-stone-900">Health Status</h2>
            </div>
            <div class="card-body">
                @if($healthData)
                    {{-- Services Status --}}
                    <div class="mb-6">
                        <h3 class="mb-3 text-sm font-medium text-stone-700 uppercase tracking-wider">Services</h3>
                        <div class="grid grid-cols-2 gap-3">
                            @foreach(($healthData['services'] ?? []) as $service => $status)
                                <div class="flex items-center gap-2">
                                    <span class="status-dot {{ $status ? 'healthy' : 'critical' }}"></span>
                                    <span class="text-sm text-stone-700">{{ ucfirst(str_replace('_', ' ', $service)) }}</span>
                                </div>
                            @endforeach
                        </div>
                    </div>

                    {{-- Resources --}}
                    @if(isset($healthData['resources']))
                        <div class="mb-6">
                            <h3 class="mb-4 text-sm font-medium text-stone-700 uppercase tracking-wider">Resources</h3>

                            {{-- CPU --}}
                            <div class="mb-4">
                                <div class="mb-2 flex justify-between text-sm">
                                    <span class="text-stone-600 font-medium">CPU</span>
                                    <span class="font-semibold text-stone-900">{{ $healthData['resources']['cpu_percent'] ?? 0 }}%</span>
                                </div>
                                <div class="progress-bar">
                                    @php
                                        $cpu = $healthData['resources']['cpu_percent'] ?? 0;
                                        $cpuClass = $cpu > 80 ? 'progress-critical' : ($cpu > 60 ? 'progress-warning' : 'progress-healthy');
                                    @endphp
                                    <div class="progress-fill {{ $cpuClass }}" style="width: {{ $cpu }}%"></div>
                                </div>
                            </div>

                            {{-- Memory --}}
                            <div class="mb-4">
                                <div class="mb-2 flex justify-between text-sm">
                                    <span class="text-stone-600 font-medium">Memory</span>
                                    <span class="font-semibold text-stone-900">{{ $healthData['resources']['memory_percent'] ?? 0 }}%</span>
                                </div>
                                <div class="progress-bar">
                                    @php
                                        $memory = $healthData['resources']['memory_percent'] ?? 0;
                                        $memoryClass = $memory > 85 ? 'progress-critical' : ($memory > 70 ? 'progress-warning' : 'progress-healthy');
                                    @endphp
                                    <div class="progress-fill {{ $memoryClass }}" style="width: {{ $memory }}%"></div>
                                </div>
                            </div>

                            {{-- Disk --}}
                            <div class="mb-4">
                                <div class="mb-2 flex justify-between text-sm">
                                    <span class="text-stone-600 font-medium">Disk</span>
                                    <span class="font-semibold text-stone-900">{{ $healthData['resources']['disk_percent'] ?? 0 }}%</span>
                                </div>
                                <div class="progress-bar">
                                    @php
                                        $disk = $healthData['resources']['disk_percent'] ?? 0;
                                        $diskClass = $disk > 80 ? 'progress-critical' : ($disk > 60 ? 'progress-warning' : 'progress-healthy');
                                    @endphp
                                    <div class="progress-fill {{ $diskClass }}" style="width: {{ $disk }}%"></div>
                                </div>
                            </div>

                            {{-- Load Average --}}
                            @if(isset($healthData['resources']['load_average']))
                                <div class="mt-4 p-4 rounded-lg bg-gradient-to-br from-stone-50 to-stone-100/50 border border-stone-200">
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600 font-medium">Load Average</span>
                                        <span class="font-mono text-sm text-stone-900">
                                            {{ implode(', ', array_map(fn($v) => number_format($v, 2), $healthData['resources']['load_average'])) }}
                                        </span>
                                    </div>
                                </div>
                            @endif
                        </div>
                    @endif

                    {{-- Uptime --}}
                    @if(isset($healthData['uptime_seconds']))
                        <div class="p-4 rounded-lg bg-gradient-to-br from-sapphire-50 to-sapphire-100/50 border border-sapphire-200 mb-3">
                            <div class="flex justify-between text-sm">
                                <span class="text-sapphire-700 font-medium">Uptime</span>
                                <span class="font-semibold text-sapphire-900">{{ $this->formatUptime($healthData['uptime_seconds']) }}</span>
                            </div>
                        </div>
                    @endif

                    {{-- Sites Count --}}
                    <div class="p-4 rounded-lg bg-gradient-to-br from-emerald-50 to-emerald-100/50 border border-emerald-200">
                        <div class="flex justify-between text-sm">
                            <span class="text-emerald-700 font-medium">Active Sites</span>
                            <span class="font-semibold text-emerald-900">{{ $healthData['sites_count'] ?? 0 }}</span>
                        </div>
                    </div>
                @else
                    {{-- Sophisticated Loading Skeleton --}}
                    <div class="space-y-4">
                        <div class="skeleton h-4 rounded"></div>
                        <div class="skeleton h-4 rounded"></div>
                        <div class="skeleton h-4 rounded"></div>
                        <div class="skeleton h-20 rounded"></div>
                    </div>
                @endif
            </div>
        </div>

        {{-- Statistics Card --}}
        <div class="card stagger-item lg:col-span-2">
            <div class="card-header">
                <h2 class="font-display text-xl font-semibold text-stone-900">Statistics (Last 24h)</h2>
            </div>
            <div class="card-body">
                @if($stats)
                    <div class="grid gap-6 md:grid-cols-2">
                        {{-- CPU Usage Chart --}}
                        <div class="chart-container">
                            <h3 class="mb-3 text-sm font-medium text-stone-700 uppercase tracking-wider">CPU Usage</h3>
                            <canvas id="cpuChart" class="h-32"></canvas>
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
                                                        borderColor: '#059669',
                                                        backgroundColor: 'rgba(5, 150, 105, 0.1)',
                                                        tension: 0.4,
                                                        borderWidth: 2
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
                        <div class="chart-container">
                            <h3 class="mb-3 text-sm font-medium text-stone-700 uppercase tracking-wider">Memory Usage</h3>
                            <canvas id="memoryChart" class="h-32"></canvas>
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
                                                        borderColor: '#2563eb',
                                                        backgroundColor: 'rgba(37, 99, 235, 0.1)',
                                                        tension: 0.4,
                                                        borderWidth: 2
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
                            <div class="chart-container">
                                <h3 class="mb-3 text-sm font-medium text-stone-700 uppercase tracking-wider">Disk I/O</h3>
                                <div class="space-y-3">
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600">Read</span>
                                        <span class="font-medium text-stone-900">{{ $stats['disk_io']['read'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600">Write</span>
                                        <span class="font-medium text-stone-900">{{ $stats['disk_io']['write'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600">IOPS</span>
                                        <span class="font-medium text-stone-900">{{ $stats['disk_io']['iops'] ?? 'N/A' }}</span>
                                    </div>
                                </div>
                            </div>
                        @endif

                        {{-- Network Traffic --}}
                        @if(isset($stats['network']))
                            <div class="chart-container">
                                <h3 class="mb-3 text-sm font-medium text-stone-700 uppercase tracking-wider">Network Traffic</h3>
                                <div class="space-y-3">
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600">Inbound</span>
                                        <span class="font-medium text-stone-900">{{ $stats['network']['inbound'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600">Outbound</span>
                                        <span class="font-medium text-stone-900">{{ $stats['network']['outbound'] ?? 'N/A' }}</span>
                                    </div>
                                    <div class="flex justify-between text-sm">
                                        <span class="text-stone-600">Connections</span>
                                        <span class="font-medium text-stone-900">{{ $stats['network']['connections'] ?? 'N/A' }}</span>
                                    </div>
                                </div>
                            </div>
                        @endif
                    </div>
                @else
                    {{-- Sophisticated Loading Skeleton --}}
                    <div class="grid gap-6 md:grid-cols-2">
                        <div class="space-y-3">
                            <div class="skeleton h-4 w-24 rounded"></div>
                            <div class="skeleton h-32 rounded"></div>
                        </div>
                        <div class="space-y-3">
                            <div class="skeleton h-4 w-24 rounded"></div>
                            <div class="skeleton h-32 rounded"></div>
                        </div>
                    </div>
                @endif
            </div>
        </div>

        {{-- Alerts Panel --}}
        <div class="card stagger-item md:col-span-2 lg:col-span-1">
            <div class="card-header">
                <h2 class="font-display text-xl font-semibold text-stone-900">Recent Alerts</h2>
            </div>
            <div class="card-body">
                @if(count($alerts) > 0)
                    <div class="space-y-3">
                        @foreach($alerts as $alert)
                            <div class="p-4 rounded-lg border {{ $alert['severity'] === 'critical' ? 'bg-gradient-to-br from-ruby-50 to-ruby-100/50 border-ruby-200' : 'bg-gradient-to-br from-champagne-50 to-champagne-100/50 border-champagne-200' }}">
                                <div class="flex items-start gap-3">
                                    <svg class="h-5 w-5 text-{{ $alert['severity'] === 'critical' ? 'ruby' : 'champagne' }}-600 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                                        <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                    </svg>
                                    <div class="flex-1 min-w-0">
                                        <p class="text-sm font-medium text-{{ $alert['severity'] === 'critical' ? 'ruby' : 'champagne' }}-900">
                                            {{ $alert['message'] }}
                                        </p>
                                        <p class="mt-1 text-xs text-{{ $alert['severity'] === 'critical' ? 'ruby' : 'champagne' }}-700">
                                            {{ $alert['timestamp']->diffForHumans() }}
                                        </p>
                                    </div>
                                </div>
                            </div>
                        @endforeach
                    </div>
                @else
                    <div class="text-center py-8">
                        <svg class="mx-auto h-12 w-12 text-emerald-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                        </svg>
                        <p class="mt-3 text-sm font-medium text-stone-600">No alerts</p>
                        <p class="text-xs text-stone-500 mt-1">All systems operating normally</p>
                    </div>
                @endif
            </div>
        </div>

        {{-- Sites on this VPS --}}
        <div class="card stagger-item md:col-span-2">
            <div class="card-header">
                <h2 class="font-display text-xl font-semibold text-stone-900">Sites on this VPS</h2>
            </div>
            <div class="card-body p-0">
                @if($sites->count() > 0)
                    <div class="overflow-x-auto">
                        <table class="table-refined">
                            <thead>
                                <tr>
                                    <th>Domain</th>
                                    <th>Status</th>
                                    <th>SSL</th>
                                    <th>Type</th>
                                    <th class="text-right">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                @foreach($sites as $site)
                                    <tr>
                                        <td class="font-medium text-stone-900">
                                            {{ $site->domain }}
                                        </td>
                                        <td>
                                            <span class="status-badge status-{{ $site->status === 'active' ? 'healthy' : 'info' }}">
                                                {{ ucfirst($site->status) }}
                                            </span>
                                        </td>
                                        <td>
                                            @if($site->ssl_enabled)
                                                <span class="inline-flex items-center gap-1.5 text-emerald-700">
                                                    <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                                                        <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd"/>
                                                    </svg>
                                                    <span class="text-sm font-medium">Enabled</span>
                                                </span>
                                            @else
                                                <span class="inline-flex items-center gap-1.5 text-stone-400">
                                                    <svg class="h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                                                        <path d="M10 2a5 5 0 00-5 5v2a2 2 0 00-2 2v5a2 2 0 002 2h10a2 2 0 002-2v-5a2 2 0 00-2-2H7V7a3 3 0 015.905-.75 1 1 0 001.937-.5A5.002 5.002 0 0010 2z"/>
                                                    </svg>
                                                    <span class="text-sm">Disabled</span>
                                                </span>
                                            @endif
                                        </td>
                                        <td class="text-stone-600 text-sm">
                                            {{ ucfirst($site->site_type) }}
                                        </td>
                                        <td class="text-right">
                                            <a href="/sites/{{ $site->id }}" class="text-emerald-700 hover:text-emerald-900 font-medium text-sm">View</a>
                                            <span class="mx-2 text-stone-300">|</span>
                                            <a href="/sites/{{ $site->id }}/ssl" class="text-sapphire-700 hover:text-sapphire-900 font-medium text-sm">SSL</a>
                                        </td>
                                    </tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @else
                    <div class="text-center py-12 px-6">
                        <svg class="mx-auto h-12 w-12 text-stone-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                        </svg>
                        <p class="mt-3 text-sm font-medium text-stone-600">No sites on this VPS</p>
                        <p class="text-xs text-stone-500 mt-1">Sites will appear here once deployed</p>
                    </div>
                @endif
            </div>
        </div>
    </div>

    {{-- Chart.js Script --}}
    @push('scripts')
        <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    @endpush
</div>
