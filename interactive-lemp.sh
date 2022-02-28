#!/bin/bash

# Set a password for the root mysql user
echo 'Welcome to the Debian 10 LEMP stack installer. Please enter the desired root mysql password to begin.\n'
read MYSQL_ROOT_PASSWORD

echo

echo 'Do you wish to install phpMyAdmin, as well? y/n'

read install_pma_input

if [ install_pma_input -eq 'y' ]
then
	INSTALL_PMA=True
elif [ install_pma_input -eq 'yes' ]
then
	INSTALL_PMA=True
elif [ install_pma_input -eq 'n' ]
then
	INSTALL_PMA=False
elif [ install_pma_input -eq 'no' ]
then
	INSTALL_PMA=False
else
	INSTALL_PMA=False
fi

if [ INSTALL_PMA -eq True ]
then
	echo "Okay, let's set the phpMyAdmin credentials so it can connect to the database."
	echo "Username? (Default: pma) "
	read PMA_DB_USERNAME
	if [ -z $PMA_DB_USERNAME ]
	then
		PMA_DB_USERNAME='pma'
	fi
	
	echo "Password? (Default: pmapassword) "
	read PMA_DB_PASSWORD
	if [ -z $PMA_DB_PASSWORD ]
	then
		PMA_DB_PASSWORD='pmapassword'
	fi
	
	echo
	
	echo 'Would you like to create a separate user with which to login to phpMyAdmin? y/n '
	read setup_user
	
	if [ setup_user -eq 'y' ]
	then
		CREATE_USER=True
	elif [ setup_user -eq 'yes' ]
	then
		CREATE_USER=True
	elif [ setup_user -eq 'n' ]
	then
		CREATE_USER=False
	elif [ setup_user -eq 'no' ]
	then
		CREATE_USER=False
	else
		CREATE_USER=False
	fi
	
	if [ $CREATE_USER -eq True ]
	then
		echo "Enter the username (Default: debadmin) "
		read PMA_USERNAME
		
		if [ -z $PMA_USERNAME ]
		then
			PMA_USERNAME='debadmin'
		fi
		
		pass=$(echo $RANDOM | md5sum | head -c 13)
		echo "Enter a password (Default: $pass) "
		read PMA_PASSWORD
		
		if [ -z $PMA_PASSWORD ]
		then
			PMA_PASSWORD=$pass
		fi
	fi
fi

apt -y update
apt-get -qq upgrade

# install and configure vsftpd
apt-get -qq install vsftpd wget curl gnupg2
sed -in "s/^#write_enable.*/write_enable=YES/" /etc/vsftpd.conf
echo "userlist_deny=YES" >> /etc/vsftpd.conf
sed -in "s/^root.*/#root/" /etc/ftpusers
systemctl restart vsftpd

# install and configure mariadb
apt-get -qq install mariadb-server mariadb-client

# thanks to https://gist.github.com/Mins/4602864
apt-get -qq install expect

