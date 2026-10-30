namespace :reactiveadmin do
  desc "Classes and inline styles with no typed layout, with source lines and replacements. FORMAT=md|json, OUT=file, SAMPLE=0"
  task styles: :environment do
    ReactiveAdmin::StyleReport::CLI.run
  end
end
