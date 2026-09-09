#!/usr/bin/env bash
#
# install_requirements.sh
#
# Memasang seluruh requirement Hailo (driver PCIe, HailoRT, TAPPAS Core,
# dan Python binding-nya) sebelum menjalankan install.sh dari hailo-apps.
#
# Idempotent: aman dijalankan ulang, termasuk untuk memperbaiki DKMS module
# setelah kernel Raspberry Pi OS naik versi.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Konfigurasi versi — HARUS match dengan valid_combinations di
# hailo_apps/config/config.yaml pada repo hailo-apps yang kamu pakai.
# ---------------------------------------------------------------------------
HAILORT_VERSION="4.23.0"
TAPPAS_VERSION="5.1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="${SCRIPT_DIR}/packages"

# shellcheck source=lib/dkms_kernel_check.sh
source "${SCRIPT_DIR}/lib/dkms_kernel_check.sh"
# shellcheck source=lib/kernel_prereqs.sh
source "${SCRIPT_DIR}/lib/kernel_prereqs.sh"
VENV_PATH=""
SKIP_TAPPAS=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "[INFO]    $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*"; }
log_step()    { echo -e "\n=== $* ===\n"; }

usage() {
  cat <<EOF
Usage: sudo $0 --venv /path/to/venv_hailo_apps [--packages /path/to/packages] [--no-tappas]

  --venv PATH        Wajib. Path ke virtualenv project hailo-apps
                      (mis. /home/asver/project/hailo-apps/venv_hailo_apps)
  --packages PATH     Opsional. Default: ./packages relatif ke script ini.
  --no-tappas         Skip instalasi TAPPAS Core + binding-nya
                      (dipakai kalau cuma butuh standalone/gen-ai apps).
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --venv) VENV_PATH="$2"; shift 2 ;;
    --packages) PKG_DIR="$2"; shift 2 ;;
    --no-tappas) SKIP_TAPPAS=true; shift ;;
    -h|--help) usage ;;
    *) log_error "Argumen tidak dikenal: $1"; usage ;;
  esac
done

if [[ "$EUID" -ne 0 ]]; then
  log_error "Jalankan dengan sudo, karena butuh dpkg/apt/dkms."
  exit 1
fi

if [[ -z "$VENV_PATH" ]]; then
  log_error "--venv wajib diisi. Contoh: --venv /home/asver/project/hailo-apps/venv_hailo_apps"
  usage
fi

if [[ ! -d "$VENV_PATH" ]]; then
  log_error "Venv tidak ditemukan di: $VENV_PATH"
  log_error "Jalankan setup_env.sh di project hailo-apps dulu sebelum script ini, atau perbaiki path."
  exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"

# ---------------------------------------------------------------------------
# Step 0: Persiapan kernel/DKMS SEBELUM driver Hailo diinstall
# ---------------------------------------------------------------------------
log_step "Step 0/7: Persiapan kernel/DKMS"

# Logic ini juga dipakai standalone lewat prepare_kernel_dkms.sh. Dijalankan
# di sini otomatis supaya hook DKMS bawaan driver Hailo (yang muncul sebagai
# prompt "Do you wish to use DKMS?" saat dpkg -i) punya build-essential,
# dkms, dan kernel headers yang benar SUDAH siap saat dia jalan -- bukan
# fallback diam-diam ke instalasi non-DKMS seperti yang sempat terjadi
# sebelumnya.
if ! ensure_kernel_build_prereqs; then
  log_error "Persiapan kernel/DKMS gagal. Perbaiki dulu sebelum lanjut instalasi driver."
  exit 1
fi
log_ok "Sistem siap untuk build module kernel via DKMS."

# ---------------------------------------------------------------------------
# Step 1: Validasi file package tersedia
# ---------------------------------------------------------------------------
log_step "Step 1/7: Validasi file package"

find_pkg() {
  # find_pkg <pattern>
  local pattern="$1"
  local match
  match=$(find "$PKG_DIR" -maxdepth 1 -iname "$pattern" 2>/dev/null | head -1)
  echo "$match"
}

