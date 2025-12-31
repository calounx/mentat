@props([
    'padding' => true,
    'shadow' => true,
])

@php
$classes = 'bg-white rounded-lg overflow-hidden';
$classes .= $shadow ? ' shadow' : '';
@endphp

<div {{ $attributes->merge(['class' => $classes]) }}>
    @isset($header)
    <div class="{{ $padding ? 'px-4 py-5 sm:px-6' : '' }} border-b border-gray-200">
        {{ $header }}
    </div>
    @endisset

    <div class="{{ $padding ? 'px-4 py-5 sm:p-6' : '' }}">
        {{ $slot }}
    </div>

    @isset($footer)
    <div class="{{ $padding ? 'px-4 py-3 sm:px-6' : '' }} bg-gray-50 border-t border-gray-200">
        {{ $footer }}
    </div>
    @endisset
</div>
