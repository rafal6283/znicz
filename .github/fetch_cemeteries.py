#!/usr/bin/env python3
"""Pobiera z OpenStreetMap (Overpass) cmentarze w promieniu R km od punktu i zapisuje je
jako wbudowany katalog aplikacji: assets/cmentarze_okolica.json.

Użycie: python3 .github/fetch_cemeteries.py [lat] [lng] [promień_km]
Domyślnie: Celestynów, 50 km.
"""
import json
import math
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

LAT = float(sys.argv[1]) if len(sys.argv) > 1 else 52.0590
LNG = float(sys.argv[2]) if len(sys.argv) > 2 else 21.3890
RADIUS_KM = float(sys.argv[3]) if len(sys.argv) > 3 else 50
OUT = Path(__file__).resolve().parent.parent / 'assets' / 'cmentarze_okolica.json'

ENDPOINTS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
]

KEEP_TAGS = ['name', 'official_name', 'alt_name', 'religion', 'denomination', 'cemetery', 'operator', 'historic',
             'heritage', 'addr:city', 'addr:place', 'addr:street', 'addr:housenumber', 'addr:postcode', 'website',
             'contact:website', 'phone', 'contact:phone', 'opening_hours', 'start_date', 'wikipedia', 'wikidata']


def overpass(q):
    last = None
    for url in ENDPOINTS:
        for attempt in range(2):
            try:
                req = urllib.request.Request(url, data=urllib.parse.urlencode({'data': q}).encode(),
                                             headers={'User-Agent': 'Znicz/1.0 (katalog cmentarzy, prywatna aplikacja)'})
                with urllib.request.urlopen(req, timeout=240) as r:
                    return json.loads(r.read().decode('utf-8'))
            except Exception as e:  # noqa: BLE001
                last = e
                print(f'{url}: {e}', file=sys.stderr)
                time.sleep(10)
    raise SystemExit(f'Overpass niedostępny: {last}')


def dist_km(a_lat, a_lng, b_lat, b_lng):
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = p2 - p1, math.radians(b_lng - a_lng)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def point_in_poly(lat, lng, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        yi, xi = poly[i]
        yj, xj = poly[j]
        if (yi > lat) != (yj > lat) and lng < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def area_ha(poly):
    if len(poly) < 3:
        return 0.0
    lat0 = poly[0][0]
    kx, ky = 111320 * math.cos(math.radians(lat0)), 110540.0
    a = 0.0
    j = len(poly) - 1
    for i in range(len(poly)):
        a += (poly[j][1] * kx) * (poly[i][0] * ky) - (poly[i][1] * kx) * (poly[j][0] * ky)
        j = i
    return abs(a) / 2 / 10000


def simplify(poly, tol_m=2.0, max_pts=80):
    """Ramer–Douglas–Peucker w metrach + limit punktów (rozmiar pliku w aplikacji)."""
    if len(poly) <= 4:
        return poly
    lat0 = poly[0][0]
    kx, ky = 111320 * math.cos(math.radians(lat0)), 110540.0
    pts = [(p[1] * kx, p[0] * ky) for p in poly]

    tol = tol_m
    while True:
        keep = [False] * len(pts)
        keep[0] = keep[-1] = True

        def rdp(lo, hi, tol=tol):
            (x1, y1), (x2, y2) = pts[lo], pts[hi]
            dx, dy = x2 - x1, y2 - y1
            norm = math.hypot(dx, dy) or 1e-9
            best, idx = 0.0, -1
            for k in range(lo + 1, hi):
                x0, y0 = pts[k]
                d = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1) / norm
                if d > best:
                    best, idx = d, k
            if best > tol and idx > 0:
                keep[idx] = True
                rdp(lo, idx)
                rdp(idx, hi)

        rdp(0, len(pts) - 1)
        out = [poly[i] for i in range(len(poly)) if keep[i]]
        if len(out) <= max_pts:
            return out
        tol *= 1.6


