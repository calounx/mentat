@props([
    'striped' => false,
    'hoverable' => true,
])

<div {{ $attributes->merge(['class' => 'bg-white shadow rounded-lg overflow-hidden']) }}>
    <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200">
            @isset($header)
            <thead class="bg-gray-50">
                {{ $header }}
            </thead>
            @endisset

            <tbody class="bg-white divide-y divide-gray-200 {{ $striped ? 'divide-y divide-gray-200' : '' }}">
                {{ $slot }}
            </tbody>

            @isset($footer)
            <tfoot class="bg-gray-50">
                {{ $footer }}
            </tfoot>
            @endisset
        </table>
    </div>

    @isset($pagination)
    <div class="px-6 py-4 border-t border-gray-200">
        {{ $pagination }}
    </div>
    @endisset
</div>
