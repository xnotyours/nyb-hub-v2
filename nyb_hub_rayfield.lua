--[[ ==========================================================================
     N Y B   H U B   |   Violence District Toolkit            v2.6
     --------------------------------------------------------------------------
     File    : nyb_hub_vanilla.lua      (file baru, engine sendiri)
     Engine  : Rayfield (sirius.menu/rayfield), dimuat via HttpGet saat inject
     Target  : [BUTCHER] Violence District      (PlaceId 93978595733734)
     Platform: Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift)

     v2.6 = 8 BIT CROWN (cosmetic): port 1:1 dari asset katalog Roblox
            "8-Bit Royal Crown" (assetId 10159600649) -- MeshId/TextureId asli
            + VFX api 8bit, ditempel ke Head pakai weld. Slider scale/offset
            biar bisa dipas-pasin, dan otomatis nempel lagi tiap respawn.

     v2.5 = ITEM USER generik: pakai item apa pun dari Remotes.Items /
            Backpack tanpa hardcode (nama diisi dari tombol Ganti Item /
            Scan Item), + scanner yang nge-dump nama tiap item & remote-nya
            ke clipboard.

     v2.4 = sticky group bar (nama grup nempel di atas area scroll) + tab
            pertama otomatis kebuka saat load (sebelumnya panel kosong sampai
            di-tap).

     v2.3 = UI pass: header grup bisa di-tap buat lipat/buka, garis pemisah
            antar grup, tab ESP + Visual dikasih header pembuka, jarak antar
            item lebih lega, tab bar/panel lebih enak di layar HP.

     v2.2 = DASH LOCK beneran (port PANDU Hub): camera aim-lock ke survivor
            terdekat -- trigger klik kanan (PC) / keybind V / tombol move2 (mobile),
            plus tombol DASH LOCK ngambang di HP. Slider range/durasi/smooth + mode Hold.

     v2.1 = port fitur dari source Aeris Hub (kode + arg remote kebaca polos):
       AIM    Aimbot survivor/killer (+FOV circle, wallcheck, predict, smooth)
              Silent aim Flashlight / Twist of Fate / Flask
       SURV   Unlimited Vault (lepas tag CollectionService "Blocked")
              Auto Pallet Slide, Drop All Pallets, Quick Recovery,
              Flowstate No CD, Anti Hook (spam Game.UpdateCharacterLook),
              Fast Bandage, God Mode, Invisible (offset look +5000 Y)
       KILLER No Slowdown, Infinite Lunge (lungeboost), Auto Stalk
       QoL    Stretch Res, Moonwalk, Auto Run, Crosshair,
              Next Killer (AllowKiller/KillerChance), Next Map (8 map),
              Bypass Exit Gate, Instant TP Gate, Save/Load Config

     Remote map dari dump live in-game:
       Generator / Healing / Carry / Attacks / Collision / Pallet / Window /
       Exit / Mechanics / Items / KillerPerks / Killers.Stalker / Events / Game
     Catatan: Remotes.Mechanics.Chat.* (TempBan/PermaBan/Unban) SENGAJA tidak
     dipakai -- itu tool moderasi yang menyasar pemain asli.
   ========================================================================== ]]

--===================== [ 0. LOAD GUARD ] ==================================
local NYB_ENV = (getgenv and getgenv()) or _G
if NYB_ENV.NYB_HUB_RUNNING then
	warn("[NYB HUB] Script sudah jalan. Tekan Unload dulu sebelum reload.")
	return
end
NYB_ENV.NYB_HUB_RUNNING = true

--===================== [ 1. SERVICES ] ====================================
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UIS                 = game:GetService("UserInputService")
local Lighting            = game:GetService("Lighting")
local TweenService        = game:GetService("TweenService")
local HttpService         = game:GetService("HttpService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local CollectionService   = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local lp  = Players.LocalPlayer
local cam = workspace.CurrentCamera

local unpack = table.unpack or unpack

--===================== [ 2. ROOT TABLE + CONFIG ] =========================
-- Satu local di main chunk. Semua modul nempel di sini supaya tidak kena
-- limit 200 local per function.
local NYB = {
	remotes = {},
	conns   = {},
	cleanups = {},
	esp      = {},
	state    = {},
	cache    = { gens = {}, hooks = {}, pallets = {}, windows = {}, gates = {} },
	ui       = {},
	alive    = true,
}

local CFG = {
	-- UI
	Keybind        = Enum.KeyCode.RightShift,
	Accent         = Color3.fromRGB(0, 210, 190),
	-- ESP
	EspPlayers     = false,
	EspChams       = false,
	EspBox         = false,
	EspName        = false,
	EspRole        = false,
	EspDist        = false,
	EspTool        = false,
	EspHealth      = false,
	EspGens        = false,
	EspHooks       = false,
	EspPallets     = false,
	EspWindows     = false,
	EspGates       = false,
	EspMaxDist     = 900,
	EspAliveOnly   = false,
	ColorKiller    = Color3.fromRGB(255, 70, 70),
	ColorSurvivor  = Color3.fromRGB(90, 190, 255),
	ColorOther     = Color3.fromRGB(200, 200, 200),
	ColorGen       = Color3.fromRGB(255, 205, 60),
	ColorGenDone   = Color3.fromRGB(60, 255, 120),
	ColorGate      = Color3.fromRGB(170, 90, 255),
	ColorHook      = Color3.fromRGB(255, 90, 90),
	ColorPallet    = Color3.fromRGB(255, 150, 60),
	ColorWindow    = Color3.fromRGB(120, 255, 240),
	KillerAlert    = false,
	AlertDist      = 90,
	-- Generator
	GenPerfect     = false,
	GenFailSafe    = false,
	GenDelayMin    = 0.10,
	GenDelayMax    = 0.28,
	AutoRepair     = false,
	AutoRepairTp   = false,
	RepairRange    = 16,
	RepairRate     = 0.35,
	-- Combat
	AutoParry      = false,
	AutoEquipDagger= false,
	ParryRange     = 22,
	ParryCooldown  = 0.8,
	AutoHeal       = false,
	HealThreshold  = 0.85,
	AutoWiggle     = false,
	AutoVault      = false,
	AntiFall       = false,
	AutoSelfUnhook = false,
	UnhookRate     = 0.5,
	AutoExit       = false,
	KillAura       = false,
	AttackRange    = 14,
	AttackRate     = 0.6,
	AttackFace     = false,
	AttackLunge    = false,
	BreakGen       = false,
	BreakRange     = 10,
	BreakRate      = 0.5,
	RealNoclip     = false,
	-- Movement
	SpeedEnabled   = false,
	SpeedValue     = 26,
	Fly            = false,
	FlySpeed       = 70,
	Noclip         = false,
	InfJump        = false,
	AntiAfk        = false,
	Gravity        = 196.2,
	-- Visual
	Fullbright     = false,
	NoFog          = false,
	AntiFlash      = false,
	SelfHighlight  = false,
	CameraFov      = 70,
	InfZoom        = false,
	TimeOfDay      = -1,
	-- Teleport
	SmoothTp       = false,
	SmoothTpTime   = 0.25,
	-- Misc
	RemoteLog      = false,
	ShowStats      = false,
	-- ==== AIM (port dari source Aeris) ====
	AimSurvivor    = false,
	AimKiller      = false,
	AimPart        = "Torso",
	AimRadius      = 150,
	AimMaxDist     = 300,
	AimSmooth      = 0.40,
	AimPredict     = 0.01,
	AimShowFov     = false,
	AimWallCheck   = false,
	AimKillerDist  = 14,
	SilentFlash    = false,
	SilentToF      = false,
	SilentFlask    = false,
	FlashYOffset   = 1.5,
	-- ==== SURVIVOR UTIL ====
	UnlimitedVault = false,
	PalletSlide    = false,
	QuickRecovery  = false,
	FlowstateNoCD  = false,
	GodMode        = false,
	Invisible      = false,
	AntiHook       = false,
	AntiHookY      = -250,
	AntiHookHz     = 44,
	FastBandage    = false,
	-- ==== KILLER UTIL ====
	NoSlowdown     = false,
	InfiniteLunge  = false,
	LungeValue     = 999,
	AutoStalk      = false,
	StalkRange     = 150,
	-- ==== QoL ====
	StretchRes     = false,
	StretchAmount  = 0.67,
	Moonwalk       = false,
	AutoRun        = false,
	Crosshair      = false,
	CrossSize      = 8,
	NextKiller     = false,
	NextMap        = false,
	BypassGate     = false,
	InstantTPGate  = false,
	-- ==== PORT LANJUTAN (v2.1) ====
	SpearSilent    = false,
	SpearSpeed     = 165,
	SpearGravity   = 103,
	SpearMaxDist   = 500,
	SpearLead      = 1.4,
	PerfectLanding = false,
	AdrenalineRush = false,
	StreamerMode   = false,
	CounterParry   = false,
	CounterParryDist = 15,
	CounterParryRate = 0.3,
	InfCorrupt     = false,
	DashLock       = false,
	DashLockDist   = 250,
	DashLockTime   = 2,
	DashLockSmooth = 0.55,
	DashLockHold   = false,
	DashLockBtn    = true,
	DashLockKey    = Enum.KeyCode.V,
	-- Item generik: nembak item dari Remotes.Items / Backpack tanpa hardcode.
	-- Nama diisi dari tombol "Ganti Item" atau hasil "Scan Item".
	UseItem        = false,
	UseItemName    = "",
	UseItemRate    = 0.5,
	UseItemEquip   = true,
	-- 8 Bit Crown: cosmetic lokal (asset katalog "8-Bit Royal Crown")
	CrownOn        = false,
	CrownScale     = 1,
	CrownYOff      = 0,
	CrownVfx       = true,
	KorlessMorph   = false,
	SkipEndscreen  = false,
	FakeName       = "NYB HUB",
}

--===================== [ 3. UTIL ] ========================================
do
	local function safe(fn, ...)
		local ok, res = pcall(fn, ...)
		if not ok then
			return nil, res
		end
		return res
	end
	NYB.safe = safe

	NYB.bind = function(signal, fn)
		local c = signal:Connect(fn)
		table.insert(NYB.conns, c)
		return c
	end

	NYB.delay = function()
		return CFG.GenDelayMin + math.random() * math.max(0, CFG.GenDelayMax - CFG.GenDelayMin)
	end

	NYB.msg = function(text)
		if NYB.ui.notify then
			NYB.ui.notify(text)
		else
			print("[NYB HUB] " .. tostring(text))
		end
	end

	NYB.hrp = function()
		local char = lp.Character
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	NYB.hum = function()
		local char = lp.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	-- deteksi role: Team-based (utama) + fallback atribut/heuristik
	NYB.role = function(plr)
		plr = plr or lp
		local team = plr.Team
		if team then
			local n = string.lower(team.Name)
			if string.find(n, "killer", 1, true) then return "Killer" end
			if string.find(n, "surv", 1, true) then return "Survivor" end
		end
		if plr:GetAttribute("SelectedKiller") ~= nil then return "Killer" end
		local char = plr.Character
		if char then
			if char:GetAttribute("Knocked") ~= nil or char:GetAttribute("IsHooked") ~= nil then
				return "Survivor"
			end
		end
		return "Unknown"
	end

	NYB.isKiller = function(plr)
		return NYB.role(plr) == "Killer"
	end

	NYB.dist = function(a, b)
		if not a or not b then return math.huge end
		return (a - b).Magnitude
	end

	NYB.rayClear = function(from, to)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { lp.Character }
		local hit = workspace:Raycast(from, to - from, params)
		return hit == nil
	end
end

--===================== [ 4. REMOTE RESOLVER ] =============================
do
	local RS = ReplicatedStorage

	local function child(parent, name)
		if not parent then return nil end
		return parent:FindFirstChild(name)
	end

	local function path(...)
		local node = RS
		local parts = { ... }
		for _, n in ipairs(parts) do
			node = child(node, n)
			if not node then return nil end
		end
		return node
	end

	NYB.remotes.resolve = function()
		local R = NYB.remotes
		local root = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 10)
		R.root = root
		if not root then return false end

		R.gen         = child(root, "Generator")
		R.genSkill    = child(R.gen, "SkillCheckEvent")
		R.genResult   = child(R.gen, "SkillCheckResultEvent")
		R.genRepair   = child(R.gen, "RepairEvent")

		local items   = child(root, "Items")
		R.items       = items
		local dagger  = items and (child(items, "Parrying Dagger") or child(items, "ParryingDagger"))
		R.dagger      = dagger
		R.parry       = child(dagger, "parry")
		R.parryResult = child(dagger, "parryResult")

		local perks   = child(root, "KillerPerks")
		local ks      = perks and child(perks, "kingscourge")
		R.kingStart   = child(ks, "KingScourgeStart")
		R.kingHit     = child(ks, "KingScourgeHit")

		R.mechanics   = child(root, "Mechanics")
		R.slow        = child(R.mechanics, "Slow") or child(R.mechanics, "Slowserver")
		R.fall        = child(R.mechanics, "Fall")

		R.pallet      = child(root, "Pallet")
		R.palletDrop  = child(R.pallet, "PalletDropEvent")
		R.palletSlide = child(R.pallet, "PalletSlideEvent")
		R.palletDone  = child(R.pallet, "PalletSlideCompleteEvent")

		R.window      = child(root, "Window")
		R.vault       = child(R.window, "VaultEvent")
		R.vaultDone   = child(R.window, "VaultCompleteEvent")

		R.healing     = child(root, "Healing")
		R.heal        = child(R.healing, "HealEvent")
		R.healSkill   = child(R.healing, "SkillCheckEvent")
		R.healResult  = child(R.healing, "SkillCheckResultEvent")
		R.healFail    = child(R.healing, "SkillCheckFailEvent")
		R.healStop    = child(R.healing, "Stophealing")
		R.healReset   = child(R.healing, "Reset")

		local gamef   = child(root, "Game")
		R.look        = child(gamef, "UpdateCharacterLook")

		local fl      = items and child(items, "Flashlight")
		R.blind       = child(fl, "GotBlinded")

		-- ==== baru: hasil dump remote live ====
		R.attacks     = child(root, "Attacks")
		R.basicAttack = child(R.attacks, "BasicAttack")
		R.afterAttack = child(R.attacks, "AfterAttack")
		R.attackHit   = child(R.attacks, "hit")
		R.lunge       = child(R.attacks, "Lunge")
		R.lungeDetect = child(R.attacks, "LungeDetect")
		R.attackLock  = child(R.attacks, "AttackLock")
		R.attackEvt   = child(root, "AttackEvent")

		local killers = child(root, "Killers")
		R.killers      = killers
		R.stalker      = child(killers, "Stalker")
		R.stalkerStart = child(R.stalker, "StartStalking")
		R.stalkerStop  = child(R.stalker, "StopStalking")
		R.stalkerGrab  = child(R.stalker, "grab")
		R.veil         = child(killers, "Veil")
		R.veilSpear    = child(R.veil, "Spearthrow")
		R.abyss        = child(killers, "Abysswalker")
		R.abyssCorrupt = child(R.abyss, "corrupt")
		R.hidden       = child(killers, "Hidden")
		R.hiddenLeap   = child(R.hidden, "Leap")
		R.hiddenM2     = child(R.hidden, "M2")

		R.collision    = child(root, "Collision")
		R.colOff       = child(R.collision, "DisableCollision")
		R.colOn        = child(R.collision, "EnableCollision")

		R.genFail      = child(R.gen, "SkillCheckFailEvent")
		R.genBreak     = child(R.gen, "BreakGenEvent")
		R.genBreakCommit = child(R.gen, "BreakGenCommit")
		R.escapeTime   = child(R.gen, "Escapetime")

		R.vaultCommit  = child(R.window, "VaultCommit")
		R.vaultReject  = child(R.window, "VaultReject")
		R.fastVault    = child(R.window, "fastvault")
		R.vaultAnim    = child(R.window, "VaultAnim")

		R.palletCommit = child(R.pallet, "PalletDropCommit")
		R.palletAnim   = child(R.pallet, "PalletDropAnim")

		R.progress     = child(root, "Progress")
		R.progressEvt  = child(R.progress, "ProgressUpdateEvent")
		R.fovEvent     = child(root, "FovEvent")

		-- ==== dari dump remote lengkap ====
		R.carry        = child(root, "Carry")
		R.hookEvent    = child(R.carry, "HookEvent")
		R.unhookEvent  = child(R.carry, "UnHookEvent")
		R.selfUnhook   = child(R.carry, "SelfUnHookEvent")
		R.hookCommit   = child(R.carry, "HookCommit")
		R.hookReject   = child(R.carry, "HookReject")
		R.carryDrop    = child(R.carry, "DropSurvivorEvent")

		R.exit         = child(root, "Exit")
		R.leverEvent   = child(R.exit, "LeverEvent")

		R.mechTeleport = child(R.mechanics, "Teleportcharacter")
		R.mechAttr     = child(R.mechanics, "ChangeAttribute")
		R.mechInterrupt= child(R.mechanics, "InterruptActions")
		R.mechCancel   = child(R.mechanics, "cancelaction")
		R.mechSync     = child(R.mechanics, "syncPosition")
		R.mechParried  = child(R.mechanics, "parriedclient")
		R.crouch       = child(R.mechanics, "Crouch")

		R.tracker      = child(child(items, "Tracker"), "active")
		R.gateItem     = child(child(items, "Gate"), "gate")
		R.bandage      = child(child(items, "Bandage"), "Fire")
		R.twistFire    = child(child(items, "Twist of Fate"), "Fire")
		R.twistAim     = child(child(items, "Twist of Fate"), "Aim")
		R.shieldRush   = child(child(items, "Riot Shield"), "Rush")
		R.monkeyPaw    = child(child(items, "Monkey Paw"), "Use")
		R.candle       = child(child(items, "WaxBound Candle"), "Fire")
		R.holyWater    = child(child(items, "Holy Water"), "Throw")
		R.adrenShot    = child(child(items, "Adrenaline Shot"), "Healthy")

		local ev       = child(root, "Events")
		local hallo    = ev and child(ev, "Halloween")
		R.evPassClaim  = child(child(hallo, "Pass"), "Claim")
		R.evPassReroll = child(child(hallo, "Pass"), "Reroll")
		R.evCrush      = child(hallo, "Crush")
		R.evMedal      = child(child(ev, "Medal"), "MedalQuestClaim")
		R.evGift       = child(child(ev, "Christmas"), "gift")

		R.playerAction = child(gamef, "PlayerActionEvent")
		R.roundEvt     = child(root, "Round")
		R.teleport     = child(root, "Teleport")

		return true
	end

	NYB.remotes.count = function()
		local n = 0
		for _, v in pairs(NYB.remotes) do
			if typeof(v) == "Instance" then n = n + 1 end
		end
		return n
	end

	-- tooltip daftar remote yang kedeteksi (buat self-test / clipboard)
	NYB.remotes.list = function()
		local out = {}
		local names = {
			"gen", "genSkill", "genResult", "genFail", "genRepair", "genBreak",
			"dagger", "parry", "parryResult", "kingStart", "kingHit",
			"slow", "fall", "palletDrop", "palletSlide", "palletDone",
			"vault", "vaultDone", "fastVault", "vaultCommit", "vaultReject",
			"heal", "healSkill", "healResult", "look", "blind",
			"basicAttack", "lunge", "attackHit", "attackLock",
			"colOff", "colOn", "progressEvt",
		}
		for _, k in ipairs(names) do
			local v = NYB.remotes[k]
			table.insert(out, string.format("%s=%s", k, tostring(v ~= nil)))
		end
		return table.concat(out, " ")
	end
end

