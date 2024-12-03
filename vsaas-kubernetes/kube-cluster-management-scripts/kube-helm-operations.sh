#!/bin/bash

display_help() {
  echo "Usage: $0 [command]"
  echo
  echo "Commands:"
  echo "  install   Install Helm"
  echo "  help      Display Helm help"
  echo "  version   Display Helm version"
  echo "  create    Create a new Helm chart"
  echo "  package   Package a Helm chart"
  echo "  lint      Lint a Helm chart"
  echo "  install   Install a Helm chart"
  echo "  upgrade   Upgrade a Helm release"
  echo "  rollback  Rollback a Helm release"
  echo "  uninstall Uninstall a Helm release"
  echo "  list      List Helm releases"
  echo "  repo      Manage Helm repositories"
  echo
}

install_helm() {
  if command -v helm &> /dev/null; then
    echo "Helm is already installed."
  else
    echo "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    echo "Helm installation completed."
  fi
}

create_chart() {
  read -p "Enter the name of the new chart: " chart_name
  helm create "$chart_name"
  echo "New Helm chart '$chart_name' created."
}

package_chart() {
  read -p "Enter the path to the chart directory: " chart_path
  helm package "$chart_path"
  echo "Helm chart packaged."
}

lint_chart() {
  read -p "Enter the path to the chart directory: " chart_path
  helm lint "$chart_path"
}

install_chart() {
  read -p "Enter the name of the release: " release_name
  read -p "Enter the chart reference (e.g., repo/chart): " chart_ref
  helm install "$release_name" "$chart_ref"
  echo "Helm chart installed."
}

upgrade_release() {
  read -p "Enter the name of the release to upgrade: " release_name
  read -p "Enter the chart reference (e.g., repo/chart): " chart_ref
  helm upgrade "$release_name" "$chart_ref"
  echo "Helm release upgraded."
}

rollback_release() {
  read -p "Enter the name of the release to rollback: " release_name
  read -p "Enter the revision to rollback to: " revision
  helm rollback "$release_name" "$revision"
  echo "Helm release rolled back."
}

uninstall_release() {
  read -p "Enter the name of the release to uninstall: " release_name
  helm uninstall "$release_name"
  echo "Helm release uninstalled."
}

list_releases() {
  helm list
}

manage_repos() {
  echo "Helm Repository Management"
  echo "1. Add a new repository"
  echo "2. Update repository information"
  echo "3. Remove a repository"
  echo "4. List repositories"
  read -p "Enter your choice (1-4): " choice

  case $choice in
    1)
      read -p "Enter the repository name: " repo_name
      read -p "Enter the repository URL: " repo_url
      helm repo add "$repo_name" "$repo_url"
      echo "Repository added."
      ;;
    2)
      helm repo update
      echo "Repository information updated."
      ;;
    3)
      read -p "Enter the repository name to remove: " repo_name
      helm repo remove "$repo_name"
      echo "Repository removed."
      ;;
    4)
      helm repo list
      ;;
    *)
      echo "Invalid choice. Please try again."
      ;;
  esac
}

if [[ $# -eq 0 ]]; then
  display_help
else
  case $1 in
    install)
      install_helm
      ;;
    help)
      helm --help
      ;;
    version)
      helm version
      ;;
    create)
      create_chart
      ;;
    package)
      package_chart
      ;;
    lint)
      lint_chart
      ;;
    install)
      install_chart
      ;;
    upgrade)
      upgrade_release
      ;;
    rollback)
      rollback_release
      ;;
    uninstall)
      uninstall_release
      ;;
    list)
      list_releases
      ;;
    repo)
      manage_repos
      ;;
    *)
      echo "Invalid command. Use '$0 help' for available commands."
      ;;
  esac
fi