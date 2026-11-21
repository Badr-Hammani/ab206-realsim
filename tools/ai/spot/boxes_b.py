# Option B (user pick 2026-11-21): every house = plain box lined up with its local street grid, no overlaps
# usage: in the spot work folder after build.py/inf.py (pieces.json -> pieces_det.json, inf_cells.json -> inf_det.json),
#        ZONES=<zones.json> python3 boxes_b.py, then merge.py. final_blk.json = blocks picked by eye (optional).
import json,cv2,os,numpy as np
P=json.load(open('pieces_det.json'));I=json.load(open('inf_det.json'))
EYE=json.load(open('final_blk.json')) if os.path.exists('final_blk.json') else [];BX=(600,640,720,760)
inblk=lambda p:BX[0]<=np.mean([q[0] for q in p])<=BX[2] and BX[1]<=np.mean([q[1] for q in p])<=BX[3]
src=[(p['poly'],p.get('col',[0,0,0]),None) for p in P if not inblk(p['poly'])]
src+=[(p['poly'],[0,0,0],3.2) for p in I if not inblk(p['poly'])]
src+=[(p,[0,0,0],None) for p in EYE]
src=[(np.array(p,np.float32),c,h) for p,c,h in src if len(p)>=3 and cv2.contourArea(np.array(p,np.float32))>10]
cen=np.array([p.mean(0) for p,_,_ in src])
ang=[];wt=[]
for p,_,_ in src:
  (c,(w,h),a)=cv2.minAreaRect(p);ang.append(np.deg2rad((a%90)*4));wt.append(w*h)
ang=np.array(ang);wt=np.array(wt)
def local_angle(c):
  d=np.hypot(*(cen-c).T);k=(d<120)
  z=np.sum(wt[k]*np.exp(1j*ang[k]))      # circular mean of 90-degree-periodic angles
  return (np.rad2deg(np.angle(z))/4)%90
def pbox(p,a,lo=8,hi=92):
  R=cv2.getRotationMatrix2D((0,0),a,1);Ri=cv2.invertAffineTransform(R)
  m=np.zeros((1,1));q=cv2.transform(p[None],R)[0];mn,mx=q.min(0),q.max(0)
  xs,ys=np.meshgrid(np.linspace(mn[0],mx[0],25),np.linspace(mn[1],mx[1],25))
  g=np.stack([xs.ravel(),ys.ravel()],1).astype(np.float32);w=cv2.transform(g[None],Ri)[0]
  ins=np.array([cv2.pointPolygonTest(p,(float(x),float(y)),False)>=0 for x,y in w])
  if ins.sum()<4: return None
  G=g[ins];lo_,hi_=np.percentile(G,lo,0),np.percentile(G,hi,0)
  if (hi_-lo_).min()<4: return None   # thinner than 2 m: not a house
  return a,lo_,hi_
boxes=[]
for (p,c,h) in src:
  a=local_angle(p.mean(0))
  if h==3.2: continue
  if False:   # big village patch: fill with ~8 m single-storey houses
    R=cv2.getRotationMatrix2D((0,0),a,1);Ri=cv2.invertAffineTransform(R)
    q=cv2.transform(p[None],R)[0];mn,mx=q.min(0),q.max(0)
    for x in np.arange(mn[0],mx[0],18):
      for y in np.arange(mn[1],mx[1],18):
        cc=cv2.transform(np.array([[[x+8,y+8]]],np.float32),Ri)[0,0]
        if cv2.pointPolygonTest(p,(float(cc[0]),float(cc[1])),True)>=4:
          boxes.append(((a,np.array([x+1,y+1]),np.array([x+16,y+16])),c,h))
    continue
  b=pbox(p,a)
  if b: boxes.append((b,c,h))
def poly(b):
  a,lo,hi=b;Ri=cv2.invertAffineTransform(cv2.getRotationMatrix2D((0,0),a,1))
  return cv2.transform(np.array([[[lo[0],lo[1]],[hi[0],lo[1]],[hi[0],hi[1]],[lo[0],hi[1]]]],np.float32),Ri)[0]
# village: fill the informal zone with ~8 m single-storey houses wherever the photo is built-up
import os
Z=json.load(open(os.environ['ZONES']));V=np.array(Z['include'][2],np.float32)
img=cv2.imread('area.png');lab=cv2.cvtColor(img,cv2.COLOR_BGR2LAB).astype(np.float32)
Lc,Ac,Bc=lab[:,:,0],lab[:,:,1]-128,lab[:,:,2]-128
sd=cv2.blur(Lc*Lc,(9,9))-cv2.blur(Lc,(9,9))**2;sd=np.sqrt(np.maximum(sd,0))
ground=(Bc>14)&(Ac>-4)&(Lc>140)&(sd<10)
veg=(Ac<-6)&(Lc<130)
road=cv2.imread('road.png',0)>0 if os.path.exists('road.png') else np.zeros_like(ground)
vm=np.zeros(Lc.shape,np.uint8);cv2.fillPoly(vm,[V.astype(np.int32)],1)
for rp in Z.get('remove',[]): cv2.fillPoly(vm,[np.array(rp,np.int32)],0)
a=local_angle(V.mean(0));R=cv2.getRotationMatrix2D((0,0),a,1);Ri=cv2.invertAffineTransform(R)
q=cv2.transform(V[None],R)[0];mn,mx=q.min(0),q.max(0);nv=0
for x in np.arange(mn[0],mx[0],17):
  for y in np.arange(mn[1],mx[1],17):
    cc=cv2.transform(np.array([[[x+1,y+1],[x+16,y+1],[x+16,y+16],[x+1,y+16]]],np.float32),Ri)[0]
    m=np.zeros(Lc.shape,np.uint8);cv2.fillPoly(m,[cc.astype(np.int32)],1);k=m>0
    if k.sum()<100 or vm[k].mean()<0.9: continue
    if ground[k].mean()>0.35 or veg[k].mean()>0.35 or road[k].mean()>0.1: continue
    boxes.append(((a,np.array([x+1,y+1]),np.array([x+16,y+16])),[0,0,0],3.2));nv+=1
print('village boxes',nv)
boxes.sort(key=lambda t:-np.prod(t[0][2]-t[0][1]))
S=1200*2;occ=np.zeros((S,S),np.uint8);out=[]
for b,c,h in boxes:
  q=poly(b);m=np.zeros_like(occ);cv2.fillPoly(m,[(q*2).astype(np.int32)],1)
  a=m.sum()
  if a==0: continue
  if (m&occ).sum()>0.2*a: continue
  occ|=m
  out.append({'poly':[[round(float(x),1),round(float(y),1)] for x,y in q],'area_m2':round(a/16,1),'col':c,**({'manual':True,'h':h} if h else {})})
C=np.array([np.mean(o['poly'],0) for o in out])
keep=[]
for i,o in enumerate(out):
  d=np.hypot(*(C-C[i]).T);d[i]=1e9
  if o['area_m2']<40 and d.min()>30: continue   # lone small box on open ground
  keep.append(o)
out=keep
json.dump(out,open('pieces.json','w'));json.dump([],open('inf_cells.json','w'))
print(len(src),'->',len(out),'boxes')