def fold(s):
    tr = str.maketrans('ąćęłńóśźżĄĆĘŁŃÓŚŹŻ', 'acelnoszzACELNOSZZ')
    return s.translate(tr).lower()


def nominatim_town(lat, lng):
    """Miejscowość punktu wg granic administracyjnych (Nominatim, max 1 zapytanie/s)."""
    url = ('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=14&accept-language=pl'
           f'&lat={lat:.6f}&lon={lng:.6f}')
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Znicz/1.0 (katalog cmentarzy, jednorazowe pobranie)'})
        with urllib.request.urlopen(req, timeout=30) as r:
            a = json.loads(r.read().decode('utf-8')).get('address', {})
        for k in ('village', 'town', 'city', 'hamlet', 'suburb', 'municipality'):
            if a.get(k):
                return a[k]
    except Exception as e:  # noqa: BLE001
        print(f'Nominatim {lat},{lng}: {e}', file=sys.stderr)
    finally:
        time.sleep(1.1)
    return None


def town_from_name(name, cands):
    """Miejscowość wymieniona w nazwie cmentarza („…w Otwocku”, „Parafia Grzebowilk”)."""
    if not name:
        return None
    n = fold(name)
    best = None
    for pname in cands:
        f = fold(pname)
        stem = f[:max(4, len(f) - 2)] if len(f) > 5 else f
        if len(stem) >= 4 and stem in n and (best is None or len(f) > len(fold(best))):
            best = pname
    return best


def kind_of(tags):
    r = ' '.join(tags.get(k, '') for k in ('religion', 'denomination', 'cemetery', 'historic')).lower()
    op = tags.get('operator', '').lower()
    name = tags.get('name', '').lower()
    if 'military' in r or 'war' in r or 'wojenn' in name or 'wojsk' in name or 'żołnier' in name:
        return 'wojskowy'
    if 'jewish' in r or 'żydow' in name:
        return 'żydowski'
    if 'orthodox' in r or 'prawosław' in name:
        return 'prawosławny'
    if 'lutheran' in r or 'protestant' in r or 'evangelical' in r or 'ewangel' in name:
        return 'ewangelicki'
    if 'komunaln' in name or 'gmin' in op or 'miast' in op or 'komunal' in op:
        return 'komunalny'
    if 'parafi' in op or 'parafi' in name or 'catholic' in r or 'christian' in r:
        return 'parafialny'
    return None


