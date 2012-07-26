ProjectLimelight::Application.configure do
  # Settings specified here will take precedence over those in config/application.rb

  # In the development environment your application's code is reloaded on
  # every request.  This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Log error messages when you accidentally call methods on nil.
  config.whiny_nils = true

  # Show full error reports and disable caching
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # Print deprecation notices to the Rails logger
  config.active_support.deprecation = :log

  # Only use best-standards-support built into browsers
  config.action_dispatch.best_standards_support = :builtin

  # Do not compress assets
  config.assets.compress = false

  # Expands the lines which load the assets
  config.assets.debug = true

  # Raise exception on mass assignment protection for Active Record models
  #config.active_record.mass_assignment_sanitizer = :strict

  # Enable threaded mode
  #config.threadsafe!

  # Use a different cache store in development
  #config.cache_store = :torque_box_store

  # Use a different cache store in development
  #config.cache_store = :torque_box_store

  # Log the query plan for queries taking more than this (works
  # with SQLite, MySQL, and PostgreSQL)
  #config.active_record.auto_explain_threshold_in_seconds = 0.5

  config.log_tags = [:uuid, :remote_ip]

  # Pusher
  Pusher.app_id = 10176
  Pusher.key = 'da6d3243e3cce708de16'
  Pusher.secret = 'bdd4c6fd8ff0f27b25f1'

  # ActionMailer Config
  # Setup for development - deliveries, errors raised
  ActionMailer::Base.register_interceptor(DevelopmentMailInterceptor)
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.default :charset => "utf-8"
  config.action_mailer.default_url_options = {
          :host => 'localhost:3000'
  }
  config.action_mailer.smtp_settings = {
          :domain => 'projectlimelight.com',
          :address => 'smtp.sendgrid.net',
          :port => 587,
          :authentication => :plain,
          :enable_starttls_auto => true,
          :user_name => 'app1232528@heroku.com',
          :password => 'tv3ngda9'
  }
end