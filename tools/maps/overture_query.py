"""Fetches OpenStreetMap-derived features around Khouribga from the Overture Maps open release on AWS.
Usage: python overture_query.py theme=base/type=infrastructure infra.json   (or theme=buildings/type=building bld.json,
theme=transportation/type=segment roads.json, theme=base/type=land_use landuse.json, theme=base/type=land land.json,
theme=places/type=place places.json)
Needs: pip install s3fs pyarrow shapely"""
import s3fs, pyarrow.dataset as ds, pyarrow.compute as pc, sys, shapely.wkb as W, json, os
fs = s3fs.S3FileSystem(anon=True)
R="overturemaps-us-west-2/release/2026-11-18.0"
theme=sys.argv[1]
d=ds.dataset(f"{R}/{theme}", filesystem=fs, format="parquet")
F=lambda k: pc.field(("bbox",k))
f=(F("xmin")>-7.03)&(F("xmax")<-6.85)&(F("ymin")>32.80)&(F("ymax")<32.93)
if theme.startswith("theme=places"):
    t=d.to_table(filter=f, columns=["names","basic_category","bbox","confidence"])
    out=[{"name":(r["names"] or {}).get("primary"),"cat":r["basic_category"],"x":r["bbox"]["xmin"],"y":r["bbox"]["ymin"],"conf":r["confidence"]} for r in t.to_pylist()]
    json.dump(out,open(sys.argv[2],"w")); print(len(out)); sys.exit()
cols=[c for c in ["id","subtype","class","names","geometry","height","num_floors"] if c in d.schema.names]
t=d.to_table(filter=f, columns=cols)
out=[]
for r in t.to_pylist():
    g=W.loads(r["geometry"])
    out.append({"subtype":r.get("subtype"),"class":r.get("class"),"name":(r.get("names") or {}).get("primary"),"height":r.get("height"),"floors":r.get("num_floors"),"wkt":g.wkt})
json.dump(out,open(sys.argv[2],"w"))
print(len(out))
