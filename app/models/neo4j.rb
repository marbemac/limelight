class Neo4j

  class << self

    def neo
      @neo ||= ENV['NEO4J_URL'] ? Neography::Rest.new(ENV['NEO4J_URL']) : Neography::Rest.new
    end

    def parse_id(string)
      string.split('/').last.to_i
    end

    def find_or_create_category(name)
      topic = Topic.where("aliases.slug" => name.parameterize).first

      unless !topic || topic.is_category
        topic.is_category = true
        topic.save
      end

      unless topic
        topic = Topic.new
        topic.name = name
        topic.user_id = User.marc_id
        topic.is_category = true
        topic.save
      end

      topic.neo4j_node
    end

    def share_create(post, user)
      share = post.get_share(user.id)
      return unless share

      post_node = Neo4j.neo.get_node_index('post_media', 'uuid', post.id.to_s)
      user_node = Neo4j.neo.get_node_index('users', 'uuid', user.id.to_s)

      # add share relationship between user and post
      rel1 = Neo4j.neo.create_relationship('shared', user_node, post_node)
      Neo4j.neo.add_relationship_to_index('users', 'shared', "#{user.id.to_s}-#{post.id.to_s}", rel1)

      topic_node1 = nil
      topic_node2 = nil

      # increase affinity between mentioned topics and the sharer
      # increase the talk count between the user and mentioned topics
      share.topic_mentions.each_with_index do |t,i|
        if i == 0
          topic_node1 = Neo4j.neo.get_node_index('topics', 'uuid', t.id.to_s)
          Neo4j.update_affinity(user.id.to_s, t.id.to_s, user_node, topic_node1, 1)
          Neo4j.update_talk_count(user, t, 1, user_node, topic_node1, post.id)
        else
          topic_node2 = Neo4j.neo.get_node_index('topics', 'uuid', t.id.to_s)
          Neo4j.update_affinity(user.id.to_s, t.id.to_s, user_node, topic_node2, 1)
          Neo4j.update_talk_count(user, t, 1, user_node, topic_node2, post.id)
        end
      end

      # increase affinity between mentioned topics and each other
      if share.topic_mentions.length > 1
        topics = share.topic_mentions.to_a
        Neo4j.update_affinity(topics[0].id.to_s, topics[1].id.to_s, topic_node1, topic_node1, 1, true, nil)
      end
    end

    # update the talk relationship between a user and a topic
    def update_talk_count(user, topic, change, user_node=nil, topic_node=nil, post_id=nil)
      talking = Neo4j.neo.get_relationship_index('talking', 'nodes', "#{user.id.to_s}-#{topic.id.to_s}")
      user_node = Neo4j.neo.get_node_index('users', 'uuid', user.id.to_s) unless user_node
      topic_node = Neo4j.neo.get_node_index('topics', 'uuid', topic.id.to_s) unless topic_node

      if talking
        payload = {}
        properties = Neo4j.neo.get_relationship_properties(talking)
        weight = properties && properties['weight'] ? properties['weight'] : 0
        if weight + change == 0
          Neo4j.neo.delete_relationship(talking)
          Neo4j.neo.remove_relationship_from_index('talking', talking)
        else
          payload['weight'] = weight+change
        end

        if post_id
          if change > 0
            payload['shares'] = properties['shares'] ? (properties['shares'] << post_id.to_s).uniq : [post_id.to_s]
          elsif properties['shares']
            properties['shares'].delete(post_id.to_s)
            payload['shares'] = properties['shares'] if properties['shares'].length > 0
          end
        end

        Neo4j.neo.set_relationship_properties(talking, payload) if payload.length > 0
      else
        payload = {'weight' => change}
        if post_id
          payload['shares'] = [post_id.to_s]
        end

        talking = Neo4j.neo.create_relationship('talking', user_node, topic_node)
        Neo4j.neo.set_relationship_properties(talking, payload)
        Neo4j.neo.add_relationship_to_index('talking', 'nodes', "#{user.id.to_s}-#{topic.id.to_s}", talking)
      end

      Neo4j.update_affinity(user.id.to_s, topic.id.to_s, user_node, topic_node, change, true)
    end

    def post_add_topic_mention(post, topic, post_node=nil, creator_node=nil, mention_node=nil, topic_nodes=nil)
      # increase the creators affinity to these topics
      unless post.user_id.to_s == User.limelight_user_id
        Neo4j.update_affinity(post.user_id.to_s, topic.id.to_s, creator_node, mention_node, 1, false)
      end

      unless topic_nodes
        topic_nodes = []
        post.topic_mentions.each do |m|
          if m.id != topic.id
            node = Neo4j.neo.get_node_index('topics', 'uuid', m.id.to_s)
            topic_nodes << {:node => node, :node_id => m.id.to_s}
          end
        end
      end

      # increase the mentioned topics affinity towards the other mentioned topics
      topic_nodes.each do |t|
        Neo4j.update_affinity(topic.id.to_s, t[:node_id], mention_node, t[:node], 1, true)
      end
    end

    def post_remove_topic_mention(post, topic)
      mention_node = Neo4j.neo.get_node_index('topics', 'uuid', topic.id.to_s)
      return unless mention_node

      rel1 = Neo4j.neo.get_relationship_index('posts', 'mentions', "#{post.id.to_s}-#{topic.id.to_s}")
      return unless rel1

      Neo4j.neo.delete_relationship(rel1)
      Neo4j.neo.remove_relationship_from_index('posts', rel1)

      # decrease the creators affinity to these topics
      creator_node = Neo4j.neo.get_node_index('users', 'uuid', post.user_id.to_s)
      Neo4j.update_affinity(post.user_id.to_s, topic.id.to_s, creator_node, mention_node, -1, false)

      topic_nodes = []
      post.topic_mentions.each do |m|
        if m.id != topic.id
          node = Neo4j.neo.get_node_index('topics', 'uuid', m.id.to_s)
          topic_nodes << {:node => node, :node_id => m.id.to_s}
        end
      end

      # decrease the mentioned topics affinity towards the other mentioned topics
      topic_nodes.each do |t|
        Neo4j.update_affinity(topic.id.to_s, t[:node_id], mention_node, t[:node], -1, true)
      end

    end

    # updates the affinity between two nodes
    def update_affinity(node1_id, node2_id, node1, node2, change=0, mutual=nil)
      affinity = self.neo.get_relationship_index('affinity', 'nodes', "#{node1_id}-#{node2_id}")
      if affinity
        payload = {}
        if change
          properties = self.neo.get_relationship_properties(affinity)
          weight = properties && properties['weight'] ? properties['weight'] : 0
          if weight + change == 0
            self.neo.delete_relationship(affinity)
            self.neo.remove_relationship_from_index('affinity', affinity)
          else
            payload['weight'] = weight+change
          end
        end

        self.neo.set_relationship_properties(affinity, payload) if payload.length > 0
      else
        affinity = self.neo.create_relationship('affinity', node1, node2)
        self.neo.set_relationship_properties(affinity, {
                'weight' => change,
                'mutual' => mutual
        })
        self.neo.add_relationship_to_index('affinity', 'nodes', "#{node1_id}-#{node2_id}", affinity)
        if mutual == true
          self.neo.add_relationship_to_index('affinity', 'nodes', "#{node2_id}-#{node1_id}", affinity)
        end
      end
    end

    # get a topic's relationships. sort them into two groups, outgoing and incoming
    def get_topic_relationships(topic)
      query = "
        START n=node:topics(uuid = '#{topic.id}')
        MATCH (n)-[r]->(x)
        WHERE has(r.connection_id)
        RETURN r,x
      "
      outgoing = Neo4j.neo.execute_query(query)

      query = "
        START n=node:topics(uuid = '#{topic.id}')
        MATCH (n)<-[r]-(x)
        WHERE has(r.connection_id)
        RETURN r,x
      "
      incoming = Neo4j.neo.execute_query(query)

      query = "
        START n=node:topics(uuid = '#{topic.id}')
        MATCH (n)-[r:pull]->(x)
        RETURN r,x
      "
      pulls = Neo4j.neo.execute_query(query)

      query = "
        START n=node:topics(uuid = '#{topic.id}')
        MATCH (n)<-[r:pull]-(x)
        RETURN r,x
      "
      pushes = Neo4j.neo.execute_query(query)

      organized = {}

      if outgoing
        outgoing['data'].each do |c|
          type = c[0]['type']
          organized[type] ||= c[0]['data'].select{|key,value|['connection_id','reverse_name','inline'].include?(key)}.merge({'connections' => []})
          organized[type]['connections'] << c[0]['data'].select{|key,value|['user_id'].include?(key)}.merge(c[1]['data'])
        end
      end

      if incoming
        incoming['data'].each do |c|
          type = c[0]['data']['reverse_name'].blank? ? c[0]['type'] : c[0]['data']['reverse_name']
          organized[type] ||= c[0]['data'].select{|key,value|['connection_id','reverse_name','inline'].include?(key)}.merge({'connections' => []})
          data = c[0]['data'].select{|key,value|['user_id'].include?(key)}.merge(c[1]['data'])
          organized[type]['connections'] << data
        end
      end

      if pulls
        pulls['data'].each do |c|

          found = nil

          organized.each do |k,o|
            found = o['connections'].detect{|con| con['uuid'] == c[1]['data']['uuid'] }
            break if found
          end

          if found
            found['pull'] = true
            next
          end

          type = 'Pull'
          organized[type] ||= {
              'connection_id' => 'pull',
              'reverse_name' => 'pull',
              'inline' => 'pull',
              'connections' => []
          }
          organized[type]['connections'] << { 'pull' => true }.merge(c[1]['data'])
        end
      end

      if pushes
        pushes['data'].each do |c|

          found = nil

          organized.each do |k,o|
            found = o['connections'].detect{|con| con['uuid'] == c[1]['data']['uuid'] }
            break if found
          end

          if found
            found['reverse_pull'] = true
            next
          end

          type = 'Push'
          organized[type] ||= {
              'connection_id' => 'push',
              'reverse_name' => 'push',
              'inline' => 'push',
              'connections' => []
          }
          organized[type]['connections'] << { 'reverse_pull' => true }.merge(c[1]['data'])
        end
      end

      returnable = []
      organized.each do |type, data|
        returnable << {:name => type}.merge(data)
      end

      returnable
    end

    # get a topics pull from ids (aka the children)
    def pull_from_ids(topic_neo_id, depth=20)
      Rails.cache.fetch("neo4j-#{topic_neo_id}-pulling-#{depth}", :expires_in => 2.minutes) do
        query = "
          START n=node(#{topic_neo_id})
          MATCH n-[:pull*1..#{depth}]->x
          RETURN distinct x.uuid
        "
        ids = Neo4j.neo.execute_query(query)
        pull_from = []
        if ids
          ids['data'].each do |id|
            pull_from << Moped::BSON::ObjectId(id[0])
          end
        end
        pull_from
      end
    end

    # get the topics that pull from the given topics (aka the parents)
    def pulled_from_ids(topic_neo_id, depth=20)
      Rails.cache.fetch("neo4j-#{topic_neo_id}-pushing-#{depth}", :expires_in => 2.minutes) do
        query = "
          START n=node(#{topic_neo_id})
          MATCH n<-[:pull*1..#{depth}]-x
          RETURN distinct x.uuid
        "
        ids = Neo4j.neo.execute_query(query)
        pull_from = []
        if ids
          ids['data'].each do |id|
            pull_from << Moped::BSON::ObjectId(id[0])
          end
        end
        pull_from
      end
    end

    def user_topic_children(user_id, topic_neo_id)
      Rails.cache.fetch("neo4j-#{user_id}-#{topic_neo_id}-pulling", :expires_in => 2.minutes) do
        query = "
          START n=node(#{topic_neo_id})
          MATCH n-[:pull]->x-[:pull*0..20]->y<-[:talking]-z
          WHERE z.uuid = '#{user_id}'
          RETURN distinct x.uuid
        "
        ids = Neo4j.neo.execute_query(query)
        children_ids = []
        if ids
          ids['data'].each do |id|
            children_ids << Moped::BSON::ObjectId(id[0])
          end
        end
        children_ids
      end
    end

    def user_topics(user_neo_id)
      Rails.cache.fetch("neo4j-#{user_neo_id}-topics", :expires_in => 2.minutes) do
        query = "
          START n=node(#{user_neo_id})
          MATCH n-[:talking]->x<-[:pull*0..20]-y<-[?:pull]-z
          WHERE z is null
          RETURN distinct y.uuid
        "
        ids = Neo4j.neo.execute_query(query)
        topic_ids = []
        if ids
          ids['data'].each do |id|
            topic_ids << Moped::BSON::ObjectId(id[0])
          end
        end
        topic_ids
      end
    end

    # get the # of shares a user has in this topic and it's children
    def user_topic_share_count(user_id, topic_neo_id)
      Rails.cache.fetch("neo4j-#{user_id}-#{topic_neo_id}-share_count", :expires_in => 2.minutes) do
        count = 0
        query = "
          START n=node(#{topic_neo_id})
          MATCH n-[:pull*0..20]->x<-[r:talking]-y
          WHERE y.uuid = '#{user_id}'
          RETURN r.shares
        "
        data = Neo4j.neo.execute_query(query)
        ids = []
        if data && data['data']
          data['data'].each do |d|
            ids += d[0]
          end
          count = ids.uniq.length
        end
        count
      end
    end

    def get_connection(con_id, topic1_id, topic2_id)
      Neo4j.neo.get_relationship_index('topics', con_id.to_s, "#{topic1_id.to_s}-#{topic2_id.to_s}")
    end
  end

end