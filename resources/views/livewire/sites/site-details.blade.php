<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <div class="flex items-center">
                <a href="{{ route('sites.index') }}" class="mr-4 text-gray-400 hover:text-gray-600">
                    <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/>
                    </svg>
                </a>
                <div>
                    <h1 class="text-2xl font-bold text-gray-900">{{ $site?->domain ?? 'Site Details' }}</h1>
                    <p class="mt-1 text-sm text-gray-600">Detailed site information and SSL status.</p>
                </div>
            </div>
        </div>
        @if($site)
            <div class="mt-4 sm:mt-0 flex space-x-3">
                <button wire:click="refresh"
                        wire:loading.attr="disabled"
                        class="inline-flex items-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50">
                    <svg wire:loading.class="animate-spin" class="h-5 w-5 mr-2 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
                    </svg>
                    Refresh
                </button>
                <a href="{{ $site->getUrl() }}" target="_blank"
                   class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                    <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
                    </svg>
                    Visit Site
                </a>
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

    @if($site)
        <!-- Loading State -->
        <div wire:loading wire:target="loadSiteData,refresh" class="mb-6">
            <div class="bg-white shadow rounded-lg p-8">
                <div class="flex items-center justify-center">
                    <svg class="animate-spin h-8 w-8 text-blue-600" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span class="ml-3 text-gray-600">Loading site data...</span>
                </div>
            </div>
        </div>

        <div wire:loading.remove wire:target="loadSiteData,refresh">
            @if($lastUpdated)
                <p class="text-sm text-gray-500 mb-4">Last updated: {{ $lastUpdated }}</p>
            @endif

            <!-- Site Overview Cards -->
            <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4 mb-6">
                <!-- Status -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                @php
                                    $statusColor = match($site->status) {
                                        'active' => 'text-green-400',
                                        'disabled' => 'text-gray-400',
                                        'creating' => 'text-yellow-400',
                                        'failed' => 'text-red-400',
                                        default => 'text-gray-400',
                                    };
                                @endphp
                                <svg class="h-6 w-6 {{ $statusColor }}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">Status</dt>
                                    <dd class="text-2xl font-semibold text-gray-900 capitalize">{{ $site->status }}</dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Site Type -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                <svg class="h-6 w-6 text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">Site Type</dt>
                                    <dd class="text-2xl font-semibold text-gray-900 capitalize">{{ $site->site_type }}</dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- PHP Version -->
                <div class="bg-white overflow-hidden shadow rounded-lg">
                    <div class="p-5">
                        <div class="flex items-center">
                            <div class="flex-shrink-0">
                                <svg class="h-6 w-6 text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 20l4-16m4 4l4 4-4 4M6 16l-4-4 4-4"/>
                                </svg>
                            </div>
                            <div class="ml-5 w-0 flex-1">
                                <dl>
                                    <dt class="text-sm font-medium text-gray-500 truncate">PHP Version</dt>
                                    <dd class="text-2xl font-semibold text-gray-900">{{ $site->php_version }}</dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Storage -->
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
                                    <dt class="text-sm font-medium text-gray-500 truncate">Storage Used</dt>
                                    <dd class="text-2xl font-semibold text-gray-900">
                                        {{ number_format(($site->storage_used_mb ?? 0) / 1024, 2) }} GB
                                    </dd>
                                </dl>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Site Information & SSL Status -->
            <div class="grid grid-cols-1 gap-6 lg:grid-cols-2 mb-6">
                <!-- Site Information from VPS -->
                <div class="bg-white shadow rounded-lg">
                    <div class="px-4 py-5 sm:p-6">
                        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Site Information</h3>
                        @if(!empty($siteInfo))
                            <dl class="grid grid-cols-1 gap-4">
                                @if(isset($siteInfo['document_root']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Document Root</dt>
                                        <dd class="mt-1 text-sm text-gray-900 font-mono">{{ $siteInfo['document_root'] }}</dd>
                                    </div>
                                @endif
                                @if(isset($siteInfo['nginx_config']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Nginx Config</dt>
                                        <dd class="mt-1 text-sm text-gray-900 font-mono">{{ $siteInfo['nginx_config'] }}</dd>
                                    </div>
                                @endif
                                @if(isset($siteInfo['php_fpm_pool']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">PHP-FPM Pool</dt>
                                        <dd class="mt-1 text-sm text-gray-900 font-mono">{{ $siteInfo['php_fpm_pool'] }}</dd>
                                    </div>
                                @endif
                                @if(isset($siteInfo['database']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Database</dt>
                                        <dd class="mt-1 text-sm text-gray-900">{{ $siteInfo['database']['name'] ?? 'N/A' }}</dd>
                                    </div>
                                @endif
                                @if(isset($siteInfo['disk_usage']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Disk Usage</dt>
                                        <dd class="mt-1 text-sm text-gray-900">{{ $siteInfo['disk_usage'] }}</dd>
                                    </div>
                                @endif
                                @if(isset($siteInfo['created_at']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Created At</dt>
                                        <dd class="mt-1 text-sm text-gray-900">{{ $siteInfo['created_at'] }}</dd>
                                    </div>
                                @endif
                                @if(isset($siteInfo['last_modified']))
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Last Modified</dt>
                                        <dd class="mt-1 text-sm text-gray-900">{{ $siteInfo['last_modified'] }}</dd>
                                    </div>
                                @endif
                            </dl>
                        @else
                            <p class="text-sm text-gray-500">No additional site information available from VPS.</p>
                        @endif
                    </div>
                </div>

                <!-- SSL Status -->
                <div class="bg-white shadow rounded-lg">
                    <div class="px-4 py-5 sm:p-6">
                        <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">SSL Certificate</h3>

                        @if($site->ssl_enabled)
                            <div class="flex items-center mb-4">
                                <svg class="h-8 w-8 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                </svg>
                                <span class="ml-2 text-lg font-medium text-green-600">SSL Enabled</span>
                            </div>

                            <dl class="grid grid-cols-1 gap-4">
                                @if($site->ssl_expires_at)
                                    <div>
                                        <dt class="text-sm font-medium text-gray-500">Expires</dt>
                                        <dd class="mt-1 text-sm {{ $site->isSslExpiringSoon() ? 'text-yellow-600 font-medium' : ($site->isSslExpired() ? 'text-red-600 font-medium' : 'text-gray-900') }}">
                                            {{ $site->ssl_expires_at->format('M d, Y') }}
                                            @if($site->isSslExpired())
                                                (Expired)
                                            @elseif($site->isSslExpiringSoon())
                                                ({{ $site->ssl_expires_at->diffForHumans() }})
                                            @endif
                                        </dd>
                                    </div>
                                @endif

                                @if(!empty($sslStatus))
                                    @if(isset($sslStatus['issuer']))
                                        <div>
                                            <dt class="text-sm font-medium text-gray-500">Issuer</dt>
                                            <dd class="mt-1 text-sm text-gray-900">{{ $sslStatus['issuer'] }}</dd>
                                        </div>
                                    @endif
                                    @if(isset($sslStatus['valid_from']))
                                        <div>
                                            <dt class="text-sm font-medium text-gray-500">Valid From</dt>
                                            <dd class="mt-1 text-sm text-gray-900">{{ $sslStatus['valid_from'] }}</dd>
                                        </div>
                                    @endif
                                    @if(isset($sslStatus['valid_until']))
                                        <div>
                                            <dt class="text-sm font-medium text-gray-500">Valid Until</dt>
                                            <dd class="mt-1 text-sm text-gray-900">{{ $sslStatus['valid_until'] }}</dd>
                                        </div>
                                    @endif
                                    @if(isset($sslStatus['type']))
                                        <div>
                                            <dt class="text-sm font-medium text-gray-500">Certificate Type</dt>
                                            <dd class="mt-1 text-sm text-gray-900">{{ $sslStatus['type'] }}</dd>
                                        </div>
                                    @endif
                                    @if(isset($sslStatus['auto_renew']))
                                        <div>
                                            <dt class="text-sm font-medium text-gray-500">Auto Renew</dt>
                                            <dd class="mt-1">
                                                @if($sslStatus['auto_renew'])
                                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                                        Enabled
                                                    </span>
                                                @else
                                                    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                                        Disabled
                                                    </span>
                                                @endif
                                            </dd>
                                        </div>
                                    @endif
                                @endif
                            </dl>
                        @else
                            <div class="flex items-center text-gray-500">
                                <svg class="h-8 w-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                                </svg>
                                <span class="ml-2 text-lg font-medium">SSL Not Enabled</span>
                            </div>
                            <p class="mt-4 text-sm text-gray-500">
                                SSL certificate is not configured for this site. Consider enabling SSL for secure connections.
                            </p>
                        @endif
                    </div>
                </div>
            </div>

            <!-- Server Information -->
            <div class="bg-white shadow rounded-lg">
                <div class="px-4 py-5 sm:p-6">
                    <h3 class="text-lg leading-6 font-medium text-gray-900 mb-4">Server Information</h3>
                    <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                        <div>
                            <dt class="text-sm font-medium text-gray-500">Hostname</dt>
                            <dd class="mt-1 text-sm text-gray-900">{{ $site->vpsServer?->hostname ?? 'N/A' }}</dd>
                        </div>
                        <div>
                            <dt class="text-sm font-medium text-gray-500">IP Address</dt>
                            <dd class="mt-1 text-sm text-gray-900 font-mono">{{ $site->vpsServer?->ip_address ?? 'N/A' }}</dd>
                        </div>
                        <div>
                            <dt class="text-sm font-medium text-gray-500">Region</dt>
                            <dd class="mt-1 text-sm text-gray-900">{{ $site->vpsServer?->region ?? 'N/A' }}</dd>
                        </div>
                    </dl>
                </div>
            </div>
        </div>
    @else
        <!-- Site Not Found -->
        <div class="bg-white shadow rounded-lg">
            <div class="px-6 py-12 text-center">
                <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                </svg>
                <h3 class="mt-2 text-sm font-medium text-gray-900">Site Not Found</h3>
                <p class="mt-1 text-sm text-gray-500">The requested site could not be found.</p>
                <div class="mt-6">
                    <a href="{{ route('sites.index') }}"
                       class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700">
                        Back to Sites
                    </a>
                </div>
            </div>
        </div>
    @endif
</div>
