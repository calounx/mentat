@props([
    'label' => null,
    'error' => null,
    'help' => null,
    'required' => false,
    'type' => 'text',
    'name' => '',
    'id' => null,
])

@php
$inputId = $id ?? $name;
$hasError = $error || $errors->has($name);
$errorMessage = $error ?? $errors->first($name);
@endphp

<div {{ $attributes->only('class') }}>
    @if($label)
    <label for="{{ $inputId }}" class="block text-sm font-medium text-gray-700 mb-1">
        {{ $label }}
        @if($required)
        <span class="text-red-500">*</span>
        @endif
    </label>
    @endif

    <div class="relative">
        <input
            type="{{ $type }}"
            name="{{ $name }}"
            id="{{ $inputId }}"
            {{ $attributes->except(['class', 'label', 'error', 'help', 'required'])->merge([
                'class' => 'shadow-sm focus:ring-blue-500 focus:border-blue-500 block w-full sm:text-sm border-gray-300 rounded-md' . ($hasError ? ' border-red-300 text-red-900 placeholder-red-300 focus:ring-red-500 focus:border-red-500' : '')
            ]) }}
            @if($required) required @endif
        >

        @if($hasError)
        <div class="absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none">
            <x-icon name="x-circle" size="5" class="text-red-500" />
        </div>
        @endif
    </div>

    @if($hasError)
    <p class="mt-1 text-sm text-red-600">{{ $errorMessage }}</p>
    @endif

    @if($help && !$hasError)
    <p class="mt-1 text-sm text-gray-500">{{ $help }}</p>
    @endif
</div>
