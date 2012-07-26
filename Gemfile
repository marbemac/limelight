source :rubygems

ruby '1.9.3'

gem 'bundler', '1.2.0.pre.1'
gem 'rails', '3.2.6'
gem 'jquery-rails'
gem 'rack'
gem 'rack-contrib'
gem 'mongoid', '>= 3.0.1'
gem 'devise' # Authentication
gem 'yajl-ruby' # json
gem 'omniauth-facebook'
gem 'omniauth-twitter'
gem 'koala', '1.5' # facebook graph api support
gem 'twitter' # twitter api support
gem 'tweetstream' # twitter streaming api support
gem 'resque', '1.21.0'#, :git => 'https://github.com/hone/resque.git', :branch => 'heroku'
gem 'resque-scheduler', '2.0.0.h', :require => 'resque_scheduler' # scheduled resque jobs
gem 'resque-loner' # Unique resque jobs
gem 'resque_mailer'
gem 'chronic' # Date/Time management
gem 'cancan' # Authorization
gem 'airbrake' # Exception notification
gem 'soulmate', '0.1.3', :require => 'soulmate/server' # Redis based autocomplete storage
gem 'dalli' # memcache
gem 'pusher' # pusher publish/subscribe
gem 'neography', '0.0.27' # neo4j graph database
gem 'mixpanel' # analytics
gem 'ken', :git => 'git://github.com/marbemac/ken.git' # freebase
gem 'mongoid-cached-json'
gem 'omnicontacts'
gem 'cloudinary'

group :production, :staging do
  gem "rack-timeout"
  gem 'thin'
end

group :development do
end

platforms :ruby do
  gem 'bson_ext'
  gem 'heroku'
  gem 'newrelic_rpm'
  #gem 'newrelic_moped'
  #gem 'rpm_contrib', '2.1.11' # extra instrumentation for the new relic rpm agent
  #gem 'newrelic-redis', '1.3.2' # new relic redis instrumentation
  #gem 'newrelic-faraday'

  group :development do
    gem "foreman"
    gem 'pry-rails'
  end
end

platforms :jruby do
  #gem 'jruby-openssl'
  #gem 'trinidad'
  #gem 'bson'
  #gem 'rmagick4j' # Image manipulation (put rmagick at the bottom because it's a little bitch about everything) #McM: lol
end