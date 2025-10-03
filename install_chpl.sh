
validate_args() {
  local chpl_version=$1
  local chpl_comm=$2
  local chpl_backend=$3

  export CHPL_USE_OLD_PACKAGES=0
  export CHPL_REAL_VERSION=$chpl_version
  case "$chpl_version" in
    latest)
      export CHPL_REAL_VERSION=2.6.0
      ;;
    nightly)
      echo "Error: nightly builds not yet implemented"
      exit 1
      ;;
    2.5.0)
      export CHPL_USE_OLD_PACKAGES=1
      ;;
    2.6.0)
      ;;
    *)
      echo "Error: unsupported Chapel version: $chpl_version"
      exit 1
      ;;
  esac

  case "$chpl_comm" in
    none|gasnet-udp)
      ;;
    gasnet-smp)
      echo "Error: gasnet-smp not yet supported"
      exit 1
      ;;
    *)
      echo "Error: unsupported Chapel communication layer: $chpl_comm"
      exit 1
      ;;
  esac

  case "$chpl_backend" in
    clang|llvm)
      ;;
    gnu)
      echo "Error: gnu backend not yet supported"
      exit 1
      ;;
    *)
      echo "Error: unsupported Chapel backend compiler: $chpl_backend"
      exit 1
      ;;
  esac

  if [ $CHPL_USE_OLD_PACKAGES -eq 1 ] && [ "$chpl_backend" != "llvm" ]; then
    echo "Error: only llvm backend is supported for Chapel version $chpl_version"
    exit 1
  fi
  if [ $CHPL_USE_OLD_PACKAGES -eq 1 ] && [ "$chpl_comm" != "none" ]; then
    echo "Error: only none communication layer is supported for Chapel version $chpl_version"
    exit 1
  fi

}


determine_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "darwin"
  elif [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID-$VERSION_ID" in
      "fedora-"*) echo "fedora${VERSION_ID}" ;;
      "debian-"*) echo "debian${VERSION_ID}" ;;
      "ubuntu-24."*) echo "ubuntu24" ;;
      "ubuntu-22."*) echo "ubuntu22" ;;
      "rocky-"*) echo "el${VERSION_ID}" ;;
      "almalinux-"*) echo "el${VERSION_ID}" ;;
      "rhel-"*) echo "el${VERSION_ID}" ;;
      *) echo "Error: unknown OS: $ID-$VERSION_ID"; exit 1 ;;
    esac
  else
    echo "Error: unable to determine OS type"
    exit 1
  fi
}

determine_pkg_suffix() {
  local os_suffix=$1
  case "$os_suffix" in
    fedora*|el*) echo "rpm" ;;
    debian*|ubuntu*) echo "deb" ;;
    *) echo "Error: unknown OS suffix: $os_suffix"; exit 1 ;;
  esac
}
normalized_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *) echo "Error: unsupported architecture: $(uname -m)"; exit 1 ;;
  esac
}
determine_arch_suffix() {
  local os_suffix=$1
  
  case "$os_suffix" in
    fedora*|el*) echo $(normalized_arch) ;;
    debian*|ubuntu*)
      case "$(normalized_arch)" in
        x86_64) echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) echo "Error: unsupported architecture: $(uname -m)"; exit 1 ;;
      esac
      ;;
    *) echo "Error: unknown OS suffix: $os_suffix"; exit 1 ;;
  esac
}
package_install() {
  local os_suffix=$1
  local pkg_file=$2
  case "$os_suffix" in
    fedora*|el*)
      sudo dnf install -y $pkg_file || exit 1
      ;;
    debian*|ubuntu*)
      sudo apt-get update || exit 1
      sudo apt-get install -y $pkg_file || exit 1
      ;;
    *) echo "Error: unknown OS suffix: $os_suffix"; exit 1 ;;
  esac
}

install_chpl() {
  local chpl_version=$1
  local chpl_comm=$2
  local chpl_backend=$3

  validate_args $chpl_version $chpl_comm $chpl_backend
  set_chpl_env_vars $chpl_version $chpl_comm $chpl_backend


  OS_SUFFIX=$(determine_os)

  # TODO: use brew
  if [ "$OS_SUFFIX" = "darwin" ]; then
    echo "Error: prebuilt Chapel binaries not yet available for macOS"
    exit 1
  fi


  local pkg_suffix=$(determine_pkg_suffix $OS_SUFFIX)
  local arch_suffix=$(determine_arch_suffix $OS_SUFFIX)
  curl -L -o chapel.$pkg_suffix https://github.com/chapel-lang/chapel/releases/download/$CHPL_REAL_VERSION/chapel-$CHPL_REAL_VERSION-1.$OS_SUFFIX.$arch_suffix.$pkg_suffix
  if [ $? -ne 0 ]; then
    echo "Error: failed to download Chapel package"
    exit 1
  fi
  package_install $OS_SUFFIX ./chapel.$pkg_suffix


  set_github_env $chpl_version $chpl_comm $chpl_backend
  set_github_output $chpl_version $chpl_comm $chpl_backend
}

set_chpl_env_vars() {
  local chpl_version=$1
  local chpl_comm=$2
  local chpl_backend=$3

  export CHPL_ENV_VARS=$(mktemp)

  if [ "$chpl_comm" = "none" ]; then
    echo "CHPL_COMM=none" >> $CHPL_ENV_VARS
  else
    local comm_substrate=${chpl_comm#gasnet-}
    echo "CHPL_COMM=gasnet" >> $CHPL_ENV_VARS
    echo "CHPL_COMM_SUBSTRATE=$comm_substrate" >> $CHPL_ENV_VARS
  fi
  echo "CHPL_TARGET_COMPILER=$chpl_backend" >> $CHPL_ENV_VARS

  export $(cat $CHPL_ENV_VARS | xargs)
}
set_github_env() {
  cat $CHPL_ENV_VARS >> $GITHUB_ENV 
}
set_github_output() {
  local chpl_version=$1
  local chpl_comm=$2
  local chpl_backend=$3
  echo "chpl=$(which chpl)" >> $GITHUB_OUTPUT
  echo "chpldoc=$(which chpldoc)" >> $GITHUB_OUTPUT
  echo "chplcheck=$(which chplcheck)" >> $GITHUB_OUTPUT
  echo "mason=$(which mason)" >> $GITHUB_OUTPUT
  echo "chpl_home=$(chpl --print-chpl-home)" >> $GITHUB_OUTPUT
}
