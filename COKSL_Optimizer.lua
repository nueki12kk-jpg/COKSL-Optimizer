if not game:IsLoaded() then game.Loaded:Wait() end

local genv = (getgenv and getgenv()) or _G
if genv.COKSL_OPTIMIZER and type(genv.COKSL_OPTIMIZER.Destroy) == "function" then
	pcall(genv.COKSL_OPTIMIZER.Destroy)
end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local Stats            = game:GetService("Stats")
local SoundService     = game:GetService("SoundService")
local HttpService      = game:GetService("HttpService")
local MaterialService  = game:GetService("MaterialService")
local CoreGui          = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Workspace   = workspace
local Terrain     = Workspace:FindFirstChildOfClass("Terrain") or Workspace:WaitForChild("Terrain", 5)

local ENV = {
	setfpscap      = setfpscap or set_fps_cap,
	getfpscap      = getfpscap or get_fps_cap,
	sethidden      = sethiddenproperty or set_hidden_property or set_hidden_prop,
	gethidden      = gethiddenproperty or get_hidden_property or get_hidden_prop,
	writefile      = writefile,
	readfile       = readfile,
	isfile         = isfile,
	isfolder       = isfolder,
	makefolder     = makefolder,
	listfiles      = listfiles,
	delfile        = delfile,
	getcustomasset = getcustomasset or getsynasset,
	gethui         = gethui,
	cleardrawcache = cleardrawcache,
}
ENV.fs = (ENV.writefile and ENV.readfile and ENV.isfile and ENV.isfolder and ENV.makefolder and ENV.listfiles) and true or false

local ROOT      = "COKSL_Optimizer"
local ASSET_DIR = ROOT .. "/assets"
local PROF_DIR  = ROOT .. "/profiles"

