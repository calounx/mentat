@props([
    'type' => 'info',
    'dismissible' => false,
    'icon' => true,
])

@php
$config = [
    'success' => [
        'bg' => 'bg-green-50',
        'border' => 'border-green-400',
        'text' => 'text-green-700',
        'iconColor' => 'text-green-400',
        'iconPath' => 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
    ],
    'error' => [
        'bg' => 'bg-red-50',
        'border' => 'border-red-400',
        'text' => 'text-red-700',
        'iconColor' => 'text-red-400',
        'iconPath' => 'M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z',
    ],
    'warning' => [
        'bg' => 'bg-yellow-50',
        'border' => 'border-yellow-400',
        'text' => 'text-yellow-700',
        'iconColor' => 'text-yellow-400',
        'iconPath' => 'M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z',
    ],
    'info' => [
        'bg' => 'bg-blue-50',
        'border' => 'border-blue-400',
        'text' => 'text-blue-700',
        'iconColor' => 'text-blue-400',
        'iconPath' => 'M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z',
    ],
];

$currentConfig = $config[$type] ?? $config['info'];
@endphp

<div {{ $attributes->merge(['class' => "{$currentConfig['bg']} border-l-4 {$currentConfig['border']} p-4"]) }}
     @if($dismissible)
     x-data="{ show: true }"
     x-show="show"
     x-transition:leave="transition ease-in duration-150"
     x-transition:leave-start="opacity-100"
     x-transition:leave-end="opacity-0"
     @endif>
    <div class="flex {{ $dismissible ? 'justify-between' : '' }}">
        <div class="flex">
            @if($icon)
            <div class="flex-shrink-0">
                <svg class="h-5 w-5 {{ $currentConfig['iconColor'] }}" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="{{ $currentConfig['iconPath'] }}" clip-rule="evenodd"/>
                </svg>
            </div>
            @endif
            <div class="{{ $icon ? 'ml-3' : '' }}">
                <p class="text-sm {{ $currentConfig['text'] }}">
                    {{ $slot }}
                </p>
            </div>
        </div>
        @if($dismissible)
        <div class="ml-auto pl-3">
            <div class="-mx-1.5 -my-1.5">
                <button type="button"
                        @click="show = false"
                        class="inline-flex rounded-md p-1.5 {{ $currentConfig['text'] }} hover:{{ $currentConfig['bg'] }} focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-{{ $type }}-50">
                    <span class="sr-only">Dismiss</span>
                    <x-icon name="x-mark" size="5" />
                </button>
            </div>
        </div>
        @endif
    </div>
</div>
