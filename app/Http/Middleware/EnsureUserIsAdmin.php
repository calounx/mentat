<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Middleware to ensure the authenticated user has admin privileges.
 *
 * Admin users are those with 'owner' or 'admin' roles.
 * This middleware should be applied to routes that manage infrastructure,
 * security, or operations that could expose data from other tenants.
 */
class EnsureUserIsAdmin
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (!$user || !$user->isAdmin()) {
            if ($request->expectsJson()) {
                return response()->json([
                    'success' => false,
                    'error' => [
                        'code' => 'FORBIDDEN',
                        'message' => 'This action requires administrator privileges.',
                    ],
                ], 403);
            }

            abort(403, 'This action requires administrator privileges.');
        }

        return $next($request);
    }
}
