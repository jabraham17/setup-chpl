
mysudo() {
  if [ "$(id -u)" -ne 0 ]; then
    sudo "$@"
  else
    "$@"
  fi
}

get_chapel_versions() {
  git ls-remote --tags https://github.com/chapel-lang/chapel.git 2>/dev/null \
    | grep -oE 'refs/tags/[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's|refs/tags/||' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | uniq
}

# Returns 0 (true) if $1 >= $2, 1 (false) otherwise
version_ge() {
  local v1_major v1_minor v1_patch v2_major v2_minor v2_patch
  IFS='.' read -r v1_major v1_minor v1_patch <<< "$1"
  IFS='.' read -r v2_major v2_minor v2_patch <<< "$2"
  if [ "$v1_major" -gt "$v2_major" ]; then return 0; fi
  if [ "$v1_major" -lt "$v2_major" ]; then return 1; fi
  if [ "$v1_minor" -gt "$v2_minor" ]; then return 0; fi
  if [ "$v1_minor" -lt "$v2_minor" ]; then return 1; fi
  if [ "$v1_patch" -ge "$v2_patch" ]; then return 0; fi
  return 1
}

validate_args() {
  local chpl_version=$1
  local chpl_comm=$2
  local chpl_backend=$3

  export CHPL_USE_OLD_PACKAGES=0

  # Fetch all available versions from chapel-lang
  local all_versions
  all_versions=$(get_chapel_versions)
  if [ -z "$all_versions" ]; then
    echo "Error: failed to fetch Chapel versions from chapel-lang"
    exit 1
  fi

  case "$chpl_version" in
    latest)
      export CHPL_REAL_VERSION=$(echo "$all_versions" | tail -1)
      ;;
    nightly)
      echo "Error: nightly builds not yet implemented"
      exit 1
      ;;
    *)
      export CHPL_REAL_VERSION=$chpl_version
      ;;
  esac

  # Validate version exists on chapel-lang
  if ! echo "$all_versions" | grep -qx "$CHPL_REAL_VERSION"; then
    echo "Error: Chapel version $CHPL_REAL_VERSION does not exist on chapel-lang"
    exit 1
  fi

  # Check minimum version
  if ! version_ge "$CHPL_REAL_VERSION" "2.1.0"; then
    echo "Error: Chapel version $CHPL_REAL_VERSION is less than minimum supported version 2.1.0"
    exit 1
  fi

  # Versions < 2.6.0 use old package format
  if ! version_ge "$CHPL_REAL_VERSION" "2.6.0"; then
    export CHPL_USE_OLD_PACKAGES=1
  fi

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
      "fedora-"*) echo "fc${VERSION_ID}" ;;
      "debian-"*) echo "debian${VERSION_ID}" ;;
      "ubuntu-24."*) echo "ubuntu24" ;;
      "ubuntu-22."*) echo "ubuntu22" ;;
      "rocky-10"*|"almalinux-10"*|"rhel-10"*) echo "el10" ;;
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
    fc*|el*) echo "rpm" ;;
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
    fc*|el*) echo $(normalized_arch) ;;
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
    fc*|el*)
      mysudo dnf install -y $pkg_file || exit 1
      ;;
    debian*|ubuntu*)
      mysudo apt-get update || exit 1
      mysudo apt-get install -y $pkg_file || exit 1
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

  package_install $OS_SUFFIX curl


  local pkg_suffix=$(determine_pkg_suffix $OS_SUFFIX)
  local arch_suffix=$(determine_arch_suffix $OS_SUFFIX)
  local package_name=chapel-$CHPL_REAL_VERSION-1.$OS_SUFFIX.$arch_suffix.$pkg_suffix
  curl -L https://github.com/chapel-lang/chapel/releases/download/$CHPL_REAL_VERSION/$package_name -o $package_name
  if [ $? -ne 0 ]; then
    echo "Error: failed to download Chapel package"
    exit 1
  fi
  package_install $OS_SUFFIX ./$package_name


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
