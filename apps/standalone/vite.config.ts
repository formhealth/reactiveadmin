/// <reference types="vitest/config" />
import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

const target = process.env.RA_API_TARGET ?? 'http://localhost:3003'

// `rake reactiveadmin:client:build` sets these: where the Rails host serves the build from, and the URL prefix of
// its files. The manifest tells the host's shell which hashed files to load. Left unset, this is the plain build.
const outDir = process.env.RA_OUT_DIR
const assetPrefix = process.env.RA_ASSET_PREFIX ?? '/'

// Vendor groups keep the entry small and cacheable; heavy ones (forms, dates, table, purify) are only
// imported by lazy page/dialog chunks, so they never load with the shell.
const vendorGroups = Object.entries({
  react: /node_modules\/(react|react-dom|scheduler)\//,
  router: /node_modules\/(react-router|cookie|set-cookie-parser)\//,
  query: /node_modules\/@tanstack\/(query-core|react-query)\//,
  table: /node_modules\/@tanstack\/(table-core|react-table)\//,
  forms: /node_modules\/(react-hook-form|zod)\//,
  datefns: /node_modules\/(date-fns|@date-fns)\//,
  calendar: /node_modules\/react-day-picker\//,
  purify: /node_modules\/dompurify\//,
}).map(([name, test], i, all) => ({ name: `vendor-${name}`, test, priority: all.length - i }))

export default defineConfig({
  base: assetPrefix,
  // The host build is for production: none of the dev server's static files (mocks, the MSW worker) ship with it.
  publicDir: outDir ? false : 'public',
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@': path.resolve(import.meta.dirname, 'src') } },
  build: {
    outDir: outDir ?? 'dist',
    emptyOutDir: true,
    manifest: 'manifest.json',
    // The second entry is the script the classic dashboard loads for its switch; the manifest names its hashed file.
    rolldownOptions: { input: { index: 'index.html', uiToggle: 'src/classic/uiToggle.ts' }, output: { codeSplitting: { groups: vendorGroups } } },
  },
  // With a DOM package installed, vitest's node loader hook fails on every file (Node 24.12).
  test: { include: ['src/**/*.test.ts', 'crawl/**/*.test.ts'], experimental: { nodeLoader: false } },
  server: {
    port: 5174,
    // Whole path segments only: a plain '/admin' prefix would also capture the SPA routes /admin_users and /admin_comments.
    proxy: { '^/(api|admin|assets|packs)(/|$)': { target, changeOrigin: false } },
  },
})
