import { createRequire } from "node:module";
import { dirname } from "node:path";
import { defineConfig } from "vitepress";

// Pages sit outside this package, so Vite can't find vue from them.
const vueDir = dirname(createRequire(import.meta.url).resolve("vue/package.json"));

const repo = "https://github.com/formhealth/reactiveadmin";

export default defineConfig({
  title: "ReactiveAdmin",
  description:
    "Front your ActiveAdmin resources and pages with a JSON API, an OpenAPI document, an MCP server, and a modern React admin.",
  base: "/reactiveadmin/",
  cleanUrls: true,
  lastUpdated: false,
  // The demo is built separately and copied in after this build.
  ignoreDeadLinks: [/^\/demo\//],
  // The repo root is the source so the guides render in place; only the pages below are published.
  srcDir: "../..",
  srcExclude: [
    "**/node_modules/**",
    "gem/**",
    "openapi/**",
    "apps/standalone/**",
    "apps/site/README.md",
    "README.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
  ],
  rewrites: {
    "apps/site/index.md": "index.md",
    "docs/guide/:page.md": "guide/:page.md",
    "CHANGELOG.md": "changelog.md",
    "ROADMAP.md": "roadmap.md",
  },
  vite: {
    resolve: { alias: [{ find: /^vue(\/|$)/, replacement: `${vueDir}$1` }] },
  },
  // Pages serves only the root 404.html, so a deep link into the demo lands here; send it to the demo, which restores the path.
  head: [
    [
      "script",
      {},
      `var b='/reactiveadmin/demo/',l=location;if(l.pathname.indexOf(b)===0)l.replace(b+'?p='+encodeURIComponent(l.pathname.slice(b.length-1)+l.search+l.hash))`,
    ],
  ],
  themeConfig: {
    nav: [
      { text: "Guides", link: "/guide/getting-started" },
      { text: "Changelog", link: "/changelog" },
      { text: "Demo", link: "/demo/", target: "_self" },
      { text: "Storybook", link: "/storybook/", target: "_self" },
    ],
    socialLinks: [{ icon: "github", link: repo }],
    editLink: {
      pattern: `${repo}/edit/main/:path`,
      text: "Edit this page on GitHub",
    },
    search: { provider: "local" },
    sidebar: [
      {
        text: "Start here",
        items: [
          { text: "Getting started", link: "/guide/getting-started" },
          { text: "Overview", link: "/guide/overview" },
        ],
      },
      {
        text: "Configure",
        items: [
          { text: "Configuration", link: "/guide/configuration" },
          { text: "DSL reference", link: "/guide/dsl" },
          { text: "Security", link: "/guide/security" },
        ],
      },
      {
        text: "Adopt",
        items: [
          { text: "Rolling out", link: "/guide/rollout" },
          { text: "Doctor", link: "/guide/doctor" },
        ],
      },
      {
        text: "Integrate",
        items: [
          { text: "OpenAPI", link: "/guide/openapi" },
          { text: "MCP server", link: "/guide/mcp" },
          { text: "Custom views", link: "/guide/custom-views" },
        ],
      },
      {
        text: "Reference",
        items: [
          { text: "Testing", link: "/guide/testing" },
          { text: "ActiveAdmin support", link: "/guide/activeadmin-support" },
          { text: "Changelog", link: "/changelog" },
          { text: "Roadmap", link: "/roadmap" },
        ],
      },
    ],
    footer: {
      message: 'Released under the <a href="https://github.com/formhealth/reactiveadmin/blob/main/LICENSE">MIT License</a>.',
      copyright: 'Copyright © 2026 <a href="https://www.formhealth.co">Form Health, Inc.</a>',
    },
  },
});
