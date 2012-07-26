class Neo4jShareCreate

  @queue = :neo4j

  def self.perform(post_id, user_id)
    post = PostMedia.find(post_id)
    user = User.find(user_id)
    Neo4j.share_create(post, user) if post && user
  end
end