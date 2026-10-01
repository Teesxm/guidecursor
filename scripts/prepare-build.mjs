import { createHash } from 'node:crypto'
import { execSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'

const commit = process.env.VERCEL_GIT_COMMIT_SHA || process.env.GITHUB_SHA || 'local'
const deploymentIdentity =
  process.env.VERCEL_URL ||
  process.env.VERCEL_DEPLOYMENT_ID ||
  process.env.DEPLOYMENT_ID ||
  String(Date.now())

const build = createHash('sha256')
  .update([commit, deploymentIdentity].join('|'))
  .digest('hex')
  .slice(0, 16)

let history = []
let sequence = null
try {
  history = execSync('git log --first-parent --format=%H -n 80', { encoding: 'utf8' })
    .trim()
    .split('\n')
    .map((sha) => sha.slice(0, 12))
    .filter(Boolean)
} catch {}

try {
  const raw = execSync('git rev-list --first-parent --count HEAD', { encoding: 'utf8' }).trim()
  const parsed = Number(raw)
  if (Number.isFinite(parsed) && parsed > 0) sequence = parsed
} catch {}

if (!history.length && commit !== 'local') history = [commit.slice(0, 12)]

const envPath = '.env.local'
let env = existsSync(envPath) ? readFileSync(envPath, 'utf8') : ''
env = env
  .split('\n')
  .filter((line) => !line.startsWith('VITE_BUILD_ID='))
  .join('\n')
  .replace(/\n+$/, '')

writeFileSync(envPath, (env ? env + '\n' : '') + `VITE_BUILD_ID=${build}\n`)

mkdirSync('public', { recursive: true })
writeFileSync(
  'public/version.json',
  JSON.stringify(
    {
      build,
      commit: commit.slice(0, 12),
      deployment: deploymentIdentity,
      generatedAt: new Date().toISOString(),
      sequence,
      history,
      checkerVersion: 2,
    },
    null,
    2,
  ) + '\n',
)

console.log(`Prepared GuideCursor build ${build} with ${history.length} commit(s) in update history`)
