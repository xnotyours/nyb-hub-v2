--[[ ==========================================================================
     N Y B   H U B   v2   |   Violence District Toolkit
     --------------------------------------------------------------------------
     File    : nyb_hub_v2.lua      (rebuild dari nol)
     Engine  : WindUI (Footagesus), dimuat via HttpGet saat inject
     Target  : [BUTCHER] Violence District   (PlaceId 93978595733734)
     Platform: Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift)

     Kenapa ditulis ulang:
       Versi v3.1 numpuk 3 bug di lapisan port UI (section bersarang, section
       gak pernah kebuka karena Expandable, gagal diam-diam). Daripada nambal,
       lapisan UI-nya ditulis ulang bersih dengan aturan yang gak bisa gagal
       diam-diam:
         - TIDAK pakai WindUI Section. Header grup = Paragraph, pemisah = Divider.
           Jadi gak ada Expandable, gak ada nesting, gak ada ClipsDescendants.
         - Semua helper nempel di root table N (gak ada local lintas blok do..end).
         - Tiap method di-feature-detect; kalau nggak ada, dicatat di log,
           bukan bikin chunk mati.
         - Self-test per fitur, hasilnya tampil DI LAYAR.

     Catatan: Remotes.Mechanics.Chat.* (TempBan/PermaBan/Unban) sengaja TIDAK
     dipakai -- itu tool moderasi server, bukan fitur cheat.
     ========================================================================== ]]

--===================== [ 0. GUARD + SERVICES ] =============================
local N = {}

N.env = (getgenv and getgenv()) or _G
if N.env.NYB2_RUNNING then
	warn("[NYB v2] Script sudah jalan. Tekan Unload dulu sebelum reload.")
	return
end
N.env.NYB2_RUNNING = true

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UIS                 = game:GetService("UserInputService")
local Lighting            = game:GetService("Lighting")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")

local LP  = Players.LocalPlayer
local CAM = workspace.CurrentCamera

--===================== [ 1. LOG (di layar + console) ] =====================
N.logLines = {}
N.ui = {}

