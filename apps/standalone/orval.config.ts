import { defineConfig } from 'orval'

export default defineConfig({
  core: {
    input: { target: '../../openapi/core.yaml', override: { transformer: './orval.transform.mjs' } },
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
})
