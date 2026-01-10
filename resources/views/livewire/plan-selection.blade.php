<div class="min-h-screen bg-gray-100 flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
    <div class="max-w-7xl w-full">
        <!-- Header -->
        <div class="text-center mb-12">
            <h1 class="text-4xl font-bold text-gray-900">Welcome to CHOM!</h1>
            <p class="mt-4 text-xl text-gray-600">Your account has been approved. Select a plan to get started.</p>
            @if($error)
                <div class="mt-6 mx-auto max-w-md rounded-md bg-red-50 border border-red-200 p-4">
                    <div class="flex">
                        <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                        </svg>
                        <div class="ml-3">
                            <p class="text-sm font-medium text-red-800">{{ $error }}</p>
                        </div>
                    </div>
                </div>
            @endif
        </div>

        <!-- Plans Grid -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8 max-w-6xl mx-auto">
            @foreach($plans as $plan)
                <div class="relative bg-white rounded-2xl shadow-lg {{ $plan['is_recommended'] ? 'ring-4 ring-blue-500 transform scale-105' : 'ring-1 ring-gray-200' }} transition-all duration-200 hover:shadow-xl">
                    @if($plan['is_recommended'])
                        <div class="absolute -top-5 left-0 right-0 flex justify-center">
                            <span class="inline-flex items-center px-4 py-1 rounded-full text-sm font-semibold bg-blue-500 text-white shadow-lg">
                                <svg class="mr-1 h-4 w-4" fill="currentColor" viewBox="0 0 20 20">
                                    <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                                </svg>
                                Recommended
                            </span>
                        </div>
                    @endif

                    <div class="p-8">
                        <!-- Plan Header -->
                        <div class="text-center mb-8">
                            <h3 class="text-2xl font-bold text-gray-900">{{ $plan['name'] }}</h3>
                            <div class="mt-4">
                                <span class="text-4xl font-extrabold text-gray-900">{{ $plan['price'] }}</span>
                            </div>
                        </div>

                        <!-- Features List -->
                        <ul class="space-y-4 mb-8">
                            @foreach($plan['features'] as $feature)
                                <li class="flex items-start">
                                    <svg class="flex-shrink-0 h-6 w-6 text-green-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                                    </svg>
                                    <span class="ml-3 text-gray-700">{{ $feature }}</span>
                                </li>
                            @endforeach
                        </ul>

                        <!-- Select Button -->
                        <button wire:click="selectPlan('{{ $plan['tier'] }}')"
                                class="w-full py-3 px-6 rounded-lg font-semibold transition-all duration-200
                                       {{ $plan['is_recommended']
                                          ? 'bg-blue-600 text-white hover:bg-blue-700 shadow-md hover:shadow-lg'
                                          : 'bg-gray-100 text-gray-900 hover:bg-gray-200 border-2 border-gray-300' }}">
                            Select {{ $plan['name'] }}
                        </button>
                    </div>
                </div>
            @endforeach
        </div>

        <!-- Footer Note -->
        <div class="mt-12 text-center">
            <p class="text-sm text-gray-500">
                You can request plan changes later from your dashboard.
            </p>
            <p class="mt-2 text-sm text-gray-500">
                All plan changes require administrator approval.
            </p>
        </div>
    </div>
</div>
