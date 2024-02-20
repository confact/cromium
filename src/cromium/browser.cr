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

    url = URI.parse(endpoint)
    
    @driver = HTTP::Client.new(url.host.not_nil!, url.port.not_nil!)
  end

  def send_command(command, **params)
    payload = { "method" => command, "params" => params }.to_json
    response = @driver.post("/json", body: payload)

    if response.status_code == 200
      JSON.parse(response.body)
    else
      raise "Error: #{response.status_code} #{response.body}"
    end
  end

  def version
    send_command("version")
  end

  def new_page : Page
    data = @driver.put("/json/new")
    json_data = JSON.parse(data.body)
    puts json_data
    page = Cromium::Page.new(json_data["webSocketDebuggerUrl"].as_s, json_data["id"].as_s)
    @pages << page
    page
  end

  def activate_tab(tab_id)
    response = @driver.get("/json/activate/#{tab_id}")

    if response.status_code == 200
      JSON.parse(response.body)
    else
      raise "Error: #{response.status_code} #{response.body}"
    end
  end

  def activate_page(page : Page)
    activate_tab(page.id)
  end

  def close_tab(tab_id)
    response = @driver.get("/json/close/#{tab_id}")

    @pages.delete_if { |page| page.id == tab_id }

    if response.status_code == 200
      JSON.parse(response.body)
    else
      raise "Error: #{response.status_code} #{response.body}"
    end
  end

  def close_page(page : Page)
    close_tab(page.id)
  end

  def close
    @pages.each do |page|
      page.close
      @pages.delete(page)
    end
    @driver.close
    @@process.try(&.stop)
    exit
  end

  def self.start
    Signal::INT.trap do
      @@process.try(&.stop)
      exit
    end
    Signal::HUP.trap do
      @@process.try(&.stop)
      exit
    end
    if Cromium.process
      @@process = Cromium::Process.start
    end
    new(Cromium.endpoint)
  end
end

