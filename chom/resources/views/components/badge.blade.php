@props([
    'variant' => 'default',
    'size' => 'md',
    'removable' => false,
])

@php
$variantClasses = [
    'default' => 'bg-gray-100 text-gray-800',
    'primary' => 'bg-blue-100 text-blue-800',
    'success' => 'bg-green-100 text-green-800',
    'danger' => 'bg-red-100 text-red-800',
    'warning' => 'bg-yellow-100 text-yellow-800',
    'info' => 'bg-blue-100 text-blue-800',
];

$sizeClasses = [
    'sm' => 'px-2 py-0.5 text-xs',
    'md' => 'px-2.5 py-0.5 text-xs',
    'lg' => 'px-3 py-1 text-sm',
];

$classes = implode(' ', [
    'inline-flex items-center rounded-full font-medium',
    $variantClasses[$variant] ?? $variantClasses['default'],
    $sizeClasses[$size] ?? $sizeClasses['md'],
]);
@endphp

<span {{ $attributes->merge(['class' => $classes]) }}>
    {{ $slot }}

    @if($removable)
    <button type="button" class="ml-1 inline-flex flex-shrink-0 focus:outline-none">
        <x-icon name="x-mark" size="3" />
    </button>
    @endif
</span>