DRIVER_DEB=$(find_pkg "hailort-pcie-driver_${HAILORT_VERSION}_*.deb")
HAILORT_DEB=$(find_pkg "hailort_${HAILORT_VERSION}_*.deb")
HAILORT_WHL=$(find_pkg "hailort-${HAILORT_VERSION}-*.whl")

if [[ -z "$DRIVER_DEB" || -z "$HAILORT_DEB" || -z "$HAILORT_WHL" ]]; then
  log_error "File HailoRT versi ${HAILORT_VERSION} tidak lengkap di $PKG_DIR"
  log_error "Dibutuhkan: hailort-pcie-driver_${HAILORT_VERSION}_*.deb, hailort_${HAILORT_VERSION}_*.deb, hailort-${HAILORT_VERSION}-*.whl"
  log_error "Download dari https://hailo.ai/developer-zone/ (Software Suite -> HailoRT, arch arm64, OS Linux)"
  exit 1
fi
log_ok "Driver: $(basename "$DRIVER_DEB")"
log_ok "HailoRT: $(basename "$HAILORT_DEB")"
log_ok "HailoRT Python binding: $(basename "$HAILORT_WHL")"

if [[ "$SKIP_TAPPAS" == false ]]; then
  TAPPAS_DEB=$(find_pkg "hailo-tappas-core_${TAPPAS_VERSION}_*.deb")
  TAPPAS_WHL=$(find_pkg "hailo_tappas_core_python_binding-${TAPPAS_VERSION}-*.whl")
  # Binding TAPPAS untuk system Python (di luar venv) -- opsional, sebagian
  # setup tidak menyertakan file ini. Kalau tidak ada, dilewati tanpa error.
  TAPPAS_SYSTEM_PY_DEB=$(find_pkg "python3-hailo-tappas_${TAPPAS_VERSION}_*.deb")

  if [[ -z "$TAPPAS_DEB" || -z "$TAPPAS_WHL" ]]; then
    log_error "File TAPPAS versi ${TAPPAS_VERSION} tidak lengkap di $PKG_DIR"
    log_error "Dibutuhkan: hailo-tappas-core_${TAPPAS_VERSION}_*.deb, hailo_tappas_core_python_binding-${TAPPAS_VERSION}-*.whl"
    log_error "Kalau tidak butuh TAPPAS (standalone/gen-ai app saja), jalankan ulang dengan --no-tappas"
    exit 1
  fi
  log_ok "TAPPAS Core: $(basename "$TAPPAS_DEB")"
  log_ok "TAPPAS Python binding: $(basename "$TAPPAS_WHL")"
  if [[ -n "$TAPPAS_SYSTEM_PY_DEB" ]]; then
    log_ok "TAPPAS system-Python binding: $(basename "$TAPPAS_SYSTEM_PY_DEB")"
  else
    log_warn "python3-hailo-tappas_${TAPPAS_VERSION}_*.deb tidak ditemukan -- dilewati (opsional, hanya untuk system Python di luar venv)."
  fi
else
  log_warn "Mode --no-tappas: TAPPAS Core dilewati."
fi

# ---------------------------------------------------------------------------
# Step 1: Copot versi lama dari repo distro yang bisa konflik
# ---------------------------------------------------------------------------
log_step "Step 2/7: Membersihkan instalasi lama dari repo distro"

apt-get remove -y hailort python3-hailort hailo-tappas-core >/dev/null 2>&1 || true
log_ok "Selesai (paket yang tidak ada akan diabaikan)."

# ---------------------------------------------------------------------------
# Step 2: Install driver PCIe + HailoRT
# ---------------------------------------------------------------------------
log_step "Step 3/7: Install HailoRT PCIe driver + runtime"

apt-get update

dpkg -i "$DRIVER_DEB" || true
dpkg -i "$HAILORT_DEB" || true
apt-get -f install -y

