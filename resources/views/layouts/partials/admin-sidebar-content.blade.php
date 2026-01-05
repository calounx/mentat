<!-- Logo -->
<div class="flex h-16 shrink-0 items-center">
    <a href="{{ route('admin.dashboard') }}" class="flex items-center gap-2">
        <span class="text-2xl font-bold text-orange-500">CHOM</span>
        <span class="text-sm font-medium text-gray-400">Admin</span>
    </a>
</div>

<!-- Navigation -->
<nav class="flex flex-1 flex-col">
    <ul role="list" class="flex flex-1 flex-col gap-y-7">
        <li>
            <ul role="list" class="-mx-2 space-y-1">
                <!-- Dashboard -->
                <li>
                    <a href="{{ route('admin.dashboard') }}"
                       class="group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 {{ request()->routeIs('admin.dashboard') ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white hover:bg-gray-700' }}">
                        <svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12l8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25" />
                        </svg>
                        Dashboard
                    </a>
                </li>

                <!-- VPS Management -->
                <li>
                    <a href="{{ route('admin.vps.index') }}"
                       class="group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 {{ request()->routeIs('admin.vps.*') ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white hover:bg-gray-700' }}">
                        <svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M5.25 14.25h13.5m-13.5 0a3 3 0 01-3-3m3 3a3 3 0 100 6h13.5a3 3 0 100-6m-16.5-3a3 3 0 013-3h13.5a3 3 0 013 3m-19.5 0a4.5 4.5 0 01.9-2.7L5.737 5.1a3.375 3.375 0 012.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 01.9 2.7m0 0a3 3 0 01-3 3m0 3h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008zm-3 6h.008v.008h-.008v-.008zm0-6h.008v.008h-.008v-.008z" />
                        </svg>
                        VPS Servers
                    </a>
                </li>

                <!-- Tenant Management -->
                <li>
                    <a href="{{ route('admin.tenants.index') }}"
                       class="group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 {{ request()->routeIs('admin.tenants.*') ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white hover:bg-gray-700' }}">
                        <svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 003.741-.479 3 3 0 00-4.682-2.72m.94 3.198l.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0112 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 016 18.719m12 0a5.971 5.971 0 00-.941-3.197m0 0A5.995 5.995 0 0012 12.75a5.995 5.995 0 00-5.058 2.772m0 0a3 3 0 00-4.681 2.72 8.986 8.986 0 003.74.477m.94-3.197a5.971 5.971 0 00-.94 3.197M15 6.75a3 3 0 11-6 0 3 3 0 016 0zm6 3a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0zm-13.5 0a2.25 2.25 0 11-4.5 0 2.25 2.25 0 014.5 0z" />
                        </svg>
                        Tenants
                    </a>
                </li>

                <!-- Site Overview -->
                <li>
                    <a href="{{ route('admin.sites.index') }}"
                       class="group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 {{ request()->routeIs('admin.sites.*') ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white hover:bg-gray-700' }}">
                        <svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M12 21a9.004 9.004 0 008.716-6.747M12 21a9.004 9.004 0 01-8.716-6.747M12 21c2.485 0 4.5-4.03 4.5-9S14.485 3 12 3m0 18c-2.485 0-4.5-4.03-4.5-9S9.515 3 12 3m0 0a8.997 8.997 0 017.843 4.582M12 3a8.997 8.997 0 00-7.843 4.582m15.686 0A11.953 11.953 0 0112 10.5c-2.998 0-5.74-1.1-7.843-2.918m15.686 0A8.959 8.959 0 0121 12c0 .778-.099 1.533-.284 2.253m0 0A17.919 17.919 0 0112 16.5c-3.162 0-6.133-.815-8.716-2.247m0 0A9.015 9.015 0 013 12c0-1.605.42-3.113 1.157-4.418" />
                        </svg>
                        All Sites
                    </a>
                </li>

                <!-- Plan Management -->
                <li>
                    <a href="{{ route('admin.plans.index') }}"
                       class="group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 {{ request()->routeIs('admin.plans.*') ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white hover:bg-gray-700' }}">
                        <svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z" />
                        </svg>
                        Plans
                    </a>
                </li>

                <!-- System Settings -->
                <li>
                    <a href="{{ route('admin.settings.index') }}"
                       class="group flex gap-x-3 rounded-md p-2 text-sm font-semibold leading-6 {{ request()->routeIs('admin.settings.*') ? 'bg-gray-700 text-white' : 'text-gray-400 hover:text-white hover:bg-gray-700' }}">
                        <svg class="h-6 w-6 shrink-0" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
                            <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                        </svg>
                        Settings
                    </a>
                </li>
            </ul>
        </li>

        <!-- Quick Stats -->
        <li class="mt-auto">
            <div class="rounded-lg bg-gray-700/50 p-4">
                <h3 class="text-xs font-semibold text-gray-400 uppercase tracking-wide">System Status</h3>
                <div class="mt-3 space-y-2">
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Environment</span>
                        <span class="font-medium {{ app()->environment('production') ? 'text-green-400' : 'text-yellow-400' }}">
                            {{ ucfirst(app()->environment()) }}
                        </span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Laravel</span>
                        <span class="font-medium text-white">{{ app()->version() }}</span>
                    </div>
                </div>
            </div>
        </li>
    </ul>
</nav>
