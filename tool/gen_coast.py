import json, math

MINLAT, MAXLAT = 26.5, 45.5
MINLON, MAXLON = 118.5, 136.5

def inside(lon, lat):
    return MINLON <= lon <= MAXLON and MINLAT <= lat <= MAXLAT

def iter_lines(gj):
    for feat in gj['features']:
        g = feat.get('geometry') or {}
        t = g.get('type'); c = g.get('coordinates')
        if t == 'LineString':
            yield c
        elif t == 'MultiLineString':
            for part in c:
                yield part

def clip_runs(coords):
    """Split a linestring into contiguous runs of points inside bbox.
    Include one boundary-crossing neighbor so lines reach the edge."""
    runs = []
    cur = []
    n = len(coords)
    for i,(lon,lat) in enumerate(coords):
        if inside(lon,lat):
            if not cur:
                # include previous point (outside) so the line extends to edge
                if i>0:
                    cur.append(coords[i-1])
            cur.append((lon,lat))
        else:
            if cur:
                cur.append((lon,lat))  # include this outside point to reach edge
                runs.append(cur); cur=[]
    if cur: runs.append(cur)
    return runs

def perp_dist(p, a, b):
    (px,py),(ax,ay),(bx,by)=p,a,b
    dx,dy=bx-ax,by-ay
    if dx==0 and dy==0: return math.hypot(px-ax,py-ay)
    t=((px-ax)*dx+(py-ay)*dy)/(dx*dx+dy*dy)
    t=max(0,min(1,t))
    cx,cy=ax+t*dx,ay+t*dy
    return math.hypot(px-cx,py-cy)

def rdp(pts, eps):
    if len(pts)<3: return pts
    dmax,idx=0,0
    for i in range(1,len(pts)-1):
        d=perp_dist(pts[i],pts[0],pts[-1])
        if d>dmax: dmax,idx=d,i
    if dmax>eps:
        left=rdp(pts[:idx+1],eps); right=rdp(pts[idx:],eps)
        return left[:-1]+right
    return [pts[0],pts[-1]]

EPS=0.012  # simplification tolerance in degrees (~1.3km)
MINPTS=2

polylines=[]
stats={'main':0,'minor':0}
for fname,key in [('ne10_coastline.geojson','main'),('ne10_minor_islands.geojson','minor')]:
    gj=json.load(open(fname))
    for line in iter_lines(gj):
        # quick reject: bounding
        if not any(inside(lon,lat) for lon,lat in line): 
            continue
        for run in clip_runs(line):
            if len(run)<MINPTS: continue
            simp=rdp(run,EPS)
            if len(simp)>=MINPTS:
                polylines.append(simp)
                stats[key]+=1

# stats
tot_pts=sum(len(p) for p in polylines)
print("polylines:",len(polylines),"main runs:",stats['main'],"minor runs:",stats['minor'],"total points:",tot_pts)

# write dart
with open('country_borders_data.dart','w') as f:
    f.write("// 자동 생성: Natural Earth 10m 해안선 + 소형 섬 해안선(공개 도메인)에서\n")
    f.write("// 한반도 주변(위도 %.1f~%.1f, 경도 %.1f~%.1f)을 bbox로 클리핑·단순화(RDP %.3f°)한 좌표.\n" % (MINLAT,MAXLAT,MINLON,MAXLON,EPS))
    f.write("// 출처: https://github.com/nvkelso/natural-earth-vector (Natural Earth, Public Domain)\n")
    f.write("// 실제 해안선·섬을 그대로 담아 지도가 실제 지형과 일치한다.\n")
    f.write("const Map<String, List<List<(double lat, double lon)>>> countryBorders = {\n")
    f.write("  '해안선': [\n")
    for p in polylines:
        f.write("    [\n")
        for lon,lat in p:
            f.write("      (%.3f, %.3f),\n" % (lat,lon))
        f.write("    ],\n")
    f.write("  ],\n")
    f.write("};\n")
print("wrote country_borders_data.dart")
import os
print("dart file size:", os.path.getsize('country_borders_data.dart'))
