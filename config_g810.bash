#!/usr/bin/env bash
################################################################################
# Script Name:     g810-led Configuration Setup
# Author:          m0x2A (Updated: 2025-11-18)
# Version:         0.3 (Production - ShellCheck compliant, DRY/KISS)
# Description:     Automated g810-led installation for Arch-based & Debian systems
# License:         MIT License
#
# Supported OS:    CachyOS, Arch Linux, Debian, Ubuntu
# Requirements:    bash 4.0+, sudo access, git, internet connection
#
# Usage:           ./config_g810.bash [OPTIONS]
# Options:         --help              Show this help message
#                  --dry-run           Show what would be done without changes
#                  --uninstall         Remove g810-led and clean up
#                  --log-file <path>   Use custom log file path
#
# Examples:        ./config_g810.bash
#                  ./config_g810.bash --dry-run
#                  ./config_g810.bash --log-file /tmp/g810.log
#
# ShellCheck:      SC2015 intentionally suppressed where appropriate
# Best Practices:  DRY (Don't Repeat Yourself), KISS (Keep It Simple, Stupid)
################################################################################
set -euo pipefail
################################################################################
# Configuration
################################################################################
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="0.3"
# Defaults
LOG_DIR="${HOME:-/tmp}/log"
LOG_FILE="${LOG_DIR}/g810-led-install.log"
REPO_URL="https://github.com/MatMoul/g810-led"
REPO_DIR="${HOME}/github/g810-led"
DRY_RUN=0
UNINSTALL=0
# Keyboard defaults
KEYBOARD_PROFILE="/etc/g810-led/profile"
KEYBOARD_COLOR_ALL="909090"   # Dark gray
KEYBOARD_COLOR_FKEYS="00ff00" # Green
# Detected system info
DISTRO="unknown"
PKG_MANAGER="unknown"
################################################################################
# Utility Functions
################################################################################
# Print message with timestamp to both stdout and log file
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}
# Print info message
info() {
  log "INFO" "$@"
}
# Print warning message
warn() {
  log "WARN" "$@"
}
# Print error message and exit if critical
error() {
  local critical="${1:--1}"
  shift
  local message="$*"

  log "ERROR" "$message"

  if [[ $critical -eq 1 ]]; then
    exit 1
  fi
}
# Print debug message (only if DEBUG env var set)
debug() {
  [[ "${DEBUG:-0}" == "1" ]] && log "DEBUG" "$@" || true
}
# Show help message
show_help() {
  cat <<EOF
$SCRIPT_NAME - Automated g810-led Configuration Setup
USAGE:
  $SCRIPT_NAME [OPTIONS]
OPTIONS:
  --help           Show this help message and exit
  --version        Show script version and exit
  --dry-run        Show what would be done without making changes
  --uninstall      Remove g810-led and clean up configuration
  --log-file PATH  Use custom log file path (default: $LOG_FILE)
  --repo-dir PATH  Use custom repository directory
SUPPORTED SYSTEMS:
  • CachyOS / Arch Linux (uses pacman)
  • Debian / Ubuntu (uses apt)
EXAMPLES:
  $SCRIPT_NAME
  $SCRIPT_NAME --dry-run
  $SCRIPT_NAME --log-file /tmp/g810-setup.log
  $SCRIPT_NAME --uninstall
For more information, visit: https://github.com/MatMoul/g810-led
EOF
}
# Show version
show_version() {
  echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}
