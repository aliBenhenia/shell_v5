# typed: strict
# frozen_string_literal: true

require "test_runner_formula"
require "github_runner"

class GitHubRunnerMatrix
  extend T::Sig

  # FIXME: Enable cop again when https://github.com/sorbet/sorbet/issues/3532 is fixed.
  # rubocop:disable Style/MutableConstant
  MaybeStringArray = T.type_alias { T.nilable(T::Array[String]) }
  private_constant :MaybeStringArray

  RunnerSpec = T.type_alias { T.any(LinuxRunnerSpec, MacOSRunnerSpec) }
  private_constant :RunnerSpec

  MacOSRunnerSpecHash = T.type_alias { { name: String, runner: String, cleanup: T::Boolean } }
  private_constant :MacOSRunnerSpecHash

  LinuxRunnerSpecHash = T.type_alias do
    {
      name:      String,
      runner:    String,
      container: T::Hash[Symbol, String],
      workdir:   String,
      timeout:   Integer,
      cleanup:   T::Boolean,
    }
  end
  private_constant :LinuxRunnerSpecHash

  RunnerSpecHash = T.type_alias { T.any(LinuxRunnerSpecHash, MacOSRunnerSpecHash) }
  private_constant :RunnerSpecHash
  # rubocop:enable Style/MutableConstant

  sig { returns(T::Array[GitHubRunner]) }
  attr_reader :runners

  sig {
    params(
      testing_formulae: T::Array[TestRunnerFormula],
      deleted_formulae: MaybeStringArray,
      dependent_matrix: T::Boolean,
    ).void
  }
  def initialize(testing_formulae, deleted_formulae, dependent_matrix:)
    @testing_formulae = T.let(testing_formulae, T::Array[TestRunnerFormula])
    @deleted_formulae = T.let(deleted_formulae, MaybeStringArray)
    @dependent_matrix = T.let(dependent_matrix, T::Boolean)

    @runners = T.let([], T::Array[GitHubRunner])
    generate_runners!

    freeze
  end

  sig { returns(T::Array[RunnerSpecHash]) }
  def active_runner_specs_hash
    runners.select(&:active)
           .map(&:spec)
           .map(&:to_h)
  end

  private

  sig { returns(LinuxRunnerSpec) }
  def linux_runner_spec
    linux_runner  = ENV.fetch("HOMEBREW_LINUX_RUNNER")
    linux_cleanup = ENV.fetch("HOMEBREW_LINUX_CLEANUP")

    LinuxRunnerSpec.new(
      name:      "Linux",
      runner:    linux_runner,
      container: {
        image:   "ghcr.io/homebrew/ubuntu22.04:master",
        options: "--user=linuxbrew -e GITHUB_ACTIONS_HOMEBREW_SELF_HOSTED",
      },
      workdir:   "/github/home",
      timeout:   4320,
      cleanup:   linux_cleanup == "true",
    )
  end

  VALID_PLATFORMS = T.let([:macos, :linux].freeze, T::Array[Symbol])
  VALID_ARCHES = T.let([:arm64, :x86_64].freeze, T::Array[Symbol])

  sig {
    params(
      platform:      Symbol,
      arch:          Symbol,
      spec:          RunnerSpec,
      macos_version: T.nilable(OS::Mac::Version),
    ).returns(GitHubRunner)
  }
  def create_runner(platform, arch, spec, macos_version = nil)
    raise "Unexpected platform: #{platform}" if VALID_PLATFORMS.exclude?(platform)
    raise "Unexpected arch: #{arch}" if VALID_ARCHES.exclude?(arch)

    runner = GitHubRunner.new(platform: platform, arch: arch, spec: spec, macos_version: macos_version)
    runner.active = active_runner?(runner)
    runner.freeze
  end

  sig { void }
  def generate_runners!
    return if @runners.present?

    @runners << create_runner(:linux, :x86_64, linux_runner_spec)

    github_run_id      = ENV.fetch("GITHUB_RUN_ID")
    github_run_attempt = ENV.fetch("GITHUB_RUN_ATTEMPT")
    ephemeral_suffix = +"-#{github_run_id}-#{github_run_attempt}"
    ephemeral_suffix << "-deps" if @dependent_matrix
    ephemeral_suffix.freeze

    MacOSVersions::SYMBOLS.each_value do |version|
      macos_version = OS::Mac::Version.new(version)
      next if macos_version.unsupported_release?

      spec = MacOSRunnerSpec.new(
        name:    "macOS #{version}-x86_64",
        runner:  "#{version}#{ephemeral_suffix}",
        cleanup: false,
      )
      @runners << create_runner(:macos, :x86_64, spec, macos_version)

      next unless macos_version >= :big_sur

      # Use bare metal runner when testing dependents on ARM64 Monterey.
      use_ephemeral = (macos_version >= :ventura && @dependent_matrix) ||
                      (macos_version >= :monterey && !@dependent_matrix)
      runner, cleanup = if use_ephemeral
        ["#{version}-arm64#{ephemeral_suffix}", false]
      else
        ["#{version}-arm64", true]
      end

      spec = MacOSRunnerSpec.new(name: "macOS #{version}-arm64", runner: runner, cleanup: cleanup)
      @runners << create_runner(:macos, :arm64, spec, macos_version)
    end

    @runners.freeze
  end

  sig { params(runner: GitHubRunner).returns(T::Boolean) }
  def active_runner?(runner)
    if @dependent_matrix
      formulae_have_untested_dependents?(runner)
    else
      return true if @deleted_formulae.present?

      compatible_formulae = @testing_formulae.dup

      platform = runner.platform
      arch = runner.arch
      macos_version = runner.macos_version

      compatible_formulae.select! { |formula| formula.public_send(:"#{platform}_compatible?") }
      compatible_formulae.select! { |formula| formula.public_send(:"#{arch}_compatible?") }
      compatible_formulae.select! { |formula| formula.compatible_with?(macos_version) } if macos_version

      compatible_formulae.present?
    end
  end

  sig { params(runner: GitHubRunner).returns(T::Boolean) }
  def formulae_have_untested_dependents?(runner)
    platform = runner.platform
    arch = runner.arch
    macos_version = runner.macos_version

    @testing_formulae.any? do |formula|
      # If the formula has a platform/arch/macOS version requirement, then its
      # dependents don't need to be tested if these requirements are not satisfied.
      next false unless formula.public_send(:"#{platform}_compatible?")
      next false unless formula.public_send(:"#{arch}_compatible?")
      next false if macos_version.present? && !formula.compatible_with?(macos_version)

      compatible_dependents = formula.dependents(platform: platform, arch: arch, macos_version: macos_version&.to_sym)
                                     .dup

      compatible_dependents.select! { |dependent_f| dependent_f.public_send(:"#{platform}_compatible?") }
      compatible_dependents.select! { |dependent_f| dependent_f.public_send(:"#{arch}_compatible?") }
      compatible_dependents.select! { |dependent_f| dependent_f.compatible_with?(macos_version) } if macos_version

      # These arrays will generally have been generated by different Formulary caches,
      # so we can only compare them by name and not directly.
      (compatible_dependents.map(&:name) - @testing_formulae.map(&:name)).present?
    end
  end
end
