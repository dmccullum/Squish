import os, json
ROOT = os.path.dirname(os.path.abspath(__file__))
HEAD = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
def svg(body, defs=''):
    return HEAD + (f'<defs>{defs}</defs>' if defs else '') + body + '</svg>'

def write_icon(name, groups, fill, fill_dark=None):
    d = os.path.join(ROOT, name + '.icon'); a = os.path.join(d, 'Assets')
    os.makedirs(a, exist_ok=True)
    for f in os.listdir(a): os.remove(os.path.join(a, f))
    gj = []
    for g in groups:
        layers = []
        for L in g['layers']:
            open(os.path.join(a, L['name'] + '.svg'), 'w').write(L['svg'])
            lj = {'name': L['name'], 'image-name': L['name'] + '.svg'}
            for k in ('glass', 'fill', 'opacity', 'blend-mode', 'fill-specializations'):
                if k in L: lj[k] = L[k]
            layers.append(lj)
        gj.append({'name': g['name'], 'layers': layers,
                   'shadow': g.get('shadow', {'kind': 'neutral', 'opacity': 0.5}),
                   'specular': g.get('specular', True),
                   'translucency': g.get('translucency', {'enabled': False, 'value': 0}),
                   **({'blur-material': g['blur']} if 'blur' in g else {}),
                   **({'lighting': g['lighting']} if 'lighting' in g else {})})
    j = {'fill': fill, 'groups': gj,
         'supported-platforms': {'circles': ['watchOS'], 'squares': 'shared'}}
    if fill_dark:
        j['fill-specializations'] = [{'value': fill}, {'appearance': 'dark', 'value': fill_dark}]
    json.dump(j, open(os.path.join(d, 'icon.json'), 'w'), indent=2)

def grad(a, b, y0=0, y1=0.8):
    return {'linear-gradient': [a, b], 'orientation': {'start': {'x': 0.5, 'y': y0}, 'stop': {'x': 0.5, 'y': y1}}}

ORANGE = grad('display-p3:1.0,0.62,0.25,1', 'display-p3:0.98,0.33,0.20,1')
ORANGE_DARK = grad('display-p3:0.36,0.14,0.08,1', 'display-p3:0.12,0.05,0.04,1')

# ---------- shared photo art ----------
SKY = '<linearGradient id="sky" x1="0" y1="{y0}" x2="0" y2="{y1}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#2F8CFF"/><stop offset="1" stop-color="#9ADFFF"/></linearGradient>'
def hills(x0, x1, ybase, h):
    # two rolling hills spanning x0..x1, top of hills around ybase-h
    w = x1 - x0
    X = lambda f: x0 + f * w
    back = (f'M{X(-.05)},{ybase+40} L{X(-.05)},{ybase-h*.55} C{X(.15)},{ybase-h*.85} {X(.28)},{ybase-h} {X(.40)},{ybase-h} '
            f'C{X(.52)},{ybase-h} {X(.60)},{ybase-h*.70} {X(.70)},{ybase-h*.62} C{X(.82)},{ybase-h*.54} {X(.95)},{ybase-h*.72} {X(1.05)},{ybase-h*.80} L{X(1.05)},{ybase+40} Z')
    front = (f'M{X(-.05)},{ybase+40} L{X(-.05)},{ybase-h*.30} C{X(.12)},{ybase-h*.42} {X(.26)},{ybase-h*.62} {X(.42)},{ybase-h*.58} '
             f'C{X(.58)},{ybase-h*.54} {X(.70)},{ybase-h*.30} {X(.86)},{ybase-h*.34} C{X(.94)},{ybase-h*.36} {X(1.0)},{ybase-h*.42} {X(1.05)},{ybase-h*.44} L{X(1.05)},{ybase+40} Z')
    return back, front

def photo_layers(clip_d, x0, y0, x1, y1, prefix, sun=(0.74, 0.30, 0.085)):
    w, h = x1 - x0, y1 - y0
    cp = f'<clipPath id="c"><path d="{clip_d}"/></clipPath>'
    sky = svg(f'<path d="{clip_d}" fill="url(#sky)"/>', SKY.format(y0=y0, y1=y1))
    sx, sy, sr = x0 + w * sun[0], y0 + h * sun[1], w * sun[2]
    sunl = svg(f'<g clip-path="url(#c)"><circle cx="{sx}" cy="{sy}" r="{sr}" fill="#FFD43B"/></g>', cp)
    b, f = hills(x0, x1, y1, h * 0.55)
    hl = svg(f'<g clip-path="url(#c)"><path d="{b}" fill="#5FD39B"/><path d="{f}" fill="#19A463"/></g>', cp)
    return [{'name': prefix + '-sky', 'svg': sky}, {'name': prefix + '-sun', 'svg': sunl}, {'name': prefix + '-hills', 'svg': hl}]

