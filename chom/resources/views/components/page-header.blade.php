@props([
    'title' => '',
    'description' => null,
])

<div {{ $attributes->merge(['class' => 'mb-8']) }}>
    <div class="sm:flex sm:items-center sm:justify-between">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">{{ $title }}</h1>
            @if($description)
            <p class="mt-1 text-sm text-gray-600">{{ $description }}</p>
            @endif
        </div>

        @isset($actions)
        <div class="mt-4 sm:mt-0">
            {{ $actions }}
        </div>
        @endisset
    </div>
</div>
