# typed: true
# frozen_string_literal: true

# Never `require` anything in this file (except English). It needs to be able to
# work as the first item in `brew.rb` so we can load gems with Bundler when
# needed before anything else is loaded (e.g. `json`).

require "English"

module Homebrew
  # Keep in sync with the `Gemfile.lock`'s BUNDLED WITH.
  # After updating this, run `brew vendor-gems --update=--bundler`.
  HOMEBREW_BUNDLER_VERSION = "2.3.26"

  module_function

  # @api private
  def gemfile
    File.join(ENV.fetch("HOMEBREW_LIBRARY"), "Homebrew", "Gemfile")
  end

  # @api private
  def valid_gem_groups
    install_bundler!
    require "bundler"

    Bundler.with_unbundled_env do
      ENV["BUNDLE_GEMFILE"] = gemfile
      groups = Bundler::Definition.build(Bundler.default_gemfile, Bundler.default_lockfile, false).groups
      groups.delete(:default)
      groups.map(&:to_s)
    end
  end

  def ruby_bindir
    "#{RbConfig::CONFIG["prefix"]}/bin"
  end

  def ohai_if_defined(message)
    if defined?(ohai)
      $stderr.ohai message
    else
      $stderr.puts "==> #{message}"
    end
  end

  def opoo_if_defined(message)
    if defined?(opoo)
      $stderr.opoo message
    else
      $stderr.puts "Warning: #{message}"
    end
  end

  def odie_if_defined(message)
    if defined?(odie)
      odie message
    else
      $stderr.puts "Error: #{message}"
      exit 1
    end
  end

  def setup_gem_environment!(setup_path: true)
    require "rubygems"
    raise "RubyGems too old!" if Gem::Version.new(Gem::VERSION) < Gem::Version.new("2.2.0")

    # Match where our bundler gems are.
    gem_home = "#{HOMEBREW_LIBRARY_PATH}/vendor/bundle/ruby/#{RbConfig::CONFIG["ruby_version"]}"
    Gem.paths = {
      "GEM_HOME" => gem_home,
      "GEM_PATH" => gem_home,
    }

    # Set TMPDIR so Xcode's `make` doesn't fall back to `/var/tmp/`,
    # which may be not user-writable.
    ENV["TMPDIR"] = ENV.fetch("HOMEBREW_TEMP", nil)

    return unless setup_path

    # Add necessary Ruby and Gem binary directories to `PATH`.
    paths = ENV.fetch("PATH").split(":")
    paths.unshift(ruby_bindir) unless paths.include?(ruby_bindir)
    paths.unshift(Gem.bindir) unless paths.include?(Gem.bindir)
    ENV["PATH"] = paths.compact.join(":")

    # Set envs so the above binaries can be invoked.
    # We don't do this unless requested as some formulae may invoke system Ruby instead of ours.
    ENV["GEM_HOME"] = gem_home
    ENV["GEM_PATH"] = gem_home
  end

  def install_gem!(name, version: nil, setup_gem_environment: true)
    setup_gem_environment! if setup_gem_environment

    specs = Gem::Specification.find_all_by_name(name, version)

    if specs.empty?
      ohai_if_defined "Installing '#{name}' gem"
      # `document: []` is equivalent to --no-document
      # `build_args: []` stops ARGV being used as a default
      # `env_shebang: true` makes shebangs generic to allow switching between system and Portable Ruby
      specs = Gem.install name, version, document: [], build_args: [], env_shebang: true
    end

    specs += specs.flat_map(&:runtime_dependencies)
                  .flat_map(&:to_specs)

    # Add the specs to the $LOAD_PATH.
    specs.each do |spec|
      spec.require_paths.each do |path|
        full_path = File.join(spec.full_gem_path, path)
        $LOAD_PATH.unshift full_path unless $LOAD_PATH.include?(full_path)
      end
    end
  rescue Gem::UnsatisfiableDependencyError
    odie_if_defined "failed to install the '#{name}' gem."
  end

  def install_gem_setup_path!(name, version: nil, executable: name, setup_gem_environment: true)
    install_gem!(name, version: version, setup_gem_environment: setup_gem_environment)
    return if find_in_path(executable)

    odie_if_defined <<~EOS
      the '#{name}' gem is installed but couldn't find '#{executable}' in the PATH:
        #{ENV.fetch("PATH")}
    EOS
  end

  def find_in_path(executable)
    ENV.fetch("PATH").split(":").find do |path|
      File.executable?(File.join(path, executable))
    end
  end

  def install_bundler!
    setup_gem_environment!
    install_gem_setup_path!(
      "bundler",
      version:               HOMEBREW_BUNDLER_VERSION,
      executable:            "bundle",
      setup_gem_environment: false,
    )
  end

  def install_bundler_gems!(only_warn_on_failure: false, setup_path: true, groups: [])
    old_path = ENV.fetch("PATH", nil)
    old_gem_path = ENV.fetch("GEM_PATH", nil)
    old_gem_home = ENV.fetch("GEM_HOME", nil)
    old_bundle_gemfile = ENV.fetch("BUNDLE_GEMFILE", nil)
    old_bundle_with = ENV.fetch("BUNDLE_WITH", nil)
    old_bundle_frozen = ENV.fetch("BUNDLE_FROZEN", nil)
    old_sdkroot = ENV.fetch("SDKROOT", nil)

    invalid_groups = groups - valid_gem_groups
    raise ArgumentError, "Invalid gem groups: #{invalid_groups.join(", ")}" unless invalid_groups.empty?

    install_bundler!

    require "settings"

    # Combine the passed groups with the ones stored in settings
    groups |= (Homebrew::Settings.read(:gemgroups)&.split(";") || [])
    groups.sort!

    ENV["BUNDLE_GEMFILE"] = gemfile
    ENV["BUNDLE_WITH"] = groups.join(" ")
    ENV["BUNDLE_FROZEN"] = "true"

    # System Ruby does not pick up the correct SDK by default.
    if ENV["HOMEBREW_MACOS_SYSTEM_RUBY_NEW_ENOUGH"]
      macos_major = ENV.fetch("HOMEBREW_MACOS_VERSION").partition(".").first
      sdkroot = "/Library/Developer/CommandLineTools/SDKs/MacOSX#{macos_major}.sdk"
      ENV["SDKROOT"] = sdkroot if Dir.exist?(sdkroot)
    end

    if @bundle_installed_groups != groups
      bundle = File.join(find_in_path("bundle"), "bundle")
      bundle_check_output = `#{bundle} check 2>&1`
      bundle_check_failed = !$CHILD_STATUS.success?

      # for some reason sometimes the exit code lies so check the output too.
      bundle_installed = if bundle_check_failed || bundle_check_output.include?("Install missing gems")
        if system bundle, "install"
          true
        else
          message = <<~EOS
            failed to run `#{bundle} install`!
          EOS
          if only_warn_on_failure
            opoo_if_defined message
          else
            odie_if_defined message
          end
          false
        end
      else
        true
      end

      if bundle_installed
        Homebrew::Settings.write(:gemgroups, groups.join(";"))
        @bundle_installed_groups = groups
      end
    end

    setup_gem_environment!
  ensure
    unless setup_path
      # Reset the paths. We need to have at least temporarily changed them while invoking `bundle`.
      ENV["PATH"] = old_path
      ENV["GEM_PATH"] = old_gem_path
      ENV["GEM_HOME"] = old_gem_home
      ENV["BUNDLE_GEMFILE"] = old_bundle_gemfile
      ENV["BUNDLE_WITH"] = old_bundle_with
      ENV["BUNDLE_FROZEN"] = old_bundle_frozen
    end
    ENV["SDKROOT"] = old_sdkroot
  end
end
