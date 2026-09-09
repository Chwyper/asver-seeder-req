# hailo-req-installer

**Repo privat — backup pribadi.** Berisi script otomatis untuk memasang
seluruh requirement Hailo (driver PCIe, HailoRT, TAPPAS Core, dan Python
binding-nya) sebelum menjalankan `install.sh` dari `hailo-apps`, ditambah
file `.deb`/`.whl` itu sendiri — supaya kalau microSD perlu di-flash ulang
atau OS diinstall ulang, tidak perlu login Developer Zone dan download ulang
dari awal.

## Struktur

```
hailo-req-installer/
├── install_requirements.sh     <- instalasi lengkap dari nol (7 langkah, termasuk step 0 di bawah)
├── prepare_kernel_dkms.sh      <- standalone: SEBELUM install driver, siapkan dkms/headers
├── fix_kernel_dkms.sh          <- standalone: SETELAH terpasang, perbaiki module usai kernel upgrade
├── lib/
│   ├── kernel_prereqs.sh       <- logic persiapan sebelum driver diinstall (dipakai 2 script)
│   └── dkms_kernel_check.sh    <- logic verifikasi/rebuild module setelah driver ada (dipakai 2 script)
├── .gitattributes              <- WAJIB: paksa LF, lihat catatan di bawah
├── packages/
│   ├── hailort-pcie-driver_4.23.0_all.deb
│   ├── hailort_4.23.0_arm64.deb
│   ├── hailo-tappas-core_5.1.0_arm64.deb
│   ├── hailort-4.23.0-cp311-cp311-linux_aarch64.whl
│   ├── hailo_tappas_core_python_binding-5.1.0-py3-none-any.whl
│   └── python3-hailo-tappas_5.1.0_arm64.deb      (opsional, system Python)
└── README.md
```

**Kenapa ada dua library DKMS terpisah, bukan satu:** `kernel_prereqs.sh`
urus kondisi **sebelum** module Hailo ada sama sekali (dkms, build-essential,
headers) -- dipakai `prepare_kernel_dkms.sh` dan sebagai Step 0 otomatis di
`install_requirements.sh`. `dkms_kernel_check.sh` urus kondisi **setelah**
module sudah pernah ter-build sekali, tapi kernel naik versi dan perlu
rebuild -- dipakai `fix_kernel_dkms.sh` dan Step 5 di `install_requirements.sh`.
Beda tahap, beda tanggung jawab, jadi sengaja tidak digabung satu file.

## PENTING kalau develop dari Windows: soal line ending

Windows (Notepad, PowerShell, VS Code tanpa setting eol) menyimpan text file
dengan CRLF (`\r\n`). Bash di Raspberry Pi/Linux expect LF (`\n`) saja. Kalau
file `.sh` ke-commit dengan CRLF, script akan gagal jalan di Pi dengan error
semacam `$'\r': command not found`, atau bahkan shebang `#!/usr/bin/env bash`
tidak dikenali sama sekali.

`.gitattributes` di repo ini sudah di-set `*.sh text eol=lf` supaya git
otomatis normalize ke LF setiap commit, apa pun editor yang kamu pakai. Tapi
kalau kamu **clone repo ini pertama kali di Windows** sebelum `.gitattributes`
sempat diterapkan, jalankan ini sekali di Windows setelah clone untuk pastikan:

```powershell
git config core.autocrlf input
```

Dan kalau suatu saat script tetap error di Pi meski sudah ada `.gitattributes`,
cek cepat dari sisi Linux:

```bash
file install_requirements.sh
# harusnya: "Bourne-Again shell script, ASCII text executable"
# kalau muncul "with CRLF line terminators", jalankan:
sed -i 's/\r$//' install_requirements.sh fix_kernel_dkms.sh lib/dkms_kernel_check.sh
```

## Tiga script, tiga kebutuhan berbeda

**`install_requirements.sh`** — instalasi lengkap dari nol: persiapan
kernel/DKMS, driver PCIe, HailoRT, TAPPAS Core, verifikasi module, sampai
Python binding di venv. Pakai ini setelah flash OS baru — sudah termasuk
semua langkah dua script di bawah, tidak perlu jalankan manual terpisah
kecuali mau debug satu bagian saja.

```bash
chmod +x install_requirements.sh prepare_kernel_dkms.sh fix_kernel_dkms.sh \
         lib/kernel_prereqs.sh lib/dkms_kernel_check.sh
sudo ./install_requirements.sh --venv /home/asver/project/hailo-apps/venv_hailo_apps
```

**`prepare_kernel_dkms.sh`** — standalone, cuma siapkan `dkms`,
`build-essential`, dan kernel headers yang match kernel aktif. Pakai ini
kalau mau cek/prep sistem terpisah dulu (mis. langsung setelah flash OS,
sebelum sempat siapkan file `packages/`), atau untuk debug kalau instalasi
driver Hailo gagal dengan pesan DKMS di `install_requirements.sh`:

```bash
sudo ./prepare_kernel_dkms.sh
```

**`fix_kernel_dkms.sh`** — standalone, urus kondisi SETELAH driver sudah
pernah terpasang. Pakai ini kalau semua sudah pernah jalan, tapi tiba-tiba
`hailortcli` berhenti kerja setelah `apt full-upgrade` menaikkan versi
kernel (kasus yang pernah kejadian: driver ter-build untuk kernel lama,
kernel baru jalan tanpa driver ter-load). Tidak install ulang HailoRT/TAPPAS
dari nol, cuma rebuild module kernel-nya:

```bash
sudo ./fix_kernel_dkms.sh
```

## Versi yang dipakai

Mengikuti `valid_combinations` di `hailo_apps/config/config.yaml` untuk
arch **hailo8** / **hailo8l**:

```
HailoRT      : 4.23.0
TAPPAS Core  : 5.1.0
```

Kalau kamu pindah ke arch **hailo10h**, cek ulang kombinasi valid di
`config.yaml` — beda (5.1.1:5.1.0, 5.2.0:5.2.0, atau 5.3.0:5.3.0). Kalau
ganti versi, update juga dua variabel `HAILORT_VERSION`/`TAPPAS_VERSION`
di awal `install_requirements.sh` DAN `fix_kernel_dkms.sh`. (`prepare_kernel_dkms.sh`
tidak menyebut versi HailoRT/TAPPAS sama sekali -- dia cuma urus prasyarat
generik yang sama untuk versi berapa pun.)

## Ukuran file

File terbesar saat ini ~9.9MB (`hailort-*.whl`) — jauh di bawah limit
GitHub (100MB hard limit, 50MB warning), jadi git biasa cukup, tidak perlu
Git LFS.

## Kenapa tetap privat, meski file sudah ikut di-commit

Walau repo ini privat sekarang, jangan jadikan kebiasaan meng-assume repo
privat selalu aman disimpan begini seterusnya — kalau suatu saat repo
di-fork, di-transfer ke organisasi, atau tidak sengaja diubah jadi publik,
file proprietary Hailo ikut ter-expose. Untuk kebutuhan sekarang (backup
pribadi, repo privat, satu pemilik) ini keputusan yang wajar; cukup diingat
risikonya kalau visibility repo berubah nanti.
