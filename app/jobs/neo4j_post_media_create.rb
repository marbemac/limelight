class Neo4jPostMediaCreate

  @queue = :neo4j

  def self.perform(post_media_id)
    post_media = PostMedia.find(post_media_id)
    Neo4j.post_media_create(post_media) if post_media
  end
end