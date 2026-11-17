<script setup lang="ts">
import { ref } from "vue";
import { withBase } from "vitepress";

type Part = "scopes" | "filters" | "actions" | "columns";

// Where each part of the registration shows up in the desktop screenshot, as percentages of it.
const regions: Record<Part, { left: number; top: number; width: number; height: number; label: string }> = {
  actions: { left: 52.6, top: 2.2, width: 46, height: 3.8, label: "action items" },
  scopes: { left: 21.4, top: 7.6, width: 38, height: 3.9, label: "scopes" },
  filters: { left: 21.4, top: 12.9, width: 66.8, height: 8.6, label: "filters" },
  columns: { left: 21.5, top: 23, width: 77, height: 4.8, label: "columns" },
};

const groups: { part?: Part; lines: string[] }[] = [
  { lines: ["ActiveAdmin.register Post do"] },
  { part: "scopes", lines: ["  scope :all, default: true", "  scope :embargoed", "  scope :not_embargoed", "  scope :review_failed"] },
  { lines: [""] },
  {
    part: "filters",
    lines: ["  filter :author_id", "  filter :editor", "  filter :published_on", "  filter :embargo_until", "  filter :publication_status", "  filter :created_at"],
  },
  { lines: [""] },
  {
    part: "actions",
    lines: ["  action_item :publish_pending, only: :index do", '    link_to "Publish pending",', "      publish_pending_admin_posts_path,", "      method: :post", "  end"],
  },
  { lines: [""] },
  {
    part: "columns",
    lines: [
      "  index do",
      "    selectable_column",
      "    id_column",
      "    column :author",
      "    column :editor",
      "    column :published_on",
      "    column :embargo_until",
      "    column :publication_status",
      "    column :created_at",
      "    actions",
      "  end",
    ],
  },
  { lines: ["end"] },
];

const active = ref<Part>("scopes");

