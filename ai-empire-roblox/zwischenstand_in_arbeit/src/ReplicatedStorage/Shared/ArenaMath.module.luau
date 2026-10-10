--!strict
-- A concrete route planner. Skill changes detours and decisions; every move stays inside the course.
local Math={}
Math.WIDTH=9
Math.HEIGHT=7
local walls={"3:1","3:2","3:3","3:5","3:6","5:2","5:3","5:4","5:5","7:1","7:3","7:4","7:6"}
function Math.blocked(x: number,z: number): boolean
	if x<1 or x>Math.WIDTH or z<1 or z>Math.HEIGHT then return true end
	return table.find(walls,tostring(x)..":"..tostring(z))~=nil
end
function Math.route(stats: any,seed: number): any
	local start={x=1,z=4};local goal={x=9,z=4}
	local queue={start};local seen={['1:4']=true};local parent={};local i=1
	while i<=#queue do
		local cell=queue[i];i+=1
		if cell.x==goal.x and cell.z==goal.z then break end
		for _, d in {{1,0},{0,-1},{0,1},{-1,0}} do
			local x,z=cell.x+d[1],cell.z+d[2];local key=tostring(x)..":"..tostring(z)
			if not Math.blocked(x,z) and not seen[key] then
				seen[key]=true;parent[key]=cell;table.insert(queue,{x=x,z=z})
			end
		end
	end
	local path={goal};local cell=goal
	while cell.x~=start.x or cell.z~=start.z do
		cell=parent[tostring(cell.x)..":"..tostring(cell.z)]
		assert(cell,"arena must have a legal route")
		table.insert(path,1,cell)
	end
	local shortest=#path
	local skill=(stats.reasoning or 0)*0.6+(stats.coding or 0)*0.25+(stats.reliability or 0)*0.15
	local detours=math.max(0,math.floor(5/(1+skill/35)+(seed%3)/2)-1)
	for _=1,detours do
		-- Two legal moves away from and back to an existing cell.
		for n=2,#path-1 do
			local p=path[n]
			if not Math.blocked(p.x,p.z+1) then table.insert(path,n+1,{x=p.x,z=p.z+1});table.insert(path,n+2,{x=p.x,z=p.z});break end
		end
	end
	local secondsPerStep=math.clamp(1.8-(stats.speed or 40)/100,0.55,1.5)
	local score=math.round(skill*0.45+100*shortest/#path+20/secondsPerStep)
	return {path=path,shortest=shortest,moves=#path-1,seconds=(#path-1)*secondsPerStep,stepSeconds=secondsPerStep,score=score,detours=detours}
end
function Math.cargo(stats: any): any
	local correct=math.clamp(math.floor((stats.coding or 0)/15),1,8)
	return {correct=correct,total=8,score=correct*12.5}
end
return Math