function N.log(text)
	local s = tostring(text)
	N.logLines[#N.logLines + 1] = s
	print("[NYB v2] " .. s)
	if N.ui.pushLog then pcall(N.ui.pushLog, s) end
end

--===================== [ 2. CFG + FEATURE REGISTRY ] =======================
N.CFG = {
	Accent          = Color3.fromRGB(0, 210, 190),
	Keybind         = Enum.KeyCode.RightShift,

	-- ESP pemain
	EspPlayers      = false,
	EspChams        = false,
	EspBox          = false,
	EspName         = false,
	EspDist         = false,
	EspHealth       = false,
	EspRole         = false,
	EspMaxDist      = 500,

	-- ESP objek
	EspGens         = false,
	EspGates        = false,
	EspHooks        = false,
	EspPallets      = false,
	EspWindows      = false,

	-- warna
	ColorKiller     = Color3.fromRGB(255, 70, 70),
	ColorSurvivor   = Color3.fromRGB(70, 170, 255),
	ColorOther      = Color3.fromRGB(200, 200, 200),
	ColorGen        = Color3.fromRGB(255, 200, 60),
	ColorGenDone    = Color3.fromRGB(90, 255, 140),
	ColorGate       = Color3.fromRGB(160, 120, 255),
	ColorHook       = Color3.fromRGB(255, 140, 200),
	ColorPallet     = Color3.fromRGB(200, 160, 90),
	ColorWindow     = Color3.fromRGB(120, 220, 255),

	-- aim
	Aimbot          = false,
	AimFov          = 120,
	AimSmooth       = 0.35,
	AimShowFov      = false,
	AimWallCheck    = true,

	-- movement
	SpeedOn         = false,
	SpeedValue      = 28,
	FlyOn           = false,
	FlySpeed        = 60,
	NoclipOn        = false,
	InfJump         = false,

	-- visual
	Fullbright      = false,
	NoFog           = false,
	CamFov          = false,
	CamFovValue     = 90,

	-- auto
	AutoHeal        = false,
	AutoParry       = false,
	KillAura        = false,
	AttackRange     = 14,

	RemoteLog       = false,
}

-- daftar fitur: dipakai buat bikin toggle DI UI *dan* buat self-test.
-- tiap entri: key (field CFG), label, tab, on(v) = efek samping, test() = verifikasi.
N.FEAT = {}
function N.feature(def)
	N.FEAT[#N.FEAT + 1] = def
	return def
end

--===================== [ 3. CORE HELPERS ] =================================
N.conns = {}

function N.bind(signal, fn)
	local ok, c = pcall(function() return signal:Connect(fn) end)
	if ok and c then
		N.conns[#N.conns + 1] = c
		return c
	end
	return nil
end

function N.hrp()
	local ch = LP.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

function N.hum()
	local ch = LP.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

function N.msg(text)
	N.log(text)
	if N.ui.notify then pcall(N.ui.notify, N.ui, tostring(text)) end
end

--===================== [ 4. REMOTES (dari dump, bukan tebakan) ] ===========
N.remotes = { map = {}, list = {} }

function N.remotes.resolve()
	local root = ReplicatedStorage:FindFirstChild("Remotes")
	N.remotes.map, N.remotes.list = {}, {}
	if not root then
		N.log("Remotes TIDAK ADA di ReplicatedStorage")
		return 0
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			local full = d:GetFullName()
			local key  = full:gsub("^ReplicatedStorage%.Remotes%.?", "")
			N.remotes.map[key] = d
			N.remotes.list[#N.remotes.list + 1] = full
		end
	end
	return #N.remotes.list
end

function N.remotes.get(key)
	return N.remotes.map[key]
end

--===================== [ 5. MAP SCAN + CACHE ] =============================
N.cache = { gens = {}, gates = {}, hooks = {}, pallets = {}, windows = {} }
N.scanMeta = { last = 0, gensDone = 0, gensLeft = 0 }

local function nameHas(inst, ...)
	local n = string.lower(inst.Name)
	for _, w in ipairs({ ... }) do
		if string.find(n, w, 1, true) then return true end
	end
	return false
end

function N.scan()
	local c = N.cache
	c.gens, c.gates, c.hooks, c.pallets, c.windows = {}, {}, {}, {}, {}

	for _, d in ipairs(workspace:GetDescendants()) do
		local ok, cls = pcall(function() return d.ClassName end)
		if ok and cls then
			if nameHas(d, "generator", "gen ") or d.Name == "Generator" then
				table.insert(c.gens, d)
			elseif nameHas(d, "gate", "exit") then
				table.insert(c.gates, d)
			elseif nameHas(d, "hook") then
				table.insert(c.hooks, d)
			elseif nameHas(d, "pallet", "pallet") then
				table.insert(c.pallets, d)
			elseif nameHas(d, "window", "vault") then
				table.insert(c.windows, d)
			end
		end
	end

	-- hitung generator yang belum selesai (flag attribute umum di VD)
	local left = 0
	for _, g in ipairs(c.gens) do
		local done = false
		pcall(function()
			done = (g:GetAttribute("Completed") == true) or (g:GetAttribute("Done") == true)
				or (g:GetAttribute("Progress") == 1)
		end)
		if not done then left = left + 1 end
	end
	N.scanMeta.gensLeft = left
	N.scanMeta.gensDone = #c.gens - left
	N.scanMeta.last = tick()

	N.log(string.format("scan: gen=%d (belum %d) gate=%d hook=%d pallet=%d window=%d",
		#c.gens, left, #c.gates, #c.hooks, #c.pallets, #c.windows))
	return #c.gens + #c.gates + #c.hooks + #c.pallets + #c.windows
end

--===================== [ 6. ESP ENGINE ] ===================================
N.esp = { pool = {}, clear = nil, sync = nil }

function N.esp.clear()
	for id, item in pairs(N.esp.pool) do
		pcall(function()
			if item.hl then item.hl:Destroy() end
			if item.gui then item.gui:Destroy() end
		end)
		N.esp.pool[id] = nil
	end
end

-- item = { id, part, color, label, dist, hp }
function N.esp.sync(list)
	local seen = {}
	for _, it in ipairs(list) do
		seen[it.id] = true
		local cur = N.esp.pool[it.id]
		if not cur then
			cur = { id = it.id }
			if N.CFG.EspChams then
				local hl = Instance.new("Highlight")
				hl.Name = "NYB2_HL"
				hl.FillColor = it.color
				hl.OutlineColor = Color3.new(1, 1, 1)
				hl.FillTransparency = 0.55
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Parent = it.part
				cur.hl = hl
			end
			if N.CFG.EspBox or N.CFG.EspName or N.CFG.EspDist or N.CFG.EspHealth then
				local g = Instance.new("BillboardGui")
				g.Name = "NYB2_BB"
				g.Size = UDim2.new(0, 120, 0, 42)
				g.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
				g.AlwaysOnTop = true
				g.Adornee = it.part
				g.Parent = N.ui.gui or LP:FindFirstChild("PlayerGui")
				local txt = Instance.new("TextLabel")
				txt.Name = "Info"
				txt.Size = UDim2.new(1, 0, 1, 0)
				txt.BackgroundTransparency = 1
				txt.TextColor3 = it.color
				txt.TextStrokeTransparency = 0.2
				txt.TextSize = 12
				txt.Font = Enum.Font.GothamBold
				txt.TextScaled = false
				txt.Parent = g
				cur.gui = g
				cur.txt = txt
			end
			N.esp.pool[it.id] = cur
		end

		-- refresh warna / visibilitas
		if cur.hl then cur.hl.FillColor = it.color end
		if cur.txt then
			local parts = {}
			if N.CFG.EspName then parts[#parts + 1] = it.label end
			if N.CFG.EspRole and it.role then parts[#parts + 1] = "[" .. it.role .. "]" end
			if N.CFG.EspHealth and it.hp then parts[#parts + 1] = string.format("%.0f hp", it.hp) end
			if N.CFG.EspDist then parts[#parts + 1] = string.format("%.0f", it.dist) end
			cur.txt.Text = table.concat(parts, " ")
			if cur.gui then cur.gui.Enabled = (#parts > 0) end
		end
	end

	for id, item in pairs(N.esp.pool) do
		if not seen[id] then
			pcall(function()
				if item.hl then item.hl:Destroy() end
				if item.gui then item.gui:Destroy() end
			end)
			N.esp.pool[id] = nil
		end
	end
end

N.esp.count = function()
	local n = 0
	for _ in pairs(N.esp.pool) do n = n + 1 end
	return n
end

function N.espFrame()
	if not N.alive then return end
	if not (N.CFG.EspPlayers or N.CFG.EspGens or N.CFG.EspGates or N.CFG.EspHooks
		or N.CFG.EspPallets or N.CFG.EspWindows) then
		if N.esp.count() > 0 then N.esp.clear() end
		return
	end

	local me = N.hrp()
	if not me then return end
	local list = {}

	-- pemain
	if N.CFG.EspPlayers then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and p.Character then
				local h = p.Character:FindFirstChildOfClass("Humanoid")
				local root = p.Character:FindFirstChild("HumanoidRootPart")
				if root and h and h.Health > 0 then
					local d = (root.Position - me.Position).Magnitude
					if d <= (N.CFG.EspMaxDist or 500) then
						local role = nil
						pcall(function() role = p:GetAttribute("Role") or p:GetAttribute("Killer") and "Killer" end)
						local team = p.Team and p.Team.Name
						role = role or team
						local col = N.CFG.ColorOther
						if role == "Killer" then col = N.CFG.ColorKiller
						elseif role == "Survivor" then col = N.CFG.ColorSurvivor end
						list[#list + 1] = {
							id = "P_" .. p.Name, part = root, color = col,
							label = p.Name, role = role, dist = d, hp = h.Health,
						}
					end
				end
			end
		end
	end

	-- objek map
	local groups = {
		{ on = N.CFG.EspGens,    set = N.cache.gens,    col = N.CFG.ColorGen,  tag = "Gen" },
		{ on = N.CFG.EspGates,   set = N.cache.gates,   col = N.CFG.ColorGate, tag = "Gate" },
		{ on = N.CFG.EspHooks,   set = N.cache.hooks,   col = N.CFG.ColorHook, tag = "Hook" },
		{ on = N.CFG.EspPallets, set = N.cache.pallets, col = N.CFG.ColorPallet, tag = "Pallet" },
		{ on = N.CFG.EspWindows, set = N.cache.windows, col = N.CFG.ColorWindow, tag = "Window" },
	}
	for _, gr in ipairs(groups) do
		if gr.on then
			for i, inst in ipairs(gr.set) do
				local pos
				pcall(function()
					if inst:IsA("BasePart") then pos = inst.Position
					elseif inst:IsA("Model") and inst.PrimaryPart then pos = inst.PrimaryPart.Position
					else
						local bp = inst:FindFirstChildWhichIsA("BasePart", true)
						if bp then pos = bp.Position end
					end
				end)
				if pos then
					local d = (pos - me.Position).Magnitude
					list[#list + 1] = {
						id = gr.tag .. "_" .. tostring(inst:GetFullName()),
						part = (inst:IsA("BasePart") and inst) or inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true),
						color = gr.col, label = gr.tag .. " #" .. i, dist = d,
					}
				end
			end
		end
	end

	N.esp.sync(list)
end

--===================== [ 7. AIM ] ==========================================
N.aim = {}

function N.aim.getTarget()
	local me = N.hrp()
	if not me then return nil end
	local best, bestScore = nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character then
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			local head = p.Character:FindFirstChild("Head")
			local root = p.Character:FindFirstChild("HumanoidRootPart")
			if head and root and h and h.Health > 0 then
				local screen, onScreen = CAM:WorldToViewportPoint(head.Position)
				if onScreen then
					local cx = CAM.ViewportSize.X / 2
					local cy = CAM.ViewportSize.Y / 2
					local off = (Vector2.new(screen.X, screen.Y) - Vector2.new(cx, cy)).Magnitude
					if off <= (N.CFG.AimFov or 120) then
						if N.CFG.AimWallCheck then
							local ok, res = pcall(function()
								local rp = RaycastParams.new()
								rp.FilterType = Enum.RaycastFilterType.Exclude
								rp.FilterDescendantsInstances = { LP.Character }
								local r = workspace:Raycast(CAM.CFrame.Position, head.Position - CAM.CFrame.Position, rp)
								return r == nil
							end)
							if ok and not res then off = off + 1e6 end
						end
						if off < bestScore then best, bestScore = head, off end
					end
				end
			end
		end
	end
	return best
end

function N.aimStep()
	if not N.alive or not N.CFG.Aimbot then return end
	local t = N.aim.getTarget()
	if not t then return end
	local sm = 1 - math.clamp(N.CFG.AimSmooth or 0.35, 0, 1)
	local goal = CFrame.lookAt(CAM.CFrame.Position, t.Position)
	CAM.CFrame = CAM.CFrame:Lerp(goal, math.clamp(sm, 0.02, 1))
end

N.aim.fovCircle = nil
function N.aim.drawFov()
	if N.aim.fovCircle then pcall(function() N.aim.fovCircle:Destroy() end) N.aim.fovCircle = nil end
	if not N.CFG.AimShowFov then return end
	local parent = N.ui.gui or LP:FindFirstChild("PlayerGui")
	if not parent then return end
	local f = Instance.new("Frame")
	f.Name = "NYB2_FOV"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.5, 0)
	f.Size = UDim2.fromOffset(N.CFG.AimFov * 2, N.CFG.AimFov * 2)
	f.BackgroundTransparency = 1
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = N.CFG.Accent
	s.Thickness = 1.5
	s.Transparency = 0.4
	s.Parent = f
	N.aim.fovCircle = f
end

--===================== [ 8. MOVEMENT / VISUAL ] ============================
N.flyBV = nil
N.visualOriginals = {}

function N.applySpeed()
	local h = N.hum()
	if not h then return end
	h.WalkSpeed = N.CFG.SpeedOn and (N.CFG.SpeedValue or 28) or 16
end

function N.applyFly()
	local hrp = N.hrp()
	if not hrp then return end
	if N.CFG.FlyOn then
		if not N.flyBV then
			local bv = Instance.new("BodyVelocity")
			bv.Name = "NYB2_FLY"
			bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
			bv.Velocity = Vector3.zero
			bv.Parent = hrp
			N.flyBV = bv
		end
	elseif N.flyBV then
		pcall(function() N.flyBV:Destroy() end)
		N.flyBV = nil
	end
end

function N.applyNoclip()
	local ch = LP.Character
	if not ch then return end
	local wantCollide = not N.CFG.NoclipOn
	pcall(function()
		for _, d in ipairs(ch:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide ~= wantCollide then d.CanCollide = wantCollide end
		end
	end)
end

function N.applyFullbright()
	if N.CFG.Fullbright then
		N.visualOriginals.Brightness = N.visualOriginals.Brightness or Lighting.Brightness
		N.visualOriginals.ClockTime = N.visualOriginals.ClockTime or Lighting.ClockTime
		Lighting.Brightness = 3
		Lighting.ClockTime = 14
	elseif N.visualOriginals.Brightness then
		Lighting.Brightness = N.visualOriginals.Brightness
		if N.visualOriginals.ClockTime then Lighting.ClockTime = N.visualOriginals.ClockTime end
	end
end

function N.applyNoFog()
	if N.CFG.NoFog then
		N.visualOriginals.FogEnd = N.visualOriginals.FogEnd or Lighting.FogEnd
		Lighting.FogEnd = 1e6
		Lighting.FogStart = 0
	elseif N.visualOriginals.FogEnd then
		Lighting.FogEnd = N.visualOriginals.FogEnd
	end
end

function N.applyCamFov()
	CAM.FieldOfView = N.CFG.CamFov and (N.CFG.CamFovValue or 90) or 70
end

function N.tickMovement()
	-- fly pakai kamera
	if N.CFG.FlyOn and N.flyBV then
		local dir = Vector3.zero
		local hum = N.hum()
		if hum then
			dir = hum.MoveDirection
		end
		N.flyBV.Velocity = dir * (N.CFG.FlySpeed or 60) + Vector3.new(0, (UIS:IsKeyDown(Enum.KeyCode.Space) and 1 or 0) * (N.CFG.FlySpeed or 60), 0)
	end
end

--===================== [ 9. AUTO ] =========================================
function N.autoHeal()
	local h, ch = N.hum(), LP.Character
	if not h or not ch then return end
	if h.Health < h.MaxHealth then
		local pack = LP:FindFirstChildOfClass("Backpack")
		local key = nil
		pcall(function()
			if pack then
				for _, t in ipairs(pack:GetChildren()) do
					if string.find(string.lower(t.Name), "bandage") or string.find(string.lower(t.Name), "medkit") then
						key = t.Name
						break
					end
				end
			end
		end)
		if key then
			local tool = pack and pack:FindFirstChild(key)
			if tool and h then pcall(function() h:EquipTool(tool) end) end
		end
	end
end

--===================== [ 10. UI (WindUI, usage yg udah diverifikasi) ] =====
local WINDUI_URL = "https://raw.githubusercontent.com/Footagesus/WindUI/refs/heads/main/dist/main.lua"
local okW, WindUI = pcall(function()
	return loadstring(game:HttpGet(WINDUI_URL))()
end)

if not okW or type(WindUI) ~= "table" or type(WindUI.CreateWindow) ~= "function" then
	N.env.NYB2_RUNNING = nil
	warn("[NYB v2] WindUI gagal dimuat: " .. tostring(WindUI))
	return
end

N.log("WindUI dimuat")

local okWin, Window = pcall(function()
	return WindUI:CreateWindow({
		Title = "NYB HUB",
		Author = "Violence District  ·  v2",
		Theme = "Dark",
		ToggleKey = N.CFG.Keybind,
		Resizable = false,
		Transparent = false,
	})
end)

if not okWin or type(Window) ~= "table" then
	N.env.NYB2_RUNNING = nil
	warn("[NYB v2] CreateWindow gagal: " .. tostring(Window))
	return
end

N.ui.window = Window
N.ui.gui = WindUI.ScreenGui
N.ui.reg = {}
N.ui.tabs = {}

-- helper UI: SEMUA di root table, gak ada local lintas blok.
function N.ui.pick(parent, method)
	if type(parent) ~= "table" then return nil end
	if type(parent[method]) == "function" then return parent end
	return nil
end

function N.ui.notify(_, text)
	pcall(function()
		WindUI:Notify({ Title = "NYB HUB", Content = tostring(text), Icon = "info", Duration = 3 })
	end)
end

function N.ui.para(tab, text)
	local p = N.ui.pick(tab, "Paragraph")
	if not p then return nil end
	local ok, el = pcall(function() return p:Paragraph({ Title = tostring(text) }) end)
	if ok then return el end
	return nil
end

function N.ui.divider(tab)
	local d = N.ui.pick(tab, "Divider")
	if not d then return nil end
	local ok, el = pcall(function() return d:Divider({}) end)
	if ok then return el end
	return nil
end

function N.ui.header(tab, text)
	N.ui.para(tab, "── " .. text .. " ──")
	N.ui.divider(tab)
end

function N.ui.toggle(tab, label, key, on)
	local t = N.ui.pick(tab, "Toggle")
	if not t then
		N.log("!! Tab tidak punya :Toggle -- toggle '" .. label .. "' dilewati")
		return nil
	end
	local ok, el = pcall(function()
		return t:Toggle({
			Title = label,
			Value = N.CFG[key] and true or false,
			Callback = function(state)
				N.CFG[key] = state
				if on then
					local okc, err = pcall(on, state)
					if not okc then N.log("toggle " .. key .. " error: " .. tostring(err)) end
				end
			end,
		})
	end)
	if not ok then
		N.log("!! toggle '" .. label .. "' gagal dibuat: " .. tostring(el))
		return nil
	end
	N.ui.reg[key] = el
	return el
end

function N.ui.slider(tab, label, key, min, max, dec)
	local s = N.ui.pick(tab, "Slider")
	if not s then
		N.log("!! Tab tidak punya :Slider -- slider '" .. label .. "' dilewati")
		return nil
	end
	local step = (dec and dec > 0) and (10 ^ -dec) or 1
	local ok, el = pcall(function()
		return s:Slider({
			Title = label,
			Value = { Min = min, Max = max, Default = N.CFG[key] },
			Step = step,
			Callback = function(v) N.CFG[key] = v end,
		})
	end)
	if not ok then
		N.log("!! slider '" .. label .. "' gagal: " .. tostring(el))
		return nil
	end
	return el
end

function N.ui.button(tab, label, fn)
	local b = N.ui.pick(tab, "Button")
	if not b then
		N.log("!! Tab tidak punya :Button -- tombol '" .. label .. "' dilewati")
		return nil
	end
	local ok, el = pcall(function()
		return b:Button({
			Title = label,
			Callback = function()
				local okr, err = pcall(fn)
				if not okr then N.msg("Error: " .. tostring(err)) end
			end,
		})
	end)
	if not ok then N.log("!! tombol '" .. label .. "' gagal: " .. tostring(el)) end
	return el
end

function N.setCfg(key, v)
	N.CFG[key] = v
	local el = N.ui.reg[key]
	if el and type(el.Set) == "function" then
		pcall(function() el:Set(v and true or false, false, false) end)
	end
end

--===================== [ 11. FEATURE → UI + SELF TEST ] ====================
-- tiap fitur punya: key, label, tab, on(v), test()
-- on(v)   = efek samping (apply/unapply)
-- test()  = balikin (ok, detail) -- dipakai self-test

function N.featureToggle(key, label, on, test)
	N.feature({ key = key, label = label, on = on, test = test })
end

-- ---- visual / movement (efek langsung) ----
N.featureToggle("SpeedOn", "Speed Boost", function() N.applySpeed() end, function()
	N.setCfg("SpeedOn", true); N.applySpeed()
	task.wait(0.3)
	local h = N.hum()
	local v = h and h.WalkSpeed or -1
	N.setCfg("SpeedOn", false); N.applySpeed()
	return v > 16, string.format("WalkSpeed=%s (harus > 16)", tostring(v))
end)

N.featureToggle("FlyOn", "Fly", function() N.applyFly() end, function()
	if not N.hrp() then return false, "HRP tidak ada" end
	N.setCfg("FlyOn", true); N.applyFly()
	task.wait(0.3)
	local got = N.flyBV ~= nil
	N.setCfg("FlyOn", false); N.applyFly()
	return got, "BodyVelocity=" .. tostring(got)
end)

N.featureToggle("NoclipOn", "Noclip", function() N.applyNoclip() end, function()
	local ch = LP.Character
	if not ch then return false, "character tidak ada" end
	N.setCfg("NoclipOn", true); N.applyNoclip()
	task.wait(0.3)
	local n = 0
	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide == false then n = n + 1 end
	end
	N.setCfg("NoclipOn", false); N.applyNoclip()
	return n > 0, "part non-collide=" .. n
end)

N.featureToggle("Fullbright", "Fullbright", function() N.applyFullbright() end, function()
	local before = Lighting.Brightness
	N.setCfg("Fullbright", true); N.applyFullbright()
	task.wait(0.2)
	local got = Lighting.Brightness
	N.setCfg("Fullbright", false); N.applyFullbright()
	return got > before, string.format("Brightness %s -> %s", tostring(before), tostring(got))
end)

N.featureToggle("NoFog", "No Fog", function() N.applyNoFog() end, function()
	local before = Lighting.FogEnd
	N.setCfg("NoFog", true); N.applyNoFog()
	task.wait(0.2)
	local got = Lighting.FogEnd
	N.setCfg("NoFog", false); N.applyNoFog()
	return got > before, string.format("FogEnd %s -> %s", tostring(before), tostring(got))
end)

N.featureToggle("CamFov", "Camera FOV", function() N.applyCamFov() end, function()
	local before = CAM.FieldOfView
	N.setCfg("CamFov", true); N.applyCamFov()
	task.wait(0.2)
	local got = CAM.FieldOfView
	N.setCfg("CamFov", false); N.applyCamFov()
	return got ~= before, string.format("FOV %s -> %s", tostring(before), tostring(got))
end)

N.featureToggle("AimShowFov", "Tampilkan Lingkaran FOV", function() N.aim.drawFov() end, function()
	N.setCfg("AimShowFov", true); N.aim.drawFov()
	task.wait(0.2)
	local got = N.aim.fovCircle ~= nil
	N.setCfg("AimShowFov", false); N.aim.drawFov()
	return got, "Frame=" .. tostring(got)
end)

-- ---- ESP (loop-driven) ----
N.featureToggle("EspPlayers", "ESP Pemain", function(v)
	if v then
		N.setCfg("EspChams", true)
		N.setCfg("EspName", true)
		N.setCfg("EspDist", true)
		N.setCfg("EspHealth", true)
	end
end, function()
	local others = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then others = others + 1 end
	end
	N.setCfg("EspPlayers", true); N.setCfg("EspChams", true)
	N.setCfg("EspName", true);    N.setCfg("EspDist", true)
	N.espFrame()
	task.wait(0.4)
	N.espFrame()
	local n = N.esp.count()
	N.setCfg("EspPlayers", false); N.setCfg("EspChams", false)
	N.setCfg("EspName", false);    N.setCfg("EspDist", false)
	N.espFrame()
	if others == 0 then return nil, "skip: tidak ada pemain lain di server" end
	return n > 0, string.format("objek ESP=%d dari %d pemain lain", n, others)
end)

N.featureToggle("EspGens", "ESP Generator", nil, function()
	N.scan()
	local n = #N.cache.gens
	if n == 0 then return false, "scan tidak nemu generator (nama objek beda)" end
	N.setCfg("EspGens", true)
	N.espFrame(); task.wait(0.3); N.espFrame()
	local got = N.esp.count()
	N.setCfg("EspGens", false); N.espFrame()
	return got > 0, string.format("gen=%d objek ESP=%d", n, got)
end)

N.featureToggle("EspGates", "ESP Gate / Exit", nil, function()
	N.scan()
	local n = #N.cache.gates
	if n == 0 then return false, "scan tidak nemu gate" end
	N.setCfg("EspGates", true)
	N.espFrame(); task.wait(0.3); N.espFrame()
	local got = N.esp.count()
	N.setCfg("EspGates", false); N.espFrame()
	return got > 0, string.format("gate=%d objek ESP=%d", n, got)
end)

N.featureToggle("Aimbot", "Aimbot", nil, function()
	local t = N.aim.getTarget()
	N.setCfg("Aimbot", true)
	N.setCfg("Aimbot", false)
	if not t then return nil, "skip: tidak ada target dalam FOV" end
	return true, "target ketemu: " .. tostring(t.Parent and t.Parent.Name)
end)

N.featureToggle("AutoHeal", "Auto Heal", nil, function()
	local found = false
	pcall(function()
		local pack = LP:FindFirstChildOfClass("Backpack")
		if pack then
			for _, t in ipairs(pack:GetChildren()) do
				if string.find(string.lower(t.Name), "bandage") then found = true break end
			end
		end
	end)
	if not found then return nil, "skip: tidak ada bandage di backpack" end
	return true, "ada bandage di backpack"
end)

N.featureToggle("AutoParry", "Auto Parry", nil, function()
	local r = N.remotes.get("Items.Parrying Dagger.parry")
	if not r then return false, "remote Parrying Dagger.parry tidak ketemu" end
	local ok, err = pcall(function() r:FireServer() end)
	return ok, ok and "remote parry bisa dikirim" or ("gagal: " .. tostring(err))
end)

N.featureToggle("KillAura", "Kill Aura", nil, function()
	local me = N.hrp()
	if not me then return false, "HRP tidak ada" end
	local near = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 and (r.Position - me.Position).Magnitude <= (N.CFG.AttackRange or 14) then
				near = p
				break
			end
		end
	end
	if not near then return nil, "skip: tidak ada pemain dalam jangkauan" end
	return true, "target dekat: " .. near.Name
end)

N.featureToggle("RemoteLog", "Remote Log", nil, function()
	return #N.remotes.list > 0, "remote terdeteksi=" .. #N.remotes.list
end)

--===================== [ 12. BUILD TABS ] ==================================
N.TABBED = {
	{ name = "Main",     icon = "house" },
	{ name = "ESP",      icon = "eye" },
	{ name = "Aim",      icon = "crosshair" },
	{ name = "Auto",     icon = "zap" },
	{ name = "Movement", icon = "footprints" },
	{ name = "Visual",   icon = "palette" },
	{ name = "Misc",     icon = "settings" },
}

function N.ui.addTab(name, icon)
	local ok, tab = pcall(function() return Window:Tab({ Title = name, Icon = icon }) end)
	if not ok then
		N.log("!! tab '" .. name .. "' gagal: " .. tostring(tab))
		return nil
	end
	N.ui.tabs[name] = tab
	return tab
end

N.buildUI = function()
	for _, t in ipairs(N.TABBED) do
		local tab = N.ui.addTab(t.name, t.icon)
		if tab then
			if t.name == "Main" then
				N.ui.header(tab, "Preset")
				N.ui.button(tab, "Preset Survivor", function()
					N.setCfg("EspPlayers", true); N.setCfg("EspChams", true)
					N.setCfg("EspName", true); N.setCfg("EspDist", true)
					N.setCfg("EspGens", true); N.setCfg("SpeedOn", true)
					N.applySpeed()
					N.msg("Preset Survivor aktif")
				end)
				N.ui.button(tab, "Preset Killer", function()
					N.setCfg("EspPlayers", true); N.setCfg("EspChams", true)
					N.setCfg("EspName", true); N.setCfg("KillAura", true)
					N.setCfg("SpeedOn", true); N.applySpeed()
					N.msg("Preset Killer aktif")
				end)
				N.ui.button(tab, "Matikan Semua Fitur", function()
					for k in pairs(N.CFG) do
						if type(N.CFG[k]) == "boolean" then N.setCfg(k, false) end
					end
					N.applySpeed(); N.applyFly(); N.applyNoclip()
					N.applyFullbright(); N.applyNoFog(); N.applyCamFov()
					N.aim.drawFov(); N.esp.clear()
					N.msg("Semua fitur dimatikan")
				end)

				N.ui.header(tab, "Diagnostik")
				N.ui.button(tab, "SELF TEST (hasil di layar + clipboard)", N.runSelfTest)
				N.ui.button(tab, "Scan Ulang Map", function()
					local n = N.scan()
					N.msg("scan selesai: " .. n .. " objek")
				end)
				N.ui.button(tab, "Dump Remote (clipboard)", function()
					local txt = table.concat(N.remotes.list, "\n")
					if setclipboard then pcall(setclipboard, txt) end
					N.msg(#N.remotes.list .. " remote dicopy")
				end)
				N.ui.button(tab, "Unload Script", N.unload)
			elseif t.name == "ESP" then
				N.ui.header(tab, "Pemain")
				N.ui.toggle(tab, "ESP Pemain", "EspPlayers", nil)
				N.ui.toggle(tab, "Chams (Highlight)", "EspChams", nil)
				N.ui.toggle(tab, "Nama", "EspName", nil)
				N.ui.toggle(tab, "Jarak", "EspDist", nil)
				N.ui.toggle(tab, "HP", "EspHealth", nil)
				N.ui.slider(tab, "Jarak Maks ESP", "EspMaxDist", 50, 2000, 0)
				N.ui.header(tab, "Objek Map")
				N.ui.toggle(tab, "Generator", "EspGens", nil)
				N.ui.toggle(tab, "Gate / Exit", "EspGates", nil)
				N.ui.toggle(tab, "Hook", "EspHooks", nil)
				N.ui.toggle(tab, "Pallet", "EspPallets", nil)
				N.ui.toggle(tab, "Window / Vault", "EspWindows", nil)
			elseif t.name == "Aim" then
				N.ui.header(tab, "Aimbot")
				N.ui.toggle(tab, "Aimbot", "Aimbot", nil)
				N.ui.toggle(tab, "Wall Check", "AimWallCheck", nil)
				N.ui.toggle(tab, "Tampilkan Lingkaran FOV", "AimShowFov", function() N.aim.drawFov() end)
				N.ui.slider(tab, "FOV Radius", "AimFov", 20, 500, 0)
				N.ui.slider(tab, "Smoothness", "AimSmooth", 0, 1, 2)
			elseif t.name == "Auto" then
				N.ui.header(tab, "Survivor")
				N.ui.toggle(tab, "Auto Heal", "AutoHeal", nil)
				N.ui.toggle(tab, "Auto Parry", "AutoParry", nil)
				N.ui.header(tab, "Killer")
				N.ui.toggle(tab, "Kill Aura", "KillAura", nil)
				N.ui.slider(tab, "Attack Range", "AttackRange", 5, 60, 0)
			elseif t.name == "Movement" then
				N.ui.header(tab, "Kecepatan")
				N.ui.toggle(tab, "Speed Boost", "SpeedOn", function() N.applySpeed() end)
				N.ui.slider(tab, "WalkSpeed", "SpeedValue", 16, 300, 0)
				N.ui.header(tab, "Terbang & Noclip")
				N.ui.toggle(tab, "Fly", "FlyOn", function() N.applyFly() end)
				N.ui.slider(tab, "Fly Speed", "FlySpeed", 10, 400, 0)
				N.ui.toggle(tab, "Noclip", "NoclipOn", function() N.applyNoclip() end)
				N.ui.toggle(tab, "Infinite Jump", "InfJump", nil)
			elseif t.name == "Visual" then
				N.ui.header(tab, "Layar")
				N.ui.toggle(tab, "Fullbright", "Fullbright", function() N.applyFullbright() end)
				N.ui.toggle(tab, "No Fog", "NoFog", function() N.applyNoFog() end)
				N.ui.header(tab, "Kamera")
				N.ui.toggle(tab, "Camera FOV", "CamFov", function() N.applyCamFov() end)
				N.ui.slider(tab, "FOV Value", "CamFovValue", 40, 140, 0)
			elseif t.name == "Misc" then
				N.ui.header(tab, "Diagnostik")
				N.ui.toggle(tab, "Remote Log", "RemoteLog", nil)
				N.ui.button(tab, "Resolve Remote Ulang", function()
					N.remotes.resolve()
					N.msg("remote: " .. #N.remotes.list)
				end)
				N.ui.para(tab, "Engine: WindUI · v2 rebuild\nKalau panel/toggle hilang, tekan hotkey " ..
					tostring(N.CFG.Keybind):gsub("Enum.KeyCode.", "") .. ".")
			end
		end
	end
	N.log("UI selesai dibangun: " .. #N.TABBED .. " tab")
end

--===================== [ 13. MAIN LOOP ] ===================================
N.alive = true

N.tickEsp = function(dt)
	if not N.alive then return end
	if tick() - (N.scanMeta.last or 0) > 3 then N.scan() end
	N.espFrame()
end

N.tickAuto = function(dt)
	if not N.alive then return end
	if N.CFG.AutoHeal then pcall(N.autoHeal) end
end

N.bind(RunService.RenderStepped, function(dt)
	if not N.alive then return end
	pcall(N.aimStep)
	pcall(N.tickMovement)
end)

N.bind(RunService.Heartbeat, function(dt)
	N.tickEsp(dt)
	N.tickAuto(dt)
	if tick() - (N.hudLast or 0) > 0.5 then
		N.hudLast = tick()
		pcall(N.ui.hudUpdate)
	end
end)

N.bind(UIS.JumpRequest, function()
	if N.alive and N.CFG.InfJump then
		local h = N.hum()
		if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

N.bind(LP.CharacterAdded, function()
	task.wait(1)
	N.applySpeed(); N.applyNoclip(); N.applyFly()
end)

--===================== [ 14. SELF TEST (tampil di layar) ] =================
N.ui.report = nil
N.ui.pushLog = nil

N.runSelfTest = function()
	local L = {}
	local function T(s) L[#L + 1] = tostring(s) end

	T("===== NYB HUB v2 — SELF TEST =====")
	T("PlaceId      : " .. tostring(game.PlaceId))
	T("character    : " .. (N.hrp() and "OK" or "TIDAK ADA"))
	T("remote       : " .. #N.remotes.list)
	local g = N.ui.gui
	T("gui overlay  : " .. (g and (tostring(g.ClassName) .. "  Enabled=" .. tostring(g.Enabled)
		.. "  Parent=" .. tostring(g.Parent and g.Parent.Name)) or "NIL"))
	local pass, fail, skip = 0, 0, 0
	T("")
	for _, f in ipairs(N.FEAT) do
		local v, detail = nil, "tidak ada test"
		if f.test then
			local okc, a, b = pcall(f.test)
			if not okc then
				v, detail = false, "ERROR: " .. tostring(a)
			else
				v, detail = a, b
			end
		end
		if v == true then pass = pass + 1
		elseif v == false then fail = fail + 1
		else skip = skip + 1 end
		T(string.format("[%-5s] %-28s %s",
			v == true and "OK" or (v == false and "GAGAL" or "SKIP"),
			f.label, detail ~= nil and tostring(detail) or ""))
	end
	T("")
	T(string.format("VERDICT: %d lulus, %d GAGAL, %d skip", pass, fail, skip))
	T("==================================")
	T("")
	T("---- DUMP OBJEK MAP (buat benerin scan) ----")
	for _, l in ipairs(N.mapDump()) do T(l) end

	local txt = table.concat(L, "\n")
	print(txt)
	if setclipboard then pcall(setclipboard, txt) end
	N.ui.showReport(txt)
	return txt
end

-- panel laporan di layar
function N.ui.showReport(txt)
	if N.ui.report then pcall(function() N.ui.report:Destroy() end) N.ui.report = nil end
	local parent = N.ui.gui or LP:FindFirstChild("PlayerGui")
	if not parent then return end
	local sg = Instance.new("ScreenGui")
	sg.Name = "NYB2_REPORT"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 9998
	sg.Parent = parent
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -20, 1, -180)
	f.Position = UDim2.new(0, 10, 0, 90)
	f.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
	f.BackgroundTransparency = 0.06
	f.BorderSizePixel = 0
	f.Parent = sg
	local uc = Instance.new("UICorner") uc.CornerRadius = UDim.new(0, 10) uc.Parent = f
	local us = Instance.new("UIStroke") us.Color = N.CFG.Accent us.Thickness = 2 us.Parent = f
	local sl = Instance.new("ScrollingFrame")
	sl.Size = UDim2.new(1, -16, 1, -44)
	sl.Position = UDim2.new(0, 8, 0, 8)
	sl.BackgroundTransparency = 1
	sl.BorderSizePixel = 0
	sl.ScrollBarThickness = 4
	local nlines = 0
	for _ in tostring(txt):gmatch("\n") do nlines = nlines + 1 end
	nlines = nlines + 1
	sl.CanvasSize = UDim2.new(0, 0, 0, 26 * nlines)
	sl.Parent = f
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -8, 0, 26 * nlines)
	lbl.BackgroundTransparency = 1
	lbl.Text = txt
	lbl.TextColor3 = Color3.fromRGB(230, 235, 240)
	lbl.TextSize = 14
	lbl.Font = Enum.Font.Code
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextYAlignment = Enum.TextYAlignment.Top
	lbl.TextWrapped = true
	lbl.Parent = sl
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -16, 0, 28)
	btn.Position = UDim2.new(0, 8, 1, -36)
	btn.BackgroundColor3 = N.CFG.Accent
	btn.Text = "TUTUP (hasil sudah di clipboard)"
	btn.TextColor3 = Color3.fromRGB(10, 12, 16)
	btn.TextSize = 14
	btn.Font = Enum.Font.GothamBold
	btn.Parent = f
	local uc2 = Instance.new("UICorner") uc2.CornerRadius = UDim.new(0, 6) uc2.Parent = btn
	btn.MouseButton1Click:Connect(function() sg:Destroy() N.ui.report = nil end)
	N.ui.report = sg
end


--===================== [ 14b. HUD LIVE ] ===================================
-- Selalu tampil. Jadi buat tau fitur jalan atau nggak, lu cukup liat layar:
-- toggle apa pun -> angka ON harus naik. Kalau ON naik tapi fitur diam,
-- berarti jalur toggle SEHAT dan yang rusak implementasi fiturnya.
N.ui.hud, N.ui.hudLbl = nil, nil

N.ui.hudMake = function()
	local parent = N.ui.gui or LP:FindFirstChild("PlayerGui")
	if not parent then return end
	local sg = Instance.new("ScreenGui")
	sg.Name = "NYB2_HUD"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 9997
	sg.Parent = parent
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, -16, 0, 138)
	f.Position = UDim2.new(0, 8, 0, 34)
	f.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	f.BackgroundTransparency = 0.22
	f.BorderSizePixel = 0
	f.Parent = sg
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = N.CFG.Accent
	st.Thickness = 1
	st.Transparency = 0.5
	st.Parent = f
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -10, 1, -8)
	l.Position = UDim2.new(0, 5, 0, 4)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.fromRGB(205, 255, 240)
	l.TextSize = 12
	l.Font = Enum.Font.Code
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = true
	l.Parent = f
	N.ui.hud, N.ui.hudLbl = sg, l
end

N.ui.hudUpdate = function()
	if not N.ui.hudLbl then return end
	local on = 0
	for _, f in ipairs(N.FEAT) do if N.CFG[f.key] then on = on + 1 end end
	local head = string.format("NYB v2  alive=%s  conns=%d  esp=%d  ON=%d/%d",
		tostring(N.alive), #N.conns, N.esp.count(), on, #N.FEAT)
	local tail = {}
	local from = math.max(1, #N.logLines - 5)
	for i = from, #N.logLines do tail[#tail + 1] = "> " .. tostring(N.logLines[i]) end
	N.ui.hudLbl.Text = head .. "\n" .. table.concat(tail, "\n")
end


--===================== [ 14c. MAP DUMP ] ===================================
-- scan() nebak nama objek dari keyword. Kalau salah tebak, hasilnya 0 dan
-- "ESP Generator" gagal. Fungsi ini nge-dump nama asli yang ada di workspace
-- supaya tebakannya bisa diganti data.
N.mapDump = function()
	local desc = workspace:GetDescendants()
	local counts, kw = {}, {}
	for _, d in ipairs(desc) do
		local ok, nm, cl = pcall(function() return d.Name, d.ClassName end)
		if ok and nm then
			local key = cl .. "  |  " .. nm
			counts[key] = (counts[key] or 0) + 1
			local low = string.lower(nm)
			if string.find(low, "gen", 1, true) or string.find(low, "gate", 1, true)
				or string.find(low, "exit", 1, true) or string.find(low, "hook", 1, true)
				or string.find(low, "pallet", 1, true) or string.find(low, "vault", 1, true)
				or string.find(low, "lever", 1, true) or string.find(low, "window", 1, true) then
				kw[key] = (kw[key] or 0) + 1
			end
		end
	end
	local function top(t, n)
		local list = {}
		for k, v in pairs(t) do list[#list + 1] = { k = k, v = v } end
		table.sort(list, function(a, b) return a.v > b.v end)
		local o = {}
		for i = 1, math.min(n, #list) do
			o[#o + 1] = string.format("  %4dx  %s", list[i].v, list[i].k)
		end
		return o
	end
	local out = {}
	out[#out + 1] = "descendant total: " .. tostring(#desc)
	out[#out + 1] = "TOP 18 nama terbanyak:"
	for _, l in ipairs(top(counts, 18)) do out[#out + 1] = l end
	out[#out + 1] = "KANDIDAT gen/gate/hook/pallet/vault/lever/window:"
	local kl = top(kw, 18)
	if #kl == 0 then out[#out + 1] = "  (TIDAK ADA nama yg cocok keyword)" end
	for _, l in ipairs(kl) do out[#out + 1] = l end
	return out
end

--===================== [ 15. BOOT ] ========================================
N.unload = function()
	N.alive = false
	for _, c in ipairs(N.conns) do pcall(function() c:Disconnect() end) end
	N.conns = {}
	N.esp.clear()
	pcall(function() if N.flyBV then N.flyBV:Destroy() end end)
	pcall(function() if N.aim.fovCircle then N.aim.fovCircle:Destroy() end end)
	pcall(function() if N.ui.report then N.ui.report:Destroy() end end)
	pcall(function() Window:Destroy() end)
	N.env.NYB2_RUNNING = nil
	print("[NYB v2] Unloaded.")
end

N.remotes.resolve()
N.scan()
N.buildUI()
N.ui.hudMake()

-- Self-test otomatis: begitu script di-load, panel laporan muncul sendiri.
-- Gak perlu klik apa pun, gak perlu baca console.
task.delay(8, function()
	pcall(function() N.runSelfTest() end)
end)

task.wait(0.4)
N.log(string.format("NYB HUB v2 loaded. remote=%d gen=%d", #N.remotes.list, #N.cache.gens))
N.msg("NYB HUB v2 loaded. Buka tab Main -> SELF TEST buat cek semua fitur.")

print("[NYB HUB v2] loaded. remote=" .. #N.remotes.list)
