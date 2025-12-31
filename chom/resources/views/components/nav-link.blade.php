@props([
    'active' => false,
    'href' => '#',
])

@php
$classes = $active
    ? 'inline-flex items-center px-1 pt-1 border-b-2 border-blue-500 text-gray-900 text-sm font-medium'
    : 'inline-flex items-center px-1 pt-1 border-b-2 border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300 text-sm font-medium';
@endphp

<a href="{{ $href }}" {{ $attributes->merge(['class' => $classes]) }}>
    {{ $slot }}
</a>
