<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SystemSetting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class SystemConfigController extends Controller
{
    /**
     * Export SMTP configuration for Alertmanager
     * Used by deployment scripts to configure alerting
     *
     * @return JsonResponse
     */
    public function exportSmtpConfig(): JsonResponse
    {
        try {
            $settings = [
                'mailer' => SystemSetting::get('mail.mailer', 'smtp'),
                'host' => SystemSetting::get('mail.host', '127.0.0.1'),
                'port' => SystemSetting::get('mail.port', 587),
                'username' => SystemSetting::get('mail.username', ''),
                'password' => SystemSetting::get('mail.password', ''),
                'encryption' => SystemSetting::get('mail.encryption', 'tls'),
                'from_address' => SystemSetting::get('mail.from_address', 'noreply@example.com'),
                'from_name' => SystemSetting::get('mail.from_name', 'CHOM'),
            ];

            Log::info('SMTP configuration exported', [
                'host' => $settings['host'],
                'from_address' => $settings['from_address'],
            ]);

            return response()->json([
                'success' => true,
                'data' => $settings,
            ]);
        } catch (\Exception $e) {
            Log::error('Failed to export SMTP configuration', [
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'success' => false,
                'error' => 'Failed to export SMTP configuration',
            ], 500);
        }
    }

    /**
     * Export SMTP configuration in shell format
     * For bash scripts that need environment variables
     *
     * @return \Illuminate\Http\Response
     */
    public function exportSmtpConfigShell()
    {
        try {
            $settings = [
                'MAIL_MAILER' => SystemSetting::get('mail.mailer', 'smtp'),
                'MAIL_HOST' => SystemSetting::get('mail.host', '127.0.0.1'),
                'MAIL_PORT' => SystemSetting::get('mail.port', 587),
                'MAIL_USERNAME' => SystemSetting::get('mail.username', ''),
                'MAIL_PASSWORD' => SystemSetting::get('mail.password', ''),
                'MAIL_ENCRYPTION' => SystemSetting::get('mail.encryption', 'tls'),
                'MAIL_FROM_ADDRESS' => SystemSetting::get('mail.from_address', 'noreply@example.com'),
                'MAIL_FROM_NAME' => SystemSetting::get('mail.from_name', 'CHOM'),
            ];

            $output = "# SMTP Configuration - Generated from database\n";
            $output .= "# Source: system_settings table\n\n";

            foreach ($settings as $key => $value) {
                $output .= "{$key}=\"{$value}\"\n";
            }

            return response($output, 200)
                ->header('Content-Type', 'text/plain');
        } catch (\Exception $e) {
            return response('# Error: ' . $e->getMessage(), 500)
                ->header('Content-Type', 'text/plain');
        }
    }

    /**
     * Export SMTP configuration in YAML format for Alertmanager
     *
     * @return \Illuminate\Http\Response
     */
    public function exportSmtpConfigYaml()
    {
        try {
            $host = SystemSetting::get('mail.host', '127.0.0.1');
            $port = SystemSetting::get('mail.port', 587);
            $username = SystemSetting::get('mail.username', '');
            $password = SystemSetting::get('mail.password', '');
            $encryption = SystemSetting::get('mail.encryption', 'tls');
            $fromAddress = SystemSetting::get('mail.from_address', 'noreply@example.com');

            $requireTls = ($encryption !== 'null' && $encryption !== '');

            $yaml = "# SMTP Configuration for Alertmanager\n";
            $yaml .= "# Generated from system_settings database\n";
            $yaml .= "global:\n";
            $yaml .= "  smtp_smarthost: '{$host}:{$port}'\n";
            $yaml .= "  smtp_from: '{$fromAddress}'\n";
            $yaml .= "  smtp_auth_username: '{$username}'\n";
            $yaml .= "  smtp_auth_password: '{$password}'\n";
            $yaml .= "  smtp_require_tls: " . ($requireTls ? 'true' : 'false') . "\n";

            return response($yaml, 200)
                ->header('Content-Type', 'text/yaml');
        } catch (\Exception $e) {
            return response('# Error: ' . $e->getMessage(), 500)
                ->header('Content-Type', 'text/yaml');
        }
    }
}
