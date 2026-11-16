#!/usr/bin/env bash
# Installs the built gem from a local index into a Gemfile with no path to this checkout, then runs
# smoke_packaged_gem.rb against it. Run from gem/ after `rake package`.
set -euo pipefail

scratch="${SCRATCH:-$(mktemp -d)}"
mkdir -p "$scratch/index/gems"
cp pkg/reactiveadmin-*.gem "$scratch/index/gems/"
gem generate_index -d "$scratch/index"
cat > "$scratch/Gemfile" <<GEMFILE
source "https://rubygems.org"
source "file://$scratch/index" do
  gem "reactiveadmin"
end
gem "rails", "~> 8.1.4"
gem "activeadmin", "~> 3.5"
gem "pundit"
gem "sprockets-rails"
gem "sqlite3"
GEMFILE

export BUNDLE_GEMFILE="$scratch/Gemfile" BUNDLE_PATH="$scratch/bundle"
bundle install
bundle exec ruby script/smoke_packaged_gem.rb
# Again under another prefix: the build refers to its own files relatively, so no rebuild is needed.
REACTIVEADMIN_ASSET_PREFIX=/admin-ui bundle exec ruby script/smoke_packaged_gem.rb
