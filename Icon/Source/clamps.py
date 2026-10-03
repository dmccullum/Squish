import os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gen.py')).read()
ns = {'__file__': os.path.join(os.path.dirname(os.path.abspath(__file__)), 'gen.py')}
exec(src[:src.index('# ================= A · Glass Press')], ns)
svg, rr, barrel, hills, write_icon, grad, WHITE, ORANGE = (ns[k] for k in ('svg','rr','barrel','hills','write_icon','grad','WHITE','ORANGE'))
DUSK = dict(sky0='#4B5BFF', sky1='#FFB38A', sun='#FFE7A3', h1='#8D63D9', h2='#4A2F8F')
T = lambda v, b: {'translucency': {'enabled': True, 'value': v}, 'blur': b}
STEEL = '<linearGradient id="st" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#D9DDE2"/><stop offset="0.45" stop-color="#FFFFFF"/><stop offset="1" stop-color="#A9B0B8"/></linearGradient>'
STEELV = STEEL.replace('id="st"', 'id="sv"').replace('x2="1" y2="0"', 'x2="0" y2="1"')

def vbarrel(x0, y0, x1, y1, r, b):
    # rounded rect whose top/bottom bulge outward by b
    mx = (x0 + x1) / 2
    return (f'M{x0},{y0+r} Q{x0},{y0} {x0+r*0.9},{y0-b*0.35} C{x0+(mx-x0)*0.6},{y0-b} {x1-(x1-mx)*0.6},{y0-b} {x1-r*0.9},{y0-b*0.35} '
            f'Q{x1},{y0} {x1},{y0+r} V{y1-r} Q{x1},{y1} {x1-r*0.9},{y1+b*0.35} C{x1-(x1-mx)*0.6},{y1+b} {x0+(mx-x0)*0.6},{y1+b} {x0+r*0.9},{y1+b*0.35} '
            f'Q{x0},{y1} {x0},{y1-r} Z')

def photo(clip_d, x0, y0, x1, y1, pal=DUSK, sun=(0.72, 0.32, 0.08)):
    w, h = x1 - x0, y1 - y0
    cp = f'<clipPath id="c"><path d="{clip_d}"/></clipPath>'
    g = f'<linearGradient id="sky" x1="0" y1="{y0}" x2="0" y2="{y1}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{pal["sky0"]}"/><stop offset="1" stop-color="{pal["sky1"]}"/></linearGradient>'
    sky = {'name': 'sky', 'svg': svg(f'<path d="{clip_d}" fill="url(#sky)"/>', g)}
    sx, sy, sr = x0 + w * sun[0], y0 + h * sun[1], min(w, h) * sun[2] * 1.3
    sunl = {'name': 'sun', 'svg': svg(f'<g clip-path="url(#c)"><circle cx="{sx}" cy="{sy}" r="{sr}" fill="{pal["sun"]}"/></g>', cp)}
    b, f = hills(x0 - 40, x1 + 40, y1 + 30, h * 0.55)
    hl = {'name': 'hills', 'svg': svg(f'<g clip-path="url(#c)"><path d="{b}" fill="{pal["h1"]}"/><path d="{f}" fill="{pal["h2"]}"/></g>', cp)}
    return [hl, sun_l] if False else (sky, sunl, hl)

def photo_groups(clip, box, **kw):
    sky, sun, hl = photo(clip, *box, **kw)
    return [{'name': 'Land', 'shadow': {'kind': 'layer-color', 'opacity': 0.5}, 'layers': [hl, sun]},
            {'name': 'Sky', **T(0.2, 0.3), 'shadow': {'kind': 'layer-color', 'opacity': 0.6}, 'layers': [sky]}]

C_FRAME = 'M196,200 H760 A96,96 0 0 1 856,296 V728 A96,96 0 0 1 760,824 H196 A40,40 0 0 1 156,784 V744 A40,40 0 0 1 196,704 H720 V320 H196 A40,40 0 0 1 156,280 V240 A40,40 0 0 1 196,200 Z'
C_BOX = (214, 386, 668, 696)
def c_screw(handle='#FF6A3D'):
    return svg(f'<rect x="415" y="140" width="52" height="210" rx="14" fill="url(#st)"/>'
               f'<rect x="311" y="118" width="260" height="48" rx="24" fill="{handle}"/>'
               f'<path d="{rr(331,340,551,386,16)}" fill="url(#st)"/>', STEEL)