const escape = (text: string) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
const paint = (line: string) =>
  escape(line)
    .replace(/("[^"]*")/g, '<span class="str">$1</span>')
    .replace(/(:\w+|\w+:(?= ))/g, '<span class="sym">$1</span>')
    .replace(/\b(do|end|true)\b/g, '<span class="kw">$1</span>');

const shot = (name: string, scheme: string) => withBase(`/screenshots/${name}-${scheme}.png`);

const request = `GET /api/admin/posts?scope=embargoed

{
  "resource": "posts",
  "rows": [
    { "id": "5005",
      "cells": {
        "publication_status":
          { "type": "status", "label": "Pending",
            "variant": "neutral" },
        …
      },
      …
    }
  ],
  "meta": { "current_scope": "embargoed",
            "total_count": 18 }
}`;

const tool = `tools/call

{
  "name": "list_records",
  "arguments": {
    "resource": "posts",
    "scope": "embargoed",
    "order": "created_at_desc"
  }
}`;

const kept = [
  "Your app/admin registrations and the DSL",
  "Controllers and their overrides",
  "Filtering, scopes, sorting, and pagination",
  "Authentication and your authorization adapter",
  "Formtastic forms and Arbre show pages",
  "The classic admin, at the same URLs, as the fallback",
];

const added = [
  { text: "A React admin that works on a phone", link: "/demo/", external: true },
  { text: "A JSON API with an OpenAPI 3.1 document", link: "/guide/openapi" },
  { text: "An MCP server for agents: off until you turn it on, read-only until a resource opts in", link: "/guide/mcp" },
  { text: "Masking, rate limits, and audit events", link: "/guide/security" },
  { text: "A per-person switch between classic and new", link: "/guide/rollout" },
  { text: "A doctor task that reports what renders natively", link: "/guide/doctor" },
];
</script>

<template>
  <div class="home">
    <header class="intro">
      <h1>Add an API, MCP, and responsive React frontend to <em>your</em> ActiveAdmin.</h1>
      <p class="lede">
        Keep your app/admin files as they are. ReactiveAdmin reuses their controllers, filters, scopes, forms, and authorization, so you don't write
        serializers, API controllers, or pages per resource.
      </p>
      <p class="actions">
        <a class="primary" :href="withBase('/guide/getting-started')">Get started</a>
        <a class="secondary" :href="withBase('/demo/')" target="_self">Try the demo</a>
        <a class="plain" :href="withBase('/storybook/')" target="_self">Storybook</a>
        <a class="plain" :href="withBase('/guide/overview')">Why ReactiveAdmin</a>
        <a class="plain" href="https://github.com/formhealth/reactiveadmin">GitHub</a>
      </p>
    </header>

    <section class="proof" aria-labelledby="proof-title">
      <h2 id="proof-title" class="visually-hidden">A registration and the screen it renders</h2>
      <div class="source">
        <p class="file">app/admin/posts.rb</p>
        <div class="code" role="group" aria-label="Parts of the registration. Choose one to see where it appears in the screenshot.">
          <template v-for="(group, index) in groups" :key="index">
            <button
              v-if="group.part"
              type="button"
              class="part"
              :class="{ on: active === group.part }"
              :aria-pressed="active === group.part"
              :aria-label="`Show the ${regions[group.part].label} in the screenshot`"
              @mouseenter="active = group.part"
              @focus="active = group.part"
              @click="active = group.part"
            >
              <span v-for="(line, n) in group.lines" :key="n" class="line" v-html="paint(line)" />
            </button>
            <span v-else v-for="(line, n) in group.lines" :key="`plain-${n}`" class="line" v-html="paint(line) || '&nbsp;'" />
          </template>
        </div>
      </div>

      <figure class="screen">
        <div class="desktop">
          <img
            v-for="scheme in ['light', 'dark']"
            :key="scheme"
            :class="`${scheme}-only`"
            :src="shot('index', scheme)"
            alt="The posts index in ReactiveAdmin: action buttons, scope tabs with counts, a row of filters, and a table of posts with status badges"
            width="1440"
            height="900"
          />
          <span
            class="mark"
            aria-hidden="true"
            :style="{
              left: `${regions[active].left}%`,
              top: `${regions[active].top}%`,
              width: `${regions[active].width}%`,
              height: `${regions[active].height}%`,
            }"
          />
        </div>
        <div class="phone">
          <img
            v-for="scheme in ['light', 'dark']"
            :key="scheme"
            :class="`${scheme}-only`"
            :src="shot('index-mobile', scheme)"
            alt="The same posts index on a phone, with each post as a card"
            width="390"
            height="844"
          />
        </div>
        <figcaption>
          A registration like this renders as a table on a wide screen and as cards on a phone.
          <span class="wide-only">Choose a part of the file to find it in the screenshot.</span>
        </figcaption>
      </figure>
    </section>

    <section class="also" aria-labelledby="also-title">
      <h2 id="also-title">The same file also answers API clients and agents</h2>
      <div class="pair">
        <div>
          <h3>JSON API</h3>
          <pre><code>{{ request }}</code></pre>
          <p>Typed values, not HTML. The <a :href="withBase('/guide/openapi')">OpenAPI document</a> lists only what the signed-in admin may access.</p>
        </div>
        <div>
          <h3>MCP server</h3>
          <pre><code>{{ tool }}</code></pre>
          <p>Agents call the same API as the admin their token belongs to. MCP is off until you turn it on, and each resource is <a :href="withBase('/guide/mcp')">read-only until you opt it in</a>.</p>
        </div>
      </div>
    </section>

    <section class="ledger" aria-labelledby="ledger-title">
      <h2 id="ledger-title" class="visually-hidden">What stays and what's new</h2>
      <div>
        <h3>Stays as it is</h3>
        <ul>
          <li v-for="item in kept" :key="item">{{ item }}</li>
        </ul>
      </div>
      <div>
        <h3>New</h3>
        <ul>
          <li v-for="item in added" :key="item.text">
            <a :href="withBase(item.link)" :target="item.external ? '_self' : undefined">{{ item.text }}</a>
          </li>
        </ul>
      </div>
    </section>

    <section class="setup" aria-labelledby="install-title">
      <h2 id="install-title">Install</h2>
      <pre><code>bundle add reactiveadmin
bin/rails generate reactiveadmin:install</code></pre>
      <p><a :href="withBase('/guide/getting-started')">Getting started</a> covers configuration, routes, and the client.</p>
    </section>
  </div>
</template>

<style scoped>
.home {
  max-width: 1240px;
  margin: 0 auto;
  padding: 56px 32px 96px;
  color: var(--ra-ink);
}

.intro h1 {
  max-width: 17ch;
  font-size: clamp(2.25rem, 5vw, 4rem);
  font-weight: 600;
  line-height: 1.04;
  letter-spacing: -0.03em;
}
.intro h1 em {
  font-style: italic;
  font-weight: 500;
}
.lede {
  max-width: 62ch;
  margin-top: 24px;
  font-size: 1.25rem;
  line-height: 1.5;
  color: var(--ra-slate);
}
.actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px 24px;
  margin-top: 32px;
}
.actions a {
  font-weight: 500;
  text-decoration: none;
}
.actions .primary,
.actions .secondary {
  padding: 10px 20px;
  border: 1px solid var(--ra-blue);
  border-radius: 6px;
}
.actions .primary {
  background: #2b5c8e;
  border-color: #2b5c8e;
  color: #fff;
}
.actions .secondary {
  color: var(--ra-blue);
}
.actions .plain {
  color: var(--ra-ink);
  border-bottom: 1px solid var(--ra-rule);
}
.actions .plain:hover {
  border-bottom-color: currentColor;
}
a:focus-visible,
button:focus-visible {
  outline: 2px solid var(--ra-blue);
  outline-offset: 2px;
}

