#!/usr/bin/env bash

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# GLOBAL

CERTA_LIB=${BASH_SOURCE[0]}

CWD=$(cd $(dirname "${CERTA_LIB}") && pwd)

# SOURCE «certa» CONFIGURATION
source "${CWD}/../etc/configuration.sh"


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# UTILITY

# CERTA USAGE
function help()
{
    local EOF
    cat << EOF
certa-help
   certa USAGE.

certa-setup
   INSTALL «certa» ACCORDING TO VALUES IN configuration.sh.
   OPTIONS:
      NONE

certa-teardown
   UNINSTALL «certa».
   REMOVE ALL PATHS CREATED BY «certa» DURING AND AFTER INSTALL.
   OPTIONS:
      NONE

certa-issue
   CREATE SUBORDINATE KEY-PAIR SPECIFIED BY ARGUMENTS.
   ARGUMENTS:
      REQUIRES MINIMUM OF ONE ARGUMENT.
      USED FOR "subjectAltName".
   OPTIONS:
      -n, --name)
      TAKES ARGUMENT TO SPECIFY NAME FOR SUBORDINATE KEY-PAIR.
      OPTIONAL.
   IF "--name" OPTION IS NOT GIVEN, THE FIRST SUBJECT ALTERNATIVE NAME
   IS USED FOR THE SUBORDINATE NAME.

certa-show
   SHOW SUBORDINATE CERTIFICATES ISSUED BY «certa».
   INCLUDES STATUS DETAILS.
   OPTIONS:
      NONE

certa-revoke
   REVOKE SUBORDINATE CERTIFICATE.
   ARGUMENTS:
      TAKES EXACTLY ONE ARGUMENT FOR SUBORDINATE NAME.
   OPTIONS:
      NONE

certa-remove
   REVOKE AND REMOVE SUBORDINATE KEY-PAIR.
   ARGUMENTS:
      TAKES EXACTLY ONE ARGUMENT FOR SUBORDINATE NAME.
   OPTIONS:
      NONE

NOTE:
   SUBORDINATE NAMES ARE UNIQUE.
EOF
    # EXIT
    exit
}


# ERROR MESSAGE
function err()
{
    echo -e " \033[1;31m●\033[0m $*" 1>&2
}


# OK MESSAGE
function ok()
{
    echo -e " \033[1;36m●\033[0m $*"
}


