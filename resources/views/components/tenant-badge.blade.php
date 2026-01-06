@props(['status', 'tier' => null])

@php
$statusColors = [
    'active' => 'bg-green-100 text-green-800',
    'pending' => 'bg-yellow-100 text-yellow-800',
    'suspended' => 'bg-red-100 text-red-800',
];

$tierColors = [
    'starter' => 'bg-gray-100 text-gray-800',
    'pro' => 'bg-blue-100 text-blue-800',
    'enterprise' => 'bg-purple-100 text-purple-800',
];
@endphp

<div class="flex items-center gap-2">
    <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $statusColors[$status] ?? 'bg-gray-100 text-gray-800' }}">
        {{ ucfirst($status) }}
    </span>

    @if($tier)
        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $tierColors[$tier] ?? 'bg-gray-100 text-gray-800' }}">
            {{ ucfirst($tier) }}
        </span>
    @endif
</div>
