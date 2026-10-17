import json,sys,math
legs=[json.loads(l[6:]) for l in open(sys.argv[1]) if l.startswith('@@LEG ')]
def key(l): return (l['from'],l['to'],l.get('plot'))
want=[('hq_garage','hq_entrance'),('hq_entrance','airport_departures'),('hq_garage','airport_departures'),('airport_arrivals','hq_entrance'),('airport_departures','hq_garage'),('hq_entrance','clouddesk'),('clouddesk','hq_entrance'),('hq_entrance','hq_garage'),('pm_limo','pm_hotel'),('pm_limo','pm_helixresearch'),('pm_hotel','pm_airport'),('pm_frontierscience','pm_limo'),('pm_limo','pm_airport')]
for l in legs:
    if (l['from'],l['to']) in want: print(f"{l['from']:>20s} -> {l['to']:<20s} plot={l.get('plot')} len={l['len']:7.1f} dur={l['dur']:6.1f}s  key={l['key']}")
# continuity: max gap, max yaw step
worst=(0,None); worstTurn=(0,None)
for l in legs:
    p=l['pts']
    for i in range(1,len(p)):
        d=math.dist(p[i],p[i-1])
        if d>worst[0]: worst=(d,l['key'])
    for i in range(1,len(p)-1):
        a=(p[i][0]-p[i-1][0],p[i][2]-p[i-1][2]); b=(p[i+1][0]-p[i][0],p[i+1][2]-p[i][2])
        la=math.hypot(*a); lb=math.hypot(*b)
        if la<1e-6 or lb<1e-6: continue
        c=max(-1,min(1,(a[0]*b[0]+a[1]*b[1])/la/lb)); ang=math.degrees(math.acos(c))
        if ang>worstTurn[0]: worstTurn=(ang,l['key'],i,p[i])
print("max point gap",worst); print("max heading step",worstTurn)
print("legs",len(legs),"max dur",max(l['dur'] for l in legs),"min dur",min(l['dur'] for l in legs))
