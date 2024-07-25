#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2024 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
# SPDX-License-Identifier: GPL-3.0-only
#
# Author(s): Michael Messner
# Contributor(s): Benedikt Kuehne

# Description: Identifies the main Linux distribution like Kali Linux, Debian, Fedora or OpenWRT

S06_distribution_identification()
{
  module_log_init "${FUNCNAME[0]}"
  module_title "System identification"
  pre_module_reporter "${FUNCNAME[0]}"

  export DLINK_FW_VER=""
  local OUTPUT=0
  local FILE_QUOTED
  local PATTERN=""
  local IDENTIFIER=""
  local OUT1=""
  local SED_COMMAND=""
  local FILE_QUOTED=""
  local CONFIG=""
  local FILE=""
  local SEARCH_FILE=""
  local FOUND_FILES=()
  export CSV_RULE=""

  write_csv_log "file" "type" "identifier" "csv_rule"

  while read -r CONFIG; do
    # [^#*/;]：表示一个字符类，匹配不包含 #、*、/ 和 ; 的任意字符
    if safe_echo "${CONFIG}" | grep -q "^[^#*/;]"; then
      SEARCH_FILE="$(safe_echo "${CONFIG}" | cut -d\; -f2)"
      # -xdev: find 只会在当前文件系统中查找，不会进入挂载在当前文件系统中的其他文件系统
      # -iwholename 选项用于忽略大小写地匹配文件的完整路径名
      mapfile -t FOUND_FILES < <(find "${FIRMWARE_PATH}" -xdev -iwholename "*${SEARCH_FILE}" || true)
      for FILE in "${FOUND_FILES[@]}"; do
        if [[ -f "${FILE}" ]]; then
          PATTERN="$(safe_echo "${CONFIG}" | cut -d\; -f3)"
          # do not use safe_echo for SED_COMMAND
          SED_COMMAND="$(echo "${CONFIG}" | cut -d\; -f4)"
          FILE_QUOTED=$(escape_echo "${FILE}")
          OUT1="$(eval "${PATTERN}" "${FILE_QUOTED}" || true)"
          # echo "PATTERN: $PATTERN"
          # echo "SED command: $SED_COMMAND"
          # echo "identified: $OUT1"
          # echo "FILE: $FILE_QUOTED"
          IDENTIFIER=$(echo "${OUT1}" | eval "${SED_COMMAND}" | sed 's/  \+/ /g' | sed 's/ $//' || true)

          if [[ $(basename "${FILE}") == "image_sign" ]]; then
            # dlink image_sign file handling
            dlink_image_sign
          fi

          if [[ "${IDENTIFIER}" != *[0-9]* ]] && [[ "${IDENTIFIER}" == *"supermicro:bmc"* ]]; then
              print_output "[+] Version information found ${ORANGE}${IDENTIFIER}${GREEN} in file ${ORANGE}$(print_path "${FILE}")${GREEN} with Linux distribution detection"
              get_csv_rule_distri "${IDENTIFIER}"
              write_csv_log "${FILE}" "Linux" "${IDENTIFIER}" "${CSV_RULE}"
          fi

          # check if not zero and not only spaces
          if [[ -n "${IDENTIFIER// }" ]] && [[ "${IDENTIFIER}" == *[0-9]* ]]; then
            if [[ -n "${DLINK_FW_VER}" ]]; then
              print_output "[+] Version information found ${ORANGE}${IDENTIFIER}${GREEN} in file ${ORANGE}$(print_path "${FILE}")${GREEN} for D-Link device."
              get_csv_rule_distri "${IDENTIFIER}"
              write_csv_log "${FILE}" "dlink" "${IDENTIFIER}" "${CSV_RULE}"
            else
              print_output "[+] Version information found ${ORANGE}${IDENTIFIER}${GREEN} in file ${ORANGE}$(print_path "${FILE}")${GREEN} with Linux distribution detection"
              get_csv_rule_distri "${IDENTIFIER}"
              write_csv_log "${FILE}" "Linux" "${IDENTIFIER}" "${CSV_RULE}"
            fi
            OUTPUT=1
          fi
        fi
      done
    fi
  done < "${CONFIG_DIR}"/distri_id.cfg

  write_log ""
  module_end_log "${FUNCNAME[0]}" "${OUTPUT}"
}

