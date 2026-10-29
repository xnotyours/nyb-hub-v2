# NYB HUB v2 — Violence District Toolkit

Rebuild dari nol. Bukan tambalan dari v3.1.

| | |
|---|---|
| Versi | v2 |
| File | `nyb_hub_v2.lua` — 1.155 baris |
| Engine UI | [WindUI](https://github.com/Footagesus/WindUI), di-fetch via `HttpGet` saat inject |
| Target | [BUTCHER] Violence District (PlaceId `93978595733734`) |
| Platform | Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift) |

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/xnotyours/nyb-hub-v2/main/nyb_hub_v2.lua"))()
```

## Kenapa ditulis ulang

Versi v3.1 menumpuk 3 bug di lapisan port UI — semuanya gagal **diam-diam**, jadi
gejalanya "menu muncul, fitur nggak ngefek":

1. `U.section` pakai `parentOf(page)` → `__cur`, jadi section ke-2 dibuat di dalam
   section ke-1, ke-3 di dalam ke-2 — sampai 10 level di tab Auto.
2. `Section:Expandable` baru jadi `true` saat element pertama masuk, dan
   `Open()`/`Close()` dua-duanya di-guard `if Expandable`. Jadi `Open()` yang
   dipanggil `task.defer` itu no-op → section kekunci di tinggi header, dan
   `Main.Outline` punya `ClipsDescendants = true` → toggle ke-clip, gak kelihatan,
   gak bisa diklik.
3. Build gagal separuh tanpa jejak: satu method hilang = satu exception = seluruh
   chunk mati setelah window kebentuk.

## Aturan desain v2 — biar kelas bug itu gak bisa kejadian lagi

- **TIDAK pakai WindUI `Section` sama sekali.** Header grup = `Paragraph`,
  pemisah = `Divider`, element nempel langsung di **Tab**. Jadi nol risiko
  `Expandable`, nol nesting, nol `ClipsDescendants`.
- **Semua helper nempel di root table `N`.** Gak ada `local` yang dideklarasi di
  dalam `do ... end` lalu dipakai di blok lain — itu penyebab "This tab is Empty"
  di v3.1 (`luac -p` lolos, runtime `nil`).
- **Tiap method WindUI di-feature-detect** lewat `N.ui.pick(tab, method)`. Kalau
  versi WindUI beda dan method-nya nggak ada, kejadiannya **dicatat ke log**, bukan
  bikin chunk mati. Gak ada kegagalan senyap.
- **Remote dari dump asli**, bukan tebakan nama.
- **Main chunk cuma 13 `local`** (limit Lua 200).

## Coba fitur satu-satu

Tab **Main → `SELF TEST`**. Dia jalanin tiap fitur satu per satu, verifikasi
hasilnya, terus nampilin laporan **di layar** (plus ke clipboard):

- `[OK ]` fitur jalan, plus detail terukurnya (mis. `WalkSpeed=28 (harus > 16)`)
- `[!! ]` fitur gagal, plus alasannya
- `[-- ]` gak ada test buat fitur itu

Jadi lu gak perlu baca console executor — hasilnya baca langsung dari layar.

## Fitur

**Main** — Preset Survivor, Preset Killer, Matikan Semua Fitur, Self Test,
Scan Ulang Map, Dump Remote, Unload

**ESP** — ESP Pemain (+ Chams / Nama / Jarak / HP), Jarak Maks ESP,
ESP Generator, Gate/Exit, Hook, Pallet, Window/Vault

**Aim** — Aimbot, Wall Check, Lingkaran FOV, FOV Radius, Smoothness

**Auto** — Auto Heal, Auto Parry, Kill Aura, Attack Range

**Movement** — Speed Boost, WalkSpeed, Fly, Fly Speed, Noclip, Infinite Jump

**Visual** — Fullbright, No Fog, Camera FOV, FOV Value

**Misc** — Remote Log, Resolve Remote Ulang

## Catatan

- `Remotes.Mechanics.Chat.*` (TempBan / PermaBan / Unban) **sengaja gak dipakai** —
  itu tool moderasi server, bukan fitur cheat.
- Guard global: `getgenv().NYB2_RUNNING`. Tekan **Unload** sebelum reload.
- Kalau panel/toggle ilang: tekan hotkey `RightShift` (WindUI yang pegang).
