# Azure IAM Connector Setup

## Overview
This directory contains utilities for setting up Azure Identity and Access Management (IAM) resources required for the Secure Workload Azure connector. The setup script creates the necessary application registrations, service principals, custom roles, and permissions required for Secure Workload to interact with Azure resources.

## Prerequisites
- Azure subscription
- Azure CLI installed (if running locally) or access to Azure Cloud Shell
- Permissions to create application registrations, service principals, and custom roles in Azure

## Quick Start
The quickest way to set up the Azure IAM connector is through Azure Cloud Shell:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/akshay-tetration/connectors/main/azure/iam_setup_v1.sh)
```

This command will execute the script with default settings (non-interactive mode).

## Script Options
The script supports the following command line options:

```
Usage: ./iam_setup_v1.sh -m <mode> -i <interactive>
  -m, --mode          Mode of operation (iam(default) or cleanup)
  -i, --interactive   Interactive mode (true or false(default))
```

### Modes
- **iam**: (Default) Creates all required IAM resources including:
  - Application registration
  - Service principal
  - Custom role with necessary permissions
  - Role assignments

- **cleanup**: Deletes resources created by the script. You will need to provide:
  - Application ID
  - Role name

### Interactive Mode
- **false**: (Default) Uses auto-generated names for resources
- **true**: Prompts for resource names and subscription selection

## Examples

### Basic setup (non-interactive)
```bash
./iam_setup_v1.sh
```

### Interactive setup
```bash
./iam_setup_v1.sh -i true
```

### Cleanup resources
```bash
./iam_setup_v1.sh -m cleanup
```

## Output
Upon successful execution, the script will output the following information:

1. Credentials required for onboarding the Azure Connector:
   - Tenant ID
   - Subscription ID
   - Client ID
   - Client Secret

2. Information required for cleanup:
   - Application ID
   - Application Name
   - Role ID
   - Role Name

Make sure to save this information securely, as you will need it to:
- Configure the Secure Workload Azure connector
- Clean up resources when no longer needed

## Permissions
The custom role created by this script includes permissions for:
- Reading VM, network, and container resources
- Flow log access
- NSG management
- Storage account access
- Resource group reads

## Troubleshooting
If the script fails:
- Check that you have the appropriate permissions in Azure
- Ensure you're logged into the Azure CLI
- Check if the resources already exist
- Review any error messages displayed by the script
