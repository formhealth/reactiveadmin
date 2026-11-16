// Snapshots the gem's sanitizer policy (a host app prints it with `rake reactiveadmin:html_policy`). Defaults to the gem's
// dummy app; HOST_APP_PATH points at another Rails app. The gem's html_policy_spec fails when the snapshot drifts.
import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const hostApp = process.env.HOST_APP_PATH ?? fileURLToPath(new URL('../../../gem/spec/dummy', import.meta.url))
const out = execFileSync('bundle', ['exec', 'rake', 'reactiveadmin:html_policy'], { cwd: hostApp, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] })

const policy = JSON.parse(out)
if (!policy.display || !policy.frame) throw new Error('Unexpected policy shape; is the gem up to date?')

// Trusted hosts are per deployment: the client reads them from the manifest (`site.trusted_media_hosts`) instead.
policy.display.trusted_hosts = []
policy.frame.trusted_hosts = []

writeFileSync(new URL('../src/sanitize/htmlPolicy.json', import.meta.url), `${JSON.stringify(policy, null, 2)}\n`)
console.log(`Wrote html policy v${policy.version} from ${hostApp}`)
