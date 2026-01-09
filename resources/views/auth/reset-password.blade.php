<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Reset Password - {{ config('chom.name', 'CHOM') }}</title>

    <!-- Fonts -->
    <link rel="preconnect" href="https://fonts.bunny.net">
    <link href="https://fonts.bunny.net/css?family=instrument-sans:400,500,600,700" rel="stylesheet" />

    <!-- Styles -->
    @if (file_exists(public_path('build/manifest.json')) || file_exists(public_path('hot')))
        @vite(['resources/css/app.css', 'resources/js/app.js'])
    @else
        <script src="https://cdn.tailwindcss.com"></script>
    @endif
</head>
<body class="bg-gray-100 min-h-screen flex items-center justify-center">
    <div class="max-w-md w-full mx-4">
        <div class="text-center mb-8">
            <h1 class="text-3xl font-bold text-blue-600">CHOM</h1>
            <p class="text-gray-600 mt-2">Cloud Hosting & Observability Manager</p>
        </div>

        <div class="bg-white rounded-lg shadow-md p-8">
            <h2 class="text-xl font-semibold text-gray-900 mb-2">Reset your password</h2>
            <p class="text-sm text-gray-600 mb-6">
                Please enter your new password below. Your password must be at least 8 characters and contain uppercase letters, lowercase letters, and numbers.
            </p>

            @if($errors->any())
                <div class="bg-red-50 border-l-4 border-red-400 p-4 mb-6">
                    <div class="text-sm text-red-700">
                        @foreach($errors->all() as $error)
                            <p>{{ $error }}</p>
                        @endforeach
                    </div>
                </div>
            @endif

            <form method="POST" action="{{ route('password.update') }}">
                @csrf

                <input type="hidden" name="token" value="{{ $token }}">
                <input type="hidden" name="email" value="{{ $email }}">

                <div class="mb-4">
                    <label for="email" class="block text-sm font-medium text-gray-700 mb-1">
                        Email address
                    </label>
                    <input type="email"
                           id="email"
                           name="email"
                           value="{{ old('email', $email) }}"
                           required
                           readonly
                           class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm bg-gray-50 focus:ring-blue-500 focus:border-blue-500">
                </div>

                <div class="mb-4">
                    <label for="password" class="block text-sm font-medium text-gray-700 mb-1">
                        New Password
                    </label>
                    <input type="password"
                           id="password"
                           name="password"
                           required
                           autofocus
                           class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500">
                    <p class="mt-1 text-xs text-gray-500">Minimum 8 characters with uppercase, lowercase, and numbers</p>
                </div>

                <div class="mb-6">
                    <label for="password_confirmation" class="block text-sm font-medium text-gray-700 mb-1">
                        Confirm Password
                    </label>
                    <input type="password"
                           id="password_confirmation"
                           name="password_confirmation"
                           required
                           class="w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm focus:ring-blue-500 focus:border-blue-500">
                </div>

                <button type="submit"
                        class="w-full py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500">
                    Reset Password
                </button>
            </form>

            <p class="mt-6 text-center text-sm text-gray-600">
                Remember your password?
                <a href="{{ route('login') }}" class="font-medium text-blue-600 hover:text-blue-500">
                    Back to login
                </a>
            </p>
        </div>

        <div class="mt-4 bg-yellow-50 border border-yellow-200 rounded-md p-4">
            <p class="text-xs text-yellow-800">
                <strong>Note:</strong> This password reset link will expire in 60 minutes for security purposes.
            </p>
        </div>
    </div>
</body>
</html>
