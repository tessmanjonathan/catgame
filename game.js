import * as THREE from 'three';

// ============================================================
// cat HAS STOPPED WORKING — a work-from-home cat survival game
// ============================================================

// ---------- constants ----------
const FLOOR_Y = { basement: -3, main: 0, up: 3 };
const LEVELS = [-3, 0, 3];
const WALL_H = 2.8;
const EYE = 1.55;
const PLAYER_R = 0.32;
const RING_LIMIT = 18;            // seconds to answer phone
const HEART_MAX = 9;
const TASK_PAY = 35;              // $ per completed work task
const BOB_PAY = 55;               // $ for covering Bob's work
const NO_HEART_BONUS = 20;        // end-of-day bonus if no hearts were lost
const NIGHT_HEAL = 3;             // hearts recovered per night of sleep
const DISTRACT_MIN = 5;           // seconds — a bored cat's attention floor

// you start with one kitten; extra cats are adopted from the shop.
// each new cat is more chaotic than the last, and hazards pace up per cat.
const CHAOS_LADDER = [0.9, 1.3, 1.65, 2.0];
const MAX_CATS = 4;
// adoption is free — the shelter just doesn't always have a cat ready.
// CAT_AVAILABLE_DAYS[n] = the day cat #(n+1) becomes available for adoption.
const CAT_AVAILABLE_DAYS = [1, 3, 6, 10];
function nextCatIdx() { return cats.length + pendingAdopts.length; }
function catAvailable() {
  const i = nextCatIdx();
  return i < MAX_CATS && day >= CAT_AVAILABLE_DAYS[i];
}
function riskWindow() {
  const n = cats.length;
  return [Math.max(16, 34 - 7 * (n - 1)), Math.max(30, 56 - 9 * (n - 1))];
}
const NAME_POOL = ['Whiskers', 'Shadow', 'Luna', 'Toast', 'Chaos', 'Beans', 'Mochi', 'Pickle', 'Noodle', 'Gizmo'];
const CAT_COLORS = [
  { key: 'orange', body: 0xe8933a, dark: 0xd0782a, eye: 0x222222 },
  { key: 'gray',   body: 0x8a8f98, dark: 0x6c7078, eye: 0x222222 },
  { key: 'black',  body: 0x33333a, dark: 0x232328, eye: 0xddcc44 },
  { key: 'white',  body: 0xf2f0ea, dark: 0xd8d4c8, eye: 0x222222 },
  { key: 'calico', body: 0xb07040, dark: 0x7a4a28, eye: 0x222222 },
];

// stairs: enter at z0 (low end), exit at z1 (high end)
const STAIRS = [
  { minX: 0.75, maxX: 2.45, z0: -1.9, z1: -5.0, y0: 0, y1: 3 },   // up
  { minX: -2.3, maxX: -0.6,  z0: -1.9, z1: -5.0, y0: 0, y1: -3 }, // down
];

// ---------- three.js setup ----------
const scene = new THREE.Scene();
scene.background = new THREE.Color(0x87b5e0);
scene.fog = new THREE.Fog(0x87b5e0, 30, 70);

const camera = new THREE.PerspectiveCamera(72, innerWidth / innerHeight, 0.05, 120);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(innerWidth, innerHeight);
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
document.getElementById('app').appendChild(renderer.domElement);
addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
});

scene.add(new THREE.AmbientLight(0xffffff, 0.65));
const sun = new THREE.DirectionalLight(0xfff2d8, 0.9);
sun.position.set(12, 20, 8);
scene.add(sun);
const fill = new THREE.DirectionalLight(0xaac4ff, 0.3);
fill.position.set(-8, 6, -10);
scene.add(fill);

const MAT = {};
function mat(color) {
  if (!MAT[color]) MAT[color] = new THREE.MeshLambertMaterial({ color });
  return MAT[color];
}
function box(w, h, d, color, x, y, z, parent = scene) {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(color));
  m.position.set(x, y, z);
  parent.add(m);
  return m;
}
function prim(geo, color, x, y, z, parent = scene) {
  const m = new THREE.Mesh(geo, mat(color));
  m.position.set(x, y, z);
  parent.add(m);
  return m;
}
function cyl(rt, rb, h, color, x, y, z, parent = scene, seg = 10) {
  return prim(new THREE.CylinderGeometry(rt, rb, h, seg), color, x, y, z, parent);
}
function sph(r, color, x, y, z, parent = scene) {
  return prim(new THREE.SphereGeometry(r, 8, 6), color, x, y, z, parent);
}
function cone(r, h, color, x, y, z, parent = scene, seg = 8) {
  return prim(new THREE.ConeGeometry(r, h, seg), color, x, y, z, parent);
}
function grp(x, y, z, parent = scene) {
  const g = new THREE.Group();
  g.position.set(x, y, z);
  parent.add(g);
  return g;
}
// invisible padded hitbox so tiny things (hair ties, ribbons...) are easy to click.
// added to a group BEFORE registerInteract so it inherits the group's userData.
const HIT_MAT = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false });
function hitPad(parent, r, x = 0, y = 0.12, z = 0) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, 6, 5), HIT_MAT);
  m.position.set(x, y, z);
  parent.add(m);
  return m;
}

// ---------- world state ----------
const walls = [];        // collision AABBs {minX,maxX,minY,maxY,minZ,maxZ}
const interactables = []; // meshes with userData.act
const raycaster = new THREE.Raycaster();

function addWallBox(mesh) {
  mesh.geometry.computeBoundingBox();
  const b = mesh.geometry.boundingBox.clone();
  b.translate(mesh.position);
  walls.push({ minX: b.min.x, maxX: b.max.x, minY: b.min.y, maxY: b.max.y, minZ: b.min.z, maxZ: b.max.z });
  return mesh;
}
function wall(w, h, d, x, y, z, color = 0xd8d2c4) {
  return addWallBox(box(w, h, d, color, x, y, z));
}

// wall run along an axis with gaps (for doors/windows). axis 'x' or 'z'
function wallRun(axis, fixed, from, to, baseY, gaps = [], color = 0xd8d2c4, h = WALL_H) {
  const segs = [];
  let cur = from;
  const sorted = [...gaps].sort((a, b) => a[0] - b[0]);
  for (const [g0, g1] of sorted) { segs.push([cur, g0]); cur = g1; }
  segs.push([cur, to]);
  for (const [a, b] of segs) {
    if (b - a < 0.05) continue;
    const len = b - a, mid = (a + b) / 2;
    if (axis === 'x') wall(len, h, 0.2, mid, baseY + h / 2, fixed, color);
    else wall(0.2, h, len, fixed, baseY + h / 2, mid, color);
  }
}

// floor slab with optional rectangular holes
function floorSlab(y, color, holes = []) {
  const X0 = -8, X1 = 8, Z0 = -6, Z1 = 6;
  const xs = [X0, X1];
  for (const h of holes) { xs.push(h.minX, h.maxX); }
  xs.sort((a, b) => a - b);
  for (let i = 0; i < xs.length - 1; i++) {
    const xa = xs[i], xb = xs[i + 1];
    if (xb - xa < 0.01) continue;
    const cx = (xa + xb) / 2;
    const zs = [Z0, Z1];
    for (const h of holes) if (cx > h.minX && cx < h.maxX) zs.push(h.minZ, h.maxZ);
    zs.sort((a, b) => a - b);
    let inHole = false;
    for (let j = 0; j < zs.length - 1; j++) {
      const za = zs[j], zb = zs[j + 1];
      if (zb - za < 0.01) continue;
      const cz = (za + zb) / 2;
      inHole = holes.some(h => cx > h.minX && cx < h.maxX && cz > h.minZ && cz < h.maxZ);
      if (!inHole) box(xb - xa, 0.2, zb - za, color, cx, y - 0.1, cz);
    }
  }
}

function groundY(x, z, curY) {
  for (const s of STAIRS) {
    if (x >= s.minX && x <= s.maxX && z <= s.z0 && z >= s.z1) {
      const t = (s.z0 - z) / (s.z0 - s.z1);
      const y = s.y0 + (s.y1 - s.y0) * t;
      if (Math.abs(curY - y) < 1.9) return y;
    }
  }
  let best = 0, bd = 1e9;
  for (const f of LEVELS) { const d = Math.abs(curY - f); if (d < bd) { bd = d; best = f; } }
  return best;
}
function nearestLevel(y) {
  let best = 0, bd = 1e9;
  for (const f of LEVELS) { const d = Math.abs(y - f); if (d < bd) { bd = d; best = f; } }
  return best;
}

// ---------- build the house ----------
// exterior: grass ring around the house footprint
box(120, 0.2, 51.5, 0x7fae62, 0, -0.12, -32.15);   // north of house
box(120, 0.2, 51.5, 0x7fae62, 0, -0.12, 32.15);    // south
box(51.5, 0.2, 13.3, 0x7fae62, -34.25, -0.12, 0);  // west strip beside house
box(51.5, 0.2, 13.3, 0x7fae62, 34.25, -0.12, 0);   // east strip
for (let i = 0; i < 14; i++) {
  const a = (i / 14) * Math.PI * 2, r = 22 + (i % 4) * 5;
  const t = box(1.2, 3.2, 1.2, 0x5b8f4a, Math.cos(a) * r, 2.2, Math.sin(a) * r);
  box(0.5, 1.6, 0.5, 0x7a5a3a, t.position.x, 0.6, t.position.z);
}
// fence
for (const [w, d, x, z] of [[36, 0.3, 0, 15], [36, 0.3, 0, -15], [0.3, 30, 18, 0], [0.3, 30, -18, 0]])
  box(w, 1.1, d, 0xb09a7a, x, 0.55, z);

// roof ledge outside upstairs bedroom window (cat can end up "on the roof")
box(4, 0.25, 3, 0x8a6a4a, -10, 2.95, -4);

// floors
floorSlab(-3, 0x9a8f80);                                          // basement
floorSlab(0, 0xc2a678, [ { minX: -2.4, maxX: -0.45, minZ: -6, maxZ: -1.9 } ]); // main (open down-stairwell)
floorSlab(3, 0xb5936a, [ { minX: 0.7, maxX: 2.5, minZ: -5.1, maxZ: -1.9 } ]);  // upstairs (open up-stairwell)
box(16.6, 0.3, 12.6, 0x9a5d4a, 0, 3 + WALL_H + 0.15, 0);           // roof/ceiling above upstairs

// staircase: visible steps (walkable via groundY ramp math)
for (const s of STAIRS) {
  const cx = (s.minX + s.maxX) / 2, w = s.maxX - s.minX;
  const N = 12, runLen = Math.abs(s.z1 - s.z0);
  for (let i = 0; i < N; i++) {
    const t = (i + 0.5) / N;
    const z = s.z0 + (s.z1 - s.z0) * t;
    const y = s.y0 + (s.y1 - s.y0) * t;
    box(w, 0.26, runLen / N + 0.05, i % 2 ? 0x8a7a5f : 0x94826a, cx, y - 0.13, z);
  }
}
// stairwell core wall between the up and down runs — full wall for basement+main
// levels only; upstairs it's a slim railing so the landing doesn't feel boxed in
// (top stops just under the upstairs slab so the two faces never z-fight)
wall(0.7, 5.78, 3.3, 0.4, -0.11, -3.5, 0xcbbfa8);
// upstairs railings (thin, waist height)
wall(0.1, 0.95, 3.1, 0.72, 3.48, -3.45, 0xb9a077);   // west edge of stair opening
wall(1.8, 0.95, 0.1, 1.6, 3.48, -1.85, 0xb9a077);    // south edge of stair opening
// railing posts + top rails (visual)
for (const [px, pz] of [[0.72, -4.95], [0.72, -3.45], [0.72, -1.9], [1.25, -1.85], [2.4, -1.85]])
  box(0.09, 1.0, 0.09, 0x8a6a4a, px, 3.5, pz);
box(0.14, 0.06, 3.1, 0x8a6a4a, 0.72, 3.98, -3.45);
box(1.8, 0.06, 0.14, 0x8a6a4a, 1.6, 3.98, -1.85);
// railings around the main-floor opening (down run)
wall(0.12, 4.4, 4.1, -2.42, -0.9, -3.95, 0x9a8a6a);  // west side of down run (basement→main)
wall(0.12, 4.4, 3.3, -0.5, -0.85, -3.5, 0x9a8a6a);   // east side of down run
// ---- perimeter walls (per level), with window gaps ----
const winKitchenGap = [4.4, 5.6], winBedGap = [-4.6, -3.4];
// main level perimeter
wallRun('x', -6, -8, 8, 0, [winKitchenGap], 0xd8d2c4);
wallRun('x', 6, -8, 8, 0, [], 0xd8d2c4);
wallRun('z', -8, -6, 6, 0, [], 0xd8d2c4);
wallRun('z', 8, -6, 6, 0, [], 0xd8d2c4);
// window sills (block player, cat can hop over)
wall(1.2, 1.0, 0.2, 5.0, 0.5, -6);
wall(1.2, 0.6, 0.2, 5.0, WALL_H - 0.3, -6); // header
// upstairs perimeter
wallRun('x', -6, -8, 8, 3, [], 0xd8d2c4);
wallRun('x', 6, -8, 8, 3, [], 0xd8d2c4);
wallRun('z', -8, -6, 6, 3, [winBedGap], 0xd8d2c4);
wallRun('z', 8, -6, 6, 3, [], 0xd8d2c4);
wall(0.2, 1.0, 1.2, -8, 3.5, -4);
wall(0.2, 0.6, 1.2, -8, 3 + WALL_H - 0.3, -4);
// basement perimeter
wallRun('x', -6, -8, 8, -3, [], 0xa8a094);
wallRun('x', 6, -8, 8, -3, [], 0xa8a094);
wallRun('z', -8, -6, 6, -3, [], 0xa8a094);
wallRun('z', 8, -6, 6, -3, [], 0xa8a094);

// ---- interior walls ----
wallRun('z', -2.5, -6, 6, 0, [[-1.7, -0.5], [2.2, 3.5]], 0xe8e0d0);
wallRun('z', 2.5, -6, 6, 0, [[-1.7, -0.5], [2.2, 3.5]], 0xe8e0d0);
wallRun('x', 0, -8, -2.5, 0, [[-6.2, -5.0]], 0xe8e0d0);
wallRun('x', 0, 2.5, 8, 0, [[5.0, 6.2]], 0xe8e0d0);
wallRun('x', 3.6, -2.5, 2.5, 0, [[-0.6, 0.6]], 0xe8e0d0);   // main bathroom front wall
// upstairs
wallRun('z', -1, -6, 6, 3, [[-3.5, -2.2], [2.2, 3.5]], 0xe8e0d0);
wallRun('x', 0, -8, -1, 3, [], 0xe8e0d0);
wallRun('z', 2.5, -6, -1, 3, [[-1.9, -1.0]], 0xe8e0d0);      // closet
wallRun('x', -1, 2.5, 8, 3, [], 0xe8e0d0);
wallRun('z', 2.5, 2, 6, 3, [[3.4, 4.6]], 0xe8e0d0);          // upstairs bath
wallRun('x', 2, 2.5, 8, 3, [], 0xe8e0d0);
// basement: one divider
wallRun('x', 0, -8, 8, -3, [[-1.2, 1.2]], 0xb8b0a4);

// room name lookup
const ROOMS = [
  { name: 'the office',        lvl: 0,  minX: -8, maxX: -2.5, minZ: -6, maxZ: 0 },
  { name: 'the TV room',       lvl: 0,  minX: -8, maxX: -2.5, minZ: 0, maxZ: 6 },
  { name: 'the kitchen',       lvl: 0,  minX: 2.5, maxX: 8, minZ: -6, maxZ: 0 },
  { name: 'the dining room',   lvl: 0,  minX: 2.5, maxX: 8, minZ: 0, maxZ: 6 },
  { name: 'the main bathroom', lvl: 0,  minX: -2.5, maxX: 2.5, minZ: 3.6, maxZ: 6 },
  { name: 'the hallway',       lvl: 0,  minX: -2.5, maxX: 2.5, minZ: -6, maxZ: 3.6 },
  { name: 'the bedroom',       lvl: 3,  minX: -8, maxX: -1, minZ: -6, maxZ: 0 },
  { name: 'the guest bedroom', lvl: 3,  minX: -8, maxX: -1, minZ: 0, maxZ: 6 },
  { name: 'the closet',        lvl: 3,  minX: 2.5, maxX: 8, minZ: -6, maxZ: -1 },
  { name: 'the upstairs bathroom', lvl: 3, minX: 2.5, maxX: 8, minZ: 2, maxZ: 6 },
  { name: 'upstairs',          lvl: 3,  minX: -8, maxX: 8, minZ: -6, maxZ: 6 },
  { name: 'the laundry room',  lvl: -3, minX: -8, maxX: 8, minZ: -6, maxZ: 0 },
  { name: 'the basement den',  lvl: -3, minX: -8, maxX: 8, minZ: 0, maxZ: 6 },
];
function roomName(x, y, z) {
  const lvl = nearestLevel(y);
  for (const r of ROOMS) if (r.lvl === lvl && x >= r.minX && x <= r.maxX && z >= r.minZ && z <= r.maxZ) return r.name;
  return lvl === 3 ? 'upstairs' : lvl === -3 ? 'the basement' : 'somewhere';
}

// ============================================================
// FURNITURE + INTERACTABLES
// ============================================================
// hazard tiers gate the pacing: tier 1 = tutorial-ish, 2 = mid game, 3 = late game
const hazards = {};   // id -> hazard record
const distracts = {}; // id -> {pos, time, label}

function registerInteract(obj, data) {
  obj.userData = { ...obj.userData, ...data };
  if (obj.isGroup) {
    obj.traverse(o => {
      if (o.isMesh) { o.userData = { ...o.userData, ...data }; interactables.push(o); }
    });
  } else interactables.push(obj);
  return obj;
}

function addToggleHazard(id, mesh, opts) {
  const h = { id, type: 'toggle', mesh, tier: 2, everFixed: false, ...opts };
  h.curSurface = h.surface || null;   // where the hazard is reachable NOW (items can move)
  hazards[id] = h;
  registerInteract(mesh, { act: 'toggle', id });
  applyToggleVis(h);
  return h;
}
function applyToggleVis(h) {
  if (h.onVis) h.onVis(h.armed);
  else if (h.mesh.isMesh) h.mesh.material = mat(h.armed ? (h.armedColor ?? 0xcc4444) : (h.safeColor ?? 0x66aa66));
}
function addItemHazard(id, mesh, opts) {
  const h = { id, type: 'item', mesh, tier: 2, stashed: false, held: false,
              home: mesh.position.clone(), ...opts };
  h.curSurface = h.surface || null;   // tracks the surface the item currently sits on
  hazards[id] = h;
  registerInteract(mesh, { act: 'item', id });
  return h;
}
const containers = {}; // id -> {label, cap, used, mesh, owned, price, unlock, pending}
// shop = { price, unlock } makes the container a shop item: hidden until bought.
function addContainer(id, mesh, label, cap = 2, shop = null) {
  containers[id] = { id, label, cap, used: 0, mesh,
                     owned: !shop, price: shop ? shop.price : 0, unlock: shop ? (shop.unlock || 1) : 1,
                     pending: false };
  registerInteract(mesh, { act: 'container', id, label });
  if (shop) mesh.visible = false;
}
// shop = { price, unlock } makes the distraction a shop item: hidden until bought.
// surface = {x,z,h,ax,az}: the cat hops up onto a surface to use it (h above floor,
// ax/az = approach offset pointing into open room space).
function addDistraction(id, mesh, label, time, shop = null, anim = 'sit', surface = null) {
  const d = { id, pos: mesh.position.clone(), time, label, mesh, anim, surface,
              owned: !shop, price: shop ? shop.price : 0, unlock: shop ? (shop.unlock || 1) : 1,
              pending: false };
  distracts[id] = d;
  registerInteract(mesh, { act: 'distract', id, label });
  if (!d.owned) mesh.visible = false;
}

// ---- shared prop builders ----
function buildToilet(x, z, y) {
  const g = grp(x, y, z);
  cyl(0.26, 0.3, 0.36, 0xffffff, 0, 0.2, -0.08, g);         // bowl
  box(0.46, 0.55, 0.22, 0xf4f4f4, 0, 0.45, 0.26, g);        // tank
  box(0.3, 0.04, 0.08, 0xdddddd, 0, 0.75, 0.26, g);         // flush button
  const lid = box(0.48, 0.05, 0.5, 0xf8f8f8, 0, 0.4, -0.08, g);
  const water = cyl(0.2, 0.2, 0.03, 0x66bbee, 0, 0.39, -0.08, g);
  return { g, lid, water };
}
function toiletVis(t, armed) {
  t.water.visible = armed;
  if (armed) { t.lid.position.set(0, 0.62, 0.12); t.lid.rotation.x = Math.PI * 0.45; }
  else { t.lid.position.set(0, 0.4, -0.08); t.lid.rotation.x = 0; }
}
function buildPlant(x, y, z, leaf = 0x3a8a3a, tall = 0.5) {
  const g = grp(x, y, z);
  cyl(0.15, 0.11, 0.24, 0xb0603a, 0, 0.12, 0, g);           // terracotta pot
  cyl(0.03, 0.03, tall * 0.7, 0x5a7a3a, 0, 0.24 + tall * 0.3, 0, g);
  sph(0.22, leaf, 0, 0.3 + tall * 0.6, 0, g);
  sph(0.15, leaf, 0.13, 0.22 + tall * 0.6, 0.07, g);
  sph(0.14, leaf, -0.11, 0.27 + tall * 0.6, -0.09, g);
  return g;
}

// ---------- OFFICE (main, x -8..-2.5, z -6..0) ----------
const desk = box(2.2, 0.1, 1.0, 0x8a6a4a, -6.8, 0.85, -3);
box(0.15, 0.85, 0.9, 0x7a5a3a, -7.8, 0.42, -3); box(0.15, 0.85, 0.9, 0x7a5a3a, -5.8, 0.42, -3);
const monitor = grp(-6.9, 0.9, -3.35);
box(1.1, 0.7, 0.08, 0x222833, 0, 0.6, 0, monitor);          // screen bezel
cyl(0.05, 0.05, 0.24, 0x333a44, 0, 0.12, 0, monitor);       // stand
box(0.42, 0.04, 0.26, 0x333a44, 0, 0.02, 0, monitor);       // base
// the actual screen renders the typing minigame via a canvas texture
const scrCanvas = document.createElement('canvas');
scrCanvas.width = 512; scrCanvas.height = 320;
const scrCtx = scrCanvas.getContext('2d');
const scrTex = new THREE.CanvasTexture(scrCanvas);
scrTex.colorSpace = THREE.SRGBColorSpace;
const screenMesh = new THREE.Mesh(new THREE.PlaneGeometry(1.0, 0.62), new THREE.MeshBasicMaterial({ map: scrTex }));
screenMesh.position.set(0, 0.6, 0.05);
monitor.add(screenMesh);
registerInteract(monitor, { act: 'computer' });
const kb = grp(-6.8, 0.9, -2.85);
box(0.8, 0.05, 0.32, 0x333a44, 0, 0.03, 0, kb);
for (let i = 0; i < 3; i++) box(0.72, 0.02, 0.07, 0x8892a0, 0, 0.06, -0.1 + i * 0.1, kb); // key rows
registerInteract(kb, { act: 'computer' });
// office chair — seat with the backrest flush against its REAR edge, armrests, star base
const chair = grp(-6.8, 0, -2.2);
box(0.52, 0.08, 0.5, 0x444a55, 0, 0.52, 0, chair);                   // seat (rear edge z=0.25)
const chBack = box(0.5, 0.66, 0.09, 0x444a55, 0, 0.88, 0.3, chair);  // backrest, slight recline
chBack.rotation.x = 0.12;
for (const sx of [-0.3, 0.3]) {
  box(0.06, 0.22, 0.06, 0x333944, sx, 0.63, 0.1, chair);             // armrest posts
  box(0.09, 0.04, 0.34, 0x222222, sx, 0.76, 0.02, chair);            // arm pads
}
cyl(0.05, 0.05, 0.42, 0x222222, 0, 0.3, 0, chair);                   // gas lift
for (let i = 0; i < 5; i++) {                                        // 5-star base + casters
  const a = i * Math.PI * 2 / 5;
  const leg = box(0.34, 0.04, 0.06, 0x222222, Math.cos(a) * 0.17, 0.06, Math.sin(a) * 0.17, chair);
  leg.rotation.y = -a;
  sph(0.035, 0x111111, Math.cos(a) * 0.32, 0.035, Math.sin(a) * 0.32, chair);
}
// desk phone
const phoneMesh = grp(-5.95, 0.9, -3.3);
box(0.34, 0.09, 0.24, 0x1f8f1f, 0, 0.05, 0, phoneMesh);
box(0.3, 0.07, 0.09, 0x26b526, 0, 0.13, -0.06, phoneMesh);  // handset
box(0.16, 0.02, 0.1, 0x0a5a0a, 0.05, 0.1, 0.05, phoneMesh); // keypad
hitPad(phoneMesh, 0.3, 0, 0.1, 0);
registerInteract(phoneMesh, { act: 'phone' });
// bookshelf with books
const bookshelf = grp(-3.0, 0, -5.5);
box(1.4, 1.8, 0.4, 0x7a5a3a, 0, 0.9, 0, bookshelf);
const BOOKC = [0xaa4444, 0x4466aa, 0x44aa66, 0xccaa44, 0x8844aa, 0xcc6633];
for (let s = 0; s < 3; s++)
  for (let i = 0; i < 6; i++)
    box(0.13, 0.32 + (i % 3) * 0.03, 0.28, BOOKC[(s * 6 + i) % 6], -0.5 + i * 0.2, 0.42 + s * 0.55, 0.08, bookshelf);
