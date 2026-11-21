import os
import cv2, numpy as np, json
from skimage.segmentation import watershed
a=cv2.imread('area.png'); H,W=a.shape[:2]
lab=cv2.cvtColor(a,cv2.COLOR_BGR2LAB).astype(np.float32); L,A,B=lab[...,0],lab[...,1]-128,lab[...,2]-128
sat=np.hypot(A,B)
Z=json.load(open(os.environ.get('ZONES','zones.json')))
zone=np.zeros((H,W),np.uint8)
for p in Z['include'][:2]: cv2.fillPoly(zone,[np.array(p,np.int32)],1)
infz=np.zeros((H,W),np.uint8); cv2.fillPoly(infz,[np.array(Z['include'][2],np.int32)],1); zone[infz>0]=0
for p in Z.get('extra',[]): cv2.fillPoly(zone,[np.array(p,np.int32)],1)
for p in Z.get('exclude',[]): cv2.fillPoly(zone,[np.array(p,np.int32)],0)
veg=((A<-6)&(L<130))|((A<-3)&(L<90))
veg=cv2.morphologyEx(veg.astype(np.uint8),cv2.MORPH_OPEN,np.ones((3,3),np.uint8)).astype(bool)
shadow=(L<95)&~veg
shadow_core=(L<80)&~veg
road=((sat<8)&(L>70)&(L<140)).astype(np.uint8)
road=cv2.morphologyEx(road,cv2.MORPH_OPEN,np.ones((7,7),np.uint8))
n,lb,st,_=cv2.connectedComponentsWithStats(road,8)
road=np.isin(lb,[i for i in range(1,n) if st[i,4]>3000])
road=cv2.dilate(road.astype(np.uint8),np.ones((3,3),np.uint8)).astype(bool)
loc=cv2.blur(L,(41,41))
red=(A>9)&(L>85)&(L<200)
sdm=cv2.blur(L,(7,7)); sd=np.sqrt(np.maximum(cv2.blur(L*L,(7,7))-sdm*sdm,0))
sand=(sd<6)&(B>14.5)&(A>-3)&(L>150)
sand=cv2.morphologyEx(sand.astype(np.uint8),cv2.MORPH_OPEN,np.ones((3,3),np.uint8)).astype(bool)
cand=((L>loc+2)|red)&~sand&~veg&~shadow_core&~(shadow&(L<loc-10))&~road&(zone>0)
cand=cv2.morphologyEx(cand.astype(np.uint8),cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
cand=cv2.morphologyEx(cand,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
# manual edits: remove polygons, add polygons
for p in Z.get('remove',[]): cv2.fillPoly(cand,[np.array(p,np.int32)],0)
for p in Z.get('add',[]): cv2.fillPoly(cand,[np.array(p,np.int32)],1)
for q in Z.get('manual',[]): cv2.fillPoly(cand,[np.array(q['poly'],np.int32)],0)
# split big blobs into house-size pieces
dist=cv2.distanceTransform(cand,cv2.DIST_L2,3)
pk=(dist>=4)&(dist==cv2.dilate(dist,np.ones((15,15),np.uint8)))
mk,_=cv2.connectedComponents(pk.astype(np.uint8))
mk_l=cv2.connectedComponents(pk.astype(np.uint8))[1]
ws=watershed(-dist,mk_l,mask=cand>0)
# dominant grid angle per 120 px window (structure tensor of the gradient, mod 90 deg)
gx=cv2.Sobel(L,cv2.CV_32F,1,0,ksize=3); gy=cv2.Sobel(L,cv2.CV_32F,0,1,ksize=3)
th=np.arctan2(gy,gx); mag=np.hypot(gx,gy)
c4=cv2.blur(mag*np.cos(4*th),(121,121)); s4=cv2.blur(mag*np.sin(4*th),(121,121))
ang_map=np.arctan2(s4,c4)/4.0      # radians, dominant edge direction mod 90
# heights: shadow run west of each piece
pieces=[]
for i in range(1,ws.max()+1):
    m=(ws==i).astype(np.uint8)
    ar=int(m.sum())
    if ar<50: continue   # < 12.5 m2
    cs,_=cv2.findContours(m,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
    c=max(cs,key=cv2.contourArea)
    hull=cv2.convexHull(c); sol=cv2.contourArea(c)/max(cv2.contourArea(hull),1)
    mw=2*ar/max(cv2.arcLength(c,True),1)
    if sol<0.5 or mw<5: continue
    ys0,xs0=np.nonzero(m); sdm_=sd[ys0,xs0].mean()
    if B[ys0,xs0].mean()>15 and sdm_<12 and not red[ys0,xs0].mean()>0.5: continue
    ys,xs=np.nonzero(m)
    cx,cy=xs.mean(),ys.mean(); t=ang_map[int(cy),int(cx)]
    u=np.array([np.cos(t),np.sin(t)]); v=np.array([-u[1],u[0]])
    P=np.stack([xs-cx,ys-cy],1); pu=P@u; pv=P@v
    u0,u1=np.percentile(pu,[3,97]); v0,v1=np.percentile(pv,[3,97])
    box=np.array([[u0,v0],[u1,v0],[u1,v1],[u0,v1]])
    rect_area=(u1-u0+1)*(v1-v0+1); rfill=ar/max(rect_area,1)
    P2=np.stack([cx+box[:,0]*u[0]+box[:,1]*v[0], cy+box[:,0]*u[1]+box[:,1]*v[1]],1)
    rm=np.zeros_like(m); cv2.fillPoly(rm,[P2.astype(np.int32)],1); sfr=(sand&(rm>0)).sum()/max(rm.sum(),1)
    if rfill>0.62 and sfr<0.15:
        poly=np.stack([cx+box[:,0]*u[0]+box[:,1]*v[0], cy+box[:,0]*u[1]+box[:,1]*v[1]],1)
    else:
        poly=cv2.approxPolyDP(c,1.2,True).reshape(-1,2)
    y0b,y1b=ys.min(),ys.max()+1; x0b=max(xs.min()-24,0); x1b=xs.max()+1
    sub=m[y0b:y1b,x0b:x1b]
    kk=np.zeros((1,49),np.uint8); kk[0,24:]=1          # spread the piece 24 px to the west
    band=(cv2.dilate(sub,kk,anchor=(24,0))>0)&(sub==0)&(cand[y0b:y1b,x0b:x1b]==0)
    shp=(band&shadow[y0b:y1b,x0b:x1b]).sum()
    rows=max(len(np.unique(ys)),1)
    sh=float(shp)/rows
    pieces.append({'poly':np.asarray(poly,float).tolist(),'area_m2':ar*0.25,'shadow_px':sh,'col':a[ys,xs].mean(0).tolist()})
for q in Z.get('manual',[]): pieces.append({'poly':q['poly'],'area_m2':0,'shadow_px':0,'h':q['h'],'manual':True,'col':[0,0,0]})
json.dump(pieces,open('pieces.json','w'))
ov=a.copy()
for p in pieces:
    pp=np.array(p['poly'],np.int32); cv2.fillPoly(ov,[pp],(255,0,255))
out=cv2.addWeighted(a,0.55,ov,0.45,0)
for p in pieces: cv2.polylines(out,[np.array(p['poly'],np.int32)],True,(255,255,0),1)
cv2.imwrite('b_full.png',out)
cv2.imwrite('sand.png',(sand*255).astype(np.uint8))
print(len(pieces), np.median([p['shadow_px'] for p in pieces if p['shadow_px']>0]))
