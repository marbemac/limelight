require "omnicontacts"

Rails.application.middleware.use OmniContacts::Builder do
  importer :gmail, ENV["GOOGLE_KEY"] || "878681641011-539hes1hlj5t55qte7hmg9jk6113va14.apps.googleusercontent.com", ENV["GOOGLE_SECRET"] || "RRXSZ7AWo9By3CYENka3RsEj", {:redirect_path => "/contacts/gmail/callback", :max_results => 1500}
  importer :yahoo, ENV["YAHOO_KEY"] || "dj0yJmk9TE5jZGFncEhHRnNtJmQ9WVdrOVdHeGFUekV5TjJFbWNHbzlNVEEzTWpnNE9EazJNZy0tJnM9Y29uc3VtZXJzZWNyZXQmeD1jMA--", ENV["YAHOO_KEY"] || "ded9b15bf89408dd6e0d2b5dc56875ff58b36d1b", {:callback_path => '/contacts/yahoo/callback'}
  #importer :hotmail, "00000000480CA45F", "9yGM7CTe78KCaCqTa-h292leZJs20Atw", {:redirect_uri => "http://staging.projectlimelight.com/contacts/hotmail/callback"}
end