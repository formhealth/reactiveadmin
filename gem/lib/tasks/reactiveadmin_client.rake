namespace :reactiveadmin do
  namespace :client do
    desc "Build the React client into config.ui.client_assets (default public/reactiveadmin). OUT=dir overrides it. Needs node >= 24 and pnpm"
    task build: :environment do
      out = ENV["OUT"].presence&.then { Rails.root.join(it) } || ReactiveAdmin::Ui::Assets.root
      puts "built #{ReactiveAdmin::Ui::ClientBuild.new(out:).call.relative_path_from(Rails.root)}"
    rescue ReactiveAdmin::Ui::ClientBuild::Error => e
      abort e.message
    end
  end
end
