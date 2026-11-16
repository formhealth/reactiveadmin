#!/usr/bin/env node
// Node refuses to strip types from files under node_modules, so the crawl runs from a checkout of this repository.
if (Number(process.versions.node.split('.')[0]) < 24) {
  console.error('reactiveadmin-crawl needs Node.js 24 or newer (it runs TypeScript directly).')
  process.exit(2)
}
await import(new URL('../crawl/cli.ts', import.meta.url).href)