# 1 · Frosted glass C-clamp on tangerine (brand-matched with icon A)
write_icon('C1-glass-orange', [
    {'name': 'Screw', 'layers': [{'name': 'screw', 'svg': c_screw('#4B5BFF')}]},
    {'name': 'Frame', **T(0.55, 0.7), 'layers': [{'name': 'frame', 'glass': True, 'fill': WHITE, 'opacity': 0.8, 'svg': svg(f'<path d="{C_FRAME}"/>')}]},
    *photo_groups(barrel(*C_BOX, 30, 22), C_BOX),
], ORANGE)

# 2 · Hardware-store orange C-clamp on warm white
write_icon('C2-orange-tool', [
    {'name': 'Screw', 'layers': [{'name': 'screw', 'svg': c_screw('#2B2B30')}]},
    {'name': 'Frame', 'shadow': {'kind': 'layer-color', 'opacity': 0.5},
     'layers': [{'name': 'frame', 'svg': svg(f'<path d="{C_FRAME}"/>'),
                 'fill': grad('display-p3:1.0,0.58,0.22,1', 'display-p3:0.95,0.30,0.16,1', 0, 1)}]},
    *photo_groups(barrel(*C_BOX, 30, 22), C_BOX),
], grad('display-p3:1,0.985,0.97,1', 'display-p3:0.92,0.90,0.88,1', 0, 1))

# 3 · F-clamp (bar clamp) on graphite, squeezing top-to-bottom
F_BOX = (330, 316, 830, 708)
fbar = rr(170, 110, 236, 914, 24)
fjaws = rr(170, 206, 708, 276, 30) + ' ' + rr(170, 748, 708, 818, 30)
fpads = rr(500, 272, 660, 316, 14) + ' ' + rr(500, 708, 660, 752, 14)
write_icon('C3-f-clamp', [
    {'name': 'Grip', 'layers': [
        {'name': 'pads', 'svg': svg(f'<path d="{fpads}" fill="url(#st)"/>', STEEL)},
        {'name': 'grip', 'svg': svg(f'<path d="{rr(536,814,624,960,30)}"/>'), 'fill': grad('display-p3:1.0,0.58,0.22,1', 'display-p3:0.95,0.30,0.16,1', 0, 1)}]},
    {'name': 'Jaws', **T(0.5, 0.6), 'layers': [
        {'name': 'jaws', 'glass': True, 'fill': WHITE, 'opacity': 0.85, 'svg': svg(f'<path d="{fjaws}"/>')},
        {'name': 'bar', 'glass': True, 'fill': WHITE, 'opacity': 0.6, 'svg': svg(f'<path d="{fbar}"/>')}]},
    *photo_groups(barrel(*F_BOX, 30, 24), F_BOX),
], grad('display-p3:0.20,0.21,0.24,1', 'display-p3:0.07,0.07,0.09,1', 0, 1))

# 4 · Bench vise squeezing side-to-side, on deep dusk indigo
V_BOX = (300, 330, 676, 690)
jaws = rr(140, 300, 300, 720, 36) + ' ' + rr(676, 300, 836, 720, 36)
teeth = ''.join(f'<rect x="{x}" y="{y}" width="14" height="22" rx="5"/>' for x in (286, 676) for y in range(340, 700, 48))
base = rr(100, 712, 924, 828, 44)
screw = (f'<rect x="836" y="490" width="96" height="44" rx="14" fill="url(#st)"/>'
         f'<rect x="922" y="380" width="40" height="264" rx="20" fill="url(#sv)"/>'
         f'<circle cx="942" cy="380" r="30" fill="#FF6A3D"/><circle cx="942" cy="644" r="30" fill="#FF6A3D"/>')
write_icon('C4-vise', [
    {'name': 'Screw', 'layers': [{'name': 'screw', 'svg': svg(screw, STEEL + STEELV)}]},
    {'name': 'Jaws', **T(0.5, 0.6), 'layers': [
        {'name': 'teeth', 'svg': svg(teeth), 'fill': {'solid': 'display-p3:0.98,0.42,0.22,1'}},
        {'name': 'jaws', 'glass': True, 'fill': WHITE, 'opacity': 0.85, 'svg': svg(f'<path d="{jaws}"/>')},
        {'name': 'base', 'glass': True, 'fill': WHITE, 'opacity': 0.7, 'svg': svg(f'<path d="{base}"/>')}]},
    *photo_groups(vbarrel(*V_BOX, 30, 26), V_BOX, sun=(0.70, 0.30, 0.09)),
], grad('display-p3:0.22,0.20,0.52,1', 'display-p3:0.08,0.07,0.20,1', 0, 1))
print('ok')
