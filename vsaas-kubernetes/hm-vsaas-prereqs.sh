#!/bin/bash

if [[ -t 1 ]]; then
    BOLD=$(tput bold)
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    NC=$(tput sgr0)
else
    BOLD=""
    GREEN=""
    RED=""
    YELLOW=""
    NC=""
fi


PREREQUISITES_DIR="vsaas-prerequisites"
TEMPLATES_DIR="${PREREQUISITES_DIR}/templates"
SCRIPT_NAME=$(basename "$0")


show_help() {
    printf "%s\n" "${BOLD}NAME${NC}"
    printf "    %s - Manage VSaaS prerequisites installation and cleanup\n\n" "$SCRIPT_NAME"

    printf "%s\n" "${BOLD}SYNOPSIS${NC}"
    printf "    %s COMMAND [OPTIONS]\n\n" "$SCRIPT_NAME"

    printf "%s\n" "${BOLD}DESCRIPTION${NC}"
    printf "    A script to manage the installation and cleanup of VSaaS prerequisites using Helm.\n"
    printf "    It handles installation and cleanup of all components in the templates directory.\n\n"

    printf "%s\n" "${BOLD}COMMANDS${NC}"
    printf "    %sinstall%s\n" "${GREEN}" "${NC}"
    printf "        Install all prerequisites components from the templates directory.\n\n"
    
    printf "    %scleanup%s\n" "${GREEN}" "${NC}"
    printf "        Remove all installed prerequisites components.\n\n"
    
    printf "    %slist%s\n" "${GREEN}" "${NC}"
    printf "        Display all discovered components.\n\n"
    
    printf "    %shelp%s\n" "${GREEN}" "${NC}"
    printf "        Display this help message.\n\n"

    printf "%s\n" "${BOLD}DIRECTORY STRUCTURE${NC}"
    printf "    The script expects the following directory structure:\n"
    printf "    %s/\n" "$PREREQUISITES_DIR"
    printf "    ├── templates/           # Directory containing all component templates\n"
    printf "    ├── Chart.yaml          # Main Helm chart file\n"
    printf "    └── values.yaml         # Main values file (optional)\n\n"

    printf "%s\n" "${BOLD}EXAMPLES${NC}"
    printf "    1. List all available components:\n"
    printf "       $ %s list\n\n" "$SCRIPT_NAME"
    printf "    2. Install all prerequisites:\n"
    printf "       $ %s install\n\n" "$SCRIPT_NAME"
    printf "    3. Clean up all installed components:\n"
    printf "       $ %s cleanup\n\n" "$SCRIPT_NAME"

    printf "%s\n" "${BOLD}REQUIREMENTS${NC}"
    printf "    - kubectl: Kubernetes command-line tool\n"
    printf "    - helm: Kubernetes package manager\n\n"

    printf "%s\n" "${BOLD}EXIT STATUS${NC}"
    printf "    0   Success\n"
    printf "    1   General error\n"
    printf "    2   Invalid command\n"
}


log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


check_command() {
    if ! command -v $1 &> /dev/null; then
        error "$1 is required but not installed."
        exit 1
    fi
}


validate_prerequisites() {
    if [ ! -d "$PREREQUISITES_DIR" ]; then
        error "Prerequisites directory not found: $PREREQUISITES_DIR"
        exit 1
    fi

    if [ ! -f "$PREREQUISITES_DIR/Chart.yaml" ]; then
        error "Chart.yaml not found in $PREREQUISITES_DIR"
        exit 1
    fi

    if [ ! -d "$TEMPLATES_DIR" ]; then
        error "Templates directory not found: $TEMPLATES_DIR"
        exit 1
    fi
}


discover_components() {
    local components=()
    if [ -d "$TEMPLATES_DIR" ]; then
        for dir in "$TEMPLATES_DIR"/*/ ; do
            if [ -d "$dir" ]; then
                component=$(basename "$dir")
                components+=("$component")
            fi
        done
    fi
    echo "${components[@]}"
}


install_all() {
    log "Starting installation of all components..."
    
    local values_flag=""
    if [ -f "$PREREQUISITES_DIR/values.yaml" ]; then
        values_flag="-f $PREREQUISITES_DIR/values.yaml"
    fi

    helm upgrade --install vsaas-prerequisites ./$PREREQUISITES_DIR $values_flag || {
        error "Installation failed"
        exit 1
    }
    
    log "All components installed successfully"
}


cleanup() {
    log "Starting cleanup..."
    
    helm uninstall vsaas-prerequisites 2>/dev/null || {
        warn "vsaas-prerequisites not found or already uninstalled"
    }
    
    log "Cleanup completed"
}


list_components() {
    log "Discovering components in $TEMPLATES_DIR..."
    IFS=' ' read -r -a components <<< $(discover_components)
    
    if [ ${#components[@]} -eq 0 ]; then
        warn "No components found in templates directory"
        return
    fi

    printf "\nFound components:\n"
    printf "%-20s\n" "COMPONENT"
    printf "%-20s\n" "---------"
    for component in "${components[@]}"; do
        printf "%-20s\n" "$component"
    done
}


print_banner() {
    echo -e "${BOLD}"
    echo '┌─╼ VSAAS PREREQUISITES ╾─┐'
    echo -e "${NC}"
    echo -e "${GREEN}VSaaS Prerequisites Installation Script${NC}"
    echo -e "${GREEN}=====================================${NC}\n"
}

check_command kubectl
check_command helm
validate_prerequisites

case "$1" in
    "install")
        print_banner
        install_all
        ;;
    "cleanup")
        print_banner
        cleanup
        ;;
    "list")
        list_components
        ;;
    "help"|"-h"|"--help")
        print_banner
        show_help
        ;;
    *)
        error "Invalid command: $1"
        echo "Run '$SCRIPT_NAME help' for usage information"
        exit 2
        ;;
esac