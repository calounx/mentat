<div x-data="{
    showToast: false,
    toastMessage: '',
    toastType: 'success'
}"
@ssl-issued.window="showToast = true; toastMessage = 'SSL certificate is being issued'; toastType = 'success'"
@ssl-renewed.window="showToast = true; toastMessage = 'SSL certificate is being renewed'; toastType = 'success'"
@auto-renew-toggled.window="showToast = true; toastMessage = 'Auto-renewal setting updated'; toastType = 'success'"
@refresh-status-delayed.window="setTimeout(() => $wire.refreshStatus(), $event.detail.delay)"
class="space-y-4">

    {{-- Success/Error Messages --}}
    @if($successMessage)
    <div class="rounded-md bg-green-50 p-4 border border-green-200" x-data="{ show: true }" x-show="show" x-init="setTimeout(() => show = false, 5000)" x-transition>
        <div class="flex">
            <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
                </svg>
            </div>
            <div class="ml-3 flex-1">
                <p class="text-sm font-medium text-green-800">{{ $successMessage }}</p>
            </div>
            <div class="ml-auto pl-3">
                <button @click="show = false" class="inline-flex text-green-400 hover:text-green-600 focus:outline-none">
                    <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                        <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                    </svg>
                </button>
            </div>
        </div>
    </div>
    @endif

    @if($errorMessage)
    <div class="rounded-md bg-red-50 p-4 border border-red-200" x-data="{ show: true }" x-show="show" x-init="setTimeout(() => show = false, 5000)" x-transition>
        <div class="flex">
            <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                </svg>
            </div>
            <div class="ml-3 flex-1">
                <p class="text-sm font-medium text-red-800">{{ $errorMessage }}</p>
            </div>
            <div class="ml-auto pl-3">
                <button @click="show = false" class="inline-flex text-red-400 hover:text-red-600 focus:outline-none">
                    <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                        <path d="M6.28 5.22a.75.75 0 00-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 101.06 1.06L10 11.06l3.72 3.72a.75.75 0 101.06-1.06L11.06 10l3.72-3.72a.75.75 0 00-1.06-1.06L10 8.94 6.28 5.22z" />
                    </svg>
                </button>
            </div>
        </div>
    </div>
    @endif

    {{-- SSL Certificate Card --}}
    <div class="bg-white overflow-hidden shadow rounded-lg border border-gray-200" wire:poll.30s="refreshStatus">
        <div class="px-4 py-5 sm:p-6">
            <div class="flex items-center justify-between mb-4">
                <h3 class="text-lg font-medium leading-6 text-gray-900">SSL Certificate</h3>
                <button
                    wire:click="refreshStatus"
                    wire:loading.attr="disabled"
                    class="inline-flex items-center px-3 py-1.5 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
                    title="Refresh Status">
                    <svg wire:loading.remove wire:target="refreshStatus" class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                    </svg>
                    <svg wire:loading wire:target="refreshStatus" class="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                </button>
            </div>

            @if($sslStatus)
                <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
                    {{-- Domain --}}
                    <div class="sm:col-span-2">
                        <dt class="text-sm font-medium text-gray-500">Domain</dt>
                        <dd class="mt-1 text-sm text-gray-900 font-mono">{{ $sslStatus['domain'] ?? 'N/A' }}</dd>
                    </div>

                    {{-- Status --}}
                    <div class="sm:col-span-1">
                        <dt class="text-sm font-medium text-gray-500">Status</dt>
                        <dd class="mt-1">
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium
                                @if($this->getStatusColor() === 'green') bg-green-100 text-green-800
                                @elseif($this->getStatusColor() === 'yellow') bg-yellow-100 text-yellow-800
                                @elseif($this->getStatusColor() === 'red') bg-red-100 text-red-800
                                @else bg-gray-100 text-gray-800
                                @endif">
                                <svg class="mr-1.5 h-2 w-2
                                    @if($this->getStatusColor() === 'green') text-green-400
                                    @elseif($this->getStatusColor() === 'yellow') text-yellow-400
                                    @elseif($this->getStatusColor() === 'red') text-red-400
                                    @else text-gray-400
                                    @endif" fill="currentColor" viewBox="0 0 8 8">
                                    <circle cx="4" cy="4" r="3" />
                                </svg>
                                {{ $this->getStatusText() }}
                            </span>
                        </dd>
                    </div>

                    {{-- Issuer --}}
                    @if($this->hasCertificate())
                    <div class="sm:col-span-1">
                        <dt class="text-sm font-medium text-gray-500">Issuer</dt>
                        <dd class="mt-1 text-sm text-gray-900">{{ $sslStatus['issuer'] ?? 'Let\'s Encrypt' }}</dd>
                    </div>

                    {{-- Expiry Date --}}
                    <div class="sm:col-span-1">
                        <dt class="text-sm font-medium text-gray-500">Expires</dt>
                        <dd class="mt-1 text-sm text-gray-900">
                            @if(isset($sslStatus['expires_at']))
                                {{ \Carbon\Carbon::parse($sslStatus['expires_at'])->format('Y-m-d') }}
                            @else
                                N/A
                            @endif
                        </dd>
                    </div>

                    {{-- Days Remaining --}}
                    <div class="sm:col-span-1">
                        <dt class="text-sm font-medium text-gray-500">Days Remaining</dt>
                        <dd class="mt-1 text-sm font-semibold
                            @if(isset($sslStatus['days_remaining']))
                                @if($sslStatus['days_remaining'] > 30) text-green-600
                                @elseif($sslStatus['days_remaining'] > 7) text-yellow-600
                                @else text-red-600
                                @endif
                            @else text-gray-900
                            @endif">
                            {{ $sslStatus['days_remaining'] ?? 'N/A' }}
                            @if(isset($sslStatus['days_remaining']))
                                {{ Str::plural('day', $sslStatus['days_remaining']) }}
                            @endif
                        </dd>
                    </div>
                    @endif
                </dl>

                {{-- Action Buttons --}}
                <div class="mt-6 flex flex-col sm:flex-row gap-3">
                    @if($this->hasCertificate())
                        {{-- Renew Certificate Button --}}
                        @if($this->canRenew())
                        <button
                            wire:click="renewSSL"
                            wire:loading.attr="disabled"
                            wire:target="renewSSL"
                            class="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed">
                            <svg wire:loading.remove wire:target="renewSSL" class="-ml-1 mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                            </svg>
                            <svg wire:loading wire:target="renewSSL" class="animate-spin -ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24">
                                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                            </svg>
                            <span wire:loading.remove wire:target="renewSSL">Renew Certificate</span>
                            <span wire:loading wire:target="renewSSL">Renewing...</span>
                        </button>
                        @endif

                        {{-- Auto-Renewal Toggle --}}
                        <button
                            wire:click="toggleAutoRenew"
                            wire:loading.attr="disabled"
                            wire:target="toggleAutoRenew"
                            class="inline-flex items-center justify-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md
                                {{ $autoRenewEnabled ? 'text-green-700 bg-green-50 border-green-300 hover:bg-green-100' : 'text-gray-700 bg-white hover:bg-gray-50' }}
                                focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed">
                            <svg wire:loading.remove wire:target="toggleAutoRenew" class="-ml-1 mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                @if($autoRenewEnabled)
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                                @else
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
                                @endif
                            </svg>
                            <svg wire:loading wire:target="toggleAutoRenew" class="animate-spin -ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24">
                                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                            </svg>
                            <span wire:loading.remove wire:target="toggleAutoRenew">
                                Auto-Renew: {{ $autoRenewEnabled ? 'ON' : 'OFF' }}
                            </span>
                            <span wire:loading wire:target="toggleAutoRenew">Updating...</span>
                        </button>
                    @else
                        {{-- Issue Certificate Button --}}
                        <button
                            wire:click="issueSSL"
                            wire:loading.attr="disabled"
                            wire:target="issueSSL"
                            class="inline-flex items-center justify-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed">
                            <svg wire:loading.remove wire:target="issueSSL" class="-ml-1 mr-2 h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                            </svg>
                            <svg wire:loading wire:target="issueSSL" class="animate-spin -ml-1 mr-2 h-5 w-5" fill="none" viewBox="0 0 24 24">
                                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                            </svg>
                            <span wire:loading.remove wire:target="issueSSL">Issue SSL Certificate</span>
                            <span wire:loading wire:target="issueSSL">Issuing...</span>
                        </button>
                    @endif
                </div>

                {{-- Auto-Renewal Info --}}
                @if($this->hasCertificate() && $autoRenewEnabled)
                <div class="mt-4 bg-blue-50 border border-blue-200 rounded-md p-3">
                    <div class="flex">
                        <div class="flex-shrink-0">
                            <svg class="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
                                <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z" clip-rule="evenodd" />
                            </svg>
                        </div>
                        <div class="ml-3">
                            <p class="text-sm text-blue-700">
                                Certificate will be automatically renewed when {{ $renewalDays }} days remain before expiration.
                            </p>
                        </div>
                    </div>
                </div>
                @endif

            @else
                {{-- Loading State --}}
                <div class="flex items-center justify-center py-12">
                    <svg class="animate-spin h-8 w-8 text-gray-400" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    <span class="ml-3 text-sm text-gray-500">Loading SSL status...</span>
                </div>
            @endif
        </div>
    </div>

    {{-- Toast Notification --}}
    <div
        x-show="showToast"
        x-transition:enter="transform ease-out duration-300 transition"
        x-transition:enter-start="translate-y-2 opacity-0 sm:translate-y-0 sm:translate-x-2"
        x-transition:enter-end="translate-y-0 opacity-100 sm:translate-x-0"
        x-transition:leave="transition ease-in duration-100"
        x-transition:leave-start="opacity-100"
        x-transition:leave-end="opacity-0"
        @click="showToast = false"
        x-init="$watch('showToast', value => { if(value) setTimeout(() => showToast = false, 3000) })"
        class="fixed bottom-4 right-4 max-w-sm w-full bg-white shadow-lg rounded-lg pointer-events-auto ring-1 ring-black ring-opacity-5 overflow-hidden z-50"
        style="display: none;">
        <div class="p-4">
            <div class="flex items-start">
                <div class="flex-shrink-0">
                    <svg x-show="toastType === 'success'" class="h-6 w-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                </div>
                <div class="ml-3 w-0 flex-1 pt-0.5">
                    <p class="text-sm font-medium text-gray-900" x-text="toastMessage"></p>
                </div>
            </div>
        </div>
    </div>
</div>
