# frozen_string_literal: true

module SprocketsHelpers
  module_function

  def available?
    # We can't scan for sprockets in gemfile_lock because it's
    #   a dependency of Rails even if not required.
    # We also can't scan for defined?(Sprockets) because this is used to
    #   require Sprockets in the config/application.rb
    # !!Bundler.locked_gems.specs.find {|gem_spec| gem_spec.name == 'sprockets'}
    ENV.fetch("BUNDLE_GEMFILE", nil).include?("sprockets")
  end

  # The block depends on sprockets, don't run it if sprockets is missing
  def when_available
    return unless available?

    yield
  end

  def clear_sprockets_cache
    # Remove cached files
    Rails.root.join("tmp/cache").tap do |tmp|
      tmp.rmtree if tmp.exist?
      tmp.mkpath
    end
  end

  def fetch_asset_body(asset_logical_path)
    Rails.application.assets[asset_logical_path].to_s
  end

  # Sprockets 2 doesn't expire this assets well in
  # this kind of setting,
  # so override `fresh?` to mark it as expired.
  def manually_expire_asset(asset_name)
    asset = Rails.application.assets[asset_name]
    def asset.fresh?(_env)
      false
    end
  end

  def precompile_assets
    invoke_assets_precompile_task

    if Rails.application.respond_to?(:assets_manifest)
      # Make a new manifest since assets weren't compiled before
      config = Rails.application.config
      path = File.join(config.paths["public"].first, config.assets.prefix)
      new_manifest = Sprockets::Manifest.new(Rails.application.assets, path)
      Rails.application.assets_manifest = new_manifest
    end

    assets_directory = File.expand_path("../dummy/public/assets", __dir__)
    raise "Asset precompilation failed" unless Dir.exist?(assets_directory)
  end

  def clear_precompiled_assets
    assets_directory = File.expand_path("../dummy/public/assets", __dir__)
    FileUtils.rm_r(assets_directory)
    ENV.delete("RAILS_GROUPS")
  end

  class << self
    private

    def invoke_assets_precompile_task
      # Changing directories is required because:
      # - assets:precompile runs webpacker:compile when availabled
      # - webpacker:compile depends on `./bin/webpack`, so `.` must be the app root
      Dir.chdir("./test/dummy") do
        ENV["RAILS_GROUPS"] = "assets" # required for Rails 3.2
        Rake::Task["assets:precompile"].reenable

        if Rails::VERSION::MAJOR == 3
          Rake::Task["assets:precompile:all"].reenable
          Rake::Task["assets:precompile:primary"].reenable
          Rake::Task["assets:precompile:nondigest"].reenable
        end

        Rake::Task["assets:precompile"].invoke
      end
    end
  end
end
