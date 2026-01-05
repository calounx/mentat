<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Ensure the authenticated user has an associated tenant.
 *
 * Super admins without a tenant are redirected to the admin dashboard.
 * Regular users without a tenant see an error message.
 */
class EnsureHasTenant
{
    /**
     * Handle an incoming request.
     *
     * @param Request $request
     * @param Closure $next
     * @return Response
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (!$user) {
            return redirect()->route('login');
        }

        $tenant = $user->currentTenant();

        if (!$tenant) {
            // Super admins without a tenant should use admin dashboard
            if ($user->isSuperAdmin()) {
                return redirect()->route('admin.dashboard')
                    ->with('info', 'You do not have a customer tenant. Use the admin panel to manage the system.');
            }

            // Regular users without a tenant - something is wrong with their account
            abort(403, 'No tenant configured for your account. Please contact support.');
        }

        return $next($request);
    }
}
