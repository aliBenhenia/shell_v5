# typed: false
# frozen_string_literal: true

require "hardware"
require "software_spec"
require "development_tools"
require "extend/ENV"
require "system_command"

# Helper module for querying information about the system configuration.
#
# @api private
module SystemConfig
  class << self
    extend T::Sig

    include SystemCommand::Mixin

    def clang
      @clang ||= if DevelopmentTools.installed?
        DevelopmentTools.clang_version
      else
        Version::NULL
      end
    end

    def clang_build
      @clang_build ||= if DevelopmentTools.installed?
        DevelopmentTools.clang_build_version
      else
        Version::NULL
      end
    end

    sig { returns(Pathname) }
    def homebrew_repo
      HOMEBREW_REPOSITORY.dup.extend(GitRepositoryExtension)
    end

    sig { returns(String) }
    def head
      homebrew_repo.git_head || "(none)"
    end

    sig { returns(String) }
    def last_commit
      homebrew_repo.git_last_commit || "never"
    end

    sig { returns(String) }
    def origin
      homebrew_repo.git_origin || "(none)"
    end

    sig { returns(String) }
    def core_tap_head
      CoreTap.instance.git_head || "(none)"
    end

    sig { returns(String) }
    def core_tap_last_commit
      CoreTap.instance.git_last_commit || "never"
    end

    sig { returns(String) }
    def core_tap_branch
      CoreTap.instance.git_branch || "(none)"
    end

    sig { returns(String) }
    def core_tap_origin
      CoreTap.instance.remote || "(none)"
    end

    sig { returns(String) }
    def describe_clang
      return "N/A" if clang.null?

      if clang_build.null?
        clang.to_s
      else
        "#{clang} build #{clang_build}"
      end
    end

    def describe_path(path)
      return "N/A" if path.nil?

      realpath = path.realpath
      if realpath == path
        path
      else
        "#{path} => #{realpath}"
      end
    end

    sig { returns(String) }
    def describe_homebrew_ruby_version
      case RUBY_VERSION
      when /^1\.[89]/, /^2\.0/
        "#{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}"
      else
        RUBY_VERSION
      end
    end

    sig { returns(String) }
    def describe_homebrew_ruby
      "#{describe_homebrew_ruby_version} => #{RUBY_PATH}"
    end

    sig { returns(T.nilable(String)) }
    def hardware
      return if Hardware::CPU.type == :dunno

      "CPU: #{Hardware.cores_as_words}-core #{Hardware::CPU.bits}-bit #{Hardware::CPU.family}"
    end

    sig { returns(String) }
    def kernel
      `uname -m`.chomp
    end

    sig { returns(String) }
    def describe_git
      return "N/A" unless Utils::Git.available?

      "#{Utils::Git.version} => #{Utils::Git.path}"
    end

    sig { returns(String) }
    def describe_curl
      out, = system_command(curl_executable, args: ["--version"], verbose: false)

      if /^curl (?<curl_version>[\d.]+)/ =~ out
        "#{curl_version} => #{curl_path}"
      else
        "N/A"
      end
    end

    def core_tap_config(out = $stdout)
      if CoreTap.instance.installed?
        out.puts "Core tap origin: #{core_tap_origin}"
        out.puts "Core tap HEAD: #{core_tap_head}"
        out.puts "Core tap last commit: #{core_tap_last_commit}"
        out.puts "Core tap branch: #{core_tap_branch}"
      end

      if (formula_json = Homebrew::API::HOMEBREW_CACHE_API/"formula.jws.json") && formula_json.exist?
        out.puts "Core tap JSON: #{formula_json.mtime.utc.strftime("%d %b %H:%M UTC")}"
      elsif !CoreTap.instance.installed?
        out.puts "Core tap: N/A"
      end
    end

    def homebrew_config(out = $stdout)
      out.puts "HOMEBREW_VERSION: #{HOMEBREW_VERSION}"
      out.puts "ORIGIN: #{origin}"
      out.puts "HEAD: #{head}"
      out.puts "Last commit: #{last_commit}"
    end

    def homebrew_env_config(out = $stdout)
      out.puts "HOMEBREW_PREFIX: #{HOMEBREW_PREFIX}"
      {
        HOMEBREW_REPOSITORY: Homebrew::DEFAULT_REPOSITORY,
        HOMEBREW_CELLAR:     Homebrew::DEFAULT_CELLAR,
      }.freeze.each do |key, default|
        value = Object.const_get(key)
        out.puts "#{key}: #{value}" if value.to_s != default.to_s
      end

      Homebrew::EnvConfig::ENVS.each do |env, hash|
        method_name = Homebrew::EnvConfig.env_method_name(env, hash)

        if hash[:boolean]
          out.puts "#{env}: set" if Homebrew::EnvConfig.send(method_name)
          next
        end

        value = Homebrew::EnvConfig.send(method_name)
        next unless value
        next if (default = hash[:default].presence) && value.to_s == default.to_s

        if ENV.sensitive?(env)
          out.puts "#{env}: set"
        else
          out.puts "#{env}: #{value}"
        end
      end
      out.puts "Homebrew Ruby: #{describe_homebrew_ruby}"
    end

    def host_software_config(out = $stdout)
      out.puts "Clang: #{describe_clang}"
      out.puts "Git: #{describe_git}"
      out.puts "Curl: #{describe_curl}"
    end

    def dump_verbose_config(out = $stdout)
      homebrew_config(out)
      core_tap_config(out)
      homebrew_env_config(out)
      out.puts hardware if hardware
      host_software_config(out)
    end
    alias dump_generic_verbose_config dump_verbose_config
  end
end

require "extend/os/system_config"
