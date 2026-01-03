<?php

namespace App\Repositories\Contracts;

use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Pagination\LengthAwarePaginator;

/**
 * Base Repository Interface
 *
 * Defines the contract for all repository implementations in the application.
 * Repositories act as an abstraction layer between the application logic and data access,
 * promoting better testability and maintainability.
 */
interface RepositoryInterface
{
    /**
     * Find a record by its ID
     *
     * @param string $id
     * @return Model|null
     */
    public function findById(string $id): ?Model;

    /**
     * Create a new record
     *
     * @param array $data
     * @return Model
     */
    public function create(array $data): Model;

    /**
     * Update an existing record
     *
     * @param string $id
     * @param array $data
     * @return Model
     */
    public function update(string $id, array $data): Model;

    /**
     * Delete a record
     *
     * @param string $id
     * @return bool
     */
    public function delete(string $id): bool;

    /**
     * Get all records with optional pagination
     *
     * @param int $perPage
     * @return LengthAwarePaginator|Collection
     */
    public function findAll(int $perPage = 15): LengthAwarePaginator|Collection;
}