def main():
    radius_m = int(RADIUS_KM * 1000)
    a = f'(around:{radius_m},{LAT},{LNG})'
    q = (f'[out:json][timeout:220];('
         f'way["landuse"="cemetery"]{a};relation["landuse"="cemetery"]{a};'
         f'way["amenity"="grave_yard"]{a};relation["amenity"="grave_yard"]{a};node["amenity"="grave_yard"]{a};'
         f');out geom;')
    data = overpass(q)
    print(f'Elementów cmentarzy: {len(data["elements"])}')
    time.sleep(5)
    pq = (f'[out:json][timeout:120];'
          f'node["place"~"^(city|town|village|suburb|quarter|hamlet)$"]["name"](around:{radius_m + 5000},{LAT},{LNG});out;')
    places = [(e['lat'], e['lon'], e['tags']['name'], e['tags']['place']) for e in overpass(pq)['elements']]
    print(f'Miejscowości: {len(places)}')

    items = {}
    for el in data['elements']:
        t = el['type']
        tags = el.get('tags', {})
        if tags.get('animal') in ('yes', 'pets') or tags.get('cemetery') == 'animal' or 'zwierz' in tags.get('name', '').lower():
            continue  # cmentarze dla zwierząt
        outline = []
        if t == 'way':
            outline = [(g['lat'], g['lon']) for g in el.get('geometry', [])]
        elif t == 'relation':
            for m in el.get('members', []):
                if m.get('type') != 'way' or m.get('role', 'outer') == 'inner':
                    continue
                pts = [(g['lat'], g['lon']) for g in m.get('geometry', [])]
                if len(pts) > len(outline):
                    outline = pts
        if t == 'node':
            c_lat, c_lng = el['lat'], el['lon']
        elif outline:
            c_lat = sum(p[0] for p in outline) / len(outline)
            c_lng = sum(p[1] for p in outline) / len(outline)
        else:
            continue
        if len(outline) > 1 and outline[0] == outline[-1]:
            outline = outline[:-1]
        items[f'{t}/{el["id"]}'] = {'id': f'{t}/{el["id"]}', 'tags': tags, 'outline': outline, 'lat': c_lat, 'lng': c_lng}

    # ten sam cmentarz oznaczony podwójnie (landuse + amenity) – zostaw większy obrys
    ordered = sorted(items.values(), key=lambda c: -area_ha(c['outline']))
    kept = []
    for c in ordered:
        dup = None
        for k in kept:
            if len(k['outline']) >= 3 and point_in_poly(c['lat'], c['lng'], k['outline']):
                dup = k
                break
        if dup is not None:
            # przenieś brakujące tagi (np. nazwę z amenity=grave_yard na landuse=cemetery)
            for key, v in c['tags'].items():
                dup['tags'].setdefault(key, v)
            continue
        kept.append(c)

    out = []
    for c in kept:
        tags = c['tags']
        ha = area_ha(c['outline'])
        if 0 < ha < 0.02 and not tags.get('name'):
            continue  # pojedyncze mogiły / kwatery bez nazwy
        d = dist_km(LAT, LNG, c['lat'], c['lng'])
        if d > RADIUS_KM:
            continue
        town = tags.get('addr:city') or tags.get('addr:place')
        if not town:
            near = [p[2] for p in places if dist_km(c['lat'], c['lng'], p[0], p[1]) < 10]
            town = town_from_name(tags.get('name') or tags.get('official_name'), near)
        if not town:
            town = nominatim_town(c['lat'], c['lng'])
        if not town and places:
            # najbliższa miejscowość (przysiółki tylko gdy nic innego nie ma w pobliżu)
            best = None
            for (plat, plng, pname, ptype) in places:
                dd = dist_km(c['lat'], c['lng'], plat, plng) * (1.6 if ptype == 'hamlet' else 1.0)
                if best is None or dd < best[0]:
                    best = (dd, pname)
            if best and best[0] < 6:
                town = best[1]
        kept_tags = {k: tags[k] for k in KEEP_TAGS if k in tags}
        if town:
            kept_tags['znicz:town'] = town
        kind = kind_of(tags)
        if kind:
            kept_tags['znicz:kind'] = kind
        outline = simplify(c['outline']) if len(c['outline']) >= 3 else []
        out.append({
            'id': c['id'],
            'lat': round(c['lat'], 6),
            'lng': round(c['lng'], 6),
            'd': round(d, 1),
            'ha': round(ha, 2),
            'tags': kept_tags,
            'o': [[round(p[0], 6), round(p[1], 6)] for p in outline],
        })
    out.sort(key=lambda c: c['d'])
    meta = {
        'format': 'znicz-katalog-cmentarzy',
        'center': [LAT, LNG],
        'radius_km': RADIUS_KM,
        'generated': time.strftime('%Y-%m-%d'),
        'source': '© współtwórcy OpenStreetMap (ODbL)',
        'count': len(out),
        'items': out,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(meta, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    named = sum(1 for c in out if c['tags'].get('name'))
    print(f'Zapisano {len(out)} cmentarzy ({named} z nazwą) do {OUT} ({OUT.stat().st_size // 1024} KB)')
    kinds = {}
    for c in out:
        k = c['tags'].get('znicz:kind', '?')
        kinds[k] = kinds.get(k, 0) + 1
    print('Rodzaje:', kinds)


if __name__ == '__main__':
    main()
