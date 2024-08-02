#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2023 Siemens AG
# Copyright 2020-2024 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
# SPDX-License-Identifier: GPL-3.0-only
#
# Author(s): Michael Messner, Pascal Eckmann

# Description:  Searches for password related files and tries to extract passwords and root accounts.

S45_pass_file_check()
{
  module_log_init "${FUNCNAME[0]}"
  module_title "Search password files"
  pre_module_reporter "${FUNCNAME[0]}"

  local PASSWD_STUFF=""
  local PASS_FILES_FOUND=0
  local SUDOERS_FILE_PATH=()
  local SUDOERS_FILE=""
  local WHO_HAS_BEEN_SUDO=""
  local LINE=""
  local PASSWD_STUFF=()

  mapfile -t PASSWD_STUFF < <(config_find "${CONFIG_DIR}""/pass_files.cfg")

  if [[ "${PASSWD_STUFF[0]-}" == "C_N_F" ]] ; then print_output "[!] Config not found"
  elif [[ "${#PASSWD_STUFF[@]}" -ne 0 ]] ; then
    # pull out vital sudoers info
    # This test is based on the source code from LinEnum: https://github.com/rebootuser/LinEnum/blob/master/LinEnum.sh
    local SUDOERS=""
    mapfile -t SUDOERS_FILE_PATH < <(mod_path "/ETC_PATHS/sudoers")

    for SUDOERS_FILE in "${SUDOERS_FILE_PATH[@]}" ; do
      if [[ -e "${SUDOERS_FILE}" ]] ; then
        # -v 选项表示反转匹配，即显示不匹配指定模式的行
        SUDOERS="${SUDOERS}""\\n""$(grep -v -e '^$' "${SUDOERS_FILE}" 2>/dev/null | grep -v "#" 2>/dev/null)"
      fi
    done
    # who has sudoed in the past
    # This test is based on the source code from LinEnum: https://github.com/rebootuser/LinEnum/blob/master/LinEnum.sh
    WHO_HAS_BEEN_SUDO=$(find "${FIRMWARE_PATH}" "${EXCL_FIND[@]}" -xdev -name .sudo_as_admin_successful 2>/dev/null)

    if [[ "${#PASSWD_STUFF[@]}" -gt 0 ]] || [[ -n "${SUDOERS}" ]] || [[ -n "${WHO_HAS_BEEN_SUDO}" ]] ; then
      print_output "[+] Found ""${#PASSWD_STUFF[@]}"" password related files:"
      for LINE in "${PASSWD_STUFF[@]}" ; do
        print_output "$(indent "$(print_path "${LINE}")")"
        if [[ -f "${LINE}" ]] && ! [[ -x "${LINE}" ]] ; then
          local POSSIBLE_PASSWD=""
          # regex source: https://serverfault.com/questions/972572/regex-for-etc-passwd-content
          # POSSIBLE_PASSWD=$(grep -hIE '^([^:]*:){6}[^:]*$' "${LINE}" | grep -v ":x:" | grep -v ":\*:" | grep -v ":!:" 2> /dev/null)
          POSSIBLE_PASSWD=$(grep -hIE '^[a-zA-Z0-9]+:.:[0-9]+:[0-9]+([^:]*:){3}[^:]*$' "${LINE}" | grep -v ":x:" | grep -v ":\*:" | grep -v ":!:" 2> /dev/null || true)

          local POSSIBLE_SHADOWS=""
          # POSSIBLE_SHADOWS=$(grep -hIE '^([^:]*:){8}[^:]*$' "${LINE}" | grep -v ":x:" | grep -v ":\*:" | grep -v ":!:" 2> /dev/null)
          POSSIBLE_SHADOWS=$(grep -hIE '^[a-zA-Z0-9]+:\$[0-9a-z]\$.*:[0-9]+:[0-9]+:[0-9]+([^:]*:){4}[^:]*' "${LINE}" | grep -v ":x:" | grep -v ":\*:" | grep -v ":!:" 2> /dev/null || true)

          local ROOT_ACCOUNTS=""
          # This test is based on the source code from LinEnum: https://github.com/rebootuser/LinEnum/blob/master/LinEnum.sh
          ROOT_ACCOUNTS=$(grep -v -E "^#" "${LINE}" 2>/dev/null| awk -F: '$3 == 0 { print $1}' 2> /dev/null || true)

          local L_BREAK=0
          if [[ "$(echo "${ROOT_ACCOUNTS}" | wc -w)" -gt 0 ]] ; then
            print_output "$(indent "$(green "Identified the following root accounts:")")"
            print_output "$(indent "$(indent "$(orange "${ROOT_ACCOUNTS}")")")"
            L_BREAK=1
          fi

          if [[ "$(echo "${POSSIBLE_SHADOWS}" | wc -w)" -gt 0 ]] || [[ "$(echo "${POSSIBLE_PASSWD}" | wc -w)" -gt 0 ]] ; then
            print_output "$(indent "$(green "Found passwords or weak configuration:")")"
            PASS_FILES_FOUND=1
            export PASS_FILES_FOUND
            if [[ "$(echo "${POSSIBLE_SHADOWS}" | wc -w)" -gt 0 ]] ; then
              print_output "$(indent "$(indent "$(orange "${POSSIBLE_SHADOWS}")")")"
            fi
            if [[ "$(echo "${POSSIBLE_PASSWD}" | wc -w)" -gt 0 ]] ; then
              print_output "$(indent "$(indent "$(orange "${POSSIBLE_PASSWD}")")")"
            fi
            L_BREAK=1
          fi
          if ! [[ ${L_BREAK} -eq 0 ]] ; then
            print_ln
          fi
        fi
      done
      if [[ -n "${SUDOERS}" ]] ; then
        print_output "[+] Sudoers configuration:"
        print_output "$(indent "$(orange "${SUDOERS}")")"
      fi
      if [[ -n "${WHO_HAS_BEEN_SUDO}" ]] ; then
        print_output "[+] Accounts that have recently used sudo:"
        print_output "$(indent "$(orange "${WHO_HAS_BEEN_SUDO}")")"
      fi
    fi
    write_log ""
    write_log "[*] Statistics:${PASS_FILES_FOUND}"
  else
    print_output "[-] No password files found"
  fi

  module_end_log "${FUNCNAME[0]}" "${#PASSWD_STUFF[@]}"
}

