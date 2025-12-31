@props([
    'label' => '',
    'value' => '',
    'icon' => null,
    'iconColor' => 'text-gray-400',
    'trend' => null,
    'trendDirection' => 'up',
])

<div {{ $attributes->merge(['class' => 'bg-white overflow-hidden shadow rounded-lg']) }}>
    <div class="p-5">
        <div class="flex items-center">
            @if($icon)
            <div class="flex-shrink-0">
                <x-icon :name="$icon" size="6" class="{{ $iconColor }}" />
            </div>
            @endif

            <div class="{{ $icon ? 'ml-5' : '' }} w-0 flex-1">
                <dl>
                    <dt class="text-sm font-medium text-gray-500 truncate">{{ $label }}</dt>
                    <dd class="flex items-baseline">
                        <div class="text-2xl font-semibold text-gray-900">{{ $value }}</div>
                        @if($trend)
                        <div class="ml-2 flex items-baseline text-sm font-semibold {{ $trendDirection === 'up' ? 'text-green-600' : 'text-red-600' }}">
                            @if($trendDirection === 'up')
                            <x-icon name="arrow-up" size="4" class="self-center flex-shrink-0" />
                            @else
                            <x-icon name="arrow-down" size="4" class="self-center flex-shrink-0" />
                            @endif
                            <span class="ml-1">{{ $trend }}</span>
                        </div>
                        @endif
                    </dd>
                </dl>
            </div>
        </div>

        @if($slot->isNotEmpty())
        <div class="mt-4">
            {{ $slot }}
        </div>
        @endif
    </div>
</div>
