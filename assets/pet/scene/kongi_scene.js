// Shared by the offline Flutter viewer and the 3D browser verification.
// The GLB contains actual meshes; wardrobe changes update material opacity.
(() => {
  const viewer = document.querySelector('model-viewer');
  let config = {outfit: [], motion: 'Idle', reducedMotion: false, paused: false};
  let loaded = false;
  let playing = null;
  let animationRequest = 0;
  const colors = new Map();
  let appliedOutfit = null;
  let yaw = null;
  function report(type, detail = '') {
    window.PetScene?.postMessage(JSON.stringify({type, detail}));
  }
  function apply() {
    if (!loaded) return;
    const selected = new Set(config.outfit);
    const outfitKey = [...selected].sort().join(',');
    if (outfitKey !== appliedOutfit) {
    for (const material of viewer.model.materials) {
      if (material.name.startsWith('item:')) {
        const id = material.name.split(':')[1];
        const color = colors.get(material.name).slice();
        color[3] = selected.has(id) ? 1 : 0;
        material.pbrMetallicRoughness.setBaseColorFactor(color);
        continue;
      }
      if (['blue','gold'].includes(material.name)) {
        const color = colors.get(material.name).slice();
        color[3] = Array.from(selected).some(id => id.endsWith('_scarf')) ? 0 : 1;
        material.pbrMetallicRoughness.setBaseColorFactor(color);
        continue;
      }
      if (material.name === 'belly') {
        const color = colors.get(material.name).slice();
        color[3] = Array.from(selected).some(id => ['knit','winter'].includes(id) || ['_vest','_cardigan','_raincoat','_coat','_overall','_knit'].some(end=>id.endsWith(end))) ? 0 : 1;
        material.pbrMetallicRoughness.setBaseColorFactor(color);
        continue;
      }
      const category = material.name.split('_')[0];
      const id = {hat: 'hat', knit: 'knit', flower: 'flower'}[category];
      if (!id) continue;
      const color = colors.get(material.name).slice();
      color[3] = selected.has(id) || id === 'knit' && selected.has('winter') ? 1 : 0;
      if (material.name === 'knit_green' && selected.has('winter')) {
        color[0] = .46; color[1] = .28; color[2] = .60;
      }
      material.pbrMetallicRoughness.setBaseColorFactor(color);
    }
    appliedOutfit = outfitKey;
    }
    viewer.cameraControls = !!config.interactive;
    if (config.reducedMotion || config.paused) {
      animationRequest++;
      playing = null;
      viewer.pause();
      if (config.reducedMotion) {
        viewer.animationName = 'Idle';
        viewer.currentTime = 0;
        playing = null;
      }
      return;
    }
    const next = viewer.availableAnimations.includes(config.motion) ? config.motion : 'Idle';
    // Let a jump/eating reaction land before a parent clears its motion flag.
    if (next === 'Idle' && ['Jump', 'Eat', 'Happy'].includes(playing)) return;
    if (next !== playing || viewer.paused) {
      playing = next;
      const request = ++animationRequest;
      viewer.pause();
      viewer.animationName = next;
      // animationName is a reactive property. Wait for its update before play,
      // otherwise the viewer's update resets finite repetitions to infinity.
      Promise.resolve(viewer.updateComplete).then(() => {
        if (request !== animationRequest || config.reducedMotion || config.paused) return;
        viewer.currentTime = 0;
        viewer.play(['Jump','Eat','Happy'].includes(next) ? {repetitions: 1} : {});
      });
    }
  }
  window.kongi = {
    configure(next) { config = {...config, ...next}; apply(); },
    view(angle) {
      const angles = {angle: 25, front: 0, side: 90, back: 180};
      yaw = (angles[angle] ?? 25) * Math.PI / 180;
      viewer.cameraOrbit = `${yaw}rad 80deg 5.4m`;
    },
    rotate(pixels) {
      if (!loaded || config.paused) return;
      if (yaw === null) yaw = viewer.getCameraOrbit().theta;
      yaw -= pixels * .006;
      viewer.cameraOrbit = `${yaw}rad 80deg 5.4m`;
      viewer.jumpCameraToGoal();
    },
    status() {
      return {loaded, playing, paused: viewer.paused, outfit: config.outfit,
        animations: viewer.availableAnimations,
        orbit: viewer.getCameraOrbit ? viewer.getCameraOrbit().toString() : null};
    }
  };
  viewer.addEventListener('load', () => {
    loaded = true;
    for (const material of viewer.model.materials) {
      colors.set(material.name, Array.from(material.pbrMetallicRoughness.baseColorFactor));
    }
    apply();
    report('ready', viewer.availableAnimations);
  });
  viewer.addEventListener('finished', () => {
    playing = null;
    config.motion = 'Idle';
    apply();
  });
  viewer.addEventListener('error', () => report('error', 'model-load'));
  window.addEventListener('error', () => report('error', 'scene-error'));
})();
