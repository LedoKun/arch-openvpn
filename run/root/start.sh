#!/bin/bash

# if vpn set to "no" then don't run openvpn
if [[ "${VPN_ENABLED}" == "no" ]]; then

	echo "[info] VPN not enabled, skipping configuration of VPN"

else

	echo "[info] VPN is enabled, beginning configuration of VPN"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Environment variables defined as follows" ; set
		echo "[debug] Directory listing of files in /config/openvpn as follows" ; ls -al /config/openvpn
	fi

	# if vpn username and password specified then write credentials to file (authentication maybe via keypair)
	if [[ ! -z "${VPN_USER}" && ! -z "${VPN_PASS}" ]]; then

		# store credentials in separate file for authentication
		if ! $(grep -Fq "auth-user-pass credentials.conf" "${VPN_CONFIG}"); then
			sed -i -e 's/auth-user-pass.*/auth-user-pass credentials.conf/g' "${VPN_CONFIG}"
		fi

		echo "${VPN_USER}" > /config/openvpn/credentials.conf

		username_char_check=$(echo "${VPN_USER}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')

		if [[ ! -z "${username_char_check}" ]]; then
			echo "[warn] Username contains characters which could cause authentication issues, please consider changing this if possible"
		fi

		echo "${VPN_PASS}" >> /config/openvpn/credentials.conf

		password_char_check=$(echo "${VPN_PASS}" | grep -P -o -m 1 '[^a-zA-Z0-9@]+')

		if [[ ! -z "${password_char_check}" ]]; then
			echo "[warn] Password contains characters which could cause authentication issues, please consider changing this if possible"
		fi

	fi

	# remove persist-tun from ovpn file if present, this allows reconnection to tunnel on disconnect
	sed -i '/^persist-tun/d' "${VPN_CONFIG}"

	# remove reneg-sec from ovpn file if present, this is removed to prevent re-checks and dropouts
	sed -i '/^reneg-sec.*/d' "${VPN_CONFIG}"

	# remove up script from ovpn file if present, this is removed as we do not want any other up/down scripts to run
	sed -i '/^up\s.*/d' "${VPN_CONFIG}"

	# remove down script from ovpn file if present, this is removed as we do not want any other up/down scripts to run
	sed -i '/^down\s.*/d' "${VPN_CONFIG}"

	# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
	sed -i '/^route-ipv6/d' "${VPN_CONFIG}"

	# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
	sed -i '/^ifconfig-ipv6/d' "${VPN_CONFIG}"

	# remove ipv6 configuration from ovpn file if present (iptables not configured to support ipv6)
	sed -i '/^tun-ipv6/d' "${VPN_CONFIG}"

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Contents of ovpn file ${VPN_CONFIG} as follows..." ; cat "${VPN_CONFIG}"
	fi

	# get first matching 'remote' line in ovpn 
	vpn_remote=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '^remote\s.*')

	if [ -n "${vpn_remote}" ]; then

		# remove all remote lines as we cannot cope with multi remote lines
		sed -i '/^remote\s.*/d' "${VPN_CONFIG}"

		# write the single remote line back to the ovpn file on line 1
		sed -i -e "1i${vpn_remote}" "${VPN_CONFIG}"

	fi

	# create the tunnel device
	[ -d /dev/net ] || mkdir -p /dev/net
	[ -c /dev/net/"${VPN_DEVICE_TYPE}" ] || mknod /dev/net/"${VPN_DEVICE_TYPE}" c 10 200

	# get ip for local gateway (eth0)
	DEFAULT_GATEWAY=$(ip route show default | awk '/default/ {print $3}')
	echo "[info] Default route for container is ${DEFAULT_GATEWAY}"

	# split comma seperated string into list from NAME_SERVERS env variable
	IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

	# remove existing ns, docker injects ns from host and isp ns can block/hijack
	> /etc/resolv.conf

	# process name servers in the list
	for name_server_item in "${name_server_list[@]}"; do

		# strip whitespace from start and end of name_server_item
		name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "[info] Adding ${name_server_item} to /etc/resolv.conf"
		echo "nameserver ${name_server_item}" >> /etc/resolv.conf

	done

	# if the vpn_remote is NOT an ip address then resolve it
	if ! echo "${VPN_REMOTE}" | grep -P -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'; then

		# resolve vpn remote endpoint to ip (used to write to hosts file)
		vpn_remote_ip=$(dig +short "${VPN_REMOTE}" | tail -n1)

		# write vpn remote endpoint to hosts file (used for name resolution on lan when tunnel restarted due to iptable dns block)
		if [[ ! -z "${vpn_remote_ip}" ]]; then
			echo "${vpn_remote_ip}    ${VPN_REMOTE}" >> /etc/hosts
		else
			echo "[crit] ${VPN_REMOTE} cannot be resolved, possible DNS issues" ; exit 1
		fi

	fi

	if [[ "${DEBUG}" == "true" ]]; then
		echo "[debug] Show name servers defined for container" ; cat /etc/resolv.conf
		echo "[debug] Show name resolution for VPN endpoint ${VPN_REMOTE}" ; drill "${VPN_REMOTE}"
		echo "[debug] Show contents of hosts file" ; cat /etc/hosts
	fi

	# setup ip tables and routing for application
	source /root/iptable.sh

	# start openvpn tunnel
	source /root/openvpn.sh

fi
