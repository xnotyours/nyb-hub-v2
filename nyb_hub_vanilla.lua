--[[ ==========================================================================
     N Y B   H U B   |   Violence District Toolkit            v2.8
     --------------------------------------------------------------------------
     File    : nyb_hub_vanilla.lua      (single file, nol dependensi luar)
     Engine  : UI pola Aeris Hub (VD) -- kodenya diangkat INLINE ke dalam file
               ini lalu di-rebrand jadi NYB (CreateAerisLibrary ->
               CreateNYBLibrary, Aeris_* -> NYB_*, watermark/hub -> "NYB Hub").
               TANPA loadstring, TANPA fetch library pihak ketiga.
     Target  : [BUTCHER] Violence District      (PlaceId 93978595733734)
     Platform: Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift)
     Tanpa key: gak ada whitelist / validasi / countdown key di script ini.

     v2.8 = KEY DIHAPUS: label countdown "Key: 23h 59m" + loop 1 detiknya
            dibuang dari kartu profil, kartunya dikecilin 74 -> 56 px. Di file
            ini emang gak pernah ada validasi key -- cuma tampilannya doang
            yang nyisa dari engine Aeris.

     v2.7 = UI SCALE: ukuran window dulu dipatok mati 690x470 px -- di HP itu
            nutup hampir seluruh layar. Sekarang seluruh window di-skala lewat
            UIScale: auto-fit ke viewport (maks 82% lebar / 88% tinggi) x
            slider manual 0.40-1.30, dihitung ulang saat layar diputar.
            Kontrolnya di tab Misc -> UI (+ tombol Reset Ukuran Window).

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
	-- Instance sebelumnya masih nempel. Dulu di sini kita cuma `warn()` lalu
	-- `return` -- dan di executor yang nyembunyiin warn(), efeknya persis
	-- seperti "script gak jalan": nggak ada window, nggak ada error.
	-- Sekarang: matikan instance lama otomatis, terus lanjut load yang baru.
	if type(NYB_ENV.NYB_UNLOAD) == "function" then
		local okU, errU = pcall(NYB_ENV.NYB_UNLOAD)
		if not okU then
			warn("[NYB HUB] gagal unload instance lama: " .. tostring(errU))
		end
	else
		warn("[NYB HUB] instance lama gak punya hook unload -- GUI lama dibersihin paksa.")
		for _, name in ipairs({ "NYB_MainHub", "NYB_Notifications", "NYB_Watermark",
			"NYB_HUB_Overlay", "NYB_AimFov", "NYB_Crosshair", "NYB_Info", "NYB_DashLock" }) do
			pcall(function()
				local p = (gethui and gethui()) or game:GetService("CoreGui")
				local g = p:FindFirstChild(name)
				if g then g:Destroy() end
			end)
		end
	end
	NYB_ENV.NYB_HUB_RUNNING = nil
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
	UIScaleAuto    = true,
	UIScale        = 0.9,
	-- Kamera (port Aeris)
	ThirdPerson    = false,
	InfinityZoom   = false,
	DBDCamera      = false,
	DBDDistance    = 13,
	DBDHeight      = 4.2,
	DBDRunSmooth   = 0.1,
	DBDLookSmooth  = 0.28,
	DBDSens        = 0.55,
	DBDPitchMin    = -0.55,
	DBDPitchMax    = 0.45,
	DBDFOV         = 70,
	-- Performa (port Aeris)
	NoShadow       = false,
	RemoveTexture  = false,
	-- Crosshair (port Aeris)
	CrossStyle     = "Plus",
	CrossThick     = 2,
	CrossOffX      = 0,
	CrossOffY      = 0,
	CrossKey       = "None",
	-- Info overlay (port Aeris)
	KillerPerks    = false,
	StunRing       = false,
	Spectator      = false,
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

--===================== [ 5. NYB UI ENGINE ] ================================
-- Engine UI dipakai dari hub publik VD (Aeris) -- ditulis INLINE di script,
-- bukan fetch library pihak ketiga. Pola ini yang dipakai hub-hub VD yang jalan:
-- window draggable, tab, section, toggle/slider/button/dropdown/keybind/colorpicker,
-- watermark, notifikasi, config manager. Nol dependensi luar, nol kontrak vendor.
--
-- Kontrak API (diverifikasi dari sumbernya, semua POSISIONAL):
--   lib:CreateWindow{Title,Subtitle,Logo,Watermark,...}
--   window:CreateTab(tabName, icon) -> tabObj
--   tabObj:CreateSection(name, icon) -> section { Name, Card, ItemsFrame }
--   section:AddToggle(name, default, cb, opts)   -> toggleObj :SetValue/:GetValue
--   section:AddSlider(name, min, max, def, cb)   -> sliderObj :SetValue/:GetValue
--   section:AddButton(name, cb)                  -> TextButton
--   section:AddDropdown(name, list, def, cb)     -> ddObj :SetValue/:GetValue
--   lib:Notify{Title, Description, Duration, Logo}
--
-- Catatan: element nempel ke SECTION, bukan ke Tab. Engine ini TIDAK punya
-- AddLabel -- jadi U.label bikin TextLabel sendiri dan menempelkannya ke
-- section.ItemsFrame (section-nya expose Card + ItemsFrame).

--[[
    ═══════════════════════════════════════════════════════
                 A E R I S   U I   E N G I N E
              Custom Violet & White UI Framework
    ═══════════════════════════════════════════════════════
]]

local function CreateNYBLibrary()
    local lib = {
        Scheme = {
            AccentColor = Color3.fromRGB(180, 130, 255),
            BackgroundColor = Color3.fromRGB(16, 11, 26),
            MainColor = Color3.fromRGB(24, 17, 38),
            OutlineColor = Color3.fromRGB(200, 170, 255),
            FontColor = Color3.fromRGB(255, 255, 255),
            SubTextColor = Color3.fromRGB(175, 160, 205),
            HoverColor = Color3.fromRGB(48, 34, 72)
        },
        Windows = {},
        Flags = {},
        Options = {},
        Elements = {},
        ShimmerGradients = {},
        MenuKey = Enum.KeyCode.RightShift,
        WatermarkEnabled = true
    }

    local TweenService = game:GetService("TweenService")
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local HttpService = game:GetService("HttpService")
    local localPlayer = Players.LocalPlayer

    -- Safe GUI Parent Detection
    local function GetSafeGuiParent()
        local success, parent = pcall(function()
            if gethui then return gethui() end
            local cg = game:GetService("CoreGui")
            local t = Instance.new("Folder", cg)
            t:Destroy()
            return cg
        end)
        if success and parent then return parent end
        return localPlayer:WaitForChild("PlayerGui")
    end

    -- 60 FPS Iridescent Violet & White Shimmer Animation Loop
    RunService.RenderStepped:Connect(function()
        local rot = (tick() * 65) % 360
        for i = #lib.ShimmerGradients, 1, -1 do
            local grad = lib.ShimmerGradients[i]
            if grad and grad.Parent then
                grad.Rotation = rot
            else
                table.remove(lib.ShimmerGradients, i)
            end
        end
    end)

    function lib:ApplyShimmer(parent, thickness)
        local stroke = parent:FindFirstChildOfClass("UIStroke")
        if not stroke then
            stroke = Instance.new("UIStroke")
            stroke.Thickness = thickness or 1.8
            stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            stroke.Color = Color3.fromRGB(255, 255, 255)
            stroke.Transparency = 0.2
            stroke.Parent = parent
        end
        local grad = stroke:FindFirstChildOfClass("UIGradient")
        if not grad then
            grad = Instance.new("UIGradient")
            grad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(0.20, Color3.fromRGB(185, 120, 255)),
                ColorSequenceKeypoint.new(0.40, Color3.fromRGB(240, 220, 255)),
                ColorSequenceKeypoint.new(0.60, Color3.fromRGB(140, 60, 240)),
                ColorSequenceKeypoint.new(0.80, Color3.fromRGB(210, 170, 255)),
                ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 255, 255))
            })
            grad.Parent = stroke
            table.insert(lib.ShimmerGradients, grad)
        end
        return stroke, grad
    end

    -- Modern Toast Notifications System
    local notifyGui = Instance.new("ScreenGui")
    notifyGui.Name = "NYB_Notifications"
    notifyGui.IgnoreGuiInset = true
    notifyGui.DisplayOrder = 100000
    notifyGui.ResetOnSpawn = false
    notifyGui.Parent = GetSafeGuiParent()

    local notifyList = Instance.new("Frame")
    notifyList.Name = "NotifyContainer"
    notifyList.AnchorPoint = Vector2.new(1, 1)
    notifyList.Position = UDim2.new(1, -20, 1, -20)
    notifyList.Size = UDim2.new(0, 320, 1, -40)
    notifyList.BackgroundTransparency = 1
    notifyList.Parent = notifyGui

    local notifyLayout = Instance.new("UIListLayout")
    notifyLayout.FillDirection = Enum.FillDirection.Vertical
    notifyLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    notifyLayout.Padding = UDim.new(0, 10)
    notifyLayout.Parent = notifyList

    function lib:Notify(config)
        config = type(config) == "table" and config or { Title = "NYB", Description = tostring(config), Duration = 3 }
        local title = config.Title or "NYB Hub"
        local desc = config.Description or ""
        local duration = tonumber(config.Duration) or 3

        local card = Instance.new("Frame")
        card.Name = "NotifyCard"
        card.Size = UDim2.new(1, 0, 0, 66)
        card.BackgroundColor3 = Color3.fromRGB(18, 12, 30)
        card.BackgroundTransparency = 0.15
        card.BorderSizePixel = 0
        card.ClipsDescendants = true
        card.Parent = notifyList

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = card

        lib:ApplyShimmer(card, 1.5)

        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, 4, 1, 0)
        accent.BackgroundColor3 = Color3.fromRGB(180, 130, 255)
        accent.BorderSizePixel = 0
        accent.Parent = card

        local tLabel = Instance.new("TextLabel")
        tLabel.Text = title
        tLabel.Font = Enum.Font.GothamBold
        tLabel.TextSize = 14
        tLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        tLabel.TextXAlignment = Enum.TextXAlignment.Left
        tLabel.BackgroundTransparency = 1
        tLabel.Position = UDim2.new(0, 14, 0, 10)
        tLabel.Size = UDim2.new(1, -24, 0, 18)
        tLabel.Parent = card

        local dLabel = Instance.new("TextLabel")
        dLabel.Text = desc
        dLabel.Font = Enum.Font.Gotham
        dLabel.TextSize = 12
        dLabel.TextColor3 = Color3.fromRGB(200, 190, 225)
        dLabel.TextXAlignment = Enum.TextXAlignment.Left
        dLabel.BackgroundTransparency = 1
        dLabel.Position = UDim2.new(0, 14, 0, 30)
        dLabel.Size = UDim2.new(1, -24, 0, 24)
        dLabel.TextWrapped = true
        dLabel.Parent = card

        local prog = Instance.new("Frame")
        prog.Size = UDim2.new(1, 0, 0, 2)
        prog.Position = UDim2.new(0, 0, 1, -2)
        prog.BackgroundColor3 = Color3.fromRGB(190, 140, 255)
        prog.BorderSizePixel = 0
        prog.Parent = card

        card.Position = UDim2.new(1, 50, 0, 0)
        TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 0, 0, 0)
        }):Play()

        TweenService:Create(prog, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
            Size = UDim2.new(0, 0, 0, 2)
        }):Play()

        task.delay(duration, function()
            if card and card.Parent then
                local outTween = TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
                    Position = UDim2.new(1, 50, 0, 0),
                    BackgroundTransparency = 1
                })
                outTween:Play()
                outTween.Completed:Wait()
                card:Destroy()
            end
        end)
    end

    -- Modern Floating Watermark
    local watermarkGui = Instance.new("ScreenGui")
    watermarkGui.Name = "NYB_Watermark"
    watermarkGui.IgnoreGuiInset = true
    watermarkGui.DisplayOrder = 99998
    watermarkGui.ResetOnSpawn = false
    watermarkGui.Parent = GetSafeGuiParent()

    local watermarkFrame = Instance.new("Frame")
    watermarkFrame.Name = "WatermarkFrame"
    watermarkFrame.Position = UDim2.new(0, 20, 0, 16)
    watermarkFrame.Size = UDim2.new(0, 260, 0, 32)
    watermarkFrame.BackgroundColor3 = Color3.fromRGB(18, 12, 30)
    watermarkFrame.BackgroundTransparency = 0.25
    watermarkFrame.BorderSizePixel = 0
    watermarkFrame.Parent = watermarkGui

    local wmCorner = Instance.new("UICorner")
    wmCorner.CornerRadius = UDim.new(0, 8)
    wmCorner.Parent = watermarkFrame

    lib:ApplyShimmer(watermarkFrame, 1.5)

    local wmLogo = Instance.new("ImageLabel")
    wmLogo.Image = "rbxassetid://94398897297532"
    wmLogo.Size = UDim2.new(0, 22, 0, 22)
    wmLogo.Position = UDim2.new(0, 6, 0.5, -11)
    wmLogo.BackgroundTransparency = 1
    wmLogo.ScaleType = Enum.ScaleType.Fit
    wmLogo.Parent = watermarkFrame

    local wmLabel = Instance.new("TextLabel")
    wmLabel.Text = "NYB Hub | Violence District | FPS: 60"
    wmLabel.Font = Enum.Font.GothamMedium
    wmLabel.TextSize = 12
    wmLabel.TextColor3 = Color3.fromRGB(240, 230, 255)
    wmLabel.BackgroundTransparency = 1
    wmLabel.Position = UDim2.new(0, 34, 0, 0)
    wmLabel.Size = UDim2.new(1, -40, 1, 0)
    wmLabel.TextXAlignment = Enum.TextXAlignment.Left
    wmLabel.Parent = watermarkFrame

    task.spawn(function()
        local frameCount = 0
        local lastTime = os.clock()
        RunService.RenderStepped:Connect(function()
            frameCount = frameCount + 1
            local now = os.clock()
            if now - lastTime >= 1 then
                local fps = math.round(frameCount / (now - lastTime))
                frameCount = 0
                lastTime = now
                if wmLabel and wmLabel.Parent then
                    wmLabel.Text = string.format("NYB Hub | Violence District | FPS: %d", fps)
                end
            end
        end)
    end)

    function lib:SetWatermark(opt)
        if type(opt) == "table" then
            watermarkFrame.Visible = opt.Enabled ~= false
        elseif type(opt) == "boolean" then
            watermarkFrame.Visible = opt
        end
    end

    -- Main Window Constructor
    function lib:CreateWindow(config)
        config = config or {}
        local windowTitle = config.Title or "NYB Hub"
        local windowSubtitle = config.Subtitle or "Violence District"
        local logoAsset = config.Logo or "rbxassetid://94398897297532"

        local mainGui = Instance.new("ScreenGui")
        mainGui.Name = "NYB_MainHub"
        mainGui.IgnoreGuiInset = true
        mainGui.DisplayOrder = 50
        mainGui.ResetOnSpawn = false
        mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        mainGui.Parent = GetSafeGuiParent()

        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "MainWindow"
        mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
        mainFrame.Size = UDim2.new(0, 690, 0, 470)
        mainFrame.BackgroundColor3 = Color3.fromRGB(16, 11, 26)
        mainFrame.BackgroundTransparency = 0.20
        mainFrame.BorderSizePixel = 0
        mainFrame.ClipsDescendants = false
        mainFrame.Parent = mainGui

        local mainCorner = Instance.new("UICorner")
        mainCorner.CornerRadius = UDim.new(0, 14)
        mainCorner.Parent = mainFrame

        lib:ApplyShimmer(mainFrame, 2.2)

        -- ==== UI SCALE (auto-fit layar + slider manual) ====
        -- Ukuran dasar window 690x470 px. Di HP ukuran itu nutup hampir seluruh
        -- layar, jadi seluruh window (dan anak-anaknya) di-skala lewat UIScale.
        -- Skala = autoFit(viewport) x userScale, dan dihitung ulang tiap kali
        -- ViewportSize berubah (rotasi layar / masuk split-screen).
        local BASE_W, BASE_H = 690, 470
        local mainScale = Instance.new("UIScale")
        mainScale.Name = "NYBUIScale"
        mainScale.Parent = mainFrame

        local function viewportSize()
            local cam = workspace.CurrentCamera
            local vp = cam and cam.ViewportSize
            if not vp or vp.X <= 0 or vp.Y <= 0 then
                return Vector2.new(BASE_W, BASE_H)
            end
            return vp
        end

        -- Window dibatasi maksimal 82% lebar & 88% tinggi viewport, dan
        -- tidak pernah diperbesar melebihi ukuran dasar.
        local function autoFitScale()
            local vp = viewportSize()
            local fitW = (vp.X * 0.82) / BASE_W
            local fitH = (vp.Y * 0.88) / BASE_H
            return math.clamp(math.min(fitW, fitH, 1), 0.40, 1)
        end

        local function userScale()
            if type(CFG) ~= "table" then return 1 end
            return math.clamp(tonumber(CFG.UIScale) or 1, 0.40, 1.30)
        end

        local function applyScale()
            local auto = (type(CFG) ~= "table") or (CFG.UIScaleAuto ~= false)
            mainScale.Scale = (auto and autoFitScale() or 1) * userScale()
        end

        local function hookCamera()
            local cam = workspace.CurrentCamera
            if not cam then return end
            cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyScale)
        end
        hookCamera()
        workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            task.defer(function()
                hookCamera()
                applyScale()
            end)
        end)

        applyScale()

        -- Header Frame (Draggable)
        local header = Instance.new("Frame")
        header.Name = "Header"
        header.Size = UDim2.new(1, 0, 0, 52)
        header.BackgroundColor3 = Color3.fromRGB(22, 15, 36)
        header.BackgroundTransparency = 0.35
        header.BorderSizePixel = 0
        header.Parent = mainFrame

        local headerCorner = Instance.new("UICorner")
        headerCorner.CornerRadius = UDim.new(0, 14)
        headerCorner.Parent = header

        local headerMask = Instance.new("Frame")
        headerMask.Size = UDim2.new(1, 0, 0, 14)
        headerMask.Position = UDim2.new(0, 0, 1, -14)
        headerMask.BackgroundColor3 = Color3.fromRGB(22, 15, 36)
        headerMask.BackgroundTransparency = 0.35
        headerMask.BorderSizePixel = 0
        headerMask.Parent = header

        local headerLine = Instance.new("Frame")
        headerLine.Size = UDim2.new(1, 0, 0, 1)
        headerLine.Position = UDim2.new(0, 0, 1, 0)
        headerLine.BackgroundColor3 = Color3.fromRGB(160, 110, 225)
        headerLine.BackgroundTransparency = 0.7
        headerLine.BorderSizePixel = 0
        headerLine.Parent = header

        local logoImg = Instance.new("ImageLabel")
        logoImg.Name = "Logo"
        logoImg.Image = logoAsset
        logoImg.Size = UDim2.new(0, 36, 0, 36)
        logoImg.Position = UDim2.new(0, 12, 0.5, -18)
        logoImg.BackgroundTransparency = 1
        logoImg.ScaleType = Enum.ScaleType.Fit
        logoImg.Parent = header

        local logoCorner = Instance.new("UICorner")
        logoCorner.CornerRadius = UDim.new(0, 8)
        logoCorner.Parent = logoImg

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Text = windowTitle
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.TextSize = 17
        titleLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.BackgroundTransparency = 1
        titleLbl.Position = UDim2.new(0, 56, 0, 8)
        titleLbl.Size = UDim2.new(0, 200, 0, 20)
        titleLbl.Parent = header

        local subLbl = Instance.new("TextLabel")
        subLbl.Text = windowSubtitle
        subLbl.Font = Enum.Font.GothamMedium
        subLbl.TextSize = 11
        subLbl.TextColor3 = Color3.fromRGB(185, 160, 225)
        subLbl.TextXAlignment = Enum.TextXAlignment.Left
        subLbl.BackgroundTransparency = 1
        subLbl.Position = UDim2.new(0, 56, 0, 28)
        subLbl.Size = UDim2.new(0, 200, 0, 16)
        subLbl.Parent = header

        -- Controls on header
        local controlsFrame = Instance.new("Frame")
        controlsFrame.Size = UDim2.new(0, 70, 1, 0)
        controlsFrame.Position = UDim2.new(1, -75, 0, 0)
        controlsFrame.BackgroundTransparency = 1
        controlsFrame.Parent = header

        local minBtn = Instance.new("TextButton")
        minBtn.Name = "MinBtn"
        minBtn.Text = "-"
        minBtn.Font = Enum.Font.GothamBold
        minBtn.TextSize = 18
        minBtn.TextColor3 = Color3.fromRGB(220, 210, 240)
        minBtn.Size = UDim2.new(0, 28, 0, 28)
        minBtn.Position = UDim2.new(0, 0, 0.5, -14)
        minBtn.BackgroundColor3 = Color3.fromRGB(40, 28, 60)
        minBtn.BackgroundTransparency = 0.5
        minBtn.Parent = controlsFrame

        local minCorner = Instance.new("UICorner")
        minCorner.CornerRadius = UDim.new(0, 6)
        minCorner.Parent = minBtn

        local closeBtn = Instance.new("TextButton")
        closeBtn.Name = "CloseBtn"
        closeBtn.Text = "X"
        closeBtn.Font = Enum.Font.GothamBold
        closeBtn.TextSize = 13
        closeBtn.TextColor3 = Color3.fromRGB(255, 140, 160)
        closeBtn.Size = UDim2.new(0, 28, 0, 28)
        closeBtn.Position = UDim2.new(0, 36, 0.5, -14)
        closeBtn.BackgroundColor3 = Color3.fromRGB(40, 28, 60)
        closeBtn.BackgroundTransparency = 0.5
        closeBtn.Parent = controlsFrame

        local closeCorner = Instance.new("UICorner")
        closeCorner.CornerRadius = UDim.new(0, 6)
        closeCorner.Parent = closeBtn

        -- Smooth Dragging
        local isDragging = false
        local dragStart, startPos
        header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isDragging = true
                dragStart = input.Position
                startPos = mainFrame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        isDragging = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                -- delta mouse ada di ruang piksel layar, sedangkan Position offset
                -- window ikut di-skala -> bagi dengan skala biar geraknya 1:1 sama jari
                local sc = math.max(mainScale.Scale, 0.05)
                local delta = (input.Position - dragStart) / sc
                mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)

        -- Left Sidebar for Tabs
        local sidebar = Instance.new("Frame")
        sidebar.Name = "Sidebar"
        sidebar.Size = UDim2.new(0, 160, 1, -53)
        sidebar.Position = UDim2.new(0, 0, 0, 53)
        sidebar.BackgroundColor3 = Color3.fromRGB(18, 12, 30)
        sidebar.BackgroundTransparency = 0.35
        sidebar.BorderSizePixel = 0
        sidebar.Parent = mainFrame

        local sidebarCorner = Instance.new("UICorner")
        sidebarCorner.CornerRadius = UDim.new(0, 14)
        sidebarCorner.Parent = sidebar

        local sidebarDivider = Instance.new("Frame")
        sidebarDivider.Size = UDim2.new(0, 1, 1, 0)
        sidebarDivider.Position = UDim2.new(1, -1, 0, 0)
        sidebarDivider.BackgroundColor3 = Color3.fromRGB(160, 110, 225)
        sidebarDivider.BackgroundTransparency = 0.7
        sidebarDivider.BorderSizePixel = 0
        sidebarDivider.Parent = sidebar

        local tabList = Instance.new("ScrollingFrame")
        tabList.Name = "TabList"
        tabList.Size = UDim2.new(1, -16, 1, -78)
        tabList.Position = UDim2.new(0, 8, 0, 8)
        tabList.BackgroundTransparency = 1
        tabList.ScrollBarThickness = 0
        tabList.CanvasSize = UDim2.new(0, 0, 0, 0)
        tabList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        tabList.Parent = sidebar

        -- User Profile Card (Bottom Left Corner)
        local profileCard = Instance.new("Frame")
        profileCard.Name = "UserProfileCard"
        profileCard.Position = UDim2.new(0, 8, 1, -64)
        profileCard.Size = UDim2.new(1, -16, 0, 56)
        profileCard.BackgroundColor3 = Color3.fromRGB(22, 14, 36)
        profileCard.BackgroundTransparency = 0.35
        profileCard.BorderSizePixel = 0
        profileCard.Parent = sidebar

        local pCorner = Instance.new("UICorner")
        pCorner.CornerRadius = UDim.new(0, 10)
        pCorner.Parent = profileCard

        lib:ApplyShimmer(profileCard, 1.2)

        -- Avatar Headshot
        local avatarImg = Instance.new("ImageLabel")
        avatarImg.Name = "Avatar"
        avatarImg.Size = UDim2.new(0, 38, 0, 38)
        avatarImg.Position = UDim2.new(0, 6, 0.5, -19)
        avatarImg.BackgroundColor3 = Color3.fromRGB(35, 22, 55)
        avatarImg.BackgroundTransparency = 0.3
        avatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(localPlayer.UserId) .. "&w=150&h=150"
        avatarImg.Parent = profileCard

        local avCorner = Instance.new("UICorner")
        avCorner.CornerRadius = UDim.new(1, 0)
        avCorner.Parent = avatarImg

        local avStroke = Instance.new("UIStroke")
        avStroke.Thickness = 1.2
        avStroke.Color = Color3.fromRGB(180, 130, 255)
        avStroke.Transparency = 0.4
        avStroke.Parent = avatarImg

        task.spawn(function()
            pcall(function()
                local content, isReady = Players:GetUserThumbnailAsync(localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
                if isReady and content and content ~= "" then
                    avatarImg.Image = content
                end
            end)
        end)

        -- Display Name
        local dName = Instance.new("TextLabel")
        dName.Name = "DisplayName"
        dName.Text = localPlayer.DisplayName or localPlayer.Name
        dName.Font = Enum.Font.GothamBold
        dName.TextSize = 12
        dName.TextColor3 = Color3.fromRGB(255, 255, 255)
        dName.TextXAlignment = Enum.TextXAlignment.Left
        dName.TextTruncate = Enum.TextTruncate.AtEnd
        dName.BackgroundTransparency = 1
        dName.Position = UDim2.new(0, 50, 0, 8)
        dName.Size = UDim2.new(1, -54, 0, 15)
        dName.Parent = profileCard

        -- Status badge
        local statusBadge = Instance.new("TextLabel")
        statusBadge.Name = "StatusBadge"
        statusBadge.Text = "NYB Hub"
        statusBadge.Font = Enum.Font.GothamMedium
        statusBadge.TextSize = 10
        statusBadge.TextColor3 = Color3.fromRGB(140, 255, 175)
        statusBadge.TextXAlignment = Enum.TextXAlignment.Left
        statusBadge.BackgroundTransparency = 1
        statusBadge.Position = UDim2.new(0, 50, 0, 27)
        statusBadge.Size = UDim2.new(1, -54, 0, 14)
        statusBadge.Parent = profileCard

        local tabLayout = Instance.new("UIListLayout")
        tabLayout.FillDirection = Enum.FillDirection.Vertical
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        tabLayout.Padding = UDim.new(0, 6)
        tabLayout.Parent = tabList

        -- Content Area
        local contentArea = Instance.new("Frame")
        contentArea.Name = "ContentArea"
        contentArea.Size = UDim2.new(1, -162, 1, -54)
        contentArea.Position = UDim2.new(0, 161, 0, 53)
        contentArea.BackgroundTransparency = 1
        contentArea.ClipsDescendants = true
        contentArea.Parent = mainFrame

        -- Bottom-Right Window Resize Handle (with min/max limits)
        local resizeGrip = Instance.new("Frame")
        resizeGrip.Name = "ResizeGrip"
        resizeGrip.AnchorPoint = Vector2.new(1, 1)
        resizeGrip.Position = UDim2.new(1, -2, 1, -2)
        resizeGrip.Size = UDim2.new(0, 18, 0, 18)
        resizeGrip.BackgroundTransparency = 1
        resizeGrip.ZIndex = 80
        resizeGrip.Parent = mainFrame

        -- 3 Diagonal grip lines
        for i = 1, 3 do
            local gLine = Instance.new("Frame")
            gLine.Size = UDim2.new(0, 13 - (i-1)*4, 0, 2)
            gLine.AnchorPoint = Vector2.new(1, 1)
            gLine.Position = UDim2.new(1, -2, 1, -2 - (i-1)*4)
            gLine.BackgroundColor3 = Color3.fromRGB(190, 150, 255)
            gLine.BackgroundTransparency = 0.35
            gLine.BorderSizePixel = 0
            gLine.ZIndex = 81
            gLine.Parent = resizeGrip
            local glc = Instance.new("UICorner")
            glc.CornerRadius = UDim.new(0, 1)
            glc.Parent = gLine
        end

        local isResizing = false
        local resizeStartMouse, resizeStartSize
        resizeGrip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isResizing = true
                resizeStartMouse = input.Position
                resizeStartSize = mainFrame.AbsoluteSize
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        isResizing = false
                    end
                end)
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if isResizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local sc = math.max(mainScale.Scale, 0.05)
                local delta = (input.Position - resizeStartMouse) / sc
                -- AbsoluteSize sudah ikut skala -> balikin ke ukuran dasar dulu
                local baseW = resizeStartSize.X / sc
                local baseH = resizeStartSize.Y / sc
                -- Batas atas ikut viewport, jadi window gak bisa ditarik lebih besar dari layar
                local vp = viewportSize()
                local maxW = math.max(420, (vp.X * 0.98) / sc)
                local maxH = math.max(340, (vp.Y * 0.98) / sc)
                local newW = math.clamp(baseW + delta.X, 420, maxW)
                local newH = math.clamp(baseH + delta.Y, 340, maxH)
                mainFrame.Size = UDim2.new(0, newW, 0, newH)
            end
        end)

        local window = {
            Gui = mainGui,
            Frame = mainFrame,
            Tabs = {},
            CurrentTab = nil,
            IsMinimized = false,
            IsLocked = false,
            -- UI scale API (dipakai tab Misc -> UI)
            ApplyScale = applyScale,
            AutoFitScale = autoFitScale,
            GetScale = function() return mainScale.Scale end,
            ResetSize = function()
                if type(CFG) == "table" then
                    CFG.UIScaleAuto = true
                    CFG.UIScale = 0.9
                end
                mainFrame.Size = UDim2.new(0, BASE_W, 0, BASE_H)
                mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
                applyScale()
            end,
        }

        local originalSize = mainFrame.Size
        minBtn.MouseButton1Click:Connect(function()
            window.IsMinimized = not window.IsMinimized
            if window.IsMinimized then
                TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset, 0, 52)
                }):Play()
                sidebar.Visible = false
                contentArea.Visible = false
                minBtn.Text = "+"
            else
                TweenService:Create(mainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Size = originalSize
                }):Play()
                sidebar.Visible = true
                contentArea.Visible = true
                minBtn.Text = "-"
            end
        end)

        -- Floating Mobile / Quick-Open Toggle Button
        local alwaysShowMobile = false
        local mobileToggle = Instance.new("TextButton")
        mobileToggle.Name = "NYBMobileToggle"
        mobileToggle.Size = UDim2.new(0, 48, 0, 48)
        mobileToggle.Position = UDim2.new(0, 18, 0.45, -24)
        mobileToggle.BackgroundColor3 = Color3.fromRGB(22, 14, 36)
        mobileToggle.BackgroundTransparency = 0.25
        mobileToggle.BorderSizePixel = 0
        mobileToggle.Text = ""
        mobileToggle.AutoButtonColor = false
        mobileToggle.Visible = false
        mobileToggle.ZIndex = 200
        mobileToggle.Parent = mainGui

        local mtCorner = Instance.new("UICorner")
        mtCorner.CornerRadius = UDim.new(0, 24)
        mtCorner.Parent = mobileToggle

        local mtStroke = Instance.new("UIStroke")
        mtStroke.Thickness = 1.5
        mtStroke.Color = Color3.fromRGB(180, 120, 255)
        mtStroke.Transparency = 0.3
        mtStroke.Parent = mobileToggle

        local mtLogo = Instance.new("ImageLabel")
        mtLogo.Name = "Logo"
        mtLogo.Size = UDim2.new(1, -12, 1, -12)
        mtLogo.Position = UDim2.new(0, 6, 0, 6)
        mtLogo.BackgroundTransparency = 1
        mtLogo.Image = logoAsset
        mtLogo.ImageColor3 = Color3.fromRGB(240, 230, 255)
        mtLogo.ScaleType = Enum.ScaleType.Fit
        mtLogo.ZIndex = 201
        mtLogo.Parent = mobileToggle

        lib:ApplyShimmer(mobileToggle, 1.5)

        local isMenuOpen = true
        local lastToggleTick = 0

        local function SetMenuOpen(open)
            local now = tick()
            if now - lastToggleTick < 0.25 then return end
            lastToggleTick = now

            isMenuOpen = open == true
            if isMenuOpen then
                mainFrame.Visible = true
                mainFrame.BackgroundTransparency = 0.20
                if not window.IsMinimized then
                    sidebar.Visible = true
                    contentArea.Visible = true
                end

                if not alwaysShowMobile then
                    mobileToggle.Visible = false
                end
            else
                mainFrame.Visible = false

                mobileToggle.Visible = true
                mobileToggle.BackgroundTransparency = 0.25
                mtLogo.ImageTransparency = 0
            end
        end

        local function ToggleMenu()
            SetMenuOpen(not isMenuOpen)
        end

        -- Clean Dragging & Clicking for Mobile/Desktop Toggle Button
        local isDraggingMT = false
        local dragStartPos = nil
        local startPosMT = nil
        local hasDragged = false

        mobileToggle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                isDraggingMT = true
                hasDragged = false
                dragStartPos = input.Position
                startPosMT = mobileToggle.Position
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if isDraggingMT and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                if dragStartPos and startPosMT then
                    local delta = input.Position - dragStartPos
                    if delta.Magnitude > 8 then
                        hasDragged = true
                        mobileToggle.Position = UDim2.new(
                            startPosMT.X.Scale,
                            startPosMT.X.Offset + delta.X,
                            startPosMT.Y.Scale,
                            startPosMT.Y.Offset + delta.Y
                        )
                    end
                end
            end
        end)

        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if isDraggingMT then
                    isDraggingMT = false
                    if not hasDragged then
                        SetMenuOpen(true)
                    end
                end
            end
        end)

        -- Backup click handler for mobileToggle
        mobileToggle.MouseButton1Click:Connect(function()
            if not hasDragged then
                SetMenuOpen(true)
            end
        end)

        closeBtn.MouseButton1Click:Connect(function()
            SetMenuOpen(false)
        end)

        UserInputService.InputBegan:Connect(function(input, gpe)
            if not gpe and input.KeyCode == lib.MenuKey then
                ToggleMenu()
            end
        end)

        function window:SetMenuKey(key)
            if typeof(key) == "EnumItem" then
                lib.MenuKey = key
            elseif type(key) == "string" and Enum.KeyCode[key] then
                lib.MenuKey = Enum.KeyCode[key]
            end
        end

        function window:SetLocked(bool)
            window.IsLocked = bool
        end

        function window:SetAlwaysShowMobileButton(bool)
            alwaysShowMobile = bool == true
            if alwaysShowMobile then
                mobileToggle.Visible = true
                mobileToggle.BackgroundTransparency = 0.25
                mtLogo.ImageTransparency = 0
            elseif isMenuOpen then
                mobileToggle.Visible = false
            end
        end

        function window:ToggleMenu()
            ToggleMenu()
        end

        local TAB_DEFAULT_ICONS = {
            ["Main"] = "rbxassetid://10723345749",       -- Home
            ["Survivor"] = "rbxassetid://10709791437",   -- Shield / Survivor
            ["Killer"] = "rbxassetid://10734950309",     -- Crossed Swords
            ["Visual"] = "rbxassetid://10709769841",     -- Eye / ESP
            ["Teleport"] = "rbxassetid://10723346959",   -- MapPin / Teleport
            ["Settings"] = "rbxassetid://10734950020",   -- Settings Gear
        }

        function window:CreateTab(tabName, icon, ...)
            local iconAsset = (type(icon) == "string" and icon ~= "") and icon or (TAB_DEFAULT_ICONS[tabName] or "rbxassetid://10723345749")

            local tabBtn = Instance.new("TextButton")
            tabBtn.Name = "Tab_" .. tabName
            tabBtn.Size = UDim2.new(1, 0, 0, 38)
            tabBtn.BackgroundColor3 = Color3.fromRGB(30, 20, 50)
            tabBtn.BackgroundTransparency = 0.7
            tabBtn.BorderSizePixel = 0
            tabBtn.Text = ""
            tabBtn.AutoButtonColor = false
            tabBtn.Parent = tabList

            -- Tab Icon Image
            local tabIcon = Instance.new("ImageLabel")
            tabIcon.Name = "Icon"
            tabIcon.Image = iconAsset
            tabIcon.Size = UDim2.new(0, 18, 0, 18)
            tabIcon.Position = UDim2.new(0, 12, 0.5, -9)
            tabIcon.BackgroundTransparency = 1
            tabIcon.ImageColor3 = Color3.fromRGB(180, 160, 220)
            tabIcon.ScaleType = Enum.ScaleType.Fit
            tabIcon.Parent = tabBtn

            -- Tab Title Text
            local tabTitle = Instance.new("TextLabel")
            tabTitle.Name = "Title"
            tabTitle.Text = tabName
            tabTitle.Font = Enum.Font.GothamMedium
            tabTitle.TextSize = 13
            tabTitle.TextColor3 = Color3.fromRGB(200, 185, 230)
            tabTitle.TextXAlignment = Enum.TextXAlignment.Left
            tabTitle.BackgroundTransparency = 1
            tabTitle.Position = UDim2.new(0, 38, 0, 0)
            tabTitle.Size = UDim2.new(1, -44, 1, 0)
            tabTitle.Parent = tabBtn

            local tabBtnCorner = Instance.new("UICorner")
            tabBtnCorner.CornerRadius = UDim.new(0, 8)
            tabBtnCorner.Parent = tabBtn

            local pageScroll = Instance.new("ScrollingFrame")
            pageScroll.Name = "Page_" .. tabName
            pageScroll.Size = UDim2.new(1, -20, 1, -20)
            pageScroll.Position = UDim2.new(0, 10, 0, 10)
            pageScroll.BackgroundTransparency = 1
            pageScroll.BorderSizePixel = 0
            pageScroll.ScrollBarThickness = 3
            pageScroll.ScrollBarImageColor3 = Color3.fromRGB(180, 120, 255)
            pageScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
            pageScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
            pageScroll.Visible = false
            pageScroll.Parent = contentArea

            local pageLayout = Instance.new("UIListLayout")
            pageLayout.FillDirection = Enum.FillDirection.Vertical
            pageLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            pageLayout.Padding = UDim.new(0, 12)
            pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
            pageLayout.Parent = pageScroll

            local tabObj = {
                Name = tabName,
                Button = tabBtn,
                Page = pageScroll,
                Sections = {}
            }

            local function ActivateTab()
                for _, t in ipairs(window.Tabs) do
                    t.Page.Visible = false
                    TweenService:Create(t.Button, TweenInfo.new(0.2), {
                        BackgroundColor3 = Color3.fromRGB(30, 20, 50),
                        BackgroundTransparency = 0.7
                    }):Play()
                    local bTitle = t.Button:FindFirstChild("Title")
                    if bTitle then
                        TweenService:Create(bTitle, TweenInfo.new(0.2), { TextColor3 = Color3.fromRGB(200, 185, 230) }):Play()
                    end
                    local bIcon = t.Button:FindFirstChild("Icon")
                    if bIcon then
                        TweenService:Create(bIcon, TweenInfo.new(0.2), { ImageColor3 = Color3.fromRGB(175, 155, 215) }):Play()
                    end
                    local str = t.Button:FindFirstChildOfClass("UIStroke")
                    if str then str.Enabled = false end
                end

                pageScroll.Visible = true
                TweenService:Create(tabBtn, TweenInfo.new(0.2), {
                    BackgroundColor3 = Color3.fromRGB(130, 70, 220),
                    BackgroundTransparency = 0.35
                }):Play()
                if tabTitle then
                    TweenService:Create(tabTitle, TweenInfo.new(0.2), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
                end
                if tabIcon then
                    TweenService:Create(tabIcon, TweenInfo.new(0.2), { ImageColor3 = Color3.fromRGB(255, 255, 255) }):Play()
                end

                local activeStroke = tabBtn:FindFirstChildOfClass("UIStroke")
                if not activeStroke then
                    activeStroke = Instance.new("UIStroke")
                    activeStroke.Thickness = 1.2
                    activeStroke.Color = Color3.fromRGB(200, 160, 255)
                    activeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    activeStroke.Parent = tabBtn
                end
                activeStroke.Enabled = true
                window.CurrentTab = tabObj
            end

            tabBtn.MouseButton1Click:Connect(ActivateTab)

            function tabObj:CreatePage(pageName)
                return tabObj
            end

            function tabObj:CreateSection(secName, secIcon)
                local sectionCard = Instance.new("Frame")
                sectionCard.Name = "Card_" .. secName
                sectionCard.Size = UDim2.new(1, -6, 0, 0)
                sectionCard.AutomaticSize = Enum.AutomaticSize.Y
                sectionCard.BackgroundColor3 = Color3.fromRGB(24, 16, 40)
                sectionCard.BackgroundTransparency = 0.45
                sectionCard.BorderSizePixel = 0
                sectionCard.Parent = pageScroll

                local secCorner = Instance.new("UICorner")
                secCorner.CornerRadius = UDim.new(0, 10)
                secCorner.Parent = sectionCard

                local secStroke = Instance.new("UIStroke")
                secStroke.Thickness = 1
                secStroke.Color = Color3.fromRGB(140, 95, 215)
                secStroke.Transparency = 0.5
                secStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                secStroke.Parent = sectionCard

                local secHeader = Instance.new("Frame")
                secHeader.Name = "SecHeader"
                secHeader.Size = UDim2.new(1, 0, 0, 32)
                secHeader.BackgroundTransparency = 1
                secHeader.Parent = sectionCard

                local secTitle = Instance.new("TextLabel")
                secTitle.Text = secName
                secTitle.Font = Enum.Font.GothamBold
                secTitle.TextSize = 13
                secTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
                secTitle.TextXAlignment = Enum.TextXAlignment.Left
                secTitle.Position = UDim2.new(0, 12, 0, 0)
                secTitle.Size = UDim2.new(1, -24, 1, 0)
                secTitle.BackgroundTransparency = 1
                secTitle.Parent = secHeader

                local secLine = Instance.new("Frame")
                secLine.Size = UDim2.new(1, -24, 0, 1)
                secLine.Position = UDim2.new(0, 12, 1, -1)
                secLine.BackgroundColor3 = Color3.fromRGB(130, 85, 200)
                secLine.BackgroundTransparency = 0.6
                secLine.BorderSizePixel = 0
                secLine.Parent = secHeader

                local itemsFrame = Instance.new("Frame")
                itemsFrame.Name = "ItemsFrame"
                itemsFrame.Size = UDim2.new(1, -24, 0, 0)
                itemsFrame.Position = UDim2.new(0, 12, 0, 36)
                itemsFrame.AutomaticSize = Enum.AutomaticSize.Y
                itemsFrame.BackgroundTransparency = 1
                itemsFrame.Parent = sectionCard

                local itemsLayout = Instance.new("UIListLayout")
                itemsLayout.FillDirection = Enum.FillDirection.Vertical
                itemsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
                itemsLayout.Padding = UDim.new(0, 8)
                itemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
                itemsLayout.Parent = itemsFrame

                local paddingBottom = Instance.new("UIPadding")
                paddingBottom.PaddingBottom = UDim.new(0, 10)
                paddingBottom.Parent = itemsFrame

                local section = {
                    Name = secName,
                    Card = sectionCard,
                    ItemsFrame = itemsFrame
                }

                                -- 1. ADD TOGGLE
                function section:AddToggle(toggleName, defaultVal, callback, opts)
                    defaultVal = defaultVal == true
                    callback = callback or function() end
                    opts = opts or {}
                    local flagName = (type(opts) == "table" and opts.Flag) or toggleName

                    local toggleRow = Instance.new("Frame")
                    toggleRow.Name = "Toggle_" .. toggleName
                    toggleRow.Size = UDim2.new(1, 0, 0, 32)
                    toggleRow.BackgroundTransparency = 1
                    toggleRow.Parent = itemsFrame

                    local label = Instance.new("TextLabel")
                    label.Text = toggleName
                    label.Font = Enum.Font.Gotham
                    label.TextSize = 13
                    label.TextColor3 = Color3.fromRGB(240, 235, 255)
                    label.TextXAlignment = Enum.TextXAlignment.Left
                    label.BackgroundTransparency = 1
                    label.Position = UDim2.new(0, 4, 0, 0)
                    label.Size = UDim2.new(1, -120, 1, 0)
                    label.Parent = toggleRow

                    local rightControls = Instance.new("Frame")
                    rightControls.Name = "RightControls"
                    rightControls.AnchorPoint = Vector2.new(1, 0.5)
                    rightControls.Position = UDim2.new(1, -4, 0.5, 0)
                    rightControls.Size = UDim2.new(0, 110, 0, 24)
                    rightControls.BackgroundTransparency = 1
                    rightControls.Parent = toggleRow

                    local rightLayout = Instance.new("UIListLayout")
                    rightLayout.FillDirection = Enum.FillDirection.Horizontal
                    rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
                    rightLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                    rightLayout.Padding = UDim.new(0, 6)
                    rightLayout.Parent = rightControls

                    local switchBtn = Instance.new("TextButton")
                    switchBtn.Name = "Switch"
                    switchBtn.Size = UDim2.new(0, 42, 0, 22)
                    switchBtn.BackgroundColor3 = defaultVal and Color3.fromRGB(150, 75, 255) or Color3.fromRGB(42, 28, 64)
                    switchBtn.BackgroundTransparency = 0.35
                    switchBtn.BorderSizePixel = 0
                    switchBtn.Text = ""
                    switchBtn.AutoButtonColor = false
                    switchBtn.LayoutOrder = 100
                    switchBtn.Parent = rightControls

                    local switchCorner = Instance.new("UICorner")
                    switchCorner.CornerRadius = UDim.new(0, 11)
                    switchCorner.Parent = switchBtn

                    local knob = Instance.new("Frame")
                    knob.Name = "Knob"
                    knob.Size = UDim2.new(0, 16, 0, 16)
                    knob.Position = defaultVal and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
                    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    knob.BorderSizePixel = 0
                    knob.Parent = switchBtn

                    local knobCorner = Instance.new("UICorner")
                    knobCorner.CornerRadius = UDim.new(0, 8)
                    knobCorner.Parent = knob

                    local state = defaultVal
                    local toggleObj = { State = state }

                    local function SetState(newVal)
                        state = newVal == true
                        toggleObj.State = state
                        lib.Flags[flagName] = state
                        if state then
                            TweenService:Create(switchBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(150, 75, 255) }):Play()
                            TweenService:Create(knob, TweenInfo.new(0.2), { Position = UDim2.new(1, -19, 0.5, -8) }):Play()
                        else
                            TweenService:Create(switchBtn, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(42, 28, 64) }):Play()
                            TweenService:Create(knob, TweenInfo.new(0.2), { Position = UDim2.new(0, 3, 0.5, -8) }):Play()
                        end
                        pcall(callback, state)
                    end

                    switchBtn.MouseButton1Click:Connect(function()
                        SetState(not state)
                    end)

                    function toggleObj:SetValue(val)
                        SetState(val)
                    end

                    function toggleObj:GetValue()
                        return state
                    end

                    function toggleObj:AddKeyPicker(keyOrName, pOpts)
                        pOpts = pOpts or {}
                        local currentKey = "None"
                        if type(keyOrName) == "string" and keyOrName ~= "None" and not pOpts.Default then
                            currentKey = keyOrName
                        elseif pOpts.Default then
                            currentKey = pOpts.Default
                        end

                        local keyBtn = Instance.new("TextButton")
                        keyBtn.Name = "KeyPicker"
                        keyBtn.Size = UDim2.new(0, 48, 0, 20)
                        keyBtn.BackgroundColor3 = Color3.fromRGB(50, 34, 75)
                        keyBtn.BackgroundTransparency = 0.4
                        keyBtn.BorderSizePixel = 0
                        keyBtn.Text = "[" .. currentKey .. "]"
                        keyBtn.Font = Enum.Font.GothamMedium
                        keyBtn.TextSize = 11
                        keyBtn.TextColor3 = Color3.fromRGB(200, 185, 230)
                        keyBtn.AutoButtonColor = false
                        keyBtn.LayoutOrder = 10
                        keyBtn.Parent = rightControls

                        local keyCorner = Instance.new("UICorner")
                        keyCorner.CornerRadius = UDim.new(0, 5)
                        keyCorner.Parent = keyBtn

                        local isBinding = false
                        keyBtn.MouseButton1Click:Connect(function()
                            if isBinding then return end
                            isBinding = true
                            keyBtn.Text = "[...]"
                            local conn
                            conn = UserInputService.InputBegan:Connect(function(inp)
                                if inp.UserInputType == Enum.UserInputType.Keyboard then
                                    if inp.KeyCode == Enum.KeyCode.Backspace or inp.KeyCode == Enum.KeyCode.Escape then
                                        currentKey = "None"
                                    else
                                        currentKey = inp.KeyCode.Name
                                    end
                                    keyBtn.Text = "[" .. currentKey .. "]"
                                    lib.Flags[flagName .. "_Key"] = currentKey
                                    isBinding = false
                                    conn:Disconnect()
                                    if pOpts.Callback then
                                        pcall(pOpts.Callback, currentKey)
                                    end
                                end
                            end)
                        end)

                        UserInputService.InputBegan:Connect(function(inp, gpe)
                            if not gpe and inp.UserInputType == Enum.UserInputType.Keyboard then
                                if currentKey ~= "None" and inp.KeyCode.Name == currentKey then
                                    SetState(not state)
                                end
                            end
                        end)

                        local keyFlag = (pOpts and pOpts.Flag) or (flagName .. "_Key")
                        lib.Flags[keyFlag] = currentKey
                        lib.Elements[keyFlag] = {
                            Type = "Keybind",
                            Name = keyFlag,
                            Flag = keyFlag,
                            Get = function() return currentKey end,
                            Set = function(k)
                                currentKey = tostring(k or "None")
                                lib.Flags[keyFlag] = currentKey
                                keyBtn.Text = "[" .. currentKey .. "]"
                                if pOpts and pOpts.Callback then
                                    pcall(pOpts.Callback, currentKey)
                                end
                            end
                        }

                        return keyBtn
                    end

                    function toggleObj:AddColorPicker(arg1, arg2)
                        local defColor = typeof(arg1) == "Color3" and arg1 or (typeof(arg2) == "table" and arg2.Default or Color3.fromRGB(255, 255, 255))
                        local cpOpts = typeof(arg2) == "table" and arg2 or (typeof(arg1) == "table" and arg1 or {})
                        local cpCallback = cpOpts.Callback or function() end

                        local swatch = Instance.new("TextButton")
                        swatch.Name = "ColorPickerSwatch"
                        swatch.Size = UDim2.new(0, 20, 0, 20)
                        swatch.BackgroundColor3 = defColor
                        swatch.BorderSizePixel = 0
                        swatch.Text = ""
                        swatch.AutoButtonColor = false
                        swatch.LayoutOrder = 5
                        swatch.Parent = rightControls

                        local sCorner = Instance.new("UICorner")
                        sCorner.CornerRadius = UDim.new(0, 4)
                        sCorner.Parent = swatch

                        local colorsList = {
                            Color3.fromRGB(255, 255, 255),
                            Color3.fromRGB(180, 130, 255),
                            Color3.fromRGB(255, 75, 75),
                            Color3.fromRGB(75, 255, 120),
                            Color3.fromRGB(255, 220, 75),
                            Color3.fromRGB(75, 180, 255),
                            Color3.fromRGB(255, 120, 220)
                        }
                        local cIdx = 1
                        swatch.MouseButton1Click:Connect(function()
                            cIdx = (cIdx % #colorsList) + 1
                            local newC = colorsList[cIdx]
                            swatch.BackgroundColor3 = newC
                            lib.Flags[flagName .. "_Color"] = { R = newC.R, G = newC.G, B = newC.B }
                            pcall(cpCallback, newC)
                        end)

                        local cpFlag = (cpOpts and cpOpts.Flag) or (flagName .. "_Color")
                        lib.Flags[cpFlag] = { R = defColor.R, G = defColor.G, B = defColor.B }
                        lib.Elements[cpFlag] = {
                            Type = "Color",
                            Name = cpFlag,
                            Flag = cpFlag,
                            Get = function() return swatch.BackgroundColor3 end,
                            Set = function(col)
                                if typeof(col) == "Color3" then
                                    swatch.BackgroundColor3 = col
                                    lib.Flags[cpFlag] = { R = col.R, G = col.G, B = col.B }
                                    pcall(cpCallback, col)
                                elseif type(col) == "table" and col.R and col.G and col.B then
                                    local c3 = Color3.new(col.R, col.G, col.B)
                                    swatch.BackgroundColor3 = c3
                                    lib.Flags[cpFlag] = col
                                    pcall(cpCallback, c3)
                                end
                            end
                        }

                        return swatch
                    end

                    lib.Flags[flagName] = defaultVal
                    lib.Elements[flagName] = {
                        Type = "Toggle",
                        Name = toggleName,
                        Flag = flagName,
                        Get = function() return toggleObj.State end,
                        Set = function(v) SetState(v) end
                    }
                    lib.Options[flagName] = toggleObj

                    return toggleObj
                end

                -- 2. ADD CHECKBOX
                function section:AddCheckbox(cbName, defVal, callback)
                    return section:AddToggle(cbName, defVal, callback)
                end

                -- 3. ADD SLIDER
                function section:AddSlider(sliderName, minVal, maxVal, defVal, callback, opts)
                    minVal = tonumber(minVal) or 0
                    maxVal = tonumber(maxVal) or 100
                    defVal = tonumber(defVal) or minVal
                    callback = callback or function() end
                    opts = opts or {}
                    local flagName = (type(opts) == "table" and opts.Flag) or sliderName

                    local sliderCard = Instance.new("Frame")
                    sliderCard.Name = "Slider_" .. sliderName
                    sliderCard.Size = UDim2.new(1, 0, 0, 46)
                    sliderCard.BackgroundTransparency = 1
                    sliderCard.Parent = itemsFrame

                    local sTitle = Instance.new("TextLabel")
                    sTitle.Text = sliderName
                    sTitle.Font = Enum.Font.Gotham
                    sTitle.TextSize = 13
                    sTitle.TextColor3 = Color3.fromRGB(240, 235, 255)
                    sTitle.TextXAlignment = Enum.TextXAlignment.Left
                    sTitle.BackgroundTransparency = 1
                    sTitle.Position = UDim2.new(0, 4, 0, 0)
                    sTitle.Size = UDim2.new(0.6, 0, 0, 20)
                    sTitle.Parent = sliderCard

                    local valLabel = Instance.new("TextLabel")
                    valLabel.Text = tostring(defVal)
                    valLabel.Font = Enum.Font.GothamMedium
                    valLabel.TextSize = 12
                    valLabel.TextColor3 = Color3.fromRGB(200, 180, 235)
                    valLabel.TextXAlignment = Enum.TextXAlignment.Right
                    valLabel.BackgroundTransparency = 1
                    valLabel.Position = UDim2.new(0.6, 0, 0, 0)
                    valLabel.Size = UDim2.new(0.4, -4, 0, 20)
                    valLabel.Parent = sliderCard

                    local track = Instance.new("Frame")
                    track.Name = "Track"
                    track.Size = UDim2.new(1, -8, 0, 6)
                    track.Position = UDim2.new(0, 4, 0, 28)
                    track.BackgroundColor3 = Color3.fromRGB(48, 32, 68)
                    track.BorderSizePixel = 0
                    track.Parent = sliderCard

                    local trackCorner = Instance.new("UICorner")
                    trackCorner.CornerRadius = UDim.new(0, 3)
                    trackCorner.Parent = track

                    local initialPct = (maxVal == minVal) and 0 or math.clamp((defVal - minVal) / (maxVal - minVal), 0, 1)

                    local fill = Instance.new("Frame")
                    fill.Name = "Fill"
                    fill.Size = UDim2.new(initialPct, 0, 1, 0)
                    fill.BackgroundColor3 = Color3.fromRGB(160, 90, 255)
                    fill.BorderSizePixel = 0
                    fill.Parent = track

                    local fillCorner = Instance.new("UICorner")
                    fillCorner.CornerRadius = UDim.new(0, 3)
                    fillCorner.Parent = fill

                    local knob = Instance.new("Frame")
                    knob.Name = "Knob"
                    knob.AnchorPoint = Vector2.new(0.5, 0.5)
                    knob.Position = UDim2.new(initialPct, 0, 0.5, 0)
                    knob.Size = UDim2.new(0, 14, 0, 14)
                    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    knob.BorderSizePixel = 0
                    knob.Parent = track

                    local knobCorner = Instance.new("UICorner")
                    knobCorner.CornerRadius = UDim.new(0, 7)
                    knobCorner.Parent = knob

                    local currentValue = defVal
                    local isSliding = false

                    local sliderObj = {
                        Value = defVal
                    }

                    local function UpdateFromX(xPos)
                        local pct = math.clamp((xPos - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                        fill.Size = UDim2.new(pct, 0, 1, 0)
                        knob.Position = UDim2.new(pct, 0, 0.5, 0)

                        local rawVal = minVal + (maxVal - minVal) * pct
                        local step = (maxVal - minVal <= 10 and maxVal - minVal > 1) and 0.1 or (maxVal - minVal <= 1 and 0.01 or 1)
                        local rounded = math.floor(rawVal / step + 0.5) * step
                        if step < 1 then
                            currentValue = tonumber(string.format("%.2f", rounded))
                        else
                            currentValue = math.floor(rounded)
                        end
                        sliderObj.Value = currentValue
                        lib.Flags[flagName] = currentValue
                        valLabel.Text = tostring(currentValue)
                        pcall(callback, currentValue)
                    end

                    track.InputBegan:Connect(function(inp)
                        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                            isSliding = true
                            UpdateFromX(inp.Position.X)
                            inp.Changed:Connect(function()
                                if inp.UserInputState == Enum.UserInputState.End then
                                    isSliding = false
                                end
                            end)
                        end
                    end)

                    UserInputService.InputChanged:Connect(function(inp)
                        if isSliding and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                            UpdateFromX(inp.Position.X)
                        end
                    end)

                    function sliderObj:SetValue(val)
                        val = tonumber(val) or minVal
                        currentValue = math.clamp(val, minVal, maxVal)
                        sliderObj.Value = currentValue
                        lib.Flags[flagName] = currentValue
                        local pct = (maxVal == minVal) and 0 or math.clamp((currentValue - minVal) / (maxVal - minVal), 0, 1)
                        fill.Size = UDim2.new(pct, 0, 1, 0)
                        knob.Position = UDim2.new(pct, 0, 0.5, 0)
                        valLabel.Text = tostring(currentValue)
                        pcall(callback, currentValue)
                    end

                    function sliderObj:GetValue()
                        return sliderObj.Value
                    end

                    lib.Flags[flagName] = defVal
                    lib.Elements[flagName] = {
                        Type = "Slider",
                        Name = sliderName,
                        Flag = flagName,
                        Get = function() return sliderObj.Value end,
                        Set = function(v) sliderObj:SetValue(v) end
                    }
                    lib.Options[flagName] = sliderObj

                    return sliderObj
                end

                -- 4. ADD BUTTON
                function section:AddButton(btnName, callback)
                    callback = callback or function() end

                    local btn = Instance.new("TextButton")
                    btn.Name = "Button_" .. btnName
                    btn.Size = UDim2.new(1, 0, 0, 34)
                    btn.BackgroundColor3 = Color3.fromRGB(90, 50, 160)
                    btn.BackgroundTransparency = 0.50
                    btn.BorderSizePixel = 0
                    btn.Text = btnName
                    btn.Font = Enum.Font.GothamBold
                    btn.TextSize = 13
                    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
                    btn.AutoButtonColor = false
                    btn.Parent = itemsFrame

                    local btnCorner = Instance.new("UICorner")
                    btnCorner.CornerRadius = UDim.new(0, 8)
                    btnCorner.Parent = btn

                    lib:ApplyShimmer(btn, 1.5)

                    btn.MouseEnter:Connect(function()
                        TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundTransparency = 0.35 }):Play()
                    end)
                    btn.MouseLeave:Connect(function()
                        TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundTransparency = 0.50 }):Play()
                    end)
                    btn.MouseButton1Click:Connect(function()
                        TweenService:Create(btn, TweenInfo.new(0.08), { BackgroundTransparency = 0.2 }):Play()
                        task.wait(0.08)
                        TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.35 }):Play()
                        pcall(callback)
                    end)

                    return btn
                end

                -- 5. ADD DROPDOWN
                function section:AddDropdown(ddName, optionsList, defaultOpt, callback)
                    optionsList = type(optionsList) == "table" and optionsList or {}
                    callback = callback or function() end
                    local flagName = ddName
                    local selected = defaultOpt or (optionsList[1] or "None")

                    local ddCard = Instance.new("Frame")
                    ddCard.Name = "Dropdown_" .. ddName
                    ddCard.Size = UDim2.new(1, 0, 0, 58)
                    ddCard.AutomaticSize = Enum.AutomaticSize.Y
                    ddCard.BackgroundTransparency = 1
                    ddCard.Parent = itemsFrame

                    local dTitle = Instance.new("TextLabel")
                    dTitle.Text = ddName
                    dTitle.Font = Enum.Font.Gotham
                    dTitle.TextSize = 13
                    dTitle.TextColor3 = Color3.fromRGB(240, 235, 255)
                    dTitle.TextXAlignment = Enum.TextXAlignment.Left
                    dTitle.BackgroundTransparency = 1
                    dTitle.Position = UDim2.new(0, 4, 0, 0)
                    dTitle.Size = UDim2.new(1, -8, 0, 18)
                    dTitle.Parent = ddCard

                    local mainBtn = Instance.new("TextButton")
                    mainBtn.Name = "MainBox"
                    mainBtn.Size = UDim2.new(1, 0, 0, 32)
                    mainBtn.Position = UDim2.new(0, 0, 0, 22)
                    mainBtn.BackgroundColor3 = Color3.fromRGB(36, 24, 56)
                    mainBtn.BackgroundTransparency = 0.4
                    mainBtn.BorderSizePixel = 0
                    mainBtn.Text = "  " .. tostring(selected)
                    mainBtn.Font = Enum.Font.GothamMedium
                    mainBtn.TextSize = 13
                    mainBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                    mainBtn.TextXAlignment = Enum.TextXAlignment.Left
                    mainBtn.AutoButtonColor = false
                    mainBtn.Parent = ddCard

                    local mbCorner = Instance.new("UICorner")
                    mbCorner.CornerRadius = UDim.new(0, 8)
                    mbCorner.Parent = mainBtn

                    local mbStroke = Instance.new("UIStroke")
                    mbStroke.Thickness = 1
                    mbStroke.Color = Color3.fromRGB(150, 105, 225)
                    mbStroke.Transparency = 0.5
                    mbStroke.Parent = mainBtn

                    local arrow = Instance.new("TextLabel")
                    arrow.Text = "▼"
                    arrow.Font = Enum.Font.GothamBold
                    arrow.TextSize = 11
                    arrow.TextColor3 = Color3.fromRGB(180, 140, 240)
                    arrow.BackgroundTransparency = 1
                    arrow.Position = UDim2.new(1, -26, 0, 0)
                    arrow.Size = UDim2.new(0, 20, 1, 0)
                    arrow.Parent = mainBtn

                    local optsContainer = Instance.new("Frame")
                    optsContainer.Name = "OptionsList"
                    optsContainer.Size = UDim2.new(1, 0, 0, 0)
                    optsContainer.Position = UDim2.new(0, 0, 0, 56)
                    optsContainer.AutomaticSize = Enum.AutomaticSize.Y
                    optsContainer.BackgroundColor3 = Color3.fromRGB(22, 14, 38)
                    optsContainer.BackgroundTransparency = 0.15
                    optsContainer.BorderSizePixel = 0
                    optsContainer.Visible = false
                    optsContainer.ZIndex = 30
                    optsContainer.Parent = ddCard

                    local oCorner = Instance.new("UICorner")
                    oCorner.CornerRadius = UDim.new(0, 8)
                    oCorner.Parent = optsContainer

                    local oStroke = Instance.new("UIStroke")
                    oStroke.Thickness = 1
                    oStroke.Color = Color3.fromRGB(130, 80, 200)
                    oStroke.Transparency = 0.4
                    oStroke.Parent = optsContainer

                    local oLayout = Instance.new("UIListLayout")
                    oLayout.FillDirection = Enum.FillDirection.Vertical
                    oLayout.Padding = UDim.new(0, 2)
                    oLayout.Parent = optsContainer

                    local isOpen = false

                    local ddObj = {
                        Value = selected
                    }

                    local function BuildOptions(list)
                        for _, c in ipairs(optsContainer:GetChildren()) do
                            if c:IsA("TextButton") then
                                c:Destroy()
                            end
                        end
                        for _, opt in ipairs(list) do
                            local optBtn = Instance.new("TextButton")
                            optBtn.Size = UDim2.new(1, -6, 0, 26)
                            optBtn.Position = UDim2.new(0, 3, 0, 0)
                            optBtn.BackgroundColor3 = Color3.fromRGB(38, 24, 60)
                            optBtn.BackgroundTransparency = 0.6
                            optBtn.BorderSizePixel = 0
                            optBtn.Text = "  " .. tostring(opt)
                            optBtn.Font = Enum.Font.Gotham
                            optBtn.TextSize = 12
                            optBtn.TextColor3 = Color3.fromRGB(230, 220, 250)
                            optBtn.TextXAlignment = Enum.TextXAlignment.Left
                            optBtn.ZIndex = 31
                            optBtn.AutoButtonColor = false
                            optBtn.Parent = optsContainer

                            local oBtnCorner = Instance.new("UICorner")
                            oBtnCorner.CornerRadius = UDim.new(0, 5)
                            oBtnCorner.Parent = optBtn

                            optBtn.MouseEnter:Connect(function()
                                optBtn.BackgroundTransparency = 0.2
                            end)
                            optBtn.MouseLeave:Connect(function()
                                optBtn.BackgroundTransparency = 0.6
                            end)
                            optBtn.MouseButton1Click:Connect(function()
                                selected = opt
                                ddObj.Value = selected
                                lib.Flags[flagName] = selected
                                mainBtn.Text = "  " .. tostring(selected)
                                isOpen = false
                                optsContainer.Visible = false
                                arrow.Text = "▼"
                                pcall(callback, selected)
                            end)
                        end
                    end

                    BuildOptions(optionsList)

                    mainBtn.MouseButton1Click:Connect(function()
                        isOpen = not isOpen
                        optsContainer.Visible = isOpen
                        arrow.Text = isOpen and "▲" or "▼"
                    end)

                    function ddObj:SetValue(opt)
                        selected = opt
                        ddObj.Value = selected
                        lib.Flags[flagName] = selected
                        mainBtn.Text = "  " .. tostring(selected)
                        pcall(callback, selected)
                    end

                    function ddObj:GetValue()
                        return ddObj.Value
                    end

                    function ddObj:Refresh(newList)
                        BuildOptions(newList)
                    end
                    ddObj.SetOptions = ddObj.Refresh
                    ddObj.SetValues = ddObj.Refresh
                    ddObj.Update = ddObj.Refresh

                    lib.Flags[flagName] = selected
                    lib.Elements[flagName] = {
                        Type = "Dropdown",
                        Name = ddName,
                        Flag = flagName,
                        Get = function() return ddObj.Value end,
                        Set = function(v) ddObj:SetValue(v) end
                    }
                    lib.Options[flagName] = ddObj

                    return ddObj
                end

                -- 6. ADD TEXTBOX
                function section:AddTextbox(tbName, placeholder, callback)
                    placeholder = placeholder or "Type here..."
                    callback = callback or function() end
                    local flagName = tbName

                    local tbRow = Instance.new("Frame")
                    tbRow.Name = "Textbox_" .. tbName
                    tbRow.Size = UDim2.new(1, 0, 0, 36)
                    tbRow.BackgroundTransparency = 1
                    tbRow.Parent = itemsFrame

                    local input = Instance.new("TextBox")
                    input.Size = UDim2.new(1, 0, 1, 0)
                    input.BackgroundColor3 = Color3.fromRGB(36, 24, 56)
                    input.BackgroundTransparency = 0.4
                    input.BorderSizePixel = 0
                    input.PlaceholderText = placeholder
                    input.PlaceholderColor3 = Color3.fromRGB(160, 140, 190)
                    input.Text = ""
                    input.Font = Enum.Font.Gotham
                    input.TextSize = 13
                    input.TextColor3 = Color3.fromRGB(255, 255, 255)
                    input.ClearTextOnFocus = false
                    input.Parent = tbRow

                    local inCorner = Instance.new("UICorner")
                    inCorner.CornerRadius = UDim.new(0, 8)
                    inCorner.Parent = input

                    local inStroke = Instance.new("UIStroke")
                    inStroke.Thickness = 1
                    inStroke.Color = Color3.fromRGB(150, 105, 225)
                    inStroke.Transparency = 0.5
                    inStroke.Parent = input

                    input.FocusLost:Connect(function(enterPressed)
                        lib.Flags[flagName] = input.Text
                        pcall(callback, input.Text)
                    end)

                    lib.Flags[flagName] = ""
                    lib.Elements[flagName] = {
                        Type = "Textbox",
                        Name = tbName,
                        Flag = flagName,
                        Get = function() return input.Text end,
                        Set = function(t)
                            input.Text = tostring(t or "")
                            lib.Flags[flagName] = input.Text
                            pcall(callback, input.Text)
                        end
                    }

                    return input
                end

                -- 7. ADD KEYBIND
                function section:AddKeybind(kbName, defaultKey, callback)
                    defaultKey = defaultKey or "None"
                    callback = callback or function() end
                    local boundKey = defaultKey
                    local flagName = kbName

                    local kbRow = Instance.new("Frame")
                    kbRow.Name = "Keybind_" .. kbName
                    kbRow.Size = UDim2.new(1, 0, 0, 32)
                    kbRow.BackgroundTransparency = 1
                    kbRow.Parent = itemsFrame

                    local label = Instance.new("TextLabel")
                    label.Text = kbName
                    label.Font = Enum.Font.Gotham
                    label.TextSize = 13
                    label.TextColor3 = Color3.fromRGB(240, 235, 255)
                    label.TextXAlignment = Enum.TextXAlignment.Left
                    label.BackgroundTransparency = 1
                    label.Position = UDim2.new(0, 4, 0, 0)
                    label.Size = UDim2.new(1, -110, 1, 0)
                    label.Parent = kbRow

                    local kBtn = Instance.new("TextButton")
                    kBtn.Size = UDim2.new(0, 100, 0, 24)
                    kBtn.Position = UDim2.new(1, -104, 0.5, -12)
                    kBtn.BackgroundColor3 = Color3.fromRGB(45, 30, 70)
                    kBtn.BackgroundTransparency = 0.4
                    kBtn.BorderSizePixel = 0
                    kBtn.Text = "[" .. defaultKey .. "]"
                    kBtn.Font = Enum.Font.GothamMedium
                    kBtn.TextSize = 11
                    kBtn.TextColor3 = Color3.fromRGB(220, 205, 245)
                    kBtn.Parent = kbRow

                    local kCorner = Instance.new("UICorner")
                    kCorner.CornerRadius = UDim.new(0, 6)
                    kCorner.Parent = kBtn

                    local isListening = false
                    kBtn.MouseButton1Click:Connect(function()
                        if isListening then return end
                        isListening = true
                        kBtn.Text = "[...]"
                        local conn
                        conn = UserInputService.InputBegan:Connect(function(inp)
                            if inp.UserInputType == Enum.UserInputType.Keyboard then
                                if inp.KeyCode == Enum.KeyCode.Backspace or inp.KeyCode == Enum.KeyCode.Escape then
                                    boundKey = "None"
                                else
                                    boundKey = inp.KeyCode.Name
                                end
                                kBtn.Text = "[" .. boundKey .. "]"
                                lib.Flags[flagName] = boundKey
                                isListening = false
                                conn:Disconnect()
                                pcall(callback, boundKey)
                            end
                        end)
                    end)

                    local kbObj = {
                        Value = boundKey,
                        SetValue = function(self, key)
                            boundKey = tostring(key or "None")
                            kbObj.Value = boundKey
                            lib.Flags[flagName] = boundKey
                            kBtn.Text = "[" .. boundKey .. "]"
                            pcall(callback, boundKey)
                        end,
                        GetValue = function(self)
                            return boundKey
                        end
                    }

                    lib.Flags[flagName] = defaultKey
                    lib.Elements[flagName] = {
                        Type = "Keybind",
                        Name = kbName,
                        Flag = flagName,
                        Get = function() return boundKey end,
                        Set = function(k) kbObj:SetValue(k) end
                    }
                    lib.Options[flagName] = kbObj

                    return kBtn
                end

                -- 8. ADD COLORPICKER
                function section:AddColorPicker(arg1, arg2, arg3)
                    local title = "Color Picker"
                    local defColor = Color3.fromRGB(255, 255, 255)
                    local cpCallback = function() end

                    if type(arg1) == "string" then
                        title = arg1
                        if typeof(arg2) == "Color3" then
                            defColor = arg2
                            if type(arg3) == "table" and arg3.Callback then
                                cpCallback = arg3.Callback
                            elseif type(arg3) == "function" then
                                cpCallback = arg3
                            end
                        end
                    elseif typeof(arg1) == "Color3" then
                        defColor = arg1
                        if type(arg2) == "table" then
                            title = arg2.Title or title
                            cpCallback = arg2.Callback or cpCallback
                        end
                    end

                    local flagName = title
                    local currentColor = defColor

                    local cpRow = Instance.new("Frame")
                    cpRow.Name = "ColorPicker_" .. title
                    cpRow.Size = UDim2.new(1, 0, 0, 32)
                    cpRow.BackgroundTransparency = 1
                    cpRow.Parent = itemsFrame

                    local label = Instance.new("TextLabel")
                    label.Text = title
                    label.Font = Enum.Font.Gotham
                    label.TextSize = 13
                    label.TextColor3 = Color3.fromRGB(240, 235, 255)
                    label.TextXAlignment = Enum.TextXAlignment.Left
                    label.BackgroundTransparency = 1
                    label.Position = UDim2.new(0, 4, 0, 0)
                    label.Size = UDim2.new(1, -40, 1, 0)
                    label.Parent = cpRow

                    local swatch = Instance.new("TextButton")
                    swatch.Size = UDim2.new(0, 24, 0, 24)
                    swatch.Position = UDim2.new(1, -28, 0.5, -12)
                    swatch.BackgroundColor3 = defColor
                    swatch.BorderSizePixel = 0
                    swatch.Text = ""
                    swatch.Parent = cpRow

                    local swCorner = Instance.new("UICorner")
                    swCorner.CornerRadius = UDim.new(0, 5)
                    swCorner.Parent = swatch

                    local colors = {
                        Color3.fromRGB(255, 255, 255),
                        Color3.fromRGB(180, 130, 255),
                        Color3.fromRGB(255, 80, 80),
                        Color3.fromRGB(80, 255, 130),
                        Color3.fromRGB(255, 220, 80),
                        Color3.fromRGB(80, 180, 255),
                        Color3.fromRGB(255, 120, 220)
                    }
                    local idx = 1
                    swatch.MouseButton1Click:Connect(function()
                        idx = (idx % #colors) + 1
                        currentColor = colors[idx]
                        swatch.BackgroundColor3 = currentColor
                        lib.Flags[flagName] = { R = currentColor.R, G = currentColor.G, B = currentColor.B }
                        pcall(cpCallback, currentColor)
                    end)

                    local cpObj = {
                        Value = currentColor,
                        SetValue = function(self, col)
                            if typeof(col) == "Color3" then
                                currentColor = col
                                swatch.BackgroundColor3 = col
                                lib.Flags[flagName] = { R = col.R, G = col.G, B = col.B }
                                pcall(cpCallback, col)
                            elseif type(col) == "table" and col.R and col.G and col.B then
                                local c3 = Color3.new(col.R, col.G, col.B)
                                currentColor = c3
                                swatch.BackgroundColor3 = c3
                                lib.Flags[flagName] = col
                                pcall(cpCallback, c3)
                            end
                        end,
                        GetValue = function(self)
                            return swatch.BackgroundColor3
                        end
                    }

                    lib.Flags[flagName] = { R = defColor.R, G = defColor.G, B = defColor.B }
                    lib.Elements[flagName] = {
                        Type = "Color",
                        Name = title,
                        Flag = flagName,
                        Get = function() return swatch.BackgroundColor3 end,
                        Set = function(c) cpObj:SetValue(c) end
                    }
                    lib.Options[flagName] = cpObj

                    return swatch
                end

                -- 9. ADD CONFIG MANAGER (Interactive List + Max 10 limit + Real Settings Restoration)
                function section:AddConfigManager(folderPath)
                    folderPath = folderPath or "NYBHub/Configs"

                    local isfolder = isfolder or function() return false end
                    local makefolder = makefolder or function() end
                    local listfiles = listfiles or function() return {} end
                    local readfile = readfile or function() return nil end
                    local writefile = writefile or function() end
                    local delfile = delfile or function() end

                    pcall(function()
                        if not isfolder(folderPath) then
                            makefolder(folderPath)
                        end
                    end)

                    local inMemoryConfigs = {}

                    local cfgCard = Instance.new("Frame")
                    cfgCard.Name = "ConfigManagerCard"
                    cfgCard.Size = UDim2.new(1, 0, 0, 0)
                    cfgCard.AutomaticSize = Enum.AutomaticSize.Y
                    cfgCard.BackgroundTransparency = 1
                    cfgCard.Parent = itemsFrame

                    local cfgLayout = Instance.new("UIListLayout")
                    cfgLayout.FillDirection = Enum.FillDirection.Vertical
                    cfgLayout.Padding = UDim.new(0, 8)
                    cfgLayout.Parent = cfgCard

                    -- Header with live count (X/10)
                    local headerRow = Instance.new("Frame")
                    headerRow.Size = UDim2.new(1, 0, 0, 20)
                    headerRow.BackgroundTransparency = 1
                    headerRow.Parent = cfgCard

                    local countLabel = Instance.new("TextLabel")
                    countLabel.Name = "CountLabel"
                    countLabel.Text = "Saved Configs (0/10)"
                    countLabel.Font = Enum.Font.GothamBold
                    countLabel.TextSize = 12
                    countLabel.TextColor3 = Color3.fromRGB(200, 175, 240)
                    countLabel.TextXAlignment = Enum.TextXAlignment.Left
                    countLabel.BackgroundTransparency = 1
                    countLabel.Size = UDim2.new(0.6, 0, 1, 0)
                    countLabel.Parent = headerRow

                    local limitNote = Instance.new("TextLabel")
                    limitNote.Text = "Max 10 configs"
                    limitNote.Font = Enum.Font.Gotham
                    limitNote.TextSize = 11
                    limitNote.TextColor3 = Color3.fromRGB(150, 130, 185)
                    limitNote.TextXAlignment = Enum.TextXAlignment.Right
                    limitNote.BackgroundTransparency = 1
                    limitNote.Size = UDim2.new(0.4, 0, 1, 0)
                    limitNote.Parent = headerRow

                    -- Input + Save button row
                    local inputRow = Instance.new("Frame")
                    inputRow.Size = UDim2.new(1, 0, 0, 32)
                    inputRow.BackgroundTransparency = 1
                    inputRow.Parent = cfgCard

                    local input = Instance.new("TextBox")
                    input.Name = "ConfigInput"
                    input.Size = UDim2.new(1, -112, 1, 0)
                    input.BackgroundColor3 = Color3.fromRGB(34, 22, 54)
                    input.BackgroundTransparency = 0.35
                    input.BorderSizePixel = 0
                    input.PlaceholderText = "New config name..."
                    input.PlaceholderColor3 = Color3.fromRGB(150, 130, 180)
                    input.Text = ""
                    input.Font = Enum.Font.Gotham
                    input.TextSize = 12
                    input.TextColor3 = Color3.fromRGB(255, 255, 255)
                    input.Parent = inputRow

                    local inC = Instance.new("UICorner")
                    inC.CornerRadius = UDim.new(0, 8)
                    inC.Parent = input

                    local inStroke = Instance.new("UIStroke")
                    inStroke.Thickness = 1
                    inStroke.Color = Color3.fromRGB(140, 95, 215)
                    inStroke.Transparency = 0.5
                    inStroke.Parent = input

                    local saveBtn = Instance.new("TextButton")
                    saveBtn.Name = "SaveBtn"
                    saveBtn.Size = UDim2.new(0, 104, 1, 0)
                    saveBtn.Position = UDim2.new(1, -104, 0, 0)
                    saveBtn.BackgroundColor3 = Color3.fromRGB(120, 60, 210)
                    saveBtn.BackgroundTransparency = 0.4
                    saveBtn.BorderSizePixel = 0
                    saveBtn.Text = "+ Save Config"
                    saveBtn.Font = Enum.Font.GothamBold
                    saveBtn.TextSize = 12
                    saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                    saveBtn.AutoButtonColor = false
                    saveBtn.Parent = inputRow

                    local saveC = Instance.new("UICorner")
                    saveC.CornerRadius = UDim.new(0, 8)
                    saveC.Parent = saveBtn

                    lib:ApplyShimmer(saveBtn, 1.2)

                    -- List Container for Configs
                    local listFrame = Instance.new("Frame")
                    listFrame.Name = "ConfigsList"
                    listFrame.Size = UDim2.new(1, 0, 0, 0)
                    listFrame.AutomaticSize = Enum.AutomaticSize.Y
                    listFrame.BackgroundTransparency = 1
                    listFrame.Parent = cfgCard

                    local listLayout = Instance.new("UIListLayout")
                    listLayout.FillDirection = Enum.FillDirection.Vertical
                    listLayout.Padding = UDim.new(0, 5)
                    listLayout.Parent = listFrame

                    -- Clean filename parsing function to prevent folder path duplication
                    local function CleanConfigName(rawPath)
                        local s = tostring(rawPath):gsub(string.char(92), "/")
                        local fname = s:match("([^/]+)$") or s
                        local base = fname:match("^(.-)%.json$") or fname:match("^(.-)%.txt$") or fname
                        return base
                    end

                    local function GetAllConfigs()
                        local cfgs = {}
                        local seen = {}
                        pcall(function()
                            if isfolder(folderPath) then
                                local files = listfiles(folderPath)
                                for _, f in ipairs(files) do
                                    local name = CleanConfigName(f)
                                    if name and name ~= "" and not seen[name] then
                                        seen[name] = true
                                        table.insert(cfgs, name)
                                    end
                                end
                            end
                        end)
                        for name, _ in pairs(inMemoryConfigs) do
                            local base = CleanConfigName(name)
                            if base and base ~= "" and not seen[base] then
                                seen[base] = true
                                table.insert(cfgs, base)
                            end
                        end
                        table.sort(cfgs)
                        return cfgs
                    end

                    local function RenderList()
                        for _, child in ipairs(listFrame:GetChildren()) do
                            if child:IsA("Frame") or child:IsA("TextLabel") then
                                child:Destroy()
                            end
                        end

                        local cfgs = GetAllConfigs()
                        countLabel.Text = string.format("Saved Configs (%d/10)", #cfgs)

                        if #cfgs == 0 then
                            local emptyLabel = Instance.new("TextLabel")
                            emptyLabel.Text = "No configs saved yet. Enter a name above to save one."
                            emptyLabel.Font = Enum.Font.Gotham
                            emptyLabel.TextSize = 11
                            emptyLabel.TextColor3 = Color3.fromRGB(160, 145, 195)
                            emptyLabel.BackgroundTransparency = 1
                            emptyLabel.Size = UDim2.new(1, 0, 0, 24)
                            emptyLabel.Parent = listFrame
                            return
                        end

                        for _, cName in ipairs(cfgs) do
                            local itemRow = Instance.new("Frame")
                            itemRow.Name = "Item_" .. cName
                            itemRow.Size = UDim2.new(1, 0, 0, 32)
                            itemRow.BackgroundColor3 = Color3.fromRGB(28, 18, 46)
                            itemRow.BackgroundTransparency = 0.5
                            itemRow.BorderSizePixel = 0
                            itemRow.Parent = listFrame

                            local irCorner = Instance.new("UICorner")
                            irCorner.CornerRadius = UDim.new(0, 6)
                            irCorner.Parent = itemRow

                            local irStroke = Instance.new("UIStroke")
                            irStroke.Thickness = 1
                            irStroke.Color = Color3.fromRGB(120, 80, 190)
                            irStroke.Transparency = 0.6
                            irStroke.Parent = itemRow

                            local icon = Instance.new("TextLabel")
                            icon.Text = "📄"
                            icon.Font = Enum.Font.Gotham
                            icon.TextSize = 12
                            icon.Size = UDim2.new(0, 24, 1, 0)
                            icon.Position = UDim2.new(0, 6, 0, 0)
                            icon.BackgroundTransparency = 1
                            icon.Parent = itemRow

                            local nameLbl = Instance.new("TextLabel")
                            nameLbl.Text = cName
                            nameLbl.Font = Enum.Font.GothamMedium
                            nameLbl.TextSize = 12
                            nameLbl.TextColor3 = Color3.fromRGB(240, 235, 255)
                            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                            nameLbl.Position = UDim2.new(0, 32, 0, 0)
                            nameLbl.Size = UDim2.new(1, -125, 1, 0)
                            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                            nameLbl.BackgroundTransparency = 1
                            nameLbl.Parent = itemRow

                            local actions = Instance.new("Frame")
                            actions.Size = UDim2.new(0, 85, 1, 0)
                            actions.Position = UDim2.new(1, -90, 0, 0)
                            actions.BackgroundTransparency = 1
                            actions.Parent = itemRow

                            local aLayout = Instance.new("UIListLayout")
                            aLayout.FillDirection = Enum.FillDirection.Horizontal
                            aLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
                            aLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                            aLayout.Padding = UDim.new(0, 5)
                            aLayout.Parent = actions

                            -- Load Button
                            local loadBtn = Instance.new("TextButton")
                            loadBtn.Size = UDim2.new(0, 50, 0, 22)
                            loadBtn.BackgroundColor3 = Color3.fromRGB(110, 55, 190)
                            loadBtn.BackgroundTransparency = 0.35
                            loadBtn.BorderSizePixel = 0
                            loadBtn.Text = "Load"
                            loadBtn.Font = Enum.Font.GothamBold
                            loadBtn.TextSize = 11
                            loadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                            loadBtn.AutoButtonColor = false
                            loadBtn.Parent = actions

                            local lbCorner = Instance.new("UICorner")
                            lbCorner.CornerRadius = UDim.new(0, 5)
                            lbCorner.Parent = loadBtn

                            loadBtn.MouseButton1Click:Connect(function()
                                local rawJson = nil
                                pcall(function()
                                    if isfolder(folderPath) then
                                        local candidates = {
                                            folderPath .. "/" .. cName .. ".json",
                                            folderPath .. string.char(92) .. cName .. ".json",
                                            folderPath .. "/" .. cName,
                                            folderPath .. string.char(92) .. cName
                                        }
                                        for _, p in ipairs(candidates) do
                                            local ok, res = pcall(function() return readfile(p) end)
                                            if ok and res and res ~= "" then
                                                rawJson = res
                                                break
                                            end
                                        end
                                    end
                                end)

                                local cfgData = nil
                                if rawJson and rawJson ~= "" then
                                    pcall(function()
                                        cfgData = HttpService:JSONDecode(rawJson)
                                    end)
                                end

                                if not cfgData or not cfgData.flags then
                                    cfgData = inMemoryConfigs[cName]
                                end

                                if cfgData and cfgData.flags then
                                    local appliedCount = 0
                                    for flag, val in pairs(cfgData.flags) do
                                        local elem = lib.Elements[flag]
                                        if elem and elem.Set then
                                            local ok = pcall(function()
                                                elem.Set(val)
                                            end)
                                            if ok then
                                                appliedCount = appliedCount + 1
                                            end
                                        end
                                    end
                                    lib:Notify({
                                        Title = "Config Loaded",
                                        Description = string.format("Config '%s' applied (%d settings updated)!", cName, appliedCount),
                                        Duration = 3
                                    })
                                else
                                    lib:Notify({
                                        Title = "Config Error",
                                        Description = "Could not load data for config '" .. cName .. "'!",
                                        Duration = 3
                                    })
                                end
                            end)

                            -- Delete Button
                            local delBtn = Instance.new("TextButton")
                            delBtn.Size = UDim2.new(0, 24, 0, 22)
                            delBtn.BackgroundColor3 = Color3.fromRGB(150, 45, 65)
                            delBtn.BackgroundTransparency = 0.4
                            delBtn.BorderSizePixel = 0
                            delBtn.Text = "X"
                            delBtn.Font = Enum.Font.GothamBold
                            delBtn.TextSize = 11
                            delBtn.TextColor3 = Color3.fromRGB(255, 180, 190)
                            delBtn.AutoButtonColor = false
                            delBtn.Parent = actions

                            local dbCorner = Instance.new("UICorner")
                            dbCorner.CornerRadius = UDim.new(0, 5)
                            dbCorner.Parent = delBtn

                            delBtn.MouseButton1Click:Connect(function()
                                pcall(function()
                                    if isfolder(folderPath) then
                                        delfile(folderPath .. "/" .. cName .. ".json")
                                        delfile(folderPath .. string.char(92) .. cName .. ".json")
                                        delfile(folderPath .. "/" .. cName)
                                        delfile(folderPath .. string.char(92) .. cName)
                                    end
                                end)
                                inMemoryConfigs[cName] = nil
                                for k, _ in pairs(inMemoryConfigs) do
                                    if CleanConfigName(k) == cName then
                                        inMemoryConfigs[k] = nil
                                    end
                                end
                                RenderList()
                                lib:Notify({ Title = "Config Manager", Description = "Config '" .. cName .. "' deleted!", Duration = 2 })
                            end)
                        end
                    end

                    saveBtn.MouseButton1Click:Connect(function()
                        local cName = input.Text:gsub("[^%w_%-]", "")
                        if cName == "" then
                            lib:Notify({ Title = "Config Manager", Description = "Please enter a valid config name!", Duration = 2.5 })
                            return
                        end

                        local currentConfigs = GetAllConfigs()
                        local alreadyExists = false
                        for _, existing in ipairs(currentConfigs) do
                            if existing == cName then
                                alreadyExists = true
                                break
                            end
                        end

                        -- Limit: Maximum 10 configs!
                        if not alreadyExists and #currentConfigs >= 10 then
                            lib:Notify({
                                Title = "Config Limit Reached",
                                Description = "Maximum limit of 10 configs reached! Delete an existing config first.",
                                Duration = 3.5
                            })
                            return
                        end

                        -- Save all registered elements
                        local savedFlags = {}
                        for flag, elem in pairs(lib.Elements) do
                            pcall(function()
                                local val = elem.Get()
                                if typeof(val) == "Color3" then
                                    val = { R = val.R, G = val.G, B = val.B }
                                end
                                savedFlags[flag] = val
                            end)
                        end

                        local cfgData = {
                            name = cName,
                            savedAt = os.time(),
                            flags = savedFlags
                        }
                        local json = HttpService:JSONEncode(cfgData)

                        pcall(function()
                            if not isfolder(folderPath) then
                                makefolder(folderPath)
                            end
                            writefile(folderPath .. "/" .. cName .. ".json", json)
                        end)

                        inMemoryConfigs[cName] = cfgData
                        input.Text = ""
                        RenderList()

                        local newCount = #GetAllConfigs()
                        lib:Notify({
                            Title = "Config Manager",
                            Description = string.format("Config '%s' saved successfully! (%d/10)", cName, newCount),
                            Duration = 2.5
                        })
                    end)

                    RenderList()
                end

                table.insert(tabObj.Sections, section)
                return section
            end

            table.insert(window.Tabs, tabObj)
            if #window.Tabs == 1 then
                ActivateTab()
            end
            return tabObj
        end

        return window
    end

    return lib
end

local lib = CreateNYBLibrary()

NYB.ui.lib = lib
NYB.ui.win = lib:CreateWindow({
	Title = "NYB Hub",
	Subtitle = "Violence District",
	SubtitleColor = Color3.fromRGB(190, 140, 255),
	Logo = "rbxassetid://94398897297532",
	LogoSize = 32,
	Watermark = true,
	WatermarkText = "NYB Hub",
	WatermarkIcon = "rbxassetid://94398897297532",
})

--==== STATE MODUL -- semua nempel di NYB.ui, gak ada local lintas blok ====
NYB.ui.tabs    = {}
NYB.ui.pages   = {}
NYB.ui.reg     = {}
NYB.ui._groups = {}
NYB.ui.tabOf   = setmetatable({}, { __mode = "k" })
NYB.ui.colors = {
	bg     = Color3.fromRGB(16, 11, 26),
	panel  = Color3.fromRGB(24, 17, 38),
	panel2 = Color3.fromRGB(34, 24, 52),
	stroke = Color3.fromRGB(140, 95, 215),
	text   = Color3.fromRGB(240, 235, 255),
	dim    = Color3.fromRGB(175, 160, 205),
	accent = Color3.fromRGB(180, 130, 255),
}
NYB.ui.window          = { Visible = true }
NYB.ui.status          = ""
NYB.ui.sticky          = nil
NYB.ui.stickyLbl       = nil
NYB.ui.applyResponsive = function()
	local w = NYB.ui.win
	if type(w) == "table" and type(w.ApplyScale) == "function" then w.ApplyScale() end
end
NYB.ui.applyScale = NYB.ui.applyResponsive
NYB.ui.stickyTick      = function() end

-- host overlay buat ESP / aim / crosshair (engine-nya punya GUI sendiri,
-- tapi buat overlay kita bikin ScreenGui terpisah biar DisplayOrder-nya jelas)
do
	local parent = (gethui and gethui()) or game:GetService("CoreGui")
	local g = Instance.new("ScreenGui")
	g.Name = "NYB_HUB_Overlay"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 50
	local okP = pcall(function() g.Parent = parent end)
	if not okP then
		local lp2 = game:GetService("Players").LocalPlayer
		g.Parent = lp2:FindFirstChild("PlayerGui") or lp2:WaitForChild("PlayerGui")
	end
	NYB.ui.gui = g
end

NYB.ui.setWin = function(v)
	NYB.msg(v and "Window dibuka lewat hotkey." or "Window disembunyikan lewat hotkey.")
end

NYB.ui.tabFor = function(page)
	if type(page) == "table" then
		return NYB.ui.tabOf[page] or page.__tab
	end
	return nil
end

-- element nempel ke SECTION, bukan ke tab (kontrak engine ini).
-- Kalau belum ada section, bikin "Umum" dulu.
NYB.ui.secFor = function(page)
	if type(page) == "table" and page.__cur then return page.__cur end
	local tab = NYB.ui.tabFor(page)
	if not tab then return nil end
	local ok, sec = pcall(function() return tab:CreateSection("Umum") end)
	if ok and type(page) == "table" then page.__cur = sec end
	return ok and sec or nil
end

NYB.ui.createTab = function(name, short)
	local ok, tab = pcall(function() return NYB.ui.win:CreateTab(tostring(name), nil) end)
	if not ok or type(tab) ~= "table" then
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
	if not ok or type(sec) ~= "table" then
		warn("[NYB HUB] section '" .. tostring(text) .. "' gagal: " .. tostring(sec))
		return nil
	end
	if type(page) == "table" then page.__cur = sec end
	table.insert(NYB.ui._groups, { page = page, header = sec, text = text })
	return sec
end

NYB.ui.toggle = function(page, text, key, callback)
	local sec = NYB.ui.secFor(page)
	if not sec then
		warn("[NYB HUB] toggle '" .. tostring(text) .. "': section tidak ada")
		return nil
	end
	local default = (type(key) == "string") and (CFG[key] == true) or (key == true)
	local ok, el = pcall(function()
		return sec:AddToggle(tostring(text), default, function(state)
			if type(key) == "string" then CFG[key] = state end
			if callback then
				local okc, err = pcall(callback, state)
				if not okc then warn("[NYB HUB] toggle error: " .. tostring(err)) end
			end
		end)
	end)
	if not ok or type(el) ~= "table" then
		warn("[NYB HUB] toggle '" .. tostring(text) .. "' gagal: " .. tostring(el))
		return nil
	end
	local api = {
		key = (type(key) == "string") and key or nil,
		el  = el,
		set = function(v)
			v = v and true or false
			if type(el.SetValue) == "function" then pcall(function() el:SetValue(v) end) end
		end,
		get = function()
			if type(el.GetValue) == "function" then
				local okg, g = pcall(function() return el:GetValue() end)
				if okg then return g end
			end
			return nil
		end,
	}
	if api.key then NYB.ui.reg[api.key] = api end
	return api
end

NYB.ui.slider = function(page, text, min, max, default, decimals, callback)
	local sec = NYB.ui.secFor(page)
	if not sec then
		warn("[NYB HUB] slider '" .. tostring(text) .. "': section tidak ada")
		return nil
	end
	local ok, el = pcall(function()
		return sec:AddSlider(tostring(text), min, max, tonumber(default) or min, function(v)
			if callback then
				local okc, err = pcall(callback, v)
				if not okc then warn("[NYB HUB] slider error: " .. tostring(err)) end
			end
		end)
	end)
	if not ok or type(el) ~= "table" then
		warn("[NYB HUB] slider '" .. tostring(text) .. "' gagal: " .. tostring(el))
		return nil
	end
	return {
		el  = el,
		get = function()
			if type(el.GetValue) == "function" then
				local okg, g = pcall(function() return el:GetValue() end)
				if okg then return g end
			end
			return default
		end,
		set = function(v)
			if type(el.SetValue) == "function" then pcall(function() el:SetValue(v) end) end
		end,
	}
end

-- Engine ini punya AddDropdown + AddKeybind, tapi NYB.ui belum punya wrapper-nya.
-- Kontrak engine (diverifikasi dari section 5):
--   sec:AddDropdown(nama, opsi, default, cb) -> ddObj  (:SetValue / :GetValue / .Value)
--   sec:AddKeybind(nama, defaultKey, cb)     -> kBtn   (objeknya di lib.Options[nama])
NYB.ui.dropdown = function(page, text, options, default, key, callback)
	local sec = NYB.ui.secFor(page)
	if not sec then
		warn("[NYB HUB] dropdown '" .. tostring(text) .. "': section tidak ada")
		return nil
	end
	local def = default
	if type(key) == "string" and CFG[key] ~= nil then def = CFG[key] end
	local ok, el = pcall(function()
		return sec:AddDropdown(tostring(text), options, def, function(v)
			if type(key) == "string" then CFG[key] = v end
			if callback then
				local okc, err = pcall(callback, v)
				if not okc then warn("[NYB HUB] dropdown error: " .. tostring(err)) end
			end
		end)
	end)
	if not ok or type(el) ~= "table" then
		warn("[NYB HUB] dropdown '" .. tostring(text) .. "' gagal: " .. tostring(el))
		return nil
	end
	local api = {
		key = (type(key) == "string") and key or nil,
		el  = el,
		set = function(v)
			if type(el.SetValue) == "function" then pcall(function() el:SetValue(v) end) end
		end,
		get = function()
			if type(el.GetValue) == "function" then
				local okg, g = pcall(function() return el:GetValue() end)
				if okg then return g end
			end
			return nil
		end,
	}
	if api.key then NYB.ui.reg[api.key] = api end
	return api
end

NYB.ui.keybind = function(page, text, defaultKey, callback)
	local sec = NYB.ui.secFor(page)
	if not sec then
		warn("[NYB HUB] keybind '" .. tostring(text) .. "': section tidak ada")
		return nil
	end
	local ok, el = pcall(function()
		return sec:AddKeybind(tostring(text), tostring(defaultKey or "None"), function(k)
			if callback then
				local okc, err = pcall(callback, k)
				if not okc then warn("[NYB HUB] keybind error: " .. tostring(err)) end
			end
		end)
	end)
	if not ok then warn("[NYB HUB] keybind '" .. tostring(text) .. "' gagal: " .. tostring(el)) end
	local obj = NYB.ui.lib and NYB.ui.lib.Options and NYB.ui.lib.Options[tostring(text)]
	return { el = el, obj = obj }
end

NYB.ui.button = function(page, text, callback)
	local sec = NYB.ui.secFor(page)
	if not sec then
		warn("[NYB HUB] tombol '" .. tostring(text) .. "': section tidak ada")
		return nil
	end
	local ok, el = pcall(function()
		return sec:AddButton(tostring(text), function()
			local okc, err = pcall(callback)
			if not okc then NYB.msg("Error: " .. tostring(err)) end
		end)
	end)
	if not ok then warn("[NYB HUB] tombol '" .. tostring(text) .. "' gagal: " .. tostring(el)) end
	return ok and el or nil
end

-- Engine ini gak punya AddLabel. Tapi objek section-nya expose .ItemsFrame,
-- jadi kita tempel TextLabel asli di situ -> `lbl.Text = ...` jalan native.
NYB.ui.label = function(page, text, color)
	local sec = NYB.ui.secFor(page)
	if not sec then return nil end
	local parent = sec.ItemsFrame or sec.Card
	if not parent then
		warn("[NYB HUB] label: section gak expose ItemsFrame/Card")
		return nil
	end
	local lbl = Instance.new("TextLabel")
	lbl.Name = "NYB_Label"
	lbl.Size = UDim2.new(1, -8, 0, 18)
	lbl.BackgroundTransparency = 1
	lbl.Text = tostring(text or "")
	lbl.TextColor3 = color or NYB.ui.colors.dim
	lbl.TextSize = 12
	lbl.Font = Enum.Font.Gotham
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	lbl.Parent = parent
	return lbl
end

NYB.ui.notify = function(text, duration)
	pcall(function()
		NYB.ui.lib:Notify({
			Title = "NYB Hub",
			Description = tostring(text),
			Duration = duration or 3,
			Logo = "rbxassetid://94398897297532",
		})
	end)
end

NYB.ui.setStatus = function(text)
	NYB.ui.status = tostring(text)
end

NYB.setCfg = function(key, v)
	CFG[key] = v
	local t = NYB.ui.reg[key]
	if t and t.set then t.set(v) end
end

--==== HOTKEY PER FITUR (pola KeyPicker Aeris) ================================
-- Satu listener global, banyak aksi: biar tiap port gak bikin listener sendiri.
-- Pakai:
--   U.keybind(page, "Parry Sekarang", "F", function(k) CFG.ParryKey = k end)
--   NYB.hotkey("ParryKey", function() NYB.parry() end)
NYB.hotkeys = {}
NYB.hotkey = function(cfgKey, fn)
	if type(cfgKey) ~= "string" or type(fn) ~= "function" then return end
	table.insert(NYB.hotkeys, { key = cfgKey, fn = fn })
end
NYB.bind(UIS.InputBegan, function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local name = input.KeyCode and input.KeyCode.Name or nil
	if not name or name == "None" then return end
	for _, h in ipairs(NYB.hotkeys) do
		if CFG[h.key] == name then
			local ok, err = pcall(h.fn)
			if not ok then warn("[NYB HUB] hotkey error: " .. tostring(err)) end
		end
	end
end)


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

	--==== CROSSHAIR: style / ketebalan / posisi ====
	-- Bentuk "Plus" tetap gambar yang lama (4 batang bercelah); Dot dan Circle
	-- dari port Aeris. Thickness default 2 dan offset 0 -> sama persis kayak
	-- sebelumnya, jadi nggak ada perubahan tampilan buat yang gak nyentuh ini.
	NYB.buildCrosshair = function()
		if crossGui and crossGui.Parent then
			crossGui:Destroy()
		end
		crossGui = nil
		if not CFG.Crosshair then return end
		local s = CFG.CrossSize
		local th = math.clamp(tonumber(CFG.CrossThick) or 2, 1, 5)
		local ox = tonumber(CFG.CrossOffX) or 0
		local oy = tonumber(CFG.CrossOffY) or 0
		local style = CFG.CrossStyle or "Plus"
		crossGui = Instance.new("ScreenGui")
		crossGui.Name = "NYB_Crosshair"
		crossGui.ResetOnSpawn = false
		crossGui.IgnoreGuiInset = true
		crossGui.Parent = NYB.ui.gui
		local function frame(w, h, x, y, centered)
			local f = Instance.new("Frame")
			f.Size = UDim2.new(0, w, 0, h)
			f.Position = UDim2.new(0.5, x + ox, 0.5, y + oy)
			if centered then f.AnchorPoint = Vector2.new(0.5, 0.5) end
			f.BackgroundColor3 = CFG.Accent
			f.BorderSizePixel = 0
			f.ZIndex = 20
			f.Parent = crossGui
			return f
		end
		if style == "Dot" then
			local d = frame(s, s, 0, 0, true)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = d
		elseif style == "Circle" then
			local d = frame(s * 2, s * 2, 0, 0, true)
			d.BackgroundTransparency = 1
			local st = Instance.new("UIStroke")
			st.Color = CFG.Accent
			st.Thickness = th
			st.Parent = d
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = d
		else
			local half = th / 2
			frame(s, th, -s - 3, -half)
			frame(s, th, 3, -half)
			frame(th, s, -half, -s - 3)
			frame(th, s, -half, 3)
		end
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

--===================== [ 11b. PORT AERIS: CAMERA + PERFORMA ] ==============
-- Port ADITIF dari source Aeris Hub (baris 10971-11424, 13152-13395,
-- 16697-16804). Nol fitur lama diubah: Stretch Res, Camera FOV, Fullbright,
-- No Fog, Zoom Unlock tetap apa adanya -- blok ini cuma NAMBAH.
--
-- Semua yang perlu diakses dari luar nempel di NYB.* karena local di dalam
-- `do` block nggak kelihatan dari blok lain.
do
	--==== NO SHADOW ====
	-- applyVisual() punya snapshot lighting sendiri dan nulis GlobalShadows.
	-- Kita simpan snapshot terpisah biar bisa balikin nilai asli tanpa nebak,
	-- dan No Shadow selalu menang saat Fullbright nyala (dua-duanya matiin shadow).
	local origShadows = Lighting.GlobalShadows

	NYB.applyPerf = function()
		pcall(function()
			-- CATATAN: jangan ditulis `(a or b) and false or c`. Di Lua, kalau
			-- `(a or b)` true maka `true and false` = false, lalu `false or c`
			-- balik ke c -- jadi No Shadow nggak pernah ngefek.
			if CFG.NoShadow or CFG.Fullbright then
				Lighting.GlobalShadows = false
			else
				Lighting.GlobalShadows = origShadows
			end
		end)
	end

	-- Aeris nge-guard Lighting lewat Heartbeat karena game nulis ulang nilai itu
	-- sendiri tiap round/atmosphere baru. Kita pakai pola yang sama, dan
	-- applyVisual() ikut dipanggil biar dua-duanya nggak rebutan urutan.
	local lastGuard = 0
	NYB.bind(RunService.Heartbeat, function()
		if not (CFG.NoShadow or CFG.Fullbright or CFG.NoFog) then return end
		local now = tick()
		if now - lastGuard < 0.4 then return end
		lastGuard = now
		NYB.applyVisual()
		NYB.applyPerf()
	end)

	--==== THIRD PERSON (KILLER) ====
	-- Port fn52 + fn51 + Set/ResetWorldTransparency dari Aeris.
	local TP_BODY = {
		LeftHand = true, RightHand = true, LeftLowerArm = true, RightLowerArm = true,
		LeftUpperArm = true, RightUpperArm = true,
	}

	local function walkParts(root, fn)
		if not root then return end
		pcall(function()
			if root:IsA("BasePart") or root:IsA("Decal") then fn(root) end
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then fn(d) end
			end
		end)
	end

	-- Di VD, badan karakter kita nempel sebagai anak kamera. Kalau nggak dibikin
	-- transparan, kamera orang ketiga malah ngeliat isi kepala sendiri.
	local function worldTransparency(v)
		if not cam then return end
		for _, ch in ipairs(cam:GetChildren()) do
			if ch ~= lp.Character then
				walkParts(ch, function(d)
					pcall(function()
						d.LocalTransparencyModifier = v
						d.Transparency = v
					end)
				end)
			end
		end
	end

	local function characterTransparency(v)
		local char = lp.Character
		if not char then return end
		for _, ch in ipairs(char:GetChildren()) do
			if ch.Name == "Hat" or (ch:IsA("BasePart") and TP_BODY[ch.Name]) or ch:IsA("Tool") then
				walkParts(ch, function(d)
					pcall(function()
						d.LocalTransparencyModifier = v
						d.Transparency = v
					end)
				end)
			end
		end
	end

	local function thirdPersonReset()
		pcall(function()
			lp.CameraMode = Enum.CameraMode.Classic
			if CFG.InfinityZoom then
				lp.CameraMinZoomDistance = 0
				lp.CameraMaxZoomDistance = math.huge
			else
				lp.CameraMinZoomDistance = 0.5
				lp.CameraMaxZoomDistance = 128
			end
		end)
		worldTransparency(0)
		characterTransparency(0)
	end

	local tpConn = nil
	local function thirdPersonOff()
		if tpConn then tpConn:Disconnect() tpConn = nil end
		thirdPersonReset()
	end

	NYB.thirdPerson = function(on)
		if on and not NYB.isKiller(lp) then
			-- Aeris nolak fitur ini kalau bukan Killer; ikut, tapi kasih pesan
			-- yang kelihatan (warn() sering nggak tampil di executor HP).
			CFG.ThirdPerson = false
			if NYB.ui.reg.ThirdPerson then NYB.ui.reg.ThirdPerson.set(false) end
			NYB.msg("Third Person cuma buat Killer.")
			return
		end

		if tpConn then tpConn:Disconnect() tpConn = nil end
		if not on then thirdPersonReset() return end

		pcall(function()
			lp.CameraMode = Enum.CameraMode.Classic
			lp.CameraMinZoomDistance = 7
			lp.CameraMaxZoomDistance = 128
		end)
		worldTransparency(1)

		tpConn = RunService.RenderStepped:Connect(function()
			if not CFG.ThirdPerson then return end
			if not NYB.isKiller(lp) then
				-- keluar dari role Killer (mis. round selesai) -> matiin sendiri
				CFG.ThirdPerson = false
				if NYB.ui.reg.ThirdPerson then NYB.ui.reg.ThirdPerson.set(false) end
				thirdPersonReset()
				return
			end
			pcall(function()
				lp.CameraMode = Enum.CameraMode.Classic
				lp.CameraMinZoomDistance = 7
				lp.CameraMaxZoomDistance = 128
				characterTransparency(0)
			end)
		end)
	end

	table.insert(NYB.cleanups, function()
		if tpConn then pcall(function() tpConn:Disconnect() end) tpConn = nil end
	end)

	--==== INFINITY ZOOM OUT ====
	-- Beda dari "Zoom Unlock" yang sudah ada (max 500 stud): ini beneran tanpa
	-- batas. Dua-duanya nulis property yang sama, jadi kalau yang ini nyala,
	-- Zoom Unlock dimatiin biar nggak rebutan.
	NYB.infinityZoom = function(on)
		pcall(function()
			if on then
				lp.CameraMaxZoomDistance = math.huge
				lp.CameraMinZoomDistance = 0
			else
				lp.CameraMaxZoomDistance = 12
				lp.CameraMinZoomDistance = 0.5
			end
		end)
	end

	--==== DBD CAMERA ====
	-- Port DBD_Start / DBD_Stop / DBD_initYaw / DBD_isLookTouch dari Aeris.
	local DBD = {
		yaw = 0, pitch = 0.12, lookInput = nil, lastPos = nil,
		conn = nil, chg = nil, beg = nil, endc = nil, oldFOV = nil,
	}

	local function dbdIsLookTouch(pos)
		local vp = cam and cam.ViewportSize
		if not vp then return false end
		-- sisi kanan layar = area ngeliat (Aeris: > 22% lebar viewport)
		return pos.X > vp.X * 0.22
	end

	local function dbdInitYaw()
		local hrp = NYB.hrp()
		if not hrp then return end
		local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude > 0.05 then
			DBD.yaw = math.atan2(-look.X, -look.Z)
		end
	end

	local function dbdStop()
		for _, k in ipairs({ "conn", "chg", "beg", "endc" }) do
			if DBD[k] then
				pcall(function() DBD[k]:Disconnect() end)
				DBD[k] = nil
			end
		end
		pcall(function() cam.CameraType = Enum.CameraType.Custom end)
		if DBD.oldFOV then pcall(function() cam.FieldOfView = DBD.oldFOV end) end
		DBD.lookInput = nil
		DBD.lastPos = nil
	end

	local function dbdStart()
		dbdStop()
		if not CFG.DBDCamera then return end

		dbdInitYaw()
		pcall(function()
			DBD.oldFOV = cam.FieldOfView
			cam.CameraType = Enum.CameraType.Scriptable
			cam.FieldOfView = CFG.DBDFOV
		end)
		local hum = NYB.hum()
		if hum then pcall(function() hum.AutoRotate = true end) end

		DBD.chg = UIS.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if input ~= DBD.lookInput then return end
			local pos = input.Position
			if DBD.lastPos then
				DBD.yaw = DBD.yaw - (pos.X - DBD.lastPos.X) * 0.011 * CFG.DBDSens
				DBD.pitch = math.clamp(
					DBD.pitch - (pos.Y - DBD.lastPos.Y) * 0.011 * CFG.DBDSens,
					CFG.DBDPitchMin, CFG.DBDPitchMax)
			end
			DBD.lastPos = pos
		end)

		DBD.beg = UIS.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch and dbdIsLookTouch(input.Position) then
				DBD.lookInput = input
				DBD.lastPos = input.Position
			end
		end)

		DBD.endc = UIS.InputEnded:Connect(function(input)
			if input == DBD.lookInput then
				DBD.lookInput = nil
				DBD.lastPos = nil
			end
		end)

		DBD.conn = RunService.RenderStepped:Connect(function(dt)
			if not CFG.DBDCamera then return end
			local hrp = NYB.hrp()
			if not hrp then return end
			local dir = Vector3.new(
				math.sin(DBD.yaw) * math.cos(DBD.pitch),
				math.sin(DBD.pitch),
				math.cos(DBD.yaw) * math.cos(DBD.pitch))
			local target = hrp.Position + Vector3.new(0, 1.6, 0)
			local goalPos = target - dir * CFG.DBDDistance + Vector3.new(0, CFG.DBDHeight - 1.6, 0)
			local goal = CFrame.lookAt(goalPos, target)
			-- smoothing lebih ringan saat jari lagi nempel (LookSmooth) daripada
			-- saat kamera ngikut lari (RunSmooth) -- angka & rumus dari Aeris
			local lookSmooth = DBD.lookInput and CFG.DBDLookSmooth or CFG.DBDRunSmooth
			local alpha = 1 - math.pow(1 - lookSmooth, dt * 60)
			cam.CFrame = cam.CFrame:Lerp(goal, alpha)
		end)
	end

	NYB.dbdStart = dbdStart
	NYB.dbdStop = dbdStop

	-- respawn: kamera balik ke Custom, jadi DBD & Third Person harus dipasang ulang
	NYB.bind(lp.CharacterAdded, function()
		task.wait(0.6)
		if CFG.DBDCamera then
			pcall(function() cam = workspace.CurrentCamera end)
			dbdStart()
		end
		if CFG.ThirdPerson then NYB.thirdPerson(true) end
	end)

	table.insert(NYB.cleanups, function()
		for _, k in ipairs({ "conn", "chg", "beg", "endc" }) do
			if DBD[k] then pcall(function() DBD[k]:Disconnect() end) DBD[k] = nil end
		end
		pcall(function() cam.CameraType = Enum.CameraType.Custom end)
	end)

	--==== REMOVE TEXTURE (LOW GFX) ====
	-- Port LowGFX_ProcessOne / ApplyLowGFX / RestoreLowGFX dari Aeris.
	-- Tiap objek yang diubah disimpan dulu nilai aslinya biar bisa dibalikin.
	-- Skybox sengaja TIDAK dihapus (Aeris naruh itu di sub-option terpisah);
	-- hapus Sky bikin langit item total dan di sini itu kerasa kayak bug.
	local lowSaved = {}

	local function lowSave(obj, kind, extra)
		if #lowSaved > 6000 then return end
		table.insert(lowSaved, { obj = obj, kind = kind, extra = extra })
	end

	local function lowProcessOne(d)
		if not CFG.RemoveTexture or not d then return end
		pcall(function()
			if (d:IsA("BasePart") or d:IsA("UnionOperation") or d:IsA("MeshPart"))
				and d.Material ~= Enum.Material.SmoothPlastic then
				lowSave(d, "Part", d.Material)
				d.Material = Enum.Material.SmoothPlastic
			end
			if (d:IsA("ParticleEmitter") or d:IsA("Smoke") or d:IsA("Explosion")
				or d:IsA("Sparkles") or d:IsA("Fire")) and d.Enabled ~= false then
				lowSave(d, "Particle", true)
				d.Enabled = false
			end
			if (d:IsA("BloomEffect") or d:IsA("BlurEffect") or d:IsA("DepthOfFieldEffect")
				or d:IsA("SunRaysEffect") or d:IsA("ColorCorrectionEffect")) and d.Enabled ~= false then
				lowSave(d, "VFX", true)
				d.Enabled = false
			end
			if (d:IsA("Decal") or d:IsA("Texture")) and d.Texture ~= "" then
				lowSave(d, "Texture", d.Texture)
				d.Texture = ""
			end
		end)
	end

	local function lowApply()
		if not CFG.RemoveTexture then return end
		for _, root in ipairs({ workspace, Lighting }) do
			local i = 0
			for _, d in ipairs(root:GetDescendants()) do
				i = i + 1
				if i % 250 == 0 then task.wait() end
				if not CFG.RemoveTexture then return end
				lowProcessOne(d)
			end
		end
	end

	local function lowRestore()
		for _, s in ipairs(lowSaved) do
			local o = s.obj
			if o and o.Parent then
				pcall(function()
					if s.kind == "Part" then
						o.Material = s.extra
					elseif s.kind == "Texture" then
						o.Texture = s.extra
					else
						o.Enabled = s.extra
					end
				end)
			end
		end
		table.clear(lowSaved)
	end

	NYB.lowGfx = function(on)
		if on then
			task.spawn(lowApply)
		else
			lowRestore()
		end
	end

	-- map baru yang di-stream masuk juga harus diproses, kalau nggak cuma
	-- bagian awal map yang kehilangan tekstur
	NYB.bind(workspace.DescendantAdded, function(d)
		if not CFG.RemoveTexture then return end
		task.defer(lowProcessOne, d)
	end)

	table.insert(NYB.cleanups, function()
		pcall(lowRestore)
	end)
