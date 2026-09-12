import * as T from './vendor/three.module.js';
// Anatomical, articulated meshes with independent elbows, knees and eyelids.
const ball=new T.SphereGeometry(1,16,12);
const cache=new Map();
const mat=(color,roughness=.8)=>{const k=color+':'+roughness;if(!cache.has(k))cache.set(k,new T.MeshStandardMaterial({color,roughness}));return cache.get(k);};
function add(parent,geometry,material,x,y,z){const o=new T.Mesh(geometry,material);o.position.set(x,y,z);o.castShadow=true;o.receiveShadow=true;parent.add(o);return o;}
function oval(p,x,y,z,w,h,d,m){const o=add(p,ball,m,x,y,z);o.scale.set(w,h,d);return o;}
function loft(rows,segments=24){const pos=[],uv=[],indices=[];for(let j=0;j<rows.length;j++){const [y,w,front,back,offset=0]=rows[j];for(let i=0;i<=segments;i++){const angle=i/segments*Math.PI*2,c=Math.cos(angle),s=Math.sin(angle);pos.push(w*s,y,offset+c*(c>=0?front:back));uv.push(i/segments,j/(rows.length-1));}}for(let j=0;j<rows.length-1;j++)for(let i=0;i<segments;i++){const a=j*(segments+1)+i,b=a+segments+1;if(rows.at(-1)[0]>rows[0][0])indices.push(a,a+1,b,a+1,b+1,b);else indices.push(a,b,a+1,a+1,b,b+1);}const g=new T.BufferGeometry();g.setAttribute('position',new T.Float32BufferAttribute(pos,3));g.setAttribute('uv',new T.Float32BufferAttribute(uv,2));g.setIndex(indices);g.computeVertexNormals();return g;}
function seam(parent,points,color,radius=.003){const path=new T.CatmullRomCurve3(points.map(p=>new T.Vector3(...p)));return add(parent,new T.TubeGeometry(path,Math.max(5,points.length*3),radius,5,false),mat(color),0,0,0);}
let serial=0;
// nah=false lässt alles weg, was erst aus wenigen Metern sichtbar wird.
export function naturalHuman(color,pants,nah=true){
 const id=serial++,g=new T.Group();const skinTone=[0xc3987b,0xa67455,0x79513b,0xd4ad8c,0xb68467][id%5];
 const skin=new T.MeshPhysicalMaterial({color:skinTone,roughness:.73,sheen:.14,sheenColor:0xb78d76});
 const cloth=mat(color,.94),denim=mat(pants,.96),dark=mat(0x292e31),hairColor=[0x302820,0x554332,0x251f1b,0x6b5238][id%4];
 // Pelvis, waist, rib cage and shoulders have different cross sections.
 const body=add(g,loft([[.86,.14,.095,.10],[.91,.18,.11,.105],[1.02,.145,.09,.10],[1.15,.17,.115,.105],[1.32,.21,.12,.105],[1.43,.23,.10,.085],[1.48,.13,.075,.07],[1.49,.065,.057,.052]],28),cloth,0,0,0);
 add(g,new T.CylinderGeometry(.057,.065,.12,16),skin,0,1.51,0);
 // Jaw, cheekbones, temple, forehead and cranium; no spherical mask.
 const face=add(g,loft([[1.55,.025,.046,.033,.027],[1.57,.065,.065,.053,.018],[1.62,.081,.078,.067,.009],[1.68,.092,.091,.079],[1.72,.092,.092,.084],[1.76,.087,.087,.085],[1.80,.087,.086,.084],[1.85,.067,.064,.065],[1.88,.02,.023,.022],[1.883,.001,.001,.001]],32),skin,0,0,0);
 const colors=[];const base=new T.Color(skinTone),attr=face.geometry.attributes.position;for(let i=0;i<attr.count;i++){const x=attr.getX(i),y=attr.getY(i),z=attr.getZ(i);const shade=1+.015*Math.sin(i*23.71);const c=base.clone().multiplyScalar(shade);if(z>.045&&y>1.64&&y<1.71&&Math.abs(x)>.035)c.lerp(new T.Color(0xb87865),.10);colors.push(c.r,c.g,c.b);}face.geometry.setAttribute('color',new T.Float32BufferAttribute(colors,3));face.material=skin.clone();face.material.color.setHex(0xffffff);face.material.vertexColors=true;
 const eyes=[],lids=[];for(const side of [-1,1]){
  const eye=oval(g,side*.036,1.737,.082,.022,.0105,.012,mat(0xd4d2c8,.34));eyes.push(eye);
  oval(eye,0,0,.83,.37,.77,.22,mat([0x53614b,0x6d5236,0x506975][id%3],.22));oval(eye,0,0,1,.15,.45,.07,mat(0x192326,.15));
  const lid=oval(g,side*.036,1.737,.087,.023,.011,.005,skin);lid.visible=false;lids.push(lid);
  if(nah){
   seam(g,[[side*.015,1.742,.090],[side*.035,1.749,.091],[side*.058,1.74,.087]],skinTone,.0025);
   seam(g,[[side*.017,1.759,.087],[side*.038,1.765,.088],[side*.060,1.756,.082]],hairColor,.0035);
  }
  oval(g,side*.096,1.707,-.003,.013,.031,.018,skin);oval(g,side*.103,1.707,.008,.004,.017,.009,mat(0x946a55));
 }
 // A continuous bridge with separate nostrils and restrained lips.
 add(g,loft([[1.686,.012,.014,.004,.091],[1.694,.019,.023,.004,.094],[1.709,.011,.025,.005,.091],[1.741,.007,.016,.004,.082],[1.758,.005,.006,.003,.081]],12),skin,0,0,0);
 if(nah){
  for(const side of [-1,1])oval(g,side*.011,1.689,.107,.005,.0025,.0035,mat(0x654b3c));
  seam(g,[[-.024,1.662,.086],[-.01,1.667,.093],[0,1.664,.096],[.01,1.667,.093],[.024,1.662,.086]],0x96675b,.003);
  seam(g,[[-.023,1.661,.086],[0,1.657,.095],[.023,1.661,.086]],0xb27c6a,.004);
 }
 const hair=new T.Group();g.add(hair);hair.position.y=1.78;
 const cap=add(hair,loft([[0,.090,.090,.084],[.025,.088,.087,.083],[.062,.072,.068,.067],[.106,.01,.013,.013]],28),mat(hairColor,.97),0,0,-.005);
 if(nah)for(let i=0;i<8;i++){const x=-.064+i*.018;seam(hair,[[x,.015,.079],[x+.007,.07,.04],[x-.008,.086,-.016],[x-.016,.038,-.073]],i%2?hairColor:0x40382b,.007);}
 // Clothing has a collar, zipper, belt and stitched trouser seams.
 if(nah){
  seam(g,[[0,1.475,.07],[-.058,1.45,.085],[-.064,1.41,.10]],0xc3c5b4,.009);seam(g,[[0,1.475,.07],[.058,1.45,.085],[.064,1.41,.10]],0xc3c5b4,.009);
  seam(g,[[0,1.42,.12],[0,1.20,.119],[0,.99,.10]],0x727b78,.0035);
  add(g,new T.BoxGeometry(.045,.033,.012),mat(0x939b93,.35),0,.926,.111);
 }
 const legs=[],arms=[],knees=[],elbows=[];
 for(const side of [-1,1]){
  const leg=new T.Group();leg.position.set(side*.105,.91,0);g.add(leg);legs.push(leg);
  add(leg,loft([[0,.098,.092,.095],[-.13,.085,.085,.087],[-.29,.063,.066,.068],[-.43,.055,.053,.055]],18),denim,0,0,0);
  const knee=new T.Group();knee.position.y=-.41;leg.add(knee);knees.push(knee);
  add(knee,loft([[0,.056,.059,.058],[-.12,.062,.062,.069],[-.28,.045,.04,.043],[-.40,.038,.033,.038]],16),denim,0,0,0);
  oval(knee,0,-.416,.06,.055,.046,.13,dark);oval(knee,0,-.448,.06,.056,.011,.13,mat(0x707572));
  if(nah)seam(leg,[[side*.091,-.04,.01],[side*.080,-.18,.01],[side*.057,-.38,.01]],0x626b68,.002);
  const arm=new T.Group();arm.position.set(side*.235,1.415,0);g.add(arm);arms.push(arm);
  add(arm,loft([[.025,.071,.071,.068],[-.13,.058,.058,.057],[-.28,.046,.048,.046]],16),cloth,0,0,0);
  const elbow=new T.Group();elbow.position.y=-.275;arm.add(elbow);elbows.push(elbow);
  add(elbow,loft([[.01,.047,.049,.047],[-.10,.045,.043,.043],[-.23,.031,.031,.032]],16),cloth,0,0,0);
  oval(elbow,0,-.275,.003,.036,.057,.023,skin);
  if(nah){
   for(let f=0;f<4;f++){const finger=oval(elbow,(f-1.5)*.015,-.335+(Math.abs(f-1.5))*.007,.009,.009,.032,.011,skin);finger.rotation.x=.12;}
   const thumb=oval(elbow,-side*.035,-.282,.016,.014,.030,.013,skin);thumb.rotation.z=-side*.45;
  } else {
   // Ersatz für die Hand: ein geschlossener Block statt fünf Fingern.
   oval(elbow,0,-.318,.008,.032,.045,.026,skin);
  }
 }
 const tattoo=add(arms[0],new T.PlaneGeometry(.055,.09),mat(0x314643),0,-.28,.051);tattoo.visible=false;
 const garments=[];g.traverse(o=>{if(o.isMesh&&o.material===cloth)garments.push(o);});g.userData={body,hair,tattoo,legs,arms,knees,elbows,eyes,lids,face,id,garments,rig:'anatomical-v1'};return g;
}
export function animateNaturalHuman(g,time,moving,armed){const u=g.userData,amount=Math.min(1,moving),phase=time*(moving>1?11:7.4);u.legs.forEach((leg,i)=>{const step=Math.sin(phase+i*Math.PI);leg.rotation.x=step*.43*amount;u.knees[i].rotation.x=Math.max(0,-step)*.65*amount+.025;});u.arms.forEach((arm,i)=>{arm.rotation.x=armed?-1.04:-Math.sin(phase+i*Math.PI)*.25*amount;arm.rotation.z=(i?1:-1)*.04;u.elbows[i].rotation.x=armed?-.32:-.12-Math.max(0,Math.sin(phase+i*Math.PI))*.14*amount;});const blink=(time+u.id*.39)%4.9<.11;u.eyes.forEach(e=>e.visible=!blink);u.lids.forEach(e=>e.visible=blink);u.body.scale.z=1+Math.sin(time*1.6+u.id)*.009;}
