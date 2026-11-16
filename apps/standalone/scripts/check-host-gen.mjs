// Proves `reactiveadmin-gen` works end to end: writes the dummy app's full OpenAPI document with
// `rake reactiveadmin:openapi`, generates hooks from it (single file and split by tag), typechecks them
// against a small consumer and runs their requests against a stubbed fetch. Needs Ruby and the gem's bundle.
// Used by CI; run it with `pnpm check:host-gen`.
import { spawnSync } from 'node:child_process'
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { generate } from 'orval'
import { hostOrvalConfig } from './reactiveadmin-gen.mjs'

const client = path.resolve(fileURLToPath(import.meta.url), '../..')
const dummy = path.resolve(client, '../../gem/spec/dummy')
// Inside the package so the generated files resolve its imports, and outside node_modules so vitest runs the tests there.
const work = path.join(client, 'tmp/host-gen')
const document = path.join(work, 'admin.yaml')

const run = (command, args, options) => {
  const { status } = spawnSync(command, args, { stdio: 'inherit', ...options })
  if (status !== 0) throw new Error(`${command} ${args.join(' ')} failed`)
}

rmSync(work, { recursive: true, force: true })
mkdirSync(work, { recursive: true })

const env = { ...process.env, RAILS_ENV: 'test', DATABASE_URL: `sqlite3://${path.join(work, 'dummy.sqlite3')}`, OUT: document, BUNDLE_GEMFILE: path.join(dummy, '../../Gemfile') }
run('bundle', ['exec', 'ruby', 'bin/crawl_prepare'], { cwd: dummy, env, stdio: ['ignore', 'ignore', 'inherit'] })
run('bundle', ['exec', 'rake', 'reactiveadmin:openapi'], { cwd: dummy, env })

// The preset's imports are relative to the client, so it refuses an output elsewhere.
try {
  hostOrvalConfig({ input: document, output: tmpdir() })
  throw new Error('host-gen: an output outside the client package was accepted')
} catch (error) {
  if (!/inside the client package/.test(error.message)) throw error
}

// The source of one generated function, so a check can't match text elsewhere in a 30,000-line file.
const definition = (source, name) => {
  const start = source.indexOf(`export const ${name} =`)
  const end = source.indexOf('\n}', start)
  if (start < 0 || end < 0) throw new Error(`host-gen: ${name} not generated`)
  return source.slice(start, end)
}

