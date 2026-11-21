import json,cv2,numpy as np,sys
from sklearn.ensemble import RandomForestClassifier
d=np.load('rf_feats.npz');X,seg,zone=d['X'],d['seg'],d['zone'];H,W=seg.shape;n=seg.max()+1
G=json.load(open('gt_user.json'))
fold=sys.argv[1] if len(sys.argv)>1 else 'all'
def cx(p): return np.mean([q[0] for q in p])
def keep(p): return fold=='all' or (fold=='A' and cx(p)<800) or (fold=='B' and cx(p)>=800)
def mask(polys):
    z=np.zeros((H,W),np.uint8)
    for p in polys: cv2.fillPoly(z,[(np.array(p)*2).astype(np.int32)],1)
    return z
idx=seg.ravel();cnt=np.bincount(idx,minlength=n)+1e-6
mean=lambda v:np.bincount(idx,weights=v.ravel().astype(np.float64),minlength=n)/cnt
pos=mask([p for p in G['pos'] if keep(p)]);neg=mask([p for p in G['neg'] if keep(p)])&(pos==0)
y=np.full(n,-1);y[mean(pos)>0.6]=1;y[mean(neg)>0.6]=0;y[d['fr']>0.7]=0;y[d['fv']>0.7]=0;y[d['lots']>0.6]=0
tr=y>=0
clf=RandomForestClassifier(n_estimators=300,min_samples_leaf=2,class_weight='balanced',random_state=0,n_jobs=-1).fit(X[tr],y[tr])
prob=clf.predict_proba(X)[:,1];prob[0]=0
np.save('rf_prob_%s.npy'%fold,(prob[seg]*(zone>0)).astype(np.float16))
print('fold',fold,'pos',(y==1).sum(),'neg',(y==0).sum())
