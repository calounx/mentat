<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-gray-900">Team Management</h1>
            <p class="mt-1 text-sm text-gray-600">Manage members of {{ $organization->name }}.</p>
        </div>
        @if(auth()->user()->isAdmin())
            <button wire:click="openInviteModal"
                    class="mt-4 sm:mt-0 inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                <svg class="h-5 w-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"/>
                </svg>
                Invite Member
            </button>
        @endif
    </div>

    <!-- Flash Messages -->
    @if(session('success'))
        <div class="mb-4 bg-green-50 border-l-4 border-green-400 p-4">
            <p class="text-sm text-green-700">{{ session('success') }}</p>
        </div>
    @endif

    @if(session('error'))
        <div class="mb-4 bg-red-50 border-l-4 border-red-400 p-4">
            <p class="text-sm text-red-700">{{ session('error') }}</p>
        </div>
    @endif

    <!-- Stats -->
    <div class="grid grid-cols-2 gap-5 sm:grid-cols-4 mb-6">
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Total Members</dt>
                <dd class="mt-1 text-3xl font-semibold text-gray-900">{{ array_sum($roleStats) }}</dd>
            </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Owners</dt>
                <dd class="mt-1 text-3xl font-semibold text-purple-600">{{ $roleStats['owner'] ?? 0 }}</dd>
            </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Admins</dt>
                <dd class="mt-1 text-3xl font-semibold text-blue-600">{{ $roleStats['admin'] ?? 0 }}</dd>
            </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
            <div class="px-4 py-5 sm:p-6">
                <dt class="text-sm font-medium text-gray-500 truncate">Members</dt>
                <dd class="mt-1 text-3xl font-semibold text-green-600">{{ ($roleStats['member'] ?? 0) + ($roleStats['viewer'] ?? 0) }}</dd>
            </div>
        </div>
    </div>

    <!-- Search -->
    <div class="bg-white shadow rounded-lg mb-6">
        <div class="px-4 py-4 sm:px-6">
            <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <svg class="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
                    </svg>
                </div>
                <input type="text"
                       wire:model.live.debounce.300ms="search"
                       placeholder="Search members by name or email..."
                       class="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm">
            </div>
        </div>
    </div>

    <!-- Members Table -->
    <div class="bg-white shadow rounded-lg overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
                <tr>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Member
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Role
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Status
                    </th>
                    <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Joined
                    </th>
                    <th scope="col" class="relative px-6 py-3">
                        <span class="sr-only">Actions</span>
                    </th>
                </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
                @forelse($members as $member)
                    <tr class="{{ $member->id === auth()->id() ? 'bg-blue-50' : '' }}">
                        <td class="px-6 py-4 whitespace-nowrap">
                            <div class="flex items-center">
                                <div class="flex-shrink-0 h-10 w-10">
                                    <div class="h-10 w-10 rounded-full bg-gray-200 flex items-center justify-center">
                                        <span class="text-lg font-medium text-gray-600">
                                            {{ strtoupper(substr($member->name, 0, 1)) }}
                                        </span>
                                    </div>
                                </div>
                                <div class="ml-4">
                                    <div class="text-sm font-medium text-gray-900">
                                        {{ $member->name }}
                                        @if($member->id === auth()->id())
                                            <span class="text-xs text-gray-500">(you)</span>
                                        @endif
                                    </div>
                                    <div class="text-sm text-gray-500">{{ $member->email }}</div>
                                </div>
                            </div>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @php
                                $roleColors = [
                                    'owner' => 'bg-purple-100 text-purple-800',
                                    'admin' => 'bg-blue-100 text-blue-800',
                                    'member' => 'bg-green-100 text-green-800',
                                    'viewer' => 'bg-gray-100 text-gray-800',
                                ];
                            @endphp
                            <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium {{ $roleColors[$member->role] ?? 'bg-gray-100 text-gray-800' }}">
                                {{ ucfirst($member->role) }}
                            </span>
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap">
                            @if($member->email_verified_at)
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                    Active
                                </span>
                            @else
                                <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
                                    Pending
                                </span>
                            @endif
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                            {{ $member->created_at->format('M d, Y') }}
                        </td>
                        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                            @if(auth()->user()->isAdmin() && $member->id !== auth()->id())
                                <div class="flex items-center justify-end space-x-2">
                                    <button wire:click="editMember('{{ $member->id }}')"
                                            class="text-blue-600 hover:text-blue-900"
                                            title="Edit">
                                        <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"/>
                                        </svg>
                                    </button>
                                    @if(!$member->isOwner() || $roleStats['owner'] > 1)
                                        <button wire:click="confirmDelete('{{ $member->id }}')"
                                                class="text-red-600 hover:text-red-900"
                                                title="Remove">
                                            <svg class="h-5 w-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
                                            </svg>
                                        </button>
                                    @endif
                                </div>
                            @endif
                        </td>
                    </tr>
                @empty
                    <tr>
                        <td colspan="5" class="px-6 py-12 text-center">
                            <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"/>
                            </svg>
                            <h3 class="mt-2 text-sm font-medium text-gray-900">No members found</h3>
                            <p class="mt-1 text-sm text-gray-500">
                                @if($search)
                                    Try adjusting your search criteria.
                                @else
                                    Get started by inviting your first team member.
                                @endif
                            </p>
                        </td>
                    </tr>
                @endforelse
            </tbody>
        </table>

        @if($members->hasPages())
            <div class="px-6 py-4 border-t border-gray-200">
                {{ $members->links() }}
            </div>
        @endif
    </div>

    <!-- Role Permissions Info -->
    <div class="mt-6 bg-white shadow rounded-lg">
        <div class="px-4 py-5 sm:px-6 border-b border-gray-200">
            <h3 class="text-lg leading-6 font-medium text-gray-900">Role Permissions</h3>
        </div>
        <div class="px-4 py-5 sm:p-6">
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div class="border rounded-lg p-4">
                    <div class="flex items-center mb-2">
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
                            Owner
                        </span>
                    </div>
                    <ul class="text-sm text-gray-600 space-y-1">
                        <li>Full organization access</li>
                        <li>Billing & subscription management</li>
                        <li>Team management</li>
                        <li>All site operations</li>
                    </ul>
                </div>
                <div class="border rounded-lg p-4">
                    <div class="flex items-center mb-2">
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                            Admin
                        </span>
                    </div>
                    <ul class="text-sm text-gray-600 space-y-1">
                        <li>Team management</li>
                        <li>All site operations</li>
                        <li>View metrics & logs</li>
                        <li>Backup management</li>
                    </ul>
                </div>
                <div class="border rounded-lg p-4">
                    <div class="flex items-center mb-2">
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                            Member
                        </span>
                    </div>
                    <ul class="text-sm text-gray-600 space-y-1">
                        <li>Site management</li>
                        <li>View metrics & logs</li>
                        <li>Create backups</li>
                        <li>Limited settings access</li>
                    </ul>
                </div>
                <div class="border rounded-lg p-4">
                    <div class="flex items-center mb-2">
                        <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                            Viewer
                        </span>
                    </div>
                    <ul class="text-sm text-gray-600 space-y-1">
                        <li>View sites</li>
                        <li>View metrics & logs</li>
                        <li>Read-only access</li>
                        <li>No modifications</li>
                    </ul>
                </div>
            </div>
        </div>
    </div>

    <!-- Invite Modal -->
    @if($showInviteModal)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Invite Team Member</h3>

                <form wire:submit="inviteMember">
                    <div class="mb-4">
                        <label for="inviteName" class="block text-sm font-medium text-gray-700 mb-1">Name</label>
                        <input type="text"
                               id="inviteName"
                               wire:model="inviteName"
                               class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500"
                               placeholder="John Doe">
                        @error('inviteName') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="mb-4">
                        <label for="inviteEmail" class="block text-sm font-medium text-gray-700 mb-1">Email</label>
                        <input type="email"
                               id="inviteEmail"
                               wire:model="inviteEmail"
                               class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500"
                               placeholder="john@example.com">
                        @error('inviteEmail') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="mb-6">
                        <label for="inviteRole" class="block text-sm font-medium text-gray-700 mb-1">Role</label>
                        <select id="inviteRole"
                                wire:model="inviteRole"
                                class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                            <option value="admin">Admin</option>
                            <option value="member">Member</option>
                            <option value="viewer">Viewer</option>
                        </select>
                        @error('inviteRole') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="flex justify-end space-x-3">
                        <button type="button"
                                wire:click="closeInviteModal"
                                class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                            Cancel
                        </button>
                        <button type="submit"
                                class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                            Send Invitation
                        </button>
                    </div>
                </form>
            </div>
        </div>
    @endif

    <!-- Edit Modal -->
    @if($showEditModal)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Edit Team Member</h3>

                <form wire:submit="updateMember">
                    <div class="mb-4">
                        <label for="editName" class="block text-sm font-medium text-gray-700 mb-1">Name</label>
                        <input type="text"
                               id="editName"
                               wire:model="editName"
                               class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                        @error('editName') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="mb-4">
                        <label for="editEmail" class="block text-sm font-medium text-gray-700 mb-1">Email</label>
                        <input type="email"
                               id="editEmail"
                               wire:model="editEmail"
                               class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                        @error('editEmail') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="mb-6">
                        <label for="editRole" class="block text-sm font-medium text-gray-700 mb-1">Role</label>
                        <select id="editRole"
                                wire:model="editRole"
                                class="w-full border border-gray-300 rounded-md py-2 px-3 focus:ring-blue-500 focus:border-blue-500">
                            @if(auth()->user()->isOwner())
                                <option value="owner">Owner</option>
                            @endif
                            <option value="admin">Admin</option>
                            <option value="member">Member</option>
                            <option value="viewer">Viewer</option>
                        </select>
                        @error('editRole') <span class="text-sm text-red-600">{{ $message }}</span> @enderror
                    </div>

                    <div class="flex justify-end space-x-3">
                        <button type="button"
                                wire:click="closeEditModal"
                                class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                            Cancel
                        </button>
                        <button type="submit"
                                class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                            Save Changes
                        </button>
                    </div>
                </form>
            </div>
        </div>
    @endif

    <!-- Delete Confirmation Modal -->
    @if($deletingUserId)
        <div class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
            <div class="bg-white rounded-lg p-6 max-w-md w-full mx-4">
                <h3 class="text-lg font-medium text-gray-900 mb-4">Remove Team Member</h3>
                <p class="text-sm text-gray-500 mb-6">
                    Are you sure you want to remove this member from the team? They will lose access to all organization resources.
                </p>
                <div class="flex justify-end space-x-3">
                    <button wire:click="cancelDelete"
                            class="px-4 py-2 border border-gray-300 rounded-md text-sm font-medium text-gray-700 hover:bg-gray-50">
                        Cancel
                    </button>
                    <button wire:click="deleteMember"
                            class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-red-600 hover:bg-red-700">
                        Remove Member
                    </button>
                </div>
            </div>
        </div>
    @endif
</div>
