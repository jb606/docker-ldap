#!/bin/bash

#set -e
#############################################
# These can be passed in from the environment
#############################################

ROOT_PASSWORD=${ROOT_PASSWD:-secret}
ROOTDN=${ROOTDN:-'cn=admin'}
SUFFIX=${SUFFIX:-'dc=example,dc=local'}
URIS=${URIS:-"ldap:/// ldapi:///"}
ENABLE_TLS=${ENABLE_TLS:-'no'}
TLS_CA=${TLS_CA}
TLS_CERT=${TLS_CERT}
TLS_KEY=${TLS_KEY}

############################################
# INTERNAL STUFF
###########################################

USE_SELF_SIGNED=1
SSL_CFG=/files/ssl_self_cfg



if [ -f "/etc/os-release" ]; then
	source /etc/os-release
	DB_CFG="/etc/openldap/DB_CONFIG.example"
else
	exit 1
	DB_CFG="/usr/share/openldap-servers/DB_CONFIG.example"
fi

if [ "$ID" == "centos" ]; then
	DB_CFG="/usr/share/openldap-servers/DB_CONFIG.example"
fi

function ldapsed() {
	local c
	local f=$2
	if [ "$1" == "add" ]; then
		c="ldapadd"
	elif [ "$1" == "modify" ]; then
		c="ldapmodify"
	else
		echo "Well crap ($1)"
		exit 1
	fi
	local dcAttr
	dcAttr=$(echo "${SUFFIX}" | grep -Po "(?<=^dc\=)[\w\d]+")
	
	sed -e "s ROOT_PASSWORD ${ROOT_PASSWORD_HASH} g"\
	    -e "s ROOTDN ${ROOTDN} g" \
	    -e "s SUFFIX ${SUFFIX} g" \
	    -e "s FIRSTDC ${dcAttr} g" \
	    -e "s TLS_CA ${TLS_CA} g" \
	    -e "s TLS_CERT ${TLS_CERT} g" \
	    -e "s TLS_KEY ${TLS_KEY} g" \
	    $f | $c -Y EXTERNAL -H ldapi:/// 
}
###########################################################################33
# Main Script
#############################################################################

# Dummy check, ldaps needs to be added to URIs.
R=`echo $URIS | grep ldaps`
RET=$?
URIS=`echo $URIS | sed -e 's/\"//g'`
if [ ${ENABLE_TLS} == "yes" -a $RET -eq 1 ]; then
	echo "Adding ldaps:/// to the URI list"
       URIS="${URIS} ldaps:///"
fi

if [ $TLS_CA -a $TLS_CERT -a $TLS_KEY ]; then
	echo -n "External TLS options set "
	USE_SELF_SIGNED=0
	echo "($USE_SELF_SIGNED)"

	if [ ! -f "$TLS_CA" -a ! -f "$TLS_CERT" -a ! -f "$TLS_KEY" ]; then
		echo "Missing cert files, please check your settings"
		echo "CA: $TLS_CA CERT: $TLS_CERT KEY: $TLS_KEY"
		exit 1
	fi
	
fi
# Self signed cert section
if [ ${ENABLE_TLS} == "yes" -a $USE_SELF_SIGNED -eq 1 ]; then
	echo "Using self-signed certs."
	TLS_CA="/etc/openldap/cert.crt"
	TLS_CERT="/etc/openldap/cert.crt"
	TLS_KEY="/etc/openldap/cert.key"
	if [ ! -f "$SSL_CFG" ]; then
		echo "WTH $SSL_CFG missing?"
		exit 1
	fi

	if [ ! -f "$TLS_CA" -a ! -f "$TLS_CERT" -a ! -f "$TLS_KEY" -a $ENABLE_TLS == "yes" ]; then
		echo "TLS Config Files Missing !!!!"
		cat $SSL_CFG | sed -e "s HOSTNAME ${HOSTNAME} g" > /tmp/ssl
		SSL_CFG=/tmp/ssl
		openssl req -x509 -config $SSL_CFG  -nodes -newkey rsa:2048 -keyout $TLS_KEY -out $TLS_CERT -days 3650
	fi
fi
if [ ! -f "/var/lib/ldap/DB_CONFIG" ]; then
	echo "SLAPD not setup"
	echo "Starting inital config"
	cp $DB_CFG /var/lib/ldap/DB_CONFIG
	chown ldap:ldap /var/lib/ldap/DB_CONFIG
	chmod o-rwx /var/lib/ldap/DB_CONFIG
	chown -R ldap:ldap /var/lib/ldap
        chown -R ldap:ldap /etc/openldap/slapd.d
        chown -R ldap:ldap /var/run/openldap
	echo "Starting slapd"
	slapd -d 64 -u ldap -g ldap -F /etc/openldap/slapd.d -h "ldapi:///" &
	sleep 5
	echo "Loading base config for $SUFFIX"
	ROOT_PASSWORD_HASH=$(slappasswd -s "${ROOT_PASSWORD}")
	ldapsed "modify" /files/config_base.ldif
	if [ ${ENABLE_TLS} == "yes" ]; then
		echo "Setting up TLS "
		chown ldap:ldap $TLS_CA
		chown ldap:ldap $TLS_CERT
		chown ldap:ldap $TLS_KEY
		chmod 640 $TLS_CA $TLS_CERT
		chmod 400 $TLS_KEY
		
		ldapsed "modify" /files/tls_cfg.ldif
	fi
	echo "Adding system ($ROOTDN)"
	ldapsed "add" /files/basecfg.ldif
	if [ -d "/files/ldif.d" ]; then
		for ldif in `ls /files/ldif.d/*.ldif`; do
			echo "Adding $ldif"
			ldapsed "add" $ldif
		done
	fi
	echo "Shutting down slapd...standby"
	kill `ps -a | grep slapd | awk '{print $1}'`

fi

echo "Starting Slapd with URIs $URIS"
slapd -d64 -u ldap -g ldap -F /etc/openldap/slapd.d -h "${URIS}"

