#!/usr/bin/env bash
#
# lib/dkms_kernel_check.sh
#
# Fungsi bersama untuk memastikan module DKMS hailo_pci ter-build dan
# ter-load untuk kernel yang SEDANG AKTIF. Dipakai oleh install_requirements.sh
# dan fix_kernel_dkms.sh -- jangan duplikasi logic ini di dua tempat, cukup
# source file ini.
#
# Wajib dijalankan sebagai root (dipanggil dari script yang sudah cek EUID).

DKMS_LOG_PREFIX="[dkms-check]"

_dkms_log()  { echo "  ${DKMS_LOG_PREFIX} $*"; }

# ensure_dkms_module_for_current_kernel <module_name> <expected_version>
#
# module_name     : nama module DKMS, mis. "hailo_pci"
# expected_version: versi yang di-expect ada di /usr/src/<module_name>-<version>,
#                    mis. "4.23.0"
#
# Return 0 kalau module sudah/berhasil di-load untuk kernel aktif.
# Return 1 kalau gagal dan butuh intervensi manual (mis. reboot pertama kali,
# atau source DKMS tidak ditemukan sama sekali).
ensure_dkms_module_for_current_kernel() {
  local module_name="$1"
  local expected_version="$2"
  local current_kernel
  current_kernel="$(uname -r)"

  _dkms_log "Kernel aktif: ${current_kernel}"

  if ! command -v dkms >/dev/null 2>&1; then
    _dkms_log "dkms tidak terpasang. Install dulu: apt-get install -y dkms"
    return 1
  fi

  # 1. Pastikan kernel headers untuk kernel aktif ada.
  #    Nama paket berbeda-beda antar rilis Raspberry Pi OS/Debian, jadi coba
  #    beberapa kandidat daripada hardcode satu nama.
  if [[ ! -d "/usr/src/linux-headers-${current_kernel}" && ! -d "/lib/modules/${current_kernel}/build" ]]; then
    _dkms_log "Kernel headers untuk ${current_kernel} belum terdeteksi, mencoba install..."
    apt-get update -qq
    if apt-get install -y "linux-headers-${current_kernel}" 2>/dev/null; then
      _dkms_log "linux-headers-${current_kernel} terpasang."
    elif apt-get install -y raspberrypi-kernel-headers 2>/dev/null; then
      _dkms_log "raspberrypi-kernel-headers terpasang (fallback)."
    else
      _dkms_log "Gagal install kernel headers otomatis. Cek manual: apt-cache search linux-headers"
      return 1
    fi
  else
    _dkms_log "Kernel headers untuk ${current_kernel} sudah ada."
  fi

  # 2. Cek apakah module sudah ter-build untuk kernel ini.
  local status_output
  status_output="$(dkms status "${module_name}" 2>/dev/null || true)"

  if echo "$status_output" | grep -q "${current_kernel}"; then
    _dkms_log "${module_name} sudah ter-build untuk kernel aktif."
  else
    _dkms_log "${module_name} BELUM ter-build untuk kernel aktif. Rebuild..."

    local src_dir
    src_dir="/usr/src/${module_name}-${expected_version}"

    if [[ ! -d "$src_dir" ]]; then
      _dkms_log "Source tidak ditemukan di ${src_dir}."
      _dkms_log "Pastikan paket driver (hailort-pcie-driver) sudah pernah di-install minimal sekali."
      return 1
    fi

    # add tidak masalah dipanggil berulang -- dkms akan bilang "already added"
    # kalau memang sudah, itu bukan error fatal.
    dkms add "$src_dir" 2>/dev/null || true

    if dkms install "${module_name}/${expected_version}" -k "$current_kernel" --force; then
      _dkms_log "Rebuild ${module_name}/${expected_version} untuk ${current_kernel} berhasil."
    else
      _dkms_log "Rebuild GAGAL. Cek log di /var/lib/dkms/${module_name}/${expected_version}/build/make.log"
      return 1
    fi
  fi

  # 3. Load module.
  if lsmod | grep -q "^${module_name} "; then
    _dkms_log "${module_name} sudah ter-load."
    return 0
  fi

  if modprobe "$module_name" 2>/dev/null; then
    _dkms_log "${module_name} berhasil di-load."
    return 0
  else
    _dkms_log "modprobe ${module_name} gagal. Kalau ini instalasi PERTAMA KALI (bukan rebuild"
    _dkms_log "setelah kernel upgrade), ini normal -- reboot dulu, lalu jalankan ulang script ini"
    _dkms_log "untuk verifikasi module ter-load otomatis saat boot."
    return 1
  fi
}
