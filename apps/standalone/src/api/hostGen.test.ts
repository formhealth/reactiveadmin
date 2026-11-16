import { describe, expect, it } from 'vitest'
import { cachePolicies, uploadsAsMultipart } from '../../scripts/reactiveadmin-gen.mjs'

describe('the host hooks preset', () => {
  it('always refetches an opened record or edit form, and never keeps a revealed value', () => {
    const spec = {
      paths: {
        '/api/admin/authors': { get: { operationId: 'listAuthors' } },
        '/api/admin/authors/{id}': { get: { operationId: 'getAuthor' }, patch: { operationId: 'updateAuthor' } },
        '/api/admin/authors/{id}/edit': { get: { operationId: 'getEditAuthorForm' } },
        '/api/admin/authors/{id}/_value': { get: { operationId: 'getAuthorValue' } },
      },
    }
    expect(cachePolicies(spec)).toEqual({
      getAuthor: { query: { options: { refetchOnMount: 'always' } } },
      getEditAuthorForm: { query: { options: { refetchOnMount: 'always' } } },
      getAuthorValue: { query: { options: { staleTime: 0, gcTime: 0 } } },
    })
  })

  it('types a JSON control as JSON text in a multipart write, and leaves JSON writes alone', () => {
    const body = (properties: object) => ({ type: 'object', properties: { author: { type: 'object', properties } } })
    const spec = {
      components: { schemas: { AuthorWrite: body({ avatar: { type: 'string', format: 'binary' }, metadata: { 'x-control': 'json' } }) } },
      paths: {
        '/api/admin/authors': { post: { requestBody: { content: { 'application/json': { schema: { $ref: '#/components/schemas/AuthorWrite' } } } } } },
        '/api/admin/posts': { post: { requestBody: { content: { 'application/json': { schema: body({ meta: { 'x-control': 'json' } }) } } } } },
      },
    }
    const out = uploadsAsMultipart(structuredClone(spec))
    expect(Object.keys(out.paths['/api/admin/authors'].post.requestBody.content)).toEqual(['multipart/form-data'])
    expect(out.components.schemas.AuthorWrite.properties.author.properties.metadata).toMatchObject({ type: 'string' })
    expect(out.paths['/api/admin/posts'].post.requestBody.content['application/json'].schema.properties.author.properties.meta).toEqual({ 'x-control': 'json' })
  })

  it('reaches JSON controls inside has_many rows, keyed by index', () => {
    const rows = { type: 'object', additionalProperties: { type: 'object', properties: { file: { type: 'string', format: 'binary' }, data: { 'x-control': 'json' } } } }
    const spec = { paths: { '/api/admin/posts': { post: { requestBody: { content: { 'application/json': { schema: { type: 'object', properties: { post: { type: 'object', properties: { attachments_attributes: rows } } } } } } } } } } }
    const out = uploadsAsMultipart(structuredClone(spec))
    const row = out.paths['/api/admin/posts'].post.requestBody.content['multipart/form-data'].schema.properties.post.properties.attachments_attributes.additionalProperties
    expect(row.properties.data).toMatchObject({ type: 'string' })
  })
})
