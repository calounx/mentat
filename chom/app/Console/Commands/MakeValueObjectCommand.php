<?php

namespace App\Console\Commands;

use Illuminate\Console\GeneratorCommand;

class MakeValueObjectCommand extends GeneratorCommand
{
    protected $signature = 'make:value-object {name : The name of the value object class}';

    protected $description = 'Create a new value object class';

    protected $type = 'ValueObject';

    /**
     * Get the stub file for the generator.
     */
    protected function getStub(): string
    {
        return __DIR__ . '/stubs/value-object.stub';
    }

    /**
     * Get the default namespace for the class.
     */
    protected function getDefaultNamespace($rootNamespace): string
    {
        return $rootNamespace . '\ValueObjects';
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

        // Create the stub file if it doesn't exist
        $stubFile = $stubDir . '/value-object.stub';
        if (!file_exists($stubFile)) {
            file_put_contents($stubFile, $this->getValueObjectStub());
        }

        $result = parent::handle();

        if ($result === self::SUCCESS) {
            $this->components->info("Value Object [{$this->argument('name')}] created successfully.");
            $this->newLine();
            $this->components->info('Example usage:');
            $this->line('  $valueObject = new ' . class_basename($this->argument('name')) . '(\'value\');');
            $this->line('  $stringValue = $valueObject->toString();');
        }

        return $result ?? self::FAILURE;
    }

    /**
     * Get the value object stub content.
     */
    protected function getValueObjectStub(): string
    {
        return <<<'STUB'
<?php

namespace {{ namespace }};

use InvalidArgumentException;
use Stringable;

class {{ class }} implements Stringable
{
    /**
     * Create a new value object instance.
     */
    public function __construct(
        private readonly string $value
    ) {
        $this->validate($value);
    }

    /**
     * Validate the value.
     *
     * @throws InvalidArgumentException
     */
    protected function validate(string $value): void
    {
        if (empty($value)) {
            throw new InvalidArgumentException('Value cannot be empty');
        }

        // Add your validation logic here
    }

    /**
     * Get the string value.
     */
    public function toString(): string
    {
        return $this->value;
    }

    /**
     * Get the string representation.
     */
    public function __toString(): string
    {
        return $this->toString();
    }

    /**
     * Check equality with another value object.
     */
    public function equals(self $other): bool
    {
        return $this->value === $other->value;
    }

    /**
     * Create a new instance from a string.
     */
    public static function fromString(string $value): self
    {
        return new self($value);
    }
}

STUB;
    }
}
