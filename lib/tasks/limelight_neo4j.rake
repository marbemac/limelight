namespace :limelight_neo4j do

  desc "Migrate data from old limelight structure to new one in neo4j."
  task :migrate_data => :environment do

    # move topics over
    topics = Topic.all
    topics.each do |t|
      node = Neo4j.neo.get_node_index('topics', 'uuid', t.id.to_s)
      unless node
        node = Neo4j.neo.create_node('uuid' => t.id.to_s, 'type' => 'topic', 'name' => t.name, 'slug' => t.slug)
      end
      Neo4j.neo.add_node_to_index('topics', 'uuid', t.id.to_s, node)
      t.save
      print "Loaded #{t.name} topic\n"
    end

    # move users over
    users = User.all
    users.each do |u|
      # add the user node
      node = Neo4j.neo.get_node_index('users', 'uuid', u.id.to_s)
      unless node
        node = Neo4j.neo.create_node('uuid' => u.id.to_s, 'type' => 'user', 'username' => u.username, 'slug' => u.slug)
      end
      Neo4j.neo.add_node_to_index('users', 'uuid', u.id.to_s, node)

      # add following users relationships
      u.following_users.each do |f|
        #Resque.enqueue(Neo4jFollowCreate, u.id.to_s, f.to_s, 'users', 'users')
      end

      # add following topics relationships
      u.following_topics.each do |f|
        #Resque.enqueue(Neo4jFollowCreate, u.id.to_s, f.to_s, 'users', 'topics')
      end

      print "Loaded #{u.username} user\n"
    end

    # move posts over
    posts = Post.all
    posts.each do |p|
      #Resque.enqueue(Neo4jPostCreate, p.id.to_s)
    end
    print "Loaded #{posts.length} posts\n"

  end

end