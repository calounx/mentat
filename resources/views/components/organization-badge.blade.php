@props(['status'])

@php
$colors = [
    'active' => 'bg-green-100 text-green-800',
    'suspended' => 'bg-yellow-100 text-yellow-800',
    'cancelled' => 'bg-red-100 text-red-800',
];
@endphp

<span {{ $attributes->merge(['class' => 'inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ' . ($colors[$status] ?? 'bg-gray-100 text-gray-800')]) }}>
    {{ ucfirst($status) }}
</span>