local Conns = {}
local function Connect(signal, fn)
	local c = signal:Connect(fn)
	Conns[#Conns + 1] = c
	return c
end

local function Budget(ms)
	local t, lim = os.clock(), ms / 1000
	return function()
		if os.clock() - t >= lim then
			task.wait()
			t = os.clock()
			return true
		end
		return false
	end
end

local function Debounce(fn, delay)
	local token = 0
	return function()
		token += 1
		local mine = token
		task.delay(delay, function()
			if mine == token then fn() end
		end)
	end
end

local function E(enumName, item)
	local ok, v = pcall(function() return Enum[enumName][item] end)
	if ok then return v end
	return nil
end

local Notify = function() end

local B64 = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local lookup = {}
	for i = 1, 64 do lookup[string.byte(chars, i)] = i - 1 end

	function B64.decode(s)
		s = string.gsub(s, "[^%w%+/=]", "")
		local out, n = {}, 0
		for i = 1, #s, 4 do
			local a, b, c, d = string.byte(s, i, i + 3)
			local va, vb = lookup[a], lookup[b]
			if not (va and vb) then break end
			local vc, vd = lookup[c], lookup[d]
			local v = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
			local b1 = math.floor(v / 65536)
			local b2 = math.floor(v / 256) % 256
			local b3 = v % 256
			n += 1
			if vc and vd then
				out[n] = string.char(b1, b2, b3)
			elseif vc then
				out[n] = string.char(b1, b2)
			else
				out[n] = string.char(b1)
			end
		end
		return table.concat(out)
	end
end

local S = {
	LowPolyLevel     = 2,
	BlackScreenFps   = 15,
	ParticleFps      = 50,
	ParticleDistance = 250,
	GCInterval       = 60,
	GCThreshold      = 2000,
	RenderDistance   = 500,
	AdaptiveDistance = true,
	FogMask          = false,
	MaxFps           = 240,
	IdleFps          = 30,
	IdleSeconds      = 45,
	BackgroundFps    = 5,
}

local Mod = {}
local Mods  = setmetatable({}, { __mode = "k" })
local Owned = {}
local Stash = {}

local function rawGet(inst, prop) return inst[prop] end
local function rawSet(inst, prop, value) inst[prop] = value end

local function readProp(inst, prop, hidden)
	if hidden then
		if not ENV.gethidden then return false end
		return pcall(ENV.gethidden, inst, prop)
	end
	return pcall(rawGet, inst, prop)
end

local function writeProp(inst, prop, value, hidden)
	if hidden then
		if not ENV.sethidden then return false end
		return pcall(ENV.sethidden, inst, prop, value)
	end
	return pcall(rawSet, inst, prop, value)
end

function Mod.Set(owner, inst, prop, value, hidden)
	local props = Mods[inst]
	if not props then
		props = {}
		Mods[inst] = props
	end
	local rec = props[prop]
	if not rec then
		local ok, old = readProp(inst, prop, hidden)
		if not ok then
			if next(props) == nil then Mods[inst] = nil end
			return false
		end
		rec = { orig = old, hidden = hidden, owners = {}, n = 0 }
		props[prop] = rec
	end
	if not rec.owners[owner] then
		rec.owners[owner] = true
		rec.n += 1
		local o = Owned[owner]
		if not o then
			o = setmetatable({}, { __mode = "k" })
			Owned[owner] = o
		end
		local pp = o[inst]
		if not pp then
			pp = {}
			o[inst] = pp
		end
		pp[prop] = true
		if prop == "Parent" then Stash[inst] = true end
	end
	return (writeProp(inst, prop, value, hidden))
end

function Mod.SetEnum(owner, inst, prop, enumName, item, hidden)
	local v = E(enumName, item)
	if v == nil then return false end
	return Mod.Set(owner, inst, prop, v, hidden)
end

local function releaseOne(owner, inst, prop, ownedTbl)
	local props = Mods[inst]
	local rec = props and props[prop]
	if rec and rec.owners[owner] then
		rec.owners[owner] = nil
		rec.n -= 1
		if rec.n <= 0 then
			props[prop] = nil
			if next(props) == nil then Mods[inst] = nil end
			if prop == "Parent" then Stash[inst] = nil end
			writeProp(inst, prop, rec.orig, rec.hidden)
		end
	end
	local pp = ownedTbl and ownedTbl[inst]
	if pp then
		pp[prop] = nil
		if next(pp) == nil then ownedTbl[inst] = nil end
	end
end

function Mod.Unset(owner, inst, prop)
	releaseOne(owner, inst, prop, Owned[owner])
end

function Mod.Release(owner)
	local o = Owned[owner]
	if not o then return end
	Owned[owner] = nil
	local step = Budget(4)
	for inst, pp in next, o do
		for prop in next, pp do
			releaseOne(owner, inst, prop, o)
		end
		step()
	end
end

local ProxyFolder

local function Ignored(inst)
	return ProxyFolder ~= nil and (inst == ProxyFolder or inst.Parent == ProxyFolder)
end

local function IsCharacter(inst)
	local p = inst.Parent
	while p and p ~= Workspace do
		if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then return true end
		p = p.Parent
	end
	return false
end

local ScanRoots = { Workspace, Lighting, SoundService, MaterialService }

local Perf = { fps = 60 }
Connect(RunService.Heartbeat, function(dt)
	if dt > 0 then Perf.fps += (1 / dt - Perf.fps) * 0.06 end
end)

function Perf.Pressure(target)
	return math.clamp((target - Perf.fps) / (target * 0.6), 0, 1)
end

local Render = { off = {} }
function Render.Set(owner, disabled)
	Render.off[owner] = disabled and true or nil
	pcall(function() RunService:Set3dRenderingEnabled(next(Render.off) == nil) end)
end

local FPS = { requests = {}, applied = nil, default = 60 }
if ENV.getfpscap then
	local ok, v = pcall(ENV.getfpscap)
	if ok and type(v) == "number" and v > 0 then FPS.default = v end
end
function FPS.Update()
	if not ENV.setfpscap then return end
	local cap
	for _, v in pairs(FPS.requests) do
		if not cap or v < cap then cap = v end
	end
	if cap == nil then
		if FPS.applied ~= nil then
			FPS.applied = nil
			pcall(ENV.setfpscap, FPS.default)
		end
	elseif cap ~= FPS.applied then
		FPS.applied = cap
		pcall(ENV.setfpscap, cap)
	end
end
function FPS.Request(owner, cap) FPS.requests[owner] = cap; FPS.Update() end
function FPS.Release(owner) FPS.requests[owner] = nil; FPS.Update() end

local Focus = { focused = true, handlers = {} }
Connect(UserInputService.WindowFocused, function()
	Focus.focused = true
	for _, h in pairs(Focus.handlers) do pcall(h, true) end
end)
Connect(UserInputService.WindowFocusReleased, function()
	Focus.focused = false
	for _, h in pairs(Focus.handlers) do pcall(h, false) end
end)

local Features = {}
local ActiveApply = {}

local function RebuildApply()
	local list = {}
	for _, f in pairs(Features) do
		if f.enabled and f.applied and f.apply then list[#list + 1] = f end
	end
	ActiveApply = list
end

local function NewFeature(name, def)
	def.name, def.enabled, def.applied, def.gen = name, false, false, 0
	Features[name] = def
	return def
end

local function ScanAll(f, fn)
	local gen = f.gen
	local step = Budget(6)
	for _, root in ipairs(ScanRoots) do
		local ok, list = pcall(root.GetDescendants, root)
		if ok then
			for i = 1, #list do
				if f.gen ~= gen then return false end
				local inst = list[i]
				if not Ignored(inst) then pcall(fn, inst) end
				step()
			end
		end
	end
	return true
end

local function Reconcile(f)
	if f.working then return end
	f.working = true
	task.spawn(function()
		while f.applied ~= f.enabled or f.restartReq do
			if f.applied and (not f.enabled or f.restartReq) then
				f.restartReq = false
				f.applied = false
				RebuildApply()
				if f.disable then
					local ok, err = pcall(f.disable, f)
					if not ok then warn("[COKSL] " .. f.name .. " disable: " .. tostring(err)) end
				end
				Mod.Release(f.name)
			end
			if f.enabled and not f.applied then
				f.applied = true
				RebuildApply()
				if f.enable then
					local ok, err = pcall(f.enable, f)
					if not ok then warn("[COKSL] " .. f.name .. " enable: " .. tostring(err)) end
				end
			end
		end
		f.working = false
	end)
end

local function FeatureSet(f, on)
	on = on and true or false
	if f.enabled == on then return end
	f.enabled = on
	f.gen += 1
	Reconcile(f)
end

local function FeatureRestart(f)
	if not f.enabled then return end
	f.restartReq = true
	f.gen += 1
	Reconcile(f)
end

local function OnAdded(inst)
	if #ActiveApply == 0 or Ignored(inst) then return end
	for i = 1, #ActiveApply do
		pcall(ActiveApply[i].apply, inst)
	end
end
Connect(Workspace.DescendantAdded, OnAdded)
Connect(Lighting.DescendantAdded, OnAdded)
Connect(SoundService.DescendantAdded, OnAdded)
Connect(MaterialService.DescendantAdded, OnAdded)
local LP = NewFeature("LowPoly", {})
local LP_OWN = "LowPoly"
local Proxies, ProxyList = {}, {}
local MAX_PROXIES = 6000

local function EnsureProxyFolder()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end
	if not ProxyFolder or ProxyFolder.Parent ~= cam then
		if ProxyFolder then ProxyFolder:Destroy() end
		ProxyFolder = Instance.new("Folder")
		ProxyFolder.Name = "COKSL_LowPoly"
		ProxyFolder.Parent = cam
	end
	return ProxyFolder
end

local function RemoveProxy(src)
	local px = Proxies[src]
	if px then
		Proxies[src] = nil
		px:Destroy()
	end
end

local function MakeProxy(src)
	if Proxies[src] or #ProxyList >= MAX_PROXIES then return end
	if not src.Anchored or src.Transparency >= 0.98 then return end
	local cn = src.ClassName
	if cn ~= "MeshPart" and cn ~= "UnionOperation" then return end
	if src.Size.Magnitude < 2 then return end
	local folder = EnsureProxyFolder()
	if not folder then return end

	local px = Instance.new("Part")
	px.Anchored, px.CanCollide, px.CanQuery, px.CanTouch, px.CastShadow = true, false, false, false, false
	px.Material = Enum.Material.SmoothPlastic
	px.Size, px.CFrame, px.Transparency = src.Size, src.CFrame, src.Transparency
	if cn == "MeshPart" and (src.TextureID ~= "" or src:FindFirstChildOfClass("SurfaceAppearance")) then
		px.Color = Color3.fromRGB(163, 162, 165)
	else
		px.Color = src.Color
	end
	px.Parent = folder
	Proxies[src] = px
	ProxyList[#ProxyList + 1] = src
	Mod.Set(LP_OWN, src, "LocalTransparencyModifier", 1)
end

function LP.apply(inst)
	local lvl = S.LowPolyLevel
	local cn = inst.ClassName

	if inst:IsA("BasePart") then
		if inst == Terrain or IsCharacter(inst) then return end
		if inst:IsA("TriangleMeshPart") then
			Mod.SetEnum(LP_OWN, inst, "RenderFidelity", "RenderFidelity", "Performance")
		end
		if lvl >= 2 then
			Mod.Set(LP_OWN, inst, "Material", Enum.Material.SmoothPlastic)
			Mod.Set(LP_OWN, inst, "Reflectance", 0)
			Mod.Set(LP_OWN, inst, "CastShadow", false)
		end
		if lvl >= 3 then MakeProxy(inst) end
	elseif cn == "Model" then
		if not inst:FindFirstChildOfClass("Humanoid") then
			Mod.SetEnum(LP_OWN, inst, "LevelOfDetail", "ModelLevelOfDetail", "StreamingMesh")
		end
	elseif lvl >= 2 then
		if cn == "Decal" or cn == "Texture" then
			if not IsCharacter(inst) then Mod.Set(LP_OWN, inst, "Transparency", 1) end
		elseif cn == "SurfaceAppearance" or cn == "MaterialVariant" then
			if not IsCharacter(inst) then Mod.Set(LP_OWN, inst, "Parent", nil) end
		elseif cn == "Sky" then
			Mod.Set(LP_OWN, inst, "StarCount", 0)
			Mod.Set(LP_OWN, inst, "CelestialBodiesShown", false)
		elseif cn == "Clouds" then
			Mod.Set(LP_OWN, inst, "Enabled", false)
		end
	end
end

local function ProxySync(gen)
	local cursor, lastFolder = 1, ProxyFolder
	while LP.enabled and LP.gen == gen do
		local folder = EnsureProxyFolder()
		if folder and folder ~= lastFolder then
			lastFolder = folder
			for _, px in pairs(Proxies) do px.Parent = folder end
		end
		local t0 = os.clock()
		local looped = 0
		while os.clock() - t0 < 0.0015 do
			local n = #ProxyList
			if n == 0 or looped >= n then break end
			if cursor > n then cursor = 1 end
			local src = ProxyList[cursor]
			local px = Proxies[src]
			if not px or not src.Parent or not src.Anchored then
				RemoveProxy(src)
				pcall(Mod.Unset, LP_OWN, src, "LocalTransparencyModifier")
				ProxyList[cursor] = ProxyList[n]
				ProxyList[n] = nil
			else
				if px.CFrame ~= src.CFrame then px.CFrame = src.CFrame end
				if px.Size ~= src.Size then px.Size = src.Size end
				cursor += 1
			end
			looped += 1
		end
		RunService.Heartbeat:Wait()
	end
end

function LP.enable(f)
	local lvl = S.LowPolyLevel
	local R = settings().Rendering
	Mod.SetEnum(LP_OWN, R, "QualityLevel", "QualityLevel", "Level01")
	Mod.SetEnum(LP_OWN, R, "MeshPartDetailLevel", "MeshPartDetailLevel", "Level04")
	if Terrain then
		Mod.Set(LP_OWN, Terrain, "WaterWaveSize", 0)
		Mod.Set(LP_OWN, Terrain, "WaterWaveSpeed", 0)
		Mod.Set(LP_OWN, Terrain, "WaterReflectance", 0)
		if lvl >= 2 then Mod.Set(LP_OWN, Terrain, "Decoration", false, true) end
	end
	Mod.SetEnum(LP_OWN, Workspace, "LevelOfDetail", "ModelLevelOfDetail", "StreamingMesh")
	if lvl >= 2 then
		Mod.Set(LP_OWN, Lighting, "GlobalShadows", false)
	end
	if lvl >= 3 then task.spawn(ProxySync, f.gen) end
	ScanAll(f, LP.apply)
end

function LP.disable(f)
	table.clear(Proxies)
	table.clear(ProxyList)
	if ProxyFolder then
		pcall(function() ProxyFolder:Destroy() end)
		ProxyFolder = nil
	end
end

LP.refresh = Debounce(function() FeatureRestart(LP) end, 0.6)

local BS = NewFeature("BlackScreen", {})
local BSGui, BSInfo

local function ProtectGui(gui)
	if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
	local parent
	if ENV.gethui then
		local ok, h = pcall(ENV.gethui)
		if ok then parent = h end
	end
	parent = parent or CoreGui
	local ok = pcall(function() gui.Parent = parent end)
	if not ok or not gui.Parent then
		gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	end
end

local function BuildBlackScreen()
	BSGui = Instance.new("ScreenGui")
	BSGui.Name = "COKSL_BlackScreen"
	BSGui.ResetOnSpawn = false
	BSGui.IgnoreGuiInset = true
	BSGui.DisplayOrder = 2147483000
	BSGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	BSGui.Enabled = false
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BorderSizePixel = 0
	bg.Active = true
	bg.Parent = BSGui
	BSInfo = Instance.new("TextLabel")
	BSInfo.AnchorPoint = Vector2.new(0.5, 0.5)
	BSInfo.Position = UDim2.fromScale(0.5, 0.5)
	BSInfo.Size = UDim2.fromOffset(420, 90)
	BSInfo.BackgroundTransparency = 1
	BSInfo.Font = Enum.Font.SourceSansBold
	BSInfo.TextSize = 18
	BSInfo.TextColor3 = Color3.fromRGB(90, 90, 90)
	BSInfo.Text = ""
	BSInfo.Parent = bg
	ProtectGui(BSGui)
end

function BS.enable(f)
	if not BSGui then BuildBlackScreen() end
	BSGui.Enabled = true
	Render.Set("BlackScreen", true)
	FPS.Request("BlackScreen", S.BlackScreenFps)
	local gen = f.gen
	task.spawn(function()
		while BS.enabled and BS.gen == gen do
			local mem = 0
			pcall(function() mem = Stats:GetTotalMemoryUsageMb() end)
			BSInfo.Text = string.format("BLACK SCREEN MODE\nFPS %d   •   MEM %d MB\nRightShift / COKSL button = open menu", math.floor(Perf.fps + 0.5), math.floor(mem))
			task.wait(1)
		end
	end)
end

function BS.disable()
	if BSGui then BSGui.Enabled = false end
	Render.Set("BlackScreen", false)
	FPS.Release("BlackScreen")
end

function BS.refresh()
	if BS.enabled then FPS.Request("BlackScreen", S.BlackScreenFps) end
end

local PA = NewFeature("Particles", {})
local PList, PInfo = {}, setmetatable({}, { __mode = "k" })
local PClasses = { ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true }

function PA.apply(inst)
	if PClasses[inst.ClassName] and not PInfo[inst] then
		PInfo[inst] = {
			rate = (inst.ClassName == "ParticleEmitter") and inst.Rate or nil,
			forced = false,
			set = nil,
		}
		PList[#PList + 1] = inst
	end
end

local function particleRestore(inst, info)
	if info.forced then
		pcall(rawSet, inst, "Enabled", true)
		info.forced = false
	end
	if info.set and info.rate then
		pcall(rawSet, inst, "Rate", info.rate)
		info.set = nil
	end
end

local function processParticle(inst, info, p, camPos)
	local far = false
	if camPos then
		local par, pos = inst.Parent, nil
		if par then
			if par:IsA("BasePart") then
				pos = par.Position
			elseif par:IsA("Attachment") then
				pos = par.WorldPosition
			end
		end
		if pos then far = (pos - camPos).Magnitude > S.ParticleDistance end
	end

	local isEmitter = info.rate ~= nil
	local offAt, onAt = 0.5, 0.3
	if isEmitter then
		offAt, onAt = 0.9, 0.7
		local cur = inst.Rate
		if info.set and math.abs(cur - info.set) > 0.01 then info.rate = cur end
		if p > 0.03 then
			local target = info.rate * (1 - 0.85 * p)
			if math.abs(cur - target) > 0.01 then inst.Rate = target end
			info.set = target
		elseif info.set then
			if math.abs(cur - info.rate) > 0.01 then inst.Rate = info.rate end
			info.set = nil
		end
	end

	local wantOff = far or (info.forced and p > onAt) or (not info.forced and p >= offAt)
	if wantOff then
		if inst.Enabled then
			inst.Enabled = false
			info.forced = true
		end
	elseif info.forced then
		inst.Enabled = true
		info.forced = false
	end
end

local function particleLoop(gen)
	local p, cursor, nextP = 0, 1, 0
	while PA.enabled and PA.gen == gen do
		local now = os.clock()
		if now >= nextP then
			nextP = now + 0.25
			p += (Perf.Pressure(S.ParticleFps) - p) * 0.35
		end
		local cam = Workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position
		local t0, steps = os.clock(), 0
		while steps < 300 and os.clock() - t0 < 0.0012 do
			local n = #PList
			if n == 0 then break end
			if cursor > n then cursor = 1 end
			local inst = PList[cursor]
			local info = PInfo[inst]
			if not inst.Parent or not info then
				if info then particleRestore(inst, info) end
				PInfo[inst] = nil
				PList[cursor] = PList[n]
				PList[n] = nil
			else
				processParticle(inst, info, p, camPos)
				cursor += 1
			end
			steps += 1
		end
		RunService.Heartbeat:Wait()
	end
end

function PA.enable(f)
	task.spawn(particleLoop, f.gen)
	ScanAll(f, PA.apply)
end

function PA.disable()
	local step = Budget(4)
	for i = 1, #PList do
		local inst = PList[i]
		local info = PInfo[inst]
		if info then particleRestore(inst, info) end
		step()
	end
	table.clear(PList)
	PInfo = setmetatable({}, { __mode = "k" })
end

local GC = NewFeature("GC", {})
local gcWarned = false

local function totalMem()
	local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
	return ok and v or 0
end

local function CollectNow(silent)
	local before = totalMem()
	local ok = pcall(collectgarbage, "collect")
	pcall(collectgarbage, "step", 200)
	if ENV.cleardrawcache then pcall(ENV.cleardrawcache) end
	if not ok and not gcWarned then
		gcWarned = true
		Notify("Garbage Collector", "This executor blocks collectgarbage('collect'); only the draw cache was cleared.", 6)
	end
	task.wait(0.6)
	local after = totalMem()
	if not silent then
		Notify("Garbage Collector", string.format("Memory %d MB → %d MB (%+d MB)", before, after, after - before), 4)
	end
	return before - after
end

function GC.enable(f)
	local gen, last = f.gen, os.clock()
	task.spawn(function()
		while GC.enabled and GC.gen == gen do
			task.wait(1)
			local now = os.clock()
			local overLimit = totalMem() >= S.GCThreshold and now - last >= 20
			if now - last >= S.GCInterval or overLimit then
				last = os.clock()
				CollectNow(not overLimit)
				last = os.clock()
			end
		end
	end)
end

local DR = NewFeature("Distance", {})
local DR_OWN = "Distance"
local DList, DSet, DHidden = {}, setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })

function DR.apply(inst)
	if inst:IsA("BasePart") and inst ~= Terrain and not DSet[inst] and inst.Transparency < 1 and not IsCharacter(inst) then
		DSet[inst] = true
		DList[#DList + 1] = inst
	end
end

local function distanceLoop(gen)
	local cursor, nextP, pressure, R, fogOwned = 1, 0, 0, S.RenderDistance, false
	while DR.enabled and DR.gen == gen do
		local now = os.clock()
		if now >= nextP then
			nextP = now + 0.5
			local target = S.AdaptiveDistance and Perf.Pressure(50) or 0
			pressure += (target - pressure) * 0.3
			R = S.RenderDistance * (1 - 0.6 * pressure)
			if S.FogMask and not (Features.NoFog.enabled or Features.QuickLighting.enabled) then
				local fe = R * 1.05
				if fogOwned or Lighting.FogEnd > fe then
					fogOwned = true
					Mod.Set(DR_OWN, Lighting, "FogEnd", fe)
					Mod.Set(DR_OWN, Lighting, "FogStart", R * 0.5)
				end
			elseif fogOwned then
				fogOwned = false
				Mod.Unset(DR_OWN, Lighting, "FogEnd")
				Mod.Unset(DR_OWN, Lighting, "FogStart")
			end
		end

		local cam = Workspace.CurrentCamera
		if cam then
			local cpos = cam.CFrame.Position
			local Rin = R * 0.92
			local t0, steps = os.clock(), 0
			while steps < 500 and os.clock() - t0 < 0.0012 do
				local n = #DList
				if n == 0 then break end
				if cursor > n then cursor = 1 end
				local part = DList[cursor]
				if not part.Parent then
					DHidden[part] = nil
					DSet[part] = nil
					Mod.Unset(DR_OWN, part, "LocalTransparencyModifier")
					DList[cursor] = DList[n]
					DList[n] = nil
				else
					local d = (part.Position - cpos).Magnitude - part.Size.Magnitude * 0.5
					if DHidden[part] then
						if d < Rin then
							Mod.Unset(DR_OWN, part, "LocalTransparencyModifier")
							DHidden[part] = nil
						end
					elseif d > R then
						if Mod.Set(DR_OWN, part, "LocalTransparencyModifier", 1) then DHidden[part] = true end
					end
					cursor += 1
				end
				steps += 1
			end
		end
		RunService.Heartbeat:Wait()
	end
end

function DR.enable(f)
	task.spawn(distanceLoop, f.gen)
	ScanAll(f, DR.apply)
end

function DR.disable()
	table.clear(DList)
	DSet = setmetatable({}, { __mode = "k" })
	DHidden = setmetatable({}, { __mode = "k" })
end

local UN = NewFeature("FpsUnlocker", {})
local lastInput = os.clock()
local function touchInput() lastInput = os.clock() end
Connect(UserInputService.InputBegan, touchInput)
Connect(UserInputService.InputChanged, touchInput)

local function unlockCap()
	return S.MaxFps >= 1000 and 9999 or S.MaxFps
end

local function playerIsActive()
	if os.clock() - lastInput < S.IdleSeconds then return true end
	local ok, keys = pcall(UserInputService.GetKeysPressed, UserInputService)
	if ok and #keys > 0 then return true end
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.MoveDirection.Magnitude > 0.05 then return true end
	return false
end

function UN.enable(f)
	if not ENV.setfpscap then
		Notify("FPS Unlocker", "This executor has no setfpscap(): the unlocker can't work here.", 6)
		return
	end
	FPS.Request("Unlocker", unlockCap())
	local gen = f.gen
	task.spawn(function()
		while UN.enabled and UN.gen == gen do
			if playerIsActive() then
				FPS.Release("Idle")
			else
				FPS.Request("Idle", S.IdleFps)
			end
			task.wait(0.5)
		end
	end)
end

function UN.disable()
	FPS.Release("Unlocker")
	FPS.Release("Idle")
end

function UN.refresh()
	if UN.enabled and UN.applied and ENV.setfpscap then FPS.Request("Unlocker", unlockCap()) end
end

local FF = {}

local function FFlag(key, name, apply, enable, disable)
	local f = NewFeature(name, { apply = apply, enable = enable, disable = disable })
	if apply then
		local userEnable = enable
		f.enable = function(self)
			if userEnable then userEnable(self) end
			ScanAll(self, apply)
		end
	end
	FF[key] = f
	return f
end

local function notLocalCharacter(inst)
	local lc = LocalPlayer.Character
	return not (lc and inst:IsDescendantOf(lc))
end

FFlag("FF_QualityLock", "GraphicsQualityLock", nil, function(f)
	local R = settings().Rendering
	Mod.SetEnum(f.name, R, "QualityLevel", "QualityLevel", "Level01")
	Mod.SetEnum(f.name, R, "MeshPartDetailLevel", "MeshPartDetailLevel", "Level04")
end)

FFlag("FF_TextureReduction", "TextureReduction", function(inst)
	local cn = inst.ClassName
	if cn == "Decal" or cn == "Texture" then
		if not IsCharacter(inst) then Mod.Set("TextureReduction", inst, "Transparency", 1) end
	elseif cn == "SurfaceAppearance" or cn == "MaterialVariant" then
		if not IsCharacter(inst) then Mod.Set("TextureReduction", inst, "Parent", nil) end
	elseif cn == "MeshPart" then
		if inst.TextureID ~= "" and not IsCharacter(inst) then Mod.Set("TextureReduction", inst, "TextureID", "") end
	end
end)

FFlag("FF_Instancing", "GlobalInstancing", function(inst)
	if inst:IsA("BasePart") and inst ~= Terrain and not IsCharacter(inst) then
		Mod.Set("GlobalInstancing", inst, "Material", Enum.Material.SmoothPlastic)
		Mod.Set("GlobalInstancing", inst, "Reflectance", 0)
	end
end, function(f)
	Mod.Set(f.name, MaterialService, "Use2022Materials", false)
end)

FFlag("FF_LightCulling", "LightCulling", function(inst)
	if inst:IsA("Light") then
		Mod.Set("LightCulling", inst, "Shadows", false)
	elseif inst:IsA("BasePart") and inst ~= Terrain then
		Mod.Set("LightCulling", inst, "CastShadow", false)
	end
end, function(f)
	Mod.Set(f.name, Lighting, "GlobalShadows", false)
	Mod.Set(f.name, Lighting, "ShadowSoftness", 0)
end)

FFlag("FF_PostFx", "PostProcessingOff", function(inst)
	if inst:IsA("PostEffect") then Mod.Set("PostProcessingOff", inst, "Enabled", false) end
end)

FFlag("FF_SkyClouds", "SkyCloudReduction", function(inst)
	local cn = inst.ClassName
	if cn == "Sky" then
		Mod.Set("SkyCloudReduction", inst, "StarCount", 0)
		Mod.Set("SkyCloudReduction", inst, "CelestialBodiesShown", false)
	elseif cn == "Atmosphere" then
		Mod.Set("SkyCloudReduction", inst, "Density", 0)
		Mod.Set("SkyCloudReduction", inst, "Haze", 0)
		Mod.Set("SkyCloudReduction", inst, "Glare", 0)
	elseif cn == "Clouds" then
		Mod.Set("SkyCloudReduction", inst, "Enabled", false)
	end
end)

FFlag("FF_Terrain", "TerrainSimplifier", nil, function(f)
	if not Terrain then return end
	Mod.Set(f.name, Terrain, "WaterWaveSize", 0)
	Mod.Set(f.name, Terrain, "WaterWaveSpeed", 0)
	Mod.Set(f.name, Terrain, "WaterReflectance", 0)
	Mod.Set(f.name, Terrain, "Decoration", false, true)
end)

FFlag("FF_Audio", "AudioOptimizer", function(inst)
	if inst:IsA("SoundEffect") then Mod.Set("AudioOptimizer", inst, "Enabled", false) end
end, function(f)
	Mod.SetEnum(f.name, SoundService, "AmbientReverb", "ReverbType", "NoReverb")
end)

FFlag("FF_Humanoid", "HumanoidOptimizer", function(inst)
	if inst.ClassName == "Humanoid" and notLocalCharacter(inst) then
		Mod.SetEnum("HumanoidOptimizer", inst, "DisplayDistanceType", "HumanoidDisplayDistanceType", "None")
		Mod.SetEnum("HumanoidOptimizer", inst, "HealthDisplayType", "HumanoidHealthDisplayType", "AlwaysOff")
	end
end)

FFlag("FF_Physics", "PhysicsThrottle", nil, function(f)
	Mod.SetEnum(f.name, Workspace, "InterpolationThrottling", "InterpolationThrottlingMode", "Enabled")
	Mod.Set(f.name, settings().Physics, "AllowSleep", true)
end)

FFlag("FF_Ads", "AdsBlocker", function(inst)
	if inst.ClassName == "AdGui" then Mod.Set("AdsBlocker", inst, "Enabled", false) end
end)

do
	local BT = NewFeature("BackgroundThrottle", {})
	local function react(focused)
		if not BT.enabled or not BT.applied then return end
		if focused then
			Render.Set("Background", false)
			FPS.Release("Background")
		else
			Render.Set("Background", true)
			FPS.Request("Background", S.BackgroundFps)
		end
	end
	function BT.enable()
		Focus.handlers.BT = react
		react(Focus.focused)
	end
	function BT.disable()
		Focus.handlers.BT = nil
		Render.Set("Background", false)
		FPS.Release("Background")
	end
	FF.FF_Background = BT
end

FFlag("FF_Cullable", "CullableScene", function(inst)
	if inst.ClassName == "Model" and not inst:FindFirstChildOfClass("Humanoid") then
		Mod.SetEnum("CullableScene", inst, "LevelOfDetail", "ModelLevelOfDetail", "StreamingMesh")
	end
end, function(f)
	Mod.SetEnum(f.name, Workspace, "LevelOfDetail", "ModelLevelOfDetail", "StreamingMesh")
end)

FFlag("FF_CompatLighting", "CompatibilityLighting", nil, function(f)
	if not (ENV.sethidden and ENV.gethidden) then
		Notify("Compatibility Lighting", "Your executor has no sethiddenproperty/gethiddenproperty.", 5)
		return
	end
	Mod.SetEnum(f.name, Lighting, "Technology", "Technology", "Compatibility", true)
end)

FFlag("FF_MeshDetail", "MeshDetailReduction", function(inst)
	if inst:IsA("TriangleMeshPart") and not IsCharacter(inst) then
		Mod.SetEnum("MeshDetailReduction", inst, "RenderFidelity", "RenderFidelity", "Performance")
	end
end)

local QG = NewFeature("QuickGraphics", {})
local QL = NewFeature("QuickLighting", {})
local QT = NewFeature("QuickTexture", {})
local QR = NewFeature("QuickTerrain", {})
local QE = NewFeature("QuickEffects", {})
local NF = NewFeature("NoFog", {})

function QG.apply(inst)
	if inst:IsA("TriangleMeshPart") and not IsCharacter(inst) then
		Mod.SetEnum("QuickGraphics", inst, "RenderFidelity", "RenderFidelity", "Performance")
	end
end

function QG.enable(f)
	local R = settings().Rendering
	Mod.SetEnum(f.name, R, "QualityLevel", "QualityLevel", "Level01")
	Mod.SetEnum(f.name, R, "MeshPartDetailLevel", "MeshPartDetailLevel", "Level04")
	Mod.SetEnum(f.name, Workspace, "InterpolationThrottling", "InterpolationThrottlingMode", "Enabled")
	ScanAll(f, QG.apply)
end

function QL.apply(inst)
	local cn = inst.ClassName
	if cn == "Atmosphere" then
		Mod.Set("QuickLighting", inst, "Density", 0)
		Mod.Set("QuickLighting", inst, "Offset", 0)
		Mod.Set("QuickLighting", inst, "Glare", 0)
		Mod.Set("QuickLighting", inst, "Haze", 0)
	elseif inst:IsA("PostEffect") then
		Mod.Set("QuickLighting", inst, "Enabled", false)
	elseif inst:IsA("BasePart") and inst ~= Terrain and not IsCharacter(inst) then
		Mod.Set("QuickLighting", inst, "CastShadow", false)
	end
end

function QL.enable(f)
	Mod.Set(f.name, Lighting, "GlobalShadows", false)
	Mod.Set(f.name, Lighting, "FogEnd", 1e9)
	ScanAll(f, QL.apply)
end

function QT.apply(inst)
	local cn = inst.ClassName
	if cn == "Sky" then
		Mod.Set("QuickTexture", inst, "StarCount", 0)
		Mod.Set("QuickTexture", inst, "CelestialBodiesShown", false)
	elseif cn == "SurfaceAppearance" then
		if not IsCharacter(inst) then Mod.Set("QuickTexture", inst, "Parent", nil) end
	elseif cn == "Decal" or cn == "Texture" then
		if not IsCharacter(inst) then Mod.Set("QuickTexture", inst, "Transparency", 1) end
	elseif inst:IsA("BasePart") and inst ~= Terrain and not IsCharacter(inst) then
		Mod.Set("QuickTexture", inst, "Material", Enum.Material.SmoothPlastic)
	end
end

function QT.enable(f)
	ScanAll(f, QT.apply)
end

function QR.enable(f)
	if not Terrain then return end
	Mod.Set(f.name, Terrain, "WaterWaveSize", 0)
	Mod.Set(f.name, Terrain, "WaterWaveSpeed", 0)
	Mod.Set(f.name, Terrain, "WaterReflectance", 0)
	Mod.Set(f.name, Terrain, "WaterTransparency", 0)
	Mod.Set(f.name, Terrain, "Decoration", false, true)
end

local EffectClasses = { ParticleEmitter = true, Sparkles = true, Smoke = true, Trail = true, Fire = true }

function QE.apply(inst)
	if EffectClasses[inst.ClassName] then
		Mod.Set("QuickEffects", inst, "Enabled", false)
	end
end

function QE.enable(f)
	ScanAll(f, QE.apply)
end

function NF.apply(inst)
	if inst.ClassName == "Atmosphere" then
		Mod.Set("NoFog", inst, "Density", 0)
		Mod.Set("NoFog", inst, "Haze", 0)
	end
end

function NF.enable(f)
	Mod.Set(f.name, Lighting, "FogEnd", 1e9)
	local gen = f.gen
	task.spawn(function()
		while NF.enabled and NF.gen == gen do
			if Lighting.FogEnd < 1e8 then Lighting.FogEnd = 1e9 end
			task.wait(1)
		end
	end)
	ScanAll(f, NF.apply)
end
local ASSET_B64 = {
	logo = [==[
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
1hGOhs8I3xB+b6b5TOnMtgiI4EdsiLgfaRmZF/l9FCkqMqou6lG0U3RxdPcs1qzkWftnvY7xj6mMuTvbarZydmesamxSbGPsm7iAuKq4gXiH+EXxlxJ0EyQJ
7YnkxNjEPYnjcwLnbJoznOSaVJZ0Y67l3KK5F+bpzsuedzxZNVmQfDiFmBKXsj/lgyBCUC8YT+Wnbk0dE/KEm4VPRb6ijaJRsbe4SjyS5p1WlfY43Tt9Q/po
hk9GdcYzCU9SK3mRGZK5I/NNVkTW3qzP2XHZLTmUnJSco1INaZa0K9cwtyi3T2YrK5MN5Hnmbcobk4fK9+Qj+XPz2xVshUzRo7RSrlAOFkwvqCt4WxhbeLhI
vUha1DPfZv7q+SMLghZ8vZCwULiws9i4eFnx4CK/RbsWI4tTF3cuMV1SumR4afDSfctoy7KW/VDiWFJV8mp53PKOUoPSpaVDK4JXNJWplMnLbq70WrljFWGV
ZFXvapfVW1Z/KheVX6xwrKiu+LBGuObiV05f1Xz1eW3a2t5Kt8rt60jrpOturPdZv69KvWpB1dCG8A2tG/GN5RtfbUredKF6avWOzbTNys0DNWE17VvMtqzb
8qE2o/Z6nX9dy1b9rau3vtkm2ta/3Xd78w6DHRU73u+U7Ly1K3hXa71FffVu0u6C3Y8aYhu6v+Z+3bhHd0/Fno97pXsH9kXv62p0b2zcr7+/sgltUjaNHkg6
cOWbgG/am+2ad7VwWioOwkHlwSffpnx741Dooc7D3MPN35l/t/UI60h5K9I6v3WsLaNtoD2hve/ojKOdHV4dR763/37vMeNjdcc1j1eeoJ0oPfH55IKT46dk
p56dTj891JncefdM/JlrXVFdvWdDz54/F3TuTLdf98nz3uePXfC8cPQi92LbJbdLrT2uPUd+cP3hSK9bb+tl98vtVzyudPRN6zvR79N/+mrA1XPX+NcuXZ95
ve/G7Bu3bibdHLgluvX4dvbtF3cK7kzcXXqPeK/8vtr96gf6D+p/tP6xZcBt4PhgwGDPw1kP7w4Jh57+lP/Th+HSR8xH1SNGI42PnR8fGw0avfJkzpPhp7Kn
E8/Kflb/eetzq+ff/eL7S89Y/NjwC/mLz7+ueanzcu+rqa86xyPHH7zOeT3xpvytztt977jvut/HvR+ZKPxA/lDz0fpjx6fQT/c+53z+/C/3hPP7btcu4QAA
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
e56QewAAAABJRU5ErkJggg==
]==],
	cog = [==[
iVBORw0KGgoAAAANSUhEUgAAAF0AAABdCAYAAADHcWrDAAAE6klEQVR4nO2d73HbOBDF396kAHVwTAXRVXB0BbE7cCq4SwWnVOBJBcxVYKcC6SqwrgLzKrA6
ePeB0MjWkCAWJP6Iwm/Gkw8igMXLElwCCxAoFAqFQqFQuCQktQFHSK4B/AVgFaD6A4BvIrIPULeanER/AVAFbKIVkY8B63fml9QGAADJGmEFB4DKtJOcLEQH
sF5YO1ZyEf3XhbVjJRfRr8rTs3iQkmSstkQkeZ+Te7oJFRfbXh/JRQfwx8LbywuSt0xDnbrvkyG5Ibkl+UjynuToW6UR/DWR6K+uwpv+PJr+baZqNQvsBO/r
VMOe8ZNkZX7LgQeS1YCND+x3is1UzSY9ydl59Avs8yV7dHMfMNclf5D1sDd/QGefzcYDgI8icrBcY2Wq6A2A+yl1XCg/ROSLb2Fv0dkNHc++5RfAb76zllNC
xocJZZeAd/+9RCd5C6D2bXQh1EYHNV7DC8PPfV8KXnP0ak83IVOlLbdQKp8QUuXpjiHitaEOIbWe/oAi+DkrKB+qzp5eQsRRnENIjadfe4g4hrM+TqKXENEJ
5xDSaXgpIaIzTiHkqKeXEFGFUwhp9fQSInoxGkKOeXoJEfWMhpCDnp5hiLgH8Lf5txWR1ixAVOge8p+R11y9fhaS3RJVDjTsWd0ZsLliPnY/DtlpG15SDysH
ADci8kVEWpcCItKKyB2AO5xWq1IxqJ9N9HZ+O5zZo7s9dz6FReQJwA3SCt+qS5BckXxOcFu+0nE4cejDmmkyDp7pkBFhEz72GFnPIfibPsTOrfEX/MzwJpLB
zQw699kfy3HmtZ/knxGMrmY1+mR7FcH2IA4T2uMHQ6yZbA/5fFLZrl3E+IpwEcE/geo98jNg3V81F6tEN/MJTypz3Am9820XqN4n1/eIIz4pGP95lHEhtOht
oHr/1RbwEX3nUWaUKbmBjvW3gapWO4uP6LVHmVE4R2xrr78KVLV6ks1H9E8eZVwIPUNYBapXrYdKdOONXqlkDoQWvQ5U7632LtV6epgXgI7fA9YNdPPtobjI
F6MjVSDbY7yRbuY2uolgNFnmXpJN79bTZX7Xhzqy/VuOjPG2NdIVgC3irztO3tNzhN067xbxV8H26Fa9evtge5A2SLPQuwIw6i1jGMEbpFl2XMOSEZDrGuka
wIvvUGPKpbhL31IN/WATPYeF3S312QAN0gwp5wzqd0l5Lzt007N7AHsROZgh6Ljv8zPySnIdzHsZS6u71n2iU7HuMy25jPMzLZfRFPw+t1UL5/tYuDuan268
/RklXdqFefLTzf/at1lMWj5Oa6WajV5b5BUd5MZORG5cLtSIXqOLfwv9zL+7ziRzhsoEuHR+aHLRtTumK3QhZOFE2B3TZkW9PFTfMxoinqM+BaO8ML0jzikY
JYR8hyqd7siU46SufUOvc4h4zpTjpLwPDlsIXl4OTBDdhJA73/IXjipEPGfqEYEuc+47nJI3x848TIXm7MjZ1nC9YXcs6vlq+GZoqY2n0z1zoGH/CaRr81uQ
E0hngV2qRq0sUw90KgavdDgmxPQrv7N2p8B0p0rfp+57Uhj/sOOge5tcSP6pAsZfAPc+rnUukosOlG9ipGK3sHas5CJ6rNs9i2/X5SK6eoda5u1YyUX0WB7Y
RmrHSvKHyhFe0VcaP6Q24A13CPw90gD1FgqFQqFQKFwB/wMICWTqPedc+AAAAABJRU5ErkJggg==
]==],
	profiles = [==[
iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAACyUlEQVR4nO2bQWsTQRiGn6+UIkU89CAexJN46KmoKCIIXqxH8SiIF++epKh4FRT6BwTxpD+h
VOkhiEj1ID1IKaWIiBQJUqVIlRgcD0ma6XSTXWc2+Xaz88CS7DfvZL59d2czM8kKDsaYA8BNYBaYBCaAcWDMerU3rFeceIdxt53/5G97s2laZfZ+09I329tP
4AXwWER+2x8i9o4xZqotPB2YcFF5D8yKyLdOwD1TTxjdgwc4CTy1A7tXgDHmDPB22BkpcV5E3sDevjmdUsnuh25/DMG9CoehOwHsMyCJR8BD9t5YOuRlwqAN
mAPu9hKnGfBdRLYyNlxIjDG/+pVndXVkSTMgz75eSKIB2gloEw3QTkCbaIB2AtpEA7QT0CZtKNxzHGCMOU5rnmCzLiJ3HN0F4JZfepmZE5ENn4reBgBTwFUn
tpygO5qgyxv3RGSm8l0gGqCdgDYhq7UfgFNObCdBt5igy5s134reBojIDq1V1jTdFlDYRZXKd4FoQGB56YkGaCegjfe3gDHmCHCN7m8GTeCziCw4umngckiS
GXguIl99KoaMA44B807sJbDgxGYSdHnzGvAyoPJdIBqgnYA2IfeATeAB3R9N/wBJixKrbd0g2fStGDIX+ALcy6BbAVZ82xk0le8CcSQYWF56Rv4A06i8ASFz
gQngsBNuiEjd0U3SWkIfJHURafhUDBkHzLD/b3XLwDkndgV4FtBOFs4C73wqVr4LRAO0E9Am5B6wDdSc2GqCrp6gy5tt34ohc4E14GIG3RKw5NvOoIkjwcDy
0jPyB5hGNEA7AW2iAdoJaBMN0E5Am8obkDYUHmsvfJSZvic5zYD7tJ66KjN9T6BtwMce5aHP/RaRT503u5eHiLyiwLO2HKmJSK2z4/aPG8D6UNMZLhvAdTsg
rsIYcwi4DVwCDtJ9fL6MNIEGrT9wLgLzIvLDFvwDhCKLrPHSXFoAAAAASUVORK5CYII=
]==],
	quit = [==[
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
1hGOhs8I3xB+b6b5TOnMtgiI4EdsiLgfaRmZF/l9FCkqMqou6lG0U3RxdPcs1qzkWftnvY7xj6mMuTvbarZydmesamxSbGPsm7iAuKq4gXiH+EXxlxJ0EyQJ
7YnkxNjEPYnjcwLnbJoznOSaVJZ0Y67l3KK5F+bpzsuedzxZNVmQfDiFmBKXsj/lgyBCUC8YT+Wnbk0dE/KEm4VPRb6ijaJRsbe4SjyS5p1WlfY43Tt9Q/po
hk9GdcYzCU9SK3mRGZK5I/NNVkTW3qzP2XHZLTmUnJSco1INaZa0K9cwtyi3T2YrK5MN5Hnmbcobk4fK9+Qj+XPz2xVshUzRo7RSrlAOFkwvqCt4WxhbeLhI
vUha1DPfZv7q+SMLghZ8vZCwULiws9i4eFnx4CK/RbsWI4tTF3cuMV1SumR4afDSfctoy7KW/VDiWFJV8mp53PKOUoPSpaVDK4JXNJWplMnLbq70WrljFWGV
ZFXvapfVW1Z/KheVX6xwrKiu+LBGuObiV05f1Xz1eW3a2t5Kt8rt60jrpOturPdZv69KvWpB1dCG8A2tG/GN5RtfbUredKF6avWOzbTNys0DNWE17VvMtqzb
8qE2o/Z6nX9dy1b9rau3vtkm2ta/3Xd78w6DHRU73u+U7Ly1K3hXa71FffVu0u6C3Y8aYhu6v+Z+3bhHd0/Fno97pXsH9kXv62p0b2zcr7+/sgltUjaNHkg6
cOWbgG/am+2ad7VwWioOwkHlwSffpnx741Dooc7D3MPN35l/t/UI60h5K9I6v3WsLaNtoD2hve/ojKOdHV4dR763/37vMeNjdcc1j1eeoJ0oPfH55IKT46dk
p56dTj891JncefdM/JlrXVFdvWdDz54/F3TuTLdf98nz3uePXfC8cPQi92LbJbdLrT2uPUd+cP3hSK9bb+tl98vtVzyudPRN6zvR79N/+mrA1XPX+NcuXZ95
ve/G7Bu3bibdHLgluvX4dvbtF3cK7kzcXXqPeK/8vtr96gf6D+p/tP6xZcBt4PhgwGDPw1kP7w4Jh57+lP/Th+HSR8xH1SNGI42PnR8fGw0avfJkzpPhp7Kn
E8/Kflb/eetzq+ff/eL7S89Y/NjwC/mLz7+ueanzcu+rqa86xyPHH7zOeT3xpvytztt977jvut/HvR+ZKPxA/lDz0fpjx6fQT/c+53z+/C/3hPP7btcu4QAA
ACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAB3RJTUUH6gkUETAjyaW+OwAAACJ0RVh0U29mdHdhcmUAQWRvYmXCriBQaG90
b3Nob3DCriBUb3VjaOLO2UAAAATrSURBVHic7VstdxtHFL2zSMxiFZNZxWwolsCwiDUsgWX1P4jKzCpY5pS5qP0HETRry2wUhaUoCjPZvQUze7zezHvzsbNS
z4nvOQay5n3deTuz8+YJeMITvmmYQxkiyRw5Y8yoPo6mXAmYEXbFMaUJKU5A7kynohQRxQg4VOB9DCViMAHHCryPXCIGEZAR/F3TNLdVVX0CsAdw3/t+AmDa
NM2sqqoFgO9TlOeQkEVAYuC/A9gC2AHoBt4PvsXE/U0BzACcAngO4IdYgylEJBMQGfy/AH5FJ3BjjBRwyN4Ej4n4EcB3IbnRtk+GcUlySXI2gu2Z030ZcqK0
7dYBDVuSK5KnbtbG8mHibKyczcOQEAh+Q/J8zMA9/kyczc3oJASCX48964pfbTasRyMhYuYXheIZ4uNitExQdF7zwGmv+Ng+DtdFCZCU1XX9N+1qfPTgWzgS
ls63MiQ4ucaj6xXJ6QhxDALJqfOtjyaZAIlF2gVH3eNJPlPkSXIekJ8H5N8qsjMqi2IqAf3ZvyV5HiNf1/V7JYCrgO0rRfYzyZOA/LnztYv4LFCMXzAy9Ume
KXpIIQtInrggJbyOsD11vnqRS8CO5DIm+I4ebSa9WUDyJ0mgruv3CbaXzudiBFwyceFjeDa/yoK6rj8o458l2J5SODPkBE+Sq5TgO/reKjqvemNfxo6NtL2S
lGlCPuyY+cZH8iQwq2edsX8IYz4zsHMIthcMPAaVJNv7fANbyEiGMeZLVVVrZciFc3YOQMqyjTHmY4b5PazvXTyKTSKgX0y4hVzBCcIY81vTNFvh6zboN74v
m6bZGWN+zjR9D+v7I3e6HyQC+thhAAEAoGTB1D0GF4Kc9/+RuIf1PR7CM5i1AHp0S8+4FynbnmLTuxC238dmwKDZ7yBpNgfOfgvV91gCisAtZNqC2MXGGPPP
mP4ABybAYYPwjrJHPFGDEEtAsXO/MeYLbLlcw9aNKwHV91gCZixU/Ajs9y1WOS8+HlvtnYKIWAJOUS4LNjGDmqZ5V8DWBNZ3EbFvgkUIoD3MRG2pVVU9Z8Lh
R4CPgKzDUPZZoKf7L0G/98RY1/WHgfayzwJ9zAEMIoC2kCFVk7yvwVVVnVIpf0VgAet7GoRZWjOzEEr9RPiLG6Nlh1oCE2xOKdQGY4TJAfVAjz6tJjB3Y7RC
ak4tIL8uqDjyhonbIfWqUL8gop0VziQbHpsT56sXsUp82DJxMaReFzzrjRULqYn1wAWFm+MUxyVcMPLun0p9XwooUE5/GWFzxiEV4QgS9iRfMOJRCATj3eOp
rAVuIRUXRNrUf+F8HBa8QgDruv6TgYvRQCBqOgeI826LLvhz55sXyQR0SPDdD6pX40PK2xp5FAqklK/I0+8FPQRIWDvDk57Ma0kgdjGLvVqjnfkFj9gkcckj
9QnwoS9AbZoqZUzDO9qrqINdmdO+6S2d7XGDdwZDuKEtQBarHQh+TJyNlbOporTxGKw5UjbwYdbV5z0l+LE6Re9gO0VvYOvy+4GdolPYc/0StlM02EMc2yma
3U4aScRHANd4IOITgHtjjFoUddnTbZFdAniFiKNtaovsIbvF72CJuIXLCmFcO9sL2MCjO8YP1i3eRfGFJhNH+b1AF8ciYmhXeLGLEcGRkqR8patES/wxfjU2
CP/7X435MJSMsX87+IQnPOHbxX+9PMIyOO5MLAAAAABJRU5ErkJggg==
]==],
	sliderOff = [==[
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
1hGOhs8I3xB+b6b5TOnMtgiI4EdsiLgfaRmZF/l9FCkqMqou6lG0U3RxdPcs1qzkWftnvY7xj6mMuTvbarZydmesamxSbGPsm7iAuKq4gXiH+EXxlxJ0EyQJ
7YnkxNjEPYnjcwLnbJoznOSaVJZ0Y67l3KK5F+bpzsuedzxZNVmQfDiFmBKXsj/lgyBCUC8YT+Wnbk0dE/KEm4VPRb6ijaJRsbe4SjyS5p1WlfY43Tt9Q/po
hk9GdcYzCU9SK3mRGZK5I/NNVkTW3qzP2XHZLTmUnJSco1INaZa0K9cwtyi3T2YrK5MN5Hnmbcobk4fK9+Qj+XPz2xVshUzRo7RSrlAOFkwvqCt4WxhbeLhI
vUha1DPfZv7q+SMLghZ8vZCwULiws9i4eFnx4CK/RbsWI4tTF3cuMV1SumR4afDSfctoy7KW/VDiWFJV8mp53PKOUoPSpaVDK4JXNJWplMnLbq70WrljFWGV
ZFXvapfVW1Z/KheVX6xwrKiu+LBGuObiV05f1Xz1eW3a2t5Kt8rt60jrpOturPdZv69KvWpB1dCG8A2tG/GN5RtfbUredKF6avWOzbTNys0DNWE17VvMtqzb
8qE2o/Z6nX9dy1b9rau3vtkm2ta/3Xd78w6DHRU73u+U7Ly1K3hXa71FffVu0u6C3Y8aYhu6v+Z+3bhHd0/Fno97pXsH9kXv62p0b2zcr7+/sgltUjaNHkg6
cOWbgG/am+2ad7VwWioOwkHlwSffpnx741Dooc7D3MPN35l/t/UI60h5K9I6v3WsLaNtoD2hve/ojKOdHV4dR763/37vMeNjdcc1j1eeoJ0oPfH55IKT46dk
p56dTj891JncefdM/JlrXVFdvWdDz54/F3TuTLdf98nz3uePXfC8cPQi92LbJbdLrT2uPUd+cP3hSK9bb+tl98vtVzyudPRN6zvR79N/+mrA1XPX+NcuXZ95
ve/G7Bu3bibdHLgluvX4dvbtF3cK7kzcXXqPeK/8vtr96gf6D+p/tP6xZcBt4PhgwGDPw1kP7w4Jh57+lP/Th+HSR8xH1SNGI42PnR8fGw0avfJkzpPhp7Kn
E8/Kflb/eetzq+ff/eL7S89Y/NjwC/mLz7+ueanzcu+rqa86xyPHH7zOeT3xpvytztt977jvut/HvR+ZKPxA/lDz0fpjx6fQT/c+53z+/C/3hPP7btcu4QAA
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
]==],
	sliderOn = [==[
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
1hGOhs8I3xB+b6b5TOnMtgiI4EdsiLgfaRmZF/l9FCkqMqou6lG0U3RxdPcs1qzkWftnvY7xj6mMuTvbarZydmesamxSbGPsm7iAuKq4gXiH+EXxlxJ0EyQJ
7YnkxNjEPYnjcwLnbJoznOSaVJZ0Y67l3KK5F+bpzsuedzxZNVmQfDiFmBKXsj/lgyBCUC8YT+Wnbk0dE/KEm4VPRb6ijaJRsbe4SjyS5p1WlfY43Tt9Q/po
hk9GdcYzCU9SK3mRGZK5I/NNVkTW3qzP2XHZLTmUnJSco1INaZa0K9cwtyi3T2YrK5MN5Hnmbcobk4fK9+Qj+XPz2xVshUzRo7RSrlAOFkwvqCt4WxhbeLhI
vUha1DPfZv7q+SMLghZ8vZCwULiws9i4eFnx4CK/RbsWI4tTF3cuMV1SumR4afDSfctoy7KW/VDiWFJV8mp53PKOUoPSpaVDK4JXNJWplMnLbq70WrljFWGV
ZFXvapfVW1Z/KheVX6xwrKiu+LBGuObiV05f1Xz1eW3a2t5Kt8rt60jrpOturPdZv69KvWpB1dCG8A2tG/GN5RtfbUredKF6avWOzbTNys0DNWE17VvMtqzb
8qE2o/Z6nX9dy1b9rau3vtkm2ta/3Xd78w6DHRU73u+U7Ly1K3hXa71FffVu0u6C3Y8aYhu6v+Z+3bhHd0/Fno97pXsH9kXv62p0b2zcr7+/sgltUjaNHkg6
cOWbgG/am+2ad7VwWioOwkHlwSffpnx741Dooc7D3MPN35l/t/UI60h5K9I6v3WsLaNtoD2hve/ojKOdHV4dR763/37vMeNjdcc1j1eeoJ0oPfH55IKT46dk
p56dTj891JncefdM/JlrXVFdvWdDz54/F3TuTLdf98nz3uePXfC8cPQi92LbJbdLrT2uPUd+cP3hSK9bb+tl98vtVzyudPRN6zvR79N/+mrA1XPX+NcuXZ95
ve/G7Bu3bibdHLgluvX4dvbtF3cK7kzcXXqPeK/8vtr96gf6D+p/tP6xZcBt4PhgwGDPw1kP7w4Jh57+lP/Th+HSR8xH1SNGI42PnR8fGw0avfJkzpPhp7Kn
E8/Kflb/eetzq+ff/eL7S89Y/NjwC/mLz7+ueanzcu+rqa86xyPHH7zOeT3xpvytztt977jvut/HvR+ZKPxA/lDz0fpjx6fQT/c+53z+/C/3hPP7btcu4QAA
ACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAB3RJTUUH6gkUETsyQOFHAgAAACJ0RVh0U29mdHdhcmUAQWRvYmXCriBQaG90
b3Nob3DCriBUb3VjaOLO2UAAAAiMSURBVHic7ZzrUxvXGYefs1p0QWBAAtuF1AZsMw5g7thOxq1ju2nStGldl6a3D6knf1Kn0w+dtJNpPa2nX+rY9Xh8S5pL
U19AJsaeOo4RDg7E5iaBQAhp9/SDtIskVgIcbmH9m9nZo7Mr7avz7Pvue87uWcEzLVUia71cyRzlpzJiUbW3tz/1Qb7JknJ1/rYQmU3f3d29JBaL7mRHUPkg
GdtUVaWgoAAhlGQrGt8xQEhJIpFgbm7O/G42JKv6xcDl3fgM1sL6ltZW6urqQHHg9RbhLHAikUiZXBRFAAIpdaYjU8RjCUbGRvjPRx8yNzeXExrMg8sHLecG
u8GyAmXUVVZWsntPHU1NTczOxZ/q990uFwPBfj67d4/79z9DSmkJbzFolpV2h2V8djqddHW9QYnPRzw+D0pVHXgLvdTW1vCt7dvx+8pwu90IIYjFYoTDkww/
fsxAcICxiQk0Tcs4hpCSv/7lHaLRaPJzFrh80BZU2AlWPq/q7NzP3oZGXC4XAIoQ7N61i7q6Pfh9PgoLPXnDm6HZ2VlC4TD9wQHu3LlLPJEwjzP6+DHnzr2L
pmk5vS0bWsaHZ7AkLpeLgy+8SH1jA/F4siFra2poa22m3O9fEqRcikxPEwj0cu/+fTMZGR8b4cqlS4TDYcDa29KhmQU7wzI+CyF44xe/pLikFACPx8Px139I
WVnZih4/Go3y7rnzjI2PJ4+va7zz5z+RSHlfPmjKilryDZaUkhNdP2dLaRJOTXU1XSeOU1pauuLH8ng8HP/J67S1tgAgFAdvnnwLn99v2pJLCtjXu4xU3OFw
8NMTP8NfXoGUktqaao4deYnioqKvFQLzyeV0cqCzg/2dHQghEIrCq6++htvttrTTYGQrD8t13WpuaaF86zZ0Xefbzz3HKy9/D6ezYNXtEULQ3trCiwcPAFBY
VMSJri7TzmxoYDNg6TIaoKqqio7OZINt3VrBy8eOrppXWUkIQUP98+zaVQtAYdEWGhoaF9hp7G4bYFZnK8DhI0fRU53Yw4cO4Xa71tw2VVX5/rGjlJWVgpS8
8oPXKC4uttrVHsBywfL5/ZSkMsK21hbKy/1rbpshIQT7OzoAmIpE2FtfbxkabQHMSoqi8Ktf/4aEplGyZQud7W1rGgqtVFtTzc4dOwDoaO/E6XQuuO7aClj6
GbtzZzWx1Ljg7l216w4Lkl7W2tKEEIK4pnH48EvmNtskHbn6NFu3bzPLTfsaNwQwgK0VFTgcDgBKynwIJQORY9MDy5bR92ptaQOSHWSPx7POVs1LVVWam/YB
4PP5ssPi5k46ciUbpaWlkDpzq6t3rLldi6mx/vmkxwtBRXk5YKOQmC0pJU3NzSQSCQTgW+FxwpWQ1+ulqMiLlJJD3/mu/bLE7PTYnxqzQwg87o0TDtPl9XoB
2LZ9e3q1/a5hSSX/thBiXTrKS1GhcV0Viv08LFsJTTPLRka20aSqKoB5y8WQbYAZ2aGUkoQ23wiKsjGbwLDLeDQh5WXqxrR2BZTvnpJx9gLour4W5ixbhl0F
BZl3DTYtsHxSlfkwqKWFx40kIxSmn1xgU2BS6qm1ZHZ2dp2tsdbMTPKJKvTME8qWwMbGx4AksGh0YwKbnp4GYHh4OKPelsBu9fRQkAo14xMT62zNQkWmp5mK
RBBC8OEH/87YZktg4XDYfBY+OPBwna1ZqL6+u6mSZGxsLGPbpgW22Oh74FYAgIGHD5mZmVkLk5akeDzOp319AIyPjxOLxTK2b1pg2RJCZEAcHvrSLH96u2/V
phUtV09GRszMNRyayM5iNdsAM2SAC/b343I6Afi8v39DAJNSErjVi5QS1eHgvStXzJMstZa2A2ZI0zRO/+0UDoeDyckprt3oXndon/f388XgIwB6em5adjls
C0wIwdDQEJPhEAC3ensZGR1dN3uklNy42QPAluIibvf2mnamhXLdFsDSw0p6AwghuHr5EqqqIqXk/Q8+IroOHelEIsGFi5cJhUIoisK/zp1lcnLSKnHa3CEx
/Q9bTTAQQjA4OMi1Tz4GYHR0lEuXr6zp+KKUktt9dwgODAAwNRmi7/btDBvTT7JNDcxK2dmiEILumzcZGxtBURQefTnE+QsXM+Ymr5aklFy/2c1/r98AIDoz
zT9OnzbtstKmB5ZvIrixaJrG30+dYvTJE4QQfDE4yMUrV5mcnFq1RGQ2FuOTa9fp7gkgpUTXNc6e+afZJ7TyLiBhi/lhVjNW0su6rpvlkyffojD1mLTL5eL4
j3+Er6xsxR6DS45fRjlz7jwTqWExqev84fe/AzJBGffEhBAEAgEnoNkSmLG2WpxOJ0eOHmVvfT3xeLLTWr1zJx1trVRUlH8tcFORCN3dAe4/eGDemBwfG+HC
+fOEQqEFXpXuXYFAQAWkbabMLgealJKDB19gX3MLztQcZ2PqbN2e3VSU+/F6vUuCF41GGZ+YIBgc4O7/7pn3uaSUDD96xNmzZ8w5znlgOQENbDQpPdc02XzQ
VFXlzd+epLikNOMtAkIIvIWF1NbWUFVZid/nw+12oSgKsViMUCjM0Fdf0d8fZHxiYsGxHULw9tt/ZDo1Im9mgIqSUQYIBAIuwHymwVavfcjlZcY611JZVUVD
YyMtLW1P3U/zuF0Eg0F6bwXof/AAXddzepRRTsHSmH83lW67F6ssB1p2HcD+AwepqanB5fZQXFxMQUEBeto+SS9JPpMxHYkQmYoQDod4/72rxGIxy058Hlh6
aoEkNJk3CD+DllmXvp+iKCgOhxmiktWZb7fRdd0cbc8Gkl5eimcZv2nLl4Plup4Z5VzelW/ucbasRlmWAs0CFiwHmKHNBm4xaMY6F6xc38/3/igrUEY5EAh4
mA+BGWEw47eW8R83o7JHetS0escia4X59st8Fi2z0TUyQegksz7Di7TUAnk8y9D/AXibpKAxdRNMAAAAAElFTkSuQmCC
]==],
}

local A = {}

local function LoadAssets()
	if not (ENV.writefile and ENV.isfolder and ENV.makefolder and ENV.getcustomasset) then return end
	pcall(function()
		if not ENV.isfolder(ROOT) then ENV.makefolder(ROOT) end
		if not ENV.isfolder(ASSET_DIR) then ENV.makefolder(ASSET_DIR) end
	end)
	local paths = {}
	for name, data in pairs(ASSET_B64) do
		local path = ASSET_DIR .. "/" .. name .. ".png"
		if pcall(ENV.writefile, path, B64.decode(data)) then paths[name] = path end
	end
	task.wait(0.1)
	for name, path in pairs(paths) do
		local ok, url = pcall(ENV.getcustomasset, path)
		if ok and type(url) == "string" and url ~= "" then A[name] = url end
	end
end
LoadAssets()

local UI = { Flags = {} }
local C = {
	Body = Color3.fromRGB(178, 178, 178),
	Bar = Color3.fromRGB(115, 115, 115),
	White = Color3.fromRGB(255, 255, 255),
	Track = Color3.fromRGB(51, 51, 51),
	Black = Color3.fromRGB(0, 0, 0),
	Thumb = Color3.fromRGB(150, 150, 150),
}
local FONT = Enum.Font.SourceSansBold
local WIN_W, WIN_H, BAR_H, FOOT_H = 560, 260, 42, 22
local SCROLL_IMG = "rbxassetid://7445543667"

local function New(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			o[k] = v
		end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function Corner(r)
	return New("UICorner", { CornerRadius = UDim.new(0, r) })
end

local function Label(props)
	local p = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextSize = 17,
		TextColor3 = C.White,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeColor3 = Color3.fromRGB(80, 80, 80),
		TextStrokeTransparency = 0.85,
		Text = "",
	}
	for k, v in pairs(props) do p[k] = v end
	return New("TextLabel", p)
end

local function IsPointerBegin(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
end

local function IsPointerMove(input)
	local t = input.UserInputType
	return t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.Touch
end

local Gui = New("ScreenGui", {
	Name = "COKSL_Optimizer",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 2147483647,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
ProtectGui(Gui)

local function MakeDraggable(handle, target, onClick)
	local dragging, moved, startPos, startUDim, startInput = false, false, nil, nil, nil
	Connect(handle.InputBegan, function(input)
		if IsPointerBegin(input) then
			dragging, moved = true, false
			startPos, startUDim, startInput = input.Position, target.Position, input
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if not dragging or not IsPointerMove(input) then return end
		if startInput.UserInputType == Enum.UserInputType.Touch and input ~= startInput then return end
		local delta = input.Position - startPos
		if delta.Magnitude > 6 then moved = true end
		if moved then
			local vp = Gui.AbsoluteSize
			if vp.X > 0 and vp.Y > 0 then
				target.Position = UDim2.new(
					math.clamp(startUDim.X.Scale + delta.X / vp.X, 0.02, 0.98), 0,
					math.clamp(startUDim.Y.Scale + delta.Y / vp.Y, 0.03, 0.97), 0
				)
			end
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if not dragging then return end
		local isTouch = startInput.UserInputType == Enum.UserInputType.Touch
		local matches = isTouch and input == startInput or (not isTouch and input.UserInputType == Enum.UserInputType.MouseButton1)
		if matches then
			dragging = false
			if not moved and onClick then onClick() end
		end
	end)
end

local function MakeSwitch(parent, position)
	if A.sliderOff and A.sliderOn then
		local off = New("ImageLabel", {
			BackgroundTransparency = 1, Image = A.sliderOff, Size = UDim2.fromOffset(46, 21),
			Position = position, AnchorPoint = Vector2.new(0, 0.5), Parent = parent,
		})
		local on = New("ImageLabel", {
			BackgroundTransparency = 1, Image = A.sliderOn, Size = UDim2.fromOffset(46, 21),
			Position = position, AnchorPoint = Vector2.new(0, 0.5), Visible = false, Parent = parent,
		})
		return function(state)
			off.Visible = not state
			on.Visible = state
		end
	end
	local track = New("Frame", {
		BackgroundColor3 = C.Track, BorderSizePixel = 0, Size = UDim2.fromOffset(46, 21),
		Position = position, AnchorPoint = Vector2.new(0, 0.5), Parent = parent,
	}, { Corner(8) })
	local knob = New("Frame", {
		BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.fromOffset(17, 17),
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Parent = track,
	}, { Corner(9) })
	return function(state)
		knob.Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	end
end

local function NewPage(parent)
	local holder = New("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = parent,
	})
	New("Frame", {
		BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.new(0, 8, 1, -16),
		Position = UDim2.new(1, -18, 0, 8), Parent = holder,
	}, { Corner(4) })
	local scroll = New("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, -10, 1, -16), Position = UDim2.new(0, 0, 0, 8),
		ScrollBarThickness = 8, ScrollBarImageColor3 = C.Thumb, ScrollBarImageTransparency = 0,
		TopImage = SCROLL_IMG, MidImage = SCROLL_IMG, BottomImage = SCROLL_IMG,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = holder,
	}, {
		New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }),
		New("UIPadding", {
			PaddingLeft = UDim.new(0, 30), PaddingRight = UDim.new(0, 14),
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10),
		}),
	})

	local page = { holder = holder, scroll = scroll, order = 0 }

	local function nextOrder()
		page.order += 1
		return page.order
	end

	function page.Section(text)
		local row = New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = scroll,
		})
		Label({
			Text = string.upper(text), TextSize = 18, Position = UDim2.new(0, 0, 0, 4),
			Size = UDim2.new(1, 0, 0, 20), Parent = row,
		})
		New("Frame", {
			BackgroundColor3 = C.White, BackgroundTransparency = 0.6, BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 1), Parent = row,
		})
	end

	function page.Toggle(cfg)
		local row = New("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nextOrder(), Parent = scroll,
		})
		Label({
			Text = cfg.Name, Size = UDim2.new(0, 222, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})
		local setSwitch = MakeSwitch(row, UDim2.new(0, 232, 0.5, 0))
		if cfg.Hint then
			Label({
				Text = "≈ " .. cfg.Hint, TextSize = 12, TextTransparency = 0.2,
				Position = UDim2.new(0, 290, 0, 0), Size = UDim2.new(1, -290, 1, 0),
				TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
			})
		end
		local flag = { Type = "Toggle", Value = false, Save = true }
		function flag.Set(v, silent)
			v = v and true or false
			local changed = v ~= flag.Value
			flag.Value = v
			if cfg.Key then S[cfg.Key] = v end
			setSwitch(v)
			if changed and not silent and cfg.Callback then task.spawn(cfg.Callback, v) end
		end
		Connect(row.Activated, function() flag.Set(not flag.Value) end)
		if cfg.Key then flag.Value = S[cfg.Key] and true or false end
		setSwitch(flag.Value)
		if cfg.Flag then UI.Flags[cfg.Flag] = flag end
		return flag
	end

	function page.Slider(cfg)
		local TRACK_X, TRACK_W = 232, 150
		local row = New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Parent = scroll,
		})
		Label({
			Text = cfg.Name, Size = UDim2.new(0, 222, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})
		local track = New("Frame", {
			BackgroundColor3 = C.Track, BorderSizePixel = 0, Size = UDim2.new(0, TRACK_W, 0, 6),
			Position = UDim2.new(0, TRACK_X, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), Parent = row,
		}, { Corner(3) })
		local fill = New("Frame", {
			BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0), Parent = track,
		}, { Corner(3) })
		local knob = New("Frame", {
			BackgroundColor3 = C.White, BorderSizePixel = 0, Size = UDim2.fromOffset(15, 15),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Parent = track,
		}, { Corner(8), New("UIStroke", { Color = C.Track, Thickness = 2 }) })
		local valueLabel = Label({
			TextSize = 15, Position = UDim2.new(0, TRACK_X + TRACK_W + 14, 0, 0),
			Size = UDim2.new(1, -(TRACK_X + TRACK_W + 14), 1, 0), Parent = row,
		})
		local hit = New("TextButton", {
			Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
			Position = UDim2.new(0, TRACK_X - 10, 0, 0), Size = UDim2.new(0, TRACK_W + 20, 1, 0), Parent = row,
		})

		local flag = { Type = "Slider", Value = nil, Save = true }
		local step = cfg.Step or 1

		local function render(v)
			local r = (v - cfg.Min) / (cfg.Max - cfg.Min)
			fill.Size = UDim2.new(r, 0, 1, 0)
			knob.Position = UDim2.new(r, 0, 0.5, 0)
			valueLabel.Text = cfg.Format and cfg.Format(v) or (tostring(v) .. (cfg.Suffix or ""))
		end

		function flag.Set(v, silent)
			v = tonumber(v) or cfg.Default
			v = math.clamp(math.floor((v - cfg.Min) / step + 0.5) * step + cfg.Min, cfg.Min, cfg.Max)
			local changed = v ~= flag.Value
			flag.Value = v
			if cfg.Key then S[cfg.Key] = v end
			render(v)
			if changed and not silent and cfg.Callback then task.spawn(cfg.Callback, v) end
		end

		local dragging, activeInput = false, nil
		local function fromX(x)
			local r = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
			flag.Set(cfg.Min + (cfg.Max - cfg.Min) * r)
		end
		Connect(hit.InputBegan, function(input)
			if IsPointerBegin(input) then
				dragging, activeInput = true, input
				scroll.ScrollingEnabled = false
				fromX(input.Position.X)
			end
		end)
		Connect(UserInputService.InputChanged, function(input)
			if dragging and IsPointerMove(input) then
				if input.UserInputType == Enum.UserInputType.Touch and input ~= activeInput then return end
				fromX(input.Position.X)
			end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if dragging and (input == activeInput or input.UserInputType == Enum.UserInputType.MouseButton1) then
				dragging = false
				scroll.ScrollingEnabled = true
			end
		end)

		flag.Set(S[cfg.Key] or cfg.Default, true)
		if cfg.Flag then UI.Flags[cfg.Flag] = flag end
		return flag
	end

	function page.Button(cfg)
		local row = New("Frame", {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(), Parent = scroll,
		})
		Label({
			Text = cfg.Name, Size = UDim2.new(0, 222, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd, Parent = row,
		})
		local btn = New("TextButton", {
			Text = cfg.Text or "RUN", Font = FONT, TextSize = 16, TextColor3 = C.White,
			BackgroundColor3 = C.Black, BorderSizePixel = 0, AutoButtonColor = true,
			Size = UDim2.fromOffset(96, 24), Position = UDim2.new(0, 232, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5), Parent = row,
		}, { Corner(10) })
		Connect(btn.Activated, function() task.spawn(cfg.Callback) end)
	end

	return page
end

local Main = New("Frame", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	BackgroundColor3 = C.Body,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Visible = false,
	Parent = Gui,
}, { Corner(12), New("UIScale", { Name = "Scale" }) })

