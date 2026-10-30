# NYB HUB — Violence District Toolkit

| | |
|---|---|
| Versi | **v2.7** |
| File aktif | `nyb_hub_vanilla.lua` — 6.621 baris, ~245 KB |
| Engine UI | pola **Aeris Hub (VD)** — kode diangkat **inline** ke dalam file, di-rebrand jadi NYB (`CreateAerisLibrary` → `CreateNYBLibrary`, `Aeris_*` → `NYB_*`) |
| Dependensi luar | **nol** — gak pakai `loadstring`, gak fetch library pihak ketiga |
| Target | [BUTCHER] Violence District (PlaceId `93978595733734`) |
| Platform | Mobile (Delta / Hydrogen) + PC (Xeno / Wave / Swift) |

## Load

```lua
-- commit-pinned: immutable, gak kena cache CDN
loadstring(game:HttpGet("https://raw.githubusercontent.com/xnotyours/nyb-hub-v2/9865759/nyb_hub_vanilla.lua"))()
```

> **PENTING — `raw.githubusercontent.com` nge-cache `main` selama 5 menit**
> (`cache-control: max-age=300`, `x-cache: HIT`). Habis push, URL `.../main/...`
> bisa masih nyajiin versi lama; `?v=<timestamp>` nggak nolongin.
> Yang bener: **pin commit SHA** — immutable. Verifikasi dengan
> `sha256sum` lokal vs `curl -sL <url> | sha256sum`, harus sama.

## Isi repo

- `nyb_hub_vanilla.lua` — **versi aktif**. Engine UI pola Aeris, kode fitur v2.6.
- `nyb_hub_rayfield.lua` — varian yang UI-nya Rayfield, kode fitur sama.
- `nyb_hub_v2.lua` — percobaan rebuild WindUI (tidak dipakai; butuh `HttpGet` saat inject).

## Struktur

**9 tab · 32 section · 86 toggle · 45 slider · 34 tombol**

- **Main** — Preset, Session
- **ESP** — Pemain, Objek Map, Lain
- **Aim** — Aimbot, Silent Aim
- **Auto** — Generator, Survivor QoL, Killer, Survivor Utility, Killer Utility,
  Fake Perks, Killer Ability, Status Generator, Item
- **Combat** — Parry
- **Movement** — Kecepatan, Terbang & Noclip, Lain
- **Visual** — Layar
- **Teleport** — Objek Map, Pemain
- **Misc** — Diagnostik, Probe, Info Overlay, Gate, Cosmetic / QoL, **UI**, Config,
  Remote Terdeteksi, Info

## UI Scale (v2.7)

Ukuran window dulu dipatok mati **690×470 px** — di HP itu nutup ~60% lebar dan
hampir seluruh tinggi layar. Sekarang seluruh window (dan anak-anaknya) di-skala
lewat `UIScale`:

```
skala = autoFit(viewport) × UIScale
autoFit = min(viewport.X × 0.82 / 690, viewport.Y × 0.88 / 470, 1)   -- dibatasi 0.40
```

Dihitung ulang otomatis tiap `ViewportSize` berubah (rotasi layar). Kontrolnya di
**Misc → UI**: toggle *Auto Fit Layar (HP)*, slider *UI Scale* (0.40–1.30), dan
tombol *Reset Ukuran Window*. Nilainya ikut tersimpan di `NYB_HUB/config.json`.

## Config

Disimpan sebagai `NYB_HUB/config.json` di workspace executor (`makefolder` /
`isfolder` / `writefile`). Tombol Save / Load / Reset ada di **Misc → Config**.

## Catatan

- `Remotes.Mechanics.Chat.*` (TempBan / PermaBan / Unban) **sengaja gak dipakai** —
  itu tool moderasi server, bukan fitur cheat.
- Guard global pakai flag `NYB_ENV` / `NYB_HUB_RUNNING` di `getgenv()`. Tekan
  **Unload** dulu sebelum reload.
- Sisa sebutan "Aeris" di dalam file cuma komentar kredit port (6 baris), nol di
  kode jalan.
