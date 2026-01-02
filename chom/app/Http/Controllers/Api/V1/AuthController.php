<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\V1\LoginRequest;
use App\Http\Requests\V1\RegisterRequest;
use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rules\Password;

class AuthController extends Controller
{
    /**
     * Register a new user with organization.
     */
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users'],
            'password' => ['required', 'confirmed', Password::defaults()],
            'organization_name' => ['required', 'string', 'max:255'],
        ]);

        try {
            DB::beginTransaction();

            try {
                // Create organization first (without default_tenant_id to avoid circular dependency)
                $organization = Organization::create([
                    'name' => $validated['organization_name'],
                    'slug' => Str::slug($validated['organization_name']).'-'.Str::random(6),
                    'billing_email' => $validated['email'],
                    'default_tenant_id' => null,
                ]);

                // Now create the tenant with the organization_id
                $tenant = Tenant::create([
                    'organization_id' => $organization->id,
                    'name' => 'Default',
                    'slug' => 'default',
                    'tier' => 'starter',
                    'status' => 'active',
                ]);

                // Update organization with the default tenant
                $organization->update(['default_tenant_id' => $tenant->id]);

                // Create user as owner
                $user = User::create([
                    'name' => $validated['name'],
                    'email' => $validated['email'],
                    'password' => $validated['password'],
                    'organization_id' => $organization->id,
                    'role' => 'owner',
                ]);

                DB::commit();

                $result = compact('user', 'organization', 'tenant');
            } catch (\Exception $e) {
                DB::rollBack();
                throw $e;
            }

            // Create API token
            $token = $result['user']->createToken('api-token')->plainTextToken;

            return response()->json([
                'user' => [
                    'id' => $result['user']->id,
                    'name' => $result['user']->name,
                    'email' => $result['user']->email,
                    'role' => $result['user']->role,
                ],
                'token' => $token,
            ], 201);
        } catch (\Exception $e) {
            // Log the actual error for debugging
            \Log::error('Registration failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            return response()->json([
                'message' => 'Registration failed',
                'errors' => [
                    'server' => ['Failed to create account. Please try again.'],
                ],
            ], 500);
        }
    }

    /**
     * Login user and return token.
     */
    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email'],
            'password' => ['required', 'string'],
            'remember' => ['sometimes', 'boolean'],
        ]);

        if (! Auth::attempt(['email' => $validated['email'], 'password' => $validated['password']], $validated['remember'] ?? false)) {
            return response()->json([
                'message' => 'Invalid credentials',
            ], 401);
        }

        $user = Auth::user();

        // Check if organization exists
        if (! $user->organization) {
            return response()->json([
                'message' => 'User is not associated with an organization.',
            ], 403);
        }

        // Create new token with appropriate expiration
        $tokenName = 'api-token';
        $expiresAt = ($validated['remember'] ?? false) ? now()->addDays(30) : now()->addDay();

        $token = $user->createToken($tokenName, ['*'], $expiresAt)->plainTextToken;

        return response()->json([
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
            ],
            'token' => $token,
        ], 200);
    }

    /**
     * Logout user (revoke current token).
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json([
            'message' => 'Logged out successfully',
        ], 200);
    }

    /**
     * Get current authenticated user.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        $user->load('organization');

        return response()->json([
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
        ], 200);
    }

    /**
     * Refresh API token.
     */
    public function refresh(Request $request): JsonResponse
    {
        $user = $request->user();

        // Delete current token
        $user->currentAccessToken()->delete();

        // Create new token with 1 day expiration
        $token = $user->createToken('api-token', ['*'], now()->addDay())->plainTextToken;

        return response()->json([
            'token' => $token,
        ], 200);
    }
}