log_ok "Driver dan HailoRT terpasang."

# ---------------------------------------------------------------------------
# Step 3: Install TAPPAS Core (dan dependency-nya via apt)
# ---------------------------------------------------------------------------
if [[ "$SKIP_TAPPAS" == false ]]; then
  log_step "Step 4/7: Install TAPPAS Core"

  dpkg -i "$TAPPAS_DEB" || true
  # dpkg -i di atas hampir pasti melaporkan dependency problems di sistem
  # fresh -- itu normal, apt -f install di bawah yang resolve semuanya.
  apt-get -f install -y

  if [[ -n "$TAPPAS_SYSTEM_PY_DEB" ]]; then
    dpkg -i "$TAPPAS_SYSTEM_PY_DEB" || true
    apt-get -f install -y
  fi

  log_ok "TAPPAS Core terpasang."
else
  log_step "Step 4/7: Dilewati (--no-tappas)"
fi

# ---------------------------------------------------------------------------
# Step 4: Pastikan DKMS module cocok dengan kernel yang sedang aktif
# ---------------------------------------------------------------------------
log_step "Step 5/7: Verifikasi DKMS module vs kernel aktif"

# Logic DKMS/kernel-matching ada di lib/dkms_kernel_check.sh, dipakai bareng
# dengan fix_kernel_dkms.sh supaya tidak ada dua salinan logic yang beda.
if ensure_dkms_module_for_current_kernel "hailo_pci" "$HAILORT_VERSION"; then
  log_ok "hailo_pci ter-load untuk kernel aktif."
else
  log_warn "hailo_pci belum ter-load. Kalau ini instalasi PERTAMA KALI, REBOOT lalu jalankan:"
  log_warn "  sudo ./fix_kernel_dkms.sh"
  log_warn "untuk verifikasi tanpa perlu ulang seluruh instalasi ini."
fi

# ---------------------------------------------------------------------------
# Step 5: Install Python binding ke venv project
# ---------------------------------------------------------------------------
log_step "Step 6/7: Install Python binding ke venv"

VENV_PIP="$VENV_PATH/bin/pip"
VENV_PYTHON="$VENV_PATH/bin/python3"

if [[ ! -x "$VENV_PIP" ]]; then
  log_error "pip tidak ditemukan di $VENV_PATH/bin/pip -- pastikan --venv menunjuk ke venv yang valid."
  exit 1
fi

# Jalankan sebagai user asli (bukan root) supaya file venv tidak berubah
# ownership jadi root.
sudo -u "$REAL_USER" "$VENV_PIP" install "$HAILORT_WHL"

if [[ "$SKIP_TAPPAS" == false ]]; then
  sudo -u "$REAL_USER" "$VENV_PIP" install "$TAPPAS_WHL"
fi

log_info "Verifikasi import Python..."
if [[ "$SKIP_TAPPAS" == false ]]; then
  sudo -u "$REAL_USER" "$VENV_PYTHON" -c "import hailo; import hailo_platform; print('import hailo + hailo_platform: OK')"
else
  sudo -u "$REAL_USER" "$VENV_PYTHON" -c "import hailo; print('import hailo: OK')"
fi

log_ok "Python binding terpasang dan bisa di-import."

# ---------------------------------------------------------------------------
# Step 6: Ringkasan
# ---------------------------------------------------------------------------
log_step "Step 7/7: Selesai"

echo "Versi yang terpasang:"
dpkg -l | grep -E "^ii\s+(hailort|hailo-tappas-core)\b" || true
echo ""

if lsmod | grep -q hailo_pci; then
  log_ok "Semua langkah selesai. hailo_pci ter-load. Lanjut jalankan install.sh dari hailo-apps."
else
  log_warn "Semua langkah selesai TAPI hailo_pci belum ter-load di sesi ini."
  log_warn "Reboot sekarang, lalu cek dengan: lsmod | grep hailo && hailortcli fw-control identify"
fi
