// Generates typed react-query hooks (`useListAuthors`) from a host's own OpenAPI document, the output of
// `rake reactiveadmin:openapi`, through the same `apiFetch` mutator as the generic client.
//   node scripts/reactiveadmin-gen.mjs <openapi.yaml> <outDir> [--split] [--mutator <module exporting apiFetch>]
import { readFileSync, statSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parseArgs } from 'node:util'
import { generate } from 'orval'
import { parse } from 'yaml'
import transformer from '../orval.transform.mjs'

const client = path.resolve(fileURLToPath(import.meta.url), '../..')
const defaultMutator = path.join(client, 'src/api/fetcher.ts')
const paramsSerializer = { path: path.join(client, 'src/api/serializeParams.ts'), name: 'serializeParams' }
const formData = { path: path.join(client, 'src/api/writeBody.ts'), name: 'writeBody' }

// Orval imports these helpers into every tag file, including those that don't call them, which fails a host's `noUnusedLocals`.
const dropUnusedHelpers = (paths) => {
  for (const file of paths.filter((p) => p.endsWith('.ts') && statSync(p).isFile())) {
    const source = readFileSync(file, 'utf8')
    const unused = [paramsSerializer.name, formData.name].filter((name) => !source.includes(`${name}(`))
    const stripped = unused.reduce((text, name) => text.replace(new RegExp(`^import \\{ ${name} \\} from .*\\n`, 'm'), ''), source)
    if (stripped !== source) writeFileSync(file, stripped)
  }
}

const containsBinary = (schema, schemas, seen = new Set()) => {
  if (!schema || typeof schema !== 'object' || seen.has(schema)) return false
  seen.add(schema)
  if (schema.$ref) return containsBinary(schemas[schema.$ref.split('/').pop()], schemas, seen)
  return schema.format === 'binary' || Object.values(schema).some((value) => containsBinary(value, schemas, seen))
}

// The document types a file control as a binary string in the JSON body, which orval would `JSON.stringify` to `{}`.
// Declared as multipart, the body goes through `writeBody`, which sends multipart only when a file is attached.
// A multipart body has no JSON types, so a JSON control (`x-control: json`) in it is typed as JSON text, which the
// server parses into the structure where the host permits one. Callers pass `JSON.stringify(value)`; `{}` and `[]`
// then survive as clears. has_many rows sit under `additionalProperties` (keyed by index).
const jsonAsText = (schema, schemas, seen = new Set()) => {
  if (!schema || typeof schema !== 'object' || seen.has(schema)) return
  seen.add(schema)
  if (schema.$ref) return jsonAsText(schemas[schema.$ref.split('/').pop()], schemas, seen)
  for (const [name, property] of Object.entries(schema.properties ?? {}))
    if (property?.['x-control'] === 'json') schema.properties[name] = { type: 'string', description: 'JSON text: with a file attached the request is multipart.' }
    else jsonAsText(property, schemas, seen)
  for (const key of ['items', 'additionalProperties', 'allOf', 'oneOf', 'anyOf']) [schema[key]].flat().forEach((part) => jsonAsText(part, schemas, seen))
}

export const uploadsAsMultipart = (spec) => {
  const schemas = spec.components?.schemas ?? {}
  for (const operation of Object.values(spec.paths ?? {}).flatMap((item) => Object.values(item))) {
    const json = operation?.requestBody?.content?.['application/json']
    if (!json || !containsBinary(json.schema, schemas)) continue
    jsonAsText(json.schema, schemas)
    operation.requestBody.content = { 'multipart/form-data': json }
  }
  return spec
}

// Opening a record or its edit form always asks the server (and so its audit), as the generic client's
// `openedRecordQuery` does, and a revealed `_value` never stays in the shared cache, as `src/json/expand.ts` keeps it.
export const cachePolicies = (spec) =>
  Object.fromEntries(
    Object.entries(spec.paths ?? {}).flatMap(([route, item]) => {
      const id = item?.get?.operationId
      if (!id) return []
      if (route.endsWith('/{id}/_value')) return [[id, { query: { options: { staleTime: 0, gcTime: 0 } } }]]
      return /\/\{id\}(\/edit)?$/.test(route) ? [[id, { query: { options: { refetchOnMount: 'always' } } }]] : []
    }),
  )

// The generated files import the client's fetcher and helpers by relative path, so they only resolve from inside it.
const assertInsideClient = (output) => {
  const relative = path.relative(client, path.resolve(output))
  if (!relative || relative.startsWith('..') || path.isAbsolute(relative))
    throw new Error(`reactiveadmin-gen: the output directory must be inside the client package (${client}), not ${path.resolve(output)}`)
}

// `split` writes one file per tag (one per resource and page), so a large admin isn't one huge module.
export const hostOrvalConfig = ({ input, output, mutator = defaultMutator, split = false }) => {
  assertInsideClient(output)
  return {
    input: { target: path.resolve(input), override: { transformer: (spec) => uploadsAsMultipart(transformer(spec)) } },
    output: {
      target: split ? path.resolve(output, 'tags') : path.resolve(output, 'hooks.ts'),
      schemas: path.resolve(output, 'model'),
      client: 'react-query',
      mode: split ? 'tags-split' : 'single',
      clean: true,
      urlEncodeParameters: true,
      override: {
        mutator: { path: path.resolve(mutator), name: 'apiFetch' },
        paramsSerializer,
        formData,
        fetch: { includeHttpResponseReturnType: false },
        operations: cachePolicies(parse(readFileSync(path.resolve(input), 'utf8'))),
      },
    },
    hooks: { afterAllFilesWrite: [dropUnusedHelpers] },
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values, positionals } = parseArgs({ allowPositionals: true, options: { split: { type: 'boolean' }, mutator: { type: 'string' } } })
  const [input, output] = positionals
  if (!input || !output) {
    console.error('usage: reactiveadmin-gen <openapi.yaml> <outDir> [--split] [--mutator <path>]')
    process.exit(2)
  }
  await generate(hostOrvalConfig({ input, output, ...values }), process.cwd())
}
