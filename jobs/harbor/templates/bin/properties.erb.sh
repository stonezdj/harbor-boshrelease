#!/usr/bin/env bash

#Protocol of harbor
export HARBOR_PROTOCOL='<%= p("ui_url_protocol") %>'

#Hostname of harbor
export HARBOR_HOSTNAME='<%= p("hostname", spec.ip).downcase %>'

#None empty value means to install optional component Notary
export WITH_NOTARY='<%= p("with_notary") ? "true" : "" %>'
  
#None empty value means to install optional component Clair
export WITH_CLAIR='<%= p("with_clair") ? "true" : "" %>'

#None empty value means to install optional component Trivy
export WITH_TRIVY='<%= p("with_trivy") ? "true" : "" %>'



#Database password of Harbor
HARBOR_DB_PWD='<%= p("db_password") %>'

#Auth mode
AUTH_MODE='<%= p("auth_mode") %>'

#UAA server
UAA_SERVER_ADDRESS='<%= p('uaa.url').downcase %>'

#UAA admin secret
UAA_ADMIN='<%= p('uaa.admin.client_id') %>'
UAA_ADMIN_SECRET='<%= p('uaa.admin.client_secret') %>'

#Whether verify server cert or not
UAA_VERIFY_CERT='<%= p('uaa.verify_cert') %>'

#Harbor UAA client
HARBOR_UAA_CLIENT_ID='<%= p('uaa.client_id') %>'