local function fitWindow()
	local vp = Gui.AbsoluteSize
	if vp.X > 0 and vp.Y > 0 then
		Main.Scale.Scale = math.clamp(math.min((vp.X - 24) / WIN_W, (vp.Y - 24) / WIN_H), 0.45, 1)
	end
end
fitWindow()
Connect(Gui:GetPropertyChangedSignal("AbsoluteSize"), fitWindow)

local Bar = New("Frame", {
	BackgroundColor3 = C.Bar, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, BAR_H), Parent = Main,
}, { Corner(12) })
New("Frame", {
	BackgroundColor3 = C.Bar, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 12),
	Position = UDim2.new(0, 0, 1, -12), Parent = Bar,
})

local TabsHolder = New("Frame", {
	BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -70, 1, 0), Parent = Bar,
}, {
	New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 18),
	}),
})

local Content = New("Frame", {
	BackgroundTransparency = 1, Position = UDim2.new(0, 0, 0, BAR_H), Size = UDim2.new(1, 0, 1, -(BAR_H + FOOT_H)), Parent = Main,
})

Label({
	Text = "by @nueki12kk (Discord) :)", TextSize = 13, TextTransparency = 0.1,
	TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 1, -FOOT_H),
	Size = UDim2.new(1, 0, 0, FOOT_H), Parent = Main,
})
New("Frame", {
	BackgroundColor3 = C.White, BackgroundTransparency = 0.6, BorderSizePixel = 0,
	Position = UDim2.new(0, 14, 1, -FOOT_H), Size = UDim2.new(1, -28, 0, 1), Parent = Main,
})

