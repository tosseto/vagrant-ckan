#!/usr/bin/env bash

set -ex

# CKAN_PKG='python-ckan_2.0_amd64.deb'
#
# apt-get update -y
#
# apt-get -y install debconf-utils
# cat <<EOL | debconf-set-selections
# grub-pc grub-pc/install_devices multiselect /dev/vda
# grub-pc grub-pc/install_devices_empty boolean false
# EOL
# apt-get -y upgrade
#
# export LANG=en_US.UTF-8
# export LC_ALL=en_US.UTF-8
# locale-gen en_US.UTF-8
# dpkg-reconfigure locales


# Installing CKAN from Source
# http://docs.ckan.org/en/ckan-2.2/install-from-source.html

# Install the required packages

apt-get update
apt-get install -y nginx apache2 libapache2-mod-wsgi python-dev postgresql libpq-dev python-pip python-virtualenv git-core solr-jetty openjdk-6-jdk python-pastescript pwgen

PASSWD=`pwgen 12 1`

# Install CKAN into a Python virtual environment

if [ ! -d /usr/lib/ckan/default ]; then
    mkdir -p /usr/lib/ckan/default
fi

chown `whoami` /usr/lib/ckan/default
virtualenv --no-site-packages /usr/lib/ckan/default
. /usr/lib/ckan/default/bin/activate

pip install -e 'git://github.com/ckan/ckan.git@release-v2.3#egg=ckan'
pip install -r /usr/lib/ckan/default/src/ckan/requirements.txt
deactivate
. /usr/lib/ckan/default/bin/activate

# Setup a PostgreSQL database

sudo -u postgres createuser -S -D -R ckan_default
sudo -u postgres createdb -O ckan_default ckan_default -E utf-8
echo "ALTER USER ckan_default WITH PASSWORD '$PASSWD';" | sudo -u postgres psql
install -o postgres -g postgres -m 0644 /vagrant/files/pg_hba.conf /etc/postgresql/9.3/main/
service postgresql restart

# Create a CKAN config file

mkdir -p /etc/ckan/default
chown -R www-data /etc/ckan/

cd /usr/lib/ckan/default/src/ckan
paster make-config ckan /etc/ckan/default/development.ini
sed -e "s/ckan_default:pass/ckan_default:$PASSWD/" /etc/ckan/default/development.ini > /etc/ckan/default/production.ini

# Setup Solr (Single Solr instance)

install -o root -g root -m 0644 /vagrant/files/jetty /etc/default/

if [ -f /etc/solr/conf/schema.xml ]; then
    mv /etc/solr/conf/schema.xml /etc/solr/conf/schema.xml.bak
fi

if [ ! -L /etc/solr/conf/schema.xml ]; then
    ln -s /usr/lib/ckan/default/src/ckan/ckan/config/solr/schema-2.3.xml /etc/solr/conf/schema.xml
fi

sudo service jetty restart

# Create database tables

cd /usr/lib/ckan/default/src/ckan
paster db init -c /etc/ckan/default/production.ini

# Link to who.ini

ln -s /usr/lib/ckan/default/src/ckan/who.ini /etc/ckan/default/who.ini


# Create the WSGI Script File
# http://docs.ckan.org/en/ckan-2.2/deployment.html
install -o www-data -g www-data -m 0644 /vagrant/files/apache.wsgi /etc/ckan/default/
install -o www-data -g www-data -m 0644 /vagrant/files/ckan_default.conf /etc/apache2/sites-available/
install -o www-data -g www-data -m 0644 /vagrant/files/ports.conf /etc/apache2/

install -o www-data -g www-data -m 0644 /vagrant/files/ckan_default.nginx /etc/nginx/sites-available/ckan_default
ln -s /etc/nginx/sites-available/ckan_default /etc/nginx/sites-enabled/ckan_default
rm -f /etc/nginx/sites-enabled/default

a2dissite 000-default
a2ensite ckan_default
service apache2 restart
service nginx restart

# echo postfix postfix/main_mailer_type select 'Internet Site' | debconf-set-selections
# echo postfix postfix/mail_name string $HOSTNAME | debconf-set-selections
# apt-get -y install postfix

# sudo install -o root -g root -m 0600 /vagrant/files/ckan.cron /etc/cron.d/ckan
# sudo install -o root -g root -m 0700 /vagrant/files/reset_ckan_pass.sh /usr/local/bin/
