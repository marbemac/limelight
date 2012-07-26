class SmCreateTopic

  @queue = :fast

  def self.perform(topic_id)
    topic = Topic.find(topic_id)
    LlSoulmate.create_topic(topic) if topic
  end
end