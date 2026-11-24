#!/usr/bin/env python3
"""
Delar en glb förlustfritt i två: toppnoderna vars namn börjar med något av prefixen flyttas till en egen
glb, resten stannar. Inget räknas om: noder, nät, material, texturer och buffertdata kopieras som de är
(bara index numreras om). GitHub tar inte filer över 100 MB, och Vidingsjö XL:s objekt-glb var ~155 MB
(vägar 67, hus 60), så step3 delar ut vägarna (`Vagar`) när objekt-glb:n är större än DELA_OVER_MB.

    .venv/bin/python -I scripts/dela_glb.py <in.glb> <ut_flyttade.glb> <prefix> [<prefix> ...]

<in.glb> skrivs om utan de flyttade noderna. Spelets kartscen instanserar båda filerna (se
tools/import_geodata_map.gd).
"""
import json
import struct
import sys

DELA_OVER_MB = 95.0
TEX_NYCKLAR = ('baseColorTexture', 'metallicRoughnessTexture')
MAT_TEX_NYCKLAR = ('normalTexture', 'occlusionTexture', 'emissiveTexture')


def las(path):
    data = open(path, 'rb').read()
    magic, ver, _ = struct.unpack('<III', data[:12])
    assert magic == 0x46546C67 and ver == 2, 'inte en glb 2.0'
    pos, gltf, binary = 12, None, b''
    while pos < len(data):
        length, typ = struct.unpack('<II', data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if typ == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif typ == 0x004E4942:
            binary = chunk
        pos += 8 + length
    return gltf, binary


def skriv(path, gltf, binary):
    js = json.dumps(gltf, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    binary += b'\0' * (-len(binary) % 4)
    total = 12 + 8 + len(js) + (8 + len(binary) if binary else 0)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        if binary:
            f.write(struct.pack('<II', len(binary), 0x004E4942) + binary)


def delmangd(g, binary, toppnoder):
    """En ny glTF med bara toppnoderna `toppnoder` (index) och allt de använder."""
    for nyckel in ('skins', 'animations', 'cameras'):
        assert not g.get(nyckel), f'{nyckel} stöds inte'
    noder = []

    def samla(n):
        noder.append(n)
        for c in g['nodes'][n].get('children', []):
            samla(c)

    for n in toppnoder:
        samla(n)
    nod_ny = {n: i for i, n in enumerate(noder)}
    mesh_ny, mat_ny, tex_ny, img_ny, smp_ny, acc_ny, bv_ny = {}, {}, {}, {}, {}, {}, {}
    ut = {k: v for k, v in g.items() if k in ('asset', 'extensionsUsed', 'extensionsRequired', 'extras')}
    ut.update(nodes=[], meshes=[], materials=[], textures=[], images=[], samplers=[], accessors=[], bufferViews=[])
    ny_bin = bytearray()

    def bufview(i):
        if i not in bv_ny:
            v = dict(g['bufferViews'][i])
            data = binary[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]
            ny_bin.extend(b'\0' * (-len(ny_bin) % 4))
            v['byteOffset'] = len(ny_bin)
            v['buffer'] = 0
            ny_bin.extend(data)
            bv_ny[i] = len(ut['bufferViews'])
            ut['bufferViews'].append(v)
        return bv_ny[i]

    def accessor(i):
        if i not in acc_ny:
            a = dict(g['accessors'][i])
            if 'bufferView' in a:
                a['bufferView'] = bufview(a['bufferView'])
            assert 'sparse' not in a, 'glesa accessorer stöds inte'
            acc_ny[i] = len(ut['accessors'])
            ut['accessors'].append(a)
        return acc_ny[i]

    def textur(i):
        if i not in tex_ny:
            t = dict(g['textures'][i])
            if 'source' in t:
                s = t['source']
                if s not in img_ny:
                    im = dict(g['images'][s])
                    if 'bufferView' in im:
                        im['bufferView'] = bufview(im['bufferView'])
                    img_ny[s] = len(ut['images'])
                    ut['images'].append(im)
                t['source'] = img_ny[s]
            if 'sampler' in t:
                s = t['sampler']
                if s not in smp_ny:
                    smp_ny[s] = len(ut['samplers'])
                    ut['samplers'].append(g['samplers'][s])
                t['sampler'] = smp_ny[s]
            tex_ny[i] = len(ut['textures'])
            ut['textures'].append(t)
        return tex_ny[i]

    def material(i):
        if i not in mat_ny:
            m = json.loads(json.dumps(g['materials'][i]))
            pbr = m.get('pbrMetallicRoughness', {})
            for k in TEX_NYCKLAR:
                if k in pbr:
                    pbr[k]['index'] = textur(pbr[k]['index'])
            for k in MAT_TEX_NYCKLAR:
                if k in m:
                    m[k]['index'] = textur(m[k]['index'])
            mat_ny[i] = len(ut['materials'])
            ut['materials'].append(m)
        return mat_ny[i]

    def mesh(i):
        if i not in mesh_ny:
            m = json.loads(json.dumps(g['meshes'][i]))
            for p in m['primitives']:
                p['attributes'] = {k: accessor(v) for k, v in p['attributes'].items()}
                if 'indices' in p:
                    p['indices'] = accessor(p['indices'])
                if 'material' in p:
                    p['material'] = material(p['material'])
                assert 'targets' not in p, 'morph targets stöds inte'
            mesh_ny[i] = len(ut['meshes'])
            ut['meshes'].append(m)
        return mesh_ny[i]

    for n in noder:
        nd = dict(g['nodes'][n])
        if 'children' in nd:
            nd['children'] = [nod_ny[c] for c in nd['children']]
        if 'mesh' in nd:
            nd['mesh'] = mesh(nd['mesh'])
        ut['nodes'].append(nd)
    ut['scenes'] = [{'nodes': [nod_ny[n] for n in toppnoder]}]
    ut['scene'] = 0
    ut['buffers'] = [{'byteLength': len(ny_bin)}] if ny_bin else []
    for k in [k for k, v in ut.items() if v == [] and k != 'nodes']:
        del ut[k]
    return ut, bytes(ny_bin)


def dela(src, dst, prefix):
    """Flyttar toppnoderna som börjar med något prefix ur src till dst. Antal flyttade noder."""
    g, binary = las(src)
    topp = g['scenes'][g.get('scene', 0)]['nodes']
    flytta = [n for n in topp if g['nodes'][n].get('name', '').startswith(tuple(prefix))]
    kvar = [n for n in topp if n not in flytta]
    if not flytta:
        return 0
    a, abin = delmangd(g, binary, kvar)
    b, bbin = delmangd(g, binary, flytta)
    skriv(dst, b, bbin)
    skriv(src, a, abin)
    return len(flytta)


if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    n = dela(sys.argv[1], sys.argv[2], sys.argv[3:])
    print(f'dela_glb: {n} toppnoder till {sys.argv[2]}')
