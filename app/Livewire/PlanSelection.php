<?php

namespace App\Livewire;

use App\Models\TierLimit;
use Illuminate\Support\Facades\Log;
use Livewire\Component;

class PlanSelection extends Component
{
    public array $plans = [];
    public ?string $error = null;

    public function mount(): void
    {
        $tenant = auth()->user()->currentTenant();

        // If tenant doesn't require plan selection, redirect to dashboard
        if (! $tenant || ! $tenant->requiresPlanSelection()) {
            redirect()->route('dashboard');

            return;
        }

        // Get plans from database
        $tierLimits = TierLimit::active()
            ->currentlyValid()
            ->orderByRaw("CASE tier WHEN 'starter' THEN 1 WHEN 'pro' THEN 2 WHEN 'enterprise' THEN 3 ELSE 4 END")
            ->get();

        $this->plans = $tierLimits->map(function ($tierLimit) {
            return [
                'tier' => $tierLimit->tier,
                'name' => ucfirst($tierLimit->tier),
                'price' => $this->getPriceDisplay($tierLimit->tier),
                'features' => $this->getFeatures($tierLimit),
                'is_recommended' => $tierLimit->tier === 'pro',
            ];
        })->toArray();
    }

    protected function getPriceDisplay(string $tier): string
    {
        return match ($tier) {
            'starter' => 'Free',
            'pro' => '$29/month',
            'enterprise' => '$99/month',
            default => 'Contact Us',
        };
    }

    protected function getFeatures($tierLimit): array
    {
        $features = [
            "Up to {$tierLimit->max_sites} sites",
        ];

        if ($tierLimit->max_backups_per_site > 0) {
            $features[] = $tierLimit->max_backups_per_site.' backups per site';
        } else {
            $features[] = 'Unlimited backups';
        }

        // Add tier-specific features
        $features = array_merge($features, match ($tierLimit->tier) {
            'starter' => [
                'Basic monitoring',
                'Email support',
                'Community access',
            ],
            'pro' => [
                'Advanced monitoring',
                'Priority email support',
                'Custom domains',
                'API access',
            ],
            'enterprise' => [
                'Real-time monitoring',
                '24/7 phone support',
                'Custom SLA',
                'Dedicated account manager',
                'White-label options',
            ],
            default => [],
        });

        return $features;
    }

    public function selectPlan(string $tier): void
    {
        $tenant = auth()->user()->currentTenant();

        if (! $tenant) {
            $this->error = 'No tenant found. Please contact support.';

            return;
        }

        try {
            $tenant->selectPlan($tier);

            session()->flash('success', 'Plan selected successfully! Welcome to CHOM.');

            redirect()->route('dashboard');
        } catch (\Exception $e) {
            Log::error('Plan selection error', ['error' => $e->getMessage(), 'tier' => $tier]);
            $this->error = 'Failed to select plan: '.$e->getMessage();
        }
    }

    public function render()
    {
        return view('livewire.plan-selection', [
            'plans' => $this->plans,
        ])->layout('layouts.guest', ['title' => 'Select Your Plan']);
    }
}