local TabList = {}

local function selectTab(name)
	for _, t in ipairs(TabList) do
		local active = t.name == name
		t.frame.Visible = active
		t.text.TextSize = active and 21 or 15
		t.text.TextTransparency = active and 0 or 0.12
		if t.icon then
			local s = active and 27 or 20
			t.icon.Size = UDim2.fromOffset(s, s)
		end
	end
end

local function MakeTab(name, iconUrl, order, frame)
	local btn = New("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), LayoutOrder = order, Parent = TabsHolder,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	})
	local icon
	if iconUrl then
		icon = New("ImageLabel", {
			BackgroundTransparency = 1, Image = iconUrl, Size = UDim2.fromOffset(20, 20), LayoutOrder = 1, Parent = btn,
		})
	end
	local text = Label({
		Text = name, TextSize = 15, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0), LayoutOrder = 2, Parent = btn,
	})
	TabList[#TabList + 1] = { name = name, frame = frame, text = text, icon = icon }
	Connect(btn.Activated, function() selectTab(name) end)
end

local ProfilesFrame = New("Frame", {
	BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, Parent = Content,
})
local ConfigPage = NewPage(Content)

MakeTab("PROFILES", A.profiles, 1, ProfilesFrame)
MakeTab("CONFIGS", A.cog, 2, ConfigPage.holder)

if A.quit then
	local closeBtn = New("ImageButton", {
		BackgroundTransparency = 1, Image = A.quit, Size = UDim2.fromOffset(28, 28),
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Parent = Bar,
	})
	Connect(closeBtn.Activated, function() Main.Visible = false end)
else
	local closeBtn = New("TextButton", {
		Text = "X", Font = FONT, TextSize = 20, TextColor3 = C.White, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(28, 28), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0), Parent = Bar,
	})
	Connect(closeBtn.Activated, function() Main.Visible = false end)
