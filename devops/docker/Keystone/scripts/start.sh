#!/bin/bash

# Copyright 2018 Whitestack, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# For those usages not covered by the Apache License, Version 2.0 please
# contact: esousa@whitestack.com or glavado@whitestack.com
##

set -e

DB_EXISTS=""
USER_DB_EXISTS=""
DB_NOT_EMPTY=""

max_attempts=120
function wait_db(){
    db_host=$1
    db_port=$2
    attempt=0
    echo "Wait until $max_attempts seconds for MySQL mano Server ${db_host}:${db_port} "
    while ! mysqladmin ping -h"$db_host" -P"$db_port" --silent; do
        #wait 120 sec
        if [ $attempt -ge $max_attempts ]; then
            echo
            echo "Can not connect to database ${db_host}:${db_port} during $max_attempts sec"
            return 1
        fi
        attempt=$[$attempt+1]
        echo -n "."
        sleep 1
    done
    return 0
}

function wait_keystone_host(){
    attempt=0
    timeout=2
    echo "Wait until Keystone hostname can be resolved "
    while ! nslookup $KEYSTONE_HOST; do
        #wait 120 sec
        if [ $attempt -ge $max_attempts ]; then
            echo
            echo "Can not resolve ${KEYSTONE_HOST} during $max_attempts sec"
            return 1
        fi
        attempt=$[$attempt+1]
        echo -n "."
        sleep 1
    done
    return 0
}

function is_db_created() {
    db_host=$1
    db_port=$2
    db_user=$3
    db_pswd=$4
    db_name=$5

    if mysqlshow -h"$db_host" -P"$db_port" -u"$db_user" -p"$db_pswd" | grep -v Wildcard | grep -q $db_name; then
        echo "DB $db_name exists"
        return 0
    else
        echo "DB $db_name does not exist"
        return 1
    fi
}

function is_user_db_created() {
    db_host=$1
    db_port=$2
    db_user=$3
    db_pswd=$4
    db_user_to_check=$5

    user_count=$(mysql -h"$db_host" -P"$db_port" -u"$db_user" -p"$db_pswd" --default_character_set utf8 -sse "SELECT COUNT(*) FROM mysql.user WHERE user='$db_user_to_check' AND host='%';")

    if [ $user_count -gt 0 ]; then
        echo "DB User $db_name exists"
        return 0
    else
        echo "DB User $db_name does not exist"
        return 1
    fi
}

wait_db "$DB_HOST" "$DB_PORT" || exit 1

is_db_created "$DB_HOST" "$DB_PORT" "$ROOT_DB_USER" "$ROOT_DB_PASSWORD" "keystone" && DB_EXISTS="Y"
is_user_db_created "$DB_HOST" "$DB_PORT" "$ROOT_DB_USER" "$ROOT_DB_PASSWORD" "keystone" && USER_DB_EXISTS="Y"

