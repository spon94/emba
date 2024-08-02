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

# Description:  Scrapes firmware for certification files and their end date.

S60_cert_file_check()
{
  module_log_init "${FUNCNAME[0]}"
  module_title "Search certificates"
  pre_module_reporter "${FUNCNAME[0]}"

  local CERT_FILES_ARR=()
  readarray -t CERT_FILES_ARR < <(config_find "${CONFIG_DIR}""/cert_files.cfg")

  local CERT_FILES_CNT=0
  local TOTAL_CERT_CNT=0
  local CERT_OUT_CNT=0
  local CURRENT_DATE=""
  local LINE=""
  local CERT_DATE=""
  local CERT_DATE_=""
  local CERT_NAME=""
  local CERT_LOG=""
  local NESTED_CERT_CNT=0
  local FUTURE_DATE=""
  local EXPIRE_WATCH_DATE="2 years"
  local SPECIFIC_CERT=""
  local CERT_WARNING_CNT=0
  local SIGNATURE=""

  if [[ "${CERT_FILES_ARR[0]-}" == "C_N_F" ]]; then print_output "[!] Config not found"
  elif [[ ${#CERT_FILES_ARR[@]} -ne 0 ]]; then
    write_csv_log "Certificate file" "Certificate expire on" "Certificate expired"
    print_output "[+] Found ""${ORANGE}${#CERT_FILES_ARR[@]}${GREEN}"" possible certification files:"
    print_ln
    CURRENT_DATE=$(date +%s)
    FUTURE_DATE=$(date --date="${EXPIRE_WATCH_DATE}" +%s)
    for LINE in "${CERT_FILES_ARR[@]}" ; do
      if [[ -f "${LINE}" && $(wc -l "${LINE}" | awk '{print $1}'|| true) -gt 1 ]]; then
        ((CERT_FILES_CNT+=1))
        if command -v openssl > /dev/null ; then
          CERT_NAME=$(basename "${LINE}")
          CERT_LOG="${LOG_PATH_MODULE}/cert_details_${CERT_NAME}.txt"
          write_log "[*] Cert file: ${LINE}\n" "${CERT_LOG}"
          # storeutl 是 OpenSSL 中的一个实用工具，用于操作证书存储
          # -noout 通常用于不需要输出证书内容而只需要其他信息的情况
          # -text 选项用于以文本格式输出证书信息
          # -certs 选项用于指定要处理的是证书文件
          timeout --preserve-status --signal SIGINT 10 openssl storeutl -noout -text -certs "${LINE}" 2>/dev/null >> "${CERT_LOG}" || true
          NESTED_CERT_CNT=$(tail -n 1 < "${CERT_LOG}" | grep -o '[0-9]\+')
          if ! [[ "${NESTED_CERT_CNT}" =~ ^[0-9]+$ ]]; then
            print_output "[-] Something went wrong for certificate ${LINE}" "no_log"
            continue
          fi
          TOTAL_CERT_CNT=$((TOTAL_CERT_CNT + NESTED_CERT_CNT))
          for ((i=1; i<=NESTED_CERT_CNT; i++)); do
            index=$((i - 1))
            # --iso-8601 是 GNU date 命令的一个选项，用于以 ISO 8601 格式输出日期和时间
            CERT_DATE=$(date --date="$(grep 'Not After :' "${CERT_LOG}" | awk -v cnt="${i}" 'NR==cnt {sub(/.*: /, ""); print}')" --iso-8601 || true)
            CERT_DATE_=$(date --date="$(grep 'Not After :' "${CERT_LOG}" | awk -v cnt="${i}" 'NR==cnt {sub(/.*: /, ""); print}')" +%s || true)
            SIGNATURE=$(sed -n '/Signature Value:/!b;n;p' "${CERT_LOG}" | sed -n "${i}p" | xargs)
            # head -n -1：输出文件的所有行，除了最后一行
            # -v idx="${index}"：将外部变量 ${index} 传递给 awk，并在 awk 中使用变量 idx
            # BEGIN 块：在处理任何输入行之前执行
            # found = 0：初始化变量 found 为 0，用于跟踪是否找到了目标证书
            # /^[0-9]+: Certificate$/ { ... }
              # 如果匹配到这样的行且 found 为真，表示找到了一个证书的结束标志，打印当前收集的证书信息并重置 cert 和 found
            SPECIFIC_CERT=$(head -n -1 < "${CERT_LOG}" | awk -v idx="${index}" '
            BEGIN { found = 0 }
            /^[0-9]+: Certificate$/ {
                if (found) {
                  print cert;
                  cert = "";
                  found = 0
                }
            }
            $1 == idx ":" && !found {
                found = 1
            }
            # 如果 found 为真，将当前行追加到 cert 变量中
            found {
                cert = cert $0 ORS
            }
            # END 块：在处理完所有输入行之后执行
            END {
                if (found) {
                    print cert
                }
            }' | tail -n+2)

            if [[ ${CERT_DATE_} -lt ${CURRENT_DATE} ]]; then
              print_output "  ${RED}${CERT_DATE} - $(print_path "${LINE}") ${SIGNATURE} ${NC}" "" "${SPECIFIC_CERT}"
              write_csv_log "${LINE}" "${CERT_DATE_}" "yes"
              ((CERT_OUT_CNT+=1))
            elif [[ ${CERT_DATE_} -le ${FUTURE_DATE} ]]; then
              print_output "  ${ORANGE}${CERT_DATE} - $(print_path "${LINE}") ${SIGNATURE} ${NC}" "" "${SPECIFIC_CERT}"
              write_csv_log "${LINE}" "${CERT_DATE_}" "expires within ${EXPIRE_WATCH_DATE}"
              ((CERT_WARNING_CNT+=1))
            else
              print_output "  ${GREEN}${CERT_DATE} - $(print_path "${LINE}") ${SIGNATURE} ${NC}" "" "${SPECIFIC_CERT}"
              write_csv_log "${LINE}" "${CERT_DATE_}" "no"
            fi
          done
        else
          print_output "$(indent "$(orange "$(print_path "${LINE}")")")"
          write_csv_log "${LINE}" "unknown" "unknown"
        fi
      fi
    done
    write_log ""
    write_log "[*] Statistics:${TOTAL_CERT_CNT}:${CERT_FILES_CNT}:${CERT_OUT_CNT}:${CERT_WARNING_CNT}"
  else
    print_output "[-] No certification files found"
  fi

  module_end_log "${FUNCNAME[0]}" "${TOTAL_CERT_CNT}"
}

