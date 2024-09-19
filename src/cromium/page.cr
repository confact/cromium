require "./frame"
class Cromium::Page
  property id : String
  property url : String
  property frame : Frame
  property requested_callbacks : Int32 = 0
  property navigate_type : NAVIGATE_TYPE = NAVIGATE_TYPE::NAVIGATE
  property done_callback_channel : Channel(Int32)
  property callback_channel : Hash(Int32, Channel(JSON::Any)) = Hash(Int32, Channel(JSON::Any)).new
  property requested_callbacks_mutex : Mutex = Mutex.new
  property active_requests : Int32 = 0
  property ws : HTTP::WebSocket

  enum NAVIGATE_TYPE
    NAVIGATE
    SET_CONTENT
  end

  def initialize(@url : String, @id : String)
    @done_callback_channel = Channel(Int32).new
    @ws = HTTP::WebSocket.new(@url)
    setup_websocket
    frame_id = get_frame_id
    @frame = Frame.new(frame_id)
  end

  private def setup_websocket
    @ws.on_message do |message|
      handle_message(message)
    end

    spawn do
      @ws.run
    end
  end

  def send_command(command : String, **params) : JSON::Any
    @requested_callbacks += 1
    message = {
      "id" => @requested_callbacks,
      "method" => command,
      "params" => params
    }.to_json
    @callback_channel[@requested_callbacks] = Channel(JSON::Any).new
    
    @ws.send(message)
    data = @callback_channel[@requested_callbacks].receive
    @callback_channel.delete(@requested_callbacks)
    data
  end

  def send_command(command : String) : JSON::Any
    @requested_callbacks += 1
    message = {
      "id" => @requested_callbacks,
      "method" => command,
      "params" => {} of String => String
    }.to_json
    @callback_channel[@requested_callbacks] = Channel(JSON::Any).new
    
    @ws.send(message)
    data = @callback_channel[@requested_callbacks].receive
    @callback_channel.delete(@requested_callbacks)

    if data["error"]?
      raise "CDP Error: #{data["error"]["message"]}"
    end

    data
  end

  def goto(url : String)
    @navigate_type = NAVIGATE_TYPE::NAVIGATE
    send_command("Page.navigate", url: url)
  end

  def navigate(url : String)
    goto(url)
  end

  def screenshot_to_file(filename : String)
    puts "Taking screenshot"
    file = screenshot
    File.write(filename, Base64.decode(file))
  end

  def screenshot_to_file(filename : String, **params)
    file = screenshot(**params)
    File.write(filename, Base64.decode(file))
  end

  def screenshot : String
    send_command("Page.captureScreenshot")["result"]["data"].as_s
  end

  def screenshot(**params) : String
    send_command("Page.captureScreenshot", **params)["result"]["data"].as_s
  end

  def pdf_to_file(filename : String)
    puts "Taking pdf"
    file = pdf
    File.write(filename, Base64.decode(file))
  end

  def pdf_to_file(filename : String, **params)
    file = pdf(**params)
    File.write(filename, Base64.decode(file))
  end

  def pdf(**params) : String
    send_command("Page.printToPDF", **params)["result"]["data"].as_s
  end

  def pdf : String
    send_command("Page.printToPDF")["result"]["data"].as_s
  end

  def html : String
    send_command("Runtime.evaluate", expression: "document.documentElement.outerHTML")["result"]["result"]["value"].as_s
  end

  def get_frame_id
    data = send_command("Page.getFrameTree")
    data["result"]["frameTree"]["frame"]["id"].as_s
  end

  def set_content(content : String, wait_for : String = "networkIdle0")
    script = "document.open(); document.write(#{content.to_json}); document.close();"
    send_command("Runtime.evaluate", expression: script)
    @navigate_type = NAVIGATE_TYPE::SET_CONTENT
  end

  def set_content(content : IO, wait_for : String = "networkIdle0")
    set_content(content.read, wait_for)
  end

  def on_screenshot(&block : (JSON::Any) -> Nil)
    on_event("Page.captureScreenshot") do |data|
      block.call(data["result"]["data"])
    end
  end

  def on_pdf(&block : (JSON::Any) -> Nil)
    on_event("Page.printToPDF") do |data|
      block.call(data["result"]["data"])
    end
  end

  def on_html(&block : (JSON::Any) -> Nil)
    on_event("Runtime.evaluate", expression: "document.documentElement.outerHTML") do |data|
      block.call(data["result"]["result"]["value"])
    end
  end

  def wait_for_page_load
    send_command("Page.enable")
    send_command("Network.enable")
    puts "Waiting for page to load..."

    if @navigate_type == NAVIGATE_TYPE::SET_CONTENT
      wait_for_network_idle_and_page_load
    else
      wait_for_page_load_event
    end
  end

  def wait_for_page_load(&block)
    wait_for_page_load
    block.call
  end

  def close
    @ws.close
  end

  def wait_for_function(function : String) : JSON::Any
    data = send_command("Runtime.evaluate", expression: function)
    data["result"]["result"]
  end

  private def wait_for_page_load_event
    puts "Waiting for page load event..."
    @done_callback_channel.receive # Wait for Page.loadEventFired
    puts "Page load event detected."
  end

  private def wait_for_network_idle_and_page_load
    spawn do
      loop do
        # Wait for page load to complete and for network requests to finish
        if @active_requests == 0
          # Wait for an additional 500ms to ensure no new requests come in
          sleep 0.5
          if @active_requests == 0
            puts "Network idle detected."
            @done_callback_channel.send(0)
            break
          end
        end
        sleep 0.1
      end
    end

    wait_for_page_load_event
  end

  private def on_event(event : String, block : (JSON::Any) -> Nil)
    data = send_command(event)
    yield data
  end

  private def on_event(event : String, **params)
    data = send_command(event, **params)
    yield data
  end

  private def handle_message(message : String)
    data = JSON.parse(message)
    if data["id"]?
      @requested_callbacks_mutex.synchronize do
        callback = @callback_channel[data["id"].as_i]?
        unless callback
          return
        end
        callback.send(data)
      end
    elsif data["method"]?
      # Handle network events
      if data["method"] == "Network.requestWillBeSent"
        @active_requests += 1
      elsif data["method"] == "Network.loadingFinished" || data["method"] == "Network.loadingFailed"
        @active_requests -= 1
      elsif data["method"] == "Page.loadEventFired"
        @done_callback_channel.send(0)
      end
    end
  end
end