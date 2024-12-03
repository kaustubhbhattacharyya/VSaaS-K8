#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

###############################################################################
# Prints the script header with formatting
# Arguments:
#   None
# Outputs:
#   Writes formatted header to stdout
###############################################################################
print_header() {
    echo -e "${GREEN}================================================"
    echo -e "          Helm Installation Script"
    echo -e "================================================${NC}"
}

###############################################################################
# Updates help menu to include helmfile options
# Arguments:
#   None
# Outputs:
#   Updated help menu
###############################################################################
print_help() {
    echo -e "${YELLOW}Usage: $0 [OPTIONS]"
    echo -e "\nOptions:"
    echo -e "  -h,  --help               Display this help message"
    echo -e "  -i,  --install            Install Helm"
    echo -e "  -if, --install-helmfile   Install Helmfile"
    echo -e "  -ia, --install-all        Install both Helm and Helmfile"
    echo -e "  -u,  --uninstall          Uninstall Helm"
    echo -e "  -uf, --uninstall-helmfile Uninstall Helmfile"
    echo -e "  -ua, --uninstall-all      Uninstall both Helm and Helmfile"
    echo -e "  -c,  --check              Check installations"
    echo -e "\nExample:"
    echo -e "  $0 --install              Install Helm"
    echo -e "  $0 --install-helmfile     Install Helmfile"
    echo -e "  $0 --install-all          Install both tools"
    echo -e "  $0 --check                Check installations${NC}"
}

###############################################################################
# Checks if a command exists in the system
# Arguments:
#   $1 - Command to check
# Returns:
#   0 if command exists, 1 if it doesn't
###############################################################################
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

###############################################################################
# Verifies sudo privileges and sudo installation
# Arguments:
#   None
# Outputs:
#   Error message if sudo is not installed
#   Warning message if sudo password might be required
# Returns:
#   0 if sudo is available, 1 if not installed
###############################################################################
check_sudo() {
    if ! command_exists sudo; then
        echo -e "${RED}Error: sudo is not installed. Please install sudo first.${NC}"
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}Please enter your sudo password when prompted.${NC}"
    fi
}

###############################################################################
# Checks and installs required system packages
# Arguments:
#   None
# Outputs:
#   Status messages about package installation
# Dependencies:
#   apt-get, sudo
###############################################################################
check_requirements() {
    echo -e "${GREEN}Checking system requirements...${NC}"
    
    # Check if curl is installed
    if ! command_exists curl; then
        echo -e "${YELLOW}Installing curl...${NC}"
        sudo apt-get update
        sudo apt-get install -y curl
    fi
    
    # Check if apt-transport-https is installed
    if ! command_exists apt-transport-https; then
        echo -e "${YELLOW}Installing apt-transport-https...${NC}"
        sudo apt-get install -y apt-transport-https
    fi
}

###############################################################################
# Installs Helm package manager
# Arguments:
#   None
# Outputs:
#   Installation progress and status messages
# Dependencies:
#   curl, apt-get, gpg
# Notes:
#   - Requires sudo privileges
#   - Will prompt for reinstallation if Helm is already installed
###############################################################################
install_helm() {
    print_header
    echo -e "${GREEN}Starting Helm installation...${NC}"
    
    # Check requirements
    check_sudo
    check_requirements
    
    # Check if Helm is already installed
    if command_exists helm; then
        echo -e "${YELLOW}Helm is already installed. Version: $(helm version --short)${NC}"
        read -p "Do you want to reinstall? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}Installation cancelled.${NC}"
            exit 0
        fi
    fi
    
    echo -e "${GREEN}Adding Helm repository and GPG key...${NC}"
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    
    echo -e "${GREEN}Adding Helm repository to sources list...${NC}"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    
    echo -e "${GREEN}Updating package list...${NC}"
    sudo apt-get update
    
    echo -e "${GREEN}Installing Helm...${NC}"
    sudo apt-get install -y helm
    
    # Verify installation
    if command_exists helm; then
        echo -e "${GREEN}Helm installation completed successfully!"
        echo -e "Helm version: $(helm version --short)${NC}"
        
        # Initialize Helm
        echo -e "${GREEN}Initializing Helm...${NC}"
        helm repo add stable https://charts.helm.sh/stable
        helm repo update
        
        # Set correct permissions
        sudo chown -R $USER:$USER ~/.config/helm 2>/dev/null || true
    else
        echo -e "${RED}Error: Helm installation failed!${NC}"
        exit 1
    fi
}

