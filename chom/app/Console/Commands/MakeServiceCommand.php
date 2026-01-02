<?php

namespace App\Console\Commands;

use Illuminate\Console\GeneratorCommand;
use Illuminate\Support\Str;

class MakeServiceCommand extends GeneratorCommand
{
    protected $signature = 'make:service {name : The name of the service class}';

    protected $description = 'Create a new service class';

    protected $type = 'Service';

    /**
     * Get the stub file for the generator.
     */
    protected function getStub(): string
    {
        return __DIR__.'/stubs/service.stub';
    }

    /**
     * Get the default namespace for the class.
     */
    protected function getDefaultNamespace($rootNamespace): string
    {
        return $rootNamespace.'\Services';
    }

    /**
     * Build the class with the given name.
     */
    protected function buildClass($name): string
    {
        $stub = parent::buildClass($name);

        $stub = str_replace(
            '{{ serviceName }}',
            Str::studly(class_basename($name)),
            $stub
        );

        return $stub;
    }

    /**
     * Execute the console command.
     */
    public function handle(): int
    {
        // Create stub directory if it doesn't exist
        $stubDir = __DIR__.'/stubs';
        if (! is_dir($stubDir)) {
            mkdir($stubDir, 0755, true);
        }

        // Create the stub file if it doesn't exist
        $stubFile = $stubDir.'/service.stub';
        if (! file_exists($stubFile)) {
            file_put_contents($stubFile, $this->getServiceStub());
        }

        $result = parent::handle();

        if ($result === self::SUCCESS) {
            $this->components->info("Service [{$this->argument('name')}] created successfully.");
            $this->newLine();
            $this->components->info('Example usage:');
            $this->line('  use App\\Services\\'.$this->argument('name').';');
            $this->newLine();
            $this->line('  public function __construct(');
            $this->line('      private '.class_basename($this->argument('name')).' $service');
            $this->line('  ) {}');
        }

        return $result ?? self::FAILURE;
    }

    /**
     * Get the service stub content.
     */
    protected function getServiceStub(): string
    {
        return <<<'STUB'
<?php

namespace {{ namespace }};

use Illuminate\Support\Facades\Log;

class {{ class }}
{
    /**
     * Create a new service instance.
     */
    public function __construct()
    {
        //
    }

    /**
     * Execute the service logic.
     *
     * @return mixed
     */
    public function execute(): mixed
    {
        // Service implementation here

        return null;
    }
}

STUB;
    }
}
