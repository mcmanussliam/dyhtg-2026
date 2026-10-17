"""Bake separate, closed clothing shells from the original character (stdlib only)."""
from collections import Counter
from math import exp, sqrt
from pathlib import Path

from build_character import ARMS, blend, capsule

ROOT = Path(__file__).resolve().parents[1]
PROFILES = {"tshirt": .016, "hoodie": .024,
            "tank_top": .014, "high_vis": .020, "hoodie_pocket": .035}


def clamp(value, low=0., high=1.):
    return max(low, min(high, value))


def arm_clearance(p):
    # Cut actual curved arms out, rather than clipping shoulders with an X plane.
    # The remaining surface wraps continuously from chest over shoulder to back.
    clearance = 1.0
    for segments in ARMS.values():
        arm = 1.0
        for start, end, radius in segments:
            arm = blend(arm, capsule(p, start, end, radius), .035)
        clearance = min(clearance, arm - .025)
    return clearance


def field(p, kind):
    x, y, z = p
    front = clamp((z - .10) / .08)
    collar = .80 - .035 * front * exp(-x*x/.02)
    if kind == "tshirt":
        return min(y-.27, collar-y, .305-z, max(.235-abs(x), y-z-.205))
    if kind == "hoodie":
        return min(y-.25, .805-.045*front*exp(-x*x/.025)-y, .34-z)
    if kind == "hoodie_pocket":
        return min(y-.32, .45-y, .15-abs(x)-max(0,y-.40)*.6, z-.18)
    if kind == "tank_top":
        neck = .79-.10*front*exp(-x*x/.018)
        return min(y-.27, neck-y, arm_clearance(p), .305-z)
    if kind == "high_vis":
        neck = .80-.11*front*(1-clamp(abs(x)/.18))
        return min(y-.27, neck-y, arm_clearance(p), .305-z,
                   max(.20-z, abs(x)-.025))
    raise ValueError(f"Unknown garment profile: {kind}")


def normalise(v):
    size = sqrt(sum(a*a for a in v))
    return tuple(a / max(size, 1e-10) for a in v)


def lerp(a, b, amount):
    return tuple(x + (y-x)*amount for x, y in zip(a, b))



def bake(kind, thickness, vertices, normals, faces):
    points, directions, triangles, cache = [], [], [], {}

    def add(p, n, layer):
        key = (layer, *(round(value, 6) for value in p))
        if key not in cache:
            cache[key] = len(points)
            distance = thickness if layer == 0 else .004
            points.append(tuple(p[i] + n[i]*distance for i in range(3)))
            directions.append(n if layer == 0 else tuple(-value for value in n))
        return cache[key]

    values = [field(p, kind) for p in vertices]
    outer = []
    for face in faces:
        polygon = [(vertices[index], normals[index]) for index in face]
        clipped = []
        for index, (p, n) in enumerate(polygon):
            q, m = polygon[(index+1) % 3]
            a, b = values[face[index]], values[face[(index+1) % 3]]
            if a >= 0:
                clipped.append((p, n))
            if (a >= 0) != (b >= 0):
                t = a/(a-b)
                clipped.append((lerp(p, q, t), normalise(lerp(n, m, t))))
        for index in range(1, len(clipped)-1):
            patch = [clipped[0], clipped[index], clipped[index+1]]
            outside = tuple(add(p, n, 0) for p, n in patch)
            inside = tuple(add(p, n, 1) for p, n in patch)
            if len(set(outside)) == 3:
                outer.append(outside)
                triangles.extend([outside, tuple(reversed(inside))])
    # Close every collar, arm hole and hem. Real rim faces make thickness visible.
    edges = Counter()
    ordered = {}
    for face in outer:
        for a, b in zip(face, face[1:]+face[:1]):
            key = tuple(sorted((a, b)))
            edges[key] += 1
            ordered[key] = (a, b)
    inner = {outside: cache[(1, *key[1:])] for key, outside in cache.items() if key[0] == 0}
    for key, count in edges.items():
        if count != 1:
            continue
        a, b = ordered[key]
        c, d = inner[a], inner[b]
        # Separate normals for the rim preserve the soft body surface and crisp hem.
        pa, pb, pc = points[a], points[b], points[c]
        u = tuple(pb[i]-pa[i] for i in range(3))
        v = tuple(pc[i]-pa[i] for i in range(3))
        rim_normal = normalise((u[2]*v[1]-u[1]*v[2], u[0]*v[2]-u[2]*v[0], u[1]*v[0]-u[0]*v[1]))
        start = len(points)
        for source in [a, b, c, d]:
            points.append(points[source])
            directions.append(rim_normal)
        triangles.extend([(start+1, start, start+2), (start+1, start+2, start+3)])
    # Weld duplicated rim normals by exported position when checking watertightness.
    welded_edges = Counter()
    for face in triangles:
        for a, b in zip(face, face[1:] + face[:1]):
            pa, pb = (tuple(round(value, 6) for value in points[i]) for i in (a, b))
            welded_edges[tuple(sorted((pa, pb)))] += 1
    if any(count != 2 for count in welded_edges.values()):
        raise ValueError(f"{kind}: clothing must remain closed and manifold")
    if kind in ("tank_top", "high_vis"):
        # A vest must be one connected shell, not isolated front/back panels.
        neighbours = {}
        for a, b in welded_edges:
            neighbours.setdefault(a, set()).add(b)
            neighbours.setdefault(b, set()).add(a)
        pending = [next(iter(neighbours))]
        while pending:
            point = pending.pop()
            if point in neighbours:
                pending.extend(neighbours.pop(point))
        if neighbours:
            raise ValueError(f"{kind}: shoulders must connect the front and back")
    output = ROOT / ("game/character/skins/hoodie/pocket.obj" if kind == "hoodie_pocket" else f"game/character/skins/{kind}/{kind}.obj")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w") as stream:
        stream.write(f"# Original {kind} shell; generated by tools/build_clothing.py\no Garment\n")
        for p in points:
            stream.write("v %.6f %.6f %.6f\n" % p)
        for n in directions:
            stream.write("vn %.6f %.6f %.6f\n" % n)
        for a, b, c in triangles:
            stream.write(f"f {a+1}//{a+1} {b+1}//{b+1} {c+1}//{c+1}\n")
    print(f"{kind}: {len(triangles)} triangles, {thickness*1000:.0f} mm fabric shell")


def main():
    vertices, normals, faces = [], [], []
    for line in (ROOT / "game/character/art/character.obj").read_text().splitlines():
        parts = line.split()
        if parts and parts[0] == "v":
            vertices.append(tuple(map(float, parts[1:])))
        elif parts and parts[0] == "vn":
            normals.append(tuple(map(float, parts[1:])))
        elif parts and parts[0] == "f":
            faces.append(tuple(int(part.split("/")[0])-1 for part in parts[1:]))
    for kind, thickness in PROFILES.items():
        bake(kind, thickness, vertices, normals, faces)


if __name__ == "__main__":
    main()