###############################################################################
# Uninstalls Helm and removes all related configurations
# Arguments:
#   None
# Outputs:
#   Uninstallation progress and status messages
# Dependencies:
#   apt-get, sudo
# Notes:
#   - Requires confirmation before uninstallation
#   - Removes all Helm configurations and repositories
###############################################################################
uninstall_helm() {
    print_header
    echo -e "${YELLOW}Starting Helm uninstallation...${NC}"
    
    # Check if Helm is installed
    if ! command_exists helm; then
        echo -e "${RED}Helm is not installed.${NC}"
        exit 1
    fi
    
    # Confirm uninstallation
    read -p "Are you sure you want to uninstall Helm? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Uninstallation cancelled.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Removing Helm...${NC}"
    sudo apt-get remove -y helm
    sudo apt-get autoremove -y
    
    echo -e "${YELLOW}Removing Helm configuration files...${NC}"
    rm -rf ~/.helm
    rm -rf ~/.config/helm
    sudo rm -f /etc/apt/sources.list.d/helm-stable-debian.list
    sudo rm -f /usr/share/keyrings/helm.gpg
    
    echo -e "${GREEN}Helm has been successfully uninstalled.${NC}"
}

###############################################################################
# Installs Helmfile with proper binary download and verification
# Arguments:
#   None
# Outputs:
#   Installation progress and status messages
# Dependencies:
#   curl, sudo
###############################################################################
install_helmfile() {
    print_header
    echo -e "${GREEN}Starting Helmfile installation...${NC}"
    
    # Check requirements
    check_sudo
    check_requirements
    
    # Remove existing helmfile if present
    if [ -f "/usr/local/bin/helmfile" ]; then
        echo -e "${YELLOW}Removing existing Helmfile...${NC}"
        sudo rm -f /usr/local/bin/helmfile
    fi
    
    # Get latest version
    echo -e "${GREEN}Getting latest Helmfile version...${NC}"
    local latest_version=$(curl -s https://api.github.com/repos/helmfile/helmfile/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    
    if [ -z "$latest_version" ]; then
        echo -e "${RED}Failed to get latest version. Using default version 0.158.1${NC}"
        latest_version="0.158.1"
    fi
    
    echo -e "${GREEN}Installing Helmfile version ${latest_version}...${NC}"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || {
        echo -e "${RED}Failed to create temporary directory${NC}"
        return 1
    }
    
    # Download Helmfile
    local download_url="https://github.com/helmfile/helmfile/releases/download/v${latest_version}/helmfile_${latest_version}_linux_amd64.tar.gz"
    echo -e "${GREEN}Downloading from: ${download_url}${NC}"
    
    if ! curl -LO "$download_url"; then
        echo -e "${RED}Failed to download Helmfile${NC}"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract the archive
    if ! tar xzf "helmfile_${latest_version}_linux_amd64.tar.gz"; then
        echo -e "${RED}Failed to extract Helmfile archive${NC}"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Install the binary
    echo -e "${GREEN}Installing Helmfile binary...${NC}"
    chmod +x helmfile
    if ! sudo mv helmfile /usr/local/bin/; then
        echo -e "${RED}Failed to install Helmfile binary${NC}"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    # Verify installation
    echo -e "${GREEN}Verifying installation...${NC}"
    if ! helmfile -v; then
        echo -e "${RED}Helmfile installation verification failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Helmfile installation completed successfully!${NC}"
    return 0
}

###############################################################################
# Verifies Helmfile installation
# Arguments:
#   None
# Returns:
#   0 if verification succeeds, 1 if it fails
###############################################################################
verify_helmfile() {
    echo -e "${GREEN}Verifying Helmfile installation...${NC}"
    
    # Check if binary exists
    if [ ! -f "/usr/local/bin/helmfile" ]; then
        echo -e "${RED}Helmfile binary not found${NC}"
        return 1
    fi
    
    # Check if binary is executable
    if [ ! -x "/usr/local/bin/helmfile" ]; then
        echo -e "${RED}Helmfile binary is not executable${NC}"
        return 1
    fi
    
    # Check version output
    if ! helmfile -v &>/dev/null; then
        echo -e "${RED}Helmfile version check failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Helmfile verification successful${NC}"
    return 0
}

###############################################################################
# Alternative manual installation if automatic fails
# Arguments:
#   None
# Returns:
#   0 if installation succeeds, 1 if it fails
###############################################################################
manual_install_helmfile() {
    echo -e "${YELLOW}Attempting manual installation...${NC}"
    
    local version="0.158.1"
    local binary_url="https://github.com/helmfile/helmfile/releases/download/v${version}/helmfile_linux_amd64"
    
    # Download binary directly
    if ! curl -Lo helmfile "$binary_url"; then
        echo -e "${RED}Failed to download Helmfile binary${NC}"
        return 1
    fi
    
    chmod +x helmfile
    if ! sudo mv helmfile /usr/local/bin/; then
        echo -e "${RED}Failed to install Helmfile binary${NC}"
        return 1
    fi
    
    # Verify installation
    if ! verify_helmfile; then
        echo -e "${RED}Manual installation verification failed${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Manual installation completed successfully!${NC}"
    return 0
}

###############################################################################
# Uninstalls Helmfile
# Arguments:
#   None
# Outputs:
#   Uninstallation progress and status messages
###############################################################################
uninstall_helmfile() {
    print_header
    echo -e "${YELLOW}Starting Helmfile uninstallation...${NC}"
    
    # Check if Helmfile is installed
    if ! command_exists helmfile; then
        echo -e "${RED}Helmfile is not installed.${NC}"
        return 1
    fi
    
    # Confirm uninstallation
    read -p "Are you sure you want to uninstall Helmfile? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Uninstallation cancelled.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Removing Helmfile...${NC}"
    sudo rm -f /usr/local/bin/helmfile
    
    echo -e "${GREEN}Helmfile has been successfully uninstalled.${NC}"
}

###############################################################################
# Installs both Helm and Helmfile
# Arguments:
#   None
# Outputs:
#   Installation progress and status messages
###############################################################################
install_all() {
    print_header
    echo -e "${GREEN}Installing Helm and Helmfile...${NC}"
    
    # Install Helm
    install_helm || {
        echo -e "${RED}Helm installation failed!${NC}"
        return 1
    }
    
    # Install Helmfile
    install_helmfile || {
        echo -e "${RED}Helmfile installation failed!${NC}"
        return 1
    }
    
    echo -e "${GREEN}Both Helm and Helmfile installed successfully!${NC}"
}

###############################################################################
# Uninstalls both Helm and Helmfile
# Arguments:
#   None
# Outputs:
#   Uninstallation progress and status messages
###############################################################################
uninstall_all() {
    print_header
    echo -e "${YELLOW}Uninstalling Helm and Helmfile...${NC}"
    
    # Uninstall Helm
    uninstall_helm
    
    # Uninstall Helmfile
    uninstall_helmfile
    
    echo -e "${GREEN}Both Helm and Helmfile uninstalled successfully!${NC}"
}

###############################################################################
# Checks installation status of both Helm and Helmfile
# Arguments:
#   None
# Outputs:
#   Installation status and version information
###############################################################################
check_installations() {
    print_header
    echo -e "${GREEN}Checking installations...${NC}"
    
    # Check Helm
    echo -e "\n${YELLOW}Helm Status:${NC}"
    if command_exists helm; then
        echo -e "${GREEN}Helm is installed${NC}"
        echo "Version: $(helm version --short)"
        echo -e "\nHelm repositories:"
        helm repo list
    else
        echo -e "${RED}Helm is not installed${NC}"
    fi
    
    # Check Helmfile
    echo -e "\n${YELLOW}Helmfile Status:${NC}"
    if command_exists helmfile; then
        echo -e "${GREEN}Helmfile is installed${NC}"
        echo "Version: $(helmfile --version)"
    else
        echo -e "${RED}Helmfile is not installed${NC}"
    fi
}

###############################################################################
# Checks Helm installation status and configuration
# Arguments:
#   None
# Outputs:
#   Helm version, repository list, and configuration status
# Notes:
#   - Displays detailed information about the Helm installation
#   - Shows repository list if Helm is installed
###############################################################################
check_helm() {
    print_header
    echo -e "${GREEN}Checking Helm installation...${NC}"
    
    if command_exists helm; then
        echo -e "${GREEN}Helm is installed.${NC}"
        echo -e "Version: $(helm version --short)"
        echo -e "\nHelm repositories:"
        helm repo list
        echo -e "\nHelm configuration:"
        ls -la ~/.config/helm 2>/dev/null || echo "No Helm configuration directory found."
    else
        echo -e "${RED}Helm is not installed.${NC}"
        exit 1
    fi
}

###############################################################################
# Main script execution
# Process command line arguments and execute appropriate function
###############################################################################
case "$1" in
    -h|--help)
        print_help
        ;;
    -i|--install)
        install_helm
        ;;
    -if|--install-helmfile)
        install_helmfile
        ;;
    -ia|--install-all)
        install_all
        ;;
    -u|--uninstall)
        uninstall_helm
        ;;
    -uf|--uninstall-helmfile)
        uninstall_helmfile
        ;;
    -ua|--uninstall-all)
        uninstall_all
        ;;
    -c|--check)
        check_installations
        ;;
    *)
        echo -e "${RED}Error: Invalid option${NC}"
        print_help
        exit 1
        ;;
esac