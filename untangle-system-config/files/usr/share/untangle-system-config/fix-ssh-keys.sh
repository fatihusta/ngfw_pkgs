#! /bin/sh

SSH_KEYS_DIR=/etc/ssh
DSA_KEY=${SSH_KEYS_DIR}/ssh_host_dsa_key
DSA_PUBKEY=${SSH_KEYS_DIR}/ssh_host_dsa_key.pub
RSA_KEY=${SSH_KEYS_DIR}/ssh_host_rsa_key
RSA_PUBKEY=${SSH_KEYS_DIR}/ssh_host_rsa_key.pub
DSA_BLACKLIST=`dirname $0`/dsa.blacklist
RSA_BLACKLIST=`dirname $0`/rsa.blacklist

create_key() {
  file="$1"
  shift # because we use "$@" later on
  rm -f "${file}"
  ssh-keygen -q -f "${file}" -N '' "$@"
}

create_keys() {
  create_key ${RSA_KEY} -t rsa
  create_key ${DSA_KEY} -t dsa
}

blacklisted() {
  [ -f "$1" ] && grep -q `md5sum "$1" | awk '{print $1}'` "$2"
}

if blacklisted ${DSA_PUBKEY} ${DSA_BLACKLIST} || \
   blacklisted ${RSA_PUBKEY} ${RSA_BLACKLIST} ; then
  create_keys
fi
