import xml.etree.ElementTree as ET

def load(path):
    root = ET.parse(path).getroot()
    nodes, ways, rels = {}, {}, {}
    ntags = {}
    for el in root:
        if el.tag == 'node':
            nid = int(el.get('id'))
            nodes[nid] = (float(el.get('lon')), float(el.get('lat')))
            t = {c.get('k'): c.get('v') for c in el if c.tag == 'tag'}
            if t:
                ntags[nid] = t
        elif el.tag == 'way':
            ways[int(el.get('id'))] = {
                'nds': [int(c.get('ref')) for c in el if c.tag == 'nd'],
                'tags': {c.get('k'): c.get('v') for c in el if c.tag == 'tag'}}
        elif el.tag == 'relation':
            rels[int(el.get('id'))] = {
                'members': [(c.get('type'), int(c.get('ref')), c.get('role')) for c in el if c.tag == 'member'],
                'tags': {c.get('k'): c.get('v') for c in el if c.tag == 'tag'}}
    return nodes, ntags, ways, rels
