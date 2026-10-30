namespace :reactiveadmin do
  desc "Checklist of what still relies on classic ActiveAdmin. " \
    "FORMAT=md|json, OUT=file, BASELINE=file.yml (exit 1 on new items), WRITE_BASELINE=file.yml, HTML_THRESHOLD=0.1, SAMPLE=0"
  task legacy: :environment do
    exit(1) if ReactiveAdmin::LegacyInventory::CLI.run.positive?
  end
end
