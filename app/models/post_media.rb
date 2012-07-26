require "limelight"

class PostMedia
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::CachedJson
  include Limelight::Acl
  include Limelight::Images
  include ModelUtilitiesHelper

  field :title
  field :description # if a link, the pulled description from the url
  field :ll_score, :default => 0
  field :neo4j_id, :type => Integer
  field :status, :default => 'active'
  field :pending_images

  embeds_many :sources, :as => :has_source, :class_name => 'SourceSnippet'
  embeds_many :shares, :class_name => 'PostShare'

  belongs_to :user, :index => true
  has_and_belongs_to_many :topics, :inverse_of => nil, :index => true

  validate :title_length, :unique_source
  validates :description, :length => {:maximum => 1500}

  attr_accessible :title, :source_name, :source_url, :source_video_id, :source_title, :source_content, :embed_html, :description, :pending_images
  attr_accessor :source_name, :source_url, :source_video_id, :source_title, :source_content

  scope :active, where(:status => 'active')
  scope :pending, where(:status => 'pending')

  before_validation :set_source_snippet
  before_create :neo4j_create, :current_user_own
  after_create :process_images
  after_save :update_shares_topics
  before_destroy :disconnect

  index({ "shares.user_id" => 1, "shares.created_at" => -1, "shares.topic_mention_ids" => 1 })
  index({ "shares.user_id" => 1, "shares.updated_at" => -1, "shares.topic_mention_ids" => 1 })
  index({ :topic_ids => 1, :created_at => -1 })
  index({ :topic_ids => 1, :updated_at => -1 })
  index({ :topic_ids => 1, :score => -1 })

  def to_param
    id.to_s
  end

  def name
    title
  end

  # short version of the contnet "foo bar foo bar..." used in notifications etc.
  def short_name
    return '' if title.nil? || title.blank?

    short = title[0..30]
    if title.length > 30
      short += '...'
    end
    short
  end

  def og_type
    og_namespace + ":post"
  end

  def set_source_snippet
    if @source_url && !@source_url.blank?
      source = SourceSnippet.new
      source.name = @source_name
      source.url = @source_url
      source.video_id = @source_video_id unless @source_video_id.blank?

      if @source_name && !@source_name.blank?
        topic = Topic.where(:slug => @source_name.parameterize).first
        unless topic
          topic = user.topics.create(:name => @source_name)
        end
        source.id = topic.id
      end

      add_source(source)
    end
  end

  def add_source(source)
    unless sources.where(:url => source.url).first
      self.sources << source
    end
  end

  # if required, checks that the given post URL is valid
  def has_valid_url
    if sources.length == 0
      errors.add(:url, "Source is required")
    end
    if sources.length > 0 && (sources[0].url.length < 3 || sources[0].url.length > 200)
      errors.add(:url, "Source URL must be between 3 and 200 characters long")
    end
  end

  def title_length
    if title && title.length > 125
      errors.add(:title, "Title cannot be more than 125 characters long")
    end
  end

  def unique_source
    if sources.length > 0 && !sources.first.url.blank? && !persisted?
      if PostMedia.where('sources.url' => sources.first.url).first
        errors.add('Link', "Source has already been added to Limelight")
      end
    end
  end

  def primary_source
    sources.first
  end

  def topic_count
    topic_ids.length
  end

  def neo4j_create
    node = Neo4j.neo.create_node('uuid' => id.to_s, 'type' => 'post_media', 'subtype' => self.class.name, 'created_at' => created_at.to_i)
    Neo4j.neo.add_node_to_index('post_media', 'uuid', id.to_s, node)
    self.neo4j_id = Neo4j.parse_id(node['self'])
    node
  end

  # SHARES
  def add_share(user_id, content, topic_ids=[], topic_names=[], from_bookmarklet=false)
    existing = shares.where(:user_id => user_id).first
    return existing if existing

    share = PostShare.new(:content => content, :topic_mention_ids => topic_ids, :topic_mention_names => topic_names, :from_bookmarklet => from_bookmarklet)
    share.user_id = user_id

    if share.valid?

      self.shares << share
      share.set_mentions

      share.topic_mention_ids.each do |t|
        self.topic_ids << t
      end

      self.topic_ids.uniq!
    end

    share
  end

  def delete_share(user_id)
    share = get_share(user_id)
    if share
      share.topic_mentions.each do |t|
        Neo4j.update_talk_count(share.user, t, -1, nil, nil, id)
      end
      self.shares.delete(share)
      self.ll_score -= 1
      reset_topic_ids
    end
  end

  def get_share(user_id)
    shares.where(:user_id => user_id).first
  end

  # sets all shares status to active
  # sets all their topic_ids to the first two topic ids on this post if found
  def publish_shares
    self.shares.where(:status => 'publishing').each do |share|
      share.status = 'active'
      share.expire_cached_json
    end
  end
  # END SHARES

  # goes through all shares and re-calculates the topic_ids that should be on this post
  def reset_topic_ids
    topic_ids = []
    shares.each do |s|
      topic_ids += s.topic_mention_ids
    end
    self.topic_ids = topic_ids.uniq
  end

  def current_user_own
    grant_owner(user.id)
  end

  def disconnect
    # remove from neo4j
    node = Neo4j.neo.get_node_index('post_media', 'uuid', id.to_s)
    Neo4j.neo.delete_node!(node)
    Topic.where(:id => {"$in" => topic_ids}).inc(:post_count, -1)
  end

  def update_shares_topics
    if topic_ids_was != topic_ids
      removed = topic_ids_was ? topic_ids_was - topic_ids : []
      added = topic_ids_was ? topic_ids - topic_ids_was : topic_ids

      return if removed.length == 0 && added.length == 0

      # if this post has new topics and didn't have any before, add them to pending shares
      if !topic_ids_was || topic_ids_was.length == 0
        target_shares = self.shares.where(:status => 'pending')
        target_topics = Topic.where(:_id => {"$in" => topic_ids.first(2)})
        target_shares.each do |s|
          target_topics.each do |t|
            s.add_topic_mention(t)
          end
        end
      end

      # update post counts on topics
      Topic.where(:id => {"$in" => removed}).inc(:post_count, -1)
      Topic.where(:id => {"$in" => added}).inc(:post_count, 1)
    end
  end

  def publish
    self.created_at = Time.now
    self.status = 'active'
  end

  ##########
  # JSON
  ##########

  def mixpanel_data(extra=nil)
    {
            "Post Type" => _type,
            "Post Shares" => ll_score,
            "Post Created At" => created_at,
    }
  end

  json_fields \
    :id => { :definition => :_id, :properties => :short, :versions => [ :v1 ] },
    :type => { :definition => :_type, :properties => :short, :versions => [ :v1 ] },
    :title => { :properties => :short, :versions => [ :v1 ] },
    :description => { :properties => :short, :versions => [ :v1 ] },
    :topic_count => { :properties => :short, :versions => [ :v1 ] },
    :share_count => { :definition => :ll_score, :properties => :short, :versions => [ :v1 ] },
    :status => { :properties => :short, :versions => [ :v1 ] },
    :created_at => { :definition => lambda { |instance| instance.created_at.to_i }, :properties => :short, :versions => [ :v1 ] },
    :video => { :definition => lambda { |instance| instance.json_video }, :properties => :short, :versions => [ :v1 ] },
    :video_autoplay => { :definition => lambda { |instance| instance.json_video(true) }, :properties => :short, :versions => [ :v1 ] },
    :images => { :definition => lambda { |instance| instance.status == "pending" ? instance.pending_images : instance.json_images }, :properties => :short, :versions => [ :v1 ] },
    :shares => { :type => :reference, :properties => :short, :versions => [ :v1 ] },
    :primary_source => { :type => :reference, :definition => :primary_source, :properties => :short, :versions => [ :v1 ] },
    :topic_mentions => { :type => :reference, :definition => :topics, :properties => :short, :versions => [ :v1 ] }

  def json_video(autoplay=nil)
    unless _type != 'Video' || embed_html.blank?
      video_embed(sources[0], 680, 480, nil, nil, embed_html, autoplay)
    end
  end

  def json_images
    if images.length > 0 || !remote_image_url.blank?
      {
        :ratio => image_ratio,
        :w => image_width,
        :h => image_height,
        :original => image_url(nil, nil, nil, true),
        :fit => {
            :large => image_url(:fit, :large),
            :normal => image_url(:fit, :normal),
            :small => image_url(:fit, :small)
        },
        :square => {
            :large => image_url(:square, :large),
            :normal => image_url(:square, :normal),
            :small => image_url(:square, :small)
        }
      }
    end
  end

  ##########
  # END JSON
  ##########

  # find a topic by slug or id
  def self.find_by_slug_id(id)
    if Moped::BSON::ObjectId.legal?(id)
      Topic.find(id)
    else
      Topic.where(:slug => id.parameterize).first
    end
  end

  def self.create_pending(user, url, comment, created_at=Time.now, medium=nil)
    # Use fetch_url to grab the url and find any existing posts
    response = fetch_url(url)
    return nil if response.nil?
    # If there's already a post
    if response[:existing]
      post = response[:existing]
    # Otherwise create a new post
    else
      response[:type] = response[:type] && ['Link','Picture','Video'].include?(response[:type]) ? response[:type] : 'Link'
      params = {:source_url => response[:url],
                :source_name => response[:provider_name],
                :embed_html => response[:video],
                :title => response[:title],
                :type => response[:type],
                :description => response[:description],
                :pending_images => response[:images]
      }
      post = Kernel.const_get(response[:type]).new(params)
      post.user_id = user.id
      post.status = "pending"
      post.created_at = created_at
    end

    if post && !post.get_share(user.id)

      share = post.add_share(user.id, comment)
      share.status = "pending"
      share.created_at = created_at
      share.add_medium(medium) if medium

      if post.valid?
        post.save
      else
        nil
      end
    else
      nil
    end
  end

  def self.create_pending_from_tweet(user, tweet)
    # Grab first url from tweet if it exists
    if tweet.urls.first
      # Remove urls from text
      comment = tweet.text
      tweet.urls.each do |u|
        comment.slice!(u.url)
      end
      url = tweet.urls.first.expanded_url
      medium = {:source => "Twitter", :id => tweet.id.to_i, :url => "https://twitter.com/#{user.twitter_handle}/statuses/#{tweet.id.to_i}"}

      create_pending(user, url, comment, tweet.created_at, medium)
    end
  end

  # Accepts:
  # topic_id
  # user_id
  # status
  # sort (popularity, created_at)
  # page
  def self.find_by_params(params)
    if params[:user_id]
      user = User.find_by_slug_id(params[:user_id])

      if params[:topic_id]
        topic = Topic.find_by_slug_id(params[:topic_id])
        topic_ids = Neo4j.pull_from_ids(topic.neo4j_id).to_a
        @posts = PostMedia.where("shares.user_id" => user.id, "shares.0.topic_mention_ids" => {"$in" => topic_ids << topic.id})
      else
        if signed_in? && (user.id == current_user.id || current_user.role?("admin")) && params[:status] == 'pending'
          @posts = PostMedia.unscoped.where("shares.user_id" => user.id, "shares.0.status" => 'pending')
        else
          @posts = PostMedia.where("shares.user_id" => user.id, "shares.0.status" => "active")
        end
      end
    elsif params[:topic_id]
      topic = Topic.find_by_slug_id(params[:topic_id])
      topic_ids = topic ? Neo4j.pull_from_ids(topic.neo4j_id).to_a << topic.id : []
      @posts = PostMedia.where(:topic_ids => {"$in" => topic_ids})
    else
      if params[:status] && params[:status] == 'pending'
        @posts = PostMedia.unscoped.any_of({:status => 'pending'}, {"shares.status" => 'pending'}).desc("_id")
      else
        @posts = PostMedia.scoped
      end
    end

    key = 'posts'
    key += "-#{params[:user_id]}" if params[:user_id]
    key += "-#{params[:topic_id]}" if params[:topic_id]
    key += "-#{params[:status]}" if params[:status]
    timestamp = @posts.only(:updated_at).desc('updated_at').first.updated_at
    key += "-#{timestamp}"

    # caching
    data = Rails.cache.fetch(key, :expires_in => 1.day) do
      if params[:sort] && params[:sort] == 'popularity'
        @posts = @posts.desc("score")
      else
        if params[:user_id] && params[:topic_id]
          @posts = @posts.desc("shares.0.created_at")
        else
          @posts = @posts.desc("created_at")
        end
      end

      @posts = @posts.skip(20*(params[:page].to_i-1)) if params[:page]

      @posts.limit(20).map do |p|
        response = p.to_json(:properties => :public)
        if params[:user_id]
          response = Yajl::Parser.parse(response)
          response['share'] = p.get_share(user.id)
          response['shares'] = p.shares.where('user_id' => user.id).to_a
          response
        elsif params[:status] && params[:status] == 'pending'
          response = Yajl::Parser.parse(response)
          response['shares'] = p.shares.where('status' => 'pending').to_a
          response
        else
          Yajl::Parser.parse(response)
        end
      end
    end

    data
  end

end