// high wall shelf (shop item): cat-proof storage, mounted too high for any cat
const hiShelf = grp(-5.0, 2.1, -5.72);
box(1.5, 0.07, 0.42, 0x8a6a4a, 0, 0, 0, hiShelf);              // plank
box(0.06, 0.32, 0.34, 0x7a5a3a, -0.55, -0.2, 0.02, hiShelf);   // brackets
box(0.06, 0.32, 0.34, 0x7a5a3a, 0.55, -0.2, 0.02, hiShelf);
box(0.3, 0.24, 0.28, 0xaa8855, -0.4, 0.16, 0, hiShelf);        // a stored box
cyl(0.08, 0.08, 0.22, 0x8899aa, 0.35, 0.15, 0, hiShelf);       // jar
addContainer('hishelf', hiShelf, 'high office shelf', 3, { price: 50, unlock: 2 });
// round cat bed
const catBed = grp(-7.2, 0, -0.8);
cyl(0.45, 0.5, 0.18, 0x9a6aa0, 0, 0.09, 0, catBed);
cyl(0.34, 0.34, 0.09, 0xc9a9d0, 0, 0.17, 0, catBed);
addDistraction('bed', catBed, 'cat bed', 15, null, 'curl');

// ---------- KITCHEN (main, x 2.5..8, z -6..0) ----------
box(4.5, 0.9, 0.8, 0xe0e0e0, 5.6, 0.45, -5.4); // counter along window wall
box(0.7, 0.05, 0.5, 0xb8c4cc, 5.9, 0.92, -5.45); // sink basin
cyl(0.03, 0.03, 0.28, 0x99a4ac, 5.9, 1.05, -5.68); // faucet riser
box(0.2, 0.04, 0.05, 0x99a4ac, 5.83, 1.18, -5.68); // faucet spout
// fridge
const fridge = grp(7.5, 0, -5.4);
box(0.9, 1.8, 0.8, 0xd8d8d8, 0, 0.9, 0, fridge);
box(0.92, 0.03, 0.82, 0xb0b0b0, 0, 1.15, 0, fridge);        // freezer/fridge split
box(0.05, 0.35, 0.06, 0x8a8f94, -0.32, 1.42, 0.42, fridge); // handles
box(0.05, 0.6, 0.06, 0x8a8f94, -0.32, 0.72, 0.42, fridge);
// stove
const stove = grp(3.6, 0, -5.4);
box(0.9, 0.9, 0.7, 0xcfd4d8, 0, 0.45, 0, stove);
box(0.9, 0.05, 0.7, 0x333333, 0, 0.93, 0, stove);
const burners = [];
for (const [bx, bz] of [[-0.22, -0.16], [0.22, -0.16], [-0.22, 0.16], [0.22, 0.16]])
  burners.push(cyl(0.11, 0.11, 0.035, 0x222222, bx, 0.96, bz, stove));
for (let i = 0; i < 4; i++) {
  const k = cyl(0.035, 0.035, 0.05, 0xeeeeee, -0.3 + i * 0.2, 0.82, 0.37, stove);
  k.rotation.x = Math.PI / 2;
}
addToggleHazard('stove', stove, {
  name: 'stove burner', anim: 'sniffHigh', armed: false, rearm: true, tier: 2,
  fixHint: 'Turn off the stove', armHint: 'Stove is off',
  dangerText: 'The cat is sniffing the HOT STOVE!',
  armMsg: 'You left the stove on again...',
  onVis: a => burners.forEach(b => b.material = mat(a ? 0xff5522 : 0x222222)),
});
// knives on a cutting board
const knives = grp(4.6, 0.92, -5.4);
box(0.55, 0.03, 0.4, 0xc9a678, 0, 0.015, 0, knives); // cutting board
for (let i = 0; i < 3; i++) {
  box(0.32, 0.015, 0.05, 0xd8dde2, -0.08, 0.045, -0.12 + i * 0.12, knives); // blade
  box(0.15, 0.035, 0.045, 0x222222, 0.16, 0.05, -0.12 + i * 0.12, knives); // handle
}
hitPad(knives, 0.38, 0, 0.06, 0);
addItemHazard('knives', knives, { name: 'kitchen knives', anim: 'paw', label: 'kitchen knives', tier: 2, dangerText: 'The cat is batting the KNIVES around!',
  surface: { x: 4.6, z: -5.35, h: 0.9, ax: 0, az: 1.1 } });
// chocolate bar
const chocolate = grp(6.6, 0.9, -5.4);
box(0.3, 0.04, 0.16, 0x5a3a22, 0, 0.03, 0, chocolate);
for (let i = 0; i < 3; i++)
  for (let j = 0; j < 2; j++)
    box(0.07, 0.02, 0.055, 0x6b4630, -0.09 + i * 0.09, 0.06, -0.04 + j * 0.08, chocolate);
box(0.12, 0.06, 0.18, 0xcc3355, 0.18, 0.03, 0, chocolate); // wrapper end
hitPad(chocolate, 0.28, 0, 0.05, 0);
addItemHazard('chocolate', chocolate, { name: 'chocolate bar', anim: 'eat', label: 'chocolate bar', tier: 2, dangerText: 'The cat is licking the CHOCOLATE!',
  surface: { x: 6.6, z: -5.35, h: 0.9, ax: 0, az: 1.1 } });
const kplant = buildPlant(7.6, 0, -2.5);
hitPad(kplant, 0.42, 0, 0.35, 0);
addItemHazard('kplant', kplant, { name: 'houseplant', anim: 'eat', label: 'houseplant (toxic!)', tier: 2, dangerText: 'The cat is chewing the HOUSEPLANT!' });
// trash can with a flip lid
const trash = grp(3.0, 0, -0.6);
cyl(0.26, 0.21, 0.7, 0x778899, 0, 0.35, 0, trash);
const trashLid = cyl(0.29, 0.29, 0.05, 0x556677, 0, 0.73, 0, trash);
addToggleHazard('trash', trash, {
  name: 'trash can', anim: 'headIn', armed: false, rearm: true, tier: 2,
  fixHint: 'Close the trash lid', armHint: 'Trash lid closed',
  dangerText: 'The cat is headfirst in the TRASH eating chicken bones!',
  armMsg: 'The trash lid popped open.',
  onVis: a => {
    trashLid.rotation.z = a ? 1.0 : 0;
    trashLid.position.set(a ? 0.26 : 0, a ? 0.82 : 0.73, 0);
  },
});
// cupboard + drawer
const cupboard = grp(6.9, 0, -5.55);
box(1.2, 1.0, 0.5, 0x8a6a4a, 0, 2.0, 0, cupboard);
box(0.03, 0.96, 0.02, 0x6a4a2a, 0, 2.0, 0.26, cupboard);   // door split
box(0.04, 0.16, 0.05, 0xd9c9a0, -0.1, 2.0, 0.27, cupboard); // handles
box(0.04, 0.16, 0.05, 0xd9c9a0, 0.1, 2.0, 0.27, cupboard);
addContainer('cupboard', cupboard, 'kitchen cupboard', 2);
const drawer = grp(4.6, 0, -5.35);
box(1.0, 0.3, 0.6, 0x7a5a3a, 0, 0.6, 0, drawer);
box(0.3, 0.05, 0.05, 0xd9c9a0, 0, 0.6, 0.31, drawer); // handle
addContainer('drawer', drawer, 'kitchen drawer', 2);
// kitchen window frame
box(1.34, 0.07, 0.12, 0xf5f0e0, 5.0, 2.06, -6);
box(1.34, 0.07, 0.12, 0xf5f0e0, 5.0, 0.97, -6);
box(0.07, 1.16, 0.12, 0xf5f0e0, 4.42, 1.52, -6);
box(0.07, 1.16, 0.12, 0xf5f0e0, 5.58, 1.52, -6);
// kitchen window (escape hazard)
const winKitchen = new THREE.Mesh(new THREE.BoxGeometry(1.2, 1.0, 0.08), new THREE.MeshLambertMaterial({ color: 0xaaddff, transparent: true, opacity: 0.45 }));
winKitchen.position.set(5.0, 1.5, -6);
scene.add(winKitchen);
addToggleHazard('winKitchen', winKitchen, {
  name: 'kitchen window', anim: 'climb', armed: false, rearm: true, isWindow: true, tier: 2,
  outsidePos: new THREE.Vector3(5.0, 0, -8.0), outsideText: 'THE CAT GOT OUT THE KITCHEN WINDOW!',
  fixHint: 'Close the kitchen window', armHint: 'Window closed',
  dangerText: 'The cat is halfway out the KITCHEN WINDOW!',
  armMsg: 'The wind blew the kitchen window open!',
  onVis: a => { winKitchen.position.y = a ? 2.3 : 1.5; },
});
// food & water bowls
box(1.1, 0.02, 0.6, 0x5577aa, 3.5, 0.01, -4.6); // mat
const bowl = grp(3.2, 0, -4.6);
cyl(0.2, 0.14, 0.11, 0xd0d0e8, 0, 0.06, 0, bowl);
const bowlFood = cyl(0.15, 0.15, 0.06, 0x9a6a3a, 0, 0.11, 0, bowl); bowlFood.visible = false;
hitPad(bowl, 0.28, 0, 0.1, 0);
registerInteract(bowl, { act: 'bowl' });
const waterBowl = grp(3.8, 0, -4.6);
cyl(0.2, 0.14, 0.11, 0x88aadd, 0, 0.06, 0, waterBowl);
cyl(0.15, 0.15, 0.04, 0x3d6dc9, 0, 0.1, 0, waterBowl); // water
// treat jar on a side table
box(0.5, 0.8, 0.5, 0x8a6a4a, 7.5, 0.4, -0.4); // side table
const treats = grp(7.5, 0.8, -0.4);
cyl(0.13, 0.13, 0.32, 0xdd8833, 0, 0.16, 0, treats);
cyl(0.145, 0.145, 0.06, 0x8a5522, 0, 0.35, 0, treats); // lid
box(0.22, 0.14, 0.02, 0xfff2cc, 0, 0.17, 0.125, treats); // label
hitPad(treats, 0.3, 0, 0.18, 0);
addDistraction('treats', treats, 'treat jar (shake it)', 10, null, 'eat',
  { x: 7.5, z: -0.4, h: 0.8, ax: -1.0, az: 0 });   // cat eats ON the side table

// ---------- MAIN BATHROOM (hall end) ----------
const t1 = buildToilet(-1.6, 5.3, 0);
addToggleHazard('toilet1', t1.g, {
  name: 'toilet', anim: 'fish', armed: true, rearm: true, tier: 1,
  fixHint: 'Close the toilet lid', armHint: 'Lid closed',
  dangerText: 'The cat is fishing in the TOILET!',
  armMsg: 'Someone left the toilet lid up. It was you.',
  onVis: a => toiletVis(t1, a),
});
// pedestal sink + faucet (rotated so the faucet sits against the wall)
const sink1 = grp(0.8, 0, 5.5);
cyl(0.12, 0.16, 0.7, 0xe8e8e8, 0, 0.35, 0, sink1);
cyl(0.3, 0.22, 0.16, 0xffffff, 0, 0.78, 0, sink1);
cyl(0.025, 0.025, 0.2, 0x99a4ac, 0, 0.92, -0.18, sink1);
box(0.05, 0.03, 0.14, 0x99a4ac, 0, 1.0, -0.12, sink1);
sink1.rotation.y = Math.PI;
// pill bottle
const meds = grp(0.8, 0.86, 5.42);
cyl(0.06, 0.06, 0.18, 0xff8844, 0, 0.09, 0, meds);
cyl(0.065, 0.065, 0.05, 0xffffff, 0, 0.2, 0, meds);
box(0.1, 0.1, 0.005, 0xfff6ee, 0, 0.1, 0.06, meds); // label
hitPad(meds, 0.26, 0, 0.1, 0);
addItemHazard('meds', meds, { name: 'medicine bottle', anim: 'paw', label: 'medicine bottle', tier: 2, dangerText: 'The cat knocked over your MEDICINE!',
  surface: { x: 0.8, z: 5.4, h: 0.86, ax: 0, az: -1.2 } });
// medicine cabinet with mirror
const medCab = grp(0.8, 0, 5.85);
box(0.7, 0.5, 0.18, 0xcccccc, 0, 1.8, 0, medCab);
box(0.6, 0.4, 0.02, 0xbfe0ec, 0, 1.8, -0.1, medCab); // mirror face
box(0.04, 0.12, 0.04, 0x8a8f94, -0.26, 1.8, -0.11, medCab);
addContainer('medcab', medCab, 'medicine cabinet', 1);

// ---------- TV ROOM (main, x -8..-2.5, z 0..6) ----------
// couch
const couch = grp(-6.5, 0, 5.2);
box(2.4, 0.35, 1.0, 0x6a5acd, 0, 0.3, 0, couch);
box(2.4, 0.6, 0.25, 0x5a4abd, 0, 0.68, 0.38, couch);
box(0.25, 0.55, 1.0, 0x5a4abd, -1.08, 0.48, 0, couch);
box(0.25, 0.55, 1.0, 0x5a4abd, 1.08, 0.48, 0, couch);
box(1.0, 0.12, 0.8, 0x7a6add, -0.52, 0.42, -0.06, couch);
box(1.0, 0.12, 0.8, 0x7a6add, 0.52, 0.42, -0.06, couch);
// TV on a media console (shifted east so it no longer blocks the office doorway)
box(1.8, 0.4, 0.45, 0x7a5a3a, -3.9, 0.2, 0.35); // console
box(1.6, 1.0, 0.1, 0x1a1a22, -3.9, 1.0, 0.35);  // TV frame
box(1.5, 0.88, 0.02, 0x2a3a55, -3.9, 1.0, 0.41); // screen
// tangled TV cables + power strip
const cords = grp(-3.9, 0, 0.75);
for (let i = 0; i < 4; i++) {
  const c = box(0.5, 0.03, 0.03, 0x222222, -0.35 + i * 0.22, 0.03, (i % 2) * 0.14, cords);
  c.rotation.y = i * 0.8;
}
box(0.22, 0.08, 0.09, 0xf0f0f0, 0.4, 0.04, 0.05, cords); // power strip
hitPad(cords, 0.42, 0, 0.05, 0.05);
addToggleHazard('cords', cords, {
  name: 'TV cables', anim: 'tangle', armed: false, rearm: false, tier: 2,
  fixHint: 'Tuck away the TV cables', armHint: 'Cables tucked',
  dangerText: 'The cat is CHEWING THE TV CABLES!',
  onVis: a => { cords.visible = a; },
});
// coffee table
const ctab = grp(-4.6, 0, 3.0);
box(1.2, 0.06, 0.7, 0x8a6a4a, 0, 0.42, 0, ctab);
for (const [lx, lz] of [[-0.52, -0.28], [0.52, -0.28], [-0.52, 0.28], [0.52, 0.28]])
  box(0.07, 0.42, 0.07, 0x7a5a3a, lx, 0.21, lz, ctab);
// ribbon toy — a tier-1 starter hazard
const ribbon = grp(-4.4, 0.45, 3.1);
prim(new THREE.TorusKnotGeometry(0.11, 0.03, 48, 8), 0xff44aa, 0, 0.12, 0, ribbon);
hitPad(ribbon, 0.32, 0, 0.12, 0);
addItemHazard('ribbon', ribbon, { name: 'ribbon toy', anim: 'paw', label: 'ribbon toy (choking hazard)', tier: 1, dangerText: 'The cat is SWALLOWING THE RIBBON!' });
// laser pointer
const laserMesh = grp(-4.9, 0.45, 2.85);
const laserBody = cyl(0.035, 0.035, 0.26, 0x333333, 0, 0.05, 0, laserMesh);
laserBody.rotation.z = Math.PI / 2;
sph(0.032, 0xff2222, 0.13, 0.05, 0, laserMesh);        // emitter
box(0.04, 0.02, 0.035, 0xff2222, -0.04, 0.09, 0, laserMesh); // button
hitPad(laserMesh, 0.26, 0, 0.06, 0);
addItemHazard('laser', laserMesh, { name: 'laser pointer', label: 'laser pointer', tool: true, safeItem: true });
// window blinds + dangling pull cord with tassel
const blinds = grp(-7.85, 0, 4.0);
box(0.08, 1.4, 1.1, 0xf0e4c0, 0, 1.9, 0, blinds);
for (let i = 0; i < 5; i++) box(0.1, 0.02, 1.1, 0xe0d4b0, 0, 1.4 + i * 0.25, 0, blinds);
const blindCord = box(0.025, 1.2, 0.025, 0xeeddaa, 0.09, 1.4, 0.45, blinds);
const tassel = sph(0.05, 0xcc9944, 0.09, 0.78, 0.45, blinds);
hitPad(blinds, 0.4, 0.12, 1.05, 0.45);
addToggleHazard('blinds', blinds, {
  name: 'blind cord', anim: 'tangle', armed: false, rearm: true, tier: 2,
  fixHint: 'Tie up the blind cord', armHint: 'Cord tied up',
  dangerText: 'The cat is TANGLED IN THE BLIND CORD!',
  armMsg: 'The blind cord came loose again.',
  onVis: a => {
    blindCord.scale.y = a ? 1 : 0.35;
    blindCord.position.y = a ? 1.4 : 1.9;
    tassel.position.y = a ? 0.78 : 1.68;
  },
});
// birthday balloon on a string
const balloon = grp(-3.2, 0, 5.0);
sph(0.3, 0xff6688, 0, 1.95, 0, balloon);
const knot = cone(0.07, 0.12, 0xee5577, 0, 1.62, 0, balloon);
knot.rotation.z = Math.PI;
box(0.015, 1.5, 0.015, 0xdddddd, 0, 0.85, 0, balloon); // string
hitPad(balloon, 0.42, 0, 1.9, 0);
addToggleHazard('balloon', balloon, {
  name: 'birthday balloon', anim: 'pounce', armed: false, rearm: false, tier: 2,
  fixHint: 'Pop the balloon (sorry, balloon)', armHint: '',
  dangerText: 'The cat is attacking the BALLOON! If it pops in its face...',
  onVis: a => { balloon.visible = a; },
});
// fern
const tvplant = grp(-2.9, 0, 1.2);
cyl(0.16, 0.12, 0.26, 0x8a5a3a, 0, 0.13, 0, tvplant);
for (let i = 0; i < 5; i++) {
  const f = cone(0.055, 0.5, 0x2a7a2a, Math.cos(i * 1.26) * 0.12, 0.42, Math.sin(i * 1.26) * 0.12, tvplant);
  f.rotation.set(Math.sin(i * 1.26) * 0.6, 0, -Math.cos(i * 1.26) * 0.6);
}
hitPad(tvplant, 0.4, 0, 0.3, 0);
addItemHazard('tvplant', tvplant, { name: 'fern', anim: 'eat', label: 'fern (cats love to eat these)', tier: 2, dangerText: 'The cat is eating the FERN!' });
// toy chest
const toyChest = grp(-7.5, 0, 2.0);
box(1.0, 0.5, 0.6, 0xaa7744, 0, 0.25, 0, toyChest);
box(1.04, 0.12, 0.64, 0x8a5a30, 0, 0.56, 0, toyChest);
box(0.08, 0.1, 0.04, 0xddbb44, 0, 0.5, 0.32, toyChest); // latch
addContainer('chest', toyChest, 'toy chest', 3);
// cat tower
const tower = grp(-3.0, 0, 4.2);
box(0.7, 0.08, 0.7, 0xc2a678, 0, 0.04, 0, tower);
cyl(0.09, 0.09, 0.7, 0xb08a5a, 0, 0.43, 0, tower);
box(0.55, 0.07, 0.55, 0xc2a678, 0, 0.81, 0, tower);
cyl(0.08, 0.08, 0.58, 0xb08a5a, 0.14, 1.13, 0.14, tower);
box(0.5, 0.07, 0.5, 0x9a6aa0, 0.14, 1.45, 0.14, tower);
addDistraction('tower', tower, 'cat tower', 18, { price: 40, unlock: 1 }, 'sit');
// open cardboard box
const cardboard = grp(-5.5, 0, 1.5);
box(0.7, 0.45, 0.7, 0xb08a5a, 0, 0.23, 0, cardboard);
box(0.6, 0.02, 0.6, 0x3a2a18, 0, 0.44, 0, cardboard); // dark inside
for (let i = 0; i < 4; i++) {
  const f = box(0.6, 0.02, 0.22, 0xc09a6a, 0, 0.5, 0, cardboard);
  f.rotation.y = i * Math.PI / 2;
  f.translateZ(0.44);
  f.rotateX(-0.7);
}
addDistraction('boxx', cardboard, 'cardboard box (irresistible)', 12, null, 'curl');

// ---------- DINING (main, x 2.5..8, z 0..6) ----------
const dtable = grp(5.5, 0, 3.5);
box(2.0, 0.08, 1.2, 0x8a6a4a, 0, 0.78, 0, dtable);
for (const [lx, lz] of [[-0.9, -0.5], [0.9, -0.5], [-0.9, 0.5], [0.9, 0.5]])
  box(0.09, 0.78, 0.09, 0x7a5a3a, lx, 0.39, lz, dtable);
for (const dx of [-1.4, 1.4]) {
  const ch = grp(5.5 + dx, 0, 3.5);
  box(0.42, 0.06, 0.42, 0x9a7248, 0, 0.45, 0, ch);
  box(0.42, 0.55, 0.06, 0x9a7248, 0, 0.75, -0.18, ch);
  ch.rotation.y = dx < 0 ? Math.PI / 2 : -Math.PI / 2;
  for (const [lx, lz] of [[-0.17, -0.17], [0.17, -0.17], [-0.17, 0.17], [0.17, 0.17]])
    box(0.05, 0.45, 0.05, 0x7a5a3a, lx, 0.22, lz, ch);
}
// candle with a flame
const candle = grp(5.5, 0.82, 3.5);
cyl(0.05, 0.05, 0.26, 0xf4ead0, 0, 0.13, 0, candle);
cyl(0.09, 0.09, 0.03, 0xb8a888, 0, 0.015, 0, candle); // dish
const flame = cone(0.035, 0.11, 0xffaa22, 0, 0.32, 0, candle);
hitPad(candle, 0.28, 0, 0.18, 0);
addToggleHazard('candle', candle, {
  name: 'lit candle', anim: 'sniffHigh', armed: false, rearm: true, tier: 2,
  fixHint: 'Blow out the candle', armHint: 'Candle out',
  dangerText: 'The cat\'s TAIL IS OVER THE CANDLE FLAME!',
  armMsg: 'The scented candle is somehow lit again.',
  surface: { x: 5.15, z: 3.5, h: 0.82, ax: 0, az: 1.3 },
  onVis: a => { flame.visible = a; },
});
// lily bouquet
const lilies = grp(6.4, 0.82, 3.5);
cyl(0.09, 0.06, 0.3, 0x7799bb, 0, 0.15, 0, lilies);
for (let i = 0; i < 3; i++) {
  const a = i * 2.1;
  box(0.02, 0.28, 0.02, 0x5a8a4a, Math.cos(a) * 0.06, 0.4, Math.sin(a) * 0.06, lilies);
  const fl = cone(0.07, 0.13, 0xffffff, Math.cos(a) * 0.09, 0.56, Math.sin(a) * 0.09, lilies, 6);
  fl.rotation.set(Math.sin(a) * 0.4, 0, -Math.cos(a) * 0.4);
  sph(0.025, 0xffcc44, Math.cos(a) * 0.09, 0.6, Math.sin(a) * 0.09, lilies);
}
hitPad(lilies, 0.34, 0, 0.35, 0);
addItemHazard('lilies', lilies, { name: 'lily bouquet', anim: 'eat', label: 'lilies (VERY toxic to cats)', tier: 2, dangerText: 'The cat is nibbling the LILIES! Those are super toxic!',
  surface: { x: 6.05, z: 3.5, h: 0.82, ax: 0, az: 1.3 } });
// crumpled plastic bag
const plasticBag = grp(3.2, 0, 5.2);
box(0.4, 0.28, 0.3, 0xeeeeee, 0, 0.14, 0, plasticBag);
box(0.3, 0.2, 0.24, 0xf6f6f6, 0.1, 0.3, 0.04, plasticBag);
box(0.04, 0.18, 0.03, 0xe0e0e0, -0.12, 0.42, 0, plasticBag); // handle loops
box(0.04, 0.18, 0.03, 0xe0e0e0, 0.12, 0.42, 0, plasticBag);
hitPad(plasticBag, 0.34, 0, 0.2, 0);
addItemHazard('bag', plasticBag, { name: 'plastic bag', anim: 'headIn', label: 'plastic bag (suffocation hazard)', tier: 2, dangerText: 'The cat has its HEAD IN THE PLASTIC BAG!' });
// scratching post
const post = grp(1.8, 0, 1.0);
box(0.5, 0.06, 0.5, 0x8a6a4a, 0, 0.03, 0, post);
for (let i = 0; i < 6; i++) cyl(0.09, 0.09, 0.16, i % 2 ? 0xc9b28a : 0xb9a077, 0, 0.14 + i * 0.16, 0, post);
box(0.34, 0.06, 0.34, 0x8a6a4a, 0, 1.1, 0, post);
addDistraction('post', post, 'scratching post', 12, { price: 25, unlock: 1 }, 'scratch');

