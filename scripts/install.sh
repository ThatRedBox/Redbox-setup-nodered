#!/bin/bash

##
#   Install.sh
#   Installs the latest version of Redbox on your device.
#
#   Released under the MIT License (see LICENSE.txt)
#
#  ----------------------------------------------------------------------------
#   Before changing this script
#  ----------------------------------------------------------------------------
#
#   The order is load-bearing. Edgeberry is checked, and installed if missing,
#   first - before Node.js - because its installer is what is expected to have
#   put Node.js in place on a fresh device. Node-RED reads its palette and its
#   flow file once, at startup, so it is started at the very end - after the
#   node packages are installed and the default flow is in place. Start it any
#   earlier and the install still reports success while Node-RED runs with an
#   empty palette, or with no flow to announce this box to Edgeberry with.
#
#   Node.js belongs to the whole device, not to this project. Edgeberry runs on
#   the same /usr/bin/node. Node.js is therefore installed when it is missing and
#   otherwise left exactly as found: a version that does not suit Node-RED is
#   reported and the install stops. Upgrading it here would change the runtime
#   underneath another application.
#
#   Versions are pinned, never discovered - see NODEREDVERSION below.
#
#   Steps report outcomes, not activity:
#
#     report_success                      prints [Success]
#     report_failure <output> [severity]  prints the reason indented on stderr;
#                                         'fatal' (default) exits 1, 'warning'
#                                         returns so the caller can continue
#     run_step <desc> <severity> <cmd..>  both of the above around one command
#
#   Never send a command's output to /dev/null. A bare "Failed!" cannot be
#   debugged on a device you are not sitting in front of.
#
#   'problems' counts failures that did not abort the install. The script exits
#   non-zero when it is not zero, so a partial install is never reported as a
#   success to whoever called it.
##

PROJECT=Redbox
REPONAME=Redbox-setup-nodered
REPOOWNER=ThatRedBox

APPDIR=/opt/${PROJECT}
SYSDCONF=redbox-nodered-service.conf

##
#   Pinned versions
#   Pin deliberately, and bump deliberately. An unpinned install takes whatever
#   the registry serves that day, which is how a device ends up with a Node-RED
#   it cannot start.
#
#   Node-RED 5.x requires Node.js >= 22.9. An Edgeberry device runs Debian's
#   Node.js 20, which is also what Edgeberry Core runs on, so the Node-RED 4.x
#   line is the supported combination here. Before raising this, check that the
#   whole palette - and Edgeberry - support the Node.js version the new line
#   needs.
##
NODEREDVERSION=4.1.13

