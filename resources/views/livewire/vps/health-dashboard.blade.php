<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">VPS Health Dashboard</h1>
            <p class="mt-1 text-sm text-gray-600">Monitor server health, stats, and security status.</p>
        </div>
        @if($selectedVpsId)
            <div class="mt-4 sm:mt-0 flex space-x-3">
                <button wire:click="refresh"
                        wire:loading.attr="disabled"
                        class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50">
                    <svg wire:loading.class="animate-spin" class="h-5 w-5 mr-2 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                    </svg>
                    Refresh
                </button>
                <button wire:click="runSecurityAudit"
                        wire:loading.attr="disabled"
                        class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50">
                    <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                    </svg>
                    Security Audit
                </button>
            </div>
        @endif
    </div>

    <!-- Flash Messages -->
    @if(session('success'))
        <div class="mb-4 bg-green-50 border-l-4 border-green-400 p-4">
            <p class="text-sm text-green-700">{{ session('success') }}</p>
        </div>
    @endif

    @if($error)
        <div class="mb-4 bg-red-50 border-l-4 border-red-400 p-4">
            <p class="text-sm text-red-700">{{ $error }}</p>
        </div>
    @endif

    <!-- VPS Selector -->
    <div class="bg-white shadow rounded-lg mb-6">
        <div class="px-4 py-4 sm:px-6">
            <label for="vps-select" class="block text-sm font-medium text-gray-700 mb-2">Select VPS Server</label>
            <select id="vps-select"
                    wire:model.live="selectedVpsId"
                    wire:change="selectVps($event.target.value)"
                    class="w-full max-w-md border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                <option value="">Choose a VPS server...</option>
                @foreach($vpsServers as $vps)
                    <option value="{{ $vps->id }}">{{ $vps->hostname }} ({{ $vps->ip_address }})</option>
                @endforeach
            </select>
            @if($vpsServers->isEmpty())
                <p class="mt-2 text-sm text-gray-500">No VPS servers available for your account.</p>
            @endif
        </div>
    </div>

    @if($selectedVpsId)
        <!-- Loading State -->
        <div wire:loading wire:target="loadVpsData,selectVps,refresh,runSecurityAudit" class="mb-6">
            <div class="bg-white shadow rounded-lg p-8">
                <div class="flex items-center justify-center">
                    <svg class="animate-spin h-8 w-8 text-blue-600" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span class="ml-3 text-gray-600">Loading VPS data...</span>
                </div>
            </div>
        </div>

        <div wire:loading.remove wire:target="loadVpsData,selectVps,refresh,runSecurityAudit">
            @if($lastUpdated)
                <p class="text-sm text-gray-500 mb-4">Last updated: {{ $lastUpdated }}</p>
            @endif

            <!-- Health Status Cards -->
            <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-6">
                <!-- Overall Health -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                @php
                                    $healthStatus = $healthData['status'] ?? 'unknown';
                                    $healthColor = match($healthStatus) {
                                        'healthy' => 'text-green-400',
                                        'warning' => 'text-yellow-400',
                                        'critical', 'unhealthy' => 'text-red-400',
                                        default => 'text-gray-400',
                                    };
                                @endphp
                                <svg class="h-6 w-6 {{ $healthColor }}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">Health Status</dt>
                                    <dd class="flex items-baseline">
                                        <div class="text-2xl font-semibold text-gray-900 capitalize">{{ $healthStatus }}</div>
                                    </dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- CPU Usage -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                <svg class="h-6 w-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">CPU Usage</dt>
                                    <dd class="flex items-baseline">
                                        <div class="text-2xl font-semibold text-gray-900">
                                            {{ $statsData['cpu_percent'] ?? $dashboardData['cpu_percent'] ?? 'N/A' }}%
                                        </div>
                                    </dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Memory Usage -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                <svg class="h-6 w-6 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">Memory Usage</dt>
                                    <dd class="flex items-baseline">
                                        <div class="text-2xl font-semibold text-gray-900">
                                            {{ $statsData['memory_percent'] ?? $dashboardData['memory_percent'] ?? 'N/A' }}%
                                        </div>
                                    </dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Disk Usage -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                <svg class="h-6 w-6 text-orange-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">Disk Usage</dt>
                                    <dd class="flex items-baseline">
                                        <div class="text-2xl font-semibold text-gray-900">
                                            {{ $statsData['disk_percent'] ?? $dashboardData['disk_percent'] ?? 'N/A' }}%
                                        </div>
                                    </dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Dashboard Details & Stats -->
            <div class="grid grid-cols-1 gap-6 lg:grid-cols-2 mb-6">
                <!-- System Information -->
                <div class="bg-white shadow rounded-lg">
                    <div class="px-4 py-5 sm:p-6">
                        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">System Information</h3>
                        <dl class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                            <div>
                                <dt class="text-sm font-medium text-gray-500">Uptime</dt>
                                <dd class="mt-1 text-sm text-gray-900">{{ $dashboardData['uptime'] ?? $statsData['uptime'] ?? 'N/A' }}</dd>
                            </div>
                            <div>
                                <dt class="text-sm font-medium text-gray-500">Load Average</dt>
                                <dd class="mt-1 text-sm text-gray-900">{{ $statsData['load_average'] ?? $dashboardData['load_average'] ?? 'N/A' }}</dd>
                            </div>
                            <div>
                                <dt class="text-sm font-medium text-gray-500">Total Memory</dt>
                                <dd class="mt-1 text-sm text-gray-900">{{ $statsData['memory_total'] ?? $dashboardData['memory_total'] ?? 'N/A' }}</dd>
                            </div>
                            <div>
                                <dt class="text-sm font-medium text-gray-500">Used Memory</dt>
                                <dd class="mt-1 text-sm text-gray-900">{{ $statsData['memory_used'] ?? $dashboardData['memory_used'] ?? 'N/A' }}</dd>
                            </div>
                            <div>
                                <dt class="text-sm font-medium text-gray-500">Total Disk</dt>
                                <dd class="mt-1 text-sm text-gray-900">{{ $statsData['disk_total'] ?? $dashboardData['disk_total'] ?? 'N/A' }}</dd>
                            </div>
                            <div>
                                <dt class="text-sm font-medium text-gray-500">Used Disk</dt>
                                <dd class="mt-1 text-sm text-gray-900">{{ $statsData['disk_used'] ?? $dashboardData['disk_used'] ?? 'N/A' }}</dd>
                            </div>
                        </dl>
                    </div>
                </div>

                <!-- Services Status -->
                <div class="bg-white shadow rounded-lg">
                    <div class="px-4 py-5 sm:p-6">
                        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Services Status</h3>
                        @if(!empty($dashboardData['services']) || !empty($healthData['services']))
                            @php $services = $dashboardData['services'] ?? $healthData['services'] ?? []; @endphp
                            <ul class="divide-y divide-gray-200">
                                @foreach($services as $serviceName => $serviceStatus)
                                    <li class="py-3 flex items-center justify-between">
                                        <span class="text-sm font-medium text-gray-900 capitalize">{{ $serviceName }}</span>
                                        @php
                                            $status = is_array($serviceStatus) ? ($serviceStatus['status'] ?? 'unknown') : $serviceStatus;
                                            $statusColor = match($status) {
                                                'running', 'active', 'healthy' => 'bg-green-100 text-green-800',
                                                'stopped', 'inactive' => 'bg-red-100 text-red-800',
                                                'warning' => 'bg-yellow-100 text-yellow-800',
                                                default => 'bg-gray-100 text-gray-800',
                                            };
                                        @endphp
                                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusColor }}">
                                            {{ ucfirst($status) }}
                                        </span>
                                    </li>
                                @endforeach
                            </ul>
                        @else
                            <p class="text-sm text-gray-500">No service data available.</p>
                        @endif
                    </div>
                </div>
            </div>

            <!-- Security Audit Results -->
            @if(!empty($securityAuditData))
                <div class="bg-white shadow rounded-lg">
                    <div class="px-4 py-5 sm:p-6">
                        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Security Audit Results</h3>

                        @if(isset($securityAuditData['score']))
                            <div class="mb-4">
                                <div class="flex items-center justify-between mb-2">
                                    <span class="text-sm font-medium text-gray-700">Security Score</span>
                                    <span class="text-lg font-semibold {{ $securityAuditData['score'] >= 80 ? 'text-green-600' : ($securityAuditData['score'] >= 60 ? 'text-yellow-600' : 'text-red-600') }}">
                                        {{ $securityAuditData['score'] }}/100
                                    </span>
                                </div>
                                <div class="w-full bg-gray-200 rounded-full h-2.5">
                                    <div class="h-2.5 rounded-full {{ $securityAuditData['score'] >= 80 ? 'bg-green-600' : ($securityAuditData['score'] >= 60 ? 'bg-yellow-500' : 'bg-red-600') }}"
                                         style="width: {{ $securityAuditData['score'] }}%"></div>
                                </div>
                            </div>
                        @endif

                        @if(!empty($securityAuditData['issues']))
                            <div class="mt-4">
                                <h4 class="text-sm font-medium text-gray-700 mb-2">Issues Found</h4>
                                <ul class="space-y-2">
                                    @foreach($securityAuditData['issues'] as $issue)
                                        <li class="flex items-start">
                                            @php
                                                $severity = $issue['severity'] ?? 'info';
                                                $severityColor = match($severity) {
                                                    'critical', 'high' => 'text-red-500',
                                                    'medium', 'warning' => 'text-yellow-500',
                                                    'low', 'info' => 'text-blue-500',
                                                    default => 'text-gray-500',
                                                };
                                            @endphp
                                            <svg class="h-5 w-5 {{ $severityColor }} mr-2 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                                                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                                            </svg>
                                            <div>
                                                <p class="text-sm text-gray-900">{{ $issue['message'] ?? $issue }}</p>
                                                @if(isset($issue['recommendation']))
                                                    <p class="text-xs text-gray-500 mt-1">{{ $issue['recommendation'] }}</p>
                                                @endif
                                            </div>
                                        </li>
                                    @endforeach
                                </ul>
                            </div>
                        @else
                            <p class="text-sm text-green-600">No security issues found.</p>
                        @endif

                        @if(!empty($securityAuditData['checks']))
                            <div class="mt-4">
                                <h4 class="text-sm font-medium text-gray-700 mb-2">Security Checks</h4>
                                <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
                                    @foreach($securityAuditData['checks'] as $checkName => $checkResult)
                                        <div class="flex items-center justify-between p-2 bg-gray-50 rounded">
                                            <span class="text-sm text-gray-700 capitalize">{{ str_replace('_', ' ', $checkName) }}</span>
                                            @if($checkResult === true || $checkResult === 'pass' || $checkResult === 'passed')
                                                <svg class="h-5 w-5 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                                                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                                                </svg>
                                            @else
                                                <svg class="h-5 w-5 text-red-500" fill="currentColor" viewBox="0 0 20 20">
                                                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                                                </svg>
                                            @endif
                                        </div>
                                    @endforeach
                                </div>
                            </div>
                        @endif
                    </div>
                </div>
            @endif
        </div>
    @else
        <!-- No VPS Selected -->
        <div class="bg-white shadow rounded-lg">
            <div class="px-6 py-12 text-center">
                <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"/>
                </svg>
                <h3 class="mt-2 text-sm font-medium text-gray-900">No VPS Selected</h3>
                <p class="mt-1 text-sm text-gray-500">Select a VPS server from the dropdown above to view its health dashboard.</p>
            </div>
        </div>
    @endif
</div>
