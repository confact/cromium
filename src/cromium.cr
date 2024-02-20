require "./cromium/browser.cr"

module Cromium
  VERSION = "0.1.0"

  @@endpoint = "http://localhost:9222"
  @@process = true

  def self.endpoint=(endpoint)
    @@endpoint = endpoint
  end

  def self.remote=(remote)
    @@process = remote
  end

  def self.start : Browser
    Browser.start
  end

  def self.stop
    Browser.stop if Browser.running?
  end

  def self.version
    VERSION
  end

  def self.process
    @@process
  end

  def self.endpoint
    @@endpoint
  end
end
