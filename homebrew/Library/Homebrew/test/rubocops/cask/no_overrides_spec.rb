# typed: false
# frozen_string_literal: true

require "rubocops/rubocop-cask"
require "test/rubocops/cask/shared_examples/cask_cop"

describe RuboCop::Cop::Cask::NoOverrides do
  include CaskCop

  subject(:cop) { described_class.new }

  context "when there are no on_system blocks" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version '1.2.3'
          url 'https://brew.sh/foo.pkg'

          name 'Foo'
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are no top-level standalone stanzas" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          on_mojave :or_later do
            version :latest
          end
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are top-level stanzas also in `on_*` blocks that should not override" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version '1.2.3'

          on_arm do
            binary "foo-\#{version}-arm64"
          end

          app "foo-\#{version}.app"

          binary "foo-\#{version}"
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are `arch` variables in the `url` in the `on_*` blocks" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86"
          version '1.2.3'
          on_mojave :or_later do
            url "https://brew.sh/foo-\#{version}-\#{arch}.pkg"
            sha256 "aaa"
          end
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are `version` interpolations in `on_*` blocks with methods called on them" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version 0.99,123.3

          on_mojave :or_later do
            url "https://brew.sh/foo-\#{version.csv.first}-\#{version.csv.second}.pkg"
          end
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are `arch` interpolations in regexps in `on_*` blocks" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86"

          version 0.99,123.3

          on_mojave :or_later do
            url "https://brew.sh/foo-\#{arch}-\#{version.csv.first}-\#{version.csv.last}.pkg"

            livecheck do
              url "https://brew.sh/foo/releases.html"
              regex(/href=.*?foo[._-]v?(\d+(?:.\d+)+)-\#{arch}.pkg/i)
            end
          end
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are single-line livecheck blocks within `on_*` blocks, ignore their contents" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          on_intel do
            livecheck do
              url 'https://brew.sh/foo' # Livecheck should be allowed since it's a different "kind" of URL.
            end
            version '1.2.3'
          end
          on_arm do
            version '2.3.4'
          end

          url 'https://brew.sh/foo.pkg'
          sha256 "bbb"
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are multi-line livecheck blocks within `on_*` blocks, ignore their contents" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          on_intel do
            livecheck do
              url 'https://brew.sh/foo' # Livecheck should be allowed since it's a different "kind" of URL.
              strategy :sparkle
            end
            version '1.2.3'
          end
          on_arm do
            version '2.3.4'
          end

          url 'https://brew.sh/foo.pkg'
          sha256 "bbb"
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there's only one difference between the `on_*` blocks" do
    let(:source) do
      <<~CASK
        cask "foo" do
          version "1.2.3"

          on_big_sur :or_older do
            sha256 "bbb"
            url "https://brew.sh/legacy/foo-2.3.4.dmg"
          end
          on_monterey :or_newer do
            sha256 "aaa"
            url "https://brew.sh/foo-2.3.4.dmg"
          end
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when there are multiple differences between the `on_*` blocks" do
    let(:source) do
      <<~CASK
        cask "foo" do
          version "1.2.3"
          sha256 "aaa"
          url "https://brew.sh/foo-2.3.4.dmg"

          on_big_sur :or_older do
            sha256 "bbb"
            url "https://brew.sh/legacy/foo-2.3.4.dmg"
          end
        end
      CASK
    end

    let(:expected_offenses) do
      [{
        message:  <<~EOS,
          Cask/NoOverrides: Do not use a top-level `sha256` stanza as the default. Add it to an `on_{system}` block instead.
          Use `:or_older` or `:or_newer` to specify a range of macOS versions.
        EOS
        severity: :convention,
        line:     3,
        column:   2,
        source:   "sha256 \"aaa\"",
      }, {
        message:  <<~EOS,
          Cask/NoOverrides: Do not use a top-level `url` stanza as the default. Add it to an `on_{system}` block instead.
          Use `:or_older` or `:or_newer` to specify a range of macOS versions.
        EOS
        severity: :convention,
        line:     4,
        column:   2,
        source:   "url \"https://brew.sh/foo-2.3.4.dmg\"",
      }]
    end

    include_examples "reports offenses"
  end

  context "when there are top-level standalone stanzas" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version '2.3.4'
          on_mojave :or_older do
            version '1.2.3'
          end

          url 'https://brew.sh/foo-2.3.4.dmg'
        end
      CASK
    end

    let(:expected_offenses) do
      [{
        message:  <<~EOS,
          Cask/NoOverrides: Do not use a top-level `version` stanza as the default. Add it to an `on_{system}` block instead.
          Use `:or_older` or `:or_newer` to specify a range of macOS versions.
        EOS
        severity: :convention,
        line:     2,
        column:   2,
        source:   "version '2.3.4'",
      }]
    end

    include_examples "reports offenses"
  end
end
