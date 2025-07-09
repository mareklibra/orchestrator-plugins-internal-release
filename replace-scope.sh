#!/usr/bin/env bash

# ==============================================================================
# Plugin Scope Rewriter
# ==============================================================================
# This script downloads Backstage plugins from the Red Hat npm registry and
# rewrites their scope from @redhat to a custom scope of your choice.
#
# What it does:
# - Downloads specified Red Hat Backstage plugins as .tgz files
# - Extracts and modifies the package.json in each plugin to:
#   * Update the package name scope (e.g., @redhat/plugin -> @acme/plugin)
#   * Update all scoped dependencies from @redhat to the new scope
#   * Update pluginPackages array in backstage configuration
# - Repacks the modified plugins with the new scope
# - Saves the rewritten plugins to ./rewritten-plugins/
#
# Usage:
#   ./replace-scope.sh <NEW_SCOPE>
#
# Example:
#   ./replace-scope.sh @acme
#
# Requirements:
# - npm (for downloading packages)
# - jq (for JSON manipulation)
# - tar (for extracting/creating .tgz files)
#
# ==============================================================================

set -euo pipefail

# === Argument check ===
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <NEW_SCOPE>"
  echo "Example: $0 @acme"
  exit 1
fi

NEW_SCOPE="$1"
ORIGINAL_SCOPE="@redhat"
REGISTRY_URL="https://npm.registry.redhat.com"

# List of plugins to process
PLUGINS=(
  "@redhat/backstage-plugin-orchestrator"
  "@redhat/backstage-plugin-orchestrator-backend-dynamic"
  "@redhat/backstage-plugin-scaffolder-backend-module-orchestrator-dynamic"
)

# Output directory
OUTPUT_DIR="./rewritten-plugins"
mkdir -p "$OUTPUT_DIR"

# Function to download, rewrite scope, and repack the plugin
process_plugin() {
  local plugin="$1"

  echo "🔽 Downloading $plugin from $REGISTRY_URL..."

  # Download .tgz file
  npm pack "$plugin" --registry="$REGISTRY_URL"
  local tgz_file
  local plugin_name_for_file=$(echo "${plugin//@/}" | sed 's/\//-/g')
  tgz_file=$(ls "${plugin_name_for_file}"-*.tgz)

  echo "📦 Processing $tgz_file..."

  local workdir
  workdir=$(mktemp -d)
  tar -xzf "$tgz_file" -C "$workdir"
  local package_json="$workdir/package/package.json"

  # Update "name" field
  jq --arg old "$ORIGINAL_SCOPE" --arg new "$NEW_SCOPE" \
    'if .name | startswith($old) then .name |= sub($old; $new) else . end' \
    "$package_json" > "$package_json.tmp" && mv "$package_json.tmp" "$package_json"

  # Update dependencies (scoped only)
  for dep_type in dependencies devDependencies peerDependencies optionalDependencies; do
    jq --arg old "$ORIGINAL_SCOPE/" --arg new "$NEW_SCOPE/" \
      "if .${dep_type} then .${dep_type} |= with_entries(if .key | startswith(\$old) then .key |= sub(\$old; \$new) else . end) else . end" \
      "$package_json" > "$package_json.tmp" && mv "$package_json.tmp" "$package_json"
  done

  # Update pluginPackages (scoped only)
  jq --arg old "$ORIGINAL_SCOPE/" --arg new "$NEW_SCOPE/" \
    'if .backstage.pluginPackages then .backstage.pluginPackages |= map(if . | startswith($old) then . |= sub($old; $new) else . end) else . end' \
    "$package_json" > "$package_json.tmp" && mv "$package_json.tmp" "$package_json"

  # Repack with new name
  pushd "$workdir" > /dev/null
  new_name=$(jq -r .name package/package.json | sed 's/@//; s/\//-/g')
  new_tgz="${new_name}.tgz"
  tar -czf "$new_tgz" package
  popd > /dev/null

  mv "$workdir/$new_tgz" "$OUTPUT_DIR/"
  echo "✅ Rewritten package saved to $OUTPUT_DIR/$new_tgz"

  # Cleanup
  rm -rf "$workdir"
  rm -f "$tgz_file"
}

# === MAIN LOOP ===
for plugin in "${PLUGINS[@]}"; do
  process_plugin "$plugin"
done