dlink_image_sign() {
  # the firmware version can be found in /config/buildver
  local DLINK_BUILDVER=()
  local DLINK_BREV=""
  local DLINK_BVER=""
  local DLINK_FW_VERx=""

  mapfile -t DLINK_BUILDVER < <(find "${FIRMWARE_PATH}" -xdev -path "*config/buildver")
  for DLINK_BVER in "${DLINK_BUILDVER[@]}"; do
    DLINK_FW_VER=$(grep -E "[0-9]+\.[0-9]+" "${DLINK_BVER}")
    if ! [[ "${DLINK_FW_VER}" =~ ^v.* ]]; then
      DLINK_FW_VER="v${DLINK_FW_VER}"
    fi
    # -> v2.14
  done

  local DLINK_BUILDREV=()
  # probably we can use this in the future. Currently there is no need for it:
  mapfile -t DLINK_BUILDREV < <(find "${FIRMWARE_PATH}" -xdev -path "*config/buildrev")
  for DLINK_BREV in "${DLINK_BUILDREV[@]}"; do
    DLINK_FW_VERx=$(grep -E "^[A-Z][0-9]+" "${DLINK_BREV}" || true)
    # -> B01
    DLINK_FW_VER="${DLINK_FW_VER}""${DLINK_FW_VERx}"
    # -> v2.14B01
    # if we have multiple files we only take the first one - this usually happens if we have some packed firmware
    break
  done

  if [[ -n "${DLINK_FW_VER}" ]]; then
    IDENTIFIER="D-Link ${IDENTIFIER}"" ${DLINK_FW_VER}"
    # -> D-Link dir-300 v2.14B01
  fi
}

get_csv_rule_distri() {
  # this is a temp solution. If this list grows we are going to solve it via a configuration file
  local VERSION_IDENTIFIER="${1:-}"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER,,}" | tr -dc '[:print:]')"

  ### handle versions of linux distributions:
  # debian 9 (stretch) - installer build 20170615+deb9u5
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/(debian) [0-9]+\ \([a-z]+\)\ -\ installer\ build\ [0-9]+\+deb([0-9]+)u([0-9])/\1:\1_linux:\2\.\3/')"
  # Fedora 17 (Beefy Miracle)
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/(fedora)\ ([0-9]+).*/\1project:\1:\2/')"
  # CentOS
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/centos\ linux\ ([0-9]+(\.[0-9]+)+?).*/centos:centos:\1/')"
  # Ubuntu
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/(ubuntu)\ ([0-9]+\,[0-9]+).*/\1_linux:\1:\2/')"
  # OpenWRT KAMIKAZE r18* -> 8.09.2
  # see also: https://openwrt.org/about/history
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/(openwrt)\ (kamikaze)\ r1[4-8][0-9][0-9][0-9].*/\1:\2:8.09/')"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/(openwrt)\ (backfire)\ r2[0-9][0-9][0-9][0-9].*/\1:\2:10.03/')"
  # OpenWrt 18.06.2 r7676-cddd7b4c77
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/(openwrt)\ ([0-9]+\.[0-9]+\.[0-9]+)\ (r[0-9]+\-[a-z0-9]+).*/openwrt:\2:\3/')"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/lede\ ([0-9]+\.[0-9]+\.[0-9]+)(-)?(rc[0-9])?.*/openwrt:\1:\3/')"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/openwrt\ ([0-9]+\.[0-9]+)/openwrt:\1/')"
  # OpenWrt Attitude Adjustment r7549 -> 12.09
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/openwrt\ attitude\ adjustment\ r([0-9]+).*/openwrt:12\.09/')"
  # d-link dir-300 v2.14b01
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/d-link\ (.*)\ v([0-9].[0-9]+[a-z][0-9]+)/dlink:\1_firmware:\2/')"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/d-link\ (.*)\ v([0-9].[0-9]+)/dlink:\1_firmware:\2/')"
  # dd-wrt v24-sp2
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/dd-wrt\ v([0-9]+)-?(sp[0-9])?.*/dd-wrt:dd-wrt:\1:\2/')"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/dd-wrt\ \#([0-9]+).*/dd-wrt:dd-wrt:\1/')"
  # iotgoat v1.0
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/iotgoat\ v([0-9]\.[0-9]+)/iotgoat:\1/')"
  # F5 BigIP
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/big-ip\ ltm\ ([0-9]+(\.[0-9]+)+?)/f5:big-ip_local_traffic_manager:\1/')"
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/big-ip\ asm\ ([0-9]+(\.[0-9]+)+?)/f5:big-ip_application_security_manager:\1/')"
  # Yocto linux - e.g.: poky:(yocto:project:reference:distro):2.2:(morty)
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/.*\(yocto:project:reference:distro\):([0-9]+(\.[0-9]+)+?):\(.*\)$/yoctoproject:yocto:\1/')"
  # Buildroot 2022.01.01
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/buildroot\ ([0-9]+(\.[0-9]+)+?)/buildroot:\1/')"
  #   MikroTik routerOS V2.4 (c) 1999-2001       http://mikrotik.com/
  VERSION_IDENTIFIER="$(safe_echo "${VERSION_IDENTIFIER}" | sed -r 's/.*mikrotik\ routeros\ v([0-9]\.[0-9]+).*/mikrotik:routeros:\1/')"
  VERSION_IDENTIFIER="${VERSION_IDENTIFIER// /:}"
  CSV_RULE="$(safe_echo "${VERSION_IDENTIFIER}" | tr -dc '[:print:]')"
}
