#######################################################################################
# Copyright ETSI Contributors and Others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################################
FROM ubuntu:22.04

ARG APT_PROXY
RUN if [ ! -z $APT_PROXY ] ; then \
    echo "Acquire::http::Proxy \"$APT_PROXY\";" > /etc/apt/apt.conf.d/proxy.conf ;\
    echo "Acquire::https::Proxy \"$APT_PROXY\";" >> /etc/apt/apt.conf.d/proxy.conf ;\
    fi

EXPOSE 5000

WORKDIR /app

RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common && \
    add-apt-repository -y cloud-archive:antelope && \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2=2.4.* \
    keystone=2:23.0.* \
    libapache2-mod-wsgi-py3=4.9.* \
    python3-pip=22.0.* \
    build-essential=12.9* \
    python3-dev=3.10.* \
    libldap2-dev=2.5.* \
    libsasl2-dev=2.1.* \
    libssl-dev=3.0.* \
    libffi-dev=3.4* \
    libxml2-dev=2.9.* \
    libxslt1-dev=1.1.* \
    zlib1g-dev=1:1.2.* \
    ldap-utils=2.5.* \
    curl=7.81.* \
    net-tools=1.60* \
    mysql-client=8.0.* \
    dnsutils=1:9.18.* && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install python-ldap==3.2.0 ldappool==3.0.0 python-openstackclient==6.2.0

# Creating the user for the app
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -d /app appuser && \
    usermod -a -G keystone appuser && \
    usermod -a -G adm appuser && \
    chown -R appuser:appuser /app && \
    chown root:keystone /etc/keystone && \
    chmod 770 /etc/keystone && \
    chown root:keystone /etc/ssl/certs && \
    chmod 770 /etc/ssl/certs && \
    chown root:keystone /etc/apache2/apache2.conf && \
    chmod 664 /etc/apache2/apache2.conf && \
    sed -i 's/Listen 80/Listen 8080/g' /etc/apache2/ports.conf && \
    chown root:keystone /var/spool && \
    chmod 775 /var/spool && \
    chmod 770 /var/log/apache2 && \
    chmod 660 /var/log/apache2/* && \
    chmod 770 /var/log/keystone && \
    chown root:keystone /var/run/apache2 && \
    chmod 775 /var/run/apache2 && \
    mkdir -p /etc/sudoers.d && \
    echo "%appuser ALL= NOPASSWD: /sbin/service apache2 *" > /etc/sudoers.d/appuser

COPY scripts/start.sh /app/start.sh

RUN chmod +x start.sh

USER root

# database
ENV DB_HOST                 keystone-db
ENV DB_PORT                 3306
ENV ROOT_DB_USER            root
ENV ROOT_DB_PASSWORD        admin
ENV KEYSTONE_DB_PASSWORD    admin
# keystone
ENV REGION_ID               RegionOne
ENV KEYSTONE_HOST           keystone
# admin user
ENV ADMIN_USERNAME          admin
ENV ADMIN_PASSWORD          admin
ENV ADMIN_PROJECT           admin
# nbi service user
ENV SERVICE_USERNAME        nbi
ENV SERVICE_PASSWORD        nbi
ENV SERVICE_PROJECT         service
# ldap
# ENV LDAP_AUTHENTICATION_DOMAIN_NAME     no default
# ENV LDAP_URL                            ldap://localhost
# ENV LDAP_BIND_USER                      no default
# ENV LDAP_BIND_PASSWORD                  no default
# ENV LDAP_CHASE_REFERRALS                no default
# ENV LDAP_PAGE_SIZE                      0
# ENV LDAP_USER_TREE_DN                   no default
# ENV LDAP_USER_OBJECTCLASS               inetOrgPerson
# ENV LDAP_USER_ID_ATTRIBUTE              cn
# ENV LDAP_USER_NAME_ATTRIBUTE            sn
# ENV LDAP_USER_PASS_ATTRIBUTE            userPassword
# ENV LDAP_USER_FILTER                    no default
# ENV LDAP_USER_ENABLED_ATTRIBUTE         enabled
# ENV LDAP_USER_ENABLED_MASK              0
# ENV LDAP_USER_ENABLED_DEFAULT           true
# ENV LDAP_USER_ENABLED_INVERT            false
# ENV LDAP_GROUP_OBJECTCLASS              groupOfNames
# ENV LDAP_GROUP_TREE_DN                  no default
# ENV LDAP_USE_STARTTLS                   false
# ENV LDAP_TLS_CACERT_BASE64              no default
# ENV LDAP_TLS_REQ_CERT                   demand

ENTRYPOINT ["./start.sh"]
