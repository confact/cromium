require "http/client"
require "json"
require "base64"
require "./process.cr"
require "./page.cr"

class Cromium::Browser
  @@process = nil : Cromium::Process?
  @pages = [] of Cromium::Page

  def initialize(endpoint : String? = nil)
    @@process ||= Cromium::Process.start if Cromium.process

    url = URI.parse(endpoint || Cromium.endpoint)
    @driver = HTTP::Client.new(url.host.not_nil!, url.port.not_nil!)
  end

  def send_command(command : String, **params)
    payload = { "method" => command, "params" => params }.to_json
    response = @driver.post("/json", body: payload)

    if response.status_code == 200
      data = JSON.parse(response.body)
      if data["error"]?
        raise "CDP Error: #{data["error"]["message"]}"
      end
      data
    else
      raise "HTTP Error: #{response.status_code} #{response.body}"
    end
  end

  def version
    send_command("Browser.getVersion")
  end

  def new_page : Cromium::Page
    response = @driver.put("/json/new")
    json_data = JSON.parse(response.body)
    page = Cromium::Page.new(json_data["webSocketDebuggerUrl"].as_s, json_data["id"].as_s)
    @pages << page
    page
  end

  def activate_tab(tab_id)
    response = @driver.get("/json/activate/#{tab_id}")
    handle_response(response)
  end

  def activate_page(page : Cromium::Page)
    activate_tab(page.id)
  end

  def close_tab(tab_id)
    response = @driver.get("/json/close/#{tab_id}")
    handle_response(response)
    @pages.reject! { |page| page.id == tab_id }
  end

  def close_page(page : Cromium::Page)
    close_tab(page.id)
  end

  def close
    @pages.each do |page|
      page.close
    end
    @driver.close
    exit
  end

  def self.start
    Signal::INT.trap do
      exit
    end

    Signal::HUP.trap do
      exit
    end

    at_exit do
      @@process.try(&.stop)
    end

    @@process = Cromium::Process.start if Cromium.process
    new(Cromium.endpoint)
  end

  private def handle_response(response)
    if response.status_code == 200
      JSON.parse(response.body)
    else
      raise "Error: #{response.status_code} #{response.body}"
    end
  end
end
