class TopicConnection
  include Mongoid::Document
  include Mongoid::Timestamps::Updated

  field :name
  field :reverse_name, :default => nil
  field :inline
  field :pull_from, :default => false, :type => Boolean
  field :reverse_pull_from, :default => false, :type => Boolean
  field :user_id

  belongs_to :user, index: true

  validates :name, :presence => true, :uniqueness => { :case_sensitive => false }
  validates :user_id, :presence => true

  attr_accessible :name, :reverse_name, :pull_from, :reverse_pull_from, :inline

  index({ :name => 1 })

  # Return the topic slug instead of its ID
  def to_param
    self.name.parameterize
  end

  def created_at
    id.generation_time
  end

  class << self

    # find a topic by slug or id
    def find_by_slug_id(id)
      if Moped::BSON::ObjectId.legal?(id)
        TopicConnection.find(id)
      else
        TopicConnection.where(:name => id).first
      end
    end

    # pulla is a hash of format { :pull => Boolean, :reverse_pull => Boolean }
    # TODO: improve error detection - return false and don't save topics if no connection was created?
    # TODO: use batch operations
    def add(connection, topic1, topic2, user_id, pulla=nil)
      rel1 = Neo4j.get_connection(connection.id, topic1.id, topic2.id)
      unless rel1
        action_log = {
                :action => 'create',
                :from_id => user_id,
                :to_id => connection.id,
                :from_topic => topic1.id,
                :to_topic => topic2.id
        }
        node1 = Neo4j.neo.get_node_index('topics', 'uuid', topic1.id.to_s)
        node2 = Neo4j.neo.get_node_index('topics', 'uuid', topic2.id.to_s)

        unless node1
          topic1.neo4j_create
          node1 = Neo4j.neo.get_node_index('topics', 'uuid', topic1.id.to_s)
        end
        unless node2
          topic2.neo4j_create
          node2 = Neo4j.neo.get_node_index('topics', 'uuid', topic2.id.to_s)
        end

        rel1 = Neo4j.neo.create_relationship(connection.name, node1, node2)
        Neo4j.neo.set_relationship_properties(rel1, {
                'connection_id' => connection.id.to_s,
                'reverse_name' => connection.reverse_name,
                'user_id' => user_id.to_s,
                'pull' => (pulla.nil? ? connection.pull_from : pulla[:pull]),
                'reverse_pull' => (pulla.nil? ? connection.reverse_pull_from : pulla[:reverse_pull])
        })
        Neo4j.neo.add_relationship_to_index('topics', connection.id.to_s, "#{topic1.id.to_s}-#{topic2.id.to_s}", rel1)

        if (pulla.nil? && connection.pull_from == true) || (!pulla.nil? && pulla[:pull])
          rel1 = Neo4j.neo.get_relationship_index('topics', 'pull', "#{topic1.id.to_s}-#{topic2.id.to_s}")
          unless rel1
            rel1 = Neo4j.neo.create_relationship('pull', node1, node2)
            Neo4j.neo.add_relationship_to_index('topics', 'pull', "#{topic1.id.to_s}-#{topic2.id.to_s}", rel1)
            action_log[:pull_from] = true
          end
        end

        if (pulla.nil? && connection.reverse_pull_from == true) || (!pulla.nil? && pulla[:reverse_pull])
          rel1 = Neo4j.neo.get_relationship_index('topics', 'pull', "#{topic2.id.to_s}-#{topic1.id.to_s}")
          unless rel1
            rel1 = Neo4j.neo.create_relationship('pull', node2, node1)
            Neo4j.neo.add_relationship_to_index('topics', 'pull', "#{topic2.id.to_s}-#{topic1.id.to_s}", rel1)
            action_log[:reverse_pull_from] = true
          end
        end

        if connection.id.to_s == Topic.type_of_id && !topic1.primary_type_id
          topic1.set_primary_type(topic2.id)
        end

        topic1.save
        topic2.save
        #TopicConSug.destroy_all(conditions: { topic1_id: topic1.id, topic2_id: topic2.id, con_id: connection.id })
        Neo4j.update_affinity(topic1.id.to_s, topic2.id.to_s, node1, node2, 10, true, true)
        ActionConnection.create(action_log)
        true
      else
        false
      end
    end

    # add a pull connection from topic1 -> topic2
    def add_pull(topic1, topic2)
      rel1 = Neo4j.neo.get_relationship_index('topics', 'pull', "#{topic1.id.to_s}-#{topic2.id.to_s}")
      unless rel1
        node1 = Neo4j.neo.get_node(topic1.neo4j_id)
        node2 = Neo4j.neo.get_node(topic2.neo4j_id)

        rel1 = Neo4j.neo.create_relationship('pull', node1, node2)
        Neo4j.neo.add_relationship_to_index('topics', 'pull', "#{topic1.id.to_s}-#{topic2.id.to_s}", rel1)
      end
      true
    end

    def remove(connection, topic1, topic2)
      node = Neo4j.neo.get_node(topic1.neo4j_id)

      rel1 = Neo4j.neo.get_relationship_index('topics', connection.id.to_s, "#{topic1.id.to_s}-#{topic2.id.to_s}")
      unless rel1
        rel1 = Neo4j.neo.get_relationship_index('topics', connection.id.to_s, "#{topic2.id.to_s}-#{topic1.id.to_s}")
      end
      if rel1
        Neo4j.neo.delete_relationship(rel1)
        Neo4j.neo.remove_relationship_from_index('topics', rel1)
      else # find the relationship manually
        outgoing = Neo4j.neo.get_node_relationships(node, "out", connection.name)
        if outgoing
          outgoing.each do |rel|
            if Neo4j.parse_id(rel['end']).to_i == topic2.neo4j_id.to_i
              Neo4j.neo.delete_relationship(rel)
              break
            end
          end
        end
      end

      # check to see if we should remove the pull connections
      outgoing = Neo4j.neo.get_node_relationships(node, "out")
      incoming = Neo4j.neo.get_node_relationships(node, "in")
      pull = false
      reverse_pull = false

      if outgoing
        outgoing.each do |o|
          if Neo4j.parse_id(o['end']) == topic2.neo4j_id.to_i
            pull = true if o['data']['pull']
            reverse_pull = true if o['data']['reverse_pull']
          end
        end
      end

      if incoming
        incoming.each do |o|
          if Neo4j.parse_id(o['start']) == topic2.neo4j_id.to_i
            pull = true if o['data']['reverse_pull']
            reverse_pull = true if o['data']['pull']
          end
        end
      end

      unless pull
        rel1 = Neo4j.neo.get_relationship_index('topics', 'pull', "#{topic1.id.to_s}-#{topic2.id.to_s}")
        if rel1
          rel1 = [rel1] unless rel1.kind_of?(Array)
          rel1.each do |rel|
            Neo4j.neo.delete_relationship(rel)
            Neo4j.neo.remove_relationship_from_index('topics', rel)
          end
        else # look for it manually
          outgoing = Neo4j.neo.get_node_relationships(node, "out", 'pull')
          if outgoing
            outgoing.each do |rel|
              if Neo4j.parse_id(rel['end']) == topic2.neo4j_id.to_i
                Neo4j.neo.delete_relationship(rel)
              end
            end
          end
        end
      end

      unless reverse_pull
        rel1 = Neo4j.neo.get_relationship_index('topics', 'pull', "#{topic2.id.to_s}-#{topic1.id.to_s}")
        if rel1
          rel1 = [rel1] unless rel1.kind_of?(Array)
          rel1.each do |rel|
            Neo4j.neo.delete_relationship(rel)
            Neo4j.neo.remove_relationship_from_index('topics', rel)
          end
        else # look for it manually
          incoming = Neo4j.neo.get_node_relationships(node, "in", 'pull')
          if incoming
            incoming.each do |rel|
              if Neo4j.parse_id(rel['start']) == topic2.neo4j_id.to_i
                Neo4j.neo.delete_relationship(rel)
              end
            end
          end
        end
      end

      if connection.id.to_s == Topic.type_of_id
        # check to see if there are other type of connections we can replace this one with
        query = "
          START topic=node:topics(uuid = '#{topic1.id.to_s}')
          MATCH topic-[r1:`Type Of`]->topic2
          WHERE
          RETURN r1,topic2
        "
        types = Neo4j.neo.execute_query(query)
        if types && types['data'].length > 0 && topic1.primary_type == topic2.name
          topic1.primary_type = types['data'][0][1]['data']['name']
          topic1.primary_type_id = types['data'][0][1]['data']['uuid']
        elsif !types || types['data'].length == 0
          topic1.primary_type = nil
          topic1.primary_type_id = nil
        end
        topic1.save
        Resque.enqueue(SmCreateTopic, topic1.id.to_s)
      end

      Neo4j.update_affinity(topic1.id.to_s, topic2.id.to_s, nil, nil, -10, true, false)
    end

    # remove a pull connection from topic1 -> topic2
    def remove_pull(topic1, topic2)
      rel1 = Neo4j.neo.get_relationship_index('topics', 'pull', "#{topic1.id.to_s}-#{topic2.id.to_s}")
      if rel1
        Neo4j.neo.delete_relationship(rel1)
        Neo4j.neo.remove_relationship_from_index('topics', rel1)
      else # find the relationship manually
        node = Neo4j.neo.get_node(topic1.neo4j_id)
        outgoing = Neo4j.neo.get_node_relationships(node, "out", 'pull')
        if outgoing
          outgoing.each do |rel|
            if Neo4j.parse_id(rel['end']).to_i == topic2.neo4j_id.to_i
              Neo4j.neo.delete_relationship(rel)
              break
            end
          end
        end
      end
    end
  end
end