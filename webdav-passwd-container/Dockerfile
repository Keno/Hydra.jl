FROM ubuntu:12.10
MAINTAINER "Keno Fischer"<kfischer@college.harvard.edu>
run apt-get update
run apt-get -y install apache2 
run a2enmod dav dav_fs dav_lock

env APACHE_RUN_USER    www-data
env APACHE_RUN_GROUP   www-data
env APACHE_PID_FILE    /var/run/apache2.pid
env APACHE_RUN_DIR     /var/run/apache2
env APACHE_LOCK_DIR    /var/lock/apache2
env APACHE_LOG_DIR     /var/log/apache2
env LANG               C

run a2enmod rewrite
run mkdir /documentroot
ADD 000-default /etc/apache2/sites-enabled/000-default