end

MakeDraggable(Bar, Main)

local NotifyHolder = New("Frame", {
	BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -14, 1, -14), Size = UDim2.new(0, 270, 1, -28), Parent = Gui,
}, {
	New("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		Padding = UDim.new(0, 6),
	}),
})

Notify = function(title, text, duration)
	task.spawn(function()
		local card = New("Frame", {
			BackgroundColor3 = C.Bar, BorderSizePixel = 0, AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0), Parent = NotifyHolder,
		}, {
			Corner(10),
			New("UIStroke", { Color = C.White, Transparency = 0.7, Thickness = 1 }),
			New("UIPadding", {
				PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			}),
			New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		})
		Label({ Text = title, TextSize = 17, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, Parent = card })
		Label({
			Text = text, TextSize = 14, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 2, Parent = card,
		})
		task.wait(duration or 4)
		card:Destroy()
	end)
end

local FloatBtn
if A.logo then
	FloatBtn = New("ImageButton", {
		Name = "COKSL_Button", BackgroundColor3 = C.Black, Image = A.logo, AutoButtonColor = false,
		Size = UDim2.fromOffset(46, 46), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.04, 0.5), Parent = Gui,
	}, { Corner(23) })
else
	FloatBtn = New("TextButton", {
		Name = "COKSL_Button", BackgroundColor3 = C.Black, Text = "C", Font = FONT, TextSize = 24,
		TextColor3 = C.White, AutoButtonColor = false, Size = UDim2.fromOffset(46, 46),
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.04, 0.5), Parent = Gui,
	}, { Corner(23) })
