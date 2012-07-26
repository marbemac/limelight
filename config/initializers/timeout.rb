if Rails.env.production?
  Rack::Timeout.timeout = 30  # seconds
end