# typed: strict
# frozen_string_literal: true

module SharedEnvExtension
  extend T::Sig

  def setup_build_environment(formula: nil, cc: nil, build_bottle: false, bottle_arch: nil, testing_formula: false,
                              debug_symbols: false)
    generic_shared_setup_build_environment(formula: formula, cc: cc, build_bottle: build_bottle,
                                           bottle_arch: bottle_arch, testing_formula: testing_formula,
                                           debug_symbols: debug_symbols)

    # Normalise the system Perl version used, where multiple may be available
    self["VERSIONER_PERL_VERSION"] = MacOS.preferred_perl_version
  end

  sig { returns(T::Boolean) }
  def no_weak_imports_support?
    return false unless compiler == :clang

    return false if !MacOS::Xcode.version.null? && MacOS::Xcode.version < "8.0"
    return false if !MacOS::CLT.version.null? && MacOS::CLT.version < "8.0"

    true
  end

  sig { returns(T::Boolean) }
  def no_fixup_chains_support?
    return false if MacOS.version <= :catalina

    # NOTE: `-version_details` is supported in Xcode 10.2 at the earliest.
    ld_version_details = JSON.parse(Utils.safe_popen_read("/usr/bin/ld", "-version_details"))
    ld_version = Version.parse(ld_version_details["version"])

    # This is supported starting Xcode 13, which ships ld64-711.
    # https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes
    # https://en.wikipedia.org/wiki/Xcode#Xcode_11.0_-_14.x_(since_SwiftUI_framework)_2
    ld_version >= 711
  end
end
