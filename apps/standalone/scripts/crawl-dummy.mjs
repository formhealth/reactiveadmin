// Boots the gem's dummy app (seeded sqlite) and Vite pointed at it, runs the crawl, and stops both.
// Extra arguments go to the crawl: `pnpm crawl:dummy --resources=posts`.
import { spawn, spawnSync } from 'node:child_process'
import { rmSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import net from 'node:net'

const client = path.resolve(fileURLToPath(import.meta.url), '../..')
const gem = path.resolve(client, '../../gem')
const dummy = path.join(gem, 'spec/dummy')
const railsPort = Number(process.env.CRAWL_RAILS_PORT ?? 3098)
const vitePort = Number(process.env.CRAWL_VITE_PORT ?? 5198)
const host = '127.0.0.1'
const database = path.join(dummy, 'tmp/crawl.sqlite3')
const env = { ...process.env, RAILS_ENV: 'test', DATABASE_URL: `sqlite3://${database}`, BUNDLE_GEMFILE: path.join(gem, 'Gemfile') }

const inUse = (port) =>
  new Promise((resolve) => {
    const socket = net.connect(port, host)
    socket.once('connect', () => (socket.destroy(), resolve(true)))
    socket.once('error', () => resolve(false))
  })

async function waitFor(url, label, children) {
  for (let i = 0; i < 120; i++) {
    if (children.some((c) => c.exitCode !== null)) throw new Error(`${label} exited early`)
    try {
      await fetch(url)
      return
    } catch {
      await new Promise((r) => setTimeout(r, 500))
    }
  }
  throw new Error(`${label} did not come up at ${url}`)
}

const children = []
const stop = () => children.forEach((c) => c.exitCode === null && c.pid && process.kill(-c.pid, 'SIGTERM'))
process.on('SIGINT', () => (stop(), process.exit(130)))
process.on('SIGTERM', () => (stop(), process.exit(143)))

let code = 2
try {
  for (const port of [railsPort, vitePort]) if (await inUse(port)) throw new Error(`port ${port} is in use; set CRAWL_RAILS_PORT / CRAWL_VITE_PORT`)

  rmSync(database, { force: true })
  const prepared = spawnSync('bundle', ['exec', 'ruby', 'spec/dummy/bin/crawl_prepare'], { cwd: gem, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] })
  if (prepared.status !== 0) throw new Error('seeding the dummy app failed')
  const adminId = prepared.stdout.trim().split('\n').at(-1)

  // Own process groups, so stopping them takes the whole tree.
  const rails = spawn('bundle', ['exec', 'rackup', 'spec/dummy/config.ru', '-p', String(railsPort), '-o', host], { cwd: gem, env, detached: true, stdio: 'ignore' })
  const vite = spawn(process.execPath, ['node_modules/vite/bin/vite.js', '--host', host, '--port', String(vitePort), '--strictPort'], {
    cwd: client,
    env: { ...process.env, RA_API_TARGET: `http://${host}:${railsPort}` },
    detached: true,
    stdio: 'ignore',
  })
  children.push(rails, vite)
  await waitFor(`http://${host}:${railsPort}/login`, 'the dummy app', children)
  await waitFor(`http://${host}:${vitePort}/`, 'vite', children)

  const crawl = spawnSync(process.execPath, ['crawl/cli.ts', ...process.argv.slice(2)], {
    cwd: client,
    stdio: 'inherit',
    env: {
      ...process.env,
      CRAWL_BASE_URL: `http://${host}:${vitePort}`,
      CRAWL_LOGIN: path.join(client, 'crawl/hooks/dummy.login.ts'),
      CRAWL_ALLOWLIST: path.join(client, 'crawl/allowlists/dummy.json'),
      CRAWL_DUMMY_ORIGIN: `http://${host}:${railsPort}`,
      CRAWL_DUMMY_ADMIN_ID: adminId,
    },
  })
  code = crawl.status ?? 2
} catch (error) {
  console.error(`crawl:dummy: ${error.message}`)
} finally {
  stop()
}
process.exit(code)
