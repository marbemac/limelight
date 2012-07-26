require 'resque_scheduler'

if ENV["REDISTOGO_URL"]
  uri = URI.parse(ENV["REDISTOGO_URL"])
  Resque.redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
elsif Rails.env.development?
  Resque.redis = 'localhost:6379'
end

Dir["#{Rails.root}/app/jobs/*.rb"].each { |file| require file }

#Resque::Scheduler.dynamic = true
Resque.schedule = YAML.load_file(File.join(Rails.root, 'config/resque_schedule.yml'))