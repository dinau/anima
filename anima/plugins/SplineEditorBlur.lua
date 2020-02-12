--takes care of feather polygon being simple
--vec2 not vec3 not camera

require"anima"
local mat = require"anima.matrixffi"
local TA = require"anima.TA"
local vert_sh = [[
	in vec2 position;
	void main()
	{
		gl_Position = vec4(position,-1,1);
	
	}
	]]

local frag_sh = [[
	uniform vec3 color = vec3(1);
	void main()
	{
		gl_FragColor = vec4(color,1);
	}
	]]
	
local program

local function mod(a,b)
	return ((a-1)%b)+1
end

--this version allows identical points
local function CatmulRom(p0,p1,p2,p3,ps,alpha,amountOfPoints,last)

	local function GetT( t,  p0,  p1,alpha)
	    local a = math.pow((p1.x-p0.x), 2.0) + math.pow((p1.y-p0.y), 2.0);
	    local b = math.pow(a, 0.5);
	    local c = math.pow(b, alpha);
	   
	    return (c + t);
	end
	
	local t0 = 0.0;
	local t1 = GetT(t0, p0, p1, alpha);
	local t2 = GetT(t1, p1, p2, alpha);
	local t3 = GetT(t2, p2, p3, alpha);
	
	--print(t0,t1,t2,t3)
	local range = last and amountOfPoints or (amountOfPoints - 1)
	
	--special cases
	local A1s,A3s
	if p1==p2 then
		for i=0,range do ps[#ps + 1] = p1 end
		return
	end
	if p0==p1 then A1s = p0 end
	if p2==p3 then A3s = p2 end
	
	local inc = (t2-t1)/amountOfPoints
	for i=0,range do
		local t = t1 + inc*i
	--for t=t1; t<t2; t+=((t2-t1)/amountOfPoints))
	    local A1 = A1s or (t1-t)/(t1-t0)*p0 + (t-t0)/(t1-t0)*p1;
	    local A2 = (t2-t)/(t2-t1)*p1 + (t-t1)/(t2-t1)*p2;
	    local A3 = A3s or (t3-t)/(t3-t2)*p2 + (t-t2)/(t3-t2)*p3;

	    local B1 = (t2-t)/(t2-t0)*A1 + (t-t0)/(t2-t0)*A2;
	    local B2 = (t3-t)/(t3-t1)*A2 + (t-t1)/(t3-t1)*A3;

	    local C = (t2-t)/(t2-t1)*B1 + (t-t1)/(t2-t1)*B2;
	   -- print(C)
	    ps[#ps + 1] = C
	end
end

local function Spline(points,alpha,amountOfPoints,closed)
	--print("Spline alpha",alpha)
	local ps = {}
	local i0,i1,i2,i3
	if closed then
		if #points < 3 then return ps end
		for i=1,#points-3 do
			CatmulRom(points[i],points[i+1],points[i+2],points[i+3],ps,alpha,amountOfPoints)
		end
		CatmulRom(points[#points-2],points[#points-1],points[#points],points[1],ps,alpha,amountOfPoints)
		CatmulRom(points[#points-1],points[#points],points[1],points[2],ps,alpha,amountOfPoints)
		CatmulRom(points[#points],points[1],points[2],points[3],ps,alpha,amountOfPoints,true)
		ps[#ps] = nil --delete repeated
	else
		if #points < 4 then return ps end
		for i=1,#points-4 do
			CatmulRom(points[i],points[i+1],points[i+2],points[i+3],ps,alpha,amountOfPoints)
		end
		local i = #points-3
		CatmulRom(points[i],points[i+1],points[i+2],points[i+3],ps,alpha,amountOfPoints,true)
	end
	return ps
end

local blur3
local function Editor(GL)
	local plugin = require"anima.plugins.plugin"
	local M = plugin.new{res={GL.W,GL.H}}

	local numsplines = 1
	local NM 
	NM = GL:Dialog("spline",
	{
	{"newspline",0,guitypes.button,function(this) 
		numsplines=numsplines+1;
		this.vars.curr_spline[0]=numsplines 
		this.defs.curr_spline.args.max=numsplines 
		M:newshape() end},
	{"curr_spline",1,guitypes.valint,{min=1,max=numsplines}},
	{"feather",0,guitypes.val,{min=0,max=0.1}},
	{"alpha",0.5,guitypes.val,{min=0,max=1},function() M:set_all_vaos() end},
	{"divs",3,guitypes.valint,{min=1,max=30},function() M:set_all_vaos() end},
	{"closed",true,guitypes.toggle,function() M:set_all_vaos() end},
	{"drawpoints",true,guitypes.toggle},
	{"drawregion",false,guitypes.toggle},
	{"drawspline",true,guitypes.toggle},
	{"orientation",0,guitypes.button,function() M:change_orientation(); M:process_all() end},
	{"points",0,guitypes.combo,{"nil","set","edit","clear"},function(val,this) 
		if val == 0 then
			GL.mouse_pick = nil
		elseif val == 1 then --set
			local mousepick = {action=function(X,Y)
							local Xv,Yv = GL:ScreenToViewport(X,Y)
							--print("screen",X,Y)
							--print("viewport",Xv,Yv)
							M:process1(Xv,Yv)
							M:set_vaos()
						end}
			GL.mouse_pick = mousepick
		elseif val == 2 then --edit
			local mousepick = {action=function(X,Y)
							X,Y = GL:ScreenToViewport(X,Y)
							local touched = -1
							for i,v in ipairs(M.sccoors[NM.curr_spline]) do
								local vec = mat.vec2(v[1] - X, v[2] - Y)
								if (vec.norm) < 3 then touched = i; break end
							end
							if touched > 0 then
								GL.mouse_pos_cb = function(x,y)
									x,y = GL:ScreenToViewport(x,y)
									M.sccoors[NM.curr_spline][touched] = {x,y}
									M:process_all()
								end
							else
								GL.mouse_pos_cb = nil
							end
	
						end,
						action_rel = function(X,Y)
							GL.mouse_pos_cb = nil
						end}
			GL.mouse_pick = mousepick
		elseif val == 3 then --clear
			local mousepick = {action=function(X,Y)
							X,Y = GL:ScreenToViewport(X,Y)
							local touched = -1
							for i,v in ipairs(M.sccoors[NM.curr_spline]) do
								local vec = mat.vec2(v[1] - X, v[2] - Y)
								if (vec.norm) < 3 then touched = i; break end
							end
							if touched > 0 then
								table.remove(M.sccoors[NM.curr_spline],touched)
								M:process_all()
							end
						end}
			GL.mouse_pick = mousepick
		
		end
	end},
	
	{"set_last",0,guitypes.button,function() 
		local mousepick = {action=function(X,Y)
							X,Y = GL:ScreenToViewport(X,Y)
							local touched = -1
							for i,v in ipairs(M.sccoors[NM.curr_spline]) do
								local vec = mat.vec2(v[1] - X, v[2] - Y)
								if (vec.norm) < 3 then touched = i; break end
							end
							if touched > 0 then
								M:set_last(touched)
								M:process_all()
								GL.mouse_pick = nil
							end
	
						end}
		GL.mouse_pick = mousepick
	end},
	{"clear",0,guitypes.button,function() M:newshape() end},
	})

	M.NM = NM
	NM.plugin = M
	
	if not blur3 then
		blur3 = require"anima.plugins.gaussianblur3"(GL)
		blur3.NM.invisible = true
	end
	
	local vaopoints, vaoS, vaoT, blurfbo={},{},{}
	local function initVaos()
		vaopoints[NM.curr_spline] = VAO({position=TA():Fill(0,8)},program)
		vaoS[NM.curr_spline] = VAO({position=TA():Fill(0,8)},program)
		vaoT[NM.curr_spline] = VAO({position=TA():Fill(0,8)},program,{0,1,2,3})
	end
	function M:init()
		if not program then
			program = GLSL:new():compile(vert_sh,frag_sh)
		end
		initVaos()
		blurfbo = GL:initFBO({no_depth=true})
		self:newshape()
	end
	M.sccoors = {}
	M.eyepoints = {}
	M.ps = {}
	function M:newshape()
		self.sccoors[NM.curr_spline] = {}
		self.eyepoints[NM.curr_spline] = {}
		self.ps[NM.curr_spline] = {}
		if not vaopoints[NM.curr_spline] then initVaos() end
	end

	function M:process1(X,Y)
		local ndc = mat.vec2(X,Y)*2/mat.vec2(GL.W,GL.H) - mat.vec2(1,1)
		--local eyepoint = MPinv * mat.vec4(ndc.x,ndc.y,0,1)
		local eyepoint =  mat.vec2(ndc.x,ndc.y)
		table.insert(self.eyepoints[NM.curr_spline],eyepoint)
		table.insert(self.sccoors[NM.curr_spline],{X,Y})
		self.NM.dirty = true
		return X,Y
	end
	
	function M:process_all()
		local scoorsO = self.sccoors[NM.curr_spline] --deepcopy(self.sccoors)
		self:newshape()
		for i,v in ipairs(scoorsO) do
			self:process1(unpack(v))
		end
		M:set_vaos()
	end
	function M:numpoints(ind)
		ind = ind or NM.curr_spline
		return #self.eyepoints[ind]
	end

	function M:change_orientation()
		local sc,nsc = self.sccoors[NM.curr_spline],{}
		for i=#sc,1,-1 do
			nsc[#nsc + 1] = sc[i]
		end
		self.sccoors[NM.curr_spline] = nsc
	end
	function M:set_last(ind)
		if ind == #self.sccoors[NM.curr_spline] then return end
		local sc,nsc = self.sccoors[NM.curr_spline],{}
		local first = mod(ind+1,#sc)
		for i=first,#sc do
			nsc[#nsc + 1] = sc[i]
		end
		for i=1,ind do
			nsc[#nsc + 1] = sc[i]
		end
		self.sccoors[NM.curr_spline] = nsc
	end
	
	function M:set_vaos(ii)
		ii = ii or NM.curr_spline
		if #self.eyepoints[ii] > 0 then
		local lp = mat.vec2vao(self.eyepoints[ii])
		vaopoints[ii]:set_buffer("position",lp,(#self.eyepoints[ii])*2)
		if self:numpoints()>2 then
			self.ps[ii] = Spline(self.eyepoints[ii],NM.alpha,NM.divs,NM.closed)
			local lps = mat.vec2vao(self.ps[ii])
			vaoS[ii]:set_buffer("position",lps,(#self.ps[ii])*2)

			self:set_vaoT(ii)
		end
		end
	end
	function M:set_all_vaos()
		for i=1,numsplines do
			self:set_vaos(i)
		end
	end
	local CG = require"anima.CG3"
	function M:set_vaoT(ii)
		local lps = mat.vec2vao(self.ps[ii])
		vaoT[ii]:set_buffer("position",lps,(#self.ps[ii])*2)
		local indexes
		indexes,self.good_indexes = CG.EarClip(self.ps[ii])
		vaoT[ii]:set_indexes(indexes)
	end
	
	function M:process(_,w,h)
		--if NM.collapsed then return end
		w,h = w or self.res[1],h or self.res[2]
		--blurfbo = GL:get_fbo()
		blurfbo:Bind()
		gl.glDisable(glc.GL_DEPTH_TEST)
		gl.glViewport(0, 0, w, h)
		ut.Clear()
		program:use()

		if NM.drawregion  then
			if self.good_indexes then
				program.unif.color:set{1,1,1}
			else
				program.unif.color:set{1,0,0}
			end
			for i=1,numsplines do
				if M:numpoints(i) > 2 then
				vaoT[i]:draw_elm()
				end
			end
			--vaoT:draw_mesh()
		end
		if NM.drawspline  then
			program.unif.color:set{1,1,0}
			--vaoS:draw(glc.GL_LINE_STRIP,(#self.ps))
			for i=1,numsplines do
				if M:numpoints(i) > 2 then
				vaoS[i]:draw(glc.GL_LINE_LOOP,(#self.ps[i]))
				end
			end
		end
		if NM.drawpoints and M:numpoints() > 0 then
			program.unif.color:set{1,0,0}
			gl.glPointSize(6)
			vaopoints[NM.curr_spline]:draw(glc.GL_POINTS,M:numpoints())
			program.unif.color:set{1,1,0}
			vaopoints[NM.curr_spline]:draw(glc.GL_POINTS,1)
			
			gl.glPointSize(1)
			--program.unif.color:set{0.2,0.2,0.2}
			--vaopoints:draw(glc.GL_LINE_STRIP,M:numpoints())
		end
		blurfbo:UnBind()

		blur3.NM.vars.stdevs[0] = 3.5
		blur3.NM.vars.radio[0] = math.min(39*2,math.max(1,NM.feather*GL.W))
		blur3:update()
		blurfbo:tex():inc_signature()
		--blur3:set_texsignature(blurfbo:GetTexture())
		blur3:process(blurfbo:tex(),w,h)
		--blur3:draw(t,w,h,{clip={blurfbo:GetTexture()}})
		-- blurfbo:GetTexture():draw(t,w,h)
		
		--blurfbo:release()
		gl.glEnable(glc.GL_DEPTH_TEST)
	end
	function M:save()
		--print"SplineEditor6 save"
		local pars = {sccoors=self.sccoors,VP={GL.W,GL.H}}
		pars.dial = NM:GetValues()
		pars.numsplines = numsplines
		return pars
	end
	function M:load(params)
		if not params then return end
		for j,sc in ipairs(params.sccoors) do
		for i,v in ipairs(sc) do
			v[1] = v[1]*GL.W/params.VP[1]
			v[2] = v[2]*GL.H/params.VP[2]
		end
		end
		NM:SetValues(params.dial or {})
		M.sccoors = params.sccoors
		for j,sc in ipairs(params.sccoors) do
			NM.vars.curr_spline[0] = j
			self:process_all()
		end
		numsplines = params.numsplines
		NM.defs.curr_spline.args.max=numsplines
	end
	GL:add_plugin(M,"spline")
	return M
end

--[=[
local GL = GLcanvas{H=800,aspect=3/2}
local camara = newCamera(GL,"ident")
local edit = Editor(GL,camara)
local plugin = require"anima.plugins.plugin"
edit.fb = plugin.serializer(edit)
--GL.use_presets = true
function GL.init()
	GL:DirtyWrap()
end
function GL.draw(t,w,h)
	--ut.Clear()
	edit:process(nil)
end
GL:start()
--]=]
--[=[
local GL = GLcanvas{H=800,aspect=3/2}
--local camara = newCamera(GL,"fps")--"ident")
local edit = Editor(GL)--,camara)
local plugin = require"anima.plugins.plugin"
edit.ps = plugin.serializer(edit)
--GL.use_presets = true
--local blur = require"anima.plugins.gaussianblur3"(GL)
--local blur = require"anima.plugins.liquid".make(GL)
--local blur = require"anima.plugins.photofx".make(GL)
local blur = require"anima.plugins.LCHfx".make(GL)
local fboblur,fbomask,tex
local tproc
local NM = GL:Dialog("proc",
{{"showmask",false,guitypes.toggle},
{"invert",false,guitypes.toggle},
{"minmask",0,guitypes.val,{min=0,max=1}},
{"maxmask",1,guitypes.val,{min=0,max=1}},
})

local DBox = GL:DialogBox("photomask")
DBox:add_dialog(edit.NM)
DBox:add_dialog(blur.NM)
DBox:add_dialog(NM)

function GL.init()
	fboblur = GL:initFBO({no_depth=true})
	fbomask = GL:initFBO({no_depth=true})
	tex = GL:Texture():Load[[c:\luagl\media\estanque3.jpg]]
	tproc = require"anima.plugins.texture_processor"(GL,3,NM)
	tproc:set_textures{tex,fboblur:GetTexture(),fbomask:GetTexture()}
	tproc:set_process[[vec4 process(vec2 pos){
	
		if (invert)
			c3 = vec4(1) - c3;
		c3 = min(max(c3,vec4(minmask)),vec4(maxmask));
		if (showmask)
			return c3 + c1*(vec4(1)-c3);
		else
			return mix(c1,c2,c3.r);
	}
	]]
end
function GL.draw2(t,w,h)
	ut.Clear()
	edit:draw(t,w,h)
end
function GL.draw(t,w,h)
	fboblur:Bind()
	blur:draw(t,w,h,{clip={tex}})
	fboblur:UnBind()
	
	--if edit.NM.dirty then
	fbomask:Bind()
	ut.Clear()
	edit:process() --draw(t,w,h)
	fbomask:UnBind()
	edit.NM.dirty = false
	--end
	
	ut.Clear()
	--fboblur:GetTexture():draw(t,w,h)
	--fbomask:GetTexture():draw(t,w,h)
	--edit:draw(t,w,h)
	tproc:process({tex,fboblur:GetTexture(),fbomask:GetTexture()})
end
GL:start()
--]=]
return Editor