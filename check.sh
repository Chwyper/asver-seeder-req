#!/bin/bash

echo "=========================================="
echo " Memulai Pemeriksaan Instalasi Hailo & Kamera"
echo "=========================================="
echo ""

# 1. Cek Paket DKMS & Hailo
echo "[*] Memeriksa paket terinstall..."
if dpkg -l | grep -q "hailo-all"; then
    echo " > hailo-all: TERINSTALL"
else
    echo " > hailo-all: TIDAK DITEMUKAN"
fi

if dpkg -l | grep -q "dkms"; then
    echo " > dkms: TERINSTALL"
else
    echo " > dkms: TIDAK DITEMUKAN"
fi

if dpkg -l | grep -q "rpicam-apps"; then
    echo " > rpicam-apps: TERINSTALL"
else
    echo " > rpicam-apps: TIDAK DITEMUKAN"
fi

echo ""

# 2. Cek Driver / Kernel Module Hailo
echo "[*] Memeriksa kernel module Hailo..."
if lsmod | grep -q "hailo"; then
    echo " > Driver kernel Hailo aktif (Loaded)."
else
    echo " > PERINGATAN: Driver kernel Hailo tidak aktif di memori."
fi

echo ""

# 3. Cek Komunikasi dengan Hardware Hailo
echo "[*] Memeriksa komunikasi dengan perangkat Hailo (hailortcli)..."
if command -v hailortcli &> /dev/null; then
    hailortcli fw-control identify
    if [ $? -eq 0 ]; then
        echo " > Sukses: Hailo device terdeteksi dan merespon!"
    else
        echo " > Gagal: hailortcli tidak dapat berkomunikasi dengan hardware."
    fi
else
    echo " > Perintah hailortcli tidak ditemukan."
fi

echo ""

# 4. Cek Kamera Raspberry Pi
echo "[*] Memeriksa rpicam-apps..."
if command -v rpicam-still &> /dev/null; then
    echo " > rpicam-still tersedia."
else
    echo " > rpicam-still tidak ditemukan."
fi

echo ""
echo "=========================================="
echo " Pemeriksaan Selesai."
echo "=========================================="