# MESSAGE
function msg()
{
    local MSG="$*"
    if (( ${#MSG[*]} == 0 )); then
        MSG="   "
    fi
    echo -en " ● ${MSG}"
}


# EXIT UPON ERROR
function x()
{
    local CODE=${1:?}
    if (( CODE != 0 )); then
        err "EXITING…  STATUS CODE: ${CODE}  ${CERTA_LIB##*/} LINE: ${2:?}"
        exit ${CODE}
    fi
}


function check_user()
{
    (( EUID == 0 )) && return
    err "USER PRIVILEGE REQUIRED."
    exit 1
}


# CHECK USAGE
function check_usage()
{
    while true; do
        [[ -z "${1}" ]] && break
        # `help` FOR ANY OPTION
        if [[
            "${1}" =~ [[:space:]]\-+[a-z] ||\
            "${1}" =~ [Hh][Ee][Ll][Pp]
        ]]; then
            help
        fi
        shift
    done
}


# ESTABLISH GLOBAL PATH VARIABLES
function setvars()
{
    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
    # «certa» PATHS

    # CERTA HOME
    CERTA_HOME="${CERTA_INSTALL_DIR:-/opt}/certa"

    # BIN DIRECTORY, CERTA EXECUTABLES
    BIN_DIR="${CERTA_HOME}/bin"

    # CA DIRECTORY
    CA_DIR="${CERTA_HOME}/ca"

    # DOC DIRECTORY
    DOC_DIR="${CERTA_HOME}/doc"

    # ETC DIRECTORY
    ETC_DIR="${CERTA_HOME}/etc"

    # LIB DIRECTORY
    LIB_DIR="${CERTA_HOME}/lib"

    # TEST DIRECTORY
    TEST_DIR="${CERTA_HOME}/test"

    # SUBORDINATE DIRECTORY
    SUB_DIR="${CERTA_HOME}/sub"

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
    # «certa» ROOT CA PATHS

    # ROOT CONFIGURATION FILE
    ROOT_CONFIG="${ETC_DIR}/certa-root.conf"

    # ROOT CERTIFICATE DIRECTORY
    ROOT_CERT_DIR="${CA_DIR}/cert"

    # ROOT NEW CERTIFICATE DIRECTORY
    ROOT_NEWCERT_DIR="${CA_DIR}/new"

    # ROOT CERTIFICATE REVOCATION LIST DIRECTORY
    ROOT_CRL_DIR="${CA_DIR}/crl"

    # ROOT PRIVATE DIRECTORY
    ROOT_PRIV_DIR="${CA_DIR}/priv"

    # ROOT TEMPORARY DIRECTORY
    ROOT_TMP_DIR="${CA_DIR}/tmp"
}


function ssl()
{
    local SSL

    # OpenSSl EXECUTABLE
    if ! SSL=$(command -v openssl); then
        err "ERROR. CANNOT FIND openssl COMMAND."
        exit 1
    fi

    ${SSL} "$@"
}


function statdir()
{
    [[ -d ${1:?} ]] && echo -n ${1}
}


# IDENTIFY DIRECTORY WHERE LOCAL CERTS MAY BE ADDED
function get_pki_dir()
{
    if statdir "/usr/share/pki/ca-trust-source/anchors"; then
        # FEDORA, RHEL
        return
    elif statdir "/usr/local/share/ca-certificates"; then
        # DEBIAN, UBUNTU
        return
    else
        # PKI DIRECTORY NOT IDENTIFIED
        x 1 ${LINENO}
    fi
}


# IDENTIFY, CALL APPROPRIATE TOOL FOR MANAGING LOCAL CERTS
function update_pki()
{
    local CMD

    if CMD=$(command -v update-ca-trust); then
        # FEDORA, RHEL
        ${CMD}
    elif CMD=$(command -v update-ca-certificates); then
        # DEBIAN, UBUNTU
        ${CMD} "$@"
    else
        # COMMAND NOT IDENTIFIED
        x 1 ${LINENO}
    fi
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# CONFIGURATION

# «certa» ROOT CONFIGURATION
function write_root_conf()
{
    local EOF
    set -eu
    cat << EOF > ${ROOT_CONFIG}
[ CA_default ]
certificate   = ${ROOT_CERT_DIR}/certa-root.crt.pem
private_key   = ${ROOT_PRIV_DIR}/certa-root.key.pem
new_certs_dir = ${ROOT_NEWCERT_DIR}

crl_dir   = ${ROOT_CRL_DIR}
crl       = ${ROOT_CRL_DIR}/certa-root.crl.pem
crlnumber = ${ROOT_CRL_DIR}/crlnumber
database  = ${ROOT_CRL_DIR}/index
serial    = ${ROOT_CRL_DIR}/serial

#default_md      = sha256
#policy          = policy_de_rigueur

name_opt        = ca_default
cert_opt        = ca_default
default_md      = sha256
unique_subject  = no
policy          = policy_de_rigueur


[ req_distinguished_name ]
organizationName = certa
commonName       = ${COMMON_NAME}


[ ca ]
default_ca = CA_default


[ policy_de_rigueur ]
countryName         = optional
stateOrProvinceName = optional
organizationName    = supplied


[ req ]
distinguished_name = req_distinguished_name
x509_extensions    = v3_ca
string_mask        = utf8only
prompt             = no


[ v3_ca ]
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid:always, issuer
basicConstraints       = critical, CA:true, pathlen:0
keyUsage               = critical, digitalSignature, cRLSign, keyCertSign


EOF
    chmod go+r ${ROOT_CONFIG}
    ok "WROTE «certa» ROOT CONFIGURATION: ${ROOT_CONFIG}"
    set +eu
}


# SUBORDINATE CONFIGURATION
function write_sub_conf()
{
    local CONFIG EOF i n
    local -a SUBNAMES

    SUBNAMES=("$@")
    CONFIG="${ETC_DIR:?}/${SUBNAMES[0]}.conf"

    cat << EOF > ${CONFIG}
[ req ]
distinguished_name = req_distinguished_name
x509_extensions    = v3_ext
string_mask        = utf8only
default_md         = sha256
prompt             = no


[ req_distinguished_name ]
organizationName = certa


[ v3_ext ]
subjectAltName   = @alt_names
basicConstraints = CA:FALSE
keyUsage         = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth


[ alt_names ]
EOF
    # APPEND SUBJECT ALTERNATIVE NAMES
    i=1
    for n in "${SUBNAMES[@]}"; do
        echo "DNS.${i} = ${n}" >> ${CONFIG}
        ((i++))
    done
    chmod go+r ${CONFIG}
    ok "WROTE SUBORDINATE CONFIGURATION: ${CONFIG}"
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# SETUP

function mkdirs()
{
    local i
    local -a DIRS
    set -eu

    # «certa» DIRECTORIES
    DIRS+=(
        ${CERTA_HOME}
        ${BIN_DIR}
        ${CA_DIR}
        ${DOC_DIR}
        ${ETC_DIR}
        ${LIB_DIR}
        ${SUB_DIR}
        ${TEST_DIR}
    )
    # «certa» ROOT CA DIRECTORIES
    DIRS+=(
        ${ROOT_CERT_DIR}
        ${ROOT_CRL_DIR}
        ${ROOT_NEWCERT_DIR}
        ${ROOT_PRIV_DIR}
        ${ROOT_TMP_DIR}
    )
    # CREATE DIRECTORIES
    for i in "${DIRS[@]}"; do
        mkdir --parents --verbose ${i}
    done
    # ALLOW DIRECTORY ACCESS
    chmod              \
        755            \
        ${CERTA_HOME}  \
        ${BIN_DIR}     \
        ${DOC_DIR}     \
        ${ETC_DIR}     \
        ${LIB_DIR}     \
        ${SUB_DIR}     \
        ${TEST_DIR}
    set +eu
}


# INSTALL «certa»
function install_self()
{
    local BIN ETC README TEST
    set -eu

    # EXECUTABLES
    BIN="${CWD}/../bin"
    install         \
        --verbose   \
        --mode=754  \
        ${BIN}/certa-* ${BIN_DIR}
    x $? ${LINENO}
    chmod                       \
        o+x                     \
        "${BIN_DIR}/certa-help"
    x $? ${LINENO}

    # LIBRARY
    install         \
        --verbose   \
        --mode=644  \
        ${CERTA_LIB} ${LIB_DIR}
    x $? ${LINENO}

    # CONFIGURATION
    ETC="${CWD}/../etc"
    install         \
        --verbose   \
        --mode=644  \
        ${ETC}/* ${ETC_DIR}
    x $? ${LINENO}

    # DOCUMENTATION
    README="${CWD}/../README.md"
    install         \
        --verbose   \
        --mode=644  \
        ${README} ${DOC_DIR}
    x $? ${LINENO}

    # TEST
    TEST="${CWD}/../test"
    install         \
        --verbose   \
        --mode=754  \
        ${TEST}/[a-z]* ${TEST_DIR}
    x $? ${LINENO}

    set +eu
    # DONE
    ok "INSTALLED «certa»: ${CERTA_HOME}"
}


# GET «certa» ROOT TEMPORARY FILE PATH
function get_tmp()
{
    local PAT='.*\.tmp\.[0-9A-Za-z]\{10\}$'
    find                   \
        ${ROOT_TMP_DIR:?}  \
        -mindepth 1        \
        -type f            \
        -not -empty        \
        -regextype grep    \
        -regex ${PAT}      \
        -print             \
        -quit
}


# CREATE TEMPORARY FILE
function mk_root_tmp()
{
    local TMP
    TMP=$(mktemp --tmpdir="${ROOT_TMP_DIR:?}" ".tmp.XXXXXXXXXX")
    ssl rand -base64 32 >${TMP}
}


# CREATE «certa» ROOT CA PATHS
function mk_root_paths()
{
    # CREATE DATA FILES
    [[ -f "${ROOT_CRL_DIR:?}/index" ]] ||\
        cp /dev/null "${ROOT_CRL_DIR:?}/index"
    [[ -f "${ROOT_CRL_DIR}/index.attr" ]] ||\
        cp /dev/null "${ROOT_CRL_DIR}/index.attr"

    # WRITE CONFIGURATION FILE
    [[ -s "${ROOT_CONFIG:?}" ]] || write_root_conf

    # INTIALIZE CRLNUMBER FILE
    [[ -s "${ROOT_CRL_DIR:?}/crlnumber" ]] ||\
        echo "00" >"${ROOT_CRL_DIR:?}/crlnumber"

    # INTIALIZE SERIAL FILE
    [[ -s "${ROOT_CRL_DIR:?}/serial" ]] ||\
        ssl rand -hex 16 >"${ROOT_CRL_DIR:?}/serial"

    # CREATE ROOT TEMPORARY FILE
    [[ -z "$(get_tmp)" ]] && mk_root_tmp

    # CREATE RANDOM FILE
    [[ -f "${ROOT_TMP_DIR:?}/.rand" ]] ||\
        cp /dev/null "${ROOT_TMP_DIR:?}/.rand"
}


# CREATE SUBORDINATE PATHS
function mk_sub_paths()
{
    local SUB DIR

    SUB=${1:?}

    if [[ ! -d "${SUB_DIR:?}" ]]; then
        err "NO SUCH DIRECTORY: ${SUB_DIR} — SEE: certa-help"
        exit 1
    fi

    # SUBORDINATE DIRECTORY PATH
    DIR="${SUB_DIR:?}/${SUB}"
    if [[ -e "${DIR}" ]]; then
        err "SUBORDINATE DIRECTORY ALREADY EXISTS: ${DIR}"
        exit 1
    fi

    mkdir ${DIR}

    # PASSWORD FILE
    ssl rand -base64 32 >"${DIR}/${SUB}.pass"
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# MANAGE KEY-PAIRS

# CREATE «certa» ROOT KEY
function mk_root_key()
{
    local TMP BITS KEY

    TMP=$(get_tmp)
    [[ -z "${TMP}" ]] && x 1 ${LINENO}
    KEY="${ROOT_PRIV_DIR:?}/certa-root.key.pem"
    [[ -f "${KEY}" ]] && x 1 ${LINENO}
    [[ -n "${KEY_BITS}" ]]  &&\
        BITS="-pkeyopt rsa_keygen_bits:${KEY_BITS}"

    ssl                    \
        genpkey            \
        -algorithm RSA     \
        -pass file:${TMP}  \
        ${BITS}            \
        -out ${KEY}        \
        &>/dev/null
    x $? ${LINENO}
    ok "CREATED ROOT KEY: ${KEY}"
}


# VALIDATE «certa» ROOT KEY
function validate_root_key()
{
    local TMP KEY

    TMP=$(get_tmp)
    [[ -z "${TMP}" ]] && x 1 ${LINENO}
    KEY="${ROOT_PRIV_DIR:?}/certa-root.key.pem"

    msg
    ssl                      \
        rsa                  \
        -check               \
        -noout               \
        -passin file:${TMP}  \
        -in ${KEY}
    x $? ${LINENO}
    ok "«certa» ROOT KEY VALIDATED."
}


# CREATE «certa» ROOT CA CERTIFICATE
function mk_root_cert()
{
    local TMP KEY RAND CERT

    TMP=$(get_tmp)
    [[ -z "${TMP}" ]] && x 1 ${LINENO}
    KEY="${ROOT_PRIV_DIR:?}/certa-root.key.pem"
    RAND="${ROOT_TMP_DIR:?}/.rand"
    CERT="${ROOT_CERT_DIR:?}/certa-root.crt.pem"
    [[ -f "${CERT}" ]] && x 1 ${LINENO}

    msg
    ssl                           \
        req                       \
        -new                      \
        -verbose                  \
        -x509                     \
        -config ${ROOT_CONFIG:?}  \
        -days 3650                \
        -passin file:${TMP}       \
        -rand ${RAND}             \
        -key ${KEY}               \
        -out ${CERT}
    x $? ${LINENO}
    ok "CREATED «certa» ROOT CERTIFICATE: ${CERT}"
}


# VALIDATE «certa» ROOT CA CERTIFICATE
function validate_root_cert()
{
    local CERT

    CERT="${ROOT_CERT_DIR}/certa-root.crt.pem"

    ssl x509 -noout -in ${CERT}
    x $? ${LINENO}
    ok "«certa» ROOT CERT VALIDATED."
}


# CREATE «certa» ROOT CERTIFICATE REVOCATION LIST
function mk_root_crl()
{
    local TMP CRL

    TMP=$(get_tmp)
    [[ -z "${TMP}" ]] && x 1 ${LINENO}
    CRL="${ROOT_CRL_DIR:?}/certa-root.crl.pem"

    msg "CREATING «certa» ROOT CRL …\n   "
    ssl                           \
        ca                        \
        -gencrl                   \
        -verbose                  \
        -config ${ROOT_CONFIG:?}  \
        -crldays ${DURATION:?}    \
        -passin file:${TMP}       \
        -out ${CRL}
    x $? ${LINENO}
    ok "CREATED «certa» ROOT CRL: ${CRL}"
}


# VALIDATE «certa» ROOT CERTIFICATE REVOCATION LIST
function validate_root_crl()
{
    local CRL

    CRL="${ROOT_CRL_DIR:?}/certa-root.crl.pem"

    ssl crl -noout -in ${CRL}
    x $? ${LINENO}
    ok "«certa» ROOT CRL VALIDATED."
}


function remove_local_certa()
{
    msg "REMOVING «certa» ROOT CA FROM LOCAL CERTIFICATE BUNDLE …\n"
    rm --verbose "$(get_pki_dir)/certa.crt" || return
    update_pki --fresh --verbose >/dev/null || return
    ok "UPDATED SYSTEM CERTIFICATES."
}


# ADD «certa» ROOT CA TO LOCAL CERTIFICATE BUNDLE
function add_local_certa()
{
    local ROOT_CERT LOCAL_CERT

    ROOT_CERT="${ROOT_CERT_DIR:?}/certa-root.crt.pem"
    LOCAL_CERT="$(get_pki_dir)/certa.crt"

    msg "COPYING «certa» ROOT CA …\n   "
    cp --verbose ${ROOT_CERT} ${LOCAL_CERT}
    x $? ${LINENO}
    chmod go+r ${LOCAL_CERT}

    update_pki --verbose >/dev/null
    x $? ${LINENO}

    ok "UPDATED SYSTEM CERTIFICATES."
}


function get_cert_status()
{
    # Appendix B: CA Database
    #   https://pki-tutorial.readthedocs.io/en/latest/cadb.html
    local SERIAL PAT INDEX STATUS

    SERIAL=${1:?}
    PAT='^[A-Z](?=\s+[0-9A-Z]+\s+'"${SERIAL})"
    INDEX="${ROOT_CRL_DIR:?}/index"
    grep --quiet "${SERIAL}" "${INDEX}" &&\
        STATUS=$(grep --perl-regexp --only-matching "${PAT}" "${INDEX}")

    case ${STATUS} in
        "V") echo -n "valid";;
        "R") echo -n "revoked";;
        "E") echo -n "expired";;
        *) echo -n "unknown";;
    esac
}


function x509_info()
{
    local CERT=${1:?}

    ssl                 \
        x509            \
        -noout          \
        -serial         \
        -issuer         \
        -subject        \
        -dates          \
        -in "${CERT}"  |\
    sed 's/^[A-Za-z]\+=//g'
}


function show_crl_info()
{
    local CERT ISSUER
    local IFS EOF INFO i
    local SERIAL STATUS SUBJECT SUBNAME
    local -a OUTPUT

    CERT=${1:?}
    IFS=$'\n'
    i=0
    for INFO in $(x509_info "${CERT}"); do
        OUTPUT[${i}]="${INFO}"
        ((i++))
    done

    SUBNAME=$(basename "${CERT%/*}")
    SERIAL=${OUTPUT[0]}
    STATUS=$(get_cert_status "${SERIAL}")
    ISSUER="${OUTPUT[1]//\ =\ /=}"
    SUBJECT="${OUTPUT[2]//\ =\ /=}"

    cat << EOF
● ${SUBNAME}
  PATH:     ${CERT}
  STATUS:   ${STATUS}
  SERIAL:   ${SERIAL}
  ISSUER:   ${ISSUER}
  SUBJECT:  ${SUBJECT}
  BEGIN:    ${OUTPUT[3]}
  END:      ${OUTPUT[4]}

EOF
}


# REVOKE SUBORDINATE CERTIFICATE USING «certa» ROOT CRL
function revoke_sub_cert()
{
    local SUB CERT

    SUB=${1:?}
    CERT="${SUB_DIR:?}/${SUB}/${SUB}.crt.pem"
    if [[ ! -e "${CERT}" ]]; then
        err "SUBORDINATE CERTIFICATE NOT FOUND: ${CERT}"
        return 1
    fi

    ssl                         \
        ca                      \
        -updatedb               \
        -verbose                \
        -config ${ROOT_CONFIG}  \
        -revoke ${CERT}
    x $? ${LINENO}
    ok "REVOKED CERTIFICATE: ${CERT}"
}


# CREATE SUBORDINATE KEY
function mk_sub_key()
{
    local SUB KEY PASS BITS

    SUB=${1:?}
    KEY="${SUB_DIR:?}/${SUB}/${SUB}.key.pem"
    PASS="${SUB_DIR}/${SUB}/${SUB}.pass"
    if [[ -n "${KEY_BITS}" ]]; then
        BITS="-pkeyopt rsa_keygen_bits:${KEY_BITS}"
    fi

    ssl                     \
        genpkey             \
        -algorithm RSA      \
        -pass file:${PASS}  \
        ${BITS}             \
        -out ${KEY}         \
        &>/dev/null
    x $? ${LINENO}
    ok "CREATED SUBORDINATE KEY: ${KEY}"
}


# VALIDATE SUBORDINATE KEY
function validate_sub_key()
{
    local SUB KEY PASS

    SUB=${1:?}
    KEY="${SUB_DIR:?}/${SUB}/${SUB}.key.pem"
    PASS="${SUB_DIR}/${SUB}/${SUB}.pass"

    ssl                       \
        rsa                   \
        -check                \
        -noout                \
        -passin file:${PASS}  \
        -in ${KEY}            \
        >/dev/null
    x $? ${LINENO}
    ok "SUBORDINATE KEY VALIDATED."
}


# CREATE SUBORDINATE CERTIFICATE SINGING REQUEST
function mk_sub_csr()
{
    local SUB CSR KEY SUBCONF PASS

    SUB=${1:?}
    CSR="${SUB_DIR:?}/${SUB}/${SUB}.csr.pem"
    KEY="${SUB_DIR}/${SUB}/${SUB}.key.pem"
    SUBCONF="${ETC_DIR:?}/${SUB}.conf"
    PASS="${SUB_DIR}/${SUB}/${SUB}.pass"

    msg
    ssl                       \
        req                   \
        -new                  \
        -verbose              \
        -config ${SUBCONF}    \
        -passin file:${PASS}  \
        -key ${KEY}           \
        -out ${CSR}
    x $? ${LINENO}
    ok "CREATED SUBORDINATE CSR: ${CSR}"
}


# VALIDATE SUBORDINATE CERTIFICATE SIGNING REQUEST
function validate_sub_csr()
{
    local SUB CSR

    SUB=${1:?}
    CSR="${SUB_DIR:?}/${SUB}/${SUB}.csr.pem"

    msg "VALIDATING SUBORDINATE CSR …\n   "
    ssl req -verify -in ${CSR}
    x $? ${LINENO}
    ok "SUBORDINATE CSR VALIDATED."
}


# CREATE SIGNED SUBORDINATE CERTIFICATE
function mk_sub_cert()
{
    local SUB CSR CERT SUBCONF TMP

    SUB=${1:?}
    CSR="${SUB_DIR:?}/${SUB}/${SUB}.csr.pem"
    CERT="${SUB_DIR}/${SUB}/${SUB}.crt.pem"
    SUBCONF="${ETC_DIR:?}/${SUB}.conf"
    TMP=$(get_tmp)
    [[ -z "${TMP}" ]] && x 1 ${LINENO}

    msg "CREATING SIGNED SUBORDINATE CERTIFICATE …\n   "
    ssl                           \
        ca                        \
        -batch                    \
        -create_serial            \
        -notext                   \
        -verbose                  \
        -config ${ROOT_CONFIG:?}  \
        -extfile ${SUBCONF}       \
        -extensions v3_ext        \
        -days ${DURATION:?}       \
        -passin file:${TMP}       \
        -in ${CSR}                \
        -out ${CERT}
    x $? ${LINENO}
    ok "CREATED SUBORDINATE CERTIFICATE: ${CERT}"
}


# VALIDATE SUBORDINATE CERTIFICATE
function validate_sub_cert()
{
    local SUB CERT

    SUB=${1:?}
    CERT="${SUB_DIR:?}/${SUB}/${SUB}.crt.pem"

    ssl x509 -noout -in ${CERT}
    x $? ${LINENO}
    ok "SUBORDINATE CERTIFICATE VALIDATED."
}


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
# CERTA ROUTINES

function teardown()
{
    # PRELIMINARY
    check_user
    umask 0077
    check_usage "$@"
    setvars
    msg "UNINSTALLING «certa» …\n"

    # REMOVE «certa» ROOT CA FROM LOCAL CERTS
    remove_local_certa

    set -eu
    # REMOVE INSTALL PATHS
    rm               \
        --force      \
        --recursive  \
        ${CA_DIR}    \
        ${DOC_DIR}   \
        ${ETC_DIR}   \
        ${LIB_DIR}   \
        ${SUB_DIR}   \
        ${TEST_DIR}  \
        ${BIN_DIR}
    rm               \
        --force      \
        --recursive  \
        --verbose    \
        ${CERTA_HOME}

    # DONE
    ok "«certa» TEARDOWN COMPLETE."
}


function setup()
{
    # PRELIMINARY
    check_user
    umask 0077
    check_usage "$@"
    setvars
    msg "INSTALLING «certa» VERSION: ${CERTA_VERSION:?}…\n"

    # OpenSSl COMMAND
    ssl version

    # PATHS
    mkdirs
    mk_root_paths
    install_self

    # CREATE «certa» ROOT CA
    mk_root_key
    validate_root_key
    mk_root_cert
    validate_root_cert
    mk_root_crl
    validate_root_crl

    # ADD «certa» ROOT CA TO LOCAL CERTS
    add_local_certa

    # DONE
    ok "«certa» SETUP COMPLETE."
}


function show()
{
    local FOUND i

    # PRELIMINARY
    check_user
    umask 0077
    check_usage "$@"
    setvars

    FOUND=false
    for i in $(
        find                   \
            ${SUB_DIR:?}       \
            -mindepth 1        \
            -type f            \
            -name "*.crt.pem"  \
            2>/dev/null
    ); do
        show_crl_info ${i}
        FOUND=true
    done

    # DONE
    if ! ${FOUND}; then
        err "NO SUBORDINATE KEY-PAIRS FOUND."
    fi
}


function revoke_certificate()
{
    # PRELIMINARY
    check_user
    umask 0077
    check_usage "$@"
    setvars

    # SUBORDINATE NAME
    SUB=${1:?}
    if [[ -z "${SUB}" ]]; then
        err "SUBORDINATE NAME REQUIRED"
        exit 1
    fi
    msg "REVOKING SUBORDINATE CERTIFICATE FOR «${SUB}» …\n"

    # REVOKE SUBORDINATE CERTIFICATE
    revoke_sub_cert ${SUB}
}


function remove_certificate()
{
    # PRELIMINARY
    check_user
    umask 0077
    check_usage "$@"
    setvars

    # SUBORDINATE NAME
    SUB=${1:?}
    if [[ -z "${SUB}" ]]; then
        err "SUBORDINATE NAME REQUIRED"
        exit 1
    fi
    msg "REMOVING SUBORDINATE KEY-PAIR FOR «${SUB}» …\n"

    # REVOKE SUBORDINATE CERTIFICATE
    revoke_sub_cert ${SUB}

    # REMOVE SUBORDINATE DIRECTORY PATH
    [[ -n "${SUB_DIR}" && -d "${SUB_DIR}/${SUB}" ]] || exit 1
    rm --force --recursive --verbose "${SUB_DIR}/${SUB}"

    # DONE
    ok "SUBORDINATE KEY-PAIR REMOVED: ${SUB_DIR}/${SUB}"
}


function issue_certificate()
{
    local MSG i 
    local -a SUBNAMES ALTNAMES

    # PRELIMINARY
    check_user
    umask 0077
    setvars

    # HANDLE ARGUMENTS
    while true; do
        [[ -z "${1}" ]] && break
        if [[ "${1}" =~ \-+n ]]; then
            # SUBORDINATE NAME OPTION
            shift
            if [[ -z "${1}" ]]; then
                err "ARGUMENT REQUIRED FOR NAME OPTION"
                exit 1
            else
                SUBNAMES+=("${1}")
            fi
        elif [[
            "${1}" =~ [[:space:]]\-+[a-z] ||\
            "${1}" =~ [Hh][Ee][Ll][Pp]
        ]]; then
            # HELP
            err "USAGE:"
            help
        else
            # APPEND SUBJECT ALTERNATIVE NAMES
            ALTNAMES+=("${1}")
        fi
        shift
    done

    SUBNAMES+=("${ALTNAMES[@]}")
    if (( "${#SUBNAMES[*]}" == 0 )); then
        err "ARGUMENTS REQUIRED FOR SUBJECT ALTERNATIVE NAMES."
        exit 1
    fi

    # PATHS
    mk_sub_paths ${SUBNAMES[0]}

    # WRITE CONFIGURATION FILE
    write_sub_conf "${SUBNAMES[@]}"

    # CREATE SUBORDINATE KEY-PAIR
    MSG="CREATING SUBORDINATE KEY-PAIR FOR «${SUBNAMES[0]}» …\n"
    MSG+="   USING DNS NAMES:\n"
    for i in "${SUBNAMES[@]}"; do
        MSG+="\tDNS: \033[1m${i}\033[0m\n"
    done
    msg "${MSG}"

    mk_sub_key ${SUBNAMES[0]}
    validate_sub_key ${SUBNAMES[0]}
    mk_sub_csr ${SUBNAMES[0]}
    validate_sub_csr ${SUBNAMES[0]}
    mk_sub_cert ${SUBNAMES[0]}
    validate_sub_cert ${SUBNAMES[0]}

    # DONE
    ok "SUBORDINATE KEY-PAIR CREATED: ${SUB_DIR:?}/${SUBNAMES[0]}"
}


