#!/bin/bash

# If no env var for FTP_USER has been specified, use 'admin':
if [ "$FTP_USER" = "**String**" ]; then
    export FTP_USER='admin'
fi

# If no env var has been specified, generate a random password for FTP_USER:
if [ "$FTP_PASS" = "**Random**" ]; then
    export FTP_PASS=`cat /dev/urandom | tr -dc A-Z-a-z-0-9 | head -c${1:-16}`
fi

# Do not log to STDOUT by default:
if [ "$LOG_STDOUT" = "**Boolean**" ]; then
    export LOG_STDOUT=''
else
    export LOG_STDOUT='Yes.'
fi

# Create home dir and update vsftpd user db:
mkdir -p "/home/vsftpd/${FTP_USER}"

if [[ ! -v "$USER_ID" ]]; then
	usermod -u ${USER_ID} ftp
fi
if [[ ! -v "$GROUP_ID" ]]; then
	groupmod -g ${GROUP_ID} ftp
fi


#do not overwrite existing virtual_users.txt and only add FTP_USER if it not already exists
#TODO add check to update password if FTP_PASS do not equals the current one in file
if ! grep -Fxq "${FTP_USER}" /etc/vsftpd/virtual_users.txt; then
	echo -e "${FTP_USER}\n${FTP_PASS}" >> /etc/vsftpd/virtual_users.txt
fi

/usr/bin/db_load -T -t hash -f /etc/vsftpd/virtual_users.txt /etc/vsftpd/virtual_users.db

#create directories for every user in virtual_users.txt
for user in $(awk 'NR%2==1' /etc/vsftpd/virtual_users.txt); do
	mkdir -p /home/vsftpd/$user
done

chown -R ftp:ftp /home/vsftpd/
chown -R ftp:ftp /var/log/vsftpd

# Set passive mode parameters:
if [ "$PASV_ADDRESS" = "**IPv4**" ]; then
    export PASV_ADDRESS=$(/sbin/ip route|awk '/default/ { print $3 }')
fi

# Add ssl options
if [ $SSL_ENABLE = "YES" ]; then
	echo "ssl_enable=YES" >> /etc/vsftpd/vsftpd.conf
	echo "allow_anon_ssl=NO" >> /etc/vsftpd/vsftpd.conf
	echo "force_local_data_ssl=YES" >> /etc/vsftpd/vsftpd.conf
	echo "force_local_logins_ssl=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_tlsv1_1=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_tlsv1_2=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_tlsv1=NO" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_sslv2=NO" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_sslv3=NO" >> /etc/vsftpd/vsftpd.conf
	echo "require_ssl_reuse=YES" >> /etc/vsftpd/vsftpd.conf
	echo "ssl_ciphers=HIGH" >> /etc/vsftpd/vsftpd.conf
	echo "rsa_cert_file=/etc/ssl/certs/vsftpd.crt" >> /etc/vsftpd/vsftpd.conf
	echo "rsa_private_key_file=/etc/ssl/private/vsftpd.key" >> /etc/vsftpd/vsftpd.conf
	# Generate self-signed ssl files if no ones exist
	mkdir -p /etc/ssl/private/
	# mount your key and cert file as /etc/ssl/private/vsftpd.key and /etc/ssl/private/vsftpd.crt to override this
	if [ ! -f "/etc/ssl/private/vsftpd.key" ] && [ ! -f /etc/ssl/private/vsftpd.crt ]; then
		# TODO set better subject
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/vsftpd.key -out /etc/ssl/certs/vsftpd.crt -subj "/C=PE/ST=Lima/L=Lima/O=Acme Inc. /OU=IT Department/CN=acme.com"
	elif ([ ! -f "/etc/ssl/private/vsftpd.key" ] && [ -f /etc/ssl/private/vsftpd.crt ]) || ([ -f "/etc/ssl/private/vsftpd.key" ] && [ ! -f /etc/ssl/private/vsftpd.crt ]); then
		echo "Only one of /etc/ssl/private/vsftpd.key or /etc/ssl/private/vsftpd.crt exists exiting" 
	fi
fi


echo "pasv_address=${PASV_ADDRESS}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_max_port=${PASV_MAX_PORT}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_min_port=${PASV_MIN_PORT}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_addr_resolve=${PASV_ADDR_RESOLVE}" >> /etc/vsftpd/vsftpd.conf
echo "pasv_enable=${PASV_ENABLE}" >> /etc/vsftpd/vsftpd.conf
echo "file_open_mode=${FILE_OPEN_MODE}" >> /etc/vsftpd/vsftpd.conf
echo "local_umask=${LOCAL_UMASK}" >> /etc/vsftpd/vsftpd.conf

# Get log file path
export LOG_FILE=`grep xferlog_file /etc/vsftpd/vsftpd.conf|cut -d= -f2`

# stdout server info:
if [ ! $LOG_STDOUT ]; then
cat << EOB
	*************************************************
	*                                               *
	*    Docker image: fauria/vsftd                 *
	*    https://github.com/fauria/docker-vsftpd    *
	*                                               *
	*************************************************

	SERVER SETTINGS
	---------------
	· FTP User: $FTP_USER
	· FTP Password: $FTP_PASS
	· Log file: $LOG_FILE
	· Redirect vsftpd log to STDOUT: No.
EOB
else
    /usr/bin/ln -sf /dev/stdout $LOG_FILE
fi

# Run vsftpd:
&>/dev/null /usr/sbin/vsftpd /etc/vsftpd/vsftpd.conf
