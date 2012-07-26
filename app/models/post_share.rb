class PostShare
  include Mongoid::Document
  include Mongoid::CachedJson
  include Limelight::Mentions

  field :content
  field :status, :default => 'active'
  field :mediums, :default => []
  field :created_at, :default => Time.now

  attr_accessible :content, :mediums

  belongs_to :user
  embedded_in :post_media

  after_create :update_user_share, :neo4j_create
  before_save :check_status

  def update_user_share
    if status == "active"
      user.share_count += 1
      user.save
    end
  end

  def neo4j_create
    Resque.enqueue(Neo4jShareCreate, _parent.id.to_s, user_id.to_s)
  end

  def add_medium(medium)
    self.mediums << medium
  end

  # if the status changed from pending to active, push it out to feeds
  def check_status
    if !status_was || status_was != status
      if status == 'active'
        _parent.ll_score += 1
      end
    end
  end

  ##########
  # JSON
  ##########

  def mixpanel_data(extra=nil)
    {}
  end

  def mediums_json
    mediums.map do |m|
      {
          # need to return the id as a string, because javascript doesn't like huge ints returned by some places
          :id => m['id'].to_s,
          :source => m['source'],
          :url => m['url']
      }
    end
  end

  json_fields \
    :id => { :definition => :_id, :properties => :short, :versions => [ :v1 ] },
    :status => { :properties => :short, :versions => [ :v1 ] },
    :content => { :properties => :short, :versions => [ :v1 ] },
    :mediums => { :properties => :short, :definition => :mediums_json, :versions => [ :v1 ] },
    :created_at => { :definition => :created_at, :properties => :short, :versions => [ :v1 ] },
    :user => { :type => :reference, :properties => :short, :versions => [ :v1 ] },
    :topic_mentions => { :type => :reference, :properties => :short, :versions => [ :v1 ] }

end