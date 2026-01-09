<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">System Settings</h1>
            <p class="mt-1 text-sm text-gray-400">Configure global settings and view system information.</p>
        </div>
    </div>

    <!-- Flash Messages -->
    @if($success)
        <div class="mb-4 bg-green-900/50 border-l-4 border-green-500 p-4 rounded">
            <p class="text-sm text-green-200">{{ $success }}</p>
        </div>
    @endif

    @if($error)
        <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
            <p class="text-sm text-red-200">{{ $error }}</p>
        </div>
    @endif

    <div class="grid grid-cols-1 gap-6 lg:grid-cols-2">
        <!-- System Information -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">System Information</h3>
                <dl class="grid grid-cols-2 gap-4">
                    @foreach($systemInfo as $key => $value)
                        <div>
                            <dt class="text-xs font-medium text-gray-400">{{ ucwords(str_replace('_', ' ', $key)) }}</dt>
                            <dd class="mt-1 text-sm text-white">{{ $value }}</dd>
                        </div>
                    @endforeach
                </dl>
            </div>
        </div>

        <!-- Storage Stats -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">Storage</h3>
                <div class="mb-4">
                    <div class="flex justify-between text-sm mb-2">
                        <span class="text-gray-400">Used: {{ $storageStats['used'] }}</span>
                        <span class="text-gray-400">Free: {{ $storageStats['free'] }}</span>
                    </div>
                    <div class="w-full bg-gray-700 rounded-full h-4">
                        <div class="h-4 rounded-full {{ $storageStats['percent_used'] > 90 ? 'bg-red-500' : ($storageStats['percent_used'] > 75 ? 'bg-yellow-500' : 'bg-blue-500') }}"
                             style="width: {{ $storageStats['percent_used'] }}%"></div>
                    </div>
                    <div class="flex justify-between text-xs text-gray-500 mt-1">
                        <span>{{ $storageStats['percent_used'] }}% used</span>
                        <span>Total: {{ $storageStats['total'] }}</span>
                    </div>
                </div>
            </div>
        </div>

        <!-- Database Info -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">Database</h3>
                <dl class="space-y-3">
                    @foreach($databaseStats as $key => $value)
                        <div class="flex justify-between">
                            <dt class="text-sm text-gray-400">{{ ucwords(str_replace('_', ' ', $key)) }}</dt>
                            <dd class="text-sm text-white">{{ $value }}</dd>
                        </div>
                    @endforeach
                </dl>
            </div>
        </div>

        <!-- Application Settings (Read-only display) -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">Application Settings</h3>
                <dl class="space-y-3">
                    <div class="flex justify-between">
                        <dt class="text-sm text-gray-400">App Name</dt>
                        <dd class="text-sm text-white">{{ $appName }}</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-sm text-gray-400">Environment</dt>
                        <dd class="text-sm {{ $appEnv === 'production' ? 'text-green-400' : 'text-yellow-400' }}">{{ ucfirst($appEnv) }}</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-sm text-gray-400">Debug Mode</dt>
                        <dd class="text-sm {{ $appDebug ? 'text-red-400' : 'text-green-400' }}">{{ $appDebug ? 'Enabled' : 'Disabled' }}</dd>
                    </div>
                </dl>
            </div>
        </div>

        <!-- Email Settings (Editable) -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700 lg:col-span-2">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">Email Configuration (SMTP)</h3>
                <p class="text-sm text-gray-400 mb-4">Configure SMTP settings for system emails and Alertmanager notifications.</p>

                <form wire:submit.prevent="saveMailSettings" class="space-y-4">
                    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
                        <!-- Mailer -->
                        <div>
                            <label for="mailMailer" class="block text-sm font-medium text-gray-300">Mail Driver</label>
                            <select wire:model="mailMailer" id="mailMailer" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white focus:border-blue-500 focus:ring-blue-500">
                                <option value="smtp">SMTP</option>
                                <option value="sendmail">Sendmail</option>
                                <option value="log">Log (Development)</option>
                            </select>
                            @error('mailMailer') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>

                        <!-- Encryption -->
                        <div>
                            <label for="mailEncryption" class="block text-sm font-medium text-gray-300">Encryption</label>
                            <select wire:model="mailEncryption" id="mailEncryption" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white focus:border-blue-500 focus:ring-blue-500">
                                <option value="tls">TLS</option>
                                <option value="ssl">SSL</option>
                                <option value="null">None</option>
                            </select>
                            @error('mailEncryption') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>

                        <!-- Host -->
                        <div>
                            <label for="mailHost" class="block text-sm font-medium text-gray-300">SMTP Host</label>
                            <input wire:model="mailHost" type="text" id="mailHost" placeholder="smtp-relay.brevo.com" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white placeholder-gray-500 focus:border-blue-500 focus:ring-blue-500">
                            @error('mailHost') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>

                        <!-- Port -->
                        <div>
                            <label for="mailPort" class="block text-sm font-medium text-gray-300">SMTP Port</label>
                            <input wire:model="mailPort" type="number" id="mailPort" placeholder="587" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white placeholder-gray-500 focus:border-blue-500 focus:ring-blue-500">
                            @error('mailPort') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>

                        <!-- Username -->
                        <div>
                            <label for="mailUsername" class="block text-sm font-medium text-gray-300">SMTP Username</label>
                            <input wire:model="mailUsername" type="text" id="mailUsername" placeholder="your-email@example.com" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white placeholder-gray-500 focus:border-blue-500 focus:ring-blue-500">
                            @error('mailUsername') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>

                        <!-- Password -->
                        <div>
                            <label for="mailPassword" class="block text-sm font-medium text-gray-300">SMTP Password / API Key</label>
                            <input wire:model="mailPassword" type="password" id="mailPassword" placeholder="••••••••" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white placeholder-gray-500 focus:border-blue-500 focus:ring-blue-500">
                            @error('mailPassword') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                            <p class="mt-1 text-xs text-gray-500">For Brevo: Use your SMTP API key, not account password</p>
                        </div>

                        <!-- From Address -->
                        <div>
                            <label for="mailFromAddress" class="block text-sm font-medium text-gray-300">From Email Address</label>
                            <input wire:model="mailFromAddress" type="email" id="mailFromAddress" placeholder="noreply@example.com" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white placeholder-gray-500 focus:border-blue-500 focus:ring-blue-500">
                            @error('mailFromAddress') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>

                        <!-- From Name -->
                        <div>
                            <label for="mailFromName" class="block text-sm font-medium text-gray-300">From Name</label>
                            <input wire:model="mailFromName" type="text" id="mailFromName" placeholder="CHOM System" class="mt-1 block w-full rounded-md bg-gray-700 border-gray-600 text-white placeholder-gray-500 focus:border-blue-500 focus:ring-blue-500">
                            @error('mailFromName') <p class="mt-1 text-xs text-red-400">{{ $message }}</p> @enderror
                        </div>
                    </div>

                    <!-- Test Email Result -->
                    @if($testEmailResult)
                        <div class="mt-4 p-3 rounded {{ str_contains($testEmailResult, '✓') ? 'bg-green-900/50 border border-green-600 text-green-200' : 'bg-red-900/50 border border-red-600 text-red-200' }}">
                            <p class="text-sm">{{ $testEmailResult }}</p>
                        </div>
                    @endif

                    <!-- Action Buttons -->
                    <div class="flex justify-between items-center mt-6">
                        <button type="button" wire:click="testEmailConnection" wire:loading.attr="disabled" wire:target="testEmailConnection"
                                class="inline-flex items-center px-4 py-2 border border-gray-600 rounded-md shadow-sm text-sm font-medium text-gray-300 bg-gray-600 hover:bg-gray-500 disabled:opacity-50">
                            <svg wire:loading.class="animate-spin" wire:target="testEmailConnection" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75" />
                            </svg>
                            Test Connection
                        </button>

                        <button type="submit" wire:loading.attr="disabled" wire:target="saveMailSettings"
                                class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50">
                            <svg wire:loading.class="animate-spin" wire:target="saveMailSettings" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 3.75V16.5L12 14.25 7.5 16.5V3.75m9 0H18A2.25 2.25 0 0120.25 6v12A2.25 2.25 0 0118 20.25H6A2.25 2.25 0 013.75 18V6A2.25 2.25 0 016 3.75h1.5m9 0h-9" />
                            </svg>
                            Save Settings
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- Default Site Settings -->
        <div class="bg-gray-800 shadow rounded-lg border border-gray-700">
            <div class="px-4 py-5 sm:p-6">
                <h3 class="text-lg leading-6 font-medium text-white mb-4">Default Site Settings</h3>
                <dl class="space-y-3">
                    <div class="flex justify-between">
                        <dt class="text-sm text-gray-400">Default PHP Version</dt>
                        <dd class="text-sm text-white">{{ $defaultPhpVersion }}</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-sm text-gray-400">Backup Retention</dt>
                        <dd class="text-sm text-white">{{ $defaultBackupRetentionDays }} days</dd>
                    </div>
                    <div class="flex justify-between">
                        <dt class="text-sm text-gray-400">Metrics Retention</dt>
                        <dd class="text-sm text-white">{{ $defaultMetricsRetentionDays }} days</dd>
                    </div>
                </dl>
                <p class="mt-4 text-xs text-gray-500">
                    These settings are configured via environment variables. Edit the .env file to change them.
                </p>
            </div>
        </div>
    </div>

    <!-- Maintenance Actions -->
    <div class="mt-6 bg-gray-800 shadow rounded-lg border border-gray-700">
        <div class="px-4 py-5 sm:p-6">
            <h3 class="text-lg leading-6 font-medium text-white mb-4">Maintenance Actions</h3>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <div class="bg-gray-700 rounded-lg p-4">
                    <h4 class="text-sm font-medium text-white mb-2">Clear Caches</h4>
                    <p class="text-xs text-gray-400 mb-3">Clear application, config, view, and route caches.</p>
                    <button wire:click="clearCache"
                            wire:loading.attr="disabled"
                            wire:target="clearCache"
                            class="w-full inline-flex justify-center items-center px-4 py-2 border border-gray-600 rounded-md shadow-sm text-sm font-medium text-gray-300 bg-gray-600 hover:bg-gray-500 disabled:opacity-50">
                        <svg wire:loading.class="animate-spin" wire:target="clearCache" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182m0-4.991v4.99" />
                        </svg>
                        Clear All
                    </button>
                </div>

                <div class="bg-gray-700 rounded-lg p-4">
                    <h4 class="text-sm font-medium text-white mb-2">Optimize</h4>
                    <p class="text-xs text-gray-400 mb-3">Cache config, routes, and views for better performance.</p>
                    <button wire:click="optimizeApplication"
                            wire:loading.attr="disabled"
                            wire:target="optimizeApplication"
                            class="w-full inline-flex justify-center items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50">
                        <svg wire:loading.class="animate-spin" wire:target="optimizeApplication" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 13.5l10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75z" />
                        </svg>
                        Optimize
                    </button>
                </div>

                <div class="bg-gray-700 rounded-lg p-4">
                    <h4 class="text-sm font-medium text-white mb-2">Run Migrations</h4>
                    <p class="text-xs text-gray-400 mb-3">Apply pending database migrations.</p>
                    <button wire:click="runMigrations"
                            wire:loading.attr="disabled"
                            wire:target="runMigrations"
                            wire:confirm="Are you sure you want to run pending migrations?"
                            class="w-full inline-flex justify-center items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-orange-600 hover:bg-orange-700 disabled:opacity-50">
                        <svg wire:loading.class="animate-spin" wire:target="runMigrations" class="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
                        </svg>
                        Run
                    </button>
                </div>
            </div>
        </div>
    </div>

    <!-- Warning Notice -->
    <div class="mt-6 bg-yellow-900/30 border border-yellow-600 rounded-lg p-4">
        <div class="flex">
            <svg class="h-5 w-5 text-yellow-400 mr-3 flex-shrink-0" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
            </svg>
            <div>
                <p class="text-sm text-yellow-200">
                    <strong>Note:</strong> Some settings require editing the <code class="bg-yellow-900/50 px-1 rounded">.env</code> file directly.
                    Always make a backup before modifying configuration files in production.
                </p>
            </div>
        </div>
    </div>
</div>
