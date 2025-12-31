import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.js'],
            refresh: [
                // Livewire components
                'app/Http/Livewire/**',
                'app/Livewire/**',
                // Blade templates
                'resources/views/**',
                // Routes
                'routes/**',
            ],
        }),
        tailwindcss(),
    ],
    server: {
        host: '0.0.0.0',
        port: 5173,
        strictPort: false,
        hmr: {
            host: 'localhost',
            protocol: 'ws',
        },
        watch: {
            usePolling: false,
            interval: 100,
            ignored: [
                '**/storage/framework/views/**',
                '**/storage/logs/**',
                '**/vendor/**',
                '**/node_modules/**',
            ],
        },
    },
    build: {
        manifest: true,
        outDir: 'public/build',
        rollupOptions: {
            output: {
                manualChunks: {
                    // Split vendor chunks for better caching
                    'vendor': [
                        'alpinejs',
                    ],
                },
            },
        },
        chunkSizeWarningLimit: 1000,
    },
    optimizeDeps: {
        include: [
            'alpinejs',
        ],
    },
});