--===================== [ 5. RAYFIELD UI ] ==================================
-- Lapisan UI pakai Rayfield. Fitur (section 6+) TIDAK diubah sama sekali --
-- yang diganti cuma layer ini, jadi kode fitur tetap yang terbukti jalan.
--
-- Kontrak Rayfield yg sudah diverifikasi dari sumbernya (sirius.menu/rayfield):
--   Rayfield:CreateWindow{Name,...} / Window:CreateTab(Name, Image)
--   Tab:CreateSection(text)  -> header VISUAL doang, gak ada collapse/Expandable
--   Tab:CreateToggle{Name,CurrentValue,Flag,Callback} -> return tabel settings KITA
--   Tab:CreateSlider{Name,Range={min,max},Increment,CurrentValue,Callback} -> idem
--   Tab:CreateButton{Name,Callback}   Tab:CreateLabel(text, icon, color)
--   Rayfield:Notify{Title,Content,Duration,Image}    Rayfield = ScreenGui (DisplayOrder 100)
--
-- Kenapa aman: :Set() ditempel ke tabel settings yg KITA kirim sendiri, jadi
-- sinkronisasi dari NYB.setCfg gak perlu nebak bentuk return-nya. Dan section
-- Rayfield itu cuma judul + spasi -- gak ada Expandable/ClipsDescendants yg
-- bisa nyembunyiin element kayak di WindUI.

local okR, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not okR or type(Rayfield) ~= "table" then
	NYB_ENV.NOVA_VD_RUNNING = nil
	warn("[NYB HUB] Rayfield gagal dimuat: " .. tostring(Rayfield))
	return
end

local okW, Window = pcall(function()
	return Rayfield:CreateWindow({
		Name = "NYB HUB",
		LoadingTitle = "NYB HUB",
		LoadingSubtitle = "Violence District  ·  v2.6",
		Icon = 4483362458,
		Theme = "Default",
		ToggleUIKeybind = CFG.Keybind,
		DisableBuildWarnings = true,
		ConfigurationSaving = { Enabled = false },
	})
end)

if not okW or type(Window) ~= "table" then
	NYB_ENV.NOVA_VD_RUNNING = nil
	warn("[NYB HUB] Rayfield CreateWindow gagal: " .. tostring(Window))
	return
end

--==== STATE MODUL -- semuanya nempel di NYB.ui, gak ada local lintas blok ====
NYB.ui.rayfield = Rayfield
NYB.ui.win      = Window
NYB.ui.tabs     = {}
NYB.ui.pages    = {}
NYB.ui.reg      = {}
NYB.ui._groups  = {}
NYB.ui.tabOf    = setmetatable({}, { __mode = "k" })
NYB.ui.colors = {
	bg     = Color3.fromRGB(18, 20, 24),
	panel  = Color3.fromRGB(24, 27, 32),
	panel2 = Color3.fromRGB(32, 36, 43),
	stroke = Color3.fromRGB(48, 53, 62),
	text   = Color3.fromRGB(228, 232, 238),
	dim    = Color3.fromRGB(150, 154, 164),
	accent = CFG.Accent,
}
NYB.ui.ICON = {
	Main = 4483362458, ESP = 4483362458, Aim = 4483362458, Auto = 4483362458,
	Combat = 4483362458, Movement = 4483362458, Visual = 4483362458,
	Teleport = 4483362458, Misc = 4483362458,
}
NYB.ui.window          = { Visible = true }
NYB.ui.gui             = Rayfield
NYB.ui.status          = ""
NYB.ui.sticky          = nil
NYB.ui.stickyLbl       = nil
NYB.ui.applyResponsive = function() end
NYB.ui.stickyTick      = function() end

NYB.ui.setWin = function(v)
	NYB.msg(v and "Window Rayfield dibuka lewat hotkey." or "Window disembunyikan lewat hotkey.")
end

-- holder.page -> Tab Rayfield
NYB.ui.tabFor = function(page)
	if type(page) == "table" then
		return NYB.ui.tabOf[page] or page.__tab
	end
	return nil
end

NYB.ui.createTab = function(name, short)
	local okT, tab = pcall(function()
		return NYB.ui.win:CreateTab(name, NYB.ui.ICON[name] or 4483362458)
	end)
	if not okT or type(tab) ~= "table" then
		warn("[NYB HUB] tab '" .. tostring(name) .. "' gagal: " .. tostring(tab))
		return nil
	end
	local holder = { __tab = tab, name = name, short = short or name }
	holder.activate = function() end
	holder.page = holder
	NYB.ui.tabOf[holder] = tab
	table.insert(NYB.ui.tabs, holder)
	table.insert(NYB.ui.pages, holder)
	return holder
end

NYB.ui.section = function(page, text)
	local tab = NYB.ui.tabFor(page)
	if not tab then return nil end
	local ok, sec = pcall(function() return tab:CreateSection(tostring(text)) end)
	if not ok then
		warn("[NYB HUB] section '" .. tostring(text) .. "' gagal: " .. tostring(sec))
		return nil
	end
	table.insert(NYB.ui._groups, { page = page, header = sec, text = text })
	return sec
end

NYB.ui.toggle = function(page, text, key, callback)
	local tab = NYB.ui.tabFor(page)
	if not tab then
		warn("[NYB HUB] toggle '" .. tostring(text) .. "': tab tidak ketemu")
		return nil
	end
	local default = (type(key) == "string") and (CFG[key] and true or false) or (key and true or false)
	local settings = {
		Name = tostring(text),
		CurrentValue = default,
		Flag = (type(key) == "string") and key or nil,
		Callback = function(state)
			if type(key) == "string" then CFG[key] = state end
			if callback then
				local okc, err = pcall(callback, state)
				if not okc then warn("[NYB HUB] toggle error: " .. tostring(err)) end
			end
		end,
	}
	local ok, el = pcall(function() return tab:CreateToggle(settings) end)
	if not ok then
		warn("[NYB HUB] toggle '" .. tostring(text) .. "' gagal: " .. tostring(el))
		return nil
	end
	-- Rayfield balikin tabel settings yg SAMA, dan nempelin :Set ke situ.
	local api = {
		key = settings.Flag,
		el  = el,
		set = function(v)
			v = v and true or false
			local target = (type(el) == "table") and el or settings
			if type(target.Set) == "function" then pcall(function() target:Set(v) end) end
		end,
	}
	if api.key then NYB.ui.reg[api.key] = api end
	return api
end

NYB.ui.slider = function(page, text, min, max, default, decimals, callback)
	local tab = NYB.ui.tabFor(page)
	if not tab then
		warn("[NYB HUB] slider '" .. tostring(text) .. "': tab tidak ketemu")
		return nil
	end
	decimals = tonumber(decimals) or 0
	local step = (decimals > 0) and (10 ^ -decimals) or 1
	local settings = {
		Name = tostring(text),
		Range = { min, max },
		Increment = step,
		CurrentValue = tonumber(default) or min,
		Callback = function(v)
			if callback then
				local okc, err = pcall(callback, v)
				if not okc then warn("[NYB HUB] slider error: " .. tostring(err)) end
			end
		end,
	}
	local ok, el = pcall(function() return tab:CreateSlider(settings) end)
	if not ok then
		warn("[NYB HUB] slider '" .. tostring(text) .. "' gagal: " .. tostring(el))
		return nil
	end
	return {
		el  = el,
		get = function()
			local t = (type(el) == "table") and el or settings
			return t.CurrentValue or default
		end,
		set = function(v)
			local t = (type(el) == "table") and el or settings
			if type(t.Set) == "function" then pcall(function() t:Set(v) end) end
		end,
	}
end

NYB.ui.button = function(page, text, callback)
	local tab = NYB.ui.tabFor(page)
	if not tab then
		warn("[NYB HUB] tombol '" .. tostring(text) .. "': tab tidak ketemu")
		return nil
	end
	local ok, el = pcall(function()
		return tab:CreateButton({
			Name = tostring(text),
			Callback = function()
				local okc, err = pcall(callback)
				if not okc then NYB.msg("Error: " .. tostring(err)) end
			end,
		})
	end)
	if not ok then warn("[NYB HUB] tombol '" .. tostring(text) .. "' gagal: " .. tostring(el)) end
	return el
end

-- Section 13 nulis `lbl.Text = ...`, sedangkan label Rayfield diubah lewat
-- :Set(). Jadi dibungkus proxy: __newindex meneruskan .Text ke :Set().
-- Nilainya disimpan di `store` terpisah -- kalau di-rawset, penulisan kedua
-- gak akan lewat __newindex lagi dan labelnya berhenti update.
NYB.ui.label = function(page, text, color)
	local tab = NYB.ui.tabFor(page)
	if not tab then return nil end
	local ok, el = pcall(function() return tab:CreateLabel(tostring(text or ""), nil, color) end)
	if not ok then
		warn("[NYB HUB] label gagal: " .. tostring(el))
		return nil
	end
	local store = { Text = tostring(text or "") }
	local proxy = {}
	setmetatable(proxy, {
		__index = function(_, k) return store[k] end,
		__newindex = function(_, k, v)
			store[k] = v
			if k == "Text" and type(el) == "table" and type(el.Set) == "function" then
				pcall(function() el:Set(tostring(v)) end)
			end
		end,
	})
	proxy.__el = el
	return proxy
end

NYB.ui.notify = function(text, duration)
	pcall(function()
		NYB.ui.rayfield:Notify({
			Title = "NYB HUB",
			Content = tostring(text),
			Duration = duration or 3,
			Image = 4483362458,
		})
	end)
end

NYB.ui.setStatus = function(text)
	NYB.ui.status = tostring(text)
end

-- setCfg: ubah CFG + sinkronkan widget (visual saja, callback TIDAK dipanggil --
-- sama seperti vanilla, efek samping fitur tetap di callback yang punya caller).
NYB.setCfg = function(key, v)
	CFG[key] = v
	local t = NYB.ui.reg[key]
	if t and t.set then t.set(v) end
end

task.wait(0.2)

--===================== [ 6. ESP ENGINE ] ==================================
do
	local ESP = NYB.esp
	ESP.pool = {}
	ESP.tracked = {}

	local function make(entry)
		local model = entry.model
		local o = {}

		if entry.chams then
			local hl = Instance.new("Highlight")
			hl.Name = "NYB_Chams"
			hl.Adornee = model
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			hl.FillTransparency = 0.72
			hl.OutlineTransparency = 0
			hl.Parent = cam
			o.hl = hl
		end

		local bb = Instance.new("BillboardGui")
		bb.Name = "NYB_ESP"
		bb.Adornee = entry.adornee or model
		bb.AlwaysOnTop = true
		bb.Size = UDim2.new(0, 240, 0, 46)
		bb.StudsOffset = Vector3.new(0, 3.1, 0)
		bb.MaxDistance = 1000
		bb.Parent = cam
		o.bb = bb

		local bg = Instance.new("Frame")
		bg.Size = UDim2.new(1, 0, 1, 0)
		bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		bg.BackgroundTransparency = 0.5
		bg.BorderSizePixel = 0
		bg.Parent = bb
		local uc = Instance.new("UICorner")
		uc.CornerRadius = UDim.new(0, 4)
		uc.Parent = bg

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 12
		lbl.TextStrokeTransparency = 0.35
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextYAlignment = Enum.TextYAlignment.Center
		lbl.Text = ""
		lbl.Parent = bg
		o.lbl = lbl

		if entry.box then
			local box = Instance.new("BoxHandleAdornment")
			box.Size = Vector3.new(3, 6, 3)
			box.Adornee = entry.adornee or model
			box.AlwaysOnTop = true
			box.Transparency = 0.6
			box.ZIndex = 5
			box.Parent = cam
			o.box = box
		end

		ESP.pool[model] = o
		return o
	end

	-- sinkronisasi: entry = {model, adornee, text, color, chams, box}
	ESP.sync = function(list)
		local present = {}
		for _, e in ipairs(list) do
			local model = e.model
			if model then
				present[model] = true
				local o = ESP.pool[model]
				if not o then o = make(e) end
				-- chams bisa di-toggle saat runtime
				if e.chams and not o.hl then
					local hl = Instance.new("Highlight")
					hl.Name = "NYB_Chams"
					hl.Adornee = model
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.FillTransparency = 0.72
					hl.OutlineTransparency = 0
					hl.Parent = cam
					o.hl = hl
				elseif (not e.chams) and o.hl then
					o.hl:Destroy()
					o.hl = nil
				end
				-- box juga
				if e.box and not o.box then
					local box = Instance.new("BoxHandleAdornment")
					box.Size = Vector3.new(3, 6, 3)
					box.Adornee = e.adornee or model
					box.AlwaysOnTop = true
					box.Transparency = 0.6
					box.ZIndex = 5
					box.Parent = cam
					o.box = box
				elseif (not e.box) and o.box then
					o.box:Destroy()
					o.box = nil
				end
				if o.bb and o.bb.Adornee ~= (e.adornee or model) then
					o.bb.Adornee = e.adornee or model
				end
				if o.hl then
					o.hl.FillColor = e.color
					o.hl.OutlineColor = e.color
				end
				if o.box then
					o.box.Color3 = e.color
				end
				if o.lbl then
					o.lbl.Text = e.text
					o.lbl.TextColor3 = e.color
				end
			end
		end
		for model, o in pairs(ESP.pool) do
			if not present[model] then
				if o.hl then o.hl:Destroy() end
				if o.bb then o.bb:Destroy() end
				if o.box then o.box:Destroy() end
				ESP.pool[model] = nil
			end
		end
		ESP.count = 0
		for _ in pairs(ESP.pool) do ESP.count = ESP.count + 1 end
	end

	ESP.clear = function()
		for model, o in pairs(ESP.pool) do
			if o.hl then o.hl:Destroy() end
			if o.bb then o.bb:Destroy() end
			if o.box then o.box:Destroy() end
			ESP.pool[model] = nil
		end
	end
end

--===================== [ 7. MAP SCANNER ] =================================
do
	local C = NYB.cache

	NYB.scan = function()
		local map = workspace:FindFirstChild("Map")
		local root = map or workspace

		C.gens, C.hooks, C.pallets, C.windows, C.gates = {}, {}, {}, {}, {}
		C.vaultList = {}
		C.scanRoot = map and "Map" or "workspace"

		local function consider(d)
			local n = d.Name
			if d:IsA("BasePart") and n == "VaultTrigger" then
				table.insert(C.vaultList, d)
			end
			if not d:IsA("Model") then return end
			local ln = string.lower(n)

			-- Generator: nama ada "generator" (+ bukan part "GeneratorPoint"),
			-- dan punya atribut progress ATAU anak GeneratorPoint
			if string.find(ln, "generator", 1, true) and not string.find(ln, "point", 1, true) then
				if d:GetAttribute("RepairProgress") ~= nil
					or d:GetAttribute("ProgressRepair") ~= nil
					or d:GetAttribute("kickcount") ~= nil
					or d:FindFirstChild("GeneratorPoint1", true)
					or d:FindFirstChild("GeneratorPoint", true) then
					C.gens[d] = true
				end
			end

			if string.find(ln, "hook", 1, true) and d:FindFirstChild("HookPoint", true) then
				C.hooks[d] = true
			end

			if string.find(ln, "pallet", 1, true) and not string.find(ln, "point", 1, true)
				and (d:FindFirstChild("PrimaryPartPallet", true) or d:FindFirstChild("PalletPoint", true)) then
				C.pallets[d] = true
			end

			if string.find(ln, "window", 1, true)
				and (d:FindFirstChild("VaultTrigger", true) or d:FindFirstChild("VaultPoint", true)) then
				C.windows[d] = true
			end

			if string.find(ln, "exitlever", 1, true) or string.find(ln, "exit", 1, true)
				or (string.find(ln, "gate", 1, true) and not string.find(ln, "gatehouse", 1, true)) then
				C.gates[d] = true
			end
		end

		for _, d in ipairs(root:GetDescendants()) do
			consider(d)
		end

		-- fallback: Map ada tapi generator nol -> sisir sisa workspace
		if map and next(C.gens) == nil then
			for _, d in ipairs(workspace:GetDescendants()) do
				if not d:IsDescendantOf(map) then
					consider(d)
				end
			end
		end

		C.genList   = {}
		C.hookList  = {}
		C.palletList= {}
		C.windowList= {}
		C.gateList  = {}
		for k in pairs(C.gens) do table.insert(C.genList, k) end
		for k in pairs(C.hooks) do table.insert(C.hookList, k) end
		for k in pairs(C.pallets) do table.insert(C.palletList, k) end
		for k in pairs(C.windows) do table.insert(C.windowList, k) end
		for k in pairs(C.gates) do table.insert(C.gateList, k) end
	end

	NYB.part = function(model)
		if not model then return nil end
		local p = model.PrimaryPart
		if p and p:IsA("BasePart") then return p end
		local named = model:FindFirstChild("Main", true) or model:FindFirstChild("HookPoint", true)
			or model:FindFirstChild("GeneratorPoint1", true) or model:FindFirstChild("defaultMaterial", true)
			or model:FindFirstChild("HitBox", true) or model:FindFirstChild("PrimaryPartPallet", true)
		if named and named:IsA("BasePart") then return named end
		-- GeneratorPoint bisa bernama "GeneratorPoint", "GeneratorPoint1", "GeneratorPointA", dst.
		for _, ch in ipairs(model:GetChildren()) do
			if ch:IsA("BasePart") and string.find(ch.Name, "GeneratorPoint", 1, true) then
				return ch
			end
		end
		return model:FindFirstChildWhichIsA("BasePart", true)
	end

	NYB.genProgress = function(gen)
		local p = gen:GetAttribute("RepairProgress")
		if p == nil then p = gen:GetAttribute("ProgressRepair") end
		return tonumber(p) or 0
	end

	NYB.genDone = function(gen)
		local c = gen:GetAttribute("Completed")
		if c ~= nil then return c == true end
		return NYB.genProgress(gen) >= 100
	end

	NYB.nearest = function(list, from)
		local best, bd = nil, math.huge
		from = from or (NYB.hrp() and NYB.hrp().Position)
		if not from then return nil end
		for _, m in ipairs(list or {}) do
			if m and m.Parent then
				local pt = NYB.part(m)
				if pt then
					local d = (pt.Position - from).Magnitude
					if d < bd then bd = d; best = m end
				end
			end
		end
		return best, bd
	end
end

