@props([
    'sortable' => false,
    'direction' => null,
])

<th {{ $attributes->merge(['class' => 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider']) }}>
    @if($sortable)
    <button type="button" class="group inline-flex items-center space-x-1">
        <span>{{ $slot }}</span>
        @if($direction === 'asc')
        <x-icon name="arrow-up" size="4" class="text-gray-400" />
        @elseif($direction === 'desc')
        <x-icon name="arrow-down" size="4" class="text-gray-400" />
        @else
        <x-icon name="arrow-up" size="4" class="text-gray-300 group-hover:text-gray-400" />
        @endif
    </button>
    @else
    {{ $slot }}
    @endif
</th>
