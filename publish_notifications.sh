#!/bin/bash

# Inputs
read -p "Enter new version to release: " version
read -p "Enter Organization name on npmjs.com (default: masayag-tests): " npmOrgName
npmOrgName=${npmOrgName:-masayag-tests}
read -p "Enter Organization name on github.com to fetch the code (default: masayag): " githubOrgName
githubOrgName=${githubOrgName:-masayag}
read -p "Enter Branch name on github.com to fetch the code (default: main): " githubRefName
githubRefName=${githubRefName:-main}
read -p "Dry run (true/false, default: true): " dryRun
dryRun=${dryRun:-true}

# Ensure GITHUB_TOKEN and NPM_TOKEN are set in your environment variables

# Checkout backstage-plugins
git clone https://github.com/$githubOrgName/backstage-plugins.git --branch $githubRefName --depth 1

# Get the commit hash
commit_hash=$(git -C backstage-plugins rev-parse HEAD)
echo "Commit Hash: $commit_hash"

# Setup Node.js (ensure Node.js and Yarn are installed)
cd backstage-plugins

# Install dependencies
yarn --prefer-offline --frozen-lockfile

# Update the package version
echo "Update version of plugins/notifications and plugins/notifications-backend to $version"
(cd plugins/notifications && yarn version --new-version $version --no-git-tag-version)
(cd plugins/notifications-backend && yarn version --new-version $version --no-git-tag-version)

# Replace the package organization name
old_string="@janus-idp/plugin-notifications"
new_string="@$npmOrgName/plugin-notifications"
grep -rl "$old_string" | xargs sed -i "s|$old_string|$new_string|g"

old_string="janus-idp.plugin-notifications"
new_string="$npmOrgName.plugin-notifications"
grep -rl "$old_string" | xargs sed -i "s|$old_string|$new_string|g" || true

# Refresh dependencies
yarn --prefer-offline --frozen-lockfile

# Build the packages
echo "Build plugins/notifications and plugins/notifications-backend"
(cd plugins/notifications && yarn tsc && yarn build && yarn export-dynamic)
(cd plugins/notifications-backend && yarn tsc && yarn build && yarn export-dynamic)

# Delete exports property from notifications-backend/dist-dynamic
jq 'del(.exports)' plugins/notifications-backend/dist-dynamic/package.json > temp.json && mv temp.json plugins/notifications-backend/dist-dynamic/package.json

# Publish packages to npmjs.com
if [ "$dryRun" = false ]; then
    echo "Publishing packages to npmjs.com"
    echo "//registry.npmjs.org/:_authToken=$NPM_TOKEN" >> ~/.npmrc
    folders=("plugins/notifications" "plugins/notifications-backend" "plugins/notifications-backend/dist-dynamic")
    for folder in "${folders[@]}"; do
      (cd $folder && npm publish --access public)
    done
fi

# Publish the release on GitHub (requires GitHub CLI - gh)
if [ "$dryRun" = false ]; then
    gh release create "$version" --title "$version" --notes "Commit from $githubOrgName/backstage-plugins @ $githubRefName\n$commit_hash"
fi

