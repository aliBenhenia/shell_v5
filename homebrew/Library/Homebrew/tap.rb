# typed: true
# frozen_string_literal: true

require "commands"
require "completions"
require "extend/cachable"
require "description_cache_store"
require "settings"

# A {Tap} is used to extend the formulae provided by Homebrew core.
# Usually, it's synced with a remote Git repository. And it's likely
# a GitHub repository with the name of `user/homebrew-repo`. In such
# cases, `user/repo` will be used as the {#name} of this {Tap}, where
# {#user} represents the GitHub username and {#repo} represents the repository
# name without the leading `homebrew-`.
class Tap
  extend T::Sig

  extend Cachable

  TAP_DIRECTORY = (HOMEBREW_LIBRARY/"Taps").freeze

  HOMEBREW_TAP_FORMULA_RENAMES_FILE = "formula_renames.json"
  HOMEBREW_TAP_MIGRATIONS_FILE = "tap_migrations.json"
  HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR = "audit_exceptions"
  HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR = "style_exceptions"
  HOMEBREW_TAP_PYPI_FORMULA_MAPPINGS = "pypi_formula_mappings.json"

  HOMEBREW_TAP_JSON_FILES = %W[
    #{HOMEBREW_TAP_FORMULA_RENAMES_FILE}
    #{HOMEBREW_TAP_MIGRATIONS_FILE}
    #{HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR}/*.json
    #{HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR}/*.json
    #{HOMEBREW_TAP_PYPI_FORMULA_MAPPINGS}
  ].freeze

  def self.fetch(*args)
    case args.length
    when 1
      user, repo = args.first.split("/", 2)
    when 2
      user = args.first
      repo = args.second
    end

    raise "Invalid tap name '#{args.join("/")}'" if [user, repo].any? { |part| part.nil? || part.include?("/") }

    # We special case homebrew and linuxbrew so that users don't have to shift in a terminal.
    user = user.capitalize if ["homebrew", "linuxbrew"].include? user
    repo = repo.sub(HOMEBREW_OFFICIAL_REPO_PREFIXES_REGEX, "")

    return CoreTap.instance if ["Homebrew", "Linuxbrew"].include?(user) && ["core", "homebrew"].include?(repo)

    cache_key = "#{user}/#{repo}".downcase
    cache.fetch(cache_key) { |key| cache[key] = Tap.new(user, repo) }
  end

  def self.from_path(path)
    match = File.expand_path(path).match(HOMEBREW_TAP_PATH_REGEX)
    return if match.blank? || match[:user].blank? || match[:repo].blank?

    fetch(match[:user], match[:repo])
  end

  sig { returns(T.attached_class) }
  def self.default_cask_tap
    @default_cask_tap ||= fetch("Homebrew", "cask")
  end

  sig { params(force: T::Boolean).returns(T::Boolean) }
  def self.install_default_cask_tap_if_necessary(force: false)
    false
  end

  extend Enumerable

  # The user name of this {Tap}. Usually, it's the GitHub username of
  # this {Tap}'s remote repository.
  attr_reader :user

  # The repository name of this {Tap} without the leading `homebrew-`.
  attr_reader :repo

  # The name of this {Tap}. It combines {#user} and {#repo} with a slash.
  # {#name} is always in lowercase.
  # e.g. `user/repo`
  attr_reader :name

  # The full name of this {Tap}, including the `homebrew-` prefix.
  # It combines {#user} and 'homebrew-'-prefixed {#repo} with a slash.
  # e.g. `user/homebrew-repo`
  attr_reader :full_name

  # The local path to this {Tap}.
  # e.g. `/usr/local/Library/Taps/user/homebrew-repo`
  attr_reader :path

  # @private
  def initialize(user, repo)
    @user = user
    @repo = repo
    @name = "#{@user}/#{@repo}".downcase
    @full_name = "#{@user}/homebrew-#{@repo}"
    @path = TAP_DIRECTORY/@full_name.downcase
    @path.extend(GitRepositoryExtension)
    @alias_table = nil
    @alias_reverse_table = nil
  end

  # Clear internal cache.
  def clear_cache
    @remote = nil
    @repo_var = nil
    @formula_dir = nil
    @cask_dir = nil
    @command_dir = nil
    @formula_files = nil
    @alias_dir = nil
    @alias_files = nil
    @aliases = nil
    @alias_table = nil
    @alias_reverse_table = nil
    @command_files = nil
    @formula_renames = nil
    @tap_migrations = nil
    @audit_exceptions = nil
    @style_exceptions = nil
    @pypi_formula_mappings = nil
    @config = nil
    @spell_checker = nil
    remove_instance_variable(:@private) if instance_variable_defined?(:@private)
  end

  # The remote path to this {Tap}.
  # e.g. `https://github.com/user/homebrew-repo`
  def remote
    return default_remote unless installed?

    @remote ||= path.git_origin
  end

  # The remote repository name of this {Tap}.
  # e.g. `user/homebrew-repo`
  def remote_repo
    return unless remote

    @remote_repo ||= remote.delete_prefix("https://github.com/")
                           .delete_prefix("git@github.com:")
                           .delete_suffix(".git")
  end

  # The default remote path to this {Tap}.
  sig { returns(String) }
  def default_remote
    "https://github.com/#{full_name}"
  end

  def repo_var
    @repo_var ||= path.to_s
                      .delete_prefix(TAP_DIRECTORY.to_s)
                      .tr("^A-Za-z0-9", "_")
                      .upcase
  end

  # True if this {Tap} is a Git repository.
  def git?
    path.git?
  end

  # git branch for this {Tap}.
  def git_branch
    raise TapUnavailableError, name unless installed?

    path.git_branch
  end

  # git HEAD for this {Tap}.
  def git_head
    raise TapUnavailableError, name unless installed?

    @git_head ||= path.git_head
  end

  # Time since last git commit for this {Tap}.
  def git_last_commit
    raise TapUnavailableError, name unless installed?

    path.git_last_commit
  end

  # The issues URL of this {Tap}.
  # e.g. `https://github.com/user/homebrew-repo/issues`
  sig { returns(T.nilable(String)) }
  def issues_url
    return if !official? && custom_remote?

    "#{default_remote}/issues"
  end

  def to_s
    name
  end

  # True if this {Tap} is an official Homebrew tap.
  def official?
    user == "Homebrew"
  end

  # True if the remote of this {Tap} is a private repository.
  def private?
    return @private if instance_variable_defined?(:@private)

    @private = read_or_set_private_config
  end

  # {TapConfig} of this {Tap}.
  def config
    @config ||= begin
      raise TapUnavailableError, name unless installed?

      TapConfig.new(self)
    end
  end

  # True if this {Tap} has been installed.
  def installed?
    path.directory?
  end

  # True if this {Tap} is not a full clone.
  def shallow?
    (path/".git/shallow").exist?
  end

  # @private
  sig { returns(T::Boolean) }
  def core_tap?
    false
  end

  # Install this {Tap}.
  #
  # @param clone_target [String] If passed, it will be used as the clone remote.
  # @param force_auto_update [Boolean, nil] If present, whether to override the
  #   logic that skips non-GitHub repositories during auto-updates.
  # @param quiet [Boolean] If set, suppress all output.
  # @param custom_remote [Boolean] If set, change the tap's remote if already installed.
  # @param verify [Boolean] If set, verify all the formula, casks and aliases in the tap are valid.
  def install(quiet: false, clone_target: nil, force_auto_update: nil, custom_remote: false, verify: false)
    require "descriptions"
    require "readall"

    if official? && DEPRECATED_OFFICIAL_TAPS.include?(repo)
      odie "#{name} was deprecated. This tap is now empty and all its contents were either deleted or migrated."
    elsif user == "caskroom" || name == "phinze/cask"
      new_repo = (repo == "cask") ? "cask" : "cask-#{repo}"
      odie "#{name} was moved. Tap homebrew/#{new_repo} instead."
    end

    raise TapNoCustomRemoteError, name if custom_remote && clone_target.nil?

    requested_remote = clone_target || default_remote

    if installed? && !custom_remote
      raise TapRemoteMismatchError.new(name, @remote, requested_remote) if clone_target && requested_remote != remote
      raise TapAlreadyTappedError, name if force_auto_update.nil? && !shallow?
    end

    # ensure git is installed
    Utils::Git.ensure_installed!

    if installed?
      if requested_remote != remote # we are sure that clone_target is not nil and custom_remote is true here
        fix_remote_configuration(requested_remote: requested_remote, quiet: quiet)
      end

      unless force_auto_update.nil?
        if force_auto_update
          config["forceautoupdate"] = force_auto_update
        elsif config["forceautoupdate"] == "true"
          config.delete("forceautoupdate")
        end
        return
      end

      $stderr.ohai "Unshallowing #{name}" if shallow? && !quiet
      args = %w[fetch]
      # Git throws an error when attempting to unshallow a full clone
      args << "--unshallow" if shallow?
      args << "-q" if quiet
      path.cd { safe_system "git", *args }
      return
    end

    clear_cache

    $stderr.ohai "Tapping #{name}" unless quiet
    args =  %W[clone #{requested_remote} #{path}]

    # Override possible user configs like:
    #   git config --global clone.defaultRemoteName notorigin
    args << "--origin=origin"
    args << "-q" if quiet

    # Override user-set default template
    args << "--template="

    begin
      safe_system "git", *args

      if verify && !Readall.valid_tap?(self, aliases: true) && !Homebrew::EnvConfig.developer?
        raise "Cannot tap #{name}: invalid syntax in tap!"
      end
    rescue Interrupt, RuntimeError
      ignore_interrupts do
        # wait for git to possibly cleanup the top directory when interrupt happens.
        sleep 0.1
        FileUtils.rm_rf path
        path.parent.rmdir_if_possible
      end
      raise
    end

    config["forceautoupdate"] = force_auto_update unless force_auto_update.nil?

    Commands.rebuild_commands_completion_list
    link_completions_and_manpages

    formatted_contents = contents.presence&.to_sentence&.dup&.prepend(" ")
    $stderr.puts "Tapped#{formatted_contents} (#{path.abv})." unless quiet
    CacheStoreDatabase.use(:descriptions) do |db|
      DescriptionCacheStore.new(db)
                           .update_from_formula_names!(formula_names)
    end
    CacheStoreDatabase.use(:cask_descriptions) do |db|
      CaskDescriptionCacheStore.new(db)
                               .update_from_cask_tokens!(cask_tokens)
    end

    if official?
      untapped = self.class.untapped_official_taps
      untapped -= [name]

      if untapped.empty?
        Homebrew::Settings.delete :untapped
      else
        Homebrew::Settings.write :untapped, untapped.join(";")
      end
    end

    return if clone_target
    return unless private?
    return if quiet

    path.cd do
      return if Utils.popen_read("git", "config", "--get", "credential.helper").present?
    end

    $stderr.puts <<~EOS
      It looks like you tapped a private repository. To avoid entering your
      credentials each time you update, you can use git HTTP credential
      caching or issue the following command:
        cd #{path}
        git remote set-url origin git@github.com:#{full_name}.git
    EOS
  end

  def link_completions_and_manpages
    command = "brew tap --repair"
    Utils::Link.link_manpages(path, command)

    Homebrew::Completions.show_completions_message_if_needed
    if official? || Homebrew::Completions.link_completions?
      Utils::Link.link_completions(path, command)
    else
      Utils::Link.unlink_completions(path)
    end
  end

  def fix_remote_configuration(requested_remote: nil, quiet: false)
    if requested_remote.present?
      path.cd do
        safe_system "git", "remote", "set-url", "origin", requested_remote
        safe_system "git", "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"
      end
      $stderr.ohai "#{name}: changed remote from #{remote} to #{requested_remote}" unless quiet
    end

    current_upstream_head = path.git_origin_branch
    return if requested_remote.blank? && path.git_origin_has_branch?(current_upstream_head)

    args = %w[fetch]
    args << "--quiet" if quiet
    args << "origin"
    safe_system "git", "-C", path, *args
    path.git_origin_set_head_auto

    new_upstream_head = path.git_origin_branch
    return if new_upstream_head == current_upstream_head

    path.git_rename_branch old: current_upstream_head, new: new_upstream_head
    path.git_branch_set_upstream local: new_upstream_head, origin: new_upstream_head

    return if quiet

    $stderr.ohai "#{name}: changed default branch name from #{current_upstream_head} to #{new_upstream_head}!"
  end

  # Uninstall this {Tap}.
  def uninstall(manual: false)
    require "descriptions"
    raise TapUnavailableError, name unless installed?

    $stderr.puts "Untapping #{name}..."

    abv = path.abv
    formatted_contents = contents.presence&.to_sentence&.dup&.prepend(" ")

    CacheStoreDatabase.use(:descriptions) do |db|
      DescriptionCacheStore.new(db)
                           .delete_from_formula_names!(formula_names)
    end
    CacheStoreDatabase.use(:cask_descriptions) do |db|
      CaskDescriptionCacheStore.new(db)
                               .delete_from_cask_tokens!(cask_tokens)
    end
    Utils::Link.unlink_manpages(path)
    Utils::Link.unlink_completions(path)
    path.rmtree
    path.parent.rmdir_if_possible
    $stderr.puts "Untapped#{formatted_contents} (#{abv})."

    Commands.rebuild_commands_completion_list
    clear_cache

    return if !manual || !official?

    untapped = self.class.untapped_official_taps
    return if untapped.include? name

    untapped << name
    Homebrew::Settings.write :untapped, untapped.join(";")
  end

  # True if the {#remote} of {Tap} is customized.
  def custom_remote?
    return true unless remote

    remote.casecmp(default_remote).nonzero?
  end

  # Path to the directory of all {Formula} files for this {Tap}.
  sig { returns(Pathname) }
  def formula_dir
    # Official formulae taps always use this directory, saves time to hardcode.
    @formula_dir ||= if official?
      path/"Formula"
    else
      potential_formula_dirs.find(&:directory?) || (path/"Formula")
    end
  end

  sig { returns(T::Array[Pathname]) }
  def potential_formula_dirs
    @potential_formula_dirs ||= [path/"Formula", path/"HomebrewFormula", path].freeze
  end

  # Path to the directory of all {Cask} files for this {Tap}.
  sig { returns(Pathname) }
  def cask_dir
    @cask_dir ||= path/"Casks"
  end

  def contents
    contents = []

    if (command_count = command_files.count).positive?
      contents << Utils.pluralize("command", command_count, include_count: true)
    end

    if (cask_count = cask_files.count).positive?
      contents << Utils.pluralize("cask", cask_count, include_count: true)
    end

    if (formula_count = formula_files.count).positive?
      contents << Utils.pluralize("formula", formula_count, plural: "e", include_count: true)
    end

    contents
  end

  # An array of all {Formula} files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def formula_files
    @formula_files ||= if formula_dir.directory?
      # TODO: odeprecate the non-official/old logic with a new minor release somehow?
      if official?
        formula_dir.find
      else
        formula_dir.children
      end.select(&method(:formula_file?))
    else
      []
    end
  end

  # A cached hash of {Formula} basenames to {Formula} file pathnames for a {Tap}
  sig { params(tap: Tap).returns(T::Hash[String, Pathname]) }
  def self.formula_files_by_name(tap)
    cache_key = "formula_files_by_name_#{tap}"
    cache.fetch(cache_key) do |key|
      cache[key] = tap.formula_files.each_with_object({}) do |file, hash|
        # If there's more than one file with the same basename: intentionally
        # ignore the later ones here.
        hash[file.basename.to_s] ||= file
      end
    end
  end

  # An array of all versioned {Formula} files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def versioned_formula_files
    @versioned_formula_files ||= formula_files.select do |file|
      file.basename(".rb").to_s =~ /@[\d.]+$/
    end
  end

  # An array of all {Cask} files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def cask_files
    @cask_files ||= if cask_dir.directory?
      # TODO: odeprecate the non-official/old logic with a new minor release somehow?
      if official?
        cask_dir.find
      else
        cask_dir.children
      end.select(&method(:ruby_file?))
    else
      []
    end
  end

  # A cached hash of {Cask} basenames to {Cask} file pathnames for a {Tap}
  sig { params(tap: Tap).returns(T::Hash[String, Pathname]) }
  def self.cask_files_by_name(tap)
    cache_key = "cask_files_by_name_#{tap}"

    cache.fetch(cache_key) do |key|
      cache[key] = tap.cask_files.each_with_object({}) do |file, hash|
        # If there's more than one file with the same basename: intentionally
        # ignore the later ones here.
        hash[file.basename.to_s] ||= file
      end
    end
  end

  # returns true if the file has a Ruby extension
  # @private
  sig { params(file: Pathname).returns(T::Boolean) }
  def ruby_file?(file)
    file.extname == ".rb"
  end

  # returns true if given path would present a {Formula} file in this {Tap}.
  # accepts both absolute path and relative path (relative to this {Tap}'s path)
  # @private
  sig { params(file: T.any(String, Pathname)).returns(T::Boolean) }
  def formula_file?(file)
    file = Pathname.new(file) unless file.is_a? Pathname
    file = file.expand_path(path)
    return false unless ruby_file?(file)
    return false if cask_file?(file)

    file.to_s.start_with?("#{formula_dir}/")
  end

  # returns true if given path would present a {Cask} file in this {Tap}.
  # accepts both absolute path and relative path (relative to this {Tap}'s path)
  # @private
  sig { params(file: T.any(String, Pathname)).returns(T::Boolean) }
  def cask_file?(file)
    file = Pathname.new(file) unless file.is_a? Pathname
    file = file.expand_path(path)
    return false unless ruby_file?(file)

    file.to_s.start_with?("#{cask_dir}/")
  end

  # An array of all {Formula} names of this {Tap}.
  sig { returns(T::Array[String]) }
  def formula_names
    @formula_names ||= formula_files.map(&method(:formula_file_to_name))
  end

  # An array of all {Cask} tokens of this {Tap}.
  sig { returns(T::Array[String]) }
  def cask_tokens
    @cask_tokens ||= cask_files.map(&method(:formula_file_to_name))
  end

  # path to the directory of all alias files for this {Tap}.
  # @private
  sig { returns(Pathname) }
  def alias_dir
    @alias_dir ||= path/"Aliases"
  end

  # an array of all alias files of this {Tap}.
  # @private
  sig { returns(T::Array[Pathname]) }
  def alias_files
    @alias_files ||= Pathname.glob("#{alias_dir}/*").select(&:file?)
  end

  # an array of all aliases of this {Tap}.
  # @private
  sig { returns(T::Array[String]) }
  def aliases
    @aliases ||= alias_files.map { |f| alias_file_to_name(f) }
  end

  # a table mapping alias to formula name
  # @private
  def alias_table
    return @alias_table if @alias_table

    @alias_table = {}
    alias_files.each do |alias_file|
      @alias_table[alias_file_to_name(alias_file)] = formula_file_to_name(alias_file.resolved_path)
    end
    @alias_table
  end

  # a table mapping formula name to aliases
  # @private
  def alias_reverse_table
    return @alias_reverse_table if @alias_reverse_table

    @alias_reverse_table = {}
    alias_table.each do |alias_name, formula_name|
      @alias_reverse_table[formula_name] ||= []
      @alias_reverse_table[formula_name] << alias_name
    end
    @alias_reverse_table
  end

  sig { returns(Pathname) }
  def command_dir
    @command_dir ||= path/"cmd"
  end

  # An array of all commands files of this {Tap}.
  sig { returns(T::Array[Pathname]) }
  def command_files
    @command_files ||= if command_dir.directory?
      Commands.find_commands(command_dir)
    else
      []
    end
  end

  sig { returns(Hash) }
  def to_hash
    hash = {
      "name"          => name,
      "user"          => user,
      "repo"          => repo,
      "path"          => path.to_s,
      "installed"     => installed?,
      "official"      => official?,
      "formula_names" => formula_names,
      "formula_files" => formula_files.map(&:to_s),
      "cask_tokens"   => cask_tokens,
      "cask_files"    => cask_files.map(&:to_s),
      "command_files" => command_files.map(&:to_s),
    }

    if installed?
      hash["remote"] = remote
      hash["custom_remote"] = custom_remote?
      hash["private"] = private?
    end

    hash
  end

  # Hash with tap formula renames.
  sig { returns(Hash) }
  def formula_renames
    @formula_renames ||= if (rename_file = path/HOMEBREW_TAP_FORMULA_RENAMES_FILE).file?
      JSON.parse(rename_file.read)
    else
      {}
    end
  end

  # Hash with tap migrations.
  sig { returns(Hash) }
  def tap_migrations
    @tap_migrations ||= if (migration_file = path/HOMEBREW_TAP_MIGRATIONS_FILE).file?
      JSON.parse(migration_file.read)
    else
      {}
    end
  end

  # Hash with audit exceptions
  sig { returns(Hash) }
  def audit_exceptions
    @audit_exceptions = read_formula_list_directory "#{HOMEBREW_TAP_AUDIT_EXCEPTIONS_DIR}/*"
  end

  # Hash with style exceptions
  sig { returns(Hash) }
  def style_exceptions
    @style_exceptions = read_formula_list_directory "#{HOMEBREW_TAP_STYLE_EXCEPTIONS_DIR}/*"
  end

  # Hash with pypi formula mappings
  def pypi_formula_mappings
    @pypi_formula_mappings = read_formula_list path/HOMEBREW_TAP_PYPI_FORMULA_MAPPINGS
  end

  # @private
  sig { returns(T::Boolean) }
  def should_report_analytics?
    return !Homebrew::EnvConfig.no_install_from_api? && official? unless installed?

    !private?
  end

  sig { params(other: T.nilable(T.any(String, Tap))).returns(T::Boolean) }
  def ==(other)
    other = Tap.fetch(other) if other.is_a?(String)
    self.class == other.class && name == other.name
  end

  def self.each(&block)
    return unless TAP_DIRECTORY.directory?

    return to_enum unless block

    TAP_DIRECTORY.subdirs.each do |user|
      user.subdirs.each do |repo|
        yield fetch(user.basename.to_s, repo.basename.to_s)
      end
    end
  end

  # An array of all installed {Tap} names.
  sig { returns(T::Array[String]) }
  def self.names
    map(&:name).sort
  end

  # An array of all tap cmd directory {Pathname}s.
  sig { returns(T::Array[Pathname]) }
  def self.cmd_directories
    Pathname.glob TAP_DIRECTORY/"*/*/cmd"
  end

  # An array of official taps that have been manually untapped
  sig { returns(T::Array[String]) }
  def self.untapped_official_taps
    Homebrew::Settings.read(:untapped)&.split(";") || []
  end

  # @private
  sig { params(file: Pathname).returns(String) }
  def formula_file_to_name(file)
    "#{name}/#{file.basename(".rb")}"
  end

  # @private
  sig { params(file: Pathname).returns(String) }
  def alias_file_to_name(file)
    "#{name}/#{file.basename}"
  end

  def audit_exception(list, formula_or_cask, value = nil)
    return false if audit_exceptions.blank?
    return false unless audit_exceptions.key? list

    list = audit_exceptions[list]

    case list
    when Array
      list.include? formula_or_cask
    when Hash
      return false unless list.include? formula_or_cask
      return list[formula_or_cask] if value.blank?

      list[formula_or_cask] == value
    end
  end

  private

  def read_or_set_private_config
    case config["private"]
    when "true" then true
    when "false" then false
    else
      config["private"] = begin
        if custom_remote?
          true
        else
          GitHub.private_repo?(full_name)
        end
      rescue GitHub::API::HTTPNotFoundError
        true
      rescue GitHub::API::Error
        false
      end
    end
  end

  sig { params(file: Pathname).returns(T.any(T::Array[String], Hash)) }
  def read_formula_list(file)
    JSON.parse file.read
  rescue JSON::ParserError
    opoo "#{file} contains invalid JSON"
    {}
  rescue Errno::ENOENT
    {}
  end

  sig { params(directory: String).returns(Hash) }
  def read_formula_list_directory(directory)
    list = {}

    Pathname.glob(path/directory).each do |exception_file|
      list_name = exception_file.basename.to_s.chomp(".json").to_sym
      list_contents = read_formula_list exception_file

      next if list_contents.blank?

      list[list_name] = list_contents
    end

    list
  end
end

# A specialized {Tap} class for the core formulae.
class CoreTap < Tap
  extend T::Sig

  # @private
  sig { void }
  def initialize
    super "Homebrew", "core"
  end

  sig { returns(CoreTap) }
  def self.instance
    @instance ||= new
  end

  sig { void }
  def self.ensure_installed!
    return if instance.installed?
    return unless Homebrew::EnvConfig.no_install_from_api?
    return if Homebrew::EnvConfig.automatically_set_no_install_from_api?

    # Tests override homebrew-core locations and we don't want to auto-tap in them.
    return if ENV["HOMEBREW_TESTS"]

    instance.install
  end

  sig { returns(String) }
  def remote
    super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::EnvConfig.core_git_remote
  end

  # CoreTap never allows shallow clones (on request from GitHub).
  def install(quiet: false, clone_target: nil, force_auto_update: nil, custom_remote: false, verify: false)
    remote = Homebrew::EnvConfig.core_git_remote # set by HOMEBREW_CORE_GIT_REMOTE
    requested_remote = clone_target || remote

    # The remote will changed again on `brew update` since remotes for homebrew/core are mismatched
    raise TapCoreRemoteMismatchError.new(name, remote, requested_remote) if requested_remote != remote

    if remote != default_remote
      $stderr.puts "HOMEBREW_CORE_GIT_REMOTE set: using #{remote} as the Homebrew/homebrew-core Git remote."
    end

    super(quiet: quiet, clone_target: remote, force_auto_update: force_auto_update, custom_remote: custom_remote)
  end

  # @private
  sig { params(manual: T::Boolean).void }
  def uninstall(manual: false)
    raise "Tap#uninstall is not available for CoreTap" if Homebrew::EnvConfig.no_install_from_api?

    super
  end

  # @private
  sig { returns(T::Boolean) }
  def core_tap?
    true
  end

  # @private
  sig { returns(T::Boolean) }
  def linuxbrew_core?
    remote_repo.to_s.end_with?("/linuxbrew-core") || remote_repo == "Linuxbrew/homebrew-core"
  end

  # @private
  sig { returns(Pathname) }
  def formula_dir
    @formula_dir ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { returns(Pathname) }
  def alias_dir
    @alias_dir ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { returns(Hash) }
  def formula_renames
    @formula_renames ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { returns(Hash) }
  def tap_migrations
    @tap_migrations ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { returns(Hash) }
  def audit_exceptions
    @audit_exceptions ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { returns(Hash) }
  def style_exceptions
    @style_exceptions ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { returns(Hash) }
  def pypi_formula_mappings
    @pypi_formula_mappings ||= begin
      self.class.ensure_installed!
      super
    end
  end

  # @private
  sig { params(file: Pathname).returns(String) }
  def formula_file_to_name(file)
    file.basename(".rb").to_s
  end

  # @private
  sig { params(file: Pathname).returns(String) }
  def alias_file_to_name(file)
    file.basename.to_s
  end

  # @private
  sig { returns(T::Array[String]) }
  def aliases
    return super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::API::Formula.all_aliases.keys
  end

  # @private
  sig { returns(T::Array[String]) }
  def formula_names
    return super if Homebrew::EnvConfig.no_install_from_api?

    Homebrew::API::Formula.all_formulae.keys
  end
end

# Permanent configuration per {Tap} using `git-config(1)`.
class TapConfig
  extend T::Sig

  attr_reader :tap

  sig { params(tap: Tap).void }
  def initialize(tap)
    @tap = tap
  end

  def [](key)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.read key, repo: tap.path
  end

  def []=(key, value)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.write key, value.to_s, repo: tap.path
  end

  def delete(key)
    return unless tap.git?
    return unless Utils::Git.available?

    Homebrew::Settings.delete key, repo: tap.path
  end
end

require "extend/os/tap"
