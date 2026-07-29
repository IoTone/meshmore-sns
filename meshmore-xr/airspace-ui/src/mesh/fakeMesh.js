// A simulated MeshCore feed, standing in for libmeshcore's MeshcoreSession.
//
// In production this is:
//   MeshcoreSession -> SessionListener -> ChannelMessageFrame / AdvertFrame /
//   ContactFrame -> domain store -> Horizon
//
// Nodes carry a true BEARING, a true ELEVATION, and a true DISTANCE. Bearing is
// the primary index, not sort order: a node is not row 7 of a list, it is 40 deg
// to your left and 12 deg up at 300 m.

const NAMES = [
  'kanako.1', 'davi1', 'relay-nw', 't1000-e', 'gate-cam', 'ridge',
  'hab-2', 'shed', 'mule.4', 'oku.9', 'beacon', 'ridge-hi',
];

export function makeMesh() {
  return NAMES.map((nm, i) => {
    const bearing = (i / NAMES.length) * Math.PI * 2 + (i % 3) * 0.22;
    return {
      name: nm,
      bearing,
      // Elevation is real: a ridge station is genuinely above you, a drone more
      // so. The mesh is a volumetric shell, not a flat ring.
      elev: (Math.sin(i * 2.1) * 0.34) + (nm === 'ridge-hi' ? 0.5 : 0),
      dist: 0.28 + ((i * 37) % 100) / 140,
      age: ((i * 53) % 100) / 100,   // recency drives luminance
      located: nm !== 'shed',         // a node with no position estimate
      hops: 1 + (i % 3),
    };
  });
}