--===================== [ 8. AUTO: SKILLCHECK + REPAIR ] ===================
do
	local R = NYB.remotes

	-- ambil node SkillCheck dari PlayerGui
	local function skillNodes()
		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return nil end
		local gui = pg:FindFirstChild("SkillCheckPromptGui")
		if not gui then return nil end
		local check = gui:FindFirstChild("Check")
		if not check then return nil end
		local line = check:FindFirstChild("Line")
		local goal = check:FindFirstChild("Goal")
		return check, line, goal
	end

	local lastVisible = false

	local function pressSpace()
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
			task.wait(0.04)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
		end)
	end

	-- Layer 1: snap needle + kirim space
	NYB.autoSkill = function()
		if not CFG.GenPerfect then
			lastVisible = false
			return
		end
		local check, line, goal = skillNodes()
		if not check then return end

		local vis = check.Visible
		if vis and not lastVisible then
			task.delay(NYB.delay(), function()
				if not CFG.GenPerfect then return end
				local ck, ln, gl = skillNodes()
				if not ck or not ln or not gl then return end
				pcall(function()
					ln.Rotation = 109 + (gl.Rotation or 0)
				end)
				pressSpace()
			end)
		end
		lastVisible = vis
	end

	-- Layer 2: hook outgoing remote, paksa hasil success
	NYB.installHook = function()
		if not CFG.GenFailSafe then return end
		if NYB.state.hooked then return end
		local ok = pcall(function()
			local mt = getrawmetatable(game)
			local old = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if m == "FireServer" and not checkcaller() then
					if CFG.GenPerfect and typeof(self) == "Instance" then
						local nm = string.lower(self.Name)
						if string.find(nm, "skillcheckresult", 1, true) then
							local a = { ... }
							a[1] = "success"
							if a[2] == nil then a[2] = 1 end
							return old(self, unpack(a))
						elseif nm == "kingscourgehit" then
							local a = { ... }
							a[2] = "success"
							return old(self, unpack(a))
						end
					end
					if CFG.AntiFall and R.fall and self == R.fall then
						local a = { ... }
						a[1] = 0
						return old(self, unpack(a))
					elseif CFG.AntiFlash and R.blind and self == R.blind then
						if lp.Team and lp.Team.Name == "Killer" then
							return nil
						end
					end

					-- INVISIBLE: geser CFrame UpdateCharacterLook keluar peta
					if CFG.Invisible and self == R.look then
						local a = {}
						for i, v in ipairs({ ... }) do
							if typeof(v) == "CFrame" then
								a[i] = v * CFrame.new(0, 5000, 0)
							else
								a[i] = v
							end
						end
						return old(self, unpack(a))
					end

					-- SILENT AIM Twist of Fate: arg Vector3 pertama = arah ke target
					if CFG.SilentToF and self == R.twistFire then
						local a = { ... }
						local tgt = NYB.silentTarget and NYB.silentTarget()
						if tgt then
							local hrp = NYB.hrp()
							local from = hrp and hrp.Position or cam.CFrame.Position
							local dir = (tgt.Position - from)
							if dir.Magnitude > 0.001 then
								for i = 1, math.min(#a, 4) do
									if typeof(a[i]) == "Vector3" then
										a[i] = dir.Unit
										break
									end
								end
							end
						end
						return old(self, unpack(a))
					end

					-- SILENT AIM Flask (Cure): arah throw diganti ke survivor terdekat
					if CFG.SilentFlask and typeof(self) == "Instance" and self.Name == "ThrowFlask" then
						local a = { ... }
						local tgt = NYB.silentTarget and NYB.silentTarget()
						if tgt and a[2] ~= nil and typeof(a[2]) == "Vector3" then
							a[1] = (tgt.Position - a[2]).Unit
							setnamecallmethod(m)
							return old(self, unpack(a))
						end
					end

					-- SILENT VEIL (spear): arah balistik + lead target
					if CFG.SpearSilent and typeof(self) == "Instance" and self.Name == "Spearthrow" then
						local hrp = NYB.hrp()
						local origin = hrp and hrp.Position
						local target = NYB.silentTarget and NYB.silentTarget()
						if target and origin and target.Parent then
							local speed = CFG.SpearSpeed
							local gravity = CFG.SpearGravity
							local hum = target.Parent:FindFirstChildOfClass("Humanoid")
							local mv = Vector3.zero
							if hum and hum.MoveDirection.Magnitude > 0 then
								mv = hum.MoveDirection * hum.WalkSpeed
							elseif target:IsA("BasePart") then
								mv = target.AssemblyLinearVelocity
							end
							local planar = Vector3.new(mv.X, 0, mv.Z)
							local delta = target.Position - origin
							local dist = delta.Magnitude
							if dist > 0.1 and dist <= CFG.SpearMaxDist then
								local horiz = Vector3.new(delta.X, 0, delta.Z).Magnitude
								local travel = select(2, NYB.ballistic(speed, gravity, horiz, delta.Y))
								local leadPos = target.Position + planar * (travel or 0) * CFG.SpearLead
								local d2 = leadPos - origin
								local h2 = Vector3.new(d2.X, 0, d2.Z).Magnitude
								local ang2 = select(1, NYB.ballistic(speed, gravity, math.max(h2, 0.1), d2.Y))
								local dir
								if h2 > 0.001 then
									dir = Vector3.new(d2.X, 0, d2.Z).Unit * math.cos(ang2)
										+ Vector3.new(0, math.sin(ang2), 0)
								else
									dir = d2.Unit
								end
								setnamecallmethod(m)
								return old(self, dir, speed, origin)
							end
						end
					end
				end
				return old(self, ...)
			end)
			setreadonly(mt, true)
			NYB.state.hooked = true
		end)
		if not ok then
			NYB.msg("Hook tidak didukung executor ini (Layer 2 off).")
		end
	end

	-- koneksi event QTE dipasang setelah remote di-resolve (dipanggil dari BOOT)
	NYB.autoSkillInit = function()
		if NYB.state.skillInit then return end
		NYB.state.skillInit = true
		if R.genSkill then
			NYB.bind(R.genSkill.OnClientEvent, function() NYB.state.qtePending = true end)
		end
		if R.kingStart then
			NYB.bind(R.kingStart.OnClientEvent, function() NYB.state.qtePending = true end)
		end
		if R.healSkill then
			NYB.bind(R.healSkill.OnClientEvent, function() NYB.state.qtePending = true end)
		end
	end
end

--===================== [ 9. AUTO: REPAIR / HEAL / PARRY / WIGGLE ] ========
do
	local R = NYB.remotes
	local C = NYB.cache

	NYB.autoRepair = function()
		local hrp = NYB.hrp()
		if not hrp then return end

		local gen, dist = NYB.nearest(C.genList, hrp.Position)
		if not gen then return end

		-- cari GeneratorPoint terdekat
		local point, pd = nil, math.huge
		for _, ch in ipairs(gen:GetChildren()) do
			if ch:IsA("BasePart") and string.find(ch.Name, "GeneratorPoint", 1, true) then
				local d = (ch.Position - hrp.Position).Magnitude
				if d < pd then pd = d; point = ch end
			end
		end
		if not point then return end

		if pd > CFG.RepairRange and CFG.AutoRepairTp then
			NYB.tpTo(point.Position + Vector3.new(0, 3, 0))
			return
		end
		if pd > CFG.RepairRange then return end

		local now = tick()
		if not NYB.state.lastRepair or now - NYB.state.lastRepair >= CFG.RepairRate then
			NYB.state.lastRepair = now
			NYB.state.repairPoint = point
			NYB.playRepairAnim()
			pcall(function()
				if R.genRepair then R.genRepair:FireServer(point, true) end
			end)
		end
	end

	NYB.stopRepair = function()
		NYB.stopRepairAnim()
		local p = NYB.state.repairPoint
		NYB.state.repairPoint = nil
		if p then
			pcall(function()
				if R.genRepair then R.genRepair:FireServer(p, false) end
			end)
		end
	end

	NYB.playRepairAnim = function()
		if NYB.state.repairTrack and NYB.state.repairTrack.IsPlaying then return end
		pcall(function()
			local hum = NYB.hum()
			local anim = hum and hum:FindFirstChildOfClass("Animator")
			if not anim then return end
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://92960319113695"
			local t = anim:LoadAnimation(a)
			t.Priority = Enum.AnimationPriority.Action
			t:Play()
			NYB.state.repairTrack = t
		end)
	end

	NYB.stopRepairAnim = function()
		pcall(function()
			if NYB.state.repairTrack and NYB.state.repairTrack.IsPlaying then
				NYB.state.repairTrack:Stop()
			end
		end)
		NYB.state.repairTrack = nil
	end

	--======== HEAL ========
	NYB.autoHeal = function()
		local hum = NYB.hum()
		local hrp = NYB.hrp()
		if not hum or not hrp then return end
		if hum.Health >= hum.MaxHealth * CFG.HealThreshold then return end
		local char = lp.Character
		local ci = char and char:FindFirstChild("CheckInterractable")
		if ci and (ci:GetAttribute("isRepairing") or ci:GetAttribute("isHealing")) then return end
		local now = tick()
		if NYB.state.lastHeal and now - NYB.state.lastHeal < 0.5 then return end
		NYB.state.lastHeal = now
		pcall(function()
			if R.heal then R.heal:FireServer(hrp, true) end
		end)
	end

	--======== PARRY ========
	NYB.parry = function()
		if not CFG.AutoParry then return end
		if NYB.state.parryCD then return end
		local char = lp.Character
		if not char then return end

		local dagger = char:FindFirstChild("Parrying Dagger")
		local pack = lp:FindFirstChild("Backpack")
		if not dagger and pack then dagger = pack:FindFirstChild("Parrying Dagger") end
		if not dagger then return end

		if CFG.AutoEquipDagger and dagger.Parent == pack then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				pcall(function() hum:EquipTool(dagger) end)
				task.wait(0.08)
			end
		end
		if not char:FindFirstChild("Parrying Dagger") then return end

		NYB.state.parryCD = true
		pcall(function()
			if R.parry then
				for _ = 1, 3 do R.parry:FireServer() end
			end
		end)
		task.delay(CFG.ParryCooldown, function() NYB.state.parryCD = false end)
	end

	NYB.watchKiller = function(char)
		local hum = char:WaitForChild("Humanoid", 5)
		local anim = hum and hum:WaitForChild("Animator", 5)
		if not anim then return end
		NYB.bind(anim.AnimationPlayed, function()
			if not CFG.AutoParry then return end
			local hrp, khrp = NYB.hrp(), char:FindFirstChild("HumanoidRootPart")
			if not hrp or not khrp then return end
			if (hrp.Position - khrp.Position).Magnitude > CFG.ParryRange then return end
			NYB.parry()
		end)
	end

	--======== WIGGLE / ANTI-STUN ========
	NYB.autoWiggle = function()
		if not CFG.AutoWiggle then return end
		local char = lp.Character
		if not char then return end
		if not (char:GetAttribute("IsHooked") or char:GetAttribute("Knocked")) then return end
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.A, false, game)
			task.wait(0.05)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.A, false, game)
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.D, false, game)
			task.wait(0.05)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.D, false, game)
		end)
	end

	--======== AUTO VAULT (slide over window/pallet saat lari) ========
	NYB.autoVault = function()
		if not CFG.AutoVault then return end
		local hrp = NYB.hrp()
		if not hrp then return end
		for _, d in ipairs(NYB.cache.vaultList or {}) do
			if d.Parent and (d.Position - hrp.Position).Magnitude < 6 then
				pcall(function()
					if R.vault then R.vault:FireServer(d, true) end
				end)
				return
			end
		end
	end
end

--===================== [ 9b. AUTO: VD EXTRA (attack/carry/exit) ] ==========
do
	local R = NYB.remotes
	local C = NYB.cache

	--======== AUTO SELF-UNHOOK (remote resmi, bukan simulasi tombol) ========
	NYB.autoSelfUnhook = function()
		if not CFG.AutoSelfUnhook then return end
		local char = lp.Character
		if not char then return end
		local hooked = char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried")
		if not hooked then return end
		local now = tick()
		if NYB.state.lastUnhook and now - NYB.state.lastUnhook < (CFG.UnhookRate or 0.5) then return end
		NYB.state.lastUnhook = now
		pcall(function()
			if R.selfUnhook then R.selfUnhook:FireServer() end
		end)
		-- fallback: kalau remote kosong, tetap wiggle
		if not R.selfUnhook then NYB.autoWiggle() end
	end

	--======== AUTO EXIT LEVER (buka gate keluar) ========
	NYB.autoExitLever = function()
		if not CFG.AutoExit then return end
		local hrp = NYB.hrp()
		if not hrp then return end
		local lever = workspace:FindFirstChild("Map")
		if lever then
			for _, d in ipairs(lever:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "Main" or d.Name == "ExitLever" or d.Name == "Lever")
					and d:IsDescendantOf(lever) then
					local parent = d.Parent
					local isExit = parent and (string.find(string.lower(parent.Name), "exit", 1, true)
						or string.find(string.lower(parent.Name), "lever", 1, true))
					if isExit and (d.Position - hrp.Position).Magnitude < 8 then
						local now = tick()
						if NYB.state.lastLever and now - NYB.state.lastLever < 0.6 then return end
						NYB.state.lastLever = now
						pcall(function()
							if R.leverEvent then R.leverEvent:FireServer(d) end
						end)
						return
					end
				end
			end
		end
	end

	--======== KILL AURA / AUTO ATTACK (killer) ========
	NYB.killAura = function()
		if not CFG.KillAura then return end
		if NYB.role(lp) ~= "Killer" then return end
		local hrp = NYB.hrp()
		if not hrp then return end

		local best, bd = nil, math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and NYB.role(plr) ~= "Killer" then
				local char = plr.Character
				local thrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if thrp and hum and hum.Health > 0 then
					local d = (thrp.Position - hrp.Position).Magnitude
					if d <= CFG.AttackRange and d < bd and not char:GetAttribute("IsHooked") then
						bd = d
						best = thrp
					end
				end
			end
		end
		if not best then return end

		local now = tick()
		if NYB.state.lastAtk and now - NYB.state.lastAtk < CFG.AttackRate then return end
		NYB.state.lastAtk = now

		if CFG.AttackFace then
			pcall(function()
				hrp.CFrame = CFrame.new(hrp.Position, Vector3.new(best.Position.X, hrp.Position.Y, best.Position.Z))
			end)
		end
		pcall(function()
			if R.basicAttack then R.basicAttack:FireServer() end
		end)
		if CFG.AttackLunge then
			pcall(function()
				if R.lunge then R.lunge:FireServer() end
			end)
		end
	end

	--======== BREAK GENERATOR (killer) ========
	NYB.breakGen = function()
		if not CFG.BreakGen then return end
		local hrp = NYB.hrp()
		if not hrp then return end
		local gen, d = NYB.nearest(C.genList, hrp.Position)
		if not gen or (d or 999) > CFG.BreakRange then return end
		local now = tick()
		if NYB.state.lastBreak and now - NYB.state.lastBreak < CFG.BreakRate then return end
		NYB.state.lastBreak = now
		local pt = NYB.part(gen)
		pcall(function()
			if R.genBreak then R.genBreak:FireServer(pt or gen) end
		end)
	end

	--======== REAL NOCLIP (collision server-side) ========
	NYB.realNoclip = function(on)
		pcall(function()
			if on and R.colOff then
				R.colOff:FireServer(lp.Character)
			elseif (not on) and R.colOn then
				R.colOn:FireServer(lp.Character)
			end
		end)
	end

	--======== CLAIM REWARD EVENT (sekali tekan) ========
	NYB.claimEvents = function()
		local done = {}
		pcall(function()
			if R.evMedal then
				local ok, res = pcall(function() return R.evMedal:InvokeServer() end)
				table.insert(done, "MedalQuestClaim=" .. tostring(ok) .. " " .. tostring(res))
			end
			if R.evPassClaim then
				R.evPassClaim:FireServer()
				table.insert(done, "HalloweenPassClaim=ok")
			end
			if R.evGift then
				R.evGift:FireServer()
				table.insert(done, "ChristmasGift=ok")
			end
		end)
		NYB.msg(#done > 0 and table.concat(done, " | ") or "Tidak ada remote event yang ketemu.")
	end

	--======== INTERRUPT ACTION (batalkan aksi berjalan) ========
	NYB.interruptActions = function()
		pcall(function()
			if R.mechInterrupt then R.mechInterrupt:FireServer() end
			if R.mechCancel then R.mechCancel:FireServer() end
		end)
		NYB.msg("Interrupt/cancel action dikirim.")
	end

	--======== PROBE ChangeAttribute (eksperimen) ========
	NYB.probeAttr = function(name, value)
		local char = lp.Character
		if not char then return end
		if not R.mechAttr then NYB.msg("Mechanics.ChangeAttribute tidak ada.") return end
		pcall(function() R.mechAttr:FireServer(char, name, value) end)
		pcall(function() R.mechAttr:FireServer(char, { name, value }) end)
		NYB.msg("Probe ChangeAttribute: " .. tostring(name) .. " = " .. tostring(value) .. " (cek Remote Log)")
	end
end

--===================== [ 9c. AIM (port dari source Aeris) ] ===============
do
	local R = NYB.remotes
	local aimGui, aimCircle, crossGui
	local lastTarget, lastTargetTime = nil, 0

	local function tPart(char)
		if not char then return nil end
		local p = char:FindFirstChild(CFG.AimPart)
		if not (p and p:IsA("BasePart")) then p = char:FindFirstChild("Torso") end
		if not (p and p:IsA("BasePart")) then p = char:FindFirstChild("UpperTorso") end
		if not (p and p:IsA("BasePart")) then p = char:FindFirstChild("HumanoidRootPart") end
		return p
	end

	local function downed(char)
		return char:GetAttribute("Knocked") == true or char:GetAttribute("IsHooked") == true
	end

	NYB.aimMode = function()
		local role = NYB.role(lp)
		if role == "Killer" and CFG.AimKiller then return "killer" end
		if role ~= "Killer" and CFG.AimSurvivor then return "survivor" end
		return nil
	end

	NYB.aimTarget = function()
		local mode = NYB.aimMode()
		if not mode then return nil end
		local hrp = NYB.hrp()
		if not hrp then return nil end
		local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
		local best, score = nil, math.huge

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp then
				local isK = NYB.isKiller(plr)
				local wanted = (mode == "survivor") and isK or ((mode == "killer") and (not isK))
				if wanted then
					local char = plr.Character
					local chrp = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if chrp and hum and hum.Health > 0 then
						if (mode == "killer") and downed(char) then
							-- survivor yang sudah knocked/hooked dilewati (sama seperti Aeris)
						else
							local part = tPart(char) or chrp
							local d = (chrp.Position - hrp.Position).Magnitude
							local maxD = (mode == "survivor") and CFG.AimMaxDist or CFG.AimKillerDist
							if d <= maxD then
								if mode == "survivor" then
									local sp = cam:WorldToViewportPoint(part.Position)
									local m = (Vector2.new(sp.X, sp.Y) - center).Magnitude
									if m <= CFG.AimRadius and m < score then
										score = m
										best = part
									end
								else
									if d < score then
										score = d
										best = part
									end
								end
							end
						end
					end
				end
			end
		end

		if best and CFG.AimWallCheck then
			if not NYB.rayClear(cam.CFrame.Position, best.Position) then
				return nil
			end
		end
		return best
	end

	--======== FOV CIRCLE + CROSSHAIR ========
	NYB.updateAimDraw = function()
		local mode = NYB.aimMode()
		local wantCircle = CFG.AimShowFov and mode ~= nil
		if wantCircle and not (aimGui and aimGui.Parent) then
			aimGui = Instance.new("ScreenGui")
			aimGui.Name = "NYB_AimFov"
			aimGui.ResetOnSpawn = false
			aimGui.IgnoreGuiInset = true
			aimGui.Parent = NYB.ui.gui
			aimCircle = Instance.new("Frame")
			aimCircle.AnchorPoint = Vector2.new(0.5, 0.5)
			aimCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
			aimCircle.BackgroundTransparency = 1
			aimCircle.Parent = aimGui
			local uc = Instance.new("UICorner")
			uc.CornerRadius = UDim.new(1, 0)
			uc.Parent = aimCircle
			local st = Instance.new("UIStroke")
			st.Color = CFG.Accent
			st.Thickness = 1.5
			st.Transparency = 0.3
			st.Parent = aimCircle
		end
		if aimCircle then
			aimCircle.Visible = wantCircle
			if wantCircle then
				local r = (mode == "survivor") and CFG.AimRadius or 40
				aimCircle.Size = UDim2.new(0, r * 2, 0, r * 2)
			end
		end
		return mode
	end

	NYB.buildCrosshair = function()
		if crossGui and crossGui.Parent then
			crossGui:Destroy()
		end
		crossGui = nil
		if not CFG.Crosshair then return end
		local s = CFG.CrossSize
		crossGui = Instance.new("ScreenGui")
		crossGui.Name = "NYB_Crosshair"
		crossGui.ResetOnSpawn = false
		crossGui.IgnoreGuiInset = true
		crossGui.Parent = NYB.ui.gui
		local function bar(w, h, x, y)
			local f = Instance.new("Frame")
			f.Size = UDim2.new(0, w, 0, h)
			f.Position = UDim2.new(0.5, x, 0.5, y)
			f.BackgroundColor3 = CFG.Accent
			f.BorderSizePixel = 0
			f.ZIndex = 20
			f.Parent = crossGui
		end
		bar(s, 2, -s - 3, -1)
		bar(s, 2, 3, -1)
		bar(2, s, -1, -s - 3)
		bar(2, s, -1, 3)
	end

	--======== AIMBOT APPLICATION ========
	NYB.aimStep = function()
		local mode = NYB.updateAimDraw()
		if mode then
			local part = NYB.aimTarget()
			if part then
				local pos = part.Position
				local hrp = NYB.hrp()
				local d = hrp and (pos - hrp.Position).Magnitude or 0
				if d < 100 and CFG.AimPredict > 0 then
					pos = pos + cam.CFrame.RightVector * ((100 - d) * CFG.AimPredict)
				end
				local sm = math.clamp(CFG.AimSmooth, 0.05, 1)
				cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, pos), sm)
				if hrp then
					local face = CFrame.new(hrp.Position, Vector3.new(pos.X, hrp.Position.Y, pos.Z))
					hrp.CFrame = hrp.CFrame:Lerp(face, sm)
				end
			end
		end

		-- Silent aim flashlight: kamera + badan ngarah ke killer
		if CFG.SilentFlash then
			local best, bd = nil, math.huge
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= lp and NYB.isKiller(plr) then
					local char = plr.Character
					local chrp = char and char:FindFirstChild("HumanoidRootPart")
					if chrp then
						local dd = (chrp.Position - cam.CFrame.Position).Magnitude
						if dd < bd then bd = dd; best = chrp end
					end
				end
			end
			if best then
				local aim = best.Position + Vector3.new(0, CFG.FlashYOffset, 0)
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, aim), 0.5)
				local hrp = NYB.hrp()
				if hrp then
					local face = CFrame.lookAt(hrp.Position, Vector3.new(aim.X, hrp.Position.Y, aim.Z))
					hrp.CFrame = hrp.CFrame:Lerp(face, 0.5)
				end
			end
		end
	end

	--======== DIRECT TARGET NAMES buat silent aim remote ========
	NYB.silentTarget = function()
		local mode = NYB.aimMode()
		if mode == "survivor" then return NYB.aimTarget() end
		local best, bd = nil, math.huge
		local hrp = NYB.hrp()
		local from = hrp and hrp.Position or cam.CFrame.Position
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and not NYB.isKiller(plr) then
				local char = plr.Character
				local chrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if chrp and hum and hum.Health > 0 then
					local d = (chrp.Position - from).Magnitude
					if d < bd and d <= 400 then bd = d; best = chrp end
				end
			end
		end
		return best
	end