end

--===================== [ 11c. PORT AERIS: INFO OVERLAY ] ==================
-- Port ADITIF dari source Aeris (baris 5843-5960, 12195-12740, 16991-17022).
-- Tiga overlay: Killer Perks Display, Killer Stun Indicator, Spectator Info.
-- Next Killer / Next Map sudah ada di NYB, jadi nggak diutak-atik.
do
	--==== KILLER PERKS DISPLAY ====
	-- Aeris baca anak-anak karakter killer yang namanya berakhiran angka
	-- ("Nama Perk 3"), terus buang nama body part. Itu sumber datanya.
	local perksGui, perksLabel = nil, nil

	local BODY_NAMES = {
		head = true, torso = true, humanoid = true, humanoidrootpart = true,
		["left arm"] = true, ["right arm"] = true, ["left leg"] = true, ["right leg"] = true,
	}

	local function perkParse(name)
		local base, lvl = tostring(name or ""):match("^(.+)%s+(%d+)$")
		if not base then return nil end
		base = base:gsub("^%s+", ""):gsub("%s+$", "")
		if base == "" or BODY_NAMES[base:lower()] then return nil end
		return base, lvl
	end

	local function richEscape(s)
		return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	end

	local function perksBuild()
		if perksGui and perksGui.Parent then pcall(function() perksGui:Destroy() end) end
		perksGui, perksLabel = nil, nil
		if not CFG.KillerPerks then return end
		perksGui = Instance.new("ScreenGui")
		perksGui.Name = "NYB_KillerPerks"
		perksGui.ResetOnSpawn = false
		perksGui.IgnoreGuiInset = true
		perksGui.Parent = NYB.ui.gui

		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(0, 180, 0, 85)
		holder.Position = UDim2.new(0.08, 0, 0.22, 0)
		holder.BackgroundTransparency = 1
		holder.Parent = perksGui

		local panel = Instance.new("Frame")
		panel.Size = UDim2.new(1, 0, 1, 0)
		panel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		panel.BackgroundTransparency = 0.15
		panel.BorderSizePixel = 0
		panel.Parent = holder
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(0, 6)
		pc.Parent = panel
		local ps = Instance.new("UIStroke")
		ps.Color = Color3.fromRGB(60, 60, 70)
		ps.Thickness = 1
		ps.Transparency = 0.3
		ps.Parent = panel

		local head = Instance.new("Frame")
		head.Size = UDim2.new(1, 0, 0, 24)
		head.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		head.BorderSizePixel = 0
		head.Parent = panel
		local hc = Instance.new("UICorner")
		hc.CornerRadius = UDim.new(0, 6)
		hc.Parent = head

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, -60, 1, 0)
		title.Position = UDim2.new(0, 8, 0, 0)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamSemibold
		title.Text = "Killer Perks Info"
		title.TextColor3 = Color3.fromRGB(220, 220, 230)
		title.TextSize = 11
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Parent = head

		perksLabel = Instance.new("TextLabel")
		perksLabel.Size = UDim2.new(1, -14, 1, -32)
		perksLabel.Position = UDim2.new(0, 8, 0, 28)
		perksLabel.BackgroundTransparency = 1
		perksLabel.Font = Enum.Font.GothamMedium
		perksLabel.RichText = true
		perksLabel.TextXAlignment = Enum.TextXAlignment.Left
		perksLabel.TextYAlignment = Enum.TextYAlignment.Top
		perksLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
		perksLabel.TextSize = 11
		perksLabel.TextWrapped = false
		perksLabel.Parent = panel
	end

	local function killerPlayer()
		for _, p in ipairs(Players:GetPlayers()) do
			if NYB.isKiller(p) then return p end
		end
		return nil
	end

	local function perksOf(p)
		local out, seen = {}, {}
		if not p then return out end
		local model = p.Character or workspace:FindFirstChild(p.Name) or workspace:FindFirstChild(p.DisplayName)
		if not model then return out end
		for _, ch in ipairs(model:GetChildren()) do
			local nm, lvl = perkParse(ch.Name)
			if nm and not seen[nm] then
				seen[nm] = true
				table.insert(out, { Name = nm, Level = lvl })
			end
		end
		table.sort(out, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
		return out
	end

	local function perksTick()
		if not (CFG.KillerPerks and perksLabel) then return end
		local kp = killerPlayer()
		local name = kp and (kp.DisplayName or kp.Name) or "Unknown"
		local list = perksOf(kp)
		local lines = { "Killer Perks [<font color=\"rgb(255,80,80)\">" .. richEscape(name) .. "</font>]" }
		if #list == 0 then
			table.insert(lines, "<font color=\"rgb(200,200,200)\">- Waiting for perk data...</font>")
		else
			for i = 1, math.min(#list, 4) do
				local it = list[i]
				local lvl = it.Level and (" lvl " .. tostring(it.Level)) or ""
				table.insert(lines, "<font color=\"rgb(200,200,200)\">- " .. richEscape(it.Name .. lvl) .. "</font>")
			end
		end
		perksLabel.Text = table.concat(lines, "\n")
	end

	NYB.killerPerks = function(on)
		if on then
			perksBuild()
		else
			if perksGui then pcall(function() perksGui:Destroy() end) end
			perksGui, perksLabel = nil, nil
		end
	end

	--==== KILLER STUN INDICATOR ====
	-- Cincin muter di atas kepala killer tiap atribut IsStunned / Immobile true.
	local stunData = {}

	local function stunRingBuild(hrp)
		local old = hrp:FindFirstChild("NYB_StunRing")
		if old then pcall(function() old:Destroy() end) end
		local bb = Instance.new("BillboardGui")
		bb.Name = "NYB_StunRing"
		bb.Adornee = hrp
		bb.AlwaysOnTop = true
		bb.Size = UDim2.new(0, 40, 0, 40)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		bb.ResetOnSpawn = false
		bb.LightInfluence = 0
		bb.Enabled = false
		bb.Parent = hrp
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.new(1, 0, 1, 0)
		img.BackgroundTransparency = 1
		img.Image = "rbxassetid://129594563448607"
		img.ScaleType = Enum.ScaleType.Fit
		img.Parent = bb

		task.spawn(function()
			local angle = 0
			while bb and bb.Parent and CFG.StunRing do
				if bb.Enabled and cam then
					angle = (angle + 6) % 360
					img.Rotation = angle
					-- makin jauh makin gede biar tetap kebaca (angka dari Aeris)
					local d = (cam.CFrame.Position - hrp.Position).Magnitude
					local px = math.clamp(math.floor(600 / math.max(d, 1)), 22, 44)
					bb.Size = UDim2.new(0, px, 0, px)
				end
				task.wait(0.1)
			end
			pcall(function() bb:Destroy() end)
		end)
		return bb
	end

	local function stunWatch(char)
		if not char or stunData[char] then return end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		local bb = stunRingBuild(hrp)
		local rec = { ring = bb, timer = nil, conns = {} }
		stunData[char] = rec

		local function trigger(dur)
			if not rec.ring then return end
			rec.ring.Enabled = true
			if rec.timer then pcall(task.cancel, rec.timer) end
			rec.timer = task.delay(dur or 2.2, function()
				if rec.ring then rec.ring.Enabled = false end
			end)
		end

		for _, attr in ipairs({ "IsStunned", "Immobile" }) do
			local ok, c = pcall(function()
				return char:GetAttributeChangedSignal(attr):Connect(function()
					if char:GetAttribute(attr) == true then trigger(2.2) end
				end)
			end)
			if ok and c then table.insert(rec.conns, c) end
		end
	end

	local function stunClear()
		for char, rec in pairs(stunData) do
			if rec.timer then pcall(task.cancel, rec.timer) end
			for _, c in ipairs(rec.conns) do pcall(function() c:Disconnect() end) end
			if rec.ring then pcall(function() rec.ring:Destroy() end) end
			stunData[char] = nil
		end
	end

	local function stunScan()
		if not CFG.StunRing then return end
		for _, p in ipairs(Players:GetPlayers()) do
			if NYB.isKiller(p) and p.Character then stunWatch(p.Character) end
		end
	end

	NYB.stunRing = function(on)
		if not on then stunClear() return end
		stunScan()
	end

	NYB.bind(Players.PlayerAdded, function(p)
		NYB.bind(p.CharacterAdded, function(ch)
			task.wait(0.5)
			if CFG.StunRing and NYB.isKiller(p) then stunWatch(ch) end
		end)
	end)
	NYB.bind(lp.CharacterAdded, function()
		task.wait(1.5)
		stunScan()
	end)

	--==== SPECTATOR INFO ====
	-- Hitung pemain yang di tim "Spectator", tampil di tengah-bawah.
	local specGui, specLbl = nil, nil

	local function specBuild()
		if specGui and specGui.Parent then pcall(function() specGui:Destroy() end) end
		specGui, specLbl = nil, nil
		if not CFG.Spectator then return end
		specGui = Instance.new("ScreenGui")
		specGui.Name = "NYB_SpectatorInfo"
		specGui.ResetOnSpawn = false
		specGui.IgnoreGuiInset = true
		specGui.Parent = NYB.ui.gui

		local box = Instance.new("Frame")
		box.Name = "MainBox"
		box.AnchorPoint = Vector2.new(0.5, 1)
		box.Position = UDim2.new(0.5, 0, 0, -10)
		box.Size = UDim2.new(0, 68, 0, 22)
		box.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
		box.BackgroundTransparency = 0.15
		box.BorderSizePixel = 0
		box.Parent = specGui
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 6)
		bc.Parent = box

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 22, 1, 0)
		icon.Position = UDim2.new(0, 4, 0, 0)
		icon.BackgroundTransparency = 1
		icon.Font = Enum.Font.GothamBold
		icon.Text = "👁"
		icon.TextColor3 = Color3.fromRGB(180, 150, 255)
		icon.TextSize = 12
		icon.Parent = box

		specLbl = Instance.new("TextLabel")
		specLbl.Size = UDim2.new(1, -28, 1, 0)
		specLbl.Position = UDim2.new(0, 26, 0, 0)
		specLbl.BackgroundTransparency = 1
		specLbl.Font = Enum.Font.GothamBold
		specLbl.TextColor3 = Color3.fromRGB(235, 235, 240)
		specLbl.TextSize = 13
		specLbl.TextXAlignment = Enum.TextXAlignment.Left
		specLbl.Text = "0"
		specLbl.Parent = box
	end

	local function specTick()
		if not (CFG.Spectator and specLbl and specGui) then return end
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do
			local t = p.Team
			if t and string.lower(t.Name) == "spectator" then n = n + 1 end
		end
		specLbl.Text = tostring(n)
		local box = specGui:FindFirstChild("MainBox")
		if box then
			box.Size = UDim2.new(0, 55 + (n >= 10 and 8 or 0) + (n >= 100 and 8 or 0), 0, 22)
		end
	end

	NYB.spectator = function(on)
		if on then
			specBuild()
			specTick()
		else
			if specGui then pcall(function() specGui:Destroy() end) end
			specGui, specLbl = nil, nil
		end
	end

	--==== LOOP BERSAMA ====
	-- Perks + spectator di-refresh 1x/detik, bukan tiap frame: dua-duanya
	-- cuma baca daftar pemain, nggak ada gunanya jalan 60x/detik.
	local infoLast = 0
	NYB.bind(RunService.Heartbeat, function()
		if not (CFG.KillerPerks or CFG.Spectator) then return end
		local now = tick()
		if now - infoLast < 1 then return end
		infoLast = now
		pcall(perksTick)
		pcall(specTick)
	end)

	table.insert(NYB.cleanups, function()
		if perksGui then pcall(function() perksGui:Destroy() end) perksGui, perksLabel = nil, nil end
		if specGui then pcall(function() specGui:Destroy() end) specGui, specLbl = nil, nil end
		pcall(stunClear)
	end)
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
		-- Bersihin SEMUA ScreenGui yang kita bikin, bukan cuma overlay.
		-- Sebelumnya cuma NYB.ui.gui yang di-destroy, jadi window utama,
		-- notifikasi, watermark, FOV aim, crosshair, dan info overlay tetap
		-- nangkring di layar. Habis itu reload bikin window dobel: yang lama
		-- udah mati (toggle-nya gak nyambung) tapi masih ketutup yang baru.
		local GUI_NAMES = {
			"NYB_MainHub", "NYB_Notifications", "NYB_Watermark", "NYB_HUB_Overlay",
			"NYB_AimFov", "NYB_Crosshair", "NYB_Info", "NYB_DashLock",
		}
		local function wipe(parent)
			if not parent then return end
			for _, name in ipairs(GUI_NAMES) do
				local g = parent:FindFirstChild(name)
				if g then pcall(function() g:Destroy() end) end
			end
		end
		pcall(function() wipe((gethui and gethui()) or game:GetService("CoreGui")) end)
		pcall(function() wipe(game:GetService("CoreGui")) end)
		pcall(function()
			local lp = game:GetService("Players").LocalPlayer
			wipe(lp and lp:FindFirstChild("PlayerGui"))
		end)
		pcall(function() NYB.ui.gui:Destroy() end)
		NYB_ENV.NYB_HUB_RUNNING = nil
		NYB_ENV.NYB_UNLOAD = nil
		print("[NYB HUB] Unloaded.")
	end

	-- diekspor biar load berikutnya bisa ngebunuh instance ini sendiri
	-- (lihat LOAD GUARD di baris paling atas)
	NYB_ENV.NYB_UNLOAD = NYB.unload
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
	U.dropdown(T.aim.page, "Crosshair Style", { "Plus", "Dot", "Circle" }, "Plus", "CrossStyle", function()
		NYB.buildCrosshair()
	end)
	U.slider(T.aim.page, "Crosshair Thickness", 1, 5, CFG.CrossThick, 0, function(v)
		CFG.CrossThick = v
		NYB.buildCrosshair()
	end)
	U.slider(T.aim.page, "Crosshair Position X", -100, 100, CFG.CrossOffX, 0, function(v)
		CFG.CrossOffX = v
		NYB.buildCrosshair()
	end)
	U.slider(T.aim.page, "Crosshair Position Y", -100, 100, CFG.CrossOffY, 0, function(v)
		CFG.CrossOffY = v
		NYB.buildCrosshair()
	end)
	U.keybind(T.aim.page, "Crosshair Toggle Key", "None", function(k) CFG.CrossKey = k end)
	NYB.hotkey("CrossKey", function()
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

	--======== VISUAL: KAMERA (port Aeris) ========
	U.section(T.vis.page, "Kamera")
	U.toggle(T.vis.page, "Third Person (Killer)", "ThirdPerson", function(v) NYB.thirdPerson(v) end)
	U.toggle(T.vis.page, "Infinity Zoom Out", "InfinityZoom", function(v)
		CFG.InfinityZoom = v
		-- Zoom Unlock (yang sudah ada) nulis property zoom yang sama dengan
		-- batas 500 stud. Infinity Zoom lebih kuat, jadi kalau ini nyala yang
		-- lama dimatiin -- kalau nggak, yang terakhir di-toggle yang menang.
		if v and CFG.InfZoom then NYB.setCfg("InfZoom", false) end
		NYB.infinityZoom(v)
	end)
	U.toggle(T.vis.page, "DBD Camera", "DBDCamera", function(v)
		CFG.DBDCamera = v
		if v then
			-- DBD nulis cam.CFrame tiap frame; Third Person juga. Dua-duanya
			-- nggak bisa jalan bareng, jadi yang ini menang.
			if CFG.ThirdPerson then NYB.setCfg("ThirdPerson", false) end
			NYB.dbdStart()
		else
			NYB.dbdStop()
		end
	end)
	U.slider(T.vis.page, "DBD Distance", 6, 20, CFG.DBDDistance, 1, function(v) CFG.DBDDistance = v end)
	U.slider(T.vis.page, "DBD Height", 1, 8, CFG.DBDHeight, 1, function(v) CFG.DBDHeight = v end)
	U.slider(T.vis.page, "DBD Run Smooth", 0.03, 0.35, CFG.DBDRunSmooth, 2, function(v) CFG.DBDRunSmooth = v end)
	U.slider(T.vis.page, "DBD Look Smooth", 0.08, 0.6, CFG.DBDLookSmooth, 2, function(v) CFG.DBDLookSmooth = v end)
	U.slider(T.vis.page, "DBD Sensitivity", 0.15, 1.2, CFG.DBDSens, 2, function(v) CFG.DBDSens = v end)
	U.slider(T.vis.page, "DBD Pitch Min", -1.2, 0, CFG.DBDPitchMin, 2, function(v) CFG.DBDPitchMin = v end)
	U.slider(T.vis.page, "DBD Pitch Max", 0, 1.2, CFG.DBDPitchMax, 2, function(v) CFG.DBDPitchMax = v end)
	U.slider(T.vis.page, "DBD FOV", 50, 90, CFG.DBDFOV, 0, function(v)
		CFG.DBDFOV = v
		if CFG.DBDCamera then pcall(function() cam.FieldOfView = v end) end
	end)

	--======== VISUAL: PERFORMA (port Aeris) ========
	U.section(T.vis.page, "Performa")
	U.toggle(T.vis.page, "No Shadow", "NoShadow", function(v)
		CFG.NoShadow = v
		NYB.applyPerf()
	end)
	U.toggle(T.vis.page, "Remove Texture (Low GFX)", "RemoveTexture", function(v)
		CFG.RemoveTexture = v
		NYB.lowGfx(v)
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
	local tpListHolder = Instance.new("Frame")
	tpListHolder.Size = UDim2.new(1, 0, 0, 0)
	tpListHolder.AutomaticSize = Enum.AutomaticSize.Y
	tpListHolder.BackgroundTransparency = 1
	tpListHolder.Parent = T.tp.page
	local tpLay = Instance.new("UIListLayout")
	tpLay.Padding = UDim.new(0, 5)
	tpLay.Parent = tpListHolder

	local function refreshTP()
		for _, ch in ipairs(tpListHolder:GetChildren()) do
			if ch:IsA("TextButton") then ch:Destroy() end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= lp then
				local role = NYB.role(plr)
				local btn = Instance.new("TextButton")
				btn.Size = UDim2.new(1, 0, 0, 28)
				btn.BackgroundColor3 = NYB.ui.colors.panel2
				btn.Text = string.format("[%s] %s", string.sub(role, 1, 1), plr.Name)
				btn.TextColor3 = role == "Killer" and CFG.ColorKiller or CFG.ColorSurvivor
				btn.TextSize = 12
				btn.Font = Enum.Font.GothamMedium
				btn.AutoButtonColor = false
				btn.Parent = tpListHolder
				local uc = Instance.new("UICorner")
				uc.CornerRadius = UDim.new(0, 7)
				uc.Parent = btn
				btn.MouseButton1Click:Connect(function()
					local char = plr.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					if hrp then
						NYB.tpTo(hrp.Position + Vector3.new(0, 2.5, 0))
						NYB.msg("TP ke " .. plr.Name)
					else
						NYB.msg(plr.Name .. " belum spawn.")
					end
				end)
			end
		end
	end
	NYB.ui.refreshTP = refreshTP
	U.button(T.tp.page, "Refresh Daftar Pemain", refreshTP)
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
	U.toggle(T.misc.page, "Killer Perks Display", "KillerPerks", function(v) NYB.killerPerks(v) end)
	U.toggle(T.misc.page, "Killer Stun Indicator", "StunRing", function(v) NYB.stunRing(v) end)
	U.toggle(T.misc.page, "Spectator Info", "Spectator", function(v) NYB.spectator(v) end)

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

	U.section(T.misc.page, "UI")
	U.toggle(T.misc.page, "Auto Fit Layar (HP)", "UIScaleAuto", function() NYB.ui.applyScale() end)
	U.slider(T.misc.page, "UI Scale", 0.40, 1.30, CFG.UIScale or 0.9, 2, function(v)
		CFG.UIScale = v
		NYB.ui.applyScale()
	end)
	U.button(T.misc.page, "Reset Ukuran Window", function()
		if type(NYB.ui.win) == "table" and type(NYB.ui.win.ResetSize) == "function" then
			NYB.ui.win.ResetSize()
		end
		NYB.msg("Ukuran window direset ke auto-fit.")
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
	U.label(T.misc.page, "NYB HUB v2.8 · engine UI pola Aeris (inline, rebrand NYB)\n"
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
	NYB.ui.notify("NYB HUB v2.8 loaded", 4)
	task.wait(0.4)
	NYB.ui.notify("Hotkey " .. tostring(CFG.Keybind):gsub("Enum.KeyCode.", "") .. " · Self Test di tab Main", 4)
end)

print("[NYB HUB] v2.8 loaded. Remote terdeteksi: " .. tostring(NYB.remotes.count()))
