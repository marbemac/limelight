class PostPublish

  @queue = :medium

  def self.perform(post_id)
    post = PostMedia.unscoped.find(post_id)
    if post
      post.publish
      post.publish_shares
      post.save
      post.expire_cached_json
    end
  end
end