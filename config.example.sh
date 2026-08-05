# herdr-git-detail configuration.
#
# Copy to $HERDR_PLUGIN_CONFIG_DIR/config.sh (or keep next to the plugin) and
# edit. All values are optional; defaults are shown.

# Seconds between status passes. Lower = fresher, higher = less CPU.
GIT_DETAIL_INTERVAL=5

# Text shown when the working tree is clean.
GIT_DETAIL_CLEAN="clean"

# Source label reported to herdr (visible in `workspace get` tokens).
GIT_DETAIL_SOURCE="git-detail"