end

--===================== [ 9d. VD UTIL: survivor / killer / QoL ] ==========
do
	local R = NYB.remotes
	local C = NYB.cache

	--======== UNLIMITED VAULT ========
	-- Game menandai window "Blocked" lewat CollectionService. Hapus tag-nya.
	NYB.unlimitedVault = function(on)
		pcall(function()
			if on then
				for _, v in ipairs(CollectionService:GetTagged("Blocked")) do
					CollectionService:RemoveTag(v, "Blocked")
				end
				if not NYB.state.vaultConn then
					NYB.state.vaultConn = CollectionService:GetInstanceAddedSignal("Blocked"):Connect(function(inst)
						if CFG.UnlimitedVault then
							pcall(function() CollectionService:RemoveTag(inst, "Blocked") end)
						end
					end)
				end
			else
				if NYB.state.vaultConn then
					NYB.state.vaultConn:Disconnect()
					NYB.state.vaultConn = nil
				end
			end
		end)
	end

	--======== AUTO PALLET SLIDE + DROP PALLET ========
	NYB.palletStep = function()
		local hrp = NYB.hrp()
		if not hrp then return end
		local now = tick()

		if CFG.PalletSlide then
			local map = workspace:FindFirstChild("Map")
			if map then
				for _, d in ipairs(map:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "PalletPointSlide"
						and (d.Position - hrp.Position).Magnitude < 8 then
						if not NYB.state.lastSlide or now - NYB.state.lastSlide > 0.4 then
							NYB.state.lastSlide = now
							pcall(function()
								if R.palletSlide then R.palletSlide:FireServer(d, true) end
							end)
						end
						return
					end
				end
			end
		end

		if CFG.AutoVault and R.palletDrop then
			for _, m in ipairs(C.palletList or {}) do
				if m.Parent then
					local pt = m:FindFirstChild("PalletPoint", true)
					if pt and pt:IsA("BasePart") and (pt.Position - hrp.Position).Magnitude < 8 then
						if not NYB.state.lastDrop or now - NYB.state.lastDrop > 0.5 then
							NYB.state.lastDrop = now
							pcall(function() R.palletDrop:FireServer(pt) end)
						end
						return
					end
				end
			end
		end
	end

	NYB.dropAllPallets = function()
		local map = workspace:FindFirstChild("Map")
		if not map then NYB.msg("Map tidak ketemu.") return end
		local n = 0
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "PalletPoint" then
				if R.palletDrop then
					pcall(function() R.palletDrop:FireServer(d) end)
					n = n + 1
				end
			end
		end
		NYB.msg(string.format("%d pallet dikirim drop.", n))
	end

	--======== ANTI HOOK / INVISIBLE ========
	NYB.antiHookStep = function(dt)
		if not CFG.AntiHook then
			NYB.state.hookAcc = 0
			return
		end
		local char = lp.Character
		if not char then NYB.state.hookAcc = 0 return end
		if char:GetAttribute("IsCarried") ~= true then
			NYB.state.hookAcc = 0
			return
		end
		if not R.look then return end
		local interval = 1 / math.max(1, CFG.AntiHookHz)
		NYB.state.hookAcc = (NYB.state.hookAcc or 0) + dt
		local guard = 0
		while (NYB.state.hookAcc or 0) >= interval and guard < 4 do
			NYB.state.hookAcc = NYB.state.hookAcc - interval
			guard = guard + 1
			local c1 = CFrame.new(0, 1, 0)
			local c2 = CFrame.new(0, CFG.AntiHookY, 0)
			pcall(function() R.look:FireServer(c1, c2, c2, c2, c2) end)
		end
	end

	--======== GOD MODE / NO SLOWDOWN / INFINITE LUNGE / FLOWSTATE ========
	NYB.killerUtilStep = function()
		local char = lp.Character
		local hum = NYB.hum()
		if not char or not hum then return end

		if CFG.GodMode and hum.Health < hum.MaxHealth then
			pcall(function() hum.Health = hum.MaxHealth end)
		end

		if CFG.NoSlowdown and NYB.role(lp) == "Killer" and hum.WalkSpeed < 16 then
			pcall(function() hum.WalkSpeed = 16 end)
		end

		if CFG.InfiniteLunge then
			if char:GetAttribute("lungeboost") ~= CFG.LungeValue then
				pcall(function() char:SetAttribute("lungeboost", CFG.LungeValue) end)
			end
		end

		if CFG.FlowstateNoCD then
			if char:GetAttribute("Flowstate") ~= true then
				pcall(function() char:SetAttribute("Flowstate", true) end)
			end
		end
	end

	--======== QUICK RECOVERY (vault -> speedboost 1.4, 3 detik) ========
	NYB.quickRecoveryStep = function()
		if not CFG.QuickRecovery then return end
		local char = lp.Character
		if not char then return end
		local ci = char:FindFirstChild("CheckInterractable")
		local vaulting = ci and ci:GetAttribute("isVaulting") == true
		if vaulting and not NYB.state.qrActive then
			NYB.state.qrActive = true
			local until_ = tick() + 3
			task.spawn(function()
				while tick() < until_ and NYB.alive and CFG.QuickRecovery do
					pcall(function() char:SetAttribute("speedboost", 1.4) end)
					task.wait()
				end
				pcall(function() char:SetAttribute("speedboost", 1) end)
				NYB.state.qrActive = false
			end)
		end
	end

	--======== FAST BANDAGE (eksperimen) ========
	NYB.fastBandageStep = function()
		if not CFG.FastBandage then return end
		local hum = NYB.hum()
		if not hum or hum.Health >= hum.MaxHealth then return end
		local now = tick()
		if NYB.state.lastBandage and now - NYB.state.lastBandage < 0.5 then return end
		NYB.state.lastBandage = now
		pcall(function()
			if R.bandage then R.bandage:FireServer() end
		end)
	end

	--======== AUTO STALK (killer) ========
	NYB.autoStalkStep = function()
		if not CFG.AutoStalk then return end
		if NYB.role(lp) ~= "Killer" then return end
		local hrp = NYB.hrp()
		if not hrp then return end
		local stalk = R.stalkerStart
		if not stalk then return end
		local now = tick()
		if NYB.state.lastStalk and now - NYB.state.lastStalk < 0.35 then return end
		local target = nil
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and not NYB.isKiller(plr) then
				local char = plr.Character
				local chrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if chrp and hum and hum.Health > 30 then
					if (chrp.Position - hrp.Position).Magnitude <= CFG.StalkRange then
						target = plr
						break
					end
				end
			end
		end
		if target then
			NYB.state.lastStalk = now
			pcall(function() stalk:FireServer(target) end)
		end
	end

	--======== STRETCH RES (RenderStepped) ========
	NYB.stretchStep = function()
		if not CFG.StretchRes or not cam then return end
		cam.CFrame = cam.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, CFG.StretchAmount, 0, 0, 0, 1)
	end

	--======== MOONWALK (RenderStepped) ========
	NYB.moonwalkStep = function()
		if not CFG.Moonwalk then return end
		local char = lp.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum then return end
		hum.AutoRotate = false
		local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
		local lookU = look.Magnitude > 0.001 and look.Unit or look
		local rightU = right.Magnitude > 0.001 and right.Unit or right
		local s = math.sin(tick() * 35)
		local dir = CFrame.Angles(0, math.rad(30 * s), 0) * lookU
		hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)
		hum:Move(-lookU * 1.2 + rightU * (s * 1.05), false)
	end

	--======== AUTO RUN ========
	NYB.autoRunStep = function()
		if not CFG.AutoRun then return end
		local hum = NYB.hum()
		if not hum then return end
		local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
		if look.Magnitude > 0.001 then
			hum:Move(look.Unit, false)
		end
	end

	--======== INFINITY ZOOM ========
	NYB.zoomStep = function()
		if not CFG.InfZoom then return end
		pcall(function()
			lp.CameraMaxZoomDistance = 1e9
			lp.CameraMinZoomDistance = 0
		end)
	end

	--======== BYPASS EXIT GATE ========
	NYB.bypassGate = function(on)
		local map = workspace:FindFirstChild("Map")
		if not map then return end
		local n = 0
		for _, m in ipairs(C.gateList or {}) do
			if m and m.Parent then
				local lg = m:FindFirstChild("LeftGate")
				local rg = m:FindFirstChild("RightGate")
				local gateBox = m:FindFirstChild("Box")
				local lge = m:FindFirstChild("LeftGate-end") or m:FindFirstChild("LeftGate-end2")
				local rge = m:FindFirstChild("RightGate-end") or m:FindFirstChild("RightGate-end2")
				pcall(function()
					if lg then lg.Transparency = on and 1 or 0; lg.CanCollide = not on end
					if rg then rg.Transparency = on and 1 or 0; rg.CanCollide = not on end
					if lge then lge.Transparency = on and 0 or 1 end
					if rge then rge.Transparency = on and 0 or 1 end
					if gateBox then gateBox.CanCollide = not on end
				end)
				n = n + 1
			end
		end
		NYB.msg(string.format("Bypass gate %s (%d model).", on and "ON" or "OFF", n))
	end

	--======== INSTANT TP GATE (getgc + module hook) ========
	NYB.instantGate = function(on)
		NYB.state.instGate = on
		if not on then return end
		local ok = pcall(function()
			if type(getgc) ~= "function" then error("executor tidak punya getgc") end
			for _, v in pairs(getgc(true)) do
				if type(v) == "table" and rawget(v, "gateDuration") and rawget(v, "gateRemote") then
					rawset(v, "gateDuration", 0)
				end
			end
			local mods = ReplicatedStorage:FindFirstChild("Modules")
			local items = mods and mods:FindFirstChild("Items")
			local gateClient = items and items:FindFirstChild("GateClient")
			if gateClient then
				local m = require(gateClient)
				if not NYB.state.gateNew then
					NYB.state.gateNew = m.new
					m.new = function(...)
						local obj = NYB.state.gateNew(...)
						if NYB.state.instGate and type(obj) == "table" then
							pcall(function() obj.gateDuration = 0 end)
						end
						return obj
					end
				end
			end
		end)
		if not ok then
			NYB.msg("Instant TP Gate butuh executor dengan getgc (Xeno/Wave).")
		end
	end

	--======== NEXT KILLER + NEXT MAP ========
	NYB.setupInfoLabels = function()
		if NYB.state.infoGui and NYB.state.infoGui.Parent then return end
		local g = Instance.new("ScreenGui")
		g.Name = "NYB_Info"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.Parent = NYB.ui.gui
		local function mk(y)
			local l = Instance.new("TextLabel")
			l.Size = UDim2.new(0, 230, 0, 22)
			l.Position = UDim2.new(0.5, 0, 0, y)
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
			l.BackgroundTransparency = 0.15
			l.TextColor3 = Color3.fromRGB(220, 220, 230)
			l.Font = Enum.Font.GothamMedium
			l.TextSize = 11
			l.RichText = true
			l.Visible = false
			l.Parent = g
			local uc = Instance.new("UICorner")
			uc.CornerRadius = UDim.new(0, 6)
			uc.Parent = l
			return l
		end
		NYB.state.infoGui = g
		NYB.state.killerLbl = mk(10)
		NYB.state.mapLbl = mk(36)
	end

	NYB.infoStep = function()
		if not (CFG.NextKiller or CFG.NextMap) then
			if NYB.state.killerLbl then NYB.state.killerLbl.Visible = false end
			if NYB.state.mapLbl then NYB.state.mapLbl.Visible = false end
			return
		end
		NYB.setupInfoLabels()
		local kl, ml = NYB.state.killerLbl, NYB.state.mapLbl

		if kl then
			kl.Visible = CFG.NextKiller
			if CFG.NextKiller then
				local list = {}
				for _, p in ipairs(Players:GetPlayers()) do
					table.insert(list, p)
				end
				table.sort(list, function(a, b)
					local aa = a:GetAttribute("AllowKiller") or false
					local bb = b:GetAttribute("AllowKiller") or false
					if aa ~= bb then return aa end
					return (a:GetAttribute("KillerChance") or 0) > (b:GetAttribute("KillerChance") or 0)
				end)
				local p = list[1]
				if p then
					local nm = p == lp and "<font color='#ff5555'>KAMU</font>" or p.Name
					local ch = p:GetAttribute("KillerChance")
					kl.Text = "Next Killer: " .. nm .. (ch and string.format(" <font color='#888888'>(%.0f%%)</font>", ch * 100) or "")
				else
					kl.Text = "Next Killer: <font color='#888888'>-</font>"
				end
			end
		end

		if ml then
			ml.Visible = CFG.NextMap
			if CFG.NextMap then
				local map = workspace:FindFirstChild("Map")
				local name = nil
				if map then
					if map:FindFirstChild("random shakes") or map:FindFirstChild("SCP-173 Room")
						or map:FindFirstChild("SCP-205 Room") then
						name = "Site 68"
					elseif map:FindFirstChild("HooksMeat") then
						name = "BLOODBATH! Club"
					elseif map:FindFirstChild("Gate") and map.Gate:FindFirstChild("vfx") then
						name = "Firelink Shrine"
					elseif map:FindFirstChild("Bldg_Addon_RooftopUnit_A") or map:FindFirstChild("Rooftop") then
						name = "Mercy Hospital Rooftop"
					elseif map:FindFirstChild("White Armored Car") then
						name = "Mount Massive Asylum"
					elseif map:FindFirstChild("Dumbster") then
						name = "The Bay Harbor"
					elseif map:FindFirstChild("water pump") then
						name = "Valdelobos Village"
					elseif map:FindFirstChild("LargeBoulder01") then
						name = "Woodview Cabin"
					end
				end
				ml.Text = "Map: " .. (name and ("<font color='#5fd3ff'>" .. name .. "</font>") or "<font color='#888888'>?</font>")
			end
		end
	end

	--======== CONFIG SAVE / LOAD ========
	local CFG_FOLDER = "NYB_HUB"
	local CFG_FILE = CFG_FOLDER .. "/config.json"

	NYB.saveConfig = function()
		local ok = pcall(function()
			local wf = writefile
			if type(wf) ~= "function" then error("executor tidak punya writefile") end
			if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder(CFG_FOLDER) then
				makefolder(CFG_FOLDER)
			end
			local out = {}
			for k, v in pairs(CFG) do
				if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
					out[k] = v
				end
			end
			wf(CFG_FILE, HttpService:JSONEncode(out))
		end)
		NYB.msg(ok and ("Config disimpan: " .. CFG_FILE) or "Gagal simpan config (butuh executor dengan writefile).")
	end

	NYB.loadConfig = function()
		local applied = 0
		local ok = pcall(function()
			local rf = readfile
			if type(rf) ~= "function" then error("executor tidak punya readfile") end
			local txt = rf(CFG_FILE)
			if not txt or txt == "" then error("file config kosong") end
			local data = HttpService:JSONDecode(txt)
			for k, v in pairs(data) do
				if CFG[k] ~= nil and type(CFG[k]) == type(v) and k ~= "Keybind" and k ~= "Accent" then
					NYB.setCfg(k, v)
					applied = applied + 1
				end
			end
		end)
		NYB.msg(ok and string.format("Config dimuat: %d field.", applied) or "Gagal load config (belum ada / executor tidak support).")
	end

	NYB.resetConfig = function()
		local defaults = {
			AimSurvivor = false, AimKiller = false, AimShowFov = false, AimWallCheck = false,
			SilentFlash = false, SilentToF = false, SilentFlask = false,
			UnlimitedVault = false, PalletSlide = false, QuickRecovery = false, FlowstateNoCD = false,
			GodMode = false, AntiHook = false, FastBandage = false,
			NoSlowdown = false, InfiniteLunge = false, AutoStalk = false,
			StretchRes = false, Moonwalk = false, AutoRun = false, Crosshair = false,
			NextKiller = false, NextMap = false, BypassGate = false, InstantTPGate = false,
			SpearSilent = false, PerfectLanding = false, AdrenalineRush = false,
			StreamerMode = false, CounterParry = false, InfCorrupt = false, DashLock = false,
			KorlessMorph = false, SkipEndscreen = false, CrownOn = false,
		}
		for k, v in pairs(defaults) do NYB.setCfg(k, v) end
		NYB.msg("Semua fitur hasil port direset ke OFF.")
	end
end

