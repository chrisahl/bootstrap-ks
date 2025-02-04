## OpenShift Dedicated (OSD)

This module can be used to install dependencies for OpenShift Dedicated (OSD) provisioning (the `ocm` cli), provision an OSD cluster, and destroy an OSD cluster provisioned using this utility.
OSD clusters can be backed by Google Cloud or Amazon AWS services.

### Getting Started
*Optionally* run install.sh, this only works on MacOS and Fedora-based Linux instances.  

### Provisioning
1. Set the following env vars before provisioning in AWS:

```
export OCM_URL=<one of: 'production', 'staging', 'integration'>
export AWS_ACCOUNT_ID=<your AWS account ID>
export AWS_ACCESS_KEY_ID=<your AWS access key ID>
export AWS_SECRET_ACCESS_KEY=<your AWS secret access key>
export AWS_REGION=<region>  # defaults to us-east-1
export AWS_NODE_COUNT=<number> # defaults to 3

# Optional

export ADMIN_USERID=<the user ID of an administrator to create>
export ADMIN_PASSWORD=<the password of an administrator to create>

export CLUSTER_NAME=<some cluster name> # if you set a cluster name, we will use it as a base name for all resources created and append a unique identifier
# if CLUSTER_NAME is not specified, we will use the first 8 characters of the system's username
# note that cluster names are a maximum of 15 characters, and we append three - so you effectively get 12
```

2. run `./provision.sh`
3. if successful, you will see a `.json` file with metadata for your cluster!

### Cleaning up a cluster
1. run `./destroy.sh <.json file of your cluster metadata>`
