require 'ferrum'

module Browser
  def self.run
    browser = if ENV['IN_DOCKER'] == 'true'
                Ferrum::Browser.new(browser_options: { 'no-sandbox': nil })
              else
                Ferrum::Browser.new
              end

    begin
      yield browser
    ensure
      browser.quit
    end
  end

  def self.wait_for(browser, css)
    10.times do
      browser.network.wait_for_idle

      tag = browser.at_css(css)
      return tag if tag

      sleep 1
    end
    nil
  end
end
