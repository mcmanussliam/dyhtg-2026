"""Build the original seamless character mesh (stdlib only; not needed at runtime)."""
from pathlib import Path
from math import sqrt
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
STEP = 0.020
BLEND = 0.12


def ellipsoid(p, c, r):
    q = [(p[i] - c[i]) / r[i] for i in range(3)]
    k0 = sqrt(sum(v * v for v in q))
    k1 = sqrt(sum((q[i] / r[i]) ** 2 for i in range(3)))
    return k0 * (k0 - 1) / max(k1, 1e-10)


def capsule(p, a, b, r):
    ab = [b[i] - a[i] for i in range(3)]
    ap = [p[i] - a[i] for i in range(3)]
    t = max(0, min(1, sum(ap[i] * ab[i] for i in range(3)) / sum(v*v for v in ab)))
    return sqrt(sum((ap[i] - ab[i] * t) ** 2 for i in range(3))) - r


def blend(a, b, width=BLEND):
    h = max(width - abs(a - b), 0) / width
    return min(a, b) - h * h * width * 0.25


# Smooth shoulder-to-hand curves replace the angular two-piece elbow pose.
ARMS = {}
for side in (-1, 1):
    start = (side * .25, .57, .025)
    control = (side * .38, .22, .22)
    hand = (side * .12, .30, .43)
    points = []
    for sample in range(6):
        t = sample / 5
        points.append(tuple((1-t)**2 * start[i] + 2*(1-t)*t*control[i] + t*t*hand[i]
                            for i in range(3)))
    ARMS[side] = [(points[i], points[i+1], .108 - i*.004) for i in range(5)]


def field(p):
    d = ellipsoid(p, (0, .32, 0), (.35, .35, .29))
    for c, r in [((0, .59, 0), (.29, .24, .25)),
                 ((0, .73, 0), (.205, .19, .205)),
                 ((0, .96, 0), (.25, .275, .23))]:
        d = blend(d, ellipsoid(p, c, r))
    for side in (-1, 1):
        arm = 1.0
        for start, end, radius in ARMS[side]:
            arm = blend(arm, capsule(p, start, end, radius), 0.035)
        d = blend(d, arm, 0.10)
        d = blend(d, capsule(p, (side*.17, .09, .11), (side*.21, .04, .35), .115))
        d = blend(d, ellipsoid(p, (side*.21, -.025, .40), (.115, .13, .15)))
    return d


def normal(p):
    h = .0002
    gradient = []
    for axis in range(3):
        a, b = list(p), list(p)
        a[axis] += h
        b[axis] -= h
        gradient.append(field(a) - field(b))
    size = sqrt(sum(v*v for v in gradient))
    return tuple(v / max(size, 1e-10) for v in gradient)


def build():
    origin = (-.60, -.25, -.45)
    extents = (1.20, 1.60, 1.10)
    counts = tuple(round(size / STEP) + 1 for size in extents)
    points, values = {}, {}
    for x in range(counts[0]):
        for y in range(counts[1]):
            for z in range(counts[2]):
                key = (x, y, z)
                p = tuple(origin[i] + key[i] * STEP for i in range(3))
                points[key] = p
                values[key] = field(p)
    offsets = ((0,0,0), (1,0,0), (1,1,0), (0,1,0),
               (0,0,1), (1,0,1), (1,1,1), (0,1,1))
    tetrahedra = ((0,5,1,6), (0,1,2,6), (0,2,3,6),
                  (0,3,7,6), (0,7,4,6), (0,4,5,6))
    vertices, normals, faces, cache = [], [], [], {}

    def vertex(a, b):
        key = tuple(sorted((a, b)))
        if key not in cache:
            t = values[a] / (values[a] - values[b])
            p = tuple(points[a][i] + (points[b][i] - points[a][i]) * t for i in range(3))
            cache[key] = len(vertices)
            vertices.append(p)
            normals.append(normal(p))
        return cache[key]

    def triangle(a, b, c):
        pa, pb, pc = vertices[a], vertices[b], vertices[c]
        u = [pb[i]-pa[i] for i in range(3)]
        v = [pc[i]-pa[i] for i in range(3)]
        cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        if sum(cross[i]*normals[a][i] for i in range(3)) < 0:
            b, c = c, b
        faces.append((a+1, b+1, c+1))

    for x in range(counts[0]-1):
        for y in range(counts[1]-1):
            for z in range(counts[2]-1):
                cube = [(x+a, y+b, z+c) for a,b,c in offsets]
                if all(values[k] >= 0 for k in cube) or all(values[k] < 0 for k in cube):
                    continue
                for tetra in tetrahedra:
                    keys = [cube[i] for i in tetra]
                    inside = [key for key in keys if values[key] < 0]
                    outside = [key for key in keys if values[key] >= 0]
                    if len(inside) == 1:
                        triangle(*(vertex(inside[0], key) for key in outside))
                    elif len(inside) == 3:
                        triangle(*(vertex(outside[0], key) for key in inside))
                    elif len(inside) == 2:
                        # Derive quad connectivity from tetrahedron edges, not
                        # an approximate normal that may change across a joint.
                        a = vertex(inside[0], outside[0])
                        b = vertex(inside[0], outside[1])
                        c = vertex(inside[1], outside[0])
                        d = vertex(inside[1], outside[1])
                        triangle(a, b, d)
                        triangle(a, d, c)
    edge_counts = Counter()
    for face in faces:
        for a, b in zip(face, face[1:] + face[:1]):
            edge_counts[tuple(sorted((a, b)))] += 1
    if any(count != 2 for count in edge_counts.values()):
        raise ValueError("Character surface must be closed and manifold")
    # Two Taubin smoothing cycles even out sampling ripples without shrinking
    # the silhouette. Re-evaluate smooth field normals on the final surface.
    neighbours = [set() for _ in vertices]
    for face in faces:
        a, b, c = (index - 1 for index in face)
        neighbours[a].update((b, c))
        neighbours[b].update((a, c))
        neighbours[c].update((a, b))
    for weight in (0.36, -0.38, 0.36, -0.38):
        smoothed = []
        for index, p in enumerate(vertices):
            adjacent = neighbours[index]
            mean = [sum(vertices[k][i] for k in adjacent) / len(adjacent) for i in range(3)]
            smoothed.append(tuple(p[i] + weight * (mean[i] - p[i]) for i in range(3)))
        vertices = smoothed
    normals = [normal(p) for p in vertices]
    output = ROOT / 'game/character/art/character.obj'
    with output.open('w') as f:
        f.write('# Original seamless seated character; generated by tools/build_character.py\no Character\n')
        for p in vertices:
            f.write('v %.6f %.6f %.6f\n' % p)
        for n in normals:
            f.write('vn %.6f %.6f %.6f\n' % n)
        for a,b,c in faces:
            f.write(f'f {a}//{a} {b}//{b} {c}//{c}\n')
    print(f'Built {len(vertices)} vertices, {len(faces)} triangles: {output}')


if __name__ == '__main__':
    build()
