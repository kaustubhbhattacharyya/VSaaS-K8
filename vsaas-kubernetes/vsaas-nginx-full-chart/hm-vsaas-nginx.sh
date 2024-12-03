chart_name="vsaas-nginx"
namespace="vsaas-dev"
chart_folder="vsaas-nginx"


display_help() {
  echo "Usage: $0 [command]"
  echo
  echo "Commands:"
  echo "  install   Install the $chart_name Helm chart"
  echo "  upgrade   Upgrade the $chart_name Helm release"
  echo "  rollback  Rollback the $chart_name Helm release"
  echo "  uninstall Uninstall the $chart_name Helm release"
  echo "  status    Display the status of the $chart_name Helm release"
  echo "  values    Display the configured values of the $chart_name Helm release"
  echo "  help      Display this help message"
  echo
}


uninstall_existing_release() {
  if helm status "$chart_name" --namespace "$namespace" >/dev/null 2>&1; then
    echo "Uninstalling the existing '$chart_name' release..."
    helm uninstall "$chart_name" --namespace "$namespace"
    echo "Existing '$chart_name' release uninstalled."
  else
    echo "No existing '$chart_name' release found."
  fi
}


install_chart() {
  uninstall_existing_release
  echo "Installing the '$chart_name' Helm chart..."
  helm install "$chart_name" "$chart_folder" --namespace "$namespace"
  echo "Helm chart '$chart_name' installed in the '$namespace' namespace."
}


upgrade_release() {
  helm upgrade "$chart_name" "$chart_folder" --namespace "$namespace"
  echo "Helm release '$chart_name' upgraded in the '$namespace' namespace."
}


rollback_release() {
  read -p "Enter the revision to rollback to: " revision
  helm rollback "$chart_name" "$revision" --namespace "$namespace"
  echo "Helm release '$chart_name' rolled back in the '$namespace' namespace."
}


uninstall_release() {
  helm uninstall "$chart_name" --namespace "$namespace"
  echo "Helm release '$chart_name' uninstalled from the '$namespace' namespace."
}


display_status() {
  helm status "$chart_name" --namespace "$namespace"
}


display_values() {
  helm get values "$chart_name" --namespace "$namespace"
}


if [[ $
  display_help
else
  case $1 in
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
    status)
      display_status
      ;;
    values)
      display_values
      ;;
    help)
      display_help
      ;;
    *)
      echo "Invalid command. Use '$0 help' for available commands."
      ;;
  esac
fi