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
# - Calculates SHA-512 integrity hashes for each rewritten plugin
# - Saves the rewritten plugins to ./rewritten-plugins/
# - Generates integrity-hashes.txt with plugin names and their integrity values
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
# - openssl (for calculating integrity hashes)
# - base64 (for encoding integrity hashes)
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
PLUGIN_VERSION="1.5.1"

# List of plugins to process
PLUGINS=(
  "@redhat/backstage-plugin-orchestrator"
  "@redhat/backstage-plugin-orchestrator-backend-dynamic"
  "@redhat/backstage-plugin-scaffolder-backend-module-orchestrator-dynamic"
)

# Output directory
OUTPUT_DIR="./rewritten-plugins"
mkdir -p "$OUTPUT_DIR"

# Initialize integrity hashes file
echo "# Plugin Integrity Hashes" > "$OUTPUT_DIR/integrity-hashes.txt"

# Function to download, rewrite scope, and repack the plugin
process_plugin() {
  local plugin="$1"

  echo "🔽 Downloading $plugin@$PLUGIN_VERSION from $REGISTRY_URL..."

  # Download .tgz file
  npm pack "$plugin@$PLUGIN_VERSION" --registry="$REGISTRY_URL"
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
  
  # Calculate integrity hash
  local integrity
  integrity=$(openssl dgst -sha512 -binary "$OUTPUT_DIR/$new_tgz" | openssl base64 -A)
  echo "✅ Rewritten package saved to $OUTPUT_DIR/$new_tgz"
  echo "🔒 Integrity: sha512-$integrity"
  
  # Save integrity to a file for reference
  local plugin_name_from_json
  plugin_name_from_json=$(jq -r .name "$package_json")
  echo "$plugin_name_from_json: sha512-$integrity" >> "$OUTPUT_DIR/integrity-hashes.txt"

  # Cleanup
  rm -rf "$workdir"
  rm -f "$tgz_file"
}

# === MAIN LOOP ===
for plugin in "${PLUGINS[@]}"; do
  process_plugin "$plugin"
done

echo ""
echo "🎉 All plugins processed successfully!"
echo "📁 Rewritten plugins saved to: $OUTPUT_DIR/"
echo "🔒 Integrity hashes saved to: $OUTPUT_DIR/integrity-hashes.txt"


