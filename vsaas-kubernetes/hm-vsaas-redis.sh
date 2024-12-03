#!/bin/bash

function display_help() {
    echo "Usage: $0 -e [environment] -a [action]"
    echo ""
    echo "Options:"
    echo "  -e, --environment   Specify the environment (dev, prod, or staging)"
    echo "  -a, --action        Specify the action to perform (install, upgrade, uninstall, status, cleanup)"
    echo "  -h, --help          Display this help message"
}

function log_message() {
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1"
}

function set_environment_variables() {
    case "$1" in
        dev)
            NAMESPACE="vsaas-dev"
            RELEASE_NAME="vsaas-redis-dev"
            ;;
        prod)
            NAMESPACE="vsaas-prod"
            RELEASE_NAME="vsaas-redis-prod"
            ;;
        staging)
            NAMESPACE="vsaas-staging"
            RELEASE_NAME="vsaas-redis-staging"
            ;;
        *)
            log_message "Invalid environment specified. Please choose from: dev, prod, or staging."
            exit 1
            ;;
    esac
    
    CHART_FOLDER="./vsaas-redis"
}

function install_chart() {
    log_message "Installing Redis Helm chart in $1 environment..."
    helm install $RELEASE_NAME $CHART_FOLDER --namespace $NAMESPACE
    log_message "Redis Helm chart installed successfully in $1 environment."
}

function upgrade_chart() {
    log_message "Upgrading Redis Helm chart in $1 environment..."
    helm upgrade $RELEASE_NAME $CHART_FOLDER --namespace $NAMESPACE
    log_message "Redis Helm chart upgraded successfully in $1 environment."
}

function uninstall_chart() {
    log_message "Uninstalling Redis Helm chart from $1 environment..."
    helm uninstall $RELEASE_NAME --namespace $NAMESPACE
    log_message "Redis Helm chart uninstalled successfully from $1 environment."
}

function display_status() {
    log_message "Displaying status of Redis Helm release in $1 environment..."
    helm status $RELEASE_NAME --namespace $NAMESPACE
}

function cleanup_releases() {
    log_message "Cleaning up failed or pending Helm releases in $1 environment..."
    helm list --pending --failed --namespace $NAMESPACE | tail -n +2 | awk '{print $1}' | xargs -I {} helm uninstall {} --namespace $NAMESPACE
    log_message "Cleanup completed successfully in $1 environment."
}

while getopts ":e:a:h" opt; do
    case ${opt} in
        e )
            ENVIRONMENT=$OPTARG
            ;;
        a )
            ACTION=$OPTARG
            ;;
        h )
            display_help
            exit 0
            ;;
        \? )
            echo "Invalid option: $OPTARG" 1>&2
            display_help
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

if [ -z "$ENVIRONMENT" ]; then
    echo "Environment not specified. Please provide the -e or --environment option."
    display_help
    exit 1
fi

set_environment_variables $ENVIRONMENT

case "$ACTION" in
    install)
        install_chart $ENVIRONMENT
        ;;
    upgrade)
        upgrade_chart $ENVIRONMENT
        ;;
    uninstall)
        uninstall_chart $ENVIRONMENT
        ;;
    status)
        display_status $ENVIRONMENT
        ;;
    cleanup)
        cleanup_releases $ENVIRONMENT
        ;;
    *)
        echo "Invalid action specified. Please provide a valid action using the -a or --action option."
        display_help
        exit 1
        ;;
esac