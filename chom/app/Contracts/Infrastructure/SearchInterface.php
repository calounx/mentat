<?php

declare(strict_types=1);

namespace App\Contracts\Infrastructure;

/**
 * Search Interface
 *
 * Defines the contract for search operations.
 * Provides abstraction over search engines (Elasticsearch, Algolia, Meilisearch, etc.)
 *
 * Design Pattern: Adapter Pattern - adapts different search engines
 * SOLID Principle: Dependency Inversion - depend on abstraction
 *
 * @package App\Contracts\Infrastructure
 */
interface SearchInterface
{
    /**
     * Index a document
     *
     * @param string $index Index name
     * @param string|int $id Document ID
     * @param array<string, mixed> $data Document data
     * @return bool True if indexing was successful
     * @throws \RuntimeException If indexing fails
     */
    public function index(string $index, string|int $id, array $data): bool;

    /**
     * Index multiple documents
     *
     * @param string $index Index name
     * @param array<array<string, mixed>> $documents Documents to index
     * @return bool True if bulk indexing was successful
     * @throws \RuntimeException If indexing fails
     */
    public function bulkIndex(string $index, array $documents): bool;

    /**
     * Search for documents
     *
     * @param string $index Index name
     * @param string $query Search query
     * @param array<string, mixed> $filters Search filters
     * @param int $limit Maximum results
     * @param int $offset Result offset
     * @return array<string, mixed> Search results
     * @throws \RuntimeException If search fails
     */
    public function search(string $index, string $query, array $filters = [], int $limit = 10, int $offset = 0): array;

    /**
     * Delete a document
     *
     * @param string $index Index name
     * @param string|int $id Document ID
     * @return bool True if deletion was successful
     * @throws \RuntimeException If deletion fails
     */
    public function delete(string $index, string|int $id): bool;

    /**
     * Update a document
     *
     * @param string $index Index name
     * @param string|int $id Document ID
     * @param array<string, mixed> $data Document data to update
     * @return bool True if update was successful
     * @throws \RuntimeException If update fails
     */
    public function update(string $index, string|int $id, array $data): bool;

    /**
     * Create or update an index
     *
     * @param string $index Index name
     * @param array<string, mixed> $settings Index settings
     * @return bool True if creation was successful
     * @throws \RuntimeException If index creation fails
     */
    public function createIndex(string $index, array $settings = []): bool;

    /**
     * Delete an index
     *
     * @param string $index Index name
     * @return bool True if deletion was successful
     * @throws \RuntimeException If deletion fails
     */
    public function deleteIndex(string $index): bool;

    /**
     * Check if an index exists
     *
     * @param string $index Index name
     * @return bool True if index exists
     */
    public function indexExists(string $index): bool;

    /**
     * Get search engine name
     *
     * @return string Engine name (e.g., 'elasticsearch', 'algolia')
     */
    public function getEngineName(): string;
}
