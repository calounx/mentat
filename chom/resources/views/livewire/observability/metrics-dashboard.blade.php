<div wire:poll.{{ $refreshInterval }}s="refresh">
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">Metrics Dashboard</h1>
            <p class="mt-1 text-sm text-gray-600">Monitor your infrastructure and site performance.</p>
        </div>
    </div>

    <!-- Error Message -->
    @if($error)
        <div class="mb-6 bg-red-50 border-l-4 border-red-400 p-4">
            <div class="flex">
                <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                    </svg>
                </div>
                <div class="ml-3">
                    <p class="text-sm text-red-700">{{ $error }}</p>
                </div>
            </div>
        </div>
    @endif

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

            <!-- Time Range -->
            <div>
                <select wire:model.live="timeRange"
                        class="border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                    <option value="15m">Last 15 minutes</option>
                    <option value="30m">Last 30 minutes</option>
                    <option value="1h">Last 1 hour</option>
                    <option value="3h">Last 3 hours</option>
                    <option value="6h">Last 6 hours</option>
                    <option value="12h">Last 12 hours</option>
                    <option value="24h">Last 24 hours</option>
                    <option value="7d">Last 7 days</option>
                </select>
            </div>

            <!-- Refresh Interval -->
            <div>
                <select wire:model.live="refreshInterval"
                        class="border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                    <option value="10">Refresh: 10s</option>
                    <option value="30">Refresh: 30s</option>
                    <option value="60">Refresh: 1m</option>
                    <option value="300">Refresh: 5m</option>
                </select>
            </div>

            <!-- Manual Refresh -->
            <button wire:click="refresh"
                    class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50">
                <svg class="h-4 w-4 mr-2 {{ $loading ? 'animate-spin' : '' }}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                </svg>
                Refresh
            </button>
        </div>
    </div>

    <!-- Current Stats -->
    <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-6">
        <!-- CPU Usage -->
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <div class="flex items-center">
                    <div class="flex-shrink-0 bg-blue-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"/>
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dt class="text-sm font-medium text-gray-500 truncate">CPU Usage</dt>
                        <dd class="flex items-baseline">
                            <div class="text-2xl font-semibold text-gray-900">
                                @if($loading)
                                    <span class="animate-pulse">...</span>
                                @else
                                    {{ $this->getLatestValue($cpuData) }}
                                @endif
                            </div>
                        </dd>
                    </div>
                </div>
            </div>
        </div>

        <!-- Memory Usage -->
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <div class="flex items-center">
                    <div class="flex-shrink-0 bg-green-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dt class="text-sm font-medium text-gray-500 truncate">Memory Usage</dt>
                        <dd class="flex items-baseline">
                            <div class="text-2xl font-semibold text-gray-900">
                                @if($loading)
                                    <span class="animate-pulse">...</span>
                                @else
                                    {{ $this->getLatestValue($memoryData) }}
                                @endif
                            </div>
                        </dd>
                    </div>
                </div>
            </div>
        </div>

        <!-- Disk Usage -->
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <div class="flex items-center">
                    <div class="flex-shrink-0 bg-yellow-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4"/>
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dt class="text-sm font-medium text-gray-500 truncate">Disk Usage</dt>
                        <dd class="flex items-baseline">
                            <div class="text-2xl font-semibold text-gray-900">
                                @if($loading)
                                    <span class="animate-pulse">...</span>
                                @else
                                    {{ $this->getLatestValue($diskData) }}
                                @endif
                            </div>
                        </dd>
                    </div>
                </div>
            </div>
        </div>

        <!-- Network I/O -->
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <div class="flex items-center">
                    <div class="flex-shrink-0 bg-purple-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"/>
                        </svg>
                    </div>
                    <div class="ml-5 w-0 flex-1">
                        <dt class="text-sm font-medium text-gray-500 truncate">Network In</dt>
                        <dd class="flex items-baseline">
                            <div class="text-2xl font-semibold text-gray-900">
                                @if($loading)
                                    <span class="animate-pulse">...</span>
                                @else
                                    @php
                                        $netValue = 'N/A';
                                        if (!empty($networkData['data']['result'][0]['value'][1])) {
                                            $bytes = (float) $networkData['data']['result'][0]['value'][1];
                                            if ($bytes >= 1024 * 1024) {
                                                $netValue = number_format($bytes / (1024 * 1024), 1) . ' MB/s';
                                            } elseif ($bytes >= 1024) {
                                                $netValue = number_format($bytes / 1024, 1) . ' KB/s';
                                            } else {
                                                $netValue = number_format($bytes, 0) . ' B/s';
                                            }
                                        }
                                    @endphp
                                    {{ $netValue }}
                                @endif
                            </div>
                        </dd>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Charts Section -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- CPU Chart -->
        <div class="bg-white shadow rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
                <h3 class="text-lg leading-6 font-medium text-gray-900">CPU Usage Over Time</h3>
            </div>
            <div class="p-4">
                <div class="h-64 flex items-center justify-center" id="cpu-chart">
                    @if($loading)
                        <div class="text-gray-400">Loading...</div>
                    @elseif(empty($cpuData['data']['result']))
                        <div class="text-gray-400">No data available</div>
                    @else
                        <div class="w-full h-full bg-gray-50 rounded flex items-end justify-around p-4 space-x-1">
                            @php
                                $values = $cpuData['data']['result'][0]['values'] ?? [];
                                $maxValue = 100;
                                $displayValues = array_slice($values, -30);
                            @endphp
                            @foreach($displayValues as $point)
                                @php
                                    $value = min((float)($point[1] ?? 0), 100);
                                    $height = ($value / $maxValue) * 100;
                                    $color = $value > 80 ? 'bg-red-500' : ($value > 60 ? 'bg-yellow-500' : 'bg-blue-500');
                                @endphp
                                <div class="flex-1 {{ $color }} rounded-t transition-all duration-300"
                                     style="height: {{ $height }}%"
                                     title="{{ number_format($value, 1) }}%"></div>
                            @endforeach
                        </div>
                    @endif
                </div>
            </div>
        </div>

        <!-- Memory Chart -->
        <div class="bg-white shadow rounded-lg">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
                <h3 class="text-lg leading-6 font-medium text-gray-900">Memory Usage Over Time</h3>
            </div>
            <div class="p-4">
                <div class="h-64 flex items-center justify-center" id="memory-chart">
                    @if($loading)
                        <div class="text-gray-400">Loading...</div>
                    @elseif(empty($memoryData['data']['result']))
                        <div class="text-gray-400">No data available</div>
                    @else
                        <div class="w-full h-full bg-gray-50 rounded flex items-end justify-around p-4 space-x-1">
                            @php
                                $values = $memoryData['data']['result'][0]['values'] ?? [];
                                $maxValue = 100;
                                $displayValues = array_slice($values, -30);
                            @endphp
                            @foreach($displayValues as $point)
                                @php
                                    $value = min((float)($point[1] ?? 0), 100);
                                    $height = ($value / $maxValue) * 100;
                                    $color = $value > 90 ? 'bg-red-500' : ($value > 75 ? 'bg-yellow-500' : 'bg-green-500');
                                @endphp
                                <div class="flex-1 {{ $color }} rounded-t transition-all duration-300"
                                     style="height: {{ $height }}%"
                                     title="{{ number_format($value, 1) }}%"></div>
                            @endforeach
                        </div>
                    @endif
                </div>
            </div>
        </div>
    </div>

    <!-- HTTP Stats (if available) -->
    @if(!empty($httpData['data']['result']))
        <div class="bg-white shadow rounded-lg mb-6">
            <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
                <h3 class="text-lg leading-6 font-medium text-gray-900">HTTP Request Rate</h3>
            </div>
            <div class="p-4">
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
                    @foreach($httpData['data']['result'] as $result)
                        @php
                            $status = $result['metric']['status'] ?? 'unknown';
                            $value = number_format((float)($result['value'][1] ?? 0), 2);
                            $colorClass = match(true) {
                                str_starts_with($status, '2') => 'text-green-600',
                                str_starts_with($status, '3') => 'text-blue-600',
                                str_starts_with($status, '4') => 'text-yellow-600',
                                str_starts_with($status, '5') => 'text-red-600',
                                default => 'text-gray-600',
                            };
                        @endphp
                        <div class="text-center">
                            <div class="text-2xl font-bold {{ $colorClass }}">{{ $value }}</div>
                            <div class="text-sm text-gray-500">{{ $status }} req/s</div>
                        </div>
                    @endforeach
                </div>
            </div>
        </div>
    @endif

    <!-- Quick Links -->
    <div class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
            <h3 class="text-lg leading-6 font-medium text-gray-900">Quick Links</h3>
        </div>
        <div class="p-4">
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <a href="{{ config('chom.observability.grafana_url', '#') }}"
                   target="_blank"
                   class="flex items-center p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition">
                    <div class="flex-shrink-0 bg-orange-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
                        </svg>
                    </div>
                    <div class="ml-4">
                        <div class="text-sm font-medium text-gray-900">Grafana</div>
                        <div class="text-sm text-gray-500">Advanced dashboards</div>
                    </div>
                </a>

                <a href="{{ config('chom.observability.prometheus_url', '#') }}"
                   target="_blank"
                   class="flex items-center p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition">
                    <div class="flex-shrink-0 bg-red-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
                        </svg>
                    </div>
                    <div class="ml-4">
                        <div class="text-sm font-medium text-gray-900">Prometheus</div>
                        <div class="text-sm text-gray-500">Query metrics</div>
                    </div>
                </a>

                <a href="{{ config('chom.observability.alertmanager_url', '#') }}"
                   target="_blank"
                   class="flex items-center p-4 bg-gray-50 rounded-lg hover:bg-gray-100 transition">
                    <div class="flex-shrink-0 bg-yellow-500 rounded-md p-3">
                        <svg class="h-6 w-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"/>
                        </svg>
                    </div>
                    <div class="ml-4">
                        <div class="text-sm font-medium text-gray-900">Alertmanager</div>
                        <div class="text-sm text-gray-500">Manage alerts</div>
                    </div>
                </a>
            </div>
        </div>
    </div>
</div>
