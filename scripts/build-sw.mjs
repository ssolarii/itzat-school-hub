import { readFile, writeFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, relative, sep } from 'node:path';

const dist = resolve('dist');
async function filesIn(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  return (await Promise.all(entries.map(entry => entry.isDirectory() ? filesIn(resolve(directory, entry.name)) : resolve(directory, entry.name)))).flat();
}
const files = (await filesIn(dist)).filter(file => {
  const path = relative(dist, file).split(sep).join('/');
  return path === 'index.html' || path === 'manifest.webmanifest' || /^(?:assets\/.*|[^/]+)\.(?:js|css|svg|png|jpg|jpeg|webp|ico|woff2?|ttf)$/i.test(path) && path !== 'sw.js';
}).sort();
if (!files.some(file => relative(dist, file) === 'index.html')) throw new Error('Build the Vite app before generating the service worker');
const hash = createHash('sha256');
const template = await readFile(resolve('public/sw.js'), 'utf8');
// Worker behavior changes must create a new cache even if app assets are unchanged.
hash.update(template);
for (const file of files) { hash.update(relative(dist, file)); hash.update(await readFile(file)); }
const buildId = hash.digest('hex').slice(0, 16);
const assets = files.map(file => relative(dist, file).split(sep).join('/'));
await writeFile(resolve(dist, 'sw.js'), template.replace('__BUILD_ID__', buildId).replace('__BUILD_ASSETS__', JSON.stringify(assets)));
process.stdout.write(`Offline shell ${buildId}: ${assets.length} versioned assets.\n`);
