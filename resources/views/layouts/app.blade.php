<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="csrf-token" content="{{ csrf_token() }}">

    <title>{{ $title ?? 'CHOM' }} - Cloud Hosting Manager</title>

    <!-- Google Fonts - Distinctive Typography -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Crimson+Pro:wght@400;500;600;700&family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">

    <!-- Styles & Scripts -->
    @if (file_exists(public_path('build/manifest.json')) || file_exists(public_path('hot')))
        @vite(['resources/css/app.css', 'resources/js/app.js'])
    @else
        <script src="https://cdn.tailwindcss.com"></script>
        <style>
            @import url('https://fonts.googleapis.com/css2?family=Crimson+Pro:wght@400;500;600;700&family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap');
            body {
                font-family: 'DM Sans', system-ui, sans-serif;
                background: linear-gradient(135deg, #fafaf9 0%, #f5f5f4 100%);
            }
            h1, h2, h3, .font-display {
                font-family: 'Crimson Pro', Georgia, serif;
            }
        </style>
    @endif

    @livewireStyles

    <!-- Alpine.js cloak style (prevents flash of unstyled content) -->
    <style>[x-cloak] { display: none !important; }</style>
</head>
<body class="font-sans antialiased" style="background: linear-gradient(135deg, #fafaf9 0%, #f5f5f4 100%);" x-data="{ mobileMenuOpen: false }">
    <div class="min-h-screen">
        <!-- Refined Navigation -->
        <nav class="bg-white/80 backdrop-blur-xl border-b border-stone-200/60 sticky top-0 z-50">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                <div class="flex justify-between h-20">
                    <div class="flex items-center">
                        <!-- Elegant Logo -->
                        <div class="flex-shrink-0 flex items-center group">
                            <a href="{{ route('dashboard') }}" class="flex items-center gap-3 transition-all duration-300">
                                <!-- Jewel Icon -->
                                <div class="relative">
                                    <div class="absolute inset-0 bg-gradient-to-br from-emerald-500 to-sapphire-600 rounded-lg blur-lg opacity-40 group-hover:opacity-60 transition-opacity duration-300"></div>
                                    <div class="relative w-10 h-10 bg-gradient-to-br from-emerald-600 to-sapphire-700 rounded-lg flex items-center justify-center transform group-hover:scale-110 transition-transform duration-300">
                                        <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z"/>
                                        </svg>
                                    </div>
                                </div>
                                <!-- Brand Name -->
                                <div>
                                    <div class="font-display text-2xl font-semibold bg-gradient-to-r from-emerald-700 via-sapphire-700 to-emerald-700 bg-clip-text text-transparent tracking-tight">
                                        CHOM
                                    </div>
                                    <div class="text-[0.625rem] text-stone-500 tracking-widest uppercase font-medium -mt-1">
                                        Infrastructure Concierge
                                    </div>
                                </div>
                            </a>
                        </div>

                        <!-- Navigation Links (Desktop) - Refined -->
                        <div class="hidden sm:ml-12 sm:flex sm:space-x-1">
                            <a href="{{ route('dashboard') }}"
                               class="nav-link {{ request()->routeIs('dashboard') ? 'active' : '' }} inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-300
                                      {{ request()->routeIs('dashboard') ? 'text-emerald-700 bg-emerald-50/80' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }}">
                                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6"/>
                                </svg>
                                Dashboard
                            </a>
                            <a href="{{ route('sites.index') }}"
                               class="nav-link {{ request()->routeIs('sites.*') ? 'active' : '' }} inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-300
                                      {{ request()->routeIs('sites.*') ? 'text-emerald-700 bg-emerald-50/80' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }}">
                                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 01-9 9m9-9a9 9 0 00-9-9m9 9H3m9 9a9 9 0 01-9-9m9 9c1.657 0 3-4.03 3-9s-1.343-9-3-9m0 18c-1.657 0-3-4.03-3-9s1.343-9 3-9m-9 9a9 9 0 019-9"/>
                                </svg>
                                Sites
                            </a>
                            @if(!auth()->user()->isSuperAdmin() || auth()->user()->currentTenant())
                            <a href="{{ route('backups.index') }}"
                               class="nav-link {{ request()->routeIs('backups.*') ? 'active' : '' }} inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-300
                                      {{ request()->routeIs('backups.*') ? 'text-emerald-700 bg-emerald-50/80' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }}">
                                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4"/>
                                </svg>
                                Backups
                            </a>
                            <a href="{{ route('metrics.index') }}"
                               class="nav-link {{ request()->routeIs('metrics.*') ? 'active' : '' }} inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-300
                                      {{ request()->routeIs('metrics.*') ? 'text-emerald-700 bg-emerald-50/80' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }}">
                                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"/>
                                </svg>
                                Metrics
                            </a>
                            <a href="{{ route('team.index') }}"
                               class="nav-link {{ request()->routeIs('team.*') ? 'active' : '' }} inline-flex items-center px-4 py-2 text-sm font-medium rounded-lg transition-all duration-300
                                      {{ request()->routeIs('team.*') ? 'text-emerald-700 bg-emerald-50/80' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }}">
                                <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/>
                                </svg>
                                Team
                            </a>
                            @endif
                        </div>
                    </div>

                    <!-- User Menu (Desktop) - Elegant -->
                    <div class="hidden sm:ml-6 sm:flex sm:items-center gap-3">
                        @auth
                            <!-- Admin Badge -->
                            @if(auth()->user()->isSuperAdmin())
                                <a href="{{ route('admin.dashboard') }}" class="group inline-flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-champagne-800 bg-gradient-to-r from-champagne-100 to-champagne-50 rounded-full border border-champagne-200/60 hover:border-champagne-300 transition-all duration-300 hover:shadow-md">
                                    <svg class="h-4 w-4 text-champagne-600 group-hover:rotate-90 transition-transform duration-300" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
                                        <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                                    </svg>
                                    Admin
                                </a>
                            @endif

                            <!-- Organization Name -->
                            <div class="text-sm text-stone-500 font-medium">
                                {{ auth()->user()->organization?->name }}
                            </div>

                            <!-- User Menu Dropdown -->
                            <div x-data="{ userMenuOpen: false }" class="relative">
                                <button @click="userMenuOpen = !userMenuOpen"
                                        class="flex items-center gap-2 px-3 py-2 text-sm font-medium text-stone-700 rounded-lg hover:bg-stone-100 transition-all duration-300 group">
                                    <div class="w-8 h-8 rounded-full bg-gradient-to-br from-emerald-500 to-sapphire-600 flex items-center justify-center text-white font-semibold text-xs ring-2 ring-white shadow-md group-hover:ring-emerald-200 transition-all duration-300">
                                        {{ strtoupper(substr(auth()->user()->name, 0, 2)) }}
                                    </div>
                                    <span class="hidden md:block">{{ auth()->user()->name }}</span>
                                    <svg class="w-4 h-4 text-stone-400 transition-transform duration-300" :class="{'rotate-180': userMenuOpen}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
                                    </svg>
                                </button>

                                <!-- Dropdown Menu -->
                                <div x-show="userMenuOpen"
                                     @click.away="userMenuOpen = false"
                                     x-transition:enter="transition ease-out duration-200"
                                     x-transition:enter-start="opacity-0 scale-95"
                                     x-transition:enter-end="opacity-100 scale-100"
                                     x-transition:leave="transition ease-in duration-150"
                                     x-transition:leave-start="opacity-100 scale-100"
                                     x-transition:leave-end="opacity-0 scale-95"
                                     class="absolute right-0 mt-3 w-56 origin-top-right rounded-xl bg-white shadow-lg ring-1 ring-black/5 z-50 overflow-hidden"
                                     style="display: none;">
                                    <div class="p-3 bg-gradient-to-br from-stone-50 to-white border-b border-stone-100">
                                        <div class="text-sm font-semibold text-stone-900">{{ auth()->user()->name }}</div>
                                        <div class="text-xs text-stone-500 mt-1">{{ auth()->user()->email }}</div>
                                    </div>
                                    <div class="py-2">
                                        <a href="{{ route('profile.index') }}" class="flex items-center gap-3 px-4 py-2.5 text-sm text-stone-700 hover:bg-emerald-50 hover:text-emerald-700 transition-colors duration-200">
                                            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/>
                                            </svg>
                                            Profile Settings
                                        </a>
                                        <form method="POST" action="{{ route('logout') }}">
                                            @csrf
                                            <button type="submit" class="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-ruby-700 hover:bg-ruby-50 transition-colors duration-200">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"/>
                                                </svg>
                                                Sign Out
                                            </button>
                                        </form>
                                    </div>
                                </div>
                            </div>
                        @endauth
                    </div>

                    <!-- Mobile menu button -->
                    <div class="flex items-center sm:hidden">
                        <button @click="mobileMenuOpen = !mobileMenuOpen" type="button" class="inline-flex items-center justify-center p-2 rounded-lg text-stone-500 hover:text-emerald-700 hover:bg-emerald-50 transition-all duration-300">
                            <span class="sr-only">Open main menu</span>
                            <svg x-show="!mobileMenuOpen" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
                            </svg>
                            <svg x-show="mobileMenuOpen" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" style="display: none;">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                            </svg>
                        </button>
                    </div>
                </div>
            </div>

            <!-- Mobile menu -->
            <div x-show="mobileMenuOpen"
                 x-cloak
                 x-transition:enter="transition ease-out duration-200"
                 x-transition:enter-start="opacity-0 -translate-y-2"
                 x-transition:enter-end="opacity-100 translate-y-0"
                 x-transition:leave="transition ease-in duration-150"
                 x-transition:leave-start="opacity-100 translate-y-0"
                 x-transition:leave-end="opacity-0 -translate-y-2"
                 class="sm:hidden border-t border-stone-200 bg-white/95 backdrop-blur-xl">
                <div class="px-4 pt-2 pb-3 space-y-1">
                    <a href="{{ route('dashboard') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium {{ request()->routeIs('dashboard') ? 'text-emerald-700 bg-emerald-50' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }} transition-colors duration-200">
                        Dashboard
                    </a>
                    <a href="{{ route('sites.index') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium {{ request()->routeIs('sites.*') ? 'text-emerald-700 bg-emerald-50' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }} transition-colors duration-200">
                        Sites
                    </a>
                    @if(!auth()->user()->isSuperAdmin() || auth()->user()->currentTenant())
                    <a href="{{ route('backups.index') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium {{ request()->routeIs('backups.*') ? 'text-emerald-700 bg-emerald-50' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }} transition-colors duration-200">
                        Backups
                    </a>
                    <a href="{{ route('metrics.index') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium {{ request()->routeIs('metrics.*') ? 'text-emerald-700 bg-emerald-50' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }} transition-colors duration-200">
                        Metrics
                    </a>
                    <a href="{{ route('team.index') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium {{ request()->routeIs('team.*') ? 'text-emerald-700 bg-emerald-50' : 'text-stone-600 hover:text-emerald-700 hover:bg-stone-50' }} transition-colors duration-200">
                        Team
                    </a>
                    @endif
                </div>
                @auth
                    <div class="pt-4 pb-3 border-t border-stone-200">
                        <div class="px-4 mb-3">
                            <div class="flex items-center gap-3">
                                <div class="w-10 h-10 rounded-full bg-gradient-to-br from-emerald-500 to-sapphire-600 flex items-center justify-center text-white font-semibold shadow-md">
                                    {{ strtoupper(substr(auth()->user()->name, 0, 2)) }}
                                </div>
                                <div class="flex-1">
                                    <div class="text-base font-semibold text-stone-900">{{ auth()->user()->name }}</div>
                                    <div class="text-sm text-stone-500">{{ auth()->user()->email }}</div>
                                    @if(auth()->user()->organization)
                                        <div class="text-xs text-stone-400 mt-0.5">{{ auth()->user()->organization->name }}</div>
                                    @endif
                                </div>
                            </div>
                        </div>
                        <div class="px-4 space-y-1">
                            @if(auth()->user()->isSuperAdmin())
                                <a href="{{ route('admin.dashboard') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium text-champagne-800 bg-champagne-50 border border-champagne-200/60">
                                    Admin Panel
                                </a>
                            @endif
                            <a href="{{ route('profile.index') }}" class="block px-3 py-2.5 rounded-lg text-base font-medium text-stone-600 hover:text-emerald-700 hover:bg-emerald-50 transition-colors duration-200">
                                Profile Settings
                            </a>
                            <form method="POST" action="{{ route('logout') }}">
                                @csrf
                                <button type="submit" class="w-full text-left px-3 py-2.5 rounded-lg text-base font-medium text-ruby-700 hover:bg-ruby-50 transition-colors duration-200">
                                    Sign Out
                                </button>
                            </form>
                        </div>
                    </div>
                @endauth
            </div>
        </nav>

        <!-- Page Content -->
        <main class="py-8 lg:py-12">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                {{ $slot }}
            </div>
        </main>

        <!-- Elegant Footer -->
        <footer class="mt-auto border-t border-stone-200/60 bg-white/40 backdrop-blur-sm">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
                <div class="flex flex-col md:flex-row justify-between items-center gap-4">
                    <div class="text-sm text-stone-500">
                        <span class="font-display font-semibold text-stone-700">CHOM</span> — Infrastructure management, refined.
                    </div>
                    <div class="flex items-center gap-6 text-xs text-stone-400">
                        <span>© {{ date('Y') }} All rights reserved</span>
                        <span class="hidden sm:inline">•</span>
                        <span class="font-mono">v2.2.0</span>
                    </div>
                </div>
            </div>
        </footer>
    </div>

    @livewireScripts
</body>
</html>