--===================== [ 9e. PORT LANJUTAN (v2.1) ] ========================
do
	local R = NYB.remotes

	--======== SPEAR BALLISTIC SOLVER (Veil) ========
	-- fn29 versi Aeris: hitung sudut + waktu tempuh dari drag/gravitasi.
	NYB.ballistic = function(speed, gravity, horiz, height)
		local t = math.max(horiz, 0.1)
		local v2 = speed * speed
		local disc = v2 * v2 - gravity * (gravity * t * t + 2 * height * v2)
		if disc < 0 then disc = 0 end
		local s = (v2 - math.sqrt(disc)) / (gravity * t)
		local ang = math.atan(s)
		return ang, t / (speed * math.cos(ang))
	end

	--======== PERFECT LANDING ========
	-- Game set speedboost = 0.625 saat mendarat; kita naikkan jadi 1.4 selama 3 detik.
	NYB.setupPerfectLanding = function(on)
		if NYB.state.plConn then
			NYB.state.plConn:Disconnect()
			NYB.state.plConn = nil
		end
		if not on then return end
		local char = lp.Character
		if not char then return end
		NYB.state.plConn = char:GetAttributeChangedSignal("speedboost"):Connect(function()
			if not CFG.PerfectLanding then return end
			if char:GetAttribute("speedboost") == 0.625 and not NYB.state.plBoost then
				NYB.state.plBoost = true
				local until_ = tick() + 3
				task.spawn(function()
					while tick() < until_ and NYB.alive and CFG.PerfectLanding do
						pcall(function() char:SetAttribute("speedboost", 1.4) end)
						task.wait()
					end
					pcall(function() char:SetAttribute("speedboost", 1) end)
					NYB.state.plBoost = false
				end)
			end
		end)
	end

	--======== ADRENALINE RUSH ========
	-- Saat HP turun ke <= 50 dan masih > 0, speedboost 1.4 selama 5 detik.
	NYB.setupAdrenaline = function(on)
		if NYB.state.arConn then
			NYB.state.arConn:Disconnect()
			NYB.state.arConn = nil
		end
		if not on then return end
		local char = lp.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local last = hum.Health
		NYB.state.arConn = hum.HealthChanged:Connect(function(h)
			if not CFG.AdrenalineRush then return end
			local prev = last
			last = h
			if h < prev and h <= 50 and h > 0 and not NYB.state.arBoost then
				NYB.state.arBoost = true
				local until_ = tick() + 5
				task.spawn(function()
					while tick() < until_ and NYB.alive and CFG.AdrenalineRush do
						pcall(function() char:SetAttribute("speedboost", 1.4) end)
						task.wait()
					end
					pcall(function() char:SetAttribute("speedboost", 1) end)
					NYB.state.arBoost = false
				end)
			end
		end)
	end

	--======== STREAMER MODE ========
	-- Ganti semua nama pemain di teks GUI game jadi "NYB HUB".
	NYB.streamerMode = function(on)
		if NYB.state.smConns then
			for _, c in ipairs(NYB.state.smConns) do
				pcall(function() c:Disconnect() end)
			end
		end
		NYB.state.smConns = {}

		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return end

		local function scan(node)
			if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
				if not node:GetAttribute("NYB_OrigText") then
					node:SetAttribute("NYB_OrigText", node.Text)
				end
				local txt = node.Text
				local changed = false
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr ~= lp then
						if string.find(txt, plr.Name, 1, true) then
							txt = string.gsub(txt, plr.Name, CFG.FakeName)
							changed = true
						end
						if plr.DisplayName and plr.DisplayName ~= "" and string.find(txt, plr.DisplayName, 1, true) then
							txt = string.gsub(txt, plr.DisplayName, CFG.FakeName)
							changed = true
						end
					end
				end
				if changed and node.Text ~= txt then
					node.Text = txt
				end
			end
		end

		if not on then
			for _, d in ipairs(pg:GetDescendants()) do
				local orig = d:GetAttribute("NYB_OrigText")
				if orig then
					pcall(function() d.Text = orig end)
					pcall(function() d:SetAttribute("NYB_OrigText", nil) end)
				end
				local oi = d:GetAttribute("NYB_OrigImage")
				if oi then
					pcall(function() d.Image = oi end)
					pcall(function() d:SetAttribute("NYB_OrigImage", nil) end)
				end
			end
			return
		end

		for _, d in ipairs(pg:GetDescendants()) do
			scan(d)
		end
		table.insert(NYB.state.smConns, pg.DescendantAdded:Connect(function(d)
			task.defer(function()
				if CFG.StreamerMode then scan(d) end
			end)
		end))
		NYB.msg("Streamer mode ON — nama pemain diganti jadi '" .. CFG.FakeName .. "'.")
	end

	--======== COPY AVATAR ========
	NYB.applyAvatarOf = function(plr)
		if not plr then return end
		local char = lp.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then NYB.msg("Kamu belum spawn.") return end
		local ok = pcall(function()
			local desc = Players:GetHumanoidDescriptionFromUserId(plr.UserId)
			hum:ApplyDescription(desc)
		end)
		NYB.msg(ok and ("Avatar dicopy dari " .. plr.Name) or "Gagal copy avatar.")
	end

	NYB.randomAvatar = function()
		local list = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp then table.insert(list, p) end
		end
		if #list == 0 then NYB.msg("Tidak ada pemain lain.") return end
		NYB.applyAvatarOf(list[math.random(1, #list)])
	end

	--======== KORLESS MORPH ========
	NYB.korless = function(on)
		local char = lp.Character
		if not char then return end
		if not on then
			pcall(function()
				local m = char:FindFirstChild("KorlessHead")
				if m then m:Destroy() end
				if char:FindFirstChild("Head") then char.Head.Transparency = 0 end
				if char:FindFirstChild("Right Leg") then char["Right Leg"].Transparency = 0 end
			end)
			NYB.msg("Korless morph OFF.")
			return
		end
		local ok = pcall(function()
			char.Head.Transparency = 1
			local face = char.Head:FindFirstChild("face")
			if face then face:Destroy() end
			char["Right Leg"].Transparency = 1
			local mp = Instance.new("MeshPart")
			mp.Name = "KorlessHead"
			mp.Size = Vector3.new(0.85, 0.85, 0.85)
			mp.CanCollide = false
			mp.MeshId = "rbxassetid://902942096"
			mp.TextureID = "rbxassetid://902843398"
			mp.CFrame = char["Right Leg"].CFrame * CFrame.new(0, 0.7, 0)
			mp.Parent = char
			local w = Instance.new("WeldConstraint")
			w.Part0 = char["Right Leg"]
			w.Part1 = mp
			w.Parent = mp
		end)
		NYB.msg(ok and "Korless morph ON." or "Korless gagal (bentuk R15?)")
	end

	--======== 8 BIT CROWN (cosmetic) ========
	-- Port 1:1 dari asset katalog "8-Bit Royal Crown" (assetId 10159600649,
	-- milik akun Roblox). Isi file .rbxm-nya dibaca langsung:
	--   Part "Handle" + SpecialMesh   MeshId    rbxassetid://10138606900
	--                                 TextureId rbxassetid://10138606949
	--   ParticleEmitter "8bit_fire"   Texture   rbxassetid://10126369396
	--   Handle: Transparency 0, CanCollide false, ukuran nyaris nol.
	-- Game ini nge-morph karakter, jadi aksesori avatar bawaan nggak kelihatan
	-- -- makanya kita bangun ulang lokal lalu tempel ke Head pakai weld.
	local CROWN = {
		MESH = "rbxassetid://10138606900",
		TEX  = "rbxassetid://10138606949",
		VFX  = "rbxassetid://10126369396",
		TAG  = "NYB_Crown",
	}
	NYB.CROWN = CROWN

	local function crownChar(plr)
		plr = plr or lp
		local char = plr.Character
		return char, char and char:FindFirstChild("Head")
	end

	NYB.crownDrop = function(plr)
		local char = crownChar(plr)
		if not char then return end
		local old = char:FindFirstChild(CROWN.TAG)
		if old then pcall(function() old:Destroy() end) end
	end

	-- bangun + tempel. Aman dipanggil ulang (yang lama dihapus dulu).
	NYB.crownBuild = function(plr)
		local char, head = crownChar(plr)
		if not head then return false end
		NYB.crownDrop(plr)

		local scale = math.clamp(tonumber(CFG.CrownScale) or 1, 0.2, 4)
		local yoff  = tonumber(CFG.CrownYOff) or 0

		local handle = Instance.new("Part")
		handle.Name = CROWN.TAG
		handle.Size = Vector3.new(0.05, 0.05, 0.05)
		handle.Transparency = 0
		handle.CanCollide = false
		handle.Massless = true
		handle.Anchored = false
		pcall(function()
			handle.CanQuery = false
			handle.CanTouch = false
		end)

		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.MeshId = CROWN.MESH
		mesh.TextureId = CROWN.TEX
		mesh.Offset = Vector3.new(0, 0, 0)
		mesh.Scale = Vector3.new(scale, scale, scale)
		mesh.Parent = handle

		local att = Instance.new("Attachment")
		att.Name = "HatAttachment"
		att.Parent = handle

		if CFG.CrownVfx then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "8bit_fire"
			pe.Texture = CROWN.VFX
			pe.LockedToPart = true
			pe.LightEmission = 1
			pe.Rate = 14
			pe.Lifetime = NumberRange.new(0.35, 0.6)
			pe.Speed = NumberRange.new(0.4, 1.2)
			pe.Size = NumberSequence.new(0.3)
			pe.Transparency = NumberSequence.new(0.2)
			pe.Rotation = NumberRange.new(-90, 90)
			pe.RotSpeed = NumberRange.new(-60, 60)
			pe.Parent = handle
		end

		-- taruh tepat di atas ubun-ubun, lalu kunci relatif ke Head
		handle.CFrame = head.CFrame * CFrame.new(0, head.Size.Y * 0.5 + yoff, 0)
		handle.Parent = char
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = handle
		weld.Parent = handle
		return true
	end

	NYB.crown = function(on)
		CFG.CrownOn = on
		if not on then
			NYB.crownDrop(lp)
			NYB.msg("8 Bit Crown OFF.")
			return
		end
		local ok = NYB.crownBuild(lp)
		NYB.msg(ok and "8 Bit Crown ON -- nempel di kepala."
			or "8 Bit Crown gagal: karakter/Head belum ada.")
	end

	-- dipakai slider + toggle VFX: bangun ulang tanpa nginjak switch utama
	NYB.crownRefresh = function()
		if not CFG.CrownOn then return end
		if not NYB.crownBuild(lp) then
			NYB.msg("8 Bit Crown: Head belum ada (tunggu spawn).")
		end
	end

	--======== COUNTER / ANTI PARRY (killer) ========
	NYB.counterParry = function(on)
		NYB.state.cpOn = on
		if not on or NYB.state.cpThread then return end
		NYB.state.cpThread = task.spawn(function()
			local cpTrack
			while NYB.alive and NYB.state.cpOn do
				local char = lp.Character
				if char and NYB.role(lp) == "Killer" and not cpTrack then
					pcall(function()
						local hum = char:FindFirstChildOfClass("Humanoid")
						local anim = hum and hum:FindFirstChildOfClass("Animator")
						if anim then
							local a = Instance.new("Animation")
							a.AnimationId = "rbxassetid://117042998468241"
							cpTrack = anim:LoadAnimation(a)
						end
					end)
				end
				if cpTrack then
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					local close = false
					if hrp then
						for _, plr in ipairs(Players:GetPlayers()) do
							if plr ~= lp and not NYB.isKiller(plr) then
								local c2 = plr.Character
								local h2 = c2 and c2:FindFirstChild("HumanoidRootPart")
								if h2 and (hrp.Position - h2.Position).Magnitude <= CFG.CounterParryDist then
									close = true
									break
								end
							end
						end
					end
					if close then
						pcall(function()
							cpTrack:Play()
							cpTrack:AdjustWeight(0)
						end)
						task.wait(0.05)
						pcall(function() cpTrack:Stop() end)
					end
				end
				task.wait(CFG.CounterParryRate)
			end
			NYB.state.cpThread = nil
		end)
	end

	--======== INFINITE CORRUPT (Abysswalker) ========
	NYB.infCorrupt = function(on)
		NYB.state.icOn = on
		if not on or NYB.state.icThread then return end
		NYB.state.icThread = task.spawn(function()
			while NYB.alive and NYB.state.icOn do
				if NYB.role(lp) == "Killer" then
					pcall(function()
						if R.abyssCorrupt then R.abyssCorrupt:FireServer() end
					end)
				end
				task.wait(0.5)
			end
			NYB.state.icThread = nil
		end)
	end

	--======== DASH LOCK -- camera aim-lock ke survivor terdekat ============
	-- Trigger: klik kanan (PC) / keybind V / tombol move2 (mobile) / tombol NYB HUB.
	-- Efek: kamera ngunci + lerp ke HRP survivor terdekat. Bukan lewat remote,
	-- jadi tidak ada arg yang dikirim ke server -- murni kontrol kamera lokal.
	local DS = { locking = false, target = nil, timer = nil, last = 0 }
	NYB.dashState = DS

	local function dsDowned(char)
		if not char then return true end
		if char:GetAttribute("Knocked") == true then return true end
		if char:GetAttribute("IsHooked") == true then return true end
		local h = char:FindFirstChildOfClass("Humanoid")
		if h and h.Health <= 0 then return true end
		return false
	end

	local function dsClosest()
		local hrp = NYB.hrp()
		if not hrp then return nil end
		local best, bd = nil, math.huge
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= lp and NYB.role(p) == "Survivor" then
				local c = p.Character
				local thrp = c and c:FindFirstChild("HumanoidRootPart")
				if thrp and not dsDowned(c) then
					local d = (thrp.Position - hrp.Position).Magnitude
					if d < bd then bd = d; best = c end
				end
			end
		end
		if best and CFG.DashLockDist > 0 and bd > CFG.DashLockDist then return nil end
		return best, bd
	end

	--======== tombol mobile (tap = lock, tahan-geser = pindah posisi) ========
	local function dsUpdateBtn()
		if not DS.btn then return end
		if DS.locking then
			DS.btn.Text = "DASH LOCK [LOCK]"
			DS.btn.TextColor3 = Color3.fromRGB(180, 255, 180)
		elseif CFG.DashLock then
			DS.btn.Text = "DASH LOCK [ON]"
			DS.btn.TextColor3 = Color3.fromRGB(235, 235, 235)
		else
			DS.btn.Text = "DASH LOCK [OFF]"
			DS.btn.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end

	local function dsGuiMake()
		if DS.gui then return end
		local parent = (type(gethui) == "function" and gethui()) or lp:FindFirstChild("PlayerGui")
		if not parent then return end
		local g = Instance.new("ScreenGui")
		g.Name = "NYB_DashLock"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = 500
		g.Parent = parent

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromOffset(124, 34)
		frame.Position = UDim2.fromScale(0.72, 0.68)
		frame.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
		frame.BackgroundTransparency = 0.1
		frame.BorderSizePixel = 0
		frame.Active = true
		frame.Parent = g
		local c1 = Instance.new("UICorner"); c1.CornerRadius = UDim.new(0, 8); c1.Parent = frame
		local st = Instance.new("UIStroke")
		st.Color = CFG.Accent; st.Thickness = 1.5; st.Transparency = 0.3; st.Parent = frame

		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, 0, 1, 0)
		b.BackgroundTransparency = 1
		b.Text = "DASH LOCK [OFF]"
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.TextColor3 = Color3.fromRGB(150, 150, 150)
		b.AutoButtonColor = false
		b.Parent = frame
		DS.btn, DS.gui = b, g

		local dragging, dragMoved, canDrag = false, false, false
		local dragStart, startPos, hold = nil, nil, nil
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging, dragMoved, canDrag = true, false, false
				dragStart, startPos = input.Position, frame.Position
				if hold then task.cancel(hold) end
				hold = task.delay(0.18, function() if dragging then canDrag = true end end)
			end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if hold then task.cancel(hold) end
				if dragging and not dragMoved then NYB.dashTrigger() end
				dragging, dragMoved, canDrag = false, false, false
			end
		end)
		UIS.InputChanged:Connect(function(input)
			if dragging and canDrag and (input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseMovement) then
				local d = input.Position - dragStart
				if not dragMoved and (math.abs(d.X) > 16 or math.abs(d.Y) > 16) then dragMoved = true end
				if dragMoved then
					frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
						startPos.Y.Scale, startPos.Y.Offset + d.Y)
				end
			end
		end)
		table.insert(NYB.cleanups, function() pcall(function() g:Destroy() end) end)
	end

	--======== trigger (dipanggil dari input / tombol) ========
	NYB.dashTrigger = function()
		if not CFG.DashLock then return end
		if tick() - DS.last < 0.2 then return end
		DS.last = tick()
		if NYB.role(lp) ~= "Killer" then
			NYB.msg("Dash Lock cuma jalan saat kamu Killer.")
			return
		end
		local t, d = dsClosest()
		if not t then
			NYB.msg("Dash Lock: tidak ada survivor dalam jangkauan.")
			return
		end
		DS.target, DS.locking = t, true
		if DS.timer then task.cancel(DS.timer) end
		if not CFG.DashLockHold then
			DS.timer = task.delay(math.max(0.1, CFG.DashLockTime), function()
				DS.locking, DS.target, DS.timer = false, nil, nil
				dsUpdateBtn()
			end)
		end
		dsUpdateBtn()
	end

	--======== step per-frame (dipanggil dari RenderStepped) ========
	NYB.dashStep = function()
		if not CFG.DashLock then
			if DS.locking then DS.locking, DS.target = false, nil; dsUpdateBtn() end
			return
		end
		if CFG.DashLockHold and NYB.role(lp) == "Killer"
			and (not DS.locking or not DS.target or not DS.target.Parent) then
			local t = dsClosest()
			if t then DS.target, DS.locking = t, true; dsUpdateBtn() end
		end
		if DS.locking and DS.target then
			local thrp = DS.target.Parent and DS.target:FindFirstChild("HumanoidRootPart")
			if thrp then
				cam.CFrame = cam.CFrame:Lerp(
					CFrame.lookAt(cam.CFrame.Position, thrp.Position),
					math.clamp(CFG.DashLockSmooth, 0.05, 1))
			else
				DS.locking, DS.target = false, nil
				dsUpdateBtn()
			end
		end
	end

	NYB.dashLock = function(on)
		CFG.DashLock = on
		if not on then
			DS.locking, DS.target = false, nil
			if DS.timer then task.cancel(DS.timer); DS.timer = nil end
			if DS.gui then DS.gui.Enabled = false end
			dsUpdateBtn()
			return
		end
		if not NYB.state.dashSetup then
			NYB.state.dashSetup = true
			-- PC: klik kanan + keybind
			NYB.bind(UIS.InputBegan, function(input, gp)
				if gp or not CFG.DashLock then return end
				if input.UserInputType == Enum.UserInputType.MouseButton2 then NYB.dashTrigger() end
				if input.KeyCode == CFG.DashLockKey then NYB.dashTrigger() end
			end)
			-- Mobile: pantau tombol move2 milik game (sama seperti PANDU)
			if UIS.TouchEnabled then
				task.spawn(function()
					local conn, last = nil, nil
					while NYB.alive do
						task.wait(1)
						if CFG.DashLock then
							pcall(function()
								local pg = lp:FindFirstChild("PlayerGui")
								local hm = pg and pg:FindFirstChild("Hidden-mob")
								local ctrl = hm and hm:FindFirstChild("Controls")
								local mv = ctrl and ctrl:FindFirstChild("move2")
								if mv and mv ~= last then
									if conn then conn:Disconnect() end
									last = mv
									conn = mv.InputBegan:Connect(function(i)
										if i.UserInputType == Enum.UserInputType.Touch
											or i.UserInputType == Enum.UserInputType.MouseButton1 then
											NYB.dashTrigger()
										end
									end)
								end
							end)
						end
					end
				end)
			end
		end
		if CFG.DashLockBtn and UIS.TouchEnabled then
			dsGuiMake()
			if DS.gui then DS.gui.Enabled = true end
		elseif DS.gui then
			DS.gui.Enabled = false
		end
		dsUpdateBtn()
		NYB.msg("Dash Lock ON -- klik kanan (PC) / tombol V / tap DASH LOCK buat kunci.")
	end

	--======== MASK GUI -- buka GUI milik game sendiri ========
	NYB.maskGui = function(on)
		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return end
		local found = false
		for _, d in ipairs(pg:GetDescendants()) do
			local n = string.lower(d.Name)
			if (string.find(n, "mask", 1, true) or string.find(n, "select", 1, true))
				and (d:IsA("ScreenGui") or d:IsA("Frame")) then
				if not d:GetAttribute("NYB_OrigVisible") then
					d:SetAttribute("NYB_OrigVisible", d.Visible)
				end
				pcall(function() d.Visible = on and true or (d:GetAttribute("NYB_OrigVisible") or false) end)
				found = true
			end
		end
		NYB.msg(found and ("Mask GUI " .. (on and "dibuka" or "ditutup")) or "GUI mask game tidak ketemu (kamu bukan The Masked?).")
	end

	--======== INSTANT ESCAPE ========
	NYB.instantEscape = function()
		local hrp = NYB.hrp()
		if not hrp then return end
		local found = nil
		for _, d in ipairs(workspace:GetDescendants()) do
			-- nama part di game memang typo: "fininshline"
			if d:IsA("BasePart") and string.lower(d.Name) == "fininshline" then
				found = d
				break
			end
		end
		if not found then
			NYB.msg("Finish line tidak ketemu.")
			return
		end
		hrp.CFrame = found.CFrame + Vector3.new(0, 5, 0)
		NYB.msg("Instant escape: teleport ke finish line.")
	end

	--======== SKIP ENDSCREEN ========
	NYB.skipEndscreen = function(on)
		NYB.state.skipEnd = on
		if not on or NYB.state.skipThread then return end
		NYB.state.skipThread = task.spawn(function()
			while NYB.alive and NYB.state.skipEnd do
				pcall(function()
					local pg = lp:FindFirstChild("PlayerGui")
					local res = pg and pg:FindFirstChild("Results")
					if res then res:Destroy() end
					local map = workspace:FindFirstChild("Map")
					if map then
						local es = map:FindFirstChild("endscreen", true)
						if es then
							for _, d in ipairs(es:GetDescendants()) do
								if d:IsA("LocalScript") then d.Disabled = true end
							end
							es:Destroy()
						end
					end
				end)
				task.wait(0.5)
			end
			NYB.state.skipThread = nil
		end)
	end
end

