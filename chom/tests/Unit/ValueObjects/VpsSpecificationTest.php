<?php

declare(strict_types=1);

namespace Tests\Unit\ValueObjects;

use App\ValueObjects\VpsSpecification;
use InvalidArgumentException;
use PHPUnit\Framework\TestCase;

/**
 * VPS Specification Value Object Tests
 *
 * Tests VpsSpecification value object validation and behavior.
 *
 * @package Tests\Unit\ValueObjects
 */
class VpsSpecificationTest extends TestCase
{
    public function test_creates_valid_specification(): void
    {
        $spec = new VpsSpecification(
            cpuCores: 2,
            ramMb: 2048,
            diskGb: 50,
            region: 'us-east-1',
            os: 'ubuntu-22.04'
        );

        $this->assertSame(2, $spec->cpuCores);
        $this->assertSame(2048, $spec->ramMb);
        $this->assertSame(50, $spec->diskGb);
        $this->assertSame('us-east-1', $spec->region);
        $this->assertSame('ubuntu-22.04', $spec->os);
    }

    public function test_validates_cpu_cores_minimum(): void
    {
        $this->expectException(InvalidArgumentException::class);

        new VpsSpecification(
            cpuCores: 0,
            ramMb: 1024,
            diskGb: 25,
            region: 'us-east-1'
        );
    }

    public function test_validates_cpu_cores_maximum(): void
    {
        $this->expectException(InvalidArgumentException::class);

        new VpsSpecification(
            cpuCores: 33,
            ramMb: 1024,
            diskGb: 25,
            region: 'us-east-1'
        );
    }

    public function test_validates_ram_minimum(): void
    {
        $this->expectException(InvalidArgumentException::class);

        new VpsSpecification(
            cpuCores: 1,
            ramMb: 256,
            diskGb: 25,
            region: 'us-east-1'
        );
    }

    public function test_validates_invalid_region(): void
    {
        $this->expectException(InvalidArgumentException::class);

        new VpsSpecification(
            cpuCores: 1,
            ramMb: 1024,
            diskGb: 25,
            region: 'invalid-region'
        );
    }

    public function test_creates_from_array(): void
    {
        $spec = VpsSpecification::fromArray([
            'cpu_cores' => 2,
            'ram_mb' => 4096,
            'disk_gb' => 100,
            'region' => 'us-west-1',
            'os' => 'debian-12',
        ]);

        $this->assertSame(2, $spec->cpuCores);
        $this->assertSame(4096, $spec->ramMb);
        $this->assertSame(100, $spec->diskGb);
    }

    public function test_calculates_monthly_cost(): void
    {
        $spec = VpsSpecification::small();

        $cost = $spec->getMonthlyCost();

        $this->assertGreaterThan(0, $cost);
        $this->assertIsFloat($cost);
    }

    public function test_compares_specifications(): void
    {
        $spec1 = VpsSpecification::small();
        $spec2 = VpsSpecification::small();
        $spec3 = VpsSpecification::medium();

        $this->assertTrue($spec1->equals($spec2));
        $this->assertFalse($spec1->equals($spec3));
    }

    public function test_checks_minimum_requirements(): void
    {
        $minimum = VpsSpecification::small();
        $medium = VpsSpecification::medium();
        $large = VpsSpecification::large();

        $this->assertTrue($minimum->isAtLeast($minimum));
        $this->assertTrue($medium->isAtLeast($minimum));
        $this->assertTrue($large->isAtLeast($minimum));
        $this->assertFalse($minimum->isAtLeast($medium));
    }

    public function test_converts_to_array(): void
    {
        $spec = VpsSpecification::small();
        $array = $spec->toArray();

        $this->assertIsArray($array);
        $this->assertArrayHasKey('cpu_cores', $array);
        $this->assertArrayHasKey('ram_mb', $array);
        $this->assertArrayHasKey('disk_gb', $array);
        $this->assertArrayHasKey('region', $array);
    }

    public function test_immutability_with_modifiers(): void
    {
        $original = VpsSpecification::small();
        $modified = $original->withCpuCores(4);

        $this->assertNotSame($original, $modified);
        $this->assertSame(1, $original->cpuCores);
        $this->assertSame(4, $modified->cpuCores);
    }
}
