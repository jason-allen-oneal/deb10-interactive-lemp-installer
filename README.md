# deb10-interactive-lemp-installer

This bash script is intended to be an all-in-one, basic LEMP stack installatiin tool. This script assumes you are currently logged in as root.

```
Put it on the local machine
chmod 755 interactive-lemp.sh
./interactive-lemp.sh
```

**_WARNING_** - By default, this script configures vsftpd to allow for root login for ease and quickness of further setup and configuration. This is very unwise to use in production for security reasons. It is therefore recommended to remove root from the allowed ftpusers list. One may do this by either editing the script on line 16 and removing
`sed -i "s/^root.*/#root/" /etc/ftpusers`  
-or- simply run this command when you no longer require root ftp access:  
`sed -i "s/^#root/root/" /etc/ftpusers`

Tested on Debian 4.19.37-5+deb10u2 (2019-08-08) x86_64 freshly installed.