--===================== [ 9f. ITEM USER (generik) ] ========================
-- Fire remote item apa pun dari Remotes.Items / Backpack tanpa hardcode
-- satu-satu. Buat item yang belum ada di resolver (contoh: "8 Bit Crown").
-- Nama dicocokkan setelah dinormalisasi: huruf kecil, spasi / _ / - / . dibuang,
-- jadi "8 Bit Crown", "8BitCrown", "8-bit-crown" semuanya kena.
do
	local R = NYB.remotes

	local function norm(x)
		return (tostring(x):lower():gsub("[%s_%-%./]", ""))
	end
	NYB.itemNorm = norm

	-- kandidat node item: Remotes.Items.<X>, Backpack, dan tool yang lagi dipegang
	local function candidates()
		local out = {}
		local items = R.root and R.root:FindFirstChild("Items")
		if items then
			for _, c in ipairs(items:GetChildren()) do
				table.insert(out, { name = c.Name, node = c, where = "Remotes.Items" })
			end
		end
		local pack = lp:FindFirstChild("Backpack")
		if pack then
			for _, c in ipairs(pack:GetChildren()) do
				if c:IsA("Tool") then
					table.insert(out, { name = c.Name, node = c, where = "Backpack" })
				end
			end
		end
		local char = lp.Character
		if char then
			for _, c in ipairs(char:GetChildren()) do
				if c:IsA("Tool") then
					table.insert(out, { name = c.Name, node = c, where = "Equipped" })
				end
			end
		end
		return out
	end
	NYB.itemCandidates = candidates

	local function remotesOf(node)
		local out = {}
		if not node then return out end
		for _, d in ipairs(node:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
				table.insert(out, d)
			end
		end
		return out
	end
	NYB.itemRemotes = remotesOf

	-- exact match dulu, baru substring dua arah
	NYB.itemFind = function()
		local want = norm(CFG.UseItemName or "")
		if want == "" then return nil end
		local list = candidates()
		for _, c in ipairs(list) do
			if norm(c.name) == want then return c end
		end
		for _, c in ipairs(list) do
			local k = norm(c.name)
			if string.find(k, want, 1, true) or string.find(want, k, 1, true) then return c end
		end
		return nil
	end

	NYB.itemNames = function()
		local seen, out = {}, {}
		for _, c in ipairs(candidates()) do
			local k = norm(c.name)
			if not seen[k] then seen[k] = true; table.insert(out, c.name) end
		end
		table.sort(out)
		return out
	end

	NYB.itemCycle = function()
		local names = NYB.itemNames()
		if #names == 0 then
			NYB.msg("Item tidak ketemu (Backpack & Remotes.Items kosong).")
			return nil
		end
		local cur, idx = norm(CFG.UseItemName or ""), 0
		for i, n in ipairs(names) do
			if norm(n) == cur then idx = i break end
		end
		local pick = names[(idx % #names) + 1]
		CFG.UseItemName = pick
		NYB.msg("Item dipilih: " .. pick)
		return pick
	end

	NYB.itemDump = function()
		local lines = { "NYB HUB - ITEM DUMP  (PlaceId " .. tostring(game.PlaceId) .. ")" }
		local list = candidates()
		if #list == 0 then table.insert(lines, "(tidak ada item di Remotes.Items / Backpack)") end
		for _, c in ipairs(list) do
			local rn = {}
			for _, r in ipairs(remotesOf(c.node)) do
				table.insert(rn, r.Name .. "[" .. r.ClassName .. "]")
			end
			table.insert(lines, string.format("%-24s %-14s remotes: %s",
				c.name, c.where, #rn > 0 and table.concat(rn, ", ") or "-"))
		end
		local text = table.concat(lines, "\n")
		pcall(function() setclipboard(text) end)
		print(text)
		NYB.msg(string.format("%d item di-dump ke clipboard.", #list))
		return text
	end

	NYB.useItemStep = function()
		if not CFG.UseItem then return end
		if CFG.UseItemName == nil or CFG.UseItemName == "" then return end
		local hum = NYB.hum()
		if not hum or hum.Health <= 0 then return end
		local now = tick()
		if NYB.state.lastItem and now - NYB.state.lastItem < math.max(0.1, tonumber(CFG.UseItemRate) or 0.5) then
			return
		end

		local c = NYB.itemFind()
		if not c then
			if NYB.state.itemMiss ~= CFG.UseItemName then
				NYB.state.itemMiss = CFG.UseItemName
				NYB.msg("Item \"" .. tostring(CFG.UseItemName) .. "\" tidak ketemu - tekan Ganti Item / Scan Item.")
			end
			return
		end
		NYB.state.itemMiss = nil

		-- kalau masih di backpack, pegang dulu
		if CFG.UseItemEquip and c.where == "Backpack" then
			pcall(function() hum:EquipTool(c.node) end)
			c = NYB.itemFind() or c
		end

		local rs = remotesOf(c.node)
		if #rs == 0 then
			-- node-nya tool di backpack; remote aslinya ada di Remotes.Items dengan nama sama
			local items = R.root and R.root:FindFirstChild("Items")
			local mirror = items and items:FindFirstChild(c.name)
			rs = remotesOf(mirror)
		end
		if #rs == 0 then
			if NYB.state.itemNoRemote ~= c.name then
				NYB.state.itemNoRemote = c.name
				NYB.msg("Item \"" .. c.name .. "\" ketemu tapi tidak punya remote - tekan Scan Item.")
			end
			NYB.state.lastItem = now
			return
		end

		NYB.state.lastItem = now
		for _, r in ipairs(rs) do
			pcall(function()
				if r:IsA("RemoteEvent") then
					r:FireServer()
				else
					r:InvokeServer()
				end
			end)
		end
	end
end

--===================== [ 10. MOVEMENT ] ===================================
do
	local moveBV, moveBG

	NYB.tpTo = function(pos)
		local hrp = NYB.hrp()
		if not hrp or not pos then return end
		if CFG.SmoothTp then
			local dist = (hrp.Position - pos).Magnitude
			local t = math.clamp(dist / 220, 0.05, CFG.SmoothTpTime)
			local tw = TweenService:Create(hrp, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos) })
			tw:Play()
		else
			hrp.CFrame = CFrame.new(pos)
		end
	end

	NYB.setSpeed = function(v)
		local char = lp.Character
		local hum = NYB.hum()
		if hum then
			pcall(function() hum.WalkSpeed = v end)
		end
		if char then
			pcall(function() char:SetAttribute("speedboost", v / 16) end)
		end
	end

	NYB.flyToggle = function(on)
		local hrp = NYB.hrp()
		if not on then
			if moveBV then moveBV:Destroy(); moveBV = nil end
			if moveBG then moveBG:Destroy(); moveBG = nil end
			return
		end
		if not hrp then return end
		moveBV = Instance.new("BodyVelocity")
		moveBV.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		moveBV.Velocity = Vector3.zero
		moveBV.Parent = hrp
		moveBG = Instance.new("BodyGyro")
		moveBG.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		moveBG.P = 9e4
		moveBG.Parent = hrp
	end

	NYB.flyStep = function()
		if not CFG.Fly or not moveBV or not moveBG then return end
		local hrp = NYB.hrp()
		if not hrp then return end
		if moveBV.Parent ~= hrp then
			moveBV.Parent = hrp
			moveBG.Parent = hrp
		end
		local dir = Vector3.zero
		if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
		if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
		if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
		moveBV.Velocity = dir.Magnitude > 0 and dir.Unit * CFG.FlySpeed or Vector3.zero
		moveBG.CFrame = cam.CFrame
	end

	NYB.noclipStep = function()
		if not CFG.Noclip then return end
		local char = lp.Character
		if not char then return end
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false end
		end
	end
end

--===================== [ 11. VISUAL + REMOTE LOG ] ========================
do
	local origLighting = {
		Brightness = Lighting.Brightness,
		FogEnd = Lighting.FogEnd,
		GlobalShadows = Lighting.GlobalShadows,
		ClockTime = Lighting.ClockTime,
		Ambient = Lighting.Ambient,
	}

	NYB.applyVisual = function()
		pcall(function()
			if CFG.Fullbright then
				Lighting.Brightness = 3
				Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(178, 178, 178)
			else
				Lighting.Brightness = origLighting.Brightness
				Lighting.GlobalShadows = origLighting.GlobalShadows
				Lighting.Ambient = origLighting.Ambient
			end
			if CFG.NoFog then
				Lighting.FogEnd = 100000
			else
				Lighting.FogEnd = origLighting.FogEnd
			end
			if CFG.TimeOfDay >= 0 then
				Lighting.ClockTime = CFG.TimeOfDay
			else
				Lighting.ClockTime = origLighting.ClockTime
			end
		end)
	end

	NYB.applyFov = function()
		pcall(function()
			if not cam then return end
			if CFG.CameraFov and CFG.CameraFov > 0 then
				cam.FieldOfView = CFG.CameraFov
			end
		end)
	end

	NYB.antiFlashStep = function()
		if not CFG.AntiFlash then return end
		local pg = lp:FindFirstChild("PlayerGui")
		if not pg then return end
		for _, d in ipairs(pg:GetDescendants()) do
			local n = string.lower(d.Name)
			if (string.find(n, "flash", 1, true) or string.find(n, "blind", 1, true))
				and (d:IsA("Frame") or d:IsA("ImageLabel") or d:IsA("TextLabel")) then
				if d.Visible then d.Visible = false end
			end
		end
	end

	NYB.remoteLog = function(on)
		if not on then return end
		if NYB.state.logging then return end
		NYB.state.logging = true
		local lines = {}
		pcall(function()
			local mt = getrawmetatable(game)
			local old = mt.__namecall
			setreadonly(mt, false)
			mt.__namecall = newcclosure(function(self, ...)
				local m = getnamecallmethod()
				if (m == "FireServer" or m == "InvokeServer") and not checkcaller() then
					local args = { ... }
					local parts = {}
					for i = 1, math.min(#args, 4) do
						parts[i] = tostring(args[i]) .. "(" .. typeof(args[i]) .. ")"
					end
					local line = string.format("[%s] %s %s", m, self:GetFullName(), table.concat(parts, ", "))
					table.insert(lines, line)
					if #lines > 300 then table.remove(lines, 1) end
					if CFG.RemoteLog then print("[NYB HUB-RE] " .. line) end
				end
				return old(self, ...)
			end)
			setreadonly(mt, true)
		end)
		NYB.state.logLines = lines
		NYB.msg("Remote logger aktif (lihat tab Misc untuk dump).")
	end
end

--===================== [ 12. SELF TEST + UNLOAD ] =========================
do
	NYB.selfTest = function()
		local out = {}
		local function line(k, ok, detail)
			table.insert(out, string.format("%-22s %s  %s", k, ok and "OK " or "FAIL", detail or ""))
		end

		line("PlaceId", true, tostring(game.PlaceId))
		line("Remotes root", NYB.remotes.root ~= nil, NYB.remotes.root and NYB.remotes.root:GetFullName() or "tidak ketemu")
		line("Generator.RepairEvent", NYB.remotes.genRepair ~= nil, tostring(NYB.remotes.genRepair))
		line("Generator.SkillCheckEvent", NYB.remotes.genSkill ~= nil, tostring(NYB.remotes.genSkill))
		line("Generator.ResultEvent", NYB.remotes.genResult ~= nil, tostring(NYB.remotes.genResult))
		line("Parrying Dagger.parry", NYB.remotes.parry ~= nil, tostring(NYB.remotes.parry))
		line("Healing.HealEvent", NYB.remotes.heal ~= nil, tostring(NYB.remotes.heal))
		line("Pallet.DropEvent", NYB.remotes.palletDrop ~= nil, tostring(NYB.remotes.palletDrop))
		line("Window.VaultEvent", NYB.remotes.vault ~= nil, tostring(NYB.remotes.vault))
		line("Carry.SelfUnHookEvent", NYB.remotes.selfUnhook ~= nil, tostring(NYB.remotes.selfUnhook))
		line("Exit.LeverEvent", NYB.remotes.leverEvent ~= nil, tostring(NYB.remotes.leverEvent))
		line("Attacks.BasicAttack", NYB.remotes.basicAttack ~= nil, tostring(NYB.remotes.basicAttack))
		line("Attacks.Lunge", NYB.remotes.lunge ~= nil, tostring(NYB.remotes.lunge))
		line("Collision.Disable", NYB.remotes.colOff ~= nil, tostring(NYB.remotes.colOff))
		line("Mechanics.ChangeAttribute", NYB.remotes.mechAttr ~= nil, tostring(NYB.remotes.mechAttr))
		line("Generator.BreakGenEvent", NYB.remotes.genBreak ~= nil, tostring(NYB.remotes.genBreak))
		line("Healing.SkillCheckResult", NYB.remotes.healResult ~= nil, tostring(NYB.remotes.healResult))

		local char = lp.Character
		local hrp = NYB.hrp()
		line("Character/HRP", char ~= nil and hrp ~= nil, char and char:GetFullName() or "-")
		line("Role", true, NYB.role(lp))
		line("Humanoid", NYB.hum() ~= nil, NYB.hum() and tostring(math.floor(NYB.hum().Health)) or "-")
		line("speedboost attr", char and char:GetAttribute("speedboost") ~= nil, tostring(char and char:GetAttribute("speedboost")))

		local C = NYB.cache
		line("Scan root", true, tostring(C.scanRoot or "belum scan"))
		line("Generators scan", true, string.format("%d model (0 = lobby/map belum load)", #(C.genList or {})))
		local left = 0
		for _, g in ipairs(C.genList or {}) do
			if not NYB.genDone(g) then left = left + 1 end
		end
		line("Generators belum jadi", true, string.format("%d dari %d", left, #(C.genList or {})))
		line("Hooks scan", true, string.format("%d model", #(C.hookList or {})))
		line("Pallets scan", true, string.format("%d model", #(C.palletList or {})))
		line("Windows scan", true, string.format("%d model", #(C.windowList or {})))
		line("Gates scan", true, string.format("%d model", #(C.gateList or {})))
		line("Dagger di backpack", true, tostring((lp:FindFirstChild("Backpack") and lp.Backpack:FindFirstChild("Parrying Dagger")) ~= nil))

		line("ESP objects", true, tostring(NYB.esp.count or 0))
		line("Hook terpasang", true, NYB.state.hooked and "aktif" or "belum (butuh toggle Auto Perfect Skillcheck)")
		line("Remote log lines", true, tostring(#(NYB.state.logLines or {})))

		local on = {}
		for k, v in pairs(CFG) do
			if type(v) == "boolean" and v and string.find(k, "^Esp") == nil then
				table.insert(on, k)
			end
		end
		table.sort(on)
		line("Fitur ON", true, table.concat(on, ", "))

		local head = string.format("NYB HUB SELF TEST  (PlaceId %d)\n", game.PlaceId)
		local body = table.concat(out, "\n")
		local tail = string.format("\nVERDICT: %d/%d baris OK\n", #out, #out)
		local report = head .. body .. tail

		print(report)
		warn(report)
		pcall(function() setclipboard(report) end)
		NYB.msg("Self test selesai, hasil dicopy ke clipboard.")
		return report
	end

	NYB.unload = function()
		NYB.alive = false
		for _, c in ipairs(NYB.conns) do
			pcall(function() c:Disconnect() end)
		end
		NYB.conns = {}
		for _, fn in ipairs(NYB.cleanups) do
			pcall(fn)
		end
		NYB.esp.clear()
		pcall(NYB.stopRepair)
		pcall(function() NYB.flyToggle(false) end)
		pcall(function() NYB.ui.gui:Destroy() end)
		NYB_ENV.NYB_HUB_RUNNING = nil
		print("[NYB HUB] Unloaded.")
	end
end

--===================== [ 13. UI BUILD ] ===================================
do
	local U = NYB.ui
	local C = NYB.cache

	local T = {}
	T.main = U.createTab("Main", "Main")
	T.esp  = U.createTab("ESP", "ESP")
	T.aim  = U.createTab("Aim", "Aim")
	T.auto = U.createTab("Auto", "Auto")
	T.combat = U.createTab("Combat", "Fight")
	T.move = U.createTab("Movement", "Move")
	T.vis  = U.createTab("Visual", "Vis")
	T.tp   = U.createTab("Teleport", "TP")
	T.misc = U.createTab("Misc", "Misc")

	--======== MAIN ========
	U.section(T.main.page, "Preset")
	U.button(T.main.page, "Survivor Preset (Auto Gen + ESP)", function()
		NYB.setCfg("EspPlayers", true)
		NYB.setCfg("EspGens", true)
		NYB.setCfg("EspGates", true)
		NYB.setCfg("AutoRepair", true)
		NYB.setCfg("GenPerfect", true)
		NYB.setCfg("GenFailSafe", true)
		NYB.setCfg("AutoHeal", true)
		NYB.setCfg("AutoSelfUnhook", true)
		NYB.setCfg("AutoParry", true)
		NYB.installHook()
		NYB.msg("Preset Survivor aktif.")
	end)
	U.button(T.main.page, "Killer Preset (Kill Aura + ESP + Speed)", function()
		NYB.setCfg("EspPlayers", true)
		NYB.setCfg("EspGates", true)
		NYB.setCfg("SpeedEnabled", true)
		NYB.setCfg("AntiFlash", true)
		NYB.setCfg("KillAura", true)
		NYB.setCfg("BreakGen", true)
		NYB.setCfg("DashLock", true)
		NYB.dashLock(true)
		NYB.msg("Preset Killer aktif (Dash Lock siap: klik kanan / V).")
	end)
	U.button(T.main.page, "Matikan Semua Fitur", function()
		for k, v in pairs(CFG) do
			if type(v) == "boolean" and not string.find(k, "^Esp") and k ~= "GenFailSafe"
				and k ~= "AutoEquipDagger" and k ~= "AttackFace" and k ~= "SmoothTp"
				and k ~= "ShowStats" and k ~= "EspChams" and k ~= "EspName" and k ~= "EspRole"
				and k ~= "EspDist" and k ~= "EspTool" and k ~= "EspHealth" and k ~= "EspAliveOnly" then
				NYB.setCfg(k, false)
			end
		end
		pcall(NYB.stopRepair)
		NYB.dashLock(false)
		NYB.msg("Semua fitur OFF.")
	end)

	U.section(T.main.page, "Session")
	U.button(T.main.page, "Self Test (copy ke clipboard)", NYB.selfTest)
	U.button(T.main.page, "Scan Ulang Map", function()
		NYB.scan()
		NYB.msg(string.format("Scan: %d generator, %d hook, %d pallet, %d window, %d gate",
			#(C.genList or {}), #(C.hookList or {}), #(C.palletList or {}), #(C.windowList or {}), #(C.gateList or {})))
	end)
	U.button(T.main.page, "Dump Remote (clipboard)", function()
		local all = {}
		local root = ReplicatedStorage:FindFirstChild("Remotes")
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
					table.insert(all, d:GetFullName() .. "  [" .. d.ClassName .. "]")
				end
			end
		end
		local text = table.concat(all, "\n")
		pcall(function() setclipboard(text) end)
		print(text)
		NYB.msg(string.format("%d remote dicopy ke clipboard.", #all))
	end)
	U.button(T.main.page, "Unload Script", NYB.unload)

	--======== ESP ========
	U.section(T.esp.page, "Pemain")
	U.toggle(T.esp.page, "ESP Pemain", "EspPlayers", function(v)
		CFG.EspPlayers = v
		-- kalau semua sub-option mati, nyalakan set dasar biar ESP-nya kelihatan
		if v and not (CFG.EspChams or CFG.EspName or CFG.EspRole or CFG.EspDist or CFG.EspHealth) then
			NYB.setCfg("EspChams", true)
			NYB.setCfg("EspName", true)
			NYB.setCfg("EspRole", true)
			NYB.setCfg("EspDist", true)
			NYB.setCfg("EspHealth", true)
			NYB.msg("Sub-option ESP dinyalakan otomatis (Chams / Nama / Role / Jarak / HP).")
		end
	end)
	U.toggle(T.esp.page, "Chams (Highlight)", "EspChams", function(v) CFG.EspChams = v end)
	U.toggle(T.esp.page, "Box", "EspBox", function(v) CFG.EspBox = v end)
	U.toggle(T.esp.page, "Nama", "EspName", function(v) CFG.EspName = v end)
	U.toggle(T.esp.page, "Role Tag", "EspRole", function(v) CFG.EspRole = v end)
	U.toggle(T.esp.page, "Jarak", "EspDist", function(v) CFG.EspDist = v end)
	U.toggle(T.esp.page, "Item / Killer", "EspTool", function(v) CFG.EspTool = v end)
	U.toggle(T.esp.page, "HP", "EspHealth", function(v) CFG.EspHealth = v end)
	U.toggle(T.esp.page, "Hanya Hidup", "EspAliveOnly", function(v) CFG.EspAliveOnly = v end)

	U.section(T.esp.page, "Objek Map")
	U.toggle(T.esp.page, "Generator (%)", "EspGens", function(v) CFG.EspGens = v end)
	U.toggle(T.esp.page, "Gate / Exit", "EspGates", function(v) CFG.EspGates = v end)
	U.toggle(T.esp.page, "Hook", "EspHooks", function(v) CFG.EspHooks = v end)
	U.toggle(T.esp.page, "Pallet", "EspPallets", function(v) CFG.EspPallets = v end)
	U.toggle(T.esp.page, "Window / Vault", "EspWindows", function(v) CFG.EspWindows = v end)

	U.section(T.esp.page, "Lain")
	U.slider(T.esp.page, "Jarak Maks ESP", 100, 3000, CFG.EspMaxDist, 0, function(v) CFG.EspMaxDist = v end)
	U.toggle(T.esp.page, "Alarm Killer Dekat", "KillerAlert", function(v) CFG.KillerAlert = v end)
	U.slider(T.esp.page, "Radius Alarm", 20, 300, CFG.AlertDist, 0, function(v) CFG.AlertDist = v end)

	--======== AIM ========
	U.section(T.aim.page, "Aimbot")
	U.toggle(T.aim.page, "Aimbot (saat Survivor)", "AimSurvivor", function(v)
		CFG.AimSurvivor = v
		if v then NYB.msg("Aimbot survivor ON — ngunci killer.") end
	end)
	U.toggle(T.aim.page, "Aimbot (saat Killer)", "AimKiller", function(v)
		CFG.AimKiller = v
		if v then NYB.msg("Aimbot killer ON — ngunci survivor terdekat.") end
	end)
	U.slider(T.aim.page, "FOV Radius (survivor)", 20, 500, CFG.AimRadius, 0, function(v) CFG.AimRadius = v end)
	U.slider(T.aim.page, "Max Distance (survivor)", 30, 1000, CFG.AimMaxDist, 0, function(v) CFG.AimMaxDist = v end)
	U.slider(T.aim.page, "Max Distance (killer)", 5, 60, CFG.AimKillerDist, 0, function(v) CFG.AimKillerDist = v end)
	U.slider(T.aim.page, "Smoothness (0.05-1)", 0.05, 1, CFG.AimSmooth, 2, function(v) CFG.AimSmooth = v end)
	U.slider(T.aim.page, "Predict", 0, 0.1, CFG.AimPredict, 3, function(v) CFG.AimPredict = v end)
	U.toggle(T.aim.page, "Tampilkan FOV Circle", "AimShowFov", function(v) CFG.AimShowFov = v end)
	U.toggle(T.aim.page, "Wall Check", "AimWallCheck", function(v) CFG.AimWallCheck = v end)
	U.label(T.aim.page, "Target part: " .. CFG.AimPart .. " (Torso default)", NYB.ui.colors.dim)

	U.section(T.aim.page, "Silent Aim")
	U.toggle(T.aim.page, "Silent Aim Flashlight", "SilentFlash", function(v) CFG.SilentFlash = v end)
	U.toggle(T.aim.page, "Silent Aim Twist of Fate", "SilentToF", function(v)
		CFG.SilentToF = v
		if v then NYB.installHook() end
	end)
	U.toggle(T.aim.page, "Silent Aim Flask (Cure)", "SilentFlask", function(v)
		CFG.SilentFlask = v
		if v then NYB.installHook() end
	end)
	U.slider(T.aim.page, "Flash Y Offset", -5, 5, CFG.FlashYOffset, 2, function(v) CFG.FlashYOffset = v end)
	U.toggle(T.aim.page, "Silent Veil (spear, balistik)", "SpearSilent", function(v)
		CFG.SpearSilent = v
		if v then NYB.installHook() end
	end)
	U.slider(T.aim.page, "Spear Speed", 30, 400, CFG.SpearSpeed, 0, function(v) CFG.SpearSpeed = v end)
	U.slider(T.aim.page, "Spear Gravity", 10, 300, CFG.SpearGravity, 1, function(v) CFG.SpearGravity = v end)
	U.slider(T.aim.page, "Spear Max Dist", 50, 2000, CFG.SpearMaxDist, 0, function(v) CFG.SpearMaxDist = v end)
	U.slider(T.aim.page, "Spear Lead", 0, 3, CFG.SpearLead, 2, function(v) CFG.SpearLead = v end)
	U.button(T.aim.page, "Crosshair ON/OFF", function()
		NYB.setCfg("Crosshair", not CFG.Crosshair)
		NYB.buildCrosshair()
	end)
	U.slider(T.aim.page, "Crosshair Size", 3, 20, CFG.CrossSize, 0, function(v)
		CFG.CrossSize = v
		NYB.buildCrosshair()
	end)

	--======== AUTO ========
	U.section(T.auto.page, "Generator")
	U.toggle(T.auto.page, "Auto Perfect Skillcheck", "GenPerfect", function(v)
		CFG.GenPerfect = v
		if v then
			NYB.installHook()
			if not CFG.GenFailSafe then
				NYB.msg("Layer 2 (Fail-Safe Remote Hook) masih OFF — nyalakan kalau QTE masih sering gagal.")
			end
		end
	end)
	U.toggle(T.auto.page, "Fail-Safe Remote Hook", "GenFailSafe", function(v)
		CFG.GenFailSafe = v
		if v then NYB.installHook() end
	end)
	U.slider(T.auto.page, "QTE Delay Min", 0.02, 1, CFG.GenDelayMin, 2, function(v) CFG.GenDelayMin = v end)
	U.slider(T.auto.page, "QTE Delay Max", 0.05, 1.5, CFG.GenDelayMax, 2, function(v) CFG.GenDelayMax = v end)
	U.toggle(T.auto.page, "Auto Repair Generator", "AutoRepair", function(v)
		CFG.AutoRepair = v
		if not v then pcall(NYB.stopRepair) end
	end)
	U.toggle(T.auto.page, "Auto Teleport ke Gen", "AutoRepairTp", function(v) CFG.AutoRepairTp = v end)
	U.slider(T.auto.page, "Jarak Repair", 5, 40, CFG.RepairRange, 0, function(v) CFG.RepairRange = v end)
	U.slider(T.auto.page, "Repair Rate (detik)", 0.1, 2, CFG.RepairRate, 2, function(v) CFG.RepairRate = v end)

	U.section(T.auto.page, "Survivor QoL")
	U.toggle(T.auto.page, "Auto Heal", "AutoHeal", function(v) CFG.AutoHeal = v end)
	U.slider(T.auto.page, "Heal di bawah % HP", 0.3, 1, CFG.HealThreshold, 2, function(v) CFG.HealThreshold = v end)
	U.toggle(T.auto.page, "Auto Wiggle (simulasi tombol)", "AutoWiggle", function(v) CFG.AutoWiggle = v end)
	U.toggle(T.auto.page, "Auto Self-Unhook (remote asli)", "AutoSelfUnhook", function(v) CFG.AutoSelfUnhook = v end)
	U.slider(T.auto.page, "Self-Unhook Rate", 0.1, 2, CFG.UnhookRate, 2, function(v) CFG.UnhookRate = v end)
	U.toggle(T.auto.page, "Auto Vault", "AutoVault", function(v) CFG.AutoVault = v end)
	U.toggle(T.auto.page, "Auto Exit Lever", "AutoExit", function(v) CFG.AutoExit = v end)
	U.toggle(T.auto.page, "Anti Fall", "AntiFall", function(v)
		CFG.AntiFall = v
		if v then NYB.installHook() end
	end)

	U.section(T.auto.page, "Killer")
	U.toggle(T.auto.page, "Kill Aura / Auto Attack", "KillAura", function(v)
		CFG.KillAura = v
		if v and NYB.role(lp) ~= "Killer" then NYB.msg("Kamu bukan killer sekarang — aura nunggu jadi killer.") end
	end)
	U.slider(T.auto.page, "Attack Range", 5, 40, CFG.AttackRange, 0, function(v) CFG.AttackRange = v end)
	U.slider(T.auto.page, "Attack Rate (detik)", 0.15, 3, CFG.AttackRate, 2, function(v) CFG.AttackRate = v end)
	U.toggle(T.auto.page, "Auto Hadap Target", "AttackFace", function(v) CFG.AttackFace = v end)
	U.toggle(T.auto.page, "Pakai Lunge (eksperimen)", "AttackLunge", function(v) CFG.AttackLunge = v end)
	U.toggle(T.auto.page, "Auto Break Generator", "BreakGen", function(v) CFG.BreakGen = v end)
	U.slider(T.auto.page, "Break Range", 5, 30, CFG.BreakRange, 0, function(v) CFG.BreakRange = v end)
	U.slider(T.auto.page, "Break Rate (detik)", 0.1, 3, CFG.BreakRate, 2, function(v) CFG.BreakRate = v end)
	U.button(T.auto.page, "Interrupt / Cancel Action", NYB.interruptActions)
	U.button(T.auto.page, "Claim Event Reward (Halloween/Medal/Gift)", NYB.claimEvents)

	U.section(T.auto.page, "Survivor Utility")
	U.toggle(T.auto.page, "Unlimited Vault", "UnlimitedVault", function(v) NYB.unlimitedVault(v) end)
	U.toggle(T.auto.page, "Auto Pallet Slide", "PalletSlide", function(v) CFG.PalletSlide = v end)
	U.toggle(T.auto.page, "Quick Recovery (vault boost)", "QuickRecovery", function(v) CFG.QuickRecovery = v end)
	U.toggle(T.auto.page, "Flowstate No CD", "FlowstateNoCD", function(v) CFG.FlowstateNoCD = v end)
	U.toggle(T.auto.page, "Anti Hook (lepas dari gendongan)", "AntiHook", function(v) CFG.AntiHook = v end)
	U.slider(T.auto.page, "Anti Hook Offset Y", -1000, 0, CFG.AntiHookY, 0, function(v) CFG.AntiHookY = v end)
	U.slider(T.auto.page, "Anti Hook Hz", 5, 60, CFG.AntiHookHz, 0, function(v) CFG.AntiHookHz = v end)
	U.toggle(T.auto.page, "Fast Bandage", "FastBandage", function(v) CFG.FastBandage = v end)
	U.button(T.auto.page, "Drop All Pallets (map)", NYB.dropAllPallets)

	U.section(T.auto.page, "Killer Utility")
	U.toggle(T.auto.page, "No Slowdown", "NoSlowdown", function(v) CFG.NoSlowdown = v end)
	U.toggle(T.auto.page, "Infinite Lunge", "InfiniteLunge", function(v) CFG.InfiniteLunge = v end)
	U.slider(T.auto.page, "Lunge Boost Value", 1, 999, CFG.LungeValue, 0, function(v) CFG.LungeValue = v end)
	U.toggle(T.auto.page, "Auto Stalk", "AutoStalk", function(v) CFG.AutoStalk = v end)
	U.slider(T.auto.page, "Stalk Range", 20, 400, CFG.StalkRange, 0, function(v) CFG.StalkRange = v end)
	U.toggle(T.auto.page, "God Mode (isi HP terus)", "GodMode", function(v) CFG.GodMode = v end)
	U.toggle(T.auto.page, "Invisible (offset look)", "Invisible", function(v)
		CFG.Invisible = v
		if v then NYB.installHook() end
	end)

	U.section(T.auto.page, "Fake Perks")
	U.toggle(T.auto.page, "Perfect Landing", "PerfectLanding", function(v) NYB.setupPerfectLanding(v) end)
	U.toggle(T.auto.page, "Adrenaline Rush", "AdrenalineRush", function(v) NYB.setupAdrenaline(v) end)

	U.section(T.auto.page, "Killer Ability")
	U.toggle(T.auto.page, "Anti Parry / Counter Parry", "CounterParry", function(v) NYB.counterParry(v) end)
	U.slider(T.auto.page, "Counter Parry Distance", 3, 60, CFG.CounterParryDist, 0, function(v) CFG.CounterParryDist = v end)
	U.slider(T.auto.page, "Counter Parry Rate", 0.1, 2, CFG.CounterParryRate, 2, function(v) CFG.CounterParryRate = v end)
	U.toggle(T.auto.page, "Infinite Corrupt (Abysswalker)", "InfCorrupt", function(v) NYB.infCorrupt(v) end)
	U.toggle(T.auto.page, "Dash Lock (camera lock)", "DashLock", function(v) NYB.dashLock(v) end)
	U.button(T.auto.page, "Dash Lock Sekarang (manual)", function() NYB.dashTrigger() end)
	U.slider(T.auto.page, "Dash Lock Range (0 = tanpa batas)", 0, 800, CFG.DashLockDist, 0, function(v) CFG.DashLockDist = v end)
	U.slider(T.auto.page, "Dash Lock Durasi (detik)", 0.2, 10, CFG.DashLockTime, 1, function(v) CFG.DashLockTime = v end)
	U.slider(T.auto.page, "Dash Lock Smooth", 0.05, 1, CFG.DashLockSmooth, 2, function(v) CFG.DashLockSmooth = v end)
	U.toggle(T.auto.page, "Dash Lock Hold (ngunci terus)", "DashLockHold", function(v) CFG.DashLockHold = v end)
	U.toggle(T.auto.page, "Dash Lock Tombol Mobile", "DashLockBtn", function(v) CFG.DashLockBtn = v end)
	U.button(T.auto.page, "Mask GUI (buka/tutup)", function() NYB.maskGui(true) end)
	U.button(T.auto.page, "Mask GUI (tutup)", function() NYB.maskGui(false) end)
	U.button(T.auto.page, "Instant Escape", NYB.instantEscape)

	U.section(T.auto.page, "Status Generator")
	local genStatus = U.label(T.auto.page, "tekan Scan Ulang Map")
	NYB.ui.genStatus = genStatus

	U.section(T.auto.page, "Item")
	U.toggle(T.auto.page, "Pakai Item (generik)", "UseItem", function(v)
		CFG.UseItem = v
		if v then NYB.msg("Pakai item: " .. tostring(CFG.UseItemName)) end
	end)
	local itemLbl = U.label(T.auto.page, "Item: " .. tostring(CFG.UseItemName))
	NYB.ui.itemLbl = itemLbl
	U.button(T.auto.page, "Ganti Item (putar daftar terdeteksi)", function()
		local n = NYB.itemCycle()
		if n and NYB.ui.itemLbl then NYB.ui.itemLbl.Text = "Item: " .. n end
	end)
	U.button(T.auto.page, "Scan Item (copy ke clipboard)", function()
		NYB.itemDump()
	end)
	U.slider(T.auto.page, "Rate Pakai Item (detik)", 0.1, 5, CFG.UseItemRate, 2, function(v) CFG.UseItemRate = v end)
	U.toggle(T.auto.page, "Auto Equip Item", "UseItemEquip", function(v) CFG.UseItemEquip = v end)

	--======== COMBAT ========
	U.section(T.combat.page, "Parry")
	U.toggle(T.combat.page, "Auto Parry", "AutoParry", function(v) CFG.AutoParry = v end)
	U.toggle(T.combat.page, "Auto Equip Dagger", "AutoEquipDagger", function(v) CFG.AutoEquipDagger = v end)
	U.slider(T.combat.page, "Parry Range", 5, 60, CFG.ParryRange, 0, function(v) CFG.ParryRange = v end)
	U.slider(T.combat.page, "Parry Cooldown", 0.2, 5, CFG.ParryCooldown, 2, function(v) CFG.ParryCooldown = v end)
	U.button(T.combat.page, "Parry Sekarang", function()
		NYB.state.parryCD = false
		NYB.parry()
		NYB.msg("Parry manual dikirim.")
	end)

	--======== MOVEMENT ========
	U.section(T.move.page, "Kecepatan")
	U.toggle(T.move.page, "Speed Boost", "SpeedEnabled", function(v) CFG.SpeedEnabled = v end)
	U.slider(T.move.page, "WalkSpeed", 16, 120, CFG.SpeedValue, 0, function(v)
		CFG.SpeedValue = v
		if CFG.SpeedEnabled then NYB.setSpeed(v) end
	end)
	U.section(T.move.page, "Terbang & Noclip")
	U.toggle(T.move.page, "Fly", "Fly", function(v)
		CFG.Fly = v
		NYB.flyToggle(v)
		NYB.msg(v and "Fly ON (WASD + Space/Shift)" or "Fly OFF")
	end)
	U.slider(T.move.page, "Fly Speed", 20, 300, CFG.FlySpeed, 0, function(v) CFG.FlySpeed = v end)
	U.toggle(T.move.page, "Noclip (lokal)", "Noclip", function(v) CFG.Noclip = v end)
	U.toggle(T.move.page, "Real Noclip (collision server)", "RealNoclip", function(v)
		CFG.RealNoclip = v
		NYB.realNoclip(v)
	end)
	U.toggle(T.move.page, "Infinite Jump", "InfJump", function(v) CFG.InfJump = v end)
	U.slider(T.move.page, "Gravity", 0, 400, CFG.Gravity, 0, function(v)
		CFG.Gravity = v
		pcall(function() workspace.Gravity = v end)
	end)
	U.section(T.move.page, "Lain")
	U.toggle(T.move.page, "Anti AFK", "AntiAfk", function(v) CFG.AntiAfk = v end)
	U.toggle(T.move.page, "Auto Run (selalu lari)", "AutoRun", function(v) CFG.AutoRun = v end)
	U.toggle(T.move.page, "Moonwalk", "Moonwalk", function(v) CFG.Moonwalk = v end)
	U.toggle(T.move.page, "Stretch Res", "StretchRes", function(v) CFG.StretchRes = v end)
	U.slider(T.move.page, "Stretch Amount", 0.3, 1.5, CFG.StretchAmount, 2, function(v) CFG.StretchAmount = v end)

	--======== VISUAL ========
	U.section(T.vis.page, "Layar")
	U.toggle(T.vis.page, "Fullbright", "Fullbright", function(v) CFG.Fullbright = v; NYB.applyVisual() end)
	U.toggle(T.vis.page, "No Fog", "NoFog", function(v) CFG.NoFog = v; NYB.applyVisual() end)
	U.toggle(T.vis.page, "Anti Flash / Blind", "AntiFlash", function(v)
		CFG.AntiFlash = v
		if v then NYB.installHook() end
	end)
	U.toggle(T.vis.page, "Self Highlight", "SelfHighlight", function(v)
		CFG.SelfHighlight = v
		pcall(function()
			local char = lp.Character
			if not char then return end
			local ex = char:FindFirstChild("NYB_Self")
			if v then
				if not ex then
					local hl = Instance.new("Highlight")
					hl.Name = "NYB_Self"
					hl.Adornee = char
					hl.FillColor = CFG.Accent
					hl.FillTransparency = 0.6
					hl.Parent = char
				end
			elseif ex then
				ex:Destroy()
			end
		end)
	end)
	U.slider(T.vis.page, "Camera FOV", 50, 120, CFG.CameraFov, 0, function(v) CFG.CameraFov = v; NYB.applyFov() end)
	U.toggle(T.vis.page, "Zoom Unlock", "InfZoom", function(v)
		CFG.InfZoom = v
		pcall(function()
			if v then
				lp.CameraMaxZoomDistance = 500
				lp.CameraMinZoomDistance = 0.5
			else
				lp.CameraMaxZoomDistance = 128
			end
		end)
	end)
	U.slider(T.vis.page, "Time of Day (0 = off)", 0, 24, 0, 0, function(v)
		CFG.TimeOfDay = v > 0 and v or -1
		NYB.applyVisual()
	end)

	--======== TELEPORT ========
	U.section(T.tp.page, "Objek Map")
	U.button(T.tp.page, "Ke Generator Terdekat", function()
		local m, d = NYB.nearest(C.genList, NYB.hrp() and NYB.hrp().Position)
		local p = m and NYB.part(m)
		if p then NYB.tpTo(p.Position + Vector3.new(0, 3, 0)); NYB.msg(string.format("Gen terdekat %.0f stud", d)) end
	end)
	U.button(T.tp.page, "Ke Gate Terdekat", function()
		local m, d = NYB.nearest(C.gateList, NYB.hrp() and NYB.hrp().Position)
		local p = m and NYB.part(m)
		if p then NYB.tpTo(p.Position + Vector3.new(0, 3, 0)); NYB.msg("Ke gate.") end
	end)
	U.button(T.tp.page, "Ke Hook Terdekat", function()
		local m = NYB.nearest(C.hookList, NYB.hrp() and NYB.hrp().Position)
		local p = m and NYB.part(m)
		if p then NYB.tpTo(p.Position + Vector3.new(0, 3, 0)) end
	end)
	U.section(T.tp.page, "Pemain")
	-- Tab Rayfield itu bukan Instance, jadi gak bisa di-parent Instance.new("Frame").
	-- Daftar pemain dibuat pakai tombol Rayfield, sekali saat load.
	NYB.ui.tpCount = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local role = NYB.role(plr)
			U.button(T.tp.page, string.format("[%s] %s", string.sub(role, 1, 1), plr.Name), function()
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					NYB.tpTo(hrp.Position + Vector3.new(0, 2.5, 0))
					NYB.msg("TP ke " .. plr.Name)
				else
					NYB.msg(plr.Name .. " belum spawn.")
				end
			end)
			NYB.ui.tpCount = NYB.ui.tpCount + 1
		end
	end
	NYB.ui.refreshTP = function()
		NYB.msg("Daftar TP dibuat saat load (" .. tostring(NYB.ui.tpCount) .. " pemain). Reload script buat update.")
	end
	U.button(T.tp.page, "Refresh Daftar Pemain (info)", NYB.ui.refreshTP)
	U.toggle(T.tp.page, "Smooth Teleport", "SmoothTp", function(v) CFG.SmoothTp = v end)
	U.slider(T.tp.page, "Durasi TP", 0.05, 1, CFG.SmoothTpTime, 2, function(v) CFG.SmoothTpTime = v end)

	--======== MISC ========
	U.section(T.misc.page, "Diagnostik")
	U.toggle(T.misc.page, "Remote Log ke Console", "RemoteLog", function(v)
		CFG.RemoteLog = v
		if v then NYB.remoteLog(true) end
	end)
	U.button(T.misc.page, "Dump Remote Log (clipboard)", function()
		local text = table.concat(NYB.state.logLines or {}, "\n")
		pcall(function() setclipboard(text) end)
		NYB.msg(string.format("%d baris log dicopy.", #(NYB.state.logLines or {})))
	end)
	U.section(T.misc.page, "Probe (eksperimen)")
	U.button(T.misc.page, "Probe ChangeAttribute speedboost=1.6", function()
		NYB.probeAttr("speedboost", 1.6)
	end)
	U.button(T.misc.page, "Probe ChangeAttribute speedboost=6", function()
		NYB.probeAttr("speedboost", 6)
	end)

	U.section(T.misc.page, "Info Overlay (port)")
	U.toggle(T.misc.page, "Next Killer Display", "NextKiller", function(v) CFG.NextKiller = v end)
	U.toggle(T.misc.page, "Next Map Display", "NextMap", function(v) CFG.NextMap = v end)

	U.section(T.misc.page, "Gate")
	U.toggle(T.misc.page, "Bypass Exit Gate", "BypassGate", function(v)
		CFG.BypassGate = v
		NYB.bypassGate(v)
	end)
	U.toggle(T.misc.page, "Instant TP Gate (getgc)", "InstantTPGate", function(v)
		CFG.InstantTPGate = v
		NYB.instantGate(v)
	end)

	U.section(T.misc.page, "Cosmetic / QoL")
	U.toggle(T.misc.page, "Streamer Mode (sensor nama)", "StreamerMode", function(v) NYB.streamerMode(v) end)
	U.toggle(T.misc.page, "Skip Endscreen", "SkipEndscreen", function(v) NYB.skipEndscreen(v) end)
	U.toggle(T.misc.page, "Korless Morph", "KorlessMorph", function(v) NYB.korless(v) end)
	U.toggle(T.misc.page, "8 Bit Crown", "CrownOn", function(v) NYB.crown(v) end)
	U.slider(T.misc.page, "Crown Scale", 0.3, 3, CFG.CrownScale, 2, function(v)
		CFG.CrownScale = v
		NYB.crownRefresh()
	end)
	U.slider(T.misc.page, "Crown Y Offset (stud)", -1, 2, CFG.CrownYOff, 2, function(v)
		CFG.CrownYOff = v
		NYB.crownRefresh()
	end)
	U.toggle(T.misc.page, "Crown VFX (api 8bit)", "CrownVfx", function(v)
		CFG.CrownVfx = v
		NYB.crownRefresh()
	end)
	U.button(T.misc.page, "Crown: Tempel Ulang", function() NYB.crownRefresh() end)
	U.button(T.misc.page, "Copy Avatar (pemain terdekat)", function()
		local hrp = NYB.hrp()
		local best, bd
		if hrp then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= lp and p.Character then
					local h = p.Character:FindFirstChild("HumanoidRootPart")
					if h then
						local d = (h.Position - hrp.Position).Magnitude
						if not bd or d < bd then bd = d; best = p end
					end
				end
			end
		end
		NYB.applyAvatarOf(best)
	end)
	U.button(T.misc.page, "Copy Avatar (random)", NYB.randomAvatar)
	U.button(T.misc.page, "Reset Avatar Sendiri", function()
		NYB.applyAvatarOf(lp)
	end)

	U.section(T.misc.page, "Config")
	U.button(T.misc.page, "Save Config (NYB_HUB/config.json)", NYB.saveConfig)
	U.button(T.misc.page, "Load Config", NYB.loadConfig)
	U.button(T.misc.page, "Reset Semua Fitur Port", NYB.resetConfig)
	U.toggle(T.misc.page, "Status Overlay", "ShowStats", function(v) CFG.ShowStats = v end)
	U.section(T.misc.page, "Remote Terdeteksi")
	local rlbl = U.label(T.misc.page, NYB.remotes.list())
	NYB.ui.remoteLbl = rlbl
	U.button(T.misc.page, "Re-resolve Remote", function()
		NYB.remotes.resolve()
		if NYB.ui.remoteLbl then NYB.ui.remoteLbl.Text = NYB.remotes.list() end
		NYB.msg("Remote di-resolve ulang.")
	end)
	U.section(T.misc.page, "Info")
	U.label(T.misc.page, "NYB HUB v2.6 · engine UI sendiri (tanpa Rayfield)\n"
		.. "Place: " .. tostring(game.PlaceId) .. "\n"
		.. "Hotkey: " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " untuk show/hide\n"
		.. "Kalau window ketutup di HP: tekan tombol NYB HUB di kiri atas.", NYB.ui.colors.dim)

	-- buka tab pertama: tanpa ini panel kebuka kosong sampai tab di-tap
	if NYB.ui.tabs[1] and NYB.ui.tabs[1].activate then
		pcall(NYB.ui.tabs[1].activate)
	end

	-- terapkan layout setelah semua tab jadi (biar tidak ada window kebesaran)
	pcall(NYB.ui.applyResponsive)
	pcall(NYB.ui.stickyTick)
end

--===================== [ 14. ESP RENDER LOOP ] ============================
do
	local C = NYB.cache
	local U = NYB.ui

	local function playerEntries(list, hrp)
		if not CFG.EspPlayers then return end
		local myPos = hrp and hrp.Position
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp then
				local char = plr.Character
				local chrp = char and char:FindFirstChild("HumanoidRootPart")
				local head = char and (char:FindFirstChild("Head") or chrp)
				if char and chrp then
					local hum = char:FindFirstChildOfClass("Humanoid")
					local alive = hum and hum.Health > 0
					if (not CFG.EspAliveOnly) or alive then
						local dist = myPos and (chrp.Position - myPos).Magnitude or 0
						if dist <= CFG.EspMaxDist then
							local role = NYB.role(plr)
							local color = CFG.ColorOther
							if role == "Killer" then color = CFG.ColorKiller
							elseif role == "Survivor" then color = CFG.ColorSurvivor end

							local bits = {}
							if CFG.EspName then table.insert(bits, plr.Name) end
							if CFG.EspRole then table.insert(bits, "[" .. string.sub(role, 1, 4):upper() .. "]") end
							if CFG.EspDist then table.insert(bits, string.format("%.0fm", dist)) end
							local line1 = table.concat(bits, " ")

							local line2 = ""
							if CFG.EspTool then
								local item = plr:GetAttribute("EquippedItem")
								if role == "Killer" then
									local k = plr:GetAttribute("SelectedKiller")
									line2 = "Killer: " .. tostring(k or "?")
								elseif item and item ~= "" and item ~= "None" then
									line2 = "Item: " .. tostring(item)
								end
							end
							if CFG.EspHealth and hum then
								local hp = string.format("HP %.0f/%.0f", hum.Health, hum.MaxHealth)
								line2 = line2 ~= "" and (line2 .. "  " .. hp) or hp
							end

							local text = line2 ~= "" and (line1 .. "\n" .. line2) or line1
							table.insert(list, {
								model = char,
								adornee = head,
								text = text,
								color = color,
								chams = CFG.EspChams,
								box = CFG.EspBox,
							})
						end
					end
				end
			end
		end
	end

	local function objEntries(list, hrp)
		local myPos = hrp and hrp.Position
		local function push(model, color, text)
			if not model or not model.Parent then return end
			local part = NYB.part(model)
			if not part then return end
			local dist = myPos and (part.Position - myPos).Magnitude or 0
			if dist > CFG.EspMaxDist then return end
			table.insert(list, {
				model = model,
				adornee = part,
				text = string.format("%s\n%.0fm", text, dist),
				color = color,
				chams = CFG.EspChams,
				box = false,
			})
		end

		if CFG.EspGens then
			for _, g in ipairs(C.genList or {}) do
				if g.Parent then
					local p = NYB.genProgress(g)
					local done = NYB.genDone(g)
					local col = done and CFG.ColorGenDone or CFG.ColorGen
					push(g, col, done and "Generator [DONE]" or string.format("Generator %.0f%%", p))
				end
			end
		end
		if CFG.EspGates then
			for _, g in ipairs(C.gateList or {}) do push(g, CFG.ColorGate, "Gate / Exit") end
		end
		if CFG.EspHooks then
			for _, g in ipairs(C.hookList or {}) do push(g, CFG.ColorHook, "Hook") end
		end
		if CFG.EspPallets then
			for _, g in ipairs(C.palletList or {}) do push(g, CFG.ColorPallet, "Pallet") end
		end
		if CFG.EspWindows then
			for _, g in ipairs(C.windowList or {}) do push(g, CFG.ColorWindow, "Window") end
		end
	end

	NYB.espFrame = function()
		if not NYB.alive then return end
		-- idle guard: kalau semua kategori ESP OFF, tidak ada kerja sama sekali
		if not (CFG.EspPlayers or CFG.EspGens or CFG.EspGates or CFG.EspHooks
			or CFG.EspPallets or CFG.EspWindows) then
			if next(NYB.esp.pool) ~= nil then NYB.esp.clear() end
			return
		end
		local hrp = NYB.hrp()
		local list = {}
		playerEntries(list, hrp)
		objEntries(list, hrp)
		NYB.esp.sync(list)
	end

	-- generator status text
	NYB.genStatusTick = function()
		if not U.genStatus then return end
		local total = #(C.genList or {})
		local left = 0
		for _, g in ipairs(C.genList or {}) do
			if not NYB.genDone(g) then left = left + 1 end
		end
		U.genStatus.Text = string.format("%d generator terdeteksi · %d belum selesai", total, left)
	end
end

--===================== [ 15. STATUS OVERLAY ] =============================
do
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(0, 210, 0, 118)
	holder.Position = UDim2.new(0, 14, 0, 60)
	holder.BackgroundColor3 = NYB.ui.colors.bg
	holder.BackgroundTransparency = 0.25
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.Parent = NYB.ui.gui
	local uc = Instance.new("UICorner")
	uc.CornerRadius = UDim.new(0, 10)
	uc.Parent = holder
	local s = Instance.new("UIStroke")
	s.Color = NYB.ui.colors.stroke
	s.Parent = holder

	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.new(1, -16, 0, 20)
	hdr.Position = UDim2.new(0, 10, 0, 6)
	hdr.BackgroundTransparency = 1
	hdr.Text = "NYB HUB · STATUS"
	hdr.TextColor3 = CFG.Accent
	hdr.TextSize = 11
	hdr.Font = Enum.Font.GothamBold
	hdr.TextXAlignment = Enum.TextXAlignment.Left
	hdr.Parent = holder

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, -20, 1, -32)
	body.Position = UDim2.new(0, 10, 0, 26)
	body.BackgroundTransparency = 1
	body.TextColor3 = NYB.ui.colors.text
	body.TextSize = 11
	body.Font = Enum.Font.GothamMedium
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.TextWrapped = true
	body.Text = ""
	body.Parent = holder

	NYB.overlayTick = function()
		holder.Visible = CFG.ShowStats and NYB.ui.window.Visible
		if not holder.Visible then return end
		local hum = NYB.hum()
		local role = NYB.role(lp)
		local on = {}
		if CFG.GenPerfect then table.insert(on, "GEN") end
		if CFG.AutoRepair then table.insert(on, "REP") end
		if CFG.AutoParry then table.insert(on, "PARRY") end
		if CFG.AutoHeal then table.insert(on, "HEAL") end
		if CFG.EspPlayers then table.insert(on, "ESP") end
		if CFG.SpeedEnabled then table.insert(on, "SPD") end
		body.Text = string.format(
			"Role   : %s\nHP     : %.0f / %.0f\nESP    : %d objek\nRemote : %d terdeteksi\nON     : %s",
			role,
			hum and hum.Health or 0,
			hum and hum.MaxHealth or 0,
			NYB.esp.count or 0,
			NYB.remotes.count(),
			#on > 0 and table.concat(on, " ") or "-"
		)
	end
end

--===================== [ 16. MAIN LOOPS ] =================================
do
	local lastScan, lastEsp, lastAlert = 0, 0, 0

	local function killerAlert(hrp)
		if not CFG.KillerAlert or not hrp then return end
		local now = tick()
		if now - lastAlert < 3 then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp and NYB.role(plr) == "Killer" then
				local char = plr.Character
				local khrp = char and char:FindFirstChild("HumanoidRootPart")
				if khrp then
					local d = (khrp.Position - hrp.Position).Magnitude
					if d <= CFG.AlertDist then
						lastAlert = now
						NYB.msg(string.format("KILLER DEKAT: %s (%.0f stud)", plr.Name, d))
						return
					end
				end
			end
		end
	end

	NYB.bind(RunService.RenderStepped, function()
		if not NYB.alive then return end
		pcall(NYB.aimStep)
		pcall(NYB.stretchStep)
		pcall(NYB.moonwalkStep)
		pcall(NYB.dashStep)
	end)

	NYB.bind(RunService.Heartbeat, function(dt)
		if not NYB.alive then return end
		local now = tick()

		-- map scan tiap 3 detik
		if now - lastScan >= 3 then
			lastScan = now
			pcall(NYB.scan)
		end

		-- ESP tiap frame (dibatasi 20 Hz biar HP aman)
		if now - lastEsp >= 0.05 then
			lastEsp = now
			pcall(NYB.espFrame)
		end

		pcall(NYB.genStatusTick)
		if now - (NYB.state.lastSticky or 0) >= 0.05 then
			NYB.state.lastSticky = now
			pcall(NYB.ui.stickyTick)
		end
		pcall(NYB.overlayTick)
		pcall(NYB.autoSkill)

		local hrp = NYB.hrp()
		if hrp then
			if CFG.SpeedEnabled then NYB.setSpeed(CFG.SpeedValue) end
			pcall(NYB.flyStep)
			pcall(NYB.noclipStep)
			pcall(NYB.autoRepair)
			pcall(NYB.autoHeal)
			pcall(NYB.autoWiggle)
			pcall(NYB.autoSelfUnhook)
			pcall(NYB.killAura)
			pcall(NYB.breakGen)
			if CFG.RealNoclip and now - (NYB.state.lastCol or 0) > 2 then
				NYB.state.lastCol = now
				pcall(NYB.realNoclip, true)
			end
			pcall(NYB.killerUtilStep)
			pcall(NYB.quickRecoveryStep)
			pcall(NYB.fastBandageStep)
			pcall(NYB.useItemStep)
			pcall(NYB.autoStalkStep)
			pcall(NYB.autoRunStep)
			pcall(NYB.zoomStep)
			pcall(NYB.antiHookStep, dt)
			if now - (NYB.state.lastVault or 0) > 0.2 then
				NYB.state.lastVault = now
				pcall(NYB.autoVault)
				pcall(NYB.autoExitLever)
				pcall(NYB.palletStep)
				pcall(NYB.infoStep)
			end
			pcall(killerAlert, hrp)
		end

		if now - (NYB.state.lastFlash or 0) > 0.25 then
			NYB.state.lastFlash = now
			pcall(NYB.antiFlashStep)
		end
	end)

	-- respawn
	NYB.bind(lp.CharacterAdded, function(char)
		task.wait(1.2)
		pcall(function()
			NYB.esp.clear()
			if CFG.Fly then NYB.flyToggle(true) end
			if CFG.UnlimitedVault then
				task.wait(0.5)
				NYB.unlimitedVault(true)
			end
			if CFG.InfiniteLunge then
				pcall(function() char:SetAttribute("lungeboost", CFG.LungeValue) end)
			end
			if CFG.GodMode then
				local h = char:FindFirstChildOfClass("Humanoid")
				if h then h.Health = h.MaxHealth end
			end
			if CFG.PerfectLanding then NYB.setupPerfectLanding(true) end
			if CFG.AdrenalineRush then
				task.wait(0.3)
				NYB.setupAdrenaline(true)
			end
			if CFG.KorlessMorph then
				task.wait(0.5)
				NYB.korless(true)
			end
			if CFG.CrownOn then
				task.wait(0.5)
				NYB.crownBuild(lp)
			end
			if CFG.SelfHighlight then
				local hl = char:FindFirstChild("NYB_Self")
				if not hl then
					local h = Instance.new("Highlight")
					h.Name = "NYB_Self"
					h.Adornee = char
					h.FillColor = CFG.Accent
					h.FillTransparency = 0.6
					h.Parent = char
				end
			end
		end)
	end)

	-- killer animation watch
	NYB.bind(Players.PlayerAdded, function(plr)
		NYB.bind(plr.CharacterAdded, function(char)
			task.wait(1)
			if NYB.role(plr) == "Killer" then
				pcall(NYB.watchKiller, char)
			end
		end)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= lp then
			local char = plr.Character
			if char and NYB.role(plr) == "Killer" then
				pcall(NYB.watchKiller, char)
			end
		end
	end

	-- anti afk
	NYB.bind(UIS.JumpRequest, function()
		if not CFG.InfJump then return end
		local hum = NYB.hum()
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end)

	task.spawn(function()
		local vu = game:GetService("VirtualUser")
		while NYB.alive do
			task.wait(60)
			if CFG.AntiAfk then
				pcall(function()
					vu:CaptureController()
					vu:ClickButton2(Vector2.new())
				end)
			end
		end
	end)
end

--===================== [ 17. BOOT ] =======================================
task.spawn(function()
	NYB.remotes.resolve()
	NYB.autoSkillInit()
	if CFG.GenPerfect then NYB.installHook() end
	pcall(NYB.scan)
	if NYB.ui.refreshTP then pcall(NYB.ui.refreshTP) end
	if NYB.ui.remoteLbl then NYB.ui.remoteLbl.Text = NYB.remotes.list() end
	-- visual & FOV sengaja TIDAK diterapkan saat load (semua fitur default OFF,
	-- jadi script tidak mengubah apa pun sampai kamu menyalakan togglenya)
	NYB.ui.setStatus(string.format("remote: %d", NYB.remotes.count()))
	NYB.ui.notify("NYB HUB v2.6 loaded", 4)
	task.wait(0.4)
	NYB.ui.notify("Hotkey " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " · Self Test di tab Main", 4)
end)

print("[NYB HUB] v2.6 loaded. Remote terdeteksi: " .. tostring(NYB.remotes.count()))
