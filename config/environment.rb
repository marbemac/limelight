# Load the rails application
require File.expand_path('../application', __FILE__)

# Initialize the rails application
ProjectLimelight::Application.initialize!

DOMAIN_NAMES = {"staging" => "staging.projectlimelight.com", "development" => "localhost:3000", "production" =>  "projectlimelight.com", "test" => "localhost:3000"}