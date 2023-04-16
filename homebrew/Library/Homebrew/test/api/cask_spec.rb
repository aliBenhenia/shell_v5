# typed: false
# frozen_string_literal: true

require "api"

describe Homebrew::API::Cask do
  let(:cache_dir) { mktmpdir }

  before do
    stub_const("Homebrew::API::HOMEBREW_CACHE_API", cache_dir)
    Homebrew::API.clear_cache
    described_class.clear_cache
  end

  def mock_curl_download(stdout:)
    allow(Utils::Curl).to receive(:curl_download) do |*_args, **kwargs|
      kwargs[:to].write stdout
    end
    allow(Homebrew::API).to receive(:verify_and_parse_jws) do |json_data|
      [true, json_data]
    end
  end

  describe "::all_casks" do
    let(:casks_json) do
      <<~EOS
        [{
          "token": "foo",
          "url": "https://brew.sh/foo"
        }, {
          "token": "bar",
          "url": "https://brew.sh/bar"
        }]
      EOS
    end
    let(:casks_hash) do
      {
        "foo" => { "url" => "https://brew.sh/foo" },
        "bar" => { "url" => "https://brew.sh/bar" },
      }
    end

    it "returns the expected cask JSON list" do
      mock_curl_download stdout: casks_json
      casks_output = described_class.all_casks
      expect(casks_output).to eq casks_hash
    end
  end

  describe "::fetch_source" do
    it "fetches the source of a cask (defaulting to master when no `git_head` is passed)" do
      curl_output = instance_double(SystemCommand::Result, stdout: "foo", success?: true)
      expect(Utils::Curl).to receive(:curl_output)
        .with("--fail", "https://raw.githubusercontent.com/Homebrew/homebrew-cask/HEAD/Casks/foo.rb")
        .and_return(curl_output)
      described_class.fetch_source("foo", path: "Casks/foo.rb", git_head: "HEAD")
    end
  end
end
