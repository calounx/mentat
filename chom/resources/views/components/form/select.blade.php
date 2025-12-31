@props([
    'label' => null,
    'error' => null,
    'help' => null,
    'required' => false,
    'name' => '',
    'id' => null,
    'options' => [],
    'placeholder' => null,
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

    <select
        name="{{ $name }}"
        id="{{ $inputId }}"
        {{ $attributes->except(['class', 'label', 'error', 'help', 'required', 'options', 'placeholder'])->merge([
            'class' => 'block w-full pl-3 pr-10 py-2 text-base border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-md' . ($hasError ? ' border-red-300 text-red-900 focus:ring-red-500 focus:border-red-500' : '')
        ]) }}
        @if($required) required @endif
    >
        @if($placeholder)
        <option value="">{{ $placeholder }}</option>
        @endif

        @if(count($options) > 0)
            @foreach($options as $value => $label)
            <option value="{{ $value }}">{{ $label }}</option>
            @endforeach
        @else
            {{ $slot }}
        @endif
    </select>

    @if($hasError)
    <p class="mt-1 text-sm text-red-600">{{ $errorMessage }}</p>
    @endif

    @if($help && !$hasError)
    <p class="mt-1 text-sm text-gray-500">{{ $help }}</p>
    @endif
</div>