// ---------- UPSTAIRS: BEDROOM (x -8..-1, z -6..0) ----------
const bed = grp(-6.5, 3, -4.9);
bed.rotation.y = Math.PI / 2;   // headboard + pillows against the north wall
box(2.0, 0.25, 1.6, 0x7a5a3a, 0, 0.13, 0, bed);
box(1.9, 0.2, 1.5, 0xf0f0f0, 0, 0.35, 0, bed);
box(1.3, 0.1, 1.52, 0x88aacc, -0.32, 0.46, 0, bed);  // blanket
box(0.4, 0.12, 0.55, 0xffffff, 0.65, 0.5, -0.35, bed); // pillows
box(0.4, 0.12, 0.55, 0xffffff, 0.65, 0.5, 0.35, bed);
box(0.12, 0.9, 1.6, 0x6a4a2a, 0.95, 0.45, 0, bed);   // headboard
registerInteract(bed, { act: 'bed' });               // sleep here at the end of the day
// nightstand with a little lamp
const nstand = grp(-5.2, 3, -5.5);
box(0.6, 0.6, 0.5, 0x7a5a3a, 0, 0.3, 0, nstand);
cyl(0.03, 0.06, 0.2, 0x555555, -0.15, 0.7, 0, nstand);
cone(0.12, 0.15, 0xffe9a8, -0.15, 0.85, 0, nstand);   // lampshade
// hair ties: little colorful rings
const bands = grp(-5.2, 3.6, -5.35);
const BANDC = [0xcc44cc, 0x44cccc, 0xcccc44];
for (let i = 0; i < 3; i++) {
  const r = prim(new THREE.TorusGeometry(0.05, 0.018, 6, 12), BANDC[i], -0.08 + i * 0.08, 0.02, (i % 2) * 0.06, bands);
  r.rotation.x = Math.PI / 2;
}
hitPad(bands, 0.3, 0, 0.03, 0);
addItemHazard('bands', bands, { name: 'hair ties', anim: 'paw', label: 'hair ties (cats swallow these)', tier: 3, dangerText: 'The cat is SWALLOWING YOUR HAIR TIES!',
  surface: { x: -5.2, z: -5.4, h: 0.6, ax: 0, az: 1.1 } });
const winBed = new THREE.Mesh(new THREE.BoxGeometry(0.08, 1.0, 1.2), new THREE.MeshLambertMaterial({ color: 0xaaddff, transparent: true, opacity: 0.45 }));
winBed.position.set(-8, 4.5, -4);
scene.add(winBed);
addToggleHazard('winBed', winBed, {
  name: 'bedroom window', anim: 'climb', armed: false, rearm: true, isWindow: true, tier: 3,
  outsidePos: new THREE.Vector3(-10, 3.1, -4), outsideText: 'THE CAT IS OUT ON THE ROOF!',
  fixHint: 'Close the bedroom window', armHint: 'Window closed',
  dangerText: 'The cat is climbing out the BEDROOM WINDOW onto the roof!',
  armMsg: 'The bedroom window blew open!',
  onVis: a => { winBed.position.y = a ? 5.3 : 4.5; },
});
// bedroom window frame
box(0.12, 0.07, 1.34, 0xf5f0e0, -8, 5.06, -4);
box(0.12, 0.07, 1.34, 0xf5f0e0, -8, 3.97, -4);
box(0.12, 1.16, 0.07, 0xf5f0e0, -8, 4.52, -4.58);
box(0.12, 1.16, 0.07, 0xf5f0e0, -8, 4.52, -3.42);
// window perch
const perch = grp(-7.6, 3, -3.2);
box(0.7, 0.1, 0.55, 0x9a6aa0, -0.05, 0.72, 0, perch);
box(0.6, 0.06, 0.45, 0xc9a9d0, -0.05, 0.8, 0, perch); // cushion
box(0.06, 0.35, 0.06, 0x7a5a3a, -0.3, 0.5, -0.18, perch);
box(0.06, 0.35, 0.06, 0x7a5a3a, -0.3, 0.5, 0.18, perch);
addDistraction('perch', perch, 'window perch (bird watching)', 22, { price: 35, unlock: 2 }, 'watch');

// ---------- UPSTAIRS: GUEST BEDROOM (x -8..-1, z 0..6) ----------
const gbed = grp(-6.5, 3, 5.0);
gbed.rotation.y = -Math.PI / 2;  // pillow end against the south wall
box(1.8, 0.22, 1.5, 0x7a5a3a, 0, 0.11, 0, gbed);
box(1.7, 0.18, 1.4, 0xf0f0f0, 0, 0.3, 0, gbed);
box(1.2, 0.09, 1.42, 0xaa88cc, -0.25, 0.4, 0, gbed);
box(0.4, 0.12, 0.5, 0xffffff, 0.6, 0.44, 0, gbed);
// sewing kit
const sewing = grp(-3.0, 3.22, 5.0);
box(0.34, 0.09, 0.26, 0xdd4444, 0, 0.05, 0, sewing);
sph(0.07, 0xee6666, -0.07, 0.13, 0, sewing);          // pincushion
for (let i = 0; i < 3; i++) box(0.008, 0.09, 0.008, 0xd8dde2, -0.1 + i * 0.035, 0.21, 0.01 * i, sewing); // pins
cyl(0.035, 0.035, 0.07, 0x4466cc, 0.09, 0.13, 0.04, sewing);
cyl(0.045, 0.045, 0.01, 0xd9c9a0, 0.09, 0.17, 0.04, sewing);
hitPad(sewing, 0.3, 0, 0.1, 0);
addItemHazard('sewing', sewing, { name: 'sewing kit', anim: 'paw', label: 'sewing kit (needles + thread!)', tier: 3, dangerText: 'The cat found the SEWING NEEDLES!' });
const gplant = buildPlant(-1.8, 3, 1.0, 0x2f9a4f, 0.75);
hitPad(gplant, 0.42, 0, 0.4, 0);
addItemHazard('gplant', gplant, { name: 'monstera', anim: 'eat', label: 'monstera (toxic to cats)', tier: 3, dangerText: 'The cat is destroying (and eating) the MONSTERA!' });

// ---------- UPSTAIRS: BATHROOM (x 2.5..8, z 2..6) ----------
const tub = grp(6.5, 3, 5.2);
box(1.6, 0.5, 0.9, 0xffffff, 0, 0.3, 0, tub);
box(1.7, 0.08, 1.0, 0xf0f0f0, 0, 0.56, 0, tub);      // rim
const tubWater = box(1.4, 0.05, 0.7, 0x66aadd, 0, 0.53, 0, tub);
cyl(0.035, 0.035, 0.35, 0x99a4ac, 0.7, 0.75, 0, tub); // faucet riser
box(0.2, 0.05, 0.06, 0x99a4ac, 0.6, 0.92, 0, tub);
for (const [fx, fz] of [[-0.7, -0.35], [0.7, -0.35], [-0.7, 0.35], [0.7, 0.35]])
  sph(0.07, 0xd0d0d0, fx, 0.05, fz, tub);            // feet
addToggleHazard('tub', tub, {
  name: 'guest bathtub', anim: 'fish', armed: false, rearm: false, tier: 3,
  fixHint: 'Drain the bathtub', armHint: 'Tub drained',
  dangerText: 'The cat fell in the FULL BATHTUB!',
  onVis: a => { tubWater.visible = a; },
});
const t2 = buildToilet(3.4, 5.3, 3);
addToggleHazard('toilet2', t2.g, {
  name: 'upstairs toilet', anim: 'fish', armed: false, rearm: true, tier: 3,
  fixHint: 'Close the toilet lid', armHint: 'Lid closed',
  dangerText: 'The cat is drinking from the UPSTAIRS TOILET!',
  armMsg: 'The upstairs toilet lid is up again.',
  onVis: a => toiletVis(t2, a),
});

// ---------- UPSTAIRS: CLOSET (x 2.5..8, z -6..-1) ----------
const duct = grp(7.9, 3.15, -3.5);
box(0.06, 0.5, 0.62, 0x111111, 0.02, 0.3, 0, duct);   // dark duct hole
const grate = grp(0, 0.3, 0, duct);
box(0.04, 0.55, 0.68, 0x999999, -0.04, 0, 0, grate);  // frame
for (let i = 0; i < 4; i++) box(0.05, 0.06, 0.6, 0x777777, -0.05, -0.18 + i * 0.12, 0, grate);
for (const [sy, sz] of [[-0.24, -0.3], [-0.24, 0.3], [0.24, -0.3], [0.24, 0.3]])
  sph(0.02, 0xffcc00, -0.07, sy, sz, grate);          // screw heads
addToggleHazard('duct', duct, {
  name: 'air duct vent', anim: 'headIn', armed: false, rearm: false, needTool: 'screwdriver', tier: 3,
  fixHint: 'Screw the vent shut', armHint: 'Vent secured',
  needToolHint: 'Loose air vent — you need a SCREWDRIVER (try the basement workbench)',
  dangerText: 'The cat crawled INTO THE AIR DUCT!',
  onVis: a => {
    grate.rotation.z = a ? -0.55 : 0;
    grate.position.set(a ? -0.14 : 0, a ? 0.24 : 0.3, 0);
  },
});
// ironing board + iron
const iboard = grp(4.0, 3, -5.3);
box(1.2, 0.06, 0.4, 0xcfd8dd, 0, 0.72, 0, iboard);
const bl1 = box(0.05, 0.75, 0.05, 0x8a8f94, -0.2, 0.36, 0, iboard); bl1.rotation.z = 0.4;
const bl2 = box(0.05, 0.75, 0.05, 0x8a8f94, 0.2, 0.36, 0, iboard); bl2.rotation.z = -0.4;
const iron = grp(4.0, 3.75, -5.3);
const sole = box(0.3, 0.03, 0.16, 0xb8c0c8, 0, 0.015, 0, iron);
box(0.26, 0.1, 0.13, 0x4477aa, 0, 0.08, 0, iron);
box(0.16, 0.05, 0.06, 0x335588, 0, 0.17, 0, iron);   // handle
const ironLight = sph(0.025, 0xff3300, 0.12, 0.1, 0, iron);
hitPad(iron, 0.3, 0, 0.08, 0);
addToggleHazard('iron', iron, {
  name: 'hot iron', anim: 'paw', armed: false, rearm: false, tier: 3,
  fixHint: 'Unplug the iron', armHint: 'Iron unplugged',
  dangerText: 'The cat is about to knock the HOT IRON onto itself!',
  surface: { x: 4.4, z: -5.3, h: 0.75, ax: 0, az: 1.2 },
  onVis: a => {
    ironLight.visible = a;
    sole.material = mat(a ? 0xff7744 : 0xb8c0c8);
  },
});
// mothballs
const mothballs = grp(6.5, 3, -5.3);
box(0.2, 0.18, 0.14, 0xd9c9a0, 0, 0.09, 0, mothballs); // bag
for (let i = 0; i < 5; i++)
  sph(0.035, 0xf0f0f0, -0.12 + (i % 3) * 0.11, 0.035, 0.12 + Math.floor(i / 3) * 0.09, mothballs);
hitPad(mothballs, 0.3, 0, 0.08, 0.06);
addItemHazard('mothballs', mothballs, { name: 'mothballs', anim: 'eat', label: 'mothballs (toxic)', tier: 3, dangerText: 'The cat is licking the MOTHBALLS!' });
// high shelf
const shelf = grp(6.5, 4.55, -5.6);
box(1.4, 0.08, 0.45, 0x8a6a4a, 0, 0.25, 0, shelf);
box(0.06, 0.25, 0.3, 0x7a5a3a, -0.5, 0.1, 0.05, shelf);
box(0.06, 0.25, 0.3, 0x7a5a3a, 0.5, 0.1, 0.05, shelf);
box(0.3, 0.25, 0.3, 0xaa8855, -0.4, 0.42, 0, shelf); // a stored box
addContainer('shelf', shelf, 'high closet shelf', 2);

// ---------- BASEMENT: LAUNDRY (z < 0) ----------
const dryer = grp(-6.5, -3, -5.3);
box(0.9, 0.95, 0.8, 0xe8e8e8, 0, 0.48, 0, dryer);
box(0.8, 0.14, 0.06, 0x9aa4ac, 0, 0.88, 0.4, dryer);  // control panel
const dKnob = cyl(0.05, 0.05, 0.05, 0x445566, 0.25, 0.88, 0.44, dryer);
dKnob.rotation.x = Math.PI / 2;
const dHole = cyl(0.26, 0.26, 0.04, 0x111111, 0, 0.45, 0.4, dryer);
dHole.rotation.x = Math.PI / 2;
const dDoor = cyl(0.29, 0.29, 0.05, 0xc8d4dc, 0, 0.45, 0.42, dryer);
dDoor.rotation.x = Math.PI / 2;
addToggleHazard('dryer', dryer, {
  name: 'dryer', anim: 'headIn', armed: false, rearm: true, tier: 3,
  fixHint: 'Close the dryer door', armHint: 'Dryer closed',
  dangerText: 'The cat climbed INTO THE DRYER!',
  armMsg: 'You left the dryer open with warm towels inside. Cat magnet.',
  onVis: a => {
    dHole.visible = a;
    if (a) { dDoor.position.set(0.48, 0.45, 0.6); dDoor.rotation.set(Math.PI / 2, 0, 0.9); }
    else { dDoor.position.set(0, 0.45, 0.42); dDoor.rotation.set(Math.PI / 2, 0, 0); }
  },
});
// washer (closed, blue porthole)
const washer = grp(-5.4, -3, -5.3);
box(0.9, 0.95, 0.8, 0xd8d8e8, 0, 0.48, 0, washer);
const wDoor = cyl(0.26, 0.26, 0.05, 0x6688bb, 0, 0.45, 0.41, washer);
wDoor.rotation.x = Math.PI / 2;
box(0.8, 0.14, 0.06, 0x9aa4ac, 0, 0.88, 0.4, washer);
// detergent pods
const pods = grp(-4.4, -3, -5.3);
cyl(0.16, 0.14, 0.26, 0xff8822, 0, 0.13, 0, pods);
cyl(0.17, 0.17, 0.04, 0xdd6600, 0, 0.28, 0, pods);   // lid ajar
sph(0.05, 0x44ddaa, 0.2, 0.05, 0.08, pods);
sph(0.05, 0x4488ee, 0.28, 0.05, -0.04, pods);
sph(0.05, 0xffcc44, 0.22, 0.05, -0.14, pods);
hitPad(pods, 0.34, 0.08, 0.12, 0);
addItemHazard('pods', pods, { name: 'detergent pods', anim: 'eat', label: 'detergent pods (look like candy!)', tier: 3, dangerText: 'The cat is biting a DETERGENT POD!' });
// workbench with pegboard + tools
box(2.0, 0.9, 0.7, 0x7a5a3a, 5.5, -2.55, -5.4);       // bench
box(1.8, 1.0, 0.06, 0x9a7a4a, 5.5, -1.5, -5.85);      // pegboard
box(0.06, 0.3, 0.06, 0x8a4a2a, 5.0, -1.4, -5.8);      // hammer handle (decor)
box(0.2, 0.1, 0.08, 0x666666, 5.0, -1.22, -5.8);      // hammer head
box(0.05, 0.35, 0.03, 0x888888, 6.0, -1.35, -5.8);    // wrench (decor)
// the screwdriver
box(0.5, 0.02, 0.3, 0xcc3333, 5.5, -2.09, -5.35);     // "important tool" mat
const screwdriver = grp(5.5, -2.08, -5.35);
const sdHandle = cyl(0.05, 0.05, 0.18, 0xffcc00, -0.11, 0.05, 0, screwdriver);
sdHandle.rotation.z = Math.PI / 2;
const sdShaft = cyl(0.018, 0.018, 0.26, 0xc8d0d8, 0.11, 0.05, 0, screwdriver);
sdShaft.rotation.z = Math.PI / 2;
box(0.04, 0.012, 0.03, 0xc8d0d8, 0.24, 0.05, 0, screwdriver); // flat tip
hitPad(screwdriver, 0.3, 0, 0.05, 0);
addItemHazard('screwdriver', screwdriver, { name: 'screwdriver', label: 'screwdriver', tool: true, safeItem: true });
// mousetrap
const trap = grp(2.0, -3, -3.0);
box(0.3, 0.03, 0.5, 0xb08a5a, 0, 0.015, 0, trap);
const trapBar = box(0.26, 0.02, 0.03, 0x999999, 0, 0.05, -0.18, trap);
box(0.06, 0.05, 0.06, 0xffd744, 0, 0.055, 0.1, trap); // cheese
hitPad(trap, 0.3, 0, 0.08, 0);
addToggleHazard('trap', trap, {
  name: 'mousetrap', anim: 'paw', armed: false, rearm: false, tier: 3,
  fixHint: 'Disarm the mousetrap', armHint: 'Trap disarmed',
  dangerText: 'The cat is pawing at the MOUSETRAP!',
  onVis: a => { trapBar.position.z = a ? -0.18 : 0.1; },
});
// dangling string lights
const lights = grp(-2.0, -3, -5.85);
box(1.5, 0.03, 0.03, 0x333333, 0, 2.4, 0, lights);
const BULBC = [0xff5555, 0x55cc55, 0x5588ff, 0xffee88];
const bulbs = [];
for (let i = 0; i < 6; i++) bulbs.push(sph(0.045, BULBC[i % 4], -0.62 + i * 0.25, 2.32, 0, lights));
hitPad(lights, 0.55, 0, 2.32, 0);
addToggleHazard('lights', lights, {
  name: 'string lights cord', anim: 'tangle', armed: false, rearm: false, tier: 3,
  fixHint: 'Unplug the dangling string lights', armHint: 'Lights unplugged',
  dangerText: 'The cat is chewing the STRING LIGHTS. While plugged in.',
  onVis: a => bulbs.forEach((b, i) => b.material = mat(a ? BULBC[i % 4] : 0x555544)),
});
// basement storage shelf
const bshelf = grp(7.4, -3, -3.0);
box(1.6, 0.06, 0.5, 0x8a6a4a, 0, 1.0, 0, bshelf);
box(1.6, 0.06, 0.5, 0x8a6a4a, 0, 1.6, 0, bshelf);
box(0.06, 1.7, 0.5, 0x7a5a3a, -0.77, 0.85, 0, bshelf);
box(0.06, 1.7, 0.5, 0x7a5a3a, 0.77, 0.85, 0, bshelf);
cyl(0.09, 0.09, 0.25, 0x8899aa, -0.4, 1.16, 0, bshelf); // jars (decor)
cyl(0.09, 0.09, 0.25, 0xaa8899, -0.15, 1.16, 0, bshelf);
addContainer('bshelf', bshelf, 'basement shelf', 2);

// ---------- BASEMENT: DEN (z > 0) ----------
const fireplace = grp(0, -3, 5.7);
box(1.8, 1.6, 0.5, 0x883322, 0, 0.8, 0, fireplace);
box(2.0, 0.12, 0.65, 0x6a4a3a, 0, 1.64, -0.05, fireplace); // mantel
box(1.0, 0.9, 0.1, 0x111111, 0, 0.55, -0.22, fireplace);   // firebox (faces the room)
const fpGlass = new THREE.Mesh(
  new THREE.BoxGeometry(1.0, 0.9, 0.04),
  new THREE.MeshLambertMaterial({ color: 0xaaccdd, transparent: true, opacity: 0.35 })
);
fpGlass.position.set(0, 0.55, -0.29);
fireplace.add(fpGlass);
const flames = grp(0, 0.2, -0.24, fireplace);
cone(0.12, 0.4, 0xff6622, 0, 0.2, 0, flames);
cone(0.08, 0.3, 0xffaa22, -0.18, 0.15, 0, flames);
cone(0.08, 0.32, 0xffaa22, 0.18, 0.16, 0, flames);
addToggleHazard('fireplace', fireplace, {
  name: 'fireplace', anim: 'curl', armed: false, rearm: true, tier: 3,
  fixHint: 'Close the fireplace door', armHint: 'Fireplace door closed',
  dangerText: 'The cat turned on the FIREPLACE and is sitting IN it!',
  armMsg: 'The cat figured out the fireplace switch. Again.',
  onVis: a => {
    flames.visible = a;
    fpGlass.position.x = a ? 0.7 : 0;
  },
});
// old basement couch
const bcouch = grp(-4.0, -3, 4.5);
box(2.2, 0.32, 0.9, 0x8a4a6a, 0, 0.28, 0, bcouch);
box(2.2, 0.5, 0.22, 0x7a3a5a, 0, 0.6, 0.34, bcouch);
box(0.22, 0.45, 0.9, 0x7a3a5a, -1.0, 0.42, 0, bcouch);
box(0.22, 0.45, 0.9, 0x7a3a5a, 1.0, 0.42, 0, bcouch);
// catnip mouse
const catnip = grp(3.5, -3, 3.0);
const mouseBody = sph(0.09, 0x777788, 0, 0.07, 0, catnip);
mouseBody.scale.set(1.4, 0.9, 1);
sph(0.055, 0x777788, 0.14, 0.08, 0, catnip); // head
cone(0.025, 0.05, 0xffaacc, 0.16, 0.14, -0.03, catnip);
cone(0.025, 0.05, 0xffaacc, 0.16, 0.14, 0.03, catnip);
const mtail = box(0.16, 0.015, 0.015, 0xffaacc, -0.18, 0.06, 0, catnip);
mtail.rotation.y = 0.5;
for (let i = 0; i < 4; i++) sph(0.02, 0x55cc55, -0.1 + i * 0.08, 0.01, 0.12 - (i % 2) * 0.24, catnip);
hitPad(catnip, 0.3, 0, 0.08, 0);
addDistraction('catnip', catnip, 'catnip mouse', 20, { price: 30, unlock: 2 }, 'roll');

// ---------- CAT CARRIER (intro prop, in the hallway) ----------
const carrier = grp(-0.6, 0, 1.4);
box(0.62, 0.06, 0.44, 0xd9cfc0, 0, 0.03, 0, carrier);                 // base
box(0.62, 0.34, 0.44, 0xc7b8a4, 0, 0.25, 0, carrier);                 // shell
box(0.56, 0.16, 0.38, 0xb5a48e, 0, 0.48, 0, carrier);                 // top
box(0.26, 0.06, 0.08, 0x8a7a64, 0, 0.58, 0, carrier);                 // handle
for (const sx of [-0.28, 0.28]) box(0.04, 0.22, 0.3, 0x9a8a74, sx, 0.28, 0, carrier); // side vents
const carrierDoor = grp(-0.2, 0.26, 0.225, carrier);                   // hinge at left edge
box(0.38, 0.3, 0.02, 0xaab4bc, 0.19, 0, 0, carrierDoor);              // wire door
for (let i = 0; i < 3; i++) box(0.02, 0.28, 0.03, 0x8a949c, 0.08 + i * 0.1, 0, 0.01, carrierDoor);
hitPad(carrier, 0.55, 0, 0.3, 0);
registerInteract(carrier, { act: 'carrier' });

// ---------- SHOP-ONLY DISTRACTIONS (hidden until purchased) ----------
// robotic mouse — scoots around the hallway
const roboMouse = grp(1.4, 0, 2.7);
cyl(0.14, 0.16, 0.07, 0xdddddd, 0, 0.04, 0, roboMouse);
sph(0.07, 0xff4444, 0, 0.11, 0, roboMouse);
box(0.16, 0.015, 0.015, 0x333333, -0.17, 0.07, 0, roboMouse); // antenna tail
hitPad(roboMouse, 0.3, 0, 0.08, 0);
addDistraction('robo', roboMouse, 'robotic mouse', 30, { price: 45, unlock: 3 }, 'pounce');
// cat TV — a tablet on a stand in the TV room, bird channel 24/7
const catTV = grp(-6.9, 0, 2.4);
box(0.3, 0.4, 0.22, 0x8a6a4a, 0, 0.2, 0, catTV);          // little stand
box(0.52, 0.36, 0.05, 0x222222, 0, 0.58, 0.02, catTV);    // tablet
box(0.46, 0.3, 0.02, 0x55aa77, 0, 0.58, 0.055, catTV);    // "bird video"
sph(0.05, 0xcc5533, 0.08, 0.61, 0.075, catTV);            // the bird
hitPad(catTV, 0.36, 0, 0.5, 0);
addDistraction('cattv', catTV, 'cat TV (bird channel)', 40, { price: 60, unlock: 4 }, 'watch');
// deluxe cat condo — guest bedroom
const condo = grp(-4.6, 3, 2.0);
box(0.9, 0.1, 0.9, 0xc2a678, 0, 0.05, 0, condo);
box(0.5, 0.5, 0.5, 0x9a6aa0, -0.15, 0.35, 0.1, condo);    // cubby
box(0.24, 0.28, 0.02, 0x111111, -0.15, 0.32, 0.36, condo);// cubby door hole
cyl(0.1, 0.1, 0.8, 0xb08a5a, 0.3, 0.5, -0.25, condo);
box(0.55, 0.08, 0.55, 0xc2a678, 0.2, 0.94, -0.2, condo);
cyl(0.1, 0.1, 0.6, 0xb08a5a, -0.2, 1.28, 0.15, condo);
box(0.5, 0.08, 0.5, 0x9a6aa0, -0.15, 1.62, 0.1, condo);
hitPad(condo, 0.6, 0, 0.7, 0);
addDistraction('condo', condo, 'deluxe cat condo', 60, { price: 100, unlock: 5 }, 'curl');

// ---------- DAILY TRAPS (scattered to random spots each morning) ----------
// a pool of small, irresistible, terrible things. every day 3-6 of them turn up
// at random walkable spots across ALL floors, so the cats always have somewhere
// new to get in trouble — basement included.
function dailyTrap(id, label, anim, dangerText, build) {
  const g = grp(0, 0, 0);
  build(g);
  hitPad(g, 0.32, 0, 0.1, 0);
  const h = addItemHazard(id, g, { name: label.split(' (')[0], anim, label, tier: 1, dangerText, daily: true });
  h.stashed = true;         // inert until daySetup deals it out
  g.visible = false;
  return h;
}
dailyTrap('bandball', 'rubber band ball (cats swallow these)', 'paw',
  'The cat is unraveling the RUBBER BAND BALL!', g => {
    sph(0.09, 0xcc5544, 0, 0.08, 0, g);
    box(0.02, 0.14, 0.02, 0x5577cc, 0.09, 0.05, 0.04, g);
    box(0.02, 0.12, 0.02, 0xcccc55, -0.08, 0.04, -0.05, g);
  });
