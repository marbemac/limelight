class TopicFetchExternalData

  @queue = :slow

  def self.perform(topic_id)
    topic = Topic.find(topic_id)
    if topic
      topic.freebase_repopulate(true)
      topic.save
    end
  end
end