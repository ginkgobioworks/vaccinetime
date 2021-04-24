module UserAgents
  USER_AGENTS = []

  File.open("#{__dir__}/sites/config/user_agents.txt", 'r') do |f|
    f.each_line do |line|
      USER_AGENTS.append(line.strip)
    end
  end

  def self.all
    USER_AGENTS
  end

  def self.random
    all.sample
  end

  def self.chrome
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/89.0.4389.114 Safari/537.36'
  end
end
