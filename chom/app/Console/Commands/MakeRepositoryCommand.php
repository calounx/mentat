<?php

namespace App\Console\Commands;

use Illuminate\Console\GeneratorCommand;
use Illuminate\Support\Str;

class MakeRepositoryCommand extends GeneratorCommand
{
    protected $signature = 'make:repository {name : The name of the repository class}';

    protected $description = 'Create a new repository class with interface';

    protected $type = 'Repository';

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

        // Create the repository interface first
        $this->createInterface();

        // Create the repository implementation
        $result = parent::handle();

        if ($result === self::SUCCESS) {
            $this->components->info("Repository [{$this->argument('name')}] created successfully.");
            $this->newLine();
            $this->components->info('Next steps:');
            $this->line('1. Register in AppServiceProvider:');
            $this->line('   $this->app->bind(\\App\\Contracts\\' . $this->argument('name') . 'Interface::class, \\App\\Repositories\\' . $this->argument('name') . '::class);');
            $this->newLine();
            $this->line('2. Use in your controllers:');
            $this->line('   public function __construct(private ' . $this->argument('name') . 'Interface $repository) {}');
        }

        return $result ?? self::FAILURE;
    }

    /**
     * Create the repository interface.
     */
    protected function createInterface(): void
    {
        $name = $this->argument('name');
        $interfaceName = $name . 'Interface';

        $path = $this->laravel->basePath('app/Contracts/' . $interfaceName . '.php');

        if (!is_dir(dirname($path))) {
            mkdir(dirname($path), 0755, true);
        }

        if (file_exists($path)) {
            $this->components->warn("Interface [$interfaceName] already exists!");
            return;
        }

        $stub = str_replace(
            ['{{ namespace }}', '{{ class }}'],
            ['App\\Contracts', $interfaceName],
            $this->getInterfaceStub()
        );

        file_put_contents($path, $stub);
        $this->components->info("Interface [$interfaceName] created successfully.");
    }

    /**
     * Get the stub file for the generator.
     */
    protected function getStub(): string
    {
        return __DIR__ . '/stubs/repository.stub';
    }

    /**
     * Get the default namespace for the class.
     */
    protected function getDefaultNamespace($rootNamespace): string
    {
        return $rootNamespace . '\Repositories';
    }

    /**
     * Build the class with the given name.
     */
    protected function buildClass($name): string
    {
        $stub = parent::buildClass($name);

        $interfaceName = class_basename($name) . 'Interface';

        $stub = str_replace('{{ interface }}', $interfaceName, $stub);

        return $stub;
    }

    /**
     * Create stub files.
     */
    protected function createStubs(string $stubDir): void
    {
        $repoStub = $stubDir . '/repository.stub';
        if (!file_exists($repoStub)) {
            file_put_contents($repoStub, $this->getRepositoryStub());
        }

        $interfaceStub = $stubDir . '/repository-interface.stub';
        if (!file_exists($interfaceStub)) {
            file_put_contents($interfaceStub, $this->getInterfaceStub());
        }
    }

    /**
     * Get the repository stub content.
     */
    protected function getRepositoryStub(): string
    {
        return <<<'STUB'
<?php

namespace {{ namespace }};

use App\Contracts\{{ interface }};
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\Model;

class {{ class }} implements {{ interface }}
{
    /**
     * Create a new repository instance.
     */
    public function __construct(
        // Inject your model here
        // private ModelName $model
    ) {
        //
    }

    /**
     * Get all records.
     */
    public function all(): Collection
    {
        // return $this->model->all();
        return collect();
    }

    /**
     * Find a record by ID.
     */
    public function find(string $id): ?Model
    {
        // return $this->model->find($id);
        return null;
    }

    /**
     * Create a new record.
     */
    public function create(array $data): Model
    {
        // return $this->model->create($data);
        return new \stdClass();
    }

    /**
     * Update a record.
     */
    public function update(string $id, array $data): bool
    {
        // return $this->model->find($id)?->update($data) ?? false;
        return false;
    }

    /**
     * Delete a record.
     */
    public function delete(string $id): bool
    {
        // return $this->model->find($id)?->delete() ?? false;
        return false;
    }
}

STUB;
    }

    /**
     * Get the interface stub content.
     */
    protected function getInterfaceStub(): string
    {
        return <<<'STUB'
<?php

namespace {{ namespace }};

use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\Model;

interface {{ class }}
{
    /**
     * Get all records.
     */
    public function all(): Collection;

    /**
     * Find a record by ID.
     */
    public function find(string $id): ?Model;

    /**
     * Create a new record.
     */
    public function create(array $data): Model;

    /**
     * Update a record.
     */
    public function update(string $id, array $data): bool;

    /**
     * Delete a record.
     */
    public function delete(string $id): bool;
}

STUB;
    }
}
