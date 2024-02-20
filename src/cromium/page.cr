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
    data
  end

  def goto(url : String)
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
    puts "Setting content"
    send_command("Page.setDocumentContent", frameId: frame.id, html: content)
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

  def wait_to_page_load
    return if @navigate_type == NAVIGATE_TYPE::SET_CONTENT
    send_command("Page.enable")
    puts "Waiting for page to load..."
    @done_callback_channel.receive # wait for frameStoppedLoading
  end

  def wait_to_page_load(&block)
    wait_to_page_load
    block.call
  end

  def close
    @ws.close
  end

  def wait_for_function(function : String) : JSON::Any
    data = send_command("Runtime.evaluate", expression: function)
    data["result"]["result"]
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
      if data["method"] == "Page.frameStoppedLoading"
        @requested_callbacks_mutex.synchronize do
          @done_callback_channel.send(0)
        end
      end
    end
  end
end