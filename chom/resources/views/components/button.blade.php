@props([
    'variant' => 'primary',
    'size' => 'md',
    'type' => 'button',
    'loading' => false,
    'loadingText' => null,
    'icon' => null,
    'iconPosition' => 'left',
    'href' => null,
])

@php
$variantClasses = [
    'primary' => 'border-transparent text-white bg-blue-600 hover:bg-blue-700 focus:ring-blue-500',
    'secondary' => 'border-gray-300 text-gray-700 bg-white hover:bg-gray-50 focus:ring-blue-500',
    'danger' => 'border-transparent text-white bg-red-600 hover:bg-red-700 focus:ring-red-500',
    'success' => 'border-transparent text-white bg-green-600 hover:bg-green-700 focus:ring-green-500',
    'warning' => 'border-transparent text-white bg-yellow-600 hover:bg-yellow-700 focus:ring-yellow-500',
];

$sizeClasses = [
    'xs' => 'px-2.5 py-1.5 text-xs',
    'sm' => 'px-3 py-2 text-sm',
    'md' => 'px-4 py-2 text-sm',
    'lg' => 'px-4 py-2 text-base',
    'xl' => 'px-6 py-3 text-base',
];

$baseClasses = 'inline-flex items-center justify-center border font-medium rounded-md shadow-sm focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200';

$classes = implode(' ', [
    $baseClasses,
    $variantClasses[$variant] ?? $variantClasses['primary'],
    $sizeClasses[$size] ?? $sizeClasses['md'],
]);
@endphp

@if($href)
    <a href="{{ $href }}" {{ $attributes->merge(['class' => $classes]) }}>
        @if($icon && $iconPosition === 'left')
            <x-icon :name="$icon" class="mr-2 -ml-1" />
        @endif

        {{ $slot }}

        @if($icon && $iconPosition === 'right')
            <x-icon :name="$icon" class="ml-2 -mr-1" />
        @endif
    </a>
@else
    <button type="{{ $type }}" {{ $attributes->merge(['class' => $classes]) }} {{ $loading ? 'disabled' : '' }}>
        @if($loading)
            <svg class="animate-spin -ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            {{ $loadingText ?? $slot }}
        @else
            @if($icon && $iconPosition === 'left')
                <x-icon :name="$icon" class="mr-2 -ml-1" />
            @endif

            {{ $slot }}

            @if($icon && $iconPosition === 'right')
                <x-icon :name="$icon" class="ml-2 -mr-1" />
            @endif
        @endif
    </button>
@endif
