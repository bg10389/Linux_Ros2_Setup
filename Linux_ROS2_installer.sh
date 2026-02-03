#!/usr/bin/env bash
set -euo pipefail

# ROS 2 Kilted Kaiju (kilted) installer for Ubuntu Noble (24.04)
# Installs ROS 2 (desktop by default) + common dev tooling, initializes rosdep,
# and adds /opt/ros/kilted/setup.bash to the invoking user's ~/.bashrc.
#
# Usage:
#   chmod +x Linux_ROS2_installer_kilted.sh
#   ./Linux_ROS2_installer_kilted.sh
#
# Optional env vars:
#   ROS_VARIANT=desktop|ros-base   (default: desktop)
#   INSTALL_DEV_TOOLS=1|0         (default: 1)
#   SKIP_UPGRADE=1|0              (default: 0)

ROS_DISTRO="kilted"
ROS_VARIANT="${ROS_VARIANT:-desktop}"
INSTALL_DEV_TOOLS="${INSTALL_DEV_TOOLS:-1}"
SKIP_UPGRADE="${SKIP_UPGRADE:-0}"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Do not run this script with sudo or as root." >&2
  echo "Run it as your normal user so ~/.bashrc and rosdep are configured correctly." >&2
  exit 1
fi

# Determine target user/home even if this script is launched in unusual ways.
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(eval echo "~${TARGET_USER}")"
DESKTOP_DIR="${TARGET_HOME}/Desktop"
if [[ -d "${DESKTOP_DIR}" ]]; then
  LOGFILE="${DESKTOP_DIR}/ros2_${ROS_DISTRO}_install.log"
else
  LOGFILE="${TARGET_HOME}/ros2_${ROS_DISTRO}_install.log"
fi

# Log everything (stdout+stderr) to a file for later troubleshooting.
exec > >(tee -a "${LOGFILE}") 2>&1

echo "=== ROS 2 ${ROS_DISTRO} installer starting ==="
echo "Log: ${LOGFILE}"

printf "\n[1/7] Verifying OS support...\n"
if [[ ! -r /etc/os-release ]]; then
  echo "/etc/os-release not found. This script supports Ubuntu 24.04 (Noble) only." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Detected ID='${ID:-unknown}'. This script is intended for Ubuntu 24.04 (Noble)." >&2
  exit 1
fi

if [[ "${UBUNTU_CODENAME}" != "noble" ]]; then
  echo "Detected Ubuntu codename '${UBUNTU_CODENAME}'." >&2
  echo "ROS 2 ${ROS_DISTRO} deb packages are published for Ubuntu 24.04 (Noble) only." >&2
  echo "If you're on a different Ubuntu release, either upgrade to 24.04 or install a supported ROS 2 distro for your OS." >&2
  exit 1
fi

printf "\n[2/7] Setting locale (UTF-8)...\n"
sudo apt-get update
sudo apt-get install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

printf "\n[3/7] Enabling Ubuntu Universe repository...\n"
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo apt-get update

printf "\n[4/7] Installing ROS 2 apt sources (ros2-apt-source)...\n"
# Per official Kilted Ubuntu deb instructions, we install the ros2-apt-source .deb.
# This manages GPG keys and repository configuration.
sudo apt-get install -y curl python3

ROS_APT_SOURCE_VERSION="$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')"

ROS_APT_SOURCE_DEB="/tmp/ros2-apt-source.deb"
ROS_APT_SOURCE_URL="https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.${UBUNTU_CODENAME}_all.deb"

echo "Downloading: ${ROS_APT_SOURCE_URL}"
curl -fsSL -o "${ROS_APT_SOURCE_DEB}" "${ROS_APT_SOURCE_URL}"
sudo dpkg -i "${ROS_APT_SOURCE_DEB}"
# If dpkg reports missing dependencies, this will resolve them.
sudo apt-get -f install -y

printf "\n[5/7] Updating apt caches and upgrading (recommended)...\n"
sudo apt-get update
if [[ "${SKIP_UPGRADE}" != "1" ]]; then
  sudo apt-get upgrade -y
else
  echo "SKIP_UPGRADE=1 set; skipping 'apt-get upgrade'."
fi

printf "\n[6/7] Installing ROS 2 ${ROS_DISTRO} (${ROS_VARIANT}) and common tooling...\n"
case "${ROS_VARIANT}" in
  desktop)
    sudo apt-get install -y "ros-${ROS_DISTRO}-desktop"
    ;;
  ros-base|base)
    sudo apt-get install -y "ros-${ROS_DISTRO}-ros-base"
    ;;
  *)
    echo "Unknown ROS_VARIANT='${ROS_VARIANT}'. Use 'desktop' or 'ros-base'." >&2
    exit 1
    ;;
esac

sudo apt-get install -y \
  python3-rosdep \
  python3-colcon-common-extensions \
  python3-argcomplete \
  python3-vcstool \
  build-essential

if [[ "${INSTALL_DEV_TOOLS}" == "1" ]]; then
  sudo apt-get install -y ros-dev-tools
fi

printf "\n[7/7] Initializing rosdep and updating indexes...\n"
if [[ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]]; then
  sudo rosdep init
else
  echo "rosdep already initialized; skipping 'rosdep init'."
fi
rosdep update

printf "\nConfiguring shell environment...\n"
BASHRC="${TARGET_HOME}/.bashrc"
SETUP_LINE="source /opt/ros/${ROS_DISTRO}/setup.bash"

if [[ -f "${BASHRC}" ]]; then
  if ! grep -Fq "${SETUP_LINE}" "${BASHRC}"; then
    {
      echo ""
      echo "# ROS 2 ${ROS_DISTRO}"
      echo "${SETUP_LINE}"
    } >> "${BASHRC}"
    echo "Added ROS 2 setup sourcing to ${BASHRC}."
  else
    echo "ROS 2 setup sourcing already present in ${BASHRC}."
  fi
else
  echo "${SETUP_LINE}" > "${BASHRC}"
  echo "Created ${BASHRC} and added ROS 2 setup sourcing."
fi

printf "\n=== ROS 2 ${ROS_DISTRO} installation complete ===\n"
echo "Open a new terminal or run:"
echo "  source /opt/ros/${ROS_DISTRO}/setup.bash"
echo "Quick test (in two terminals):"
echo "  ros2 run demo_nodes_cpp talker"
echo "  ros2 run demo_nodes_py listener"
