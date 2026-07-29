// Diagnostic: dump every rendered object with its world position, world scale,
// and the visual angle it subtends from the camera. Anything absurdly large is
// the bug.
import { chromium } from 'playwright';

const BASE = process.argv[2] || 'http://localhost:5181';
const MODE = process.argv[3] || 'home';

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on('pageerror', (e) => console.error('pageerror:', e.message));

await page.goto(`${BASE}/?test=1&diag=1`, { waitUntil: 'networkidle' });
await page.waitForTimeout(600);
if (MODE === 'console') { await page.click('#m-console'); await page.waitForTimeout(600); }
await page.waitForTimeout(1500);

const rows = await page.evaluate(() => {
  const { scene, camera, THREE } = window.__diag;
  const out = [];
  const p = new THREE.Vector3(), s = new THREE.Vector3(), q = new THREE.Quaternion();
  scene.updateMatrixWorld(true);
  scene.traverse((o) => {
    if (!o.visible || (!o.isMesh && !o.isSprite && !o.isLine)) return;
    o.matrixWorld.decompose(p, q, s);
    const dist = p.distanceTo(camera.position);
    // approximate extent from geometry bounding sphere * world scale
    let r = 0;
    if (o.isSprite) r = Math.max(s.x, s.y) / 2;
    else if (o.geometry) {
      if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
      r = (o.geometry.boundingSphere?.radius || 0) * Math.max(s.x, s.y, s.z);
    }
    const deg = dist > 0.001 ? (2 * Math.atan(r / dist) * 180) / Math.PI : 999;
    out.push({
      name: o.name || o.type + (o.userData?.isLabel ? '(label)' : ''),
      parent: o.parent?.name || o.parent?.type || '',
      dist: +dist.toFixed(2), r: +r.toFixed(3), deg: +deg.toFixed(1),
    });
  });
  return out.sort((a, b) => b.deg - a.deg).slice(0, 22);
});

console.log(`\nmode=${MODE} — largest objects by subtended visual angle\n`);
console.log('  deg   dist    r     object');
for (const r of rows) {
  console.log(`  ${String(r.deg).padStart(5)}  ${String(r.dist).padStart(5)}  ${String(r.r).padStart(5)}  ${r.name}  <- ${r.parent}`);
}
await browser.close();
