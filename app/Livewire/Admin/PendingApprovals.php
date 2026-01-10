<?php

namespace App\Livewire\Admin;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\UserApproved;
use App\Notifications\UserRejected;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Livewire\Component;
use Livewire\WithPagination;

class PendingApprovals extends Component
{
    use WithPagination;

    public string $search = '';
    public string $filter = 'all'; // all, verified, unverified

    public bool $showApproveModal = false;
    public bool $showRejectModal = false;
    public ?string $selectedUserId = null;
    public string $approvalNotes = '';
    public string $rejectionReason = '';

    public ?string $error = null;
    public ?string $success = null;

    protected $queryString = ['search' => ['except' => '']];

    public function updatingSearch(): void
    {
        $this->resetPage();
    }

    public function openApproveUserModal(string $userId): void
    {
        $this->selectedUserId = $userId;
        $this->approvalNotes = '';
        $this->showApproveModal = true;
        $this->error = null;
    }

    public function approveUser(): void
    {
        try {
            $user = User::with('organization')->findOrFail($this->selectedUserId);
            $organization = $user->organization;

            if (! $organization) {
                $this->error = 'User has no organization. Cannot approve.';

                return;
            }

            DB::transaction(function () use ($user, $organization) {
                // Approve user
                $user->approve(auth()->user());

                // Approve organization
                $organization->approve(auth()->user(), $this->approvalNotes);

                // Approve tenant (find the tenant for this organization)
                $tenant = Tenant::where('organization_id', $organization->id)->first();
                if ($tenant) {
                    $tenant->update([
                        'is_approved' => true,
                        'approved_at' => now(),
                    ]);
                }

                // Send notification
                $user->notify(new UserApproved($user, $organization));
            });

            $this->success = "User '{$user->fullName()}' and organization '{$organization->name}' approved successfully.";
            $this->closeApproveModal();
        } catch (\Exception $e) {
            Log::error('User approval error', ['error' => $e->getMessage(), 'user_id' => $this->selectedUserId]);
            $this->error = 'Failed to approve: '.$e->getMessage();
        }
    }

    public function openRejectUserModal(string $userId): void
    {
        $this->selectedUserId = $userId;
        $this->rejectionReason = '';
        $this->showRejectModal = true;
        $this->error = null;
    }

    public function rejectUser(): void
    {
        $this->validate([
            'rejectionReason' => 'required|string|min:10',
        ]);

        try {
            $user = User::with('organization')->findOrFail($this->selectedUserId);
            $organization = $user->organization;

            DB::transaction(function () use ($user, $organization) {
                // Reject user (automatically adds to spam tracking)
                $user->reject(auth()->user(), $this->rejectionReason);

                // Reject organization
                if ($organization) {
                    $organization->reject(auth()->user(), $this->rejectionReason);
                }

                // Send notification
                $user->notify(new UserRejected($user, $this->rejectionReason));
            });

            $this->success = "User '{$user->fullName()}' rejected. Email added to spam tracking.";
            $this->closeRejectModal();
        } catch (\Exception $e) {
            Log::error('User rejection error', ['error' => $e->getMessage(), 'user_id' => $this->selectedUserId]);
            $this->error = 'Failed to reject: '.$e->getMessage();
        }
    }

    public function closeApproveModal(): void
    {
        $this->showApproveModal = false;
        $this->selectedUserId = null;
        $this->approvalNotes = '';
        $this->error = null;
    }

    public function closeRejectModal(): void
    {
        $this->showRejectModal = false;
        $this->selectedUserId = null;
        $this->rejectionReason = '';
        $this->error = null;
    }

    public function render()
    {
        $pendingUsers = User::where('approval_status', 'pending')
            ->with(['organization'])
            ->when($this->search, function ($query) {
                $query->where(function ($q) {
                    $q->where('username', 'like', "%{$this->search}%")
                        ->orWhere('first_name', 'like', "%{$this->search}%")
                        ->orWhere('last_name', 'like', "%{$this->search}%")
                        ->orWhere('email', 'like', "%{$this->search}%");
                });
            })
            ->when($this->filter === 'verified', function ($query) {
                $query->whereNotNull('email_verified_at');
            })
            ->when($this->filter === 'unverified', function ($query) {
                $query->whereNull('email_verified_at');
            })
            ->orderBy('created_at', 'desc')
            ->paginate(15);

        $stats = [
            'pending_total' => User::where('approval_status', 'pending')->count(),
            'pending_verified' => User::where('approval_status', 'pending')
                ->whereNotNull('email_verified_at')->count(),
            'pending_unverified' => User::where('approval_status', 'pending')
                ->whereNull('email_verified_at')->count(),
            'approved_today' => User::where('approval_status', 'approved')
                ->whereDate('approved_at', today())->count(),
            'rejected_total' => User::where('approval_status', 'rejected')->count(),
        ];

        return view('livewire.admin.pending-approvals', [
            'pendingUsers' => $pendingUsers,
            'stats' => $stats,
        ])->layout('layouts.admin', ['title' => 'Pending Approvals']);
    }
}
