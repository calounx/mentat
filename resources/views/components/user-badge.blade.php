@props(['role'])

@php
$colors = [
    'owner' => 'bg-purple-100 text-purple-800',
    'admin' => 'bg-blue-100 text-blue-800',
    'member' => 'bg-green-100 text-green-800',
    'viewer' => 'bg-gray-100 text-gray-800',
];
@endphp

<span {{ $attributes->merge(['class' => 'inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ' . ($colors[$role] ?? 'bg-gray-100 text-gray-800')]) }}>
    {{ ucfirst($role) }}
</span>