if [ -z $DB_EXISTS ]; then
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$ROOT_DB_USER" -p"$ROOT_DB_PASSWORD" --default_character_set utf8 -e "CREATE DATABASE keystone"
else
    if [ $(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$ROOT_DB_USER" -p"$ROOT_DB_PASSWORD" --default_character_set utf8 -sse "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'keystone';") -gt 0 ]; then
        echo "DB keystone is empty"
        DB_NOT_EMPTY="y"
    fi
fi

if [ -z $USER_DB_EXISTS ]; then
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$ROOT_DB_USER" -p"$ROOT_DB_PASSWORD" --default_character_set utf8 -e "CREATE USER 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DB_PASSWORD'"
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$ROOT_DB_USER" -p"$ROOT_DB_PASSWORD" --default_character_set utf8 -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost'"
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$ROOT_DB_USER" -p"$ROOT_DB_PASSWORD" --default_character_set utf8 -e "CREATE USER 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DB_PASSWORD'"
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$ROOT_DB_USER" -p"$ROOT_DB_PASSWORD" --default_character_set utf8 -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%'"
fi

# Setting Keystone database connection
sed -i '/^\[database\]$/,/^\[/ s/^connection = .*/connection = mysql+pymysql:\/\/keystone:'$KEYSTONE_DB_PASSWORD'@'$DB_HOST':'$DB_PORT'\/keystone/' /etc/keystone/keystone.conf

# Setting Keystone tokens
sed -i '/^\[token\]$/,/^\[/ s/^.*provider = .*/provider = fernet/' /etc/keystone/keystone.conf

# Setting Keystone for the stderr
sed -i '/\[DEFAULT\]/a use_stderr = true' /etc/keystone/keystone.conf

# Use LDAP authentication for Identity
if [ $LDAP_AUTHENTICATION_DOMAIN_NAME ]; then
    # Enable Keyston domains
    sed -i "s%.*domain_specific_drivers_enabled =.*%domain_specific_drivers_enabled = true%" /etc/keystone/keystone.conf
    sed -i "s%.*domain_config_dir =.*%domain_config_dir = /etc/keystone/domains%" /etc/keystone/keystone.conf
    mkdir -p /etc/keystone/domains
    # Configure domain for LDAP authentication
    cat << EOF > /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
[identity]
driver = ldap
[ldap]
url = $LDAP_URL
user_allow_create=false
user_allow_update=false
user_allow_delete=false
group_allow_create=false
group_allow_update=false
group_allow_delete=false
query_scope = sub
EOF
    if [ "$LDAP_BIND_USER" ]; then
        echo "user = $LDAP_BIND_USER" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_BIND_PASSWORD" ]; then
        echo "password = $LDAP_BIND_PASSWORD" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_CHASE_REFERRALS" ]; then
        echo "chase_referrals = $LDAP_CHASE_REFERRALS" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_PAGE_SIZE" ]; then
        echo "page_size = $LDAP_PAGE_SIZE" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_TREE_DN" ]; then
        echo "user_tree_dn = $LDAP_USER_TREE_DN" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_OBJECTCLASS" ]; then
        echo "user_objectclass = $LDAP_USER_OBJECTCLASS" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_ID_ATTRIBUTE" ]; then
        echo "user_id_attribute = $LDAP_USER_ID_ATTRIBUTE" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_NAME_ATTRIBUTE" ]; then
        echo "user_name_attribute = $LDAP_USER_NAME_ATTRIBUTE" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_PASS_ATTRIBUTE" ]; then
        echo "user_pass_attribute = $LDAP_USER_PASS_ATTRIBUTE" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_FILTER" ]; then
        echo "user_filter = $LDAP_USER_FILTER" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_ENABLED_ATTRIBUTE" ]; then
        echo "user_enabled_attribute = $LDAP_USER_ENABLED_ATTRIBUTE" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_ENABLED_MASK" ]; then
        echo "user_enabled_mask = $LDAP_USER_ENABLED_MASK" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_ENABLED_DEFAULT" ]; then
        echo "user_enabled_default = $LDAP_USER_ENABLED_DEFAULT" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_USER_ENABLED_INVERT" ]; then
        echo "user_enabled_invert = $LDAP_USER_ENABLED_INVERT" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_GROUP_OBJECTCLASS" ]; then
        echo "group_objectclass = $LDAP_GROUP_OBJECTCLASS" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_GROUP_TREE_DN" ]; then
        echo "group_tree_dn = $LDAP_GROUP_TREE_DN" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
    fi
    if [ "$LDAP_TLS_CACERT_BASE64" ]; then
        mkdir -p /etc/ssl/certs/
        echo "-----BEGIN CERTIFICATE-----" >> /etc/ssl/certs/ca-certificates.crt
        echo $LDAP_TLS_CACERT_BASE64 >> /etc/ssl/certs/ca-certificates.crt
        echo "-----END CERTIFICATE-----" >> /etc/ssl/certs/ca-certificates.crt
    fi
    if [ "$LDAP_USE_STARTTLS" ] && [ "$LDAP_USE_STARTTLS" == "true" ]; then
        echo "use_tls = true" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
        mkdir -p /etc/keystone/ssl/certs/
        echo "-----BEGIN CERTIFICATE-----" > /etc/keystone/ssl/certs/ca.pem
        echo $LDAP_TLS_CACERT_BASE64 >> /etc/keystone/ssl/certs/ca.pem
        echo "-----END CERTIFICATE-----" >> /etc/keystone/ssl/certs/ca.pem
        echo "tls_cacertfile = /etc/keystone/ssl/certs/ca.pem" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
        if [ "$LDAP_TLS_REQ_CERT" ]; then
            echo "tls_req_cert = $LDAP_TLS_REQ_CERT" >> /etc/keystone/domains/keystone.$LDAP_AUTHENTICATION_DOMAIN_NAME.conf
        fi
    fi
fi

# Populate Keystone database
if [ -z $DB_EXISTS ] || [ -z $DB_NOT_EMPTY ]; then
    keystone-manage db_sync
fi

# Initialize Fernet key repositories
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

wait_keystone_host

# Bootstrap Keystone service
if [ -z $DB_EXISTS ] || [ -z $DB_NOT_EMPTY ]; then
    echo "Bootstraping keystone"
    keystone-manage bootstrap \
        --bootstrap-username "$ADMIN_USERNAME" \
        --bootstrap-password "$ADMIN_PASSWORD" \
        --bootstrap-project "$ADMIN_PROJECT" \
        --bootstrap-admin-url "http://$KEYSTONE_HOST:5000/v3/" \
        --bootstrap-internal-url "http://$KEYSTONE_HOST:5000/v3/" \
        --bootstrap-public-url "http://$KEYSTONE_HOST:5000/v3/" \
        --bootstrap-region-id "$REGION_ID"
fi

echo "ServerName $KEYSTONE_HOST" >> /etc/apache2/apache2.conf

# Restart Apache Service
service apache2 restart

cat << EOF >> setup_env
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=$ADMIN_PROJECT
export OS_USERNAME=$ADMIN_USERNAME
export OS_PASSWORD=$ADMIN_PASSWORD
export OS_AUTH_URL=http://$KEYSTONE_HOST:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF

source setup_env

# Function to retry a command up to 5 times
retry() {
    local n=1
    local max=5
    local delay=5
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Attempt $n/$max:"
                sleep $delay;
            else
                echo "The command has failed after $n attempts."
                return 1
            fi
        }
    done
}

# Create NBI User
if ! openstack user show nbi --domain default; then
    echo "NBI user does not exist. Creating nbi user"
    retry openstack user create --domain default --password "$SERVICE_PASSWORD" "$SERVICE_USERNAME" || exit 1
    retry openstack project create --domain default --description "Service Project" "$SERVICE_PROJECT" || exit 1
    retry openstack role add --project "$SERVICE_PROJECT" --user "$SERVICE_USERNAME" admin || exit 1
fi
echo "Done creating the NBI user"

if [ $LDAP_AUTHENTICATION_DOMAIN_NAME ]; then
    if !(openstack domain list | grep -q $LDAP_AUTHENTICATION_DOMAIN_NAME); then
        # Create domain in keystone for LDAP authentication
        openstack domain create $LDAP_AUTHENTICATION_DOMAIN_NAME
        # Restart Apache Service
        service apache2 restart
    fi
	# Check periodically LDAP for updates
	echo "0 1 * * * keystone-manage mapping_purge --domain-name $LDAP_AUTHENTICATION_DOMAIN_NAME; keystone-manage mapping_populate --domain-name $LDAP_AUTHENTICATION_DOMAIN_NAME" >> /var/spool/cron/crontabs/root
fi

while ps -ef | grep -v grep | grep -q apache2
do
    tail -f /var/log/keystone/keystone-manage.log
done

# Only reaches this point if apache2 stops running
# When this happens exits with error code
exit 1
