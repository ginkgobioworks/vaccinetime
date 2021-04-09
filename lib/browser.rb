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
end
