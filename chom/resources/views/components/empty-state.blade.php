@props([
    'icon' => 'folder',
    'title' => 'No items',
    'description' => null,
])

<div {{ $attributes->merge(['class' => 'text-center py-12']) }}>
    <x-icon :name="$icon" size="12" class="mx-auto text-gray-400" />

    <h3 class="mt-2 text-sm font-medium text-gray-900">{{ $title }}</h3>

    @if($description)
    <p class="mt-1 text-sm text-gray-500">{{ $description }}</p>
    @endif

    @if($slot->isNotEmpty())
    <div class="mt-6">
        {{ $slot }}
    </div>
    @endif
</div>
