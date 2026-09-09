#!/usr/bin/env bash
#
# fix_kernel_dkms.sh
#
# Script BERDIRI SENDIRI untuk memastikan module kernel hailo_pci cocok
# dengan kernel yang sedang aktif, dan me-rebuild lewat DKMS kalau tidak.
#
# Kapan dipakai:
#   - Setelah `apt full-upgrade` menaikkan versi kernel Raspberry Pi OS dan
#     tiba-tiba `hailortcli fw-control identify` gagal / lsmod tidak lagi
#     menunjukkan hailo_pci.
#   - Setelah reboot pertama kali pasca instalasi awal, untuk verifikasi.
#
# Ini TIDAK meng-install ulang HailoRT/TAPPAS dari nol -- kalau itu yang
# kamu butuhkan, jalankan install_requirements.sh.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HAILORT_VERSION="4.23.0"
MODULE_NAME="hailo_pci"

if [[ "$EUID" -ne 0 ]]; then
  echo "[ERROR] Jalankan dengan sudo -- butuh akses dkms/modprobe."
  exit 1
fi

# shellcheck source=lib/dkms_kernel_check.sh
source "${SCRIPT_DIR}/lib/dkms_kernel_check.sh"

echo "=== Cek & perbaiki DKMS module ${MODULE_NAME} untuk kernel aktif ==="
echo ""

if ensure_dkms_module_for_current_kernel "$MODULE_NAME" "$HAILORT_VERSION"; then
  echo ""
  echo "[OK] ${MODULE_NAME} siap. Verifikasi device:"
  echo ""
  hailortcli fw-control identify || echo "[WARN] hailortcli gagal -- device mungkin belum ke-detect PCIe-nya, cek 'lspci | grep -i hailo'."
else
  echo ""
  echo "[WARN] Belum berhasil otomatis. Kalau ini setelah instalasi PERTAMA KALI,"
  echo "       reboot dulu:  sudo reboot"
  echo "       lalu jalankan ulang script ini untuk verifikasi."
  exit 1
fi
