<div class="py-12">
    <div class="max-w-7xl mx-auto sm:px-6 lg:px-8">
        <!-- Header -->
        <div class="mb-8">
            <h2 class="text-3xl font-bold text-white">Pending Approvals</h2>
            <p class="mt-1 text-sm text-gray-400">Review and approve or reject new user registrations</p>
        </div>

        <!-- Flash Messages -->
        @if($success)
            <div class="mb-6 rounded-md bg-green-800/50 border border-green-700 p-4">
                <div class="flex">
                    <svg class="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
                    </svg>
                    <div class="ml-3">
                        <p class="text-sm font-medium text-green-300">{{ $success }}</p>
                    </div>
                </div>
            </div>
        @endif

        @if($error)
            <div class="mb-6 rounded-md bg-red-800/50 border border-red-700 p-4">
                <div class="flex">
                    <svg class="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                    </svg>
                    <div class="ml-3">
                        <p class="text-sm font-medium text-red-300">{{ $error }}</p>
                    </div>
                </div>
            </div>
        @endif

        <!-- Stats -->
        <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-5 mb-6">
            <div class="bg-gray-800 border border-gray-700 overflow-hidden rounded-lg">
                <div class="p-5">
                    <div class="flex items-center">
                        <div class="flex-shrink-0">
                            <svg class="h-6 w-6 text-yellow-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                        </div>
                        <div class="ml-5 w-0 flex-1">
                            <dl>
                                <dt class="text-sm font-medium text-gray-400 truncate">Pending Total</dt>
                                <dd class="text-lg font-semibold text-white">{{ $stats['pending_total'] }}</dd>
                            </dl>
                        </div>
                    </div>
                </div>
            </div>

            <div class="bg-gray-800 border border-gray-700 overflow-hidden rounded-lg">
                <div class="p-5">
                    <div class="flex items-center">
                        <div class="flex-shrink-0">
                            <svg class="h-6 w-6 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                        </div>
                        <div class="ml-5 w-0 flex-1">
                            <dl>
                                <dt class="text-sm font-medium text-gray-400 truncate">Email Verified</dt>
                                <dd class="text-lg font-semibold text-white">{{ $stats['pending_verified'] }}</dd>
                            </dl>
                        </div>
                    </div>
                </div>
            </div>

            <div class="bg-gray-800 border border-gray-700 overflow-hidden rounded-lg">
                <div class="p-5">
                    <div class="flex items-center">
                        <div class="flex-shrink-0">
                            <svg class="h-6 w-6 text-red-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
                            </svg>
                        </div>
                        <div class="ml-5 w-0 flex-1">
                            <dl>
                                <dt class="text-sm font-medium text-gray-400 truncate">Unverified</dt>
                                <dd class="text-lg font-semibold text-white">{{ $stats['pending_unverified'] }}</dd>
                            </dl>
                        </div>
                    </div>
                </div>
            </div>

            <div class="bg-gray-800 border border-gray-700 overflow-hidden rounded-lg">
                <div class="p-5">
                    <div class="flex items-center">
                        <div class="flex-shrink-0">
                            <svg class="h-6 w-6 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z" />
                            </svg>
                        </div>
                        <div class="ml-5 w-0 flex-1">
                            <dl>
                                <dt class="text-sm font-medium text-gray-400 truncate">Approved Today</dt>
                                <dd class="text-lg font-semibold text-white">{{ $stats['approved_today'] }}</dd>
                            </dl>
                        </div>
                    </div>
                </div>
            </div>

            <div class="bg-gray-800 border border-gray-700 overflow-hidden rounded-lg">
                <div class="p-5">
                    <div class="flex items-center">
                        <div class="flex-shrink-0">
                            <svg class="h-6 w-6 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
                            </svg>
                        </div>
                        <div class="ml-5 w-0 flex-1">
                            <dl>
                                <dt class="text-sm font-medium text-gray-400 truncate">Rejected Total</dt>
                                <dd class="text-lg font-semibold text-white">{{ $stats['rejected_total'] }}</dd>
                            </dl>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Filters -->
        <div class="bg-gray-800 border border-gray-700 rounded-lg p-6 mb-6">
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
                <div>
                    <label for="search" class="block text-sm font-medium text-gray-300 mb-1">Search</label>
                    <input type="text" id="search" wire:model.live.debounce.300ms="search" placeholder="Username, name, or email..." class="block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-orange-500 focus:ring-orange-500 sm:text-sm">
                </div>

                <div>
                    <label for="filter" class="block text-sm font-medium text-gray-300 mb-1">Email Status</label>
                    <select id="filter" wire:model.live="filter" class="block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-orange-500 focus:ring-orange-500 sm:text-sm">
                        <option value="all">All</option>
                        <option value="verified">Email Verified</option>
                        <option value="unverified">Email Unverified</option>
                    </select>
                </div>

                <div class="flex items-end">
                    <button wire:click="$set('search', '')" class="w-full px-4 py-2 bg-gray-700 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500">
                        Clear Search
                    </button>
                </div>
            </div>
        </div>

        <!-- Pending Users Table -->
        <div class="bg-gray-800 border border-gray-700 rounded-lg overflow-hidden">
            <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-700">
                    <thead class="bg-gray-700">
                        <tr>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">User</th>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Organization</th>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Email Status</th>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Registered</th>
                            <th scope="col" class="px-6 py-3 text-right text-xs font-medium text-gray-300 uppercase tracking-wider">Actions</th>
                        </tr>
                    </thead>
                    <tbody class="bg-gray-800 divide-y divide-gray-700">
                        @forelse($pendingUsers as $user)
                            <tr class="hover:bg-gray-700">
                                <td class="px-6 py-4 whitespace-nowrap">
                                    <div class="flex items-center">
                                        <div class="flex-shrink-0 h-10 w-10">
                                            <div class="h-10 w-10 rounded-full bg-gradient-to-br from-blue-400 to-blue-600 flex items-center justify-center">
                                                <span class="text-white font-semibold">{{ strtoupper(substr($user->first_name, 0, 1)) }}</span>
                                            </div>
                                        </div>
                                        <div class="ml-4">
                                            <div class="text-sm font-medium text-white">{{ $user->fullName() }}</div>
                                            <div class="text-xs text-gray-400">@{{ $user->username }}</div>
                                            <div class="text-xs text-gray-400">{{ $user->email }}</div>
                                        </div>
                                    </div>
                                </td>
                                <td class="px-6 py-4 whitespace-nowrap">
                                    <div class="text-sm text-white">{{ $user->organization?->name ?? 'N/A' }}</div>
                                    @if($user->organization?->isFictive())
                                        <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-700 text-gray-300">
                                            Fictive
                                        </span>
                                    @endif
                                </td>
                                <td class="px-6 py-4 whitespace-nowrap">
                                    @if($user->email_verified_at)
                                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-900/50 text-green-300">
                                            <svg class="mr-1 h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                                                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
                                            </svg>
                                            Verified
                                        </span>
                                    @else
                                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-900/50 text-yellow-300">
                                            <svg class="mr-1 h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                                                <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
                                            </svg>
                                            Pending
                                        </span>
                                    @endif
                                </td>
                                <td class="px-6 py-4 whitespace-nowrap">
                                    <div class="text-sm text-gray-400">{{ $user->created_at->format('M d, Y') }}</div>
                                    <div class="text-xs text-gray-500">{{ $user->created_at->diffForHumans() }}</div>
                                </td>
                                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium space-x-2">
                                    <button wire:click="openApproveUserModal('{{ $user->id }}')"
                                            class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500">
                                        <svg class="mr-1 h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z" clip-rule="evenodd" />
                                        </svg>
                                        Approve
                                    </button>
                                    <button wire:click="openRejectUserModal('{{ $user->id }}')"
                                            class="inline-flex items-center px-3 py-1.5 border border-transparent text-xs font-medium rounded text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500">
                                        <svg class="mr-1 h-3 w-3" fill="currentColor" viewBox="0 0 20 20">
                                            <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
                                        </svg>
                                        Reject
                                    </button>
                                </td>
                            </tr>
                        @empty
                            <tr>
                                <td colspan="5" class="px-6 py-12 text-center">
                                    <svg class="mx-auto h-12 w-12 text-gray-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
                                    </svg>
                                    <h3 class="mt-2 text-sm font-medium text-gray-400">No pending approvals</h3>
                                    <p class="mt-1 text-sm text-gray-500">All user registrations have been reviewed.</p>
                                </td>
                            </tr>
                        @endforelse
                    </tbody>
                </table>
            </div>

            <!-- Pagination -->
            <div class="px-6 py-4 border-t border-gray-700">
                {{ $pendingUsers->links() }}
            </div>
        </div>
    </div>

    <!-- Approve Modal -->
    @if($showApproveModal)
        <div class="fixed inset-0 z-50 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen px-4">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75" wire:click="closeApproveModal"></div>

                <div class="relative bg-gray-800 rounded-lg max-w-lg w-full border border-gray-700">
                    <form wire:submit="approveUser">
                        <div class="px-6 py-4 border-b border-gray-700">
                            <h3 class="text-lg font-medium text-white">Approve User</h3>
                        </div>

                        <div class="px-6 py-4 space-y-4">
                            @if($error)
                                <div class="bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                    <p class="text-sm text-red-200">{{ $error }}</p>
                                </div>
                            @endif

                            <p class="text-sm text-gray-300">
                                Are you sure you want to approve this user and their organization? They will be notified via email and can then select a plan and start using the platform.
                            </p>

                            <div>
                                <label for="approvalNotes" class="block text-sm font-medium text-gray-300">Approval Notes (Optional)</label>
                                <textarea wire:model="approvalNotes" id="approvalNotes" rows="3"
                                          class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-green-500 focus:ring-green-500"
                                          placeholder="Add any internal notes about this approval..."></textarea>
                                <p class="mt-1 text-xs text-gray-400">These notes are for internal use only and will not be sent to the user.</p>
                            </div>
                        </div>

                        <div class="px-6 py-4 bg-gray-700 flex justify-end space-x-3">
                            <button type="button" wire:click="closeApproveModal"
                                    class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600">
                                Cancel
                            </button>
                            <button type="submit"
                                    class="px-4 py-2 bg-green-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-green-700">
                                Approve User
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif

    <!-- Reject Modal -->
    @if($showRejectModal)
        <div class="fixed inset-0 z-50 overflow-y-auto">
            <div class="flex items-center justify-center min-h-screen px-4">
                <div class="fixed inset-0 bg-gray-900 bg-opacity-75" wire:click="closeRejectModal"></div>

                <div class="relative bg-gray-800 rounded-lg max-w-lg w-full border border-gray-700">
                    <form wire:submit="rejectUser">
                        <div class="px-6 py-4 border-b border-gray-700">
                            <h3 class="text-lg font-medium text-white">Reject User</h3>
                        </div>

                        <div class="px-6 py-4 space-y-4">
                            @if($error)
                                <div class="bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
                                    <p class="text-sm text-red-200">{{ $error }}</p>
                                </div>
                            @endif

                            <div class="bg-yellow-900/30 border-l-4 border-yellow-500 p-4 rounded">
                                <p class="text-sm text-yellow-200">
                                    <strong>Warning:</strong> Rejecting this user will prevent them from re-registering with the same email address. This action cannot be undone.
                                </p>
                            </div>

                            <div>
                                <label for="rejectionReason" class="block text-sm font-medium text-gray-300">Rejection Reason <span class="text-red-400">*</span></label>
                                <textarea wire:model="rejectionReason" id="rejectionReason" rows="4" required
                                          class="mt-1 block w-full rounded-md border-gray-600 bg-gray-700 text-white shadow-sm focus:border-red-500 focus:ring-red-500"
                                          placeholder="Provide a clear reason for rejection (minimum 10 characters)..."></textarea>
                                @error('rejectionReason')
                                    <span class="text-red-400 text-xs">{{ $message }}</span>
                                @enderror
                                <p class="mt-1 text-xs text-gray-400">This reason will be sent to the user and saved for your records.</p>
                            </div>
                        </div>

                        <div class="px-6 py-4 bg-gray-700 flex justify-end space-x-3">
                            <button type="button" wire:click="closeRejectModal"
                                    class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-600">
                                Cancel
                            </button>
                            <button type="submit"
                                    class="px-4 py-2 bg-red-600 border border-transparent rounded-md text-sm font-medium text-white hover:bg-red-700">
                                Reject User
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    @endif
</div>
