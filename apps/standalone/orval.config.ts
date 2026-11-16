import { defineConfig } from 'orval'

const input = { target: '../../openapi/core.yaml', override: { transformer: './orval.transform.mjs' } }

export default defineConfig({
  core: {
    input,
    output: {
      target: 'src/api/generated/core.ts',
      schemas: 'src/api/generated/model',
      client: 'react-query',
      mode: 'single',
      clean: true,
      override: {
        mutator: { path: 'src/api/fetcher.ts', name: 'apiFetch' },
        fetch: { includeHttpResponseReturnType: false },
      },
    },
  },
  // Response schemas only: src/api/contract.ts checks responses against them in dev and tests.
  zod: {
    input,
    output: {
      target: 'src/api/generated/zod/core.ts',
      client: 'zod',
      mode: 'single',
      clean: true,
      override: { zod: { generate: { param: false, query: false, header: false, body: false, response: true } } },
    },
  },
})
