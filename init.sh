#!/bin/sh
set -e # Exit on error

PUID=${PUID:-1000}
PGID=${PGID:-1000}
DL_LINK=${DL_LINK:-https://github.com/5etools-mirror-3/5etools-src.git}
IMG_LINK=${IMG_LINK:-https://github.com/5etools-mirror-3/5etools-img.git}

printf " === Provided PUID: %s\n" "$PUID"
printf " === Provided PGID: %s\n" "$PGID"
printf " === These Links will be used:\n"
printf " === DL_LINK: %s\n" "$DL_LINK"
printf " === IMG_LINK: %s\n" "$IMG_LINK"

# If User and group don't exist, create them. If they do exist, ignore the error and continue.
addgroup -g "$PGID" appgroup 2>/dev/null || true
adduser -D -u "$PUID" appuser -G appgroup  2>/dev/null || true

# If the user doesn't want to update from a source, 
# check for local version.
# If local version is found, print version and start server.
# If no local version is found, print error message and exit.
if [ "$OFFLINE_MODE" = "TRUE" ]; then 
  printf " === Offline mode is enabled. Will try to launch from local files. Checking for local version...\n"
  if [ -f /usr/local/apache2/htdocs/package.json ]; then
    VERSION=$(jq -r .version /usr/local/apache2/htdocs/package.json) # Get version from package.json
    printf " === Starting version %s\n" "$VERSION"
    printf " === Configuring Apache to run as user %s:%s\n" "$PUID" "$PGID"
    # Configure Apache to run worker processes as the specified user/group
    sed -i "s/^User .*/User #$PUID/" /usr/local/apache2/conf/httpd.conf
    sed -i "s/^Group .*/Group #$PGID/" /usr/local/apache2/conf/httpd.conf
    httpd-foreground
  else
    printf " === No local version detected. Exiting.\n"
    exit 1
  fi
fi

# Move to the working directory for working with files.
cd /usr/local/apache2/htdocs || exit

printf " === Checking directory permissions for /usr/local/apache2/htdocs\n"
ls -ld /usr/local/apache2/htdocs
(
printf " === Using GitHub mirror at %s\n" "$DL_LINK"
if [ ! -d "./.git" ]; then # if no git repository already exists
    printf " === No existing git repository, creating one\n"
    git config --global user.email "autodeploy@localhost"
    git config --global user.name "AutoDeploy"
    git config --global pull.rebase false # Squelch nag message
    git config --global --add safe.directory '/usr/local/apache2/htdocs' # Disable directory ownership checking, required for mounted volumes
    git clone --depth=1 "$DL_LINK" . # clone the repo with no files and no object history
else
    printf " === Using existing git repository\n"
    git config --global --add safe.directory '/usr/local/apache2/htdocs' # Disable directory ownership checking, required for mounted volumes
fi

if [ "$IMG" = "TRUE" ]; then # if user wants images
    printf " === Pulling images from GitHub... (This will take a while)\n"
    if [ ! -d "./img/.git" ]; then
        git submodule add --depth=1 -f "$IMG_LINK" /usr/local/apache2/htdocs/img
    else
        printf " === Using existing img submodule\n"
        git submodule update --remote --depth=1
    fi    
fi

printf " === Pulling latest files from GitHub...\n"
#git fetch origin --depth=1
git reset --hard origin/HEAD
git pull origin main --depth=1
if [ -f /usr/local/apache2/htdocs/package.json ]; then
    VERSION=$(jq -r .version /usr/local/apache2/htdocs/package.json) # Get version from package.json
else 
    VERSION="unknown (no package.json)"
fi


if [ -n "$(git status --porcelain)" ]; then
    git restore .
fi
)
# Since git ran as root, we need to change ownership of the htdocs and logs directories to the non-root user.
# This must happen AFTER all git operations are complete.
printf " === Setting ownership of files to %s:%s\n" "$PUID" "$PGID"
chown -R "$PUID":"$PGID" /usr/local/apache2/htdocs
chown -R "$PUID":"$PGID" /usr/local/apache2/logs

ls -la /usr/local/apache2/htdocs

printf " === Starting version %s\n" "$VERSION"
printf " === Configuring Apache to run as user %s:%s\n" "$PUID" "$PGID"

# Configure Apache to run worker processes as the specified user/group
sed -i "s/^User .*/User #$PUID/" /usr/local/apache2/conf/httpd.conf
sed -i "s/^Group .*/Group #$PGID/" /usr/local/apache2/conf/httpd.conf

httpd-foreground
