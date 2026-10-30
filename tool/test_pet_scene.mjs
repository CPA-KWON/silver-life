import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../assets/pet/scene/kongi_scene.js', import.meta.url), 'utf8');
for (const species of ['dog', 'cat']) {
  for (const stage of ['baby', 'junior', 'adult']) {
    const bytes = fs.readFileSync(new URL(`../assets/pet/models/${species}_${stage}.glb`, import.meta.url));
    const gltf = JSON.parse(bytes.subarray(20, 20 + bytes.readUInt32LE(12)));
    const events = new Map(), reports = [];
    let writes = 0, orbit = {theta: .4, phi: 80 * Math.PI / 180, radius: 5.4};
    const viewer = {
      availableAnimations: gltf.animations.map(a => a.name),
      model: {materials: gltf.materials.map(m => ({
        name: m.name,
        pbrMetallicRoughness: {
          baseColorFactor: m.pbrMetallicRoughness.baseColorFactor ?? [1,1,1,1],
          setBaseColorFactor(color) { writes++; this.baseColorFactor = color; }
        }
      }))},
      updateComplete: Promise.resolve(), paused: true,
      addEventListener(name, handler) { events.set(name, handler); },
      pause() { this.paused = true; }, play() { this.paused = false; },
      getCameraOrbit() { return {...orbit, toString() {return `${this.theta} ${this.phi} ${this.radius}`;}}; },
      set cameraOrbit(value) {
        const [theta, phi, distance] = value.split(' ');
        orbit = {theta: Number.parseFloat(theta), phi: Number.parseFloat(phi) * Math.PI / 180, radius: Number.parseFloat(distance)};
      },
      jumpCameraToGoal() {},
    };
    const window = {PetScene: {postMessage(text) { reports.push(JSON.parse(text)); }}, addEventListener() {}};
    vm.runInNewContext(source, {window, document: {querySelector() {return viewer;}}});
    const item = `${species}_${species === 'cat' ? 'stripe_knit' : 'walk_vest'}`;
    window.kongi.configure({outfit:[item], paused:true});
    events.get('load')();
    assert.equal(reports.filter(r=>r.type==='ready').length,1);
    assert.equal(window.kongi.status().loaded,true);
    const material = viewer.model.materials.find(m=>m.name === `item:${item}`);
    assert.equal(material.pbrMetallicRoughness.baseColorFactor[3],1);
    assert(viewer.model.materials.filter(m=>m.name.startsWith('item:') && m.name.split(':')[1]!==item).every(m=>m.pbrMetallicRoughness.baseColorFactor[3]===0));
    const oldTheta = orbit.theta;
    window.kongi.rotate(100);
    assert.equal(orbit.theta, oldTheta, 'hidden model must not rotate');
    window.kongi.configure({paused:false, motion:'Idle'});
    await Promise.resolve();
    const beforeWrites = writes;
    window.kongi.rotate(100);
    assert.notEqual(orbit.theta,oldTheta);
    assert.equal(orbit.phi,80 * Math.PI / 180);
    assert.equal(orbit.radius,5.4);
    window.kongi.configure({motion:'Walk'});
    await Promise.resolve();
    assert.equal(writes,beforeWrites,'unchanged wardrobe must not reapply all materials');
    events.get('finished')();
    await Promise.resolve();
    assert.equal(window.kongi.status().playing,'Idle');
  }
}
console.log('PASS: all 6 scenes prepare outfits before ready, rotate horizontally, preserve camera height/distance, pause offscreen, and skip unchanged materials.');
