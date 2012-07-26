namespace :tweet_stream do

  desc "Stream from Twitter"

  desc "Stream from a single user"
  task :userstream => :environment do
    include EmbedlyHelper
    require 'tweetstream'

    user = User.find(User.matt_id)
    stream = user.tweet_stream

    if stream
      stream.userstream do |status|
        puts "New Tweet"
        if status.user.id.to_s == user.twuid
          puts PostMedia.create_pending_from_tweet(user, status)
        end
      end
    end
  end

end