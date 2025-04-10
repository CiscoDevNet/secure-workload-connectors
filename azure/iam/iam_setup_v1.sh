#!/bin/bash
#
#
# Azure IAM setup script.

PREFIX="ciscocsw_"
new_application=false
cleanup=false
mode="iam"
interactive=false
timestamp=$(date +%s)

# Function to display usage
usage() {
    echo "Usage: $0 -m <mode> -i <interactive>"
    echo "  -m, --mode          Mode of operation (iam(default) or cleanup)"
    echo "  -i, --interactive   Interactive mode (true or false(default))"
    exit 1
}

# Parse command line arguments
while getopts ":m:i:" opt; do
    case ${opt} in
        m )
            mode=$OPTARG
            ;;
        i )
            interactive=$OPTARG
            ;;
        \? )
            echo "Invalid option: $OPTARG" 1>&2
            usage
            ;;
        : )
            echo "Invalid option: $OPTARG requires an argument" 1>&2
            usage
            ;;
    esac
done
shift $((OPTIND -1))

# Validate mode
if [ "$mode" != "iam" ] && [ "$mode" != "cleanup" ]; then
    echo "Error: Mode must be 'iam' or 'cleanup'."
    usage
fi

# Validate interactive
if [ "$interactive" != "true" ] && [ "$interactive" != "false" ]; then
    echo "Error: Interactive must be 'true' or 'false'."
    usage
fi

# Set default values if interactive is false
if [ "$interactive" == "false" ]; then

    app_choice="new"
    app_name="${PREFIX}app_${timestamp}"
    echo "Application name: $app_name"
    subs_ids="all"
    role_name="${PREFIX}role_${timestamp}"
    echo "Role name: $role_name"
fi

# Function to create a new Azure application
create_new_application() {
    if [ "$interactive" == "true" ]; then
        echo -e ""
        echo "Enter the name for the new Azure application(will be prefixed with $PREFIX):"
        read app_name

        if [ -z "$app_name" ]; then
            echo "Error: Application name cannot be empty."
            exit 1
        fi
        app_name="$PREFIX$app_name"
    fi

    # Create the Azure application
    app_output=$(az ad app create --display-name "$app_name" --query appId -o tsv)
    if [ $? -ne 0 ]; then
        echo "New application creation failed"
        exit 1
    fi

    app_id=$app_output
    new_application=true

    az ad sp create --id $app_id
    echo "Created a new Azure application: $app_id"
    # Create a secret for the new application
    create_secret_for_application $app_id
}

# Function to use an existing Azure application
use_existing_application() {
    echo "Fetching existing Azure applications..."
    az ad app list --query '[].{name:displayName, appId:appId}' --output table

    echo "Enter the App ID of the existing Azure application:"
    read existing_app_id

    if [ -z "$existing_app_id" ]; then
        echo "Error: Application ID cannot be empty."
        exit 1
    fi

    app_id=$existing_app_id

    az ad sp create --id $app_id

    # Create a secret for the existing application
    create_secret_for_application $app_id
}

# Function to create a secret for an Azure application
create_secret_for_application() {
    local app_id=$1

    # Create a secret for the application
    secret_output=$(az ad app credential reset --id $app_id --display-name "cisco_csw_secret" --query password -o tsv)
    if [ $? -ne 0 ]; then
        echo "Failed to create secret for application."
        cleanup=true
        exit 1
    fi

    client_secret=$secret_output
    #echo "Secret created for Azure application. Client Secret: $client_secret"
}

# Function to assign the role to the application in each subscription
assign_role_to_application() {
    local subs_ids=$1
    local app_id=$2
    local role_id=$3

    IFS=',' read -r -a subs_array <<< "$subs_ids"
    for sub_id in "${subs_array[@]}"; do
        echo "Assigning role to application in subscription $sub_id..."
        az role assignment create --assignee $app_id --role $role_id --scope "/subscriptions/$sub_id"
        if [ $? -ne 0 ]; then
            echo "Failed to assign role in subscription $sub_id."
            cleanup=true
            exit 1
        fi
        echo "Role assigned to application in subscription $sub_id"
    done
}