dailyTrap('tinsel', 'tinsel strand (deadly if eaten)', 'eat',
  'The cat is EATING THE TINSEL!', g => {
    for (let i = 0; i < 5; i++) {
      const t = box(0.14, 0.015, 0.03, i % 2 ? 0xd8e8f8 : 0xaac8e8, -0.2 + i * 0.1, 0.02, (i % 2) * 0.08 - 0.04, g);
      t.rotation.y = i * 0.7;
    }
  });
dailyTrap('pill', 'dropped pill (very toxic)', 'eat',
  'The cat is licking the DROPPED PILL!', g => {
    const p = cyl(0.03, 0.03, 0.07, 0xee8899, 0, 0.03, 0, g);
    p.rotation.z = Math.PI / 2;
    cyl(0.028, 0.028, 0.03, 0xffffff, 0.02, 0.03, 0, g);
  });
dailyTrap('charger', 'phone charger cable', 'tangle',
  'The cat is CHEWING THE CHARGER CABLE!', g => {
    for (let i = 0; i < 4; i++) {
      const cbl = box(0.22, 0.02, 0.02, 0xf0f0f0, -0.15 + i * 0.1, 0.02, Math.sin(i * 2) * 0.08, g);
      cbl.rotation.y = i * 1.1;
    }
    box(0.07, 0.03, 0.05, 0xdddddd, 0.25, 0.02, 0, g);   // the plug end
  });
dailyTrap('twistties', 'twist ties (choking hazard)', 'paw',
  'The cat is batting the TWIST TIES everywhere!', g => {
    for (let i = 0; i < 3; i++) {
      const t = box(0.1, 0.012, 0.012, [0xcc4444, 0x44aa44, 0xeeeeee][i], -0.06 + i * 0.06, 0.015, (i % 2) * 0.06 - 0.03, g);
      t.rotation.y = i * 1.3;
    }
  });
dailyTrap('floss', 'floss pick (string + plastic)', 'eat',
  'The cat is swallowing the FLOSS PICK!', g => {
    box(0.09, 0.015, 0.025, 0x88ccee, 0, 0.02, 0, g);
    box(0.03, 0.012, 0.04, 0x88ccee, 0.055, 0.02, 0, g);
  });
dailyTrap('peanuts', 'packing peanuts (styrofoam snack)', 'eat',
  'The cat is eating the PACKING PEANUTS!', g => {
    for (let i = 0; i < 6; i++)
      box(0.05, 0.03, 0.035, 0xf4f0e4, -0.12 + (i % 3) * 0.1, 0.02, Math.floor(i / 3) * 0.09 - 0.04, g);
  });
dailyTrap('earring', 'dropped earring (shiny, swallowable)', 'paw',
  'The cat is about to SWALLOW YOUR EARRING!', g => {
    const r = prim(new THREE.TorusGeometry(0.03, 0.008, 6, 10), 0xffd700, 0, 0.02, 0, g);
    r.rotation.x = Math.PI / 2;
    sph(0.015, 0xeeeeff, 0.03, 0.025, 0, g);
  });
dailyTrap('shoelace', 'stray shoelace', 'tangle',
  'The cat is tangled in the SHOELACE!', g => {
    for (let i = 0; i < 4; i++) {
      const l = box(0.16, 0.015, 0.02, 0xeeeedd, -0.15 + i * 0.1, 0.015, Math.cos(i * 2.2) * 0.06, g);
      l.rotation.y = 0.5 + i * 0.9;
    }
    box(0.03, 0.02, 0.02, 0xbbaa88, 0.24, 0.015, 0, g);   // aglet. it's called an aglet.
  });
dailyTrap('tape', 'roll of sticky tape', 'paw',
  'The cat is stuck to the STICKY TAPE! It is escalating!', g => {
    const r = prim(new THREE.TorusGeometry(0.06, 0.02, 6, 12), 0xd8d0b8, 0, 0.03, 0, g);
    r.rotation.x = Math.PI / 2;
    box(0.1, 0.012, 0.03, 0xe8e0c8, 0.1, 0.02, 0, g);     // peeled-off strip
  });

// ============================================================
// NAV GRID (so cats stop walking through walls)
// ============================================================
const NAV = { cell: 0.35, x0: -8, z0: -6, nx: 46, nz: 35, grids: {} };
function navIdx(ix, iz) { return ix * NAV.nz + iz; }
function navCell(x, z) {
  return [
    Math.max(0, Math.min(NAV.nx - 1, Math.floor((x - NAV.x0) / NAV.cell))),
    Math.max(0, Math.min(NAV.nz - 1, Math.floor((z - NAV.z0) / NAV.cell))),
  ];
}
function navWorld(ix, iz) { return [NAV.x0 + (ix + 0.5) * NAV.cell, NAV.z0 + (iz + 0.5) * NAV.cell]; }
function buildNav() {
  // stair footprints are traversed by explicit ramp segments, never by grid paths
  const stairRects = STAIRS.map(s => ({
    minX: s.minX - 0.05, maxX: s.maxX + 0.05,
    minZ: Math.min(s.z0, s.z1), maxZ: Math.max(s.z0, s.z1),
    lvls: [s.y0, s.y1],
  }));
  for (const lvl of LEVELS) {
    const g = new Uint8Array(NAV.nx * NAV.nz);
    for (let ix = 0; ix < NAV.nx; ix++) for (let iz = 0; iz < NAV.nz; iz++) {
      // cell is walkable if its CENTER, inflated by the cat radius, clears all walls.
      // R must exceed collideCat's r=0.2 or paths hug corners the collider then blocks.
      const cx = NAV.x0 + (ix + 0.5) * NAV.cell, cz = NAV.z0 + (iz + 0.5) * NAV.cell, R = 0.24;
      let blocked = false;
      for (const w of walls) {
        if (w.maxY < lvl + 0.1 || w.minY > lvl + 0.5) continue;
        if (w.minX - R < cx && w.maxX + R > cx && w.minZ - R < cz && w.maxZ + R > cz) { blocked = true; break; }
      }
      if (!blocked) for (const r of stairRects) {
        if (r.lvls.includes(lvl) && r.minX < cx && r.maxX > cx && r.minZ < cz && r.maxZ > cz) { blocked = true; break; }
      }
      g[navIdx(ix, iz)] = blocked ? 0 : 1;
    }
    NAV.grids[lvl] = g;
  }
}
function nearestOkCell(g, ix, iz) {
  if (g[navIdx(ix, iz)]) return [ix, iz];
  for (let r = 1; r <= 7; r++) {
    for (let dx = -r; dx <= r; dx++) for (let dz = -r; dz <= r; dz++) {
      if (Math.max(Math.abs(dx), Math.abs(dz)) !== r) continue;
      const nx = ix + dx, nz = iz + dz;
      if (nx < 0 || nz < 0 || nx >= NAV.nx || nz >= NAV.nz) continue;
      if (g[navIdx(nx, nz)]) return [nx, nz];
    }
  }
  return [-1, -1];
}
function navLos(g, a, b) {
  const [ax, az] = navWorld(a[0], a[1]), [bx, bz] = navWorld(b[0], b[1]);
  const d = Math.hypot(bx - ax, bz - az), steps = Math.max(2, Math.ceil(d / 0.1));
  // sample the center line plus two parallels offset by the cat's radius,
  // so string-pulled shortcuts can't clip a corner the collider would catch
  const px = d > 0 ? -(bz - az) / d * 0.14 : 0, pz = d > 0 ? (bx - ax) / d * 0.14 : 0;
  for (let i = 1; i < steps; i++) {
    const t = i / steps;
    const x = ax + (bx - ax) * t, z = az + (bz - az) * t;
    for (const [ox, oz] of [[0, 0], [px, pz], [-px, -pz]]) {
      const [cx, cz] = navCell(x + ox, z + oz);
      if (!g[navIdx(cx, cz)]) return false;
    }
  }
  return true;
}
function gridPath(lvl, ax, az, bx, bz) {
  const g = NAV.grids[lvl];
  if (!g) return [[bx, bz]];
  let s = nearestOkCell(g, ...navCell(ax, az));
  let t = nearestOkCell(g, ...navCell(bx, bz));
  if (s[0] < 0 || t[0] < 0) return [[bx, bz]];
  // BFS
  const prev = new Int16Array(NAV.nx * NAV.nz).fill(-1);
  const si = navIdx(s[0], s[1]), ti = navIdx(t[0], t[1]);
  prev[si] = si;
  const q = [si];
  let found = si === ti;
  for (let qi = 0; qi < q.length && !found; qi++) {
    const cur = q[qi];
    const cx = Math.floor(cur / NAV.nz), cz = cur % NAV.nz;
    for (const [dx, dz] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = cx + dx, nz = cz + dz;
      if (nx < 0 || nz < 0 || nx >= NAV.nx || nz >= NAV.nz) continue;
      const ni = navIdx(nx, nz);
      if (!g[ni] || prev[ni] !== -1) continue;
      prev[ni] = cur;
      if (ni === ti) { found = true; break; }
      q.push(ni);
    }
  }
  if (!found) return [[bx, bz]];
  const cells = [];
  for (let cur = ti; ; cur = prev[cur]) {
    cells.push([Math.floor(cur / NAV.nz), cur % NAV.nz]);
    if (cur === prev[cur]) break;
  }
  cells.reverse();
  // string-pull: skip ahead while line of sight is clear
  const pts = [];
  let i = 0;
  while (i < cells.length - 1) {
    let j = cells.length - 1;
    while (j > i + 1 && !navLos(g, cells[i], cells[j])) j--;
    pts.push(navWorld(cells[j][0], cells[j][1]));
    i = j;
  }
  pts.push([bx, bz]);
  return pts;
}
function randomNavPoint(lvl) {
  const g = NAV.grids[lvl];
  for (let tries = 0; tries < 40; tries++) {
    const ix = Math.floor(Math.random() * NAV.nx), iz = Math.floor(Math.random() * NAV.nz);
    if (g[navIdx(ix, iz)]) return navWorld(ix, iz);
  }
  return [0, 0];
}
buildNav();

