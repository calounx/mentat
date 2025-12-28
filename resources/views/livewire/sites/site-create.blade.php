<div class="max-w-2xl mx-auto">
    <!-- Header -->
    <div class="mb-8">
        <a href="{{ route('sites.index') }}" class="inline-flex items-center text-sm text-gray-500 hover:text-gray-700 mb-4">
            <svg class="h-5 w-5 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
            </svg>
            Back to Sites
        </a>
        <h1 class="text-2xl font-bold text-gray-900">Create New Site</h1>
        <p class="mt-1 text-sm text-gray-600">
            Set up a new WordPress or HTML site on your hosting.
        </p>
    </div>

    <!-- Usage Info -->
    <div class="bg-blue-50 border-l-4 border-blue-400 p-4 mb-6">
        <div class="flex">
            <div class="flex-shrink-0">
                <svg class="h-5 w-5 text-blue-400" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
                </svg>
            </div>
            <div class="ml-3">
                <p class="text-sm text-blue-700">
                    Sites used: <strong>{{ $siteCount }}</strong> / <strong>{{ $maxSites == -1 ? 'Unlimited' : $maxSites }}</strong>
                </p>
            </div>
        </div>
    </div>

    @if(!$canCreate)
        <div class="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-6">
            <div class="flex">
                <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-yellow-400" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                    </svg>
                </div>
                <div class="ml-3">
                    <p class="text-sm text-yellow-700">
                        You've reached your site limit. Upgrade your plan to create more sites.
                    </p>
                </div>
            </div>
        </div>
    @endif

    <!-- Error Message -->
    @if($error)
        <div class="bg-red-50 border-l-4 border-red-400 p-4 mb-6">
            <div class="flex">
                <div class="flex-shrink-0">
                    <svg class="h-5 w-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
                    </svg>
                </div>
                <div class="ml-3">
                    <p class="text-sm text-red-700">{{ $error }}</p>
                </div>
            </div>
        </div>
    @endif

    <!-- Form -->
    <form wire:submit="create" class="bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:p-6 space-y-6">
            <!-- Domain -->
            <div>
                <label for="domain" class="block text-sm font-medium text-gray-700">
                    Domain Name
                </label>
                <div class="mt-1">
                    <input type="text"
                           id="domain"
                           wire:model.blur="domain"
                           placeholder="example.com"
                           class="shadow-sm focus:ring-blue-500 focus:border-blue-500 block w-full sm:text-sm border-gray-300 rounded-md @error('domain') border-red-300 @enderror"
                           {{ !$canCreate ? 'disabled' : '' }}>
                </div>
                @error('domain')
                    <p class="mt-1 text-sm text-red-600">{{ $message }}</p>
                @enderror
                <p class="mt-1 text-sm text-gray-500">
                    Enter your domain without http:// or www. Make sure DNS is pointed to your server.
                </p>
            </div>

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
                            <svg class="h-5 w-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                            </svg>
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
                            <svg class="h-5 w-5 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                            </svg>
                        @endif
                    </label>
                </div>
            </div>

            <!-- PHP Version (only for WordPress) -->
            @if($siteType === 'wordpress')
                <div>
                    <label for="phpVersion" class="block text-sm font-medium text-gray-700">
                        PHP Version
                    </label>
                    <select id="phpVersion"
                            wire:model="phpVersion"
                            class="mt-1 block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-md"
                            {{ !$canCreate ? 'disabled' : '' }}>
                        <option value="8.2">PHP 8.2 (Recommended)</option>
                        <option value="8.4">PHP 8.4</option>
                    </select>
                </div>
            @endif

            <!-- SSL -->
            <div class="flex items-center justify-between">
                <div>
                    <label for="sslEnabled" class="text-sm font-medium text-gray-700">
                        Enable SSL Certificate
                    </label>
                    <p class="text-sm text-gray-500">
                        Free Let's Encrypt SSL certificate (recommended)
                    </p>
                </div>
                <button type="button"
                        wire:click="$toggle('sslEnabled')"
                        class="relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 {{ $sslEnabled ? 'bg-blue-600' : 'bg-gray-200' }}"
                        {{ !$canCreate ? 'disabled' : '' }}>
                    <span class="sr-only">Enable SSL</span>
                    <span class="pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out {{ $sslEnabled ? 'translate-x-5' : 'translate-x-0' }}"></span>
                </button>
            </div>
        </div>

        <!-- Submit -->
        <div class="px-4 py-3 bg-gray-50 text-right sm:px-6 rounded-b-lg">
            <a href="{{ route('sites.index') }}"
               class="inline-flex justify-center py-2 px-4 border border-gray-300 shadow-sm text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 mr-3">
                Cancel
            </a>
            <button type="submit"
                    class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
                    {{ !$canCreate || $isCreating ? 'disabled' : '' }}>
                @if($isCreating)
                    <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    Creating...
                @else
                    Create Site
                @endif
            </button>
        </div>
    </form>
</div>
