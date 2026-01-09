<div>
    <!-- Header with Elegant Typography -->
    <div class="mb-8">
        <h1 class="font-display text-4xl font-semibold text-stone-900 mb-2">Dashboard</h1>
        <p class="text-base text-stone-600">
            Welcome back! Here's an overview of your hosting infrastructure.
        </p>
    </div>

    @if($tenant)
        <!-- Stats Grid with Staggered Animation -->
        <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4 mb-8">
            <!-- Total Sites -->
            <div class="card stagger-item hover-lift">
                <div class="p-6">
                    <div class="flex items-center justify-between mb-4">
                        <div class="p-3 rounded-xl bg-gradient-to-br from-sapphire-100 to-sapphire-50">
                            <svg class="h-6 w-6 text-sapphire-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                            </svg>
                        </div>
                        <div class="text-right">
                            <div class="font-display text-3xl font-semibold text-stone-900">{{ $stats['total_sites'] }}</div>
                        </div>
                    </div>
                    <div>
                        <div class="text-sm font-medium text-stone-600 uppercase tracking-wider">Total Sites</div>
                        <p class="text-xs text-stone-500 mt-1">All managed sites</p>
                    </div>
                </div>
            </div>

            <!-- Active Sites -->
            <div class="card stagger-item hover-lift">
                <div class="p-6">
                    <div class="flex items-center justify-between mb-4">
                        <div class="p-3 rounded-xl bg-gradient-to-br from-emerald-100 to-emerald-50">
                            <svg class="h-6 w-6 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                            </svg>
                        </div>
                        <div class="text-right">
                            <div class="font-display text-3xl font-semibold text-emerald-700">{{ $stats['active_sites'] }}</div>
                        </div>
                    </div>
                    <div>
                        <div class="text-sm font-medium text-stone-600 uppercase tracking-wider">Active Sites</div>
                        <p class="text-xs text-stone-500 mt-1">Healthy & running</p>
                    </div>
                </div>
            </div>

            <!-- Storage Used -->
            <div class="card stagger-item hover-lift">
                <div class="p-6">
                    <div class="flex items-center justify-between mb-4">
                        <div class="p-3 rounded-xl bg-gradient-to-br from-sapphire-100 to-sapphire-50">
                            <svg class="h-6 w-6 text-sapphire-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"/>
                            </svg>
                        </div>
                        <div class="text-right">
                            <div class="font-display text-3xl font-semibold text-stone-900">
                                {{ number_format($stats['storage_used_mb'] / 1024, 1) }}
                            </div>
                        </div>
                    </div>
                    <div>
                        <div class="text-sm font-medium text-stone-600 uppercase tracking-wider">Storage (GB)</div>
                        <p class="text-xs text-stone-500 mt-1">Total disk usage</p>
                    </div>
                </div>
            </div>

            <!-- SSL Expiring -->
            <div class="card stagger-item hover-lift">
                <div class="p-6">
                    <div class="flex items-center justify-between mb-4">
                        <div class="p-3 rounded-xl bg-gradient-to-br from-{{ $stats['ssl_expiring_soon'] > 0 ? 'champagne' : 'stone' }}-100 to-{{ $stats['ssl_expiring_soon'] > 0 ? 'champagne' : 'stone' }}-50">
                            <svg class="h-6 w-6 text-{{ $stats['ssl_expiring_soon'] > 0 ? 'champagne' : 'stone' }}-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                            </svg>
                        </div>
                        <div class="text-right">
                            <div class="font-display text-3xl font-semibold text-{{ $stats['ssl_expiring_soon'] > 0 ? 'champagne' : 'stone' }}-700">
                                {{ $stats['ssl_expiring_soon'] }}
                            </div>
                        </div>
                    </div>
                    <div>
                        <div class="text-sm font-medium text-stone-600 uppercase tracking-wider">SSL Expiring</div>
                        <p class="text-xs text-stone-500 mt-1">Needs attention soon</p>
                    </div>
                </div>
            </div>
        </div>

        <!-- Quick Actions & Recent Sites Grid -->
        <div class="grid grid-cols-1 gap-6 lg:grid-cols-2 mb-8">
            <!-- Quick Actions -->
            <div class="card stagger-item">
                <div class="card-header">
                    <h3 class="font-display text-xl font-semibold text-stone-900">Quick Actions</h3>
                    <p class="text-sm text-stone-600 mt-1">Common operations</p>
                </div>
                <div class="card-body">
                    <div class="grid grid-cols-2 gap-4">
                        <a href="{{ route('sites.create') }}"
                           class="btn btn-primary group">
                            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
                            </svg>
                            <span>New Site</span>
                        </a>
                        <a href="{{ route('sites.index') }}"
                           class="btn btn-secondary group">
                            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 10h16M4 14h16M4 18h16"/>
                            </svg>
                            <span>View All Sites</span>
                        </a>
                    </div>
                </div>
            </div>

            <!-- Recent Sites -->
            <div class="card stagger-item">
                <div class="card-header">
                    <h3 class="font-display text-xl font-semibold text-stone-900">Recent Sites</h3>
                    <p class="text-sm text-stone-600 mt-1">Recently created or updated</p>
                </div>
                <div class="card-body">
                    @if(count($recentSites) > 0)
                        <ul class="divide-y divide-stone-100">
                            @foreach($recentSites as $site)
                                <li class="py-3 flex items-center justify-between hover:bg-stone-50 -mx-6 px-6 transition-colors duration-200">
                                    <div class="flex items-center gap-3 flex-1 min-w-0">
                                        <div class="flex-shrink-0">
                                            <div class="h-10 w-10 rounded-lg bg-gradient-to-br from-{{ $site['status'] === 'active' ? 'emerald' : 'stone' }}-500 to-{{ $site['status'] === 'active' ? 'emerald' : 'stone' }}-600 flex items-center justify-center shadow-md">
                                                <span class="text-sm font-semibold text-white">
                                                    {{ strtoupper(substr($site['domain'], 0, 1)) }}
                                                </span>
                                            </div>
                                        </div>
                                        <div class="flex-1 min-w-0">
                                            <p class="text-sm font-medium text-stone-900 truncate">{{ $site['domain'] }}</p>
                                            <p class="text-xs text-stone-500">{{ $site['created_at'] }}</p>
                                        </div>
                                    </div>
                                    <div class="flex items-center gap-2 flex-shrink-0">
                                        @if($site['ssl_enabled'])
                                            <span class="inline-flex items-center px-2 py-1 rounded-md text-xs font-medium bg-emerald-100 text-emerald-800 border border-emerald-200">
                                                SSL
                                            </span>
                                        @endif
                                        <span class="status-badge status-{{ $site['status'] === 'active' ? 'healthy' : 'info' }}">
                                            {{ ucfirst($site['status']) }}
                                        </span>
                                    </div>
                                </li>
                            @endforeach
                        </ul>
                    @else
                        <div class="text-center py-8">
                            <svg class="mx-auto h-12 w-12 text-stone-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"/>
                            </svg>
                            <p class="mt-2 text-sm text-stone-500">No sites created yet</p>
                            <a href="{{ route('sites.create') }}" class="inline-block mt-3 text-sm text-emerald-700 hover:text-emerald-800 font-medium">
                                Create your first site →
                            </a>
                        </div>
                    @endif
                </div>
            </div>
        </div>

        <!-- Current Plan -->
        <div class="card stagger-item">
            <div class="card-body">
                <div class="flex items-center justify-between">
                    <div class="flex items-center gap-4">
                        <div class="p-4 rounded-xl bg-gradient-to-br from-sapphire-100 to-sapphire-50">
                            <svg class="h-8 w-8 text-sapphire-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z"/>
                            </svg>
                        </div>
                        <div>
                            <h3 class="font-display text-xl font-semibold text-stone-900">Current Plan</h3>
                            <p class="text-sm text-stone-600 mt-1">
                                You're on the <span class="font-medium text-sapphire-700">{{ ucfirst($tenant->tier) }}</span> tier
                            </p>
                        </div>
                    </div>
                    <div>
                        <span class="inline-flex items-center px-4 py-2 rounded-full text-sm font-medium bg-gradient-to-r from-sapphire-100 to-sapphire-50 text-sapphire-800 border border-sapphire-200">
                            {{ ucfirst($tenant->tier) }} Plan
                        </span>
                    </div>
                </div>
            </div>
        </div>
    @else
        <!-- No Tenant Warning -->
        <div class="card">
            <div class="card-body">
                <div class="flex items-start gap-4">
                    <div class="flex-shrink-0">
                        <div class="p-3 rounded-xl bg-gradient-to-br from-champagne-100 to-champagne-50">
                            <svg class="h-6 w-6 text-champagne-600" viewBox="0 0 20 20" fill="currentColor">
                                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                            </svg>
                        </div>
                    </div>
                    <div class="flex-1">
                        <h3 class="font-display text-lg font-semibold text-champagne-900">Tenant Configuration Required</h3>
                        <p class="mt-1 text-sm text-champagne-700">
                            No tenant has been configured for your account. Please contact support to complete your setup.
                        </p>
                        <div class="mt-4">
                            <a href="mailto:support@example.com" class="btn btn-primary">
                                <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/>
                                </svg>
                                Contact Support
                            </a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    @endif
</div>