# Cleanup function
cleanup_resources() {
    if [ "$new_application" = true ]; then
        echo "Deleting newly created application with App ID: $app_id"
        az ad app delete --id $app_id
    fi

    if [ -z "$role_name" ]; then
        echo "Role name unavailable"
        exit 0
    fi

    # Retrieve the list of subscriptions.
    subscriptions=("c2f21153-dfdd-413b-afb2-411e7da24e37" "14c85a0f-cbe8-4ee2-b72c-d88499b75369" "2feee0b1-265e-4f07-bfb4-d826c1cf8438")

    ROLE_ASSIGNMENT_IDS=()
    # Retrieve the list of role assignment for each scope.
    for sub in $subscriptions; do
        ids=$(az role assignment list --scope "/subscriptions/$sub" --role "$role_name" --query "[].id" --output tsv)

        # Append each ID to the array
        for id in $ids; do
            az role assignment delete --ids "$id"
        done
    done

    echo $ROLE_ASSIGNMENT_IDS

    echo "All role assignments for role: $role_name have been deleted."

    if [ ! -z "$role_name" ]; then
        echo "Deleting custom role with Role ID: $role_name"
        az role definition delete --name $role_name
    fi
}

# Main logic based on mode
if [ "$mode" == "cleanup" ]; then
    echo -e "Enter application ID"
    read cleanup_app
    az ad app delete --id $cleanup_app
    echo -e "Enter role name"
    read role_name
    cleanup_resources
    echo -e "Cleanup finished."
    exit 0
elif [ "$mode" == "iam" ]; then
    echo -e "Setting up required iam resources..."
else
    echo "Invalid choice. Please run the script again and choose 'iam' or 'cleanup'."
    exit 1
fi

# Register provider
az provider register --namespace 'Microsoft.CloudShell'

# Set trap for cleanup on exit
trap 'if [ "$cleanup" = true ]; then cleanup_resources; fi' EXIT

# Ask the user if they want to create a new Azure application or use an existing one
if [ "$interactive" == "true" ]; then
    echo "Do you want to create a new Azure application or use an existing one? (new/existing):"
    read app_choice
    if [ -z "$app_choice" ]; then
        echo "Error: Choice cannot be empty."
        exit 1
    fi
fi

# Either create or input the name.
if [ "$app_choice" == "new" ]; then
    create_new_application
elif [ "$app_choice" == "existing" ]; then
    use_existing_application
else
    echo "Invalid choice. Please run the script again and choose 'new' or 'existing'."
    exit 1
fi

echo -e ""
# List all the subscriptions
echo "Fetching subscriptions..."
az account list --output table --query "[].{Name:name, ID:id}"
all_subs_ids="c2f21153-dfdd-413b-afb2-411e7da24e37,14c85a0f-cbe8-4ee2-b72c-d88499b75369,2feee0b1-265e-4f07-bfb4-d826c1cf8438"

# Input for required subscriptions.
if [ "$interactive" == "true" ]; then
    echo -e ""
    echo "Enter subscription IDs (comma-separated, with no spaces) that would be onboarded. To select all the subscriptions enter: all"
    read subs_ids
fi

if [ "$subs_ids" == "all" ]; then
    subs_ids=$all_subs_ids
fi

subscriptions=$(echo $subs_ids | tr ',' '\n' | sed 's/^/\/subscriptions\//' | jq -R . | jq -s .)

echo -e ""
# Input for required role name.
if [ "$interactive" == "true" ]; then
    echo "Enter role name(will be prefixed with $PREFIX):"
    read role_name
    if [ -z "$role_name" ]; then
        echo "Error: Role name cannot be empty."
        cleanup=true
        exit 1
    fi
    role_name="$PREFIX$role_name"
fi

