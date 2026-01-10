<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

class CheckUserApprovalStatus
{
    /**
     * Handle an incoming request.
     *
     * Check if authenticated user is approved before allowing access.
     * Super admins bypass this check.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = Auth::user();

        if (!$user) {
            return redirect()->route('login');
        }

        // Super admins bypass approval check
        if ($user->isSuperAdmin()) {
            return $next($request);
        }

        // Check user approval status
        if ($user->isPending()) {
            Auth::logout();
            return redirect()->route('login')->withErrors([
                'email' => 'Your account is pending administrator approval. Please check your email for updates.',
            ]);
        }

        if ($user->isRejected()) {
            Auth::logout();
            return redirect()->route('login')->withErrors([
                'email' => 'Your account application was not approved. Please contact support for more information.',
            ]);
        }

        // Check organization approval
        if ($user->organization && !$user->organization->isApproved()) {
            Auth::logout();
            return redirect()->route('login')->withErrors([
                'email' => 'Your organization is pending approval. Please wait for administrator review.',
            ]);
        }

        return $next($request);
    }
}