end
MakeDraggable(FloatBtn, FloatBtn, function() Main.Visible = not Main.Visible end)

Connect(UserInputService.InputBegan, function(input)
	if input.KeyCode == Enum.KeyCode.RightShift then Main.Visible = not Main.Visible end
end)

local HUD = NewFeature("FpsCounter", {})
local HudFrame = New("Frame", {
	Name = "COKSL_FpsCounter", BackgroundColor3 = C.Black, BackgroundTransparency = 0.3, BorderSizePixel = 0,
	Active = true, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.06),
	Size = UDim2.fromOffset(104, 30), Visible = false, Parent = Gui,
}, { Corner(8), New("UIStroke", { Color = C.White, Transparency = 0.7, Thickness = 1 }) })
local HudText = Label({
	Text = "XXXX FPS", TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1), Parent = HudFrame,
})
MakeDraggable(HudFrame, HudFrame)

function HUD.enable(f)
	HudFrame.Visible = true
	local gen = f.gen
	task.spawn(function()
		local frames, t0 = 0, os.clock()
		local conn = RunService.Heartbeat:Connect(function() frames += 1 end)
		while HUD.enabled and HUD.gen == gen do
			task.wait(0.5)
			local now = os.clock()
			HudText.Text = string.format("%d FPS", math.floor(frames / math.max(now - t0, 0.05) + 0.5))
			frames, t0 = 0, now
		end
		conn:Disconnect()
	end)
