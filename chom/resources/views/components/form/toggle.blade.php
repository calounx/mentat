@props([
    'label' => null,
    'description' => null,
    'name' => '',
    'id' => null,
    'checked' => false,
])

@php
$inputId = $id ?? $name;
@endphp

<div class="flex items-center justify-between" {{ $attributes }}>
    @if($label || $description)
    <div>
        @if($label)
        <label for="{{ $inputId }}" class="text-sm font-medium text-gray-700">
            {{ $label }}
        </label>
        @endif
        @if($description)
        <p class="text-sm text-gray-500">{{ $description }}</p>
        @endif
    </div>
    @endif

    <button type="button"
            x-data="{ enabled: @js($checked) }"
            @click="enabled = !enabled"
            :class="enabled ? 'bg-blue-600' : 'bg-gray-200'"
            class="relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
            role="switch"
            :aria-checked="enabled.toString()">
        <span class="sr-only">{{ $label }}</span>
        <span :class="enabled ? 'translate-x-5' : 'translate-x-0'"
              class="pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"></span>
        <input type="hidden" name="{{ $name }}" :value="enabled ? '1' : '0'">
    </button>
</div>
