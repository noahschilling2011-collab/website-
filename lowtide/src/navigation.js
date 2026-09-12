// Bounded A* on a collision-tested grid, used by dispatch and mission guards.
export function findPath(start,goal,blocked,step=4,maxNodes=10000){
 const origin={x:Math.floor(Math.min(start.x,goal.x)-40),z:Math.floor(Math.min(start.z,goal.z)-40)};
 const encode=(x,z)=>x+','+z,world=(x,z)=>({x:origin.x+x*step,z:origin.z+z*step});
 const sx=Math.round((start.x-origin.x)/step),sz=Math.round((start.z-origin.z)/step),gx=Math.round((goal.x-origin.x)/step),gz=Math.round((goal.z-origin.z)/step);
 const heap=[],cost=new Map(),parent=new Map(),closed=new Set();
 const push=n=>{heap.push(n);let i=heap.length-1;while(i){const p=(i-1)>>1;if(heap[p].f<=n.f)break;heap[i]=heap[p];i=p;}heap[i]=n;};
 const pop=()=>{const top=heap[0],end=heap.pop();if(heap.length){let i=0;while(true){let c=i*2+1;if(c>=heap.length)break;if(c+1<heap.length&&heap[c+1].f<heap[c].f)c++;if(end.f<=heap[c].f)break;heap[i]=heap[c];i=c;}heap[i]=end;}return top;};
 const h=(x,z)=>Math.abs(x-gx)+Math.abs(z-gz);push({x:sx,z:sz,f:h(sx,sz)});cost.set(encode(sx,sz),0);
 let found=null,best={x:sx,z:sz,d:h(sx,sz)};
 for(let count=0;heap.length&&count<maxNodes;count++){
  const n=pop(),key=encode(n.x,n.z);if(closed.has(key))continue;closed.add(key);
  if(h(n.x,n.z)<best.d)best={...n,d:h(n.x,n.z)};
  if(n.x===gx&&n.z===gz){found=n;break;}
  for(const [dx,dz] of [[1,0],[-1,0],[0,1],[0,-1]]){const x=n.x+dx,z=n.z+dz,k=encode(x,z),p=world(x,z),mid=world(n.x+dx/2,n.z+dz/2);if(x<0||z<0||x>Math.max(sx,gx)+12||z>Math.max(sz,gz)+12||blocked(p)||blocked(mid))continue;const g=cost.get(key)+1;if(g>=(cost.get(k)??Infinity))continue;cost.set(k,g);parent.set(k,key);push({x,z,f:g+h(x,z)});}
 }
 let key=encode((found||best).x,(found||best).z),out=[];while(parent.has(key)){const [x,z]=key.split(',').map(Number);out.push(world(x,z));key=parent.get(key);}out.reverse();if(found&&!blocked(goal))out.push({x:goal.x,z:goal.z});return out;
}
