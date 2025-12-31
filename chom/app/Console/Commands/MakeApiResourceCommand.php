<?php

namespace App\Console\Commands;

use Illuminate\Console\GeneratorCommand;
use Illuminate\Support\Str;

class MakeApiResourceCommand extends GeneratorCommand
{
    protected $signature = 'make:api-resource {name : The name of the API resource class}
                            {--collection : Create a collection resource}';

    protected $description = 'Create a new API resource class';

    protected $type = 'ApiResource';

    /**
     * Get the stub file for the generator.
     */
    protected function getStub(): string
    {
        if ($this->option('collection')) {
            return __DIR__ . '/stubs/api-resource-collection.stub';
        }

        return __DIR__ . '/stubs/api-resource.stub';
    }

    /**
     * Get the default namespace for the class.
     */
    protected function getDefaultNamespace($rootNamespace): string
    {
        return $rootNamespace . '\Http\Resources';
    }

    /**
     * Execute the console command.
     */
    public function handle(): int
    {
        // Create stub directory if it doesn't exist
        $stubDir = __DIR__ . '/stubs';
        if (!is_dir($stubDir)) {
            mkdir($stubDir, 0755, true);
        }

        // Create stubs if they don't exist
        $this->createStubs($stubDir);

        $result = parent::handle();

        if ($result === self::SUCCESS) {
            $this->components->info("API Resource [{$this->argument('name')}] created successfully.");
            $this->newLine();
            $this->components->info('Example usage:');

            if ($this->option('collection')) {
                $this->line('  return ' . class_basename($this->argument('name')) . '::make($items);');
            } else {
                $this->line('  return ' . class_basename($this->argument('name')) . '::make($model);');
                $this->line('  return ' . class_basename($this->argument('name')) . '::collection($models);');
            }
        }

        return $result ?? self::FAILURE;
    }

    /**
     * Create stub files.
     */
    protected function createStubs(string $stubDir): void
    {
        $resourceStub = $stubDir . '/api-resource.stub';
        if (!file_exists($resourceStub)) {
            file_put_contents($resourceStub, $this->getResourceStub());
        }

        $collectionStub = $stubDir . '/api-resource-collection.stub';
        if (!file_exists($collectionStub)) {
            file_put_contents($collectionStub, $this->getCollectionStub());
        }
    }

    /**
     * Get the resource stub content.
     */
    protected function getResourceStub(): string
    {
        return <<<'STUB'
<?php

namespace {{ namespace }};

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class {{ class }} extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),

            // Add your resource fields here
        ];
    }
}

STUB;
    }

    /**
     * Get the collection stub content.
     */
    protected function getCollectionStub(): string
    {
        return <<<'STUB'
<?php

namespace {{ namespace }};

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

class {{ class }} extends ResourceCollection
{
    /**
     * Transform the resource collection into an array.
     *
     * @return array<int|string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'data' => $this->collection,
            'meta' => [
                'total' => $this->collection->count(),
            ],
        ];
    }
}

STUB;
    }
}
