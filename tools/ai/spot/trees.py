import os
import cv2,numpy as np,json
a=cv2.imread('area.png');H,W=a.shape[:2]
lab=cv2.cvtColor(a,cv2.COLOR_BGR2LAB).astype(np.float32);L=lab[...,0];A=lab[...,1]-128;B=lab[...,2]-128
mm=cv2.blur(L,(7,7)); sd=np.sqrt(np.maximum(cv2.blur(L*L,(7,7))-mm*mm,0))
veg=((((A<-6)&(L<130))|((A<-3)&(L<95)))&((L<100)|(sd>9))).astype(np.uint8)
veg=cv2.morphologyEx(veg,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
veg=cv2.morphologyEx(veg,cv2.MORPH_CLOSE,np.ones((3,3),np.uint8))
Z=json.load(open(os.environ.get('ZONES','zones.json')))
for q in Z.get('manual',[]): cv2.fillPoly(veg,[np.array(q['poly'],np.int32)],0)
d=cv2.distanceTransform(veg,cv2.DIST_L2,5)
pk=(d>=2.5)&(d==cv2.dilate(d,np.ones((9,9),np.uint8)))
n,lb,st,cen=cv2.connectedComponentsWithStats(pk.astype(np.uint8))
T=[]
for i in range(1,n):
    x,y=cen[i]; r=float(d[int(y),int(x)])
    # merge peaks too close
    if any((x-t[0])**2+(y-t[1])**2<(0.8*max(r,t[2]))**2 for t in T): continue
    T.append([float(x),float(y),r])
# a crown seen from above often hangs over the road, but the trunk stands on the pavement:
# trees whose centre is on the road move to the nearest pavement that is neither road nor crown
import os as _os
if _os.path.exists('road.png'):
    rd=(cv2.imread('road.png',0)>0).astype(np.uint8)
    # roads under big crowns: road colour closed over the crown (the crown hides the asphalt)
    rc=((A<-8.5)&(B<9.5)&(L>95)&(L<175)).astype(np.uint8)
    rc=cv2.morphologyEx(rc,cv2.MORPH_OPEN,np.ones((3,3),np.uint8))
    rd=np.maximum(rd,cv2.morphologyEx(rc|veg,cv2.MORPH_CLOSE,np.ones((5,5),np.uint8))&cv2.morphologyEx(rc,cv2.MORPH_CLOSE,np.ones((31,31),np.uint8)))
    n_,lb_,st_,_=cv2.connectedComponentsWithStats(rd,8)
    rd=np.isin(lb_,[i for i in range(1,n_) if st_[i,4]>1500]).astype(np.uint8)
    cv2.imwrite('road_trees.png',rd*255)
    off=(1-rd).astype(np.uint8)
    # target: nearest pavement/ground that is neither road nor crown (a crown can hide the road too)
    blocked=((rd>0)|(veg>0)).astype(np.uint8)
    dist,lab_=cv2.distanceTransformWithLabels(blocked,cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
    ys,xs=np.nonzero(blocked==0)
    idx=np.zeros(lab_.max()+1,np.int64)
    zl=lab_[blocked==0]; idx[zl]=np.arange(len(zl))
    moved=0
    for t in T:
        x,y=int(round(t[0])),int(round(t[1]))
        if 0<=x<W and 0<=y<H and rd[y,x]:
            if t[2]<7: t[2]=-1; continue      # small dark blob on the asphalt = a car or its shadow (user edits)
            k=idx[lab_[y,x]]; nx,ny=float(xs[k]),float(ys[k])
            dx,dy=nx-t[0],ny-t[1]; d=max((dx*dx+dy*dy)**0.5,1e-3)
            t[0],t[1]=nx-dx/d*1.5,ny-dy/d*1.5    # trunk ~0.75 m inside the crown edge, on the pavement
            moved+=1
    print('trees moved off the road',moved)
    T=[t for t in T if t[2]>0]
# small dark blobs hugging a building are wall shadows, not trees (user edits)
import json as _j
if _os.path.exists('pieces.json'):
    bm=np.zeros((H,W),np.uint8)
    for q in _j.load(open('pieces.json')): cv2.fillPoly(bm,[np.array(q['poly'],np.int32)],1)
    near_b=cv2.dilate(bm,np.ones((5,5),np.uint8))
    T=[t for t in T if not (t[2]<4.5 and near_b[int(min(max(t[1],0),H-1)),int(min(max(t[0],0),W-1))])]
# the person's own fixes from the fix board win
T=[t for t in T if not any((t[0]-u)**2+(t[1]-v)**2<16 for u,v in Z.get('tree_remove',[]))]
T+= [list(map(float,t)) for t in Z.get('tree_add',[])]
json.dump(T,open('trees.json','w'))
o=a.copy()
for x,y,r in T: cv2.circle(o,(int(x),int(y)),int(r+0.5),(0,255,255),1)
cv2.imwrite('trees_ov.png',o)
for i,(y,x) in enumerate([(600,0),(0,600)]):
  cv2.imwrite(f'tq{i}.jpg',np.hstack([a[y:y+400,x:x+400],o[y:y+400,x:x+400]]),[cv2.IMWRITE_JPEG_QUALITY,88])
r=np.array([t[2] for t in T])*0.5
print(len(T),'crown radius m pct',np.percentile(r,[10,50,90]))
