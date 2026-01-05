<div>
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between mb-8">
        <div>
            <h1 class="text-2xl font-bold text-white">Plan Management</h1>
            <p class="mt-1 text-sm text-gray-400">Configure pricing plans and their limits.</p>
        </div>
        <button wire:click="openCreateModal"
                class="mt-4 sm:mt-0 inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
            <svg class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
            Add Plan
        </button>
    </div>

    <!-- Flash Messages -->
    @if($success)
        <div class="mb-4 bg-green-900/50 border-l-4 border-green-500 p-4 rounded">
            <p class="text-sm text-green-200">{{ $success }}</p>
        </div>
    @endif

    @if($error)
        <div class="mb-4 bg-red-900/50 border-l-4 border-red-500 p-4 rounded">
            <p class="text-sm text-red-200">{{ $error }}</p>
        </div>
    @endif

    <!-- Plans Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        @foreach($plans as $plan)
            <div class="bg-gray-800 rounded-lg border {{ $plan->isCurrentlyValid() ? 'border-gray-700' : 'border-yellow-600' }} overflow-hidden">
                <!-- Plan Header -->
                <div class="px-6 py-4 border-b border-gray-700 {{ !$plan->is_active ? 'bg-gray-700/50' : '' }}">
                    <div class="flex items-center justify-between">
                        <div>
                            <h3 class="text-lg font-semibold text-white">{{ $plan->name }}</h3>
                            <p class="text-xs text-gray-400">Tier: {{ $plan->tier }}</p>
                        </div>
                        <div class="text-right">
                            <div class="text-2xl font-bold text-white">{{ $plan->getFormattedMonthlyPrice() }}</div>
                            <div class="text-xs text-gray-400">/month</div>
                        </div>
                    </div>
                    @if($plan->description)
                        <p class="mt-2 text-sm text-gray-400">{{ $plan->description }}</p>
                    @endif
                    <div class="mt-2 flex items-center gap-2">
                        @if($plan->is_active)
                            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-900 text-green-300">
                                Active
                            </span>
                        @else
                            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-600 text-gray-300">
                                Inactive
                            </span>
                        @endif
                        @if(!$plan->isCurrentlyValid() && $plan->is_active)
                            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-900 text-yellow-300">
                                Outside Date Range
                            </span>
                        @endif
                        <span class="text-xs text-gray-500">{{ $plan->tenants_count }} tenant(s)</span>
                    </div>
                </div>

                <!-- Plan Limits -->
                <div class="px-6 py-4 space-y-3">
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Sites</span>
                        <span class="text-white font-medium">{{ $plan->getDisplayValue('max_sites') }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Storage</span>
                        <span class="text-white font-medium">{{ $plan->max_storage_gb === -1 ? 'Unlimited' : $plan->max_storage_gb . ' GB' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Bandwidth</span>
                        <span class="text-white font-medium">{{ $plan->max_bandwidth_gb === -1 ? 'Unlimited' : $plan->max_bandwidth_gb . ' GB' }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Backup Retention</span>
                        <span class="text-white font-medium">{{ $plan->backup_retention_days }} days</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">Support Level</span>
                        <span class="text-white font-medium capitalize">{{ $plan->support_level }}</span>
                    </div>
                    <div class="flex justify-between text-sm">
                        <span class="text-gray-400">API Rate Limit</span>
                        <span class="text-white font-medium">{{ $plan->api_rate_limit_per_hour === -1 ? 'Unlimited' : number_format($plan->api_rate_limit_per_hour) . '/hr' }}</span>
                    </div>

                    <!-- Features -->
                    <div class="pt-3 border-t border-gray-700 space-y-2">
                        <div class="flex items-center text-sm">
                            @if($plan->dedicated_ip)
                                <svg class="h-4 w-4 text-green-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                                </svg>
                            @else
                                <svg class="h-4 w-4 text-gray-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                                </svg>
                            @endif
                            <span class="{{ $plan->dedicated_ip ? 'text-white' : 'text-gray-500' }}">Dedicated IP</span>
                        </div>
                        <div class="flex items-center text-sm">
                            @if($plan->staging_environments)
                                <svg class="h-4 w-4 text-green-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                                </svg>
                            @else
                                <svg class="h-4 w-4 text-gray-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                                </svg>
                            @endif
                            <span class="{{ $plan->staging_environments ? 'text-white' : 'text-gray-500' }}">Staging Environments</span>
                        </div>
                        <div class="flex items-center text-sm">
                            @if($plan->white_label)
                                <svg class="h-4 w-4 text-green-400 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                                </svg>
                            @else
                                <svg class="h-4 w-4 text-gray-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                                </svg>
                            @endif
                            <span class="{{ $plan->white_label ? 'text-white' : 'text-gray-500' }}">White Label</span>
                        </div>
                    </div>

                    <!-- Dates -->
                    @if($plan->start_date || $plan->end_date)
                        <div class="pt-3 border-t border-gray-700">
                            <div class="text-xs text-gray-400 space-y-1">
                                @if($plan->start_date)
                                    <div>Start: {{ $plan->start_date->format('M d, Y') }}</div>
                                @endif
                                @if($plan->end_date)
                                    <div>End: {{ $plan->end_date->format('M d, Y') }}</div>
                                @endif
                            </div>
                        </div>
                    @endif
                </div>

                <!-- Actions -->
                <div class="px-6 py-4 bg-gray-700/30 border-t border-gray-700 flex justify-end space-x-2">
                    <button wire:click="openEditModal('{{ $plan->tier }}')"
                            class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-blue-400 bg-blue-400/10 hover:bg-blue-400/20 rounded-md">
                        <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
                        </svg>
                        Edit
                    </button>
                    @if($plan->tenants_count === 0)
                        <button wire:click="deletePlan('{{ $plan->tier }}')"
                                wire:confirm="Are you sure you want to delete this plan?"
                                class="inline-flex items-center px-3 py-1.5 text-xs font-medium text-red-400 bg-red-400/10 hover:bg-red-400/20 rounded-md">
                            <svg class="h-4 w-4 mr-1" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                            </svg>
                            Delete
                        </button>
                    @endif
                </div>
            </div>
        @endforeach
    </div>

    @if($plans->isEmpty())
        <div class="text-center py-12 bg-gray-800 rounded-lg border border-gray-700">
            <svg class="mx-auto h-12 w-12 text-gray-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z" />
            </svg>
            <h3 class="mt-4 text-lg font-medium text-white">No plans defined</h3>
            <p class="mt-2 text-sm text-gray-400">Get started by creating your first pricing plan.</p>
        </div>
    @endif

    <!-- Edit Modal -->
    @if($showEditModal)
        <div class="fixed inset-0 bg-gray-900/80 flex items-center justify-center z-50 overflow-y-auto py-8">
            <div class="bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 border border-gray-700 max-h-[90vh] overflow-y-auto">
                <h3 class="text-lg font-medium text-white mb-4">Edit Plan: {{ $editingTier }}</h3>

                <form wire:submit="savePlan" class="space-y-6">
                    <!-- Basic Info -->
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                            <label class="block text-sm font-medium text-gray-300 mb-1">Name</label>
                            <input type="text" wire:model="editForm.name"
                                   class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            @error('editForm.name') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-300 mb-1">Price (cents/month)</label>
                            <input type="number" wire:model="editForm.price_monthly_cents"
                                   class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            @error('editForm.price_monthly_cents') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                        </div>
                    </div>

                    <div>
                        <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
                        <textarea wire:model="editForm.description" rows="2"
                                  class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500"></textarea>
                        @error('editForm.description') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                    </div>

                    <!-- Limits -->
                    <div class="border-t border-gray-700 pt-4">
                        <h4 class="text-sm font-medium text-gray-300 mb-3">Limits</h4>
                        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Max Sites</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="editForm.max_sites" {{ $editForm['unlimited_sites'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="editForm.unlimited_sites" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Storage (GB)</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="editForm.max_storage_gb" {{ $editForm['unlimited_storage'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="editForm.unlimited_storage" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Bandwidth (GB)</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="editForm.max_bandwidth_gb" {{ $editForm['unlimited_bandwidth'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="editForm.unlimited_bandwidth" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">API Rate Limit (/hour)</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="editForm.api_rate_limit_per_hour" {{ $editForm['unlimited_api_rate'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="editForm.unlimited_api_rate" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Backup Retention (days)</label>
                                <input type="number" wire:model="editForm.backup_retention_days"
                                       class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Support Level</label>
                                <select wire:model="editForm.support_level"
                                        class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                                    <option value="community">Community</option>
                                    <option value="standard">Standard</option>
                                    <option value="priority">Priority</option>
                                    <option value="dedicated">Dedicated</option>
                                </select>
                            </div>
                        </div>
                    </div>

                    <!-- Features -->
                    <div class="border-t border-gray-700 pt-4">
                        <h4 class="text-sm font-medium text-gray-300 mb-3">Features</h4>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                            <label class="flex items-center text-sm text-gray-300">
                                <input type="checkbox" wire:model="editForm.dedicated_ip" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                Dedicated IP
                            </label>
                            <label class="flex items-center text-sm text-gray-300">
                                <input type="checkbox" wire:model="editForm.staging_environments" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                Staging Environments
                            </label>
                            <label class="flex items-center text-sm text-gray-300">
                                <input type="checkbox" wire:model="editForm.white_label" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                White Label
                            </label>
                        </div>
                    </div>

                    <!-- Validity Period -->
                    <div class="border-t border-gray-700 pt-4">
                        <h4 class="text-sm font-medium text-gray-300 mb-3">Validity Period</h4>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Start Date</label>
                                <input type="date" wire:model="editForm.start_date"
                                       class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                                @error('editForm.start_date') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">End Date</label>
                                <input type="date" wire:model="editForm.end_date"
                                       class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                                @error('editForm.end_date') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                            </div>
                            <div class="flex items-end">
                                <label class="flex items-center text-sm text-gray-300">
                                    <input type="checkbox" wire:model="editForm.is_active" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                    Plan is Active
                                </label>
                            </div>
                        </div>
                        <p class="mt-2 text-xs text-gray-500">Leave dates empty for plans with no time restrictions.</p>
                    </div>

                    <!-- Actions -->
                    <div class="flex justify-end space-x-3 pt-4 border-t border-gray-700">
                        <button type="button" wire:click="closeEditModal"
                                class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-700">
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

    <!-- Create Modal -->
    @if($showCreateModal)
        <div class="fixed inset-0 bg-gray-900/80 flex items-center justify-center z-50 overflow-y-auto py-8">
            <div class="bg-gray-800 rounded-lg p-6 max-w-2xl w-full mx-4 border border-gray-700 max-h-[90vh] overflow-y-auto">
                <h3 class="text-lg font-medium text-white mb-4">Create New Plan</h3>

                <form wire:submit="createPlan" class="space-y-6">
                    <!-- Basic Info -->
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div>
                            <label class="block text-sm font-medium text-gray-300 mb-1">Tier ID</label>
                            <input type="text" wire:model="createForm.tier" placeholder="e.g., business"
                                   class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            <p class="mt-1 text-xs text-gray-500">Lowercase, no spaces (used as identifier)</p>
                            @error('createForm.tier') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-300 mb-1">Name</label>
                            <input type="text" wire:model="createForm.name" placeholder="e.g., Business"
                                   class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            @error('createForm.name') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                        </div>
                    </div>

                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <div class="md:col-span-2">
                            <label class="block text-sm font-medium text-gray-300 mb-1">Description</label>
                            <textarea wire:model="createForm.description" rows="2"
                                      class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500"></textarea>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-300 mb-1">Price (cents/month)</label>
                            <input type="number" wire:model="createForm.price_monthly_cents"
                                   class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            @error('createForm.price_monthly_cents') <span class="text-xs text-red-400">{{ $message }}</span> @enderror
                        </div>
                    </div>

                    <!-- Limits -->
                    <div class="border-t border-gray-700 pt-4">
                        <h4 class="text-sm font-medium text-gray-300 mb-3">Limits</h4>
                        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Max Sites</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="createForm.max_sites" {{ $createForm['unlimited_sites'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="createForm.unlimited_sites" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Storage (GB)</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="createForm.max_storage_gb" {{ $createForm['unlimited_storage'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="createForm.unlimited_storage" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Bandwidth (GB)</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="createForm.max_bandwidth_gb" {{ $createForm['unlimited_bandwidth'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="createForm.unlimited_bandwidth" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">API Rate Limit (/hour)</label>
                                <div class="flex items-center gap-2">
                                    <input type="number" wire:model="createForm.api_rate_limit_per_hour" {{ $createForm['unlimited_api_rate'] ? 'disabled' : '' }}
                                           class="flex-1 bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50">
                                    <label class="flex items-center text-xs text-gray-400">
                                        <input type="checkbox" wire:model.live="createForm.unlimited_api_rate" class="mr-1 rounded bg-gray-700 border-gray-600">
                                        Unlimited
                                    </label>
                                </div>
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Backup Retention (days)</label>
                                <input type="number" wire:model="createForm.backup_retention_days"
                                       class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Support Level</label>
                                <select wire:model="createForm.support_level"
                                        class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                                    <option value="community">Community</option>
                                    <option value="standard">Standard</option>
                                    <option value="priority">Priority</option>
                                    <option value="dedicated">Dedicated</option>
                                </select>
                            </div>
                        </div>
                    </div>

                    <!-- Features -->
                    <div class="border-t border-gray-700 pt-4">
                        <h4 class="text-sm font-medium text-gray-300 mb-3">Features</h4>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                            <label class="flex items-center text-sm text-gray-300">
                                <input type="checkbox" wire:model="createForm.dedicated_ip" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                Dedicated IP
                            </label>
                            <label class="flex items-center text-sm text-gray-300">
                                <input type="checkbox" wire:model="createForm.staging_environments" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                Staging Environments
                            </label>
                            <label class="flex items-center text-sm text-gray-300">
                                <input type="checkbox" wire:model="createForm.white_label" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                White Label
                            </label>
                        </div>
                    </div>

                    <!-- Validity Period -->
                    <div class="border-t border-gray-700 pt-4">
                        <h4 class="text-sm font-medium text-gray-300 mb-3">Validity Period</h4>
                        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">Start Date</label>
                                <input type="date" wire:model="createForm.start_date"
                                       class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            </div>
                            <div>
                                <label class="block text-sm font-medium text-gray-300 mb-1">End Date</label>
                                <input type="date" wire:model="createForm.end_date"
                                       class="w-full bg-gray-700 border border-gray-600 rounded-md py-2 px-3 text-white focus:ring-blue-500 focus:border-blue-500">
                            </div>
                            <div class="flex items-end">
                                <label class="flex items-center text-sm text-gray-300">
                                    <input type="checkbox" wire:model="createForm.is_active" class="mr-2 rounded bg-gray-700 border-gray-600 text-blue-600">
                                    Plan is Active
                                </label>
                            </div>
                        </div>
                        <p class="mt-2 text-xs text-gray-500">Leave dates empty for plans with no time restrictions.</p>
                    </div>

                    <!-- Actions -->
                    <div class="flex justify-end space-x-3 pt-4 border-t border-gray-700">
                        <button type="button" wire:click="closeCreateModal"
                                class="px-4 py-2 border border-gray-600 rounded-md text-sm font-medium text-gray-300 hover:bg-gray-700">
                            Cancel
                        </button>
                        <button type="submit"
                                class="px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700">
                            Create Plan
                        </button>
                    </div>
                </form>
            </div>
        </div>
    @endif
</div>
