<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="refresh" content="5;url={{ route('login') }}">

    <title>403 - Access Denied</title>

    <link rel="preconnect" href="https://fonts.bunny.net">
    <link href="https://fonts.bunny.net/css?family=instrument-sans:400,500,600,700" rel="stylesheet" />
    <script src="https://cdn.tailwindcss.com"></script>

    <style>
        body {
            font-family: 'Instrument Sans', sans-serif;
        }
        @keyframes countdown {
            from { stroke-dashoffset: 0; }
            to { stroke-dashoffset: 283; }
        }
        .countdown-circle {
            animation: countdown 5s linear forwards;
        }
    </style>
</head>
<body class="antialiased bg-gray-900 min-h-screen flex items-center justify-center">
    <div class="text-center px-4">
        <!-- Lock Icon -->
        <div class="mb-8">
            <div class="inline-flex items-center justify-center w-24 h-24 rounded-full bg-red-500/10 border-2 border-red-500/50">
                <svg class="w-12 h-12 text-red-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 10-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 002.25-2.25v-6.75a2.25 2.25 0 00-2.25-2.25H6.75a2.25 2.25 0 00-2.25 2.25v6.75a2.25 2.25 0 002.25 2.25z" />
                </svg>
            </div>
        </div>

        <!-- Error Message -->
        <h1 class="text-4xl font-bold text-white mb-2">403</h1>
        <h2 class="text-xl font-medium text-gray-300 mb-4">Access Denied</h2>
        <p class="text-gray-500 max-w-md mx-auto mb-8">
            {{ $exception->getMessage() ?: 'You do not have permission to access this resource.' }}
        </p>

        <!-- Countdown Timer -->
        <div class="mb-8">
            <div class="relative inline-flex items-center justify-center">
                <svg class="w-16 h-16 transform -rotate-90">
                    <circle cx="32" cy="32" r="28" fill="none" stroke="#374151" stroke-width="4"/>
                    <circle cx="32" cy="32" r="28" fill="none" stroke="#3b82f6" stroke-width="4"
                            stroke-dasharray="283" stroke-dashoffset="0"
                            class="countdown-circle"/>
                </svg>
                <span id="countdown" class="absolute text-xl font-bold text-white">5</span>
            </div>
            <p class="mt-4 text-sm text-gray-500">Redirecting to login in <span id="countdown-text">5</span> seconds...</p>
        </div>

        <!-- Manual Action -->
        <div class="space-x-4">
            <a href="{{ route('login') }}"
               class="inline-flex items-center px-6 py-3 border border-transparent text-sm font-medium rounded-lg text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 focus:ring-offset-gray-900 transition-colors">
                <svg class="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9" />
                </svg>
                Go to Login
            </a>
            <a href="{{ url('/') }}"
               class="inline-flex items-center px-6 py-3 border border-gray-600 text-sm font-medium rounded-lg text-gray-300 hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500 focus:ring-offset-gray-900 transition-colors">
                <svg class="w-4 h-4 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12l8.954-8.955c.44-.439 1.152-.439 1.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25" />
                </svg>
                Go to Home
            </a>
        </div>
    </div>

    <script>
        let seconds = 5;
        const countdownEl = document.getElementById('countdown');
        const countdownTextEl = document.getElementById('countdown-text');

        const interval = setInterval(() => {
            seconds--;
            if (countdownEl) countdownEl.textContent = seconds;
            if (countdownTextEl) countdownTextEl.textContent = seconds;

            if (seconds <= 0) {
                clearInterval(interval);
                window.location.href = '{{ route("login") }}';
            }
        }, 1000);
    </script>
</body>
</html>
