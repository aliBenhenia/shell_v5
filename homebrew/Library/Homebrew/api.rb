# typed: true
# frozen_string_literal: true

require "api/analytics"
require "api/cask"
require "api/formula"
require "extend/cachable"

module Homebrew
  # Helper functions for using Homebrew's formulae.brew.sh API.
  #
  # @api private
  module API
    extend T::Sig

    extend Cachable

    HOMEBREW_CACHE_API = (HOMEBREW_CACHE/"api").freeze

    sig { params(endpoint: String).returns(Hash) }
    def self.fetch(endpoint)
      return cache[endpoint] if cache.present? && cache.key?(endpoint)

      api_url = "#{Homebrew::EnvConfig.api_domain}/#{endpoint}"
      output = Utils::Curl.curl_output("--fail", api_url)
      if !output.success? && Homebrew::EnvConfig.api_domain != HOMEBREW_API_DEFAULT_DOMAIN
        # Fall back to the default API domain and try again
        api_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{endpoint}"
        output = Utils::Curl.curl_output("--fail", api_url)
      end
      raise ArgumentError, "No file found at #{Tty.underline}#{api_url}#{Tty.reset}" unless output.success?

      cache[endpoint] = JSON.parse(output.stdout)
    rescue JSON::ParserError
      raise ArgumentError, "Invalid JSON file: #{Tty.underline}#{api_url}#{Tty.reset}"
    end

    sig { params(endpoint: String, target: Pathname).returns([T.any(Array, Hash), T::Boolean]) }
    def self.fetch_json_api_file(endpoint, target:)
      retry_count = 0
      url = "#{Homebrew::EnvConfig.api_domain}/#{endpoint}"
      default_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{endpoint}"

      if Homebrew.running_as_root_but_not_owned_by_root? &&
         (!target.exist? || target.empty?)
        odie "Need to download #{url} but cannot as root! Run `brew update` without `sudo` first then try again."
      end

      # TODO: consider using more of Utils::Curl
      curl_args = %W[
        --compressed
        --speed-limit #{ENV.fetch("HOMEBREW_CURL_SPEED_LIMIT")}
        --speed-time #{ENV.fetch("HOMEBREW_CURL_SPEED_TIME")}
      ]
      curl_args << "--progress-bar" unless Context.current.verbose?
      curl_args << "--verbose" if Homebrew::EnvConfig.curl_verbose?
      curl_args << "--silent" if !$stdout.tty? || Context.current.quiet?

      skip_download = target.exist? &&
                      !target.empty? &&
                      (!Homebrew.auto_update_command? ||
                        Homebrew::EnvConfig.no_auto_update? ||
                      ((Time.now - Homebrew::EnvConfig.api_auto_update_secs.to_i) < target.mtime))
      skip_download ||= Homebrew.running_as_root_but_not_owned_by_root?

      json_data = begin
        begin
          args = curl_args.dup
          args.prepend("--time-cond", target.to_s) if target.exist? && !target.empty?
          unless skip_download
            ohai "Downloading #{url}" if $stdout.tty? && !Context.current.quiet?
            # Disable retries here, we handle them ourselves below.
            Utils::Curl.curl_download(*args, url, to: target, retries: 0, show_error: false)
          end
        rescue ErrorDuringExecution
          if url == default_url
            raise unless target.exist?
            raise if target.empty?
          elsif retry_count.zero? || !target.exist? || target.empty?
            # Fall back to the default API domain and try again
            # This block will be executed only once, because we set `url` to `default_url`
            url = default_url
            target.unlink if target.exist? && target.empty?
            skip_download = false

            retry
          end

          opoo "#{target.basename}: update failed, falling back to cached version."
        end

        FileUtils.touch(target) unless skip_download
        JSON.parse(target.read)
      rescue JSON::ParserError
        target.unlink
        retry_count += 1
        skip_download = false
        odie "Cannot download non-corrupt #{url}!" if retry_count > Homebrew::EnvConfig.curl_retries.to_i

        retry
      end

      if endpoint.end_with?(".jws.json")
        success, data = verify_and_parse_jws(json_data)
        unless success
          target.unlink
          odie <<~EOS
            Failed to verify integrity (#{data}) of:
              #{url}
            Potential MITM attempt detected. Please run `brew update` and try again.
          EOS
        end
        [data, !skip_download]
      else
        [json_data, !skip_download]
      end
    end

    sig {
      params(name: String, path: T.any(Pathname, String), git_head: String,
             sha256: T.nilable(String)).returns(String)
    }
    def self.fetch_homebrew_cask_source(name, path:, git_head:, sha256: nil)
      # TODO: unify with formula logic (https://github.com/Homebrew/brew/issues/14746)
      raw_endpoint = "#{git_head}/#{path}"
      return cache[raw_endpoint] if cache.present? && cache.key?(raw_endpoint)

      # This API sometimes returns random 404s so needs a fallback at formulae.brew.sh.
      raw_source_url = "https://raw.githubusercontent.com/Homebrew/homebrew-cask/#{raw_endpoint}"
      api_source_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/cask-source/#{name}.rb"

      url = raw_source_url
      output = Utils::Curl.curl_output("--fail", url)

      if !output.success? || output.blank?
        url = api_source_url
        output = Utils::Curl.curl_output("--fail", url)
        if !output.success? || output.blank?
          raise ArgumentError, <<~EOS
            No valid file found at either of:
            #{Tty.underline}#{raw_source_url}#{Tty.reset}
            #{Tty.underline}#{api_source_url}#{Tty.reset}
          EOS
        end
      end

      cask_source = output.stdout
      actual_sha256 = Digest::SHA256.hexdigest(cask_source)
      if sha256 && actual_sha256 != sha256
        raise ArgumentError, <<~EOS
          SHA256 mismatch
          Expected: #{Formatter.success(sha256.to_s)}
            Actual: #{Formatter.error(actual_sha256.to_s)}
               URL: #{url}
          Check if you can access the URL in your browser.
          Regardless, try again in a few minutes.
        EOS
      end

      cache[raw_endpoint] = cask_source
    end

    sig { params(json: Hash).returns(Hash) }
    def self.merge_variations(json)
      bottle_tag = ::Utils::Bottles::Tag.new(system: Homebrew::SimulateSystem.current_os,
                                             arch:   Homebrew::SimulateSystem.current_arch)

      if (variations = json["variations"].presence) &&
         (variation = variations[bottle_tag.to_s].presence)
        json = json.merge(variation)
      end

      json.except("variations")
    end

    sig { params(names: T::Array[String], type: String, regenerate: T::Boolean).returns(T::Boolean) }
    def self.write_names_file(names, type, regenerate:)
      names_path = HOMEBREW_CACHE_API/"#{type}_names.txt"
      if !names_path.exist? || regenerate
        names_path.write(names.join("\n"))
        return true
      end

      false
    end

    sig { params(json_data: Hash).returns([T::Boolean, T.any(String, Array, Hash)]) }
    private_class_method def self.verify_and_parse_jws(json_data)
      signatures = json_data["signatures"]
      homebrew_signature = signatures&.find { |sig| sig.dig("header", "kid") == "homebrew-1" }
      return false, "key not found" if homebrew_signature.nil?

      header = JSON.parse(Base64.urlsafe_decode64(homebrew_signature["protected"]))
      if header["alg"] != "PS512" || header["b64"] != false # NOTE: nil has a meaning of true
        return false, "invalid algorithm"
      end

      require "openssl"

      pubkey = OpenSSL::PKey::RSA.new((HOMEBREW_LIBRARY_PATH/"api/homebrew-1.pem").read)
      signing_input = "#{homebrew_signature["protected"]}.#{json_data["payload"]}"
      unless pubkey.verify_pss("SHA512",
                               Base64.urlsafe_decode64(homebrew_signature["signature"]),
                               signing_input,
                               salt_length: :digest,
                               mgf1_hash:   "SHA512")
        return false, "signature mismatch"
      end

      [true, JSON.parse(json_data["payload"])]
    end
  end
end