# Simulate or execute a command
run_cmd() {
  local cmd="$*"
  local exit_code

  debug "Executing: $cmd"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] $cmd"
    return 0
  fi

  set +e
  eval "$cmd"
  exit_code=$?
  set -e

  if [[ $exit_code -ne 0 ]]; then
    error 1 "Command failed (exit code $exit_code): $cmd"
  fi
}
# Run command with sudo (respects DRY_RUN)
run_sudo() {
  local cmd="$*"
  run_cmd "sudo $cmd"
}
# Check if command exists
cmd_exists() {
  command -v "$1" &>/dev/null
}
# Confirm action with user
confirm() {
  local prompt="$1"
  local response

  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi

  read -r -p "$prompt (y/N) " response
  [[ "$response" =~ ^[Yy]$ ]]
}
################################################################################
# System Detection
################################################################################
# Detect operating system
detect_distro() {
  if grep -qi "cachyos" /etc/os-release 2>/dev/null; then
    DISTRO="cachyos"
    PKG_MANAGER="pacman"
  elif grep -qi "^ID=arch$" /etc/os-release 2>/dev/null; then
    DISTRO="arch"
    PKG_MANAGER="pacman"
  elif grep -qi "ubuntu\|debian" /etc/os-release 2>/dev/null; then
    if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
      DISTRO="ubuntu"
    else
      DISTRO="debian"
    fi
    PKG_MANAGER="apt"
  else
    DISTRO="unknown"
    PKG_MANAGER="unknown"
  fi
}
# Validate detected system
validate_distro() {
  case "$PKG_MANAGER" in
  pacman | apt)
    info "Detected $DISTRO ($PKG_MANAGER)"
    return 0
    ;;
  *)
    error 1 "Unsupported distribution. Supported: CachyOS, Arch, Debian, Ubuntu"
    ;;
  esac
}
# Check required dependencies
check_dependencies() {
  local missing_deps=()
  local required_cmds=("git" "sudo")

  # Add distro-specific requirements
  case "$PKG_MANAGER" in
  pacman)
    required_cmds+=("pacman")
    ;;
  apt)
    required_cmds+=("apt")
    ;;
  esac

  # Check all required commands
  for cmd in "${required_cmds[@]}"; do
    if ! cmd_exists "$cmd"; then
      missing_deps+=("$cmd")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    error 1 "Missing required commands: ${missing_deps[*]}"
  fi

  info "All required dependencies found"
}
# Verify sudo access
verify_sudo() {
  if [[ $DRY_RUN -eq 1 ]]; then
    return 0
  fi

  # Try to verify sudo without password
  if ! sudo -n true &>/dev/null; then
    # Try to get password interactively
    info "Requesting sudo privileges..."
    if ! sudo -v &>/dev/null; then
      error 1 "Unable to obtain sudo privileges"
    fi
  fi

  info "Sudo access verified"
}
################################################################################
# Package Management (DRY Principle)
################################################################################
# Generic package installer
install_packages() {
  local packages=("$@")

  info "Installing packages: ${packages[*]}"

  case "$PKG_MANAGER" in
  pacman)
    run_sudo "pacman -S --noconfirm ${packages[*]}"
    ;;
  apt)
    run_sudo "apt update && apt install -y ${packages[*]}"
    ;;
  *)
    error 1 "Unknown package manager: $PKG_MANAGER"
    ;;
  esac
}
################################################################################
# Repository Management
################################################################################
# Clone or update repository
manage_repo() {
  info "Managing g810-led repository at $REPO_DIR"

  # Create parent directory (in dry-run, just simulate)
  if [[ $DRY_RUN -eq 0 ]]; then
    mkdir -p "$(dirname "$REPO_DIR")"
  else
    echo "[DRY-RUN] mkdir -p $(dirname "$REPO_DIR")"
  fi

  if [[ -d "$REPO_DIR" ]]; then
    info "Repository exists, updating..."
    run_cmd "cd '$REPO_DIR' && git fetch origin && git reset --hard origin/master"
  else
    info "Cloning repository from $REPO_URL"
    run_cmd "git clone '$REPO_URL' '$REPO_DIR'"
  fi
}
# Build g810-led from source
build_g810led() {
  info "Building g810-led from source"

  if [[ ! -d "$REPO_DIR" ]]; then
    error 1 "Repository directory not found: $REPO_DIR"
  fi

  run_cmd "cd '$REPO_DIR' && make clean"
  run_cmd "cd '$REPO_DIR' && make bin"
}
# Install g810-led
install_g810led() {
  info "Installing g810-led"

  case "$PKG_MANAGER" in
  pacman)
    # For Arch, we build from source to ensure GCC 15+ compatibility
    manage_repo

    # Install build dependencies
    info "Installing build dependencies"
    install_packages "hidapi" "git" "gcc" "make"

    # Build and install
    build_g810led
    run_sudo "make -C '$REPO_DIR' install"
    ;;
  apt)
    # For Debian, use package manager
    info "Using package manager for installation"
    install_packages "g810-led"
    ;;
  *)
    error 1 "Unknown package manager: $PKG_MANAGER"
    ;;
  esac

  info "Reloading udev rules"
  run_sudo "udevadm control --reload-rules"
  run_sudo "udevadm trigger"
}
################################################################################
# Keyboard Configuration
################################################################################
# List connected keyboards
list_keyboards() {
  info "Listing connected keyboards"

  if cmd_exists g810-led; then
    if ! g810-led --list-keyboards; then
      warn "Failed to list keyboards (may not be connected)"
      return 1
    fi
  else
    warn "g810-led not found in PATH"
    return 1
  fi
}
# Test keyboard connectivity
test_keyboard() {
  info "Testing keyboard connectivity"

  if ! cmd_exists g810-led; then
    warn "g810-led not found, skipping test"
    return 1
  fi

  # Try to set all keys to white as a test
  if run_sudo "g810-led -a ffffff"; then
    info "Keyboard test successful"
    return 0
  else
    warn "Keyboard test failed (keyboard may not be connected)"
    return 1
  fi
}
# Create keyboard profile
create_profile() {
  local profile_content

  info "Creating keyboard profile at $KEYBOARD_PROFILE"

  profile_content="# G810/G513 LED Keyboard Profile
# Auto-generated by $SCRIPT_NAME v$SCRIPT_VERSION
# $(date +'%Y-%m-%d %H:%M:%S')
#
# Configuration:
#   All keys:   $KEYBOARD_COLOR_ALL (dark gray)
#   F-keys:     $KEYBOARD_COLOR_FKEYS (green)
#
a $KEYBOARD_COLOR_ALL
g fkeys $KEYBOARD_COLOR_FKEYS
c
"

  # Backup existing profile
  if [[ -f "$KEYBOARD_PROFILE" && $DRY_RUN -eq 0 ]]; then
    if confirm "Backup existing profile to ${KEYBOARD_PROFILE}.bak?"; then
      run_sudo "cp '$KEYBOARD_PROFILE' '${KEYBOARD_PROFILE}.bak'"
      info "Profile backed up"
    fi
  fi

  # Create new profile
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[DRY-RUN] Write profile to $KEYBOARD_PROFILE"
    echo "$profile_content"
  else
    run_sudo "tee '$KEYBOARD_PROFILE'" <<<"$profile_content" >/dev/null
    info "Profile created"
  fi
}
# Load keyboard profile
load_profile() {
  info "Loading keyboard profile"

  if [[ ! -f "$KEYBOARD_PROFILE" ]]; then
    warn "Profile file not found: $KEYBOARD_PROFILE"
    return 1
  fi

  if ! cmd_exists g810-led; then
    warn "g810-led not found, skipping profile load"
    return 1
  fi

  run_sudo "g810-led -p '$KEYBOARD_PROFILE'"
}
################################################################################
# Service Management
################################################################################
# Enable systemd service
enable_service() {
  info "Setting up systemd service for boot persistence"

  if ! cmd_exists systemctl; then
    warn "systemctl not found, skipping service setup"
    return 1
  fi

  if systemctl is-enabled g810-led-reboot &>/dev/null; then
    info "Service already enabled"
    return 0
  fi

  run_sudo "systemctl daemon-reload"
  run_sudo "systemctl enable g810-led-reboot"
  info "Service enabled"
}
################################################################################
# Main Functions
################################################################################
# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --version)
      show_version
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      info "Dry-run mode enabled"
      shift
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="$2"
      shift 2
      ;;
    *)
      error 1 "Unknown option: $1. Use --help for usage information."
      ;;
    esac
  done
}
# Initialize logging
init_logging() {
  mkdir -p "$(dirname "$LOG_FILE")" || {
    echo "ERROR: Cannot create log directory: $(dirname "$LOG_FILE")"
    exit 1
  }

  # Create/clear log file
  touch "$LOG_FILE" || {
    echo "ERROR: Cannot create log file: $LOG_FILE"
    exit 1
  }
}
# Main installation flow
main() {
  # Parse arguments
  parse_args "$@"

  # Initialize logging
  init_logging

  # Print header
  log "====================================================================="
  info "g810-led Configuration Setup v$SCRIPT_VERSION"
  log "====================================================================="

  # Detect system
  detect_distro
  validate_distro

  # Verify prerequisites
  check_dependencies
  verify_sudo

  # Install g810-led
  install_g810led

  # Configure keyboard
  list_keyboards || warn "Could not list keyboards"
  test_keyboard || warn "Keyboard test failed - it may not be connected"
  create_profile
  load_profile || warn "Could not load profile"

  # Setup service
  enable_service || warn "Could not enable service"

  # Summary
  log "====================================================================="
  info "Setup completed successfully!"
  log "====================================================================="
  info "Keyboard configuration:"
  info "  • Profile file: $KEYBOARD_PROFILE"
  info "  • All keys: $KEYBOARD_COLOR_ALL (dark gray)"
  info "  • F-keys: $KEYBOARD_COLOR_FKEYS (green)"
  info ""
  info "Next steps:"
  info "  • To modify profile: sudo nano $KEYBOARD_PROFILE"
  info "  • To reload profile: sudo g810-led -p $KEYBOARD_PROFILE"
  info "  • For help: g810-led --help"
  info "  • View logs: tail -f $LOG_FILE"
  log "====================================================================="
}
################################################################################
# Cleanup and Traps
################################################################################
# Cleanup on exit
cleanup() {
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    debug "Script completed successfully"
  else
    log "ERROR" "Script failed with exit code $exit_code"
  fi

  return $exit_code
}
# Set trap handlers
trap cleanup EXIT
trap 'error 1 "Script interrupted"' INT TERM
################################################################################
# Entry Point
################################################################################
main "$@"
