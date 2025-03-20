<!--
# Copyright 2020 Canonical Ltd.
# All rights reserved.
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
## -->

# User authentication with external LDAP server

When using the Keystone back-end, an external LDAP server may be used for user authentication, whereas the assignment information (RBAC roles/projects) is always stored in the local mysql database. In this working model, two user and project domains are used.

- The "default" domain, in which the external LDAP is not checked, mainly intended for administrative users ("admin").
- The the "ldap" domain, in which the validation of credentials is delegated to the LDAP server. User creation / deletion is also done in the external LDAP, and the GUI and osm client are used for configuring assignment only.

The name of "ldap" domain is configurable, and must be synchronized in the GUI, NBI and Keystone OSM modules.

## LDAP Synchronization

For the "ldap" domain, Keystone will synchronize the user information between the LDAP server and the local mysql database. This is done at component startup time and periodically (in the cron), once a day, executing this command

```bash
keystone-manage mapping_purge --domain-name $LDAP_AUTHENTICATION_DOMAIN_NAME; keystone-manage mapping_populate --domain-name $LDAP_AUTHENTICATION_DOMAIN_NAME
```

If a user tries to authenticate but is not yet in the local database, the relevant data will be loaded to mysql automatically. For this reason is not crucial to execute synchronization too often. User deletion in LDAP will only be performed in mysql after the periodic synchronization. For this reason, it has to be taken into account that the user info shown by osm client may not be fully up to date until the next sync.

Keystone never deletes the assignment information, even if the LDAP user disappears. For this reason, if a new client is created in LDAP reusing the same identifier, the RBAC info associated will be the previous one.

The binding to the external LDAP may be:

- Anonymous. The remote LDAP server must support anonymous BIND with read permissions over the user branch
- Authenticated. A user account must exist in the LDAP server for Keystone, having read permissions over the user branch. This account should never expire.

The connection may be in clear (which is rarely used) or TLS.

### Configuration

The Keystone component will configure itself at startup time using a few environment variables as follows (see [this](https://www.oreilly.com/library/view/identity-authentication-and/9781491941249/ch04.html) for details):

- **LDAP_AUTHENTICATION_DOMAIN_NAME**: name of the domain which use LDAP authentication
- **LDAP_URL**: URL of the LDAP server
- **LDAP_BIND_USER** and **LDAP_BIND_PASSWORD**: This is the user/password to bind and search for users. If not specified, the user accessing Keystone needs to have anonymous query rights to the dn_tree specified in the next configuration option.
- **LDAP_USER_TREE_DN**: This specifies the root of the tree in the LDAP server in which Keystone will search for users.
- **LDAP_USER_OBJECTCLASS**: This specifies the LDAP object class that Keystone will filter on within user_tree_dn to find user objects. Any objects of other classes will be ignored.
- **LDAP_USER_ID_ATTRIBUTE**, **LDAP_USER_NAME_ATTRIBUTE** and **LDAP_USER_PASS_ATTRIBUTE**: This set of options define the mapping to LDAP attributes for the three key user attributes supported by Keystone. The LDAP attribute chosen for user_id must be something that is immutable for a user and no more than 64 characters in length. Notice that Distinguished Name (DN) may be longer than 64 characters and thus is not suitable. An uid, or mail may be appropriate.
- **LDAP_USER_FILTER**: This filter option allow additional filter (over and above user_objectclass) to be included into the search of user. One common use of this is to provide more efficient searching, where the recommended search for user objects is (&(objectCategory=person)(objectClass=user)). By specifying user_objectclass as user and user_filter as objectCategory=person in the Keystone configuration file, this can be achieved.
- **LDAP_USER_ENABLED_ATTRIBUTE**: In Keystone, a user entity can be either enabled or disabled. Setting the above option will give a mapping to an equivalent attribute in LDAP, allowing your LDAP management tools to disable a user.
- **LDAP_USER_ENABLED_MASK**: Some LDAP schemas, rather than having a dedicated attribute for user enablement, use a bit within a general control attribute (such as userAccountControl) to indicate this. Setting user_enabled_mask will cause Keystone to look at only the status of this bit in the attribute specified by user_enabled_attribute, with the bit set indicating the user is enabled.
- **LDAP_USER_ENABLED_DEFAULT**: Most LDAP servers use a boolean or bit in a control field to indicate enablement. However, some schemas might use an integer value in an attribute. In this situation, set user_enabled_default to the integer value that represents a user being enabled.
- **LDAP_USER_ENABLED_INVERT**: Some LDAP schemas have an “account locked” attribute, which is the equivalent to account being “disabled.” In order to map this to the Keystone enabled attribute, you can utilize the user_enabled_invert setting in conjunction with user_enabled_attribute to map the lock status to disabled in Keystone.
- **LDAP_USE_STARTTLS**: Enable Transport Layer Security (TLS) for providing a secure connection from Keystone to LDAP (StartTLS, not LDAPS).
- **LDAP_TLS_CACERT_BASE64**: CA certificate in Base64 format (if you have the PEM file, text inside "-----BEGIN CERTIFICATE-----"/"-----END CERTIFICATE-----" tags).
- **LDAP_TLS_REQ_CERT**: Defines how the certificates are checked for validity in the client (i.e., Keystone end) of the secure connection (this doesn’t affect what level of checking the server is doing on the certificates it receives from Keystone). Possible values are "demand", "never", and "allow". The default of demand means the client always checks the certificate and will drop the connection if it is not provided or invalid. never is the opposite—it never checks it, nor requires it to be provided. allow means that if it is not provided then the connection is allowed to continue, but if it is provided it will be checked—and if invalid, the connection will be dropped.

#### default values

- **LDAP_AUTHENTICATION_DOMAIN_NAME**: no default
- **LDAP_URL**: ldap://localhost
- **LDAP_BIND_USER**: no default
- **LDAP_BIND_PASSWORD**: no default
- **LDAP_USER_TREE_DN**: no default
- **LDAP_USER_OBJECTCLASS**: inetOrgPerson
- **LDAP_USER_ID_ATTRIBUTE**: cn
- **LDAP_USER_NAME_ATTRIBUTE**: sn
- **LDAP_USER_PASS_ATTRIBUTE**: userPassword
- **LDAP_USER_FILTER**: no default
- **LDAP_USER_ENABLED_ATTRIBUTE**: enabled
- **LDAP_USER_ENABLED_MASK**: 0
- **LDAP_USER_ENABLED_DEFAULT**: true
- **LDAP_USER_ENABLED_INVERT**: false
- **LDAP_USE_STARTTLS**: false
- **LDAP_TLS_CACERT_BASE64**: no default
- **LDAP_TLS_REQ_CERT**: demand

#### Example

- **LDAP_AUTHENTICATION_DOMAIN_NAME**: ldap
- **LDAP_URL**: ldap://ldap.example.com
- **LDAP_BIND_USER**: cn=keystone,ou=Users,dc=example,dc=com
- **LDAP_BIND_PASSWORD**: keystone
- **LDAP_USER_TREE_DN**: ou=Users,dc=example,dc=com
- **LDAP_USER_OBJECTCLASS**: person
- **LDAP_USER_ID_ATTRIBUTE**: cn
- **LDAP_USE_STARTTLS**: "true"
- **LDAP_TLS_CACERT_BASE64**: MIID/TCCAmWg...
