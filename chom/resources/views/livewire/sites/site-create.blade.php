<div class="max-w-2xl mx-auto">
    <!-- Header -->
    <div class="mb-8">
        <a href="{{ route('sites.index') }}" class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 mb-4">
            <x-icon name="chevron-left" size="5" class="mr-1" />
            Back to Sites
        </a>
        <h1 class="text-2xl font-bold text-gray-900">Create New Site</h1>
        <p class="mt-1 text-sm text-gray-600">
            Set up a new WordPress or HTML site on your hosting.
        </p>
    </div>

    <!-- Usage Info -->
    <x-alert type="info" class="mb-6">
        Sites used: <strong>{{ $siteCount }}</strong> / <strong>{{ $maxSites == -1 ? 'Unlimited' : $maxSites }}</strong>
    </x-alert>

    @if(!$canCreate)
        <x-alert type="warning" class="mb-6">
            You've reached your site limit. Upgrade your plan to create more sites.
        </x-alert>
    @endif

    <!-- Error Message -->
    @if($error)
        <x-alert type="error" class="mb-6">
            {{ $error }}
        </x-alert>
    @endif

    <!-- Form -->
    <form wire:submit="create">
        <x-card>
            <div class="space-y-6">
                <!-- Domain -->
                <x-form.input
                    label="Domain Name"
                    name="domain"
                    wire:model.blur="domain"
                    placeholder="example.com"
                    help="Enter your domain without http:// or www. Make sure DNS is pointed to your server."
                    :disabled="!$canCreate"
                    required
                />

                <!-- Site Type -->
                <div>
                    <label class="block text-sm font-medium text-gray-700 mb-3">
                        Site Type
                    </label>
                    <div class="grid grid-cols-2 gap-4">
                        <label class="relative flex cursor-pointer rounded-lg border bg-white p-4 shadow-sm focus:outline-none {{ $siteType === 'wordpress' ? 'border-blue-500 ring-2 ring-blue-500' : 'border-gray-300' }}">
                            <input type="radio" wire:model="siteType" value="wordpress" class="sr-only" {{ !$canCreate ? 'disabled' : '' }}>
                            <span class="flex flex-1">
                                <span class="flex flex-col">
                                    <span class="block text-sm font-medium text-gray-900">WordPress</span>
                                    <span class="mt-1 flex items-center text-sm text-gray-500">Full WordPress installation</span>
                                </span>
                            </span>
                            @if($siteType === 'wordpress')
                                <x-icon name="check-circle" size="5" class="text-blue-600" />
                            @endif
                        </label>

                        <label class="relative flex cursor-pointer rounded-lg border bg-white p-4 shadow-sm focus:outline-none {{ $siteType === 'html' ? 'border-blue-500 ring-2 ring-blue-500' : 'border-gray-300' }}">
                            <input type="radio" wire:model="siteType" value="html" class="sr-only" {{ !$canCreate ? 'disabled' : '' }}>
                            <span class="flex flex-1">
                                <span class="flex flex-col">
                                    <span class="block text-sm font-medium text-gray-900">Static HTML</span>
                                    <span class="mt-1 flex items-center text-sm text-gray-500">Simple HTML/CSS/JS site</span>
                                </span>
                            </span>
                            @if($siteType === 'html')
                                <x-icon name="check-circle" size="5" class="text-blue-600" />
                            @endif
                        </label>
                    </div>
                </div>

                <!-- PHP Version (only for WordPress) -->
                @if($siteType === 'wordpress')
                    <x-form.select
                        label="PHP Version"
                        name="phpVersion"
                        wire:model="phpVersion"
                        :options="[
                            '8.2' => 'PHP 8.2 (Recommended)',
                            '8.4' => 'PHP 8.4'
                        ]"
                        :disabled="!$canCreate"
                    />
                @endif

                <!-- SSL -->
                <x-form.toggle
                    label="Enable SSL Certificate"
                    description="Free Let's Encrypt SSL certificate (recommended)"
                    name="sslEnabled"
                    :checked="$sslEnabled"
                    wire:click="$toggle('sslEnabled')"
                />
            </div>

            <x-slot:footer>
                <div class="flex justify-end space-x-3">
                    <x-button variant="secondary" href="{{ route('sites.index') }}">
                        Cancel
                    </x-button>

                    <x-button
                        variant="primary"
                        type="submit"
                        :loading="$isCreating"
                        loadingText="Creating..."
                        :disabled="!$canCreate || $isCreating"
                    >
                        Create Site
                    </x-button>
                </div>
            </x-slot:footer>
        </x-card>
    </form>
</div>
