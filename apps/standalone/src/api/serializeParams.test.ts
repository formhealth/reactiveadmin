import { describe, expect, it } from 'vitest'
import { serializeParams } from './serializeParams'

describe('serializeParams', () => {
  it('sends array predicates the way Rails reads them', () => {
    expect(decodeURIComponent(serializeParams({ q: { weight_in: ['1', '2'], name_cont: 'a' }, per_page: 10 }))).toBe('q[weight_in][]=1&q[weight_in][]=2&q[name_cont]=a&per_page=10')
  })

  it('sends form_fields as top-level params, keeping bracketed names', () => {
    expect(decodeURIComponent(serializeParams({ form_fields: { 'report[term]': 'urgent', 'tags[]': ['a', 'b'], 'ids': ['1'] }, q: { name_cont: 'a' } }))).toBe(
      'report[term]=urgent&tags[]=a&tags[]=b&ids[]=1&q[name_cont]=a',
    )
  })

  it('sends null blank and booleans as 1/0, as a GET form does', () => {
    expect(decodeURIComponent(serializeParams({ form_fields: { 'report[term]': null, 'report[urgent]': true, 'report[closed]': false } }))).toBe(
      'report[term]=&report[urgent]=1&report[closed]=0',
    )
  })

  it('leaves out undefined values and handles no params', () => {
    expect(serializeParams({ page: undefined })).toBe('')
    expect(serializeParams()).toBe('')
  })
})
