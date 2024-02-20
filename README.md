# Cromium

An simple CDP (Chrome Devtools Protocol) client, made for testing, scraping, screenshot and html to pdf.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     cromium:
       github: confact/cromium
   ```

2. Run `shards install`

## Usage

```crystal
require "cromium"
```

### Settings

Default is local chromium executable. Cromium is using Crystal's `Process`, which looks for `chrome` in absolute path, path relative to pwd, or in path.

If you want to use a remote address and turn off the process:
```
Cromium.remote = true
Cromium.endpoint = "https://chrome.browserless.io/sdsdsdfsd"
```

If you want to run your chromium process on a specific port, instead of default 9222, just set the endpoint, but keep remote as `false`
```
Cromium.endpoint = "http://localhost:9000"
```

### API

#### Browser

* Cromium.start
  
  will return a browser, that holds the actual process or browser websocket.

* .new_page
  
  Create a new tab/page to use to browse the internet

#### Page

* .goto(string)
  
  navigates to the url

* .wait_to_page_load (&block)
  
  used after a goto, to wait for the page to render, it load until getting "correct" response from chrome.

* .screenshot
    
  returns a base64 encoded screenshot of the page

* .screenshot_to_file(file_name, **params)
    
  saves a screenshot to file, support setting params to send with command, if full_page is true, it will take a screenshot of the whole page, if hide_scrollbars is true, it will hide the scrollbars.

* .pdf
      
  returns a base64 encoded pdf of the page

* .pdf_to_file(file_name, **params)
      
  saves a pdf to file, support setting params to send with command, if print_background is true, it will print the background.

* .html
  
  returns the html of the page

* .set_content(string) * Not fully working yet *
  
  sets the content of the page

### Example

```
require "cromium"

browser = Cromium.start

page = browser.new_page

page.goto "https://www.google.com"

page.wait_to_page_load do
  page.screenshot_to_file "google.png", full_page: true, hide_scrollbars: true
  page.pdf_to_file "google.pdf", print_background: true
end
browser.close

```

## Contributing

1. Fork it (<https://github.com/confact/cromium/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Håkan](https://github.com/confact) - creator and maintainer
