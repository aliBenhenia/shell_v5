# typed: true
# frozen_string_literal: true

module Readall
  class << self
    def valid_casks?(casks, os_name: nil, arch: Hardware::CPU.type)
      return true if os_name == :linux

      current_macos_version = if os_name.is_a?(Symbol)
        MacOS::Version.from_symbol(os_name)
      else
        MacOS.version
      end

      success = T.let(true, T::Boolean)
      casks.each do |file|
        cask = Cask::CaskLoader.load(file)

        # Fine to have missing URLs for unsupported macOS
        macos_req = cask.depends_on.macos
        next if macos_req&.version && Array(macos_req.version).none? do |macos_version|
          current_macos_version.compare(macos_req.comparator, macos_version)
        end

        raise "Missing URL" if cask.url.nil?
      rescue Interrupt
        raise
      rescue Exception => e # rubocop:disable Lint/RescueException
        os_and_arch = "macOS #{current_macos_version} on #{arch}"
        onoe "Invalid cask (#{os_and_arch}): #{file}"
        $stderr.puts e
        success = false
      end
      success
    end
  end
end
