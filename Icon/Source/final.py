import os, sys, json
here = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(here, 'clamps.py')).read().split("# 1 · Frosted glass")[0])
out = sys.argv[1] if len(sys.argv) > 1 else 'Squish'
handle = svg(f'<path d="{rr(311,118,571,166,24)}"/>')
screw = svg(f'<rect x="415" y="140" width="52" height="210" rx="14" fill="url(#st)"/><path d="{rr(331,340,551,386,16)}" fill="url(#st)"/>', STEEL)
lin = lambda a, b: {'linear-gradient': [a, b], 'orientation': {'start': {'x': 0.5, 'y': 0}, 'stop': {'x': 0.5, 'y': 1}}}
across = lambda a, b: {'linear-gradient': [a, b], 'orientation': {'start': {'x': 0, 'y': 0.5}, 'stop': {'x': 1, 'y': 0.5}}}
write_icon(out, [
    {'name': 'Screw', 'layers': [
        {'name': 'handle', 'svg': handle, 'fill-specializations': [
            {'value': lin('display-p3:0.24,0.24,0.27,1', 'display-p3:0.10,0.10,0.12,1')},
            {'appearance': 'dark', 'value': lin('display-p3:0.78,0.80,0.84,1', 'display-p3:0.52,0.54,0.59,1')},
            {'appearance': 'tinted', 'value': lin('display-p3:1,1,1,1', 'display-p3:0.86,0.87,0.90,1')}]},
        # Gray in light mode so the rod and pad read against the off-white background.
        {'name': 'screw', 'svg': screw, 'fill-specializations': [
            {'value': across('display-p3:0.50,0.51,0.55,1', 'display-p3:0.30,0.31,0.34,1')},
            {'appearance': 'dark', 'value': across('display-p3:0.85,0.87,0.89,1', 'display-p3:0.66,0.69,0.72,1')},
            {'appearance': 'tinted', 'value': across('display-p3:1,1,1,1', 'display-p3:0.86,0.87,0.90,1')}]}]},
    {'name': 'Frame', 'shadow': {'kind': 'layer-color', 'opacity': 0.5},
     'layers': [{'name': 'frame', 'svg': svg(f'<path d="{C_FRAME}"/>'),
                 'fill': grad('display-p3:1.0,0.58,0.22,1', 'display-p3:0.95,0.30,0.16,1', 0, 1)}]},
    *photo_groups(barrel(*C_BOX, 30, 22), C_BOX),
], grad('display-p3:1,0.985,0.97,1', 'display-p3:0.92,0.90,0.88,1', 0, 1))
# Nudge the art right: the photo and screw sit left of the frame's center.
ij = os.path.join(here, out + '.icon', 'icon.json')
j = json.load(open(ij))
for g in j['groups']: g['position'] = {'scale': 1, 'translation-in-points': [24, 0]}
json.dump(j, open(ij, 'w'), indent=2)
print('ok')
