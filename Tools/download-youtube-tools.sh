#!/usr/bin/env bash
# Descarga herramientas fijadas para el bundle y verifica cada SHA-256 antes de extraer o compilar.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${ROOT_DIR}/Siyahamba/Resources/YouTubeTools.bundle"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

YT_DLP_VERSION="2026.07.04"
YT_DLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YT_DLP_VERSION}/yt-dlp_macos.zip"
YT_DLP_SHA256="b0724470a0cf6dae5175a87eee05d6e75c5a0c10d2c3015166bd4d34e92b1b7b"

FFMPEG_VERSION="9.0.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SHA256="cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635"
LAME_VERSION="3.100"
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

verify_sha256() {
    local archive="$1"
    local expected="$2"
    local actual
    actual="$(shasum -a 256 "${archive}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "Error: SHA-256 no coincide para ${archive}" >&2
        echo "Esperado: ${expected}" >&2
        echo "Actual:    ${actual}" >&2
        exit 1
    fi
}

download() {
    local url="$1"
    local expected_sha256="$2"
    local destination="$3"

    curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error \
        --output "${destination}" "${url}"
    verify_sha256 "${destination}" "${expected_sha256}"
}

extract_yt_dlp_bundle() {
    local archive="$1"
    local destination="$2"

    if ! grep -Fqx "yt-dlp_macos" < <(unzip -Z1 "${archive}") || ! grep -Fqx "_internal/Python" < <(unzip -Z1 "${archive}"); then
        echo "Error: ${archive} no contiene el bundle completo de yt-dlp" >&2
        exit 1
    fi
    rm -rf "${destination}"
    mkdir -p "${destination}"
    unzip -q "${archive}" -d "${destination}"
    chmod 755 "${destination}/yt-dlp_macos"
}

build_ffmpeg() {
    local arch="$1"
    local ffmpeg_source="${WORK_DIR}/ffmpeg-${FFMPEG_VERSION}-${arch}"
    local lame_source="${WORK_DIR}/lame-${LAME_VERSION}-${arch}"
    local prefix="${WORK_DIR}/prefix-${arch}"
    local target="${DESTINATION}/ffmpeg-${arch}"
    local configure_arch="${arch}"
    local host="${arch}-apple-darwin"
    local jobs
    if [[ "${arch}" == "arm64" ]]; then
        configure_arch="aarch64"
        host="aarch64-apple-darwin"
    fi
    jobs="$(sysctl -n hw.logicalcpu)"

    tar -xf "${WORK_DIR}/lame.tar.gz" -C "${WORK_DIR}"
    mv "${WORK_DIR}/lame-${LAME_VERSION}" "${lame_source}"
    (
        cd "${lame_source}"
        CC="clang -arch ${arch}" CFLAGS="-arch ${arch}" \
            ./configure --host="${host}" --prefix="${prefix}" --disable-shared --enable-static --disable-frontend
        make -j"${jobs}"
        make install
    )

    tar -xf "${WORK_DIR}/ffmpeg.tar.xz" -C "${WORK_DIR}"
    mv "${WORK_DIR}/ffmpeg-${FFMPEG_VERSION}" "${ffmpeg_source}"
    (
        cd "${ffmpeg_source}"
        ./configure \
            --prefix="${prefix}" \
            --arch="${configure_arch}" \
            --target-os=darwin \
            --cc="clang -arch ${arch}" \
            --extra-cflags="-arch ${arch} -I${prefix}/include" \
            --extra-ldflags="-arch ${arch} -L${prefix}/lib" \
            --enable-cross-compile \
            --disable-x86asm \
            --disable-doc \
            --disable-debug \
            --disable-shared \
            --enable-static \
            --disable-gpl \
            --disable-nonfree \
            --enable-version3 \
            --enable-libmp3lame \
            --enable-ffmpeg \
            --disable-ffplay \
            --disable-ffprobe
        make -j"${jobs}"
        install -m 755 ffmpeg "${target}"
    )
}

mkdir -p "${DESTINATION}"
rm -rf "${DESTINATION}/yt-dlp"
rm -f "${DESTINATION}/ffmpeg-arm64" "${DESTINATION}/ffmpeg-x86_64"

download "${YT_DLP_URL}" "${YT_DLP_SHA256}" "${WORK_DIR}/yt-dlp_macos.zip"
extract_yt_dlp_bundle "${WORK_DIR}/yt-dlp_macos.zip" "${DESTINATION}/yt-dlp"

download "${LAME_URL}" "${LAME_SHA256}" "${WORK_DIR}/lame.tar.gz"
download "${FFMPEG_URL}" "${FFMPEG_SHA256}" "${WORK_DIR}/ffmpeg.tar.xz"
build_ffmpeg arm64
build_ffmpeg x86_64

echo "Herramientas verificadas en ${DESTINATION}"
