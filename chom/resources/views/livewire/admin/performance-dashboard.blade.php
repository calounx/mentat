<div class="p-6" wire:poll.{{ $refreshInterval }}ms="refresh">
    <div class="mb-6">
        <h2 class="text-2xl font-bold text-gray-900 dark:text-white">Performance Dashboard</h2>
        <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">Real-time application performance metrics</p>
    </div>

    <!-- Application Metrics -->
    <div class="mb-6">
        <h3 class="text-lg font-semibold mb-4 text-gray-800 dark:text-gray-200">Application Metrics</h3>
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <div class="text-sm text-gray-500 dark:text-gray-400">Environment</div>
                <div class="mt-2 text-2xl font-semibold text-gray-900 dark:text-white">
                    {{ $metrics['environment'] ?? 'N/A' }}
                </div>
            </div>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <div class="text-sm text-gray-500 dark:text-gray-400">Laravel Version</div>
                <div class="mt-2 text-2xl font-semibold text-gray-900 dark:text-white">
                    {{ $metrics['laravel_version'] ?? 'N/A' }}
                </div>
            </div>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <div class="text-sm text-gray-500 dark:text-gray-400">Avg Response Time</div>
                <div class="mt-2 text-2xl font-semibold text-gray-900 dark:text-white">
                    {{ $metrics['avg_response_time'] ?? 'N/A' }}
                </div>
            </div>

            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <div class="text-sm text-gray-500 dark:text-gray-400">Debug Mode</div>
                <div class="mt-2 text-2xl font-semibold {{ $metrics['debug_mode'] === 'Enabled' ? 'text-yellow-600' : 'text-green-600' }}">
                    {{ $metrics['debug_mode'] ?? 'N/A' }}
                </div>
            </div>
        </div>
    </div>

    <!-- System Metrics -->
    <div class="mb-6">
        <h3 class="text-lg font-semibold mb-4 text-gray-800 dark:text-gray-200">System Resources</h3>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <!-- Memory -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <h4 class="font-semibold mb-3 text-gray-900 dark:text-white">Memory Usage</h4>
                <div class="space-y-2">
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Current:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['memory']['current'] ?? 'N/A' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Peak:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['memory']['peak'] ?? 'N/A' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Limit:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['memory']['limit'] ?? 'N/A' }}</span>
                    </div>
                    <div class="mt-2">
                        <div class="flex justify-between text-xs mb-1">
                            <span class="text-gray-600 dark:text-gray-400">Usage</span>
                            <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['memory']['percentage'] ?? 0 }}%</span>
                        </div>
                        <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                            <div class="bg-blue-600 h-2 rounded-full transition-all duration-500" style="width: {{ $systemMetrics['memory']['percentage'] ?? 0 }}%"></div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Disk -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <h4 class="font-semibold mb-3 text-gray-900 dark:text-white">Disk Usage</h4>
                <div class="space-y-2">
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Used:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['disk']['used'] ?? 'N/A' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Free:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['disk']['free'] ?? 'N/A' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Total:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['disk']['total'] ?? 'N/A' }}</span>
                    </div>
                    <div class="mt-2">
                        <div class="flex justify-between text-xs mb-1">
                            <span class="text-gray-600 dark:text-gray-400">Usage</span>
                            <span class="font-medium text-gray-900 dark:text-white">{{ $systemMetrics['disk']['percentage'] ?? 0 }}%</span>
                        </div>
                        <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                            <div class="{{ $systemMetrics['disk']['percentage'] > 80 ? 'bg-red-600' : 'bg-green-600' }} h-2 rounded-full transition-all duration-500" style="width: {{ $systemMetrics['disk']['percentage'] ?? 0 }}%"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Database & Cache -->
    <div class="mb-6">
        <h3 class="text-lg font-semibold mb-4 text-gray-800 dark:text-gray-200">Infrastructure</h3>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <!-- Database -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <h4 class="font-semibold mb-3 text-gray-900 dark:text-white">Database</h4>
                <div class="space-y-2">
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Status:</span>
                        <span class="font-medium {{ $databaseMetrics['connected'] ?? false ? 'text-green-600' : 'text-red-600' }}">
                            {{ $databaseMetrics['connected'] ?? false ? 'Connected' : 'Disconnected' }}
                        </span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Driver:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $databaseMetrics['driver'] ?? 'N/A' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Database:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $databaseMetrics['database'] ?? 'N/A' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Size:</span>
                        <span class="font-medium text-gray-900 dark:text-white">{{ $databaseMetrics['size'] ?? 'N/A' }}</span>
                    </div>
                </div>
            </div>

            <!-- Cache/Redis -->
            <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
                <h4 class="font-semibold mb-3 text-gray-900 dark:text-white">Cache ({{ $cacheMetrics['driver'] ?? 'N/A' }})</h4>
                <div class="space-y-2">
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-600 dark:text-gray-400">Status:</span>
                        <span class="font-medium {{ $cacheMetrics['connected'] ?? false ? 'text-green-600' : 'text-red-600' }}">
                            {{ $cacheMetrics['connected'] ?? false ? 'Connected' : 'Disconnected' }}
                        </span>
                    </div>
                    @if(isset($cacheMetrics['info']) && is_array($cacheMetrics['info']))
                        <div class="flex justify-between text-sm">
                            <span class="text-gray-600 dark:text-gray-400">Memory Used:</span>
                            <span class="font-medium text-gray-900 dark:text-white">{{ $cacheMetrics['info']['used_memory'] ?? 'N/A' }}</span>
                        </div>
                        <div class="flex justify-between text-sm">
                            <span class="text-gray-600 dark:text-gray-400">Hit Rate:</span>
                            <span class="font-medium text-gray-900 dark:text-white">{{ $cacheMetrics['info']['hit_rate'] ?? 'N/A' }}</span>
                        </div>
                        <div class="flex justify-between text-sm">
                            <span class="text-gray-600 dark:text-gray-400">Connected Clients:</span>
                            <span class="font-medium text-gray-900 dark:text-white">{{ $cacheMetrics['info']['connected_clients'] ?? 'N/A' }}</span>
                        </div>
                    @endif
                </div>
            </div>
        </div>
    </div>

    <!-- Queue -->
    <div class="mb-6">
        <h3 class="text-lg font-semibold mb-4 text-gray-800 dark:text-gray-200">Queue Configuration</h3>
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow p-4">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                    <div class="text-sm text-gray-600 dark:text-gray-400">Driver</div>
                    <div class="mt-1 font-medium text-gray-900 dark:text-white">{{ $queueMetrics['driver'] ?? 'N/A' }}</div>
                </div>
                <div>
                    <div class="text-sm text-gray-600 dark:text-gray-400">Connection</div>
                    <div class="mt-1 font-medium text-gray-900 dark:text-white">{{ $queueMetrics['connection'] ?? 'N/A' }}</div>
                </div>
                <div>
                    <div class="text-sm text-gray-600 dark:text-gray-400">Queue Name</div>
                    <div class="mt-1 font-medium text-gray-900 dark:text-white">{{ $queueMetrics['queue'] ?? 'N/A' }}</div>
                </div>
            </div>
        </div>
    </div>

    <!-- Auto-refresh indicator -->
    <div class="text-xs text-gray-500 dark:text-gray-400 text-center">
        Auto-refreshing every {{ $refreshInterval / 1000 }} seconds
    </div>
</div>