end

function HUD.disable()
	HudFrame.Visible = false
end

local function featureToggle(name, key, feature, hint)
	return ConfigPage.Toggle({
		Name = name, Flag = key, Hint = hint,
		Callback = function(v) FeatureSet(feature, v) end,
	})
end

ConfigPage.Section("Low-Poly Map Generator")
featureToggle("Low-Poly Map Generator", "LowPoly", Features.LowPoly, "flat map, cheap meshes")
ConfigPage.Slider({
	Name = "Low-Poly Level", Flag = "LowPolyLevel", Key = "LowPolyLevel", Min = 1, Max = 3, Step = 1, Default = 2,
	Format = function(v) return ({ "1 • Soft", "2 • Flat", "3 • Blocky" })[v] end,
	Callback = function() Features.LowPoly.refresh() end,
})

ConfigPage.Section("Black Screen Mode")
featureToggle("Black Screen Mode", "BlackScreen", Features.BlackScreen, "3D off + low FPS")
ConfigPage.Slider({
	Name = "Black Screen FPS", Flag = "BlackScreenFps", Key = "BlackScreenFps", Min = 5, Max = 60, Step = 5, Default = 15,
	Suffix = " FPS", Callback = function() Features.BlackScreen.refresh() end,
})

ConfigPage.Section("Dynamic Particle Anti-Lag")
featureToggle("Dynamic Particle Anti-Lag", "Particles", Features.Particles, "throttles by FPS + distance")
ConfigPage.Slider({
	Name = "Particle FPS Target", Flag = "ParticleFps", Key = "ParticleFps", Min = 20, Max = 144, Step = 2, Default = 50,
	Suffix = " FPS",
})
ConfigPage.Slider({
	Name = "Particle Distance", Flag = "ParticleDistance", Key = "ParticleDistance", Min = 50, Max = 1000, Step = 10,
	Default = 250, Suffix = " studs",
})

ConfigPage.Section("Auto Garbage Collector")
featureToggle("Auto Garbage Collector", "GC", Features.GC, "timer + memory limit")
ConfigPage.Slider({
	Name = "GC Interval", Flag = "GCInterval", Key = "GCInterval", Min = 15, Max = 600, Step = 15, Default = 60, Suffix = " s",
})
ConfigPage.Slider({
	Name = "GC Memory Limit", Flag = "GCThreshold", Key = "GCThreshold", Min = 500, Max = 8000, Step = 100,
	Default = 2000, Suffix = " MB",
})
ConfigPage.Button({ Name = "Collect Garbage Now", Text = "RUN", Callback = function() CollectNow(false) end })

ConfigPage.Section("Distance Render Optimizer")
featureToggle("Distance Render Optimizer", "Distance", Features.Distance, "hides far parts (client only)")
ConfigPage.Slider({
	Name = "Render Distance", Flag = "RenderDistance", Key = "RenderDistance", Min = 100, Max = 2000, Step = 50,
	Default = 500, Suffix = " studs",
})
ConfigPage.Toggle({ Name = "Adaptive Distance", Flag = "AdaptiveDistance", Key = "AdaptiveDistance", Hint = "shrinks when FPS drops" })
ConfigPage.Toggle({ Name = "Fog Pop-in Mask", Flag = "FogMask", Key = "FogMask", Hint = "fog hides the cut-off edge" })

