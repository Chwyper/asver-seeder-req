#!/usr/bin/env bash
#
# prepare_kernel_dkms.sh
#
# Jalankan ini PALING PERTAMA, sebelum install_requirements.sh, kalau kamu
# mau pastikan sistem siap membangun module kernel via DKMS sebelum driver
# Hailo (hailort-pcie-driver_*.deb) diinstall.
#
# install_requirements.sh sebenarnya sudah panggil fungsi yang sama secara
# otomatis di awal -- script ini untuk kamu yang mau cek/prep sistem secara
# terpisah dulu (mis. langsung setelah flash OS baru, sebelum sempat clone
# repo requirement Hailo-nya sekalipun).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$EUID" -ne 0 ]]; then
  echo "[ERROR] Jalankan dengan sudo -- butuh akses apt."
  exit 1
fi

# shellcheck source=lib/kernel_prereqs.sh
source "${SCRIPT_DIR}/lib/kernel_prereqs.sh"

echo "=== Persiapan kernel/DKMS sebelum instalasi driver Hailo ==="
echo ""

if ensure_kernel_build_prereqs; then
  echo ""
  echo "[OK] Sistem siap. Lanjut ke:"
  echo "     sudo ./install_requirements.sh --venv /path/ke/venv_hailo_apps"
else
  echo ""
  echo "[ERROR] Ada prasyarat yang gagal disiapkan -- lihat pesan di atas sebelum lanjut."
  echo "        Jangan install driver Hailo dulu sebelum ini beres, supaya DKMS hook"
  echo "        bawaan driver tidak diam-diam fallback ke instalasi non-DKMS."
  exit 1
fi