// ============================================================
// THE CATS
// ============================================================
const cats = [];
const pendingAdopts = [];   // {name, colorDef} — new cats arrive next morning
function buildCatMesh(colorDef) {
  const g = new THREE.Group();
  const bodyC = colorDef.body, darkC = colorDef.dark;
  const body = box(0.55, 0.28, 0.32, bodyC, 0, 0.24, 0, g);
  const head = box(0.26, 0.24, 0.24, bodyC, 0.33, 0.42, 0, g);
  // ears + eyes ride on the head so head animation carries them
  const ears = [
    box(0.08, 0.1, 0.06, bodyC, 0.09, 0.16, 0.07, head),
    box(0.08, 0.1, 0.06, bodyC, 0.09, 0.16, -0.07, head),
  ];
  box(0.04, 0.04, 0.02, colorDef.eye, 0.135, 0.04, 0.06, head);
  box(0.04, 0.04, 0.02, colorDef.eye, 0.135, 0.04, -0.06, head);
  const tail = box(0.3, 0.07, 0.07, darkC, -0.4, 0.34, 0, g);
  const legs = [];  // 0,1 = front · 2,3 = back
  for (const [lx, lz] of [[0.18, 0.1], [0.18, -0.1], [-0.18, 0.1], [-0.18, -0.1]])
    legs.push(box(0.07, 0.2, 0.07, darkC, lx, 0.1, lz, g));
  return { g, body, head, tail, ears, legs };
}
function makeCat(name, colorDef, chaos) {
  const { g, body, head, tail, ears, legs } = buildCatMesh(colorDef);
  scene.add(g);
  const parts = [body, head, tail, ...legs];
  const basePose = parts.map(p => ({ p, pos: p.position.clone(), rot: p.rotation.clone(), scl: p.scale.clone() }));
  const c = {
    isCat: true, g, body, head, tail, ears, legs, basePose, name, chaos,
    speed: 1.7 + 0.5 * chaos,
    state: {
      mode: 'carrier',   // carrier | introSit | wander | walk | danger | distracted | pester | held | outside | eating | hop | perched
      waypoints: [], nextMode: null, target: null,
      idleT: 2, hurtT: 0, distractT: 0, eatT: 0, pesterT: 0,
      dangerAge: 0, heartsLostHere: 0, stuckT: 0,
      outside: false, outsideHaz: null, outsideText: '',
      full: 0,
      distractUses: {}, distractId: null,   // per-day boredom with each toy
      morningEat: false, napT: 0,
      idlePose: 'sit', perch: null, hopT: 0, hopDur: 0.5, hopFrom: null, hopTo: null,
      heldT: 0, noHoldT: 0, squirmWarned: false,   // cats tolerate being held only so long
      surf: null,           // the elevated surface the cat is currently on
      afterHop: null,       // {mode, target, sf} — enter this after an upward hop
      goAfterHop: null,     // deferred catGoTo args — walk here after hopping down
    },
  };
  const pad = hitPad(g, 0.45, 0, 0.28, 0);
  for (const o of [body, head, pad]) { o.userData.act = 'cat'; o.userData.catRef = c; interactables.push(o); }
  g.visible = false;
  cats.push(c);
  return c;
}
// swap "the cat" for this cat's name in hazard text
function pers(text, c) {
  return text.replace(/the cat('s)?/i, (m, g1) => c.name + (g1 || ''));
}
function catNamesJoined() { return cats.map(c => c.name).join(' & '); }

// ============================================================
// CAT ANIMATION — procedural poses per activity
// ============================================================
// furniture a cat may hop up onto: x/z/h = top spot, ax/az = approach offset
// pointing into open room space, r = footprint radius (for dropping a held cat onto it)
const PERCHES = [
  { name: 'couch',          x: -6.5, z: 5.2,  lvl: 0,  h: 0.47, ax: 0,   az: -1.1, r: 1.3 },
  { name: 'coffee table',   x: -4.6, z: 3.0,  lvl: 0,  h: 0.45, ax: 0.9, az: 0,    r: 0.75 },
  { name: 'dining table',   x: 5.5,  z: 3.5,  lvl: 0,  h: 0.82, ax: 0,   az: 1.2,  r: 1.1 },
  { name: 'kitchen counter',x: 5.0,  z: -5.3, lvl: 0,  h: 0.9,  ax: 0,   az: 1.0,  r: 1.0 },
  { name: 'bed',            x: -6.5, z: -4.9, lvl: 3,  h: 0.55, ax: 0,   az: 1.3,  r: 1.2 },
  { name: 'guest bed',      x: -6.5, z: 5.0,  lvl: 3,  h: 0.5,  ax: 0,   az: -1.3, r: 1.1 },
  { name: 'basement couch', x: -4.0, z: 4.5,  lvl: -3, h: 0.44, ax: 0,   az: -1.1, r: 1.2 },
  { name: 'workbench',      x: 5.5,  z: -5.4, lvl: -3, h: 0.9,  ax: 0,   az: 1.0,  r: 1.0 },
];
// yaw that faces from a perch/surface back toward its approach side (≈ the room center)
function faceRoomYaw(p) { return Math.atan2(-p.az, p.ax); }

function resetPose(c) {
  for (const b of c.basePose) {
    b.p.position.copy(b.pos);
    b.p.rotation.copy(b.rot);
    b.p.scale.copy(b.scl);
  }
  c.body.scale.set(1, 1, 1);
}
// helper: fold the cat into a sit (haunches down, front legs straight)
function sitBase(c, t) {
  c.body.rotation.z = 0.5;
  c.body.position.set(-0.05, 0.26, 0);
  c.head.position.set(0.24, 0.56, 0);
  c.legs[2].position.y = 0.06; c.legs[2].scale.y = 0.55;
  c.legs[3].position.y = 0.06; c.legs[3].scale.y = 0.55;
  c.legs[0].position.set(0.2, 0.12, 0.1);
  c.legs[1].position.set(0.2, 0.12, -0.1);
  c.tail.position.set(-0.2, 0.08, 0.14);
  c.tail.rotation.y = 1.1 + Math.sin(t * 1.5) * 0.15;
}
// helper: rear up on the hind legs, front paws off the ground
function rearUpBase(c, t) {
  c.body.rotation.z = 0.95;
  c.body.position.set(-0.1, 0.34, 0);
  c.head.position.set(0.1, 0.66, 0);
  c.head.rotation.z = -0.35;
  c.legs[2].position.set(-0.16, 0.1, 0.1);
  c.legs[3].position.set(-0.16, 0.1, -0.1);
  c.legs[0].position.set(0.12, 0.42, 0.1);  c.legs[0].rotation.z = -0.9;
  c.legs[1].position.set(0.12, 0.42, -0.1); c.legs[1].rotation.z = -0.9;
  c.tail.position.set(-0.34, 0.12, 0);
  c.tail.rotation.y = Math.sin(t * 3) * 0.4;
}
// helper: flopped on its back, belly up
function backBase(c, t) {
  c.body.position.y = 0.16;
  c.head.position.set(0.34, 0.2, 0.06);
  c.head.rotation.x = 2.7;
  c.tail.position.set(-0.38, 0.1, 0);
  for (let i = 0; i < 4; i++) c.legs[i].position.y = 0.34;
}
const POSE = {
  stand() {},
  walk(c, t) {
    const w = Math.sin(t * 11);
    c.legs[0].rotation.z = w * 0.6;  c.legs[3].rotation.z = w * 0.6;
    c.legs[1].rotation.z = -w * 0.6; c.legs[2].rotation.z = -w * 0.6;
    c.tail.rotation.z = 0.5;                       // tail up while trotting
    c.tail.rotation.y = Math.sin(t * 6) * 0.4;
  },
  sit(c, t) { sitBase(c, t); },
  beg(c, t) {   // sitting, staring up at you, meow-bobbing
    sitBase(c, t);
    c.head.rotation.z = 0.45 + Math.max(0, Math.sin(t * 3.2)) * 0.12;
  },
  loaf(c, t) {  // the classic bread shape
    c.body.position.y = 0.15;
    c.body.scale.y = 1 + Math.sin(t * 2) * 0.04;   // breathing
    c.head.position.set(0.3, 0.32, 0);
    for (let i = 0; i < 4; i++) { c.legs[i].scale.y = 0.3; c.legs[i].position.y = 0.03; }
    c.tail.position.set(-0.16, 0.1, 0.15);
    c.tail.rotation.y = 1.35;
  },
  curl(c, t) {  // fully asleep, nose tucked
    c.body.position.y = 0.13;
    c.body.scale.y = 1 + Math.sin(t * 1.6) * 0.05;
    c.head.position.set(0.22, 0.2, 0.06);
    c.head.rotation.z = -0.4;
    for (let i = 0; i < 4; i++) { c.legs[i].scale.y = 0.25; c.legs[i].position.y = 0.03; }
    c.tail.position.set(-0.1, 0.06, 0.17);
    c.tail.rotation.y = 1.5;
  },
  roll(c, t) {  // on its back, legs and tail wiggling in the air
    backBase(c, t);
    for (let i = 0; i < 4; i++) {
      c.legs[i].rotation.z = Math.sin(t * 7 + i * 1.8) * 0.5;
      c.legs[i].position.y = 0.34 + Math.sin(t * 5 + i * 2.2) * 0.04;
    }
    c.tail.rotation.y = Math.sin(t * 7) * 0.8;
  },
  tangle(c, t) {  // like roll, but frantic — something HAS the cat
    backBase(c, t);
    for (let i = 0; i < 4; i++) {
      c.legs[i].rotation.z = Math.sin(t * 16 + i * 1.8) * 0.8;
      c.legs[i].position.y = 0.34 + Math.sin(t * 13 + i * 2.2) * 0.07;
    }
    c.head.rotation.x = 2.7 + Math.sin(t * 10) * 0.3;
    c.tail.rotation.y = Math.sin(t * 15) * 1.0;
  },
  eat(c, t) {   // face down in something (food, plants, regrets)
    c.head.position.set(0.4, 0.2 + Math.abs(Math.sin(t * 7)) * 0.04, 0);
    c.head.rotation.z = -0.75;
    c.tail.rotation.z = 0.35;
    c.tail.rotation.y = Math.sin(t * 2.5) * 0.25;
  },
  paw(c, t) {   // sitting up, one paw batting at the thing
    sitBase(c, t);
    c.head.position.set(0.26, 0.5, 0);
    c.head.rotation.z = -0.25;
    c.legs[0].position.set(0.24, 0.24, 0.1);
    c.legs[0].rotation.z = -1.0 + Math.sin(t * 9) * 0.7;
  },
  fish(c, t) {  // paw dipping slowly in — toilet, tub...
    sitBase(c, t);
    c.head.position.set(0.28, 0.48, 0);
    c.head.rotation.z = -0.4;
    c.legs[0].position.set(0.27, 0.2, 0.06);
    c.legs[0].rotation.z = -1.3 + Math.sin(t * 3.2) * 0.45;
  },
  headIn(c, t) { // head buried in it, rear end up, tail flagging
    c.body.rotation.z = -0.45;
    c.body.position.set(0.02, 0.3, 0);
    c.head.position.set(0.42, 0.12, 0);
    c.head.rotation.z = -0.5 + Math.sin(t * 6) * 0.08;
    c.legs[0].position.set(0.2, 0.05, 0.1);  c.legs[0].scale.y = 0.55;
    c.legs[1].position.set(0.2, 0.05, -0.1); c.legs[1].scale.y = 0.55;
    c.legs[2].position.set(-0.2, 0.18, 0.1);  c.legs[2].scale.y = 1.25;
    c.legs[3].position.set(-0.2, 0.18, -0.1); c.legs[3].scale.y = 1.25;
    c.tail.position.set(-0.38, 0.5, 0);
    c.tail.rotation.z = 0.9;
    c.tail.rotation.y = Math.sin(t * 6) * 0.5;
  },
  sniffHigh(c, t) { // up on hind legs investigating something tall/hot
    rearUpBase(c, t);
    c.head.rotation.z = -0.35 + Math.sin(t * 5) * 0.1; // sniff-sniff
  },
  climb(c, t) {  // scrabbling up toward a window
    rearUpBase(c, t);
    c.legs[0].position.y = 0.42 + Math.sin(t * 12) * 0.07;
    c.legs[1].position.y = 0.42 - Math.sin(t * 12) * 0.07;
  },
  scratch(c, t) { // raking the post, alternating paws
    rearUpBase(c, t);
    c.legs[0].position.y = 0.44 + Math.sin(t * 8) * 0.09;
    c.legs[1].position.y = 0.44 - Math.sin(t * 8) * 0.09;
    c.tail.rotation.y = Math.sin(t * 4) * 0.5;
  },
  pounce(c, t) {  // butt-wiggle crouch, then spring
    const cyc = (t * 0.8) % 1;
    if (cyc < 0.6) {  // the wind-up wiggle
      c.body.position.y = 0.17;
      c.head.position.set(0.35, 0.3, 0);
      c.body.rotation.x = Math.sin(t * 14) * 0.08;
      c.tail.rotation.y = Math.sin(t * 12) * 0.7;
      for (let i = 0; i < 4; i++) { c.legs[i].scale.y = 0.6; c.legs[i].position.y = 0.05; }
    } else {          // airborne
      const k = (cyc - 0.6) / 0.4;
      const arc = Math.sin(Math.PI * k) * 0.3;
      c.body.position.y = 0.24 + arc;
      c.head.position.set(0.33, 0.42 + arc, 0);
      c.tail.position.y = 0.34 + arc;
      for (let i = 0; i < 4; i++) { c.legs[i].position.y = 0.12 + arc; c.legs[i].rotation.z = i < 2 ? -0.5 : 0.5; }
    }
  },
  watch(c, t) {   // sitting, head tracking the birds/screen
    sitBase(c, t);
    c.head.rotation.x = Math.sin(t * 1.7) * 0.3;
    c.head.position.y = 0.56 + Math.max(0, Math.sin(t * 0.9)) * 0.03;
  },
  groom(c, t) {   // sitting, licking a shoulder
    sitBase(c, t);
    c.head.position.set(0.16, 0.34, 0.1);
    c.head.rotation.y = -0.7 + Math.sin(t * 8) * 0.12;
    c.head.rotation.z = -0.5;
  },
  dangle(c, t) {  // being carried; limp acceptance
    for (let i = 0; i < 4; i++) c.legs[i].rotation.z = Math.sin(t * 2 + i) * 0.25;
    c.tail.rotation.y = Math.sin(t * 1.5) * 0.3;
  },
  jump(c) {   // airborne mid-leap — stretched out
    c.body.rotation.z = 0.22;
    c.head.position.set(0.36, 0.5, 0);
    c.legs[0].rotation.z = -0.9; c.legs[1].rotation.z = -0.9;  // front legs reaching
    c.legs[2].rotation.z = 0.8;  c.legs[3].rotation.z = 0.8;   // hind legs trailing
    c.tail.rotation.z = 0.5;
  },
};
function animateCat(c) {
  const s = c.state;
  if (s.mode === 'carrier') return;
  const t = performance.now() * 0.001 + c.chaos * 13;
  resetPose(c);
  let key = 'stand';
  switch (s.mode) {
    case 'walk': key = 'walk'; break;
    case 'hop': key = 'jump'; break;
    case 'danger': { const h = hazards[s.target]; key = (h && h.anim) || 'paw'; break; }
    case 'outside': key = 'sit'; break;
    case 'distracted': {
      const d = s.distractId ? distracts[s.distractId] : null;
      key = s.distractId === 'laser' ? 'pounce' : d ? d.anim : 'curl';
      break;
    }
    case 'eating': key = 'eat'; break;
    case 'waitFood': case 'pester': key = 'beg'; break;
    case 'hiddenNap': key = 'curl'; break;
    case 'held': key = 'dangle'; break;
    case 'introSit': key = 'sit'; break;
    case 'perched': key = s.idlePose === 'roll' ? 'loaf' : s.idlePose; break;
    case 'wander': key = s.idlePose; break;
  }
  (POSE[key] || POSE.stand)(c, t);
}
function pickIdlePose() {
  const r = Math.random();
  return r < 0.45 ? 'sit' : r < 0.7 ? 'loaf' : r < 0.85 ? 'roll' : 'groom';
}
function startHop(c, to, upward) {
  const s = c.state;
  s.mode = 'hop';
  s.hopUpward = upward;
  s.hopT = 0;
  s.hopDur = upward ? 0.5 : 0.45;
  s.hopFrom = c.g.position.clone();
  s.hopTo = to;
  c.g.rotation.y = Math.atan2(-(to.z - s.hopFrom.z), to.x - s.hopFrom.x);
}

function routeTo(c, x, y, z) {
  const from = nearestLevel(c.g.position.y), to = nearestLevel(y);
  const UP_IN = [1.6, -1.5], UP_OUT = [1.6, -5.45], DN_IN = [-1.45, -1.5], DN_OUT = [-1.45, -5.45];
  const hops = [];
  if (from === 0 && to === 3) hops.push({ e: UP_IN, x: UP_OUT, l: 3 });
  else if (from === 3 && to === 0) hops.push({ e: UP_OUT, x: UP_IN, l: 0 });
  else if (from === 0 && to === -3) hops.push({ e: DN_IN, x: DN_OUT, l: -3 });
  else if (from === -3 && to === 0) hops.push({ e: DN_OUT, x: DN_IN, l: 0 });
  else if (from === 3 && to === -3) hops.push({ e: UP_OUT, x: UP_IN, l: 0 }, { e: DN_IN, x: DN_OUT, l: -3 });
  else if (from === -3 && to === 3) hops.push({ e: DN_OUT, x: DN_IN, l: 0 }, { e: UP_IN, x: UP_OUT, l: 3 });
  const pts = [];
  let cur = [c.g.position.x, c.g.position.z], lvl = from;
  for (const h of hops) {
    pts.push(...gridPath(lvl, cur[0], cur[1], h.e[0], h.e[1]));
    pts.push(h.x); // ramp traversal (groundY handles the slope)
    cur = h.x; lvl = h.l;
  }
  pts.push(...gridPath(lvl, cur[0], cur[1], x, z));
  return pts;
}

function catGoTo(c, x, y, z, nextMode, targetId = null) {
  const s = c.state;
  const lvl = nearestLevel(c.g.position.y);
  if (c.g.position.y > lvl + 0.25) {
    // up on something — hop down to the floor first, then walk
    const sf = s.surf || s.perch;
    const tx = sf ? sf.x + sf.ax : c.g.position.x;
    const tz = sf ? sf.z + sf.az : c.g.position.z;
    s.surf = null;
    s.afterHop = null;
    s.goAfterHop = { x, y, z, nextMode, targetId };
    startHop(c, { x: tx, y: lvl, z: tz }, false);
    return;
  }
  s.waypoints = routeTo(c, x, y, z);
  s.mode = 'walk';
  s.nextMode = nextMode;
  s.target = targetId;
  s.dest = { x, y, z };
  s.stuckT = 0;
  s.repathed = false;
}

function hazardArmed(h) {
  return h && ((h.type === 'toggle' && h.armed) ||
               (h.type === 'item' && !h.stashed && !h.held) ||
               (h.type === 'barf' && !h.cleaned));
}
// the cat has arrived at (or hopped up to) an armed hazard — trouble begins
function enterDanger(c, h) {
  const s = c.state;
  s.mode = 'danger';
  s.target = h.id;
  s.hurtT = 8;
  s.dangerAge = 0;
  s.heartsLostHere = 0;
  msg(`🙀 ${pers(h.dangerText, c)}`, 'danger');
  msg(`(faint meowing from ${roomName(c.g.position.x, c.g.position.y, c.g.position.z)})`, '');
}
// leave whatever the cat is on (if anything), then idle-wander
function dismountThenWander(c) {
  const s = c.state;
  const lvl = nearestLevel(c.g.position.y);
  if (c.g.position.y > lvl + 0.25) {
    const sf = s.surf || s.perch;
    const tx = sf ? sf.x + sf.ax : c.g.position.x + 0.7;
    const tz = sf ? sf.z + sf.az : c.g.position.z + 0.7;
    s.surf = null;
    startHop(c, { x: tx, y: lvl, z: tz }, false);
  } else {
    s.mode = 'wander';
    s.idleT = 2 + Math.random() * 2;
    s.idlePose = pickIdlePose();
  }
}

function armedHazardList() {
  return Object.values(hazards).filter(h => {
    if (h.type === 'barf') return !h.cleaned;
    if ((h.tier || 99) > phase) return false;
    if (h.type === 'toggle') return h.armed;
    if (h.type === 'item') return !h.stashed && !h.held && !h.safeItem;
    return false;
  });
}

function catDecide(c) {
  if (gameOver || !tutorialDone) { c.state.idleT = 1; return; }
  const s = c.state;
  const armed = armedHazardList();
  const base = phase === 1 ? 0.14 : phase === 2 ? 0.32 : 0.5;
  const seekChance = Math.min(0.75, base * c.chaos);
  if (bowlFull && s.full <= 0 && Math.random() < 0.5) {
    catGoTo(c, bowl.position.x, 0, bowl.position.z, 'eating');
    return;
  }
  if (bowlFull && s.full > 0 && Math.random() < 0.35) {
    // full cat still goes back for seconds — that's the overeating hazard
    catGoTo(c, bowl.position.x, 0, bowl.position.z, 'eating');
    return;
  }
  if (armed.length && Math.random() < seekChance) {
    const h = armed[Math.floor(Math.random() * armed.length)];
    const p = h.mesh.position;
    const sf = h.curSurface;
    if (sf) catGoTo(c, sf.x + sf.ax, p.y, sf.z + sf.az, 'danger', h.id);
    else catGoTo(c, p.x, p.y, p.z, 'danger', h.id);
    return;
  }
  // early game the cat mostly wants YOU
  if (inComputer && Math.random() < (phase === 1 ? 0.5 : 0.35)) {
    catGoTo(c, player.x + 0.5, player.y, player.z, 'pester');
    return;
  }
  // sometimes: jump up on the furniture, because it's there
  if (Math.random() < 0.16) {
    const lvl = nearestLevel(c.g.position.y);
    const opts = PERCHES.filter(p => p.lvl === lvl);
    if (opts.length) {
      const p = opts[Math.floor(Math.random() * opts.length)];
      s.perch = p;
      catGoTo(c, p.x + p.ax, lvl, p.z + p.az, 'hopUp');
      return;
    }
  }
  // wander — the main floor during the tutorial-ish phase, then the whole house
  const lvls = phase === 1 ? [0] : LEVELS;
  const lvl = lvls[Math.floor(Math.random() * lvls.length)];
  const [x, z] = randomNavPoint(lvl);
  catGoTo(c, x, lvl, z, 'wanderIdle');
}

// each use of a toy halves how long it holds THAT cat's attention (resets overnight)
function distractTime(c, d) {
  const uses = c.state.distractUses[d.id] || 0;
  return Math.max(DISTRACT_MIN, d.time / Math.pow(2, uses));
}
// a cat counts as "on" a toy if it's using it or walking toward it
function onToy(c, id) {
  const s = c.state;
  return s.distractId === id &&
    (s.mode === 'distracted' || (s.mode === 'walk' && s.nextMode === 'distracted'));
}
function distractCat(id) {
  const d = distracts[id];
  if (!d || !d.owned) return;
  // one cat per distraction: if a cat already has this toy, it's locked until done.
  const occupant = cats.find(c => onToy(c, d.id));
  if (occupant) {
    // re-click is NOT a new use: no boredom tick, no timer reset.
    msg(`→ ${d.label}: ${occupant.name} is already on it (${Math.max(1, Math.ceil(occupant.state.distractT))}s left)`, '');
    return;
  }
  // eligible = free to be lured (not held/away/eating, and not busy with a DIFFERENT toy)
  const eligible = cats.filter(c => {
    const m = c.state.mode;
    if (m === 'held' || m === 'carrier' || m === 'outside' ||
        m === 'hiddenNap' || m === 'waitFood' || m === 'eating' || m === 'hop') return false;
    if (c.state.distractId && c.state.distractId !== d.id &&
        (m === 'distracted' || (m === 'walk' && c.state.nextMode === 'distracted'))) return false;
    return true;
  });
  if (!eligible.length) { msg('Nobody is interested right now. Tough crowd.'); return; }
  // grab the single NEAREST eligible cat
  let c = eligible[0], best = Infinity;
  for (const cand of eligible) {
    const dx = cand.g.position.x - d.pos.x, dz = cand.g.position.z - d.pos.z;
    const dist = dx * dx + dz * dz;
    if (dist < best) { best = dist; c = cand; }
  }
  const s = c.state;
  endDanger(c, false);
  const t = distractTime(c, d);
  s.distractUses[d.id] = (s.distractUses[d.id] || 0) + 1;
  const sf = d.surface;
  if (sf) catGoTo(c, sf.x + sf.ax, d.pos.y, sf.z + sf.az, 'distracted');
  else catGoTo(c, d.pos.x, d.pos.y, d.pos.z, 'distracted');
  s.distractT = t;
  s.distractId = d.id;
  msg(`→ ${d.label}: ${c.name} ${t <= DISTRACT_MIN + 0.01 ? 'is pretty bored of it (' + Math.round(t) + 's)' : '(' + Math.round(t) + 's)'}`, 'good');
}

function endDanger(c, announce = true) {
  const s = c.state;
  if (s.mode === 'danger' || s.mode === 'outside') {
    if (announce) msg(`${c.name} is safe. For now.`, 'good');
    s.outside = false;
    s.outsideHaz = null;
    dismountThenWander(c);
  }
}

function hurtCat(c, reason) {
  if (hearts <= 1) return; // the cat never dies — the vet run is already happening
  hearts--;
  heartsLostToday++;
  updateHearts();
  flashHearts();
  playHurtMeow(c);
  msg(`💔 ${pers(reason, c)} (${hearts} hearts left)`, 'danger');
  if (hearts <= 1) vetVisit(c);
}

// laser dot
const laserDot = box(0.15, 0.03, 0.15, 0xff2222, 0, -99, 0);
let laserT = 0;

// barf
let barfCounter = 0;
const barfPendings = []; // {t, pos}
function spawnBarf(x, y, z) {
  const b = box(0.35, 0.06, 0.35, 0x88aa33, x, y + 0.04, z);
  const id = 'barf' + (barfCounter++);
  hazards[id] = { id, type: 'barf', mesh: b, cleaned: false, name: 'cat barf', anim: 'eat',
    dangerText: 'The cat is EATING ITS OWN BARF. Why. WHY.' };
  registerInteract(b, { act: 'barf', id });
  msg('Someone barfed somewhere... find it before it gets re-eaten.', 'danger');
}

// ============================================================
// PLAYER
// ============================================================
function lockPointer() {
  try {
    const p = renderer.domElement.requestPointerLock();
    if (p && p.catch) p.catch(() => {});
  } catch (e) { /* headless / unsupported */ }
}

const player = { x: -0.5, y: 0, z: -1.2, yaw: Math.PI, pitch: -0.14, vy: 0 };
const keys = {};
let held = null;           // hazard record, cat object, or null
let pointerLocked = false;
let inComputer = false;

addEventListener('keydown', e => {
  if (adoptOpen) return;   // the adoption form owns the keyboard
  keys[e.code] = true;
  if (inComputer) { handleTyping(e); e.preventDefault(); return; }
  if (e.code === 'KeyP' && started && !gameOver && !tutorialOpen) togglePause();
});
addEventListener('keyup', e => keys[e.code] = false);

document.addEventListener('pointerlockchange', () => {
  pointerLocked = document.pointerLockElement === renderer.domElement;
  // browser ESC kicked us out while typing → treat it as stepping away
  if (!pointerLocked && inComputer && !adoptOpen) exitComputer(false);
  updateLockHint();
});

// ---- pause ----
let paused = false;
function togglePause() {
  if (!paused && $('dayOverlay').style.display === 'flex') return; // day summary already halts play
  paused = !paused;
  $('pauseScreen').style.display = paused ? 'flex' : 'none';
  if (paused) document.exitPointerLock();
  else lockPointer();
  updateLockHint();
}
addEventListener('mousemove', e => {
  if (!pointerLocked || inComputer) return;
  player.yaw -= e.movementX * 0.0023;
  player.pitch -= e.movementY * 0.0023;
  player.pitch = Math.max(-1.45, Math.min(1.45, player.pitch));
});

function collideR(nx, nz, y, r) {
  for (const w of walls) {
    if (y + 1.6 < w.minY || y + 0.2 > w.maxY) continue;
    const cx = Math.max(w.minX, Math.min(nx, w.maxX));
    const cz = Math.max(w.minZ, Math.min(nz, w.maxZ));
    const dx = nx - cx, dz = nz - cz;
    const d2 = dx * dx + dz * dz;
    if (d2 < r * r) {
      const d = Math.sqrt(d2) || 0.001;
      nx = cx + (dx / d) * r;
      nz = cz + (dz / d) * r;
    }
  }
  return [nx, nz];
}
// cats are shorter — only low walls block them
function collideCat(nx, nz, y) {
  const r = 0.2;
  for (const w of walls) {
    if (y + 0.55 < w.minY || y + 0.08 > w.maxY) continue;
    const cx = Math.max(w.minX, Math.min(nx, w.maxX));
    const cz = Math.max(w.minZ, Math.min(nz, w.maxZ));
    const dx = nx - cx, dz = nz - cz;
    const d2 = dx * dx + dz * dz;
    if (d2 < r * r) {
      const d = Math.sqrt(d2) || 0.001;
      nx = cx + (dx / d) * r;
      nz = cz + (dz / d) * r;
    }
  }
  return [nx, nz];
}

// ============================================================
// AUDIO (synthesized — no assets)
// ============================================================
let AC = null;
function audio() { if (!AC) AC = new (window.AudioContext || window.webkitAudioContext)(); return AC; }
function meow(volume, pitch = 1) {
  try {
    const ac = audio();
    const o = ac.createOscillator(), g = ac.createGain(), f = ac.createBiquadFilter();
    o.type = 'sawtooth';
    f.type = 'lowpass'; f.frequency.value = 1200;
    const t = ac.currentTime;
    o.frequency.setValueAtTime(620 * pitch, t);
    o.frequency.linearRampToValueAtTime(780 * pitch, t + 0.12);
    o.frequency.linearRampToValueAtTime(330 * pitch, t + 0.55);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(volume * 0.28, t + 0.08);
    g.gain.linearRampToValueAtTime(0.0001, t + 0.6);
    o.connect(f); f.connect(g); g.connect(ac.destination);
    o.start(t); o.stop(t + 0.65);
  } catch (e) { /* audio blocked */ }
}
function playHurtMeow(c) {
  const d = c.g.position.distanceTo(camera.position);
  meow(Math.min(1, 2.5 / (1 + d * 0.4)), 1.35);
}
let meowLoopT = 0;
function beep(freq, dur, vol = 0.15, type = 'square') {
  try {
    const ac = audio();
    const o = ac.createOscillator(), g = ac.createGain();
    o.type = type; o.frequency.value = freq;
    const t = ac.currentTime;
    g.gain.setValueAtTime(vol, t);
    g.gain.linearRampToValueAtTime(0.0001, t + dur);
    o.connect(g); g.connect(ac.destination);
    o.start(t); o.stop(t + dur);
  } catch (e) {}
}

// ============================================================
// HUD / MESSAGES
// ============================================================
const $ = id => document.getElementById(id);
let hearts = HEART_MAX;
function updateHearts() {
  $('hearts').textContent = '❤️'.repeat(Math.max(0, hearts)) + '🖤'.repeat(HEART_MAX - Math.max(0, hearts));
}
function updateEcon() {
  $('dayLabel').textContent = 'DAY ' + day;
  $('moneyLabel').textContent = money;
  const req = dayTasks.filter(t => !t.bob);
  $('taskLabel').textContent = req.length
    ? `${req.filter(t => t.done).length}/${req.length}` + (dayTasks.some(t => t.bob && !t.done) ? ' (+Bob?)' : '')
    : '—';
}
function flashHearts() {
  $('hearts').style.transition = 'none'; $('hearts').style.transform = 'scale(1.3)';
  setTimeout(() => { $('hearts').style.transition = 'transform 0.3s'; $('hearts').style.transform = 'scale(1)'; }, 60);
}
function msg(text, cls = '') {
  const div = document.createElement('div');
  div.className = 'msg ' + cls;
  div.textContent = text;
  $('messages').appendChild(div);
  setTimeout(() => div.remove(), 6500);
  while ($('messages').children.length > 4) $('messages').firstChild.remove();
}
let bossT = null;
function bossSay(text) {
  const b = $('bossBanner');
  b.textContent = text;
  b.style.display = 'block';
  beep(520, 0.12, 0.12, 'triangle');
  clearTimeout(bossT);
  bossT = setTimeout(() => { b.style.display = 'none'; }, 6000);
}
function setObjective(text) {
  const o = $('objective');
  o.textContent = text || '';
  o.style.display = text ? 'block' : 'none';
}
function updateLockHint() {
  $('lockHint').style.display =
    (started && !gameOver && !pointerLocked && !inComputer && !tutorialOpen && !paused && !adoptOpen) ? 'block' : 'none';
}

// ============================================================
// COMPUTER / TYPING MINIGAME (rendered onto the monitor itself)
// ============================================================
// no letter 'x' in any syllable — X is the "step away from the computer" key
const SYL = ['syn', 'erg', 'lev', 'blorp', 'quar', 'flim', 'den', 'corp', 'zam', 'plu', 'gran', 'yeet', 'stak', 'vio', 'merg', 'holt', 'bram', 'chur', 'kip', 'wonk', 'fiz', 'dram', 'lum', 'pon', 'trab'];
function gibberish() {
  let w = '';
  const n = 2 + Math.floor(Math.random() * 2);
  for (let i = 0; i < n; i++) w += SYL[Math.floor(Math.random() * SYL.length)];
  return w;
}
let screenBlocked = false;

// ---- the five work minigames (plus Bob-flavored reskins) ----
const MEET_POOL = ['Standup', 'Budget Sync', '1:1 w/ Boss', 'Sprint Review', 'All Hands', 'Retro', 'Vibes Check', 'Q3 Kickoff'];
const DAYS_W = ['MON', 'TUE', 'WED', 'THU', 'FRI'];
const MAIL_REAL = [
  ['boss@corp.biz', 'Re: re: re: those numbers'],
  ['hr@corp.biz', 'Mandatory Fun Day logistics'],
  ['bob@corp.biz', 'quick favor?? pls'],
  ['it@corp.biz', 'Your password expires TODAY'],
  ['ceo@corp.biz', 'Thoughts on our synergy journey'],
  ['facilities@corp.biz', 'Fridge cleanout Friday'],
];
const MAIL_SPAM = [
  ['prince@definitely.real', 'URGENT inheritance 4 U'],
  ['pills@meds4.less', 'FREE PILLS no vet needed'],
  ['winner@lotto.wow', 'You WON $10,000,000!!!'],
  ['hotsingles@ur.area', 'CATS in your area want to meet'],
  ['crypto@moon.gg', 'CatCoin going 1000x. trust me'],
];
const CALL_WORDS = ['SYNERGY', 'PIVOT', 'DEADLINE', 'BUDGET', 'ALIGNMENT', 'ROADMAP', 'STAKEHOLDER', 'DELIVERABLE', 'BANDWIDTH', 'LEVERAGE'];
const SHEET_ITEMS = ['CAT FOOD', 'VET FUND', 'TREATS', 'RENT', 'COFFEE', 'LASER PENS', 'CAT TOYS', 'CATNIP', 'LINT ROLLERS', 'SCRATCH POST'];
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function shuffled(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

// every game: start(st) inits, key(st,e) handles a keypress, draw(st,c,W,H) renders.
// progress = st.done / st.total; the task completes when done >= total.
const GAMES = {
  report: {
    label: 'Write the report', hint: 'type the letters',
    start(st) { st.total = 20; st.done = 0; st.word = gibberish(); st.idx = 0; st.wrong = false; },
    key(st, e) {
      if (e.key.length !== 1) return;
      if (e.key.toLowerCase() === st.word[st.idx]) {
        st.idx++; st.wrong = false;
        beep(700 + st.idx * 30, 0.03, 0.04, 'sine');
        if (st.idx >= st.word.length) { st.done++; st.idx = 0; st.word = gibberish(); beep(1000, 0.1, 0.08, 'sine'); }
      } else { st.wrong = true; beep(180, 0.08, 0.06); }
    },
    draw(st, c, W) {
      c.font = 'bold 40px monospace'; c.textAlign = 'left';
      const done = st.word.slice(0, st.idx), rest = st.word.slice(st.idx);
      let x = (W - c.measureText(st.word).width) / 2;
      c.fillStyle = '#6fd66f'; c.fillText(done, x, 150);
      x += c.measureText(done).width;
      c.fillStyle = st.wrong ? '#ff6b6b' : '#cfe8ff'; c.fillText(rest, x, 150);
      if (st.wrong) c.fillRect(x, 158, c.measureText(rest).width, 3);
    },
  },
  calendar: {
    label: 'Organize the calendar', hint: 'press the number shown under the right day',
    start(st) { st.total = 12; st.done = 0; this.next(st); },
    // days stay MON..FRI, but the key numbers under them shuffle every meeting
    next(st) { st.meeting = pick(MEET_POOL); st.day = Math.floor(Math.random() * 5); st.keys = shuffled([1, 2, 3, 4, 5]); st.wrong = -1; },
    key(st, e) {
      const n = parseInt(e.key, 10);
      if (!(n >= 1 && n <= 5)) return;
      const i = st.keys.indexOf(n);
      if (i === st.day) { st.done++; beep(1000, 0.08, 0.08, 'sine'); this.next(st); }
      else { st.wrong = i; beep(180, 0.08, 0.06); }
    },
    draw(st, c, W) {
      c.fillStyle = '#cfe8ff'; c.font = '17px monospace'; c.textAlign = 'center';
      c.fillText('Move the meeting to the right day:', W / 2, 90);
      c.fillStyle = '#ffd9a0'; c.font = 'bold 20px monospace';
      c.fillText(`"${st.meeting}"  →  ${DAYS_W[st.day]}`, W / 2, 125);
      for (let i = 0; i < 5; i++) {
        const x = 36 + i * 90;
        c.fillStyle = i === st.wrong ? '#5a2030' : '#16305a';
        c.fillRect(x, 160, 78, 60);
        c.fillStyle = '#8ab4e8'; c.font = '14px monospace';
        c.fillText(DAYS_W[i], x + 39, 185);
        c.fillStyle = '#ffe9a8'; c.font = 'bold 18px monospace';
        c.fillText(String(st.keys[i]), x + 39, 210);
      }
    },
  },
  mail: {
    label: 'Clear the inbox', hint: 'R = reply · D = delete spam',
    start(st) { st.total = 14; st.done = 0; this.next(st); },
    next(st) {
      st.spam = Math.random() < 0.5;
      st.mail = pick(st.spam ? MAIL_SPAM : MAIL_REAL);
      st.wrong = false;
    },
    key(st, e) {
      const k = e.key.toLowerCase();
      if (k !== 'r' && k !== 'd') return;
      const right = st.spam ? 'd' : 'r';
      if (k === right) { st.done++; beep(1000, 0.08, 0.08, 'sine'); this.next(st); }
      else { st.wrong = true; beep(180, 0.08, 0.06); }
    },
    draw(st, c, W) {
      c.fillStyle = '#16305a'; c.fillRect(46, 70, W - 92, 110);
      c.fillStyle = '#8ab4e8'; c.font = '14px monospace'; c.textAlign = 'left';
      c.fillText('FROM: ' + st.mail[0], 62, 100);
      c.fillStyle = '#cfe8ff'; c.font = 'bold 17px monospace';
      c.fillText('SUBJ: ' + st.mail[1], 62, 130);
      c.textAlign = 'center'; c.font = '15px monospace';
      c.fillStyle = st.wrong ? '#ff8a8a' : '#9df09d';
      c.fillText(st.wrong ? 'Nope! Look closer at the sender...' : '[R] reply politely     [D] delete (spam)', W / 2, 165);
    },
  },
  sheet: {
    label: 'Fill in the spreadsheet', hint: 'WASD scroll · type the highlighted cell: letter, then number',
    // the sheet is 6x6, viewed 3x3 at a time (4 pages, scrolled with WASD).
    // CORP-OS removed columns A and D in an update — conveniently, so typing
    // a column letter never collides with the scroll keys.
    COLS: 'BCEFGH',
    start(st) { st.total = 8; st.done = 0; st.cells = {}; st.px = 0; st.py = 0; this.next(st); },
    next(st) {
      const free = [];
      for (const col of this.COLS) for (let r = 1; r <= 6; r++) if (!st.cells[col + r]) free.push(col + r);
      st.target = pick(free);
      st.entry = { label: pick(SHEET_ITEMS), val: '$' + (5 + Math.floor(Math.random() * 95)) };
      st.stage = 0;  // 0 = waiting for the column letter, 1 = waiting for the row number
      st.wrong = false;
    },
    key(st, e) {
      if (e.key.length !== 1) return;
      const lk = e.key.toLowerCase();
      if (lk === 'a') { st.px = 0; return; }   // scroll — never a cell guess
      if (lk === 'd') { st.px = 1; return; }
      if (lk === 'w') { st.py = 0; return; }
      if (lk === 's') { st.py = 1; return; }
      const k = e.key.toUpperCase();
      if (st.stage === 0) {
        if (!this.COLS.includes(k)) return;
        if (k === st.target[0]) { st.stage = 1; st.wrong = false; beep(800, 0.05, 0.05, 'sine'); }
        else { st.wrong = true; beep(180, 0.08, 0.06); }
      } else {
        if (!'123456'.includes(k)) return;
        if (k === st.target[1]) {
          st.cells[st.target] = st.entry;
          st.done++;
          beep(1000, 0.08, 0.08, 'sine');
          if (st.done < st.total) this.next(st);
        } else { st.wrong = true; st.stage = 0; beep(180, 0.08, 0.06); }
      }
    },
    draw(st, c, W) {
      const COLS = this.COLS;
      c.font = '13px monospace'; c.textAlign = 'center';
      c.fillStyle = '#cfe8ff';
      c.fillText(`Enter  ${st.entry.label} ${st.entry.val}  into the highlighted cell`, W / 2, 66);
      c.fillStyle = st.wrong ? '#ff8a8a' : '#ffd9a0';
      c.fillText(st.wrong ? 'nope — read the headers again'
               : st.stage === 1 ? `${st.target[0]} _` : 'type the cell: column letter, then row number', W / 2, 83);
      // which page is the target on?
      const tCol = COLS.indexOf(st.target[0]), tRow = parseInt(st.target[1], 10) - 1;
      const tpx = Math.floor(tCol / 3), tpy = Math.floor(tRow / 3);
      const x0 = 108, y0 = 104, cw = 108, ch = 44;
      // page indicator
      c.font = '11px monospace'; c.textAlign = 'right'; c.fillStyle = '#55688a';
      c.fillText(`cols ${COLS[st.px * 3]}–${COLS[st.px * 3 + 2]} · rows ${st.py * 3 + 1}–${st.py * 3 + 3}`, W - 14, 72);
      // column + row headers for the visible page
      c.font = '13px monospace'; c.textAlign = 'center';
      for (let i = 0; i < 3; i++) {
        c.fillStyle = '#8ab4e8';
        c.fillText(COLS[st.px * 3 + i], x0 + cw * i + cw / 2, y0 - 5);
      }
      for (let j = 0; j < 3; j++) {
        const r = st.py * 3 + j + 1;
        c.fillStyle = '#8ab4e8'; c.textAlign = 'right';
        c.fillText(String(r), x0 - 10, y0 + j * ch + 27);
        c.textAlign = 'center';
        for (let i = 0; i < 3; i++) {
          const id = COLS[st.px * 3 + i] + r, filled = st.cells[id];
          const isTarget = id === st.target;
          c.fillStyle = filled ? '#12331a' : isTarget ? '#8a5a10' : '#16305a';
          c.fillRect(x0 + cw * i + 2, y0 + j * ch + 2, cw - 4, ch - 4);
          if (isTarget && !filled) {
            c.strokeStyle = '#ffd9a0'; c.lineWidth = 3;
            c.strokeRect(x0 + cw * i + 3.5, y0 + j * ch + 3.5, cw - 7, ch - 7);
          }
          if (filled) {
            c.fillStyle = '#9df09d'; c.font = '10px monospace';
            c.fillText(filled.label, x0 + cw * i + cw / 2, y0 + j * ch + 19);
            c.fillText(filled.val, x0 + cw * i + cw / 2, y0 + j * ch + 33);
            c.font = '13px monospace';
          }
        }
      }
      // off-page? point the way (with the key to press), stacked in the right margin
      c.fillStyle = '#ffb347'; c.font = 'bold 15px monospace'; c.textAlign = 'left';
      const ax = x0 + 3 * cw + 14, gy = y0 + 1.5 * ch + 5;
      if (tpy < st.py) c.fillText('▲ W', ax, gy - 26);
      if (tpx < st.px) c.fillText('◀ A', ax, gy);
      if (tpx > st.px) c.fillText('D ▶', ax, gy);
      if (tpy > st.py) c.fillText('▼ S', ax, gy + 26);
    },
  },
  call: {
    label: 'Call with the boss', hint: 'memorize, then press the numbers IN ORDER · A = ask again',
    start(st) { st.total = 4; st.done = 0; this.next(st); },
    next(st) {
      const pool = shuffled(CALL_WORDS);
      st.words = pool.slice(0, 3);
      st.opts = shuffled(pool.slice(0, 6));
      st.picked = 0;
      st.showUntil = performance.now() + 4200;
    },
    key(st, e) {
      if (performance.now() < st.showUntil) return;
      if (e.key.toLowerCase() === 'a') {
        // "sorry, could you repeat that?" — boss re-lists the points, you start over
        st.showUntil = performance.now() + 4200;
        st.picked = 0;
        beep(500, 0.12, 0.06, 'triangle');
        return;
      }
      const n = parseInt(e.key, 10);
      if (!(n >= 1 && n <= 6)) return;
      if (st.opts[n - 1] === st.words[st.picked]) {
        st.picked++;
        beep(800 + st.picked * 150, 0.07, 0.07, 'sine');
        if (st.picked >= 3) { st.done++; beep(1200, 0.12, 0.09, 'sine'); this.next(st); }
      } else {
        st.picked = 0;
        beep(180, 0.12, 0.06);
      }
    },
    draw(st, c, W) {
      if (performance.now() < st.showUntil) {
        c.fillStyle = '#9df09d'; c.font = '15px monospace'; c.textAlign = 'center';
        c.fillText('📞 The boss says (MEMORIZE THE ORDER):', W / 2, 85);
        c.fillStyle = '#ffd9a0'; c.font = 'bold 24px monospace';
        st.words.forEach((w, i) => c.fillText(`${i + 1}. ${w}`, W / 2, 125 + i * 36));
      } else {
        c.fillStyle = '#cfe8ff'; c.font = '15px monospace'; c.textAlign = 'center';
        c.fillText(`"So what were my three points?"  (${st.picked}/3${st.picked ? ' — keep going' : ''})`, W / 2, 82);
        c.fillStyle = '#556'; c.font = '12px monospace';
        c.fillText('A = "sorry, could you repeat that?"', W / 2, 240);
        c.font = 'bold 15px monospace';
        st.opts.forEach((w, i) => {
          const col = i % 2, row = Math.floor(i / 2);
          const x = 60 + col * 200, y = 105 + row * 42;
          c.fillStyle = '#16305a'; c.fillRect(x, y, 190, 32);
          c.fillStyle = '#ffe9a8'; c.textAlign = 'left'; c.fillText(String(i + 1), x + 10, y + 22);
          c.fillStyle = '#cfe8ff'; c.textAlign = 'center'; c.fillText(w, x + 105, y + 22);
        });
      }
    },
  },
};
const GAME_KEYS = ['report', 'calendar', 'mail', 'sheet', 'call'];

function makeDayTasks() {
  // duplicates are allowed — some days it's just reports, reports, reports
  const n = day <= 2 ? 3 : 4;
  dayTasks = [];
  for (let i = 0; i < n; i++) {
    const k = pick(GAME_KEYS);
    dayTasks.push({ key: k, label: GAMES[k].label, pay: TASK_PAY, done: false, bob: false, st: null });
  }
  if (day >= 2 && Math.random() < 0.45) {
    const k = pick(GAME_KEYS);
    dayTasks.push({ key: k, label: `Bob's "${GAMES[k].label.toLowerCase()}" (cover for him)`, pay: BOB_PAY, done: false, bob: true, st: null });
  }
  curTaskI = -1;
}

function completeTask() {
  const t = dayTasks[curTaskI];
  t.done = true;
  money += t.pay; earnedToday += t.pay;
  msg(`✅ ${t.label} — done! +$${t.pay}`, 'good');
  if (t.bob) bossSay('📎 Bob: "omg thank u!! i owe you. again. still."');
  beep(1250, 0.2, 0.1, 'sine');
  curTaskI = -1;
  comp = (dayStage === 'evening' && dayTasks.every(x => x.done)) ? 'shop' : 'tasks';
  if (dayStage === 'work' && dayTasks.filter(x => !x.bob).every(x => x.done)) finishWorkDay();
  updateEcon();
  drawScreen();
}
function finishWorkDay() {
  dayStage = 'evening';
  ringing = false; awayTime = 0; $('awayWarn').style.display = 'none';
  if (heartsLostToday === 0) {
    money += NO_HEART_BONUS; earnedToday += NO_HEART_BONUS;
    msg(`🎉 Work day done! Zero-hearts-lost bonus: +$${NO_HEART_BONUS}!`, 'good');
  } else msg('🎉 Work day done! You are off the clock.', 'good');
  const bobLeft = dayTasks.some(t => t.bob && !t.done);
  comp = bobLeft ? 'tasks' : 'shop';
  if (bobLeft) {
    msg('📎 Bob\'s task is still open — do it for the extra cash, or ignore him (again).');
    setObjective('📎 Optional: finish Bob\'s task · 🛒 SHOP on the computer · then go to BED');
  } else {
    setObjective('🛒 SHOP on the computer (optional) — then go UPSTAIRS and click your BED to sleep');
  }
}

// ---- the shop (buy tonight, delivered tomorrow morning) ----
// product thumbnails: each item is rendered once, offscreen, into a little canvas
const thumbs = {};  // catalog id -> 2D canvas
let thumbsMade = false;
function makeThumbs() {
  if (thumbsMade) return;
  thumbsMade = true;
  const SZ = 128;
  const tr = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  tr.setSize(SZ, SZ);
  const ts = new THREE.Scene();
  ts.add(new THREE.AmbientLight(0xffffff, 0.85));
  const dl = new THREE.DirectionalLight(0xfff2d8, 0.9);
  dl.position.set(2, 3, 4);
  ts.add(dl);
  const tc = new THREE.PerspectiveCamera(38, 1, 0.01, 60);
  const snap = (obj) => {
    const clone = obj.clone(true);
    clone.position.set(0, 0, 0);
    clone.rotation.set(0, -0.6, 0);
    clone.traverse(o => { o.visible = true; });
    ts.add(clone);
    const bb = new THREE.Box3().setFromObject(clone);
    const ctr = bb.getCenter(new THREE.Vector3());
    const r = bb.getSize(new THREE.Vector3()).length() / 2 || 1;
    tc.position.set(ctr.x + r * 1.5, ctr.y + r * 0.9, ctr.z + r * 1.5);
    tc.lookAt(ctr);
    tr.render(ts, tc);
    const cv = document.createElement('canvas');
    cv.width = SZ; cv.height = SZ;
    cv.getContext('2d').drawImage(tr.domElement, 0, 0);
    ts.remove(clone);
    return cv;
  };
  for (const d of Object.values(distracts)) thumbs[d.id] = snap(d.mesh);
  for (const b of Object.values(containers)) if (b.price > 0) thumbs[b.id] = snap(b.mesh);
  const model = buildCatMesh(CAT_COLORS[1]);   // display-model cat for the adoption card
  thumbs.adopt = snap(model.g);
  tr.dispose();
}
function shopCatalog() {
  const list = [
    ...Object.values(distracts).filter(d => !d.owned)
      .map(d => ({ kind: 'toy', rec: d, id: d.id, label: d.label, price: d.price,
                   locked: day < d.unlock, unlock: d.unlock, pending: d.pending, time: d.time })),
    ...Object.values(containers).filter(b => !b.owned)
      .map(b => ({ kind: 'storage', rec: b, id: b.id, label: b.label, price: b.price,
                   locked: day < b.unlock, unlock: b.unlock, pending: b.pending, cap: b.cap })),
  ].sort((a, b) => a.price - b.price);
  if (catAvailable())
    list.push({ kind: 'cat', id: 'adopt', label: 'a whole entire cat', price: 0,
                locked: false, unlock: 1, pending: false });
  return list;
}
let shopScroll = 0;
function buyItem(i) {
  const it = shopCatalog()[i];
  if (!it) return;
  if (it.kind === 'cat') { openAdopt(); return; }
  const d = it.rec;
  if (day < d.unlock) { msg(`Out of stock — CATS-R-US restocks it on day ${d.unlock}.`); return; }
  if (d.pending) { msg('Already ordered — it arrives tomorrow morning.'); return; }
  if (money < d.price) { msg(`Not enough money for the ${d.label} ($${d.price}).`, 'danger'); beep(180, 0.1, 0.08); return; }
  money -= d.price;
  d.pending = true;
  boughtToday.push(d);
  msg(`🛒 Ordered: ${d.label} — arrives tomorrow morning!`, 'good');
  beep(900, 0.12, 0.1, 'triangle');
  updateEcon();
  drawScreen();
}

// ---- adopting another cat (name + coat picker) ----
let adoptOpen = false;
let adoptColor = CAT_COLORS[0];
function openAdopt() {
  if (!catAvailable()) { msg('The shelter has no cats available right now. Check back in a few days.'); return; }
  adoptOpen = true;
  document.exitPointerLock();
  const used = new Set(cats.map(c => c.name.toLowerCase()));
  pendingAdopts.forEach(a => used.add(a.name.toLowerCase()));
  const avail = NAME_POOL.filter(n => !used.has(n.toLowerCase()));
  $('adoptName').value = avail.length ? pick(avail) : 'Trouble';
  const chipBox = $('adoptChips');
  chipBox.innerHTML = '';
  for (const n of avail.slice(0, 6)) {
    const s = document.createElement('span');
    s.className = 'chip'; s.textContent = n;
    s.onclick = () => { $('adoptName').value = n; };
    chipBox.appendChild(s);
  }
  const colorRow = $('adoptColors');
  colorRow.innerHTML = '';
  CAT_COLORS.forEach(cd => {
    const s = document.createElement('div');
    s.className = 'swatch' + (cd === adoptColor ? ' sel' : '');
    s.style.background = '#' + cd.body.toString(16).padStart(6, '0');
    s.onclick = () => {
      adoptColor = cd;
      colorRow.querySelectorAll('.swatch').forEach(el => el.classList.remove('sel'));
      s.classList.add('sel');
    };
    colorRow.appendChild(s);
  });
  $('adoptPriceLine').textContent = 'Adoption is FREE · arrives tomorrow morning · each cat is more chaotic than the last';
  $('adoptOverlay').style.display = 'flex';
}
function closeAdopt() {
  adoptOpen = false;
  $('adoptOverlay').style.display = 'none';
  drawScreen();
  if (!inComputer && started && !gameOver) lockPointer();
}
$('adoptBuy').onclick = () => {
  if (!catAvailable()) { closeAdopt(); return; }
  const name = ($('adoptName').value.trim() || 'Trouble').slice(0, 14);
  pendingAdopts.push({ name, colorDef: adoptColor });
  msg(`🐈 Adoption approved! ${name} arrives tomorrow morning.`, 'good');
  beep(900, 0.12, 0.1, 'triangle');
  updateEcon();
  closeAdopt();
};
$('adoptCancel').onclick = () => closeAdopt();

function drawScreen() {
  const c = scrCtx, W = 512, H = 320;
  c.fillStyle = '#081426'; c.fillRect(0, 0, W, H);
  c.fillStyle = '#12233f'; c.fillRect(0, 0, W, 28);
  c.fillStyle = '#8ab4e8'; c.font = '13px monospace'; c.textAlign = 'left';
  c.fillText(`CORP-OS 95 · day ${day} · $${money}`, 8, 18);
  const req = dayTasks.filter(t => !t.bob), doneN = req.filter(t => t.done).length;

  if (!inComputer) {
    c.fillStyle = '#4a6a9a'; c.font = '19px monospace'; c.textAlign = 'center';
    c.fillText(dayStage === 'evening' ? 'off the clock 😌' : `tasks done: ${doneN}/${req.length || '?'}`, W / 2, 135);
    c.fillStyle = '#ffd9a0';
    c.fillText(dayStage === 'evening' ? 'Click the monitor to SHOP' : 'Click the monitor to work', W / 2, 175);
  } else if (comp === 'game' && screenBlocked) {
    c.fillStyle = '#3a1520'; c.fillRect(0, 90, W, 130);
    c.fillStyle = '#ff8a8a'; c.font = 'bold 26px monospace'; c.textAlign = 'center';
    c.fillText('🐈 A CAT IS ON THE KEYBOARD', W / 2, 150);
    c.font = '16px monospace'; c.fillStyle = '#ffd0d0';
    c.fillText('Deal with it. (X to step away, then pick it up or distract it)', W / 2, 185);
  } else if (comp === 'game') {
    const t = dayTasks[curTaskI], g = GAMES[t.key], st = t.st;
    c.fillStyle = '#ffd9a0'; c.font = 'bold 15px monospace'; c.textAlign = 'center';
    c.fillText((t.bob ? '📎 ' : '') + t.label.toUpperCase(), W / 2, 50);
    g.draw(st, c, W, H);
    c.fillStyle = '#1a2f52'; c.fillRect(66, 252, 380, 13);
    c.fillStyle = '#6fd66f'; c.fillRect(66, 252, 380 * (st.done / st.total), 13);
    c.fillStyle = '#8ab4e8'; c.font = '14px monospace'; c.textAlign = 'center';
    c.fillText(`${st.done} / ${st.total}`, W / 2, 285);
    c.fillStyle = '#556'; c.font = '12px monospace';
    c.fillText(g.hint + ' — ⌫ task list — X step away', W / 2, 306);
  } else if (comp === 'tasks') {
    c.fillStyle = '#ffd9a0'; c.font = 'bold 17px monospace'; c.textAlign = 'center';
    c.fillText(`📋 TODAY'S TASKS — DAY ${day}`, W / 2, 55);
    c.font = '15px monospace'; c.textAlign = 'left';
    dayTasks.forEach((t, i) => {
      const y = 90 + i * 34;
      c.fillStyle = t.done ? '#12331a' : '#16305a';
      c.fillRect(46, y - 20, W - 92, 28);
      c.fillStyle = '#ffe9a8'; c.fillText(String(i + 1), 58, y);
      c.fillStyle = t.done ? '#6fd66f' : '#cfe8ff';
      c.fillText(`${t.done ? '✔ ' : ''}${t.label}  ($${t.pay})`, 82, y);
    });
    c.textAlign = 'center'; c.font = '14px monospace'; c.fillStyle = '#9df09d';
    const y0 = 100 + dayTasks.length * 34;
    if (dayStage === 'morning') { c.fillStyle = '#ff8a8a'; c.fillText('⚠ feed the cat first — the meowing is unbearable', W / 2, y0); }
    else if (dayStage === 'evening') c.fillText(doneN >= req.length ? 'all required tasks done! press B for the SHOP' : '', W / 2, y0);
    else c.fillText('press a number to start a task', W / 2, y0);
  } else if (comp === 'shop') {
    makeThumbs();
    const list = shopCatalog();
    c.fillStyle = '#ffd9a0'; c.font = 'bold 15px monospace'; c.textAlign = 'center';
    c.fillText('🛒 CATS-R-US EXPRESS — overnight delivery', W / 2, 45);
    if (!list.length) {
      c.fillStyle = '#9df09d'; c.font = '14px monospace';
      c.fillText('You own EVERYTHING. Your cats are landlords now.', W / 2, 150);
    }
    const rows = Math.ceil(list.length / 3);
    shopScroll = Math.max(0, Math.min(shopScroll, Math.max(0, rows - 2)));
    const cardW = 156, cardH = 104, x0 = 15, y0 = 54;
    list.forEach((it, i) => {
      const row = Math.floor(i / 3) - shopScroll, col = i % 3;
      if (row < 0 || row > 1) return;
      const x = x0 + col * (cardW + 10), y = y0 + row * (cardH + 6);
      c.fillStyle = it.pending ? '#12331a' : it.locked ? '#0e1728' : '#16305a';
      c.fillRect(x, y, cardW, cardH);
      c.strokeStyle = it.pending ? '#2f6a3a' : '#2a4a7a';
      c.strokeRect(x + 0.5, y + 0.5, cardW - 1, cardH - 1);
      c.fillStyle = '#ffe9a8'; c.font = 'bold 12px monospace'; c.textAlign = 'left';
      c.fillText(String(i + 1), x + 6, y + 14);
      const th = thumbs[it.id];
      if (th) {
        c.globalAlpha = it.locked ? 0.28 : 1;
        c.drawImage(th, x + cardW / 2 - 26, y + 3, 52, 52);
        c.globalAlpha = 1;
      }
      c.textAlign = 'center'; c.font = '11px monospace';
      c.fillStyle = it.locked ? '#55688a' : '#cfe8ff';
      let name = it.label.split(' (')[0];
      if (name.length > 22) name = name.slice(0, 21) + '…';
      c.fillText(name, x + cardW / 2, y + 66);
      c.font = '9px monospace'; c.fillStyle = it.locked ? '#3d4d68' : '#8ab4e8';
      c.fillText(it.kind === 'cat' ? 'permanent. very permanent.'
               : it.kind === 'storage' ? `cat-proof storage · ${it.cap} slots`
               : `holds a cat ~${it.time}s`, x + cardW / 2, y + 78);
      c.font = 'bold 12px monospace';
      if (it.pending) {
        c.fillStyle = '#6fd66f'; c.fillText('✓ ORDERED', x + cardW / 2, y + 94);
      } else if (it.locked) {
        c.fillStyle = '#ff8a8a'; c.fillText('OUT OF STOCK', x + cardW / 2, y + 90);
        c.fillStyle = '#55688a'; c.font = '9px monospace';
        c.fillText(`restock: day ${it.unlock}`, x + cardW / 2, y + 101);
      } else {
        c.fillStyle = money >= it.price ? '#9df09d' : '#ff8a8a';
        c.fillText(it.kind === 'cat' ? 'FREE' : '$' + it.price, x + cardW / 2, y + 94);
      }
    });
    if (shopScroll > 0) { c.fillStyle = '#ffd9a0'; c.font = '12px monospace'; c.textAlign = 'right'; c.fillText('▲ more', W - 12, 62); }
    if (rows - shopScroll > 2) { c.fillStyle = '#ffd9a0'; c.font = '12px monospace'; c.textAlign = 'right'; c.fillText('▼ more', W - 12, 268); }
    c.textAlign = 'center'; c.font = '12px monospace'; c.fillStyle = '#8ab4e8';
    const bobLeft = dayTasks.some(t => t.bob && !t.done);
    c.fillText(`number = buy${rows > 2 ? ' · W/S scroll' : ''} · T = tasks${bobLeft ? ' (Bob still needs help!)' : ''} · X = done (go to bed)`, W / 2, 305);
  }
  scrTex.needsUpdate = true;
  const cur = curTaskI >= 0 ? dayTasks[curTaskI] : null;
  const p = cur && cur.st ? cur.st.done / cur.st.total : 0;
  $('workFill').style.width = (p * 100) + '%';
  $('workPct').textContent = Math.floor(p * 100);
}
function catBlockingKeyboard() {
  return cats.some(c => {
    const s = c.state;
    if (s.mode !== 'pester' && s.mode !== 'held') return false;
    const d = Math.hypot(c.g.position.x - player.x, c.g.position.z - player.z);
    return d < 2.2 && Math.abs(c.g.position.y - player.y) < 1.8;
  });
}
function handleTyping(e) {  // all keyboard input while sitting at the computer
  if (e.key === 'Escape' || e.key.toLowerCase() === 'x') { exitComputer(); return; }
  if (comp === 'game') {
    if (e.key === 'Backspace') { curTaskI = -1; comp = 'tasks'; drawScreen(); return; } // progress is saved
    if (catBlockingKeyboard()) return;
    const t = dayTasks[curTaskI];
    GAMES[t.key].key(t.st, e);
    if (t.st.done >= t.st.total) { completeTask(); return; }
    drawScreen();
  } else if (comp === 'tasks') {
    if (e.key.toLowerCase() === 'b' && dayStage === 'evening') { comp = 'shop'; drawScreen(); return; }
    const n = parseInt(e.key, 10);
    if (n >= 1 && n <= dayTasks.length) {
      const t = dayTasks[n - 1];
      if (t.done) { msg('That one is already done. Nice.'); return; }
      if (dayStage === 'morning') { msg('Feed the cat first! You can\'t think through this meowing.', 'danger'); return; }
      curTaskI = n - 1;
      if (!t.st) { t.st = {}; GAMES[t.key].start(t.st); }
      comp = 'game';
      if (!firstTaskStarted) { firstTaskStarted = true; msg('You\'re on the clock now. Don\'t go idle too long...'); }
      drawScreen();
    }
  } else if (comp === 'shop') {
    if (e.key.toLowerCase() === 't') { comp = 'tasks'; drawScreen(); return; }
    if (e.key === 'ArrowDown' || e.key.toLowerCase() === 's') { shopScroll++; drawScreen(); return; }
    if (e.key === 'ArrowUp' || e.key.toLowerCase() === 'w') { shopScroll = Math.max(0, shopScroll - 1); drawScreen(); return; }
    const n = parseInt(e.key, 10);
    if (n >= 1) buyItem(n - 1);
  }
}

// camera glides to the monitor while working
let compBlend = 0;
const compCamPos = new THREE.Vector3(-6.9, 1.5, -2.62);
const compCamQuat = new THREE.Quaternion();
{
  const m = new THREE.Matrix4().lookAt(compCamPos, new THREE.Vector3(-6.9, 1.5, -3.35), new THREE.Vector3(0, 1, 0));
  compCamQuat.setFromRotationMatrix(m);
}

function enterComputer() {
  inComputer = true;
  $('compExit').style.display = 'block';
  awayTime = 0;   // sitting down does NOT silence a ringing phone — you must ANSWER it
  updateLockHint();
  if (curTaskI >= 0 && !dayTasks[curTaskI].done) comp = 'game';         // resume mid-task
  else comp = (dayStage === 'evening' && !dayTasks.some(t => t.bob && !t.done)) ? 'shop' : 'tasks';
  if (dayStage === 'work' && !firstTaskStarted) setObjective('');
  drawScreen();
}
function exitComputer(tryRelock = true) {
  inComputer = false;
  $('compExit').style.display = 'none';
  drawScreen();
  if (tryRelock) lockPointer();
  updateLockHint();
}

// ============================================================
// BOSS / AWAY MECHANIC
// ============================================================
let awayTime = 0, ringing = false, ringT = 0, ringBeepT = 0;
const BOSS_LINES = [
  '📞 "Hey, saw you went idle — just circling back!" You survived the boss call.',
  '📞 "Quick ping! You there? Great." The boss hangs up, suspicious.',
  '📞 "Do you have a sec? Never mind, keep grinding." Close one.',
];
function awayLimit() {
  // boss gets antsier as the day drags on
  return phase <= 1 ? 55 : phase === 2 ? 45 : 35;
}

// ============================================================
// GAME FLOW
// ============================================================
let started = false, gameOver = false;
let carrierOpen = false;
let tutorialDone = false;
let tutorialOpen = false;
let playClock = 0;            // seconds since this day's chaos began
let phase = 0;                // 0 = intro, then 1..3 progressive chaos
let riskT = 20;               // countdown to the next random "risk state"
let bowlFull = false;

// ---- the endless days ----
let day = 1;
let money = 0;
let dayStage = 'intro';       // intro (day-1 arrival) | morning (feed the cat) | work | evening (shop + bed)
let dayTasks = [];            // {key, label, pay, done, bob, st}
let curTaskI = -1;            // task currently on screen (-1 = none)
let comp = 'tasks';           // what the monitor shows: tasks | game | shop
let firstTaskStarted = false;
let heartsLostToday = 0, earnedToday = 0, vetToday = false, boughtToday = [];
let quietT = -1, quietDone = false;   // the "it's too quiet..." event
const adoptAnnounced = new Set();     // cat indexes whose shelter call already happened
let dayOvAction = null;
let overlayOpen = false;              // day-summary/vet dialog up → the whole sim freezes
$('dayOvBtn').onclick = () => {
  overlayOpen = false;
  $('dayOverlay').style.display = 'none';
  if (dayOvAction) { const f = dayOvAction; dayOvAction = null; f(); }
};

// generic two-button dialog (freezes the sim while open)
function showConfirm(title, text, yesLabel, noLabel, onYes, onNo = null) {
  overlayOpen = true;
  document.exitPointerLock();
  $('confirmTitle').textContent = title;
  $('confirmText').textContent = text;
  $('confirmYes').textContent = yesLabel;
  $('confirmNo').textContent = noLabel;
  $('confirmOverlay').style.display = 'flex';
  const close = () => { overlayOpen = false; $('confirmOverlay').style.display = 'none'; };
  $('confirmYes').onclick = () => { close(); if (onYes) onYes(); };
  $('confirmNo').onclick = () => { close(); if (onNo) onNo(); else lockPointer(); };
}

function daySetup() {
  makeDayTasks();
  playClock = 0; riskT = 20; firstTaskStarted = false;
  heartsLostToday = 0; earnedToday = 0; vetToday = false; boughtToday = [];
  quietDone = false; quietT = 90 + Math.random() * 120;
  tick.p2 = tick.p3 = false;
  bowlFull = false; bowlFood.visible = false;
  // overnight housekeeping: everything re-secured, barf mysteriously gone
  for (const h of Object.values(hazards)) {
    if (h.type === 'toggle') { h.armed = false; h.everFixed = false; applyToggleVis(h); }
    if (h.type === 'barf' && !h.cleaned) { h.cleaned = true; h.mesh.visible = false; scene.remove(h.mesh); }
  }
  // ...but somehow the cats unpacked every cupboard: stashed items are back out
  const hadStashed = Object.values(containers).some(b => b.used > 0);
  for (const h of Object.values(hazards)) {
    if (h.type === 'item' && !h.daily) {
      h.stashed = false;
      h.held = false;
      h.mesh.visible = true;
      h.mesh.position.copy(h.home);
      h.curSurface = h.surface || null;
    }
  }
  for (const b of Object.values(containers)) b.used = 0;
  if (hadStashed) msg('🙄 The cats unpacked everything you stashed. It\'s all back out.', 'danger');
  // deal out today's random traps — a fresh mix at fresh spots, on every floor
  const dailyPool = Object.values(hazards).filter(h => h.daily);
  for (const h of dailyPool) { h.stashed = true; h.held = false; h.mesh.visible = false; h.curSurface = null; }
  const todays = shuffled(dailyPool).slice(0, 3 + Math.min(day - 1, 3));
  const lvlOrder = shuffled([...LEVELS]);
  todays.forEach((h, i) => {
    const lvl = lvlOrder[i % lvlOrder.length];   // round-robin so every floor gets some
    const [x, z] = randomNavPoint(lvl);
    h.mesh.position.set(x, lvl, z);
    h.stashed = false;
    h.mesh.visible = true;
  });
  if (todays.length) msg('🪤 New hazards are lying around the house somewhere. The cats already know.', 'danger');
  // overnight deliveries
  for (const d of Object.values(distracts)) {
    if (d.pending) { d.pending = false; d.owned = true; d.mesh.visible = true; msg(`📦 Delivered overnight: ${d.label}!`, 'good'); }
  }
  for (const b of Object.values(containers)) {
    if (b.pending) { b.pending = false; b.owned = true; b.mesh.visible = true; msg(`📦 Installed overnight: the ${b.label}!`, 'good'); }
  }
  // overnight adoptions arrive hungry
  for (const a of pendingAdopts) {
    const chaos = CHAOS_LADDER[Math.min(cats.length, CHAOS_LADDER.length - 1)];
    makeCat(a.name, a.colorDef, chaos);
    msg(`🐈 ${a.name} has arrived! (chaos level: ${chaos.toFixed(1)}×)`, 'good');
  }
  pendingAdopts.length = 0;
  // cats wake up fresh, bored of nothing, and LOUDLY hungry in the kitchen
  for (const c of cats) {
    const s = c.state;
    s.distractUses = {}; s.distractId = null; s.full = 0; s.morningEat = false;
    s.mode = 'waitFood'; s.waypoints = []; s.idleT = 0;
    s.outside = false; s.outsideHaz = null;
    s.surf = null; s.afterHop = null; s.goAfterHop = null; s.perch = null;
    c.g.position.set(3.0 + Math.random() * 1.0, 0, -4.0 + Math.random() * 0.8);
    c.g.visible = true;
  }
  // you wake up in bed
  player.x = -5.2; player.y = 3; player.z = -3.2; player.yaw = -Math.PI / 2; player.pitch = 0.1;
  dayStage = 'morning';
  curTaskI = -1; comp = 'tasks';
  updateEcon();
  updateHearts();
  drawScreen();
  setObjective(`😾 ${catNamesJoined()} is meowing in the KITCHEN — go downstairs and fill the food bowl!`);
  msg(`☀ Day ${day}. The meowing started at 6am sharp.`);
  // the shelter calls when a new cat becomes available (adoption is free)
  if (catAvailable() && !adoptAnnounced.has(nextCatIdx())) {
    adoptAnnounced.add(nextCatIdx());
    showConfirm('🐈 The shelter called!',
      'Oh how cute — a new cat is available for adoption. Are you going to rescue it? (It\'s free. The chaos is also free.)',
      '🐈 RESCUE IT', 'MAYBE LATER',
      () => openAdopt());
  }
}

function goToSleep() {
  if (inComputer) exitComputer(false);
  document.exitPointerLock();
  // put down whatever (or whoever) you're carrying
  if (held) {
    if (!held.isCat) { held.held = false; held.mesh.visible = true; held.mesh.position.set(-5.6, 3.15, -2.6); }
    held = null;
    $('held').textContent = '';
  }
  // the cats settle down for the night too
  for (const c of cats) {
    endDanger(c, false);
    c.state.mode = 'distracted';
    c.state.distractT = 9999;
    c.state.distractId = null;
    c.state.waypoints = [];
  }
  const healed = Math.min(HEART_MAX - hearts, NIGHT_HEAL);
  hearts += healed;
  const doneAll = dayTasks.filter(t => t.done).length;
  const lines = [];
  lines.push(`💼 Tasks finished: ${doneAll}/${dayTasks.length}${dayTasks.some(t => t.bob && t.done) ? " (including Bob's!)" : ''}`);
  lines.push(`💰 Earned today: $${earnedToday} — wallet: $${money}`);
  lines.push(`💔 Hearts lost today: ${heartsLostToday}`);
  if (vetToday) lines.push('🏥 Emergency vet visit. It cost literally everything.');
  lines.push(healed > 0
    ? `😴 ${catNamesJoined()} slept 16 hours and recovered ${healed} heart${healed > 1 ? 's' : ''} (${hearts}/${HEART_MAX} ❤️)`
    : `😴 ${catNamesJoined()} slept 16 hours. Hearts already full (${hearts}/${HEART_MAX} ❤️)`);
  if (boughtToday.length) lines.push(`📦 Arriving tomorrow: ${boughtToday.map(d => d.label).join(', ')}`);
  $('dayOvTitle').textContent = `🌙 DAY ${day} COMPLETE`;
  $('dayOvTitle').style.color = '#ffb347';
  $('dayOvText').innerHTML = lines.join('<br>');
  $('dayOvBtn').textContent = `☀ WAKE UP — DAY ${day + 1}`;
  dayOvAction = () => { day++; daySetup(); if (!overlayOpen) lockPointer(); };
  overlayOpen = true;
  $('dayOverlay').style.display = 'flex';
  updateHearts();
}

function vetVisit(c) {
  if (vetToday) return;
  vetToday = true;
  const bill = money;
  money = 0;
  hearts = HEART_MAX;
  updateHearts(); updateEcon();
  if (inComputer) exitComputer(false);
  document.exitPointerLock();
  // in the panic you also cat-proofed the whole house
  for (const h of Object.values(hazards)) {
    if (h.type === 'toggle' && h.armed) { h.armed = false; applyToggleVis(h); }
  }
  for (const cc of cats) {
    endDanger(cc, false);
    cc.state.mode = 'wander'; cc.state.idleT = 6;
    cc.state.outside = false; cc.state.outsideHaz = null;
    cc.state.surf = null; cc.state.afterHop = null; cc.state.goAfterHop = null;
    if (nearestLevel(cc.g.position.y) !== cc.g.position.y) cc.g.position.y = nearestLevel(cc.g.position.y);
  }
  // the rest of the work day is a write-off — unfinished tasks pay nothing
  dayStage = 'evening';
  ringing = false; awayTime = 0; $('awayWarn').style.display = 'none';
  curTaskI = -1; comp = 'shop';
  $('dayOvTitle').textContent = '🏥 VET EMERGENCY';
  $('dayOvTitle').style.color = '#ff6b6b';
  $('dayOvText').innerHTML =
    `${c.name} was down to its LAST heart. You dropped everything, grabbed the carrier, and RAN.<br><br>` +
    `The vet fixed everything. The bill came to <b>$${bill}</b> — mysteriously, the exact amount of money you had.<br><br>` +
    `${c.name} is back to ${HEART_MAX}/${HEART_MAX} hearts and back to plotting. The work day is a write-off. Go home and sleep.`;
  $('dayOvBtn').textContent = '🐈 TAKE KITTY HOME';
  dayOvAction = () => { setObjective('🛏 Exhausted. Go UPSTAIRS and click your BED to sleep.'); lockPointer(); };
  overlayOpen = true;
  $('dayOverlay').style.display = 'flex';
}

// ---- start screen wiring ----
let chosenColor = CAT_COLORS[0];
{
  const chipBox = $('nameChips');
  for (const n of NAME_POOL.slice(0, 6)) {
    const s = document.createElement('span');
    s.className = 'chip'; s.textContent = n;
    s.onclick = () => { $('catName').value = n; };
    chipBox.appendChild(s);
  }
  const colorRow = $('colorRow');
  CAT_COLORS.forEach((cd, i) => {
    const s = document.createElement('div');
    s.className = 'swatch' + (i === 0 ? ' sel' : '');
    s.style.background = '#' + cd.body.toString(16).padStart(6, '0');
    s.onclick = () => {
      chosenColor = cd;
      colorRow.querySelectorAll('.swatch').forEach(el => el.classList.remove('sel'));
      s.classList.add('sel');
    };
    colorRow.appendChild(s);
  });
}

$('startBtn').onclick = () => {
  const name = ($('catName').value.trim() || 'Whiskers').slice(0, 14);
  makeCat(name, chosenColor, CHAOS_LADDER[0]);   // more cats can be adopted from the shop
  $('startScreen').style.display = 'none';
  $('hud').style.display = 'block';
  started = true;
  audio();
  makeDayTasks();
  updateHearts();
  updateEcon();
  drawScreen();
  lockPointer();
  setObjective(`📦 Set ${catNamesJoined()} free — walk up and click the carrier`);
  msg('You just got home from the shelter. The carrier is meowing.', '');
};
renderer.domElement.addEventListener('click', () => {
  if (started && !inComputer && !pointerLocked && !gameOver && !tutorialOpen && !paused && !adoptOpen) lockPointer();
});

function openCarrier() {
  if (carrierOpen) { msg('The carrier is empty now. It still smells like adventure.'); return; }
  carrierOpen = true;
  carrierDoor.rotation.y = -1.9;
  msg('You open the carrier door...', 'good');
  cats.forEach((c, i) => {
    setTimeout(() => {
      if (gameOver) return;
      c.g.visible = true;
      c.g.position.set(-0.6, 0, 1.05);
      c.state.mode = 'walk';
      c.state.nextMode = 'introSit';
      // kittens toddle out toward the player and sit looking up
      c.state.waypoints = [[-0.5 + (i - (cats.length - 1) / 2) * 0.85, 0.65 - (i % 2) * 0.25]];
      meow(0.5, 1.25 + i * 0.12);
      if (i > 0) msg(`${c.name} pads out after ${cats[0].name}.`, '');
      else msg(`${c.name} wobbles out and stretches. Heart rate: -20%.`, 'good');
    }, 600 + i * 1000);
  });
  setTimeout(() => {
    if (gameOver) return;
    msg(`"Alright ${catNamesJoined()}, time for me to get some work done. Be good!"`, 'talk');
    showTutorial();
  }, 1400 + cats.length * 1000);
}
function showTutorial() {
  tutorialOpen = true;
  document.exitPointerLock();
  $('tutTitle').textContent = `Welcome home, ${catNamesJoined()}!`;
  $('tutorial').style.display = 'flex';
  updateLockHint();
}
$('tutBtn').onclick = () => {
  tutorialOpen = false;
  tutorialDone = true;
  dayStage = 'work';
  $('tutorial').style.display = 'none';
  lockPointer();
  setObjective('💻 Go to the OFFICE and click the computer — today\'s tasks are on it');
  // phase 1 starter dangers: the ribbon toy is already out; open the toilet lid
  const t = hazards['toilet1'];
  t.armed = true;
  applyToggleVis(t);
  cats.forEach((c, i) => {
    if (c.state.mode === 'introSit' || c.state.mode === 'walk') {
      c.state.mode = 'wander';
      c.state.idleT = 3 + i * 2.5;
    }
  });
  updateLockHint();
};

function endGame() {   // there is only one way to lose now: getting fired
  if (gameOver) return;
  gameOver = true;
  document.exitPointerLock();
  $('compExit').style.display = 'none';
  $('lockHint').style.display = 'none';
  $('endScreen').style.display = 'flex';
  const first = cats[0] ? cats[0].name : 'the cat';
  $('endTitle').textContent = '📞 YOU\'RE FIRED';
  $('endTitle').style.color = '#ff6b6b';
  $('endText').textContent = `You didn't answer the boss's call. HR has been looped in. You survived ${day} day${day > 1 ? 's' : ''} and saved $${money}. ${first}, at least, looks pleased — you can play with cats full-time now.`;
}

// ============================================================
// INTERACTION (click handling)
// ============================================================
function treeVisible(o) {
  while (o) { if (o.visible === false) return false; o = o.parent; }
  return true;
}
function aimedObject() {
  raycaster.setFromCamera(new THREE.Vector2(0, 0), camera);
  const hits = raycaster.intersectObjects(interactables.filter(o => o.parent && treeVisible(o)), false);
  for (const h of hits) {
    if (h.distance > 3.0) break;
    return h.object;
  }
  // also allow clicking cat parts via group
  for (const c of cats) {
    if (!c.g.visible) continue;
    const catHits = raycaster.intersectObject(c.g, true);
    if (catHits.length && catHits[0].distance < 3.4) return c.body;
  }
  return null;
}

renderer.domElement.addEventListener('mousedown', e => {
  if (!started || gameOver || inComputer || !pointerLocked || paused) return;
  if (e.button === 2) { // drop
    if (held) dropHeld();
    return;
  }
  if (e.button !== 0) return;
  const obj = aimedObject();

  // laser pointer: click floor/nothing while holding it
  if (held && !held.isCat && held.id === 'laser' && (!obj || obj.userData.act === undefined)) {
    fireLaser();
    return;
  }
  if (!obj) return;
  const u = obj.userData;

  switch (u.act) {
    case 'carrier': {
      openCarrier();
      return;
    }
    case 'computer': {
      if (!carrierOpen) { msg('Let the kitten out of the carrier first!'); return; }
      if (!tutorialDone) return;
      if (held && held.isCat) { msg('You can\'t type while holding a cat. (It would love that though.)'); return; }
      const d = camera.position.distanceTo(new THREE.Vector3(-6.9, 1.5, -3.35));
      if (d < 3.2) enterComputer();
      return;
    }
    case 'phone': {
      if (ringing) {
        ringing = false; ringT = 0; awayTime = 0;
        $('awayWarn').style.display = 'none';
        bossSay(BOSS_LINES[Math.floor(Math.random() * BOSS_LINES.length)]);
      } else msg('The phone is quiet. Ominously quiet.');
      return;
    }
    case 'toggle': {
      const h = hazards[u.id];
      if (h.needTool && h.armed) {
        const holdingTool = held && !held.isCat && held.id === h.needTool;
        if (!holdingTool) { msg(h.needToolHint, 'danger'); return; }
      }
      if (h.armed) {
        h.armed = false;
        h.everFixed = true;
        applyToggleVis(h);
        msg(`✔ ${h.name} — safe now.`, 'good');
        for (const c of cats) {
          if ((c.state.mode === 'danger' || c.state.mode === 'walk') && c.state.target === h.id) endDanger(c);
          if (c.state.outsideHaz === h.id) msg(`...but ${c.name} is still outside! Click it to bring it in.`, 'danger');
        }
      } else {
        msg(h.armHint || 'Already safe.');
      }
      return;
    }
    case 'item': {
      if (held) { msg('Your hands are full. Right-click to drop.'); return; }
      pickUpItem(hazards[u.id]);
      return;
    }
    case 'container': {
      const box = containers[u.id];
      if (held && !held.isCat && !held.safeItem) {
        if (box.used >= box.cap) { msg(`The ${box.label} is FULL (max ${box.cap}). Find somewhere else.`, 'danger'); return; }
        box.used++;
        stashHeld(box.label);
      } else if (held && !held.isCat && held.safeItem) {
        msg('That\'s a tool, keep it or drop it (right-click).');
      } else {
        msg(`The ${box.label}. Cat-proof storage (${box.used}/${box.cap} used).`);
      }
      return;
    }
    case 'distract': {
      distractCat(u.id);
      if (u.id === 'treats') beep(1300, 0.15, 0.1, 'triangle');
      return;
    }
    case 'bowl': {
      fillBowl();
      return;
    }
    case 'bed': {
      if (dayStage === 'evening') {
        const buyable = shopCatalog().filter(it => !it.pending && !it.locked && it.price <= money);
        if (buyable.length) {
          showConfirm('🛒 Wait — the shop is still open',
            `Are you sure you don't want to buy anything else for your cat? You have $${money}, and there ${buyable.length === 1 ? 'is 1 thing' : 'are ' + buyable.length + ' things'} you can afford.`,
            '🛏 SLEEP ANYWAY', '🛒 KEEP SHOPPING',
            () => goToSleep());
        } else goToSleep();
      }
      else if (dayStage === 'morning') msg('No going back to bed — the cat is starving (allegedly).');
      else msg('No napping. You have work to do.');
      return;
    }
    case 'barf': {
      const h = hazards[u.id];
      h.cleaned = true;
      h.mesh.visible = false;
      interactables.splice(interactables.indexOf(h.mesh), 1);
      scene.remove(h.mesh);
      for (const c of cats) if (c.state.target === h.id) endDanger(c);
      msg('You cleaned up the barf. Peak work-from-home experience.', 'good');
      return;
    }
    case 'cat': {
      if (held) { msg('Hands full! Right-click to drop first.'); return; }
      pickUpCat(u.catRef);
      return;
    }
  }
});
addEventListener('contextmenu', e => e.preventDefault());

function fillBowl() {
  if (bowlFull) { msg('The bowl is already full.'); return; }
  bowlFull = true; bowlFood.visible = true;
  // hungry cats come running at the sound of the bowl (busy/full cats don't)
  for (const c of cats) {
    const s = c.state;
    if (s.full > 0) continue;
    if (s.mode === 'wander' || (s.mode === 'walk' && s.nextMode === 'wanderIdle'))
      catGoTo(c, bowl.position.x, 0, bowl.position.z, 'eating');
  }
  if (dayStage === 'morning') {
    // filling the bowl IS feeding the cats — the work day unlocks right away
    dayStage = 'work';
    setObjective('💻 Cats fed! Get to the OFFICE computer and pick a task.');
    msg('Breakfast is served. Blessed silence incoming.', 'good');
  }
  else if (cats.some(c => c.state.full > 0)) msg('You filled the bowl... but somebody just ate. Overfeeding is a hazard!', 'danger');
  else msg('You filled the food bowl.', 'good');
}

function pickUpItem(h) {
  held = h;
  h.held = true;
  h.mesh.visible = false;
  $('held').textContent = `🤚 Holding: ${h.label}` + (h.safeItem ? '' : ' — stash it in a cupboard/drawer/chest/shelf');
  if (h.id === 'laser') $('held').textContent = '🤚 Holding: laser pointer — left-click the floor to lure the cats';
  if (h.id === 'screwdriver') $('held').textContent = '🤚 Holding: screwdriver — use it on the loose air vent';
  for (const c of cats)
    if ((c.state.mode === 'danger' || c.state.mode === 'walk') && c.state.target === h.id) endDanger(c);
}
function dropHeld() {
  if (held && held.isCat) { dropCatAt(); return; }
  const h = held;
  held = null;
  $('held').textContent = '';
  h.held = false;
  // aiming at a surface? set the item ON it instead of dumping it on the floor
  // (mesh stays invisible during the raycast so the ray can't hit the item itself)
  raycaster.setFromCamera(new THREE.Vector2(0, 0), camera);
  const hits = raycaster.intersectObjects(scene.children, true);
  let placed = false;
  for (const hit of hits) {
    if (hit.distance > 3.0) break;
    const o = hit.object;
    if (!o.isMesh || o.material === HIT_MAT || !treeVisible(o)) continue;
    let isCatPart = false;
    for (let p = o; p; p = p.parent) if (p.userData && p.userData.catRef) { isCatPart = true; break; }
    if (isCatPart || !hit.face) continue;
    const n = hit.face.normal.clone().transformDirection(o.matrixWorld);
    if (n.y < 0.5) continue;   // only tops of things count as surfaces
    const p = hit.point;
    h.mesh.position.set(p.x, p.y + 0.03, p.z);
    const hgt = p.y - nearestLevel(p.y);
    if (hgt > 0.25) {
      // elevated — remember the surface so cats hop up to it from the player's side
      let ax = player.x - p.x, az = player.z - p.z;
      const d = Math.hypot(ax, az) || 1;
      h.curSurface = { x: p.x, z: p.z, h: hgt, ax: ax / d * 1.1, az: az / d * 1.1 };
      if (!h.safeItem) msg(`You set the ${h.label} up there. The cats saw you do it.`, 'danger');
    } else {
      h.curSurface = null;
      if (!h.safeItem) msg(`You dropped the ${h.label}. It is once again a cat magnet.`, 'danger');
    }
    placed = true;
    break;
  }
  if (!placed) {
    const dir = new THREE.Vector3();
    camera.getWorldDirection(dir);
    const px = player.x + dir.x * 0.9, pz = player.z + dir.z * 0.9;
    h.mesh.position.set(px, groundY(px, pz, player.y) + 0.15, pz);
    h.curSurface = null;
    if (!h.safeItem) msg(`You dropped the ${h.label}. It is once again a cat magnet.`, 'danger');
  }
  h.mesh.visible = true;
}
function stashHeld(containerLabel) {
  const h = held;
  held = null;
  $('held').textContent = '';
  h.stashed = true;
  h.held = false;
  msg(`✔ ${h.label} stashed in the ${containerLabel}. Permanently cat-proofed.`, 'good');
}
function pickUpCat(c) {
  const d = camera.position.distanceTo(c.g.position);
  if (d > 3.4) return;
  if (c.state.noHoldT > 0) {
    msg(`😾 ${c.name} is not in the mood to be held right now. (${Math.ceil(c.state.noHoldT)}s)`);
    return;
  }
  if (c.state.mode === 'hiddenNap') {
    msg(`😌 There you are! ${c.name} was just asleep in ${roomName(c.g.position.x, c.g.position.y, c.g.position.z)}. False alarm.`, 'good');
  }
  endDanger(c, false);
  held = c;
  c.state.mode = 'held';
  c.state.heldT = 12;
  c.state.squirmWarned = false;
  c.state.outside = false; c.state.outsideHaz = null;
  c.state.surf = null; c.state.afterHop = null; c.state.goAfterHop = null;
  $('held').textContent = `🤚 Holding: ${c.name.toUpperCase()} (purring). Right-click to put down (bonus: drop it on the cat bed).`;
  msg(`You scooped up ${c.name}. It is furious and also purring.`, 'good');
  meow(0.4, 1.6);
}
function dropCatAt() {
  const c = held;
  held = null;
  $('held').textContent = '';
  const dir = new THREE.Vector3();
  camera.getWorldDirection(dir);
  const px = player.x + dir.x * 0.8, pz = player.z + dir.z * 0.8;
  c.g.position.set(px, groundY(px, pz, player.y), pz);
  if (c.g.position.distanceTo(catBed.position) < 1.2) {
    const d = distracts['bed'];
    const t = Math.max(DISTRACT_MIN, distractTime(c, d) + 7); // hand-delivery bonus
    c.state.distractUses['bed'] = (c.state.distractUses['bed'] || 0) + 1;
    c.state.mode = 'distracted';
    c.state.distractT = t;
    c.state.distractId = 'bed';
    c.state.waypoints = [];
    msg(`${c.name} curls up in the bed. ${Math.round(t)} blissful seconds of productivity.`, 'good');
    return;
  }
  // dropped onto furniture? set the cat ON TOP of it, settled and facing the room
  const lvl = nearestLevel(player.y);
  for (const p of PERCHES) {
    if (p.lvl !== lvl || Math.hypot(px - p.x, pz - p.z) > (p.r || 0.9)) continue;
    c.g.position.set(px, lvl + p.h, pz);
    c.g.rotation.y = faceRoomYaw(p);
    c.state.mode = 'perched';
    c.state.perch = p;
    c.state.perchT = 10 + Math.random() * 15;
    c.state.idlePose = Math.random() < 0.55 ? 'sit' : 'loaf';
    c.state.waypoints = [];
    msg(`${c.name} settles on the ${p.name}.`, 'good');
    return;
  }
  if (bowlFull && c.state.full <= 0) {
    // still hungry — heads straight back to breakfast instead of sulking
    catGoTo(c, bowl.position.x, 0, bowl.position.z, 'eating');
    return;
  }
  c.state.mode = 'wander';
  c.state.idleT = 1.5;
}
function fireLaser() {
  raycaster.setFromCamera(new THREE.Vector2(0, 0), camera);
  const dir = raycaster.ray.direction;
  const floorY = nearestLevel(player.y);
  const t = (floorY + 0.03 - camera.position.y) / dir.y;
  if (t > 0 && t < 20) {
    const p = camera.position.clone().addScaledVector(dir, t);
    laserDot.position.copy(p);
    laserT = 8;
    for (const c of cats) {
      const m = c.state.mode;
      if (m === 'held' || m === 'carrier' || m === 'outside' || m === 'hiddenNap' || m === 'waitFood' || m === 'eating' || m === 'hop') continue;
      endDanger(c, false);
      catGoTo(c, p.x, floorY, p.z, 'distracted');
      c.state.distractT = 8;
      c.state.distractId = 'laser';
    }
    msg('The red dot. The cats MUST have the red dot.', 'good');
  }
}

// ============================================================
// HINT (what you're looking at)
// ============================================================
function updateHint() {
  const el = $('hint');
  if (inComputer || gameOver || !pointerLocked) { el.style.display = 'none'; return; }
  const obj = aimedObject();
  if (!obj) { el.style.display = 'none'; return; }
  const u = obj.userData;
  let text = '';
  if (u.act === 'carrier') text = carrierOpen ? 'the (empty) cat carrier' : '📦 Click — open the carrier';
  else if (u.act === 'computer') text = dayStage === 'evening' ? 'Click — open the SHOP' : 'Click — get to work';
  else if (u.act === 'phone') text = ringing ? 'ANSWER THE PHONE!' : 'desk phone';
  else if (u.act === 'toggle') { const h = hazards[u.id]; text = h.armed ? '⚠ ' + h.fixHint : (h.armHint || 'safe'); }
  else if (u.act === 'item') { const h = hazards[u.id]; text = 'Pick up: ' + h.label; }
  else if (u.act === 'container') {
    const box = containers[u.id];
    text = held && !held.isCat && !held.safeItem
      ? (box.used >= box.cap ? `${box.label} — FULL (${box.used}/${box.cap})` : `Stash the ${held.label} here (${box.used}/${box.cap})`)
      : `${box.label} (${box.used}/${box.cap})`;
  }
  else if (u.act === 'distract') text = 'Distract the cats: ' + u.label;
  else if (u.act === 'bed') text = dayStage === 'evening' ? `🛏 Click — SLEEP (end day ${day})` : 'your bed (no naps allowed)';
  else if (u.act === 'bowl') text = bowlFull ? 'Food bowl (full)'
    : dayStage === 'morning' ? '🍽 FEED THE CAT — fill the bowl'
    : 'Fill the food bowl' + (cats.some(c => c.state.full > 0) ? ' — kitty is FULL, careful' : '');
  else if (u.act === 'barf') text = 'Clean up the barf 🤢';
  else if (u.act === 'cat') {
    const c = u.catRef;
    text = (c.state.mode === 'danger' || c.state.mode === 'outside') ? `RESCUE ${c.name.toUpperCase()}!`
         : c.state.mode === 'hiddenNap' ? `😴 found ${c.name}!`
         : `Pick up ${c.name}`;
  }
  el.textContent = text;
  el.style.display = text ? 'block' : 'none';
}

// ============================================================
// MAIN LOOP
// ============================================================
let last = performance.now();
let scrRedrawT = 0;
function tick(now) {
  requestAnimationFrame(tick);
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (!started || gameOver || paused || overlayOpen) { renderer.render(scene, camera); return; }

  // ----- clocks & phases (later days start meaner) -----
  if (tutorialDone) playClock += dt;
  phase = !tutorialDone ? 0
        : day === 1 ? (playClock < 160 ? 1 : playClock < 460 ? 2 : 3)
        : day === 2 ? (playClock < 300 ? 2 : 3)
        : 3;
  if (phase === 2 && !tick.p2) { tick.p2 = true; msg('😼 The cats are getting bolder. Watch the stairs.', 'danger'); }
  if (phase === 3 && !tick.p3) { tick.p3 = true; msg('🔥 Full chaos hours. Everything is a hazard now.', 'danger'); }

  // ----- player movement (works even without pointer lock, so ESC never strands you) -----
  if (!inComputer && !tutorialOpen) {
    const sp = (keys['ShiftLeft'] ? 5.4 : 3.6) * dt;
    let fx = 0, fz = 0;
    const sin = Math.sin(player.yaw), cos = Math.cos(player.yaw);
    if (keys['KeyW']) { fx += sin * -1; fz += cos * -1; }
    if (keys['KeyS']) { fx += sin; fz += cos; }
    if (keys['KeyA']) { fx += -cos; fz += sin; }
    if (keys['KeyD']) { fx += cos; fz += -sin; }
    const len = Math.hypot(fx, fz);
    if (len > 0) {
      let nx = player.x + (fx / len) * sp;
      let nz = player.z + (fz / len) * sp;
      [nx, nz] = collideR(nx, nz, player.y, PLAYER_R);
      nx = Math.max(-7.8, Math.min(7.8, nx));
      nz = Math.max(-5.8, Math.min(5.8, nz));
      player.x = nx; player.z = nz;
    }
    const gy = groundY(player.x, player.z, player.y);
    player.y += (gy - player.y) * Math.min(1, dt * 14);
  }
  // camera: blend between first-person and the monitor close-up
  const target = inComputer ? 1 : 0;
  compBlend += (target - compBlend) * Math.min(1, dt * 5);
  if (Math.abs(compBlend - target) < 0.002) compBlend = target;
  const pPos = new THREE.Vector3(player.x, player.y + EYE, player.z);
  const pQuat = new THREE.Quaternion().setFromEuler(new THREE.Euler(player.pitch, player.yaw, 0, 'YXZ'));
  const t01 = compBlend * compBlend * (3 - 2 * compBlend); // smoothstep
  camera.position.lerpVectors(pPos, compCamPos, t01);
  camera.quaternion.slerpQuaternions(pQuat, compCamQuat, t01);
  $('crosshair').style.display = inComputer ? 'none' : 'block';

  // ----- away / boss (only while on the clock) -----
  if (dayStage === 'work' && firstTaskStarted && !inComputer) {
    awayTime += dt;
    if (!ringing && awayTime > awayLimit()) {
      ringing = true; ringT = 0;
      $('awayWarn').style.display = 'block';
      bossSay('📞 Your status went AWAY. The boss is calling your desk phone!');
    }
  }
  if (ringing) {
    ringT += dt; ringBeepT -= dt;
    if (ringBeepT <= 0) {
      const d = camera.position.distanceTo(phoneMesh.position);
      beep(1150, 0.25, Math.min(0.3, 1.6 / (1 + d * 0.35)));
      ringBeepT = 0.7;
    }
    if (ringT > RING_LIMIT) { endGame(); return; }
  }

  // ----- "...it's too quiet" (from day 2 on, once per day) -----
  if (dayStage === 'work' && firstTaskStarted && day >= 2 && !quietDone) {
    quietT -= dt;
    if (quietT <= 0) {
      const cands = cats.filter(c => c.state.mode === 'wander' || c.state.mode === 'walk');
      if (cands.length) {
        quietDone = true;
        const c = pick(cands);
        const lvl = LEVELS[Math.floor(Math.random() * LEVELS.length)];
        const [x, z] = randomNavPoint(lvl);
        catGoTo(c, x, lvl, z, 'hiddenNap');
        msg(`🤫 ...it's too quiet. TOO quiet. What is ${c.name} doing?`, 'danger');
      } else quietT = 20;
    }
  }

  // ----- random risk states (paced hazard arming) -----
  if (dayStage === 'work' && firstTaskStarted) {
    riskT -= dt;
    if (riskT <= 0) {
      const [rMin, rMax] = riskWindow();
      riskT = rMin + Math.random() * (rMax - rMin) - (phase - 1) * 4;
      const cap = (phase === 1 ? 2 : phase === 2 ? 4 : 8) + (cats.length - 1);
      const toggles = Object.values(hazards).filter(h => h.type === 'toggle');
      const armedCount = toggles.filter(h => h.armed).length;
      const cands = toggles.filter(h => !h.armed && (h.tier || 99) <= phase && (h.rearm || !h.everFixed));
      if (armedCount < cap && cands.length) {
        const h = cands[Math.floor(Math.random() * cands.length)];
        h.armed = true;
        applyToggleVis(h);
        msg('⚠ ' + (h.armMsg || `The ${h.name} is a hazard again!`), 'danger');
        msg(`(coming from ${roomName(h.mesh.position.x, h.mesh.position.y, h.mesh.position.z)})`, '');
      }
    }
  }

  // ----- bowl / fullness / barf -----
  for (const c of cats) if (c.state.full > 0) c.state.full -= dt;
  for (let i = barfPendings.length - 1; i >= 0; i--) {
    barfPendings[i].t -= dt;
    if (barfPendings[i].t <= 0) {
      const p = barfPendings[i].pos;
      spawnBarf(p.x, nearestLevel(p.y), p.z);
      barfPendings.splice(i, 1);
    }
  }

  // ----- laser -----
  if (laserT > 0) { laserT -= dt; if (laserT <= 0) laserDot.position.y = -99; }

  // ----- cats -----
  for (const c of cats) updateCat(c, dt);

  // ----- meow loop (3D-ish: louder when closer) -----
  meowLoopT -= dt;
  if (meowLoopT <= 0) {
    meowLoopT = 2.1;
    for (const c of cats) {
      if (c.state.mode === 'danger' || c.state.mode === 'outside' || c.state.mode === 'waitFood') {
        const d = c.g.position.distanceTo(camera.position);
        meow(Math.min(1, 2.2 / (1 + d * 0.45)), c.state.mode === 'waitFood' ? 1.15 : 1);
      }
    }
  }

  // ----- cat status lines -----
  const parts = [];
  for (const c of cats) {
    const m = c.state.mode;
    if (m === 'danger') parts.push(`😿 ${c.name}: meowing from ${roomName(c.g.position.x, c.g.position.y, c.g.position.z)}`);
    else if (m === 'outside') parts.push(`🙀 ${c.name} IS OUTSIDE!`);
    else if (m === 'distracted') parts.push(`😸 ${c.name}: happily distracted`);
    else if (m === 'held') parts.push(`😻 ${c.name} (purring)`);
    else if (m === 'pester') parts.push(`😼 ${c.name} wants YOUR attention`);
    else if (m === 'waitFood') parts.push(`🍽 ${c.name} is HUNGRY — fill the food bowl!`);
    else if (m === 'hiddenNap') parts.push(`🤫 ${c.name}: ...suspiciously quiet. Go find it.`);
  }
  $('catStatus').innerHTML = parts.join('<br>');

  // ----- computer screen refresh -----
  if (inComputer) {
    const blocked = catBlockingKeyboard();
    scrRedrawT -= dt;
    if (blocked !== screenBlocked || scrRedrawT <= 0) {
      screenBlocked = blocked;
      scrRedrawT = 0.5;
      drawScreen();
    }
  }

  updateHint();
  renderer.render(scene, camera);
}

function updateCat(c, dt) {
  const s = c.state;
  animateCat(c);
  if (s.noHoldT > 0) s.noHoldT -= dt;

  if (s.mode === 'carrier' || s.mode === 'introSit') return;

  if (s.mode === 'hop') {
    s.hopT += dt;
    const k = Math.min(1, s.hopT / s.hopDur);
    c.g.position.x = s.hopFrom.x + (s.hopTo.x - s.hopFrom.x) * k;
    c.g.position.z = s.hopFrom.z + (s.hopTo.z - s.hopFrom.z) * k;
    c.g.position.y = s.hopFrom.y + (s.hopTo.y - s.hopFrom.y) * k + Math.sin(Math.PI * k) * 0.4;
    if (k >= 1) {
      if (s.goAfterHop) {            // landed on the floor — resume the deferred trip
        const g2 = s.goAfterHop;
        s.goAfterHop = null;
        catGoTo(c, g2.x, g2.y, g2.z, g2.nextMode, g2.targetId);
        return;
      }
      if (s.afterHop) {              // landed up on a surface — start the planned activity
        const a = s.afterHop;
        s.afterHop = null;
        s.surf = a.sf;
        if (a.mode === 'danger') {
          const h = hazards[a.target];
          if (hazardArmed(h)) {
            enterDanger(c, h);
            const p = h.mesh.position;   // face the thing it's messing with
            c.g.rotation.y = Math.atan2(-(p.z - c.g.position.z), p.x - c.g.position.x);
          } else dismountThenWander(c);
        } else {                     // 'distracted' — timer/id already set by distractCat
          s.mode = 'distracted';
          c.g.rotation.y = faceRoomYaw(a.sf);
        }
        return;
      }
      if (s.hopUpward) {
        s.mode = 'perched';
        s.perchT = 8 + Math.random() * 14;
        s.idlePose = Math.random() < 0.55 ? 'sit' : 'loaf';
        if (s.perch) c.g.rotation.y = faceRoomYaw(s.perch);  // settle facing the room
      } else {
        s.mode = 'wander';
        s.idleT = 1.5;
      }
    }
    return;
  }

  if (s.mode === 'perched') {
    s.perchT -= dt;
    if (s.perchT <= 0 && s.perch) {
      const lvl = nearestLevel(c.g.position.y);
      startHop(c, { x: s.perch.x + s.perch.ax, y: lvl, z: s.perch.z + s.perch.az }, false);
    }
    return;
  }

  if (s.mode === 'held') {
    s.heldT -= dt;
    if (s.heldT <= 3 && !s.squirmWarned) {
      s.squirmWarned = true;
      msg(`😾 ${c.name} is getting squirmy...`);
    }
    if (s.heldT <= 0) {
      // the cat has decided it is DONE being held
      held = null;
      $('held').textContent = '';
      const dir = new THREE.Vector3();
      camera.getWorldDirection(dir);
      const px = player.x + dir.x * 0.7, pz = player.z + dir.z * 0.7;
      c.g.position.set(px, groundY(px, pz, player.y), pz);
      s.mode = 'wander';
      s.idleT = 1.5;
      s.noHoldT = 20;
      msg(`🐈 ${c.name} squirmed out of your arms! It needs some space now.`, 'danger');
      meow(0.5, 1.4);
      return;
    }
    const dir = new THREE.Vector3();
    camera.getWorldDirection(dir);
    c.g.position.set(camera.position.x + dir.x * 0.6, camera.position.y - 0.7, camera.position.z + dir.z * 0.6);
    c.g.rotation.y = player.yaw + Math.PI / 2;
    return;
  }

  if (s.mode === 'outside') {
    s.hurtT -= dt;
    if (s.hurtT <= 0) {
      s.hurtT = 8;
      hurtCat(c, s.outsideText || 'The cat is having adventures outside. Bad ones.');
    }
    return;
  }

  if (s.mode === 'walk') {
    const wp = s.waypoints[0];
    if (!wp) {
      // arrived
      const nm = s.nextMode;
      if (nm === 'introSit') {
        s.mode = 'introSit';
      } else if (nm === 'danger') {
        const h = hazards[s.target];
        if (hazardArmed(h)) {
          const sf = h.curSurface;
          if (sf) {   // the trouble is up on a surface — jump onto it first
            s.afterHop = { mode: 'danger', target: s.target, sf };
            startHop(c, { x: sf.x, y: nearestLevel(c.g.position.y) + sf.h, z: sf.z }, true);
          } else enterDanger(c, h);
        } else { s.mode = 'wander'; s.idleT = 1; }
      } else if (nm === 'eating') {
        if (bowlFull) {
          s.mode = 'eating';
          s.eatT = 3.5;
        } else { s.mode = 'wander'; s.idleT = 1; }
      } else if (nm === 'distracted') {
        const d = s.distractId ? distracts[s.distractId] : null;
        const sf = d && d.surface;
        if (sf) {
          s.afterHop = { mode: 'distracted', sf };
          startHop(c, { x: sf.x, y: nearestLevel(c.g.position.y) + sf.h, z: sf.z }, true);
        } else s.mode = 'distracted';
      } else if (nm === 'hiddenNap') {
        s.mode = 'hiddenNap';
        s.napT = 75;
      } else if (nm === 'pester') {
        s.mode = 'pester';
        s.pesterT = 12;
        msg(`😼 ${c.name} has arrived to help you type.`, 'danger');
      } else if (nm === 'hopUp' && s.perch) {
        const lvl = nearestLevel(c.g.position.y);
        startHop(c, { x: s.perch.x, y: lvl + s.perch.h, z: s.perch.z }, true);
      } else {
        s.mode = 'wander';
        s.idleT = 2 + Math.random() * 3;
        s.idlePose = pickIdlePose();
      }
      return;
    }
    const [tx, tz] = wp;
    const dx = tx - c.g.position.x, dz = tz - c.g.position.z;
    const d = Math.hypot(dx, dz);
    const arriveR = s.waypoints.length === 1 ? 0.45 : 0.3;
    if (d < arriveR) { s.waypoints.shift(); s.stuckT = 0; return; }
    const tension = Math.min(1, playClock / 540);
    const sp = c.speed * (1 + tension * 0.4) * dt;
    let nx = c.g.position.x + (dx / d) * sp;
    let nz = c.g.position.z + (dz / d) * sp;
    [nx, nz] = collideCat(nx, nz, c.g.position.y);
    const moved = Math.hypot(nx - c.g.position.x, nz - c.g.position.z);
    if (moved < sp * 0.35) {
      s.stuckT += dt;
      if (s.stuckT > 2.5) { s.waypoints.shift(); s.stuckT = 0; return; } // squeeze past — never wedge forever
      if (s.stuckT > 1.2 && !s.repathed && s.dest) {
        // wedged on a corner — recompute the whole route from where we actually are
        s.repathed = true;
        s.waypoints = routeTo(c, s.dest.x, s.dest.y, s.dest.z);
        return;
      }
    } else { s.stuckT = 0; s.repathed = false; }
    c.g.position.x = nx;
    c.g.position.z = nz;
    c.g.position.y = groundY(c.g.position.x, c.g.position.z, c.g.position.y);
    c.g.rotation.y = Math.atan2(-dz, dx);
    c.g.position.y += Math.abs(Math.sin(performance.now() * 0.012 + c.chaos * 5)) * 0.04;
    return;
  }

  if (s.mode === 'danger') {
    s.hurtT -= dt;
    s.dangerAge += dt;
    const h = hazards[s.target];
    if (!hazardArmed(h)) { endDanger(c); return; }
    if (s.hurtT <= 0) {
      s.hurtT = 7;
      hurtCat(c, h.dangerText);
      s.heartsLostHere = (s.heartsLostHere || 0) + 1;
      if (s.heartsLostHere >= 2 && !h.isWindow) {
        msg(`😾 ${c.name} got bored of that particular near-death experience and wandered off.`, '');
        dismountThenWander(c);
        s.idleT = 4;
        return;
      }
    }
    // windows: after a while the cat actually gets out
    if (h.isWindow && s.dangerAge > 10 && !s.outside) {
      s.mode = 'outside';
      s.outside = true;
      s.outsideHaz = h.id;
      s.outsideText = h.outsideText;
      s.hurtT = 8;
      c.g.position.copy(h.outsidePos);
      msg('🙀 ' + pers(h.outsideText, c) + ' Go to the window and grab it!', 'danger');
    }
    return;
  }

  if (s.mode === 'waitFood') {
    // parked by the bowl, yelling, until breakfast appears
    if (bowlFull) {
      s.morningEat = true;
      catGoTo(c, bowl.position.x, 0, bowl.position.z, 'eating');
    }
    return;
  }

  if (s.mode === 'hiddenNap') {
    s.napT -= dt;
    const d = Math.hypot(c.g.position.x - player.x, c.g.position.z - player.z);
    if (d < 2.6 && Math.abs(c.g.position.y - player.y) < 1.6) {
      msg(`😌 Found ${c.name} — fast asleep in ${roomName(c.g.position.x, c.g.position.y, c.g.position.z)}. False alarm.`, 'good');
      s.mode = 'distracted';
      s.distractT = 25;
      s.distractId = null;
    } else if (s.napT <= 0) {
      msg(`${c.name} woke up from a secret nap somewhere. Refreshed. Dangerous.`);
      s.mode = 'wander';
      s.idleT = 1;
    }
    return;
  }

  if (s.mode === 'eating') {
    s.eatT -= dt;
    if (s.eatT <= 0) {
      if (s.morningEat) {
        // breakfast: the bowl stays full until every hungry cat has eaten
        s.morningEat = false;
        s.full = 50;
        s.mode = 'distracted';
        s.distractT = 40;
        s.distractId = null;
        msg(`😸 ${c.name} had breakfast. Content — for a while.`, 'good');
        if (!cats.some(cc => cc.state.mode === 'waitFood' || cc.state.morningEat)) {
          bowlFull = false; bowlFood.visible = false;
        }
        return;
      }
      if (bowlFull) {
        // don't empty the bowl out from under a cat that's still waiting for breakfast
        if (!cats.some(cc => cc !== c && (cc.state.mode === 'waitFood' || cc.state.morningEat)))
          { bowlFull = false; bowlFood.visible = false; }
        if (s.full > 0) {
          hurtCat(c, 'The cat ate WAY too much. It regrets nothing.');
          barfPendings.push({ t: 8, pos: c.g.position.clone() });
          s.full = 60;
        } else {
          s.full = 50;
          msg(`😸 ${c.name} ate. Full and content (for now).`, 'good');
        }
      }
      s.mode = 'wander';
      s.idleT = 3;
    }
    return;
  }

  if (s.mode === 'distracted') {
    s.distractT -= dt;
    if (s.distractT <= 0) dismountThenWander(c);
    return;
  }

  if (s.mode === 'pester') {
    s.pesterT -= dt;
    const dx = player.x - c.g.position.x, dz = player.z - c.g.position.z;
    const d = Math.hypot(dx, dz);
    if (d > 1.0) {
      let nx = c.g.position.x + (dx / d) * c.speed * dt;
      let nz = c.g.position.z + (dz / d) * c.speed * dt;
      [nx, nz] = collideCat(nx, nz, c.g.position.y);
      c.g.position.x = nx; c.g.position.z = nz;
      c.g.position.y = groundY(c.g.position.x, c.g.position.z, c.g.position.y);
    }
    if (s.pesterT <= 0) { s.mode = 'wander'; s.idleT = 1; }
    return;
  }

  // wander/idle
  s.idleT -= dt;
  if (s.idleT <= 0) catDecide(c);
}

updateHearts();
drawScreen();
requestAnimationFrame(tick);

// debug/testing hook (harmless in normal play)
window.DEBUG = { player, cats, hazards, distracts, containers, NAV, walls, catGoTo, openCarrier, gridPath,
  PERCHES, pickUpCat, dropCatAt, startHop, buyItem, shopCatalog, pickUpItem, dropHeld,
  get bowlFull() { return bowlFull; }, get overlayOpen() { return overlayOpen; },
  enterComputer, exitComputer, daySetup, goToSleep, vetVisit, finishWorkDay, completeTask, makeDayTasks,
  dismissTutorial: () => $('tutBtn').onclick(),
  addMoney: n => { money += n; updateEcon(); },
  fillBowl,
  distractCat,
  set quietT(v) { quietT = v; },
  get phase() { return phase; }, get playClock() { return playClock; },
  get day() { return day; }, get money() { return money; },
  get dayStage() { return dayStage; }, set dayStage(v) { dayStage = v; },
  get ringing() { return ringing; }, set ringing(v) { ringing = v; },
  get dayTasks() { return dayTasks; }, get hearts() { return hearts; }, set hearts(v) { hearts = v; updateHearts(); } };