# Generate role template
cat > /tmp/role.json <<- EOF
{
  "Name": "$role_name",
  "Description": "Cisco Secure Workload (CSW) generated policy.",
  "IsCustom": true,
  "AssignableScopes": $subscriptions,
  "Actions": [
          "Microsoft.Network/networkInterfaces/read",
          "Microsoft.Network/networkInterfaces/ipconfigurations/read",
          "Microsoft.Network/virtualNetworks/read",
          "Microsoft.Compute/virtualMachines/read",
          "Microsoft.Network/publicIPAddresses/read",
          "Microsoft.Compute/virtualMachineScaleSets/read",
          "Microsoft.Compute/virtualMachineScaleSets/networkInterfaces/read",
          "Microsoft.Compute/virtualMachineScaleSets/publicIPAddresses/read",
          "Microsoft.Compute/virtualMachineScaleSets/vmSizes/read",
          "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/read",
          "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/networkInterfaces/read",
          "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/networkInterfaces/ipConfigurations/publicIPAddresses/read",
          "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/networkInterfaces/ipConfigurations/read",
          "Microsoft.ContainerService/containerServices/read",
          "Microsoft.ContainerService/managedClusters/read",
          "Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action",
          "Microsoft.ContainerService/managedClusters/agentPools/read",
          "Microsoft.Network/virtualNetworks/subnets/read",
          "Microsoft.Network/networkWatchers/read",
          "Microsoft.Network/networkWatchers/flowLogs/read",
          "Microsoft.Network/networkWatchers/queryFlowLogStatus/action",
          "Microsoft.Storage/storageAccounts/listKeys/Action",
          "Microsoft.Storage/storageAccounts/Read",
          "Microsoft.Authorization/permissions/read",
          "Microsoft.Network/networkSecurityGroups/read",
          "Microsoft.Network/networkSecurityGroups/write",
          "Microsoft.Network/networkSecurityGroups/delete",
          "Microsoft.Network/networkSecurityGroups/join/action",
          "Microsoft.Network/networkInterfaces/write",
          "Microsoft.Network/virtualNetworks/subnets/write",
          "Microsoft.Network/virtualNetworks/subnets/join/action",
          "Microsoft.Network/networkWatchers/flowLogs/write",
          "Microsoft.Resources/subscriptions/resourceGroups/read",
          "Microsoft.Network/publicIPAddresses/join/action"
        ],
  "dataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
  ]
}
EOF

echo -e ""
# Create role
echo "Creating custom role from /tmp/role.json..."
role_output=$(az role definition create --role-definition /tmp/role.json --query id -o tsv)
if [ $? -ne 0 ]; then
    echo "Custom role creation failed"
    cleanup=true
    exit 1
fi

role_id=$role_output
echo -e ""
echo "Custom role created successfully with Role ID: $role_id"

echo "Application_ID: $app_id"
echo "Role_ID: $role_id"
echo "Role_Name: $role_name"

# Assign the custom role to the application in each subscription
assign_role_to_application "$subs_ids" "$app_id" "$role_id"

# Fetch the Tenant ID
tenant_id=$(az account show --query 'tenantId' -o tsv)

# Extract the first subscription ID
IFS=',' read -r -a subs_array <<< "$subs_ids"
first_subscription_id=${subs_array[0]}

echo
echo "-------------------------------------------------------"
echo "Credentials required to onboard Azure Connector !!"
echo "-------------------------------------------------------"
echo "Tenant_ID: $tenant_id"
echo "Subscription_ID: $first_subscription_id"
echo "Client_ID: $app_id"
echo "Client_Secret: $client_secret"
echo
echo "-------------------------------------------------------"
echo "Information required to initiate cleanup (Save it !!)"
echo "-------------------------------------------------------"
echo "Application ID: $app_id"
echo "Application Name": $app_name
echo "Role ID: $role_id"
echo "Role Name: $role_name"
echo "-------------------------------------------------------"
echo

# Reset cleanup flag if everything is successful
cleanup=false
