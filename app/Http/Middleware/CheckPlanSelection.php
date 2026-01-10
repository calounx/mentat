<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class CheckPlanSelection
{
    /**
     * Handle an incoming request.
     *
     * Redirect to plan selection page if tenant requires plan selection.
     * Super admins bypass this check.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next): Response
    {
        $user = auth()->user();

        if (!$user || $user->isSuperAdmin()) {
            return $next($request);
        }

        $tenant = $user->currentTenant();

        if (!$tenant) {
            return $next($request);
        }

        // If tenant requires plan selection, redirect (unless already on plan selection page)
        if ($tenant->requiresPlanSelection() && !$request->routeIs('plan-selection')) {
            return redirect()->route('plan-selection');
        }

        return $next($request);
    }
}
