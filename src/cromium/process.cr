class Cromium::Process
  @process = nil : ::Process?

  def initialize
    endpoint_url = URI.parse(Cromium.endpoint)
    @process = ::Process.new("chromium", ["--headless", "--disable-gpu", "--remote-debugging-port=#{endpoint_url.port}"])
  end

  def self.start : self
    process = new
    process.wait_for_browser
    process
  end

  def stopped?
    !@process.try(&.exists?)
  end

  def stop
    if @process
      @process.try(&.signal(Signal::TERM))
      puts "Chromium process with PID #{@process.not_nil!.pid} stopped"
      @process = nil
    else
      puts "No Chromium process running"
    end
  end

  def wait_for_browser
    puts "Waiting for browser with pid #{@process.try(&.pid)} to connect..."
    loop do
      begin
        response = HTTP::Client.get("#{Cromium.endpoint}/json/version")
        puts "Response: #{response.status_code}"
        if response.status_code == 200
          puts "Browser connected"
          break
        end
        sleep 0.1
      rescue
        sleep 0.1
      end
    end
  end
end
