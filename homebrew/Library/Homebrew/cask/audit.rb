# typed: true
# frozen_string_literal: true

require "cask/denylist"
require "cask/download"
require "digest"
require "livecheck/livecheck"
require "utils/curl"
require "utils/git"
require "utils/shared_audits"

module Cask
  # Audit a cask for various problems.
  #
  # @api private
  class Audit
    extend T::Sig

    extend Predicable

    attr_reader :cask, :download

    attr_predicate :new_cask?, :strict?, :signing?, :online?, :token_conflicts?

    def initialize(
      cask,
      download: nil, quarantine: nil,
      token_conflicts: nil, online: nil, strict: nil, signing: nil,
      new_cask: nil, only: [], except: []
    )
      # `new_cask` implies `online`, `token_conflicts`, `strict` and `signing`
      online = new_cask if online.nil?
      strict = new_cask if strict.nil?
      signing = new_cask if signing.nil?
      token_conflicts = new_cask if token_conflicts.nil?

      # `online` and `signing` imply `download`
      download = online || signing if download.nil?

      @cask = cask
      @download = Download.new(cask, quarantine: quarantine) if download
      @online = online
      @strict = strict
      @signing = signing
      @new_cask = new_cask
      @token_conflicts = token_conflicts
      @only = only || []
      @except = except || []
    end

    def run!
      only_audits = @only
      except_audits = @except

      private_methods.map(&:to_s).grep(/^audit_/).each do |audit_method_name|
        name = audit_method_name.delete_prefix("audit_")
        next if !only_audits.empty? && only_audits&.exclude?(name)
        next if except_audits&.include?(name)

        send(audit_method_name)
      end

      self
    rescue => e
      odebug e, e.backtrace
      add_error "exception while auditing #{cask}: #{e.message}"
      self
    end

    def errors
      @errors ||= []
    end

    sig { returns(T::Boolean) }
    def errors?
      errors.any?
    end

    sig { returns(T::Boolean) }
    def success?
      !errors?
    end

    sig { params(message: T.nilable(String), location: T.nilable(String), strict_only: T::Boolean).void }
    def add_error(message, location: nil, strict_only: false)
      # Only raise non-critical audits if the user specified `--strict`.
      return if strict_only && !@strict

      errors << ({ message: message, location: location })
    end

    def result
      Formatter.error("failed") if errors?
    end

    sig { returns(T.nilable(String)) }
    def summary
      return if success?

      summary = ["audit for #{cask}: #{result}"]

      errors.each do |error|
        summary << " #{Formatter.error("-")} #{error[:message]}"
      end

      summary.join("\n")
    end

    private

    sig { void }
    def audit_untrusted_pkg
      odebug "Auditing pkg stanza: allow_untrusted"

      return if @cask.sourcefile_path.nil?

      tap = @cask.tap
      return if tap.nil?
      return if tap.user != "Homebrew"

      return if cask.artifacts.none? { |k| k.is_a?(Artifact::Pkg) && k.stanza_options.key?(:allow_untrusted) }

      add_error "allow_untrusted is not permitted in official Homebrew Cask taps"
    end

    sig { void }
    def audit_stanza_requires_uninstall
      odebug "Auditing stanzas which require an uninstall"

      return if cask.artifacts.none? { |k| k.is_a?(Artifact::Pkg) || k.is_a?(Artifact::Installer) }
      return if cask.artifacts.any?(Artifact::Uninstall)

      add_error "installer and pkg stanzas require an uninstall stanza"
    end

    sig { void }
    def audit_single_pre_postflight
      odebug "Auditing preflight and postflight stanzas"

      if cask.artifacts.count { |k| k.is_a?(Artifact::PreflightBlock) && k.directives.key?(:preflight) } > 1
        add_error "only a single preflight stanza is allowed"
      end

      count = cask.artifacts.count do |k|
        k.is_a?(Artifact::PostflightBlock) &&
          k.directives.key?(:postflight)
      end
      return unless count > 1

      add_error "only a single postflight stanza is allowed"
    end

    sig { void }
    def audit_single_uninstall_zap
      odebug "Auditing single uninstall_* and zap stanzas"

      count = cask.artifacts.count do |k|
        k.is_a?(Artifact::PreflightBlock) &&
          k.directives.key?(:uninstall_preflight)
      end

      add_error "only a single uninstall_preflight stanza is allowed" if count > 1

      count = cask.artifacts.count do |k|
        k.is_a?(Artifact::PostflightBlock) &&
          k.directives.key?(:uninstall_postflight)
      end

      add_error "only a single uninstall_postflight stanza is allowed" if count > 1

      return unless cask.artifacts.count { |k| k.is_a?(Artifact::Zap) } > 1

      add_error "only a single zap stanza is allowed"
    end

    sig { void }
    def audit_required_stanzas
      odebug "Auditing required stanzas"
      [:version, :sha256, :url, :homepage].each do |sym|
        add_error "a #{sym} stanza is required" unless cask.send(sym)
      end
      add_error "at least one name stanza is required" if cask.name.empty?
      # TODO: specific DSL knowledge should not be spread around in various files like this
      rejected_artifacts = [:uninstall, :zap]
      installable_artifacts = cask.artifacts.reject { |k| rejected_artifacts.include?(k) }
      add_error "at least one activatable artifact stanza is required" if installable_artifacts.empty?
    end

    sig { void }
    def audit_description
      # Fonts seldom benefit from descriptions and requiring them disproportionately
      # increases the maintenance burden.
      return if cask.tap == "homebrew/cask-fonts"

      add_error("Cask should have a description. Please add a `desc` stanza.", strict_only: true) if cask.desc.blank?
    end

    sig { void }
    def audit_version_special_characters
      return unless cask.version

      return if cask.version.latest?

      raw_version = cask.version.raw_version
      return if raw_version.exclude?(":") && raw_version.exclude?("/")

      add_error "version should not contain colons or slashes"
    end

    sig { void }
    def audit_no_string_version_latest
      return unless cask.version

      odebug "Auditing version :latest does not appear as a string ('latest')"
      return unless cask.version.raw_version == "latest"

      add_error "you should use version :latest instead of version 'latest'"
    end

    sig { void }
    def audit_sha256_no_check_if_latest
      return unless cask.sha256

      odebug "Auditing sha256 :no_check with version :latest"
      return unless cask.version.latest?
      return if cask.sha256 == :no_check

      add_error "you should use sha256 :no_check when version is :latest"
    end

    sig { void }
    def audit_sha256_no_check_if_unversioned
      return unless cask.sha256
      return if cask.sha256 == :no_check

      add_error "Use `sha256 :no_check` when URL is unversioned." if cask.url&.unversioned?
    end

    sig { void }
    def audit_sha256_actually_256
      return unless cask.sha256

      odebug "Auditing sha256 string is a legal SHA-256 digest"
      return unless cask.sha256.is_a?(Checksum)
      return if cask.sha256.length == 64 && cask.sha256[/^[0-9a-f]+$/i]

      add_error "sha256 string must be of 64 hexadecimal characters"
    end

    sig { void }
    def audit_sha256_invalid
      return unless cask.sha256

      odebug "Auditing sha256 is not a known invalid value"
      empty_sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      return unless cask.sha256 == empty_sha256

      add_error "cannot use the sha256 for an empty string: #{empty_sha256}"
    end

    sig { void }
    def audit_appcast
      return unless cask.appcast

      add_error "`appcast` should be replaced with a `livecheck`."
    end

    sig { void }
    def audit_latest_with_livecheck
      return unless cask.version.latest?
      return unless cask.livecheckable?
      return if cask.livecheck.skip?

      add_error "Casks with a `livecheck` should not use `version :latest`."
    end

    sig { void }
    def audit_latest_with_auto_updates
      return unless cask.version.latest?
      return unless cask.auto_updates

      add_error "Casks with `version :latest` should not use `auto_updates`."
    end

    LIVECHECK_REFERENCE_URL = "https://docs.brew.sh/Cask-Cookbook#stanza-livecheck"

    sig { params(livecheck_result: T.any(NilClass, T::Boolean, Symbol)).void }
    def audit_hosting_with_livecheck(livecheck_result: audit_livecheck_version)
      return if cask.discontinued?
      return if cask.version.latest?
      return if block_url_offline?
      return if cask.livecheckable?
      return if livecheck_result == :auto_detected

      add_livecheck = "please add a livecheck. See #{Formatter.url(LIVECHECK_REFERENCE_URL)}"

      case cask.url.to_s
      when %r{sourceforge.net/(\S+)}
        return unless online?

        add_error "Download is hosted on SourceForge, #{add_livecheck}"
      when %r{dl.devmate.com/(\S+)}
        add_error "Download is hosted on DevMate, #{add_livecheck}"
      when %r{rink.hockeyapp.net/(\S+)}
        add_error "Download is hosted on HockeyApp, #{add_livecheck}"
      end
    end

    SOURCEFORGE_OSDN_REFERENCE_URL = "https://docs.brew.sh/Cask-Cookbook#sourceforgeosdn-urls"

    sig { void }
    def audit_download_url_format
      return unless cask.url

      odebug "Auditing URL format"
      if bad_sourceforge_url?
        add_error "SourceForge URL format incorrect. See #{Formatter.url(SOURCEFORGE_OSDN_REFERENCE_URL)}"
      elsif bad_osdn_url?
        add_error "OSDN URL format incorrect. See #{Formatter.url(SOURCEFORGE_OSDN_REFERENCE_URL)}"
      end
    end

    VERIFIED_URL_REFERENCE_URL = "https://docs.brew.sh/Cask-Cookbook#when-url-and-homepage-domains-differ-add-verified"

    sig { void }
    def audit_unnecessary_verified
      return if block_url_offline?
      return unless verified_present?
      return unless url_match_homepage?
      return unless verified_matches_url?

      add_error "The URL's domain #{Formatter.url(domain)} matches the homepage domain " \
                "#{Formatter.url(homepage)}, the 'verified' parameter of the 'url' stanza is unnecessary. " \
                "See #{Formatter.url(VERIFIED_URL_REFERENCE_URL)}"
    end

    sig { void }
    def audit_missing_verified
      return if block_url_offline?
      return if file_url?
      return if url_match_homepage?
      return if verified_present?

      add_error "The URL's domain #{Formatter.url(domain)} does not match the homepage domain " \
                "#{Formatter.url(homepage)}, a 'verified' parameter has to be added to the 'url' stanza. " \
                "See #{Formatter.url(VERIFIED_URL_REFERENCE_URL)}"
    end

    sig { void }
    def audit_no_match
      return if block_url_offline?
      return unless verified_present?
      return if verified_matches_url?

      add_error "Verified URL #{Formatter.url(url_from_verified)} does not match URL " \
                "#{Formatter.url(strip_url_scheme(cask.url.to_s))}. " \
                "See #{Formatter.url(VERIFIED_URL_REFERENCE_URL)}"
    end

    sig { void }
    def audit_generic_artifacts
      cask.artifacts.select { |a| a.is_a?(Artifact::Artifact) }.each do |artifact|
        unless artifact.target.absolute?
          add_error "target must be absolute path for #{artifact.class.english_name} #{artifact.source}"
        end
      end
    end

    sig { void }
    def audit_languages
      @cask.languages.each do |language|
        Locale.parse(language)
      rescue Locale::ParserError
        add_error "Locale '#{language}' is invalid."
      end
    end

    sig { void }
    def audit_token_conflicts
      return unless token_conflicts?
      return unless core_formula_names.include?(cask.token)

      add_error(
        "possible duplicate, cask token conflicts with Homebrew core formula: #{Formatter.url(core_formula_url)}",
        strict_only: true,
      )
    end

    sig { void }
    def audit_token_valid
      add_error "cask token contains non-ascii characters" unless cask.token.ascii_only?
      add_error "cask token + should be replaced by -plus-" if cask.token.include? "+"
      add_error "cask token whitespace should be replaced by hyphens" if cask.token.include? " "
      add_error "cask token @ should be replaced by -at-" if cask.token.include? "@"
      add_error "cask token underscores should be replaced by hyphens" if cask.token.include? "_"
      add_error "cask token should not contain double hyphens" if cask.token.include? "--"

      if cask.token.match?(/[^a-z0-9-]/)
        add_error "cask token should only contain lowercase alphanumeric characters and hyphens"
      end

      return if !cask.token.start_with?("-") && !cask.token.end_with?("-")

      add_error "cask token should not have leading or trailing hyphens"
    end

    sig { void }
    def audit_token_bad_words
      return unless new_cask?

      token = cask.token

      add_error "cask token contains .app" if token.end_with? ".app"

      match_data = /-(?<designation>alpha|beta|rc|release-candidate)$/.match(cask.token)
      if match_data && cask.tap&.official? && cask.tap != "homebrew/cask-versions"
        add_error "cask token contains version designation '#{match_data[:designation]}'"
      end

      add_error("cask token mentions launcher", strict_only: true) if token.end_with? "launcher"

      add_error("cask token mentions desktop", strict_only: true) if token.end_with? "desktop"

      add_error("cask token mentions platform", strict_only: true) if token.end_with? "mac", "osx", "macos"

      add_error("cask token mentions architecture", strict_only: true) if token.end_with? "x86", "32_bit", "x86_64",
                                                                                          "64_bit"

      frameworks = %w[cocoa qt gtk wx java]
      return if frameworks.include?(token) || !token.end_with?(*frameworks)

      add_error("cask token mentions framework", strict_only: true)
    end

    sig { void }
    def audit_download
      return if download.blank? || cask.url.blank?

      odebug "Auditing download"
      download.fetch
    rescue => e
      add_error "download not possible: #{e}"
    end

    sig { void }
    def audit_livecheck_unneeded_long_version
      return unless cask.livecheck.strategy == :sparkle
      return unless cask.version.csv.second
      return if cask.url.to_s.include? cask.version.csv.second
      return if cask.version.csv.third.present? && cask.url.to_s.include?(cask.version.csv.third)

      add_error(
        "Download does not require additional version components. Use `&:short_version` in the livecheck",
        strict_only: true,
      )
    end

    sig { void }
    def audit_signing
      return if !signing? || download.blank? || cask.url.blank?

      odebug "Auditing signing"
      artifacts = cask.artifacts.select { |k| k.is_a?(Artifact::Pkg) || k.is_a?(Artifact::App) }

      return if artifacts.empty?

      downloaded_path = download.fetch
      primary_container = UnpackStrategy.detect(downloaded_path, type: @cask.container&.type, merge_xattrs: true)

      return if primary_container.nil?

      Dir.mktmpdir do |tmpdir|
        tmpdir = Pathname(tmpdir)
        primary_container.extract_nestedly(to: tmpdir, basename: downloaded_path.basename, verbose: false)

        artifacts.each do |artifact|
          artifact_path = artifact.is_a?(Artifact::Pkg) ? artifact.path : artifact.source
          path = tmpdir/artifact_path.relative_path_from(cask.staged_path)

          next unless path.exist?

          result = system_command("spctl", args: ["--assess", "--type", "install", path], print_stderr: false)

          next if result.success?

          add_error(<<~EOS, strict_only: true)
            Signature verification failed:
            #{result.merged_output}
            macOS on ARM requires software to be signed.
            Please contact the upstream developer to let them know they should sign and notarize their software.
          EOS
        end
      end
    end

    sig { returns(T.any(NilClass, T::Boolean, Symbol)) }
    def audit_livecheck_version
      return unless online?

      referenced_cask, = Homebrew::Livecheck.resolve_livecheck_reference(cask)

      # Respect skip conditions for a referenced cask
      if referenced_cask
        skip_info = Homebrew::Livecheck::SkipConditions.referenced_skip_information(
          referenced_cask,
          Homebrew::Livecheck.cask_name(cask),
        )
      end

      # Respect cask skip conditions (e.g. discontinued, latest, unversioned)
      skip_info ||= Homebrew::Livecheck::SkipConditions.skip_information(cask)
      return :skip if skip_info.present?

      latest_version = Homebrew::Livecheck.latest_version(
        cask,
        referenced_formula_or_cask: referenced_cask,
      )&.fetch(:latest)

      return :auto_detected if cask.version.to_s == latest_version.to_s

      add_error "Version '#{cask.version}' differs from '#{latest_version}' retrieved by livecheck."

      false
    end

    def audit_livecheck_min_os
      return unless online?
      return unless cask.livecheckable?
      return unless cask.livecheck.strategy == :sparkle

      out, _, status = curl_output("--fail", "--silent", "--location", cask.livecheck.url)
      return unless status.success?

      require "rexml/document"

      xml = begin
        REXML::Document.new(out)
      rescue REXML::ParseException
        nil
      end

      return if xml.blank?

      item = xml.elements["//rss//channel//item"]
      return if item.blank?

      min_os = item.elements["sparkle:minimumSystemVersion"]&.text
      min_os = "11" if min_os == "10.16"
      return if min_os.blank?

      begin
        min_os_string = OS::Mac::Version.new(min_os).strip_patch
      rescue MacOSVersionError
        return
      end

      return if min_os_string <= HOMEBREW_MACOS_OLDEST_ALLOWED

      cask_min_os = cask.depends_on.macos&.version

      return if cask_min_os == min_os_string

      min_os_symbol = if cask_min_os.present?
        cask_min_os.to_sym.inspect
      else
        "no minimum OS version"
      end
      add_error "Upstream defined #{min_os_string.to_sym.inspect} as the minimum OS version " \
                "and the cask defined #{min_os_symbol}"
    end

    sig { void }
    def audit_github_prerelease_version
      return if cask.tap == "homebrew/cask-versions"

      odebug "Auditing GitHub prerelease"
      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil?

      tag = SharedAudits.github_tag_from_url(cask.url)
      tag ||= cask.version
      error = SharedAudits.github_release(user, repo, tag, cask: cask)
      add_error error if error
    end

    sig { void }
    def audit_gitlab_prerelease_version
      return if cask.tap == "homebrew/cask-versions"

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil?

      odebug "Auditing GitLab prerelease"

      tag = SharedAudits.gitlab_tag_from_url(cask.url)
      tag ||= cask.version
      error = SharedAudits.gitlab_release(user, repo, tag, cask: cask)
      add_error error if error
    end

    sig { void }
    def audit_github_repository_archived
      # Discontinued casks may have an archived repo.
      return if cask.discontinued?

      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil?

      odebug "Auditing GitHub repo archived"

      metadata = SharedAudits.github_repo_data(user, repo)
      return if metadata.nil?

      add_error "GitHub repo is archived" if metadata["archived"]
    end

    sig { void }
    def audit_gitlab_repository_archived
      # Discontinued casks may have an archived repo.
      return if cask.discontinued?

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*}) if online?
      return if user.nil?

      odebug "Auditing GitLab repo archived"

      metadata = SharedAudits.gitlab_repo_data(user, repo)
      return if metadata.nil?

      add_error "GitLab repo is archived" if metadata["archived"]
    end

    sig { void }
    def audit_github_repository
      return unless new_cask?

      user, repo = get_repo_data(%r{https?://github\.com/([^/]+)/([^/]+)/?.*})
      return if user.nil?

      odebug "Auditing GitHub repo"

      error = SharedAudits.github(user, repo)
      add_error error if error
    end

    sig { void }
    def audit_gitlab_repository
      return unless new_cask?

      user, repo = get_repo_data(%r{https?://gitlab\.com/([^/]+)/([^/]+)/?.*})
      return if user.nil?

      odebug "Auditing GitLab repo"

      error = SharedAudits.gitlab(user, repo)
      add_error error if error
    end

    sig { void }
    def audit_bitbucket_repository
      return unless new_cask?

      user, repo = get_repo_data(%r{https?://bitbucket\.org/([^/]+)/([^/]+)/?.*})
      return if user.nil?

      odebug "Auditing Bitbucket repo"

      error = SharedAudits.bitbucket(user, repo)
      add_error error if error
    end

    sig { void }
    def audit_denylist
      return unless cask.tap
      return unless cask.tap.official?
      return unless (reason = Denylist.reason(cask.token))

      add_error "#{cask.token} is not allowed: #{reason}"
    end

    sig { void }
    def audit_reverse_migration
      return unless new_cask?
      return unless cask.tap
      return unless cask.tap.official?
      return unless cask.tap.tap_migrations.key?(cask.token)

      add_error "#{cask.token} is listed in tap_migrations.json"
    end

    sig { void }
    def audit_https_availability
      return unless download

      if cask.url && !cask.url.using
        validate_url_for_https_availability(cask.url, "binary URL", cask.token, cask.tap,
                                            user_agents: [cask.url.user_agent], referer: cask.url&.referer)
      end

      if cask.livecheckable? && !cask.livecheck.url.is_a?(Symbol)
        validate_url_for_https_availability(cask.livecheck.url, "livecheck URL", cask.token, cask.tap,
                                            check_content: true)
      end

      return unless cask.homepage

      validate_url_for_https_availability(cask.homepage, SharedAudits::URL_TYPE_HOMEPAGE, cask.token, cask.tap,
                                          user_agents:   [:browser, :default],
                                          check_content: true,
                                          strict:        strict?)
    end

    # sig {
    #   params(url_to_check: T.any(String, URL), url_type: String, cask_token: String, tap: Tap,
    #          options: T.untyped).void
    # }
    def validate_url_for_https_availability(url_to_check, url_type, cask_token, tap, **options)
      problem = curl_check_http_content(url_to_check.to_s, url_type, **options)
      exception = tap&.audit_exception(:secure_connection_audit_skiplist, cask_token, url_to_check.to_s)

      if problem
        add_error problem unless exception
      elsif exception
        add_error "#{url_to_check} is in the secure connection audit skiplist but does not need to be skipped"
      end
    end

    sig { params(regex: T.any(String, Regexp)).returns(T.nilable(T::Array[String])) }
    def get_repo_data(regex)
      return unless online?

      _, user, repo = *regex.match(cask.url.to_s)
      _, user, repo = *regex.match(cask.homepage) unless user
      return if !user || !repo

      repo.gsub!(/.git$/, "")

      [user, repo]
    end

    sig {
      params(regex: T.any(String, Regexp), valid_formats_array: T::Array[T.any(String, Regexp)]).returns(T::Boolean)
    }
    def bad_url_format?(regex, valid_formats_array)
      return false unless cask.url.to_s.match?(regex)

      valid_formats_array.none? { |format| cask.url.to_s =~ format }
    end

    sig { returns(T::Boolean) }
    def bad_sourceforge_url?
      bad_url_format?(/sourceforge/,
                      [
                        %r{\Ahttps://sourceforge\.net/projects/[^/]+/files/latest/download\Z},
                        %r{\Ahttps://downloads\.sourceforge\.net/(?!(project|sourceforge)/)},
                      ])
    end

    sig { returns(T::Boolean) }
    def bad_osdn_url?
      bad_url_format?(/osd/, [%r{\Ahttps?://([^/]+.)?dl\.osdn\.jp/}])
    end

    # sig { returns(String) }
    def homepage
      URI(cask.homepage.to_s).host
    end

    # sig { returns(String) }
    def domain
      URI(cask.url.to_s).host
    end

    sig { returns(T::Boolean) }
    def url_match_homepage?
      host = cask.url.to_s
      host_uri = URI(host)
      host = if host.match?(/:\d/) && host_uri.port != 80
        "#{host_uri.host}:#{host_uri.port}"
      else
        host_uri.host
      end

      return false if homepage.blank?

      home = homepage.downcase
      if (split_host = T.must(host).split(".")).length >= 3
        host = T.must(split_host[-2..]).join(".")
      end
      if (split_home = homepage.split(".")).length >= 3
        home = split_home[-2..].join(".")
      end
      host == home
    end

    # sig { params(url: String).returns(String) }
    def strip_url_scheme(url)
      url.sub(%r{^[^:/]+://(www\.)?}, "")
    end

    # sig { returns(String) }
    def url_from_verified
      strip_url_scheme(cask.url.verified)
    end

    sig { returns(T::Boolean) }
    def verified_matches_url?
      url_domain, url_path = strip_url_scheme(cask.url.to_s).split("/", 2)
      verified_domain, verified_path = url_from_verified.split("/", 2)

      (url_domain == verified_domain || (verified_domain && url_domain&.end_with?(".#{verified_domain}"))) &&
        (!verified_path || url_path&.start_with?(verified_path))
    end

    sig { returns(T::Boolean) }
    def verified_present?
      cask.url.verified.present?
    end

    sig { returns(T::Boolean) }
    def file_url?
      URI(cask.url.to_s).scheme == "file"
    end

    sig { returns(T::Boolean) }
    def block_url_offline?
      return false if online?

      cask.url.from_block?
    end

    sig { returns(Tap) }
    def core_tap
      @core_tap ||= CoreTap.instance
    end

    # sig { returns(T::Array[String]) }
    def core_formula_names
      core_tap.formula_names
    end

    sig { returns(String) }
    def core_formula_url
      "#{core_tap.default_remote}/blob/HEAD/Formula/#{cask.token}.rb"
    end
  end
end
