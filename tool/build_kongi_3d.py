"""Generate Silver Life's original, articulated Kongi glTF 2.0 models.

No network, Blender installation, image billboard or external model required.
Coordinates are metres, Y up, +Z forward. Rebuild: python3 tool/build_kongi_3d.py
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def sphere(rows=28, cols=40, hemisphere=False):
    positions, normals, indices = [], [], []
    for r in range(rows + 1):
        theta = r / rows * math.pi * (0.5 if hemisphere else 1)
        for c in range(cols + 1):
            phi = c / cols * math.tau
            p = [math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi)]
            positions.extend(p)
            normals.extend(p)
    for r in range(rows):
        for c in range(cols):
            a = r * (cols + 1) + c
            b = a + cols + 1
            # CCW viewed from outside. Skip degenerate pole triangles.
            if r != 0:
                indices.extend([a, a + 1, b])
            if hemisphere or r != rows - 1:
                indices.extend([a + 1, b + 1, b])
    return positions, normals, indices


def torus(segments=56, sides=12, tube=0.055):
    positions, normals, indices = [], [], []
    for r in range(segments + 1):
        u = r / segments * math.tau
        for c in range(sides + 1):
            v = c / sides * math.tau
            n = [math.cos(u) * math.cos(v), math.sin(v), math.sin(u) * math.cos(v)]
            positions.extend([(1 + tube * math.cos(v)) * math.cos(u), tube * math.sin(v), (1 + tube * math.cos(v)) * math.sin(u)])
            normals.extend(n)
    for r in range(segments):
        for c in range(sides):
            a = r * (sides + 1) + c
            b = a + sides + 1
            indices.extend([a, a + 1, b, a + 1, b + 1, b])
    return positions, normals, indices


def tube_curve(points, radii, sides=16):
    """Smooth continuous 3D tube, avoiding a chain-of-spheres silhouette."""
    positions, normals, indices = [], [], []
    for i, p in enumerate(points):
        before, after = points[max(0, i-1)], points[min(len(points)-1, i+1)]
        tangent = [after[j]-before[j] for j in range(3)]
        length = math.sqrt(sum(v*v for v in tangent))
        tangent = [v/length for v in tangent]
        reference = [0, 0, 1] if abs(tangent[2]) < .9 else [0, 1, 0]
        n = [tangent[1]*reference[2]-tangent[2]*reference[1], tangent[2]*reference[0]-tangent[0]*reference[2], tangent[0]*reference[1]-tangent[1]*reference[0]]
        length = math.sqrt(sum(v*v for v in n)); n = [v/length for v in n]
        b = [tangent[1]*n[2]-tangent[2]*n[1], tangent[2]*n[0]-tangent[0]*n[2], tangent[0]*n[1]-tangent[1]*n[0]]
        for j in range(sides+1):
            angle=j/sides*math.tau
            normal=[n[k]*math.cos(angle)+b[k]*math.sin(angle) for k in range(3)]
            positions.extend([p[k]+radii[i]*normal[k] for k in range(3)])
            normals.extend(normal)
    for i in range(len(points)-1):
        for j in range(sides):
            a=i*(sides+1)+j; b=a+sides+1
            indices.extend([a,a+1,b,a+1,b+1,b])
    return positions, normals, indices


def quat(axis, angle):
    s = math.sin(angle / 2)
    return [axis[0] * s, axis[1] * s, axis[2] * s, math.cos(angle / 2)]


class Model:
    def __init__(self):
        self.binary = bytearray()
        self.g = dict(asset=dict(version='2.0', generator='Silver Life Kongi procedural model v1'),
                      scene=0, scenes=[dict(nodes=[0])], nodes=[dict(name='Kongi', children=[])],
                      meshes=[], materials=[], accessors=[], bufferViews=[], animations=[])
        self.materials, self.meshes = {}, {}
        self.geometry = {}
        for name, geo in [('sphere', sphere()), ('cap', sphere(16, 40, True)), ('torus', torus()),
                          ('tail', tube_curve([[.18*math.sin(t*1.7),.05+t*.30,-t*.23] for t in [i/40 for i in range(41)]], [.08-(i/40)*.025 for i in range(41)])),
                          ('smile', tube_curve([[x,-.352+.027*(x/.078)**2,.601] for x in [-.078+i*.156/32 for i in range(33)]], [.009]*33))]:
            pos, nor, indices = geo
            self.geometry[name] = (self.accessor(pos, 'VEC3', 5126, bounds=True, target=34962),
                                   self.accessor(nor, 'VEC3', 5126, target=34962),
                                   self.accessor(indices, 'SCALAR', 5123, target=34963))

    def accessor(self, values, kind, component=5126, bounds=False, target=None):
        while len(self.binary) % 4:
            self.binary.append(0)
        data = struct.pack('<' + ('f' if component == 5126 else 'H') * len(values), *values)
        view = dict(buffer=0, byteOffset=len(self.binary), byteLength=len(data))
        if target:
            view['target'] = target
        self.g['bufferViews'].append(view)
        self.binary.extend(data)
        stride = dict(SCALAR=1, VEC3=3, VEC4=4)[kind]
        a = dict(bufferView=len(self.g['bufferViews']) - 1, componentType=component, count=len(values) // stride, type=kind)
        if bounds:
            a['min'] = [min(values[i::stride]) for i in range(stride)]
            a['max'] = [max(values[i::stride]) for i in range(stride)]
        self.g['accessors'].append(a)
        return len(self.g['accessors']) - 1

    def material(self, name, rgb, rough=0.65, hidden=False, metal=0):
        # Input colours are sRGB; glTF baseColorFactor is linear.
        linear = [((v / 255 + .055) / 1.055) ** 2.4 if v > 10 else v / 255 / 12.92 for v in rgb]
        m = dict(name=name, pbrMetallicRoughness=dict(baseColorFactor=linear + [0 if hidden else 1], metallicFactor=metal, roughnessFactor=rough))
        if hidden:
            m['alphaMode'] = 'BLEND'
        self.materials[name] = len(self.g['materials'])
        self.g['materials'].append(m)

    def node(self, name, parent=0, p=None, scale=None, axis=None, angle=0, material=None, geo='sphere'):
        n = dict(name=name)
        if p is not None:
            n['translation'] = p
        if scale is not None:
            n['scale'] = scale
        if axis is not None:
            n['rotation'] = quat(axis, angle)
        if material:
            key = (geo, material)
            if key not in self.meshes:
                a, b, c = self.geometry[geo]
                self.meshes[key] = len(self.g['meshes'])
                self.g['meshes'].append(dict(name=f'{geo}_{material}', primitives=[dict(attributes=dict(POSITION=a, NORMAL=b), indices=c, material=self.materials[material])]))
            n['mesh'] = self.meshes[key]
        index = len(self.g['nodes'])
        self.g['nodes'].append(n)
        self.g['nodes'][parent].setdefault('children', []).append(index)
        return index

    def animation(self, name, tracks):
        a = dict(name=name, samplers=[], channels=[])
        for node, path, times, values in tracks:
            ti = self.accessor(times, 'SCALAR', bounds=True)
            out = self.accessor([v for row in values for v in row], 'VEC4' if path == 'rotation' else 'VEC3')
            a['channels'].append(dict(sampler=len(a['samplers']), target=dict(node=node, path=path)))
            a['samplers'].append(dict(input=ti, output=out, interpolation='LINEAR'))
        self.g['animations'].append(a)

    def save(self, path):
        self.g['buffers'] = [dict(byteLength=len(self.binary))]
        js = json.dumps(self.g, separators=(',', ':'), ensure_ascii=True).encode()
        js += b' ' * (-len(js) % 4)
        binary = bytes(self.binary) + b'\x00' * (-len(self.binary) % 4)
        glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary))
        glb += struct.pack('<II', len(js), 0x4E4F534A) + js
        glb += struct.pack('<II', len(binary), 0x004E4942) + binary
        path.write_bytes(glb)


def build(stage):
    m = Model()
    for name, rgb, rough in [('fur', (212, 177, 124), .77), ('ear', (158, 105, 63), .79),
                             ('cream', (244, 225, 187), .78), ('belly', (244, 225, 187), .78), ('eye', (21, 17, 14), .16),
                             ('nose', (30, 23, 19), .24), ('shine', (255, 255, 255), .18),
                             ('cheek', (226, 148, 144), .8), ('blue', (25, 104, 155), .5),
                             ('gold', (230, 179, 58), .4), ('mouth', (63, 40, 28), .55)]:
        m.material(name, rgb, rough)
        if name == 'belly':
            m.g['materials'][-1]['alphaMode'] = 'BLEND'
    for name, rgb in [('hat_pink', (231, 104, 151)), ('hat_brim', (191, 67, 112)),
                       ('hat_pom', (255, 244, 232)), ('knit_green', (55, 143, 113)),
                       ('knit_white', (246, 240, 215)), ('flower_petal', (242, 164, 181)),
                       ('flower_center', (255, 208, 88))]:
        m.material(name, rgb, .8, hidden=True)

    # Larger body and slightly smaller head/body ratio as Kongi matures.
    body_y, body_height, body_width, head_y, head_size = [
        (.67, .49, .43, 1.52, .67), (.78, .60, .48, 1.72, .68), (.9, .72, .52, 1.96, .68)][stage]
    head = m.node('HeadPivot', p=[0, head_y, 0])
    m.node('Head', head, scale=[head_size, head_size * .95, head_size * .78], material='fur')
    body = m.node('Body', p=[0, body_y, 0], scale=[body_width, body_height, .35 + .025 * stage], material='fur')
    m.node('Belly', p=[0, body_y - .04, .34 + .025 * stage], scale=[.22, .24 + .025 * stage, .035], material='belly')
    for sign, suffix in [(-1, 'L'), (1, 'R')]:
        m.node('Ear' + suffix, head, p=[sign * .62, -.13, -.01], scale=[.19, .35, .19], axis=[0, 0, 1], angle=sign * .15, material='ear')
        eye = m.node('Eye' + suffix, head, p=[sign * .245, -.035, .477], scale=[.100, .142, .058], material='eye')
        m.node('EyeShine' + suffix, head, p=[sign * .245 - .025, .015, .529], scale=[.032, .037, .016], material='shine')
        m.node('EyeShineSmall' + suffix, head, p=[sign * .245 + .026, -.105, .521], scale=[.014, .016, .012], material='shine')
        m.node('Cheek' + suffix, head, p=[sign * .40, -.19, .40], scale=[.105, .044, .028], axis=[0, 0, 1], angle=sign * .26, material='cheek')
    m.node('Muzzle', head, p=[0, -.27, .48], scale=[.27, .155, .13], material='cream')
    m.node('Nose', head, p=[0, -.225, .605], scale=[.095, .067, .065], material='nose')
    m.node('Smile', head, material='mouth', geo='smile')
    for i, (x, y, z, size) in enumerate([(-.06, .633, -.02, .065), (.03, .661, -.03, .070), (.08, .628, -.03, .050)]):
        m.node(f'Forelock{i}', head, p=[x, y, z], scale=[size, size, size], material='fur')

    paws = []
    for sign in [-1, 1]:
        paw = m.node(f'PawPivot{sign}', p=[sign * .235, .26, .18])
        m.node(f'Paw{sign}', paw, p=[0, -.09, .03], scale=[.18, .17, .20], material='fur')
        m.node(f'Toes{sign}', paw, p=[0, -.19, .11], scale=[.18, .055, .14], material='cream')
        paws.append(paw)
        arm = m.node(f'ArmPivot{sign}', p=[sign * (body_width - .06), body_y + .05, .04])
        m.node(f'Arm{sign}', arm, p=[sign * .01, -.15, .13], scale=[.12, .23, .13], axis=[0, 0, 1], angle=sign * -.22, material='fur')
        paws.append(arm)

    neck_y = head_y - .52
    m.node('Collar', p=[0, neck_y, 0], scale=[.40, .62, .32], material='blue', geo='torus')
    m.node('ScarfEnd', p=[.065, neck_y - .10, .34], scale=[.065, .135, .035], axis=[0, 0, 1], angle=-.35, material='blue')
    m.node('CollarTag', p=[-.015, neck_y - .03, .371], scale=[.045, .05, .023], material='gold')
    tail = m.node('TailPivot', p=[0, body_y - .18, -.32])
    m.node('Tail', tail, material='ear', geo='tail')
    m.node('TailTip', tail, p=[.18*math.sin(1.7),.35,-.23], scale=[.055]*3, material='fur')

    # Hat follows the head; all wardrobe materials are initially transparent.
    m.node('WoolHat', head, p=[0, .47, 0], scale=[.61, .28, .48], material='hat_pink', geo='cap')
    m.node('HatBrim', head, p=[0, .47, 0], scale=[.61, .7, .48], material='hat_brim', geo='torus')
    m.node('HatPom', head, p=[0, .80, 0], scale=[.085] * 3, material='hat_pom')
    m.node('KnitBody', p=[0, body_y, 0], scale=[body_width + .025, body_height * .91, .39 + .025 * stage], material='knit_green')
    for i in range(4):
        y = body_y - body_height * .6 + i * body_height * .35
        r = math.sqrt(max(.1, 1 - ((y - body_y) / (body_height * .91)) ** 2))
        m.node(f'KnitStripe{i}', p=[0, y, 0], scale=[(body_width + .028) * r, .28, (.393 + .025 * stage) * r], material='knit_white', geo='torus')
    for i in range(5):
        a = i * math.tau / 5
        m.node(f'FlowerPetal{i}', head, p=[-.51 + .068 * math.cos(a), .32 + .068 * math.sin(a), .38], scale=[.060, .055, .028], material='flower_petal')
    m.node('FlowerCenter', head, p=[-.51, .32, .415], scale=[.041, .041, .026], material='flower_center')

    t = [0, .4, .8, 1.2, 1.6, 2.0]
    wag = [quat([0, 0, 1], x) for x in [0, .24, -.24, .24, -.24, 0]]
    m.animation('Idle', [(0, 'scale', t, [[1, v, 1] for v in [1, 1.008, 1.014, 1.008, 1, 1]]), (tail, 'rotation', t, wag)])
    t = [0, .12, .3, .50, .72, .85, 1.1, 1.35]
    m.animation('Jump', [
        (0, 'translation', t, [[0, v, 0] for v in [0, 0, .30, .43, .12, 0, 0, 0]]),
        (0, 'scale', t, [[1.04, .93, 1.04], [1.04, .93, 1.04], [.96, 1.04, .96], [1, 1, 1], [1, 1, 1], [1.05, .94, 1.05], [1, 1, 1], [1, 1, 1]]),
        (head, 'rotation', t, [quat([0, 0, 1], x) for x in [0, 0, -.09, .06, .09, -.06, .04, 0]]),
    ])
    t = [0, .25, .5, .75, 1]
    tracks = [(0, 'translation', t, [[-.08, 0, 0], [0, .04, 0], [.08, 0, 0], [0, .04, 0], [-.08, 0, 0]])]
    for i, paw in enumerate(paws):
        sign = 1 if i % 2 else -1
        tracks.append((paw, 'rotation', t, [quat([1, 0, 0], x * sign) for x in [-.35, 0, .35, 0, -.35]]))
    m.animation('Walk', tracks)
    t = [0, .35, .7, 1.05, 1.4, 1.75, 2.1]
    m.animation('Eat', [
        (head, 'rotation', t, [quat([1, 0, 0], v) for v in [0, .24, .07, .24, .07, .13, 0]]),
        (tail, 'rotation', t, [quat([0, 0, 1], v) for v in [0, .35, -.35, .35, -.35, .2, 0]]),
    ])
    path = ROOT / 'assets' / 'pet' / 'models' / f'{["baby", "junior", "adult"][stage]}.glb'
    m.save(path)
    print(f'{path.name}: {path.stat().st_size:,} bytes, {len(m.g["nodes"])} nodes, 4 animations')


if __name__ == '__main__':
    for s in range(3):
        build(s)
