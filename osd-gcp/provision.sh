#!/bin/bash

# Color codes for bash output
BLUE='\e[36m'
GREEN='\e[32m'
RED='\e[31m'
YELLOW='\e[33m'
CLEAR='\e[39m'

# Help for MacOS
export LC_ALL=C

#----DEFAULTS----#
# Generate a 5-digit random cluster identifier for resource tagging purposes
RANDOM_IDENTIFIER=$(head /dev/urandom | LC_CTYPE=C tr -dc a-z0-9 | head -c 2 ; echo '')
# Ensure USER has a value
if [ -z "$JENKINS_HOME" ]; then
  USER=${USER:-"unknown"}
else
  USER=${USER:-"jenkins"}
fi

SHORTNAME=$(echo $USER | head -c 7)

# Generate a default resource name
RESOURCE_NAME="$SHORTNAME-$RANDOM_IDENTIFIER"
NAME_SUFFIX="odgc"

# Default to us-east1
GCLOUD_REGION=${GCLOUD_REGION:-"us-east1"}
GCLOUD_NODE_COUNT=${GCLOUD_NODE_COUNT:-"3"}
GCLOUD_MACHINE_TYPE=${GCLOUD_MACHINE_TYPE:-"custom-4-16384"}
# was: GCLOUD_MACHINE_TYPE=${GCLOUD_MACHINE_TYPE:-"n1-standard-4"}

# OCM_URL can be one of: 'production', 'staging', 'integration'
OCM_URL=${OCM_URL:-"production"}

#----VALIDATE ENV VARS----#
# Validate that we have all required env vars and exit with a failure if any are missing
missing=0

if [ -z "$GCLOUD_CREDS_FILE" ]; then
    printf "${RED}GCLOUD_CREDS_FILE env var not set. flagging for exit.${CLEAR}\n"
    missing=1
fi

if [ "$missing" -ne 0 ]; then
    exit $missing
fi

if [ ! -z "$CLUSTER_NAME" ]; then
    RESOURCE_NAME="$CLUSTER_NAME-$RANDOM_IDENTIFIER"
fi
printf "${BLUE}Using $RESOURCE_NAME to identify all created resources.${CLEAR}\n"


#----VERIFY ocm CLI----#
if [ -z "$(which ocm)" ]; then
    printf "${RED}Could not find the ocm cli, exiting.  Try running ./install.sh.${CLEAR}\n"
    exit 1
fi

#----SIGN IN TO ocm----#
if [ -f ~/.ocm.json ]; then
    REFRESH_TOKEN=`cat ~/.ocm.json | jq -r '.refresh_token'`
    CLIENT_ID=`cat ~/.ocm.json | jq -r '.client_id'`
    curl --silent https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token -d grant_type=refresh_token -d client_id=$CLIENT_ID -d refresh_token=$REFRESH_TOKEN > /dev/null
else
    ocm login --token=$OCM_TOKEN --url $OCM_URL
fi

#----CREATE CLUSTER----#
OSDGCP_CLUSTER_NAME="${RESOURCE_NAME}-${NAME_SUFFIX}"
printf "${BLUE}Creating an OSD cluster on GCP named ${OSDGCP_CLUSTER_NAME}.${CLEAR}\n"

ocm create cluster --ccs --service-account-file $GCLOUD_CREDS_FILE --provider gcp --region $GCLOUD_REGION --compute-machine-type $GCLOUD_MACHINE_TYPE --compute-nodes $GCLOUD_NODE_COUNT $OSDGCP_CLUSTER_NAME
if [ "$?" -ne 0 ]; then
    printf "${RED}Failed to provision cluster. See error above. Exiting${CLEAR}\n"
    exit 1
fi

CLUSTER_NAME=$OSDGCP_CLUSTER_NAME

printf "${GREEN}Successfully provisioned cluster ${CLUSTER_NAME}.${CLEAR}\n"

printf "${GREEN}Cluster name: '${CLUSTER_NAME}${CLEAR}'\n"

CLUSTER_ID=`ocm list clusters --parameter search="name like '${CLUSTER_NAME}'" --no-headers | awk  '{ print $1 }'`
printf "${GREEN}Cluster ID: '${CLUSTER_ID}${CLEAR}'\n"

CLUSTER_DOMAIN=`ocm get /api/clusters_mgmt/v1/clusters/$CLUSTER_ID | jq -r '.dns.base_domain'`
printf "${GREEN}Cluster domain: '${CLUSTER_DOMAIN}${CLEAR}'\n"

sed -e "s;__CLUSTER_NAME__;$CLUSTER_NAME;g" \
    -e "s;__CLUSTER_ID__;$CLUSTER_ID;g" \
    -e "s;__CLUSTER_DOMAIN__;$CLUSTER_DOMAIN;g" \
                dex-idp-config.yaml.template \
                > $(pwd)/${OSDGCP_CLUSTER_NAME}.yaml

oc login --token=$IDP_SERVICE_ACCOUNT_TOKEN --server=$IDP_ISSUER_LOGIN_SERVER
oc apply -f $(pwd)/${OSDGCP_CLUSTER_NAME}.yaml
oc logout

# Configure IDP and users
NAMELEN=`printf "%02x\n" ${#GITHUB_USER}`
printf "%b" '\x0a' > username.encoded
printf "%b" '\x'$NAMELEN >> username.encoded
printf "%s" $GITHUB_USER >> username.encoded
printf "%b" '\x12\x06' >> username.encoded
printf "%s" 'github' >> username.encoded
base64 username.encoded | sed 's/\=$//' > username.64
rm username.encoded

# Need to loop over this - to wait until it comes available

while ! ocm create idp --cluster=$CLUSTER_ID --type openid --client-id  $CLUSTER_NAME --client-secret $CLUSTER_ID-$CLUSTER_ID --issuer-url $IDP_ISSUER_URL --email-claims email --name-claims fullName,name --username-claims fullName,preferred_username,email,name
do
    printf "${YELLOW}Waiting for cluster to become active...${CLEAR}\n"
    sleep 30
done

printf "${GREEN}Adding github user ${GITHUB_USER} as admin.${CLEAR}\n"

ocm create user `cat username.64` --cluster=$CLUSTER_ID --group=cluster-admins
ocm create user `cat username.64` --cluster=$CLUSTER_ID --group=dedicated-admins
rm username.64

#-----DUMP STATE FILE----#
LOGIN_URL=https://console-openshift-console.apps.$OSDGCP_CLUSTER_NAME.$CLUSTER_DOMAIN
cat > $(pwd)/${OSDGCP_CLUSTER_NAME}.json <<EOF
{
    "CLUSTER_NAME": "${OSDGCP_CLUSTER_NAME}",
    "CLUSTER_ID": "${CLUSTER_ID}",
    "REGION": "${GCLOUD_REGION}",
    "OCM_URL": "${OCM_URL}",
    "LOGIN_URL": "${LOGIN_URL}",
    "PLATFORM": "OSD-GCP"
}
EOF

printf "${GREEN}Cluster provision successful.  Cluster named ${OSDGCP_CLUSTER_NAME} created. \n"
printf "State files saved for cleanup in $(pwd)/${OSDGCP_CLUSTER_NAME}.json and $(pwd)/${OSDGCP_CLUSTER_NAME}.yaml.${CLEAR}\n"

