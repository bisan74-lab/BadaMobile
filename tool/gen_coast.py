import json, math

MINLAT, MAXLAT = 21.0, 54.0
MINLON, MAXLON = 112.0, 144.0

def inside(lon, lat):
    return MINLON <= lon <= MAXLON and MINLAT <= lat <= MAXLAT

def iter_lines(gj, prop_filter=None):
    for feat in gj['features']:
        if prop_filter and not prop_filter(feat.get('properties') or {}):
            continue
        g = feat.get('geometry') or {}
        t = g.get('type'); c = g.get('coordinates')
        if t == 'LineString':
            yield c
        elif t == 'MultiLineString':
            for part in c:
                yield part

def clip_runs(coords):
    runs=[]; cur=[]
    for i,(lon,lat) in enumerate(coords):
        if inside(lon,lat):
            if not cur and i>0: cur.append(coords[i-1])
            cur.append((lon,lat))
        else:
            if cur:
                cur.append((lon,lat)); runs.append(cur); cur=[]
    if cur: runs.append(cur)
    return runs

def perp(p,a,b):
    (px,py),(ax,ay),(bx,by)=p,a,b
    dx,dy=bx-ax,by-ay
    if dx==0 and dy==0: return math.hypot(px-ax,py-ay)
    t=max(0,min(1,((px-ax)*dx+(py-ay)*dy)/(dx*dx+dy*dy)))
    return math.hypot(px-(ax+t*dx),py-(ay+t*dy))

def rdp(pts,eps):
    if len(pts)<3: return pts
    dm,idx=0,0
    for i in range(1,len(pts)-1):
        d=perp(pts[i],pts[0],pts[-1])
        if d>dm: dm,idx=d,i
    if dm>eps:
        return rdp(pts[:idx+1],eps)[:-1]+rdp(pts[idx:],eps)
    return [pts[0],pts[-1]]

def extract(files, eps, prop_filter=None, minpts=2):
    out=[]
    for fn in files:
        gj=json.load(open(fn))
        for line in iter_lines(gj, prop_filter):
            if not any(inside(lo,la) for lo,la in line): continue
            for run in clip_runs(line):
                if len(run)<minpts: continue
                s=rdp(run,eps)
                if len(s)>=minpts: out.append(s)
    return out

# 강: 큰 강만(scalerank 낮음)
def river_filter(props):
    sr = props.get('scalerank')
    return sr is None or sr <= 8

layers = {
 '해안선': extract(['ne10_coastline.geojson','ne10_minor_islands.geojson'], 0.010),
 '국경':   extract(['ne_10m_admin_0_boundary_lines_land.geojson'], 0.012),
 '행정':   extract(['ne_10m_admin_1_states_provinces_lines.geojson'], 0.02),
 '강':     extract(['ne_10m_rivers_lake_centerlines.geojson'], 0.014, river_filter),
}
for k,v in layers.items():
    print(k, 'polylines', len(v), 'pts', sum(len(p) for p in v))

with open('country_borders_data.dart','w') as f:
    f.write("// 자동 생성: Natural Earth 10m 해안선·소형섬·국경선·행정경계(주/성)·주요 하천\n")
    f.write("// (공개 도메인)에서 위도 %.0f~%.0f, 경도 %.0f~%.0f을 클리핑·단순화한 좌표.\n"%(MINLAT,MAXLAT,MINLON,MAXLON))
    f.write("// 출처: https://github.com/nvkelso/natural-earth-vector (Natural Earth, Public Domain)\n")
    f.write("// scratchpad/gen_coast2.py로 재생성. 키: 해안선(항상)·국경(항상)·행정/강(확대 시).\n")
    f.write("const Map<String, List<List<(double lat, double lon)>>> countryBorders = {\n")
    for k,polys in layers.items():
        f.write("  '%s': [\n"%k)
        for p in polys:
            f.write("    [\n")
            for lon,lat in p:
                f.write("      (%.3f, %.3f),\n"%(lat,lon))
            f.write("    ],\n")
        f.write("  ],\n")
    f.write("};\n")
import os
print("dart bytes", os.path.getsize('country_borders_data.dart'))
