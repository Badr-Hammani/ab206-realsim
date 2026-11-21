import json,cv2,numpy as np,os,sys
from skimage.segmentation import slic
from sklearn.ensemble import RandomForestClassifier
a=cv2.imread('area_sr.png'); H,W=a.shape[:2]   # 2x, 0.25 m/px
lab=cv2.cvtColor(a,cv2.COLOR_BGR2LAB).astype(np.float32);L,A,B=lab[...,0],lab[...,1]-128,lab[...,2]-128
Z=json.load(open('zones_raw.json'));G=json.load(open('gt_user.json'))
zone=np.zeros((H,W),np.uint8)
for p in Z['include'][:2]+Z.get('extra',[]): cv2.fillPoly(zone,[(np.array(p)*2).astype(np.int32)],1)
inf=np.zeros((H,W),np.uint8);cv2.fillPoly(inf,[(np.array(Z['include'][2])*2).astype(np.int32)],1);zone[inf>0]=0
def mask(polys,s=2):
    z=np.zeros((H,W),np.uint8)
    for p in polys: cv2.fillPoly(z,[(np.array(p)*s).astype(np.int32)],1)
    return z
road=cv2.resize(cv2.imread('road.png',0),(W,H))>0
veg=((A<-6)&(L<130))|((A<-3)&(L<95))
loc=cv2.blur(L,(41,41)); dark=(L<loc-15)&~veg
def sdk(k):
    m=cv2.blur(L,(k,k));return np.sqrt(np.maximum(cv2.blur(L*L,(k,k))-m*m,0))
sd5,sd15=sdk(5),sdk(15)
ed=cv2.Canny(a,60,140)>0
droad=cv2.distanceTransform((~road).astype(np.uint8),cv2.DIST_L2,5)
seg=slic(a[...,::-1],n_segments=int(zone.sum()/180),compactness=12,start_label=1,mask=zone>0)
n=seg.max()+1
idx=seg.ravel()
cnt=np.bincount(idx,minlength=n).astype(np.float32)+1e-6
def mean(v): return np.bincount(idx,weights=v.ravel().astype(np.float64),minlength=n)/cnt
feats=[mean(L),mean(A),mean(B),mean(sd5),mean(sd15),mean(ed),mean(np.minimum(droad,60)),mean(veg),mean(dark),mean(L-loc)]
# dark ring around each superpixel: dilate label boundaries
ringdark=np.zeros(n)
dil=cv2.dilate(seg.astype(np.float32),np.ones((7,7),np.uint8)).astype(np.int32)
er=cv2.erode(seg.astype(np.float32),np.ones((7,7),np.uint8)).astype(np.int32)
bd=(dil!=seg)|(er!=seg)
# mean darkness in a 7px neighbourhood of each segment
dn=cv2.blur(dark.astype(np.float32),(15,15))
feats.append(mean(dn))
X=np.stack(feats,1)
np.savez_compressed('rf_feats.npz',X=X,seg=seg,zone=zone,fr=mean(road),fv=mean(veg),lots=mean(mask(Z['remove'][:5])))
