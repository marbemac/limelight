require "limelight"

class Topic
  include Mongoid::Document
  include Mongoid::Paranoia
  include Mongoid::Timestamps
  include Mongoid::CachedJson
  include Limelight::Acl
  include Limelight::Images
  include ModelUtilitiesHelper

  @type_of_id = "4eb82a1caaf9060120000081"
  @related_to_id = "4f0a51745b1dc3000500016f"
  @limelight_id = '4ec69d9fcddc7f9fe80000b8'
  @limelight_feedback_id = '4ecab6c1cddc7fd77f000106'
  @stop_words = %w(a about above after again against all am an and any are arent as at be because been before being
                  below between both but by cant cannot could couldnt did didnt do does doesnt doing dont down
                  during each few for from further had hadnt has hasnt have havent having he hed hell hes her here
                  heres hers herself him himself his how hows i id ill im ive if in into is isnt it its its itself
                  lets me more most mustnt my myself no nor not of off on once only or other ought our ours
                  ourselves out over own same shant she shed shell shes should shouldnt so some such than that thats
                  the their theirs them themselves then there theres these they theyd theyll theyre theyve this
                  those through to too under until up very was wasnt we wed well were weve were werent what whats
                  when whens where wheres which while who whos whom why whys with wont would wouldnt you youd youll
                  youre youve your yours yourself yourselves)
  class << self; attr_accessor :type_of_id, :related_to_id, :limelight_id, :limelight_feedback_id, :stop_words end

  field :name
  field :url_pretty
  field :slug_pretty
  field :slug
  field :summary
  field :status, :default => 'active'
  field :primary_type
  field :primary_type_id
  field :is_topic_type, :default => false # is this topic a type for other topics?
  field :talking_ids, :default => []
  field :fb_page_id
  field :dbpedia
  field :opencyc
  field :freebase_id
  field :freebase_guid
  field :freebase_mid
  field :freebase_url
  field :freebase_deleted # if we manually deleted freebase info from this topic, can only re-enable by assigning an mid and repopulating
  field :use_freebase_image, :default => false
  field :wikipedia
  field :website
  field :websites_extra, :default => []
  field :neo4j_id, :type => Integer
  field :is_category, :default => false
  field :category_ids, :default => []
  field :post_count, :default => 0

  belongs_to :user, :index => true
  embeds_many :aliases, :as => :has_alias, :class_name => 'TopicAlias'

  validates :user, :presence => true
  validates :name, :presence => true, :length => { :minimum => 2, :maximum => 50 }
  validates :slug_pretty, :uniqueness => { :case_sensitive => false, :message => 'This pretty slug is already in use' }
  validates :slug, :uniqueness => { :case_sensitive => false, :message => 'This slug is already in use' }
  validates :freebase_guid, :uniqueness => { :case_sensitive => false, :allow_blank => true, :message => 'This freebase guid is already in use' }
  validates :freebase_id, :uniqueness => { :case_sensitive => false, :allow_blank => true, :message => 'This freebase id is already in use' }
  validates_each :name do |record, attr, value|
    if Topic.stop_words.include?(value)
      record.errors.add attr, "This topic name is not permitted."
    end
  end

  attr_accessible :name, :summary, :aliases
  attr_accessor :skip_fetch_external

  before_validation :titleize_name, :generate_slug, :on => :create
  before_validation :update_name_alias, :update_url
  before_create :neo4j_create, :init_alias, :fetch_external_data
  after_create :add_to_soulmate
  after_update :update_denorms
  before_destroy :remove_from_soulmate, :disconnect

  index({ :slug => 1 })
  index({ :slug_pretty => 1 })
  index({ :post_count => -1 })
  index({ :primary_type_id => 1 })
  index({ :is_category => 1 })
  index({ :category_ids => 1 })
  index({ :fb_page_id => 1 })
  index({ :freebase_guid => 1 }, { :sparse => true })
  index({ :freebase_id => 1 }, { :sparse => true })
  index({ "aliases.slug" => 1, :primary_type_id => 1 })

  # Return the topic slug instead of its ID
  def to_param
    url_pretty
  end

  def created_at
    id.generation_time
  end

  def title
    name
  end

  def titleize_name
    self.name = name.titleize
  end

  # create a unique slug for this topic
  def generate_slug
    possible = name.parameterize
    found = Topic.where(:slug => possible.parameterize).first
    if found && found.id != id
      count = 0
      while found && found.id != id
        count += 1
        possible = name.parameterize + '-' + count.to_s
        found = Topic.where(:slug => possible.parameterize).first
      end
    end
    self.url_pretty = possible.gsub('-', ' ').titleize.gsub(' ', '')
    self.slug_pretty = possible.parameterize.gsub('-', '')
    self.slug = possible.parameterize
  end

  def fetch_external_data
    Resque.enqueue(TopicFetchExternalData, id.to_s) unless skip_fetch_external
  end

  def freebase
    if freebase_guid && freebase_guid[0] != '#'
      self.freebase_guid = "#" + freebase_guid.split('.').last
      save
    end

    if freebase_id || freebase_guid || freebase_mid
      query = {}
      query[:type] = "/common/topic" unless is_topic_type || is_category
      query[:notable_for] = [] unless is_topic_type || is_category
      query[:id] = freebase_id ? freebase_id : nil
      query[:guid] = !freebase_id && freebase_guid ? freebase_guid : nil
      query[:mid] = !freebase_id && !freebase_guid && freebase_mid ? freebase_mid : nil
      result = Ken.session.mqlread(query)
      if result
        result2 = Ken::Topic.get(result['mid'])
        result.merge!(result2.data.as_json) if result2
      end
      result
    end
  end

  def delete_freebase
    self.freebase_id = nil
    self.freebase_mid = nil
    self.freebase_guid = nil
    self.freebase_url = nil
    self.freebase_deleted = true
    self.use_freebase_image = false
    self.websites_extra = []
  end

  # fetch and try to connect freebase data
  def freebase_repopulate(overwrite_text=false, overwrite_aliases=false, overwrite_primary_type=false, overwrite_image=false)
    return if !freebase_mid && freebase_deleted

    # get or find the freebase object
    freebase_search = nil
    freebase_object = freebase

    unless freebase_object
      search = HTTParty.get("https://www.googleapis.com/freebase/v1/search?lang=en&limit=3&query=#{URI::encode(name)}")
      return unless search && search['result'] && search['result'].first && ((search['result'].first['notable'] && search['result'].first['score'] >= 50) || search['result'].first['score'] >= 800)

      search['result'].each do |s|
        if s['name'].parameterize == name.parameterize && s['score'] >= 50
          freebase_search = s
          break
        end
      end
      # make sure the names match up at least a little bit
      unless !search || freebase_search
        return unless (search['result'].first['name'].parameterize.include?(name.parameterize) && search['result'].first['score'] > 100) || search['result'].first['score'] >= 1500
        freebase_search = search['result'].first
      end

      self.freebase_mid = freebase_search['mid']
      freebase_object = self.freebase
      return unless freebase_object
    end

    existing_topic = Topic.where(:freebase_guid => freebase_object['guid']).first
    return if existing_topic && existing_topic.id != id

    # basics
    self.freebase_id = freebase_object['id']
    self.freebase_guid = freebase_object['guid']
    self.freebase_mid = freebase_object['mid']
    self.freebase_url = freebase_object['url']
    self.summary = freebase_object['description'] unless summary

    # store extra websites
    if freebase_object['webpage']
      freebase_object['webpage'].each do |w|
        if w['text'] == '{name}'
          self.website = w['url']
        elsif ['wikipedia','new york times','crunchbase','imdb'].include?(w['text'].downcase) && !websites_extra.detect{|we| we['name'] == w['text']}
          self.websites_extra << {
                  'name' => w['text'],
                  'url' => w['url']
          }
        end
      end
    end

    # try to connect primary type
    type_connection = TopicConnection.find(Topic.type_of_id)
    if freebase_object['notable_for'] && freebase_object['notable_for'].length > 0 && (overwrite_primary_type || !primary_type_id)
      type_topic = Topic.where(:freebase_id => freebase_object['notable_for'][0]).first

      # if we didn't find the type topic, fetch it from freebase and check the name
      freebase_type_topic = nil
      unless type_topic
        freebase_type_topic = Ken.session.mqlread({ :id => freebase_object['notable_for'][0], :mid => nil, :name => nil })
        if freebase_type_topic
          type_topic = Topic.where("aliases.slug" => freebase_type_topic['name'].parameterize).first
        end
      end

      if type_topic || freebase_type_topic
        new_type = false
        if freebase_type_topic && !type_topic
          type_topic = Topic.new
          type_topic.user_id = User.marc_id
          type_topic.skip_fetch_external = true
          new_type = true
        end

        if freebase_type_topic
          extra = Ken::Topic.get(freebase_type_topic['mid'])
          freebase_type_topic.merge!(extra.data.as_json) if extra
          type_topic.freebase_mid = freebase_type_topic['mid']
          type_topic.freebase_id = freebase_type_topic['id']
          type_topic.freebase_guid = freebase_type_topic['guid']
          type_topic.freebase_url = freebase_type_topic['url']
          type_topic.name = freebase_type_topic['text'] ? freebase_type_topic['text'] : freebase_type_topic['name']
          type_topic.summary = freebase_type_topic['description'] unless type_topic.summary
          new_type = true
        end

        if type_topic.name && !type_topic.name.blank?
          saved = new_type ? type_topic.save : false
          if saved || !new_type

            if primary_type_id
              old_type_topic = Topic.find(primary_type_id)
              TopicConnection.remove(type_connection, self, old_type_topic) if old_type_topic
            end

            set_primary_type(type_topic.id)
            TopicConnection.add(type_connection, self, type_topic, User.marc_id, {:pull => false, :reverse_pull => true})
          end
        end
      end
    end

    # update the image
    if images.length == 0 || overwrite_image
      self.active_image_version = 0
      self.use_freebase_image = true
    end

    # overwrite certain things
    self.name = (freebase_object['name'] ? freebase_object['name'] : freebase_object['text']) if !name || overwrite_text
    self.summary = freebase_object['description']  if !summary || overwrite_text

    if overwrite_aliases && freebase_object['aliases'] && freebase_object['aliases'].length > 0
      update_aliases(freebase_object['aliases'])
    end
  end

  #
  # Aliases
  #

  def init_alias
    self.aliases ||= []
    add_alias(name, false, true)
  end

  def get_alias(name)
    aliases.where(:slug => name.parameterize).first
  end

  def add_alias(new_alias, ooac=false, hidden=false)
    return unless new_alias && !new_alias.blank?

    unless get_alias(new_alias)
      self.aliases << TopicAlias.new(:name => new_alias, :slug => new_alias.parameterize, :hash => new_alias.parameterize.gsub('-', ''), :ooac => ooac, :hidden => hidden)
      Resque.enqueue(SmCreateTopic, id.to_s)
      true
    end
  end

  def remove_alias old_alias
    return unless old_alias && !old_alias.blank?
    self.aliases.where(:name => old_alias).delete
    Resque.enqueue(SmCreateTopic, id.to_s)
  end

  def update_alias(alias_id, name, ooac, hidden=false)
    found = self.aliases.find(alias_id)
    if found
      if ooac == true
        existing = Topic.where('aliases.slug' => name.parameterize).to_a
        if existing.length > 1
          names = []
          existing.each {|t| names << t.name if t.id != id}
          names = names.join(', ')
          return "The '#{names}' topic already have an alias with this name."
        end
      end
      found.name = name unless name.blank?
      found.slug = name.parameterize unless name.blank?
      found.ooac = ooac
      found.hidden = hidden
      Resque.enqueue(SmCreateTopic, id.to_s)
    end
    true
  end

  def update_aliases new_aliases
    self.aliases = []
    init_alias

    new_aliases = new_aliases.split(', ') unless new_aliases.is_a? Array
    new_aliases.each do |new_alias|
      add_alias(new_alias)
    end
  end

  def update_name_alias
    if name_changed?
      if name_was
        remove_alias(name_was.pluralize)
        remove_alias(name_was.singularize)
      end
      add_alias(name.pluralize, false, true)
      add_alias(name.singularize, false, true)
    end
  end

  # END ALIASES

  def update_url
    if url_pretty_changed?
      self.slug_pretty = url_pretty.parameterize.gsub('-', '')
    end
  end

  def also_known_as
    also_known_as = Array.new
    aliases.each do |also|
      if also.slug != name.parameterize && also.slug != name.pluralize.parameterize && also.slug != name.singularize.parameterize && also.slug != short_name
        also_known_as << also.name
      end
    end
    also_known_as
  end

  #
  # SoulMate
  #

  def add_to_soulmate
    Resque.enqueue(SmCreateTopic, id.to_s)
  end

  def remove_from_soulmate
    Resque.enqueue(SmDestroyTopic, id.to_s)
  end

  #
  # Primary Type
  #

  def set_primary_type(primary_id)
    topic = Topic.find(primary_id)
    if topic
      self.primary_type = topic.name
      self.primary_type_id = topic.id
      topic.is_topic_type = true
      topic.save
      Resque.enqueue(SmCreateTopic, id.to_s)
    end
  end

  def unset_primary_type
    self.primary_type = nil
    self.primary_type_id = nil
    Resque.enqueue(SmCreateTopic, id.to_s)
  end

  def neo4j_create
    node = Neo4j.neo.create_node('uuid' => id.to_s, 'type' => 'topic', 'name' => name, 'created_at' => created_at.to_i)
    Neo4j.neo.add_node_to_index('topics', 'uuid', id.to_s, node)
    self.neo4j_id = Neo4j.parse_id(node['self'])
    node
  end

  def neo4j_update
    node = Neo4j.neo.get_node_index('topics', 'uuid', id.to_s)
    Neo4j.neo.set_node_properties(node, {'name' => name})
  end

  def neo4j_node
    Neo4j.neo.get_node_index('topics', 'uuid', id.to_s)
  end

  def disconnect
    # remove mentions of this topic
    PostMedia.where("shares.topic_mention_ids" => id).each do |object|
      shares = object.shares.where("topic_mention_ids" => id)
      shares.each do |share|
        share.remove_topic_mention(self)
      end
      object.save
    end

    # remove from neo4j
    Neo4j.neo.delete_node!(neo4j_node)

    # reset primary types
    Topic.where('primary_type_id' => id).each do |topic|
      topic.unset_primary_type
      topic.save
    end
  end

  # only returns visible aliases
  def visible_aliases
    aliases.select { |a| !a[:hidden] }
  end

  def short_summary
    if summary && !summary.blank?
      summary.split('.')[0,1].join('. ') + '.'
    end
  end

  def all_websites
    response = []
    response << { :name => 'Official', :url => website } if website
    response << { :name => 'Freebase', :url => freebase_url } if freebase_url
    websites_extra.each do |w|
      response << { :name => w[:name], :url => w[:url] }
    end
    response
  end

  def add_category(id)
    unless category_ids.include?(id)
      self.category_ids << id
    end
  end

  ##########
  # JSON
  ##########

  def mixpanel_data(extra=nil)
    {
            "Topic Name" => name,
            "Topic Post Count" => post_count,
            "Topic Created At" => created_at,
            "Topic Primary Type" => primary_type
    }
  end

  json_fields \
    :_id => { :properties => :short, :versions => [ :v1 ] },
    :id => { :definition => :url_pretty, :properties => :short, :versions => [ :v1 ] },
    :slug => { :properties => :short, :versions => [ :v1 ] },
    :url_pretty => { :properties => :short, :versions => [ :v1 ] },
    :url => { :definition => lambda { |instance| "/#{instance.to_param}" }, :properties => :short, :versions => [ :v1 ] },
    :type => { :definition => lambda { |instance| 'Topic' }, :properties => :short, :versions => [ :v1 ] },
    :name => { :properties => :short, :versions => [ :v1 ] },
    :summary => { :definition => :short_summary, :properties => :short, :versions => [ :v1 ] },
    :primary_type => { :properties => :short, :versions => [ :v1 ] },
    :primary_type_id => { :properties => :short, :versions => [ :v1 ] },
    :category_ids => { :properties => :short, :versions => [ :v1 ] },
    :images => { :definition => lambda { |instance| Topic.json_images(instance) }, :properties => :short, :versions => [ :v1 ] },
    :created_at => { :definition => lambda { |instance| instance.created_at.to_i }, :properties => :short, :versions => [ :v1 ] },
    :visible_alias_count => { :definition => lambda { |instance| instance.visible_aliases.length }, :properties => :public, :versions => [ :v1 ]},
    :aliases => { :type => :reference, :properties => :public, :versions => [ :v1 ] },
    :websites => { :definition => :all_websites, :properties => :public, :versions => [ :v1 ] },
    :freebase_url => { :properties => :public, :versions => [ :v1 ] }

  def self.json_images(model)
    {
      :ratio => model.image_ratio,
      :w => model.image_width,
      :h => model.image_height,
      :original => model.image_url(nil, nil, nil, true),
      :fit => {
        :large => model.image_url(:fit, :large),
        :normal => model.image_url(:fit, :normal),
        :small => model.image_url(:fit, :small)
      },
      :square => {
        :large => model.image_url(:square, :large),
        :normal => model.image_url(:square, :normal),
        :small => model.image_url(:square, :small)
      }
    }
  end

  ##########
  # END JSON
  ##########

  # find a topic by slug or id
  def self.find_by_slug_id(id)
    if Moped::BSON::ObjectId.legal?(id)
      Topic.find(id)
    else
      Topic.where(:slug_pretty => id.parameterize).first
    end
  end

  # search or create topics given an array of names
  def self.search_or_create(topic_mention_names, user)
    new_topics = []
    if topic_mention_names.is_a?(Array)
      # See if any of the new topic slugs are already in the DB. Check through topic aliases! Only connect to topics without a type assigned.
      new_topic_mentions = topic_mention_names.map {|name| [name, name.parameterize]}

      topic_slugs = new_topic_mentions.map {|data| data[1]}
      # topics with matching aliases that are NOT already typed and are not categories
      topics = Topic.any_of({"aliases.slug" => {'$in' => topic_slugs}, "primary_type_id" => {"$exists" => false}}, {"aliases.slug" => {'$in' => topic_slugs}, :is_category => true}).to_a

      new_topic_mentions.each do |topic_mention|
        next unless topic_mention[1].length > 2

        found_topic = false
        # Do we already have an *untyped* DB topic for this mention?
        topics.each do |topic|
          if topic.get_alias(topic_mention[1])
            found_topic = topic
          end
        end
        unless found_topic
          # If we did not find the topic, create it and save it if it is valid
          found_topic = user.topics.build({name: topic_mention[0]})
          if found_topic.valid?
            found_topic.save
          else
            found_topic = false
          end
        end

        new_topics << found_topic if found_topic
      end
    end
    new_topics
  end

  # takes a hash of filters to narrow down a topic query
  def self.find_by_params(topics, params)
    unless params[:sort]
      topics = topics.asc(:slug)
    end

    topics = topics.skip(100 * (params[:page].to_i-1)) if params[:page]

    if params[:type]
      if params[:type] == 'category'
        topics = topics.where(:is_category => true)
      end
    end

    key = 'topics'
    key += "-#{params[:type]}" if params[:type]
    key += "-#{params[:page]}" if params[:page]
    first = topics.only(:updated_at).desc('updated_at').first
    return [] unless first
    timestamp = first.updated_at
    key += "-#{timestamp}"

    Rails.cache.fetch(key, :expires_in => 1.day) do
      if params[:sort] && params[:sort] == 'popularity'
        topics = topics.map do |t|
          topic_ids = Neo4j.pull_from_ids(t.neo4j_id).to_a
          shares = PostMedia.where(:topic_ids => {"$in" => topic_ids << t.id})
          {
              :topic => t.as_json(:properties => :public),
              :count => shares.length
          }
        end
        topics.sort_by!{|t| t[:count] * -1}
      else
        topics = topics.map {|t| {:topic => t.as_json(:properties => :public)}}
      end
    end
  end

  # Checks if there is an untyped topic with an alias equal to the name. If so, returns that topic, if not, returns new topic
  def self.find_untyped_or_create(name, user)
    alias_topic = Topic.where("aliases.slug" => name.parameterize, "primary_type_id" => {"$exists" => false}).first
    if alias_topic
      alias_topic
    else
      user.topics.create({name: name})
    end
  end

  # clean and get all word combinations in a string
  def self.combinalities(string)
    return [] unless string && !string.blank?

    # generate the word combinations in the tweet (to find topics based on) and remove short words
    words = (string.split - Topic.stop_words).join(' ').gsub('-', ' ').downcase.gsub("'s", '').gsub(/[^a-z0-9 ]/, '').split.select { |w| w.length > 2 || w.match(/[0-9]/) }.join(' ')
    words = words.split(" ")
    #singular_words = words.map{|w| w.singularize}
    #words = singular_words
    combinaties = []
    i=0
    while i <= words.length-1
      combinaties << words[i].downcase
      unless i == words.length-1
        words[(i+1)..(words.length-1)].each{|volgend_element|
          combinaties<<(combinaties.last.dup<<" #{volgend_element}")
        }
      end
      i+=1
    end
    combinaties
  end

  # use alchemy api and limelight to produce topic suggestions for a given url
  def self.suggestions_by_url(url, title=nil, limit=5)
    suggestions = []

    if title
      combinations = Topic.combinalities(title)
      topics = Topic.where("aliases.slug" => {"$in" => combinations.map{|c| c.parameterize}}).desc(:response_count)
      topics.each do |t|
        suggestions << { :id => t.id.to_s, :name => t.name }
      end
    end

    postData = Net::HTTP.post_form(
            URI.parse("http://access.alchemyapi.com/calls/url/URLGetRankedNamedEntities"),
            {
                    :url => url,
                    :apikey => '1deee8afa82d7ba26ce5c5c7ceda960691f7e1b8',
                    :outputMode => 'json',
                    #:sourceText => 'cleaned',
                    :maxRetrieve => 10
            }
    )

    entities = JSON.parse(postData.body)['entities']

    if entities
      entities.each do |e|
        if e['relevance'].to_f >= 0.60

          # try to find the topic in Limelight
          if e['disambiguated'] && (e['disambiguated']['freebase'] || e['relevance'].to_f >= 0.80)

            topic = false

            if e['disambiguated']['freebase']
              topic = Topic.where(:freebase_guid => e['disambiguated']['freebase'].split('.').last).first

              # didn't find the topic with the freebase guid, check names
              unless topic
                topic = Topic.where("aliases.slug" => e['disambiguated']['name'].parameterize, :primary_type_id => {'$exists' => true}).desc(:response_count).first
                topic.freebase_guid = e['disambiguated']['freebase'].split('.').last if topic
              end
            end

            if topic
              suggestions << { :id => topic.id.to_s, :name => topic.name }
            else
              suggestions << { :id => 0, :name => e['disambiguated']['name'] }
            end
          end
        end
      end
    end

    suggestions.uniq! {|s| s[:name] }
    suggestions[0..limit]
  end

  def self.topics_for_connection
    categories = Topic.where(:is_category => true)
    neo_ids = categories.map{|t| t.neo4j_id}.join(",")
    connected_ids = Neo4j.pull_from_ids(neo_ids)
    where(:_id => {"$nin" => connected_ids}, :is_category => false)
  end

  protected

  #TODO: check that soulmate gets updated if this topic is a type for another topic
  def update_denorms
    soulmate = nil
    primary_type_updates = {}

    if name_changed? || slug_changed? || url_pretty_changed?
      soulmate = true

      if name_changed?
        primary_type_updates["primary_type"] = name
      end
    end

    unless primary_type_updates.empty?
      Topic.where("primary_type_id" => id).each do |topic|
        unless topic.id == id
          topic.set_primary_type(id)
          topic.save
        end
      end
    end

    if soulmate
      neo4j_update
      Resque.enqueue(SmCreateTopic, id.to_s)
    end
  end
end
