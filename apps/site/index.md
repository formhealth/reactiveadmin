---
layout: home
title: ReactiveAdmin

hero:
  name: ReactiveAdmin
  text: A modern admin for your ActiveAdmin
  tagline: Front your ActiveAdmin resources and pages with a JSON API, an OpenAPI document, an MCP server, and a modern React admin.
  actions:
    - theme: brand
      text: Get started
      link: /guide/getting-started
    - theme: alt
      text: Try the demo
      link: /demo/
      target: _self
    - theme: alt
      text: Browse the components
      link: /storybook/
      target: _self
    - theme: alt
      text: Why ReactiveAdmin
      link: /guide/overview
    - theme: alt
      text: GitHub
      link: https://github.com/formhealth/reactiveadmin

features:
  - title: Classic ActiveAdmin, untouched
    details: Your app/admin files stay the source of truth. ReactiveAdmin reuses their controllers, filters, scopes, forms, actions, and authorization instead of replacing them.
    link: /guide/activeadmin-support
    linkText: What's supported
  - title: Secure defaults
    details: ActiveAdmin's authentication and authorization still apply. Expose only the resources you list, guard the API per resource, and hide sensitive columns unless you opt in.
    link: /guide/security
    linkText: Security guide
  - title: MCP for agents
    details: A Model Context Protocol (MCP) server whose tools call the same API, with bearer-token authentication and read and write scopes.
    link: /guide/mcp
    linkText: MCP server
  - title: OpenAPI and typed clients
    details: An OpenAPI 3.1 document filtered to what the requesting admin may access, plus a React client generated from the contract.
    link: /guide/openapi
    linkText: OpenAPI
  - title: Audit and masking
    details: Mask attributes, summarize or tokenize JSON values, rate-limit lookups, and subscribe to audit events that carry IDs and never record data.
    link: /guide/security#masking
    linkText: Masking and audit
  - title: Incremental rollout
    details: Serve the new admin at your classic admin's URLs, switched per person by a cookie. The doctor task measures how much of your admin renders natively.
    link: /guide/rollout
    linkText: Roll it out
---

<div class="install">

## Install

ReactiveAdmin isn't on RubyGems yet. Until it is, install the gem from GitHub:

```ruby
gem "reactiveadmin", github: "formhealth/reactiveadmin", glob: "gem/*.gemspec"
```

Once the gem is published and the install generator lands, setup becomes:

```sh
bundle add reactiveadmin
rails g reactiveadmin:install
```

[Getting started](/guide/getting-started) walks through configuration, routes, and the client.

</div>

<style>
.install {
  max-width: 688px;
  margin: 0 auto;
  padding: 48px 24px 64px;
}
.install h2 {
  border-top: 0;
  margin-top: 0;
}
</style>