def rr(x0, y0, x1, y1, r):
    return (f'M{x0+r},{y0} H{x1-r} A{r},{r} 0 0 1 {x1},{y0+r} V{y1-r} A{r},{r} 0 0 1 {x1-r},{y1} '
            f'H{x0+r} A{r},{r} 0 0 1 {x0},{y1-r} V{y0+r} A{r},{r} 0 0 1 {x0+r},{y0} Z')

def barrel(x0, y0, x1, y1, r, b):
    # rounded rect whose left/right sides bulge outward by b
    my = (y0 + y1) / 2
    return (f'M{x0+r},{y0} H{x1-r} Q{x1},{y0} {x1+b*0.35},{y0+r*0.9} C{x1+b},{y0+(my-y0)*0.6} {x1+b},{y1-(y1-my)*0.6} {x1+b*0.35},{y1-r*0.9} '
            f'Q{x1},{y1} {x1-r},{y1} H{x0+r} Q{x0},{y1} {x0-b*0.35},{y1-r*0.9} C{x0-b},{y1-(y1-my)*0.6} {x0-b},{y0+(my-y0)*0.6} {x0-b*0.35},{y0+r*0.9} Q{x0},{y0} {x0+r},{y0} Z')

def chevron(cx, cy, w, h, t, down=True):
    # filled chevron with thickness t, pointing down (or up)
    s = 1 if down else -1
    pts = [(cx - w/2, cy - s*h/2), (cx, cy + s*h/2 - s*t*0.0), (cx + w/2, cy - s*h/2)]
    # build as thick polyline using stroke -> emulate with path + stroke
    return f'<path d="M{pts[0][0]},{pts[0][1]} L{pts[1][0]},{pts[1][1]} L{pts[2][0]},{pts[2][1]}" fill="none" stroke="#fff" stroke-width="{t}" stroke-linecap="round" stroke-linejoin="round"/>'

def chevron_h(cx, cy, w, h, t, right=True):
    s = 1 if right else -1
    return f'<path d="M{cx - s*w/2},{cy-h/2} L{cx + s*w/2},{cy} L{cx - s*w/2},{cy+h/2}" fill="none" stroke="#fff" stroke-width="{t}" stroke-linecap="round" stroke-linejoin="round"/>'

WHITE = {'solid': 'srgb:1,1,1,1'}


GLASS_T = lambda v, b: {'translucency': {'enabled': True, 'value': v}, 'blur': b}
# ================= A · Glass Press =================
px0, py0, px1, py1 = 196, 300, 828, 724
clip = barrel(px0, py0, px1, py1, 44, 34)
sky, sun, hl = photo_layers(clip, px0, py0, px1, py1, 'a', sun=(0.74, 0.36, 0.07))
write_icon('A-press', [
    {'name': 'Slabs', **GLASS_T(0.55, 0.7),
     'layers': [
        {'name': 'chevrons', 'svg': svg(chevron(512, 214, 132, 46, 30, True) + chevron(512, 810, 132, 46, 30, False)),
         'fill': {'solid': 'display-p3:0.98,0.40,0.20,1'}},
        {'name': 'slabs', 'glass': True, 'svg': svg(f'<path d="{rr(124,120,900,352,84)}"/><path d="{rr(124,672,900,904,84)}"/>'),
         'fill': WHITE, 'opacity': 0.75},
     ]},
    {'name': 'Land', 'shadow': {'kind': 'layer-color', 'opacity': 0.5}, 'layers': [hl, sun]},
    {'name': 'Sky', **GLASS_T(0.25, 0.3), 'shadow': {'kind': 'layer-color', 'opacity': 0.6}, 'layers': [sky]},
], ORANGE, ORANGE_DARK)