# Check if this script is running as root. If not, notify the user
# to run this script again as root and cancel the installation process
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[0;31mUser is not root. Exit.\e[0m"
    echo -e "\e[0mRun this script again as root\e[0m"
    exit 1;
fi

##
#   Step reporting
#   Every step prints its outcome. A step that fails also prints the output
#   of the command that failed: "Failed!" on its own leaves the user with
#   nothing to debug, which is exactly the situation these helpers exist to
#   avoid. Commands are therefore captured, never discarded.
##

# Steps that report a failure without aborting are counted, so the closing
# message can tell the truth about what happened instead of always claiming
# success.
problems=0

# Report a step that succeeded
report_success(){
    echo -e "\e[0;32m[Success]\e[0m"
}

# Report a step that failed. Takes the captured output of the failing command,
# and optionally the severity: 'fatal' (default) ends the installation,
# 'warning' reports and continues.
report_failure(){
    local output="$1"
    local severity="${2:-fatal}"

    if [ "${severity}" = "fatal" ]; then
        echo -e "\e[0;31mFailed! Exit.\e[0m"
    else
        echo -e "\e[0;33m[Failed]\e[0m"
    fi

    # Print the reason indented underneath the step it belongs to
    if [ -n "${output}" ]; then
        echo "${output}" | sed 's/^/    /' >&2
    fi

    if [ "${severity}" = "fatal" ]; then
        exit 1;
    fi
    return 0
}

# Run a single command as an installation step: print the description, run the
# command with its output captured, and report the outcome. Usage:
#   run_step "Installing jq" fatal apt install -y jq
run_step(){
    local description="$1"
    local severity="$2"
    shift 2
    local output

    echo -n -e "\e[0m${description} \e[0m"
    if output=$("$@" 2>&1); then
        report_success
        return 0
    fi
    report_failure "${output}" "${severity}"
    return 1
}

# Continue with a clean screen
clear;

# Display the logo: "Red" in white, "[box]" in Vivid Crimson - the same
# wordmark the interface wears.
#
# The crimson is a 24-bit colour. A terminal that cannot show it falls back to
# something near enough; the banner is decoration, so nothing here checks.
W="\e[1;97m"
R="\e[38;2;235;58;58m"
X="\e[0m"
echo -e "${W}██████╗ ███████╗██████╗ ${R}███╗██████╗  ██████╗ ██╗  ██╗███╗${X}"
echo -e "${W}██╔══██╗██╔════╝██╔══██╗${R}██╔╝██╔══██╗██╔═══██╗╚██╗██╔╝╚██║${X}"
echo -e "${W}██████╔╝█████╗  ██║  ██║${R}██║ ██████╔╝██║   ██║ ╚███╔╝  ██║${X}"
echo -e "${W}██╔══██╗██╔══╝  ██║  ██║${R}██║ ██╔══██╗██║   ██║ ██╔██╗  ██║${X}"
echo -e "${W}██║  ██║███████╗██████╔╝${R}███╗██████╔╝╚██████╔╝██╔╝ ██╗███║${X}"
echo -e "${W}╚═╝  ╚═╝╚══════╝╚═════╝ ${R}╚══╝╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚══╝${X}"
echo ""

##
#   Dependencies
#   Install system dependencies for this service
#   and installation script to work correctly
##

# Refresh the package index so subsequent apt installs use up-to-date sources.
# This takes a while, so announce it before starting instead of leaving the
# user staring at a silent screen. A stale package index is not fatal: the
# dependencies below may well already be installed, so warn and continue.
run_step "Refreshing the package index (this can take a minute)" warning \
    apt update

# Install Edgeberry using its own official installer, non-interactively.
#
# Redbox is Node-RED *for* an Edgeberry device: without the edgeberry CLI
# there is no --register-application to call later, and without Edgeberry's
# own nginx there is no proxy to reach the editor through. So it is checked
# and, if missing, installed here - first, before anything else - rather
# than left to be discovered only when the registration step fails after
# Node-RED is already fully set up.
#
# Installing it first also means the Node.js check right after this one sees
# whatever Node.js Edgeberry's installer already put in place, which is the
# version this device is meant to run.
install_edgeberry_from_scratch(){
    local installer output
    echo -n -e "\e[0mInstalling Edgeberry \e[0m"
    installer=$(mktemp)
    output=$( {
        set -e
        curl -fsL -o "${installer}" \
            https://github.com/Edgeberry/Edgeberry/releases/latest/download/install.sh
        bash "${installer}" -y
    } 2>&1 )
    local result=$?
    rm -f "${installer}"
    if [ ${result} -eq 0 ]; then
        report_success
    else
        report_failure "${output}"
    fi
}

echo -n -e "\e[0mChecking for Edgeberry \e[0m"
if which edgeberry >/dev/null 2>&1; then
    echo -e "\e[0;32m[Installed] \e[0m$(edgeberry --version 2>/dev/null)";
else
    echo -e "\e[0;33m[Not installed] \e[0m";
    install_edgeberry_from_scratch
fi

# Check for NodeJS. If it's not installed, install it.
#
# Node.js is a shared system component: Edgeberry runs on the same /usr/bin/node
# this project uses. So it is installed when missing and otherwise left exactly
# as it is - this installer never upgrades or replaces Node.js underneath
# another application. Where a version is not good enough, it says so and stops
# rather than "fixing" it.
echo -n -e "\e[0mChecking for NodeJS \e[0m"
if which node >/dev/null 2>&1; then
    echo -e "\e[0;32m[Installed] \e[0m$(node -v)";
else
    echo -e "\e[0;33m[Not installed] \e[0m";
    run_step "Installing Node using apt" fatal apt install -y nodejs
fi

# Check for NPM. If it's not installed, install it.
echo -n -e "\e[0mChecking for Node Package Manager (NPM) \e[0m"
if which npm >/dev/null 2>&1; then
    echo -e "\e[0;32m[Installed] \e[0m";
else
    echo -e "\e[0;33m[Not installed] \e[0m";
    run_step "Installing NPM using apt" fatal apt install -y npm
fi

# Check for JQ (required by the steps below). If it's not installed,
# install it.
echo -n -e "\e[0mChecking for jq \e[0m"
if which jq >/dev/null 2>&1; then
    echo -e "\e[0;32m[Installed] \e[0m";
else
    echo -e "\e[0;33m[Not installed] \e[0m";
    run_step "Installing jq using apt" fatal apt install -y jq
fi

# The Raspberry Pi's SPI and I2C buses are both off by default, and Redbox wants
# both: the MCP3008 nodes in the palette read their ADC over SPI, and the Edge
# Explorer hardware cartridge exposes I2C.
#
# They are enabled through raspi-config rather than by editing config.txt from
# here. The buses are device-level settings owned by the OS, and raspi-config is
# what the rest of the system expects to have written them - it also un-blacklists
# the kernel modules and, for I2C, adds i2c-dev to /etc/modules, which an edit of
# config.txt alone would miss.
#
# Not fatal, deliberately. Only some nodes need these buses, and a device that is
# not running Raspberry Pi OS has no raspi-config at all. Redbox installs and runs
# either way, so a bus that cannot be enabled is reported and the install carries
# on.
#
# Enable one hardware bus. Usage:
#   enable_bus "SPI" spi "/dev/spidev*"
#
# Two states are checked, because they answer different questions: 'get_<bus>'
# only reads the boot configuration, so it says what the device will do after its
# next boot, while the device nodes under /dev are what Node-RED actually opens.
enable_bus(){
    local label="$1" bus="$2" glob="$3"

    echo -n -e "\e[0mChecking the ${label} bus \e[0m"
    if ! which raspi-config >/dev/null 2>&1; then
        echo -e "\e[0;33m[Skipped] \e[0mno raspi-config on this device"
        return 0
    fi
    # Unquoted on purpose: ${glob} has to expand to the device nodes, and ls
    # fails when nothing matches, which is exactly the signal wanted here.
    if [ "$(raspi-config nonint "get_${bus}")" = "0" ] && ls ${glob} >/dev/null 2>&1; then
        echo -e "\e[0;32m[Enabled] \e[0m"
        return 0
    fi
    echo -e "\e[0;33m[Not enabled] \e[0m"

    # 'do_<bus> 0' enables (1 would disable it). It writes the dtparam to the
    # boot configuration and applies the same parameter to the running kernel,
    # so the bus normally comes up without a reboot.
    run_step "Enabling the ${label} bus" warning \
        raspi-config nonint "do_${bus}" 0 || return 1

    # Where the running kernel did not take it, the setting is real only after a
    # reboot. Say so here: the alternative is nodes that fail at runtime on a
    # device whose configuration looks perfectly correct.
    if ! ls ${glob} >/dev/null 2>&1; then
        report_failure "${label} is enabled in the boot configuration, but no ${glob} device has
appeared. Reboot the device to bring the bus up - until then the nodes that use
${label} cannot reach their hardware." warning
    fi
}

enable_bus "SPI" spi "/dev/spidev*"
enable_bus "I2C" i2c "/dev/i2c-*"

# The version of Node-RED currently installed globally, read from its
# package.json. Never ask node-red itself: when it cannot run on the installed
# Node.js it prints an error and still exits 0, so 'node-red --version' reports
# neither a version nor a failure.
installed_nodered_version(){
    local root pkg
    root=$(npm root -g 2>/dev/null) || return 1
    pkg="${root}/node-red/package.json"
    [ -f "${pkg}" ] || return 1
    jq -r '.version // empty' "${pkg}" 2>/dev/null
}

# Install Node-RED from scratch using the official installer, which also creates
# the systemd service. No --node* flag is passed on purpose: those make the
# script add the NodeSource apt repository and reinstall Node.js, which would
# replace the Node.js that Edgeberry runs on. Without one it leaves Node.js
# alone, which is what this project wants.
#
# --skip-pi does not mean going without the Pi nodes: they are in the palette in
# nodered/package.json. It is that the installer's own copy would land in
# ~/.node-red, not the userDir Node-RED runs from here. Its other Pi setup - the
# RPi.GPIO Python library the GPIO nodes call - is not governed by this flag and
# happens anyway.
install_nodered_from_scratch(){
    local installer output
    echo -n -e "\e[0mInstalling Node-RED ${NODEREDVERSION} \e[0m"
    # Download the installer to a file first. Piping a failed download straight
    # into bash succeeds on an empty script, which would report Node-RED as
    # installed when nothing happened at all.
    installer=$(mktemp)
    output=$( {
        set -e
        curl -fsL -o "${installer}" \
            https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered
        bash "${installer}" \
            --confirm-root \
            --confirm-install \
            --skip-pi \
            --nodered-version="${NODEREDVERSION}" \
            --restart
    } 2>&1 )
    local result=$?
    rm -f "${installer}"
    if [ ${result} -eq 0 ]; then
        report_success
    else
        report_failure "${output}"
    fi
}

# Check for Node-RED. Presence is not enough: it has to be the pinned version,
# because that is the version this project has been tested against and the one
# that runs on the Node.js already on this device.
echo -n -e "\e[0mChecking for Node-RED \e[0m"
current_nodered=$(installed_nodered_version)
if [ "${current_nodered}" = "${NODEREDVERSION}" ]; then
    echo -e "\e[0;32m[Installed] \e[0mv${current_nodered}";
elif [ -z "${current_nodered}" ]; then
    echo -e "\e[0;33m[Not installed] \e[0m";
    install_nodered_from_scratch
else
    # Present but not the pinned version. The systemd service already exists, so
    # replace just the package - re-running the official installer here would
    # touch far more of the system than needs touching.
    echo -e "\e[0;33m[Found v${current_nodered}, want v${NODEREDVERSION}] \e[0m";
    run_step "Installing Node-RED ${NODEREDVERSION}" fatal \
        npm install -g node-red@${NODEREDVERSION}
fi

# Node-RED states the Node.js version it needs. Check the one on this device
# satisfies it, rather than finding out from a service that crash-loops.
# Majors are compared, which is enough to catch the mismatch that matters
# without hand-rolling a semver parser.
# Note what this deliberately does not do: upgrade Node.js. It is shared with
# Edgeberry, so resolving a mismatch is a decision for a human, not a side
# effect of installing this project.
echo -n -e "\e[0mChecking Node.js suits Node-RED \e[0m"
nodered_needs=$(jq -r '.engines.node // empty' "$(npm root -g)/node-red/package.json" 2>/dev/null)
node_major=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)
needs_major=$(echo "${nodered_needs}" | grep -o '[0-9]\+' | head -1)
if [ -z "${needs_major}" ] || [ -z "${node_major}" ]; then
    # Nothing to compare against: report it rather than claiming a pass.
    echo -e "\e[0;33m[Unknown]\e[0m"
    echo -e "\e[0m    Could not determine the requirement (node-red wants '${nodered_needs:-?}', node reports '$(node -v 2>/dev/null)')\e[0m"
elif [ "${node_major}" -ge "${needs_major}" ]; then
    echo -e "\e[0;32m[Success]\e[0m"
else
    report_failure "Node-RED ${NODEREDVERSION} needs Node.js ${nodered_needs}, but this device has $(node -v).
Node.js is shared with Edgeberry on this device, so this installer will not
upgrade it. Either pin Node-RED to a release that supports Node.js ${node_major}
(NODEREDVERSION in this script), or upgrade Node.js deliberately after checking
that Edgeberry still works on the newer version."
fi

##
#   Application:
#   Look up and download the latest version from GitHub,
#   then put all the required files in their right place
#   to start the actual installation.
##

# Check for the latest release of the application using the GitHub API
echo -n -e "\e[0mGetting latest ${PROJECT} release info \e[0m"
latest_release=$(curl -H "Accept: application/vnd.github.v3+json" -s "https://api.github.com/repos/${REPOOWNER}/${REPONAME}/releases/latest")
# Check if this was successful (curl -s returns a JSON error body on failure,
# so verify the payload actually contains a release tag).
if [ -n "$latest_release" ] && echo "$latest_release" | jq -e '.tag_name' >/dev/null 2>&1; then
    report_success
else
    # The response body carries the actual reason (API rate limit exceeded,
    # repository not found, no internet connection, ...), so show it.
    report_failure "GitHub API: https://api.github.com/repos/${REPOOWNER}/${REPONAME}/releases/latest
Response was:
${latest_release:-(empty - no response from GitHub)}"
fi

# Get the asset download URL from the release info
echo -n -e "\e[0mGetting the latest ${PROJECT} release download URL \e[0m"
asset_url=$(
  echo "$latest_release" \
    | jq -r \
        --arg re "${REPONAME}-v[0-9]+\\.[0-9]+\\.[0-9]+\\.tar\\.gz" \
        '.assets[]
         | select(.name | test($re))
         | .browser_download_url'
)
# If we have an asset URL, download the tarball
if [ -n "$asset_url" ]; then
    report_success
else
    # Name what was looked for and what the release actually contains: a
    # release published without its tarball is otherwise indistinguishable
    # from a broken script.
    release_tag=$(echo "$latest_release" | jq -r '.tag_name')
    release_assets=$(echo "$latest_release" | jq -r '.assets[].name')
    report_failure "No asset matching '${REPONAME}-v<x>.<y>.<z>.tar.gz' in release ${release_tag}.
Assets in this release:
${release_assets:-(none - the release has no attached files)}"
fi

echo -n -e "\e[0mDownloading the application \e[0m"
# -f makes HTTP errors fail the command instead of silently saving an error
# page as if it were the tarball.
download_output=$(curl -fL \
    -H "Accept: application/octet-stream" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -o "repo.tar.gz" \
    "$asset_url" 2>&1)
# Check if the download was successful
if [ $? -eq 0 ] && [ -s "repo.tar.gz" ]; then
    report_success
else
    report_failure "Download URL: ${asset_url}
${download_output:-(downloaded file is empty)}"
fi

# Untar the application in the application folder
echo -n -e "\e[0mUnpacking the application \e[0m"
unpack_output=$( {
    set -e
    mkdir -p ${APPDIR}
    tar -xzf repo.tar.gz -C ${APPDIR}
} 2>&1 )
# Check if the last command succeeded
if [ $? -eq 0 ]; then
    report_success
else
    report_failure "Unpacking repo.tar.gz into ${APPDIR} failed:
${unpack_output}"
fi

# Cleanup the download tarball
rm -rf repo.tar.gz

##
#   Application:
#   Actually installing the application
##

# Install the application's systemd service mods for Node-RED
echo -e -n '\e[mInstalling Node-RED systemd service configuration \e[m'
systemd_output=$( {
    set -e
    # Make the directory for the config file and move the config file there
    mkdir -p /etc/systemd/system/nodered.service.d
    mv -f ${APPDIR}/config/${SYSDCONF} /etc/systemd/system/nodered.service.d/
    systemctl daemon-reload
    # Make sure Node-RED runs after a reboot. Starting it is deliberately left
    # until the end of this script: Node-RED reads its palette once at startup,
    # so it has to start after the nodes are in place.
    systemctl enable nodered.service
} 2>&1 )
if [ $? -eq 0 ]; then
    report_success
else
    # Node-RED's own journal explains a failed start far better than systemctl
    # does, so point at it rather than leaving the user to guess.
    report_failure "${systemd_output}
Run 'journalctl -u nodered -n 50' for the service log." warning
    problems=$((problems+1))
fi

# Install package dependencies
echo -n -e "\e[0mInstalling dependencies \e[0m"
npm_output=$(npm install --prefix ${APPDIR}/nodered 2>&1)
# Check if the last command succeeded
if [ $? -eq 0 ]; then
    report_success
else
    report_failure "npm install --prefix ${APPDIR}/nodered
${npm_output}"
fi

# Put the default flow in place.
#
# This is what makes Redbox appear on the device interface. Registering the
# manifest below tells Edgeberry where the application lives and which port to
# proxy; it says nothing about the application's name, version or links. Those
# come from an 'info' message a flow sends to the Edgeberry node at startup, so
# a box with no flow registers as an application with no name and no way in.
#
# Written only when it is not already there. From the first deploy onwards the
# flow file is the user's work, and re-running this installer to update must not
# overwrite it - which is why the shipped copy lives outside the userDir and is
# copied in, rather than being unpacked straight over it.
#
# The path is the flowFile from nodered/settings.js, resolved against the
# userDir the systemd drop-in points Node-RED at. Change it in one place and it
# has to change here too.
FLOWFILE=${APPDIR}/nodered/flows/Redbox_flows.json
echo -n -e "\e[0mInstalling the default flow \e[0m"
if [ -f "${FLOWFILE}" ]; then
    echo -e "\e[0;32m[Kept] \e[0mthis device already has flows"
else
    flow_output=$( {
        set -e
        mkdir -p "$(dirname "${FLOWFILE}")"
        cp ${APPDIR}/defaults/Redbox_flows.json "${FLOWFILE}"
    } 2>&1 )
    if [ $? -eq 0 ]; then
        report_success
    else
        # Not fatal: Node-RED starts fine without it. What is lost is the
        # application's entry on the device interface, so say which flow to
        # rebuild rather than only that a copy failed.
        report_failure "cp ${APPDIR}/defaults/Redbox_flows.json ${FLOWFILE}
${flow_output}
Node-RED will start with an empty flow. Until a flow sends its 'info' message to
an Edgeberry node, the device interface has no name or links for this box." warning
        problems=$((problems+1))
    fi
fi

# Register the application with Edgeberry
# Edgeberry owns nginx and proxies /application/* to the app port,
# so this must succeed for the UI to be reachable.
echo -n -e "\e[0mRegistering ${PROJECT} with Edgeberry \e[0m"
register_output=$(edgeberry --register-application ${APPDIR} 2>&1)
if [ $? -eq 0 ]; then
    report_success
else
    report_failure "edgeberry --register-application ${APPDIR}
${register_output}"
fi

##
#   Start Node-RED
#   Last, so that it starts with the freshly installed nodes in its palette and
#   the default flow already on disk. Node-RED reads both once at startup, so
#   starting it any earlier leaves it running without them until something
#   restarts it - and an application that never sent its info is an application
#   the device interface cannot show.
##
echo ""
echo -n -e "\e[0mStarting Node-RED \e[0m"
# Record where to start reading the journal, before anything is restarted.
nodered_since=$(date '+%Y-%m-%d %H:%M:%S')
nodered_output=$(systemctl restart nodered.service 2>&1)
if [ $? -eq 0 ]; then
    report_success
else
    report_failure "${nodered_output}
Run 'journalctl -u nodered -n 50' for the service log." warning
    problems=$((problems+1))
fi

# 'systemctl restart' returns 0 as soon as systemd has spawned the process. It
# says nothing about whether Node-RED survived: a crash-looping service reports
# itself as "active (running)" for as long as each attempt lasts. So wait for
# Node-RED to say, itself, that it got as far as running the flow.
#
# This is the check that catches what the individual steps cannot - a palette
# that will not load, a flow referring to a node that is not installed, a
# Node.js it cannot run on. It does not need to know which of those went wrong.
echo -n -e "\e[0mWaiting for Node-RED to start the flows \e[0m"
# Generous: loading a large palette on a cold Raspberry Pi is slow, and calling
# a working install broken is worse than waiting a little longer.
NODEREDSTARTTIMEOUT=90
nodered_started=false
for _ in $(seq 1 $((NODEREDSTARTTIMEOUT / 2))); do
    if journalctl -u nodered.service --since "${nodered_since}" 2>/dev/null | grep -q "Started flows"; then
        nodered_started=true
        break
    fi
    sleep 2
done

if [ "${nodered_started}" = true ]; then
    report_success
else
    report_failure "Node-RED did not report 'Started flows' within ${NODEREDSTARTTIMEOUT} seconds.
The last of its log:
$(journalctl -u nodered.service --since "${nodered_since}" --no-pager 2>/dev/null | tail -15)" warning
    problems=$((problems+1))
fi

##
#   Finish installation
##
echo ""
if [ ${problems} -eq 0 ]; then
    echo -e "\033[1m${PROJECT}\033[0m was successfully installed!"
    echo -e "\e[0mOpen the editor at http://$(hostname)/application/editor\e[0m"
    echo ""
    # Remove this script
    rm -- "$0"
    exit 0;
fi

# Something failed without aborting the installation. Say so, and exit non-zero
# so a calling script sees it too.
echo -e "\e[0;33mThe ${PROJECT} installation finished with ${problems} problem(s).\e[0m" >&2
echo -e "\e[0;33mScroll up for the details of each failed step.\e[0m" >&2
echo ""
# Remove this script
rm -- "$0"

exit 1;