const variants = { single: { split: false, hooks: () => './hooks' }, split: { split: true, hooks: (tag) => `./tags/${tag}/${tag}` } }
for (const [name, { split, hooks }] of Object.entries(variants)) {
  const output = path.join(work, name)
  const config = hostOrvalConfig({ input: document, output, split })
  // The dummy app's forms have no file input; an avatar on authors proves an upload goes out as multipart.
  const { transformer } = config.input.override
  config.input.override.transformer = (spec) => {
    spec.components.schemas.AuthorCreateParams.properties.author.properties.avatar = { type: 'string', format: 'binary' }
    return transformer(spec)
  }
  await generate(config, client)
  const generated = readFileSync(path.join(output, `${hooks('authors')}.ts`), 'utf8')
  const expectations = [
    // Array filters must go out as `q[x][]=`, which only the Rails-aware serializer does.
    ['getListAuthorsUrl', 'serializeParams(params)', "list URLs don't use the Rails params serializer"],
    // A composite ID such as `east_A/1` must stay one path segment.
    ['getGetAuthorUrl', 'encodeURIComponent(String(id))', "member URLs don't encode the id"],
    ['createAuthor', 'writeBody(authorCreateParams)', "uploads aren't sent through writeBody"],
  ]
  for (const [fn, text, failure] of expectations) if (!definition(generated, fn).includes(text)) throw new Error(`host-gen ${name}: ${failure}`)
  // Typed means a wrong filter predicate is a compile error. Rows aren't checked: `Row.cells` keeps its string index signature.
  writeFileSync(
    path.join(output, 'consumer.ts'),
    `import { useCreateAuthor, useListAuthors } from '${hooks('authors')}'
import type { AuthorRow, ListAuthorsParams, ListNotesParams } from './model'

export const params: ListAuthorsParams = { q: { name_cont: 'a' }, per_page: 10 }
export const arrayFilter: ListNotesParams = { q: { weight_in: ['1', '2'] } }
// @ts-expect-error not a declared filter predicate
export const bad: ListAuthorsParams = { q: { nope_cont: 'a' } }

export const useAuthorNames = () => useListAuthors(params, { query: { select: (page) => page.rows.map((row: AuthorRow) => row.cells?.name) } })
export const useAuthorCreate = () => useCreateAuthor()
`,
  )
  writeFileSync(
    path.join(output, 'requests.test.ts'),
    `import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import { createAuthor, exportAuthorsCsv, getAuthor } from '${hooks('authors')}'
import { listNotes } from '${hooks('notes')}'

const fetchMock = vi.fn<typeof fetch>(async (input) =>
  String(input).endsWith('/_session')
    ? Response.json({ csrf_token: 't' })
    : String(input).includes('.csv')
      ? new Response('id\\n1\\n', { headers: { 'Content-Type': 'text/csv' } })
      : Response.json({}),
)
const lastCall = () => fetchMock.mock.calls.at(-1)!

beforeEach(() => vi.stubGlobal('fetch', fetchMock))
afterEach(() => vi.unstubAllGlobals())

it('sends an _in filter the way Rails reads it', async () => {
  await listNotes({ q: { weight_in: ['1', '2'] } })
  expect(decodeURIComponent(String(lastCall()[0]))).toBe('/api/admin/notes?q[weight_in][]=1&q[weight_in][]=2')
})

it('keeps a composite id in one path segment', async () => {
  await getAuthor('east_A/1')
  expect(lastCall()[0]).toBe('/api/admin/authors/east_A%2F1')
})

it('returns a CSV export as a Blob', async () => {
  const file = await exportAuthorsCsv()
  expect(lastCall()[0]).toBe('/api/admin/authors.csv')
  expect(await file.text()).toBe('id\\n1\\n')
})

it('uploads a file as multipart', async () => {
  await createAuthor({ author: { name: 'Ann', avatar: new File(['png'], 'a.png', { type: 'image/png' }) } })
  const { body, headers } = lastCall()[1]!
  expect(body).toBeInstanceOf(FormData)
  expect((body as FormData).get('author[name]')).toBe('Ann')
  expect(((body as FormData).get('author[avatar]') as File).name).toBe('a.png')
  expect(headers).not.toHaveProperty('Content-Type')
})

it('sends JSON without a file', async () => {
  await createAuthor({ author: { name: 'Ann' } })
  const body = lastCall()[1]!.body as Blob
  expect(body.type).toBe('application/json')
  expect(JSON.parse(await body.text())).toEqual({ author: { name: 'Ann' } })
})
`,
  )
  writeFileSync(
    path.join(output, 'tsconfig.json'),
    JSON.stringify({ extends: path.join(client, 'tsconfig.app.json'), compilerOptions: { paths: { '@/*': [path.join(client, 'src/*')] } }, include: [output] }),
  )
  run(process.execPath, [path.join(client, 'node_modules/typescript/bin/tsc'), '-p', path.join(output, 'tsconfig.json')], { cwd: client })
  writeFileSync(
    path.join(output, 'vitest.config.ts'),
    `import base from '${path.join(client, 'vite.config.ts')}'
export default { ...base, test: { ...base.test, include: ['${output}/*.test.ts'] } }
`,
  )
  run(process.execPath, [path.join(client, 'node_modules/vitest/vitest.mjs'), 'run', '--config', path.join(output, 'vitest.config.ts')], { cwd: client })
  console.log(`host-gen ${name}: ok`)
}