.proof {
  display: grid;
  grid-template-columns: minmax(0, 23rem) minmax(0, 1fr);
  gap: 28px;
  align-items: start;
  margin-top: 56px;
}
.source {
  background: var(--ra-code);
  border: 1px solid var(--ra-code);
  border-radius: 10px;
  overflow: hidden;
}
.file {
  margin: 0;
  padding: 10px 16px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.75rem;
  color: #8b98aa;
  border-bottom: 1px solid #1f2b3a;
}
.code {
  padding: 12px 0;
  overflow-x: auto;
  font-family: var(--vp-font-family-mono);
  font-size: 0.75rem;
  line-height: 1.65;
  color: #c9d3e0;
}
.line {
  display: block;
  padding: 0 16px 0 14px;
  white-space: pre;
}
.part {
  display: block;
  width: 100%;
  padding: 0;
  border: 0;
  border-left: 2px solid #33445a;
  background: none;
  color: inherit;
  font: inherit;
  text-align: left;
  cursor: pointer;
}
.part:focus-visible {
  outline-offset: -2px;
}
.part.on {
  border-left-color: var(--ra-marker);
  background: rgba(224, 165, 38, 0.1);
  color: #fff;
}
.code :deep(.sym) {
  color: #9cc4f0;
}
.code :deep(.str) {
  color: #e9c98a;
}
.code :deep(.kw) {
  color: #8b98aa;
}

.screen {
  position: relative;
  margin: 0;
}
.desktop {
  position: relative;
  border: 1px solid var(--ra-rule);
  border-radius: 10px;
  overflow: hidden;
  box-shadow: 0 18px 50px rgba(23, 32, 43, 0.14);
}
.screen img {
  display: block;
  width: 100%;
  height: auto;
}
.mark {
  position: absolute;
  border: 2px solid var(--ra-marker);
  border-radius: 6px;
  background: rgba(224, 165, 38, 0.14);
  transition:
    left 0.25s ease,
    top 0.25s ease,
    width 0.25s ease,
    height 0.25s ease;
}
.phone {
  position: absolute;
  right: 20px;
  top: 34%;
  width: 22%;
  border: 5px solid #17202b;
  border-radius: 22px;
  overflow: hidden;
  box-shadow: 0 18px 50px rgba(23, 32, 43, 0.28);
}
figcaption {
  max-width: 34ch;
  margin-top: 20px;
  font-size: 0.875rem;
  color: var(--ra-slate);
}
.dark .light-only,
html:not(.dark) .dark-only {
  display: none;
}
.dark .source {
  border-color: var(--ra-rule);
}
.dark .phone {
  border-color: #46556a;
}

h2 {
  font-size: 1.75rem;
  font-weight: 600;
  line-height: 1.2;
  letter-spacing: -0.015em;
}
h3 {
  font-size: 1rem;
  font-weight: 600;
}
section p a,
.ledger a {
  color: var(--ra-blue);
  text-decoration: underline;
  text-decoration-color: var(--ra-rule);
  text-underline-offset: 3px;
}
section p a:hover,
.ledger a:hover {
  text-decoration-color: currentColor;
}

.also {
  margin-top: 96px;
}
.pair {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 40px;
  margin-top: 28px;
}
.pair p {
  max-width: 52ch;
  margin-top: 14px;
  color: var(--ra-slate);
  line-height: 1.55;
}
pre {
  margin: 12px 0 0;
  padding: 16px 18px;
  overflow-x: auto;
  background: var(--ra-code);
  border-radius: 10px;
  font-family: var(--vp-font-family-mono);
  font-size: 0.8125rem;
  line-height: 1.6;
  color: #c9d3e0;
}

.ledger {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 40px;
  margin-top: 96px;
  padding-top: 40px;
  border-top: 1px solid var(--ra-rule);
}
.ledger ul {
  margin: 16px 0 0;
  padding: 0;
  list-style: none;
}
.ledger li {
  padding: 10px 0;
  border-top: 1px solid var(--ra-rule);
  font-size: 1.0625rem;
  line-height: 1.4;
}

.setup {
  max-width: 46rem;
  margin-top: 96px;
}
.setup p {
  margin-top: 14px;
  color: var(--ra-slate);
  line-height: 1.55;
}

.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}

@media (max-width: 900px) {
  .home {
    padding: 48px 20px 72px;
  }
  .proof {
    grid-template-columns: minmax(0, 1fr);
  }
  .pair,
  .ledger {
    grid-template-columns: minmax(0, 1fr);
  }
}
@media (max-width: 640px) {
  /* A desktop screenshot is unreadable at this width, and the reader is holding the phone view. */
  .desktop,
  .wide-only {
    display: none;
  }
  .phone {
    position: static;
    width: min(100%, 300px);
    margin: 0 auto;
  }
  figcaption {
    max-width: none;
  }
  .part {
    cursor: default;
  }
  .part.on {
    border-left-color: #33445a;
    background: none;
    color: inherit;
  }
}
@media (prefers-reduced-motion: reduce) {
  .mark {
    transition: none;
  }
}
</style>
