import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const rootDir = dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        main: resolve(rootDir, 'index.html'),
        pricing: resolve(rootDir, 'pricing.html'),
        checkout: resolve(rootDir, 'checkout.html'),
        checkoutSuccess: resolve(rootDir, 'checkout-success.html'),
        downloads: resolve(rootDir, 'downloads.html'),
        privacy: resolve(rootDir, 'privacy.html'),
        terms: resolve(rootDir, 'terms.html'),
        cookies: resolve(rootDir, 'cookies.html'),
        accessibility: resolve(rootDir, 'accessibility.html'),
        security: resolve(rootDir, 'security.html'),
        useCases: resolve(rootDir, 'use-cases.html'),
        help: resolve(rootDir, 'help.html'),
        notFound: resolve(rootDir, '404.html'),
      },
    },
  },
})
