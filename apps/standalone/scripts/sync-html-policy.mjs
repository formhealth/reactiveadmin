// Snapshots the gem's sanitizer policy (the host app prints it with `rake reactiveadmin:html_policy`).
import { execFileSync } from 'node:child_process'
import { writeFileSync } from 'node:fs'

const hostApp = process.env.HOST_APP_PATH
if (!hostApp) {
  console.error('Set HOST_APP_PATH to a Rails app that runs the reactiveadmin gem, e.g. HOST_APP_PATH=~/code/my-app pnpm policy:sync')
  process.exit(1)
}
const out = execFileSync('bundle', ['exec', 'rake', 'reactiveadmin:html_policy'], { cwd: hostApp, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] })

const policy = JSON.parse(out)
if (!policy.display || !policy.frame) throw new Error('Unexpected policy shape; is the gem up to date?')

// Trusted hosts are per deployment: the client reads them from the manifest (`site.trusted_media_hosts`) instead.
policy.display.trusted_hosts = []
policy.frame.trusted_hosts = []

writeFileSync(new URL('../src/sanitize/htmlPolicy.json', import.meta.url), `${JSON.stringify(policy, null, 2)}\n`)
console.log(`Wrote html policy v${policy.version} from ${hostApp}`)
