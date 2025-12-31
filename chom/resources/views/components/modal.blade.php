@props([
    'show' => false,
    'title' => '',
    'size' => 'md',
    'closeable' => true,
])

@php
$sizeClasses = [
    'sm' => 'max-w-md',
    'md' => 'max-w-lg',
    'lg' => 'max-w-2xl',
    'xl' => 'max-w-4xl',
    'full' => 'max-w-7xl',
];
@endphp

<div x-data="{ show: @js($show) }"
     x-show="show"
     x-on:keydown.escape.window="show = false"
     {{ $attributes }}
     class="fixed inset-0 z-50 overflow-y-auto"
     style="display: none;">

    <!-- Backdrop -->
    <div x-show="show"
         x-transition:enter="ease-out duration-300"
         x-transition:enter-start="opacity-0"
         x-transition:enter-end="opacity-100"
         x-transition:leave="ease-in duration-200"
         x-transition:leave-start="opacity-100"
         x-transition:leave-end="opacity-0"
         class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
         @if($closeable)
         @click="show = false"
         @endif>
    </div>

    <!-- Modal Panel -->
    <div class="flex min-h-full items-center justify-center p-4">
        <div x-show="show"
             x-transition:enter="ease-out duration-300"
             x-transition:enter-start="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
             x-transition:enter-end="opacity-100 translate-y-0 sm:scale-100"
             x-transition:leave="ease-in duration-200"
             x-transition:leave-start="opacity-100 translate-y-0 sm:scale-100"
             x-transition:leave-end="opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"
             class="relative transform overflow-hidden rounded-lg bg-white shadow-xl transition-all w-full {{ $sizeClasses[$size] ?? $sizeClasses['md'] }}">

            <!-- Header -->
            @if($title || $closeable)
            <div class="border-b border-gray-200 px-6 py-4">
                <div class="flex items-center justify-between">
                    @if($title)
                    <h3 class="text-lg font-medium text-gray-900">{{ $title }}</h3>
                    @endif

                    @if($closeable)
                    <button type="button"
                            @click="show = false"
                            class="text-gray-400 hover:text-gray-500 focus:outline-none">
                        <span class="sr-only">Close</span>
                        <x-icon name="x-mark" size="6" />
                    </button>
                    @endif
                </div>
            </div>
            @endif

            <!-- Body -->
            <div class="px-6 py-4">
                {{ $slot }}
            </div>

            <!-- Footer -->
            @isset($footer)
            <div class="border-t border-gray-200 px-6 py-4 bg-gray-50 rounded-b-lg">
                {{ $footer }}
            </div>
            @endisset
        </div>
    </div>
</div>