ConfigPage.Section("Dynamic FPS Unlocker")
featureToggle("Dynamic FPS Unlocker", "FpsUnlocker", Features.FpsUnlocker, "DFIntTaskSchedulerTargetFps")
ConfigPage.Slider({
	Name = "Max FPS", Flag = "MaxFps", Key = "MaxFps", Min = 30, Max = 1000, Step = 10, Default = 240,
	Format = function(v) return v >= 1000 and "Unlimited" or (tostring(v) .. " FPS") end,
	Callback = function() Features.FpsUnlocker.refresh() end,
})
ConfigPage.Slider({
	Name = "Idle FPS", Flag = "IdleFps", Key = "IdleFps", Min = 10, Max = 60, Step = 5, Default = 30, Suffix = " FPS",
})
ConfigPage.Slider({
	Name = "Idle After", Flag = "IdleSeconds", Key = "IdleSeconds", Min = 10, Max = 300, Step = 5, Default = 45, Suffix = " s",
})

ConfigPage.Section("FPS Counter")
featureToggle("FPS Counter", "FpsCounter", Features.FpsCounter, "draggable HUD, e.g. 144 FPS")

ConfigPage.Section("Quick Optimizer")
featureToggle("Graphics", "QuickGraphics", Features.QuickGraphics, "quality, mesh detail, interpolation")
featureToggle("Lighting", "QuickLighting", Features.QuickLighting, "shadows, fog, atmosphere, effects")
featureToggle("Texture", "QuickTexture", Features.QuickTexture, "materials, decals, sky")
featureToggle("Terrain", "QuickTerrain", Features.QuickTerrain, "water waves, grass")
featureToggle("Effects", "QuickEffects", Features.QuickEffects, "particles, smoke, fire, trails")
featureToggle("Remove Fog", "NoFog", Features.NoFog, "FogEnd = unlimited")

ConfigPage.Section("FFlags")
local ffList = {
	{ "FF_QualityLock", "Graphics Quality Lock", "FixGraphicsQuality" },
	{ "FF_TextureReduction", "Texture Reduction", "GraphicsTextureReduction" },
	{ "FF_Instancing", "Global Instancing", "RenderEnableGlobalInstancing3" },
	{ "FF_LightCulling", "Light Culling", "FastGPULightCulling3" },
	{ "FF_PostFx", "Post-Processing Off", "SSAOMipLevels" },
	{ "FF_SkyClouds", "Sky & Cloud Reduction", "CloudsMvpForceNoHistory" },
	{ "FF_Terrain", "Terrain Simplifier", "SmoothTerrainPhysicsCache" },
	{ "FF_Audio", "Audio Optimizer", "AudioUseVolumetricPanning" },
	{ "FF_Humanoid", "Humanoid Optimizer", "HumanoidParallel*" },
	{ "FF_Physics", "Physics Throttle", "SimIfNoInterp2" },
	{ "FF_Ads", "Ads Blocker", "AdGuiEnabled3" },
	{ "FF_Background", "Background Throttle", "SkipRenderIfDataModelBusy" },
	{ "FF_Cullable", "Cullable Scene", "EnableCullableScene2" },
	{ "FF_CompatLighting", "Compatibility Lighting", "DebugForceFSMCPULightCulling" },
	{ "FF_MeshDetail", "Mesh Detail Reduction", "DefaultMeshCacheSizeMB" },
}
for _, e in ipairs(ffList) do
	featureToggle(e[2], e[1], FF[e[1]], e[3])
end

local Profiles = { mem = {} }

local function sanitize(name)
	local clean = string.gsub(tostring(name or ""), "[^%w_%-]", "_")
	return string.sub(clean, 1, 24)
end

local function ensureDirs()
	if not ENV.fs then return false end
	return (pcall(function()
		if not ENV.isfolder(ROOT) then ENV.makefolder(ROOT) end
		if not ENV.isfolder(PROF_DIR) then ENV.makefolder(PROF_DIR) end
	end))
end

function Profiles.Save(name)
	local flags = {}
	for key, fl in pairs(UI.Flags) do
		if fl.Save then flags[key] = fl.Value end
	end
	local ok, data = pcall(function() return HttpService:JSONEncode({ v = 1, flags = flags }) end)
	if not ok then return false end
	if ensureDirs() then
		return (pcall(ENV.writefile, PROF_DIR .. "/" .. name .. ".json", data))
	end
	Profiles.mem[name] = data
	return true
end

function Profiles.List()
	local names = {}
	if ENV.fs and ensureDirs() then
		local ok, files = pcall(ENV.listfiles, PROF_DIR)
		if ok and type(files) == "table" then
			for _, path in ipairs(files) do
				local n = string.match(path, "([^/\\]+)%.json$")
				if n then names[#names + 1] = n end
			end
		end
	else
		for n in pairs(Profiles.mem) do names[#names + 1] = n end
	end
	table.sort(names)
	return names
end

function Profiles.Load(name)
	local raw
	if ENV.fs and ensureDirs() then
		local path = PROF_DIR .. "/" .. name .. ".json"
		local okExists, exists = pcall(ENV.isfile, path)
		if okExists and exists then
			local okRead, txt = pcall(ENV.readfile, path)
			if okRead then raw = txt end
		end
	else
		raw = Profiles.mem[name]
	end
	if not raw then return false end
	local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(data) ~= "table" or type(data.flags) ~= "table" then return false end
	local levelBefore = S.LowPolyLevel
	for key, value in pairs(data.flags) do
		local fl = UI.Flags[key]
		if fl and fl.Type == "Slider" then fl.Set(value, true) end
	end
	for key, value in pairs(data.flags) do
		local fl = UI.Flags[key]
		if fl and fl.Type == "Toggle" then fl.Set(value) end
	end
	if S.LowPolyLevel ~= levelBefore then Features.LowPoly.refresh() end
	Features.BlackScreen.refresh()
	Features.FpsUnlocker.refresh()
	return true
end

function Profiles.Delete(name)
	if ENV.fs and ENV.delfile and ensureDirs() then
		pcall(ENV.delfile, PROF_DIR .. "/" .. name .. ".json")
	end
	Profiles.mem[name] = nil
end

local function BlackButton(text, size, pos, textSize)
	return New("TextButton", {
		Text = text, Font = FONT, TextSize = textSize, TextColor3 = C.White, BackgroundColor3 = C.Black,
		BorderSizePixel = 0, AutoButtonColor = true, Size = size, Position = pos, Parent = ProfilesFrame,
	}, { Corner(10) })
end

Label({
	Text = "CONFIGS", TextSize = 22, Position = UDim2.new(0, 22, 0, 8), Size = UDim2.new(0, 200, 0, 28), Parent = ProfilesFrame,
})
local nameBox = New("TextBox", {
	Text = "", PlaceholderText = "profile name", PlaceholderColor3 = Color3.fromRGB(150, 150, 150),
	ClearTextOnFocus = false, Font = FONT, TextSize = 16, TextColor3 = C.White, TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundColor3 = C.Black, BorderSizePixel = 0, Position = UDim2.new(0, 20, 0, 46),
	Size = UDim2.fromOffset(215, 28), Parent = ProfilesFrame,
}, {
	Corner(10),
	New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
})
local createBtn = BlackButton("CREATE", UDim2.fromOffset(86, 28), UDim2.new(0, 248, 0, 46), 16)
local listBtn = BlackButton("LIST\nV", UDim2.fromOffset(46, 46), UDim2.new(0, 20, 0, 84), 15)
local loadBtn = BlackButton("LOAD", UDim2.fromOffset(86, 38), UDim2.new(0, 78, 0, 88), 22)
local deleteBtn = BlackButton("DELETE", UDim2.fromOffset(72, 26), UDim2.new(0, 176, 0, 94), 14)
local selectedLabel = Label({
	Text = "Selected: none", TextSize = 16, Position = UDim2.new(0, 262, 0, 90),
	Size = UDim2.new(0, 270, 0, 34), Parent = ProfilesFrame,
})
Label({
	Text = ENV.fs and ("Saved in: " .. PROF_DIR .. "  (name it default to auto-load)") or "This executor has no file API: profiles live only until you leave the game.",
	TextSize = 13, TextTransparency = 0.25, TextWrapped = true, Position = UDim2.new(0, 22, 1, -40),
	Size = UDim2.new(1, -60, 0, 32), TextYAlignment = Enum.TextYAlignment.Bottom, Parent = ProfilesFrame,
})

local dropdown = New("ScrollingFrame", {
	BackgroundColor3 = C.Black, BorderSizePixel = 0, Visible = false, Position = UDim2.new(0, 20, 0, 134),
	Size = UDim2.fromOffset(200, 26), ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(), ZIndex = 5, Parent = ProfilesFrame,
}, { Corner(8), New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

local selectedProfile

local function refreshList()
	for _, ch in ipairs(dropdown:GetChildren()) do
		if ch:IsA("TextButton") then ch:Destroy() end
	end
	local names = Profiles.List()
	for i, n in ipairs(names) do
		local b = New("TextButton", {
			Text = n, Font = FONT, TextSize = 16, TextColor3 = C.White, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, ZIndex = 6, Parent = dropdown,
		})
		b.Activated:Connect(function()
			selectedProfile = n
			selectedLabel.Text = "Selected: " .. n
			dropdown.Visible = false
		end)
	end
	dropdown.Size = UDim2.fromOffset(200, math.clamp(#names, 1, 3) * 26)
	return names
end

Connect(listBtn.Activated, function()
	if dropdown.Visible then
		dropdown.Visible = false
	else
		local names = refreshList()
		if #names == 0 then
			Notify("Profiles", "No profiles yet. Type a name and press CREATE.", 4)
		else
			dropdown.Visible = true
		end
	end
end)

Connect(createBtn.Activated, function()
	local name = sanitize(nameBox.Text)
	if name == "" then
		Notify("Profiles", "Type a profile name first.", 3)
		return
	end
	if Profiles.Save(name) then
		selectedProfile = name
		selectedLabel.Text = "Selected: " .. name
		nameBox.Text = ""
		refreshList()
		Notify("Profiles", "Saved '" .. name .. "'.", 3)
	else
		Notify("Profiles", "Could not save the profile.", 4)
	end
end)

Connect(loadBtn.Activated, function()
	if not selectedProfile then
		Notify("Profiles", "Pick a profile with LIST first.", 3)
		return
	end
	if Profiles.Load(selectedProfile) then
		Notify("Profiles", "Loaded '" .. selectedProfile .. "'.", 3)
	else
		Notify("Profiles", "Could not load '" .. selectedProfile .. "'.", 4)
	end
end)

Connect(deleteBtn.Activated, function()
	if not selectedProfile then return end
	Profiles.Delete(selectedProfile)
	Notify("Profiles", "Deleted '" .. selectedProfile .. "'.", 3)
	selectedProfile = nil
	selectedLabel.Text = "Selected: none"
	refreshList()
end)

local function Destroy()
	for _, f in pairs(Features) do
		f.enabled = false
		f.gen += 1
	end
	RebuildApply()
	for _, f in pairs(Features) do
		if f.applied then
			f.applied = false
			if f.disable then pcall(f.disable, f) end
		end
	end
	local owners = {}
	for name in pairs(Owned) do owners[#owners + 1] = name end
	task.spawn(function()
		for _, name in ipairs(owners) do Mod.Release(name) end
	end)
	Render.off = {}
	pcall(function() RunService:Set3dRenderingEnabled(true) end)
	FPS.requests = {}
	FPS.Update()
	for _, c in ipairs(Conns) do pcall(c.Disconnect, c) end
	if BSGui then pcall(function() BSGui:Destroy() end) end
	if ProxyFolder then pcall(function() ProxyFolder:Destroy() end) end
	pcall(function() Gui:Destroy() end)
	genv.COKSL_OPTIMIZER = nil
end

ConfigPage.Section("Script")
ConfigPage.Button({ Name = "Unload & Restore All", Text = "UNLOAD", Callback = Destroy })

genv.COKSL_OPTIMIZER = { Destroy = Destroy, Settings = S, Features = Features, Profiles = Profiles }

selectTab("CONFIGS")
Main.Visible = true

task.spawn(function()
	local ok, names = pcall(Profiles.List)
	if ok and table.find(names, "default") then
		Profiles.Load("default")
		Notify("COKSL Hub", "Profile 'default' loaded.", 3)
	else
		Notify("COKSL Hub", "Loaded. Tap the round button to open/close the menu.", 4)
	end
end)
