<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SystemSetting extends Model
{
    protected $fillable = [
        'key',
        'value',
        'type',
        'description',
    ];

    /**
     * Get a setting value by key
     */
    public static function get(string $key, mixed $default = null): mixed
    {
        $setting = static::where('key', $key)->first();

        if (!$setting) {
            return $default;
        }

        return static::castValue($setting->value, $setting->type);
    }

    /**
     * Set a setting value by key
     */
    public static function set(string $key, mixed $value, string $type = 'string', ?string $description = null): void
    {
        // Encrypt if type is encrypted
        if ($type === 'encrypted' && $value) {
            $value = encrypt($value);
        }

        static::updateOrCreate(
            ['key' => $key],
            [
                'value' => $value,
                'type' => $type,
                'description' => $description,
            ]
        );
    }

    /**
     * Get all mail settings as array
     */
    public static function getMailSettings(): array
    {
        $settings = static::where('key', 'like', 'mail.%')->get();

        $mailSettings = [];
        foreach ($settings as $setting) {
            $keyParts = explode('.', $setting->key);
            $mailSettings[end($keyParts)] = static::castValue($setting->value, $setting->type);
        }

        return $mailSettings;
    }

    /**
     * Cast value based on type
     */
    protected static function castValue(mixed $value, string $type): mixed
    {
        return match ($type) {
            'integer' => (int) $value,
            'boolean' => filter_var($value, FILTER_VALIDATE_BOOLEAN),
            'encrypted' => $value ? decrypt($value) : '',
            default => $value,
        };
    }

    /**
     * Get value attribute with automatic decryption
     */
    public function getValueAttribute($value): mixed
    {
        return static::castValue($value, $this->type);
    }

    /**
     * Set value attribute with automatic encryption
     */
    public function setValueAttribute($value): void
    {
        if ($this->type === 'encrypted' && $value) {
            $this->attributes['value'] = encrypt($value);
        } else {
            $this->attributes['value'] = $value;
        }
    }
}
