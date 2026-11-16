/// <reference types="vitest/config" />
import { readFileSync } from 'node:fs'
import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig, type Plugin } from 'vite'

const target = process.env.RA_API_TARGET ?? 'http://localhost:3003'

// `rake reactiveadmin:client:build` sets this: where the Rails host serves the build from. The manifest tells the
// host's shell which hashed files to load, at whatever prefix it serves them from: a host build refers to its own
// files relatively, so one build works under any `ui.asset_prefix` or CDN. Left unset, this is the plain build.
const outDir = process.env.RA_OUT_DIR

// `pnpm build:demo`: the mock-backed build the project site serves under /reactiveadmin/demo/. The plain and host
// builds never set VITE_DEMO.
const demo = process.env.VITE_DEMO === '1'
const demoBase = '/reactiveadmin/demo/'

// GitHub Pages answers a deep link with the site's 404.html, which sends the browser to `?p=<path>`; this puts the
// real path back before the router reads it.
const restoreDeepLink: Plugin = {
  name: 'restore-deep-link',
  transformIndexHtml: () => [
    {
      tag: 'script',
      injectTo: 'head-prepend',
      children: `var p=new URLSearchParams(location.search).get('p');if(p)history.replaceState(null,'','${demoBase.slice(0, -1)}'+p)`,
    },
  ],
}

// The client ships with the gem and shares its version, which tells an error report which build crashed.
const clientVersion = /VERSION = "([^"]+)"/.exec(readFileSync(path.resolve(import.meta.dirname, '../../gem/lib/reactive_admin/version.rb'), 'utf8'))?.[1] ?? 'dev'

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
  base: demo ? demoBase : outDir ? './' : '/',
  define: { __CLIENT_VERSION__: JSON.stringify(clientVersion) },
  // The host build is for production: none of the dev server's static files (mocks, the MSW worker) ship with it.
  publicDir: outDir ? false : 'public',
  plugins: [react(), tailwindcss(), ...(demo ? [restoreDeepLink] : [])],
  resolve: { alias: { '@': path.resolve(import.meta.dirname, 'src') } },
  build: {
    outDir: outDir ?? (demo ? 'dist-demo' : 'dist'),
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
