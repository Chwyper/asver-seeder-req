#!/usr/bin/env bash
#
# lib/kernel_prereqs.sh
#
# Fungsi bersama untuk memastikan sistem SIAP membangun module kernel lewat
# DKMS SEBELUM driver Hailo (hailort-pcie-driver_*.deb) diinstall. Kalau
# prasyarat ini belum ada saat driver di-install, hook DKMS bawaan .deb akan
# gagal diam-diam dan fallback ke instalasi non-DKMS -- yang artinya module
# TIDAK akan otomatis rebuild kalau kernel naik versi nanti.
#
# Dipakai oleh prepare_kernel_dkms.sh (standalone) dan install_requirements.sh
# (dipanggil otomatis sebagai langkah pertama).

KPRE_LOG_PREFIX="[kernel-prereqs]"
_kpre_log() { echo "  ${KPRE_LOG_PREFIX} $*"; }

# ensure_kernel_build_prereqs
#
# Install dkms, build-essential (gcc/make/dll dibutuhkan DKMS untuk compile
# module), dan kernel headers yang PERSIS cocok dengan kernel aktif saat ini.
# Return 0 kalau semua siap, 1 kalau ada yang gagal dan butuh intervensi manual.
ensure_kernel_build_prereqs() {
  local current_kernel
  current_kernel="$(uname -r)"

  _kpre_log "Kernel aktif: ${current_kernel}"

  apt-get update -qq

  # 1. build-essential -- gcc/make/dll yang dipakai DKMS untuk compile module.
  #    Tanpa ini, dkms build akan gagal walau header lengkap.
  if dpkg -s build-essential >/dev/null 2>&1; then
    _kpre_log "build-essential sudah terpasang."
  else
    _kpre_log "Install build-essential..."
    apt-get install -y build-essential
  fi

  # 2. dkms itu sendiri.
  if command -v dkms >/dev/null 2>&1; then
    _kpre_log "dkms sudah terpasang ($(dkms --version 2>&1 | head -1))."
  else
    _kpre_log "Install dkms..."
    apt-get install -y dkms
  fi

  # 3. Kernel headers -- HARUS persis match kernel aktif, bukan cuma "ada
  #    beberapa versi headers lain di sistem". Ini penyebab paling umum DKMS
  #    diam-diam gagal build.
  if [[ -d "/usr/src/linux-headers-${current_kernel}" || -d "/lib/modules/${current_kernel}/build" ]]; then
    _kpre_log "Kernel headers untuk ${current_kernel} sudah ada."
  else
    _kpre_log "Kernel headers untuk ${current_kernel} belum ada, mencoba install..."
    if apt-get install -y "linux-headers-${current_kernel}" 2>/dev/null; then
      _kpre_log "linux-headers-${current_kernel} terpasang."
    elif apt-get install -y raspberrypi-kernel-headers 2>/dev/null; then
      _kpre_log "raspberrypi-kernel-headers terpasang (fallback nama paket generik)."
    else
      _kpre_log "GAGAL: tidak ketemu paket headers yang cocok untuk ${current_kernel}."
      _kpre_log "Cek manual: apt-cache search linux-headers | grep \$(uname -r | cut -d- -f1)"
      return 1
    fi
  fi

  # 4. Verifikasi ulang -- kalau setelah apt install pun headers tetap tidak
  #    ketemu (mis. repo tidak punya versi persis, kernel custom/backport),
  #    lebih baik gagal eksplisit di sini daripada nanti gagal samar-samar
  #    saat dkms build driver Hailo.
  if [[ ! -d "/usr/src/linux-headers-${current_kernel}" && ! -d "/lib/modules/${current_kernel}/build" ]]; then
    _kpre_log "GAGAL: headers ter-install tapi tidak match ${current_kernel} persis."
    _kpre_log "Kemungkinan repo apt kamu belum sinkron dengan kernel image yang jalan."
    _kpre_log "Coba: sudo apt full-upgrade -y   (biar kernel + headers naik bareng), lalu reboot dan ulangi."
    return 1
  fi

  _kpre_log "Semua prasyarat DKMS siap untuk kernel ${current_kernel}."
  return 0
}
