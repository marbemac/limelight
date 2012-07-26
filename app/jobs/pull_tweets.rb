class PullTweets

  @queue = :slow

  def self.perform
    users = User.where(:twitter_handle => {"$exists" => true})
    users.each do |user|
      # Get user's tweets
      tweets = Twitter.user_timeline(user.twitter_handle, :count => 50, :exclude_replies => true, :include_entities => true, :since_id => user.latest_tweet_id)
      tweets.reverse.each do |tweet|
        PostMedia.create_pending_from_tweet(user, tweet)
        user.latest_tweet_id = tweet.id
      end
      user.save
    end
  end
end