# ================= B · Accordion =================
widths = [112, 46, 112, 46, 112, 46, 112]
total = sum(widths); x = 512 - total / 2
top_hi, top_lo, depth = 286, 326, 412
bx = [x]
for w_ in widths: bx.append(bx[-1] + w_)
def ytop(i): return top_lo if i % 2 == 0 else top_hi
lit, shade = [], []
for i in range(len(widths)):
    xa, xb = bx[i], bx[i+1]
    ya, yb = ytop(i), ytop(i+1)
    d = f'M{xa},{ya} L{xb},{yb} L{xb},{yb+depth} L{xa},{ya+depth} Z'
    (lit if i % 2 == 0 else shade).append(d)
ax0, ax1, ay0, ay1 = bx[0], bx[-1], top_hi, top_lo + depth
def clipped_photo(paths):
    cp = f'<clipPath id="c">' + ''.join(f'<path d="{p}"/>' for p in paths) + '</clipPath>'
    b, f = hills(ax0, ax1, ay1, (ay1 - ay0) * 0.55)
    sx, sy = ax0 + (ax1 - ax0) * 0.72, ay0 + 120
    body = (f'<g clip-path="url(#c)"><rect x="0" y="0" width="1024" height="1024" fill="url(#sky)"/>'
            f'<circle cx="{sx}" cy="{sy}" r="52" fill="#FFD43B"/><path d="{b}" fill="#5FD39B"/><path d="{f}" fill="#19A463"/></g>')
    return svg(body, cp + SKY.format(y0=ay0, y1=ay1))
write_icon('B-accordion', [
    {'name': 'Squeeze', **GLASS_T(0.5, 0.6),
     'layers': [{'name': 'arrows', 'glass': True, 'fill': WHITE,
                 'svg': svg(chevron_h(138, 512, 52, 132, 38, True) + chevron_h(886, 512, 52, 132, 38, False))}]},
    {'name': 'Lit', 'shadow': {'kind': 'layer-color', 'opacity': 0.5}, 'layers': [{'name': 'pleats-lit', 'svg': clipped_photo(lit)}]},
    {'name': 'Folds', **GLASS_T(0.45, 0.5), 'shadow': {'kind': 'neutral', 'opacity': 0.4},
     'layers': [{'name': 'pleats-shaded', 'svg': clipped_photo(shade), 'glass': True}]},
    {'name': 'Ghost', **GLASS_T(0.8, 0.9), 'shadow': {'kind': 'neutral', 'opacity': 0.25},
     'layers': [{'name': 'ghost', 'glass': True, 'fill': WHITE, 'opacity': 0.5, 'svg': svg(f'<path d="{rr(84,318,940,706,56)}"/>')}]},
], ORANGE, ORANGE_DARK)

# ================= C · Clamp =================
STEEL = '<linearGradient id="st" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#D9DDE2"/><stop offset="0.45" stop-color="#FFFFFF"/><stop offset="1" stop-color="#A9B0B8"/></linearGradient>'
frame = 'M196,200 H760 A96,96 0 0 1 856,296 V728 A96,96 0 0 1 760,824 H196 A40,40 0 0 1 156,784 V744 A40,40 0 0 1 196,704 H720 V320 H196 A40,40 0 0 1 156,280 V240 A40,40 0 0 1 196,200 Z'
screw = (f'<rect x="415" y="140" width="52" height="210" rx="14" fill="url(#st)"/>'
         f'<rect x="311" y="118" width="260" height="48" rx="24" fill="#FF6A3D"/>'
         f'<path d="{rr(331,340,551,386,16)}" fill="url(#st)"/>')
cx0, cy0, cx1, cy1 = 214, 386, 668, 696
cclip = barrel(cx0, cy0, cx1, cy1, 30, 22)
csky, csun, chl = photo_layers(cclip, cx0, cy0, cx1, cy1, 'c', sun=(0.74, 0.32, 0.08))
write_icon('C-clamp', [
    {'name': 'Screw', 'layers': [{'name': 'screw', 'svg': svg(screw, STEEL)}]},
    {'name': 'Frame', **GLASS_T(0.5, 0.6), 'layers': [{'name': 'frame', 'glass': True, 'fill': WHITE, 'opacity': 0.85, 'svg': svg(f'<path d="{frame}"/>')}]},
    {'name': 'Land', 'shadow': {'kind': 'layer-color', 'opacity': 0.5}, 'layers': [chl, csun]},
    {'name': 'Sky', **GLASS_T(0.2, 0.3), 'shadow': {'kind': 'layer-color', 'opacity': 0.6}, 'layers': [csky]},
], grad('display-p3:0.20,0.21,0.24,1', 'display-p3:0.07,0.07,0.09,1', 0, 1))
print('ok')