SECURE_MYSQL=$(expect -c "

set timeout 10
spawn mysql_secure_installation

expect \"Enter current password for root (enter for none):\"
send \"$MYSQL_ROOT_PASSWORD\r\"

expect \"Change the root password?\"
send \"n\r\"

expect \"Remove anonymous users?\"
send \"y\r\"

expect \"Disallow root login remotely?\"
send \"y\r\"

expect \"Remove test database and access to it?\"
send \"y\r\"

expect \"Reload privilege tables now?\"
send \"y\r\"

expect eof
")

echo "$SECURE_MYSQL"

apt-get -qq purge expect

if [ $INSTALL_PMA -eq True ]
then
	mysql -u root -p$MYSQL_ROOT_PASSWORD -D mysql -e "GRANT ALL PRIVILEGES ON *.* TO '$PMA_USERNAME'@'localhost' IDENTIFIED BY '$PMA_PASSWORD' WITH GRANT OPTION"
fi

# install nginx
apt-get -qq install ca-certificates nginx
systemctl start nginx

if [ $INSTALL_PMA -eq False ]
then
	echo "Would you like to install php? y/n "
	read install_php
	if [ install_php -eq 'y' ]
	then
		INSTALL_PHP=True
	elif [ install_php -eq 'yes' ]
	then
		INSTALL_PHP=True
	elif [ install_php -eq 'n' ]
	then
		INSTALL_PHP=False
	elif [ install_php -eq 'no' ]
	then
		INSTALL_PHP=False
	else
		INSTALL_PHP=False
	fi
fi

# install php
if [ $INSTALL_PMA -eq True ] || [ $INSTALL_PHP -eq True ]
then
	apt-get -qq install php-{fpm,mbstring,zip,gd,xml,pear,gettext,cgi,mysql}
fi

if [ $INSTALL_PMA -eq True ]
then
	# install and configure phpmyadmin
	cd /tmp
	wget https://files.phpmyadmin.net/phpMyAdmin/5.1.3/phpMyAdmin-5.1.3-all-languages.tar.gz
	tar xf phpMyAdmin-5.1.3-all-languages.tar.gz 
	mv phpMyAdmin-5.1.3-all-languages/ /var/www/html/phpmyadmin
	rm phpMyAdmin-5.1.3-all-languages.tar.gz

	mysql -u root -p$MYSQL_ROOT_PASSWORD < /var/www/html/phpmyadmin/sql/create_tables.sql

	mysql -u root -p$MYSQL_ROOT_PASSWORD -D mysql -e "GRANT SELECT, INSERT, UPDATE, DELETE ON phpmyadmin.* TO 'pma'@'localhost' IDENTIFIED BY '$PMA_DB_PASSWORD'"

	chown -R www-data:www-data /var/www/html/phpmyadmin
	cp /var/www/html/phpmyadmin/config.sample.inc.php /var/www/html/phpmyadmin/config.inc.php
	chmod 755 /var/www/html/phpmyadmin/config.inc.php

	rand=$(echo $RANDOM | md5sum | head -c 13)
	curl --silent https://phpsolved.com/phpmyadmin-blowfish-secret-generator/?g=$rand > blowfish.txt
	bf_replacement=$(cat blowfish.txt | grep -oP '(?<=<pre>)[^<]*' | head -n2 | tail -1)
	sed -in "s|\$cfg\['blowfish_secret'\].*|${bf_replacement}|g" /var/www/html/phpmyadmin/config.inc.php
rm /tmp/blowfish.txt

	sed -in "s|^\/\/ \$cfg\['Servers'\]\[\$i\]\['controluser'\] = 'pma';|\$cfg\['Servers'\]\[\$i\]\['controluser'\] = 'pma';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|^\/\/ \$cfg\['Servers'\]\[\$i\]\['controlpass'\].*|\$cfg\['Servers'\]\[\$i\]\['controlpass'\] = '$PMA_DB_PASSWORD';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['pmadb'\] = 'phpmyadmin';|\$cfg\['Servers'\]\[\$i\]\['pmadb'\] = 'phpmyadmin';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['bookmarktable'\] = 'pma__bookmark';|\$cfg\['Servers'\]\[\$i\]\['bookmarktable'\] = 'pma__bookmark';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['relation'\] = 'pma__relation';|\$cfg\['Servers'\]\[\$i\]\['relation'\] = 'pma__relation';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['table_info'\] = 'pma__table_info';|\$cfg\['Servers'\]\[\$i\]\['table_info'\] = 'pma__table_info';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i]\['table_coords'\] = 'pma__table_coords';|\$cfg\['Servers'\]\[\$i]\['table_coords'\] = 'pma__table_coords';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['pdf_pages'\] = 'pma__pdf_pages';|\$cfg\['Servers'\]\[\$i\]\['pdf_pages'\] = 'pma__pdf_pages';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['column_info'\] = 'pma__column_info';|\$cfg\['Servers'\]\[\$i\]\['column_info'\] = 'pma__column_info';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['history'\] = 'pma__history';|\$cfg\['Servers'\]\[\$i\]\['history'\] = 'pma__history';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['table_uiprefs'\] = 'pma__table_uiprefs';|\$cfg\['Servers'\]\[\$i\]\['table_uiprefs'\] = 'pma__table_uiprefs';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['tracking'\] = 'pma__tracking';|\$cfg\['Servers'\]\[\$i\]\['tracking'\] = 'pma__tracking';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['userconfig'\] = 'pma__userconfig';|\$cfg\['Servers'\]\[\$i\]\['userconfig'\] = 'pma__userconfig';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['recent'\] = 'pma__recent';|\$cfg\['Servers'\]\[\$i\]\['recent'\] = 'pma__recent';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['favorite'\] = 'pma__favorite';|\$cfg\['Servers'\]\[\$i\]\['favorite'\] = 'pma__favorite';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['users'\] = 'pma__users';|\$cfg\['Servers'\]\[\$i\]\['users'\] = 'pma__users';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['usergroups'\] = 'pma__usergroups';|\$cfg\['Servers'\]\[\$i\]\['usergroups'\] = 'pma__usergroups';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['navigationhiding'\] = 'pma__navigationhiding';|\$cfg\['Servers'\]\[\$i\]\['navigationhiding'\] = 'pma__navigationhiding';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['savedsearches'\] = 'pma__savedsearches';|\$cfg\['Servers'\]\[\$i\]\['savedsearches'\] = 'pma__savedsearches';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['central_columns'\] = 'pma__central_columns';|\$cfg\['Servers'\]\[\$i\]\['central_columns'\] = 'pma__central_columns';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['designer_settings'\] = 'pma__designer_settings';|\$cfg\['Servers'\]\[\$i\]\['designer_settings'\] = 'pma__designer_settings';|g" /var/www/html/phpmyadmin/config.inc.php

	sed -in "s|\/\/ \$cfg\['Servers'\]\[\$i\]\['export_templates'\] = 'pma__export_templates';|\$cfg\['Servers'\]\[\$i\]\['export_templates'\] = 'pma__export_templates';|g" /var/www/html/phpmyadmin/config.inc.php
fi

if [ $INSTALL_PHP -eq True ] || [ $INSTALL_PMA -eq True ]
then
	# configure nginx for phpmyadmin
	sed -in "s/index index.html index.htm index.nginx-debian.html;/index index.html index.htm index.nginx-debian.html index.php;/" /etc/nginx/sites-available/default
	php_version=`php -r 'echo PHP_VERSION;'`
	ver=${php_version:0:3}
	sed -in "s|#location ~ \\\\.php\$ {|location ~ \\\\.php\$ {|g" /etc/nginx/sites-available/default
	sed -in "s|#[ \t]include snippets\/fastcgi-php\.conf;|\tinclude snippets\/fastcgi-php\.conf;|g" /etc/nginx/sites-available/default
	sed -in "s|#[ \t]fastcgi_pass unix:\/run\/php\/php7.3-fpm\.sock;|\tfastcgi_pass unix:\/run\/php\/php$ver-fpm\.sock;|g" /etc/nginx/sites-available/default
	sed -in '0,/#\}/s//\}/' /etc/nginx/sites-available/default

	systemctl restart nginx php$ver-fpm
fi

echo 'Operation complete. You should now have a fully functioning LEMP stack. You can access phpMyAdmin by visiting http://localhost/phpmyadmin. A phpMyAdmin user has been created:'
echo "Username: $PMA_USERNAME"
echo "Password: $PMA_PASSWORD"
echo 'Please make note of these credentials as they are not recoverable.'
