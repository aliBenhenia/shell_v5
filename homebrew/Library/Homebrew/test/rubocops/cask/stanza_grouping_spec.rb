# typed: false
# frozen_string_literal: true

require "rubocops/rubocop-cask"
require "test/rubocops/cask/shared_examples/cask_cop"

describe RuboCop::Cop::Cask::StanzaGrouping do
  include CaskCop

  subject(:cop) { described_class.new }

  let(:missing_line_msg) do
    "Cask/StanzaGrouping: stanza groups should be separated by a single empty line"
  end
  let(:extra_line_msg) do
    "Cask/StanzaGrouping: stanzas within the same group should have no lines between them"
  end

  context "when there is only one stanza" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version :latest
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when no stanzas are incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when no stanzas or variable assignments are incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

          version :latest
          sha256 :no_check
        end
      CASK
    end

    include_examples "does not report any offenses"
  end

  context "when one stanza is incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version :latest

          sha256 :no_check
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
        end
      CASK
    end
    let(:expected_offenses) do
      [{
        message:  extra_line_msg,
        severity: :convention,
        line:     3,
        column:   0,
        source:   "\n",
      }]
    end

    include_examples "reports offenses"

    include_examples "autocorrects source"
  end

  context "when the arch stanza is incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          version :latest
          sha256 :no_check
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"

          version :latest
          sha256 :no_check
        end
      CASK
    end
    let(:expected_offenses) do
      [{
        message:  missing_line_msg,
        severity: :convention,
        line:     3,
        column:   0,
        source:   "  version :latest",
      }]
    end

    include_examples "reports offenses"

    include_examples "autocorrects source"
  end

  context "when one variable assignment is incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
          version :latest
          sha256 :no_check
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

          version :latest
          sha256 :no_check
        end
      CASK
    end
    let(:expected_offenses) do
      [{
        message:  missing_line_msg,
        severity: :convention,
        line:     4,
        column:   0,
        source:   "  version :latest",
      }]
    end

    include_examples "reports offenses"

    include_examples "autocorrects source"
  end

  context "when many stanzas are incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
          url 'https://foo.brew.sh/foo.zip'

          name 'Foo'

          homepage 'https://foo.brew.sh'

          app 'Foo.app'
          uninstall :quit => 'com.example.foo',
                    :kext => 'com.example.foo.kextextension'
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check

          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          homepage 'https://foo.brew.sh'

          app 'Foo.app'

          uninstall :quit => 'com.example.foo',
                    :kext => 'com.example.foo.kextextension'
        end
      CASK
    end
    let(:expected_offenses) do
      [{
        message:  missing_line_msg,
        severity: :convention,
        line:     4,
        column:   0,
        source:   "  url 'https://foo.brew.sh/foo.zip'",
      }, {
        message:  extra_line_msg,
        severity: :convention,
        line:     5,
        column:   0,
        source:   "\n",
      }, {
        message:  extra_line_msg,
        severity: :convention,
        line:     7,
        column:   0,
        source:   "\n",
      }, {
        message:  missing_line_msg,
        severity: :convention,
        line:     11,
        column:   0,
        source:   "  uninstall :quit => 'com.example.foo',",
      }]
    end

    include_examples "reports offenses"

    include_examples "autocorrects source"
  end

  context "when many stanzas and variable assignments are incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

          platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
          version :latest
          sha256 :no_check
          url 'https://foo.brew.sh/foo.zip'

          name 'Foo'

          homepage 'https://foo.brew.sh'

          app 'Foo.app'
          uninstall :quit => 'com.example.foo',
                    :kext => 'com.example.foo.kextextension'
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
          platform = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

          version :latest
          sha256 :no_check

          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          homepage 'https://foo.brew.sh'

          app 'Foo.app'

          uninstall :quit => 'com.example.foo',
                    :kext => 'com.example.foo.kextextension'
        end
      CASK
    end
    let(:expected_offenses) do
      [{
        message:  extra_line_msg,
        severity: :convention,
        line:     4,
        column:   0,
        source:   "\n",
      }, {
        message:  missing_line_msg,
        severity: :convention,
        line:     6,
        column:   0,
        source:   "  version :latest",
      }, {
        message:  missing_line_msg,
        severity: :convention,
        line:     8,
        column:   0,
        source:   "  url 'https://foo.brew.sh/foo.zip'",
      }, {
        message:  extra_line_msg,
        severity: :convention,
        line:     9,
        column:   0,
        source:   "\n",
      }, {
        message:  extra_line_msg,
        severity: :convention,
        line:     11,
        column:   0,
        source:   "\n",
      }, {
        message:  missing_line_msg,
        severity: :convention,
        line:     15,
        column:   0,
        source:   "  uninstall :quit => 'com.example.foo',",
      }]
    end

    include_examples "reports offenses"

    include_examples "autocorrects source"
  end

  context "when caveats stanza is incorrectly grouped" do
    let(:source) do
      format(<<~CASK, caveats: caveats.strip)
        cask 'foo' do
          version :latest
          sha256 :no_check
          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          app 'Foo.app'
          %<caveats>s
        end
      CASK
    end
    let(:correct_source) do
      format(<<~CASK, caveats: caveats.strip)
        cask 'foo' do
          version :latest
          sha256 :no_check

          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'

          app 'Foo.app'

          %<caveats>s
        end
      CASK
    end

    context "when caveats is a one-line string" do
      let(:caveats) { "caveats 'This is a one-line caveat.'" }

      include_examples "autocorrects source"
    end

    context "when caveats is a heredoc" do
      let(:caveats) do
        <<~CAVEATS
          caveats <<~EOS
              This is a multiline caveat.

              Let's hope it doesn't cause any problems!
            EOS
        CAVEATS
      end

      include_examples "autocorrects source"
    end

    context "when caveats is a block" do
      let(:caveats) do
        <<~CAVEATS
          caveats do
              puts 'This is a multiline caveat.'

              puts "Let's hope it doesn't cause any problems!"
            end
        CAVEATS
      end

      include_examples "autocorrects source"
    end
  end

  context "when the postflight stanza is incorrectly grouped" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          app 'Foo.app'
          postflight do
            puts 'We have liftoff!'
          end
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check

          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'

          app 'Foo.app'

          postflight do
            puts 'We have liftoff!'
          end
        end
      CASK
    end

    include_examples "autocorrects source"
  end

  context "when a stanza has a comment" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check
          # comment with an empty line between

          # comment directly above
          postflight do
            puts 'We have liftoff!'
          end
          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          app 'Foo.app'
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          version :latest
          sha256 :no_check

          # comment with an empty line between

          # comment directly above
          postflight do
            puts 'We have liftoff!'
          end

          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'

          app 'Foo.app'
        end
      CASK
    end

    include_examples "autocorrects source"
  end

  context "when a stanza has a comment and there is a variable assignment" do
    let(:source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"
          # comment with an empty line between
          version :latest
          sha256 :no_check

          # comment directly above
          postflight do
            puts 'We have liftoff!'
          end
          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'
          app 'Foo.app'
        end
      CASK
    end
    let(:correct_source) do
      <<~CASK
        cask 'foo' do
          arch arm: "arm64", intel: "x86_64"
          folder = on_arch_conditional arm: "darwin-arm64", intel: "darwin"

          # comment with an empty line between
          version :latest
          sha256 :no_check

          # comment directly above
          postflight do
            puts 'We have liftoff!'
          end

          url 'https://foo.brew.sh/foo.zip'
          name 'Foo'

          app 'Foo.app'
        end
      CASK
    end

    include_examples "autocorrects source"
  end

  context "when stanzas are nested one-level in `on_*` blocks" do
    describe "basic nesting" do
      let(:source) do
        <<~CASK
          cask 'foo' do
            on_arm do
              version "1.0.2"

              sha256 :no_check
            end
            on_intel do
              version "0.9.8"
              sha256 :no_check
              url "https://foo.brew.sh/foo-intel.zip"
            end
          end
        CASK
      end

      let(:correct_source) do
        <<~CASK
          cask 'foo' do
            on_arm do
              version "1.0.2"
              sha256 :no_check
            end
            on_intel do
              version "0.9.8"
              sha256 :no_check

              url "https://foo.brew.sh/foo-intel.zip"
            end
          end
        CASK
      end

      include_examples "autocorrects source"
    end

    describe "nested `on_*` blocks with comments" do
      let(:source) do
        <<~CASK
          cask 'foo' do
            on_arm do
              version "1.0.2"

              sha256 :no_check # comment on same line
            end
            on_intel do
              version "0.9.8"
              sha256 :no_check
            end
          end
        CASK
      end

      let(:correct_source) do
        <<~CASK
          cask 'foo' do
            on_arm do
              version "1.0.2"
              sha256 :no_check # comment on same line
            end
            on_intel do
              version "0.9.8"
              sha256 :no_check
            end
          end
        CASK
      end

      include_examples "autocorrects source"
    end
  end
end
