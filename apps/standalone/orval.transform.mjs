// core.yaml: a comma or colon inside a flow-mapping `description:` (e.g. `e.g. x`, `pages, external links)`)
// parses as a stray key. Drop any schema keyword that isn't a plain identifier.
export default (spec) => {
  for (const schema of Object.values(spec.components.schemas))
    for (const prop of Object.values(schema.properties ?? {}))
      for (const key of Object.keys(prop)) if (!/^[\w$]+$/.test(key)) delete prop[key]
  return spec
}
