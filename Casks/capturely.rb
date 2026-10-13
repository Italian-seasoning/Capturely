cask "capturely" do
  version "0.1.3"
  sha256 "4988f29426ff96e6d256dea87fbae0d7039aaa6058d3853aedafa3f95d5a98c3"

  url "https://github.com/Italian-seasoning/Capturely/releases/download/v#{version}/Capturely-#{version}-macOS.zip"
  name "Capturely"
  desc "Native game replay capture and clip review"
  homepage "https://nolan-mac-apps.nolankrahn.chatgpt.site/apps/capturely"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Capturely.app"

  caveats <<~EOS
    Capturely is a preview release and is not Apple-notarized.
    Homebrew verifies the pinned SHA-256; macOS Gatekeeper checks remain enabled.
    If macOS blocks the first launch, review it in System Settings > Privacy & Security.
    Screen Recording access is required for capture.
  EOS
end
