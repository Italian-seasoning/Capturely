cask "capturely" do
  version :latest
  sha256 :no_check

  url "https://github.com/Italian-seasoning/Capturely/releases/latest/download/Capturely.zip"
  name "Capturely"
  desc "Native replay clipping for games"
  homepage "https://github.com/Italian-seasoning/Capturely"

  auto_updates true
  depends_on macos: :tahoe

  app "Capturely.app"
end
